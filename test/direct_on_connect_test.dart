// 1.0.0+22: one-to-one preferred (topologyProvider direct) —
// - explicitly continuing commissioning switches a gateway in star mode to
//   one-to-one right after get_config: `set_config max_connections=1`
//   (shipped units keep 5 in NVS; the firmware's BLE scan restarts, the
//   phone's link stays), and BLE scanning on when it was off, as step 7
//   does; already 1 → nothing sent; star preference → nothing sent;
// - 〔辨識〕 that blinked the gateway only (`ptu_write` not_connected) reads
//   one get_status while still connected and says why
//   ([CommissioningController.identifyPeerGatewayOnlyReason] →
//   [identifiedGatewayOnlyNoteFor]): just switched / no PTU heard / all
//   too weak / still picking; the plain note when get_status cannot be
//   read or carries no `direct`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

/// The demo gateway, every command recorded; [direct] replaces the
/// get_status `direct` object when set, [statusFails] refuses get_status,
/// [bothFailsNotConnected] makes target=both fail outright (older
/// firmware) so the gateway-only fallback runs.
class _Gateway extends DemoSystem {
  final commands = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic>? direct;
  bool statusFails = false;
  bool bothFailsNotConnected = false;
  final connections = <String>[];
  int disconnects = 0;

  @override
  Future<void> connect(GatewayPeer peer, {void Function(String)? onStage}) {
    connections.add(peer.id);
    return super.connect(peer, onStage: onStage);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    await super.disconnect();
  }

  List<Map<String, dynamic>> sent(String op) => [
    for (final (o, p) in commands)
      if (o == op) p,
  ];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add((op, Map.of(params)));
    if (op == 'get_status') {
      if (statusFails) throw const GatewayFailure('timeout');
      if (direct != null) {
        return {...await super.command(op, params), 'direct': direct};
      }
    }
    if (op == 'identify' &&
        bothFailsNotConnected &&
        params['target'] == 'both') {
      identifyRequests.add(Map.of(params));
      throw const GatewayFailure.gateway('not_connected');
    }
    return super.command(op, params);
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
  return (container, c, container.read(commissionProvider).peers.single);
}

/// The user explicitly connects for identification; this must only read config.
Future<(ProviderContainer, CommissioningController, GatewayPeer)> _held(
  _Gateway fake, {
  GatewayTopology topology = GatewayTopology.direct,
}) async {
  final ready = await _ready(fake, topology: topology);
  final (_, c, peer) = ready;
  final before = Map<String, dynamic>.of(fake.config);
  expect(await c.holdPeer(peer), isTrue);
  expect(c.heldPeerId, peer.id);
  expect(fake.commands.map((entry) => entry.$1), ['get_config']);
  expect(fake.config, before, reason: 'finding a gateway changes no settings');
  addTearDown(() => _expectNoConfigurationWrites(fake));
  return ready;
}

void _expectNoConfigurationWrites(_Gateway fake) {
  expect(fake.sent('set_config'), isEmpty);
  expect(fake.sent('set_ble_enabled'), isEmpty);
  expect(
    fake.commands.map((entry) => entry.$1),
    everyElement(isIn(['get_config', 'identify', 'get_status'])),
  );
}

