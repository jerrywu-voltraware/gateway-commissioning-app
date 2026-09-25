// Round 17: the candidate sheet's tiles ([DirectCandidateTile]) go
// `onTap: null` while busy with no other cue — a tap during a slow gateway
// command just looked unresponsive. Now: every row dims to 0.5 opacity and
// [DirectCandidatesSheet] shows 「閘道器處理中，請稍候…」 (with a small
// progress indicator) above the list; both clear on their own once
// [CommissionState.busy] does, with no extra wiring needed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

/// Listed first by the gateway, but not its pick (round15/16(b) naming).
const _first = 'AA:BB:CC:00:00:01';

/// identify() waits for [release] (the controller stays busy meanwhile) —
/// a busy source that, unlike switchDirectPick, never pops the sheet on its
/// own, so the busy UI can be observed while the sheet stays open.
class _SlowIdentify extends PickGateway {
  Completer<void>? hold;

  void release() => hold?.complete();

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'identify' && hold != null) await hold!.future;
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _toStep7(
  PickGateway fake,
) async {
  SharedPreferences.setMockInitialValues(const {});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.direct);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  return (container, c);
}

List<Map<String, dynamic>> _bindWrites(PickGateway fake) => [
  for (final p in fake.sent('set_config'))
    if (p.containsKey('direct_bind_mac')) p,
];

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

double _opacityOf(WidgetTester tester, Finder tile) => tester
    .widget<Opacity>(
      find.ancestor(of: tile, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'busy dims the candidate rows and shows a notice; a tap while busy '
    'sends nothing and keeps the sheet open; busy ending restores both',
    (tester) async {
      _phone(tester);
      final fake = _SlowIdentify();
      late ProviderContainer container;
      late CommissioningController c;
      await tester.runAsync(() async {
        (container, c) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tester.tap(find.byKey(const Key('direct-not-this')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('direct-candidates-sheet')), findsOneWidget);
      final tile = find.byKey(const ValueKey('direct-candidate-$_first'));
      expect(tile, findsOneWidget);

      // Not busy yet: full opacity, no notice.
      expect(find.byKey(const Key('direct-candidates-busy')), findsNothing);
      expect(_opacityOf(tester, tile), 1.0);

      // Turn busy (identify never pops the sheet on its own) and let the
      // widget tree pick it up.
      fake.hold = Completer<void>();
      unawaited(c.identify());
      expect(container.read(commissionProvider).busy, isTrue);
      await tester.pump();

      // The notice (with its small progress indicator) is up, and every
      // row — including the untouched one — is dimmed.
      final notice = find.byKey(const Key('direct-candidates-busy'));
      expect(notice, findsOneWidget);
      expect(find.text('閘道器處理中，請稍候…'), findsOneWidget);
      expect(
        find.descendant(
          of: notice,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(_opacityOf(tester, tile), 0.5);

      // A tap while busy: onTap is null (disabled), so nothing is sent and
      // the sheet stays open.
      await tester.tap(tile);
      await tester.pump();
      expect(_bindWrites(fake), isEmpty);
      expect(find.byKey(const Key('direct-candidates-sheet')), findsOneWidget);

      // Busy ends on its own: the notice clears and the row is full opacity
      // again, with no extra wiring.
      fake.release();
      await _idle(tester, container);
      await tester.pump();
      expect(container.read(commissionProvider).busy, isFalse);
      expect(find.byKey(const Key('direct-candidates-busy')), findsNothing);
      expect(_opacityOf(tester, tile), 1.0);

      // Now a tap really switches and closes the sheet.
      await tester.tap(tile);
      await tester.pump();
      await _idle(tester, container);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_bindWrites(fake), [
        {'direct_bind_mac': _first},
      ]);
      expect(find.byKey(const Key('direct-candidates-sheet')), findsNothing);
    },
  );
}
