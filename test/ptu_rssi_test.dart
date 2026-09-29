import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/ptu_rssi.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'ptu_flow_test.dart' as fixture;
import 'compact_ptu_test.dart' as compact;
import 'package:gateway_commissioning/data/demo_system.dart';

class SignalGateway extends fixture.InventoryGateway {
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    if (op == 'get_ble_devices' && pending != null) {
      operations.add(op);
      return pending!.future;
    }
    return super.command(op, params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'five-second timer refreshes visible 閘道器 RSSI and stops in background',
    (tester) async {
      final scope = await compact.pumpSelection(tester, 1);
      final fake = scope.read(linkProvider) as DemoSystem;
      fake.devices.first.addAll({'rssi': -61, 'rssi_age_ms': 1000});
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('-61 dBm'), findsOneWidget);
      final c = scope.read(commissionProvider.notifier);
      c.setForeground(false);
      fake.devices.first['rssi'] = -80;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('上次 -61 dBm'), findsOneWidget);
      expect(find.text('-80 dBm'), findsNothing);
    },
  );
  test(
    'RSSI distinguishes unknown, scan, cache, recent and stale readings',
    () {
      expect(ptuRssiText({'rssi': 0}), 'RSSI —');
      expect(ptuRssiText({'rssi': -128}), 'RSSI —');
      expect(ptuRssiText({'rssi': -65}), '掃描 -65 dBm');
      expect(ptuRssiText({'rssi': -65, 'connected': true}), '快取 -65 dBm');
      expect(
        ptuRssiText({'rssi': -65, 'connected': true, 'rssi_age_ms': 5000}),
        '-65 dBm',
      );
      expect(
        ptuRssiText({'rssi': -65, 'connected': true, 'rssi_age_ms': 16000}),
        '上次 -65 dBm',
      );
      expect(ptuRssiText({'rssi': -65, 'rssi_stale': true}), '上次 -65 dBm');
    },
  );
  test(
    'refresh preserves candidates and order; missing connection becomes stale',
    () {
      final rows = refreshPtuSignals(
        [
          {'mac': 'AA:01', 'connected': true, 'rssi': -60, 'device_number': 3},
          {'mac': 'AA:02', 'rssi': -70},
          {'mac': 'AA:03', 'connected': true, 'rssi': -80},
        ],
        [
          {
            'mac': 'aa01',
            'connected': true,
            'rssi': -55,
            'rssi_age_ms': 4,
            'device_number': 0,
          },
          {'mac': 'AA:04', 'connected': true, 'rssi': -40},
        ],
      );
      expect(rows.map((r) => r['mac']), ['AA:01', 'AA:02', 'AA:03']);
      expect(rows.first['rssi'], -55);
      expect(rows.first['device_number'], 3);
      expect(ptuRssiText(rows[1]), '掃描 -70 dBm');
      expect(rows.last['connected'], false);
      expect(ptuRssiText(rows.last), '上次 -80 dBm');
    },
  );
  test(
    'poll updates signal without rescanning or changing selection; pause gates requests',
    () async {
      final fake = SignalGateway();
      fake.attached = [
        {'mac': 'AA:BB:CC:00:00:01', 'connected': true, 'rssi': -60},
      ];
      final (scope, c) = await fixture.connect(fake);
      addTearDown(scope.dispose);
      await c.chooseStation(newStation: false);
      final selection = scope.read(commissionProvider).selected.toSet();
      fake.operations.clear();
      fake.attached.single.addAll({'rssi': -72, 'rssi_age_ms': 5000});
      await c.refreshPtuRssi();
      expect(fake.operations, ['get_ble_devices']);
      expect(scope.read(commissionProvider).ptus.single['rssi'], -72);
      expect(scope.read(commissionProvider).selected, selection);
      c.setAutoRssi(false);
      await c.refreshPtuRssi();
      c.setAutoRssi(true);
      c.setForeground(false);
      await c.refreshPtuRssi();
      expect(fake.operations, ['get_ble_devices']);
      expect(scope.read(commissionProvider).ptus.single['rssi_stale'], true);
    },
  );
  test(
    'only one poll in flight and paused result cannot overwrite stale state',
    () async {
      final fake = SignalGateway();
      final (scope, c) = await fixture.connect(fake);
      addTearDown(scope.dispose);
      await c.chooseStation(newStation: false);
      fake.operations.clear();
      fake.pending = Completer<Map<String, dynamic>>();
      final first = c.refreshPtuRssi();
      await c.refreshPtuRssi();
      expect(fake.operations, ['get_ble_devices']);
      c.setAutoRssi(false);
      fake.pending!.complete({
        'devices': [
          {'mac': 'AA:BB:CC:00:00:01', 'rssi': -20, 'connected': true},
        ],
      });
      await first;
      expect(scope.read(commissionProvider).ptus.single['rssi'], -40);
      expect(scope.read(commissionProvider).ptus.single['rssi_stale'], true);
    },
  );
}
