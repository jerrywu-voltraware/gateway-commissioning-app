import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
