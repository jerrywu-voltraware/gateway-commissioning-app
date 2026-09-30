import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/station_change.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';
import 'package:gateway_commissioning/presentation/station_change_progress.dart';

import 'network_check_test.dart' show WifiGateway;

/// The command gates reproduce a gateway restarting after an acknowledged
/// identity write. No real Bluetooth, Wi-Fi, or backend is used.
class _RestartingGateway extends WifiGateway implements GatewaySignalSource {
  _RestartingGateway() {
    config.addAll({
      'site_id': 20,
      'gateway_id': 1,
      'fleet_joined': true,
      'wifi_ssid': 'Demo-2.4G',
    });
  }

  final changes = StreamController<bool>.broadcast();
  final identityEntered = Completer<void>();
  final reconnectEntered = Completer<void>();
  final readbackEntered = Completer<void>();
  final identityAck = Completer<void>();
  final reconnectReady = Completer<void>();
  final readbackReady = Completer<void>();
  final events = <String>[];
  bool identityWritten = false;
  bool failReconnect = false;
  bool failReadback = false;

  @override
  bool signalConnected = true;
  @override
  Stream<bool> get signalConnections => changes.stream;
  @override
  Future<int> readSignal() async => -45;

  void setConnected(bool value) {
    signalConnected = value;
    if (!changes.isClosed) changes.add(value);
  }

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    if (identityWritten) {
      events.add('connect');
      if (!reconnectEntered.isCompleted) reconnectEntered.complete();
      await reconnectReady.future;
      if (failReconnect) throw const GatewayFailure('disconnected');
    }
    await super.connect(peer, onStage: onStage);
    setConnected(true);
  }

  @override
  Future<void> disconnect() async {
    setConnected(false);
    await super.disconnect();
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'set_site_identity') {
      events.add('identity-sent');
      if (!identityEntered.isCompleted) identityEntered.complete();
      await identityAck.future;
      final ack = await super.command(op, params);
      identityWritten = true;
      events.add('identity-ack');
      setConnected(false);
      return ack;
    }
    if (identityWritten && op == 'ping') events.add('ping');
    if (identityWritten && op == 'get_config') {
      events.add('readback');
      if (!readbackEntered.isCompleted) readbackEntered.complete();
      await readbackReady.future;
      if (failReadback) throw const GatewayFailure('disconnected');
    }
    return super.command(op, params);
  }
}

ProviderContainer _container(_RestartingGateway fake) => ProviderContainer(
  overrides: [
    linkProvider.overrideWithValue(fake),
    apiProvider.overrideWithValue(fake),
  ],
);

Future<CommissioningController> _connect(ProviderContainer container) async {
  final topology = container.read(topologyProvider.notifier);
  await topology.ready;
  await topology.setTopology(GatewayTopology.star);
  final c = container.read(commissionProvider.notifier);
  await c.prepare(productionApiBase, 'demo-login');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return c;
}

