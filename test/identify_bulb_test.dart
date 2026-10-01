// The gateway list's 〔辨識〕 bulb (the light bulb on every row):
// - the tapped row's bulb is a small spinner from the tap — before the scan
//   even stops — until the identify ends (blinked, failed or cancelled), in
//   the icon's own box so nothing moves; other rows keep their bulb;
// - [CommissioningController.identifyPeer] still answers true when the PTU
//   side was not connected (the gateway alone blinked), and says so through
//   `identifyPeerGatewayOnly`: either the old firmware's `not_connected`
//   failure of target=both (then target=gateway is sent) or firmware
//   1.7.45's ok ack whose `ptu_write` is `not_connected`;
// - the row and the SnackBar then say the gateway blinked and the PTU will
//   not ([identifiedGatewayOnlyHint] / [identifiedGatewayOnlyNote]); with a
//   PTU connected they keep the plain 「已送出」.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

const _a = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -40);
const _b = GatewayPeer('AA:BB:CC:DD:3B:02', 'GIOS-S81-GW02', -55);

/// A gateway whose identify can be steered: [bothFailsNotConnected] makes
/// target=both fail with the gateway's `not_connected` (older firmware);
/// [holdConnect] keeps a connect pending.
class _Link extends DemoSystem {
  bool bothFailsNotConnected = false;
  String? bothFailsWith;
  Completer<void>? holdConnect;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    await holdConnect?.future;
    return super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final code =
        bothFailsWith ?? (bothFailsNotConnected ? 'not_connected' : null);
    if (op == 'identify' && code != null && params['target'] == 'both') {
      identifyRequests.add(Map.of(params));
      throw GatewayFailure.gateway(code);
    }
    return super.command(op, params);
  }
}

/// A live scan whose stop can be held (the scan takes a while to stop).
class _ScanLink extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];
  Completer<void>? holdStop;

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final scan = StreamController<List<GatewayPeer>>();
    scans.add(scan);
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    await holdStop?.future;
    for (final scan in scans) {
      if (!scan.isClosed) unawaited(scan.close());
    }
  }

  void hear(List<GatewayPeer> peers) => scans.last.add(peers);
}

