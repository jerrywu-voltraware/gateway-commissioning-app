import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/ptu_inventory.dart';

void main() {
  test(
    'merge keeps connected-only PTUs and uses live status for duplicate MACs',
    () {
      final rows = mergePtuInventory(
        [
          {'mac': 'aa:bb:cc:00:00:01', 'rssi': -30, 'connected': false},
          {'mac': 'AA:BB:CC:00:00:02', 'rssi': -20},
        ],
        [
          {'mac': 'AA:BB:CC:00:00:01', 'connected': true, 'device_number': 3},
          {'mac': 'AA:BB:CC:00:00:03', 'connected': true, 'device_number': 4},
        ],
      );
      expect(rows.length, 3);
      expect(rows.take(2).every((p) => p['connected'] == true), isTrue);
      expect(rows.first['device_number'], 3);
      expect(rows.first['rssi'], -30);
    },
  );
}
