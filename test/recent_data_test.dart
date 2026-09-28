// 09-28 〔查看最近資料〕: the done page's third button opens a page that
// shows the last rows the back office received from this gateway, through
// the APP's own session (GET /api/app/recent/{site}/{gateway}?limit=20).
// 1. The model parses the fixed contract (local time, PTU tail, volts).
// 2. The page, top to bottom: the status banner (green / yellow / red /
//    grey, red with 〔重試〕 on an error) with the 「最近 N 筆」 line under
//    it, the newest row per PTU in big digits (MAC's last 3 groups, whole
//    MAC in small print; red border on a fault; one tile per PTU in the
//    star mode), the collapsed table (1.0.0+5: fixed columns that fit
//    360 dp with one PTU, a PTU column and a sideways scroll with more;
//    no chart any more); 〔重新整理〕 at the top right.
// 3. The done page has 〔查看最近資料〕 next to 〔完成〕／〔配置下一台〕 and
//    opens the page for the finished station / gateway.
// 4. Opening the page reports 「查看最近資料」 while a session is open, and
//    nothing once it ended (the done page's case).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/recent_data_api.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

const _sample = {
  'site_id': 80,
  'gateway_id': 1,
  'count': 2,
  'items': [
    {
      'ts': '2026-09-28T13:00:00.123+08:00',
      'seq': 123,
      'device_id': 1,
      'ptu_mac': '90:5F:E8:9A:96:00',
      'ptu_state': 'POWER_TRANSFER',
      'input_mv': 5000,
      'input_ma': 120,
      'bus_mv': 4980,
      'temp_c': 31,
    },
    {
      'ts': '2026-09-28T12:59:58+08:00',
      'seq': 122,
      'device_id': 1,
      'ptu_mac': '90:5F:E8:9A:96:00',
      'ptu_state': 'IDLE',
      'input_mv': 4990,
      'input_ma': 0,
      'bus_mv': 4980,
      'temp_c': 30,
    },
  ],
};

/// The backend as the page sees it: [mode] `data` answers [answer],
/// `empty` count 0, `network` / `auth` fail. Records the paths asked.
class _Api implements GatewayApi {
  _Api(this.mode);
  String mode;
  Map<String, dynamic> answer = Map<String, dynamic>.from(_sample);
  final paths = <String>[];

  /// When set, an answer waits for it (the loading screen's test).
  Completer<void>? gate;

  @override
  Future<void> login(String base, String password) async {}

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add('$method $path');
    if (gate != null) await gate!.future;
    switch (mode) {
      case 'empty':
        return {'site_id': 80, 'gateway_id': 1, 'count': 0, 'items': []};
      case 'network':
        throw GatewayFailure.network(
          endpoint: '$method $path',
          detail: 'Connection refused',
          backend: '後端 https://example.invalid',
        );
      case 'auth':
        throw const GatewayFailure('authentication');
    }
    return answer;
  }
}

/// Rows whose `ts` is [ago] before [now] (local), so the clock text is
/// known whatever the test machine's time zone.
Map<String, dynamic> _rowsAt(
  DateTime now,
  List<Duration> ago, {
  bool samePtu = true,
  List<String>? states,
  List<num>? ma,
}) => {
  'site_id': 80,
  'gateway_id': 1,
  'count': ago.length,
  'items': [
    for (final (i, d) in ago.indexed)
      {
        'ts': now.subtract(d).toIso8601String(),
        'seq': 100 - i,
        'device_id': 1,
        'ptu_mac': samePtu ? '90:5F:E8:9A:96:00' : '90:5F:E8:9A:96:0${i + 1}',
        'ptu_state': states != null ? states[i] : 'POWER_TRANSFER',
        'input_mv': 5000,
        'input_ma': ma != null ? ma[i] : 120,
        'bus_mv': 4980,
        'temp_c': 31,
      },
  ],
};

