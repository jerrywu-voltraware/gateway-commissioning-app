// 1.0.0+5 「閘道器狀態」: after the done page is gone the installer can
// still open 〔查看最近資料〕 — a page with the gateways this phone
// finished (kept in SharedPreferences, at most 10) and the back office's
// fleet-status list; every row opens RecentDataPage.
// 1. The store: newest first, one entry per site / gateway, cut to 10,
//    bad rows ignored.
// 2. finishDone writes an entry (demo and real runs apart).
// 3. The fleet model reads fleet-status's fields; the line's words.
// 4. The page: list / empty / error (+〔重試〕) / loading; a tap opens the
//    recent-data page of that gateway.
// 5. Entries: the start page's 〔閘道器狀態〕 and the topology menu item.
// 6. 1.0.0+7: the page logs in by itself (no session → login → 200; a 401
//    → one re-login → 200; a refused login → 「連不上後台（…）」 + 〔重試〕;
//    a session already held → no login); 「附近閘道器（藍牙掃描）」 in its
//    three states (rows / none / no permission) and a row's tap; the
//    scan stops when the page is left; the recent list's empty words.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/app_session.dart';
import 'package:gateway_commissioning/application/nearby_gateways.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/fleet_status_api.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/nearby_gateway_scan.dart';
import 'package:gateway_commissioning/data/recent_commissions.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_status_page.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';

/// The backend as the page sees it: [mode] `data` answers [fleet],
/// `empty` no gateways, `network` fails; the recent-data endpoint answers
/// one row. Records the paths asked.
class _Api implements GatewayApi {
  _Api(this.mode);
  String mode;
  List<Map<String, dynamic>> fleet = const [];
  final paths = <String>[];
  Completer<void>? gate;

  /// 1.0.0+7: every login (its base URL and credential); [refuseLogin]
  /// answers 401; [authOnce] fails the next request with 401 (an expired
  /// token) once.
  final logins = <(String, String)>[];
  bool refuseLogin = false, authOnce = false;

  @override
  Future<void> login(String base, String password) async {
    logins.add((base, password));
    if (refuseLogin) throw const GatewayFailure('authentication');
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add('$method $path');
    if (gate != null) await gate!.future;
    if (authOnce) {
      authOnce = false;
      throw const GatewayFailure('authentication');
    }
    if (path.startsWith('/api/app/recent/')) {
      return {
        'site_id': 56,
        'gateway_id': 1,
        'count': 1,
        'items': [
          {
            'ts': DateTime.now().toIso8601String(),
            'ptu_mac': '90:5F:E8:9A:96:00',
            'ptu_state': 'POWER_TRANSFER',
            'input_mv': 5000,
            'input_ma': 120,
            'temp_c': 31,
          },
        ],
      };
    }
    switch (mode) {
      case 'empty':
        return {'gateways': [], 'total': 0, 'online_count': 0};
      case 'network':
        throw GatewayFailure.network(
          endpoint: '$method $path',
          detail: 'Connection refused',
          backend: '後端 https://example.invalid',
        );
    }
    return {'gateways': fleet, 'total': fleet.length};
  }
}

/// An API that reports its session ([SessionInfo]): logged in to [origin].
class _SessionApi extends _Api implements SessionInfo {
  _SessionApi(super.mode, {this.origin});

  @override
  final String? origin;

  @override
  bool get hasSession => origin != null;
}

/// The phone's Bluetooth as the page sees it: [peers], or [failure];
/// counts the scans and whether the page's stop future fired.
class _Scanner implements NearbyGatewayScanner {
  _Scanner([this.peers = const []]);
  List<GatewayPeer> peers;
  Object? failure;
  int scans = 0;
  bool stopped = false;
  Completer<void>? gate;

  @override
  Future<List<GatewayPeer>> scanNearby({
    Duration window = nearbyScanWindow,
    Future<void>? stop,
  }) async {
    scans++;
    unawaited(stop?.then((_) => stopped = true));
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return sortNearby(peers);
  }
}

