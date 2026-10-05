import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/ptu_selection_tile.dart';
import 'support/finders.dart';

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

Future<ProviderContainer> pumpSelection(
  WidgetTester tester,
  double scale,
) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({});
  final fake = DemoSystem();
  fake.config['fleet_joined'] = true;
  fake.devices.clear();
  fake.devices.addAll(
    List.generate(
      5,
      (i) => {
        'mac': '90:2C:00:54:96:0${i + 1}',
        'device_number': i + 1,
        'connected': true,
        'rssi': 0,
      },
    ),
  );
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
  final controller = container.read(commissionProvider.notifier);
  await controller.prepare('https://example.invalid', '', offline: true);
  await controller.scan();
  await controller.connect(container.read(commissionProvider).peers.single);
  await controller.chooseStation(newStation: false);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('compact PTUs and fixed action fit at 360dp scale $scale', (
      tester,
    ) async {
      final container = await pumpSelection(tester, scale);
      final action = find.byKey(const Key('ptu-configure'));
      expect(
        action.hitTestable(),
        findsOneWidget,
        reason: 'available without scrolling',
      );
      final initialAction = tester.getRect(action);
      final firstRow = find.byType(PtuSelectionTile).first;
      expect(tester.getSize(firstRow).height, lessThan(scale == 1 ? 90 : 140));
      expect(find.text('讓每一台裝置，都確實上線。'), findsNothing);
      expect(find.text('已選 5 / 5 台'), findsOneWidget);

      await tester.ensureVisible(firstRow);
      await tester.tap(
        find.descendant(of: firstRow, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).selected, hasLength(4));
      expect(find.text('已選 4 / 5 台'), findsOneWidget);
      expect(buttonText('配置 4 台並開始監控'), findsOneWidget);
      final lastRow = find.byType(PtuSelectionTile).last;
      await tester.ensureVisible(lastRow);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(action),
        initialAction,
        reason: 'action remains pinned',
      );
      expect(
        tester.getRect(lastRow).bottom,
        lessThanOrEqualTo(initialAction.top),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('details preserve full MAC and mark unavailable signal', (
    tester,
  ) async {
    final container = await pumpSelection(tester, 1.5);
    final details = find.byTooltip('PTU #1 裝置資訊');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('MAC：90:2C:00:54:96:01'), findsOneWidget);
    expect(find.text('訊號：尚無讀值'), findsOneWidget);
    expect(find.textContaining('0 dBm'), findsNothing);
    expect(container.read(commissionProvider).selected, hasLength(5));
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('ptu-configure')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed auto-reset tile says so and offers 重試', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PtuSelectionTile(
            ptu: const {'mac': 'AA:BB', 'device_number': 7},
            selected: false,
            onChanged: null,
            blocked: true,
            blockedText: resetFailedText,
            resetLabel: '重試',
            onReset: () => tapped++,
          ),
        ),
      ),
    );
    expect(find.text('重置失敗（連線逾時），請靠近後重試'), findsOneWidget);
    expect(find.text('已屬於其他閘道器'), findsNothing);
    await tester.tap(find.text('重試'));
    expect(tapped, 1);
  });
}
