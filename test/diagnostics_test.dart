import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/verify_diagnosis.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/dashboard_api.dart';
import 'package:gateway_commissioning/data/demo_system.dart';

/// Demo backend whose step-7 data never becomes healthy.
class StaleBackend extends DemoSystem {
  bool noGatewayData = false;

  /// No gateways row: bot-monitor answers 404 gateway_not_found.
  bool noGatewayRow = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (noGatewayRow && path.endsWith('/bot-monitor')) {
      throw GatewayFailure.http(
        status: 404,
        endpoint: '$method $path',
        detail: 'gateway_not_found',
        backend: '區域網路／本機後端 http://192.168.1.20:8000',
      );
    }
    if (path.contains('verify-installation')) {
      return {
        'all_ok': false,
        'devices': [
          {
            'device_id': 1,
            'data_ok': false,
            'last_seen': null,
            'time_since_last': null,
          },
          {
            'device_id': 2,
            'data_ok': false,
            'last_seen': '2030-01-01T00:00:00',
            'time_since_last': 400,
          },
          {
            'device_id': 3,
            'data_ok': true,
            'last_seen': '2030-01-01T00:00:00',
            'time_since_last': 5,
          },
        ],
      };
    }
    if (noGatewayData && path.contains('fleet-status')) {
      return {'mqtt_connected': true, 'gateways': []};
    }
    if (path.contains('/api/latest')) {
      if (noGatewayData) return {'items': []};
      return {
        'items': [
          {
            'device_id': 2,
            'online': false,
            'lag_seconds': 400,
            'error_num': 0,
            'ts': '2030-01-01T00:00:00',
          },
          {
            'device_id': 3,
            'online': true,
            'lag_seconds': 1,
            'error_num': 7,
            'ts': '2030-01-01T00:00:00',
          },
        ],
      };
    }
    return super.request(method, path, body);
  }
}

