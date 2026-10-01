// Round 30 (user rehearsal 09-27, one-to-one, the owner as the installer;
// docs/test_results/user_rehearsal_0927/analysis.md):
// 1. P0 candidate A — help at step 5, the back office pressed 〔恢復上傳〕,
//    step 7 sent set_ble_enabled; step 8 then saw PTU connected, upload
//    on, BLE on, max_connections 1 and skipped set_config + join_fleet:
//    the firmware kept fleet_joined false (data watchdog off, no upload
//    after an OTA restart) while the APP and the back office said fine.
//    Now step 8 requires fleet_joined, and step 9 reads it again before
//    the done page (join_fleet sent once more; still false → no done
//    page, a retryable error).
// 2. C — set_wifi with the SSID the gateway was already on (MQTT up):
//    16 s without MQTT and a password asked on site. Now kept: no
//    set_wifi, no password, 〔改用其他 Wi-Fi〕 to change it.
// 3. D — 4 min 53 s choosing between two gateways: the list is ranked by
//    the phone's signal, the strongest marked 「最近（訊號最強）」, with
//    advice; two within 6 dB → 「兩台距離相近，請連線後按燈泡辨識確認」.
// 4. E — 「✓ 已連上後台；PTU 資料上傳暫停中…」 read as a fault (95 s
//    wait, a help request): says the pause is normal and to press next;
//    step 3's 「下一步：確認上線」 is in the bottom bar.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_proximity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/written_identities.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

import 'gateway_discovery_test.dart' show LiveLink;
import 'round15_direct_flow_test.dart' show PickGateway;
import 'support/pick_gateway.dart';

const _ownPtu = 'AA:BB:CC:00:00:01';
const _base = 'https://example.invalid';

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// Gateway 1 of the rehearsal: station 80/1 after leave_fleet (not in
/// service, BLE off, upload paused), on Wi-Fi Xiaomi_WU with MQTT up; its
/// own PTU at -43 dBm, the neighbours far below.
class _Gw1 extends PickGateway {
  _Gw1() : super(rssi: const [-43, -60, -72]) {
    config.addAll({
      'site_id': 80,
      'gateway_id': 1,
      'fleet_joined': false,
      'ble_enabled': false,
      'upload_paused': true,
      'max_connections': 1,
      'wifi_ssid': 'Xiaomi_WU',
    });
  }

  /// join_fleet acks ok but the gateway stays out of service.
  bool joinIgnored = false;
  bool rejectOnlineCheck = false;
  int rejectedOnlineChecks = 0;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'heartbeat_boost' && rejectOnlineCheck) {
      rejectedOnlineChecks++;
      throw const GatewayFailure.gateway('not_ready');
    }
    final before = config['fleet_joined'];
    final result = await super.command(op, params);
    if (op == 'join_fleet' && joinIgnored) config['fleet_joined'] = before;
    return result;
  }

  /// The back office's 〔恢復上傳〕 (set_data_upload over MQTT).
  void backOfficeResumesUpload() => config['upload_paused'] = false;

  int count(String op) => sent(op).length;
}

ProviderContainer _container(PickGateway fake) => ProviderContainer(
  overrides: [
    linkProvider.overrideWithValue(fake),
    apiProvider.overrideWithValue(fake),
  ],
);

class _IdentityGateway extends _Gw1 {
  String? reportedMac = _ownPtu;
  bool testModeAtFinish = false;
  bool testModeAfterJoin = false;
  int latestReads = 0;

  /// 09-28: the first [staleReads] /api/latest reads still return the row a
  /// replaced PTU uploaded before the swap (its MAC, an older timestamp).
  int staleReads = 0;
  final staleMac = 'AA:BB:CC:00:99:99';

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final result = await super.command(op, params);
    if (op == 'join_fleet' && testModeAfterJoin && latestReads >= 3) {
      config['mode'] = 'test';
      config['upload_paused'] = true;
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final result = await super.request(method, path, body);
    if (path.startsWith('/api/latest')) {
      latestReads++;
      for (final row in result['items'] as List) {
        if (latestReads <= staleReads) {
          row['ptu'] = {'ptu_mac_addr': staleMac};
          row['ts'] = DateTime(2029).toIso8601String();
        } else {
          row['ptu'] = {'ptu_mac_addr': reportedMac};
        }
      }
      if (testModeAtFinish && latestReads >= 3) config['mode'] = 'test';
      if (testModeAfterJoin && latestReads >= 3) config['fleet_joined'] = false;
    }
    return result;
  }
}

