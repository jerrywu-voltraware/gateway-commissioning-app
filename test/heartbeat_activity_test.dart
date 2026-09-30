import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/progress_checklist.dart';
import 'package:gateway_commissioning/presentation/heartbeat_activity.dart';

Widget _app({
  bool busy = true,
  Checklist? checklist,
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool disableAnimations = false,
  bool tickerEnabled = true,
}) => MaterialApp(
  theme: gatewayTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: disableAnimations,
    ),
    child: TickerMode(enabled: tickerEnabled, child: child!),
  ),
  home: Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: HeartbeatActivity(
              key: const Key('heartbeat-activity'),
              busy: busy,
              checklist: checklist,
            ),
          ),
        ),
      ],
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Checklist _waiting() =>
    onlineChecklist().done(onlineItemBackend).start(onlineItemBeat1);

Icon _receipt(WidgetTester tester, int number) =>
    tester.widget<Icon>(find.byKey(Key('heartbeat-receipt-$number')));

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('360x640 ${brightness.name} $scale: all stages fit', (
        tester,
      ) async {
        _phone(tester);
        final first = _waiting().done(onlineItemBeat1).start(onlineItemBeat2);
        final second = first.done(onlineItemBeat2).start(onlineItemTarget);
        for (final checklist in [
          onlineChecklist().start(onlineItemBackend),
          _waiting(),
          first,
          second,
          second.done(onlineItemTarget),
          first.fail('No heartbeat'),
        ]) {
          await tester.pumpWidget(
            _app(checklist: checklist, brightness: brightness, scale: scale),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(
            find.byKey(const Key('heartbeat-activity')),
          );
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(rect.bottom, lessThanOrEqualTo(640));
          expect(rect.height, lessThanOrEqualTo(170));
          expect(find.byType(Card), findsOneWidget);
          expect(find.byIcon(Icons.router_outlined), findsOneWidget);
          expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
        }
      });
    }
  }

  testWidgets('motion cannot invent receipts or finish the confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(checklist: _waiting()));
    expect(find.text('等待第 1 次心跳'), findsOneWidget);
    expect(find.text('心跳 0/2'), findsOneWidget);
    expect(_receipt(tester, 1).icon, Icons.radio_button_unchecked);
    expect(_receipt(tester, 2).icon, Icons.radio_button_unchecked);
    final packet = find.byKey(const Key('heartbeat-flow-packet'));
    final position = tester.getTopLeft(packet);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(packet).dx, greaterThan(position.dx));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('心跳 0/2'), findsOneWidget);
    expect(find.text('等待第 1 次心跳'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('receipts and phase only advance on checklist updates', (
    tester,
  ) async {
    var checklist = _waiting();
    await tester.pumpWidget(_app(checklist: checklist));
    checklist = checklist.done(onlineItemBeat1).start(onlineItemBeat2);
    await tester.pumpWidget(_app(checklist: checklist));
    expect(find.text('心跳 1/2'), findsOneWidget);
    expect(find.text('已收到 1 次，等待下一次心跳'), findsOneWidget);
    expect(_receipt(tester, 1).icon, Icons.check_circle);
    expect(_receipt(tester, 2).icon, Icons.radio_button_unchecked);
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('心跳 1/2'), findsOneWidget);

    checklist = checklist.done(onlineItemBeat2).start(onlineItemTarget);
    await tester.pumpWidget(_app(checklist: checklist));
    expect(find.text('心跳 2/2'), findsOneWidget);
    expect(find.text('已收到 2 次，正在確認上傳目標'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.text('已確認閘道器持續上線'), findsNothing);

    await tester.pumpWidget(_app(checklist: checklist.done(onlineItemTarget)));
    expect(find.text('已確認閘道器持續上線'), findsOneWidget);
    expect(find.byKey(const Key('heartbeat-flow-packet')), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('failure and idle stop motion and preserve actual receipts', (
    tester,
  ) async {
    final first = _waiting().done(onlineItemBeat1).start(onlineItemBeat2);
    await tester.pumpWidget(_app(checklist: first));
    await tester.pumpWidget(_app(checklist: first.fail('No heartbeat')));
    expect(find.text('確認暫停，請依提示重試'), findsOneWidget);
    expect(find.text('心跳 1/2'), findsOneWidget);
    expect(find.byKey(const Key('heartbeat-flow-packet')), findsNothing);
    await tester.pumpAndSettle();

    await tester.pumpWidget(_app(checklist: first, busy: false));
    expect(find.text('尚未完成心跳確認'), findsOneWidget);
    expect(find.text('心跳 1/2'), findsOneWidget);
    expect(find.byKey(const Key('heartbeat-flow-packet')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('absent or unrelated checklists never imply heartbeat evidence', (
    tester,
  ) async {
    for (final checklist in [
      null,
      connectChecklist().done(onlineItemBackend),
    ]) {
      await tester.pumpWidget(_app(checklist: checklist));
      expect(find.text('等待開始確認'), findsOneWidget);
      expect(find.text('心跳 0/2'), findsOneWidget);
      expect(find.byKey(const Key('heartbeat-flow-packet')), findsNothing);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('accessibility and TickerMode stop and resume only the motion', (
    tester,
  ) async {
    await tester.pumpWidget(_app(checklist: _waiting()));
    expect(find.byKey(const Key('heartbeat-flow-packet')), findsOneWidget);
    await tester.pumpWidget(
      _app(checklist: _waiting(), disableAnimations: true),
    );
    expect(find.byKey(const Key('heartbeat-flow-packet')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_app(checklist: _waiting(), tickerEnabled: false));
    expect(find.byKey(const Key('heartbeat-flow-packet')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_app(checklist: _waiting()));
    expect(find.byKey(const Key('heartbeat-flow-packet')), findsOneWidget);
    expect(find.text('心跳 0/2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('missing heartbeat items cannot be mistaken for completion', (
    tester,
  ) async {
    for (final checklist in [
      const Checklist(ChecklistKind.online, []),
      const Checklist(ChecklistKind.online, [
        CheckItem(onlineItemBackend, 'Backend', status: CheckStatus.done),
        CheckItem(onlineItemTarget, 'Target', status: CheckStatus.done),
      ]),
    ]) {
      await tester.pumpWidget(_app(checklist: checklist));
      expect(find.text('心跳 0/2'), findsOneWidget);
      expect(find.text('已確認閘道器持續上線'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    }
  });

  testWidgets('live announcement stays unchanged throughout waiting motion', (
    tester,
  ) async {
    await tester.pumpWidget(_app(checklist: _waiting()));
    final finder = find.byKey(const Key('heartbeat-announcement'));
    final before = tester.widget<Semantics>(finder);
    expect(before.properties.liveRegion, isTrue);
    expect(before.properties.label, '已收到 0 次心跳。等待第 1 次心跳');
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.widget<Semantics>(finder), same(before));
    await tester.pumpWidget(
      _app(checklist: _waiting().done(onlineItemBeat1).start(onlineItemBeat2)),
    );
    expect(
      tester.widget<Semantics>(finder).properties.label,
      '已收到 1 次心跳。已收到 1 次，等待下一次心跳',
    );
  });
}
