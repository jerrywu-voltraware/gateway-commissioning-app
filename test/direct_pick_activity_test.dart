import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';
import 'package:gateway_commissioning/presentation/direct_pick_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

const _mac = 'AA:BB:CC:00:00:02';
const _other = 'AA:BB:CC:00:00:03';
const _pick = DirectStatus(state: DirectState.connected, ptuMac: _mac);

Widget _app({
  DirectStatus? direct = _pick,
  bool busy = false,
  String? identifiedMac,
  bool identifyAvailable = true,
  bool unavailable = false,
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
            padding: const EdgeInsets.all(10),
            child: DirectPickActivity(
              key: const Key('direct-pick-activity'),
              direct: direct,
              busy: busy,
              identifiedMac: identifiedMac,
              identifyAvailable: identifyAvailable,
              unavailable: unavailable,
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

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('360x640 ${brightness.name} $scale: compact actual states', (
        tester,
      ) async {
        _phone(tester);
        for (final direct in [
          null,
          for (final state in DirectState.values)
            DirectStatus(state: state, ptuMac: _mac),
          const DirectStatus(
            state: DirectState.connected,
            ptuMac: _mac,
            selectReason: 'ambiguous',
          ),
        ]) {
          await tester.pumpWidget(
            _app(
              direct: direct,
              busy: true,
              brightness: brightness,
              scale: scale,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(
            find.byKey(const Key('direct-pick-activity')),
          );
          expect(rect.height, lessThanOrEqualTo(110));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(find.byIcon(Icons.router_outlined), findsOneWidget);
          expect(find.byIcon(Icons.ev_station_outlined), findsOneWidget);
          expect(find.byIcon(Icons.check_circle), findsNothing);
        }
      });
    }
  }

  testWidgets('search motion never creates a PTU or a successful link', (
    tester,
  ) async {
    const scanning = DirectStatus(state: DirectState.scanning);
    await tester.pumpWidget(_app(direct: scanning, busy: true));
    final wave = find.byKey(const Key('direct-pick-search-wave'));
    final initial = tester.widget<Transform>(wave).transform.entry(0, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<Transform>(wave).transform.entry(0, 0),
      greaterThan(initial),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('閘道器正在搜尋 PTU'), findsOneWidget);
    expect(find.byKey(const Key('direct-pick-link-selected')), findsNothing);
    expect(scanning.pickedMac, isNull);

    await tester.pumpWidget(
      _app(
        direct: const DirectStatus(state: DirectState.connecting, ptuMac: _mac),
        busy: true,
      ),
    );
    expect(find.text('閘道器正在連線 PTU'), findsOneWidget);
    expect(find.byKey(const Key('direct-pick-link-selected')), findsNothing);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('direct-pick-link-selected')), findsOneWidget);
    expect(find.text('已找到 PTU，請辨識此樁'), findsOneWidget);
    expect(wave, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('identify acknowledgement is specific to the current MAC', (
    tester,
  ) async {
    await tester.pumpWidget(_app(identifiedMac: 'aa-bb-cc-00-00-02'));
    expect(find.text('已送出辨識，請確認燈號'), findsOneWidget);
    expect(find.textContaining('已完成'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    await tester.pumpWidget(
      _app(
        direct: const DirectStatus(
          state: DirectState.connected,
          ptuMac: _other,
        ),
        identifiedMac: _mac,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已找到 PTU，請辨識此樁'), findsOneWidget);
    expect(find.text('已送出辨識，請確認燈號'), findsNothing);
  });

  testWidgets('ambiguous pick keeps a warning without claiming confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        direct: const DirectStatus(
          state: DirectState.connected,
          ptuMac: _mac,
          selectReason: 'ambiguous',
        ),
      ),
    );
    expect(find.byKey(const Key('direct-pick-ambiguous')), findsOneWidget);
    expect(find.text('訊號相近，請辨識此樁'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('firmware without PTU identify does not require that action', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(identifyAvailable: false, scale: 1.3));
    await tester.pumpAndSettle();
    expect(find.text('已找到 PTU，請確認是眼前此樁'), findsOneWidget);
    expect(find.textContaining('請辨識'), findsNothing);
    expect(find.textContaining('已確認'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty, missing, malformed or unavailable links stay unselected',
    (tester) async {
      for (final direct in [
        null,
        const DirectStatus(state: DirectState.noCandidate),
        const DirectStatus(state: DirectState.boundMissing, boundMac: _mac),
        const DirectStatus(state: DirectState.connected),
      ]) {
        await tester.pumpWidget(_app(direct: direct));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('direct-pick-link-selected')),
          findsNothing,
        );
        expect(find.byKey(const Key('direct-pick-search-wave')), findsNothing);
        expect(find.text('已找到 PTU，請辨識此樁'), findsNothing);
      }
      await tester.pumpWidget(_app(busy: true, identifiedMac: _mac));
      await tester.pumpWidget(
        _app(busy: true, identifiedMac: _mac, unavailable: true),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-pick-link-selected')), findsNothing);
      expect(find.text('已送出辨識，請確認燈號'), findsNothing);
      expect(find.text('連線待確認，請依提示重試'), findsOneWidget);
    },
  );

  testWidgets(
    'idle, reduced motion, disabled tickers and dispose stop motion',
    (tester) async {
      const scanning = DirectStatus(state: DirectState.scanning);
      await tester.pumpWidget(_app(direct: scanning, busy: true));
      final wave = find.byKey(const Key('direct-pick-search-wave'));
      expect(wave, findsOneWidget);
      for (final flags in [
        (false, false, true),
        (true, true, true),
        (true, false, false),
      ]) {
        await tester.pumpWidget(
          _app(
            direct: scanning,
            busy: flags.$1,
            disableAnimations: flags.$2,
            tickerEnabled: flags.$3,
          ),
        );
        expect(wave, findsNothing);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      }
      await tester.pumpWidget(_app(direct: scanning, busy: true));
      expect(wave, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('real direct panel keeps full MAC, RSSI and confirmation gate', (
    tester,
  ) async {
    _phone(tester);
    final fake = PickGateway();
    late ProviderContainer container;
    late CommissioningController controller;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      final topology = container.read(topologyProvider.notifier);
      await topology.ready;
      await topology.setTopology(GatewayTopology.direct);
      controller = container.read(commissionProvider.notifier);
      await controller.prepare('https://example.invalid', '', offline: true);
      await controller.scan();
      await controller.connect(container.read(commissionProvider).peers.single);
      await controller.chooseStation(newStation: false);
    });
    addTearDown(container.dispose);
    expect(container.read(commissionProvider).step, 4);
    expect(directConfirmReady(container.read(commissionProvider)), isFalse);
    final originalOperations = fake.ops.length;
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: gatewayTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('辨識此樁')),
              body: const SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: DirectStatusPanel(actionsInBar: true),
              ),
              bottomNavigationBar: const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: DirectPickActions(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DirectPickActivity), findsOneWidget);
      expect(find.byKey(const Key('direct-linked')), findsOneWidget);
      expect(
        tester.widget<MacText>(find.byKey(const Key('direct-linked'))).mac,
        _mac,
      );
      expect(find.byKey(const Key('direct-rssi')), findsOneWidget);
      final activity = tester.getRect(find.byType(DirectPickActivity));
      expect(activity.height, lessThanOrEqualTo(110));
      expect(activity.left, greaterThanOrEqualTo(0));
      expect(activity.right, lessThanOrEqualTo(360));
      expect(directConfirmReady(container.read(commissionProvider)), isFalse);
    }
    expect(fake.ops.length, originalOperations);
  });
}
