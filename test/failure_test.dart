import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/core/protocol.dart';

class TimedScan extends DemoSystem {
  @override
  Future<List<GatewayPeer>> scan() async {
    await Future<void>.delayed(const Duration(seconds: 16));
    return super.scan();
  }
}

class FaultSystem extends DemoSystem {
  bool failPoll = false;
  bool partial = false;
  int wifiBusyReplies = 0;
  Completer<void>? leaseDelay;
  Completer<void>? repairDelay;
  final commands = <String>[];
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add(op);
    if (op == 'get_net_status' && wifiBusyReplies-- > 0) {
      throw const GatewayFailure('busy');
    }
    if (op == 'get_ble_devices' && failPoll) {
      throw StateError('Lost connection');
    }
    final result = await super.command(op, params);
    if (op == 'join_fleet' && partial) {
      for (final d in devices.skip(1)) {
        d['connected'] = false;
      }
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.endsWith('/bot-monitor') && body?['enabled'] == false) {
      await leaseDelay?.future;
    }
    if (path.endsWith('/commands')) await repairDelay?.future;
    return super.request(method, path, body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late FaultSystem fake;
  late CommissioningController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fake = FaultSystem();
    container = ProviderContainer(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
      ],
    );
    controller = container.read(commissionProvider.notifier);
    await controller.prepare('https://example.invalid', '');
    await controller.scan();
    await controller.connect(container.read(commissionProvider).peers.single);
    await controller.configureWifi(1, 1, 'test', 'test-password');
  });
  tearDown(() => container.dispose());

  test('poll failure keeps monitoring on and verifies it', () async {
    await controller.discover();
    fake.failPoll = true;
    await controller.configurePtus();
    // Never leave the gateway with BLE / upload switched off.
    expect(fake.config['ble_enabled'], true);
    expect(fake.config['upload_paused'], false);
    expect(container.read(commissionProvider).error, isNotNull);
    expect(fake.commands.last, 'get_config');
  });
  test('WiFi polling tolerates handler still completing the switch', () async {
    fake.wifiBusyReplies = 3;
    await controller.configureWifi(1, 1, 'new-network', 'test-password');
    expect(container.read(commissionProvider).step, 3);
    expect(container.read(commissionProvider).error, isNull);
  });
  test('partial installation retains a verified reduced target', () async {
    await controller.discover();
    fake.partial = true;
    await controller.configurePtus();
    expect(fake.config['max_connections'], 1);
    expect(fake.config['ble_enabled'], true);
    expect(fake.config['upload_paused'], false);
    expect(container.read(commissionProvider).missing.length, 2);
  });
  test('late lease acquisition after cancellation is compensated', () async {
    fake.leaseDelay = Completer<void>();
    final operation = controller.online();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await controller.cancel();
    fake.leaseDelay!.complete();
    await operation;
    expect(fake.monitored, true);
    expect(container.read(commissionProvider).step, 1);
  });
  test('late repair response cannot undo cancellation', () async {
    fake.repairDelay = Completer<void>();
    final operation = controller.repair();
    await Future<void>.delayed(Duration.zero);
    await controller.cancel();
    fake.repairDelay!.complete();
    await operation;
    expect(container.read(commissionProvider).step, 1);
  });
  testWidgets('full scan window plus setup returns peers before deadline', (
    tester,
  ) async {
    final timed = TimedScan();
    final scope = ProviderContainer(
      overrides: [
        linkProvider.overrideWithValue(timed),
        apiProvider.overrideWithValue(timed),
      ],
    );
    addTearDown(scope.dispose);
    final c = scope.read(commissionProvider.notifier);
    final scan = c.scan();
    await tester.pump(const Duration(seconds: 16));
    await scan;
    expect(scope.read(commissionProvider).peers, hasLength(1));
    expect(scope.read(commissionProvider).error, isNull);
  });
}
