// 1.0.0+22 select_then_identify (docs/select_then_identify.md; field: the
// list's bulb took 3–5 s before the PTU lit — the phone's connect, service
// discovery and MTU 1.5–3 s, get_config 0.3 s, the gateway's own identify
// < 10 ms):
// - a card's tap selects the gateway and connects to it, keeping the link
//   ([CommissioningController.holdPeer]); its card says 「連線中…」 then
//   「已連線」 (or 「連線失敗」); the scan stops meanwhile;
// - its bulb goes over that link: no connect, no get_config, no
//   disconnect, nothing busy; pressed while the link still connects, it is
//   sent once the link is up;
// - another card: the previous link goes, the new gateway is connected;
// - 〔連線到 …〕 takes the link: no second connect, get_config and the
//   one-to-one switch still run once ([CommissioningController.connect]);
// - a dropped link: 「已斷線」 and a SnackBar; the next bulb connects again
//   first; 〔重新搜尋〕 and the list closing let the link go;
// - another row's bulb keeps its own connect → identify → disconnect; the
//   selected gateway is connected again afterwards.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

const _a = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -40);
const _b = GatewayPeer('AA:BB:CC:DD:3B:02', 'GIOS-S81-GW02', -55);

/// The demo gateway, every command recorded; [holdConnect] keeps a connect
/// pending, [failConnects] fails that many; [linkGone] makes every command
/// fail as a dropped phone link.
class _Gateway extends DemoSystem {
  final commands = <(String, Map<String, dynamic>)>[];
  final connected = <String>[];
  Completer<void>? holdConnect;
  bool linkGone = false;
  int failConnects = 0;

  List<Map<String, dynamic>> sent(String op) => [
    for (final (o, p) in commands)
      if (o == op) p,
  ];

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    connected.add(peer.id);
    await holdConnect?.future;
    if (failConnects > 0) {
      failConnects--;
      throw const GatewayFailure('ble_error', detail: '133');
    }
    linkGone = false;
    return super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add((op, Map.of(params)));
    if (linkGone) throw const GatewayFailure('not_connected');
    return super.command(op, params);
  }
}

/// A gateway link that reports its state ([GatewaySignalSource]), as
/// BleGatewayLink does: [drop] is the phone's link lost.
class _SignalGateway extends _Gateway implements GatewaySignalSource {
  final _signal = StreamController<bool>.broadcast();
  bool _up = false;

  @override
  bool get signalConnected => _up;

  @override
  Stream<bool> get signalConnections => _signal.stream;

  @override
  Future<int> readSignal() async => -50;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    await super.connect(peer, onStage: onStage);
    _up = true;
    _signal.add(true);
  }

  @override
  Future<void> disconnect() async {
    await super.disconnect();
    _up = false;
    _signal.add(false);
  }

  void drop() {
    _up = false;
    linkGone = true;
    _signal.add(false);
  }
}

