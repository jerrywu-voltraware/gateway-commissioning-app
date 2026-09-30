import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _stamp(int second) =>
    DateTime.utc(2030, 1, 1, 0, 0, second).toIso8601String();

/// Data arrival is independent of reads. Provisioning uses DemoSystem's short
/// waits; verification uses the controller's production delays on the test clock.
class _VerificationGateway extends DemoSystem {
  _VerificationGateway(this.now) {
    devices.removeRange(1, devices.length);
    // The gateway has already acknowledged commissioning's upload mode.
    config.addAll({'ds_enabled': true, 'ds_min_ms': 1000, 'ds_max_ms': 1000});
  }

  final DateTime Function() now;
  bool useRealWaits = false;
  String timestamp = _stamp(0);
  bool dataOnline = true, allOk = true;
  int errorNumber = 0;
  num lagSeconds = 0;
  String? reportedMac;
  final readTimes = <DateTime>[];
  int activeReads = 0, maxActiveReads = 0;
  int? holdRead;
  Completer<void>? hold;

  @override
  bool get demo => !useRealWaits;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (useRealWaits && path.contains('verify-installation')) {
      return {'all_ok': allOk};
    }
    if (!useRealWaits || !path.startsWith('/api/latest')) {
      return super.request(method, path, body);
    }
    readTimes.add(now());
    activeReads++;
    if (activeReads > maxActiveReads) maxActiveReads = activeReads;
    final response = <String, dynamic>{
      'items': [
        for (final device in devices.where((d) => d['connected'] == true))
          {
            'device_id': device['device_number'],
            'ptu': {'ptu_mac_addr': reportedMac ?? device['mac']},
            'online': dataOnline,
            'lag_seconds': lagSeconds,
            'error_num': errorNumber,
            'ts': timestamp,
          },
      ],
    };
    try {
      if (readTimes.length == holdRead) await hold!.future;
      return response;
    } finally {
      activeReads--;
    }
  }
}

Future<(ProviderContainer, CommissioningController, _VerificationGateway)>
_ready(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final gateway = _VerificationGateway(tester.binding.clock.now);
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(gateway),
      apiProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  final controller = container.read(commissionProvider.notifier);
  await tester.runAsync(() async {
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.star);
    await controller.prepare('https://example.invalid', '');
    await controller.scan();
    await controller.connect(container.read(commissionProvider).peers.single);
    await controller.configureWifi(1, 1, 'Demo-2.4G', 'test-password');
    await controller.online();
    await controller.discover();
    await controller.configurePtus();
  });
  final state = container.read(commissionProvider);
  expect(state.step, 6);
  expect(state.selected, hasLength(1));
  expect(state.ptus.single['device_number'], 1);
  expect(buildModeTook(state), isTrue);
  gateway.useRealWaits = true;
  return (container, controller, gateway);
}