Map<String, dynamic> _gw(
  int site,
  int gateway, {
  bool online = true,
  int ble = 1,
  Map<String, dynamic>? direct,
  String? dataAt,
  String? heartbeatAt,
}) => {
  'site_id': site,
  'gateway_id': gateway,
  'online': online,
  'ble_connected': ble,
  'max_connections': direct != null ? 1 : 5,
  'direct': ?direct,
  'device_last_seen': dataAt,
  'last_heartbeat': heartbeatAt,
  'last_seen': dataAt ?? heartbeatAt,
};

Future<void> _pumpPage(
  WidgetTester tester,
  _Api api,
  DateTime now, {
  Map<String, Object> prefs = const {},
  _Scanner? scanner,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(DemoSystem()),
        apiProvider.overrideWithValue(api),
        backendKeyProvider.overrideWithValue('build-key'),
        nearbyScannerProvider.overrideWithValue(scanner ?? _Scanner()),
      ],
      child: MaterialApp(home: GatewayStatusPage(now: () => now)),
    ),
  );
  await tester.pumpAndSettle();
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// The APP at the start page (demo link, no key needed).
Future<ProviderContainer> _pumpApp(WidgetTester tester, DemoSystem fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        envSwitchPolicyProvider.overrideWithValue(
          const EnvSwitchPolicy(
            autoSyncDefault: false,
            confirmGatewaySwitch: true,
            localBuild: false,
          ),
        ),
        localBackendProberProvider.overrideWithValue(_Prober()),
        phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
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
  await tester.pumpAndSettle();
  return container;
}

