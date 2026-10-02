// 1.0.0+12 gateway numbering (field 09-29: the automatic number did not
// match the label on the pile and could not be changed; a gateway with an
// old test identity 80/2 left in its NVS was listed as 「站 80 · 閘道器 2」,
// offered 「目前站號是 80，這台要配置在本站嗎？」 and its number 2 although the
// back office had nothing on 80):
// 1. A gateway not in service never keeps the identity it carries — unless
//    this phone wrote it a moment ago (round 26: set_site_identity acked,
//    the reconnect failed); a gateway in service keeps its number on its
//    own station.
// 2. The gateway list and 「閘道器狀態」 name a gateway known not to be
//    configured 「未配置閘道器 …XXXX」 (no station / number); the back
//    office unknown, the list reads as before.
// 3. 1.0.0+13 (replaces 1.0.0+12's 〔修改〕 number picker: a number in use
//    could be picked and 〔取代舊機〕 pressed while the old gateway was
//    online — two gateways on one station and number): the number is
//    always automatic; 〔這台是來換掉壞掉的舊機〕 under 「將配置為 站點 X /
//    閘道器 N」 lists only the station's offline gateways (not this one),
//    confirmed, sent through force_replace — and not sent when the old one
//    is online again; r33's 「閘道器編號已被使用」 offers no 〔取代舊機〕 for
//    an online gateway; the done page says 「請在機殼上標示：站 S · 閘道器 N」.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_swap.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/fleet_status_api.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/recent_gateways.dart';
import 'package:gateway_commissioning/data/written_identities.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';
import 'package:gateway_commissioning/presentation/gateway_swap_sheet.dart';
import 'package:gateway_commissioning/presentation/gateway_status_page.dart';

import 'network_check_test.dart' show WifiGateway;
import 'support/pick_gateway.dart';

/// The demo gateway's Wi-Fi MAC (`gateway_uid`).
const _uid = 'AABBCCDDEEFF';

/// [_Site.calls]' entry for set_site_identity (a Bluetooth command, logged
/// with the back office's requests so their order shows).
const _setIdentity = 'BLE set_site_identity';

/// A gateway on Wi-Fi Xiaomi_WU (MQTT up) carrying [site] / [gateway]
/// ([joined]: in service), and the back office: [fleet] (other gateways'
/// rows) plus its own row once it is in service or was given an identity.
class _Site extends WifiGateway {
  _Site({
    int site = 80,
    int gateway = 2,
    bool joined = false,
    List<Map<String, dynamic>>? fleet,
  }) : fleet = fleet ?? [] {
    config.addAll({
      'site_id': site,
      'gateway_id': gateway,
      'fleet_joined': joined,
      'wifi_ssid': 'Xiaomi_WU',
    });
  }

  final List<Map<String, dynamic>> fleet;
  final calls = <String>[];
  final identities = <Map<String, dynamic>>[];

  /// set_site_identity was received (the back office then hears it).
  bool announced = false;

  /// The reconnect after set_site_identity fails (round 26).
  bool failReconnect = false;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    if (failReconnect && announced) {
      throw const GatewayFailure('disconnected');
    }
    return super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'set_site_identity') {
      announced = true;
      identities.add(Map.of(params));
      calls.add(_setIdentity);
    }
    return super.command(op, params);
  }

  Future<List<Map<String, dynamic>>> _rows(String method, String path) async {
    final own = (await super.request(method, path))['gateways'] as List;
    return [
      ...fleet,
      if (announced || config['fleet_joined'] == true)
        for (final row in own)
          {...Map<String, dynamic>.from(row as Map), 'last_seen_mac': _uid},
    ];
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add('$method $path');
    final identity = RegExp(
      r'^/api/gateways/(\d+)/(\d+)/check-identity$',
    ).firstMatch(path);
    if (identity != null) {
      final site = int.parse(identity[1]!), gw = int.parse(identity[2]!);
      final row = (await _rows('GET', '/api/gateways/fleet-status'))
          .where((r) => r['site_id'] == site && r['gateway_id'] == gw)
          .firstOrNull;
      return {'exists': row != null, 'last_seen_mac': row?['last_seen_mac']};
    }
    final reserve = RegExp(
      r'^/api/gateways/(\d+)/(\d+)/reserve-identity',
    ).firstMatch(path);
    if (reserve != null) {
      // force_replace: the back office records this gateway for it.
      final site = int.parse(reserve[1]!), gw = int.parse(reserve[2]!);
      fleet.removeWhere((r) => r['site_id'] == site && r['gateway_id'] == gw);
      return {'ok': true, 'replaced': true};
    }
    if (path.contains('fleet-status')) {
      final site = Uri.parse(path).queryParameters['site_id'];
      return {
        'mqtt_connected': true,
        'gateways': [
          for (final row in await _rows(method, path))
            if (site == null || '${row['site_id']}' == site) row,
        ],
      };
    }
    return super.request(method, path, body);
  }
}

Map<String, dynamic> _row(int site, int gw, String mac) => {
  'site_id': site,
  'gateway_id': gw,
  'last_seen_mac': mac,
  'online': true,
};

/// Two other gateways on station 80 (1 and 2).
List<Map<String, dynamic>> _station80() => [
  _row(80, 1, 'A0:DD:6C:A3:70:F0'),
  _row(80, 2, '11:22:33:44:55:66'),
];

