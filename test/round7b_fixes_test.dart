import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'link_loss_test.dart' show DroppingLink, manualRelinkOnly, ready;

/// Drops the phone link on the [dropOnCall]-th [dropOp] command, throwing
/// [error] (what BleGatewayLink really surfaces with the adapter off).
class AdapterOffLink extends DroppingLink {
  String? dropOp;
  int dropOnCall = 1;
  Object error = const GatewayFailure('disconnected');
  int _seen = 0;
  final ops = <String>[];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    ops.add(op);
    if (!down && op == dropOp && ++_seen == dropOnCall) {
      down = true;
      dropOp = null;
      throw error;
    }
    return super.command(op, params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Manual 「重新連線並繼續」 path (round 13: automatic otherwise).
  manualRelinkOnly();

  // What BleGatewayLink.command raises while the phone's adapter is off:
  // normalizeBleError(deviceDisconnected) → disconnected, any other
  // UniversalBleException → ble_error, `_rx == null` → not_connected, and
  // the link's own epoch check after a disconnect() → 'cancelled'.
  final adapterOffErrors = <String, Object>{
    'disconnected': normalizeBleError(
      UniversalBleException(
        code: UniversalBleErrorCode.deviceDisconnected,
        message: 'Device disconnected',
      ),
    ),
    'ble_error': normalizeBleError(
      UniversalBleException(
        code: UniversalBleErrorCode.unknownError,
        message: 'Bluetooth adapter is off',
      ),
    ),
    'not_connected': const GatewayFailure('not_connected'),
    'link cancelled': const GatewayFailure('cancelled'),
  };

  // get_ble_devices calls: 1 = scan, 2 = assignment read-back,
  // 3 = first poll of the connection wait.
  for (final call in [2, 3]) {
    for (final entry in adapterOffErrors.entries) {
      test('adapter off (${entry.key}) at get_ble_devices #$call keeps '
          'step 8 with the resume banner', () async {
        final fake = AdapterOffLink()
          ..dropOp = 'get_ble_devices'
          ..dropOnCall = call
          ..error = entry.value;
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        await c.configurePtus();
        final s = container.read(commissionProvider);
        expect(s.step, 5, reason: 'never back to step 2');
        expect(s.error, phoneLinkLostText);
        expect(s.resumePending, isTrue);
        expect(s.assignedOk, hasLength(3));
        expect(configureLabel(s), startsWith('重新連線並繼續'));
        expect(s.message, isNot(contains('已取消')));
      });
    }
  }

  test(
    'adapter off during an assignment (link cancelled) keeps the rest',
    () async {
      final fake = AdapterOffLink()
        ..dropOp = 'assign_device_id'
        ..dropOnCall = 2
        ..error = const GatewayFailure('cancelled');
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.step, 5);
      expect(s.error, phoneLinkLostText);
      expect(s.assignedOk, hasLength(1));
      expect(configureLabel(s), '重新連線並繼續（剩 2 台）');
    },
  );

  test('isStep8LinkLoss: link cancelled only while the run is current', () {
    expect(isStep8LinkLoss(const GatewayFailure('cancelled'), true), isTrue);
    expect(isStep8LinkLoss(const GatewayFailure('cancelled'), false), isFalse);
    expect(
      isStep8LinkLoss(const GatewayFailure('bluetooth_off'), false),
      isTrue,
    );
    expect(isStep8LinkLoss(const GatewayFailure('timeout'), true), isFalse);
  });

  test('「取消操作」 at step 8 keeps progress instead of step 2', () async {
    final fake = AdapterOffLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final run = c.configurePtus();
    await Future<void>.delayed(Duration.zero);
    await c.stopStep8();
    await run;
    final s = container.read(commissionProvider);
    expect(s.step, 5);
    expect(s.resumePending, isTrue);
    expect(s.error, isNot(const GatewayFailure('cancelled').message));
    expect(configureLabel(s), startsWith('重新連線並繼續'));
  });

  test('reconnect shows the link stages on the first connect too', () async {
    final stages = <String>[];
    final fake = _StagedLink();
    final (container, _) = await ready(fake);
    addTearDown(container.dispose);
    container.listen(commissionProvider, (_, next) => stages.add(next.message));
    final c = container.read(commissionProvider.notifier);
    await c.connect(container.read(commissionProvider).peers.single);
    expect(stages, contains('正在連線閘道器'));
  });

