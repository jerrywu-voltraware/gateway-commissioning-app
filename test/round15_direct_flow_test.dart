// Round 15 (after field round 14, firmware 1.7.21):
// 1. Direct mode, firmware with `direct_autoconnect_supported`: step 7 sets
//    max_connections 1 at once and shows the PTU the gateway itself picked
//    (MAC / RSSI / select_reason); 「辨識此樁」 note beside the button;
//    「是這台，開始監控」 numbers exactly that MAC #1 (round 14: the APP
//    preselected another PTU, waited 98 s and two PTUs ended up #1).
// 2. ambiguous → yellow hint; 「不是這台？」 → candidate → temporary binding
//    → the gateway switches (binding kept, named on the done page).
// 3. no_candidate / bound_missing → hint and 「重新搜尋」; older firmware
//    keeps the list flow.
// 4. Star step 7 idle link loss: automatic retries (5/10/20 s) before the
//    manual 「重新連線並繼續」.
// 5. A failed get_ble_devices ends 「掃描中…」 with 「重新掃描」.
// 6. Step 9: the backend retry line sits above the per-PTU progress.
// 7. A finished run is not overwritten by a later connect (「上次配置已完成」).
// 8. Round 15b: 「是這台」 only numbers the PTU the installer identified
//    (identify ack MAC, re-checked against get_status); a temporary
//    「不是這台？」 binding is cleared on 取消 (「確認後綁定」 off) and a
//    leftover binding found on entering step 7 asks 「保留」/「解除」.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'link_loss_test.dart' show DroppingLink, ready;
import 'round13_fixes_test.dart' show Round13Link, atStep9;

/// Listed first by the gateway, but not its pick.
const _first = 'AA:BB:CC:00:00:01';

/// The gateway's own pick (strongest).
const _pick = 'AA:BB:CC:00:00:02';

const _newKeys = [
  'direct_autoconnect_supported',
  'identify_ptu_supported',
  'auto_connect_min_rssi',
  'direct_bind_mac',
];

/// Firmware 1.7.21 gateway 3 of site 80, star (max 5) before step 7,
/// recording every command. The demo simulates the direct-mode pick.
class PickGateway extends DemoSystem {
  PickGateway({
    bool newFirmware = true,
    List<int> rssi = const [-50, -38, -60],
  }) {
    config.addAll({
      'fleet_joined': true,
      'site_id': 80,
      'gateway_id': 3,
      'max_connections': 5,
    });
    for (final (i, d) in devices.indexed) {
      d['rssi'] = rssi[i];
    }
    if (!newFirmware) {
      for (final key in _newKeys) {
        config.remove(key);
      }
    }
  }

  final ops = <(String, Map<String, dynamic>)>[];

  List<Map<String, dynamic>> sent(String op) => [
    for (final (o, p) in ops)
      if (o == op) p,
  ];

  int indexOf(String op, [bool Function(Map<String, dynamic>)? where]) =>
      ops.indexWhere((e) => e.$1 == op && (where == null || where(e.$2)));

  Map<String, dynamic> device(String mac) =>
      devices.firstWhere((d) => d['mac'] == mac);

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    ops.add((op, Map.of(params)));
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _toStep7(
  PickGateway fake, {
  GatewayTopology topology = GatewayTopology.direct,
  bool bindOnConfirm = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(topology);
  await topo.setDirectBindOnConfirm(bindOnConfirm);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  return (container, c);
}

Widget _panel(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [DirectStatusPanel(), DirectPickActions()]),
      ),
    ),
  ),
);