/// The order of [ops] among the commands sent.
List<String> _order(_Gateway fake, Set<String> ops) => [
  for (final (o, _) in fake.commands)
    if (ops.contains(o)) o,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B1: the connect switches a star gateway to one-to-one', () {
    test('direct preferred, max_connections 5: set_config 1 right after '
        'get_config, before anything else is read', () async {
      final fake = _Gateway()..config['max_connections'] = 5;
      final (container, c, peer) = await _ready(fake);
      await c.connect(peer);
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.sent('set_config'), [
        {'max_connections': 1},
      ]);
      expect(fake.config['max_connections'], 1);
      expect(container.read(commissionProvider).config['max_connections'], 1);
      expect(
        _order(fake, {'get_config', 'set_config', 'get_net_status'}).take(3),
        ['get_config', 'set_config', 'get_net_status'],
      );
      // BLE scanning was already on: not touched.
      expect(fake.sent('set_ble_enabled'), isEmpty);
    });

    test('direct preferred, BLE off (identity written, not joined): '
        'scanning is turned on as step 7 does', () async {
      final fake = _Gateway()
        ..config['max_connections'] = 5
        ..config['ble_enabled'] = false;
      final (container, c, peer) = await _ready(fake);
      await c.connect(peer);
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.sent('set_config'), [
        {'max_connections': 1},
      ]);
      expect(fake.sent('set_ble_enabled'), [
        {'enabled': true},
      ]);
      expect(container.read(commissionProvider).config['ble_enabled'], true);
    });

    test('star preferred: nothing sent, the gateway keeps 5', () async {
      final fake = _Gateway()..config['max_connections'] = 5;
      final (container, c, peer) = await _ready(
        fake,
        topology: GatewayTopology.star,
      );
      await c.connect(peer);
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.sent('set_config'), isEmpty);
      expect(fake.sent('set_ble_enabled'), isEmpty);
      expect(fake.config['max_connections'], 5);
    });

    test('already one-to-one: nothing sent', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      final (container, c, peer) = await _ready(fake);
      await c.connect(peer);
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.sent('set_config'), isEmpty);
    });

    test('a gateway in service (star station at work): not touched — r33 '
        'topology ask owns that decision', () async {
      final fake = _Gateway()
        ..config['max_connections'] = 5
        ..config['fleet_joined'] = true;
      final (_, c, peer) = await _ready(fake);
      await c.connect(peer);
      expect(fake.sent('set_config'), isEmpty);
      expect(fake.config['max_connections'], 5);
      fake.devices.first['connected'] = true;
      await c.identify();
      expect(fake.identifyRequests, hasLength(1));
      expect(fake.sent('set_config'), isEmpty);
    });

    test('firmware without the direct pick (list flow): not touched', () async {
      final fake = _Gateway()..config['max_connections'] = 5;
      fake.config.remove('direct_autoconnect_supported');
      final (_, c, peer) = await _ready(fake);
      await c.connect(peer);
      expect(fake.sent('set_config'), isEmpty);
    });

    test('a gateway in test mode is left alone (step 7 refuses it)', () async {
      final fake = _Gateway()
        ..config['max_connections'] = 5
        ..config['mode'] = 'test';
      final (_, c, peer) = await _ready(fake);
      await c.connect(peer);
      expect(fake.sent('set_config'), isEmpty);
    });

    test(
      'finding and identifying a star gateway leaves max 5 and BLE off',
      () async {
        final fake = _Gateway()
          ..config['max_connections'] = 5
          ..config['ble_enabled'] = false;
        fake.devices.clear();
        final before = Map<String, dynamic>.of(fake.config);
        final (container, c, peer) = await _ready(fake);
        expect(
          await c.identifyPeer(peer),
          isFalse,
          reason: 'an unconnected card must not open a hidden connection',
        );
        expect(fake.connections, isEmpty);
        expect(fake.commands, isEmpty);
        expect(await c.holdPeer(peer), isTrue);
        expect(fake.commands.map((entry) => entry.$1), ['get_config']);
        final opened = fake.connections.length;
        final closed = fake.disconnects;
        expect(await c.identifyPeer(peer), isTrue);
        _expectNoConfigurationWrites(fake);
        expect(fake.config, before);
        expect(fake.config['max_connections'], 5);
        expect(fake.config['ble_enabled'], isFalse);
        expect(
          fake.connections.length,
          opened,
          reason: 'identify reuses the link',
        );
        expect(fake.disconnects, closed);
        expect(c.heldPeerId, peer.id);
        expect(c.identifyPeerGatewayOnly, isTrue);
        expect(
          c.identifyPeerGatewayOnlyReason?.kind,
          isNot(IdentifyGatewayOnlyKind.switchedToDirect),
        );
        final state = container.read(commissionProvider);
        expect(state.peer, isNull);
        expect(state.step, 1);
        expect(state.busy, isFalse);
      },
    );

    test(
      'identifying a different card never replaces the held gateway',
      () async {
        final fake = _Gateway();
        final (_, c, peer) = await _held(fake);
        const other = GatewayPeer('other-gateway', 'GIOS-S50-GW02', -40);
        final commands = fake.commands.length;
        final closed = fake.disconnects;
        expect(await c.identifyPeer(other), isFalse);
        expect(fake.connections, [peer.id]);
        expect(fake.commands, hasLength(commands));
        expect(fake.disconnects, closed);
        expect(c.heldPeerId, peer.id);
        _expectNoConfigurationWrites(fake);
      },
    );

    test('the list 〔辨識〕 under star preference, or on a gateway already '
        'one-to-one, sends no set_config', () async {
      for (final (topology, limit) in [
        (GatewayTopology.star, 5),
        (GatewayTopology.direct, 1),
      ]) {
        final fake = _Gateway()..config['max_connections'] = limit;
        fake.devices.first['connected'] = true;
        final (_, c, peer) = await _held(fake, topology: topology);
        expect(await c.identifyPeer(peer), isTrue);
        _expectNoConfigurationWrites(fake);
        expect(c.identifyPeerGatewayOnly, isFalse);
        expect(c.identifyPeerGatewayOnlyReason, isNull);
      }
    });

    test(
      'a missing status report does not claim identification changed topology',
      () async {
        final fake = _Gateway()
          ..config['max_connections'] = 5
          ..config['ble_enabled'] = false
          ..statusFails = true;
        fake.devices.clear();
        final (_, c, peer) = await _held(fake);
        expect(await c.identifyPeer(peer), isTrue);
        expect(c.identifyPeerGatewayOnly, isTrue);
        expect(c.identifyPeerGatewayOnlyReason, isNull);
        _expectNoConfigurationWrites(fake);
        expect(fake.config['max_connections'], 5);
        expect(fake.config['ble_enabled'], isFalse);
      },
    );
  });

  group('B2: why only the gateway blinked (get_status.direct)', () {
    test('no PTU heard: candidates empty', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      fake.devices.clear();
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      expect(fake.sent('get_status'), hasLength(1));
      expect(_order(fake, {'identify', 'get_status'}), [
        'identify',
        'get_status',
      ]);
      expect(
        c.identifyPeerGatewayOnlyReason,
        const IdentifyGatewayOnlyReason(IdentifyGatewayOnlyKind.noCandidate),
      );
    });

    test(
      'bound PTU missing: a strong other PTU does not mean still picking',
      () async {
        final fake = _Gateway()
          ..config['max_connections'] = 1
          ..direct = {
            'state': 'bound_missing',
            'select_reason': 'bound_missing',
            'bound_mac': 'AA:BB:CC:DD:40:AC',
            'min_rssi': -55,
            'candidates': [
              {
                'mac': 'AA:BB:CC:DD:96:00',
                'reason': 'not_bound',
                'rssi_med': -36,
                'rssi_peak': -34,
              },
            ],
          };
        fake.devices.clear();
        final (_, c, peer) = await _held(fake);
        expect(await c.identifyPeer(peer), isTrue);
        expect(c.identifyPeerGatewayOnly, isTrue);
        expect(
          c.identifyPeerGatewayOnlyReason?.kind,
          IdentifyGatewayOnlyKind.boundMissing,
        );
        final note = identifiedGatewayOnlyNoteFor(
          c.identifyPeerGatewayOnlyReason,
        );
        expect(note, '閘道器已閃燈；找不到已綁定的 PTU，請確認原 PTU 已開機並在附近');
        expect(note, isNot(contains('3 秒後')));
        expect(note, isNot(contains('AA:BB')));
        expect(fake.sent('get_status'), hasLength(1));
        _expectNoConfigurationWrites(fake);
      },
    );

    test('every PTU heard is below the threshold: the strongest median and '
        'the threshold (get_config auto_connect_min_rssi)', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      for (final d in fake.devices) {
        d['rssi'] = -70;
      }
      fake.devices.first['rssi'] = -62;
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      expect(
        c.identifyPeerGatewayOnlyReason,
        const IdentifyGatewayOnlyReason(
          IdentifyGatewayOnlyKind.weakSignal,
          bestRssi: -62,
          minRssi: -55,
        ),
      );
      // The gateway's own threshold, when it has one.
      fake.config['auto_connect_min_rssi'] = -60;
      await c.releaseHeld();
      expect(await c.holdPeer(peer), isTrue);
      expect(await c.identifyPeer(peer), isTrue);
      expect(
        c.identifyPeerGatewayOnlyReason,
        const IdentifyGatewayOnlyReason(
          IdentifyGatewayOnlyKind.weakSignal,
          bestRssi: -62,
          minRssi: -60,
        ),
      );
    });

    test('candidates heard, none connected yet: still picking', () async {
      final fake = _Gateway()
        ..config['max_connections'] = 1
        ..direct = {
          'active': true,
          'state': 'scanning',
          'min_rssi': -55,
          'bound_mac': '',
          'select_reason': '',
          'candidates': [
            {'mac': 'AA:BB:CC:00:00:01', 'rssi_peak': -42, 'rssi_med': -45},
            {'mac': 'AA:BB:CC:00:00:02', 'rssi_peak': -60, 'rssi_med': -63},
          ],
        };
      fake.devices.clear();
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(
        c.identifyPeerGatewayOnlyReason,
        const IdentifyGatewayOnlyReason(IdentifyGatewayOnlyKind.picking),
      );
    });

    test('a PTU connected between the identify and the get_status: picking '
        '(press again)', () async {
      final fake = _Gateway()
        ..config['max_connections'] = 1
        ..direct = {
          'active': true,
          'state': 'connected',
          'min_rssi': -55,
          'bound_mac': '',
          'select_reason': 'ok',
          'ptu_mac': 'AA:BB:CC:00:00:01',
          'ptu_rssi': -42,
          'candidates': const [],
        };
      fake.devices.clear();
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(
        c.identifyPeerGatewayOnlyReason?.kind,
        IdentifyGatewayOnlyKind.picking,
      );
    });

    test(
      'get_status refused: gateway only, no reason (the plain note)',
      () async {
        final fake = _Gateway()
          ..config['max_connections'] = 1
          ..statusFails = true;
        fake.devices.clear();
        final (container, c, peer) = await _held(fake);
        expect(await c.identifyPeer(peer), isTrue);
        expect(c.identifyPeerGatewayOnly, isTrue);
        expect(c.identifyPeerGatewayOnlyReason, isNull);
        expect(container.read(commissionProvider).error, isNull);
        expect(container.read(commissionProvider).busy, isFalse);
      },
    );

    test('firmware without the direct report: no reason', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      fake.config.remove('direct_autoconnect_supported');
      fake.devices.clear();
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      expect(c.identifyPeerGatewayOnlyReason, isNull);
    });

    test('the older firmware fallback (both fails not_connected, the gateway '
        'alone sent) classifies too', () async {
      final fake = _Gateway()
        ..config['max_connections'] = 1
        ..bothFailsNotConnected = true;
      fake.devices.clear();
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isTrue);
      expect(_order(fake, {'identify', 'get_status'}), [
        'identify',
        'identify',
        'get_status',
      ]);
      expect(
        c.identifyPeerGatewayOnlyReason?.kind,
        IdentifyGatewayOnlyKind.noCandidate,
      );
    });

    test('a PTU connected: no get_status read, no reason', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      fake.devices.first['connected'] = true;
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(c.identifyPeerGatewayOnlyReason, isNull);
      expect(fake.sent('get_status'), isEmpty);
    });

    test('each call resets the reason', () async {
      final fake = _Gateway()..config['max_connections'] = 1;
      fake.devices.clear();
      final (_, c, peer) = await _held(fake);
      expect(await c.identifyPeer(peer), isTrue);
      expect(c.identifyPeerGatewayOnlyReason, isNotNull);
      fake.config['identify_supported'] = false;
      await c.releaseHeld();
      expect(await c.holdPeer(peer), isTrue);
      expect(await c.identifyPeer(peer), isFalse);
      expect(c.identifyPeerGatewayOnly, isFalse);
      expect(c.identifyPeerGatewayOnlyReason, isNull);
    });
  });

  group('identifyGatewayOnlyReasonOf', () {
    DirectStatus? parse(Map<String, dynamic> raw) => DirectStatus.from(raw);

    test('switched wins over everything, even without a report', () {
      expect(
        identifyGatewayOnlyReasonOf(null, switched: true, minRssi: -55)?.kind,
        IdentifyGatewayOnlyKind.switchedToDirect,
      );
    });

    test('no report: null', () {
      expect(
        identifyGatewayOnlyReasonOf(null, switched: false, minRssi: -55),
        isNull,
      );
      expect(
        identifyGatewayOnlyReasonOf(
          parse({'state': 'off', 'candidates': []}),
          switched: false,
          minRssi: -55,
        ),
        isNull,
      );
    });

    test(
      'bound_missing state or reason precedes candidate/RSSI heuristics',
      () {
        for (final (state, reason) in [
          ('bound_missing', ''),
          ('scanning', 'bound_missing'),
        ]) {
          for (final int? rssi in [null, -70, -36]) {
            final direct = parse({
              'state': state,
              'select_reason': reason,
              'bound_mac': 'AA:BB:CC:00:00:01',
              'candidates': [
                if (rssi != null)
                  {
                    'mac': 'AA:BB:CC:00:00:02',
                    'rssi_med': rssi,
                    'reason': 'not_bound',
                  },
              ],
            });
            expect(
              identifyGatewayOnlyReasonOf(
                direct,
                switched: false,
                minRssi: -55,
              )?.kind,
              IdentifyGatewayOnlyKind.boundMissing,
            );
            expect(
              identifyGatewayOnlyReasonOf(
                direct,
                switched: true,
                minRssi: -55,
              )?.kind,
              IdentifyGatewayOnlyKind.switchedToDirect,
            );
          }
        }
      },
    );

    test('rssi_peak stands in for a missing rssi_med (firmware before '
        '1.7.40); one candidate at or above the threshold means picking', () {
      expect(
        identifyGatewayOnlyReasonOf(
          parse({
            'state': 'scanning',
            'candidates': [
              {'mac': 'A', 'rssi_peak': -70},
              {'mac': 'B', 'rssi_peak': -58},
            ],
          }),
          switched: false,
          minRssi: -55,
        ),
        const IdentifyGatewayOnlyReason(
          IdentifyGatewayOnlyKind.weakSignal,
          bestRssi: -58,
          minRssi: -55,
        ),
      );
      expect(
        identifyGatewayOnlyReasonOf(
          parse({
            'state': 'scanning',
            'candidates': [
              {'mac': 'A', 'rssi_peak': -70, 'rssi_med': -72},
              {'mac': 'B', 'rssi_peak': -50, 'rssi_med': -55},
            ],
          }),
          switched: false,
          minRssi: -55,
        )?.kind,
        IdentifyGatewayOnlyKind.picking,
      );
    });
  });

  group('the SnackBar sentences', () {
    test('one per reason, the plain note without one', () {
      expect(identifiedGatewayOnlyNoteFor(null), identifiedGatewayOnlyNote);
      expect(
        identifiedGatewayOnlyNoteFor(
          const IdentifyGatewayOnlyReason(
            IdentifyGatewayOnlyKind.switchedToDirect,
          ),
        ),
        identifiedGatewayOnlySwitchedNote,
      );
      expect(
        identifiedGatewayOnlySwitchedNote,
        contains('已切換為一對一，閘道器正在重新尋找 PTU，請稍後再按'),
      );
      expect(
        identifiedGatewayOnlyNoteFor(
          const IdentifyGatewayOnlyReason(IdentifyGatewayOnlyKind.noCandidate),
        ),
        identifiedGatewayOnlyNoPtuNote,
      );
      expect(
        identifiedGatewayOnlyNoPtuNote,
        contains('閘道器附近沒聽到 PTU，請確認 PTU 已上電'),
      );
      expect(
        identifiedGatewayOnlyNoteFor(
          const IdentifyGatewayOnlyReason(
            IdentifyGatewayOnlyKind.weakSignal,
            bestRssi: -62,
            minRssi: -55,
          ),
        ),
        contains('PTU 訊號太弱（最強 -62 dBm，需 ≥ -55），請靠近或檢查天線'),
      );
      expect(
        identifiedGatewayOnlyNoteFor(
          const IdentifyGatewayOnlyReason(IdentifyGatewayOnlyKind.picking),
        ),
        identifiedGatewayOnlyPickingNote,
      );
      expect(
        identifiedGatewayOnlyPickingNote,
        contains('閘道器正在選擇 PTU，請 3 秒後再按'),
      );
      expect(
        identifiedGatewayOnlySnackText(
          'GIOS-S80-GW02',
          note: identifiedGatewayOnlyNoPtuNote,
        ),
        '站 80 · 閘道器 2：$identifiedGatewayOnlyNoPtuNote',
      );
      // Without a note: as before.
      expect(
        identifiedGatewayOnlySnackText('GIOS-S80-GW02'),
        '站 80 · 閘道器 2：$identifiedGatewayOnlyNote',
      );
    });

    testWidgets('the list shows the reason\'s sentence; the row keeps the '
        'short hint', (tester) async {
      SharedPreferences.setMockInitialValues({});
      const peer = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -40);
      final link = _ScanLink();
      const reason = IdentifyGatewayOnlyReason(
        IdentifyGatewayOnlyKind.weakSignal,
        bestRssi: -70,
        minRssi: -55,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GatewayDiscovery(
                  enabled: true,
                  onConnect: (_) async {},
                  onIdentify: (_) async => true,
                  identifyGatewayOnly: () => true,
                  identifyGatewayOnlyReason: () => reason,
                  onHold: (_) async => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      link.hear(const [peer]);
      await tester.pump();
      Future<void> run() async {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      final bulb = find.byKey(ValueKey('identify-${peer.id}'));
      final snack = find.byKey(const Key('gateway-identified-snack'));
      // 1.0.0+22: the bulb is on the selected card once its link is up.
      await tester.tap(find.byKey(ValueKey(peer.id)));
      await run();
      expect(bulb, findsNothing);
      await tester.tap(find.byKey(const Key('gateway-link-identify')));
      await run();
      await tester.tap(bulb);
      await run();
      expect(
        find.descendant(
          of: snack,
          matching: find.textContaining(
            identifiedGatewayOnlyWeakNote(-70, -55),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('gateway-presence-${peer.id}')),
          matching: find.text(identifiedGatewayOnlyHint),
        ),
        findsOneWidget,
      );
      // (No reason → the plain note: identify_bulb_test.dart.)
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// A live scan the test feeds.
class _ScanLink extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final scan = StreamController<List<GatewayPeer>>();
    scans.add(scan);
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    for (final scan in scans) {
      if (!scan.isClosed) unawaited(scan.close());
    }
  }

  void hear(List<GatewayPeer> peers) => scans.last.add(peers);
}
