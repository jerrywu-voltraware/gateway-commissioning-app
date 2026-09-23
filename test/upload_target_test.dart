import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';

const _lan = MqttTarget.local('192.168.1.50');

/// Simulated gateway with injectable faults around set_mqtt_target.
class TargetGateway extends DemoSystem {
  int failConnects = 0;
  int notReadyReplies = 0;
  bool loseAck = false;
  bool ignoreChange = false;
  String? failCode;
  Completer<void>? connectGate;
  final commands = <String>[];
  final paths = <String>[];

  @override
  Future<void> connect(GatewayPeer peer) async {
    await connectGate?.future;
    if (failConnects > 0) {
      failConnects--;
      connects++;
      throw StateError('GATT 133');
    }
    await super.connect(peer);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add(op);
    if (op == 'get_net_status' && !rebooting && notReadyReplies > 0) {
      notReadyReplies--;
      throw const GatewayFailure.gateway('not_ready');
    }
    if (op == 'set_mqtt_target') {
      if (failCode != null) throw GatewayFailure.gateway(failCode!);
      if (ignoreChange) {
        final saved = Map.of(config);
        final ack = await super.command(op, params);
        config
          ..clear()
          ..addAll(saved);
        return ack;
      }
      final ack = await super.command(op, params);
      if (loseAck) throw const GatewayFailure('disconnected');
      return ack;
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    paths.add('$method $path');
    return super.request(method, path, body);
  }
}

Future<(ProviderContainer, CommissioningController)> _connected(
  DemoSystem fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare('http://192.168.1.50:18000', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  expect(container.read(commissionProvider).step, 2);
  return (container, c);
}

Future<(ProviderContainer, CommissioningController)> _atVerify(
  TargetGateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare('http://192.168.1.50:18000', '');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'test', 'test-password');
  await c.discover();
  await c.configurePtus();
  expect(container.read(commissionProvider).step, 6);
  return (container, c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsing', () {
    test('get_config / get_net_status fields', () {
      final production = parseMqttTarget({
        'fw_version': '1.7.3',
        'mqtt_target': 'production',
        'mqtt_host': '46.250.255.172',
        'mqtt_port': 8883,
      })!;
      expect(production.isLocal, isFalse);
      expect(production.label, '正式站');
      expect(production.host, '46.250.255.172');
      final local = parseMqttTarget({
        'wifi_state': 'got_ip',
        'mqtt_connected': true,
        'mqtt_target': 'local',
        'mqtt_host': '192.168.1.187',
        'mqtt_port': 8884,
      })!;
      expect(local.label, '本地 192.168.1.187:8884');
      expect(local.sameAs(const MqttTarget.local('192.168.1.187')), isFalse);
      expect(
        local.sameAs(const MqttTarget.local('192.168.1.187', port: 8884)),
        isTrue,
      );
      expect(
        production.sameAs(const MqttTarget.production()),
        isTrue,
        reason: 'production matches whatever broker host is compiled in',
      );
    });
    test('missing fields mean legacy firmware', () {
      final legacy = {'fw_version': '1.7.2', 'site_id': 1};
      expect(reportsMqttTarget(legacy), isFalse);
      expect(parseMqttTarget(legacy), isNull);
      final odd = {'mqtt_target': 'staging'};
      expect(reportsMqttTarget(odd), isTrue);
      expect(parseMqttTarget(odd), isNull);
      expect(
        legacyTargetText('1.7.2'),
        '此 Gateway 韌體（版本 1.7.2）不支援切換上傳目標，資料固定上傳正式站；需更新至 1.7.3 以上。',
      );
      expect(legacyTargetText(null), contains('版本 未知'));
    });
    test('set_mqtt_target ack result is a JSON string', () {
      const raw =
          '{"mqtt_target":"local","mqtt_host":"192.168.1.187",'
          '"mqtt_port":8883,"changed":true,"reboot_in_ms":1500}';
      for (final payload in [
        raw,
        {'message': raw},
        jsonDecode(raw) as Map<String, dynamic>,
      ]) {
        final ack = parseSetTargetAck(payload)!;
        expect(ack.changed, isTrue);
        expect(ack.rebootInMs, 1500);
        expect(
          ack.target.sameAs(const MqttTarget.local('192.168.1.187')),
          isTrue,
        );
      }
      final same = parseSetTargetAck(
        '{"mqtt_target":"production","mqtt_host":"46.250.255.172",'
        '"mqtt_port":8883,"changed":false,"reboot_in_ms":0}',
      )!;
      expect(same.changed, isFalse);
      expect(same.target.isLocal, isFalse);
      expect(parseSetTargetAck({'message': 'not json'}), isNull);
      expect(parseSetTargetAck({'mqtt_target': 'local'}), isNull);
    });
    test('request params follow the contract', () {
      expect(const MqttTarget.production().params, {'target': 'production'});
      expect(_lan.params, {
        'target': 'local',
        'host': '192.168.1.50',
        'port': 8883,
      });
      expect(sensitiveOps, contains('set_mqtt_target'));
    });
  });