Future<void> _idle(WidgetTester tester, ProviderContainer container) =>
    tester.runAsync(() async {
      for (var i = 0; i < 200 && container.read(commissionProvider).busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepGap, keepBackendGap;
  late List<Duration> keepGaps;
  setUp(() {
    keepPoll = directPollInterval;
    keepGaps = step7RetryGaps;
    keepGap = connectRetryGap;
    keepBackendGap = backendRetryGap;
    directPollInterval = const Duration(milliseconds: 1);
    step7RetryGaps = const [
      Duration(milliseconds: 1),
      Duration(milliseconds: 2),
      Duration(milliseconds: 3),
    ];
    connectRetryGap = const Duration(milliseconds: 1);
    backendRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    step7RetryGaps = keepGaps;
    connectRetryGap = keepGap;
    backendRetryGap = keepBackendGap;
  });

  group('1. direct flow: the gateway picks, the APP confirms', () {
    test('step 7 enters direct mode at once and shows only the gateway pick; '
        'identify → 是這台 numbers exactly that MAC #1', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(c.directFlow, isTrue);
      expect(s.step, 4);
      // Direct mode set on entering step 7, no APP-side scan list.
      expect(fake.sent('set_config').first, {'max_connections': 1});
      expect(fake.sent('scan_ble_discover'), isEmpty);
      expect(s.direct!.pickedMac, _pick);
      expect(s.direct!.selectReason, 'ok');
      expect(s.selected, {_pick});
      expect(s.ptus.single['mac'], _pick);
      expect(s.message, contains('辨識此樁'));

      await c.identify();
      s = container.read(commissionProvider);
      expect(fake.sent('identify').last, {'target': 'both'});
      expect(s.identifyNote, startsWith(identifySentText));
      expect(s.identifyNote, contains(_pick));
      expect(s.identifyNote, contains('-38 dBm'));

      await c.confirmDirectPick();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.sent('assign_device_id'), [
        {'mac': _pick, 'new_id': directPtuId},
      ]);
      expect(
        fake.indexOf('set_config', (p) => p['max_connections'] == 1),
        lessThan(fake.indexOf('assign_device_id')),
      );
      expect(fake.sent('join_fleet'), hasLength(1));
      // Binding setting off: nothing bound.
      expect(
        fake.sent('set_config').where((p) => p.containsKey('direct_bind_mac')),
        isEmpty,
      );
      // Only the gateway's PTU carries #1 (round 14: two PTUs were #1).
      expect(fake.device(_pick)['device_number'], 1);
      expect(fake.devices.where((d) => d['device_number'] == 1), hasLength(1));
      expect(fake.device(_first)['device_number'], 0);
    });

    test('「確認後綁定 PTU」 on: 是這台 also binds that MAC before join_fleet', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake, bindOnConfirm: true);
      addTearDown(container.dispose);
      // Round 15b: 是這台 needs 辨識此樁 first.
      await c.identify();
      await c.confirmDirectPick();
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(
        fake.sent('set_config'),
        anyElement(equals({'direct_bind_mac': _pick})),
      );
      expect(
        fake.indexOf('set_config', (p) => p['direct_bind_mac'] == _pick),
        lessThan(fake.indexOf('join_fleet')),
      );
      expect(directBoundNote(s), contains(_pick));
    });

    test(
      'identified A, the gateway switched to B before 是這台 (seen by the '
      're-read): nothing assigned, identification dropped, yellow notice',
      () async {
        final fake = PickGateway();
        final (container, c) = await _toStep7(fake);
        addTearDown(container.dispose);
        await c.identify();
        expect(container.read(commissionProvider).identifiedMac, _pick);
        // The gateway lost _pick and connected _first meanwhile.
        fake.device(_pick)['connected'] = false;
        fake.device(_first)['connected'] = true;
        await c.confirmDirectPick();
        final s = container.read(commissionProvider);
        expect(s.step, 4);
        expect(s.error, isNull);
        expect(fake.sent('assign_device_id'), isEmpty);
        expect(fake.sent('join_fleet'), isEmpty);
        expect(s.selected, {_first});
        expect(s.identifiedMac, isNull);
        expect(s.directNotice, directSwitchedText(_first));
        expect(s.directNotice, contains('MAC 後 4 碼 0001'));
        expect(directConfirmReady(s), isFalse);
      },
    );

    test('new gateway: 確認上線 enters step 7 and asks for the pick by itself; '
        'BLE left off by a new identity is switched on', () async {
      final fake = PickGateway()..config['fleet_joined'] = false;
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(topologyProvider.notifier)
          .setTopology(GatewayTopology.direct);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.configureWifi(80, 3, 'Office-2G', 'password123');
      fake.config['ble_enabled'] = false;
      await c.online(skip: true);
      final s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(fake.sent('set_ble_enabled'), [
        {'enabled': true},
      ]);
      expect(s.direct!.pickedMac, _pick);
      expect(s.selected, {_pick});
    });

    testWidgets('bottom bar: 辨識此樁 note beside the button, then 是這台', (
      tester,
    ) async {
      final fake = PickGateway();
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_panel(container));
      expect(find.byKey(const Key('direct-linked')), findsOneWidget);
      expect(find.text(_pick), findsOneWidget);
      expect(find.textContaining('門檻內訊號明顯最強'), findsOneWidget);
      expect(find.byKey(const Key('direct-ambiguous')), findsNothing);
      // No list to tick: candidates only under 「不是這台？」.
      expect(
        find.byKey(const ValueKey('direct-candidate-$_first')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('direct-identify')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      final note = tester.widget<Text>(
        find.byKey(const Key('direct-identify-note')),
      );
      expect(note.data, contains(identifySentText));
      expect(note.data, contains(_pick));
      expect(find.text('是這台，開始監控'), findsOneWidget);
    });
  });

  group('2. ambiguous and 不是這台？', () {
    testWidgets('ambiguous: yellow hint to identify', (tester) async {
      final fake = PickGateway(rssi: [-40, -43, -70]);
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.direct!.selectReason, 'ambiguous');
      expect(s.direct!.ambiguous, isTrue);
      await tester.pumpWidget(_panel(container));
      expect(find.byKey(const Key('direct-ambiguous')), findsOneWidget);
      expect(find.text(directAmbiguousText), findsOneWidget);
      expect(find.textContaining('附近訊號相近'), findsOneWidget);
      // Still a pick to confirm (identify first).
      expect(find.byKey(const Key('direct-confirm')), findsOneWidget);
    });

    test('pick Y → temporary binding → the gateway switches; 是這台 numbers Y; '
        'the binding is kept and named', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).selected, {_pick});
      await c.switchDirectPick(_first);
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.sent('set_config').last, {'direct_bind_mac': _first});
      expect(s.direct!.pickedMac, _first);
      expect(s.selected, {_first});
      expect(s.message, contains('已改連 PTU $_first'));
      expect(s.identifyNote, isEmpty);

      await c.identify();
      expect(container.read(commissionProvider).identifyNote, contains(_first));
      await c.confirmDirectPick();
      s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(fake.sent('assign_device_id'), [
        {'mac': _first, 'new_id': directPtuId},
      ]);
      // Binding setting off: the temporary binding is kept, never cleared.
      expect(
        fake.sent('set_config').where((p) => p.containsKey('direct_bind_mac')),
        [
          {'direct_bind_mac': _first},
        ],
      );
      expect(fake.config['direct_bind_mac'], _first);
      expect(directBoundNote(s), '已綁定 PTU MAC：$_first（閘道器只連這台）');
    });

    testWidgets('不是這台？ lists the candidates; a tap switches', (tester) async {
      final fake = PickGateway();
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_panel(container));
      await tester.tap(find.byKey(const Key('direct-not-this')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('direct-candidate-$_pick')),
        findsOneWidget,
      );
      expect(find.text('目前選中'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('direct-candidate-$_first')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      expect(container.read(commissionProvider).selected, {_first});
      expect(find.text(_first), findsWidgets);
      expect(
        find.byKey(const ValueKey('direct-candidate-$_first')),
        findsNothing,
        reason: 'collapsed again after the pick',
      );
    });

    test('switch that never lands: error, binding reported', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick('AA:BB:CC:00:00:99');
      final s = container.read(commissionProvider);
      expect(s.error, const GatewayFailure('direct_switch_failed').message);
      expect(s.direct!.state, DirectState.boundMissing);
      expect(s.selected, isEmpty);
    });
  });

  group('3. no pick, older firmware', () {
    testWidgets('no_candidate: hint and 重新搜尋, no confirm', (tester) async {
      final fake = PickGateway(rssi: [-80, -82, -85]);
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.direct!.state, DirectState.noCandidate);
      expect(s.selected, isEmpty);
      expect(s.ptus, isEmpty);
      expect(s.message, contains('找不到夠近的 PTU'));
      // Two negative polls end the wait (the gateway keeps scanning).
      expect(fake.sent('get_status').length, lessThanOrEqualTo(3));
      await tester.pumpWidget(_panel(container));
      expect(find.text('請靠近／確認同樁 PTU 已上電'), findsOneWidget);
      expect(find.byKey(const Key('direct-rescan')), findsOneWidget);
      expect(find.byKey(const Key('direct-rescan-bottom')), findsOneWidget);
      expect(find.byKey(const Key('direct-confirm')), findsNothing);

      fake.device(_pick)['rssi'] = -38;
      await tester.tap(find.byKey(const Key('direct-rescan')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      s = container.read(commissionProvider);
      expect(s.selected, {_pick});
      expect(find.byKey(const Key('direct-confirm')), findsOneWidget);
    });

    test('older firmware keeps the list flow (scan, range number)', () async {
      final fake = PickGateway(newFirmware: false);
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      expect(c.directFlow, isFalse);
      expect(fake.sent('scan_ble_discover'), hasLength(1));
      expect(fake.sent('get_status'), isEmpty);
      expect(fake.sent('set_config'), isEmpty);
      expect(container.read(commissionProvider).selected, hasLength(1));
      await c.configurePtus();
      expect(fake.sent('assign_device_id').single['new_id'], 11);
    });
  });

  group('4. star step 7 idle link loss', () {
    test(
      'a loss that recurs is retried 3 times (5/10/20 s) by itself',
      () async {
        final fake = _IdleDropLink();
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        c.setAutoRssi(false);
        final states = <CommissionState>[];
        container.listen(commissionProvider, (_, s) => states.add(s));
        final before = fake.connects;
        fake.down = true;
        fake.scanDrops = 3;
        await c.keepAlive(now: DateTime.now().add(const Duration(seconds: 16)));
        await _whileRelinking(container);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.ptus, isNotEmpty);
        expect(fake.connects, before + 4);
        for (var n = 1; n <= 3; n++) {
          expect(
            states.any(
              (x) => x.message == step7RetryText(n, 3, step7RetryGaps[n - 1]),
            ),
            isTrue,
            reason: 'retry $n announced',
          );
        }
        // Nothing to tap meanwhile.
        expect(
          states
              .where((x) => x.relinking)
              .every((x) => configureLabel(x) == relinkingLabel),
          isTrue,
        );
      },
    );

    test('after 3 retries the banner waits for 重新連線並繼續', () async {
      final fake = _IdleDropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      c.setAutoRssi(false);
      final before = fake.connects;
      fake.down = true;
      fake.scanDrops = 4;
      await c.keepAlive(now: DateTime.now().add(const Duration(seconds: 16)));
      await _whileRelinking(container);
      var s = container.read(commissionProvider);
      expect(fake.connects, before + 4);
      expect(s.error, isNotNull);
      expect(s.relinking, isFalse);
      expect(step7LinkLost(s), isTrue);
      expect(configureLabel(s), '重新連線並繼續');
      expect(rescanAfterLossLabel, '重新連線並繼續');

      // The tap works and gives the next loss its full retries again.
      await c.discover();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      fake.down = true;
      fake.scanDrops = 1;
      final again = fake.connects;
      await c.keepAlive(now: DateTime.now().add(const Duration(seconds: 40)));
      await _whileRelinking(container);
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.connects, again + 2);
    });
  });

  group('5. failed scan ends 掃描中…', () {
    test('get_ble_devices timeout: error, 重新掃描, not stuck', () async {
      final fake = _DevicesFailLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.failDevices = true;
      await c.discover();
      var s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.error, const GatewayFailure('timeout').message);
      expect(s.ptus, isEmpty);
      expect(s.rescanNeeded, isTrue);
      expect(configureLabel(s), rescanLabel);
      expect(configureLabel(s), isNot(scanningLabel));
      expect(s.message, contains('重新掃描'));
      fake.failDevices = false;
      await c.discover();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.rescanNeeded, isFalse);
      expect(s.ptus, isNotEmpty);
      expect(configureLabel(s), isNot(rescanLabel));
    });
  });

  group('6. step 9 backend retry keeps the progress visible', () {
    test('retry line on top, per-PTU progress below', () async {
      final fake = Round13Link()..failLatestAt.addAll({2, 3});
      final (container, c) = await atStep9(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.verify('https://example.invalid', '');
      expect(container.read(commissionProvider).verified, isTrue);
      final retrying = states
          .map((x) => x.message)
          .where((m) => m.startsWith(backendRetryText(1)))
          .toList();
      expect(retrying, isNotEmpty);
      final lines = retrying.first.split('\n');
      expect(lines.first, backendRetryText(1));
      expect(lines[1], startsWith('資料驗證 #'));
      expect(lines[1], contains('1/3'));
    });
  });

  group('7. finished run', () {
    test('a later connect keeps 上次配置已完成 (no leftover resume)', () async {
      final fake = Round13Link();
      final (container, c) = await atStep9(fake);
      await c.verify('https://example.invalid', '');
      expect(container.read(commissionProvider).verified, isTrue);
      // 結束並重新選擇閘道器 → connect again (e.g. from the list's 辨識).
      await c.cancel();
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      expect(container.read(commissionProvider).step, 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.dispose();

      final next = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(next.dispose);
      final c2 = next.read(commissionProvider.notifier);
      await c2.restore();
      var s = next.read(commissionProvider);
      expect(s.lastCompleted, isTrue);
      expect(s.savedResume, isFalse);
      expect(s.message, startsWith('上次配置已完成'));
      await c2.clearCompleted();
      s = next.read(commissionProvider);
      expect(s.lastCompleted, isFalse);
      expect(s.message, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('demo_progress'), isNull);
    });
  });

  group('8. confirm needs the identified PTU; temporary binding cleanup', () {
    test('never identified: 是這台 is blocked, nothing sent', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.identifiedMac, isNull);
      expect(directConfirmReady(s), isFalse);
      final before = fake.ops.length;
      await c.confirmDirectPick();
      s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(fake.ops, hasLength(before), reason: 'no command at all');
      expect(fake.sent('assign_device_id'), isEmpty);
      expect(fake.sent('join_fleet'), isEmpty);
      expect(s.directNotice, directIdentifyFirstText);
    });

    test('identified A, still A: 是這台 numbers A', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.identify();
      var s = container.read(commissionProvider);
      expect(s.identifiedMac, _pick);
      expect(directConfirmReady(s), isTrue);
      await c.confirmDirectPick();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.sent('assign_device_id'), [
        {'mac': _pick, 'new_id': directPtuId},
      ]);
      expect(fake.sent('join_fleet'), hasLength(1));
    });

    test('identified A, the step 7 refresh sees B: cleared at once, yellow '
        'notice, 是這台 blocked', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.identify();
      expect(container.read(commissionProvider).identifiedMac, _pick);
      fake.device(_pick)['connected'] = false;
      fake.device(_first)['connected'] = true;
      await c.refreshPtuRssi();
      var s = container.read(commissionProvider);
      expect(s.selected, {_first});
      expect(s.identifiedMac, isNull);
      expect(s.directNotice, directSwitchedText(_first));
      expect(directConfirmReady(s), isFalse);
      await c.confirmDirectPick();
      s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(fake.sent('assign_device_id'), isEmpty);
      expect(fake.sent('join_fleet'), isEmpty);
      expect(s.directNotice, directSwitchedText(_first));
      // Identifying B makes it confirmable.
      await c.identify();
      s = container.read(commissionProvider);
      expect(s.identifiedMac, _first);
      expect(s.directNotice, isEmpty);
      expect(directConfirmReady(s), isTrue);
    });

    testWidgets('是這台 disabled until 辨識此樁; a switch shows the yellow '
        'notice and disables it again', (tester) async {
      final fake = PickGateway();
      late ProviderContainer container;
      late CommissioningController c;
      await tester.runAsync(() async {
        (container, c) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_panel(container));
      FilledButton confirm() =>
          tester.widget<FilledButton>(find.byKey(const Key('direct-confirm')));
      expect(confirm().onPressed, isNull);
      expect(find.text(directIdentifyFirstLabel), findsOneWidget);
      expect(find.text('是這台，開始監控'), findsNothing);

      await tester.tap(find.byKey(const Key('direct-identify')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
      expect(find.text('是這台，開始監控'), findsOneWidget);

      fake.device(_pick)['connected'] = false;
      fake.device(_first)['connected'] = true;
      await tester.runAsync(c.refreshPtuRssi);
      await tester.pump();
      expect(find.byKey(const Key('direct-notice')), findsOneWidget);
      expect(find.text(directSwitchedText(_first)), findsOneWidget);
      expect(confirm().onPressed, isNull);
      expect(find.text(directIdentifyFirstLabel), findsOneWidget);
    });

    test('switch → 取消: the temporary binding is cleared', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick(_first);
      expect(container.read(commissionProvider).tempBoundMac, _first);
      await c.cancel();
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.error, isNull);
      expect(
        fake.sent('set_config').where((p) => p.containsKey('direct_bind_mac')),
        [
          {'direct_bind_mac': _first},
          {'direct_bind_mac': ''},
        ],
      );
      expect(fake.config['direct_bind_mac'], '');
      expect(s.tempBoundMac, isNull);
    });

    test('switch → 取消 with 「確認後綁定」 on: the binding is left', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake, bindOnConfirm: true);
      addTearDown(container.dispose);
      await c.switchDirectPick(_first);
      await c.cancel();
      expect(container.read(commissionProvider).step, 1);
      expect(fake.config['direct_bind_mac'], _first);
    });

    test('switch → 取消, the unbind fails: not blocked, noted in 詳細資訊', () async {
      final fake = _UnbindFailing();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick(_first);
      await c.cancel();
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.error, directUnbindFailedText(_first));
      expect(s.errorDetail, contains('write_failed'));
      expect(fake.config['direct_bind_mac'], _first);
    });

    test('switch → 是這台: the binding becomes permanent, never cleared nor '
        'asked about again', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick(_first);
      await c.identify();
      await c.confirmDirectPick();
      var s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.tempBoundMac, isNull);
      await c.cancel();
      expect(
        fake.sent('set_config').where((p) => p.containsKey('direct_bind_mac')),
        [
          {'direct_bind_mac': _first},
        ],
      );
      expect(fake.config['direct_bind_mac'], _first);
      // Confirmed here: entering step 7 again does not ask about it.
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.strayBindMac, isNull);
    });

    testWidgets('leftover binding on entering step 7: 保留／解除 offered, not '
        'cleared by itself; 解除 clears it', (tester) async {
      final fake = PickGateway()..config['direct_bind_mac'] = _first;
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.strayBindMac, _first);
      expect(s.selected, {_first});
      expect(
        fake.sent('set_config').where((p) => p.containsKey('direct_bind_mac')),
        isEmpty,
      );
      await tester.pumpWidget(_panel(container));
      expect(find.byKey(const Key('direct-stray-bind')), findsOneWidget);
      expect(find.text(directStrayBindText(_first)), findsOneWidget);
      expect(find.textContaining('MAC 後 4 碼 0001'), findsOneWidget);
      expect(find.byKey(const Key('direct-stray-keep')), findsOneWidget);
      await tester.tap(find.byKey(const Key('direct-stray-release')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      s = container.read(commissionProvider);
      expect(fake.sent('set_config').last, {'direct_bind_mac': ''});
      expect(fake.config['direct_bind_mac'], '');
      expect(s.strayBindMac, isNull);
      expect(s.selected, {_pick});
      expect(find.byKey(const Key('direct-stray-bind')), findsNothing);
    });

    test('leftover binding → 保留: kept and not asked again', () async {
      final fake = PickGateway()..config['direct_bind_mac'] = _first;
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).strayBindMac, _first);
      await c.keepStrayBind();
      expect(container.read(commissionProvider).strayBindMac, isNull);
      await c.discover();
      final s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.strayBindMac, isNull);
      expect(fake.config['direct_bind_mac'], _first);
      expect(
        fake.sent('set_config').where((p) => p.containsKey('direct_bind_mac')),
        isEmpty,
      );
    });
  });
}

/// set_config clearing the binding fails (the gateway's fail ack).
class _UnbindFailing extends PickGateway {
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    if (op == 'set_config' && params['direct_bind_mac'] == '') {
      ops.add((op, Map.of(params)));
      return Future.error(const GatewayFailure.gateway('write_failed'));
    }
    return super.command(op, params);
  }
}

Future<void> _whileRelinking(ProviderContainer container) async {
  for (var i = 0; i < 400; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final s = container.read(commissionProvider);
    if (!s.relinking && !s.busy) return;
  }
}

/// Star step 7: the link drops while idle ([down]); each rescan after a
/// reconnect drops it again while [scanDrops] lasts.
class _IdleDropLink extends DroppingLink {
  int scanDrops = 0;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (!down && op == 'scan_ble_discover' && scanDrops > 0) {
      scanDrops--;
      down = true;
      throw const GatewayFailure('not_connected');
    }
    return super.command(op, params);
  }
}

/// get_ble_devices answer lost over BLE (round 14: NUS TX failed) → the APP
/// times out waiting for it.
class _DevicesFailLink extends DroppingLink {
  bool failDevices = false;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (failDevices && op == 'get_ble_devices') {
      throw const GatewayFailure('timeout');
    }
    return super.command(op, params);
  }
}
