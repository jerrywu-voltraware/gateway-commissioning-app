import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

import 'support/real_fonts.dart';

const _a = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S50-GW01', -40);
const _b = GatewayPeer('AA:BB:CC:DD:3B:02', 'GIOS-S51-GW01', -55);

/// Records the real controller's requests, while holding only transport
/// completion. Selection, readiness and cancellation remain production code.
class _TwoGateways extends DemoSystem {
  _TwoGateways() {
    config['site_id'] = 50;
    config['gateway_id'] = 1;
    config['max_connections'] = 5;
    config['ble_enabled'] = false;
  }

  @override
  bool get demo => false;

  final connectedPeers = <String>[];
  final sentCommands = <String>[];
  Completer<void>? connectGate;
  Completer<void>? cleanupGate;
  bool failCleanup = false;

  @override
  Future<List<GatewayPeer>> scan() async => const [_a, _b];

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    connectedPeers.add(peer.id);
    final pending = connectGate;
    await pending?.future;
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<void> disconnect() async {
    final pending = cleanupGate;
    await pending?.future;
    if (failCleanup) throw const GatewayFailure('cleanup_failed');
    await super.disconnect();
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    sentCommands.add(op);
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await super.request(method, path, body);
    if (!path.contains('fleet-status')) return response;
    return {
      ...response,
      'gateways': [
        {'site_id': 50, 'gateway_id': 1, 'online': false},
      ],
    };
  }
}

ThemeData _theme(Brightness brightness) =>
    withRealFonts(gatewayTheme(brightness));

