import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/recent_gateways.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

class LiveLink extends DemoSystem implements GatewayScanner {
  final events = StreamController<List<GatewayPeer>>();
  bool stopped = false;
  @override
  Stream<List<GatewayPeer>> scanLive() => events.stream;
  @override
  Future<void> stopScan() async {
    stopped = true;
  }
}

class LifecycleLink extends DemoSystem implements GatewayScanner {
  final sessions = <StreamController<List<GatewayPeer>>>[];
  Completer<void>? stopGate;
  @override
  Stream<List<GatewayPeer>> scanLive() {
    final stream = StreamController<List<GatewayPeer>>();
    sessions.add(stream);
    return stream.stream;
  }

  @override
  Future<void> stopScan() async {
    await stopGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('backend presence uses verified unique UID and respects conflicts', () {
    final fleet = [
      {'last_seen_mac': 'AA:BB:CC:DD:EE:FF', 'online': true},
    ];
    expect(backendPresence(null, fleet), contains('未知'));
    expect(backendPresence('001122334455', fleet), contains('未知'));
    expect(backendPresence('AABBCCDDEEFF', fleet), '後端回報在線上');
    expect(
      backendPresence('AABBCCDDEEFF', [...fleet, ...fleet]),
      contains('未知'),
    );
    expect(
      backendPresence('AABBCCDDEEFF', [
        {...fleet.single, 'conflict_flag': 1},
      ]),
      contains('未知'),
    );
    expect(
      backendPresence('AABBCCDDEEFF', [
        {...fleet.single, 'online': false},
      ]),
      '後端回報離線',
    );
  });
  test(
    'recents survive reload, bounded, newest first and demo isolated',
    () async {
      for (var i = 0; i < 7; i++) {
        await RecentGateways.remember(
          false,
          GatewayPeer('id$i', 'GIOS-S1-GW01', -40),
          'AABBCCDDEE0$i',
        );
      }
      var rows = await RecentGateways.load(false);
      expect(rows.length, 5);
      expect(rows.first.peer.id, 'id6');
      expect(await RecentGateways.load(true), isEmpty);
      await RecentGateways.remember(
        false,
        const GatewayPeer('id5', 'renamed', -42),
        'AABBCCDDEE05',
      );
      rows = await RecentGateways.load(false);
      expect(rows.first.peer.name, 'renamed');
      expect(rows.where((r) => r.peer.id == 'id5').length, 1);
    },
  );
  test('corrupt history does not block discovery', () async {
    SharedPreferences.setMockInitialValues({'recent_gateways': 'broken json'});
    expect(await RecentGateways.load(false), isEmpty);
  });
  testWidgets(
    'results usable before scan ends; stop before connect; narrow UI',
    (tester) async {
      final link = LiveLink();
      addTearDown(link.events.close);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var connected = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GatewayDiscovery(
                  enabled: true,
                  onConnect: (peer) async {
                    expect(link.stopped, isTrue);
                    connected = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      link.events.add([
        const GatewayPeer('AA:BB:CC:DD:EE:FF', 'GIOS-S1-GW01', -42),
      ]);
      await tester.pump();
      expect(find.text('GIOS-S1-GW01'), findsOneWidget);
      expect(find.textContaining('後端狀態未知'), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump();
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNotNull);
      await tester.tap(find.byType(ListTile));
      await tester.pump(const Duration(milliseconds: 500));
      expect(link.stopped, isTrue, reason: 'tap must stop scanner');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(connected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'compact rows filter many devices and update RSSI without moving',
    (tester) async {
      final link = LiveLink();
      addTearDown(link.events.close);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: GatewayDiscovery(
                    enabled: true,
                    onConnect: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final peers = List.generate(
        30,
        (i) => GatewayPeer('AA:BB:CC:DD:EE:$i', 'GIOS-S80-GW$i', -60),
      );
      link.events.add(peers);
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('AA:BB:CC:DD:EE:0'))).height,
        lessThanOrEqualTo(90),
      );
      final before = tester.getTopLeft(find.text('GIOS-S80-GW0'));
      // Reading noise (2 dB) moves nothing.
      link.events.add([
        const GatewayPeer('AA:BB:CC:DD:EE:29', 'GIOS-S80-GW29', -58),
        ...peers.take(29),
      ]);
      await tester.pump();
      expect(tester.getTopLeft(find.text('GIOS-S80-GW0')), before);
      // Round 30: a clearly stronger one rises to the top, marked nearest.
      link.events.add([
        const GatewayPeer('AA:BB:CC:DD:EE:29', 'GIOS-S80-GW29', -30),
        ...peers.take(29),
      ]);
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('GIOS-S80-GW29')).dy,
        lessThan(tester.getTopLeft(find.text('GIOS-S80-GW0')).dy),
      );
      expect(
        find.byKey(const ValueKey('gateway-nearest-AA:BB:CC:DD:EE:29')),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'gw29');
      await tester.pump();
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('-30 dBm'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'rapid foreground return waits for scanner cleanup then restarts',
    (tester) async {
      final link = LifecycleLink();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: GatewayDiscovery(enabled: true, onConnect: (_) async {}),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(link.sessions.length, 1);
      link.stopGate = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(link.sessions.length, 1);
      link.stopGate!.complete();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(link.sessions.length, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(link.sessions.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        for (final session in link.sessions) {
          await session.close();
        }
      });
    },
  );
  test(
    'identify capability works in demo and absent capability rejects',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(demoProvider.notifier).set(true);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.identify();
      expect(container.read(commissionProvider).error, isNull);
      // No PTU connected in this demo: firmware 1.7.20 target=both still
      // acks ok (gateway LED blinks) and reports the PTU side via
      // ptu_write, rather than failing the whole ack.
      expect(container.read(commissionProvider).message, contains('閃燈'));
      expect(container.read(commissionProvider).message, contains('尚未連上 PTU'));
      expect((await RecentGateways.load(true)).single.uid, 'AABBCCDDEEFF');
      container.read(demoSystemProvider).config.remove('identify_supported');
      await c.connect(container.read(commissionProvider).peers.single);
      await c.identify();
      expect(container.read(commissionProvider).error, contains('尚未支援'));
    },
  );
}
