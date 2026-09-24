import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/demo_system.dart';

/// (A) suggestGateway 上限放寬到 50：先用 fleet-status 挑最小未用編號，只對
/// 那一個做 check-identity；不逐一查 1–50。
class FleetPickGateway extends DemoSystem {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add('$method $path');
    if (path.contains('fleet-status')) {
      // 站點 80 已用掉 1–9 號，10 號是最小的空號。
      return {
        'gateways': [
          for (int g = 1; g <= 9; g++)
            {
              'site_id': 80,
              'gateway_id': g,
              'mac': 'AA:BB:CC:00:00:${g.toString().padLeft(2, '0')}',
            },
        ],
      };
    }
    if (path.contains('check-identity')) {
      return {'exists': false, 'last_seen_mac': null};
    }
    return super.request(method, path, body);
  }
}

/// (B)1 星狀模式的掃描過濾：本 gateway（編號 1）的範圍是 device_number 1–5。
class StarInventoryGateway extends DemoSystem {
  StarInventoryGateway() {
    config.addAll({'fleet_joined': true, 'site_id': 80});
  }
  List<Map<String, dynamic>> nearby = [
    {'mac': 'AA:BB:CC:00:00:01', 'device_number': 0, 'rssi': -40},
    {'mac': 'AA:BB:CC:00:00:02', 'device_number': 3, 'rssi': -42},
    {'mac': 'AA:BB:CC:00:00:03', 'device_number': 8, 'rssi': -44},
  ];
  List<Map<String, dynamic>> attached = [];
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'scan_ble_discover') {
      return {'devices': nearby.map(Map<String, dynamic>.from).toList()};
    }
    if (op == 'get_ble_devices') {
      return {'devices': attached.map(Map<String, dynamic>.from).toList()};
    }
    if (op == 'assign_device_id') {
      final target = nearby.firstWhere((d) => d['mac'] == params['mac']);
      target['device_number'] = params['new_id'];
      return {'success': true};
    }
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _connectStar(
  StarInventoryGateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final controller = container.read(commissionProvider.notifier);
  await controller.prepare('https://example.invalid', '', offline: true);
  await controller.scan();
  await controller.connect(container.read(commissionProvider).peers.single);
  await controller.chooseStation(newStation: false);
  return (container, controller);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'suggestGateway picks the smallest free id from fleet-status with one '
    'check-identity call, not a 1..50 scan',
    () async {
      final fake = FleetPickGateway();
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', 'secret');
      fake.calls.clear();
      final (gw, kind) = await c.suggestGateway(80);
      expect(gw, 10);
      expect(kind, GatewaySuggestKind.online);
      expect(fake.calls.where((r) => r.contains('fleet-status')).length, 1);
      expect(fake.calls.where((r) => r.contains('check-identity')).length, 1);
    },
  );

  test(
    'star mode: out-of-range PTU is not preselected, cannot be selected '
    'directly, and reset-and-include frees it for a later scan',
    () async {
      final fake = StarInventoryGateway();
      final (container, controller) = await _connectStar(fake);
      addTearDown(container.dispose);
      final state = container.read(commissionProvider);
      expect(state.step, 4);
      expect(state.scannedTotal, 3);
      expect(state.pendingNext, 1);

      final inRangeFree = fake.nearby[0]; // device_number 0
      final inRangeUsed = fake.nearby[1]; // device_number 3
      final outOfRange = fake.nearby[2]; // device_number 8

      expect(controller.ptuOutOfRange(inRangeFree), isFalse);
      expect(controller.ptuOutOfRange(inRangeUsed), isFalse);
      expect(controller.ptuOutOfRange(outOfRange), isTrue);

      expect(state.selected, {inRangeFree['mac'], inRangeUsed['mac']});
      expect(state.selected.contains(outOfRange['mac']), isFalse);

      // Directly selecting the out-of-range PTU is refused.
      controller.select(outOfRange['mac'].toString(), true);
      expect(
        container.read(commissionProvider).selected.contains(
          outOfRange['mac'],
        ),
        isFalse,
      );

      // 「重置並納入」：new_id 255 然後重新掃描，之後就不再是範圍外。
      await controller.resetAndInclude(outOfRange['mac'].toString());
      expect(outOfRange['device_number'], 255);
      final after = container.read(commissionProvider);
      expect(after.pendingNext, 0);
      expect(
        controller.ptuOutOfRange(
          after.ptus.firstWhere((p) => p['mac'] == outOfRange['mac']),
        ),
        isFalse,
      );
    },
  );
}
