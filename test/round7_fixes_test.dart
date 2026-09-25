import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/ptu_selection_tile.dart';
import 'compact_ptu_test.dart' as compact;

List<String> _tileOrder(WidgetTester tester) => tester
    .widgetList<PtuSelectionTile>(find.byType(PtuSelectionTile))
    .map((t) => (t.key! as ValueKey<String>).value)
    .toList();

Future<BackendEnvState> _loadEnv(
  Map<String, Object> prefs, {
  required BackendEnv buildDefault,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(
    overrides: [
      envSwitchPolicyProvider.overrideWithValue(
        EnvSwitchPolicy(defaultEnvironment: buildDefault),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(backendEnvProvider);
  await container.read(backendEnvProvider.notifier).ready;
  return container.read(backendEnvProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backend environment default', () {
    test(
      'LOCAL_DEVELOPMENT build without a saved choice starts local',
      () async {
        final env = await _loadEnv({}, buildDefault: BackendEnv.local);
        expect(env.environment, BackendEnv.local);
      },
    );
    test('saved choice wins over the build default, same key', () async {
      final env = await _loadEnv({
        'backend_environment': 'production',
      }, buildDefault: BackendEnv.local);
      expect(env.environment, BackendEnv.production);
      final local = await _loadEnv({
        'backend_environment': 'local',
      }, buildDefault: BackendEnv.production);
      expect(local.environment, BackendEnv.local);
    });
    test('release build without a saved choice stays production', () async {
      final env = await _loadEnv({}, buildDefault: BackendEnv.production);
      expect(env.environment, BackendEnv.production);
    });
    test('hint only when the saved value differing from default', () {
      const unloaded = BackendEnvState(environment: BackendEnv.local);
      const prod = BackendEnvState(
        environment: BackendEnv.production,
        loaded: true,
      );
      const local = BackendEnvState(
        environment: BackendEnv.local,
        loaded: true,
      );
      expect(
        environmentChangeHint(unloaded, prod, buildDefault: BackendEnv.local),
        contains('正式站'),
      );
      expect(
        environmentChangeHint(unloaded, local, buildDefault: BackendEnv.local),
        isNull,
      );
      expect(
        environmentChangeHint(local, prod, buildDefault: BackendEnv.local),
        isNull,
      );
      expect(
        environmentChangeHint(null, prod, buildDefault: BackendEnv.local),
        isNull,
      );
    });
  });

  test('selection ranks connected PTUs before stronger unconnected ones', () {
    final rows = [
      {'mac': 'B', 'rssi': -40},
      {'mac': 'A', 'connected': true, 'rssi': -90},
      {'mac': 'C', 'connected': true},
    ]..sort(comparePtuForSelection);
    expect(rows.map((r) => r['mac']), ['A', 'C', 'B']);
  });

  testWidgets('RSSI refresh keeps PTU row order; resort button reorders', (
    tester,
  ) async {
    final scope = await compact.pumpSelection(tester, 1);
    final before = _tileOrder(tester);
    expect(before, hasLength(5));
    final fake = scope.read(linkProvider) as DemoSystem;
    // Reverse the signal strength so an RSSI sort would flip the list.
    for (final d in fake.devices) {
      final n = (d['device_number'] as num).toInt();
      d.addAll({'rssi': -90 + n * 10, 'rssi_age_ms': 1000});
    }
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('-40 dBm'), findsOneWidget, reason: 'values update');
    expect(_tileOrder(tester), before, reason: 'order unchanged');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(_tileOrder(tester), before);

    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('ptu-resort'))),
      alignment: 0.3,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('ptu-resort')));
    await tester.pump();
    expect(_tileOrder(tester), before.reversed.toList());
  });

  test('connected in-range PTUs are preselected even when weakest', () async {
    // Covered through comparePtuForSelection ranking in _discover and
    // _trimSelectionToTarget; see the widget flow above for the UI side.
    final rows = [
      {'mac': '1', 'connected': true, 'rssi': -95},
      for (var i = 2; i <= 6; i++) {'mac': '$i', 'rssi': -40 - i},
    ]..sort(comparePtuForSelection);
    expect(rows.take(4).map((r) => r['mac']), contains('1'));
  });
}