Future<void> _frames(WidgetTester tester) async {
  // Do not pumpAndSettle a deliberately pending connection's spinner.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<ProviderContainer> _openGatewayPage(
  WidgetTester tester,
  _TwoGateways fake, {
  Size size = const Size(360, 740),
  double scale = 1,
  bool savedProgress = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({
    'backend_environment': 'production',
    'recent_gateways': jsonEncode([
      {'id': _a.id, 'name': _a.name, 'uid': 'AABBCCDD3A00'},
    ]),
    if (savedProgress)
      'progress': jsonEncode({
        'step': 1,
        'shown': 1,
        'completed': false,
        'site': 50,
        'gateway': 1,
        'gateway_label': '站 50 · 閘道器 1 · …3A00',
        'selected': <String>[],
        'done': <String, int>{},
        'inflight': <String, int>{},
      }),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        backendKeyProvider.overrideWithValue('test-build-key'),
        envSwitchPolicyProvider.overrideWithValue(
          const EnvSwitchPolicy(
            autoSyncDefault: false,
            confirmGatewaySwitch: true,
            localBuild: false,
          ),
        ),
      ],
      child: const GatewayApp(theme: _theme),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  // Let SharedPreferences complete in the zone that created this provider.
  // Awaiting its fake-zone Future inside runAsync would deadlock the fixture.
  container.read(backendEnvProvider);
  await _frames(tester);
  await tester.pumpAndSettle();
  expect(container.read(backendEnvProvider).loaded, isTrue);
  await tester.runAsync(() async {
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.direct);
    await container
        .read(commissionProvider.notifier)
        .prepare(container.read(backendEnvProvider).base, '');
  });
  await _frames(tester);
  expect(container.read(commissionProvider).step, 1);
  expect(container.read(commissionProvider).savedProgress, savedProgress);
  expect(find.byType(GatewayDiscovery), findsOneWidget);
  expect(find.byKey(ValueKey(_a.id)), findsOneWidget);
  expect(find.byKey(ValueKey(_b.id)), findsOneWidget);
  return container;
}

Finder _card(GatewayPeer peer) => find.byKey(ValueKey(peer.id));
Finder _unselectedConnect(GatewayPeer peer) =>
    find.byKey(Key('gateway-link-${peer.id}'));
Finder _bulb(GatewayPeer peer) => find.byKey(ValueKey('identify-${peer.id}'));
Finder get _disconnect => find.byKey(const Key('gateway-disconnect'));
Finder get _commission => find.byKey(const Key('gateway-connect'));

ButtonStyleButton _button(WidgetTester tester, Finder finder) =>
    tester.widget<ButtonStyleButton>(finder);

void _expectReadOnly(_TwoGateways fake) {
  expect(fake.sentCommands.where((op) => op.startsWith('set_')), isEmpty);
  expect(fake.config['max_connections'], 5);
  expect(fake.config['ble_enabled'], isFalse);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  // Interactions can scroll if needed. The initial-layout tests deliberately
  // never call this helper or ensureVisible before their visibility checks.
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _frames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(
      await loadRealFonts(),
      isTrue,
      reason: 'Card visibility requires Roboto and the existing CJK font.',
    );
  });

  for (final size in const [
    Size(360, 640),
    Size(360, 740),
    Size(320, 658),
    Size(320, 640),
  ]) {
    for (final scale in const [1.0, 1.1, 1.3]) {
      // The measured Samsung viewport is 320x657.78 logical pixels at 1.1.
      // Keep its rounded size and an additional narrower/taller-text stress.
      if (size.width == 320 &&
          ((size.height == 658 && scale != 1.1) ||
              (size.height == 640 && scale != 1.3))) {
        continue;
      }
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} @$scale saved progress '
        'leaves first card and connect visible without scrolling',
        (tester) async {
          final fake = _TwoGateways();
          await _openGatewayPage(tester, fake, size: size, scale: scale);
          final viewport = tester.getRect(find.byType(ListView).first);
          final firstCard = tester.getRect(
            find.byKey(ValueKey('gateway-card-${_a.id}')),
          );
          final firstConnect = _unselectedConnect(_a);
          final secondTitle = find.byKey(ValueKey('gateway-title-${_b.id}'));
          final titleRect = tester.getRect(secondTitle);
          expect(firstCard.top, greaterThanOrEqualTo(viewport.top));
          expect(firstCard.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(firstCard.left, greaterThanOrEqualTo(viewport.left));
          expect(firstCard.right, lessThanOrEqualTo(viewport.right));
          final connectRect = tester.getRect(firstConnect);
          expect(connectRect.top, greaterThanOrEqualTo(viewport.top));
          expect(connectRect.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(firstConnect.hitTestable(), findsOneWidget);
          expect(_button(tester, firstConnect).onPressed, isNotNull);
          expect(titleRect.top, greaterThanOrEqualTo(viewport.top));
          expect(
            titleRect.bottom,
            lessThanOrEqualTo(viewport.bottom),
            reason: 'The second gateway title must be discoverable on entry.',
          );
          for (final element in find.byType(Scrollable).evaluate()) {
            final scroll =
                (element as StatefulElement).state as ScrollableState;
            if (scroll.widget.axisDirection == AxisDirection.down) {
              expect(scroll.position.pixels, 0);
            }
          }
          expect(fake.connectedPeers, isEmpty);
          expect(fake.sentCommands, isEmpty);
          expect(_bulb(_a), findsNothing);
          expect(_bulb(_b), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final peer in const [_a, _b]) {
    testWidgets('unselected ${peer.id} button connects only that peer; '
        'identify appears only after ready', (tester) async {
      final fake = _TwoGateways()..connectGate = Completer<void>();
      final container = await _openGatewayPage(tester, fake);
      final controller = container.read(commissionProvider.notifier);
      final other = peer.id == _a.id ? _b : _a;
      expect(controller.heldPeerId, isNull);
      await _tapVisible(tester, _unselectedConnect(peer));
      expect(fake.connectedPeers, [peer.id]);
      expect(_button(tester, _unselectedConnect(other)).onPressed, isNull);
      expect(tester.widget<InkWell>(_card(other)).onTap, isNull);
      expect(_button(tester, _commission).onPressed, isNull);
      expect(_bulb(peer), findsNothing);
      expect(_bulb(other), findsNothing);
      await _tapVisible(tester, _unselectedConnect(other));
      expect(fake.connectedPeers, [peer.id]);
      fake.connectGate!.complete();
      await _frames(tester);
      expect(controller.heldPeerId, peer.id);
      expect(_bulb(peer), findsOneWidget);
      expect(_bulb(other), findsNothing);
      expect(_button(tester, _commission).onPressed, isNotNull);
      await _tapVisible(tester, _bulb(peer));
      expect(fake.identifyRequests, hasLength(1));
      expect(fake.connectedPeers, [peer.id]);
      _expectReadOnly(fake);
      await _tapVisible(tester, _disconnect);
      expect(controller.heldPeerId, isNull);
      expect(_bulb(peer), findsNothing);
      expect(_button(tester, _commission).onPressed, isNull);
      expect(_button(tester, _unselectedConnect(other)).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('cancel waits for cleanup; late A success cannot publish ready '
      'or unlock B before cleanup', (tester) async {
    final fake = _TwoGateways()..connectGate = Completer<void>();
    final container = await _openGatewayPage(tester, fake);
    final controller = container.read(commissionProvider.notifier);
    await _tapVisible(tester, _unselectedConnect(_a));
    expect(fake.connectedPeers, [_a.id]);
    fake.cleanupGate = Completer<void>();
    await _tapVisible(tester, _disconnect);
    expect(controller.heldCleanupRequired, isTrue);
    expect(_button(tester, _unselectedConnect(_b)).onPressed, isNull);
    expect(_button(tester, _commission).onPressed, isNull);
    // Native success arrives after cancellation but before disconnect drains.
    fake.connectGate!.complete();
    await _frames(tester);
    expect(controller.heldPeerId, isNull);
    expect(_bulb(_a), findsNothing);
    expect(_bulb(_b), findsNothing);
    expect(
      fake.sentCommands,
      isEmpty,
      reason: 'Stale A cannot even read config.',
    );
    expect(_button(tester, _unselectedConnect(_b)).onPressed, isNull);
    await _tapVisible(tester, _unselectedConnect(_b));
    expect(fake.connectedPeers, [_a.id]);
    fake.cleanupGate!.complete();
    await _frames(tester);
    expect(controller.heldCleanupRequired, isFalse);
    fake.connectGate = null;
    fake.cleanupGate = null;
    await _tapVisible(tester, _unselectedConnect(_b));
    expect(fake.connectedPeers, [_a.id, _b.id]);
    expect(controller.heldPeerId, _b.id);
    expect(_bulb(_a), findsNothing);
    expect(_bulb(_b), findsOneWidget);
    _expectReadOnly(fake);
    await _tapVisible(tester, _disconnect);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed cleanup keeps its owner; a stale A disconnect cannot release B',
    (tester) async {
      final fake = _TwoGateways();
      final container = await _openGatewayPage(tester, fake);
      final controller = container.read(commissionProvider.notifier);
      await _tapVisible(tester, _unselectedConnect(_a));
      expect(controller.heldPeerId, _a.id);
      final oldDisconnectA = _button(tester, _disconnect).onPressed!;
      fake.failCleanup = true;
      await _tapVisible(tester, _disconnect);
      expect(controller.heldCleanupRequired, isTrue);
      expect(_button(tester, _disconnect).onPressed, isNotNull);
      expect(_button(tester, _unselectedConnect(_b)).onPressed, isNull);
      expect(_bulb(_a), findsNothing);
      expect(_button(tester, _commission).onPressed, isNull);
      fake.failCleanup = false;
      await _tapVisible(tester, _disconnect);
      expect(controller.heldCleanupRequired, isFalse);
      await _tapVisible(tester, _unselectedConnect(_b));
      expect(controller.heldPeerId, _b.id);
      expect(fake.connectedPeers, [_a.id, _b.id]);
      final disconnectsBeforeStale = fake.linkDisconnects;
      oldDisconnectA();
      await _frames(tester);
      expect(controller.heldPeerId, _b.id);
      expect(fake.linkDisconnects, disconnectsBeforeStale);
      expect(_bulb(_b), findsOneWidget);
      expect(_button(tester, _commission).onPressed, isNotNull);
      _expectReadOnly(fake);
      await _tapVisible(tester, _disconnect);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
