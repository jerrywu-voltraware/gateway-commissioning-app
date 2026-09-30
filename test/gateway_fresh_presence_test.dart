// A fresh phone knows advertised station numbers, but has no BLE-verified UID.
// Backend presence is a hint; it must not certify hardware or auto-connect.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/recent_gateways.dart';
import 'package:gateway_commissioning/gateway_app.dart';

import 'support/real_fonts.dart';

const _first = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -41);
const _second = GatewayPeer('AA:BB:CC:DD:3C:02', 'GIOS-S81-GW02', -59);
const _factory = GatewayPeer('AA:BB:CC:DD:70:F2', 'GIOS-S1-GW01', -70);

Map<String, dynamic> _row(
  int gateway, {
  int site = 81,
  Object? online = true,
  String uid = 'AA:BB:CC:DD:3A:00',
  Object? conflict = false,
}) => {
  'site_id': site,
  'gateway_id': gateway,
  'last_seen_mac': uid,
  'online': online,
  'conflict_flag': conflict,
};

List<Map<String, dynamic>> _fleet() => [
  _row(1),
  _row(2, uid: 'AA:BB:CC:DD:3C:00'),
];

class _FreshPhoneSystem extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];
  final connections = <String>[];
  final commands = <String>[];
  List<Map<String, dynamic>> rows = _fleet();
  List<Map<String, dynamic>> archived = [];
  bool failFleet = false;
  Completer<Map<String, dynamic>>? heldFleet;
  int fleetQueries = 0;

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final controller = StreamController<List<GatewayPeer>>();
    scans.add(controller);
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    for (final controller in scans) {
      if (!controller.isClosed) unawaited(controller.close());
    }
  }

  void hear([List<GatewayPeer> peers = const [_first, _second]]) =>
      scans.last.add(peers);

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    connections.add(peer.id);
    throw StateError('Discovery must not connect automatically');
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add(op);
    throw StateError('Discovery must not send gateway commands');
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!path.contains('fleet-status')) {
      return super.request(method, path, body);
    }
    fleetQueries++;
    if (failFleet) throw TimeoutException('Synthetic backend unavailable');
    if (heldFleet case final pending?) return pending.future;
    return {'gateways': rows, 'archived_gateways': archived};
  }
}

ThemeData _theme(Brightness brightness) =>
    withRealFonts(gatewayTheme(brightness));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(ProviderContainer, _FreshPhoneSystem)> _freshList(
  WidgetTester tester, {
  double scale = 1.1,
  bool offline = false,
  _FreshPhoneSystem? system,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  final link = system ?? _FreshPhoneSystem();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(link),
        apiProvider.overrideWithValue(link),
        backendKeyProvider.overrideWithValue('synthetic-build-key'),
      ],
      child: const GatewayApp(theme: _theme),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  await tester.runAsync(() async {
    await container.read(backendEnvProvider.notifier).ready;
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.star);
    expect(await RecentGateways.load(false), isEmpty);
    expect(await RecentGateways.load(true), isEmpty);
    await container
        .read(commissionProvider.notifier)
        .prepare(
          container.read(backendEnvProvider).base,
          'synthetic-password',
          offline: offline,
        );
  });
  await _settle(tester);
  expect(container.read(commissionProvider).step, 1);
  link.hear();
  await tester.pump();
  return (container, link);
}

Finder _card(GatewayPeer peer) =>
    find.byKey(ValueKey('gateway-card-${peer.id}'));

void _status(GatewayPeer peer, String presence, {bool pending = true}) {
  expect(_card(peer), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(ValueKey('gateway-presence-${peer.id}')),
      matching: find.text(presence),
    ),
    findsOneWidget,
  );
  expect(find.byKey(ValueKey('gateway-configured-${peer.id}')), findsNothing);
  if (pending) {
    expect(
      find.byKey(ValueKey('gateway-unconfigured-${peer.id}')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('gateway-pending-${peer.id}')),
        matching: find.text('待核對'),
      ),
      findsOneWidget,
    );
  }
}

void _noCardOverflow(WidgetTester tester, GatewayPeer peer) {
  expect(tester.takeException(), isNull);
  final card = tester.getRect(_card(peer));
  expect(card.left, greaterThanOrEqualTo(0));
  expect(card.right, lessThanOrEqualTo(360));
  for (final element
      in find
          .descendant(of: _card(peer), matching: find.byType(RichText))
          .evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.hasSize) continue;
    final value = paragraph.text.toPlainText();
    if (value.runes.length == 1 && value.runes.single >= 0xE000) continue;
    expect(paragraph.didExceedMaxLines, isFalse, reason: 'Clipped: $value');
    if (paragraph.maxLines == 1) {
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: 'Too wide: $value',
      );
    }
  }
}

