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
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'support/l10n.dart';

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
  testWidgets('results usable before scan ends; stop before connect; narrow UI', (
    tester,
  ) async {
    final link = LiveLink();
    addTearDown(link.events.close);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var connected = false;
    // The footer scans; each ready card owns its commissioning action.
    final choice = GatewayChoice();
    addTearDown(choice.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [linkProvider.overrideWithValue(link)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GatewayDiscovery(
                enabled: true,
                choice: choice,
                onHold: (_) async {
                  expect(link.stopped, isTrue);
                  return true;
                },
                onConnect: (peer) async {
                  expect(link.stopped, isTrue);
                  connected = true;
                },
              ),
            ),
            bottomNavigationBar: GatewayScanBar(choice: choice),
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
    // 1.0.0+10: the title only (the advertised name is not repeated).
    // 1.0.0+12: the factory name 1/1 is a gateway not configured —
    // 「未配置閘道器」 and its Wi-Fi MAC tail, not 「站 1 · 閘道器 1」.
    // 1.0.0+14: the title 「未配置閘道器」 (one line), the tail on line 3.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('gateway-title-AA:BB:CC:DD:EE:FF')),
          )
          .data,
      '未配置閘道器',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('gateway-detail-AA:BB:CC:DD:EE:FF')),
          )
          .data,
      '…EEFD',
    );
    expect(find.text('站 1 · 閘道器 1'), findsNothing);
    expect(find.textContaining('GIOS-S1-GW01'), findsNothing);
    expect(find.textContaining('後端未知'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump();
    // 1.0.0+9: the row is an InkWell (no ListTile).
    final row = find.byKey(const ValueKey('AA:BB:CC:DD:EE:FF'));
    expect(tester.widget<InkWell>(row).onTap, isNotNull);
    // Selection keeps scanning; card commissioning requires explicit BLE ready.
    await tester.tap(row);
    await tester.pump();
    expect(link.stopped, isFalse);
    expect(connected, isFalse);
    final start = find.byKey(const ValueKey('gateway-start-AA:BB:CC:DD:EE:FF'));
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    final connect = find.byKey(const Key('gateway-link-identify'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    expect(link.stopped, isTrue);
    expect(connected, isFalse);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    expect(
      find.descendant(of: start, matching: find.text('開始開通')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('gateway-connect-bar')), findsNothing);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump(const Duration(milliseconds: 500));
    expect(link.stopped, isTrue, reason: 'connect must stop scanner');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(connected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('English: list heading, group title and pick hint', (
    tester,
  ) async {
    useLanguage(AppLanguage.en);
    final link = LiveLink();
    addTearDown(link.events.close);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [linkProvider.overrideWithValue(link)],
        child: wrapWithL10n(
          Scaffold(
            body: SingleChildScrollView(
              child: GatewayDiscovery(enabled: true, onConnect: (_) async {}),
            ),
          ),
          language: AppLanguage.en,
        ),
      ),
    );
    await tester.pump();
    link.events.add(const [
      GatewayPeer('AA:BB:CC:DD:EE:01', 'GIOS-S80-GW01', -60),
      GatewayPeer('AA:BB:CC:DD:EE:02', 'GIOS-S80-GW02', -62),
    ]);
    await tester.pump();
    expect(find.text('Select a nearby gateway'), findsOneWidget);
    expect(find.text('Nearby devices (2)'), findsOneWidget);
    expect(
      find.text('Select the gateway card to set up, then tap [Connect]'),
      findsOneWidget,
    );
    expect(gatewayFoundCountText(2), '2 found');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('compact rows list many devices and update RSSI without moving', (
    tester,
  ) async {
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
                child: GatewayDiscovery(enabled: true, onConnect: (_) async {}),
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
      tester.getTopLeft(find.text('站 80 · 閘道器 29')).dy,
      lessThan(tester.getTopLeft(find.text('GIOS-S80-GW0')).dy),
    );
    expect(
      find.byKey(const ValueKey('gateway-nearest-AA:BB:CC:DD:EE:29')),
      findsOneWidget,
    );
    // 1.0.0+17: no filter box — every gateway heard stays listed.
    expect(find.byType(TextField), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Card &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('gateway-card-'),
      ),
      findsNWidgets(30),
    );
    expect(find.text('-30 dBm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
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