/// Round 1 fails and leaves a diagnosis; round 2 then sees upload paused and
/// its set_data_upload command times out on the BLE link.
class PausedTimeout extends StaleBackend {
  int fleetCalls = 0;
  bool verifying = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.endsWith('/bot-monitor')) verifying = true;
    if (verifying && path.contains('fleet-status')) {
      fleetCalls++;
      final result = await super.request(method, path, body);
      if (fleetCalls >= 2) {
        for (final g in (result['gateways'] as List)) {
          (g as Map)['upload_paused'] = true;
        }
      }
      return result;
    }
    return super.request(method, path, body);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (verifying && op == 'set_data_upload') {
      throw const GatewayFailure('timeout');
    }
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _atVerify(
  DemoSystem fake,
) async {
  SharedPreferences.setMockInitialValues({});
  // The gateway uploads to the same LAN backend, so step 7 runs its checks.
  fake.config.addAll({'mqtt_target': 'local', 'mqtt_host': '192.168.1.20'});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare('http://192.168.1.20:8000', '');
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

  group('GatewayFailure messages', () {
    test('404 gateway_not_found names station, gateway and backend', () {
      const failure = GatewayFailure.http(
        status: 404,
        endpoint: 'PATCH /api/gateways/3/2/bot-monitor',
        detail: 'gateway_not_found',
        backend: '區域網路／本機後端 http://192.168.1.20:8000',
      );
      expect(
        failure.message,
        startsWith(
          '後端找不到此 Gateway（站 3 / Gateway 2）。Gateway 的資料可能上傳到其他後端環境'
          '（例如正式站），而 APP 目前連的是 區域網路／本機後端 http://192.168.1.20:8000。',
        ),
      );
      expect(failure.message, contains('PATCH /api/gateways/3/2/bot-monitor'));
    });
    test('5xx and other statuses show status, endpoint and detail', () {
      const e500 = GatewayFailure.http(
        status: 502,
        endpoint: 'GET /api/latest',
      );
      expect(e500.message, contains('後端內部錯誤（HTTP 502）'));
      const e422 = GatewayFailure.http(
        status: 422,
        endpoint: 'GET /api/latest',
        detail: 'bad site',
      );
      expect(e422.message, contains('HTTP 422'));
      expect(e422.message, contains('GET /api/latest · bad site'));
    });
    test('gateway fail ack and unexpected errors are not generic', () {
      expect(
        const GatewayFailure.gateway('invalid param').message,
        'Gateway 回報失敗：invalid param',
      );
      expect(
        const GatewayFailure.gateway('busy').message,
        const GatewayFailure('busy').message,
      );
      final unexpected = GatewayFailure.unexpected(StateError('boom'));
      expect(unexpected.message, contains('StateError'));
      expect(unexpected.message, contains('boom'));
    });
  });

  group('DashboardApi', () {
    // The test binding installs a fake HttpClient; use real loopback sockets.
    HttpOverrides? saved;
    setUp(() {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() => HttpOverrides.global = saved);
    test('unreachable backend maps to network message', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final api = DashboardApi();
      try {
        await api.login('http://127.0.0.1:$port', 'pw');
        fail('login should fail');
      } on GatewayFailure catch (e) {
        expect(e.code, 'network');
        expect(e.message, contains('無法連到 區域網路／本機後端 http://127.0.0.1:$port'));
        expect(e.message, contains('同一個 Wi-Fi 網段'));
        expect(e.message, contains('防火牆'));
        expect(e.message, isNot(contains('pw')));
      }
    });
    test('404 detail and endpoint are carried without query', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path == '/api/auth/login') {
          req.response.write(jsonEncode({'api_key': 'k'}));
        } else {
          req.response.statusCode = 404;
          req.response.write(jsonEncode({'detail': 'gateway_not_found'}));
        }
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final api = DashboardApi();
      await api.login('http://127.0.0.1:${server.port}', 'pw');
      try {
        await api.request(
          'POST',
          '/api/gateways/5/1/reserve-identity?mac=AABBCC',
        );
        fail('request should fail');
      } on GatewayFailure catch (e) {
        expect(e.status, 404);
        expect(e.detail, 'gateway_not_found');
        expect(e.endpoint, 'POST /api/gateways/5/1/reserve-identity');
        expect(e.message, contains('後端找不到此 Gateway（站 5 / Gateway 1）'));
        expect(e.message, isNot(contains('AABBCC')));
      }
    });
  });

  group('step 7 diagnosis', () {
    test('per-device reasons', () {
      expect(
        ptuVerifyReasons(
          install: {'data_ok': false, 'last_seen': null},
          latest: null,
        ),
        ['後端無資料'],
      );
      final stale = DateTime.parse('2030-01-01T00:00:00');
      expect(
        ptuVerifyReasons(
          latest: {
            'online': false,
            'lag_seconds': 75,
            'error_num': 3,
            'ts': '2030-01-01T00:00:00',
          },
          previous: stale,
        ),
        ['離線', '延遲 75 秒', 'error_num=3', '資料未更新（最後 2030-01-01T00:00:00）'],
      );
    });
    test('verify timeout reports reasons for each PTU', () async {
      final fake = StaleBackend();
      final (container, c) = await _atVerify(fake);
      addTearDown(container.dispose);
      await c.verify('http://192.168.1.20:8000', '');
      final error = container.read(commissionProvider).error!;
      expect(error, startsWith('資料驗證未通過：'));
      expect(error, contains('PTU #1：後端無資料'));
      expect(error, contains('PTU #2：後端資料延遲 400 秒、離線、延遲 400 秒'));
      expect(error, contains('PTU #3：error_num=7'));
      expect(error, contains('資料未更新'));
      expect(error, isNot(contains('環境')));
    });
    test(
      'no data with a confirmed matching target points at MQTT, not env',
      () async {
        final fake = StaleBackend()..noGatewayData = true;
        final (container, c) = await _atVerify(fake);
        addTearDown(container.dispose);
        await c.verify('http://192.168.1.20:8000', '');
        final error = container.read(commissionProvider).error!;
        expect(
          error,
          contains('Gateway 的資料沒有進入目前連線的區域網路／本機後端 http://192.168.1.20:8000'),
        );
        expect(error, contains('Gateway 已確認上傳到本地 192.168.1.20:8883'));
        expect(error, contains('防火牆已開放 TCP 8883'));
        expect(error, contains('憑證包含電腦目前的 IP 192.168.1.20'));
        expect(error, isNot(contains('其他後端環境')));
      },
    );
    test(
      '404 gateway_not_found with a matching target explains MQTT',
      () async {
        final fake = StaleBackend();
        final (container, c) = await _atVerify(fake);
        addTearDown(container.dispose);
        fake.noGatewayRow = true;
        await c.verify('http://192.168.1.20:8000', '', environment: 'local');
        final error = container.read(commissionProvider).error!;
        expect(error, startsWith('後端找不到此 Gateway（站 1 / Gateway 1）'));
        expect(error, contains('還沒連上該 MQTT broker'));
        expect(error, contains('本地 MQTT broker 已啟動'));
        expect(
          error,
          contains('[HTTP 404 · PATCH /api/gateways/1/1/bot-monitor'),
        );
        expect(error, isNot(contains('其他後端環境')));
      },
    );
    test('404 with an unknown target keeps the other-backend hint', () async {
      final fake = StaleBackend();
      final (container, c) = await _atVerify(fake);
      addTearDown(container.dispose);
      fake.noGatewayRow = true;
      // A custom public URL cannot be mapped to a gateway target.
      await c.verify('https://example.invalid', '');
      expect(
        container.read(commissionProvider).error,
        contains('其他後端環境（例如正式站）'),
      );
    });
    test('cause wording depends on the known targets', () {
      const lan = MqttTarget.local('192.168.1.20');
      expect(
        missingGatewayCause(running: lan, wanted: lan, mqttConnected: false),
        contains('Gateway 最近回報 MQTT 未連線'),
      );
      const prod = MqttTarget.production(host: '46.250.255.172');
      final onProduction = missingGatewayCause(
        running: prod,
        wanted: const MqttTarget.production(),
      );
      expect(onProduction, contains('現場網路可連到正式站'));
      expect(onProduction, isNot(contains('例如正式站')));
      final unknownOnProduction = missingGatewayCause(
        wanted: const MqttTarget.production(),
      );
      expect(unknownOnProduction, contains('例如本地測試站'));
      expect(unknownOnProduction, isNot(contains('例如正式站')));
      expect(missingGatewayCause(), contains('其他後端環境（例如正式站）'));
    });
    test('BLE command timeout is not replaced by the data diagnosis', () async {
      final fake = PausedTimeout();
      final (container, c) = await _atVerify(fake);
      addTearDown(container.dispose);
      await c.verify('http://192.168.1.20:8000', '');
      expect(
        container.read(commissionProvider).error,
        const GatewayFailure('timeout').message,
      );
    });
    test('PTU without device number is flagged', () async {
      final fake = DemoSystem();
      final (container, c) = await _atVerify(fake);
      addTearDown(container.dispose);
      final state = container.read(commissionProvider);
      final mac = state.ptus.first['mac'];
      state.ptus.first['device_number'] = 0;
      await c.verify('http://192.168.1.20:8000', '');
      expect(
        container.read(commissionProvider).error,
        contains('PTU $mac：PTU 未取得裝置編號'),
      );
    });
  });
}
