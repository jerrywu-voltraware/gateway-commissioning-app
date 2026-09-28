// 09-28 〔查看最近資料〕: the done page's third button opens a page that
// shows the last rows the back office received from this gateway, through
// the APP's own session (GET /api/app/recent/{site}/{gateway}?limit=20).
// 1. The model parses the fixed contract (local time, PTU tail, volts).
// 2. Three screens: rows with the summary line, count 0 (「後台尚未收到…」),
//    an error in words with 〔重試〕; 〔重新整理〕 at the top right.
// 3. The done page has 〔查看最近資料〕 next to 〔完成〕／〔配置下一台〕 and
//    opens the page for the finished station / gateway.
// 4. Opening the page reports 「查看最近資料」 while a session is open, and
//    nothing once it ended (the done page's case).
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

  @override
  Future<void> login(String base, String password) async {}

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add('$method $path');
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
Map<String, dynamic> _rowsAt(DateTime now, List<Duration> ago) => {
  'site_id': 80,
  'gateway_id': 1,
  'count': ago.length,
  'items': [
    for (final (i, d) in ago.indexed)
      {
        'ts': now.subtract(d).toIso8601String(),
        'seq': 100 - i,
        'device_id': 1,
        'ptu_mac': '90:5F:E8:9A:96:0${i + 1}',
        'ptu_state': i == 0 ? 'POWER_TRANSFER' : 'IDLE',
        'input_mv': 5000,
        'input_ma': 120,
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
      final odd = RecentData.fromJson({
        'items': [
          {'ts': 'not-a-time', 'ptu_mac': 'AB'},
        ],
      }, site: 56, gateway: 1);
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
        contains('尚未登入'),
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

  group('page', () {
    testWidgets('rows with the summary line; refresh asks again', (
      tester,
    ) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('data')
        ..answer = _rowsAt(now, const [
          Duration(seconds: 5),
          Duration(seconds: 25),
        ]);
      await _pumpPage(tester, api, now);
      expect(find.text('站 80 閘道器 1 最近資料'), findsOneWidget);
      expect(find.byKey(const Key('recent-summary')), findsOneWidget);
      expect(find.text('最近一筆 5 秒前・共 2 筆'), findsOneWidget);
      expect(find.byKey(const Key('recent-list')), findsOneWidget);
      expect(find.text('13:00:05'), findsOneWidget);
      expect(find.text('12:59:45'), findsOneWidget);
      expect(find.text('PTU 9601'), findsOneWidget);
      expect(find.text('PTU 9602'), findsOneWidget);
      expect(find.text('POWER_TRANSFER'), findsOneWidget);
      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('5.00 V・120 mA・31 °C'), findsNWidgets(2));
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

    testWidgets('count 0: the waiting text, refresh then shows rows', (
      tester,
    ) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('empty')
        ..answer = _rowsAt(now, const [Duration(seconds: 2)]);
      await _pumpPage(tester, api, now);
      expect(find.byKey(const Key('recent-empty')), findsOneWidget);
      expect(find.text(recentDataEmptyText), findsOneWidget);
      expect(find.byKey(const Key('recent-list')), findsNothing);
      api.mode = 'data';
      await tester.tap(find.byKey(const Key('recent-empty-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-empty')), findsNothing);
      expect(find.text('最近一筆 2 秒前・共 1 筆'), findsOneWidget);
    });

    testWidgets('error: words and 〔重試〕; retry recovers', (tester) async {
      final now = DateTime(2026, 9, 28, 13, 0, 10);
      final api = _Api('network')
        ..answer = _rowsAt(now, const [Duration(seconds: 2)]);
      await _pumpPage(tester, api, now);
      expect(find.byKey(const Key('recent-error')), findsOneWidget);
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
      expect(find.byKey(const Key('recent-list')), findsOneWidget);
      // An error after data keeps the error on screen (not the old rows).
      api.mode = 'auth';
      await tester.tap(find.byKey(const Key('recent-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-error')), findsOneWidget);
      expect(find.textContaining('尚未登入'), findsOneWidget);
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
      expect(find.text('站 80 閘道器 1 最近資料'), findsOneWidget);
      // The demo backend answers one row per connected PTU.
      expect(find.byKey(const Key('recent-list')), findsOneWidget);
      expect(find.textContaining('共 '), findsOneWidget);
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
