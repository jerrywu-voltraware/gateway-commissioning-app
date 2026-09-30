import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/progress_checklist.dart';
import 'package:gateway_commissioning/data/demo_system.dart';

/// Backend heartbeats change independently of APP reads. Only online's waits
/// use real durations, advanced by the widget test clock without real hardware.
class _HeartbeatGateway extends DemoSystem {
  bool useRealWaits = false;
  String heartbeat = '2026-09-30T23:40:00.000';
  bool backendOnline = true, mqttOnline = true;
  int heartbeatReads = 0, leases = 0;

  @override
  bool get demo => !useRealWaits;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await super.request(method, path, body);
    if (path.contains('fleet-status')) {
      heartbeatReads++;
      for (final row in response['gateways'] as List) {
        (row as Map).addAll(<String, dynamic>{
          'last_heartbeat': heartbeat,
          'online': backendOnline,
          'mqtt_connected': mqttOnline,
        });
      }
    }
    if (method == 'PATCH' && path.endsWith('/bot-monitor')) leases++;
    return response;
  }
}

Future<(ProviderContainer, CommissioningController, _HeartbeatGateway)> _ready(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final gateway = _HeartbeatGateway();
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(gateway),
      apiProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  final c = container.read(commissionProvider.notifier);
  await tester.runAsync(() async {
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.star);
    await c.prepare('https://example.invalid', '');
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await c.configureWifi(1, 1, 'Demo-2.4G', 'test-password');
  });
  expect(container.read(commissionProvider).step, 3);
  gateway.useRealWaits = true;
  gateway.heartbeatReads = 0;
  gateway.leases = 0;
  return (container, c, gateway);
}

Future<void> _seconds(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('a heartbeat arriving at 3.2 seconds advances before 5 seconds', (
    tester,
  ) async {
    final (container, c, gateway) = await _ready(tester);
    final run = c.online();
    await tester.pump();
    expect(
      container.read(commissionProvider).checklist!.isDone(onlineItemBeat1),
      isTrue,
      reason:
          '${container.read(commissionProvider).step} '
          '${container.read(commissionProvider).error} '
          '${container.read(commissionProvider).message}',
    );
    await _seconds(tester, 3);
    expect(container.read(commissionProvider).busy, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    gateway.heartbeat = '2026-09-30T23:40:03.200';
    await tester.pump(const Duration(milliseconds: 800));
    expect(container.read(commissionProvider).busy, isFalse);
    await run;
    final state = container.read(commissionProvider);
    expect(state.step, 4);
    expect(state.error, isNull);
    expect(state.checklist!.allDone, isTrue);
    expect(gateway.leases, 1);
  });

  testWidgets('repeated timestamps and offline or MQTT-down replies never '
      'count as sustained online', (tester) async {
    final (container, c, gateway) = await _ready(tester);
    final run = c.online();
    await tester.pump();
    await _seconds(tester, 10);
    expect(gateway.heartbeatReads, greaterThan(2));
    expect(container.read(commissionProvider).step, 3);
    expect(
      container.read(commissionProvider).checklist!.isDone(onlineItemBeat2),
      isFalse,
    );
    expect(gateway.leases, 0);

    gateway.backendOnline = false;
    gateway.heartbeat = '2026-09-30T23:40:11.000';
    await _seconds(tester, 1);
    gateway.backendOnline = true;
    gateway.mqttOnline = false;
    gateway.heartbeat = '2026-09-30T23:40:12.000';
    await _seconds(tester, 1);
    expect(container.read(commissionProvider).step, 3);
    gateway.mqttOnline = true;
    await _seconds(tester, 1);
    expect(container.read(commissionProvider).step, 3);
    expect(gateway.leases, 0);

    gateway.heartbeat = '2026-09-30T23:40:14.000';
    await _seconds(tester, 1);
    await run;
    expect(container.read(commissionProvider).step, 4);
    expect(gateway.leases, 1);
  });

  testWidgets('cancelling the heartbeat wait ignores a later heartbeat', (
    tester,
  ) async {
    final (container, c, gateway) = await _ready(tester);
    final run = c.online();
    await tester.pump();
    await _seconds(tester, 2);
    await c.cancel();
    final reads = gateway.heartbeatReads;
    gateway.heartbeat = '2026-09-30T23:40:03.000';
    await _seconds(tester, 1);
    await run;
    expect(container.read(commissionProvider).step, 1);
    expect(container.read(commissionProvider).busy, isFalse);
    expect(gateway.heartbeatReads, reads);
    expect(gateway.leases, 0);
  });
}
