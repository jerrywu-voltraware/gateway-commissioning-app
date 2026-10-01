import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
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
  Completer<void>? holdDisconnect;
  bool failDisconnect = false;
  Completer<void>? holdIdentify;
  Object? identifyFailure;
  bool failConfigRead = false;

  @override
  Future<void> disconnect() async {
    await holdDisconnect?.future;
    if (failDisconnect) throw const GatewayFailure('cleanup_failed');
    final pending = holdConnect;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const GatewayFailure('cancelled'));
    }
    await super.disconnect();
  }

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
    if (op == 'get_config' && failConfigRead) {
      throw const GatewayFailure('identify_unsupported', fromGateway: true);
    }
    if (linkGone) throw const GatewayFailure('not_connected');
    if (op == 'identify') {
      await holdIdentify?.future;
      if (identifyFailure != null) throw identifyFailure!;
    }
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

  test(
    'finding and identifying never write configuration, including star and BLE off',
    () async {
      final fake = _Gateway()..config['max_connections'] = 5;
      fake.config['ble_enabled'] = false;
      final (container, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      expect(await c.identifyPeer(peer), isTrue);
      expect(fake.sent('set_config'), isEmpty);
      expect(fake.sent('set_ble_enabled'), isEmpty);
      expect(fake.config['max_connections'], 5);
      expect(fake.config['ble_enabled'], isFalse);
      expect(fake.connected, [peer.id]);
      expect(container.read(commissionProvider).step, 1);
      expect(c.heldPeerId, peer.id);
    },
  );

  test(
    'identify without a ready connection does not connect or send',
    () async {
      final fake = _Gateway();
      final (_, c, peer) = await _ready(fake);
      expect(await c.identifyPeer(peer), isFalse);
      expect(fake.connected, isEmpty);
      expect(fake.commands, isEmpty);
    },
  );

  test(
    'connecting rejects another gateway, repeat connect, identify and commissioning',
    () async {
      final fake = _Gateway();
      final (container, c, _) = await _ready(fake);
      fake.holdConnect = Completer<void>();
      final first = c.holdPeer(_a);
      expect(await c.holdPeer(_b), isFalse);
      expect(await c.holdPeer(_a), isFalse);
      expect(await c.identifyPeer(_a), isFalse);
      await c.connect(_b);
      expect(container.read(commissionProvider).step, 1);
      expect(fake.connected, [_a.id]);
      fake.holdConnect!.complete();
      expect(await first, isTrue);
      expect(c.heldPeerId, _a.id);
    },
  );

  test(
    'connected identity cannot be switched by identify or commissioning',
    () async {
      final fake = _Gateway();
      final (container, c, _) = await _ready(fake);
      expect(await c.holdPeer(_a), isTrue);
      expect(await c.holdPeer(_b), isFalse);
      expect(await c.identifyPeer(_b), isFalse);
      await c.connect(_b);
      expect(container.read(commissionProvider).step, 1);
      expect(c.heldPeerId, _a.id);
      expect(fake.identifyRequests, isEmpty);
      expect(fake.connected, [_a.id]);
    },
  );

  test(
    'disconnect awaits cleanup before the next gateway can connect',
    () async {
      final fake = _Gateway();
      final (_, c, _) = await _ready(fake);
      expect(await c.holdPeer(_a), isTrue);
      fake.holdDisconnect = Completer<void>();
      final release = c.releaseHeld();
      expect(await c.holdPeer(_b), isFalse);
      expect(await c.identifyPeer(_a), isFalse);
      fake.holdDisconnect!.complete();
      await release;
      expect(c.heldPeerId, isNull);
      expect(await c.holdPeer(_b), isTrue);
      expect(fake.connected, [_a.id, _b.id]);
    },
  );

  test(
    'cancel during connect waits for cleanup and ignores late completion',
    () async {
      final fake = _Gateway();
      final (_, c, _) = await _ready(fake);
      fake.holdConnect = Completer<void>();
      final hold = c.holdPeer(_a);
      fake.holdDisconnect = Completer<void>();
      final release = c.releaseHeld();
      expect(await c.holdPeer(_b), isFalse);
      fake.holdDisconnect!.complete();
      await release;
      expect(await hold, isFalse);
      expect(c.heldPeerId, isNull);
      fake.holdConnect = null;
      expect(await c.holdPeer(_b), isTrue);
    },
  );

  test(
    'cleanup failure requires retry disconnect and blocks all connection actions',
    () async {
      final fake = _Gateway();
      final (_, c, _) = await _ready(fake);
      expect(await c.holdPeer(_a), isTrue);
      fake.failDisconnect = true;
      await expectLater(c.releaseHeld(), throwsA(isA<GatewayFailure>()));
      expect(c.heldCleanupRequired, isTrue);
      expect(await c.holdPeer(_b), isFalse);
      fake.failDisconnect = false;
      await c.releaseHeld();
      expect(c.heldCleanupRequired, isFalse);
      expect(await c.holdPeer(_b), isTrue);
    },
  );

  test('failed connect cleans up then explicit retry succeeds', () async {
    final fake = _Gateway()..failConnects = 1;
    final (_, c, peer) = await _ready(fake);
    expect(await c.holdPeer(peer), isFalse);
    expect(c.heldPeerId, isNull);
    expect(await c.identifyPeer(peer), isFalse);
    expect(await c.holdPeer(peer), isTrue);
    expect(fake.connected, [peer.id, peer.id]);
  });

  test(
    'identify is immediate on the ready link and repeated request is rejected',
    () async {
      final fake = _Gateway();
      final (_, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      fake.commands.clear();
      fake.holdIdentify = Completer<void>();
      final identifying = c.identifyPeer(peer);
      await _microtasks();
      expect(await c.identifyPeer(peer), isFalse);
      expect(fake.sent('identify'), hasLength(1));
      expect(fake.sent('get_config'), isEmpty);
      expect(fake.connected, [peer.id]);
      fake.holdIdentify!.complete();
      expect(await identifying, isTrue);
    },
  );

  test('late identify after disconnect cannot restore held state', () async {
    final fake = _Gateway();
    final (_, c, peer) = await _ready(fake);
    expect(await c.holdPeer(peer), isTrue);
    fake.holdIdentify = Completer<void>();
    final identifying = c.identifyPeer(peer);
    await _microtasks();
    await c.releaseHeld();
    fake.holdIdentify!.complete();
    expect(await identifying, isFalse);
    expect(c.heldPeerId, isNull);
  });

  test(
    'begin commissioning adopts same link and only then applies direct settings',
    () async {
      final fake = _Gateway()..config['max_connections'] = 5;
      final (container, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      expect(fake.sent('set_config'), isEmpty);
      await c.connect(peer);
      expect(container.read(commissionProvider).step, 2);
      expect(fake.connected, [peer.id]);
      expect(fake.sent('set_config'), contains(equals({'max_connections': 1})));
      expect(c.heldPeerId, isNull);
    },
  );

  test(
    'remote drop needs explicit reconnect; identify never reconnects',
    () async {
      final fake = _SignalGateway();
      final (_, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      fake.drop();
      await _microtasks();
      expect(c.heldPeerId, isNull);
      expect(await c.identifyPeer(peer), isFalse);
      expect(fake.connected, [peer.id]);
      expect(await c.holdPeer(peer), isTrue);
    },
  );

  test('back during connect awaits cleanup before returning home', () async {
    final fake = _Gateway();
    final (container, c, peer) = await _ready(fake);
    fake.holdConnect = Completer<void>();
    final holding = c.holdPeer(peer);
    fake.holdDisconnect = Completer<void>();
    final leaving = c.leaveList();
    await _microtasks();
    expect(container.read(commissionProvider).step, 1);
    expect(await c.holdPeer(_b), isFalse);
    fake.holdDisconnect!.complete();
    await leaving;
    expect(await holding, isFalse);
    expect(container.read(commissionProvider).step, 0);
    expect(c.heldPeerId, isNull);
  });

  testWidgets(
    'rapid A B A B selects only; explicit connect freezes selection',
    (tester) async {
      final list = await _pumpList(tester);
      for (final peer in [_a, _b, _a, _b]) {
        await tester.tap(find.byKey(ValueKey(peer.id)));
        await tester.pump();
      }
      expect(list.holds, isEmpty);
      expect(list.choice.peer?.id, _b.id);
      expect(list.choice.ready, isFalse);
      await tester.tap(find.byKey(const Key('gateway-link-identify')));
      await _run(tester);
      expect(list.holds, [_b.id]);
      expect(_markText(tester, _b), gatewayConnectingLabel);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      await tester.pump();
      expect(list.choice.peer?.id, _b.id);
      expect(list.holds, [_b.id]);
      expect(_bulb(_b), findsNothing);
      list.holding.complete(true);
      await _run(tester);
      expect(list.choice.ready, isTrue);
      expect(_bulb(_b), findsOneWidget);
      await tester.tap(_bulb(_b));
      await _run(tester);
      expect(list.identified, [_b.id]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'disconnect keeps cards disabled until cleanup then permits selecting B',
    (tester) async {
      final list = await _pumpList(tester);
      await tester.tap(find.byKey(ValueKey(_a.id)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gateway-link-identify')));
      await _run(tester);
      list.holding.complete(true);
      await _run(tester);
      list.releaseGate = Completer<void>();
      await tester.tap(find.byKey(const Key('gateway-disconnect')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(_b.id)));
      await tester.pump();
      expect(list.choice.peer?.id, _a.id);
      expect(list.choice.ready, isFalse);
      list.releaseGate!.complete();
      await _run(tester);
      await tester.tap(find.byKey(ValueKey(_b.id)));
      await tester.pump();
      expect(list.choice.peer?.id, _b.id);
      expect(list.holds, [_a.id]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed connection retries only through explicit button', (
    tester,
  ) async {
    final list = await _pumpList(tester);
    await tester.tap(find.byKey(ValueKey(_a.id)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gateway-link-identify')));
    await _run(tester);
    list.holding.complete(false);
    await _run(tester);
    expect(_markText(tester, _a), gatewayHoldFailedLabel);
    list.holding = Completer<bool>();
    await tester.tap(find.byKey(ValueKey(_a.id)));
    await tester.pump();
    expect(list.holds, [_a.id]);
    await tester.tap(find.byKey(const Key('gateway-link-identify')));
    await _run(tester);
    expect(list.holds, [_a.id, _a.id]);
    list.holding.complete(true);
    await _run(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel connect ignores late hold result', (tester) async {
    final list = await _pumpList(tester);
    await tester.tap(find.byKey(ValueKey(_a.id)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gateway-link-identify')));
    await _run(tester);
    await tester.tap(find.byKey(const Key('gateway-disconnect')));
    await _run(tester);
    list.holding.complete(true);
    await _run(tester);
    expect(list.choice.ready, isFalse);
    expect(_bulb(_a), findsNothing);
    expect(list.releases, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'identify timeout and failed cleanup returns false and preserves retry gate',
    () async {
      final fake = _Gateway();
      final (container, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      final lost = <String>[];
      final sub = c.heldLinkLost.listen(lost.add);
      addTearDown(sub.cancel);
      fake.identifyFailure = TimeoutException('identify timeout');
      fake.failDisconnect = true;
      expect(await c.identifyPeer(peer), isFalse);
      await _microtasks();
      expect(lost, [peer.id]);
      expect(c.heldCleanupRequired, isTrue);
      expect(c.heldPeerId, isNull);
      expect(
        container.read(commissionProvider).error,
        gatewayCleanupFailedText,
      );
      expect(await c.holdPeer(_b), isFalse);
      fake.failDisconnect = false;
      await c.releaseHeld();
      expect(c.heldCleanupRequired, isFalse);
      expect(await c.holdPeer(_b), isTrue);
    },
  );

  testWidgets(
    'identify timeout with cleanup failure exposes retry disconnect, then reconnect',
    (tester) async {
      final fake = _Gateway();
      final container = await _pumpApp(tester, fake);
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      await _tap(tester, find.byKey(const Key('gateway-link-identify')));
      await _settle(tester);
      fake.identifyFailure = TimeoutException('identify timeout');
      fake.failDisconnect = true;
      await _tap(tester, _bulb(_demo));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('重試斷開'), findsOneWidget);
      expect(_bulb(_demo), findsNothing);
      expect(find.byKey(const Key('gateway-link-identify')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('gateway-start-demo-gateway')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('demo-gateway')))
            .onTap,
        isNull,
      );
      expect(
        container.read(commissionProvider.notifier).heldCleanupRequired,
        isTrue,
      );
      fake.failDisconnect = false;
      fake.identifyFailure = null;
      await _tap(tester, find.byKey(const Key('gateway-disconnect')));
      expect(
        container.read(commissionProvider.notifier).heldCleanupRequired,
        isFalse,
      );
      expect(find.byKey(const Key('gateway-link-identify')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('gateway-link-identify')));
      await _settle(tester);
      expect(_bulb(_demo), findsOneWidget);
      expect(fake.sent('set_config'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'identify timeout with successful cleanup requires explicit reconnect',
    (tester) async {
      final fake = _Gateway();
      final container = await _pumpApp(tester, fake);
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      await _tap(tester, find.byKey(const Key('gateway-link-identify')));
      await _settle(tester);
      final connects = fake.connected.length;
      fake.identifyFailure = TimeoutException('identify timeout');
      await _tap(tester, _bulb(_demo));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(_markText(tester, _demo), gatewayHoldLostLabel);
      expect(_bulb(_demo), findsNothing);
      expect(fake.connected, hasLength(connects));
      expect(
        container.read(commissionProvider.notifier).heldCleanupRequired,
        isFalse,
      );
      expect(find.byKey(const Key('gateway-link-identify')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'disposing a ready connection absorbs asynchronous cleanup failure',
    (tester) async {
      final fake = _Gateway();
      await _pumpApp(tester, fake);
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      await _tap(tester, find.byKey(const Key('gateway-link-identify')));
      await _settle(tester);
      fake.failDisconnect = true;
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'failed commissioning cleans an adopted link; failed cleanup blocks back and retry',
    () async {
      final fake = _Gateway();
      final (container, c, peer) = await _ready(fake);
      expect(await c.holdPeer(peer), isTrue);
      fake.failConfigRead = true;
      fake.failDisconnect = true;
      await c.connect(peer);
      expect(container.read(commissionProvider).step, 1);
      expect(c.heldPeerId, isNull);
      expect(c.heldCleanupRequired, isTrue);
      expect(await c.holdPeer(_b), isFalse);
      await c.leaveList();
      expect(container.read(commissionProvider).step, 1);
      expect(container.read(commissionProvider).busy, isFalse);
      fake.failDisconnect = false;
      await c.leaveList();
      expect(container.read(commissionProvider).step, 0);
      expect(fake.linkedPeer, isNull);
    },
  );

  test(
    'cancel during an established commissioning catches cleanup failure and can retry',
    () async {
      final fake = _Gateway();
      final (container, c, peer) = await _ready(fake);
      await c.connect(peer);
      expect(container.read(commissionProvider).step, 2);
      fake.failDisconnect = true;
      await c.cancel();
      expect(container.read(commissionProvider).step, 2);
      expect(container.read(commissionProvider).busy, isFalse);
      expect(c.heldCleanupRequired, isTrue);
      fake.failDisconnect = false;
      await c.cancel();
      expect(container.read(commissionProvider).step, 1);
      expect(c.heldCleanupRequired, isFalse);
      expect(fake.linkedPeer, isNull);
    },
  );

  testWidgets(
    'failed commissioning keeps retry disconnect available on its selected card',
    (tester) async {
      final fake = _Gateway();
      final container = await _pumpApp(tester, fake);
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      await _tap(tester, find.byKey(const Key('gateway-link-identify')));
      await _settle(tester);
      fake.failConfigRead = true;
      fake.failDisconnect = true;
      await _tap(
        tester,
        find.byKey(const ValueKey('gateway-start-demo-gateway')),
      );
      await _settle(tester);
      expect(container.read(commissionProvider).step, 1);
      expect(
        container.read(commissionProvider.notifier).heldCleanupRequired,
        isTrue,
      );
      expect(find.text('重試斷開'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('gateway-start-demo-gateway')),
            )
            .onPressed,
        isNull,
      );
      fake.failDisconnect = false;
      await _tap(tester, find.byKey(const Key('gateway-disconnect')));
      expect(find.byKey(const Key('gateway-link-identify')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scale in [1.3, 2.0]) {
    testWidgets(
      '360x640 actions at text scale $scale stay usable through cleanup failure',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final list = await _pumpList(tester, textScale: scale);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(ValueKey(_a.id)));
        await tester.tap(find.byKey(ValueKey(_a.id)));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(ValueKey('gateway-start-${_a.id}')),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(
          find.byKey(const Key('gateway-link-identify')),
        );
        await tester.tap(find.byKey(const Key('gateway-link-identify')));
        await _run(tester);
        expect(tester.takeException(), isNull);
        list.holding.complete(true);
        await _run(tester);
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(ValueKey('gateway-start-${_a.id}')),
              )
              .onPressed,
          isNotNull,
        );
        list.failRelease = true;
        await tester.ensureVisible(find.byKey(const Key('gateway-disconnect')));
        await tester.tap(find.byKey(const Key('gateway-disconnect')));
        await _run(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('重試斷開'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(ValueKey('gateway-start-${_a.id}')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester.widget<InkWell>(find.byKey(ValueKey(_b.id))).onTap,
          isNull,
        );
        list.failRelease = false;
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'status-page scanner stays gated from pending connect until cleanup succeeds',
    () async {
      final fake = _Gateway();
      final (container, c, peer) = await _ready(fake);
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isTrue,
      );
      fake.holdConnect = Completer<void>();
      final hold = c.holdPeer(peer);
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isFalse,
      );
      fake.holdConnect!.complete();
      expect(await hold, isTrue);
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isFalse,
      );
      fake.holdDisconnect = Completer<void>();
      fake.failDisconnect = true;
      final release = c.releaseHeld();
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isFalse,
      );
      fake.holdDisconnect!.complete();
      await expectLater(release, throwsA(isA<GatewayFailure>()));
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isFalse,
      );
      fake.failDisconnect = false;
      await c.releaseHeld();
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isTrue,
      );
    },
  );

  for (final next in [false, true]) {
    test(
      'finishDone next=$next waits for confirmed cleanup, preserves progress on failure and retries',
      () async {
        final fake = _Gateway();
        final (container, c, peer) = await _ready(
          fake,
          topology: GatewayTopology.star,
        );
        await c.prepare('https://example.invalid', 'test-password');
        await _completeDemoCommissioning(container, peer);
        expect(container.read(commissionProvider).step, 7);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('demo_progress'), isNotNull);
        fake.holdDisconnect = Completer<void>();
        fake.failDisconnect = true;
        final finishing = c.finishDone(next: next);
        await _microtasks();
        expect(container.read(commissionProvider).step, 7);
        expect(container.read(commissionProvider).busy, isTrue);
        expect(
          gatewayStatusMenuEnabled(container.read(commissionProvider)),
          isFalse,
        );
        await c.finishDone(next: !next);
        fake.holdDisconnect!.complete();
        await finishing;
        final failed = container.read(commissionProvider);
        expect(failed.step, 7);
        expect(failed.busy, isFalse);
        expect(failed.discoveryLinkActive, isTrue);
        expect(failed.error, contains('重試斷開'));
        expect(failed.errorDetail, contains('cleanup_failed'));
        expect(c.heldCleanupRequired, isTrue);
        expect(await c.holdPeer(_b), isFalse);
        expect(prefs.getString('demo_progress'), isNotNull);
        fake.failDisconnect = false;
        await c.finishDone(next: next);
        final finished = container.read(commissionProvider);
        expect(finished.step, next ? 1 : 0);
        expect(finished.busy, isFalse);
        expect(finished.discoveryLinkActive, isFalse);
        expect(finished.error, isNull);
        expect(c.heldCleanupRequired, isFalse);
        expect(fake.linkedPeer, isNull);
        expect(prefs.getString('demo_progress'), isNull);
      },
    );
  }

  testWidgets(
    'done-page cleanup failure leaves enabled finish retry and blocks navigation',
    (tester) async {
      final fake = _Gateway();
      final container = await _pumpApp(tester, fake);
      await tester.runAsync(() async {
        await container
            .read(topologyProvider.notifier)
            .setTopology(GatewayTopology.star);
        final c = container.read(commissionProvider.notifier);
        await c.scan();
        await _completeDemoCommissioning(
          container,
          container.read(commissionProvider).peers.single,
        );
      });
      await _settle(tester);
      expect(container.read(commissionProvider).step, 7);
      fake.failDisconnect = true;
      await _tap(tester, find.byKey(const Key('done-finish')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(container.read(commissionProvider).step, 7);
      expect(container.read(commissionProvider).error, contains('重試斷開'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('done-finish')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('done-next')))
            .onPressed,
        isNotNull,
      );
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isFalse,
      );
      fake.failDisconnect = false;
      await _tap(tester, find.byKey(const Key('done-finish')));
      await _settle(tester);
      expect(container.read(commissionProvider).step, 0);
      expect(
        gatewayStatusMenuEnabled(container.read(commissionProvider)),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'whole app: select, connect, identify, start commissioning reuses link',
    (tester) async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final container = await _pumpApp(tester, fake);
      fake.connected.clear();
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      expect(fake.connected, isEmpty);
      await _tap(tester, find.byKey(const Key('gateway-link-identify')));
      await _settle(tester);
      expect(fake.connected, ['demo-gateway']);
      expect(_markText(tester, _demo), gatewayHeldLabel);
      await _tap(tester, _bulb(_demo));
      await _settle(tester);
      expect(fake.identifyRequests, hasLength(1));
      expect(fake.sent('set_config'), isEmpty);
      await _tap(
        tester,
        find.byKey(const ValueKey('gateway-start-demo-gateway')),
      );
      await _settle(tester);
      expect(container.read(commissionProvider).step, 2);
      expect(fake.connected, ['demo-gateway']);
    },
  );
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
  Completer<void>? releaseGate;
  bool failRelease = false;
  final choice = GatewayChoice();
  final lost = StreamController<String>.broadcast();
}

Future<_List> _pumpList(WidgetTester tester, {double textScale = 1}) async {
  SharedPreferences.setMockInitialValues({});
  final list = _List(_ScanLink());
  addTearDown(list.lost.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [linkProvider.overrideWithValue(list.link)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: GatewayScanBar(choice: list.choice),
          body: SingleChildScrollView(
            child: GatewayDiscovery(
              enabled: true,
              choice: list.choice,
              onConnect: (_) async {},
              onIdentify: (peer) async {
                list.identified.add(peer.id);
                return true;
              },
              onHold: (peer) {
                list.holds.add(peer.id);
                return list.holding.future;
              },
              onRelease: () async {
                list.releases++;
                await list.releaseGate?.future;
                if (list.failRelease) {
                  throw const GatewayFailure('cleanup_failed');
                }
              },
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

Future<void> _completeDemoCommissioning(
  ProviderContainer container,
  GatewayPeer peer,
) async {
  final c = container.read(commissionProvider.notifier);
  await c.connect(peer);
  await c.configureWifi(80, 1, 'Demo-Network', 'test-password');
  await c.online();
  await c.discover();
  await c.configurePtus();
  await c.verify('https://example.invalid', '');
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