Future<void> _entered(Completer<void> gate) =>
    gate.future.timeout(const Duration(seconds: 3));

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (ready()) return;
  }
  fail('The simulated gateway did not reach the awaited command.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'backend_environment': 'production',
    });
  });

  test(
    'station change follows write ACK, reconnect and verified readback',
    () async {
      final fake = _RestartingGateway();
      final container = _container(fake);
      addTearDown(container.dispose);
      addTearDown(fake.changes.close);
      final c = await _connect(container);
      await c.chooseStation(newStation: true);
      final seen = <StationChangeStage>[];
      final subscription = container.listen(commissionProvider, (_, next) {
        final progress = next.activeStationChange;
        if (progress != null) {
          expect((progress.site, progress.gateway), (80, 1));
          if (seen.lastOrNull != progress.stage) seen.add(progress.stage);
        }
      });
      addTearDown(subscription.close);

      final run = c.configureWifi(80, 1, 'Demo-2.4G', '');
      await _entered(fake.identityEntered);
      expect(
        container.read(commissionProvider).activeStationChange?.stage,
        StationChangeStage.applying,
      );
      expect(fake.config['site_id'], 20);
      expect(fake.events, ['identity-sent']);

      fake.identityAck.complete();
      await _entered(fake.reconnectEntered);
      expect(
        container.read(commissionProvider).activeStationChange?.stage,
        StationChangeStage.reconnecting,
      );
      expect(fake.events, ['identity-sent', 'identity-ack', 'connect']);
      expect(seen, [
        StationChangeStage.applying,
        StationChangeStage.restarting,
        StationChangeStage.reconnecting,
      ]);

      fake.reconnectReady.complete();
      await _entered(fake.readbackEntered);
      expect(
        container.read(commissionProvider).activeStationChange?.stage,
        StationChangeStage.confirming,
      );
      expect(fake.events, [
        'identity-sent',
        'identity-ack',
        'connect',
        'ping',
        'readback',
      ]);
      // The returned configuration still has to prove the target identity.
      expect(container.read(commissionProvider).config['site_id'], 20);
      fake.readbackReady.complete();
      await run;
      final result = container.read(commissionProvider);
      expect(result.error, isNull);
      expect(result.busy, isFalse);
      expect(result.stationChange, isNull);
      expect(result.step, 3);
      expect(result.config['site_id'], 80);
      expect(fake.count('set_site_identity'), 1);
      expect(fake.count('set_wifi'), 0);
      expect(seen, StationChangeStage.values);
    },
  );

  test('failed reconnect exits the transition and can reconnect without '
      'rewriting the station', () async {
    final fake = _RestartingGateway()..failReconnect = true;
    final container = _container(fake);
    addTearDown(container.dispose);
    addTearDown(fake.changes.close);
    final c = await _connect(container);
    await c.chooseStation(newStation: true);
    final run = c.configureWifi(80, 1, 'Demo-2.4G', '');
    await _entered(fake.identityEntered);
    fake.identityAck.complete();
    await _entered(fake.reconnectEntered);
    fake.reconnectReady.complete();
    await run;
    final failed = container.read(commissionProvider);
    expect(failed.activeStationChange, isNull);
    expect(failed.stationChange, isNull);
    expect(failed.busy, isFalse);
    expect(failed.error, isNotNull);
    expect(failed.peer, isNotNull);
    expect(failed.uploadWatch, UploadWatch.linkLost);

    fake.failReconnect = false;
    fake.readbackReady.complete();
    await c.reconnectLink();
    expect(container.read(commissionProvider).error, isNull);
    expect(fake.config['site_id'], 80);
    expect(fake.signalConnected, isTrue);
    expect(fake.count('set_site_identity'), 1);
  });

  test('cancel during reconnect clears the transition and ignores late '
      'completion', () async {
    final fake = _RestartingGateway();
    final container = _container(fake);
    addTearDown(container.dispose);
    addTearDown(fake.changes.close);
    final c = await _connect(container);
    await c.chooseStation(newStation: true);
    final run = c.configureWifi(80, 1, 'Demo-2.4G', '');
    await _entered(fake.identityEntered);
    fake.identityAck.complete();
    await _entered(fake.reconnectEntered);
    await c.cancel();
    expect(container.read(commissionProvider).stationChange, isNull);
    expect(container.read(commissionProvider).peer, isNull);
    fake.reconnectReady.complete();
    await run;
    final cancelled = container.read(commissionProvider);
    expect(cancelled.activeStationChange, isNull);
    expect(cancelled.step, 1);
    expect(cancelled.peer, isNull);
    expect(fake.events, isNot(contains('ping')));
    expect(fake.events, isNot(contains('readback')));
    expect(fake.count('set_wifi'), 0);
  });

  for (final wifiOnly in [false, true]) {
    test('${wifiOnly ? 'Wi-Fi-only' : 'same identity'} does not show a '
        'station restart', () async {
      final fake = _RestartingGateway();
      final container = _container(fake);
      addTearDown(container.dispose);
      addTearDown(fake.changes.close);
      final c = await _connect(container);
      if (wifiOnly) {
        await c.chooseStation(newStation: false, wifiOnly: true);
      }
      final transitions = <StationChange>[];
      final subscription = container.listen(commissionProvider, (_, next) {
        if (next.stationChange != null) transitions.add(next.stationChange!);
      });
      addTearDown(subscription.close);
      await c.configureWifi(20, 1, 'Demo-2.4G', 'demo-test-password');
      expect(container.read(commissionProvider).error, isNull);
      expect(transitions, isEmpty);
      expect(fake.count('set_site_identity'), 0);
    });
  }

  testWidgets('page hides the form during restart, masks only the expected '
      'disconnect, and restores a visible failure with retry', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = _RestartingGateway()..failReadback = true;
    final container = _container(fake);
    addTearDown(container.dispose);
    addTearDown(fake.changes.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GatewayApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => container.read(backendEnvProvider.notifier).ready,
    );
    late CommissioningController c;
    await tester.runAsync(() async {
      c = await _connect(container);
      await c.chooseStation(newStation: true);
    });
    await tester.pumpAndSettle();
    expect(find.text(siteFieldLabel), findsOneWidget);

    final run = c.configureWifi(80, 1, 'Demo-2.4G', '');
    await _pumpUntil(tester, () => fake.identityEntered.isCompleted);
    await tester.pump();
    expect(find.byType(StationChangeProgress), findsOneWidget);
    expect(find.text('站點 80 · 閘道器 1'), findsOneWidget);
    expect(find.text(siteFieldLabel), findsNothing);
    expect(find.textContaining('最多等待'), findsNothing);
    expect(find.text('設備與連線資訊'), findsNothing);
    expect(find.byKey(const Key('page-cancel')), findsOneWidget);

    // Before the ACK this is an ordinary lost link, not a proven restart.
    fake.setConnected(false);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('gateway-link-lost')), findsOneWidget);
    fake.identityAck.complete();
    await _pumpUntil(tester, () => fake.reconnectEntered.isCompleted);
    await tester.pump();
    expect(find.text('正在重新連線閘道器'), findsOneWidget);
    expect(find.byKey(const Key('gateway-link-lost')), findsNothing);
    expect(find.byType(StationChangeProgress), findsOneWidget);

    fake.reconnectReady.complete();
    await _pumpUntil(tester, () => fake.readbackEntered.isCompleted);
    await tester.pump();
    expect(find.text('正在確認站號與 Wi-Fi'), findsOneWidget);
    fake.setConnected(false);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('gateway-link-lost')),
      findsOneWidget,
      reason: 'a new loss after reconnection must not be hidden',
    );
    fake.readbackReady.complete();
    await _pumpUntil(tester, () => !container.read(commissionProvider).busy);
    await run;
    await tester.pumpAndSettle();
    expect(find.byType(StationChangeProgress), findsNothing);
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.byKey(const Key('gateway-link-lost')), findsOneWidget);
    expect(find.byKey(const Key('ptu-resume')), findsOneWidget);
    expect(find.text(siteFieldLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('360x640 at 1.3 text scale: cancel remains reachable during '
      'reconnect and returns to gateway selection', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fake = _RestartingGateway();
    final container = _container(fake);
    addTearDown(container.dispose);
    addTearDown(fake.changes.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GatewayApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => container.read(backendEnvProvider.notifier).ready,
    );
    late CommissioningController c;
    await tester.runAsync(() async {
      c = await _connect(container);
      await c.chooseStation(newStation: true);
    });
    await tester.pumpAndSettle();
    final run = c.configureWifi(80, 1, 'Demo-2.4G', '');
    await _pumpUntil(tester, () => fake.identityEntered.isCompleted);
    fake.identityAck.complete();
    await _pumpUntil(tester, () => fake.reconnectEntered.isCompleted);
    await tester.pump();
    expect(find.byType(StationChangeProgress), findsOneWidget);
    final cancel = find.byKey(const Key('page-cancel'));
    await tester.ensureVisible(cancel);
    await tester.pump(const Duration(milliseconds: 350));
    expect(cancel.hitTestable(), findsOneWidget);
    expect(find.text('取消操作'), findsOneWidget);
    await tester.tap(cancel);
    await _pumpUntil(
      tester,
      () => container.read(commissionProvider).peer == null,
    );
    expect(container.read(commissionProvider).stationChange, isNull);
    fake.reconnectReady.complete();
    await _pumpUntil(tester, () => !container.read(commissionProvider).busy);
    await run;
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).step, 1);
    expect(find.byType(StationChangeProgress), findsNothing);
    expect(find.byKey(const Key('gateway-link-lost')), findsNothing);
    expect(fake.events, isNot(contains('readback')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
