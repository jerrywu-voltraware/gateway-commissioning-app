import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('existing station WiFi reset preserves identity and PTUs', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(demoProvider.notifier).set(true);
    final demo = container.read(demoSystemProvider);
    demo.config.addAll({
      'fleet_joined': true,
      'site_id': 80,
      'wifi_ssid': 'old-network',
    });
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    expect(
      container.read(commissionProvider).config['wifi_ssid'],
      'old-network',
    );
    final selected = container.read(commissionProvider).selected;
    await c.chooseStation(newStation: false, wifiOnly: true);
    await c.configureWifi(81, 1, 'new-network', 'password123');
    expect(container.read(commissionProvider).error, isNotNull);
    expect(demo.config['wifi_ssid'], 'old-network');
    await c.configureWifi(80, 1, 'new-network', 'password123');
    // The station is kept, so the upload is confirmed before step 6.
    var state = container.read(commissionProvider);
    expect(state.error, isNull);
    expect(state.step, 2);
    expect(state.checkPassed, isFalse);
    expect(state.config['wifi_only'], isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(commissionProvider).config['mqtt_connected'], isTrue);
    await c.passNetworkCheck();
    // Round 26: after the Wi-Fi works the station is chosen again (field:
    // another site's gateway went straight to the PTU scan).
    state = container.read(commissionProvider);
    expect(state.step, 2);
    expect(state.checkPassed, isTrue);
    expect(state.config['choose_station'], isTrue);
    expect(state.config['wifi_only'], isFalse);
    await c.chooseStation(newStation: false);
    state = container.read(commissionProvider);
    expect(state.step, 4);
    expect(state.config['wifi_ssid'], 'new-network');
    expect(state.selected, selected);
    expect(demo.config['site_id'], 80);
    expect(demo.config['fleet_joined'], isTrue);
  });
  for (final newStation in [false, true]) {
    test('existing station requires explicit choice new=$newStation', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(demoProvider.notifier).set(true);
      final demo = container.read(demoSystemProvider);
      demo.config['fleet_joined'] = true;
      demo.config['site_id'] = 80;
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      expect(
        container.read(commissionProvider).config['choose_station'],
        isTrue,
      );
      expect(container.read(commissionProvider).step, 2);
      await c.chooseStation(newStation: newStation);
      expect(demo.config['site_id'], 80);
      expect(container.read(commissionProvider).step, newStation ? 2 : 4);
      if (newStation) {
        await c.configureWifi(80, 1, 'test', 'password123');
        expect(container.read(commissionProvider).error, isNotNull);
        expect(demo.config['site_id'], 80);
        await c.configureWifi(81, 1, 'test', 'password123');
        expect(container.read(commissionProvider).error, isNull);
        expect(demo.config['site_id'], 81);
        expect(container.read(commissionProvider).step, 3);
      }
    });
  }
  test(
    'demo new installation assigns three PTUs and verifies three changing samples',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(demoProvider.notifier).set(true);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '');
      expect(container.read(commissionProvider).step, 1);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.configureWifi(1, 1, 'test-network', List.filled(12, 'x').join());
      expect(container.read(commissionProvider).step, 3);
      await c.online();
      await c.discover();
      expect(container.read(commissionProvider).selected.length, 3);
      await c.configurePtus();
      expect(container.read(commissionProvider).step, 6);
      await c.verify('https://example.invalid', '');
      final state = container.read(commissionProvider);
      expect(state.error, isNull);
      expect(state.step, 7);
      expect(state.verified, isTrue);
      expect(container.read(demoSystemProvider).monitored, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('demo_progress'), isNot(contains('password')));
    },
  );
}
