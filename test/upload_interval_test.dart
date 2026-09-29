// 1.0.0+20 (upload interval up to 5 minutes, docs/design/
// upload_interval_5min_2026-09-29.md §4):
// 1. 〔查看上傳資料〕: `upload_interval_ms` of `GET /api/app/recent` (= I)
//    sets the limits — green up to G = max(30, 2·I + 10) s, yellow up to
//    R = max(600, G + 2·I) s, red after; without it (an older back office)
//    30 s / 10 min as before. The empty page names no fixed seconds.
// 2. The data check: build mode on → exactly as before (no fallback, the
//    same window, late limit and budget). Not on → `POST /api/app/build-
//    mode/{site}/{gw}` once per connect: sent → as before; any failure (404
//    of an older back office, no answer, network) → the gateway's own
//    interval (get_config `ds_max_ms`; missing 300000; `ds_enabled` false
//    1000) widens the late limit max(60, 2·I + 10), the window max(180,
//    3·I + 60), 「尚無資料」 and the budget; the pace text follows I.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/application/verify_diagnosis.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/recent_data_api.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';
import 'package:gateway_commissioning/presentation/verify_live_panel.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

const _fallbackPrefix = '/api/app/build-mode/';

const _notFound = GatewayFailure.http(
  status: 404,
  endpoint: 'POST /api/app/build-mode/1/1',
  detail: 'Not Found',
);

/// A new gateway (star) whose get_config reports the ds_* keys as given;
/// [rejectBuild]: it refuses the build-mode set_config (`3 rejected`), so
/// build mode does not take. Records the fallback calls, the
/// verify-installation paths and the /api/latest polls; the latest rows
/// can be [frozen] (never a new time) or [lag] seconds late.
class _Gw extends PickGateway {
  _Gw({
    int? min = 5000,
    int? max = 5000,
    Object? enabled = true,
    this.rejectBuild = false,
  }) {
    config['fleet_joined'] = false;
    for (final key in ['ds_min_ms', 'ds_max_ms', 'ds_enabled']) {
      config.remove(key);
    }
    if (min != null) config['ds_min_ms'] = min;
    if (max != null) config['ds_max_ms'] = max;
    if (enabled != null) config['ds_enabled'] = enabled;
  }

  final bool rejectBuild;

  /// The fallback throws this when set, else answers [fallbackAnswer]
  /// (default: the demo's `{sent: true}`); waits for [fallbackGate] first.
  Object? fallbackError;
  Map<String, dynamic>? fallbackAnswer;
  Completer<void>? fallbackGate;

  /// Each /api/latest waits for it when set.
  Completer<void>? latestGate;
  bool frozen = false;
  num lag = 0;

  final fallbackCalls = <(String, String, Map<String, dynamic>?)>[];
  final installPaths = <String>[];
  int latestPolls = 0;

  List<Map<String, dynamic>> get buildSends => [
    for (final p in sent('set_config'))
      if (p.containsKey('ds_min_ms')) p,
  ];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (rejectBuild && op == 'set_config' && params.containsKey('ds_min_ms')) {
      ops.add((op, Map.of(params)));
      return {'message': 'config updated: 0 params changed, 3 rejected'};
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.startsWith(_fallbackPrefix)) {
      fallbackCalls.add((method, path, body));
      if (fallbackGate != null) await fallbackGate!.future;
      final error = fallbackError;
      if (error != null) throw error;
      final answer = fallbackAnswer;
      if (answer != null) return answer;
      return super.request(method, path, body);
    }
    if (path.contains('verify-installation')) installPaths.add(path);
    if (path.startsWith('/api/latest')) {
      latestPolls++;
      if (latestGate != null) await latestGate!.future;
      final result = await super.request(method, path, body);
      return {
        'items': [
          for (final raw in result['items'] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              'lag_seconds': lag,
              if (frozen) 'ts': DateTime(2030).toIso8601String(),
            },
        ],
      };
    }
    return super.request(method, path, body);
  }
}