Future<(ProviderContainer, CommissioningController, GatewayPeer)> _ready(
  _Gateway fake, {
  GatewayTopology topology = GatewayTopology.direct,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  await container.read(topologyProvider.notifier).setTopology(topology);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  fake.commands.clear();
  fake.connected.clear();
  return (container, c, container.read(commissionProvider).peers.single);
}

Future<void> _microtasks() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the controller keeps the selected gateway\'s link', () {
    test('holdPeer connects once, reads get_config, switches a star gateway '
        'to one-to-one and keeps the link — no run, nothing busy', () async {
      final fake = _Gateway()..config['max_connections'] = 5;
      final (container, c, peer) = await _ready(fake);
      final disconnects = fake.linkDisconnects;
      final holding = c.holdPeer(peer);
      expect(container.read(commissionProvider).busy, isFalse);
      expect(await holding, isTrue);
      expect(fake.connected, [peer.id]);
      expect(fake.linkedPeer, peer.id);
      expect(fake.linkDisconnects, disconnects);
      expect(c.heldPeerId, peer.id);
      expect(fake.sent('get_config'), hasLength(1));
      expect(fake.sent('set_config'), [
        {'max_connections': 1},
      ]);
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.peer, isNull);
      expect(s.busy, isFalse);
      // The same gateway again: no second connect.
      expect(await c.holdPeer(peer), isTrue);
      expect(fake.connected, [peer.id]);
    });

    test('its identify goes over the kept link: no connect, no get_config, '
        'no disconnect; the gateway-only reason still read', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      fake.devices.clear();
      final (container, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      final disconnects = fake.linkDisconnects;
      fake.commands.clear();
      fake.connected.clear();
      expect(await c.identifyPeer(peer), isTrue);
      expect(fake.connected, isEmpty);
      expect(fake.linkDisconnects, disconnects);
      expect(fake.sent('get_config'), isEmpty);
      expect(fake.sent('identify').single['target'], 'both');
      expect(c.identifyPeerGatewayOnly, isTrue);
      expect(
        c.identifyPeerGatewayOnlyReason,
        const IdentifyGatewayOnlyReason(IdentifyGatewayOnlyKind.noCandidate),
      );
      expect(c.heldPeerId, peer.id);
      expect(container.read(commissionProvider).busy, isFalse);
      // Again: still the same link.
      fake.devices.add({
        'mac': 'AA:BB:CC:00:00:09',
        'rssi': -40,
        'connected': true,
      });
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(fake.connected, isEmpty);
      expect(fake.sent('identify'), hasLength(2));
    });

    test('just switched to one-to-one by the hold: the gateway-only note '
        'says so', () async {
      final fake = _Gateway()..config['max_connections'] = 5;
      fake.devices.clear();
      final (_, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      expect(await c.identifyPeer(peer), isTrue);
      expect(
        c.identifyPeerGatewayOnlyReason?.kind,
        IdentifyGatewayOnlyKind.switchedToDirect,
      );
    });

    test('an identify while the hold still connects waits for it: one '
        'connect, then the identify', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final (_, c, peer) = await _ready(fake);
      fake.holdConnect = Completer<void>();
      final holding = c.holdPeer(peer);
      final identifying = c.identifyPeer(peer);
      await _microtasks();
      expect(fake.identifyRequests, isEmpty);
      fake.holdConnect!.complete();
      expect(await holding, isTrue);
      expect(await identifying, isTrue);
      expect(fake.connected, [peer.id]);
      expect(fake.identifyRequests, hasLength(1));
    });

    test('an identify waiting for a hold that fails: false, no connect of '
        'its own (the list says the connect failed)', () async {
      final fake = _Gateway()..failConnects = 1;
      final (_, c, peer) = await _ready(fake);
      fake.holdConnect = Completer<void>();
      final holding = c.holdPeer(peer);
      final identifying = c.identifyPeer(peer);
      await _microtasks();
      fake.holdConnect!.complete();
      expect(await holding, isFalse);
      expect(await identifying, isFalse);
      expect(fake.connected, [peer.id]);
      expect(fake.identifyRequests, isEmpty);
    });

    test(
      'another gateway: the previous hold ends, the new one is held; a '
      'late answer of the old connect keeps nothing and closes nothing',
      () async {
        final fake = _Gateway()..config['max_connections'] = 1;
        final (_, c, _) = await _ready(fake);
        final slow = fake.holdConnect = Completer<void>();
        final first = c.holdPeer(_a);
        await _microtasks();
        fake.holdConnect = null;
        expect(await c.holdPeer(_b), isTrue);
        expect(c.heldPeerId, _b.id);
        expect(fake.linkedPeer, _b.id);
        final disconnects = fake.linkDisconnects;
        // (BleGatewayLink cancels it at once; the demo link lets it land.)
        slow.complete();
        expect(await first, isFalse);
        expect(c.heldPeerId, _b.id);
        expect(fake.linkDisconnects, disconnects, reason: 'b\'s link stays');
        expect(fake.connected, [_a.id, _b.id]);
      },
    );

    test(
      '〔連線到 …〕 takes the kept link: no second connect; get_config and '
      'the one-to-one check run once in the connect, nothing sent twice',
      () async {
        final fake = _Gateway()..config['max_connections'] = 5;
        final (container, c, peer) = await _ready(fake);
        expect(await c.holdPeer(peer), isTrue);
        final disconnects = fake.linkDisconnects;
        await c.connect(peer);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 2);
        expect(identical(s.peer, peer), isTrue);
        expect(fake.connected, [peer.id], reason: 'no second connect');
        expect(fake.linkDisconnects, disconnects);
        // The hold's read and the connect's own read.
        expect(fake.sent('get_config'), hasLength(2));
        // Switched by the hold; the connect saw 1 and sent nothing more.
        expect(fake.sent('set_config'), [
          {'max_connections': 1},
        ]);
        expect(s.config['max_connections'], 1);
        // The flow owns the link now: the list's hold is gone.
        expect(c.heldPeerId, isNull);
      },
    );

    test('〔連線到 …〕 while the hold still connects: waits for it, one '
        'connect in all', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final (container, c, peer) = await _ready(fake);
      fake.holdConnect = Completer<void>();
      final holding = c.holdPeer(peer);
      final connecting = c.connect(peer);
      await _microtasks();
      fake.holdConnect!.complete();
      expect(await holding, isTrue);
      await connecting;
      expect(container.read(commissionProvider).step, 2);
      expect(fake.connected, [peer.id]);
    });

    test('a hold that failed closes what it opened; 〔連線到 …〕 then '
        'connects for itself', () async {
      final fake = _Gateway()..failConnects = 1;
      final (container, c, peer) = await _ready(fake);
      final disconnects = fake.linkDisconnects;
      expect(await c.holdPeer(peer), isFalse);
      expect(c.heldPeerId, isNull);
      expect(fake.linkDisconnects, disconnects + 1);
      expect(container.read(commissionProvider).error, isNull);
      await c.connect(peer);
      expect(container.read(commissionProvider).step, 2);
      expect(fake.connected, [peer.id, peer.id]);
    });

    test('a dropped link (the link reports it): heldLinkLost names the '
        'gateway; the next identify connects for itself', () async {
      final fake = _SignalGateway()..config['max_connections'] = 1;
      final (_, c, peer) = await _ready(fake);
      final lost = <String>[];
      final sub = c.heldLinkLost.listen(lost.add);
      addTearDown(sub.cancel);
      expect(await c.holdPeer(peer), isTrue);
      fake.drop();
      await _microtasks();
      expect(lost, [peer.id]);
      expect(c.heldPeerId, isNull);
      fake.connected.clear();
      expect(await c.identifyPeer(peer), isTrue);
      expect(fake.connected, [peer.id], reason: 'its own connect');
    });

    test('a link dropped unnoticed (no state reported): the identify fails '
        'as a lost link, nothing busy, no error on the page; the link is '
        'closed (a timed-out command may leave it up with nobody keeping '
        'it)', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final (container, c, peer) = await _ready(fake);
      final lost = <String>[];
      final sub = c.heldLinkLost.listen(lost.add);
      addTearDown(sub.cancel);
      expect(await c.holdPeer(peer), isTrue);
      final disconnects = fake.linkDisconnects;
      fake.linkGone = true;
      expect(await c.identifyPeer(peer), isFalse);
      await _microtasks();
      expect(lost, [peer.id]);
      expect(c.heldPeerId, isNull);
      expect(fake.linkDisconnects, disconnects + 1);
      expect(container.read(commissionProvider).error, isNull);
      expect(container.read(commissionProvider).busy, isFalse);
    });

    test(
      'a refusal by the gateway is the page\'s error; the link stays',
      () async {
        final fake = _Gateway()..config['max_connections'] = 1;
        final (container, c, peer) = await _ready(fake);
        expect(await c.holdPeer(peer), isTrue);
        fake.config['identify_supported'] = false;
        // The hold's config said it was supported; a fresh hold reads again.
        await c.releaseHeld();
        expect(await c.holdPeer(peer), isTrue);
        expect(await c.identifyPeer(peer), isFalse);
        expect(
          container.read(commissionProvider).error,
          const GatewayFailure('identify_unsupported').message,
        );
        expect(c.heldPeerId, peer.id);
      },
    );

    test('another row\'s identify: its own connect → identify → disconnect; '
        'the kept link is gone (the list holds again afterwards)', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final (_, c, _) = await _ready(fake);
      expect(await c.holdPeer(_a), isTrue);
      final disconnects = fake.linkDisconnects;
      expect(await c.identifyPeer(_b), isTrue);
      expect(fake.connected, [_a.id, _b.id]);
      expect(fake.linkDisconnects, greaterThan(disconnects));
      expect(c.heldPeerId, isNull);
    });

    test(
      'releaseHeld closes the kept link; nothing kept: no disconnect',
      () async {
        final fake = _Gateway()..config['max_connections'] = 1;
        final (_, c, peer) = await _ready(fake);
        var disconnects = fake.linkDisconnects;
        await c.releaseHeld();
        expect(fake.linkDisconnects, disconnects);
        expect(await c.holdPeer(peer), isTrue);
        await c.releaseHeld();
        expect(fake.linkDisconnects, disconnects + 1);
        expect(fake.linkedPeer, isNull);
        expect(c.heldPeerId, isNull);
        disconnects = fake.linkDisconnects;
        await c.releaseHeld();
        expect(fake.linkDisconnects, disconnects);
      },
    );

    test('〔結束配置〕 (leaveList) ends the hold with the link', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final (container, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      await c.leaveList();
      expect(container.read(commissionProvider).step, 0);
      expect(fake.linkedPeer, isNull);
      expect(c.heldPeerId, isNull);
    });
  });

  group('the list: a card\'s tap connects and keeps the link', () {
    testWidgets('tap: 「連線中…」, the scan stops, then 「已連線」', (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      await tester.pump();
      expect(_markText(tester, _a), gatewayConnectingLabel);
      await _run(tester);
      expect(list.link.stops, greaterThan(0), reason: 'the scan stopped');
      expect(list.holds, [_a.id]);
      list.holding.complete(true);
      await _run(tester);
      expect(_markText(tester, _a), gatewayHeldLabel);
      // Back to the foreground / on top: no new scan while one is kept.
      final scans = list.link.scans.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _run(tester);
      expect(list.link.scans.length, scans);
    });

    testWidgets('its bulb goes over that link at once (no second hold); '
        'pressed while it connects, it waits for the link', (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      await _run(tester);
      // Pressed while connecting: a spinner, nothing sent yet.
      await tester.tap(_bulb(_a));
      await tester.pump();
      expect(_spinner(_a), findsOneWidget);
      expect(list.identified, isEmpty);
      list.holding.complete(true);
      await _run(tester);
      expect(list.identified, [_a.id]);
      expect(list.holds, [_a.id]);
      expect(_chip(_a, identifiedHint), findsOneWidget);
      // Again: at once, the same link.
      await tester.pump(identifiedHintFor);
      await tester.tap(_bulb(_a));
      await _run(tester);
      expect(list.identified, [_a.id, _a.id]);
      expect(list.holds, [_a.id], reason: 'no second connect');
    });

    testWidgets('another card: the new gateway is held, the old answer is '
        'ignored', (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      await _run(tester);
      final first = list.holding;
      list.holding = Completer<bool>();
      await tester.tap(find.byKey(ValueKey(_b.id)));
      await _run(tester);
      expect(list.holds, [_a.id, _b.id]);
      expect(find.byKey(ValueKey('gateway-selected-${_a.id}')), findsNothing);
      expect(_markText(tester, _b), gatewayConnectingLabel);
      first.complete(true);
      list.holding.complete(true);
      await _run(tester);
      expect(_markText(tester, _b), gatewayHeldLabel);
    });

    testWidgets('a failed connect: 「連線失敗」 and a SnackBar; a tap on the '
        'card tries again', (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      await _run(tester);
      list.holding.complete(false);
      await _run(tester);
      expect(_markText(tester, _a), gatewayHoldFailedLabel);
      expect(find.text(gatewayHoldFailedText('站 81 · 閘道器 1')), findsOneWidget);
      list.holding = Completer<bool>();
      await tester.tap(find.byKey(ValueKey(_a.id)));
      await _run(tester);
      expect(list.holds, [_a.id, _a.id]);
      list.holding.complete(true);
      await _run(tester);
      expect(_markText(tester, _a), gatewayHeldLabel);
    });

    testWidgets('a dropped link: 「已斷線」 and a SnackBar; the bulb connects '
        'again first, then blinks', (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      list.holding.complete(true);
      await _run(tester);
      list.lost.add(_a.id);
      await _run(tester);
      expect(_markText(tester, _a), gatewayHoldLostLabel);
      expect(find.text(gatewayHoldLostText('站 81 · 閘道器 1')), findsOneWidget);
      list.holding = Completer<bool>();
      await tester.tap(_bulb(_a));
      await _run(tester);
      expect(list.holds, [_a.id, _a.id]);
      expect(list.identified, isEmpty);
      list.holding.complete(true);
      await _run(tester);
      expect(list.identified, [_a.id]);
      expect(_markText(tester, _a), gatewayHeldLabel);
    });

    testWidgets('another row\'s bulb: its own identify, then the selected '
        'gateway is held again', (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      list.holding.complete(true);
      await _run(tester);
      list.holding = Completer<bool>();
      await tester.tap(_bulb(_b));
      await _run(tester);
      expect(list.identified, [_b.id]);
      expect(list.holds, [_a.id, _a.id]);
      expect(_markText(tester, _a), gatewayConnectingLabel);
      list.holding.complete(true);
      await _run(tester);
      expect(_markText(tester, _a), gatewayHeldLabel);
    });

    testWidgets('〔重新搜尋〕 lets the link go and scans again; the list closing '
        'lets it go too', (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      list.holding.complete(true);
      await _run(tester);
      final scans = list.link.scans.length;
      await tester.tap(find.byKey(const Key('gateway-scan-toggle')));
      await _run(tester);
      expect(list.releases, 1);
      expect(list.link.scans.length, scans + 1);
      expect(find.byKey(ValueKey('gateway-selected-${_a.id}')), findsNothing);
      list.link.hear(const [_a, _b]);
      await tester.pump();
      list.holding = Completer<bool>()..complete(true);
      await tester.tap(find.byKey(ValueKey(_b.id)));
      await _run(tester);
      await tester.pumpWidget(const SizedBox());
      expect(list.releases, 2);
    });
  });

  group('the whole APP on the demo gateway', () {
    testWidgets('select → bulb → 〔連線到 …〕: one connect, no disconnect', (
      tester,
    ) async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final container = await _pumpApp(tester, fake);
      fake.connected.clear();
      final disconnects = fake.linkDisconnects;
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      await _settle(tester);
      expect(fake.connected, ['demo-gateway']);
      expect(_markText(tester, _demo), gatewayHeldLabel);
      await _tap(tester, _bulb(_demo));
      await _settle(tester);
      expect(fake.identifyRequests, hasLength(1));
      expect(fake.connected, ['demo-gateway'], reason: 'the bulb: no connect');
      expect(fake.linkDisconnects, disconnects);
      await _tap(tester, find.byKey(const Key('gateway-connect')));
      await _settle(tester);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.error, isNull);
      expect(fake.connected, ['demo-gateway'], reason: 'no second connect');
      expect(fake.linkDisconnects, disconnects);
    });
  });
}