/// Star: station 80 / gateway 1 commissioned and verified — the done page.
Future<ProviderContainer> _pumpStarDone(
  WidgetTester tester,
  DemoSystem fake,
) async {
  final container = await _pumpApp(tester, fake);
  await tester.runAsync(() async {
    final c = container.read(commissionProvider.notifier);
    final base = container.read(backendEnvProvider).base;
    await c.prepare(base, 'pw');
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await c.configureWifi(80, 1, 'Office-2G', 'pw123456');
    await c.online();
    await c.discover();
    await c.configurePtus();
    await c.verify('https://example.invalid', '');
  });
  await tester.pumpAndSettle();
  final s = container.read(commissionProvider);
  expect(s.step, 7, reason: 'done page');
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('store', () {
    test(
      'newest first, one per gateway, cut to 10, bad rows ignored',
      () async {
        SharedPreferences.setMockInitialValues({});
        expect(await RecentCommissions.load(false), isEmpty);
        final t0 = DateTime(2026, 9, 28, 14, 0);
        for (var i = 1; i <= 12; i++) {
          await RecentCommissions.remember(
            false,
            RecentCommission(
              site: 56,
              gateway: i,
              gatewayName: 'GW-$i',
              doneAt: t0.add(Duration(minutes: i)),
            ),
          );
        }
        var rows = await RecentCommissions.load(false);
        expect(rows, hasLength(10));
        expect(rows.first.gateway, 12, reason: 'newest first');
        expect(rows.last.gateway, 3, reason: 'the two oldest dropped');
        expect(rows.first.gatewayName, 'GW-12');
        expect(rows.first.doneAt, t0.add(const Duration(minutes: 12)));
        // The same gateway again: moved to the top, not doubled.
        await RecentCommissions.remember(
          false,
          RecentCommission(
            site: 56,
            gateway: 5,
            gatewayName: 'GW-5b',
            doneAt: t0.add(const Duration(hours: 1)),
          ),
        );
        rows = await RecentCommissions.load(false);
        expect(rows, hasLength(10));
        expect(rows.first.gateway, 5);
        expect(rows.first.gatewayName, 'GW-5b');
        expect(rows.where((r) => r.gateway == 5), hasLength(1));
        // Demo runs are kept apart.
        expect(await RecentCommissions.load(true), isEmpty);
        // Bad rows and a bad store read as nothing / are skipped.
        SharedPreferences.setMockInitialValues({
          'recent_commissions':
              '[{"site":1,"gateway":2,"done_at":"2026-09-28T10:00:00"},'
              '{"site":"x"},{"gateway":3},42,'
              '{"site":4,"gateway":5,"done_at":"bad"}]',
        });
        rows = await RecentCommissions.load(false);
        expect(rows, hasLength(1));
        expect(rows.single.site, 1);
        expect(rows.single.gatewayName, '');
        SharedPreferences.setMockInitialValues({'recent_commissions': '{oops'});
        expect(await RecentCommissions.load(false), isEmpty);
        expect(RecentCommissions.key(false), 'recent_commissions');
        expect(RecentCommissions.key(true), 'demo_recent_commissions');
      },
    );
  });

  group('done page', () {
    testWidgets('〔完成〕 remembers the gateway on the phone', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = DemoSystem();
      final container = await _pumpStarDone(tester, fake);
      // 1.0.0+10 (review P2-10): already kept when the verification
      // passed; 〔完成〕 keeps it once (same site / gateway).
      final verified = await RecentCommissions.load(true);
      expect(verified, hasLength(1), reason: 'kept at the verification');
      expect(verified.single.site, 80);
      expect(verified.single.gateway, 1);
      await tester.tap(find.byKey(const Key('done-finish')));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 0);
      final rows = await RecentCommissions.load(true);
      expect(rows, hasLength(1), reason: 'the demo link → the demo key');
      expect(rows.single.site, 80);
      expect(rows.single.gateway, 1);
      expect(rows.single.gatewayName, isNotEmpty, reason: 'the BLE name');
      expect(
        DateTime.now().difference(rows.single.doneAt).inMinutes,
        lessThan(5),
      );
      expect(await RecentCommissions.load(false), isEmpty);
      // The start page's 〔閘道器狀態〕 lists it.
      await tester.tap(find.byKey(const Key('home-gateway-status')));
      await tester.pumpAndSettle();
      expect(find.byType(GatewayStatusPage), findsOneWidget);
      expect(find.byKey(const Key('gs-recent-80-1')), findsOneWidget);
      expect(find.text('站 80 閘道器 1'), findsWidgets);
    });
  });

  group('fleet model', () {
    test('reads fleet-status fields; the line', () {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      String iso(Duration ago) => now.subtract(ago).toIso8601String();
      final rows = [
        _gw(
          80,
          2,
          online: false,
          ble: 0,
          heartbeatAt: iso(const Duration(minutes: 20)),
        ),
        _gw(
          56,
          1,
          ble: 0,
          direct: {'label': '已綁定', 'connected': true},
          dataAt: iso(const Duration(seconds: 7)),
          heartbeatAt: iso(const Duration(seconds: 3)),
        ),
        _gw(56, 3, ble: 2, dataAt: iso(const Duration(seconds: 61))),
        {'gateway_id': 9},
        'junk',
      ];
      final parsed = rows
          .whereType<Map>()
          .map(FleetGateway.fromJson)
          .whereType<FleetGateway>()
          .toList();
      expect(parsed, hasLength(3));
      final direct = parsed.firstWhere((g) => g.gateway == 1);
      expect(direct.site, 56);
      expect(direct.online, isTrue);
      expect(direct.ptuConnected, isTrue, reason: 'direct.connected');
      expect(direct.directLabel, '已綁定');
      expect(direct.lastData, isNotNull);
      expect(gatewayStatusLine(direct, now), '在線・PTU 已連線・7 秒前');
      final offline = parsed.firstWhere((g) => g.gateway == 2);
      expect(offline.ptuConnected, isFalse);
      expect(offline.lastData, isNull);
      expect(
        gatewayStatusLine(offline, now),
        '離線・PTU 未連線・心跳 20 分鐘前',
        reason: 'no PTU row yet → the heartbeat',
      );
      final star = parsed.firstWhere((g) => g.gateway == 3);
      expect(star.ptuConnected, isTrue, reason: 'ble_connected 2');
      expect(star.directLabel, '');
      expect(gatewayStatusLine(star, now), '在線・PTU 已連線・1 分鐘前');
      expect(
        gatewayStatusLine(
          const FleetGateway(
            site: 1,
            gateway: 1,
            online: false,
            ptuConnected: false,
          ),
          now,
        ),
        '離線・PTU 未連線・尚無資料',
      );
      expect(
        gatewayStatusDoneText(DateTime(2026, 9, 8, 9, 5)),
        '09-08 09:05 完成',
      );
    });

    test('fetch asks the fixed path and sorts by site then gateway', () async {
      final api = _Api('data')..fleet = [_gw(80, 2), _gw(56, 3), _gw(56, 1)];
      final rows = await fetchFleetStatus(api);
      expect(api.paths.single, 'GET /api/gateways/fleet-status');
      expect(rows.map((g) => '${g.site}/${g.gateway}'), [
        '56/1',
        '56/3',
        '80/2',
      ]);
      expect(await fetchFleetStatus(_Api('empty')), isEmpty);
      expect(fetchFleetStatus(_Api('network')), throwsA(isA<GatewayFailure>()));
    });
  });

  group('page', () {
    testWidgets(
      'list: recent commissions and the fleet; a tap opens the data',
      (tester) async {
        final now = DateTime(2026, 9, 28, 13, 0, 10);
        final api = _Api('data')
          ..fleet = [
            _gw(
              56,
              1,
              direct: {'label': '已綁定', 'connected': true},
              dataAt: now
                  .subtract(const Duration(seconds: 7))
                  .toIso8601String(),
            ),
            _gw(
              80,
              2,
              online: false,
              ble: 0,
              heartbeatAt: now
                  .subtract(const Duration(minutes: 3))
                  .toIso8601String(),
            ),
          ];
        await _pumpPage(
          tester,
          api,
          now,
          prefs: {
            'demo_recent_commissions':
                '[{"site":56,"gateway":1,"gateway_name":"GW-56A",'
                '"done_at":"2026-09-28T12:30:00"}]',
          },
        );
        expect(find.text(gatewayStatusLabel), findsOneWidget);
        expect(find.text(gatewayStatusRecentTitle), findsOneWidget);
        expect(find.text(gatewayStatusFleetTitle), findsOneWidget);
        // Top: the phone's own list.
        expect(find.byKey(const Key('gs-recent-56-1')), findsOneWidget);
        expect(find.text('09-28 12:30 完成'), findsOneWidget);
        expect(find.byKey(const Key('gs-recent-empty')), findsNothing);
        // Bottom: the fleet, one line each.
        expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
        expect(find.byKey(const Key('gs-fleet-80-2')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('gs-fleet-56-1-line'))).data,
          '在線・PTU 已連線・7 秒前',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('gs-fleet-80-2-line'))).data,
          '離線・PTU 未連線・心跳 3 分鐘前',
        );
        expect(find.byKey(const Key('gs-error')), findsNothing);
        expect(find.byKey(const Key('gs-loading')), findsNothing);
        expect(api.paths, ['GET /api/gateways/fleet-status']);
        // 〔重新整理〕: one more request.
        await tester.tap(find.byKey(const Key('gs-refresh')));
        await tester.pumpAndSettle();
        expect(api.paths, hasLength(2));
        // A fleet row opens the recent data of that gateway.
        await tester.tap(find.byKey(const Key('gs-fleet-80-2')));
        await tester.pumpAndSettle();
        expect(find.byType(RecentDataPage), findsOneWidget);
        expect(find.text('站 80 · 閘道器 2'), findsOneWidget);
        expect(api.paths.last, 'GET /api/app/recent/80/2?limit=20');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(GatewayStatusPage), findsOneWidget);
        // A recent-commission row too.
        await tester.tap(find.byKey(const Key('gs-recent-56-1')));
        await tester.pumpAndSettle();
        expect(find.text('站 56 · 閘道器 1'), findsOneWidget);
        expect(api.paths.last, 'GET /api/app/recent/56/1?limit=20');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('empty: both sections say so', (tester) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      await _pumpPage(tester, _Api('empty'), now);
      expect(find.byKey(const Key('gs-recent-empty')), findsOneWidget);
      expect(find.text(gatewayStatusRecentEmptyText), findsOneWidget);
      expect(find.byKey(const Key('gs-fleet-empty')), findsOneWidget);
      expect(find.text(gatewayStatusFleetEmptyText), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byKey(const Key('gs-error')), findsNothing);
    });

    testWidgets('error: words and 〔重試〕; retry recovers; recent list kept', (
      tester,
    ) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('network')..fleet = [_gw(56, 1)];
      await _pumpPage(
        tester,
        api,
        now,
        prefs: {
          'demo_recent_commissions':
              '[{"site":56,"gateway":1,"done_at":"2026-09-28T12:30:00"}]',
        },
      );
      expect(find.byKey(const Key('gs-error')), findsOneWidget);
      final text = tester
          .widget<Text>(find.byKey(const Key('gs-error-text')))
          .data!;
      expect(text, contains('Connection refused'));
      expect(find.byKey(const Key('gs-retry')), findsOneWidget);
      expect(find.byKey(const Key('gs-fleet-56-1')), findsNothing);
      // The phone's own list is still there and still opens.
      expect(find.byKey(const Key('gs-recent-56-1')), findsOneWidget);
      api.mode = 'data';
      await tester.tap(find.byKey(const Key('gs-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gs-error')), findsNothing);
      expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
    });

    testWidgets('loading: progress bar, refresh disabled', (tester) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..fleet = [_gw(56, 1)]
        ..gate = Completer<void>();
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(home: GatewayStatusPage(now: () => now)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('gs-loading')), findsOneWidget);
      expect(find.byKey(const Key('gs-progress')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('gs-refresh')))
            .onPressed,
        isNull,
      );
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gs-loading')), findsNothing);
      expect(find.byKey(const Key('gs-progress')), findsNothing);
      expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
    });

    testWidgets('fits a 360 dp phone', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..fleet = [
          _gw(
            56,
            1,
            direct: {'label': '已綁定', 'connected': true},
            dataAt: now.subtract(const Duration(seconds: 7)).toIso8601String(),
          ),
        ];
      await _pumpPage(tester, api, now);
      expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('entries', () {
    testWidgets('start page button and topology menu item open the page', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fake = DemoSystem();
      await _pumpApp(tester, fake);
      // (b) the start page's secondary button, below 〔檢查並開始〕.
      final button = find.byKey(const Key('home-gateway-status'));
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(button, findsOneWidget);
      expect(find.text(gatewayStatusLabel), findsOneWidget);
      final start = tester.getRect(find.text('檢查並開始'));
      expect(tester.getRect(button).top, greaterThan(start.bottom));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(GatewayStatusPage), findsOneWidget);
      expect(find.byKey(const Key('gs-recent-empty')), findsOneWidget);
      // 1.0.0+7: 練習模式 scans the demo link's list.
      expect(find.byKey(const Key('gs-nearby-demo-gateway')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(GatewayStatusPage), findsNothing);
      // (a) the topology menu's item.
      await tester.tap(find.byKey(const Key('topology-menu')));
      await tester.pumpAndSettle();
      final item = find.byKey(const Key('gateway-status-menu'));
      expect(item, findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(find.byType(GatewayStatusPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      // The flow is where it was.
      expect(find.text('檢查並開始'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('1.0.0+7 auto login', () {
    final now = DateTime(2026, 9, 28, 13, 0, 10);

    testWidgets('no session: logs in with the build key, then reads', (
      tester,
    ) async {
      final api = _Api('data')..fleet = [_gw(56, 1)];
      await _pumpPage(tester, api, now);
      expect(api.logins, [(productionApiBase, 'build-key')]);
      expect(api.paths, ['GET /api/gateways/fleet-status']);
      expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
      expect(find.byKey(const Key('gs-error')), findsNothing);
    });

    testWidgets('401 on the read: one re-login, the read repeated', (
      tester,
    ) async {
      final api = _SessionApi('data', origin: 'https://46.250.255.172')
        ..fleet = [_gw(56, 1)]
        ..authOnce = true;
      await _pumpPage(tester, api, now);
      // A session was held: no login before the read; one after the 401.
      expect(api.paths, [
        'GET /api/gateways/fleet-status',
        'GET /api/gateways/fleet-status',
      ]);
      expect(api.logins, [(productionApiBase, 'build-key')]);
      expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
      expect(find.byKey(const Key('gs-error')), findsNothing);
    });

    testWidgets('a session for another backend: logs in again', (tester) async {
      final api = _SessionApi('data', origin: 'http://192.168.0.12:18000')
        ..fleet = [_gw(56, 1)];
      await _pumpPage(tester, api, now);
      expect(api.logins, hasLength(1));
      expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
    });

    testWidgets('refused login: 「連不上後台（…）」 + 〔重試〕, never the done page', (
      tester,
    ) async {
      final api = _Api('data')
        ..fleet = [_gw(56, 1)]
        ..refuseLogin = true;
      await _pumpPage(tester, api, now);
      expect(api.logins, hasLength(1));
      expect(api.paths, isEmpty);
      final text = tester
          .widget<Text>(find.byKey(const Key('gs-error-text')))
          .data!;
      expect(text, startsWith('連不上後台（'));
      expect(text, isNot(contains('完成頁')));
      expect(text, isNot(contains('尚未登入')));
      expect(find.byKey(const Key('gs-retry')), findsOneWidget);
      // 〔重試〕 logs in again; the backend recovered.
      api.refuseLogin = false;
      await tester.tap(find.byKey(const Key('gs-retry')));
      await tester.pumpAndSettle();
      expect(api.logins, hasLength(2));
      expect(find.byKey(const Key('gs-error')), findsNothing);
      expect(find.byKey(const Key('gs-fleet-56-1')), findsOneWidget);
    });

    testWidgets('the recent-data page logs in by itself too', (tester) async {
      final api = _Api('data')..fleet = [_gw(56, 1)];
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(api),
            backendKeyProvider.overrideWithValue('build-key'),
          ],
          child: MaterialApp(
            home: RecentDataPage(site: 56, gateway: 1, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.logins, [(productionApiBase, 'build-key')]);
      expect(api.paths, ['GET /api/app/recent/56/1?limit=20']);
      expect(find.byKey(const Key('recent-error')), findsNothing);
    });

    test('hasSessionFor: same origin only', () {
      expect(hasSessionFor(_Api('data'), productionApiBase), isFalse);
      expect(
        hasSessionFor(
          _SessionApi('data', origin: 'https://46.250.255.172'),
          productionApiBase,
        ),
        isTrue,
      );
      expect(
        hasSessionFor(
          _SessionApi('data', origin: 'https://46.250.255.172'),
          'http://192.168.0.12:18000',
        ),
        isFalse,
      );
      expect(hasSessionFor(_SessionApi('data'), productionApiBase), isFalse);
    });
  });

  group('1.0.0+7 nearby gateways', () {
    final now = DateTime(2026, 9, 28, 13, 0, 10);

    testWidgets('rows: strongest first, 站/閘道器・RSSI・name; a tap opens', (
      tester,
    ) async {
      final scanner = _Scanner([
        const GatewayPeer('AA:BB:CC:DD:EE:02', 'GIOS-S80-GW02', -71),
        const GatewayPeer('AA:BB:CC:DD:EE:01', 'GIOS-S56-GW01', -58),
        const GatewayPeer('AA:BB:CC:DD:EE:00', 'GIOS-S0-GW00', -40),
      ]);
      final api = _Api('empty');
      await _pumpPage(tester, api, now, scanner: scanner);
      expect(scanner.scans, 1);
      expect(find.byKey(const Key('gs-nearby-scanning')), findsNothing);
      expect(find.byKey(const Key('gs-nearby-empty')), findsNothing);
      // The section sits between 「最近配置」 and 「後台在線閘道器」.
      final nearbyTop = tester.getRect(find.text(gatewayStatusNearbyTitle)).top;
      expect(
        nearbyTop,
        greaterThan(tester.getRect(find.text(gatewayStatusRecentTitle)).top),
      );
      expect(
        nearbyTop,
        lessThan(tester.getRect(find.text(gatewayStatusFleetTitle)).top),
      );
      // Rows by signal; the one without an identity is not tappable.
      final rows = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.key as ValueKey<String>).value)
          .toList();
      expect(rows, [
        'gs-nearby-AA:BB:CC:DD:EE:00',
        'gs-nearby-AA:BB:CC:DD:EE:01',
        'gs-nearby-AA:BB:CC:DD:EE:02',
      ]);
      expect(find.text('站 56 閘道器 1'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('gs-nearby-AA:BB:CC:DD:EE:01-line')),
            )
            .data,
        '-58 dBm・GIOS\u2011S56\u2011GW01',
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const Key('gs-nearby-AA:BB:CC:DD:EE:00')),
            )
            .enabled,
        isFalse,
      );
      expect(find.byKey(const Key('gs-nearby-rescan')), findsOneWidget);
      // A tap opens that gateway's recent data — no connect, no pairing.
      await tester.tap(find.byKey(const Key('gs-nearby-AA:BB:CC:DD:EE:01')));
      await tester.pumpAndSettle();
      expect(find.byType(RecentDataPage), findsOneWidget);
      expect(find.text('站 56 · 閘道器 1'), findsOneWidget);
      expect(api.paths.last, 'GET /api/app/recent/56/1?limit=20');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(GatewayStatusPage), findsOneWidget);
      // Leaving the page stops the scan (the adapter is a singleton).
      expect(scanner.stopped, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(scanner.stopped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('none heard: the words and 〔重新掃描〕 scans again', (tester) async {
      final scanner = _Scanner();
      await _pumpPage(tester, _Api('empty'), now, scanner: scanner);
      expect(find.byKey(const Key('gs-nearby-empty')), findsOneWidget);
      expect(find.text(gatewayStatusNearbyEmptyText), findsOneWidget);
      scanner.peers = [
        const GatewayPeer('AA:BB:CC:DD:EE:01', 'GIOS-S56-GW01', -58),
      ];
      await tester.tap(find.byKey(const Key('gs-nearby-rescan')));
      await tester.pumpAndSettle();
      expect(scanner.scans, 2);
      expect(find.byKey(const Key('gs-nearby-empty')), findsNothing);
      expect(
        find.byKey(const Key('gs-nearby-AA:BB:CC:DD:EE:01')),
        findsOneWidget,
      );
    });

    testWidgets('no permission / Bluetooth off: the link\'s words, 〔開啟權限設定〕', (
      tester,
    ) async {
      final scanner = _Scanner()..failure = const GatewayFailure('permission');
      await _pumpPage(tester, _Api('empty'), now, scanner: scanner);
      expect(find.byKey(const Key('gs-nearby-error')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('gs-nearby-error-text'))).data,
        const GatewayFailure('permission').message,
      );
      expect(find.byKey(const Key('gs-nearby-settings')), findsOneWidget);
      expect(find.text(gatewayStatusSettingsLabel), findsOneWidget);
      expect(find.byKey(const Key('gs-nearby-rescan')), findsOneWidget);
      // Bluetooth off reads the same way; the back office part is untouched.
      scanner.failure = const GatewayFailure('bluetooth_off');
      await tester.tap(find.byKey(const Key('gs-nearby-rescan')));
      await tester.pumpAndSettle();
      expect(find.text('請開啟手機藍牙後重試。'), findsOneWidget);
      expect(find.byKey(const Key('gs-fleet-empty')), findsOneWidget);
      // Granted: the rescan recovers.
      scanner
        ..failure = null
        ..peers = [
          const GatewayPeer('AA:BB:CC:DD:EE:01', 'GIOS-S56-GW01', -58),
        ];
      await tester.tap(find.byKey(const Key('gs-nearby-rescan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gs-nearby-error')), findsNothing);
      expect(
        find.byKey(const Key('gs-nearby-AA:BB:CC:DD:EE:01')),
        findsOneWidget,
      );
    });

    testWidgets('scanning: progress row, 〔重新掃描〕 absent until it ends', (
      tester,
    ) async {
      final scanner = _Scanner([
        const GatewayPeer('AA:BB:CC:DD:EE:01', 'GIOS-S56-GW01', -58),
      ])..gate = Completer<void>();
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(_Api('empty')),
            backendKeyProvider.overrideWithValue('build-key'),
            nearbyScannerProvider.overrideWithValue(scanner),
          ],
          child: MaterialApp(home: GatewayStatusPage(now: () => now)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('gs-nearby-scanning')), findsOneWidget);
      expect(find.text(gatewayStatusNearbyScanningText), findsOneWidget);
      expect(find.byKey(const Key('gs-nearby-rescan')), findsNothing);
      scanner.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gs-nearby-scanning')), findsNothing);
      expect(
        find.byKey(const Key('gs-nearby-AA:BB:CC:DD:EE:01')),
        findsOneWidget,
      );
    });

    testWidgets('recent list empty words (1.0.0+7)', (tester) async {
      await _pumpPage(tester, _Api('empty'), now);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('gs-recent-empty')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '這支手機尚未用此版本完成過配置',
      );
    });
  });
}