/// Star, logged in: a new gateway commissioned as 1/1, on the data check
/// (step 6), not started.
Future<(ProviderContainer, CommissioningController)> _toVerify(_Gw fake) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.star);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: false);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'test-network', 'password123');
  await c.online();
  await c.discover();
  await c.configurePtus();
  expect(container.read(commissionProvider).step, 6);
  return (container, c);
}

Future<void> _verify(CommissioningController c) =>
    c.verify('https://example.invalid', '');

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue);
}

RecentData _recent(Duration age, DateTime now, {Object? interval = _none}) =>
    RecentData.fromJson({
      'count': 1,
      'items': [
        {'ts': now.subtract(age).toIso8601String(), 'device_id': 1},
      ],
      if (!identical(interval, _none)) 'upload_interval_ms': interval,
    });

const _none = Object();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepGap, keepBackendGap, keepFallbackTimeout;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    keepPoll = directPollInterval;
    keepGap = connectRetryGap;
    keepBackendGap = backendRetryGap;
    keepFallbackTimeout = buildModeFallbackTimeout;
    directPollInterval = const Duration(milliseconds: 1);
    connectRetryGap = const Duration(milliseconds: 1);
    backendRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    connectRetryGap = keepGap;
    backendRetryGap = keepBackendGap;
    buildModeFallbackTimeout = keepFallbackTimeout;
  });

  group('查看上傳資料: the limits follow upload_interval_ms', () {
    final now = DateTime(2026, 9, 29, 22, 0);
    RecentBannerKind kind(int seconds, {Object? interval = _none}) =>
        recentBanner(
          _recent(Duration(seconds: seconds), now, interval: interval),
          now,
        ).kind;

    test('no field (an older back office): 30 s / 10 min as before', () {
      expect(kind(29), RecentBannerKind.ok);
      expect(kind(30), RecentBannerKind.stale);
      expect(kind(31), RecentBannerKind.stale);
      expect(kind(599), RecentBannerKind.stale);
      expect(kind(600), RecentBannerKind.stopped);
      expect(kind(601), RecentBannerKind.stopped);
      for (final bad in <Object?>[null, '300000', 0, -5]) {
        expect(kind(29, interval: bad), RecentBannerKind.ok, reason: '$bad');
        expect(kind(31, interval: bad), RecentBannerKind.stale);
        expect(kind(601, interval: bad), RecentBannerKind.stopped);
      }
    });

    test('I = 300000: green to 610 s, yellow to 1210 s, then red', () {
      const i = 300000;
      expect(recentGreenAge(i), const Duration(seconds: 610));
      expect(recentRedAge(i), const Duration(seconds: 1210));
      expect(kind(0, interval: i), RecentBannerKind.ok);
      expect(kind(600, interval: i), RecentBannerKind.ok);
      expect(kind(610, interval: i), RecentBannerKind.ok);
      expect(kind(611, interval: i), RecentBannerKind.stale);
      expect(kind(1210, interval: i), RecentBannerKind.stale);
      expect(kind(1211, interval: i), RecentBannerKind.stopped);
      expect(
        recentBanner(
          _recent(const Duration(seconds: 700), now, interval: i),
          now,
        ).text,
        '最近 11 分鐘沒有新資料',
      );
    });

    test('I = 5000 (today\'s policy): as before', () {
      const i = 5000;
      expect(recentGreenAge(i), recentFreshAge);
      expect(recentRedAge(i), recentStoppedAge);
      expect(kind(29, interval: i), RecentBannerKind.ok);
      expect(kind(31, interval: i), RecentBannerKind.stale);
      expect(kind(599, interval: i), RecentBannerKind.stale);
      expect(kind(601, interval: i), RecentBannerKind.stopped);
      // A double is read as a whole number of ms.
      expect(kind(31, interval: 5000.0), RecentBannerKind.stale);
    });

    test('I = 60000: green to 130 s, yellow to 10 min', () {
      expect(kind(130, interval: 60000), RecentBannerKind.ok);
      expect(kind(131, interval: 60000), RecentBannerKind.stale);
      expect(kind(600, interval: 60000), RecentBannerKind.stale);
      expect(kind(601, interval: 60000), RecentBannerKind.stopped);
    });

    test('RecentData reads upload_interval_ms (null when missing or not a '
        'positive number)', () {
      RecentData parse(Object? v, {bool present = true}) => RecentData.fromJson(
        {'count': 0, 'items': [], if (present) 'upload_interval_ms': v},
      );
      expect(parse(300000).uploadIntervalMs, 300000);
      expect(parse(5000.0).uploadIntervalMs, 5000);
      expect(parse(null).uploadIntervalMs, isNull);
      expect(parse(0).uploadIntervalMs, isNull);
      expect(parse('5000').uploadIntervalMs, isNull);
      expect(parse(null, present: false).uploadIntervalMs, isNull);
    });

    test('the empty page names no fixed seconds; with I it says how often', () {
      expect(recentDataEmptyText, isNot(contains('20 秒')));
      expect(recentDataEmptyText, isNot(matches(RegExp(r'\d'))));
      expect(recentEmptyText(null), recentDataEmptyText);
      expect(recentEmptyText(300000), '後台尚未收到這台閘道器的資料；閘道器約每 5 分鐘上傳一筆，請稍後再重新整理');
      expect(recentEmptyText(5000), contains('約每 5 秒上傳一筆'));
      final empty = RecentData.fromJson({
        'count': 0,
        'items': [],
        'upload_interval_ms': 120000,
      });
      expect(
        recentBanner(empty, now),
        RecentBanner(RecentBannerKind.empty, recentEmptyText(120000)),
      );
      for (final t in [recentEmptyText(null), recentEmptyText(300000)]) {
        expect(t, isNot(contains('Gateway')));
        expect(t, isNot(contains('客戶')));
      }
    });

    test('intervalWords: whole minutes in minutes, else seconds', () {
      expect(intervalWords(300000), '5 分鐘');
      expect(intervalWords(60000), '1 分鐘');
      expect(intervalWords(90000), '90 秒');
      expect(intervalWords(30000), '30 秒');
      expect(intervalWords(1000), '1 秒');
      expect(intervalWords(1500), '1.5 秒');
      expect(intervalWords(900000), '15 分鐘');
    });

    testWidgets('page: 5-minute interval, 11 minutes old → yellow; the demo '
        'back office sends its interval', (tester) async {
      final demo = await DemoSystem().request('GET', '/api/app/recent/1/1');
      expect(demo['upload_interval_ms'], 5000);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(
              _RecentApi({
                'site_id': 81,
                'gateway_id': 1,
                'count': 1,
                'upload_interval_ms': 300000,
                'items': [
                  {
                    'ts': now
                        .subtract(const Duration(seconds: 660))
                        .toIso8601String(),
                    'device_id': 1,
                    'ptu_mac': '90:5F:E8:9A:96:00',
                    'ptu_state': 'POWER_SAVE',
                  },
                ],
              }),
            ),
          ],
          child: MaterialApp(
            home: RecentDataPage(site: 81, gateway: 1, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-banner-stale')), findsOneWidget);
      expect(find.text('最近 11 分鐘沒有新資料'), findsOneWidget);
    });

    testWidgets('page: empty with an interval says it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(
              _RecentApi({
                'site_id': 81,
                'gateway_id': 1,
                'count': 0,
                'items': [],
                'upload_interval_ms': 300000,
              }),
            ),
          ],
          child: MaterialApp(
            home: RecentDataPage(site: 81, gateway: 1, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-empty')), findsOneWidget);
      expect(find.text(recentEmptyText(300000)), findsOneWidget);
    });
  });

  group('data check limits (pure)', () {
    test('the gateway\'s interval from get_config', () {
      expect(
        verifyIntervalOf({'ds_enabled': true, 'ds_max_ms': 300000}),
        300000,
      );
      expect(verifyIntervalOf({'ds_enabled': true, 'ds_max_ms': 5000}), 5000);
      expect(verifyIntervalOf({'ds_max_ms': 60000}), 60000);
      expect(verifyIntervalOf({'ds_max_ms': 60000.0}), 60000);
      // Missing: 5 minutes.
      expect(verifyIntervalOf({}), 300000);
      expect(verifyIntervalOf({'ds_enabled': true}), 300000);
      expect(verifyIntervalOf({'ds_max_ms': 'x'}), 300000);
      expect(verifyIntervalOf({'ds_max_ms': 0}), 300000);
      // Down-sampling off: every reading.
      expect(
        verifyIntervalOf({'ds_enabled': false, 'ds_max_ms': 300000}),
        1000,
      );
      expect(verifyIntervalOf({'ds_enabled': 0}), 1000);
      // Kept within 1 s – 5 min.
      expect(verifyIntervalOf({'ds_max_ms': 900000}), 300000);
      expect(verifyIntervalOf({'ds_max_ms': 200}), 1000);
    });

    test('null (build mode on): the +19 numbers', () {
      expect(verifyLagLimitFor(null), 60);
      expect(verifyWindowFor(null), 180);
      expect(verifyIdleLimitFor(null), verifyIdleLimit);
      expect(verifyIdleLimitFor(null), 60);
      expect(verifyInstallMinutesFor(null), 2);
      expect(
        verifyRunSecondsFor(null),
        180 + backendRetryWindow.inSeconds + 40,
      );
    });

    test('I = 300000: late limit 610 s, window 960 s, idle 610 s, '
        'verify-installation 11 minutes, budget +780 s', () {
      expect(verifyLagLimitFor(300000), 610);
      expect(verifyWindowFor(300000), 960);
      expect(verifyIdleLimitFor(300000), 610);
      expect(verifyInstallMinutesFor(300000), 11);
      expect(
        verifyRunSecondsFor(300000) - verifyRunSecondsFor(null),
        960 - 180,
      );
    });

    test('up to 10 s (and 1 s): the same numbers as build mode', () {
      for (final i in [1000, 5000, 10000]) {
        expect(verifyLagLimitFor(i), 60, reason: '$i');
        expect(verifyWindowFor(i), 180);
        expect(verifyIdleLimitFor(i), 60);
        expect(verifyInstallMinutesFor(i), 2);
        expect(verifyRunSecondsFor(i), verifyRunSecondsFor(null));
        expect(verifyPaceTextFor(i), verifyPaceText);
        expect(verifyFooterText(266, intervalMs: i), verifyFooterText(266));
      }
      // 60 s: max(60, 130), max(180, 240).
      expect(verifyLagLimitFor(60000), 130);
      expect(verifyWindowFor(60000), 240);
    });

    test('verifyTally counts a row under the late limit given', () {
      final stamp = DateTime(2030).toIso8601String();
      Map<int, int> tally(num lag, {int? limit}) {
        final counts = <int, int>{};
        final rows = [
          {
            'device_id': 1,
            'online': true,
            'lag_seconds': lag,
            'error_num': 0,
            'ts': stamp,
          },
        ];
        if (limit == null) {
          verifyTally(
            ids: [1],
            rows: rows,
            previous: {},
            counts: counts,
            lastNew: {},
            elapsed: 0,
          );
        } else {
          verifyTally(
            ids: [1],
            rows: rows,
            previous: {},
            counts: counts,
            lastNew: {},
            elapsed: 0,
            lagLimit: limit,
          );
        }
        return counts;
      }

      expect(tally(59), {1: 1});
      expect(tally(60), isEmpty, reason: 'as before');
      expect(tally(600), isEmpty, reason: 'as before');
      expect(tally(600, limit: 610), {1: 1});
      expect(tally(609, limit: 610), {1: 1});
      expect(tally(610, limit: 610), isEmpty);
    });

    test('backendRowsFresh and the reasons follow the same limit', () {
      final rows = [
        {'online': true, 'lag_seconds': 300},
      ];
      expect(backendRowsFresh(rows), isFalse);
      expect(backendRowsFresh(rows, lagLimit: 610), isTrue);
      final row = {
        'online': true,
        'lag_seconds': 300,
        'error_num': 0,
        'ts': DateTime(2030).toIso8601String(),
      };
      expect(ptuVerifyReasons(latest: row), ['延遲 300 秒']);
      expect(ptuVerifyReasons(latest: row, lagLimit: 610), isEmpty);
    });

    test('pace text: 5 minutes, spoken, no Gateway / 客戶', () {
      expect(verifyPaceTextFor(null), verifyPaceText);
      expect(verifyPaceText, '約每 10 秒收一筆，通常 30 秒內完成');
      expect(verifyPaceTextFor(300000), '約每 5 分鐘收一筆，通常 15 分鐘內完成');
      expect(verifyPaceTextFor(20000), '約每 20 秒收一筆，通常 1 分鐘內完成');
      expect(
        verifyFooterText(1043, intervalMs: 300000),
        '約每 5 分鐘收一筆，通常 15 分鐘內完成・剩餘 1043 秒',
      );
      for (final i in [null, 20000, 300000]) {
        expect(verifyPaceTextFor(i), isNot(contains('Gateway')));
        expect(verifyPaceTextFor(i), isNot(contains('客戶')));
      }
    });
  });

  group('data check: build mode on → as before', () {
    test('no fallback, the +19 window and verify-installation', () async {
      final fake = _Gw();
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).buildMode, BuildModeStatus.on);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(fake.fallbackCalls, isEmpty);
      expect(s.verifyIntervalMs, isNull);
      expect(fake.installPaths, isNotEmpty);
      for (final p in fake.installPaths) {
        expect(p, contains('threshold_minutes=2&'));
      }
    });

    test('rows that stop: the check ends after the same 18 polls', () async {
      final fake = _Gw()..frozen = true;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.verified, isFalse);
      expect(s.error, isNotNull);
      expect(fake.latestPolls, 180 ~/ verifyPollSeconds);
      expect(fake.fallbackCalls, isEmpty);
    });

    test('a row 600 s late is still not counted', () async {
      final fake = _Gw()..lag = 600;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.verified, isFalse);
      expect(fake.latestPolls, 18);
    });
  });

  group('data check: build mode not on', () {
    test('the fallback sends it: once, no body, taken as on, the window '
        'as before', () async {
      final fake = _Gw(max: 300000, rejectBuild: true)..frozen = true;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      expect(
        container.read(commissionProvider).buildMode,
        BuildModeStatus.rejected,
      );
      await _verify(c);
      var s = container.read(commissionProvider);
      expect(fake.fallbackCalls, [('POST', '/api/app/build-mode/1/1', null)]);
      // What the connect did stays; the fallback is recorded apart.
      expect(s.buildMode, BuildModeStatus.rejected);
      expect(s.buildModeFallback, BuildModeFallback.sent);
      expect(buildModeTook(s), isTrue);
      expect(s.verifyIntervalMs, isNull);
      expect(fake.latestPolls, 18, reason: 'the 180 s window');
      for (final p in fake.installPaths) {
        expect(p, contains('threshold_minutes=2&'));
      }
      final diag = diagnosticSections(s, now: DateTime(2026, 9, 29));
      expect((diag['gateway'] as Map)['build_mode'], 'rejected');
      expect((diag['gateway'] as Map)['build_mode_fallback'], 'sent');
      expect((diag['gateway'] as Map)['verify_interval_ms'], isNull);
      // 〔重試〕 in the same connect: not asked again.
      fake.frozen = false;
      await _verify(c);
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(fake.fallbackCalls, hasLength(1));
    });

    test('the fallback sends it, the data flows: passed as before', () async {
      final fake = _Gw(rejectBuild: true);
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(fake.fallbackCalls, hasLength(1));
    });

    test('404 (an older back office), ds_max_ms 300000: window 960 s, late '
        'limit 610 s, verify-installation 11 minutes', () async {
      final fake = _Gw(max: 300000, rejectBuild: true)
        ..fallbackError = _notFound
        ..frozen = true;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.verified, isFalse);
      expect(s.buildMode, BuildModeStatus.rejected);
      expect(s.buildModeFallback, BuildModeFallback.failed);
      expect(buildModeTook(s), isFalse);
      expect(s.verifyIntervalMs, 300000);
      expect(fake.latestPolls, 960 ~/ verifyPollSeconds);
      expect(fake.installPaths, isNotEmpty);
      for (final p in fake.installPaths) {
        expect(p, contains('threshold_minutes=11&'));
      }
      final diag = diagnosticSections(s, now: DateTime(2026, 9, 29));
      expect((diag['gateway'] as Map)['build_mode_fallback'], 'failed');
      expect((diag['gateway'] as Map)['verify_interval_ms'], 300000);
      // 〔重試〕 in the same connect: not asked again, the same pace.
      final polls = fake.latestPolls;
      await _verify(c);
      expect(fake.fallbackCalls, hasLength(1));
      expect(container.read(commissionProvider).verifyIntervalMs, 300000);
      expect(fake.latestPolls - polls, 96);
    });

    test(
      '404, ds_max_ms 300000: a row 600 s late counts (610 s limit)',
      () async {
        final fake = _Gw(max: 300000, rejectBuild: true)
          ..fallbackError = _notFound
          ..lag = 600;
        final (container, c) = await _toVerify(fake);
        addTearDown(container.dispose);
        await _verify(c);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 7);
        expect(s.verified, isTrue);
      },
    );

    test('404, ds_max_ms 300000: a row 610 s late does not', () async {
      final fake = _Gw(max: 300000, rejectBuild: true)
        ..fallbackError = _notFound
        ..lag = 610;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.verified, isFalse);
      expect(fake.latestPolls, 96);
    });

    test(
      '404, ds_max_ms 5000: as before (18 polls, 60 s limit, 2 minutes)',
      () async {
        final fake = _Gw(rejectBuild: true)
          ..fallbackError = _notFound
          ..lag = 60;
        final (container, c) = await _toVerify(fake);
        addTearDown(container.dispose);
        await _verify(c);
        final s = container.read(commissionProvider);
        expect(s.step, 6);
        expect(s.verified, isFalse);
        expect(s.verifyIntervalMs, 5000);
        expect(fake.latestPolls, 18);
        for (final p in fake.installPaths) {
          expect(p, contains('threshold_minutes=2&'));
        }
        expect(
          verifyFooterText(100, intervalMs: s.verifyIntervalMs),
          verifyFooterText(100),
        );
      },
    );

    test('404, no ds_* at all (older firmware): 5 minutes assumed', () async {
      final fake = _Gw(min: null, max: null, enabled: null)
        ..fallbackError = _notFound
        ..frozen = true;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      expect(fake.buildSends, isEmpty);
      expect(container.read(commissionProvider).buildMode, BuildModeStatus.off);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(fake.fallbackCalls, hasLength(1));
      expect(s.verifyIntervalMs, 300000);
      expect(fake.latestPolls, 96);
    });

    test('404, ds_enabled false: every reading (as before)', () async {
      final fake = _Gw(max: 300000, enabled: false, rejectBuild: true)
        ..fallbackError = _notFound
        ..frozen = true;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.verifyIntervalMs, 1000);
      expect(fake.latestPolls, 18);
    });

    for (final (name, error) in [
      ('no connection', const GatewayFailure('network', detail: '逾時')),
      ('the gateway offline (409)', const GatewayFailure('conflict')),
      (
        'throttled (429)',
        const GatewayFailure.http(
          status: 429,
          endpoint: 'POST /api/app/build-mode/1/1',
          detail: 'too many',
        ),
      ),
    ]) {
      test(
        '$name: never an error of the step, the data check goes on',
        () async {
          final fake = _Gw(max: 300000, rejectBuild: true)
            ..fallbackError = error;
          final (container, c) = await _toVerify(fake);
          addTearDown(container.dispose);
          await _verify(c);
          final s = container.read(commissionProvider);
          expect(s.error, isNull);
          expect(s.step, 7);
          expect(s.verifyIntervalMs, 300000);
          expect(fake.fallbackCalls, hasLength(1));
        },
      );
    }

    test('an answer without sent: true is a failure', () async {
      final fake = _Gw(max: 300000, rejectBuild: true)
        ..fallbackAnswer = {'success': true};
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.buildModeFallback, BuildModeFallback.failed);
      expect(s.verifyIntervalMs, 300000);
      expect(buildModeFallbackSent({'sent': true, 'req_id': 'x'}), isTrue);
      expect(buildModeFallbackSent({'sent': false}), isFalse);
      expect(buildModeFallbackSent({}), isFalse);
    });

    test(
      'no answer within the time given: a failure, the check goes on',
      () async {
        buildModeFallbackTimeout = const Duration(milliseconds: 40);
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final fake = _Gw(max: 300000, rejectBuild: true)..fallbackGate = gate;
        final (container, c) = await _toVerify(fake);
        addTearDown(container.dispose);
        await _verify(c);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 7);
        expect(s.verifyIntervalMs, 300000);
      },
    );

    test('the countdown: 280 s until the answer, then the 5-minute budget; '
        'the pace text follows', () async {
      final gate = Completer<void>();
      final fake = _Gw(max: 300000, rejectBuild: true)..fallbackGate = gate;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      final run = _verify(c);
      await _until(() => fake.fallbackCalls.isNotEmpty);
      var s = container.read(commissionProvider);
      expect(s.busy, isTrue);
      expect(s.verifyIntervalMs, isNull);
      expect(s.seconds, inInclusiveRange(275, verifyRunSecondsFor(null)));
      fake
        ..fallbackError = _notFound
        ..latestGate = Completer<void>();
      gate.complete();
      await _until(() => fake.latestPolls > 0);
      s = container.read(commissionProvider);
      expect(s.verifyIntervalMs, 300000);
      expect(
        s.seconds,
        inInclusiveRange(
          verifyRunSecondsFor(300000) - 5,
          verifyRunSecondsFor(300000),
        ),
      );
      expect(
        verifyFooterText(s.seconds, intervalMs: s.verifyIntervalMs),
        startsWith('約每 5 分鐘收一筆，通常 15 分鐘內完成・剩餘 '),
      );
      fake.latestGate!.complete();
      await run;
      expect(container.read(commissionProvider).step, 7);
    });

    test('a new connect asks again (one fallback per connect)', () async {
      final fake = _Gw(max: 300000, rejectBuild: true)
        ..fallbackError = _notFound;
      final (container, c) = await _toVerify(fake);
      addTearDown(container.dispose);
      await _verify(c);
      expect(container.read(commissionProvider).step, 7);
      expect(fake.fallbackCalls, hasLength(1));
      await c.finishDone(next: true);
      // 〔配置下一台〕: the next gateway on the bench, factory 1/1.
      fake.config.addAll({
        'site_id': 1,
        'gateway_id': 1,
        'fleet_joined': false,
        'gateway_uid': 'A0DD6CA370F0',
      });
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      var s = container.read(commissionProvider);
      expect(s.verifyIntervalMs, isNull, reason: 'reset by the connect');
      expect(s.buildModeFallback, BuildModeFallback.none);
      expect(s.buildMode, BuildModeStatus.rejected);
      await c.configureWifi(1, 1, 'test-network', 'password123');
      await c.online();
      await c.discover();
      await c.configurePtus();
      expect(container.read(commissionProvider).step, 6);
      await _verify(c);
      s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(fake.fallbackCalls, hasLength(2));
      expect(s.verifyIntervalMs, 300000);
    });

    test('the demo (no ds_*): the demo back office sends it, the check as '
        'before', () async {
      final fake = PickGateway()..config['fleet_joined'] = false;
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final topo = container.read(topologyProvider.notifier);
      await topo.ready;
      await topo.setTopology(GatewayTopology.star);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: false);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.configureWifi(1, 1, 'test-network', 'password123');
      await c.online();
      await c.discover();
      await c.configurePtus();
      await _verify(c);
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.buildMode, BuildModeStatus.off);
      expect(s.buildModeFallback, BuildModeFallback.sent);
      expect(s.verifyIntervalMs, isNull);
    });
  });
}

/// The back office for the recent-data page: one fixed answer.
class _RecentApi implements GatewayApi {
  _RecentApi(this.answer);
  final Map<String, dynamic> answer;

  @override
  Future<void> login(String base, String password) async {}

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async => answer;
}