void main() {
  setUpAll(() async => expect(await loadRealFonts(), isTrue));

  group('unverified advertised identity is presence only', () {
    test('fresh 81/1 and 81/2 get their own online/offline hints', () {
      final rows = [_row(1), _row(2, online: false, uid: 'AA:BB:CC:DD:3C:00')];
      expect(
        backendPresenceShort(null, rows, advertisedName: _first.name),
        '後端在線',
      );
      expect(
        backendPresenceShort(null, rows, advertisedName: _second.name),
        '後端離線',
      );
      expect(gatewayConfigured(null, rows), isFalse);
      expect(backendPresence(null, rows), contains('連線後確認身分'));
      for (final peer in [_first, _second]) {
        expect(
          gatewayKnownUnconfigured(
            name: peer.name,
            fleet: rows,
            backendKnown: true,
          ),
          isFalse,
        );
      }
    });

    test(
      'malformed or absent remembered UID permits only nonfactory fallback',
      () {
        for (final uid in [null, '', 'invalid', 'AA:BB']) {
          expect(
            backendPresenceShort(uid, _fleet(), advertisedName: _first.name),
            '後端在線',
          );
          expect(gatewayConfigured(uid, _fleet()), isFalse);
        }
        for (final name in [
          null,
          '',
          'GIOS-S0-GW01',
          'GIOS-S81-GW00',
          'other',
        ]) {
          expect(
            backendPresenceShort(null, _fleet(), advertisedName: name),
            backendUnknownShort,
          );
        }
        expect(
          backendPresenceShort(null, [
            _row(1, site: 1),
          ], advertisedName: _factory.name),
          backendUnknownShort,
        );
      },
    );

    test(
      'a valid verified UID never falls back to a matching advertised name',
      () {
        expect(
          backendPresenceShort(
            '001122334455',
            _fleet(),
            advertisedName: _first.name,
          ),
          '後端無紀錄',
        );
        final rows = [
          _row(1),
          _row(2, uid: '00:11:22:33:44:55', online: false),
        ];
        expect(
          backendPresenceShort(
            '001122334455',
            rows,
            advertisedName: _first.name,
          ),
          '後端離線',
        );
        expect(
          backendPresenceShort(
            'AABBCCDD3A00',
            _fleet(),
            advertisedName: _factory.name,
          ),
          '後端在線',
        );
        expect(gatewayConfigured('AABBCCDD3A00', _fleet()), isTrue);
      },
    );

    test(
      'duplicate advertised identities or conflicting rows stay unknown',
      () {
        final variants = <List<dynamic>>[
          [_row(1), _row(1, uid: '001122334455')],
          [_row(1), _row(1)],
          [_row(1, conflict: true)],
          [_row(1, conflict: 1)],
          [_row(1, online: null)],
          [_row(1, online: 'true')],
        ];
        for (final rows in variants) {
          expect(
            backendPresenceShort(null, rows, advertisedName: _first.name),
            backendUnknownShort,
          );
          expect(gatewayConfigured(null, rows), isFalse);
        }
      },
    );

    test(
      'an archived hint does not verify hardware; overlapping records are unknown',
      () {
        expect(
          backendPresenceShort(
            null,
            [],
            archived: [_row(1)],
            advertisedName: _first.name,
          ),
          '後端已封存',
        );
        expect(
          backendPresenceShort(
            'AABBCCDD3A00',
            [],
            archived: [_row(1)],
            advertisedName: _first.name,
          ),
          '後端已封存',
        );
        expect(
          gatewayKnownUnconfigured(
            name: _first.name,
            fleet: [],
            archived: [_row(1)],
            backendKnown: true,
          ),
          isFalse,
        );
        expect(gatewayConfigured(null, [_row(1)]), isFalse);
        expect(
          backendPresenceShort(
            null,
            [_row(1)],
            archived: [_row(1)],
            advertisedName: _first.name,
          ),
          backendUnknownShort,
        );
        for (final archived in [
          [_row(1), _row(1)],
          [_row(1, conflict: true)],
        ]) {
          expect(
            backendPresenceShort(
              null,
              [],
              archived: archived,
              advertisedName: _first.name,
            ),
            backendUnknownShort,
          );
        }
      },
    );
  });

  for (final scale in [1.1, 1.3]) {
    testWidgets(
      'fresh phone 81/1 and 81/2 pending + online; no connection; 360dp @$scale',
      (tester) async {
        final (container, link) = await _freshList(tester, scale: scale);
        expect(link.fleetQueries, greaterThan(0));
        for (final (peer, title) in [
          (_first, '站 81 · 閘道器 1'),
          (_second, '站 81 · 閘道器 2'),
        ]) {
          await tester.ensureVisible(_card(peer));
          await tester.pump();
          _status(peer, '後端在線');
          expect(
            tester
                .widget<Text>(find.byKey(ValueKey('gateway-title-${peer.id}')))
                .data,
            title,
          );
          _noCardOverflow(tester, peer);
          await tester.tap(find.byKey(ValueKey(peer.id)));
          await tester.pump();
          _status(peer, '後端在線');
        }
        expect(link.connections, isEmpty);
        expect(link.commands, isEmpty);
        expect(container.read(commissionProvider).peer, isNull);
        expect(container.read(commissionProvider).busy, isFalse);
        await tester.runAsync(() async {
          expect(await RecentGateways.load(false), isEmpty);
          expect(await RecentGateways.load(true), isEmpty);
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('fresh offline session has pending cards and unknown backend', (
    tester,
  ) async {
    final (container, link) = await _freshList(tester, offline: true);
    expect(container.read(commissionProvider).loggedIn, isFalse);
    _status(_first, backendUnknownShort);
    _status(_second, backendUnknownShort);
    expect(link.fleetQueries, 0);
    expect(link.connections, isEmpty);
    expect(link.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an archived station hint remains pending on a fresh phone', (
    tester,
  ) async {
    final (_, link) = await _freshList(
      tester,
      system: _FreshPhoneSystem()
        ..rows = []
        ..archived = _fleet(),
    );
    _status(_first, '後端已封存');
    _status(_second, '後端已封存');
    expect(link.connections, isEmpty);
    expect(link.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'ambiguous or conflicting backend identities remain pending and unknown',
    (tester) async {
      final (_, link) = await _freshList(
        tester,
        system: _FreshPhoneSystem()
          ..rows = [
            _row(1),
            _row(1, uid: '001122334455'),
            _row(2, conflict: 1),
          ],
      );
      _status(_first, backendUnknownShort);
      _status(_second, backendUnknownShort);
      expect(link.connections, isEmpty);
      expect(link.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a failed refresh invalidates previous online hints', (
    tester,
  ) async {
    final (_, link) = await _freshList(tester);
    _status(_first, '後端在線');
    link.failFleet = true;
    final before = link.fleetQueries;
    await tester.pump(const Duration(seconds: 15));
    await _settle(tester);
    expect(link.fleetQueries, greaterThan(before));
    _status(_first, backendUnknownShort);
    _status(_second, backendUnknownShort);
    expect(link.connections, isEmpty);
    expect(link.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an environment switch rejects a late old-backend online response',
    (tester) async {
      final (_, link) = await _freshList(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      _status(_first, '後端在線');
      final held = link.heldFleet = Completer<Map<String, dynamic>>();
      final before = link.fleetQueries;
      await tester.pump(const Duration(seconds: 15));
      await _settle(tester);
      expect(link.fleetQueries, greaterThan(before));
      await tester.runAsync(() async {
        final env = container.read(backendEnvProvider.notifier);
        env.setLocalHost('127.0.0.1');
        await env.select(BackendEnv.local);
      });
      await tester.pump();
      _status(_first, backendUnknownShort);
      held.complete({'gateways': _fleet(), 'archived_gateways': <dynamic>[]});
      await _settle(tester);
      _status(_first, backendUnknownShort);
      _status(_second, backendUnknownShort);
      expect(link.connections, isEmpty);
      expect(link.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('factory 1/1 never borrows a shared backend record', (
    tester,
  ) async {
    final (_, link) = await _freshList(
      tester,
      system: _FreshPhoneSystem()..rows = [_row(1, site: 1)],
    );
    link.hear(const [_factory]);
    await tester.pump();
    _status(_factory, backendUnknownShort, pending: false);
    expect(
      find.byKey(ValueKey('gateway-unconfigured-${_factory.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('gateway-pending-${_factory.id}')),
      findsNothing,
    );
    expect(link.connections, isEmpty);
    expect(link.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
