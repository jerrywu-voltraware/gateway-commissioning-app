// 09-29 (field: the gateway list had no way out): the system 返回 on the
// list left the APP at once, 「結束並重新選擇閘道器」 there only wrote
// 「已取消」 in place, and a cancel kept the gateway as `peer`, so the red
// 「手機與閘道器的藍牙已斷線」 box showed a link the APP had cut itself.
// Now: the list's button is 〔結束配置〕 (asks once, then the start page),
// 返回 on the list is the start page without asking, and only the start
// page leaves the APP; a cancel drops the peer (no red box) and, from the
// list with nothing running, says nothing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_signal.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp;

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The demo APP at the gateway list (step 1), nothing connected.
Future<(ProviderContainer, CommissioningController)> _atList(
  WidgetTester tester,
  DroppingLink fake,
) async {
  final container = await pumpApp(tester, fake);
  final c = container.read(commissionProvider.notifier);
  await tester.runAsync(() async {
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
  });
  await tester.pumpAndSettle();
  expect(container.read(commissionProvider).step, 1);
  return (container, c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. the gateway list has a way back', () {
    testWidgets('〔結束配置〕 asks once, 結束 → the start page', (tester) async {
      final (container, c) = await _atList(tester, DroppingLink());
      expect(find.text(leaveListLabel), findsOneWidget);
      expect(find.text(endFlowLabel), findsNothing);

      await tester.tap(find.byKey(const Key('page-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave-confirm')), findsOneWidget);
      expect(find.text(leaveListConfirmTitle), findsOneWidget);
      // 留在清單: nothing changes.
      await tester.tap(find.byKey(const Key('leave-confirm-stay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave-confirm')), findsNothing);
      expect(container.read(commissionProvider).step, 1);

      await tester.tap(find.byKey(const Key('page-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave-confirm-end')));
      await tester.runAsync(
        () => _until(() => container.read(commissionProvider).step == 0),
      );
      await tester.pumpAndSettle();
      final s = container.read(commissionProvider);
      expect(s.step, 0);
      expect(s.peer, isNull);
      expect(s.message, isEmpty);
      expect(s.error, isNull);
      expect(find.byKey(const Key('leave-confirm')), findsNothing);
      expect(find.byKey(const Key('page-cancel')), findsNothing);
      expect(c.state.step, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the system 返回 on the list: the start page, no question, '
        'the APP stays', (tester) async {
      final (container, _) = await _atList(tester, DroppingLink());
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await tester.runAsync(
        () => _until(() => container.read(commissionProvider).step == 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave-confirm')), findsNothing);
      expect(find.byKey(const Key('end-confirm')), findsNothing);
      expect(container.read(commissionProvider).step, 0);
      expect(find.byType(GatewayApp), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    // 「上一台已完成」 surviving 〔結束配置〕: round29_done_page_test.dart
    // (〔配置下一台〕 then 〔結束配置〕).

    test('leaveList only from the list (not the start page, not past it)',
        () async {
      final fake = DroppingLink();
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.leaveList();
      expect(container.read(commissionProvider).step, 0);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      expect(container.read(commissionProvider).step, 1);
      await c.connect(container.read(commissionProvider).peers.first);
      expect(container.read(commissionProvider).step, greaterThan(1));
      await c.leaveList();
      expect(container.read(commissionProvider).step, greaterThan(1));
      await c.cancel();
      expect(container.read(commissionProvider).step, 1);
      await c.leaveList();
      expect(container.read(commissionProvider).step, 0);
    });
  });

  group('2. a cancel drops the peer', () {
    testWidgets('connected, then cancel: the list, no peer, no red '
        '「藍牙已斷線」 box', (tester) async {
      final (container, c) = await _atList(tester, DroppingLink());
      await tester.runAsync(
        () => c.connect(container.read(commissionProvider).peers.first),
      );
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).peer, isNotNull);
      expect(container.read(commissionProvider).step, greaterThan(1));

      await tester.runAsync(c.cancel);
      await tester.pumpAndSettle();
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.peer, isNull);
      expect(find.byType(GatewayLinkAlert), findsNothing);
      // Past the list the note stays (a run was cancelled).
      expect(s.message, startsWith('已取消'));
      await tester.pumpWidget(const SizedBox());
    });

    test('cancel on the list with nothing running: no 「已取消」', () async {
      final fake = DroppingLink();
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.cancel();
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.peer, isNull);
      expect(s.message, isNot(contains('已取消')));
    });
  });
}