/// Connected, the network check passed: the station form.
Future<CommissioningController> _toStationForm(
  ProviderContainer container,
) async {
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.direct);
  await topo.setDirectBindOnConfirm(true);
  final c = container.read(commissionProvider.notifier);
  await c.prepare(_base, 'pw');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.passNetworkCheck();
  expect(container.read(commissionProvider).checkPassed, isTrue);
  return c;
}

/// The rehearsal up to step 7 (direct), the back office's 〔恢復上傳〕
/// pressed at step 5 as it was.
Future<CommissioningController> _toStep7(
  ProviderContainer container,
  _Gw1 fake,
) async {
  final c = await _toStationForm(container);
  await c.configureWifi(80, 1, 'Xiaomi_WU', '');
  expect(container.read(commissionProvider).error, isNull);
  fake.backOfficeResumesUpload();
  await c.online();
  final s = container.read(commissionProvider);
  expect(s.step, 4);
  expect(s.direct?.pickedMac, _ownPtu);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    keepPoll = directPollInterval;
    directPollInterval = const Duration(milliseconds: 1);
  });
  tearDown(() => directPollInterval = keepPoll);

  group('R27 verification identity and mode', () {
    test('test mode read after join blocks upload and completion', () async {
      final fake = _IdentityGateway()..testModeAfterJoin = true;
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStep7(container, fake);
      await c.identify();
      await c.confirmDirectPick();
      final uploads = fake.count('set_data_upload');
      await c.verify(_base, 'pw');
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.verified, isFalse);
      expect(s.testMode, isTrue);
      expect(fake.count('set_data_upload'), uploads);
    });
    for (final mac in <String?>[null, 'AA:BB:CC:00:99:99']) {
      test('missing or foreign MAC cannot complete: $mac', () async {
        final fake = _IdentityGateway()..reportedMac = mac;
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _toStep7(container, fake);
        await c.identify();
        await c.confirmDirectPick();
        await c.verify(_base, 'pw');
        var s = container.read(commissionProvider);
        expect(s.step, 6);
        expect(s.verified, isFalse);
        expect(s.error, contains('PTU 身分'));
        expect(s.verifyCounts, isEmpty);
        fake.reportedMac = 'aa-bb-cc-00-00-01';
        fake.latestReads = 0;
        await c.verify(_base, 'pw');
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.verified, isTrue);
        expect(fake.latestReads, greaterThanOrEqualTo(3));
      });
    }

    test('09-28: a replaced PTU last row (old MAC) in the first rounds '
        'is left out — neither counted nor a mismatch; the new PTU '
        'rows then pass', () async {
      final fake = _IdentityGateway()..staleReads = 2;
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStep7(container, fake);
      await c.identify();
      await c.confirmDirectPick();
      await c.verify(_base, 'pw');
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.verified, isTrue);
      expect(s.step, 7);
      // Two stale rounds, then three counted rows of the new PTU.
      expect(fake.latestReads, greaterThanOrEqualTo(5));
    });

    test('09-28: after a stale first round, a newer row with another MAC '
        'still fails', () async {
      final fake = _IdentityGateway()
        ..staleReads = 1
        ..reportedMac = 'AA:BB:CC:00:77:77';
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStep7(container, fake);
      await c.identify();
      await c.confirmDirectPick();
      await c.verify(_base, 'pw');
      final s = container.read(commissionProvider);
      expect(s.verified, isFalse);
      expect(s.error, contains('PTU 身分'));
      expect(s.verifyCounts, isEmpty);
      expect(fake.latestReads, 2, reason: 'failed on the first newer row');
    });

    for (final late in [false, true]) {
      test('test mode blocks completion, late=$late', () async {
        final fake = _IdentityGateway();
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _toStep7(container, fake);
        await c.identify();
        await c.confirmDirectPick();
        if (late) {
          fake.testModeAtFinish = true;
        } else {
          fake.config['mode'] = 'test';
        }
        await c.verify(_base, 'pw');
        final s = container.read(commissionProvider);
        expect(s.step, 6);
        expect(s.verified, isFalse);
        expect(s.error, contains('測試模式'));
      });
    }
  });

  group('1. P0 A: never done while the gateway is not in service', () {
    test('the back office resumed the upload first: step 8 still sends '
        'set_config + join_fleet, the done page has fleet_joined', () async {
      final fake = _Gw1();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStep7(container, fake);
      // As in the rehearsal: upload on, BLE on (step 7), PTU connected,
      // max_connections 1 — only fleet_joined is false.
      expect(fake.uploadPaused, isFalse);
      expect(fake.config['ble_enabled'], isTrue);
      expect(fake.config['fleet_joined'], isFalse);
      await c.identify();
      final joinsBefore = fake.count('join_fleet');
      final opsBefore = fake.ops.length;
      await c.confirmDirectPick();
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.count('join_fleet'), joinsBefore + 1);
      final step8 = fake.ops.sublist(opsBefore).map((e) => e.$1).toList();
      expect(
        step8.indexOf('set_config'),
        lessThan(step8.indexOf('join_fleet')),
        reason: 'set_config then join_fleet, as a gateway not monitored yet',
      );
      expect(fake.config['fleet_joined'], isTrue);
      await c.verify(_base, 'pw');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      expect(s.config['fleet_joined'], isTrue);
    });

    test('left the fleet after step 8: step 9 sends join_fleet again and '
        'reads it back before the done page', () async {
      final fake = _Gw1();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStep7(container, fake);
      await c.identify();
      await c.confirmDirectPick();
      expect(container.read(commissionProvider).step, 6);
      fake.config['fleet_joined'] = false;
      final joins = fake.count('join_fleet');
      await c.verify(_base, 'pw');
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(fake.count('join_fleet'), joins + 1);
      expect(fake.config['fleet_joined'], isTrue);
      expect(s.config['fleet_joined'], isTrue);
    });

    test('join_fleet does not take: no done page, a retryable error; '
        '開始資料驗證 again passes once it does', () async {
      final fake = _Gw1()..joinIgnored = true;
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStep7(container, fake);
      await c.identify();
      await c.confirmDirectPick();
      expect(container.read(commissionProvider).step, 6);
      final joins = fake.count('join_fleet');
      await c.verify(_base, 'pw');
      var s = container.read(commissionProvider);
      expect(s.step, 6, reason: 'no done page');
      expect(s.verified, isFalse);
      expect(s.error, fleetUnconfirmedText);
      expect(s.message, isNot(verifiedText));
      expect(fake.count('join_fleet'), joins + 1, reason: 'sent once more');
      expect(s.config['fleet_joined'], isFalse);
      expect(
        rescueCodeOf(
          const GatewayFailure('fleet_unconfirmed'),
          rebooted: false,
          safe: true,
          ctlStep: 6,
        ),
        RescueCode.monitorUnconfirmed,
      );
      // 「開始資料驗證」 again (the data progress is kept).
      fake.joinIgnored = false;
      await c.verify(_base, 'pw');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      expect(fake.config['fleet_joined'], isTrue);
    });
  });

  group('2. C: the Wi-Fi the gateway is already on is kept', () {
    CommissionState netState({
      String wifi = 'got_ip',
      bool mqtt = true,
      bool wifiOnly = false,
      String fw = '1.7.41',
    }) => CommissionState(
      step: 2,
      checkPassed: true,
      config: {
        'fw_version': fw,
        'wifi_ssid': 'Xiaomi_WU',
        'mqtt_connected': mqtt,
        'wifi_only': wifiOnly,
      },
      net: {'wifi_state': wifi, 'ssid': 'Xiaomi_WU', 'ip': '192.168.31.20'},
    );

    test('keptWifiSsid: joined with an IP and MQTT up only', () {
      expect(keptWifiSsid(netState()), 'Xiaomi_WU');
      expect(keptWifiSsid(netState(mqtt: false)), isNull);
      expect(keptWifiSsid(netState(wifi: 'connecting')), isNull);
      expect(keptWifiSsid(netState(wifiOnly: true)), isNull);
      expect(keptWifiSsid(netState(fw: '1.6.9')), isNull);
      expect(wifiKeptText('Xiaomi_WU'), '閘道器已連上 Xiaomi_WU，沿用');
    });

    test(
      'same SSID, MQTT up: no set_wifi, no password, MQTT not dropped',
      () async {
        final fake = _Gw1();
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _toStationForm(container);
        await c.configureWifi(80, 1, 'Xiaomi_WU', '');
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 3);
        expect(fake.sent('set_wifi'), isEmpty);
        expect(s.config['mqtt_connected'], isTrue);
        expect(s.message, wifiKeptDoneText('Xiaomi_WU'));
      },
    );

    test('another SSID: set_wifi with the password, as before', () async {
      final fake = _Gw1();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStationForm(container);
      await c.configureWifi(80, 1, 'Office-2G', 'password123');
      expect(container.read(commissionProvider).step, 3);
      expect(fake.sent('set_wifi'), [
        {'ssid': 'Office-2G', 'password': 'password123'},
      ]);
    });

    test('the kept Wi-Fi dropped by 儲存 and no password: asks for it, '
        'nothing sent', () async {
      final fake = _Gw1();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _toStationForm(container);
      fake.mqttConnected = false;
      await c.configureWifi(80, 1, 'Xiaomi_WU', '');
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.error, contains('請輸入 Wi-Fi 密碼'));
      expect(fake.sent('set_wifi'), isEmpty);
      expect(fake.sent('set_site_identity'), isEmpty);
      expect(keptWifiSsid(s), isNull, reason: 'the form asks again');
    });

    testWidgets('automatic online failure waits for explicit retry', (
      tester,
    ) async {
      final fake = _Gw1();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
            localBackendProberProvider.overrideWithValue(_Prober()),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(
        () => container.read(backendEnvProvider.notifier).ready,
      );
      await tester.runAsync(
        () => c.prepare(container.read(backendEnvProvider).base, 'pw'),
      );
      unawaited(c.scan());
      await tester.pumpAndSettle();
      unawaited(c.connect(container.read(commissionProvider).peers.single));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).checkPassed, isTrue);
      fake.rejectOnlineCheck = true;
      unawaited(c.configureWifi(80, 1, 'Xiaomi_WU', ''));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 3);
      expect(container.read(commissionProvider).error, isNotNull);
      expect(fake.rejectedOnlineChecks, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(fake.rejectedOnlineChecks, 1, reason: 'no automatic retry loop');
      fake.rejectOnlineCheck = false;
      await tester.tap(find.byKey(const Key('check-next')));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).error, isNull);
      expect(container.read(commissionProvider).step, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360x640: 「閘道器已連上 Xiaomi_WU，沿用」, no password field, '
        '〔改用其他 Wi-Fi〕; saved without set_wifi; then step 5 wording and '
        '「下一步：確認上線」 in the bottom bar', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = _Gw1();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
            localBackendProberProvider.overrideWithValue(_Prober()),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      await tester.runAsync(
        () => container.read(backendEnvProvider.notifier).ready,
      );
      await tester.runAsync(() async {
        final topology = container.read(topologyProvider.notifier);
        await topology.ready;
        await topology.setTopology(GatewayTopology.direct);
      });
      await tester.runAsync(
        () => container
            .read(commissionProvider.notifier)
            .prepare(container.read(backendEnvProvider).base, 'pw'),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      // 1.0.0+12: 80/1 was written by this phone a moment ago — only then
      // is a gateway not in service offered its station (else it is typed).
      await tester.runAsync(
        () => WrittenIdentities.remember(
          true,
          WrittenIdentity(
            uid: fake.config['gateway_uid'].toString(),
            peerId: 'demo-gateway',
            site: 80,
            gateway: 1,
            at: DateTime.now(),
          ),
        ),
      );
      // The gateway list: tap the gateway (fills the forms).
      await pickGateway(tap, find.byKey(const ValueKey('demo-gateway')));
      expect(container.read(commissionProvider).step, 2);
      expect(container.read(commissionProvider).checkPassed, isTrue);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('wifi-keep')))
            .textSpan!
            .toPlainText(),
        '✓ 閘道器已連上 Xiaomi_WU，沿用',
      );
      expect(find.widgetWithText(TextField, 'Wi-Fi 密碼'), findsNothing);
      expect(find.byKey(const Key('wifi-change')), findsOneWidget);
      expect(find.text('改用其他 Wi-Fi'), findsOneWidget);
      // 09-28: one question, 「目前站號是 80，這台要配置在本站嗎？」.
      expect(
        tester.widget<Text>(find.byKey(const Key('task-title'))).data,
        '目前站號是 80，這台要配置在本站嗎？',
      );
      await tap(find.text('使用此站點'));
      var now = container.read(commissionProvider);
      expect(now.error, isNull);
      expect(now.step, 4);
      expect(fake.sent('set_wifi'), isEmpty);
      // The online check and PTU search ran without another tap.
      expect(find.byKey(const Key('check-next')), findsNothing);
      expect(fake.sent('heartbeat_boost'), isNotEmpty);
      now = container.read(commissionProvider);
      expect(now.error, isNull);
      expect(now.step, 4);
      // Human identification remains mandatory, then the rest is automatic.
      expect(fake.count('join_fleet'), 0);
      await tap(find.text('辨識此樁'));
      await tap(find.text('是這台，開始配置'));
      now = container.read(commissionProvider);
      expect(now.error, isNull);
      expect(now.step, 7);
      expect(now.verified, isTrue);
      expect(now.config['fleet_joined'], isTrue);
      final joins = fake.count('join_fleet');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(fake.count('join_fleet'), joins);
      expect(tester.takeException(), isNull);
    });
  });

  group("3. D: the gateway list ranked by the phone's signal", () {
    final t0 = DateTime(2026, 9, 27, 20, 33);

    test('strongest first, a gateway not heard last; a clearly stronger '
        'one rises; old readings expire', () {
      final r = GatewaySignalRanker();
      r.add('gw2', -60, t0);
      r.add('gw1', -45, t0);
      expect(r.rank(['gw2', 'gw1', 'gw9'], t0), ['gw1', 'gw2', 'gw9']);
      final t1 = t0.add(const Duration(seconds: 2));
      r.add('gw2', -30, t1);
      r.add('gw2', -32, t1.add(const Duration(seconds: 1)));
      final t2 = t1.add(const Duration(seconds: 1));
      expect(r.strength('gw2', t2)!, closeTo(-40.67, 0.01));
      expect(r.rank(['gw2', 'gw1'], t2), [
        'gw2',
        'gw1',
      ], reason: '4.3 dB stronger on average: moves up');
      expect(r.strength('gw1', t0.add(const Duration(seconds: 30))), isNull);
    });

    test('reading noise within 3 dB does not reorder a known list', () {
      final r = GatewaySignalRanker();
      r.add('a', -50, t0);
      r.add('b', -52, t0);
      expect(r.rank(['a', 'b'], t0), ['a', 'b']);
      r.add('b', -47, t0.add(const Duration(seconds: 2)));
      // b: mean -49.5 vs a -50 — 0.5 dB: no swap.
      expect(r.rank(['a', 'b'], t0.add(const Duration(seconds: 2))), [
        'a',
        'b',
      ]);
    });

    test('nearest and close: within 6 dB → close; one heard → none', () {
      final r = GatewaySignalRanker();
      r.add('gw1', -45, t0);
      expect(r.nearest(['gw1'], t0), isNull);
      r.add('gw2', -50, t0);
      expect(r.nearest(['gw1', 'gw2'], t0), (nearest: 'gw1', close: true));
      final far = GatewaySignalRanker()
        ..add('gw1', -45, t0)
        ..add('gw2', -51, t0);
      expect(far.nearest(['gw2', 'gw1'], t0), (nearest: 'gw1', close: false));
      expect(validGatewayRssi(-127), isFalse);
      expect(validGatewayRssi(0), isFalse);
    });

    Future<LiveLink> pumpList(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final link = LiveLink();
      addTearDown(link.events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GatewayDiscovery(
                  enabled: true,
                  onConnect: (_) async {},
                  onIdentify: (_) async => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return link;
    }

    const gw1 = 'C8:F0:9E:4B:3A:02';
    const gw2 = 'A0:DD:6C:A3:70:F2';

    testWidgets('two gateways 3 dB apart: the stronger on top marked '
        '「最近（訊號最強）」, the advice and 「兩台距離相近」', (tester) async {
      final link = await pumpList(tester);
      // The neighbour (weaker) listed first by the scan.
      link.events.add([
        const GatewayPeer(gw2, 'GIOS-S80-GW02', -48),
        const GatewayPeer(gw1, 'GIOS-S80-GW01', -45),
      ]);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(gw1))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey(gw2))).dy),
      );
      expect(
        find.byKey(const ValueKey('gateway-nearest-$gw1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('gateway-nearest-$gw2')), findsNothing);
      expect(find.text(gatewayNearestLabel), findsOneWidget);
      expect(find.text(gatewayNearestHint), findsOneWidget);
      expect(gatewayNearestHint, contains('連線後按燈泡'));
      expect(find.byKey(const Key('gateway-close-hint')), findsOneWidget);
      expect(find.text('⚠ $gatewayCloseHint'), findsOneWidget);
      // The bulb the advice names (1.0.0+8: an icon with the tooltip;
      // 1.0.0+22: on the selected card alone, once its link is up — none
      // before a tap).
      expect(find.byTooltip('辨識閘道器'), findsNothing);
      expect(find.text('辨識閘道器'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('clearly apart (15 dB): marked and advised, no 「距離相近」; '
        'one gateway only: no mark', (tester) async {
      final link = await pumpList(tester);
      link.events.add([const GatewayPeer(gw2, 'GIOS-S80-GW02', -62)]);
      await tester.pump();
      expect(find.text(gatewayNearestLabel), findsNothing);
      expect(find.text(gatewayNearestHint), findsNothing);
      link.events.add([
        const GatewayPeer(gw2, 'GIOS-S80-GW02', -62),
        const GatewayPeer(gw1, 'GIOS-S80-GW01', -47),
      ]);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(gw1))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey(gw2))).dy),
      );
      expect(
        find.byKey(const ValueKey('gateway-nearest-$gw1')),
        findsOneWidget,
      );
      expect(find.text(gatewayNearestHint), findsOneWidget);
      expect(find.byKey(const Key('gateway-close-hint')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. E: step 5 says the pause is normal', () {
    test('the upload line: ✓ 後台連線正常…（目前暫停是正常的），請按下一步', () {
      final s = CommissionState(
        step: 2,
        config: const {
          'fw_version': '1.7.41',
          'fleet_joined': false,
          'upload_paused': true,
          'mqtt_target': 'production',
          'mqtt_connected': true,
          'wifi_ssid': 'Xiaomi_WU',
        },
        net: const {
          'wifi_state': 'got_ip',
          'ssid': 'Xiaomi_WU',
          'ip': '192.168.31.20',
        },
        wifiGraceOver: true,
      );
      final check = networkCheck(
        state: s,
        env: const BackendEnvState(loaded: true),
      );
      expect(
        check.upload.line,
        '✓ 後台連線正常。PTU 資料會在完成配置後自動開始上傳（目前暫停是正常的），APP 會自動繼續',
      );
      expect(check.upload.line, isNot(contains('暫停中')));
      expect(check.uploadOk, isTrue);
      expect(check.ready, isTrue, reason: '「下一步」 in the bottom bar');
    });
  });
}
