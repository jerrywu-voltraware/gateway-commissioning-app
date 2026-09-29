import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/presentation/gateway_signal.dart';

class SignalLink extends DemoSystem implements GatewaySignalSource {
  final changes = StreamController<bool>.broadcast();
  @override
  bool signalConnected = true;
  @override
  Stream<bool> get signalConnections => changes.stream;
  int value = -68, reads = 0;
  Completer<int>? pending;
  @override
  Future<int> readSignal() async {
    reads++;
    return pending == null ? value : pending!.future;
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    SignalLink link, {
    bool busy = false,
    String id = 'a',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GatewaySignal(
          link: link,
          peer: GatewayPeer(id, 'GIOS', -70),
          busy: busy,
        ),
      ),
    ),
  );

  testWidgets(
    'phone RSSI refreshes and disconnection immediately preserves last sample',
    (tester) async {
      final link = SignalLink();
      addTearDown(link.changes.close);
      await show(tester, link);
      await tester.pump();
      expect(find.text('手機 ↔ 閘道器：-68 dBm'), findsOneWidget);
      link.value = -82;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('手機 ↔ 閘道器：-82 dBm'), findsOneWidget);
      link.signalConnected = false;
      link.changes.add(false);
      await tester.pump();
      await tester.pump();
      expect(find.text('手機 ↔ 閘道器：已斷線・上次 -82 dBm'), findsOneWidget);
      final reads = link.reads;
      await tester.pump(const Duration(seconds: 10));
      expect(link.reads, reads);
    },
  );

  testWidgets(
    'background and busy pause polling; invalid sample cannot become live',
    (tester) async {
      final link = SignalLink();
      addTearDown(link.changes.close);
      await show(tester, link);
      await tester.pump();
      final reads = link.reads;
      await show(tester, link, busy: true);
      await tester.pump(const Duration(seconds: 20));
      expect(link.reads, reads);
      expect(find.text('手機 ↔ 閘道器：上次 -68 dBm'), findsOneWidget);
      await show(tester, link);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(link.reads, reads);
      link.value = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('手機 ↔ 閘道器：上次 -68 dBm'), findsOneWidget);
      expect(find.textContaining('0 dBm'), findsNothing);
    },
  );

  testWidgets(
    'one request at a time; late reading after disconnect is ignored',
    (tester) async {
      final link = SignalLink()..pending = Completer<int>();
      addTearDown(link.changes.close);
      await show(tester, link);
      await tester.pump(const Duration(seconds: 10));
      expect(link.reads, 1);
      link.signalConnected = false;
      link.changes.add(false);
      await tester.pump();
      link.pending!.complete(-30);
      await tester.pump();
      expect(find.text('手機 ↔ 閘道器：已斷線・掃描 -70 dBm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(link.reads, 1);
    },
  );

  testWidgets('late sample from previous peer cannot appear on new peer', (
    tester,
  ) async {
    final link = SignalLink()..pending = Completer<int>();
    addTearDown(link.changes.close);
    await show(tester, link);
    await show(tester, link, id: 'b');
    link.pending!.complete(-25);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('-25 dBm'), findsNothing);
    expect(find.text('手機 ↔ 閘道器：掃描 -70 dBm'), findsOneWidget);
    link.pending = null;
    link.value = -85;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('手機 ↔ 閘道器：-85 dBm'), findsOneWidget);
  });

  test('native disconnect error is mapped without exposing exception text', () {
    final error = normalizeBleError(
      UniversalBleException(
        code: UniversalBleErrorCode.deviceDisconnected,
        message: 'Device Disconnected',
      ),
    );
    expect(error, isA<GatewayFailure>());
    expect((error as GatewayFailure).code, 'disconnected');
    expect(error.message, isNot(contains('UniversalBle')));
  });
}