  group('environment to target', () {
    test('private IPv4 literal matches the firmware rule', () {
      for (final ok in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.0.12',
        '192.168.1.187',
      ]) {
        expect(isPrivateIpv4Literal(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '8.8.8.8',
        '172.15.0.1',
        '172.32.0.1',
        '127.0.0.1',
        '192.168.01.1',
        '192.168.1.256',
        '192.168.1',
        ' 192.168.1.1',
        '192.168.1.1:8883',
        'mybox.local',
        'localhost',
        '',
      ]) {
        expect(isPrivateIpv4Literal(bad), isFalse, reason: bad);
      }
    });
    test('正式站 always means production', () {
      final app = desiredUploadTarget('production', 'https://anything.example');
      expect(app.target!.isLocal, isFalse);
      expect(app.error, isNull);
    });
    test('本地測試站 uses the host of the configured URL, port 8883', () {
      final app = desiredUploadTarget('local', 'http://192.168.0.12:18000');
      expect(app.target!.label, '本地 192.168.0.12:8883');
      expect(app.target!.params['port'], 8883);
      expect(
        desiredUploadTarget('local', ' http://10.1.2.3:18000/ ').target!.host,
        '10.1.2.3',
      );
    });
    test('本地測試站 rejects hostnames, public and loopback IPs', () {
      for (final url in [
        'http://mypc.local:18000',
        'http://8.8.8.8:18000',
        'http://127.0.0.1:18000',
        'http://[::1]:18000',
      ]) {
        final app = desiredUploadTarget('local', url);
        expect(app.target, isNull, reason: url);
        expect(app.error, contains('不是區網私有 IPv4 位址'), reason: url);
        expect(app.wantsLocal, isTrue);
      }
      expect(desiredUploadTarget('local', '').error, contains('尚未輸入本地測試站網址'));
      expect(
        desiredUploadTarget('local', '192.168.1.1:18000').error,
        contains('無法解析主機位址'),
      );
    });
    test('其他網址 maps private IP, production domain, else unknown', () {
      expect(
        desiredUploadTarget('custom', 'http://172.20.0.5:18000').target!.label,
        '本地 172.20.0.5:8883',
      );
      expect(
        desiredUploadTarget(
          'custom',
          'https://Dashboard.Voltraware.com',
        ).target!.isLocal,
        isFalse,
      );
      for (final url in [
        'https://example.invalid',
        'http://8.8.8.8:18000',
        'http://mypc.local:18000',
      ]) {
        final app = desiredUploadTarget('custom', url);
        expect(app.target, isNull, reason: url);
        expect(app.error, isNull, reason: url);
      }
    });
  });

  group('fail codes', () {
    const codes = [
      'invalid_params',
      'invalid_target',
      'invalid_host',
      'invalid_port',
      'ota_in_progress',
      'nvs_write_failed',
      'ble_only',
      'otp_required',
      'otp_invalid',
      'otp_reused',
      'otp_locked',
      'time_not_synced',
      'not_ready',
      'busy',
      'invalid req_id',
    ];
    test('every firmware code has its own Chinese message', () {
      final generic = uploadTargetFailureText(
        'something_new',
      ).split('\n').first;
      final seen = <String>{};
      for (final code in codes) {
        final text = GatewayFailure.uploadTarget(code).message;
        expect(text, uploadTargetFailureText(code));
        expect(text, contains('[set_mqtt_target · $code]'));
        final first = text.split('\n').first;
        expect(first, isNot(generic), reason: code);
        expect(first, matches(RegExp(r'[一-鿿]')), reason: code);
        expect(seen.add(first), isTrue, reason: 'duplicate text for $code');
      }
      expect(uploadTargetFailureText('ota_in_progress'), contains('OTA'));
      expect(uploadTargetFailureText('invalid_host'), contains('私有 IPv4'));
      expect(uploadTargetFailureText('otp_locked'), contains('鎖定'));
    });
  });

