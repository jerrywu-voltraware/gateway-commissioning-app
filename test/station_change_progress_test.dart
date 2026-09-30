import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/station_change.dart';
import 'package:gateway_commissioning/presentation/progress_checklist.dart';
import 'package:gateway_commissioning/presentation/station_change_progress.dart';

Widget _app(
  StationChange progress, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: gatewayTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    appBar: AppBar(title: const Text('GIOS 現場開通')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(progress.title),
        const SizedBox(height: 12),
        StationChangeProgress(
          key: const Key('station-change-progress'),
          progress: progress,
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

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3]) {
      for (final stage in StationChangeStage.values) {
        testWidgets('360x640 ${brightness.name} $scale ${stage.name}: '
            'target and all progress rows stay visible without overflow', (
          tester,
        ) async {
          _phone(tester);
          final progress = StationChange(
            site: 65535,
            gateway: 255,
            stage: stage,
          );
          await tester.pumpWidget(
            _app(progress, brightness: brightness, scale: scale),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(find.text('站點 65535 · 閘道器 255'), findsOneWidget);
          expect(find.text(progress.title), findsOneWidget);
          for (final key in [
            'station-change-target',
            'station-change-guidance',
            'check-item-station-apply',
            'check-item-station-restart',
            'check-item-station-confirm',
          ]) {
            final finder = find.byKey(Key(key));
            expect(finder, findsOneWidget);
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(360));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(640));
          }
          expect(find.byType(ProgressChecklist), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.byKey(const Key('checklist-footer')), findsNothing);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(AlertDialog), findsNothing);
        });
      }
    }
  }

  testWidgets('waiting and reconnecting keep the restart row running until '
      'the controller confirms the new link', (tester) async {
    _phone(tester);
    const progress = StationChange(site: 80, gateway: 1);
    await tester.pumpWidget(_app(progress));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const Key('check-station-restart-pending')),
      findsOneWidget,
    );
    for (final stage in [
      StationChangeStage.restarting,
      StationChangeStage.reconnecting,
    ]) {
      await tester.pumpWidget(_app(progress.at(stage)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('check-station-restart-running')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('check-station-restart-done')), findsNothing);
      expect(find.textContaining('藍牙會短暫中斷'), findsOneWidget);
      expect(find.textContaining('APP 會自動重新連線'), findsOneWidget);
      // Time passing is not evidence that the gateway has restarted.
      await tester.pump(const Duration(seconds: 20));
      expect(find.byKey(const Key('check-station-restart-done')), findsNothing);
    }
    await tester.pumpWidget(_app(progress.at(StationChangeStage.confirming)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('check-station-restart-done')), findsOneWidget);
    expect(
      find.byKey(const Key('check-station-confirm-running')),
      findsOneWidget,
    );
    expect(find.textContaining('已重新連線'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guidance is announced as a live region and the stage icon '
      'changes without adding actions', (tester) async {
    _phone(tester);
    const progress = StationChange(site: 81, gateway: 3);
    await tester.pumpWidget(_app(progress));
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    final guidance = find.ancestor(
      of: find.byKey(const Key('station-change-guidance')),
      matching: find.byType(Semantics),
    );
    expect(
      tester
          .widgetList<Semantics>(guidance)
          .any((s) => s.properties.liveRegion == true),
      isTrue,
    );
    await tester.pumpWidget(_app(progress.at(StationChangeStage.reconnecting)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.save_outlined), findsNothing);
    expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
