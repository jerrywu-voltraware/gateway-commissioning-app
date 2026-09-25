// Round 9 phone test, second batch (dead ends after a killed step 8):
// 1. GatewayFailure('busy') is retried centrally in _command.
// 2. Step 7 with every selected PTU assigned: 開始驗證 / 恢復監控.
// 3. Scans drop assignedOk entries the gateway contradicts.
// 4. The first connect failure (133 unknownError, also during GATT setup)
//    is retried after a disconnect + short scan.
// 5. 「返回選擇 PTU」 rescans once, keeping selection and assignedOk.
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';

import 'round6_fixes_test.dart' show StaleAdapterPlatform;
import 'link_loss_test.dart' show DroppingLink, ready;

/// Answers 'busy' [busyLeft][op] times before running the op.
class BusyLink extends DroppingLink {
  final busyLeft = <String, int>{};

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final left = busyLeft[op] ?? 0;
    if (left > 0) {
      busyLeft[op] = left - 1;
      commands.add('$op:busy');
      throw const GatewayFailure('busy');
    }
    return super.command(op, params);
  }
}

/// discoverServices fails [failSetups] times with 133 unknownError.
class SetupFailPlatform extends StaleAdapterPlatform {
  int failSetups = 0;
  @override
  Future<List<BleService>> discoverServices(String id, bool descriptors) {
    calls.add('discover');
    if (failSetups > 0) {
      failSetups--;
      throw UniversalBleException(
        code: UniversalBleErrorCode.unknownError,
        message: 'GATT 133',
      );
    }
    return super.discoverServices(id, descriptors);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. busy is transient', () {
    test('busy 3 times in a row, then success', () async {
      final fake = BusyLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final messages = <String>[];
      container.listen(commissionProvider, (_, s) => messages.add(s.message));
      fake.busyLeft['join_fleet'] = 3;
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.commands.where((o) => o == 'join_fleet:busy'), hasLength(3));
      expect(fake.commands, contains('join_fleet'));
      expect(messages, contains(gatewayBusyText));
    });

    test('still busy after 10 retries is an error', () async {
      final fake = BusyLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.busyLeft['join_fleet'] = busyRetryLimit + 1;
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNotNull);
      expect(
        fake.commands.where((o) => o == 'join_fleet:busy'),
        hasLength(busyRetryLimit + 1),
      );
      expect(fake.commands, isNot(contains('join_fleet')));
    });
  });

  group('2. all configured is not a dead end', () {
    test('開始驗證 goes to step 9 without set_config/join_fleet', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.backToSelection();
      var s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(configureTargets(s), isEmpty);
      expect(configureLabel(s), '開始驗證');
      fake.commands.clear();
      await c.finishConfigured();
      s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(fake.commands, isNot(contains('set_config')));
      expect(fake.commands, isNot(contains('join_fleet')));
      expect(fake.commands, isNot(contains('assign_device_id')));
    });

    test('upload paused: 恢復監控 sends join_fleet, then step 9', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      fake.config['upload_paused'] = true;
      await c.backToSelection();
      var s = container.read(commissionProvider);
      expect(configureLabel(s), '恢復監控');
      fake.commands.clear();
      await c.finishConfigured();
      s = container.read(commissionProvider);
      expect(fake.commands, contains('join_fleet'));
      expect(fake.commands, isNot(contains('assign_device_id')));
      expect(s.step, 6);
    });
  });

  group('3. stale assignedOk', () {
    test('a rescan drops a PTU whose number no longer matches', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.backToSelection();
      final mac = fake.devices.first['mac'].toString();
      expect(container.read(commissionProvider).assignedOk, contains(mac));
      // Site re-deployed: this PTU was reset / moved out of range.
      fake.devices.first['device_number'] = 0;
      fake.devices.first['connected'] = false;
      await c.discover();
      final s = container.read(commissionProvider);
      expect(s.assignedOk, isNot(contains(mac)));
      expect(s.assignedOk, hasLength(2));
      expect(configureTargets(s), {mac});
      // Round 16b: 「剩餘」 once some are done.
      expect(configureLabel(s), '配置剩餘 1 台並開始監控');
    });
  });

  group('4. first connect failure', () {
    setUp(() {
      BleGatewayLink.staleSettle = Duration.zero;
      BleGatewayLink.retryGap = Duration.zero;
      BleGatewayLink.rescanWindow = const Duration(milliseconds: 10);
    });
    const peer = GatewayPeer('AA:BB:CC:DD:EE:FF', 'GIOS-S1', -28);

    test('133 during GATT setup is retried after disconnect + scan', () async {
      final platform = SetupFailPlatform()..failSetups = 1;
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await link.connect(peer);
      expect(link.firstConnectFailure, contains('GATT 133'));
      final second = platform.calls.lastIndexOf('connect');
      final firstDiscover = platform.calls.indexOf('discover');
      expect(firstDiscover, lessThan(second));
      expect(
        platform.calls.sublist(firstDiscover, second),
        contains('disconnect'),
      );
      expect((await link.command('ping'))['message'], '測試成功');
      await link.disconnect();
    });

    test('133 unknownError on connect: disconnect before the retry', () async {
      final platform = StaleAdapterPlatform()..failConnects = 1;
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await link.connect(peer);
      final connects = [
        for (var i = 0; i < platform.calls.length; i++)
          if (platform.calls[i] == 'connect') i,
      ];
      expect(connects, hasLength(2));
      expect(
        platform.calls.sublist(connects[0], connects[1]),
        contains('disconnect'),
      );
      await link.disconnect();
    });
  });

  group('5. back to step 7 rescans', () {
    test('discover runs, selection and assignedOk kept', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final before = container.read(commissionProvider);
      fake.commands.clear();
      await c.backToSelection();
      final s = container.read(commissionProvider);
      expect(fake.commands, contains('scan_ble_discover'));
      expect(s.step, 4);
      expect(s.selected, before.selected);
      expect(s.assignedOk, before.assignedOk);
    });
  });
}