// ---------------------------------------------------------------------------
// The list alone, its callbacks recorded.
// ---------------------------------------------------------------------------

class _ScanLink extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];
  int stops = 0;

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final scan = StreamController<List<GatewayPeer>>();
    scans.add(scan);
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    stops++;
    for (final scan in scans) {
      if (!scan.isClosed) unawaited(scan.close());
    }
  }

  void hear(List<GatewayPeer> peers) => scans.last.add(peers);
}

class _List {
  _List(this.link);
  final _ScanLink link;
  final holds = <String>[];
  final identified = <String>[];
  var holding = Completer<bool>();
  int releases = 0;
  final lost = StreamController<String>.broadcast();
}

Future<_List> _pumpList(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final list = _List(_ScanLink());
  addTearDown(list.lost.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [linkProvider.overrideWithValue(list.link)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GatewayDiscovery(
              enabled: true,
              onConnect: (_) async {},
              onIdentify: (peer) async {
                list.identified.add(peer.id);
                return true;
              },
              onHold: (peer) {
                list.holds.add(peer.id);
                return list.holding.future;
              },
              onRelease: () async => list.releases++,
              holdLost: list.lost.stream,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  list.link.hear(const [_a, _b]);
  await tester.pump();
  return list;
}

/// Lets the list's real async stop / start run.
Future<void> _run(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _bulb(GatewayPeer peer) => find.byKey(ValueKey('identify-${peer.id}'));

Finder _spinner(GatewayPeer peer) => find.descendant(
  of: _bulb(peer),
  matching: find.byType(CircularProgressIndicator),
);

Finder _chip(GatewayPeer peer, String text) => find.descendant(
  of: find.byKey(ValueKey('gateway-presence-${peer.id}')),
  matching: find.text(text),
);

/// The text of the selected mark on [peer]'s card.
String? _markText(WidgetTester tester, GatewayPeer peer) {
  final texts = find.descendant(
    of: find.byKey(ValueKey('gateway-selected-${peer.id}')),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(texts.first).data;
}

// ---------------------------------------------------------------------------
// The whole APP.
// ---------------------------------------------------------------------------

const _demo = GatewayPeer('demo-gateway', 'GIOS-S1-GW01', -42);

Future<ProviderContainer> _pumpApp(WidgetTester tester, DemoSystem fake) async {
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendKeyProvider.overrideWithValue('build-key'),
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  await tester.runAsync(() async {
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.direct);
  });
  await _tap(tester, find.text('檢查並開始'));
  expect(container.read(commissionProvider).step, 1);
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}
