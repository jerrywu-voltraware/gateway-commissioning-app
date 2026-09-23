import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/presentation/connection_status_panel.dart';

const _healthy = ProbeResult(ProbeOutcome.healthy, status: 200, version: '1');
const _peer = GatewayPeer('id', 'GIOS-S1-GW01', -40);
const _local = BackendEnvState(
  environment: BackendEnv.local,
  localHost: '192.168.1.187',
  loaded: true,
);
const _production = BackendEnvState(loaded: true);

Map<String, dynamic> _target(String target, {bool? connected}) => {
  'fw_version': '1.7.3',
  'site_id': 1,
  'gateway_id': 1,
  'mqtt_target': target,
  'mqtt_host': target == 'local' ? '192.168.1.187' : '46.250.255.172',
  'mqtt_port': 8883,
  'mqtt_connected': ?connected,
};

CommissionState _state(
  Map<String, dynamic> config, {
  Map<String, dynamic> net = const {},
  UploadWatch watch = UploadWatch.idle,
  int step = 2,
  bool loggedIn = false,
}) => CommissionState(
  step: step,
  peer: _peer,
  config: config,
  net: net,
  uploadWatch: watch,
  loggedIn: loggedIn,
);

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      _healthy;
}

/// Simulated gateway that can stop uploading, drop the link, or hold a step.
class NetGateway extends DemoSystem {
  final commands = <String>[];
  bool linkDown = false;
  Completer<void>? discoverGate;
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add(op);
    if (linkDown) throw const GatewayFailure('disconnected');
    if (op == 'scan_ble_discover') await discoverGate?.future;
    return super.command(op, params);
  }

  int get polls => commands.where((c) => c == 'get_net_status').length;

  final paths = <String>[];
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
  NetGateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      uploadWatchTimingProvider.overrideWithValue(
        const UploadWatchTiming(
          interval: Duration(milliseconds: 20),
          cap: Duration(milliseconds: 200),
        ),
      ),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare(productionApiBase, '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

Future<void> _sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('status model', () {
    test('gateway on another /24 than the test host gets the Wi-Fi hint', () {
      final status = connectionStatus(
        env: _local,
        state: _state(
          _target('local', connected: false),
          net: {
            'wifi_state': 'got_ip',
            'ip': '192.168.0.57',
            'ssid': 'Office-2G',
            'rssi': -61,
          },
          watch: UploadWatch.polling,
        ),
        probe: _healthy,
      );
      expect(status.phone.where, '本地測試主機');
      expect(status.phone.status, '✓ 已連線');
      expect(status.gateway.where, '本地測試主機');
      expect(status.gateway.status, '⏳ 連線中…');
      expect(
        status.hint,
        'Gateway 目前在 192.168.0.x 網段，連不到測試主機 192.168.1.187。'
        '請讓 Gateway 和這台電腦連同一個 Wi-Fi（可用「保留站點，重設 Wi-Fi」）。',
      );
      expect(status.allOk, isFalse);
      final details = status.details.join('\n');
      expect(
        details,
        contains('Wi-Fi「Office-2G」 · IP 192.168.0.57 · 訊號 -61 dBm'),
      );
      expect(details, contains('192.168.1.187:8883'));
      expect(details, contains('防火牆已開放 TCP 8883'));
      expect(details, contains('韌體版本：1.7.3'));
    });
    test('same subnet but never connected gets one generic hint', () {
      final status = connectionStatus(
        env: _local,
        state: _state(
          _target('local', connected: false),
          net: {'wifi_state': 'got_ip', 'ip': '192.168.1.60'},
          watch: UploadWatch.gaveUp,
        ),
        probe: _healthy,
      );
      expect(status.gateway.status, '✗ 連不上');
      expect(status.hint, '請確認電腦上的測試主機是否開著，以及 Gateway 是否連上和這台電腦同一個 Wi-Fi。');
      final pending = connectionStatus(
        env: _local,
        state: _state(
          _target('local', connected: false),
          net: {'wifi_state': 'got_ip', 'ip': '192.168.1.60'},
          watch: UploadWatch.polling,
        ),
        probe: _healthy,
      );
      expect(pending.hint, isNull, reason: 'no guess while still connecting');
    });
    test('gateway without Wi-Fi and a dropped link get their own hint', () {
      final wifi = connectionStatus(
        env: _production,
        state: _state(
          _target('production', connected: false),
          net: {'wifi_state': 'connecting', 'ip': ''},
          watch: UploadWatch.gaveUp,
        ),
        probe: _healthy,
      );
      expect(wifi.hint, startsWith('Gateway 還沒連上 Wi-Fi'));
      final lost = connectionStatus(
        env: _production,
        state: _state(_target('production'), watch: UploadWatch.linkLost),
        probe: _healthy,
      );
      expect(lost.gateway.status, '✗ 連不上');
      expect(lost.hint, startsWith('手機和 Gateway 的藍牙斷了'));
    });
    test('all connected collapses to one line', () {
      final status = connectionStatus(
        env: _local,
        state: _state(_target('local', connected: true)),
        probe: _healthy,
      );
      expect(status.gateway.status, '✓ 資料上傳中');
      expect(status.hint, isNull);
      expect(status.summary, '✓ 本地測試：手機與 Gateway 都已連上');
      final production = connectionStatus(
        env: _production,
        state: _state(_target('production', connected: true), loggedIn: true),
        probe: const ProbeResult(ProbeOutcome.notBackend, status: 200),
      );
      expect(production.summary, '✓ 正式站：手機與 Gateway 都已連上');
    });
    test('mismatch offers 同步 in plain words', () {
      final status = connectionStatus(
        env: _local,
        state: _state(_target('production', connected: true)),
        probe: _healthy,
      );
      expect(status.need, SyncNeed.sync);
      expect(status.syncTarget!.host, '192.168.1.187');
      expect(status.gateway.where, '正式站');
      expect(status.gateway.status, '⚠ 送到別處');
      expect(
        status.hint,
        'Gateway 把資料送到正式站，但手機連的是本地測試主機（192.168.1.187）。'
        '按「同步」讓 Gateway 改送到本地測試主機。',
      );
      expect(status.hint, isNot(contains('MQTT')));
      expect(status.hint, isNot(contains('8883')));
    });
    test('legacy firmware says plainly it can only use 正式站', () {
      final status = connectionStatus(
        env: _local,
        state: _state({'fw_version': '1.7.2', 'site_id': 1}),
        probe: _healthy,
      );
      expect(status.need, SyncNeed.legacy);
      expect(status.gateway.status, '⚠ 送到別處');
      expect(status.hint, '這台 Gateway 韌體太舊（版本 1.7.2），只能送到正式站，請更新到 1.7.3 以上。');
      final onProduction = connectionStatus(
        env: _production,
        state: _state({'fw_version': '1.7.2'}),
        probe: _healthy,
      );
      expect(onProduction.need, SyncNeed.none);
      expect(onProduction.hint, isNull);
    });
    test('phone row: local must answer /healthz, production may not', () {
      final down = connectionStatus(
        env: _local,
        state: _state(_target('local', connected: true)),
        probe: const ProbeResult(ProbeOutcome.unreachable),
      );
      expect(down.phone.status, '✗ 連不上');
      expect(down.hint, startsWith('手機連不到測試主機'));
      final unknown = connectionStatus(
        env: _production,
        state: _state(_target('production', connected: true)),
        probe: const ProbeResult(ProbeOutcome.httpError, status: 404),
      );
      expect(unknown.phone.where, '正式站');
      expect(unknown.phone.status, isEmpty);
    });
    test('step 7 with a local gateway warns before shipping', () {
      final status = connectionStatus(
        env: _local,
        state: _state(_target('local', connected: true), step: 7),
        probe: _healthy,
      );
      expect(status.shipWarning, isTrue);
      expect(status.allOk, isFalse);
    });
  });

  group('upload polling', () {
    test('stops once the gateway reports it is uploading', () async {
      final fake = NetGateway()..mqttConnected = false;
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      await _sleep(90);
      var s = container.read(commissionProvider);
      expect(s.uploadWatch, UploadWatch.polling);
      expect(fake.polls, greaterThanOrEqualTo(2));
      expect(s.config['mqtt_connected'], isFalse);
      fake.mqttConnected = true;
      await _sleep(80);
      s = container.read(commissionProvider);
      expect(s.uploadWatch, UploadWatch.idle);
      expect(s.config['mqtt_connected'], isTrue);
      expect(s.net['wifi_state'], 'got_ip');
      final polls = fake.polls;
      await _sleep(100);
      expect(fake.polls, polls, reason: 'no polling after success');
    });
    test('gives up after the time cap', () async {
      final fake = NetGateway()..mqttConnected = false;
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      await _sleep(400);
      final s = container.read(commissionProvider);
      expect(s.uploadWatch, UploadWatch.gaveUp);
      final polls = fake.polls;
      expect(polls, lessThanOrEqualTo(12));
      await _sleep(100);
      expect(fake.polls, polls);
      final status = connectionStatus(env: _production, state: s);
      expect(status.gateway.status, '✗ 連不上');
    });
    test('stops when the flow is ended or the link drops', () async {
      final fake = NetGateway()..mqttConnected = false;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await _sleep(50);
      await c.cancel();
      expect(container.read(commissionProvider).uploadWatch, UploadWatch.idle);
      final polls = fake.polls;
      await _sleep(100);
      expect(fake.polls, polls);

      final dropped = NetGateway()..mqttConnected = false;
      final (container2, _) = await _connected(dropped);
      addTearDown(container2.dispose);
      await _sleep(50);
      dropped.linkDown = true;
      await _sleep(60);
      expect(
        container2.read(commissionProvider).uploadWatch,
        UploadWatch.linkLost,
      );
      final after = dropped.polls;
      await _sleep(100);
      expect(dropped.polls, after);
    });
    test('never polls while a step is running on the link', () async {
      final fake = NetGateway()..mqttConnected = false;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await _sleep(30);
      fake.discoverGate = Completer<void>();
      final step = c.discover();
      await _sleep(5);
      final start = fake.commands.length;
      // Longer than the 200 ms cap: time under a step must not count.
      await _sleep(300);
      expect(container.read(commissionProvider).busy, isTrue);
      expect(fake.commands.sublist(start), isNot(contains('get_net_status')));
      fake.discoverGate!.complete();
      await step;
      expect(container.read(commissionProvider).error, isNull);
      expect(
        container.read(commissionProvider).uploadWatch,
        UploadWatch.polling,
      );
    });
    test('after a backend switch the old login is not reused', () async {
      final fake = NetGateway();
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(productionApiBase, 'secret');
      expect(container.read(commissionProvider).loggedIn, isTrue);
      c.backendChanged(productionApiBase);
      expect(container.read(commissionProvider).loggedIn, isTrue);
      c.backendChanged('http://192.168.1.99:18000');
      expect(container.read(commissionProvider).loggedIn, isFalse);
      fake.paths.clear();
      await c.repair();
      expect(
        container.read(commissionProvider).error,
        const GatewayFailure('authentication').message,
      );
      expect(fake.paths, isEmpty);
      await c.login('http://192.168.1.99:18000', 'x');
      expect(container.read(commissionProvider).loggedIn, isTrue);
    });
    test('legacy firmware is not polled', () async {
      final fake = NetGateway();
      fake.config
        ..['fw_version'] = '1.7.2'
        ..remove('mqtt_target')
        ..remove('mqtt_host')
        ..remove('mqtt_port');
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      await _sleep(60);
      expect(fake.polls, 0);
      expect(container.read(commissionProvider).uploadWatch, UploadWatch.idle);
    });
  });

  group('panel', () {
    Future<List<String>> pumpPanel(
      WidgetTester tester,
      CommissionState state,
      BackendEnvState env,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localBackendProberProvider.overrideWithValue(_Prober())],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ConnectionStatusPanel(
                    state: state,
                    env: env,
                    onSync: () => calls.add('sync'),
                    onRefresh: () => calls.add('refresh'),
                    onShipSwitch: () => calls.add('ship'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('all OK is one line and expands on tap', (tester) async {
      await pumpPanel(
        tester,
        _state(_target('local', connected: true)),
        _local,
      );
      expect(find.text('✓ 本地測試：手機與 Gateway 都已連上'), findsOneWidget);
      expect(find.text('手機 → 後端'), findsNothing);
      await tester.tap(find.text('✓ 本地測試：手機與 Gateway 都已連上'));
      await tester.pumpAndSettle();
      expect(find.text('連線狀態'), findsOneWidget);
      expect(find.text('手機 → 後端'), findsOneWidget);
      expect(find.text('Gateway → 資料上傳'), findsOneWidget);
      expect(find.text('✓ 資料上傳中'), findsOneWidget);
    });
    testWidgets('mismatch shows 同步; technical words stay collapsed', (
      tester,
    ) async {
      final calls = await pumpPanel(
        tester,
        _state(_target('production', connected: true)),
        _local,
      );
      expect(find.text('⚠ 送到別處'), findsOneWidget);
      expect(find.textContaining('8883'), findsNothing);
      expect(find.textContaining('MQTT'), findsNothing);
      await tester.tap(find.text('同步'));
      expect(calls, ['sync']);
      await tester.tap(find.text('技術細節'));
      await tester.pumpAndSettle();
      expect(find.textContaining('46.250.255.172:8883'), findsOneWidget);
      await tester.tap(find.byKey(const Key('connection-status-refresh')));
      expect(calls, ['sync', 'refresh']);
    });
    testWidgets('step 7 on a local target offers the switch back', (
      tester,
    ) async {
      final calls = await pumpPanel(
        tester,
        _state(_target('local', connected: true), step: 7),
        _local,
      );
      expect(find.text(localTargetShipWarning), findsOneWidget);
      await tester.tap(find.text('手機和 Gateway 都切回正式站'));
      expect(calls, ['ship']);
    });
  });

  testWidgets('release confirmation is short and can be declined', (
    tester,
  ) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await confirmUploadTargetSwitch(
                context,
                wanted: const MqttTarget.local('192.168.1.50'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('同時切換 Gateway？'), findsOneWidget);
    expect(
      find.text(
        'Gateway 會改把資料送到本地測試主機（192.168.1.50），並重新開機約 1 分鐘，期間請留在 Gateway 旁。',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('先不要'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切換'));
    await tester.pumpAndSettle();
    expect(answers, [false, true]);
  });
}