/// 1.0.0+13: an offline gateway's fleet-status row, its last heartbeat
/// [ago].
Map<String, dynamic> _offline(
  int site,
  int gw,
  String mac, {
  Duration ago = const Duration(hours: 3),
}) => {
  'site_id': site,
  'gateway_id': gw,
  'last_seen_mac': mac,
  'online': false,
  'last_heartbeat': DateTime.now().subtract(ago).toIso8601String(),
};

/// Station 80: gateway 1 offline (…70F0, 3 hours ago), gateway 2 online.
List<Map<String, dynamic>> _swap80() => [
  _offline(80, 1, 'A0:DD:6C:A3:70:F0'),
  _row(80, 2, '11:22:33:44:55:66'),
];

WrittenIdentity _written(int site, int gw, {DateTime? at, String uid = _uid}) =>
    WrittenIdentity(
      uid: uid,
      peerId: 'demo-gateway',
      site: site,
      gateway: gw,
      at: at ?? DateTime.now(),
    );

ProviderContainer _container(DemoSystem fake) => ProviderContainer(
  overrides: [
    linkProvider.overrideWithValue(fake),
    apiProvider.overrideWithValue(fake),
  ],
);

/// Logged in (or [offline]), connected to the demo gateway. The phone's
/// store is not reset here.
Future<CommissioningController> _connect(
  ProviderContainer container, {
  bool offline = false,
}) async {
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.star);
  final c = container.read(commissionProvider.notifier);
  await c.prepare(
    'https://example.invalid',
    offline ? '' : 'pw',
    offline: offline,
  );
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return c;
}

// ---- widgets ----

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The app on the gateway list, logged in (or [offline]).
Future<ProviderContainer> _pump(
  WidgetTester tester,
  DemoSystem fake, {
  bool offline = false,
}) async {
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        localBackendProberProvider.overrideWithValue(_Prober()),
        fieldReporterConfigProvider.overrideWithValue(
          const FieldReporterConfig(
            allowDemoLink: true,
            helpWait: Duration(milliseconds: 300),
          ),
        ),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  await tester.runAsync(
    () => container.read(backendEnvProvider.notifier).ready,
  );
  await tester.runAsync(() async {
    final topo = container.read(topologyProvider.notifier);
    await topo.ready;
    await topo.setTopology(GatewayTopology.star);
  });
  await tester.runAsync(
    () => container
        .read(commissionProvider.notifier)
        .prepare(
          container.read(backendEnvProvider).base,
          offline ? '' : 'pw',
          offline: offline,
        ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('task-title'))).data!;

String _assignment(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('gateway-assignment'))).data!;

/// 1.0.0+13: 〔這台是來換掉壞掉的舊機〕 → 「閘道器 1」 → 〔確定換機〕.
Future<void> _chooseSwap1(WidgetTester tester) async {
  await _tap(tester, find.byKey(const Key('gateway-swap')));
  await _tap(tester, find.byKey(const ValueKey('gateway-swap-1')));
  await _tap(tester, find.byKey(const Key('swap-confirm-ok')));
}

/// Connected to the factory gateway (not in service), 80 typed.
Future<void> _typeSite80(WidgetTester tester) async {
  await pickGateway(
    (f) => _tap(tester, f),
    find.byKey(const ValueKey('demo-gateway')),
  );
  expect(_title(tester), stationInputTitle);
  await tester.enterText(find.widgetWithText(TextField, siteFieldLabel), '80');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

/// A live scan answering [peers]; fleet-status answers [fleet].
class _ListLink extends DemoSystem implements GatewayScanner {
  _ListLink(this.fleet);
  final List<Map<String, dynamic>> fleet;
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

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.contains('fleet-status')) {
      return {'gateways': fleet, 'archived_gateways': const []};
    }
    return super.request(method, path, body);
  }
}

/// 80/2 used before (its MAC verified) but not in the back office.
const _old80 = GatewayPeer('A0:DD:6C:A3:70:F2', 'GIOS-S80-GW02', -50);

/// 81/1 used before and in the back office (configured).
const _gw81 = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -41);

/// 82/1: never connected here; the back office lists 82/1.
const _gw82 = GatewayPeer('AA:BB:CC:DD:3C:02', 'GIOS-S82-GW01', -60);

/// 83/4: never connected here; nothing on 83/4 in the back office.
const _gw83 = GatewayPeer('AA:BB:CC:DD:3D:02', 'GIOS-S83-GW04', -65);

/// The factory name 1/1.
const _factory = GatewayPeer('AA:BB:CC:DD:3E:02', 'GIOS-S1-GW01', -70);

const _recents =
    '[{"id":"A0:DD:6C:A3:70:F2","name":"GIOS-S80-GW02","uid":"A0DD6CA370F0"},'
    '{"id":"AA:BB:CC:DD:3A:02","name":"GIOS-S81-GW01","uid":"AABBCCDD3A00"}]';

String _tileTitle(WidgetTester tester, GatewayPeer peer) =>
    tester.widget<Text>(find.byKey(ValueKey('gateway-title-${peer.id}'))).data!;

