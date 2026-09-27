import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_net.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';

const _lan = MqttTarget.local('192.168.1.50');
const _local = BackendEnvState(
  environment: BackendEnv.local,
  localHost: '192.168.1.50',
  loaded: true,
);
const _production = BackendEnvState(loaded: true);

/// The incident text for a station whose home Wi-Fi is not at the office.
final _missingHomeWifi = wifiProblemText('Xiaomi_WU');

/// Fast polling: 20 ms rounds, upload confirmed within 200 ms, Wi-Fi grace
/// 100 ms.
const _fast = UploadWatchTiming(
  interval: Duration(milliseconds: 20),
  cap: Duration(seconds: 2),
  slowAfter: Duration(milliseconds: 100),
  confirmAfter: Duration(milliseconds: 200),
  wifiGrace: Duration(milliseconds: 100),
);

class WifiGateway extends DemoSystem {
  WifiGateway();

  /// Site 80 / gateway 1 with three numbered PTUs, set up for the home
  /// Wi-Fi 「Xiaomi_WU」 (the field incident).
  WifiGateway.station() {
    config.addAll({
      'fleet_joined': true,
      'site_id': 80,
      'gateway_id': 1,
      'wifi_ssid': 'Xiaomi_WU',
    });
    for (final (i, device) in devices.indexed) {
      device
        ..['device_number'] = i + 1
        ..['connected'] = true
        ..['notify_enabled'] = true;
    }
  }

  final commands = <String>[];
  final logins = <(String, String)>[];
  bool loseWifiOnSet = false;
  bool rejectTarget = false;
  bool netNotReadyAfterReboot = false;

  @override
  Future<void> login(String base, String password) async =>
      logins.add((base, password));

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    commands.add(op);
    if (op == 'get_net_status' && netNotReadyAfterReboot && connects > 1) {
      throw const GatewayFailure.gateway('not_ready');
    }
    if (op == 'set_mqtt_target' && rejectTarget) {
      throw const GatewayFailure.gateway('invalid_target');
    }
    if (op == 'set_wifi' && loseWifiOnSet) {
      simulateWifi('disconnected');
      unreachableSsids.add(params['ssid'] as String);
    }
    return super.command(op, params);
  }

  int count(String op) => commands.where((c) => c == op).length;
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200, version: '1');
}