  group('switching', () {
    test(
      'changed:true reboots, reconnects and reads the target back',
      () async {
        final fake = TargetGateway();
        final (container, c) = await _connected(fake);
        addTearDown(container.dispose);
        final before = container.read(commissionProvider);
        expect(parseMqttTarget(before.config)!.isLocal, isFalse);
        expect(fake.connects, 1);

        await c.switchUploadTarget(_lan);

        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.busy, isFalse);
        expect(fake.targetRequests.single, {
          'target': 'local',
          'host': '192.168.1.50',
          'port': 8883,
        });
        expect(fake.connects, 2, reason: 'reconnected to the same gateway');
        expect(
          fake.commands.sublist(fake.commands.indexOf('set_mqtt_target')),
          containsAllInOrder(['set_mqtt_target', 'ping', 'get_net_status']),
        );
        expect(parseMqttTarget(s.config)!.sameAs(_lan), isTrue);
        expect(s.config['mqtt_connected'], isTrue);
        expect(s.uploadNotice, contains('已切換到本地 192.168.1.50:8883'));
        expect(s.uploadNotice, contains('MQTT 已連線'));
        // Commissioning state is untouched.
        expect(s.step, before.step);
        expect(s.peer, before.peer);
        expect(s.message, before.message);
        expect(s.config['gateway_uid'], before.config['gateway_uid']);
      },
    );
    test('changed:false only refreshes, no reboot or reconnect', () async {
      final fake = TargetGateway();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.switchUploadTarget(const MqttTarget.production());
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.connects, 1);
      expect(fake.commands.last, 'get_net_status');
      expect(s.uploadNotice, startsWith('上傳目標未變更：Gateway 已是正式站，未重新開機。'));
    });
    test('reconnect retries until the rebooted gateway answers', () async {
      final fake = TargetGateway();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      fake.failConnects = 2;
      fake.notReadyReplies = 2;
      await c.switchUploadTarget(_lan);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.connects, 4);
      expect(
        fake.commands,
        contains('get_config'),
        reason: 'not_ready fallback',
      );
      expect(parseMqttTarget(s.config)!.sameAs(_lan), isTrue);
    });
    test('reconnect gives up with a clear message', () async {
      final fake = TargetGateway();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      fake.failConnects = 1000;
      await c.switchUploadTarget(_lan);
      final s = container.read(commissionProvider);
      expect(s.error, contains('45 秒內未能重新連上藍牙'));
      expect(s.busy, isFalse);
      expect(s.step, 2);
    });
    test('lost ACK is resolved by reconnecting and reading back', () async {
      final fake = TargetGateway()..loseAck = true;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.switchUploadTarget(_lan);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(parseMqttTarget(s.config)!.sameAs(_lan), isTrue);
    });
    test('read-back mismatch is reported', () async {
      final fake = TargetGateway()..ignoreChange = true;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.switchUploadTarget(_lan);
      expect(
        container.read(commissionProvider).error,
        contains('回報的上傳目標是正式站，不是要求的本地 192.168.1.50:8883'),
      );
    });
    for (final code in ['ota_in_progress', 'otp_invalid', 'invalid_host']) {
      test('fail ack $code shows its message and keeps state', () async {
        final fake = TargetGateway()..failCode = code;
        final (container, c) = await _connected(fake);
        addTearDown(container.dispose);
        await c.switchUploadTarget(_lan);
        final s = container.read(commissionProvider);
        expect(s.error, uploadTargetFailureText(code));
        expect(s.step, 2);
        expect(fake.connects, 1, reason: 'no reboot on failure');
      });
    }
    test('OTP-enabled gateway is blocked like set_wifi', () async {
      final fake = TargetGateway();
      fake.config['otp_enabled'] = true;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.switchUploadTarget(_lan);
      expect(
        container.read(commissionProvider).error,
        const GatewayFailure('otp_enabled').message,
      );
      expect(fake.targetRequests, isEmpty);
    });
    test('legacy firmware cannot switch', () async {
      final fake = TargetGateway();
      fake.config
        ..['fw_version'] = '1.7.2'
        ..remove('mqtt_target')
        ..remove('mqtt_host')
        ..remove('mqtt_port');
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.switchUploadTarget(_lan);
      expect(
        container.read(commissionProvider).error,
        legacyTargetText('1.7.2'),
      );
      expect(fake.commands, isNot(contains('set_mqtt_target')));
    });
    test('simulated gateway validates like the firmware', () async {
      final fake = DemoSystem();
      for (final (params, code) in [
        ({'target': 'LOCAL'}, 'invalid_target'),
        ({'target': 'local', 'host': 'mybox.local'}, 'invalid_host'),
        ({'target': 'local', 'host': '8.8.8.8'}, 'invalid_host'),
        ({'target': 'local', 'host': '192.168.1.5', 'port': 0}, 'invalid_port'),
        (
          {'target': 'local', 'host': '192.168.1.5', 'port': '8883'},
          'invalid_port',
        ),
      ]) {
        await expectLater(
          fake.command('set_mqtt_target', params),
          throwsA(isA<GatewayFailure>().having((e) => e.code, 'code', code)),
        );
      }
    });
    test('cancel during reconnect leaves no half-written state', () async {
      final fake = TargetGateway();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      fake.connectGate = Completer<void>();
      final operation = c.switchUploadTarget(_lan);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(commissionProvider).busy, isTrue);
      await c.cancel();
      fake.connectGate!.complete();
      await operation;
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.busy, isFalse);
      expect(s.uploadNotice, isEmpty);
    });
  });

  group('step 7 preflight', () {
    test('known mismatch fails fast without touching the backend', () async {
      final fake = TargetGateway();
      final (container, c) = await _atVerify(fake);
      addTearDown(container.dispose);
      fake.paths.clear();
      final clock = Stopwatch()..start();
      await c.verify('http://192.168.1.50:18000', '', environment: 'local');
      final s = container.read(commissionProvider);
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      expect(
        s.error,
        startsWith('Gateway 目前上傳到正式站，但 APP 連線的是本地 192.168.1.50:8883'),
      );
      expect(s.error, contains('切換到本地 192.168.1.50:8883'));
      expect(fake.paths, isEmpty, reason: 'no bot-monitor PATCH');
      expect(s.step, 6);
      expect(s.verified, isFalse);

      // After switching the gateway, the same verification passes.
      await c.switchUploadTarget(_lan);
      expect(container.read(commissionProvider).error, isNull);
      await c.verify('http://192.168.1.50:18000', '', environment: 'local');
      expect(container.read(commissionProvider).error, isNull);
      expect(container.read(commissionProvider).step, 7);
    });
    test('production APP with a local gateway also fails fast', () async {
      final fake = TargetGateway();
      fake.config.addAll({'mqtt_target': 'local', 'mqtt_host': '192.168.1.50'});
      final (container, c) = await _atVerify(fake);
      addTearDown(container.dispose);
      await c.verify(productionApiBase, '', environment: 'production');
      expect(
        container.read(commissionProvider).error,
        startsWith('Gateway 目前上傳到本地 192.168.1.50:8883，但 APP 連線的是正式站'),
      );
    });
    test('unknown target (legacy firmware) proceeds as before', () async {
      final fake = TargetGateway();
      fake.config
        ..['fw_version'] = '1.7.2'
        ..remove('mqtt_target')
        ..remove('mqtt_host')
        ..remove('mqtt_port');
      final (container, c) = await _atVerify(fake);
      addTearDown(container.dispose);
      await c.verify('http://192.168.1.50:18000', '', environment: 'local');
      expect(container.read(commissionProvider).error, isNull);
      expect(container.read(commissionProvider).step, 7);
    });
  });
}
