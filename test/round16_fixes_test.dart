// Round 16 (after field round 15, APP c420391, firmware 1.7.21):
// 1. 「不是這台？」 waits [directSwitchWait] (45 s) — the countdown shows the
//    same — and a later step 7 refresh that sees the chosen PTU connected
//    clears the red error at once (round 15: the APP gave up after ~21 s
//    with 「最多等待 42 秒」 on screen; the switch took 24 s).
// 2. The identify note is one line in the bottom bar (full note on tap) and
//    「不是這台？」 sits in the bar, always on screen at 360 dp (round 15: the
//    four-line note grew the bar over it).
// 3. Direct flow candidates and the picked card name PTUs by 「MAC 後 4 碼」
//    + RSSI, never by an old star number (#1–#5).
// 4. Every saved-progress prompt has 「重新開始」, in either topology
//    (round 15: 「上次中斷於第 5 步」 without a gateway had none).
// 5. The star 「每台 PTU 數」 is never written by the topology switch or the
//    direct flow; it is chosen in its own dialog (round 15: 4 instead of 5).
import 'dart:convert';

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

import 'link_loss_test.dart' show pumpApp;
import 'round15_direct_flow_test.dart' show PickGateway;

/// Listed first by the gateway, but not its pick.
const _first = 'AA:BB:CC:00:00:01';

/// The gateway's own pick (strongest).
const _pick = 'AA:BB:CC:00:00:02';

/// The gateway needs a while to connect the PTU bound by 「不是這台？」
/// (round 15 field: five failed connects, 24 s): until [delay] after the
/// binding (or while [never]), get_status reports `connecting` and no PTU.
class _SlowSwitch extends PickGateway {
  _SlowSwitch({this.delay = Duration.zero, this.never = false});

  final Duration delay;
  bool never;
  DateTime? _landAt;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final bind = params['direct_bind_mac'];
    if (op == 'set_config' && bind is String && bind.isNotEmpty) {
      _landAt = DateTime.now().add(delay);
    }
    final result = await super.command(op, params);
    final at = _landAt;
    final switching = at != null && (never || DateTime.now().isBefore(at));
    if (op == 'get_status' && switching && result['direct'] is Map) {
      final direct = Map<String, dynamic>.from(result['direct'] as Map)
        ..['state'] = 'connecting'
        ..remove('ptu_mac')
        ..remove('ptu_rssi')
        ..remove('ptu_device_number');
      return {...result, 'direct': direct};
    }
    return result;
  }
}

Future<(ProviderContainer, CommissioningController)> _toStep7(
  PickGateway fake, {
  GatewayTopology topology = GatewayTopology.direct,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(topology);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  return (container, c);
}

/// Step 7 as on the phone: the card scrolls, the actions are the bottom bar.
Widget _screen(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: DirectStatusPanel()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: DirectPickActions(),
        ),
      ),
    ),
  ),
);