Future<_ScanLink> _pumpList(
  WidgetTester tester, {
  required Future<bool> Function(GatewayPeer) onIdentify,
  bool Function()? identifyGatewayOnly,
}) async {
  SharedPreferences.setMockInitialValues({});
  final link = _ScanLink();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [linkProvider.overrideWithValue(link)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GatewayDiscovery(
              enabled: true,
              onConnect: (_) async {},
              onIdentify: onIdentify,
              identifyGatewayOnly: identifyGatewayOnly,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  link.hear(const [_a, _b]);
  await tester.pump();
  return link;
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

Finder _icon(GatewayPeer peer, IconData icon) =>
    find.descendant(of: _bulb(peer), matching: find.byIcon(icon));

Finder _chip(GatewayPeer peer, String text) => find.descendant(
  of: find.byKey(ValueKey('gateway-presence-${peer.id}')),
  matching: find.text(text),
);

Finder get _snack => find.byKey(const Key('gateway-identified-snack'));

// ---------------------------------------------------------------------------
// The real controller on the demo gateway.
// ---------------------------------------------------------------------------

Future<(ProviderContainer, CommissioningController, GatewayPeer)> _controller(
  DemoSystem fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  return (container, c, container.read(commissionProvider).peers.single);
}

/// The whole app on the demo gateway, the list (step 1) showing.
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

const _demo = GatewayPeer('demo-gateway', 'GIOS-S1-GW01', -50);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the bulb of the row being identified', () {
    testWidgets('a spinner at once (before the scan stops), in the icon\'s own '
        'box; a bulb again afterwards', (tester) async {
      final identify = Completer<bool>();
      var calls = 0;
      final link = await _pumpList(
        tester,
        onIdentify: (_) {
          calls++;
          return identify.future;
        },
        identifyGatewayOnly: () => false,
      );
      final bulbSize = tester.getSize(_bulb(_a));
      final cardA = find.byKey(ValueKey('gateway-card-${_a.id}'));
      final cardB = find.byKey(ValueKey('gateway-card-${_b.id}'));
      final cardSizeA = tester.getSize(cardA);
      final cardSizeB = tester.getSize(cardB);
      final topB = tester.getTopLeft(cardB);
      expect(_spinner(_a), findsNothing);
      expect(_icon(_a, Icons.lightbulb_outline), findsOneWidget);
      expect(
        tester.widget<IconButton>(_bulb(_a)).tooltip,
        identifyGatewayLabel,
      );

      // The scan takes its time to stop: the identify has not even begun.
      link.holdStop = Completer<void>();
      await tester.tap(_bulb(_a));
      await tester.pump();
      expect(calls, 0, reason: 'still stopping the scan');
      expect(_spinner(_a), findsOneWidget);
      expect(_icon(_a, Icons.lightbulb_outline), findsNothing);
      expect(
        find.byKey(ValueKey('identify-progress-${_a.id}')),
        findsOneWidget,
      );
      // The other row keeps its bulb, and nothing moves or changes size.
      expect(_spinner(_b), findsNothing);
      expect(_icon(_b, Icons.lightbulb_outline), findsOneWidget);
      expect(tester.getSize(_bulb(_a)), bulbSize);
      expect(tester.getSize(cardA), cardSizeA);
      expect(tester.getSize(cardB), cardSizeB);
      expect(tester.getTopLeft(cardB), topB);

      // Stopped: the identify runs, the spinner stays.
      link.holdStop!.complete();
      await _run(tester);
      expect(calls, 1);
      expect(_spinner(_a), findsOneWidget);
      expect(tester.getSize(_bulb(_a)), bulbSize);

      // Blinked: the bulb is back, solid; the plain hint and SnackBar.
      identify.complete(true);
      await _run(tester);
      expect(_spinner(_a), findsNothing);
      expect(_icon(_a, Icons.lightbulb), findsOneWidget);
      expect(_icon(_b, Icons.lightbulb_outline), findsOneWidget);
      expect(_bulb(_a), findsOneWidget);
      expect(tester.getSize(cardA), cardSizeA);
      expect(tester.getTopLeft(cardB), topB);
      expect(_chip(_a, identifiedHint), findsOneWidget);
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedHint),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedGatewayOnlyNote),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('not blinked (failed, cancelled): the bulb is back as it was, '
        'no hint, no SnackBar, gateway-only never asked', (tester) async {
      var asked = 0;
      await _pumpList(
        tester,
        onIdentify: (_) async => false,
        identifyGatewayOnly: () {
          asked++;
          return true;
        },
      );
      await tester.tap(_bulb(_a));
      await tester.pump();
      expect(_spinner(_a), findsOneWidget);
      await _run(tester);
      expect(_spinner(_a), findsNothing);
      expect(_icon(_a, Icons.lightbulb_outline), findsOneWidget);
      expect(_icon(_a, Icons.lightbulb), findsNothing);
      expect(_snack, findsNothing);
      expect(_chip(_a, identifiedHint), findsNothing);
      expect(_chip(_a, identifiedGatewayOnlyHint), findsNothing);
      expect(asked, 0);
      // The bulb works again.
      await tester.tap(_bulb(_a));
      await tester.pump();
      expect(_spinner(_a), findsOneWidget);
      await _run(tester);
      expect(_spinner(_a), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the list says when only the gateway blinked', () {
    testWidgets('the row and the SnackBar warn, for longer than the plain '
        'hint', (tester) async {
      await _pumpList(
        tester,
        onIdentify: (_) async => true,
        identifyGatewayOnly: () => true,
      );
      await tester.tap(_bulb(_a));
      await _run(tester);
      // The solid bulb stays: the gateway did blink.
      expect(_icon(_a, Icons.lightbulb), findsOneWidget);
      expect(_chip(_a, identifiedGatewayOnlyHint), findsOneWidget);
      expect(_chip(_a, identifiedHint), findsNothing);
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedGatewayOnlyNote),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedHint),
        ),
        findsNothing,
      );
      expect(identifiedGatewayOnlyNote, contains('沒連到 PTU'));
      expect(identifiedGatewayOnlyNote, contains('PTU 不會閃'));
      // Past the plain hint's 3 s it is still there; gone after 6 s.
      await tester.pump(identifiedHintFor + const Duration(milliseconds: 100));
      expect(_chip(_a, identifiedGatewayOnlyHint), findsOneWidget);
      expect(_snack, findsOneWidget);
      await tester.pump(identifiedGatewayOnlyFor);
      await tester.pump(const Duration(seconds: 1));
      expect(_chip(_a, identifiedGatewayOnlyHint), findsNothing);
      expect(_snack, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the plain hint and SnackBar are unchanged (3 s) when the '
        'identify reached the PTU, or when nothing says otherwise', (
      tester,
    ) async {
      for (final answer in <bool Function()?>[() => false, null]) {
        await _pumpList(
          tester,
          onIdentify: (_) async => true,
          identifyGatewayOnly: answer,
        );
        await tester.tap(_bulb(_b));
        await _run(tester);
        expect(_chip(_b, identifiedHint), findsOneWidget);
        expect(_chip(_b, identifiedGatewayOnlyHint), findsNothing);
        final text = tester.widget<Text>(
          find.descendant(of: _snack, matching: find.byType(Text)).first,
        );
        expect(text.data, endsWith(' $identifiedHint'));
        expect(text.data, isNot(contains(identifiedGatewayOnlyNote)));
        await tester.pump(
          identifiedHintFor + const Duration(milliseconds: 100),
        );
        expect(_chip(_b, identifiedHint), findsNothing);
        // The SnackBar's own timer starts once it has slid in.
        await tester.pump(identifiedHintFor);
        await tester.pump(const Duration(seconds: 1));
        expect(_snack, findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    test('the SnackBar sentences', () {
      expect(
        identifiedGatewayOnlySnackText('GIOS-S80-GW02'),
        '站 80 · 閘道器 2：$identifiedGatewayOnlyNote',
      );
      expect(
        identifiedGatewayOnlySnackText('x', title: '未配置閘道器 …70F0'),
        '未配置閘道器 …70F0：閘道器已閃燈；它目前沒連到 PTU，PTU 不會閃',
      );
      // The plain one is as it was.
      expect(identifiedSnackText('GIOS-S80-GW02'), '站 80 · 閘道器 2 已送出');
    });
  });

  group('identifyPeer: only the gateway blinked', () {
    test('both acked ok, ptu_write not_connected (firmware 1.7.45): answers '
        'true, gateway only', () async {
      final fake = _Link();
      final (_, c, peer) = await _controller(fake);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
      ]);
    });

    test('both failing with not_connected falls back to the gateway alone: '
        'still true, gateway only', () async {
      final fake = _Link()..bothFailsNotConnected = true;
      final (container, c, peer) = await _controller(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
        {'target': 'gateway', 'duration_ms': 4000},
      ]);
      expect(container.read(commissionProvider).error, isNull);
      expect(container.read(commissionProvider).busy, isFalse);
    });

    test('a PTU connected: the PTU got it, not gateway only', () async {
      final fake = _Link();
      fake.devices.first['connected'] = true;
      final (_, c, peer) = await _controller(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
      ]);
    });

    test('each call resets it: a PTU connected later, a gateway that cannot '
        'identify', () async {
      final fake = _Link();
      final (container, c, peer) = await _controller(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      fake.devices.first['connected'] = true;
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isFalse);
      // Gateway only again, then a failed identify: nothing left over.
      fake.devices.first['connected'] = false;
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      fake.config['identify_supported'] = false;
      expect(await c.identifyPeer(peer), isFalse);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(container.read(commissionProvider).busy, isFalse);
    });

    test('firmware without identify_ptu_supported sends the bare op and is '
        'not called gateway only', () async {
      final fake = _Link();
      fake.config.remove('identify_ptu_supported');
      final (container, c, peer) = await _controller(fake);
      // Pre-PTU firmware takes only its fixed six seconds (the APP default
      // 4 is refused; see identify_seconds_test), so pick 6 here.
      await container.read(topologyProvider.notifier).setIdentifySeconds(6);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(fake.identifyRequests, [<String, dynamic>{}]);
    });

    test('any other failure of both is still thrown, never turned into a '
        'gateway-only blink', () async {
      final fake = _Link()..bothFailsWith = 'ambiguous_target';
      final (_, c, peer) = await _controller(fake);
      expect(await c.identifyPeer(peer), isFalse);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
      ], reason: 'no second, gateway-only send');
    });
  });

  group('on the real page', () {
    testWidgets('a spinner on the row while the connect is pending, a solid '
        'bulb after; nothing else spins', (tester) async {
      final fake = _Link()..devices.first['connected'] = true;
      final container = await _pumpApp(tester, fake);
      CommissionState read() => container.read(commissionProvider);
      expect(_spinner(_demo), findsNothing);
      fake.holdConnect = Completer<void>();
      await tester.ensureVisible(_bulb(_demo));
      await tester.pumpAndSettle();
      await tester.tap(_bulb(_demo));
      await tester.pump();
      expect(_spinner(_demo), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(read().busy, isTrue, reason: 'the identify is still connecting');
      expect(_spinner(_demo), findsOneWidget, reason: 'the page rebuilt');
      fake.holdConnect!.complete();
      await tester.pumpAndSettle();
      expect(read().busy, isFalse);
      expect(_spinner(_demo), findsNothing);
      expect(_icon(_demo, Icons.lightbulb), findsOneWidget);
      expect(_chip(_demo, identifiedHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a PTU connected: the row and the SnackBar keep the plain '
        '「已送出」', (tester) async {
      final fake = _Link()..devices.first['connected'] = true;
      await _pumpApp(tester, fake);
      await _tap(tester, _bulb(_demo));
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
      ]);
      expect(_chip(_demo, identifiedHint), findsOneWidget);
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedHint),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedGatewayOnlyNote),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no PTU connected (ok ack, ptu_write not_connected): the row '
        'and the SnackBar say only the gateway blinked', (tester) async {
      final fake = _Link();
      final container = await _pumpApp(tester, fake);
      await _tap(tester, _bulb(_demo));
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
      ]);
      expect(container.read(commissionProvider).error, isNull);
      expect(_icon(_demo, Icons.lightbulb), findsOneWidget);
      expect(_chip(_demo, identifiedGatewayOnlyHint), findsOneWidget);
      expect(_chip(_demo, identifiedHint), findsNothing);
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedGatewayOnlyNote),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('both failing with not_connected, the gateway alone sent: the '
        'same warning', (tester) async {
      final fake = _Link()..bothFailsNotConnected = true;
      final container = await _pumpApp(tester, fake);
      await _tap(tester, _bulb(_demo));
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
        {'target': 'gateway', 'duration_ms': 4000},
      ]);
      expect(container.read(commissionProvider).error, isNull);
      expect(_icon(_demo, Icons.lightbulb), findsOneWidget);
      expect(_chip(_demo, identifiedGatewayOnlyHint), findsOneWidget);
      expect(
        find.descendant(
          of: _snack,
          matching: find.textContaining(identifiedGatewayOnlyNote),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
