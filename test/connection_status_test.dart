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
  bool slow = false,
}) => CommissionState(
  step: step,
  peer: _peer,
  config: config,
  net: net,
  uploadWatch: watch,
  loggedIn: loggedIn,
  uploadSlow: slow,
);

const _unconfirmed = {
  'fw_version': '1.7.3',
  'site_id': 1,
  'gateway_id': 1,
  'mqtt_target': unconfirmedMqttTarget,
};
const _custom = BackendEnvState(
  environment: BackendEnv.custom,
  customUrl: 'https://example.invalid',
  loaded: true,
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
  Completer<void>? latestGate;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add('$method $path');
    if (path.startsWith('/api/latest')) await latestGate?.future;
    return super.request(method, path, body);
  }

  final logins = <(String, String)>[];
  @override
  Future<void> login(String base, String password) async =>
      logins.add((base, password));
}

const _otherBackend = 'http://192.168.1.99:18000';

/// Commissioned through step 7 on 正式站 (existing station, 3 PTUs).
Future<(ProviderContainer, CommissioningController)> _verified(
  NetGateway fake,
) async {
  fake.config['fleet_joined'] = true;
  for (final (i, device) in fake.devices.indexed) {
    device
      ..['device_number'] = i + 1
      ..['connected'] = true
      ..['notify_enabled'] = true;
  }
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare(productionApiBase, 'secret');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  await c.configurePtus();
  await c.verify(productionApiBase, '', environment: 'production');
  return (container, c);
}