Future<void> _pumpPage(WidgetTester tester, _Api api, DateTime now) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(DemoSystem()),
        apiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: RecentDataPage(site: 80, gateway: 1, now: () => now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// Star: a new gateway commissioned as station 80 / gateway 1 and
/// verified — the done page (the round 29 sequence).
Future<ProviderContainer> _pumpStarDone(
  WidgetTester tester,
  DemoSystem fake,
) async {
  SharedPreferences.setMockInitialValues({});
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
  expect(s.verified, isTrue);
  return container;
}

/// A gateway in service whose field reports are recorded in [reports].
class _Reporting extends PickGateway implements SessionInfo {
  final reports = <Map<String, dynamic>>[];

  @override
  bool get hasSession => true;

  @override
  String? get origin => 'https://example.invalid';

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == fieldSessionsPath) {
      reports.add(Map<String, dynamic>.from(body ?? const {}));
      return {'ok': true};
    }
    return super.request(method, path, body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model', () {
    test('parses the contract; ts is local time', () {
      final data = RecentData.fromJson(Map<String, dynamic>.from(_sample));
      expect(data.siteId, 80);
      expect(data.gatewayId, 1);
      expect(data.count, 2);
      expect(data.items, hasLength(2));
      final first = data.items.first;
      expect(first.seq, 123);
      expect(first.deviceId, 1);
      expect(first.ptuMac, '90:5F:E8:9A:96:00');
      expect(first.ptuTail, '9600');
      expect(first.ptuShort, '9A:96:00');
      expect(first.ptuMacText, '90:5F:E8:9A:96:00');
      expect(first.ptuState, 'POWER_TRANSFER');
      expect(first.inputMv, 5000);
      expect(first.inputVoltsText, '5.00');
      expect(first.inputMa, 120);
      expect(first.busMv, 4980);
      expect(first.tempC, 31);
      final ts = first.ts!;
      expect(ts.isUtc, isFalse, reason: 'toLocal()');
      expect(
        ts.toUtc(),
        DateTime.utc(2026, 9, 28, 5, 0, 0, 123),
        reason: '+08:00 → UTC 05:00',
      );
      expect(data.latest, ts, reason: 'the newest row');
      expect(data.isEmpty, isFalse);
      expect(data.items[1].inputVoltsText, '4.99');
    });

    test('count 0, missing fields and bad timestamps are tolerated', () {
      final empty = RecentData.fromJson({
        'site_id': 80,
        'gateway_id': 1,
        'count': 0,
        'items': [],
      });
      expect(empty.isEmpty, isTrue);
      expect(empty.latest, isNull);
      final odd = RecentData.fromJson(
        {
          'items': [
            {'ts': 'not-a-time', 'ptu_mac': 'AB'},
          ],
        },
        site: 56,
        gateway: 1,
      );
      expect(odd.siteId, 56);
      expect(odd.count, 1, reason: 'falls back to the item count');
      expect(odd.items.single.ts, isNull);
      expect(odd.items.single.ptuTail, 'AB');
      expect(odd.items.single.inputVoltsText, '--');
      expect(recentClockText(null), '--:--:--');
      expect(parseRecentTs(null), isNull);
      expect(parseRecentTs(42), isNull);
      expect(ptuMacTail('90-5f-e8-9a-96-0a'), '960A');
    });

    test('PTU short form: the last 3 groups with colons (1.0.0+5)', () {
      expect(ptuMacShort('90:5F:E8:9A:96:00'), '9A:96:00');
      expect(ptuMacShort('90-5f-e8-9a-96-0a'), '9A:96:0A');
      expect(ptuMacShort('905FE89A9600'), '9A:96:00');
      expect(ptuMacShort('9A:96:00'), '9A:96:00');
      expect(ptuMacShort('AB'), 'AB');
      expect(ptuMacShort('ABC'), 'A:BC');
      expect(ptuMacShort(''), '');
      expect(ptuMacFull('905fe89a9600'), '90:5F:E8:9A:96:00');
      expect(ptuMacFull(''), '');
      expect(
        RecentItem.fromJson({'ptu_mac': '90:5F:E8:9A:96:00'}).ptuShort,
        '9A:96:00',
      );
    });

    test('summary and clock text', () {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final data = RecentData.fromJson(
        _rowsAt(now, const [Duration(seconds: 7), Duration(seconds: 30)]),
      );
      expect(recentSummaryText(data, now), '最近一筆 7 秒前・共 2 筆');
      expect(recentClockText(data.items.first.ts), '13:00:03');
      expect(recentClockText(DateTime(2026, 1, 1, 8, 5, 9)), '08:05:09');
      final future = RecentData.fromJson(
        _rowsAt(now, const [Duration(seconds: -3)]),
      );
      expect(recentSummaryText(future, now), '最近一筆 0 秒前・共 1 筆');
      expect(
        recentSummaryText(
          const RecentData(siteId: 1, gatewayId: 1, count: 1, items: []),
          now,
        ),
        '最近一筆 時間不明・共 1 筆',
      );
    });

    test('fetch asks the fixed path with the limit', () async {
      final api = _Api('data');
      final data = await fetchRecentData(api, site: 56, gateway: 1);
      expect(api.paths.single, 'GET /api/app/recent/56/1?limit=20');
      expect(data.count, 2);
      expect(recentDataPath(80, 2, limit: 5), '/api/app/recent/80/2?limit=5');
    });

    test('error words', () {
      expect(
        recentDataErrorText(const GatewayFailure('authentication')),
        contains('連不上後台（後台拒絕'),
      );
      expect(
        recentDataErrorText(
          GatewayFailure.http(status: 503, endpoint: 'GET /x', detail: 'down'),
        ),
        contains('503'),
      );
      expect(recentDataErrorText(StateError('boom')), contains('boom'));
    });
  });

  group('view helpers', () {
    test('PTU state words follow the firmware table; faults detected', () {
      expect(ptuStateLabel('CONFIGURATION'), '設定中');
      expect(ptuStateLabel('POWER_SAVE'), '省電');
      expect(ptuStateLabel('LOW_POWER'), '低功率');
      expect(ptuStateLabel('POWER_TRANSFER'), '充電中');
      expect(ptuStateLabel('LATCH_FAULT'), '鎖定故障');
      expect(ptuStateLabel('LATCHING_FAULT'), '鎖定故障');
      expect(ptuStateLabel('LOCAL_FAULT'), '本地故障');
      expect(ptuStateLabel('OTA_MODE'), 'OTA 更新中');
      expect(ptuStateLabel('COOLING'), '冷卻中');
      expect(ptuStateLabel('EXCEEDED_RANGE'), 'PRU 超出範圍');
      expect(ptuStateLabel('UNKNOWN'), '未知');
      expect(ptuStateLabel('power_transfer'), '充電中', reason: 'case');
      expect(ptuStateLabel('IDLE'), 'IDLE', reason: 'unknown: as sent');
      expect(ptuStateLabel(''), '--');
      expect(ptuStateLabel('NULL'), '--');
      expect(ptuStateIsFault('LOCAL_FAULT'), isTrue);
      expect(ptuStateIsFault('LATCH_FAULT'), isTrue);
      expect(ptuStateIsFault('POWER_TRANSFER'), isFalse);
      expect(ptuStateIsFault(''), isFalse);
    });

    test('short state words for the table (1.0.0+5)', () {
      expect(ptuStateShort('POWER_TRANSFER'), '充電');
      expect(ptuStateShort('IDLE'), '待機');
      expect(ptuStateShort('POWER_SAVE'), '省電');
      expect(ptuStateShort('LOW_POWER'), '低功率');
      expect(ptuStateShort('CONFIGURATION'), '設定');
      expect(ptuStateShort('COOLING'), '冷卻');
      expect(ptuStateShort('EXCEEDED_RANGE'), '超範圍');
      expect(ptuStateShort('LATCH_FAULT'), '故障');
      expect(ptuStateShort('LATCHING_FAULT'), '故障');
      expect(ptuStateShort('LOCAL_FAULT'), '故障');
      expect(ptuStateShort('OTA_MODE'), 'OTA');
      expect(ptuStateShort('UNKNOWN'), '未知');
      expect(ptuStateShort('power_transfer'), '充電', reason: 'case');
      expect(ptuStateShort('SOME_FAULT'), '故障', reason: 'any fault');
      expect(ptuStateShort('WHATEVER'), 'WHAT', reason: 'cut to 4');
      expect(ptuStateShort(''), '--');
      expect(ptuStateShort('NULL'), '--');
      for (final key in ptuStateLabels.keys) {
        expect(ptuStateShortLabels, contains(key), reason: key);
      }
    });

    test('numbers: amps, volts, temperature, age', () {
      expect(recentAmpsText(1612), '1.61');
      expect(recentAmpsText(0), '0.00');
      expect(recentAmpsText(null), '--');
      expect(recentVoltsBigText(52400), '52.4');
      expect(recentVoltsBigText(null), '--');
      expect(recentTempText(13.4), '13');
      expect(recentTempText(null), '--');
      expect(recentAgeText(const Duration(seconds: 7)), '7 秒');
      expect(recentAgeText(const Duration(seconds: -3)), '0 秒');
      expect(recentAgeText(const Duration(seconds: 59)), '59 秒');
      expect(recentAgeText(const Duration(seconds: 60)), '1 分鐘');
      expect(recentAgeText(const Duration(minutes: 9, seconds: 59)), '9 分鐘');
    });

    test('banner: fresh, stale, stopped, empty, unknown time', () {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      RecentBanner at(Duration age) =>
          recentBanner(RecentData.fromJson(_rowsAt(now, [age])), now);
      expect(
        at(const Duration(seconds: 0)),
        const RecentBanner(RecentBannerKind.ok, recentDataOkText),
      );
      expect(at(const Duration(seconds: 29)).kind, RecentBannerKind.ok);
      expect(
        at(const Duration(seconds: 30)),
        const RecentBanner(RecentBannerKind.stale, '最近 30 秒沒有新資料'),
      );
      expect(
        at(const Duration(minutes: 5)),
        const RecentBanner(RecentBannerKind.stale, '最近 5 分鐘沒有新資料'),
      );
      expect(
        at(const Duration(minutes: 9, seconds: 59)).kind,
        RecentBannerKind.stale,
      );
      expect(
        at(const Duration(minutes: 10)),
        const RecentBanner(RecentBannerKind.stopped, '最近 10 分鐘沒有新資料'),
      );
      expect(
        recentBanner(RecentData.fromJson({'count': 0, 'items': []}), now),
        const RecentBanner(RecentBannerKind.empty, recentDataEmptyText),
      );
      expect(
        recentBanner(
          const RecentData(siteId: 1, gatewayId: 1, count: 1, items: []),
          now,
        ).kind,
        RecentBannerKind.empty,
        reason: 'no items at all',
      );
      expect(
        recentBanner(
          RecentData.fromJson({
            'items': [
              {'ts': 'bad', 'ptu_mac': 'AB'},
            ],
          }),
          now,
        ).kind,
        RecentBannerKind.unknown,
      );
    });

    test('latest per device, trend text, latest line', () {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      // Two PTUs, three rows: the newest of each, newest PTU first.
      final data = RecentData.fromJson({
        'count': 3,
        'items': [
          {
            'ts': now.subtract(const Duration(seconds: 1)).toIso8601String(),
            'ptu_mac': '90:5F:E8:9A:96:02',
            'ptu_state': 'LOW_POWER',
            'input_ma': 10,
          },
          {
            'ts': now.subtract(const Duration(seconds: 2)).toIso8601String(),
            'ptu_mac': '90:5F:E8:9A:96:01',
            'ptu_state': 'POWER_TRANSFER',
            'input_ma': 1612,
          },
          {
            'ts': now.subtract(const Duration(seconds: 5)).toIso8601String(),
            'ptu_mac': '90:5F:E8:9A:96:02',
            'ptu_state': 'POWER_TRANSFER',
            'input_ma': 500,
          },
        ],
      });
      final latest = recentLatestPerDevice(data);
      expect(latest.map((i) => i.ptuTail), ['9602', '9601']);
      expect(latest.first.ptuState, 'LOW_POWER', reason: 'the newest of 9602');
      expect(recentChronological(data).map((i) => i.inputMa), [500, 1612, 10]);
      expect(recentTrendText(data), '最近 3 筆・跨 4 秒・平均每秒 0.8 筆');
      expect(
        recentLatestLine(latest.last, now),
        'PTU 90:5F:E8:9A:96:01・充電中・13:00:08（2 秒前）',
      );
      expect(recentLatestParts(latest.last, now), (
        'PTU 90:5F:E8:9A:96:01',
        '充電中・13:00:08（2 秒前）',
      ));
      // One row: no span.
      final one = RecentData.fromJson(_rowsAt(now, const [Duration.zero]));
      expect(recentLatestPerDevice(one), hasLength(1));
      expect(recentTrendText(one), '最近 1 筆');
      // Rows without a MAC group by device number; no ts → 「時間不明」.
      final byId = RecentData.fromJson({
        'items': [
          {'device_id': 1, 'ptu_state': 'POWER_TRANSFER'},
          {'device_id': 2},
          {'device_id': 1},
        ],
      });
      expect(recentLatestPerDevice(byId), hasLength(2));
      expect(recentTrendText(byId), '最近 3 筆');
      expect(
        recentLatestLine(byId.items[1], now),
        'PTU --:--:--・--・--:--:--（時間不明）',
      );
    });
  });

  group('page', () {
    testWidgets('fresh data: green banner, summary, big card, table; refresh', (
      tester,
    ) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..answer = _rowsAt(
          now,
          const [Duration(seconds: 5), Duration(seconds: 25)],
          ma: const [1612, 120],
        );
      await _pumpPage(tester, api, now);
      // 1.0.0+10: 「最近資料」 in the AppBar, the gateway under it.
      expect(find.text(recentDataPageTitle), findsOneWidget);
      expect(find.text('站 80 · 閘道器 1'), findsOneWidget);
      // 1. Banner.
      expect(find.byKey(const Key('recent-banner')), findsOneWidget);
      expect(find.byKey(const Key('recent-banner-ok')), findsOneWidget);
      expect(find.text(recentDataOkText), findsOneWidget);
      // 2. One PTU → one big card, no grid, no fault line.
      final cardFinder = find.byKey(const Key('recent-latest'));
      expect(cardFinder, findsOneWidget);
      expect(find.byKey(const Key('recent-latest-grid')), findsNothing);
      expect(find.byKey(const Key('recent-latest-fault')), findsNothing);
      // 1.0.0+8: the whole MAC on the line (a Wrap of two pieces); the
      // small 「MAC …」 print under it is gone.
      expect(find.byKey(const Key('recent-latest-line')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('recent-latest-line-mac')))
            .data,
        'PTU 90:5F:E8:9A:96:00',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('recent-latest-line-rest')))
            .data,
        '充電中・13:00:05（5 秒前）',
      );
      expect(find.textContaining('PTU 9A:96:00'), findsNothing);
      expect(find.textContaining('PTU 9600'), findsNothing);
      expect(find.byKey(const Key('recent-latest-mac')), findsNothing);
      expect(find.textContaining('MAC 90:5F'), findsNothing);
      final big = find.descendant(
        of: cardFinder,
        matching: find.byType(RichText),
      );
      final bigText = tester
          .widgetList<RichText>(big)
          .map((r) => r.text.toPlainText())
          .toList();
      expect(bigText, containsAll(['5.0 V', '1.61 A', '31 °C']));
      final card = tester.widget<Card>(cardFinder);
      final side = (card.shape! as RoundedRectangleBorder).side;
      final colors = Theme.of(tester.element(cardFinder)).colorScheme;
      expect(side.color, isNot(colors.error));
      // 3. The summary line under the banner; no chart (1.0.0+5).
      expect(find.text('最近 2 筆・跨 20 秒・平均每秒 0.1 筆'), findsOneWidget);
      final trend = tester.getRect(find.byKey(const Key('recent-trend')));
      final bannerRect = tester.getRect(find.byKey(const Key('recent-banner')));
      expect(trend.top, greaterThanOrEqualTo(bannerRect.bottom));
      expect(trend.bottom, lessThanOrEqualTo(tester.getRect(cardFinder).top));
      expect(find.byKey(const Key('recent-trend-chart')), findsNothing);
      // 4. Table collapsed, then expanded with short words for the state.
      expect(find.byKey(const Key('recent-table-tile')), findsOneWidget);
      expect(find.text('最近資料（2 筆）'), findsOneWidget);
      expect(find.byKey(const Key('recent-table')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('recent-table-tile')),
        200,
      );
      await tester.tap(find.byKey(const Key('recent-table-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-table')), findsOneWidget);
      expect(find.text('13:00:05'), findsOneWidget);
      expect(find.text('12:59:45'), findsOneWidget);
      expect(find.text('充電'), findsNWidgets(2));
      expect(find.text('POWER_TRANSFER'), findsNothing);
      // One PTU: no PTU column, no sideways scroll.
      expect(find.text('PTU'), findsNothing);
      expect(find.byKey(const Key('recent-table-scroll')), findsNothing);
      expect(find.byKey(const Key('recent-empty')), findsNothing);
      expect(find.byKey(const Key('recent-error')), findsNothing);
      expect(api.paths, ['GET /api/app/recent/80/1?limit=20']);
      // 〔重新整理〕: one more request, no polling in between.
      await tester.pump(const Duration(seconds: 30));
      expect(api.paths, hasLength(1), reason: 'no automatic polling');
      await tester.tap(find.byKey(const Key('recent-refresh')));
      await tester.pumpAndSettle();
      expect(api.paths, hasLength(2));
    });

    testWidgets('stale data: yellow banner with the age', (tester) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..answer = _rowsAt(now, const [Duration(minutes: 3)]);
      await _pumpPage(tester, api, now);
      expect(find.byKey(const Key('recent-banner-stale')), findsOneWidget);
      expect(find.text('最近 3 分鐘沒有新資料'), findsOneWidget);
      expect(find.byKey(const Key('recent-latest')), findsOneWidget);
    });

    testWidgets('fault state: red border and 「PTU 回報故障」', (tester) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..answer = _rowsAt(
          now,
          const [Duration(seconds: 1), Duration(seconds: 3)],
          states: const ['LOCAL_FAULT', 'POWER_TRANSFER'],
        );
      await _pumpPage(tester, api, now);
      final cardFinder = find.byKey(const Key('recent-latest'));
      final card = tester.widget<Card>(cardFinder);
      final side = (card.shape! as RoundedRectangleBorder).side;
      final colors = Theme.of(tester.element(cardFinder)).colorScheme;
      expect(side.color, colors.error);
      expect(side.width, 2);
      expect(find.byKey(const Key('recent-latest-fault')), findsOneWidget);
      expect(find.text(recentDataFaultText), findsOneWidget);
      expect(find.textContaining('本地故障'), findsOneWidget);
    });

    testWidgets('star mode: one tile per PTU', (tester) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..answer = _rowsAt(
          now,
          const [
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 3),
          ],
          samePtu: false,
          states: const ['POWER_TRANSFER', 'LATCH_FAULT', 'LOW_POWER'],
        );
      await _pumpPage(tester, api, now);
      expect(find.byKey(const Key('recent-latest')), findsNothing);
      expect(find.byKey(const Key('recent-latest-grid')), findsOneWidget);
      expect(find.byKey(const Key('recent-latest-9601')), findsOneWidget);
      expect(find.byKey(const Key('recent-latest-9602')), findsOneWidget);
      expect(find.byKey(const Key('recent-latest-9603')), findsOneWidget);
      expect(find.byKey(const Key('recent-latest-9602-fault')), findsOneWidget);
      expect(find.byKey(const Key('recent-latest-9601-fault')), findsNothing);
      // 1.0.0+8: star tiles show the whole MAC too.
      expect(find.text('PTU 90:5F:E8:9A:96:03'), findsOneWidget);
      expect(find.textContaining('低功率・'), findsOneWidget);
      expect(find.byKey(const Key('recent-latest-9603-mac')), findsNothing);
      expect(find.byKey(const Key('recent-trend-chart')), findsNothing);
      // Several PTUs: the PTU column and a sideways scroll.
      await tester.scrollUntilVisible(
        find.byKey(const Key('recent-table-tile')),
        200,
      );
      await tester.tap(find.byKey(const Key('recent-table-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-table-scroll')), findsOneWidget);
      expect(find.text('PTU'), findsOneWidget);
      expect(find.text('9A:96:01'), findsOneWidget);
      expect(find.text('9A:96:02'), findsOneWidget);
      expect(find.text('9A:96:03'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('table at 360 dp: every column visible, no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..answer = _rowsAt(
          now,
          const [
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 3),
            Duration(seconds: 4),
          ],
          states: const [
            'POWER_TRANSFER',
            'EXCEEDED_RANGE',
            'LOW_POWER',
            'LOCAL_FAULT',
          ],
          ma: const [1612, 12345, 0, 7],
        );
      await _pumpPage(tester, api, now);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('recent-table-tile')),
        200,
      );
      await tester.tap(find.byKey(const Key('recent-table-tile')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.byKey(const Key('recent-table')), findsOneWidget);
      expect(find.byKey(const Key('recent-table-scroll')), findsNothing);
      // The last column (狀態) ends inside the 360 dp screen, for the
      // header and for every row.
      for (final label in ['狀態', '充電', '超範圍', '低功率', '故障']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.right, lessThanOrEqualTo(360), reason: label);
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      }
      // A row's cells are one line: the state text is not wrapped.
      final state = tester.widget<Text>(find.text('超範圍'));
      expect(state.maxLines, 1);
      expect(state.softWrap, isFalse);
      expect(find.text('12.35'), findsOneWidget, reason: 'a wide A value');
      expect(tester.takeException(), isNull);
    });

    testWidgets('count 0: grey banner, refresh then shows data', (
      tester,
    ) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('empty')
        ..answer = _rowsAt(now, const [Duration(seconds: 2)]);
      await _pumpPage(tester, api, now);
      expect(find.byKey(const Key('recent-empty')), findsOneWidget);
      expect(find.byKey(const Key('recent-banner-empty')), findsOneWidget);
      expect(find.text(recentDataEmptyText), findsOneWidget);
      expect(find.byKey(const Key('recent-latest')), findsNothing);
      api.mode = 'data';
      await tester.tap(find.byKey(const Key('recent-empty-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-empty')), findsNothing);
      expect(find.text(recentDataOkText), findsOneWidget);
      expect(find.text('PTU 90:5F:E8:9A:96:00'), findsOneWidget);
      expect(find.text('充電中・13:00:08（2 秒前）'), findsOneWidget);
    });

    testWidgets('error: red banner with 〔重試〕; retry recovers', (tester) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('network')
        ..answer = _rowsAt(now, const [Duration(seconds: 2)]);
      await _pumpPage(tester, api, now);
      expect(find.byKey(const Key('recent-error')), findsOneWidget);
      expect(find.byKey(const Key('recent-banner-error')), findsOneWidget);
      final text = tester
          .widget<Text>(find.byKey(const Key('recent-error-text')))
          .data!;
      expect(text, contains('無法連到'));
      expect(text, contains('Connection refused'));
      expect(find.byKey(const Key('recent-retry')), findsOneWidget);
      api.mode = 'data';
      await tester.tap(find.byKey(const Key('recent-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-error')), findsNothing);
      expect(find.byKey(const Key('recent-latest')), findsOneWidget);
      // An error after data keeps the error on screen (not the old card).
      api.mode = 'auth';
      await tester.tap(find.byKey(const Key('recent-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-error')), findsOneWidget);
      expect(find.byKey(const Key('recent-latest')), findsNothing);
      expect(find.textContaining('連不上後台（後台拒絕'), findsOneWidget);
    });

    testWidgets('loading: progress under the app bar, refresh disabled', (
      tester,
    ) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..answer = _rowsAt(now, const [Duration.zero])
        ..gate = Completer<void>();
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            home: RecentDataPage(site: 80, gateway: 1, now: () => now),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('recent-loading')), findsOneWidget);
      expect(find.byKey(const Key('recent-progress')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('recent-refresh')))
            .onPressed,
        isNull,
      );
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-loading')), findsNothing);
      expect(find.byKey(const Key('recent-progress')), findsNothing);
    });
  });

  group('done page', () {
    testWidgets('〔查看最近資料〕 opens the page for the finished gateway', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = DemoSystem();
      await _pumpStarDone(tester, fake);
      final button = find.byKey(const Key('done-recent'));
      expect(button, findsOneWidget);
      expect(find.text(recentDataLabel), findsOneWidget);
      // Still on the first screen next to 〔完成〕／〔配置下一台〕.
      expect(find.byKey(const Key('done-finish')), findsOneWidget);
      expect(find.byKey(const Key('done-next')), findsOneWidget);
      final rect = tester.getRect(button);
      expect(rect.bottom, lessThanOrEqualTo(640));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(RecentDataPage), findsOneWidget);
      // 1.0.0+10: 「最近資料」 in the AppBar, the gateway under it.
      expect(find.text(recentDataPageTitle), findsOneWidget);
      expect(find.text('站 80 · 閘道器 1'), findsOneWidget);
      // The demo backend answers one row per connected PTU (just sent).
      expect(find.byKey(const Key('recent-body')), findsOneWidget);
      expect(find.text(recentDataOkText), findsOneWidget);
      expect(find.byKey(const Key('recent-trend')), findsOneWidget);
      expect(find.byKey(const Key('recent-trend-chart')), findsNothing);
      // Back: the done page, its buttons untouched.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RecentDataPage), findsNothing);
      expect(find.byKey(const Key('done-finish')), findsOneWidget);
      expect(find.byKey(const Key('done-recent')), findsOneWidget);
    });
  });

  group('field report', () {
    test('sent while a session is open; nothing once it ended', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _Reporting();
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
          fieldReporterConfigProvider.overrideWithValue(
            const FieldReporterConfig(allowDemoLink: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      final reporter = container.read(fieldReporterProvider);
      expect(reporter.session, isNotNull, reason: 'a run at step 2');
      expect(reporter.noteRecentDataViewed(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final report = fake.reports.firstWhere(
        (r) => r['error_message'] == recentDataReportText,
        orElse: () => const {},
      );
      expect(report['event'], 'status');
      // The done page's case: the session ended.
      reporter.end('completed');
      expect(reporter.session, isNull);
      final before = fake.reports.length;
      expect(reporter.noteRecentDataViewed(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        fake.reports
            .skip(before)
            .where((r) => r['error_message'] == recentDataReportText),
        isEmpty,
      );
    });
  });
}
