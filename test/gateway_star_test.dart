import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
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

  /// Gateway ids (besides this one) registered at site 80 in fleet-status.
  Set<int> registered = {};

  /// fleet-status fails once a PTU scan has started (backend unreachable).
  bool fleetDownDuringScan = false;
  bool _scanned = false;
  final resets = <String>[];
  int fleetCallsDuringScan = 0;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.contains('fleet-status') && _scanned) {
      fleetCallsDuringScan++;
      if (fleetDownDuringScan) throw Exception('offline');
      final base = await super.request(method, path, body);
      return {
        ...base,
        'gateways': [
          ...(base['gateways'] as List? ?? []),
          for (final g in registered) {'site_id': 80, 'gateway_id': g},
        ],
      };
    }
    return super.request(method, path, body);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'scan_ble_discover') {
      _scanned = true;
      return {'devices': nearby.map(Map<String, dynamic>.from).toList()};
    }
    if (op == 'get_ble_devices') {
      return {'devices': attached.map(Map<String, dynamic>.from).toList()};
    }
    if (op == 'assign_device_id') {
      if (params['new_id'] == 255) resets.add(params['mac'].toString());
      final target = nearby.firstWhere((d) => d['mac'] == params['mac']);
      target['device_number'] = params['new_id'];
      return {'success': true};
    }
    return super.command(op, params);
  }
}

/// (B)2 星狀模式：三顆範圍外 PTU（6/7/8，都屬未登記的 gateway 2），其中一顆
/// 重置時失敗（丟例外或 success:false），其餘兩顆仍要被重置並在重掃後可選。
class PartialResetFailureGateway extends StarInventoryGateway {
  PartialResetFailureGateway({required this.failingMac, this.throwOnReset = true}) {
    nearby = [
      {'mac': 'AA:BB:CC:00:00:04', 'device_number': 6, 'rssi': -40},
      {'mac': failingMac, 'device_number': 7, 'rssi': -42},
      {'mac': 'AA:BB:CC:00:00:06', 'device_number': 8, 'rssi': -44},
    ];
  }

  final String failingMac;
  final bool throwOnReset;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'assign_device_id' && params['mac'] == failingMac) {
      resets.add(params['mac'].toString());
      if (throwOnReset) throw const GatewayFailure('incomplete');
      return {'success': false};
    }
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _connectStar(
  StarInventoryGateway fake, {
  bool offline = true,
  GatewayTopology? topology,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  if (topology != null) {
    await container.read(topologyProvider.notifier).setTopology(topology);
  }
  final controller = container.read(commissionProvider.notifier);
  await controller.prepare(
    'https://example.invalid',
    offline ? '' : 'secret',
    offline: offline,
  );
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

  test(
    'star mode: PTU whose owner gateway is unregistered is auto-reset to 255 '
    'and becomes selectable after one rescan',
    () async {
      final fake = StarInventoryGateway(); // #8 belongs to gateway 2
      final (container, controller) = await _connectStar(fake, offline: false);
      addTearDown(container.dispose);
      final stale = fake.nearby[2];
      expect(fake.resets, [stale['mac']]);
      expect(fake.fleetCallsDuringScan, 1);
      expect(stale['device_number'], 255);
      final state = container.read(commissionProvider);
      expect(state.error, isNull);
      expect(state.pendingNext, 0);
      expect(state.starNotice, isEmpty);
      expect(state.scannedTotal, 3);
      expect(state.selected.contains(stale['mac']), isTrue);
      expect(
        controller.ptuOutOfRange(
          state.ptus.firstWhere((p) => p['mac'] == stale['mac']),
        ),
        isFalse,
      );
    },
  );

  test(
    'star mode: PTU owned by a registered gateway stays blocked and counts '
    'as belonging to another gateway',
    () async {
      final fake = StarInventoryGateway()..registered = {2};
      final (container, controller) = await _connectStar(fake, offline: false);
      addTearDown(container.dispose);
      final owned = fake.nearby[2];
      expect(fake.resets, isEmpty);
      expect(owned['device_number'], 8);
      final state = container.read(commissionProvider);
      expect(state.pendingNext, 1);
      expect(state.starNotice, isEmpty);
      expect(state.selected.contains(owned['mac']), isFalse);
      expect(controller.ptuOutOfRange(owned), isTrue);
    },
  );

  test(
    'star mode: when fleet-status fails nothing is auto-reset and a manual '
    'reset notice is shown',
    () async {
      final fake = StarInventoryGateway()..fleetDownDuringScan = true;
      final (container, controller) = await _connectStar(fake, offline: false);
      addTearDown(container.dispose);
      expect(fake.resets, isEmpty);
      final state = container.read(commissionProvider);
      expect(state.error, isNull);
      expect(state.starNotice, starOwnerUnknownText);
      expect(state.pendingNext, 1);
      expect(controller.ptuOutOfRange(fake.nearby[2]), isTrue);
    },
  );

  test('direct mode never auto-resets PTU ids', () async {
    final fake = StarInventoryGateway();
    final (container, controller) = await _connectStar(
      fake,
      offline: false,
      topology: GatewayTopology.direct,
    );
    addTearDown(container.dispose);
    expect(fake.resets, isEmpty);
    expect(fake.fleetCallsDuringScan, 0);
    expect(fake.nearby[2]['device_number'], 8);
    final state = container.read(commissionProvider);
    expect(state.scannedTotal, 3);
    expect(state.pendingNext, 0);
    expect(state.starNotice, isEmpty);
    expect(controller.ptuOutOfRange(fake.nearby[2]), isFalse);
  });

  test(
    'star mode: one stale PTU throwing during auto-reset does not fail the '
    'whole discover; the others are still reset and rescanned',
    () async {
      const failingMac = 'AA:BB:CC:00:00:05';
      final fake = PartialResetFailureGateway(failingMac: failingMac);
      final (container, controller) = await _connectStar(fake, offline: false);
      addTearDown(container.dispose);

      expect(fake.resets, containsAll(['AA:BB:CC:00:00:04', failingMac, 'AA:BB:CC:00:00:06']));

      final state = container.read(commissionProvider);
      expect(state.error, isNull);

      final reset1 = state.ptus.firstWhere(
        (p) => p['mac'] == 'AA:BB:CC:00:00:04',
      );
      final failed = state.ptus.firstWhere((p) => p['mac'] == failingMac);
      final reset2 = state.ptus.firstWhere(
        (p) => p['mac'] == 'AA:BB:CC:00:00:06',
      );
      expect(controller.ptuOutOfRange(reset1), isFalse);
      expect(controller.ptuOutOfRange(failed), isTrue);
      expect(failed['device_number'], 7);
      expect(controller.ptuOutOfRange(reset2), isFalse);
      expect(state.pendingNext, 1);
    },
  );

  test(
    'star mode: one stale PTU reporting success:false during auto-reset '
    'still counts toward pendingNext without failing discover',
    () async {
      const failingMac = 'AA:BB:CC:00:00:05';
      final fake = PartialResetFailureGateway(
        failingMac: failingMac,
        throwOnReset: false,
      );
      final (container, controller) = await _connectStar(fake, offline: false);
      addTearDown(container.dispose);

      expect(fake.resets, containsAll(['AA:BB:CC:00:00:04', failingMac, 'AA:BB:CC:00:00:06']));

      final state = container.read(commissionProvider);
      expect(state.error, isNull);

      final failed = state.ptus.firstWhere((p) => p['mac'] == failingMac);
      expect(controller.ptuOutOfRange(failed), isTrue);
      expect(failed['device_number'], 7);
      expect(state.pendingNext, 1);
    },
  );
}
