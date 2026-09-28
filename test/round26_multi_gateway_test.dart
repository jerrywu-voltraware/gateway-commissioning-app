// Round 26 (multi-gateway field test, two gateways side by side, an old
// gateway from another site):
// 1. P0 test mode: the gateway only generated test data and never scanned;
//    the APP said 「PTU 沒有回應」 and had no way out. It now reads the mode,
//    says so before anything else and offers 〔切回正常模式〕 (set_mode
//    normal → reboot → reconnect → carry on).
// 2. P0 upload paused: 「✓ 資料上傳中」 while the gateway's upload was
//    paused (0 rows). The real state is shown, 〔恢復上傳〕 sends
//    set_data_upload, and the done page re-checks the gateway itself.
// 3. Gateway names: 「站 80 · 閘道器 2」 + MAC tail + RSSI instead of two
//    「GIOS-S80-G…」 rows (360x640, text scale 1.3).
// 4. Another gateway is never a PTU: not in the star list (preselected in
//    the field) nor as the direct pick / candidates.
// 5. Backlog: a Wi-Fi reset goes back to the station choice; a gateway that
//    already carries an identity keeps it in the identity form.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/recent_gateways.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp, ready;

/// The two gateways of the field test (their Bluetooth MACs).
const _gw1 = 'C8:F0:9E:4B:3A:02';
const _gw2 = 'A0:DD:6C:A3:70:F2';

const _production = BackendEnvState(loaded: true);

const _fast = UploadWatchTiming(
  interval: Duration(milliseconds: 20),
  cap: Duration(seconds: 2),
  slowAfter: Duration(milliseconds: 100),
  confirmAfter: Duration(milliseconds: 200),
  wifiGrace: Duration(milliseconds: 1),
);

/// The old gateway of the field test: site 20 / gateway 1 in service,
/// optionally in test mode (scan refused as `scan failed: ESP_ERR_TIMEOUT`)
/// and / or with its upload paused. Records every command.
class OldGateway extends DemoSystem {
  OldGateway({
    bool station = true,
    bool testMode = false,
    bool paused = false,
  }) {
    config.addAll({
      if (station) ...{'fleet_joined': true, 'site_id': 20, 'gateway_id': 1},
      'mode': testMode ? 'test' : 'normal',
      'upload_paused': ?(paused ? true : null),
    });
  }

  final ops = <(String, Map<String, dynamic>)>[];

  /// Rows only scan_ble_discover reports (e.g. a neighbouring gateway).
  final scanExtra = <Map<String, dynamic>>[];

  /// set_data_upload is acked but the upload stays paused.
  bool ignoreResume = false;

  /// set_mode is acked but the gateway boots in test mode again.
  bool ignoreSetMode = false;

  List<Map<String, dynamic>> sent(String op) => [
    for (final (o, p) in ops)
      if (o == op) p,
  ];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    ops.add((op, Map.of(params)));
    if (rebooting) return super.command(op, params);
    if (op == 'scan_ble_discover' && config['mode'] == 'test') {
      throw const GatewayFailure.gateway('scan failed: ESP_ERR_TIMEOUT');
    }
    if (op == 'set_data_upload' && ignoreResume) {
      return {'upload_enabled': false, 'mqtt_connected': true};
    }
    if (op == 'set_mode' && ignoreSetMode) {
      rebooting = true;
      return {'message': 'mode switching to normal, rebooting...'};
    }
    final result = await super.command(op, params);
    if (op == 'scan_ble_discover') {
      return {
        'devices': [...result['devices'] as List, ...scanExtra],
      };
    }
    return result;
  }
}