  test(
    'resume with everything on the gateway: done without join_fleet',
    () async {
      final fake = AdapterOffLink()
        ..dropOp = 'get_ble_devices'
        ..dropOnCall = 2;
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      expect(container.read(commissionProvider).resumePending, isTrue);
      // Meanwhile the gateway connected all of them and resumed upload.
      for (final d in fake.devices) {
        d['connected'] = true;
        d['notify_enabled'] = true;
      }
      fake.config
        ..['upload_paused'] = false
        ..['max_connections'] = 5;
      fake.ops.clear();
      await c.resumeAssign();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.ops, isNot(contains('join_fleet')));
      expect(fake.ops, isNot(contains('assign_device_id')));
      expect(s.ptus, hasLength(3));
      expect(commissionSummaryText(s), contains('本機配置 3 台'));
    },
  );

  test('resume that cannot confirm monitoring offers retry and skip', () async {
    final fake = AdapterOffLink()
      ..dropOp = 'get_ble_devices'
      ..dropOnCall = 2;
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    await c.configurePtus();
    // One PTU never reports data (the gateway did not resume monitoring).
    fake.devices.first['zombie'] = true;
    await c.resumeAssign();
    var s = container.read(commissionProvider);
    expect(fake.ops, contains('join_fleet'));
    expect(s.monitorUnconfirmed, isTrue);
    expect(s.resumePending, isTrue, reason: '重試 = 重新連線並繼續');
    expect(s.error, contains('略過'));
    expect(s.step, 5);
    c.skipMonitorConfirm();
    s = container.read(commissionProvider);
    expect(s.step, 6);
    expect(s.monitorUnconfirmed, isFalse);
  });

  test('2 already on the gateway + 1 assigned now = 本機配置 3 台', () async {
    final fake = AdapterOffLink();
    // The gateway already took #1 and #2 (connected) but the user ticks
    // only the third one.
    for (final (i, d) in fake.devices.take(2).indexed) {
      d
        ..['device_number'] = i + 1
        ..['connected'] = true
        ..['notify_enabled'] = true;
    }
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final macs = fake.devices.map((d) => d['mac'].toString()).toList();
    c.select(macs[0], false);
    c.select(macs[1], false);
    c.select(macs[2], true);
    var s = container.read(commissionProvider);
    expect(configureLabel(s), '配置 1 台並開始監控');
    await c.configurePtus();
    s = container.read(commissionProvider);
    expect(s.step, 6);
    expect(s.ptus, hasLength(3));
    expect(s.assignedOk, containsAll(macs));
    expect(commissionSummaryText(s), contains('本機配置 3 台'));
  });

  test('button count = selected − assignedOk', () {
    const s = CommissionState(
      selected: {'A', 'B', 'C', 'D', 'E'},
      assignedOk: {'A', 'B', 'C', 'D'},
    );
    // Round 16b: 「剩餘」 once some are done.
    expect(configureLabel(s), '配置剩餘 1 台並開始監控');
    expect(configureTargets(s), {'E'});
  });

  test('a PTU the gateway connects after the scan is preselected', () async {
    final fake = AdapterOffLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    await container.read(topologyProvider.notifier).setStarCount(2);
    final macs = fake.devices.map((d) => d['mac'].toString()).toList();
    expect(container.read(commissionProvider).selected, {macs[0], macs[1]});
    fake.devices[2]
      ..['connected'] = true
      ..['device_number'] = 3;
    await c.refreshPtuRssi();
    expect(
      container.read(commissionProvider).selected,
      {macs[0], macs[2]},
      reason: 'connected #3 replaces the weakest unconnected one',
    );
  });

  test('a user edit is never overridden by the refresh', () async {
    final fake = AdapterOffLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final macs = fake.devices.map((d) => d['mac'].toString()).toList();
    c.select(macs[2], false);
    fake.devices[2]['connected'] = true;
    await c.refreshPtuRssi();
    expect(container.read(commissionProvider).selected, {macs[0], macs[1]});
  });
}

class _StagedLink extends AdapterOffLink {
  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('正在連線閘道器');
    await super.connect(peer, onStage: onStage);
  }
}