Future<(ProviderContainer, CommissioningController)> _connected(
  DemoSystem fake, {
  bool offline = true,
  String base = productionApiBase,
  UploadWatchTiming timing = _fast,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      uploadWatchTimingProvider.overrideWithValue(timing),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare(base, 'pw', offline: offline);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

Future<void> _sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

NetworkCheck _check(ProviderContainer container, [BackendEnvState? env]) =>
    networkCheck(
      state: container.read(commissionProvider),
      env: env ?? _production,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('network check gate', () {
    test(
      'reboot discards old uptime when network readback is not ready',
      () async {
        final fake = WifiGateway.station()
          ..simulateWifi('disconnected')
          ..netNotReadyAfterReboot = true;
        final (container, c) = await _connected(fake);
        addTearDown(container.dispose);
        expect(_check(container).wifiVerdict, WifiVerdict.failed);
        await c.switchUploadTarget(_lan, waitUpload: false);
        final state = container.read(commissionProvider);
        expect(state.error, isNull);
        expect(state.net, isEmpty);
        expect(state.wifi, WifiVerdict.unknown);
        expect(state.networkReady, isFalse);
        expect(state.uploadWatch, UploadWatch.polling);
      },
    );

    test('1.7.2 polls Wi-Fi without switchable MQTT target fields', () async {
      final fake = WifiGateway.station()..simulateWifi('connecting');
      fake.config
        ..['fw_version'] = '1.7.2'
        ..remove('mqtt_target')
        ..remove('mqtt_host')
        ..remove('mqtt_port');
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      expect(_check(container).wifiVerdict, WifiVerdict.connecting);
      await _sleep(80);
      expect(_check(container).ready, isTrue);
      expect(fake.count('get_net_status'), greaterThan(1));
    });

    test('failed Wi-Fi change replaces previous successful status', () async {
      final fake = WifiGateway.station()..loseWifiOnSet = true;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      expect(_check(container).ready, isTrue);
      await c.startWifiFix();
      await c.configureWifi(80, 1, 'Missing-2G', 'password123');
      expect(container.read(commissionProvider).error, isNotNull);
      expect(container.read(commissionProvider).networkReady, isFalse);
      c.backToNetworkCheck();
      expect(_check(container).wifiProblem, isTrue);
      await c.passNetworkCheck(skip: true);
      await c.chooseStation(newStation: false);
      expect(container.read(commissionProvider).step, 2);
      expect(container.read(commissionProvider).error, reuseBlockedText);
    });

    test('incident: missing home Wi-Fi blocks 沿用目前站點', () async {
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.checkPassed, isFalse, reason: 'the check comes first');
      // Up for an hour: no grace, the failure is shown at once.
      final check = _check(container);
      expect(check.wifi.text, _missingHomeWifi);
      expect(
        check.wifi.text,
        'Gateway 連不上 Wi-Fi「Xiaomi_WU」。這個 Wi-Fi 可能不在附近、密碼不對，'
        '或是 5 GHz（Gateway 只能用 2.4 GHz）。',
      );
      expect(check.wifiProblem, isTrue);
      expect(check.ready, isFalse);
      expect(check.stage, CheckStage.wifi);
      expect(displayStep(s, _production), 2);
      expect(check.reuseBlockedReason, 'Gateway 還沒連上 Wi-Fi');

      // The controller refuses 沿用 however it is reached.
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.error, reuseBlockedText);
      expect(check.canSkip, isTrue);
      await c.passNetworkCheck(skip: true);
      s = container.read(commissionProvider);
      expect(s.checkPassed, isTrue);
      expect(s.config['choose_station'], isTrue);
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.step, 2, reason: 'no jump to data verification');
      expect(s.error, reuseBlockedText);
      expect(fake.commands, isNot(contains('set_data_upload')));
    });

    test('Wi-Fi OK and uploading passes to the station choice', () async {
      final fake = WifiGateway.station()..config['wifi_ssid'] = 'Office-2G';
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      final check = _check(container);
      expect(check.wifi.line, '✓ Gateway 已連上 Wi-Fi「Office-2G」');
      expect(check.target.line, '✓ Gateway 的資料送到正式站，和手機一致');
      expect(check.upload.line, '✓ 資料上傳中');
      expect(check.ready, isTrue);
      expect(check.canSkip, isFalse);
      expect(displayStep(container.read(commissionProvider), _production), 4);
      await c.passNetworkCheck();
      var s = container.read(commissionProvider);
      expect(s.checkPassed, isTrue);
      expect(displayStep(s, _production), 5);
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 4);
      expect(displayStep(s, _production), 6);
      expect(fake.commands, contains('scan_ble_discover'));
    });

    test(
      '重設 Wi-Fi keeps site/gateway ids and PTUs, then confirms upload',
      () async {
        final fake = WifiGateway.station()..simulateWifi('disconnected');
        final (container, c) = await _connected(fake);
        addTearDown(container.dispose);
        final selected = container.read(commissionProvider).selected;
        expect(selected, hasLength(3));

        await c.startWifiFix();
        var s = container.read(commissionProvider);
        expect(s.checkPassed, isTrue);
        expect(s.config['wifi_only'], isTrue, reason: 'Wi-Fi-only flow');
        expect(s.config['choose_station'], isFalse);
        // Other ids are refused: the station stays site 80 / gateway 1.
        await c.configureWifi(81, 1, 'Office-2G', 'password123');
        expect(container.read(commissionProvider).error, isNotNull);
        expect(fake.commands, isNot(contains('set_site_identity')));

        fake.mqttConnected = false;
        await c.configureWifi(80, 1, 'Office-2G', 'password123');
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(fake.commands, isNot(contains('set_site_identity')));
        expect(fake.config['site_id'], 80);
        expect(fake.config['gateway_id'], 1);
        expect(fake.config['wifi_ssid'], 'Office-2G');
        expect(s.selected, selected, reason: 'PTUs kept');
        // Station kept: back to 確認資料上傳 before the data verification.
        expect(s.step, 2);
        expect(s.checkPassed, isFalse);
        expect(displayStep(s, _production), 4);
        await _sleep(60);
        expect(_check(container).upload.tone, StatusTone.pending);
        await c.passNetworkCheck(skip: true);
        s = container.read(commissionProvider);
        expect(s.step, 2, reason: 'no verification before the upload works');
        expect(s.error, uploadNotReadyText);

        fake.mqttConnected = true;
        await _sleep(60);
        expect(_check(container).ready, isTrue);
        await c.passNetworkCheck();
        // Round 26: the station is chosen again after the Wi-Fi reset.
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 2);
        expect(s.config['choose_station'], isTrue);
        expect(s.message, wifiUpdatedChooseStationText);
        await c.chooseStation(newStation: false);
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 4);
        expect(s.selected, selected);
        expect(s.config['site_id'], 80);
      },
    );

    test('new gateway: 設定 Wi-Fi opens the identity and Wi-Fi form', () async {
      final fake = WifiGateway()..simulateWifi('disconnected');
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      expect(_check(container).wifiProblem, isTrue);
      await c.startWifiFix();
      var s = container.read(commissionProvider);
      expect(s.checkPassed, isTrue);
      expect(s.config['wifi_only'], isFalse);
      await c.configureWifi(5, 2, 'Office-2G', 'password123');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 3);
      expect(fake.config['site_id'], 5);
      expect(fake.config['wifi_ssid'], 'Office-2G');
    });

    test('connecting right after a boot gets a grace period', () async {
      final fake = WifiGateway()
        ..simulateWifi('connecting')
        ..connectingReads = 1 << 20;
      final (container, _) = await _connected(fake, offline: false);
      addTearDown(container.dispose);
      var check = _check(container);
      expect(check.wifiVerdict, WifiVerdict.connecting);
      expect(check.wifi.line, '⏳ Gateway 正在連 Wi-Fi…');
      expect(check.canSkip, isFalse, reason: 'still waiting');
      expect(container.read(commissionProvider).networkReady, isFalse);
      await _sleep(160);
      check = _check(container);
      expect(check.wifiVerdict, WifiVerdict.failed);
      expect(check.wifi.line, '✗ ${wifiProblemText('Demo-2.4G')}');
      expect(check.canSkip, isTrue);

      // Joined within the grace period: never shown as a failure.
      final quick = WifiGateway()..simulateWifi('connecting');
      final (container2, _) = await _connected(quick);
      addTearDown(container2.dispose);
      expect(_check(container2).wifiVerdict, WifiVerdict.connecting);
      await _sleep(80);
      final joined = _check(container2);
      expect(joined.wifiVerdict, WifiVerdict.ok);
      expect(joined.wifi.line, '✓ Gateway 已連上 Wi-Fi「Demo-2.4G」');
    });

    test('no Wi-Fi configured says so and offers 設定 Wi-Fi', () {
      final state = CommissionState(
        step: 2,
        peer: const GatewayPeer('id', 'GIOS-S1-GW01', -40),
        config: const {
          'fw_version': '1.7.3',
          'mqtt_target': 'production',
          'mqtt_connected': false,
        },
        net: const {'wifi_state': 'disconnected', 'ssid': '', 'ip': ''},
      );
      expect(state.wifi, WifiVerdict.notConfigured);
      final check = networkCheck(state: state, env: _production);
      expect(check.wifi.line, '✗ Gateway 還沒有設定 Wi-Fi，所以沒辦法上傳資料。');
      expect(
        connectionStatus(env: _production, state: state).hint,
        contains('請按「設定 Wi-Fi」'),
      );
    });

    test(
      'target and Wi-Fi: target first, one reboot, no upload wait',
      () async {
        final fake = WifiGateway.station()..simulateWifi('disconnected');
        final (container, c) = await _connected(
          fake,
          base: 'http://192.168.1.50:18000',
        );
        addTearDown(container.dispose);
        final check = _check(container, _local);
        expect(check.need, SyncNeed.sync);
        expect(check.wifiProblem, isTrue);
        expect(fake.connects, 1);

        await c.startWifiFix(target: check.syncTarget);
        var s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.checkPassed, isTrue);
        expect(s.config['wifi_only'], isTrue);
        expect(parseMqttTarget(s.config)!.sameAs(_lan), isTrue);
        expect(s.uploadNotice, contains('接著設定 Wi-Fi'));
        final afterTarget = fake.commands.sublist(
          fake.commands.indexOf('set_mqtt_target'),
        );
        expect(afterTarget.take(3), [
          'set_mqtt_target',
          'ping',
          'get_net_status',
        ]);
        // Waiting for the upload would read get_net_status ~10 times.
        expect(
          afterTarget.where((op) => op == 'get_net_status').length,
          lessThanOrEqualTo(2),
        );

        await c.configureWifi(80, 1, 'Office-2G', 'password123');
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        final order = fake.commands
            .where((op) => op.startsWith('set_'))
            .toList();
        expect(order, ['set_mqtt_target', 'set_wifi']);
        expect(fake.targetRequests.single, _lan.params);
        expect(fake.connects, 2, reason: 'one reboot for both changes');
        expect(fake.count('set_site_identity'), 0);

        await _sleep(60);
        final done = _check(container, _local);
        expect(done.target.line, '✓ Gateway 的資料送到本地測試主機（192.168.1.50），和手機一致');
        expect(done.ready, isTrue);
      },
    );

    test('a failed target switch keeps the Wi-Fi form closed', () async {
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      fake.config['otp_enabled'] = true;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.startWifiFix(target: _lan);
      final s = container.read(commissionProvider);
      expect(s.error, isNotNull);
      expect(s.checkPassed, isFalse);
      expect(fake.count('set_wifi'), 0);
    });
  });

  group('upload confirmation', () {
    // Round 28: a new gateway uploads nothing before join_fleet (its
    // upload is paused on purpose) — connected, never 「資料上傳中」.
    test(
      'waits, then shows ✓ connected (upload after the commissioning)',
      () async {
        final fake = WifiGateway()..mqttConnected = false;
        final (container, _) = await _connected(fake, offline: false);
        addTearDown(container.dispose);
        var check = _check(container);
        expect(check.wifiOk, isTrue);
        expect(check.upload.line, '⏳ 等待 Gateway 開始上傳資料…（最多約 1 分鐘）');
        expect(check.stage, CheckStage.upload);
        expect(check.canSkip, isFalse);
        fake.mqttConnected = true;
        await _sleep(60);
        check = _check(container);
        expect(check.upload.line, '✓ $uploadHeldText');
        expect(check.upload.line, isNot(contains('資料上傳中')));
        expect(check.ready, isTrue);
      },
    );

    test('no upload in time: plain hints, and 新站 may continue', () async {
      final fake = WifiGateway()
        ..mqttConnected = false
        ..ip = '192.168.0.57';
      fake.config.addAll({'mqtt_target': 'local', 'mqtt_host': '192.168.1.50'});
      final (container, c) = await _connected(
        fake,
        base: 'http://192.168.1.50:18000',
      );
      addTearDown(container.dispose);
      await _sleep(300);
      final s = container.read(commissionProvider);
      expect(s.uploadLate, isTrue);
      final check = _check(container, _local);
      expect(check.upload.line, '✗ Gateway 還沒開始上傳資料。');
      expect(
        check.uploadHint,
        'Gateway 目前在 192.168.0.x 網段，可能連不到測試主機 192.168.1.50。'
        '請確認 Gateway 和這台電腦連同一個 Wi-Fi（可用「重設 Wi-Fi」）。',
      );
      expect(check.canSkip, isTrue);
      await c.passNetworkCheck(skip: true);
      expect(container.read(commissionProvider).checkPassed, isTrue);
      expect(container.read(commissionProvider).step, 2);
    });

    test('hints for the same subnet and for 正式站', () {
      CommissionState late(String target, String ip) => CommissionState(
        step: 2,
        peer: const GatewayPeer('id', 'GIOS-S1-GW01', -40),
        uploadLate: true,
        uploadWatch: UploadWatch.polling,
        config: {
          'fw_version': '1.7.3',
          'mqtt_target': target,
          'mqtt_host': target == 'local' ? '192.168.1.50' : '46.250.255.172',
          'mqtt_port': 8883,
          'mqtt_connected': false,
        },
        net: {'wifi_state': 'got_ip', 'ip': ip, 'ssid': 'Office-2G'},
      );
      expect(
        networkCheck(
          state: late('local', '192.168.1.60'),
          env: _local,
        ).uploadHint,
        '請確認電腦上的測試主機是否開著，以及 Gateway 是否連上和這台電腦同一個 Wi-Fi。',
      );
      expect(
        networkCheck(
          state: late('production', '10.0.0.8'),
          env: _production,
        ).uploadHint,
        '請確認 Gateway 所在的 Wi-Fi 可以上網。',
      );
    });
  });

  group('status panel', () {
    test('Bluetooth down with Wi-Fi down names the Wi-Fi as the cause', () {
      const state = CommissionState(
        step: 6,
        peer: GatewayPeer('id', 'GIOS-S1-GW01', -40),
        uploadWatch: UploadWatch.linkLost,
        config: {
          'fw_version': '1.7.3',
          'site_id': 80,
          'gateway_id': 1,
          'mqtt_target': 'production',
          'mqtt_host': '46.250.255.172',
          'mqtt_port': 8883,
          'mqtt_connected': false,
          'wifi_ssid': 'Xiaomi_WU',
        },
        net: {'wifi_state': 'disconnected', 'ssid': 'Xiaomi_WU', 'ip': ''},
      );
      final status = connectionStatus(env: _production, state: state);
      expect(status.hint, startsWith(_missingHomeWifi));
      expect(status.hint, contains('手機和 Gateway 的藍牙也斷了'));
      expect(status.hint, contains('按「結束並重新選擇閘道器」重新連線，再按「重設 Wi-Fi」'));
      expect(status.hint, isNot(contains('disconnected')));
      expect(status.gateway.status, '✗ Wi-Fi 沒連上');
      final details = status.details.join('\n');
      expect(details, contains('Wi-Fi「Xiaomi_WU」 · 未連線（disconnected）'));

      // Only Bluetooth known to be down: the Bluetooth hint as before.
      final lost = connectionStatus(
        env: _production,
        state: CommissionState(
          step: 6,
          peer: state.peer,
          uploadWatch: UploadWatch.linkLost,
          config: state.config,
        ),
      );
      expect(lost.hint, startsWith('手機和 Gateway 的藍牙已中斷'));
    });

    test('technical details translate the Wi-Fi state', () {
      expect(wifiStateText('got_ip'), '已連線（got_ip）');
      expect(wifiStateText('connecting'), '連線中（connecting）');
      expect(wifiStateText('disconnected'), '未連線（disconnected）');
      expect(wifiStateText('odd'), '未知（odd）');
    });
  });

  group('offline mode', () {
    test(
      'shows the check but never blocks configuring a new station',
      () async {
        final fake = WifiGateway()..mqttConnected = false;
        final (container, c) = await _connected(fake, offline: true);
        addTearDown(container.dispose);
        final check = _check(container);
        expect(check.upload.tone, StatusTone.pending);
        expect(check.canSkip, isTrue, reason: 'offline: no waiting required');
        await c.passNetworkCheck(skip: true);
        await c.configureWifi(3, 1, 'Office-2G', 'password123');
        expect(container.read(commissionProvider).step, 3);
        await c.online(skip: true);
        expect(container.read(commissionProvider).step, 4);
        await c.discover();
        await c.configurePtus();
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 6);
      },
    );

    test('online flow waits before offering to continue', () async {
      final fake = WifiGateway()..mqttConnected = false;
      final (container, _) = await _connected(
        fake,
        offline: false,
        timing: const UploadWatchTiming(
          interval: Duration(milliseconds: 20),
          confirmAfter: Duration(seconds: 5),
        ),
      );
      addTearDown(container.dispose);
      expect(_check(container).canSkip, isFalse);
    });
  });

  test(
    'simulated gateway reports connected / connecting / disconnected',
    () async {
      final fake = DemoSystem();
      Future<String> state() async =>
          (await fake.command('get_net_status'))['wifi_state'] as String;
      expect(await state(), 'got_ip');
      fake.simulateWifi('disconnected');
      expect(await state(), 'disconnected');
      expect((await fake.command('get_net_status'))['mqtt_connected'], isFalse);
      fake.simulateWifi('connecting');
      expect(await state(), 'connecting');
      expect(await state(), 'connecting');
      expect(await state(), 'got_ip');
      fake.unreachableSsids.add('Voltraware-B');
      fake.simulateWifi('disconnected');
      await fake.command('set_wifi', {'ssid': 'Voltraware-B', 'password': 'x'});
      final net = await fake.command('get_net_status');
      expect(net['last_wifi_error'], isNotEmpty);
      expect(net['wifi_state'], 'disconnected');
    },
  );

  group('page', () {
    Future<ProviderContainer> pumpApp(
      WidgetTester tester,
      DemoSystem fake, {
      Map<String, Object> prefs = const {'backend_environment': 'production'},
      bool autoSync = false,
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
            envSwitchPolicyProvider.overrideWithValue(
              EnvSwitchPolicy(
                autoSyncDefault: autoSync,
                confirmGatewaySwitch: false,
              ),
            ),
            localBackendProberProvider.overrideWithValue(_Prober()),
            phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(GatewayApp)));
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> connect(WidgetTester tester) async {
      await tap(tester, find.text('檢查並開始'));
      await tap(tester, find.text('GIOS-S1-GW01'));
    }

    String title(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('step-title'))).data!;

    testWidgets('auto sync waits for Wi-Fi before changing target', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      await pumpApp(
        tester,
        fake,
        autoSync: true,
        prefs: const {
          'backend_environment': 'local',
          'backend_local_url': 'http://192.168.1.50:18000',
        },
      );
      await connect(tester);
      expect(fake.targetRequests, isEmpty);
      expect(title(tester), '3 / 10   Gateway 網路體檢');
      await tap(tester, find.text('重設 Wi-Fi'));
      expect(fake.targetRequests, hasLength(1));
      expect(find.text('保留站點 80／閘道器 1，只更新 Wi-Fi。'), findsOneWidget);
    });

    testWidgets('offline new gateway can bypass failed target setup', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = WifiGateway()
        ..simulateWifi('disconnected')
        ..rejectTarget = true;
      fake.config['wifi_ssid'] = '';
      final container = await pumpApp(
        tester,
        fake,
        prefs: const {
          'backend_environment': 'local',
          'backend_local_url': 'http://192.168.1.50:18000',
        },
      );
      await tap(tester, find.text('先離線配置，稍後驗證資料'));
      await connect(tester);
      expect(container.read(commissionProvider).offline, isTrue);
      await tap(tester, find.text('設定 Wi-Fi'));
      expect(container.read(commissionProvider).error, isNotNull);
      await tap(tester, find.byKey(const Key('check-skip')));
      expect(find.widgetWithText(TextField, '站點 ID（1–65535）'), findsOneWidget);
      expect(container.read(commissionProvider).checkPassed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stepper shows the new order', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = WifiGateway.station()..config['wifi_ssid'] = 'Office-2G';
      await pumpApp(tester, fake);
      const expected = [
        '1 準備',
        '2 找到閘道器',
        '3 Gateway 網路體檢',
        '4 對準上傳目標',
        '5 確認資料上傳',
        '6 站點選擇',
        '7 選擇 PTU',
        '8 開始監控',
        '9 驗證資料',
        '10 完成',
      ];
      final list = find.byKey(const Key('step-list'));
      final shown = tester
          .widgetList<Text>(
            find.descendant(of: list, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      expect(shown, expected);
      // Laid out in reading order.
      Offset at(String text) => tester.getTopLeft(
        find.descendant(of: list, matching: find.text(text)),
      );
      for (var i = 1; i < expected.length; i++) {
        final a = at(expected[i - 1]), b = at(expected[i]);
        expect(b.dy > a.dy || (b.dy == a.dy && b.dx > a.dx), isTrue);
      }
      expect(title(tester), '1 / 10   準備');

      await connect(tester);
      expect(title(tester), '6 / 10   站點選擇');
      expect(find.text('沿用目前站點'), findsOneWidget);
      expect(find.byKey(const Key('check-next')), findsNothing);
      await tap(tester, find.text('沿用目前站點'));
      expect(title(tester), '7 / 10   選擇 PTU');
      expect(fake.commands, contains('scan_ble_discover'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wi-Fi down: 沿用 is disabled with the reason', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      final container = await pumpApp(tester, fake);
      await connect(tester);
      expect(title(tester), '3 / 10   Gateway 網路體檢');
      expect(find.text('✗ $_missingHomeWifi'), findsOneWidget);
      expect(find.text('重設 Wi-Fi'), findsOneWidget);
      // The panel names the Wi-Fi as the cause too, in plain words.
      expect(find.textContaining('Gateway 連不上 Wi-Fi「Xiaomi_WU」'), findsWidgets);
      expect(find.textContaining('disconnected'), findsNothing);

      await tap(tester, find.byKey(const Key('check-skip')));
      expect(title(tester), '6 / 10   站點選擇');
      final reuse = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '沿用目前站點'),
      );
      expect(reuse.onPressed, isNull);
      expect(find.byKey(const Key('reuse-blocked')), findsOneWidget);
      expect(container.read(commissionProvider).step, 2);

      // 回到網路體檢 → 重設 Wi-Fi: Wi-Fi only, site and gateway locked.
      await tap(tester, find.text('回到網路體檢'));
      await tap(tester, find.text('重設 Wi-Fi'));
      expect(find.text('保留站點 80／閘道器 1，只更新 Wi-Fi。'), findsOneWidget);
      expect(find.widgetWithText(TextField, '站點 ID（1–65535）'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow 360dp: network check and station choice fit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      await pumpApp(
        tester,
        fake,
        prefs: const {
          'backend_environment': 'local',
          'backend_local_url': 'http://192.168.1.50:18000',
        },
      );
      await connect(tester);
      expect(title(tester), '3 / 10   Gateway 網路體檢');
      // The list builds lazily: scroll the check into view.
      Future<void> reveal(Finder finder) => tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await reveal(find.text('技術細節'));
      await tap(tester, find.text('技術細節'));
      expect(find.textContaining('未連線（disconnected）'), findsOneWidget);
      await reveal(find.text('✗ $_missingHomeWifi'));
      expect(find.text('✗ $_missingHomeWifi'), findsOneWidget);
      await reveal(find.textContaining('再設定 Wi-Fi'));
      expect(
        find.text('按下後會先讓 Gateway 改送到本地測試主機（重新開機一次），再設定 Wi-Fi。'),
        findsOneWidget,
      );
      await reveal(find.byKey(const Key('check-skip')));
      await tap(tester, find.byKey(const Key('check-skip')));
      await reveal(find.byKey(const Key('reuse-blocked')));
      expect(find.byKey(const Key('reuse-blocked')), findsOneWidget);
      await reveal(find.text('保留站點，重設 Wi-Fi'));
      await tap(tester, find.text('保留站點，重設 Wi-Fi'));
      await reveal(find.text('Gateway 只能用 2.4 GHz 的 Wi-Fi，5 GHz 的網路連不上。'));
      expect(
        find.text('Gateway 只能用 2.4 GHz 的 Wi-Fi，5 GHz 的網路連不上。'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow 360dp: 對準上傳目標 step fits', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = WifiGateway.station()..config['wifi_ssid'] = 'Office-2G';
      final container = await pumpApp(
        tester,
        fake,
        prefs: const {
          'backend_environment': 'local',
          'backend_local_url': 'http://192.168.1.50:18000',
        },
      );
      Future<void> reveal(Finder finder) => tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await connect(tester);
      expect(title(tester), '4 / 10   對準上傳目標');
      final sync = find.byKey(const Key('check-sync'));
      await reveal(sync);
      expect(find.text('讓 Gateway 改送到本地測試主機（重新開機約 1 分鐘）'), findsOneWidget);
      await tap(tester, sync);
      expect(fake.targetRequests.single, _lan.params);
      expect(container.read(commissionProvider).error, isNull);
      // The title may be scrolled away (the list builds lazily).
      int shown() => displayStep(
        container.read(commissionProvider),
        container.read(backendEnvProvider),
      );
      expect(stepLabels[shown()], '站點選擇');
      // Let the 「正在把 Gateway 切到…」 snack bar go away first.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(stepLabels[shown()], '站點選擇');
      expect(tester.takeException(), isNull);
    });

    testWidgets('practice mode offers the simulated Wi-Fi states', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ProviderScope(child: GatewayApp()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      Future<void> reveal(Finder finder) => tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await reveal(find.text('使用模擬設備練習'));
      await tap(tester, find.text('使用模擬設備練習'));
      expect(container.read(demoProvider), isTrue);
      final choice = find.byKey(const Key('demo-wifi'));
      await reveal(choice);
      await tap(tester, choice);
      await tester.tap(find.text('連不上（Wi-Fi 不在附近）').last);
      await tester.pumpAndSettle();
      expect(container.read(demoSystemProvider).wifiState, 'disconnected');
      expect(tester.takeException(), isNull);
    });
  });
}