Future<(ProviderContainer, CommissioningController)> _connected(
  DemoSystem fake, {
  GatewayTopology topology = GatewayTopology.star,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      uploadWatchTimingProvider.overrideWithValue(_fast),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(topology);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

Future<void> _sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

NetworkCheck _check(ProviderContainer container) =>
    networkCheck(state: container.read(commissionProvider), env: _production);

Map<String, dynamic> _row(String mac, int rssi, {String? name, int id = 0}) => {
  'mac': mac,
  'rssi': rssi,
  'device_number': id,
  'name': ?name,
  'connected': false,
  'notify_enabled': false,
  'zombie': false,
  'last_data_age_sec': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepSwitch, keepGap;
  setUp(() {
    keepPoll = directPollInterval;
    keepSwitch = directSwitchWait;
    keepGap = connectRetryGap;
    directPollInterval = const Duration(milliseconds: 1);
    directSwitchWait = const Duration(milliseconds: 60);
    connectRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    directSwitchWait = keepSwitch;
    connectRetryGap = keepGap;
  });

  group('3. gateway names', () {
    test('GIOS-S{site}-GW{nn} reads 站 · 閘道器, anything else stays whole', () {
      expect(parseGatewayName('GIOS-S80-GW02'), (site: 80, gateway: 2));
      expect(gatewayTitle('GIOS-S80-GW01'), '站 80 · 閘道器 1');
      expect(gatewayTitle('GIOS-S80-GW02'), '站 80 · 閘道器 2');
      expect(gatewayTitle('gios-s7-gw12'), '站 7 · 閘道器 12');
      // No identity yet / not the rule: the full name, never cut.
      expect(gatewayTitle('GIOS-S0-GW00'), 'GIOS-S0-GW00');
      expect(gatewayTitle('Some-Gateway-Name'), 'Some-Gateway-Name');
      expect(macTail(_gw2), '70F2');
      expect(macTailText(_gw1), 'MAC 後 4 碼 3A02');
      // Round 28: the Wi-Fi MAC (the back office's) is the one shown.
      expect(gatewayMacText(bleId: _gw1), 'MAC 後 4 碼 3A00（藍牙 3A02）');
      expect(macTail('C8F09E4B3A02'), '3A02');
      expect(macTail('demo-gateway'), isNull);
      expect(macTail('5E0C3D1A-8F2B-4C11-9E77-0123456789AB'), isNull);
      // The header follows the gateway's own config (a site change shows
      // at once, the advertised name may still be the old one).
      expect(
        gatewayHeaderText(
          name: 'GIOS-S20-GW01',
          id: _gw2,
          config: const {
            'site_id': 80,
            'gateway_id': 2,
            'fw_version': '1.7.36',
          },
        ),
        '站 80 · 閘道器 2 · MAC 後 4 碼 70F0 · 1.7.36',
      );
      expect(gatewayHeaderText(name: 'GIOS-S0-GW00', id: 'x'), 'GIOS-S0-GW00');
    });

    Future<void> pumpList(
      WidgetTester tester,
      _LiveLink link, {
      double scale = 1.3,
    }) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GatewayDiscovery(
                    enabled: true,
                    onConnect: (_) async {},
                    onIdentify: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('two gateways of one site are told apart at 360x640, 1.3', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final link = _LiveLink();
      addTearDown(link.events.close);
      await pumpList(tester, link);
      link.events.add(const [
        GatewayPeer(_gw2, 'GIOS-S80-GW02', -54),
        GatewayPeer(_gw1, 'GIOS-S80-GW01', -44),
      ]);
      await tester.pump();
      for (final (title, tail, rssi) in [
        // Round 28: the Wi-Fi tail (as the back office shows it), the
        // Bluetooth one in brackets.
        // 1.0.0+8: the compact tile shows the Wi-Fi MAC tail only.
        // 1.0.0+9: line 2 is one Text 「GIOS-S80-GW01 · …3A00 · 後端未知」.
        ('站 80 · 閘道器 1', '…3A00', '-44 dBm'),
        ('站 80 · 閘道器 2', '…70F0', '-54 dBm'),
      ]) {
        final text = find.text(title);
        expect(text, findsOneWidget);
        await tester.ensureVisible(text);
        await tester.pump();
        // Whole, not 「GIOS-S80-G…」.
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          tester.widget<Text>(text).overflow,
          isNot(TextOverflow.ellipsis),
        );
        expect(find.textContaining(tail), findsOneWidget);
        expect(find.text(rssi), findsOneWidget);
        // The row's title and MAC tail are inside the screen.
        expect(tester.getRect(text).right, lessThanOrEqualTo(360));
        expect(
          tester.getRect(find.textContaining(tail)).right,
          lessThanOrEqualTo(360),
        );
      }
      // The advertised names stay readable (and searchable) below.
      expect(find.textContaining('GIOS-S80-GW01'), findsOneWidget);
      expect(find.textContaining('GIOS-S80-GW02'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Rule 4: the gateways heard here are never PTUs.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayDiscovery)),
      );
      final c = container.read(commissionProvider.notifier);
      expect(c.knowsGateway(_gw1), isTrue);
      expect(c.knowsGateway(_gw2), isTrue);
      expect(c.knowsGateway('90:04:22:B6:96:00'), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a recent gateway shows the name it advertises now', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      // Remembered as 20/1; renamed to 80/2 since (field backlog 3).
      await tester.runAsync(
        () => RecentGateways.remember(
          true,
          const GatewayPeer(_gw2, 'GIOS-S20-GW01', -40),
          'A0DD6CA370F0',
        ),
      );
      final link = _LiveLink();
      addTearDown(link.events.close);
      await pumpList(tester, link);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      link.events.add(const [GatewayPeer(_gw2, 'GIOS-S80-GW02', -45)]);
      await tester.pump();
      expect(find.text('站 80 · 閘道器 2'), findsOneWidget);
      expect(find.text('站 20 · 閘道器 1'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. another gateway is not a PTU', () {
    test('rules: gateway names, known MACs, direct report', () {
      expect(isGatewayName('GIOS-S20-GW01'), isTrue);
      expect(isGatewayName('gios-s80-gw02'), isTrue);
      expect(isGatewayName('GIOS-S80'), isTrue, reason: 'gateway prefix');
      expect(isGatewayName('GIOS0403ST'), isFalse);
      expect(isGatewayName('GIOS0801ST'), isFalse);
      expect(isGatewayName(null), isFalse);
      final split = splitGatewayRows([
        _row('90:04:22:B6:96:00', -45, name: 'GIOS0801ST'),
        _row(_gw2, -7, name: 'GIOS-S20-GW01'),
        _row(_gw1, -12),
      ], (mac) => gatewayMacKey(mac) == gatewayMacKey(_gw1));
      expect(split.ptus.map((r) => r['mac']), ['90:04:22:B6:96:00']);
      expect(split.gateways.map((r) => r['mac']), [_gw2, _gw1]);

      final clean = directWithoutGateways({
        'state': 'connected',
        'select_reason': 'ok',
        'ptu_mac': _gw2,
        'ptu_rssi': -7,
        'ptu_device_number': 0,
        'candidates': [
          {'mac': _gw2, 'rssi_peak': -7},
          {'mac': '90:2C:00:54:96:00', 'rssi_peak': -42},
        ],
        'neighbors': [
          {'mac': _gw2, 'rssi_peak': -7},
        ],
      }, (mac) => gatewayMacKey(mac) == gatewayMacKey(_gw2));
      final direct = DirectStatus.from(clean.direct)!;
      expect(direct.pickedMac, isNull);
      expect(direct.state, DirectState.noCandidate);
      expect(direct.candidates.map((c) => c.mac), ['90:2C:00:54:96:00']);
      expect(direct.neighbors, isEmpty);
      expect(clean.pickedGateway, _gw2);
      expect(isDirectGatewayPickText(directGatewayPickText(_gw2)), isTrue);
      expect(isDirectGatewayPickText(directSwitchedText(_gw2)), isFalse);
    });

    test('star list: a neighbouring gateway is neither listed nor '
        'preselected (field m40 / m47)', () async {
      final fake = OldGateway()
        ..scanExtra.addAll([
          // Named like a gateway (firmware before 1.7.38 lists it).
          _row(_gw1, -12, name: 'GIOS-S80-GW01'),
          // No name, but the phone's gateway list heard this MAC.
          _row(_gw2, -7, name: ''),
        ]);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      c.noteGatewayPeers(const [GatewayPeer(_gw2, 'GIOS-S80-GW02', -50)]);
      await c.chooseStation(newStation: false);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 4);
      final macs = s.ptus.map((p) => p['mac']).toList();
      expect(macs, isNot(contains(_gw1)));
      expect(macs, isNot(contains(_gw2)));
      expect(s.ptus, hasLength(3));
      expect(s.selected, {for (final d in fake.devices) d['mac']});
      expect(s.scannedTotal, 3);
      expect(c.knowsGateway(_gw1), isTrue, reason: 'remembered for direct');
    });

    test('direct: the gateway picking a neighbouring gateway is no pick; '
        '「不是這台？」 lists only PTUs and switches to one (field m43)', () async {
      final fake = OldGateway();
      fake.devices.insert(0, _row(_gw2, -7));
      final (container, c) = await _connected(
        fake,
        topology: GatewayTopology.direct,
      );
      addTearDown(container.dispose);
      c.noteGatewayPeers(const [GatewayPeer(_gw2, 'GIOS-S80-GW02', -50)]);
      await c.chooseStation(newStation: false);
      var s = container.read(commissionProvider);
      expect(c.directFlow, isTrue);
      expect(
        fake.devices.firstWhere((d) => d['mac'] == _gw2)['connected'],
        isTrue,
        reason: 'old firmware connects it',
      );
      expect(s.direct!.pickedMac, isNull);
      expect(s.ptus, isEmpty);
      expect(s.selected, isEmpty);
      expect(directConfirmReady(s), isFalse);
      expect(s.directNotice, directGatewayPickText(_gw2));
      expect(s.direct!.candidates.map((c) => c.mac), isNot(contains(_gw2)));
      expect(s.direct!.candidates, isNotEmpty);

      final ptu = fake.devices[1]['mac'] as String;
      await c.switchDirectPick(ptu);
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.direct!.pickedMac, ptu);
      expect(s.ptus.single['mac'], ptu);
      expect(isDirectGatewayPickText(s.directNotice), isFalse);
    });
  });

  group('1. test mode', () {
    test('failures a gateway in test mode explains', () {
      expect(
        testModeExplains(
          const GatewayFailure.gateway('scan failed: ESP_ERR_TIMEOUT'),
        ),
        isTrue,
      );
      expect(testModeExplains(const GatewayFailure('timeout')), isTrue);
      expect(testModeExplains(const GatewayFailure('no_devices')), isTrue);
      expect(
        testModeExplains(const GatewayFailure('phone_link_lost')),
        isFalse,
      );
      expect(testModeExplains(const GatewayFailure('cancelled')), isFalse);
      expect(
        testModeExplains(const GatewayFailure.gateway('otp_required')),
        isFalse,
      );
      expect(testModeExplains(const GatewayFailure.gateway('busy')), isFalse);
      expect(const GatewayFailure('test_mode').message, testModeText);
      expect(testModeText, contains('測試模式'));
      expect(testModeText, contains('只產生測試資料、不會連 PTU'));
      expect(testModeText, contains('需切回正常模式'));
    });

    test('connected: said at once, nothing goes on until switched back; '
        '〔切回正常模式〕 reboots, reconnects and continues', () async {
      final fake = OldGateway(testMode: true);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await _sleep(60);
      var s = container.read(commissionProvider);
      expect(s.testMode, isTrue);
      var check = _check(container);
      expect(check.upload.line, '⚠ $testModeUploadText');
      expect(check.uploadOk, isFalse);
      expect(check.testMode, isTrue);
      expect(check.canSkip, isFalse);
      expect(check.reuseBlockedReason, '閘道器在測試模式');
      expect(
        connectionStatus(env: _production, state: s).gateway.status,
        '⚠ 測試模式',
      );

      await c.passNetworkCheck();
      s = container.read(commissionProvider);
      expect(s.error, testModeText);
      expect(s.checkPassed, isFalse);
      await c.passNetworkCheck(skip: true);
      expect(container.read(commissionProvider).checkPassed, isFalse);
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.error, testModeText);
      expect(s.step, 2);
      expect(fake.sent('scan_ble_discover'), isEmpty);

      await c.leaveTestMode();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.sent('set_mode'), [
        {'mode': 'normal'},
      ]);
      expect(fake.connects, 2, reason: 'reconnected after the reboot');
      expect(s.testMode, isFalse);
      expect(s.config['mode'], 'normal');
      expect(s.message, leftTestModeText);
      await _sleep(60);
      expect(_check(container).ready, isTrue);
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 4);
      expect(s.ptus, hasLength(3));
    });

    test('step 7: 「PTU 沒有回應」 is replaced by the test mode, rescans do '
        'not scan, the switch rescans by itself', () async {
      final fake = OldGateway();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.chooseStation(newStation: false);
      expect(container.read(commissionProvider).step, 4);
      // Switched to test mode behind the APP's back (old gateway / back
      // office): the scan fails as in the field.
      fake.config['mode'] = 'test';
      await c.discover();
      var s = container.read(commissionProvider);
      expect(s.error, testModeText);
      expect(s.error, isNot(contains('PTU 沒有回應')));
      expect(s.errorDetail, contains('scan failed: ESP_ERR_TIMEOUT'));
      expect(s.testMode, isTrue);
      expect(s.message, contains(leaveTestModeLabel));
      final scans = fake.sent('scan_ble_discover').length;
      await c.discover();
      s = container.read(commissionProvider);
      expect(s.error, testModeText);
      expect(
        fake.sent('scan_ble_discover'),
        hasLength(scans),
        reason: 'known test mode: no scan that can only fail',
      );

      await c.leaveTestMode();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.testMode, isFalse);
      expect(fake.sent('scan_ble_discover'), hasLength(scans + 1));
      expect(s.step, 4);
      expect(s.ptus, hasLength(3));
    });

    test('back office switched it already: no change, no reboot', () async {
      final fake = OldGateway(testMode: true);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      fake.config['mode'] = 'normal';
      await c.leaveTestMode();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.testMode, isFalse);
      expect(fake.connects, 1);
    });

    test('still in test mode after the reboot: says so, card stays', () async {
      final fake = OldGateway(testMode: true)..ignoreSetMode = true;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.leaveTestMode();
      final s = container.read(commissionProvider);
      expect(s.error, const GatewayFailure('test_mode_stuck').message);
      expect(s.error, contains(leaveTestModeLabel));
      expect(s.testMode, isTrue);
    });

    test('direct flow: no pick is awaited in test mode', () async {
      final fake = OldGateway();
      final (container, c) = await _connected(
        fake,
        topology: GatewayTopology.direct,
      );
      addTearDown(container.dispose);
      await c.chooseStation(newStation: false);
      expect(container.read(commissionProvider).step, 4);
      final configs = fake.sent('set_config').length;
      fake.config['mode'] = 'test';
      await c.discover();
      final s = container.read(commissionProvider);
      expect(s.error, testModeText);
      expect(s.testMode, isTrue);
      expect(fake.sent('set_config'), hasLength(configs));
    });
  });

  group('2. upload paused', () {
    CommissionState paused({bool joined = true, bool? upload = true}) =>
        CommissionState(
          step: 2,
          peer: const GatewayPeer(_gw2, 'GIOS-S20-GW01', -40),
          config: {
            'fw_version': '1.7.36',
            'fleet_joined': joined,
            'upload_paused': ?upload,
            'mqtt_target': 'production',
            'mqtt_host': demoProductionMqttHost,
            'mqtt_port': 8883,
            'mqtt_connected': true,
            'wifi_ssid': 'Xiaomi_WU',
          },
          net: const {
            'wifi_state': 'got_ip',
            'ssid': 'Xiaomi_WU',
            'ip': '192.168.0.50',
            'rssi': -50,
          },
          wifiGraceOver: true,
        );

    test('network check and status panel show the real upload', () {
      final check = networkCheck(state: paused(), env: _production);
      expect(check.upload.line, '⚠ $uploadPausedText');
      expect(check.upload.line, isNot(contains('資料上傳中')));
      expect(check.uploadOk, isFalse);
      expect(check.uploadPaused, isTrue);
      expect(check.reuseBlockedReason, '閘道器的資料上傳已暫停');
      final status = connectionStatus(env: _production, state: paused());
      expect(status.gateway.status, '⚠ 上傳已暫停');
      expect(status.hint, uploadPausedStatusHint);
      expect(status.summary, isNull);
      expect(status.details, contains('資料上傳：已暫停'));
      // A heartbeat the back office saw is no upload either.
      final seen = connectionStatus(
        env: _production,
        state: paused().copy(backendSeenAt: DateTime.now()),
      );
      expect(seen.gateway.status, '⚠ 上傳已暫停');
      // Uploading: as before.
      final on = paused(upload: false);
      expect(networkCheck(state: on, env: _production).upload.line, '✓ 資料上傳中');
      expect(
        connectionStatus(env: _production, state: on).gateway.status,
        '✓ 資料上傳中',
      );
      // Not in service yet: paused on purpose until 開始監控 (join_fleet).
      // Round 28 (field: pile B read 「✓ 資料上傳中」): not a problem, but
      // never 「資料上傳中」 either.
      final fresh = paused(joined: false);
      expect(fresh.uploadPaused, isFalse);
      final freshCheck = networkCheck(state: fresh, env: _production);
      expect(freshCheck.upload.line, '✓ $uploadHeldText');
      expect(freshCheck.uploadOk, isTrue);
      expect(
        connectionStatus(env: _production, state: fresh).gateway.status,
        uploadHeldStatus,
      );
    });

    test('沿用 is held until 〔恢復上傳〕; the resume is read back', () async {
      final fake = OldGateway(paused: true);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await _sleep(60);
      var s = container.read(commissionProvider);
      expect(s.uploadPaused, isTrue);
      expect(_check(container).upload.line, '⚠ $uploadPausedText');
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.error, uploadPausedText);
      expect(s.step, 2);
      expect(fake.sent('scan_ble_discover'), isEmpty);

      await c.resumeUpload();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.sent('set_data_upload'), [
        {'enabled': true},
      ]);
      expect(s.uploadPaused, isFalse);
      expect(s.uploadNotice, uploadResumedText);
      expect(_check(container).upload.line, '✓ 資料上傳中');
      await c.chooseStation(newStation: false);
      expect(container.read(commissionProvider).step, 4);
    });

    test('a resume the gateway does not take is an error, not 上傳中', () async {
      final fake = OldGateway(paused: true)..ignoreResume = true;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.resumeUpload();
      final s = container.read(commissionProvider);
      expect(s.error, const GatewayFailure('upload_paused').message);
      expect(s.error, contains(resumeUploadLabel));
      expect(s.uploadPaused, isTrue);
    });

    test('Wi-Fi reset of a paused station: the station choice waits for '
        'the resume', () async {
      final fake = OldGateway(paused: true)..simulateWifi('disconnected');
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.startWifiFix();
      await c.configureWifi(20, 1, 'Xiaomi_WU', 'password123');
      await _sleep(80);
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.config['wifi_only'], isTrue);
      expect(s.networkReady, isTrue);
      await c.passNetworkCheck();
      s = container.read(commissionProvider);
      expect(s.error, uploadPausedText);
      expect(s.checkPassed, isFalse);
      await c.resumeUpload();
      await c.passNetworkCheck();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      // Backlog: back to the station choice, not straight to the scan.
      expect(s.step, 2);
      expect(s.checkPassed, isTrue);
      expect(s.config['choose_station'], isTrue);
      expect(s.message, wifiUpdatedChooseStationText);
      expect(fake.sent('scan_ble_discover'), isEmpty);
    });

    test('done page: the gateway paused since is resumed before 完成; '
        'one that stays paused is never shown as 上傳中', () async {
      for (final resumes in [true, false]) {
        final fake = _VerifyLink()..ignoreResume = !resumes;
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        await c.configurePtus();
        expect(container.read(commissionProvider).step, 6);
        // Paused after monitoring started; the back office has not seen it.
        fake.config['upload_paused'] = true;
        await c.verify('https://example.invalid', '');
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 7);
        expect(fake.sent('set_data_upload'), [
          {'enabled': true},
        ]);
        final status = connectionStatus(env: _production, state: s);
        if (resumes) {
          expect(fake.config['upload_paused'], isFalse);
          expect(s.uploadPaused, isFalse);
          expect(status.gateway.status, '✓ 資料上傳中');
        } else {
          expect(s.uploadPaused, isTrue);
          expect(status.gateway.status, '⚠ 上傳已暫停');
          expect(status.gateway.status, isNot(contains('上傳中')));
        }
      }
    });
  });

  group('5. backlog', () {
    test(
      'a gateway renamed a moment ago keeps its identity in the form',
      () async {
        final fake = OldGateway(station: false);
        fake.config.addAll({'site_id': 80, 'gateway_id': 2});
        final (container, _) = await _connected(fake);
        addTearDown(container.dispose);
        final s = container.read(commissionProvider);
        expect(s.config['suggested_site_id'], 80);
        expect(s.config['suggested_gateway_id'], 2);
      },
    );
  });

  group('pages at 360x640, text scale 1.3', () {
    Future<(ProviderContainer, CommissioningController)> open(
      WidgetTester tester,
      OldGateway fake,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await pumpApp(tester, fake, size: const Size(360, 640));
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(() async {
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
      });
      await tester.pumpAndSettle();
      return (container, c);
    }

    Future<void> idle(WidgetTester tester, ProviderContainer container) async {
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 400 && container.read(commissionProvider).busy;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
    }

    testWidgets('test mode: the card with its button comes first; the '
        'switch clears it', (tester) async {
      final fake = OldGateway(testMode: true);
      final (container, _) = await open(tester, fake);
      final header = find.byKey(const Key('gateway-header'));
      final list = find.byType(Scrollable).first;
      // 09-28: the gateway's name and MAC are in 「設備與連線資訊」.
      final details = find.text('設備與連線資訊');
      await tester.scrollUntilVisible(details, 120, scrollable: list);
      await tester.tap(details);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(header, 120, scrollable: list);
      expect(tester.widget<Text>(header).data, startsWith('站 20 · 閘道器 1'));
      final card = find.byKey(const Key('test-mode-card'));
      // The details are below the card: back up.
      await tester.scrollUntilVisible(card, -120, scrollable: list);
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      // Before the network check (right under the gateway header).
      final upload = find.byKey(const Key('check-upload'));
      if (upload.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(card).dy,
          lessThan(tester.getTopLeft(upload).dy),
        );
      }
      expect(find.text(testModeText), findsOneWidget);
      final button = find.byKey(const Key('test-mode-action'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(find.text(leaveTestModeLabel), findsWidgets);
      expect(tester.getRect(button).right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
      await tester.tap(button);
      await tester.pump();
      await idle(tester, container);
      expect(fake.sent('set_mode'), [
        {'mode': 'normal'},
      ]);
      expect(find.byKey(const Key('test-mode-card')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('upload paused: 〔恢復上傳〕 under the upload item', (tester) async {
      final fake = OldGateway(paused: true);
      final (container, _) = await open(tester, fake);
      await idle(tester, container);
      final upload = find.byKey(const Key('check-upload'));
      await tester.scrollUntilVisible(
        upload,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<Text>(upload).textSpan!.toPlainText(),
        '⚠ $uploadPausedText',
      );
      final resume = find.byKey(const Key('check-resume-upload'));
      await tester.ensureVisible(resume);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(resume);
      await tester.pump();
      await idle(tester, container);
      expect(fake.sent('set_data_upload'), [
        {'enabled': true},
      ]);
      expect(container.read(commissionProvider).uploadPaused, isFalse);
      expect(find.byKey(const Key('check-resume-upload')), findsNothing);
    });

    testWidgets('step 7 in test mode: the bottom button switches it back', (
      tester,
    ) async {
      final fake = OldGateway();
      final (container, c) = await open(tester, fake);
      await tester.runAsync(() => c.chooseStation(newStation: false));
      await tester.pumpAndSettle();
      fake.config['mode'] = 'test';
      await tester.runAsync(() => c.discover());
      await tester.pumpAndSettle();
      final bottom = find.byKey(const Key('ptu-configure'));
      expect(bottom, findsOneWidget);
      expect(
        find.descendant(of: bottom, matching: find.text(leaveTestModeLabel)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(bottom);
      await tester.pump();
      await idle(tester, container);
      final s = container.read(commissionProvider);
      expect(s.testMode, isFalse);
      expect(s.error, isNull);
      expect(s.ptus, hasLength(3));
    });
  });
}

class _LiveLink extends DemoSystem implements GatewayScanner {
  final events = StreamController<List<GatewayPeer>>();
  @override
  Stream<List<GatewayPeer>> scanLive() => events.stream;
  @override
  Future<void> stopScan() async {}
}

/// Step 9 of [ready]: the back office's fleet row does not carry the
/// gateway's `upload_paused` (stale), so only the gateway itself tells.
class _VerifyLink extends DroppingLink {
  bool ignoreResume = false;
  final ops = <(String, Map<String, dynamic>)>[];

  List<Map<String, dynamic>> sent(String op) => [
    for (final (o, p) in ops)
      if (o == op) p,
  ];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    ops.add((op, Map.of(params)));
    if (op == 'set_data_upload' && ignoreResume) {
      return {'upload_enabled': false, 'mqtt_connected': true};
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final result = await super.request(method, path, body);
    if (path.contains('fleet-status')) {
      for (final row in (result['gateways'] as List? ?? const [])) {
        (row as Map).remove('upload_paused');
      }
    }
    return result;
  }
}