/// 1.0.0+14: the card's line 3 (the MAC tail; for a gateway not configured
/// too — its title is 「未配置閘道器」 alone).
String _tileDetail(WidgetTester tester, GatewayPeer peer) => tester
    .widget<Text>(find.byKey(ValueKey('gateway-detail-${peer.id}')))
    .data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the store of identities this phone wrote', () {
    test('found for the same gateway within 30 min, not after; one per '
        'gateway; forgotten; demo apart', () async {
      final now = DateTime.now();
      await WrittenIdentities.remember(true, _written(80, 2));
      expect((await WrittenIdentities.find(true, uid: _uid))?.gateway, 2);
      // Its Bluetooth id when the MAC is unknown.
      expect(
        (await WrittenIdentities.find(true, peerId: 'demo-gateway'))?.site,
        80,
      );
      expect(await WrittenIdentities.find(true, uid: '001122334455'), isNull);
      expect(await WrittenIdentities.find(false, uid: _uid), isNull);
      // A later write replaces it.
      await WrittenIdentities.remember(true, _written(81, 1));
      expect(await WrittenIdentities.load(true), hasLength(1));
      expect((await WrittenIdentities.find(true, uid: _uid))?.site, 81);
      // 30 min later it is no longer kept.
      expect(
        await WrittenIdentities.find(
          true,
          uid: _uid,
          now: now.add(const Duration(minutes: 31)),
        ),
        isNull,
      );
      await WrittenIdentities.forget(true, uid: _uid);
      expect(await WrittenIdentities.load(true), isEmpty);
      // An unreadable store reads as empty.
      SharedPreferences.setMockInitialValues({
        WrittenIdentities.key(true): 'broken',
      });
      expect(await WrittenIdentities.load(true), isEmpty);
    });
  });

  group(
    '1. a gateway not in service does not keep the identity it carries',
    () {
      test('NVS 80/2, not in service, nothing on 80 in the back office: not '
          'proposed as 本站; station 80 typed → gateway 1', () async {
        final fake = _Site();
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _connect(container);
        final s = container.read(commissionProvider);
        expect(s.config['site_id'], 80, reason: 'the gateway still carries it');
        expect(s.config['suggested_site_known'], isFalse);
        expect(s.config['suggested_site_id'], isNot(80));
        expect(await c.suggestGateway(80), (1, GatewaySuggestKind.online));
      });

      test('offline: the number comes from the Bluetooth names, not from the '
          'identity it carries', () async {
        final fake = _Site(site: 80, gateway: 5);
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _connect(container, offline: true);
        expect(
          container.read(commissionProvider).config['suggested_site_known'],
          isFalse,
        );
        expect(await c.suggestGateway(80), (1, GatewaySuggestKind.offline));
      });

      test('round 26: an identity this phone wrote a moment ago is kept '
          '(「目前站號是 80」, gateway 2)', () async {
        await WrittenIdentities.remember(true, _written(80, 2));
        final fake = _Site(fleet: _station80());
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _connect(container);
        final s = container.read(commissionProvider);
        expect(s.config['suggested_site_known'], isTrue);
        expect(s.config['suggested_site_id'], 80);
        expect(s.config['suggested_gateway_id'], 2);
        expect(await c.suggestGateway(80), (2, GatewaySuggestKind.online));
      });

      test(
        'written more than 30 min ago, or another number: not kept',
        () async {
          for (final written in [
            _written(
              80,
              2,
              at: DateTime.now().subtract(const Duration(minutes: 31)),
            ),
            _written(80, 3),
          ]) {
            SharedPreferences.setMockInitialValues({});
            await WrittenIdentities.remember(true, written);
            final fake = _Site();
            final container = _container(fake);
            addTearDown(container.dispose);
            final c = await _connect(container);
            expect(
              container.read(commissionProvider).config['suggested_site_known'],
              isFalse,
            );
            expect(await c.suggestGateway(80), (1, GatewaySuggestKind.online));
          }
        },
      );

      test('round 26 end to end: set_site_identity 80/2 acked, the reconnect '
          'fails; connected again, 80/2 is proposed', () async {
        final fake = _Site(site: 1, gateway: 1);
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _connect(container);
        fake.failReconnect = true;
        await c.configureWifi(80, 2, 'Xiaomi_WU', '');
        expect(container.read(commissionProvider).error, isNotNull);
        expect(fake.identities, [
          {'site_id': 80, 'gateway_id': 2},
        ]);
        final written = await WrittenIdentities.find(true, uid: _uid);
        expect((written?.site, written?.gateway), (80, 2));
        fake.failReconnect = false;
        await c.connect(container.read(commissionProvider).peers.single);
        final s = container.read(commissionProvider);
        expect(s.config['suggested_site_known'], isTrue);
        expect(s.config['suggested_site_id'], 80);
        expect(s.config['suggested_gateway_id'], 2);
      });

      test('in service: its record is dropped (join_fleet)', () async {
        final fake = _Site(site: 1, gateway: 1);
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _connect(container);
        await c.configureWifi(80, 2, 'Xiaomi_WU', '');
        expect(await WrittenIdentities.find(true, uid: _uid), isNotNull);
        await c.online();
        await c.discover();
        await c.configurePtus();
        expect(
          container.read(commissionProvider).config['fleet_joined'],
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);
        expect(await WrittenIdentities.find(true, uid: _uid), isNull);
      });

      test(
        'a gateway in service keeps its own number on its station',
        () async {
          final fake = _Site(
            joined: true,
            fleet: [_row(80, 1, '11:22:33:44:55:66')],
          );
          final container = _container(fake);
          addTearDown(container.dispose);
          final c = await _connect(container);
          expect(
            container.read(commissionProvider).config['choose_station'],
            isTrue,
          );
          expect(await c.suggestGateway(80), (2, GatewaySuggestKind.online));
          // Another station: the smallest free number there.
          expect(await c.suggestGateway(81), (1, GatewaySuggestKind.online));
        },
      );

      test(
        '1.0.0+13 swapCandidates: the offline gateways of the station but '
        'this one; gatewayOnline: fleet-status online; null offline',
        () async {
          final fake = _Site(
            site: 1,
            gateway: 1,
            fleet: [
              _offline(80, 1, 'A0:DD:6C:A3:70:F0'),
              _row(80, 2, '11:22:33:44:55:66'),
              _offline(80, 4, 'AA:BB:CC:DD:EE:FF'), // this gateway's own MAC
              _offline(81, 1, 'AA:BB:CC:00:00:81'),
            ],
          );
          final container = _container(fake);
          addTearDown(container.dispose);
          final c = await _connect(container);
          final found = await c.swapCandidates(80);
          expect(found?.map((g) => (g.site, g.gateway, g.tail)), [
            (80, 1, '…70F0'),
          ]);
          expect(await c.swapCandidates(82), isEmpty);
          expect(await c.gatewayOnline(80, 1), isFalse);
          expect(await c.gatewayOnline(80, 2), isTrue);
          expect(await c.gatewayOnline(80, 9), isNull);
          final offline = _container(_Site(fleet: _swap80()));
          addTearDown(offline.dispose);
          final o = await _connect(offline, offline: true);
          expect(await o.swapCandidates(80), isNull);
          expect(await o.gatewayOnline(80, 1), isNull);
        },
      );
    },
  );

  group('2. a gateway known not to be configured is not named by its old '
      'identity', () {
    test('gatewayKnownUnconfigured', () {
      final fleet = [
        {'site_id': 81, 'gateway_id': 1, 'last_seen_mac': 'AA:BB:CC:DD:3A:00'},
        {'site_id': 82, 'gateway_id': 1, 'last_seen_mac': '00:11:22:33:44:55'},
      ];
      final archived = [
        {'site_id': 84, 'gateway_id': 1, 'last_seen_mac': '00:11:22:33:44:84'},
      ];
      bool unconfigured(String name, {String? uid, bool known = true}) =>
          gatewayKnownUnconfigured(
            name: name,
            uid: uid,
            fleet: fleet,
            archived: archived,
            backendKnown: known,
          );
      // Its verified MAC is not in the back office.
      expect(unconfigured('GIOS-S80-GW02', uid: 'A0DD6CA370F0'), isTrue);
      // Its verified MAC is: configured.
      expect(unconfigured('GIOS-S81-GW01', uid: 'AABBCCDD3A00'), isFalse);
      // Without a verified MAC: by its station / number.
      expect(unconfigured('GIOS-S82-GW01'), isFalse);
      expect(unconfigured('GIOS-S83-GW04'), isTrue);
      expect(unconfigured('GIOS-S84-GW01'), isFalse, reason: 'archived');
      // The factory 1/1, even with the back office unknown.
      expect(unconfigured('GIOS-S1-GW01'), isTrue);
      expect(unconfigured('GIOS-S1-GW01', known: false), isTrue);
      // The back office unknown: as before.
      expect(unconfigured('GIOS-S83-GW04', known: false), isFalse);
      expect(
        unconfigured('GIOS-S80-GW02', uid: 'A0DD6CA370F0', known: false),
        isFalse,
      );
      // No identity in the name and no verified MAC: cannot tell.
      expect(unconfigured('GIOS-S0-GW00'), isFalse);
      expect(unconfiguredGatewayTitle('…70F0'), '未配置閘道器 …70F0');
      expect(unconfiguredGatewayTitle(null), '未配置閘道器');
      expect(gatewayTailText(bleId: 'A0:DD:6C:A3:70:F2'), '…70F0');
    });

    test('「閘道器狀態」 nearby: nearbyKnownUnconfigured', () {
      const fleet = [
        FleetGateway(site: 56, gateway: 1, online: true, ptuConnected: true),
      ];
      expect(nearbyKnownUnconfigured('GIOS-S56-GW01', fleet), isFalse);
      expect(nearbyKnownUnconfigured('GIOS-S80-GW02', fleet), isTrue);
      expect(nearbyKnownUnconfigured('GIOS-S80-GW02', null), isFalse);
      expect(nearbyKnownUnconfigured('GIOS-S1-GW01', null), isTrue);
      expect(nearbyKnownUnconfigured('GIOS-S0-GW00', fleet), isFalse);
    });

    testWidgets('360x640, logged in: 「未配置閘道器 …70F0」 for 80/2 (not in the '
        'back office), 「站 81 · 閘道器 1」 kept; its MAC tail not repeated', (
      tester,
    ) async {
      _phoneView(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final link = _ListLink([
        {'site_id': 81, 'gateway_id': 1, 'last_seen_mac': 'AA:BB:CC:DD:3A:00'},
        {'site_id': 82, 'gateway_id': 1, 'last_seen_mac': '00:11:22:33:44:55'},
      ]);
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'production',
        'demo_recent_gateways': _recents,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(link),
            apiProvider.overrideWithValue(link),
            backendKeyProvider.overrideWithValue('build-key'),
          ],
          child: const GatewayApp(),
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
        await container
            .read(commissionProvider.notifier)
            .prepare(container.read(backendEnvProvider).base, 'pw');
      });
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      link.scans.last.add(const [_gw81, _old80, _gw82, _gw83, _factory]);
      await tester.pump();
      // 1.0.0+14: 「未配置閘道器」 as the title (one line), its MAC tail on
      // line 3 (1.0.0+12 had 「未配置閘道器 …70F0」 on two lines).
      expect(_tileTitle(tester, _old80), unconfiguredGatewayText);
      expect(_tileDetail(tester, _old80), '…70F0');
      expect(_tileTitle(tester, _gw81), '站 81 · 閘道器 1');
      expect(_tileTitle(tester, _gw82), '站 82 · 閘道器 1');
      expect(_tileTitle(tester, _gw83), unconfiguredGatewayText);
      expect(_tileDetail(tester, _gw83), '…3D00');
      expect(_tileTitle(tester, _factory), unconfiguredGatewayText);
      expect(_tileDetail(tester, _factory), '…3E00');
      expect(find.text('站 80 · 閘道器 2'), findsNothing);
      expect(find.text('站 83 · 閘道器 4'), findsNothing);
      // 「已配置」 as before for 81/1; every card's tail on line 3, never in
      // the title.
      expect(
        find.byKey(ValueKey('gateway-configured-${_gw81.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('gateway-unconfigured-${_old80.id}')),
        findsOneWidget,
      );
      expect(find.textContaining('未配置閘道器 …'), findsNothing);
      expect(_tileDetail(tester, _gw81), '…3A00');
      // Never cut: one line, whole.
      final title = tester.widget<Text>(
        find.byKey(ValueKey('gateway-title-${_old80.id}')),
      );
      expect(title.maxLines, 1);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(ValueKey('gateway-title-${_old80.id}')),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the back office unknown (not logged in): as before, the '
        'factory name 1/1 excepted', (tester) async {
      _phoneView(tester);
      final link = _ListLink(const []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GatewayDiscovery(enabled: true, onConnect: (_) async {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      link.scans.last.add(const [_old80, _gw83, _factory]);
      await tester.pump();
      expect(_tileTitle(tester, _old80), '站 80 · 閘道器 2');
      expect(_tileTitle(tester, _gw83), '站 83 · 閘道器 4');
      expect(_tileTitle(tester, _factory), unconfiguredGatewayText);
      expect(_tileDetail(tester, _factory), '…3E00');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('3. 換機: only an offline gateway of the station is replaced '
      '(1.0.0+13, instead of 〔修改〕)', () {
    test('offlineSwapCandidates / fleetRowOnline and the texts', () {
      final fleet = <String, dynamic>{
        'gateways': [
          {
            'site_id': 80,
            'gateway_id': 3,
            'last_seen_mac': '00:11:22:33:44:03',
            'online': false,
            'last_seen': '2026-09-29T10:00:00+08:00',
          },
          {
            'site_id': 80,
            'gateway_id': 1,
            'mac': '00:11:22:33:44:01',
            'online': false,
            'last_heartbeat': '2026-09-29T09:00:00+08:00',
            'last_seen': '2026-09-29T11:00:00+08:00',
          },
          {
            'site_id': 80,
            'gateway_id': 2,
            'last_seen_mac': '00:11:22:33:44:02',
            'online': true,
          },
          // This gateway itself (its MAC in another spelling).
          {
            'site_id': 80,
            'gateway_id': 4,
            'last_seen_mac': 'aa:bb:cc:dd:ee:ff',
            'online': false,
          },
          // Online unknown: not listed.
          {
            'site_id': 80,
            'gateway_id': 5,
            'last_seen_mac': '00:11:22:33:44:05',
          },
          // No MAC on record.
          {'site_id': 80, 'gateway_id': 6, 'online': false},
          {
            'site_id': 81,
            'gateway_id': 1,
            'last_seen_mac': '00:11:22:33:44:81',
            'online': false,
          },
        ],
      };
      final found = offlineSwapCandidates(fleet, 80, _uid);
      expect(found.map((g) => g.gateway), [1, 3, 6]);
      expect(found.first.mac, '00:11:22:33:44:01');
      expect(found.first.tail, '…4401');
      // last_heartbeat first, else last_seen.
      expect(
        found.first.lastSeen,
        DateTime.parse('2026-09-29T09:00:00+08:00').toLocal(),
      );
      expect(
        found[1].lastSeen,
        DateTime.parse('2026-09-29T10:00:00+08:00').toLocal(),
      );
      expect(found[2].tail, isNull);
      expect(found[2].lastSeen, isNull);
      expect(offlineSwapCandidates(fleet, 82, _uid), isEmpty);
      expect(fleetRowOnline(fleet, 80, 2), isTrue);
      expect(fleetRowOnline(fleet, 80, 1), isFalse);
      expect(fleetRowOnline(fleet, 80, 5), isNull);
      expect(fleetRowOnline(fleet, 80, 9), isNull);
      // Held by this gateway: its own heartbeats say nothing of the other.
      expect(fleetRowOnline(fleet, 80, 4), isFalse);
      expect(fleetRowOnline(fleet, 80, 4, ownUid: _uid), isNull);
      expect(fleetRowOnline(fleet, 80, 2, ownUid: _uid), isTrue);

      final now = DateTime(2026, 9, 29, 12);
      expect(
        swapRowDetail(
          SwapCandidate(
            site: 80,
            gateway: 1,
            mac: 'A0:DD:6C:A3:70:F0',
            lastSeen: now.subtract(const Duration(hours: 3)),
          ),
          now,
        ),
        '最後上線 3 小時前 · MAC …70F0',
      );
      expect(
        swapRowDetail(const SwapCandidate(site: 80, gateway: 6), now),
        '沒有上線紀錄',
      );
      expect(
        swapConfirmText(80, 1, '…70F0'),
        '這台將接手 站 80 · 閘道器 1。舊機（…70F0）必須已拆除或斷電。',
      );
      expect(swapOnlineText(1), '閘道器 1 目前在線上，請先把舊機斷電。');
      expect(numberTakenOnlineText(1), '閘道器 1 目前在線上，不能取代；如果這台是來換掉它，請先把舊機斷電。');
      expect(doneLabelText(80, 1), '請在機殼上標示：站 80 · 閘道器 1');
    });

    testWidgets('360x640: 〔修改〕 is gone — 「將配置為 站點 80 / 閘道器 3」 is '
        'read-only; 〔這台是來換掉壞掉的舊機〕 under it (≥ 48 dp)', (tester) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1, fleet: _swap80());
      await _pump(tester, fake);
      await pickGateway(
        (f) => _tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      expect(_title(tester), stationInputTitle);
      // No station typed yet: nothing numbered, no 換機.
      expect(find.byKey(const Key('gateway-assignment')), findsNothing);
      expect(find.byKey(const Key('gateway-swap')), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '80',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 3');
      expect(find.byKey(const Key('gateway-number-change')), findsNothing);
      expect(find.byKey(const Key('gateway-number-picker')), findsNothing);
      expect(find.text('修改'), findsNothing);
      final swap = find.byKey(const Key('gateway-swap'));
      expect(
        find.descendant(of: swap, matching: find.text(swapLabel)),
        findsOneWidget,
      );
      expect(tester.getSize(swap).height, greaterThanOrEqualTo(48));
      expect(
        tester.getTopLeft(swap).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('gateway-assignment'))).dy,
        ),
      );
      expect(find.text(swapNeedsNetworkText), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offline (the back office cannot be asked): no 〔這台是來換掉'
        '壞掉的舊機〕 but 「換機需要連上網路」', (tester) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1, fleet: _swap80());
      await _pump(tester, fake, offline: true);
      await _typeSite80(tester);
      expect(_assignment(tester), startsWith('將配置為 站點 80 / 閘道器 1（'));
      expect(find.byKey(const Key('gateway-swap')), findsNothing);
      expect(find.byKey(const Key('gateway-swap-offline')), findsOneWidget);
      expect(find.text(swapNeedsNetworkText), findsOneWidget);
      expect(find.byKey(const Key('gateway-number-change')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sheet lists only station 80\'s offline gateways other '
        'than this one: 「閘道器 1」, 「最後上線 3 小時前 · MAC …70F0」', (tester) async {
      _phoneView(tester);
      final fake = _Site(
        site: 1,
        gateway: 1,
        fleet: [
          ..._swap80(),
          _offline(80, 4, 'AA:BB:CC:DD:EE:FF'), // this gateway's own MAC
          _offline(81, 1, 'AA:BB:CC:00:00:81'),
        ],
      );
      await _pump(tester, fake);
      await _typeSite80(tester);
      await _tap(tester, find.byKey(const Key('gateway-swap')));
      expect(find.byKey(const Key('gateway-swap-sheet')), findsOneWidget);
      expect(find.text(swapSheetTitle(80)), findsOneWidget);
      expect(find.text(swapSheetHint), findsOneWidget);
      final row = find.byKey(const ValueKey('gateway-swap-1'));
      expect(row, findsOneWidget);
      for (final gw in [2, 3, 4]) {
        expect(find.byKey(ValueKey('gateway-swap-$gw')), findsNothing);
      }
      expect(
        find.descendant(of: row, matching: find.text('閘道器 1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('gateway-swap-detail-1')))
            .data,
        '最後上線 3 小時前 · MAC …70F0',
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      // 〔取消〕: nothing changes.
      await _tap(tester, find.byKey(const Key('gateway-swap-close')));
      expect(find.byKey(const Key('gateway-swap-sheet')), findsNothing);
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no offline gateway on the station: 「本站沒有離線的閘道器可以'
        '取代」 and 〔關閉〕', (tester) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1, fleet: _station80());
      await _pump(tester, fake);
      await _typeSite80(tester);
      await _tap(tester, find.byKey(const Key('gateway-swap')));
      expect(find.byKey(const Key('gateway-swap-none')), findsOneWidget);
      expect(find.text(swapNoneText), findsOneWidget);
      expect(find.byKey(const ValueKey('gateway-swap-1')), findsNothing);
      final close = find.byKey(const Key('gateway-swap-close'));
      expect(
        find.descendant(of: close, matching: find.text(swapCloseLabel)),
        findsOneWidget,
      );
      await _tap(tester, close);
      expect(find.byKey(const Key('gateway-swap-sheet')), findsNothing);
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirmed: 「將配置為 站點 80 / 閘道器 1（取代舊機 …70F0）」, '
        'asked once more, then the existing replacement — force_replace '
        'before set_site_identity; no 「閘道器編號已被使用」', (tester) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1, fleet: _swap80());
      await _pump(tester, fake);
      await _typeSite80(tester);
      await _tap(tester, find.byKey(const Key('gateway-swap')));
      await _tap(tester, find.byKey(const ValueKey('gateway-swap-1')));
      expect(find.byKey(const Key('swap-confirm')), findsOneWidget);
      expect(find.text(swapConfirmTitle), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('swap-confirm-text'))).data,
        '這台將接手 站 80 · 閘道器 1。舊機（…70F0）必須已拆除或斷電。',
      );
      // 〔取消〕 first: nothing changes.
      await _tap(tester, find.byKey(const Key('swap-confirm-cancel')));
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 3');
      expect(find.byKey(const Key('gateway-swap-cancel')), findsNothing);

      await _chooseSwap1(tester);
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 1（取代舊機 …70F0）');
      expect(find.byKey(const Key('gateway-swap')), findsNothing);
      expect(find.byKey(const Key('gateway-swap-cancel')), findsOneWidget);
      expect(fake.identities, isEmpty, reason: 'nothing sent yet');

      final before = fake.calls.length;
      await _tap(tester, find.byKey(const Key('station-use')));
      expect(find.byKey(const Key('number-taken')), findsNothing);
      const reserve =
          'POST /api/gateways/80/1/reserve-identity'
          '?mac=$_uid&force_replace=true';
      final sent = fake.calls.sublist(before);
      expect(sent, contains(reserve));
      expect(
        sent.sublist(0, sent.indexOf(reserve)),
        contains('GET /api/gateways/fleet-status?site_id=80'),
        reason: 'asked once more whether it is offline',
      );
      expect(
        sent.indexOf(reserve),
        lessThan(sent.indexOf(_setIdentity)),
        reason: 'the back office first, then the gateway',
      );
      expect(fake.identities, [
        {'site_id': 80, 'gateway_id': 1},
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('〔取消換機〕: back to the automatic number, nothing replaced', (
      tester,
    ) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1, fleet: _swap80());
      await _pump(tester, fake);
      await _typeSite80(tester);
      await _chooseSwap1(tester);
      await _tap(tester, find.byKey(const Key('gateway-swap-cancel')));
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 3');
      expect(find.byKey(const Key('gateway-swap')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the old gateway online again before it is sent: nothing '
        'sent, 「閘道器 1 目前在線上，請先把舊機斷電。」, the automatic number '
        'again', (tester) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1, fleet: _swap80());
      await _pump(tester, fake);
      await _typeSite80(tester);
      await _chooseSwap1(tester);
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 1（取代舊機 …70F0）');
      fake.fleet.first['online'] = true; // powered on again
      await _tap(tester, find.byKey(const Key('station-use')));
      expect(find.byKey(const Key('swap-online')), findsOneWidget);
      expect(find.text(swapOnlineText(1)), findsOneWidget);
      await _tap(tester, find.byKey(const Key('swap-online-ok')));
      expect(fake.identities, isEmpty);
      expect(fake.calls.where((c) => c.contains('reserve-identity')), isEmpty);
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 3');
      expect(find.byKey(const Key('gateway-swap')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('its online state unknown right before it is sent (the '
        'row gone): nothing sent, 「換機需要連上網路」, the choice kept', (tester) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1, fleet: _swap80());
      await _pump(tester, fake);
      await _typeSite80(tester);
      await _chooseSwap1(tester);
      fake.fleet.removeAt(0);
      await tester.tap(find.byKey(const Key('station-use')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(swapNeedsNetworkText), findsOneWidget);
      await tester.pumpAndSettle();
      expect(fake.identities, isEmpty);
      expect(fake.calls.where((c) => c.contains('reserve-identity')), isEmpty);
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 1（取代舊機 …70F0）');
      expect(tester.takeException(), isNull);
    });

    for (final online in [true, false, null]) {
      final label = online == null
          ? 'unknown'
          : online
          ? 'online'
          : 'offline';
      testWidgets('r33 「閘道器編號已被使用」, the holder of 1 $label: '
          '〔取代舊機〕 ${online == true ? 'not offered' : 'offered'}', (
        tester,
      ) async {
        _phoneView(tester);
        final fake = _Site(
          site: 1,
          gateway: 1,
          fleet: [
            {
              'site_id': 80,
              'gateway_id': 1,
              'last_seen_mac': 'A0:DD:6C:A3:70:F0',
              'online': ?online,
            },
          ],
        );
        await _pump(tester, fake);
        await _typeSite80(tester);
        expect(_assignment(tester), '將配置為 站點 80 / 閘道器 2');
        await _tap(tester, find.byKey(const Key('station-use')));
        final taken = find.byKey(const Key('number-taken'));
        expect(taken, findsOneWidget);
        expect(find.byKey(const Key('number-taken-next')), findsOneWidget);
        if (online == true) {
          expect(find.byKey(const Key('number-taken-replace')), findsNothing);
          expect(
            find.descendant(
              of: taken,
              matching: find.textContaining(numberTakenOnlineText(1)),
            ),
            findsOneWidget,
          );
          await _tap(tester, find.byKey(const Key('number-taken-next')));
          expect(fake.identities, [
            {'site_id': 80, 'gateway_id': 2},
          ]);
          expect(fake.calls.where((c) => c.contains('force_replace')), isEmpty);
        } else {
          expect(find.byKey(const Key('number-taken-replace')), findsOneWidget);
          expect(
            find.descendant(
              of: taken,
              matching: find.textContaining(numberTakenReplaceHint(1)),
            ),
            findsOneWidget,
          );
          await _tap(tester, find.byKey(const Key('number-taken-replace')));
          expect(
            fake.calls,
            contains(
              'POST /api/gateways/80/1/reserve-identity'
              '?mac=$_uid&force_replace=true',
            ),
          );
          expect(fake.identities, [
            {'site_id': 80, 'gateway_id': 1},
          ]);
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final online in [true, false]) {
      testWidgets('the number taken between the station page and 〔儲存〕 '
          '(「編號已被使用」), its holder ${online ? 'online' : 'offline'}: '
          '〔取代舊機（沿用此編號）〕 ${online ? 'not offered' : 'offered'}', (
        tester,
      ) async {
        _phoneView(tester);
        final fake = _Site(site: 1, gateway: 1);
        await _pump(tester, fake);
        await _typeSite80(tester);
        expect(_assignment(tester), '將配置為 站點 80 / 閘道器 1');
        // 「改用其他 Wi-Fi」: the Wi-Fi page first.
        await _tap(tester, find.byKey(const Key('wifi-change')));
        await _tap(tester, find.byKey(const Key('new-site-ok')));
        expect(find.byKey(const Key('wifi-save')), findsOneWidget);
        fake.fleet.add({..._row(80, 1, 'A0:DD:6C:A3:70:F0'), 'online': online});
        await tester.enterText(
          find.widgetWithText(TextField, 'Wi-Fi 密碼'),
          'pw123456',
        );
        await _tap(tester, find.byKey(const Key('wifi-save')));
        final dialog = find.byKey(const Key('save-number-taken'));
        expect(dialog, findsOneWidget);
        expect(
          find.byKey(const Key('save-number-taken-replace')),
          online ? findsNothing : findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining(numberTakenOnlineText(1)),
          ),
          online ? findsOneWidget : findsNothing,
        );
        await _tap(
          tester,
          find.descendant(of: dialog, matching: find.text('取消')),
        );
        expect(fake.identities, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('another station typed clears the old gateway chosen — also '
        'when 〔使用站點〕 comes before the lookup', (tester) async {
      _phoneView(tester);
      // 82 is known to the back office (no 「確定是新站？」 in between).
      final fake = _Site(
        site: 1,
        gateway: 1,
        fleet: [..._swap80(), _row(82, 5, '11:22:33:44:55:82')],
      );
      await _pump(tester, fake);
      await _typeSite80(tester);
      await _chooseSwap1(tester);
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 1（取代舊機 …70F0）');
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '81',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_assignment(tester), '將配置為 站點 81 / 閘道器 1');
      expect(find.byKey(const Key('gateway-swap')), findsOneWidget);
      // Back on 80: its automatic number, not the old gateway chosen before.
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '80',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_assignment(tester), '將配置為 站點 80 / 閘道器 3');

      await _chooseSwap1(tester);
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '82',
      );
      await tester.pump();
      // At once (the 500 ms lookup has not run).
      await tester.tap(find.byKey(const Key('station-use')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-site-confirm')), findsNothing);
      expect(fake.identities, [
        {'site_id': 82, 'gateway_id': 1},
      ]);
      expect(fake.calls.where((c) => c.contains('force_replace')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('done page: 「請在機殼上標示：站 80 · 閘道器 2」 in compact bold type '
        'on the first screen, nothing to press', (tester) async {
      _phoneView(tester);
      final fake = _Site(site: 1, gateway: 1);
      final container = await _pump(tester, fake);
      await tester.runAsync(() async {
        final c = container.read(commissionProvider.notifier);
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.configureWifi(80, 2, 'Xiaomi_WU', '');
        await c.online();
        await c.discover();
        await c.configurePtus();
      });
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 7);
      final card = find.byKey(const Key('done-label'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text(doneLabelHead)),
        findsOneWidget,
      );
      final site = find.descendant(
        of: card,
        matching: find.byKey(const Key('done-site-id')),
      );
      final id = find.descendant(
        of: card,
        matching: find.byKey(const Key('done-gateway-id')),
      );
      expect(tester.widget<Text>(site).data, '站點 80');
      expect(tester.widget<Text>(id).data, '閘道器 2');
      expect(id, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text(doneLabelHint)),
        findsNothing,
      );
      expect(doneLabelHead, '請在機殼上標示：');
      expect(doneLabelHint, '後台人員靠這個標示找到這台');
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('請在機殼上標示：站 80 · 閘道器 2'), findsOneWidget);
      semantics.dispose();
      for (final identifier in [site, id]) {
        final style = tester.widget<Text>(identifier).style!;
        expect(style.fontSize, greaterThanOrEqualTo(16));
        expect(
          style.fontWeight!.value,
          greaterThanOrEqualTo(FontWeight.w600.value),
        );
      }
      expect(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (w) => w is ButtonStyleButton || w is InkWell,
          ),
        ),
        findsNothing,
      );
      expect(tester.getRect(card).bottom, lessThan(640));
      expect(tester.takeException(), isNull);
    });
  });
}