Future<void> _seconds(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void _pending(ProviderContainer container, int count) {
  final state = container.read(commissionProvider);
  expect(state.step, 6);
  expect(state.busy, isTrue);
  expect(state.verified, isFalse);
  expect(state.verifyCounts[1] ?? 0, count);
}

void main() {
  testWidgets('verification reads at 0, 3 and 6 seconds and completes only '
      'after three actual timestamp updates', (tester) async {
    final (container, controller, gateway) = await _ready(tester);
    final run = controller.verify(productionApiBase, 'test-password');
    await tester.pump();
    _pending(container, 1);
    expect(gateway.readTimes, hasLength(1));

    await tester.pump(const Duration(milliseconds: 2999));
    expect(gateway.readTimes, hasLength(1));
    gateway.timestamp = _stamp(3);
    await tester.pump(const Duration(milliseconds: 1));
    _pending(container, 2);
    expect(gateway.readTimes, hasLength(2));

    await tester.pump(const Duration(milliseconds: 2999));
    _pending(container, 2);
    expect(gateway.readTimes, hasLength(2));
    gateway.timestamp = _stamp(6);
    await tester.pump(const Duration(milliseconds: 1));
    await run;
    final state = container.read(commissionProvider);
    expect(state.step, 7);
    expect(state.verified, isTrue);
    expect(state.verifyCounts, {1: 3});
    expect(state.error, isNull);
    expect(gateway.readTimes, hasLength(3));
    expect(
      gateway.readTimes.map((at) => at.difference(gateway.readTimes.first)),
      [Duration.zero, const Duration(seconds: 3), const Duration(seconds: 6)],
    );
    expect(gateway.maxActiveReads, 1);
    // Stop the completed page's unrelated 15-second health refresh timer.
    await controller.cancel();
  });

  testWidgets('faster reads cannot count repeated, offline, erroring or late '
      'rows, and all_ok still blocks completion', (tester) async {
    final (container, controller, gateway) = await _ready(tester);
    final run = controller.verify(productionApiBase, 'test-password');
    await tester.pump();
    _pending(container, 1);
    await _seconds(tester, 6);
    expect(gateway.readTimes, hasLength(3));
    _pending(container, 1);

    gateway.dataOnline = false;
    gateway.timestamp = _stamp(9);
    await _seconds(tester, 3);
    _pending(container, 1);
    gateway.dataOnline = true;
    gateway.errorNumber = 3;
    gateway.timestamp = _stamp(12);
    await _seconds(tester, 3);
    _pending(container, 1);
    gateway.errorNumber = 0;
    gateway.lagSeconds = 75;
    gateway.timestamp = _stamp(15);
    await _seconds(tester, 3);
    _pending(container, 1);

    // Fixing the flags on an already-seen invalid timestamp is not a new row.
    gateway.lagSeconds = 0;
    await _seconds(tester, 3);
    _pending(container, 1);
    gateway.timestamp = _stamp(21);
    await _seconds(tester, 3);
    _pending(container, 2);
    gateway.timestamp = _stamp(24);
    gateway.allOk = false;
    await _seconds(tester, 3);
    _pending(container, 3);
    expect(container.read(commissionProvider).verifyPassed, isFalse);
    gateway.allOk = true;
    await _seconds(tester, 3);
    await run;
    expect(container.read(commissionProvider).verified, isTrue);
    expect(container.read(commissionProvider).verifyCounts, {1: 3});
    await controller.cancel();
  });

  testWidgets('the same device number with another MAC never contributes '
      'to verification', (tester) async {
    final (container, controller, gateway) = await _ready(tester);
    gateway.reportedMac = 'AA:BB:CC:00:00:FF';
    final run = controller.verify(productionApiBase, 'test-password');
    await tester.pump();
    _pending(container, 0);
    gateway.reportedMac = null;
    gateway.timestamp = _stamp(3);
    await _seconds(tester, 3);
    _pending(container, 1);
    gateway.reportedMac = 'AA:BB:CC:00:00:FF';
    gateway.timestamp = _stamp(6);
    await _seconds(tester, 3);
    await run;
    final state = container.read(commissionProvider);
    expect(state.verified, isFalse);
    expect(state.busy, isFalse);
    expect(state.error, isNotNull);
    expect(state.errorDetail, contains('backend MAC'));
    expect(state.verifyCounts, isEmpty);
    final reads = gateway.readTimes.length;
    await _seconds(tester, 9);
    expect(gateway.readTimes, hasLength(reads));
  });

  testWidgets('cancellation ignores an in-flight result and stops further '
      'verification reads', (tester) async {
    final (container, controller, gateway) = await _ready(tester);
    gateway.holdRead = 2;
    gateway.hold = Completer<void>();
    final run = controller.verify(productionApiBase, 'test-password');
    await tester.pump();
    _pending(container, 1);
    gateway.timestamp = _stamp(3);
    await _seconds(tester, 3);
    expect(gateway.activeReads, 1);
    expect(gateway.readTimes, hasLength(2));
    await controller.cancel();
    final afterCancel = container.read(commissionProvider);
    expect(afterCancel.step, 1);
    expect(afterCancel.verified, isFalse);
    gateway.hold!.complete();
    await tester.pump();
    await run;
    await _seconds(tester, 12);
    final state = container.read(commissionProvider);
    expect(state.step, 1);
    expect(state.busy, isFalse);
    expect(state.verified, isFalse);
    expect(state.verifyCounts, afterCancel.verifyCounts);
    expect(state.verifyFeed, afterCancel.verifyFeed);
    expect(gateway.readTimes, hasLength(2));
    expect(gateway.activeReads, 0);
  });

  testWidgets('slow backend reads never overlap and wait three seconds after '
      'the response before the next poll', (tester) async {
    final (container, controller, gateway) = await _ready(tester);
    gateway.holdRead = 2;
    gateway.hold = Completer<void>();
    final run = controller.verify(productionApiBase, 'test-password');
    await tester.pump();
    gateway.timestamp = _stamp(3);
    await _seconds(tester, 3);
    expect(gateway.readTimes, hasLength(2));
    expect(gateway.activeReads, 1);
    await _seconds(tester, 9);
    expect(gateway.readTimes, hasLength(2));
    expect(gateway.maxActiveReads, 1);
    _pending(container, 1);
    gateway.hold!.complete();
    await tester.pump();
    _pending(container, 2);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(gateway.readTimes, hasLength(2));
    gateway.timestamp = _stamp(15);
    await tester.pump(const Duration(milliseconds: 1));
    await run;
    expect(container.read(commissionProvider).verified, isTrue);
    expect(gateway.maxActiveReads, 1);
    expect(gateway.activeReads, 0);
    expect(
      gateway.readTimes.map((at) => at.difference(gateway.readTimes.first)),
      [Duration.zero, const Duration(seconds: 3), const Duration(seconds: 15)],
    );
    await controller.cancel();
  });
}