Future<(ProviderContainer, CommissioningController)> _connected(
  NetGateway fake, {
  UploadWatchTiming timing = const UploadWatchTiming(
    interval: Duration(milliseconds: 20),
    cap: Duration(milliseconds: 200),
  ),
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
  await c.prepare(productionApiBase, '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

Future<void> _sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('status model', () {
    test('gateway on another /24 gets the Wi-Fi hint only after waiting', () {
      const net = {
        'wifi_state': 'got_ip',
        'ip': '192.168.0.57',
        'ssid': 'Office-2G',
        'rssi': -61,
      };
      const hint =
          'Gateway 目前在 192.168.0.x 網段，可能連不到測試主機 192.168.1.187。'
          '請確認 Gateway 和這台電腦連同一個 Wi-Fi（可用「保留站點，重設 Wi-Fi」）。';
      // Just started polling: a /16 network may still connect, no guess yet.
      final early = connectionStatus(
        env: _local,
        state: _state(
          _target('local', connected: false),
          net: net,
          watch: UploadWatch.polling,
        ),
        probe: _healthy,
      );
      expect(early.gateway.status, '⏳ 連線中…');
      expect(early.hint, isNull);
      // Polling for 30 s or more without upload.
      final status = connectionStatus(
        env: _local,
        state: _state(
          _target('local', connected: false),
          net: net,
          watch: UploadWatch.polling,
          slow: true,
        ),
        probe: _healthy,
      );
      expect(status.phone.where, '本地測試主機');
      expect(status.phone.status, '✓ 已連線');
      expect(status.gateway.where, '本地測試主機');
      expect(status.gateway.status, '⏳ 連線中…');
      expect(status.hint, hint);
      expect(status.allOk, isFalse);
      // Polling gave up.
      final gaveUp = connectionStatus(
        env: _local,
        state: _state(
          _target('local', connected: false),
          net: net,
          watch: UploadWatch.gaveUp,
        ),
        probe: _healthy,
      );
      expect(gaveUp.gateway.status, '✗ 連不上');
      expect(gaveUp.hint, hint);
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
          net: {'wifi_state': 'connecting', 'ip': '', 'ssid': 'Xiaomi_WU'},
          watch: UploadWatch.gaveUp,
        ),
        probe: _healthy,
      );
      // Polling gave up: the last Wi-Fi state is the cause, in plain words.
      expect(wifi.hint, startsWith('Gateway 連不上 Wi-Fi「Xiaomi_WU」'));
      expect(wifi.gateway.status, '✗ Wi-Fi 沒連上');
      final lost = connectionStatus(
        env: _production,
        state: _state(_target('production'), watch: UploadWatch.linkLost),
        probe: _healthy,
      );
      expect(lost.gateway.status, '？ 藍牙已中斷，上傳狀態待確認');
      expect(lost.hint, startsWith('手機和 Gateway 的藍牙已中斷'));
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
    test('step 7 on 正式站 has no shipping warning', () {
      final status = connectionStatus(
        env: _production,
        state: _state(
          _target('production', connected: true),
          step: 7,
          loggedIn: true,
        ),
        probe: _healthy,
      );
      expect(status.shipWarning, isFalse);
      expect(status.summary, '✓ 正式站：手機與 Gateway 都已連上');
    });
    test('unknown upload target offers exactly one action', () {
      // The APP knows where it should go: 「同步」 settles it.
      final sync = connectionStatus(
        env: _local,
        state: _state(_unconfirmed),
        probe: _healthy,
      );
      expect(sync.gateway.where, '未確認');
      expect(sync.gateway.status, '？ 未確認');
      expect(sync.need, SyncNeed.sync);
      expect(sync.hint, '還不確定 Gateway 把資料送到哪裡。按「同步」讓 Gateway 改送到本地測試主機。');
      expect(sync.allOk, isFalse);
      final details = sync.details.join('\n');
      expect(details, contains('未確認（切換結果尚未讀回）'));
      expect(details, isNot(contains('不支援切換')));
      // Nothing to sync to: read it again with the panel's refresh icon.
      final read = connectionStatus(
        env: _custom,
        state: _state(_unconfirmed),
        probe: _healthy,
      );
      expect(read.need, SyncNeed.none);
      expect(read.hint, contains('「連線狀態」這一列最右邊的重新讀取圖示'));
      expect(read.hint, isNot(contains('右上角')));
      // Still being polled: no hint until the poll has had its chance.
      final polling = connectionStatus(
        env: _local,
        state: _state(_unconfirmed, watch: UploadWatch.polling),
        probe: _healthy,
      );
      expect(polling.gateway.status, '⏳ 確認中…');
      expect(polling.hint, isNull);
    });
    test('invalid local IP shows why and offers no 同步', () {
      for (final host in ['', 'mypc.local']) {
        final env = BackendEnvState(
          environment: BackendEnv.local,
          localHost: host,
          loaded: true,
        );
        final status = connectionStatus(
          env: env,
          state: _state(_target('production', connected: true)),
          probe: _healthy,
        );
        expect(status.need, SyncNeed.invalid, reason: host);
        expect(status.syncTarget, isNull);
        expect(status.hint, env.uploadTarget.error, reason: host);
        expect(status.hint, isNotNull);
        expect(status.allOk, isFalse);
      }
    });
    test('其他網址 the APP cannot map is shown as is, never as a match', () {
      final status = connectionStatus(
        env: _custom,
        state: _state(_target('production', connected: true), loggedIn: true),
        probe: _healthy,
      );
      expect(status.need, SyncNeed.none);
      expect(status.syncTarget, isNull);
      expect(status.phone.where, '其他網址');
      expect(status.gateway.where, '正式站');
      expect(status.gateway.status, '✓ 資料上傳中');
      expect(status.hint, contains('只顯示 Gateway 目前的設定，不會自動切換'));
      expect(status.allOk, isFalse);
    });
    test('the local host name never shows the port outside the details', () {
      const other = MqttTarget.local('192.168.1.187', port: 1883);
      expect(other.plainLabel, '本地測試主機（192.168.1.187）');
      final status = connectionStatus(
        env: _local,
        state: _state({
          ..._target('local', connected: false),
          'mqtt_port': 1883,
        }),
        probe: _healthy,
      );
      expect(status.need, SyncNeed.sync);
      expect(status.hint, isNot(contains('1883')));
      expect(status.hint, isNot(contains('8883')));
      expect(status.hint, contains('見技術細節'));
      expect(status.details.join('\n'), contains('192.168.1.187:1883'));
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
    test('marks a long wait without upload, and resets it', () async {
      final fake = NetGateway()..mqttConnected = false;
      final (container, c) = await _connected(
        fake,
        timing: const UploadWatchTiming(
          interval: Duration(milliseconds: 20),
          cap: Duration(seconds: 2),
          slowAfter: Duration(milliseconds: 100),
        ),
      );
      addTearDown(container.dispose);
      await _sleep(30);
      var s = container.read(commissionProvider);
      expect(s.uploadWatch, UploadWatch.polling);
      expect(s.uploadSlow, isFalse);
      await _sleep(200);
      s = container.read(commissionProvider);
      expect(s.uploadWatch, UploadWatch.polling);
      expect(s.uploadSlow, isTrue);
      // A new wait (e.g. after 重新讀取) starts over.
      await c.refreshUploadTarget();
      expect(container.read(commissionProvider).uploadSlow, isFalse);
      fake.mqttConnected = true;
      await _sleep(80);
      s = container.read(commissionProvider);
      expect(s.uploadWatch, UploadWatch.idle);
      expect(s.uploadSlow, isFalse);
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
      // One read for the network check at connect (1.7.x answers
      // get_net_status), but no upload polling.
      expect(fake.polls, 1);
      expect(container.read(commissionProvider).uploadWatch, UploadWatch.idle);
    });
  });

  group('backend switch on step 6/7', () {
    test('step 7: the old result is cleared, not kept as passed', () async {
      final fake = NetGateway();
      final (container, c) = await _verified(fake);
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.message, '開通驗證通過，已恢復自動監控');
      expect(s.online, isTrue);

      c.backendChanged(_otherBackend);
      s = container.read(commissionProvider);
      expect(s.loggedIn, isFalse);
      expect(s.online, isFalse);
      expect(s.message, backendSwitchedDoneText);
      // Without a login nothing is asked of the new backend.
      fake.paths.clear();
      await c.refreshHealth();
      expect(fake.paths, isEmpty);
      expect(
        container.read(commissionProvider).message,
        backendSwitchedDoneText,
      );

      // After logging in there the data is checked on that backend.
      await c.login(_otherBackend, 'pw');
      await c.refreshHealth();
      s = container.read(commissionProvider);
      expect(fake.logins.last, (_otherBackend, 'pw'));
      expect(s.loggedIn, isTrue);
      expect(s.error, isNull);
      expect(s.message, '資料持續更新');
      expect(s.online, isTrue);
      expect(fake.paths.last, startsWith('GET /api/latest'));
    });
    test('step 7: 重新連線並驗證 logs in with the given password', () async {
      final fake = NetGateway();
      final (container, c) = await _verified(fake);
      addTearDown(container.dispose);
      c.backendChanged(_otherBackend);
      await c.repair();
      expect(
        container.read(commissionProvider).error,
        const GatewayFailure('authentication').message,
      );
      await c.repair(base: _otherBackend, password: 'pw');
      final s = container.read(commissionProvider);
      expect(fake.logins.last, (_otherBackend, 'pw'));
      expect(s.error, isNull);
      expect(s.loggedIn, isTrue);
      expect(s.step, 3);
      expect(fake.paths.last, 'POST /api/gateways/1/1/commands');
    });
    test('a health answer from the old backend is dropped', () async {
      final fake = NetGateway();
      final (container, c) = await _verified(fake);
      addTearDown(container.dispose);
      fake.latestGate = Completer<void>();
      final health = c.refreshHealth();
      await _sleep(5);
      c.backendChanged(_otherBackend);
      fake.latestGate!.complete();
      await health;
      final s = container.read(commissionProvider);
      expect(s.message, backendSwitchedDoneText);
      expect(s.online, isFalse);
    });
    test('step 6: a result from the old backend is cleared', () async {
      final fake = NetGateway();
      SharedPreferences.setMockInitialValues({});
      fake.config['fleet_joined'] = true;
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(productionApiBase, 'secret');
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
      await c.configurePtus();
      c.backendChanged(_otherBackend);
      expect(
        container.read(commissionProvider).message,
        backendSwitchedVerifyText,
      );
      // Gateway still on 正式站: verification stops with a mismatch.
      await c.verify(_otherBackend, 'pw', environment: 'local');
      expect(container.read(commissionProvider).error, isNotNull);
      c.backendChanged(productionApiBase);
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.error, isNull);
      expect(s.message, backendSwitchedVerifyText);
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
    testWidgets('step 7 on 正式站 shows no shipping warning', (tester) async {
      await pumpPanel(
        tester,
        _state(_target('production', connected: true), step: 7, loggedIn: true),
        _production,
      );
      expect(find.text('✓ 正式站：手機與 Gateway 都已連上'), findsOneWidget);
      await tester.tap(find.text('✓ 正式站：手機與 Gateway 都已連上'));
      await tester.pumpAndSettle();
      expect(find.text(localTargetShipWarning), findsNothing);
      expect(find.textContaining('出貨前請切回正式站'), findsNothing);
      expect(find.text('手機和 Gateway 都切回正式站'), findsNothing);
    });
    testWidgets('unknown target: 同步 or refresh, never both', (tester) async {
      final calls = await pumpPanel(tester, _state(_unconfirmed), _local);
      expect(find.text('？ 未確認'), findsOneWidget);
      expect(find.textContaining('按「同步」'), findsOneWidget);
      expect(find.textContaining('重新讀取圖示'), findsNothing);
      await tester.tap(find.text('同步'));
      expect(calls, ['sync']);

      await pumpPanel(tester, _state(_unconfirmed), _custom);
      expect(find.text('？ 未確認'), findsOneWidget);
      expect(find.textContaining('重新讀取圖示（↻）'), findsOneWidget);
      expect(find.text('同步'), findsNothing);
    });
    testWidgets('invalid local IP: the reason, no 同步', (tester) async {
      const env = BackendEnvState(
        environment: BackendEnv.local,
        localHost: 'mypc.local',
        loaded: true,
      );
      await pumpPanel(
        tester,
        _state(_target('production', connected: true)),
        env,
      );
      expect(find.text(env.uploadTarget.error!), findsOneWidget);
      expect(find.text('同步'), findsNothing);
      expect(find.byKey(const Key('connection-status-ok')), findsNothing);
    });
    testWidgets('其他網址 that cannot be mapped is display only', (tester) async {
      await pumpPanel(
        tester,
        _state(_target('production', connected: true), loggedIn: true),
        _custom,
      );
      expect(find.byKey(const Key('connection-status-ok')), findsNothing);
      expect(find.text('其他網址'), findsOneWidget);
      expect(find.text('正式站'), findsOneWidget);
      expect(find.textContaining('不會自動切換'), findsOneWidget);
      expect(find.text('同步'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
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