Future<void> _idle(WidgetTester tester, ProviderContainer container) =>
    tester.runAsync(() async {
      for (var i = 0; i < 400 && container.read(commissionProvider).busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

void _phone(WidgetTester tester, {Size size = const Size(360, 640)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _switchFailed() => const GatewayFailure('direct_switch_failed').message;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepSwitch;
  setUp(() {
    keepPoll = directPollInterval;
    keepSwitch = directSwitchWait;
    directPollInterval = const Duration(milliseconds: 1);
    directSwitchWait = const Duration(milliseconds: 80);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    directSwitchWait = keepSwitch;
  });

  group('1. 不是這台？ waits as long as the countdown says', () {
    test('the default wait is 45 s and the countdown shows 45', () {
      expect(keepSwitch, const Duration(seconds: 45));
      directSwitchWait = keepSwitch;
      expect(directSwitchSeconds, 45);
    });

    test('a switch slower than the old 14-poll limit still lands', () async {
      directSwitchWait = const Duration(seconds: 3);
      final fake = _SlowSwitch(delay: const Duration(milliseconds: 300));
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      final before = fake.sent('get_status').length;
      await c.switchDirectPick(_first);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.selected, {_first});
      expect(s.direct!.pickedMac, _first);
      expect(s.message, directSwitchDoneText(_first));
      // Round 15 gave up after directPollLimit (14) polls.
      expect(
        fake.sent('get_status').length - before,
        greaterThan(directPollLimit),
      );
    });

    test('it gives up exactly when the countdown ends; the header no longer '
        'says 正在讓閘道器改連', () async {
      directSwitchWait = const Duration(seconds: 2);
      final fake = _SlowSwitch(never: true);
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      final shown = <int>[];
      container.listen<CommissionState>(commissionProvider, (_, next) {
        if (next.busy && next.message.startsWith('正在讓閘道器改連')) {
          shown.add(next.seconds);
        }
      });
      final clock = Stopwatch()..start();
      await c.switchDirectPick(_first);
      clock.stop();
      final s = container.read(commissionProvider);
      expect(shown.first, 2, reason: 'countdown starts at the wait');
      expect(clock.elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)));
      expect(clock.elapsed, lessThan(const Duration(seconds: 4)));
      expect(s.busy, isFalse);
      expect(s.error, _switchFailed());
      expect(s.message, directSwitchPendingText(_first));
      expect(s.message, isNot(contains('正在讓閘道器改連')));
      expect(s.tempBoundMac, _first);
    });

    test('the step 7 refresh clears the error as soon as the chosen PTU is '
        'connected', () async {
      final fake = _SlowSwitch(never: true);
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick(_first);
      expect(container.read(commissionProvider).error, _switchFailed());

      // Still switching: the refresh keeps the error.
      await c.refreshPtuRssi();
      expect(container.read(commissionProvider).error, _switchFailed());

      fake.never = false;
      await c.refreshPtuRssi();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.errorDetail, isNull);
      expect(s.selected, {_first});
      expect(s.ptus.single['mac'], _first);
      expect(s.message, directSwitchDoneText(_first));
      // Then identify → 是這台 as usual.
      await c.identify();
      await c.confirmDirectPick();
      expect(container.read(commissionProvider).step, 6);
      expect(fake.sent('assign_device_id'), [
        {'mac': _first, 'new_id': directPtuId},
      ]);
    });

    test('another PTU connected meanwhile keeps the error', () async {
      final fake = _SlowSwitch(never: true);
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick(_first);
      // The binding was dropped elsewhere; the gateway connects another.
      fake.config['direct_bind_mac'] = '';
      fake.device(_first)['connected'] = false;
      fake.device(_pick)['connected'] = true;
      fake.never = false;
      await c.refreshPtuRssi();
      final s = container.read(commissionProvider);
      expect(s.selected, {_pick});
      expect(s.error, _switchFailed());
    });
  });

  group('2. bottom bar: one-line note, 不是這台？ always on screen', () {
    testWidgets('360 dp: identify does not grow the bar; 不是這台？ stays '
        'visible and opens the candidates', (tester) async {
      _phone(tester);
      // Ambiguous: the card is at its tallest (round 15 b03).
      final fake = PickGateway(rssi: [-40, -43, -70]);
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      final bar = find.byType(DirectPickActions);
      final before = tester.getSize(bar).height;

      await tester.tap(find.byKey(const Key('direct-identify')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.identifyNote, contains(_first));
      // Round 16b: the full MAC; at 360 dp the line does not fit, so the
      // bar shows the bytes that tell it apart (the full note on tap).
      expect(s.identifyLine, '已送出 · 請看樁上燈號 · $_first · -40 dBm');
      final note = tester.widget<Text>(
        find.byKey(const Key('direct-identify-note')),
      );
      expect(note.textSpan!.toPlainText(), '已送出 · 請看樁上燈號 · …01 · -40 dBm');
      expect(note.maxLines, 1);
      expect(
        tester.getSize(find.byKey(const Key('direct-identify-note'))).height,
        lessThan(30),
      );
      expect(tester.getSize(bar).height, before);

      final link = find.byKey(const Key('direct-not-this'));
      expect(link, findsOneWidget);
      final rect = tester.getRect(link);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(
        find.descendant(of: bar, matching: link),
        findsOneWidget,
        reason: 'in the bottom bar, not the scrolled card',
      );
      await tester.tap(link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('direct-candidates-sheet')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('direct-candidate-$_pick')),
        findsOneWidget,
      );
    });

    testWidgets('tapping the note shows the full one', (tester) async {
      _phone(tester);
      final fake = PickGateway();
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      // Before identify: the hint, nothing to open.
      expect(find.text('按下後請看樁上 PTU 與閘道器的燈號'), findsOneWidget);
      await tester.tap(find.byKey(const Key('direct-identify')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      expect(find.byKey(const Key('direct-identify-detail')), findsNothing);
      await tester.tap(find.byKey(const Key('direct-identify-toggle')));
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('direct-identify-detail')))
            .textSpan!
            .toPlainText(),
        identifyNoteText({'mac': _pick, 'rssi': -38}),
      );
    });

    test('one-line note texts', () {
      expect(identifySentLine, '已送出 · 請看樁上燈號');
      expect(
        identifyLineText({'mac': '90:5f:e8:9a:96:00', 'rssi': -45}),
        '已送出 · 請看樁上燈號 · 90:5F:E8:9A:96:00 · -45 dBm',
      );
      expect(identifyLineText(const {}), '已送出 · 請看樁上燈號 · 閘道器雙閃 6 秒');
      expect(
        identifyLineText(const {'ptu_write': 'not_connected'}),
        '已送出 · 只有閘道器閃燈，PTU 未收到',
      );
    });
  });

  group('3. no old star numbers in the direct flow', () {
    // Round 16b: the full MAC (「MAC 後 4 碼」 read 9600 for a whole fleet).
    testWidgets('picked card and candidates: full MAC + RSSI, no #n', (
      tester,
    ) async {
      _phone(tester);
      final fake = PickGateway();
      for (final (i, d) in fake.devices.indexed) {
        d['device_number'] = i + 1; // leftovers of a star run
      }
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      expect(
        find.descendant(
          of: find.byKey(const Key('direct-linked')),
          matching: find.text(_pick),
        ),
        findsOneWidget,
      );
      expect(find.text(_pick), findsOneWidget);
      expect(find.textContaining('後 4 碼'), findsNothing);
      expect(find.textContaining(RegExp(r'#\d')), findsNothing);

      await tester.tap(find.byKey(const Key('direct-not-this')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (final (mac, rssi) in [(_first, -50), (_pick, -38)]) {
        final row = find.byKey(ValueKey('direct-candidate-$mac'));
        expect(
          find.descendant(of: row, matching: find.text(mac)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('峰值 $rssi dBm')),
          findsOneWidget,
        );
      }
      expect(find.textContaining('後 4 碼'), findsNothing);
      expect(find.textContaining(RegExp(r'#\d')), findsNothing);
    });

    testWidgets('no pick: 改選其他 PTU lists them the same way', (tester) async {
      _phone(tester);
      final fake = PickGateway(rssi: [-80, -82, -85]);
      for (final (i, d) in fake.devices.indexed) {
        d['device_number'] = i + 3;
      }
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tester.tap(find.byKey(const Key('direct-not-this')));
      await tester.pump();
      expect(find.text('峰值 -80 dBm'), findsOneWidget);
      expect(find.text(_first), findsOneWidget);
      expect(find.textContaining('後 4 碼'), findsNothing);
      expect(find.textContaining(RegExp(r'#\d')), findsNothing);
    });
  });

  group('4. every saved-progress prompt has 重新開始', () {
    final unfinished = jsonEncode({
      'step': 3,
      'shown': 5,
      'completed': false,
      'count': 0,
      'site': 80,
      'gateway': 1,
      'peer': null,
      'selected': [],
      'done': {},
      'inflight': {},
      'assignments': [],
    });

    test('an unfinished record without a gateway: 重新開始 clears it', () async {
      SharedPreferences.setMockInitialValues({'demo_progress': unfinished});
      final fake = PickGateway();
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.restore();
      var s = container.read(commissionProvider);
      expect(s.message, startsWith('上次中斷於第 5 步'));
      expect(s.savedResume, isFalse);
      expect(s.savedProgress, isTrue);
      await c.clearCompleted();
      s = container.read(commissionProvider);
      expect(s.savedProgress, isFalse);
      expect(s.message, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('demo_progress'), isNull);
    });

    for (final topology in GatewayTopology.values) {
      testWidgets('first page shows 重新開始 (${topology.name})', (tester) async {
        final container = await pumpApp(
          tester,
          DemoSystem(),
          prefs: {
            'demo_progress': unfinished,
            'gateway_topology': topology.name,
          },
        );
        await tester.runAsync(
          () => container.read(commissionProvider.notifier).restore(),
        );
        await tester.pumpAndSettle();
        expect(container.read(topologyProvider).topology, topology);
        expect(find.textContaining('上次中斷於第 5 步'), findsOneWidget);
        expect(find.byKey(const Key('saved-resume')), findsNothing);
        await tester.tap(find.byKey(const Key('restart-after-done')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('上次中斷於'), findsNothing);
        expect(find.byKey(const Key('restart-after-done')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('5. the star PTU count survives the direct flow', () {
    test('star → direct run (max_connections 1, switch, confirm) → star keeps '
        'the saved count', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(
        fake,
        prefs: {'gateway_topology': 'star', 'gateway_star_ptu_count': 3},
      );
      addTearDown(container.dispose);
      expect(container.read(topologyProvider).topology.isDirect, isTrue);
      expect(container.read(topologyProvider).starCount, 3);
      expect(fake.config['max_connections'], 1);
      await c.switchDirectPick(_first);
      await c.identify();
      await c.confirmDirectPick();
      expect(container.read(commissionProvider).step, 6);
      expect(fake.config['max_connections'], 1);
      await container
          .read(topologyProvider.notifier)
          .setTopology(GatewayTopology.star);
      expect(container.read(topologyProvider).starCount, 3);
      expect(container.read(topologyProvider).targetCount, 3);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('gateway_star_ptu_count'), 3);
    });

    test('switching topology never writes the star count', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final topo = container.read(topologyProvider.notifier);
      await topo.ready;
      await topo.setTopology(GatewayTopology.direct);
      expect(container.read(topologyProvider).targetCount, 1);
      await topo.setTopology(GatewayTopology.star);
      expect(container.read(topologyProvider).starCount, defaultStarPtuCount);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('gateway_star_ptu_count'), isNull);
    });

    testWidgets('menu: topology items never change the count; it has its own '
        'dialog', (tester) async {
      final container = await pumpApp(
        tester,
        DemoSystem(),
        prefs: {'gateway_topology': 'star', 'gateway_star_ptu_count': 5},
      );
      Future<void> openMenu() async {
        await tester.tap(find.byKey(const Key('topology-menu')));
        await tester.pumpAndSettle();
      }

      await openMenu();
      expect(find.byKey(const Key('star-count')), findsOneWidget);
      expect(find.text('每台 PTU 數：5…'), findsOneWidget);
      // No one-tap count items beside the topology items any more.
      expect(find.byKey(const ValueKey('star-count-4')), findsNothing);
      await tester.tap(find.text(GatewayTopology.direct.label));
      await tester.pumpAndSettle();
      expect(container.read(topologyProvider).topology.isDirect, isTrue);

      await openMenu();
      expect(find.byKey(const Key('star-count')), findsNothing);
      await tester.tap(find.text(GatewayTopology.star.label));
      await tester.pumpAndSettle();
      expect(container.read(topologyProvider).topology.isStar, isTrue);
      expect(container.read(topologyProvider).starCount, 5);

      await openMenu();
      await tester.tap(find.byKey(const Key('star-count')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('star-count-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('star-count-3')));
      await tester.pumpAndSettle();
      expect(container.read(topologyProvider).starCount, 3);
      expect(find.text('星狀模式每台 PTU 數已改為 3 台'), findsOneWidget);
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getInt('gateway_star_ptu_count'), 3);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
