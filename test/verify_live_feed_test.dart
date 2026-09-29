// 1.0.0+18 (phone: 「等待期間畫面幾乎不動」): step 9's live data flow on
// the page — 「PTU ──●──▶ 閘道器 ──●──▶ 後台」 (a dot and a selection click
// per poll that brought new rows), under each PTU its last rows (data
// time, V / A / °C, lag, 「第 k 筆」 or, red, why not), the card green with
// 「資料正常上傳」 once passed, and the plain-words copy. Presentation only:
// the verification's polls, counts and result are unchanged, and no
// other back-office call is made.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/verify_feed.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/data/recent_data_api.dart';
import 'package:gateway_commissioning/presentation/verify_live_panel.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp, ready;

/// /api/latest rows with PTU values (the back office's `ptu` block);
/// polls in [lateAt] answer a lag of 75 s, in [errorAt] error_num 3. Poll
/// [holdAt] waits for [hold]; with [holdConfirm], the read-back after the
/// data passed (get_config once 3 polls are in) waits for it.
class _Scripted extends DroppingLink {
  _Scripted({
    this.lateAt = const {},
    this.errorAt = const {},
    this.values = true,
    this.holdAt,
    this.holdConfirm = false,
  });

  final Set<int> lateAt, errorAt;
  final bool values;
  final int? holdAt;
  final bool holdConfirm;
  final hold = Completer<void>();
  bool held = false;
  int latestCalls = 0;
  final paths = <String>[];

  /// The `ts` each poll served, per PTU number.
  final served = <int, Map<int, String>>{};

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add(path);
    final result = await super.request(method, path, body);
    if (!path.startsWith('/api/latest')) return result;
    final n = ++latestCalls;
    if (n == holdAt) {
      held = true;
      await hold.future;
      held = false;
    }
    final items = [
      for (final raw in result['items'] as List)
        <String, dynamic>{
          ...Map<String, dynamic>.from(raw as Map),
          'ptu': {
            ...Map<String, dynamic>.from(raw['ptu'] as Map),
            if (values) ...{
              'ptu_inputVoltage_mV': 53200,
              'ptu_inputCurrent_mA': 2720,
              'ptu_ampTemp_degC': 36,
            },
          },
          'lag_seconds': lateAt.contains(n) ? 75 : 1,
          'error_num': errorAt.contains(n) ? 3 : 0,
        },
    ];
    served[n] = {
      for (final i in items) i['device_id'] as int: i['ts'] as String,
    };
    return {'items': items};
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (holdConfirm && op == 'get_config' && latestCalls >= 3) {
      held = true;
      await hold.future;
      held = false;
    }
    return super.command(op, params);
  }
}

/// A /api/latest row of PTU #[id] at [ts].
Map<String, dynamic> _row(
  int id,
  String ts, {
  num lag = 1,
  Object? error = 0,
  bool online = true,
  bool values = true,
}) => {
  'device_id': id,
  'ts': ts,
  'online': online,
  'lag_seconds': lag,
  'error_num': error,
  'ptu': {
    'ptu_mac_addr': 'AA:BB:CC:00:00:0$id',
    if (values) ...{
      'ptu_inputVoltage_mV': 53200,
      'ptu_inputCurrent_mA': 2720,
      'ptu_ampTemp_degC': 36,
    },
  },
};

/// One poll through [verifyTally] and [verifyFeedAfterPoll], as the
/// controller runs them.
List<VerifyFeedEntry> _poll(
  List<VerifyFeedEntry> feed,
  List<Map<String, dynamic>> rows, {
  required Map<int, DateTime> previous,
  required Map<int, int> counts,
  Iterable<int> ids = const [1],
  int elapsed = 0,
}) {
  final before = Map<int, DateTime>.of(previous);
  final countsBefore = Map<int, int>.of(counts);
  verifyTally(
    ids: ids,
    rows: rows,
    previous: previous,
    counts: counts,
    lastNew: {},
    elapsed: elapsed,
  );
  return verifyFeedAfterPoll(
    feed: feed,
    ids: ids,
    rows: rows,
    before: before,
    countsBefore: countsBefore,
    countsAfter: counts,
    macs: {for (final id in ids) id: 'AA:BB:CC:00:00:0$id'},
  );
}

String _ts(int second) =>
    DateTime.utc(2030, 1, 1, 4, 0, second).toIso8601String();

VerifyFeedEntry _entry(
  int serial, {
  int id = 1,
  bool ok = true,
  int count = 1,
  List<String> reasons = const [],
}) => VerifyFeedEntry(
  serial: serial,
  poll: serial,
  id: id,
  ts: DateTime(2030, 1, 1, 12, 0, serial),
  inputMv: 53200,
  inputMa: 2720,
  tempC: 36,
  lag: 1,
  ok: ok,
  counted: ok,
  count: count,
  reasons: reasons,
);

/// Records the platform channel (the selection click).
List<MethodCall> _platformCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

int _clicks(List<MethodCall> calls) => calls
    .where(
      (c) =>
          c.method == 'HapticFeedback.vibrate' &&
          c.arguments == 'HapticFeedbackType.selectionClick',
    )
    .length;

/// The dots on the flow's links now (null: none).
List<double?> _dots(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byKey(const Key('verify-flow')),
      matching: find.byType(CustomPaint),
    ),
  ))
    if (paint.painter case final VerifyFlowLinkPainter p) p.progress,
];

String? _text(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  return null;
}

/// The texts under [key], in order, joined with [separator].
String _joined(WidgetTester tester, Key key, [String separator = '']) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    )
    .map((t) => t.data)
    .join(separator);

/// The page at step 9 (offline, so nothing starts by itself).
Future<(ProviderContainer, CommissioningController)> _pageAtStep9(
  WidgetTester tester,
  _Scripted fake,
) async {
  final container = await pumpApp(tester, fake);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await tester.runAsync(() => c.configureWifi(1, 1, 'Office-2G', 'pw123456'));
  await c.online(skip: true);
  await c.discover();
  await tester.runAsync(c.configurePtus);
  await tester.pumpAndSettle();
  expect(container.read(commissionProvider).step, 6);
  return (container, c);
}

/// Starts the verification and lets it run (real time) until [until].
Future<({Future<void> run})> _verifyUntil(
  WidgetTester tester,
  CommissioningController c,
  bool Function() until,
) async {
  late Future<void> run;
  await tester.runAsync(() async {
    run = c.verify(productionApiBase, 'pw');
    for (var i = 0; i < 400 && !until(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
  await tester.pump();
  return (run: run);
}

/// Lets the held verification finish.
Future<void> _finish(
  WidgetTester tester,
  _Scripted fake,
  Future<void> run,
) async {
  fake.hold.complete();
  await tester.runAsync(() => run);
  await tester.pumpAndSettle();
}

void main() {
  group('1. the feed of one poll (pure)', () {
    test('a new row adds one entry: data time, V / A / °C, lag, 第 1 筆', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      final feed = _poll(
        const [],
        [_row(1, _ts(3))],
        previous: previous,
        counts: counts,
      );
      expect(feed, hasLength(1));
      final e = feed.single;
      expect(e.id, 1);
      expect(e.ok, isTrue);
      expect(e.counted, isTrue);
      expect(e.count, 1);
      expect(e.restart, isFalse);
      // The row's own time, local, as HH:mm:ss.
      expect(e.ts, DateTime.parse(_ts(3)).toLocal());
      expect(recentClockText(e.ts), matches(RegExp(r'^\d\d:\d\d:03$')));
      expect(verifyFeedCountText(e), '第 1 筆');
      expect(verifyFeedValuesText(e), '53.2 V・2.72 A・36 °C・落後 1 秒');
      expect(verifyFeedAnnounce(e, ptus: 1), '收到第 1 筆');
      expect(verifyFeedAnnounce(e, ptus: 3), 'PTU #1 收到第 1 筆');
    });

    test('the same row again adds nothing; at most 5 per PTU, newest '
        'first; at 3/3 a good row reads 正常（已滿 3 筆）', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      var feed = <VerifyFeedEntry>[];
      feed = _poll(feed, [_row(1, _ts(1))], previous: previous, counts: counts);
      feed = _poll(feed, [_row(1, _ts(1))], previous: previous, counts: counts);
      expect(feed, hasLength(1));
      for (var s = 2; s <= 7; s++) {
        feed = _poll(
          feed,
          [_row(1, _ts(s))],
          previous: previous,
          counts: counts,
        );
      }
      expect(feed, hasLength(verifyFeedPerPtu));
      expect(verifyFeedPerPtu, 5);
      // Newest first.
      expect(feed.map((e) => e.ts), [
        for (var s = 7; s >= 3; s--) DateTime.parse(_ts(s)).toLocal(),
      ]);
      expect(feed.last.count, 3);
      expect(verifyFeedCountText(feed.last), '第 3 筆');
      expect(feed.first.counted, isFalse);
      expect(feed.first.ok, isTrue);
      expect(verifyFeedCountText(feed.first), '正常（已滿 3 筆）');
    });

    test('several PTUs: each keeps its own 5', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      var feed = <VerifyFeedEntry>[];
      for (var s = 1; s <= 6; s++) {
        feed = _poll(
          feed,
          [_row(1, _ts(s)), _row(2, _ts(s))],
          previous: previous,
          counts: counts,
          ids: const [1, 2],
        );
      }
      expect(feed.where((e) => e.id == 1), hasLength(5));
      expect(feed.where((e) => e.id == 2), hasLength(5));
      expect(verifyFeedNewest(feed)!.id, 2);
    });

    test('a late, erroring or offline row: not counted, red with the '
        'verification\'s own reason, the count kept', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      var feed = _poll(
        const [],
        [_row(1, _ts(1))],
        previous: previous,
        counts: counts,
      );
      feed = _poll(
        feed,
        [_row(1, _ts(2), lag: 75)],
        previous: previous,
        counts: counts,
      );
      final late = feed.first;
      expect(late.ok, isFalse);
      expect(late.count, 1);
      expect(counts[1], 1);
      expect(late.reasons, ['延遲 75 秒']);
      expect(verifyFeedCountText(late), '未計入（維持 1/3）');
      expect(verifyFeedReasonText(late), '原因：延遲 75 秒');
      expect(verifyFeedAnnounce(late, ptus: 1), '資料未計入：延遲 75 秒');

      feed = _poll(
        feed,
        [_row(1, _ts(3), error: 3)],
        previous: previous,
        counts: counts,
      );
      expect(feed.first.reasons, ['error_num=3']);
      feed = _poll(
        feed,
        [_row(1, _ts(4), online: false)],
        previous: previous,
        counts: counts,
      );
      expect(feed.first.reasons, ['離線']);
      expect(feed.first.count, 1);
      // The next good row counts on from there (cumulative, round 10).
      feed = _poll(feed, [_row(1, _ts(5))], previous: previous, counts: counts);
      expect(feed.first.ok, isTrue);
      expect(verifyFeedCountText(feed.first), '第 2 筆');
    });

    test('agrees with verifyTally: a row is good exactly when it counted', () {
      final rows = [
        _row(1, _ts(1)),
        _row(1, _ts(2), lag: 60),
        _row(1, _ts(3), lag: 59),
        _row(1, _ts(4), error: null),
        _row(1, _ts(5), online: false),
        _row(1, _ts(5)),
        _row(1, _ts(6)),
      ];
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      var feed = <VerifyFeedEntry>[];
      var entries = 0;
      for (final row in rows) {
        final was = counts[1] ?? 0;
        final newestBefore = verifyFeedNewest(feed)?.serial ?? 0;
        feed = _poll(feed, [row], previous: previous, counts: counts);
        final counted = (counts[1] ?? 0) > was;
        final newest = verifyFeedNewest(feed)!;
        if (newest.serial == newestBefore) {
          // Not a new row: nothing shown, nothing counted.
          expect(counted, isFalse, reason: '$row');
          continue;
        }
        entries++;
        expect(newest.counted, counted, reason: '$row');
        expect(newest.ok, counted || was >= 3, reason: '$row');
      }
      expect(entries, 6);
      expect(counts[1], 3);
    });

    test('a new verification: the rows before are dimmed and never '
        'announced; its first count reads 重新計數：第 1/3 筆', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      var feed = _poll(
        const [],
        [_row(1, _ts(1))],
        previous: previous,
        counts: counts,
      );
      feed = _poll(feed, [_row(1, _ts(2))], previous: previous, counts: counts);
      // 「開始資料驗證」 again: counts from 0 (not a continued one).
      feed = verifyFeedForRun(feed, {1: 'aa-bb-cc-00-00-01'});
      expect(feed.every((e) => e.earlier), isTrue);
      expect(verifyFeedNewest(feed), isNull);
      expect(
        verifyLiveText(busy: true, passed: false, feed: feed, ptus: 1),
        verifyWaitingFirstText,
      );
      // Another PTU under number 1: its old rows go.
      expect(verifyFeedForRun(feed, {1: 'AA:BB:CC:00:00:09'}), isEmpty);
      feed = _poll(
        feed,
        [_row(1, _ts(3))],
        previous: <int, DateTime>{},
        counts: <int, int>{},
      );
      final first = verifyFeedNewest(feed)!;
      expect(first.restart, isTrue);
      expect(verifyFeedCountText(first), '重新計數：第 1/3 筆');
      expect(
        verifyLiveText(busy: true, passed: false, feed: feed, ptus: 1),
        '重新計數：第 1/3 筆',
      );
      expect(feed, hasLength(3));
    });

    test('a row without PTU values: none shown, judged the same', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      final feed = _poll(
        const [],
        [_row(1, _ts(1), values: false)],
        previous: previous,
        counts: counts,
      );
      expect(feed.single.ok, isTrue);
      expect(feed.single.inputMv, isNull);
      expect(verifyFeedValuesText(feed.single), '落後 1 秒');
      expect(counts[1], 1);
    });
  });

  group('2. copy', () {
    test('the goal, the pace and the footer in plain words', () {
      expect(verifyGoalText, '收到 3 筆正常資料就算完成');
      expect(verifyLagText(3), '落後 3 秒');
      expect(verifyLagText(2.6), '落後 3 秒');
      expect(verifyPollSeconds, 10);
      expect(verifyPaceText, '約每 10 秒收一筆，通常 30 秒內完成');
      expect(verifyFooterText(266), '約每 10 秒收一筆，通常 30 秒內完成・剩餘 266 秒');
      expect(verifyFooterText(266), isNot(contains('最多等待')));
    });

    test('one poll of several PTUs is announced together', () {
      VerifyFeedEntry e(int serial, int id, {bool ok = true, int count = 2}) =>
          VerifyFeedEntry(
            serial: serial,
            poll: 2,
            id: id,
            ok: ok,
            counted: ok,
            count: count,
            reasons: ok ? const [] : const ['延遲 75 秒'],
          );
      expect(verifyPollAnnounce([e(4, 1), e(5, 2)], ptus: 2), '每台收到第 2 筆');
      expect(
        verifyPollAnnounce([e(4, 1), e(5, 2)], ptus: 3),
        'PTU #1、PTU #2 收到第 2 筆',
      );
      expect(
        verifyPollAnnounce([e(4, 1), e(5, 2, ok: false, count: 1)], ptus: 2),
        'PTU #1 收到第 2 筆；PTU #2 資料未計入：延遲 75 秒',
      );
      expect(verifyPollAnnounce([e(5, 2)], ptus: 2), 'PTU #2 收到第 2 筆');
      // The newest poll only (an earlier poll's rows are not repeated).
      final feed = [e(4, 1), e(5, 2), _entry(1, id: 1, count: 1)];
      expect(verifyFeedLastPoll(feed).map((x) => x.id), [1, 2]);
    });

    test('the live line: waiting, the newest row, passed, nothing idle', () {
      expect(
        verifyLiveText(busy: true, passed: false, feed: const [], ptus: 1),
        '等待第一筆資料…',
      );
      expect(
        verifyLiveText(
          busy: true,
          passed: false,
          feed: [_entry(2, count: 2), _entry(1)],
          ptus: 1,
        ),
        '收到第 2 筆',
      );
      expect(
        verifyLiveText(
          busy: true,
          passed: true,
          feed: [_entry(1, count: 3)],
          ptus: 1,
        ),
        '資料正常上傳',
      );
      expect(
        verifyLiveText(busy: false, passed: false, feed: const [], ptus: 1),
        isNull,
      );
    });
  });

  group('3. the verification with the feed (controller)', () {
    test('each poll adds its rows; counts, polls and the result are '
        'unchanged; no other back-office call', () async {
      final fake = _Scripted(lateAt: {2});
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      expect(container.read(commissionProvider).step, 6);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      // Poll 1 → 1/3, poll 2 late (kept), polls 3 and 4 → 3/3.
      expect(fake.latestCalls, 4);
      expect(fake.paths.where((p) => p.startsWith('/api/app/recent')), isEmpty);
      final ids = states
          .lastWhere((x) => x.verifyCounts.isNotEmpty)
          .verifyCounts
          .keys;
      expect(ids, isNotEmpty);
      final lastStep9 = states.lastWhere((x) => x.step == 6);
      expect(lastStep9.verifyPassed, isTrue);
      expect(lastStep9.verifyCounts.values, everyElement(3));
      for (final id in ids) {
        final rows = lastStep9.verifyFeed.where((e) => e.id == id).toList();
        expect(rows, hasLength(4), reason: 'PTU #$id');
        expect([for (final e in rows) e.count], [3, 2, 1, 1]);
        expect([for (final e in rows) e.ok], [true, true, false, true]);
        expect(rows[2].reasons, ['延遲 75 秒']);
        // The data time of the row each poll served.
        for (final (i, e) in rows.indexed) {
          final poll = 4 - i;
          expect(e.ts, DateTime.parse(fake.served[poll]![id]!).toLocal());
        }
        expect(verifyFeedValuesText(rows.first), '53.2 V・2.72 A・36 °C・落後 1 秒');
      }
      // Green only once the data passed.
      expect(
        states
            .where((x) => x.verifyPassed)
            .every((x) => x.verifyCounts.values.every((n) => n == 3)),
        isTrue,
      );
      // The done page carries none of it.
      expect(s.verifyFeed, isEmpty);
      expect(s.verifyPassed, isFalse);
    });

    test('rows without PTU values: the verification passes the same', () async {
      final fake = _Scripted(values: false);
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.verified, isTrue);
      expect(fake.latestCalls, 3);
      final feed = states.lastWhere((x) => x.step == 6).verifyFeed;
      expect(feed, isNotEmpty);
      expect(feed.every((e) => e.inputMv == null && e.tempC == null), isTrue);
    });

    test('返回選擇 PTU empties the feed and the green', () async {
      final fake = _Scripted(errorAt: {1, 2, 3, 4, 5, 6});
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final run = c.verify('https://example.invalid', '');
      for (var i = 0; i < 400 && fake.latestCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(container.read(commissionProvider).verifyFeed, isNotEmpty);
      await c.backToSelection();
      await run;
      final s = container.read(commissionProvider);
      expect(s.step, isNot(6));
      expect(s.verifyFeed, isEmpty);
      expect(s.verifyPassed, isFalse);
    });
  });

  group('4. the page', () {
    testWidgets('two rows in: under each PTU, newest on top, with a click, '
        'a dot that runs once, the live line; the copy', (tester) async {
      final calls = _platformCalls(tester);
      final fake = _Scripted(holdAt: 3);
      final (container, c) = await _pageAtStep9(tester, fake);
      // Before: the flow stands still, the goal sentence, no old copy.
      expect(find.byKey(const Key('verify-flow')), findsOneWidget);
      expect(_dots(tester), [null, null]);
      expect(find.text(verifyGoalText), findsOneWidget);
      expect(find.textContaining('逐台檢查'), findsNothing);

      final (:run) = await _verifyUntil(tester, c, () => fake.held);
      final s = container.read(commissionProvider);
      expect(s.busy, isTrue);
      expect(_clicks(calls), greaterThanOrEqualTo(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_dots(tester).whereType<double>(), hasLength(1));
      await tester.pump(verifyFlowDuration);
      expect(_dots(tester), [null, null]);

      final ids = s.verifyCounts.keys.toList()..sort();
      for (final id in ids) {
        final rows = s.verifyFeed.where((e) => e.id == id).toList();
        expect(rows, hasLength(2));
        final group = find.byKey(Key('verify-feed-ptu-$id'));
        expect(group, findsOneWidget);
        // Newest on top.
        final top = tester.getTopLeft(
          find.byKey(ValueKey('verify-feed-row-${rows[0].serial}')),
        );
        final below = tester.getTopLeft(
          find.byKey(ValueKey('verify-feed-row-${rows[1].serial}')),
        );
        expect(top.dy, lessThan(below.dy));
        expect(
          _joined(tester, ValueKey('verify-feed-head-${rows[0].serial}'), '  '),
          '${recentClockText(DateTime.parse(fake.served[2]![id]!).toLocal())}'
          '  第 2 筆',
        );
        expect(
          _joined(tester, ValueKey('verify-feed-values-${rows[0].serial}')),
          '53.2 V・2.72 A・36 °C・落後 1 秒',
        );
        expect(
          tester.widget<Text>(find.byKey(Key('verify-count-$id'))).data,
          '2/3',
        );
      }
      // The live line, announced.
      final live = tester.widget<Semantics>(
        find.byKey(const Key('verify-live-status')),
      );
      expect(live.properties.liveRegion, isTrue);
      expect(
        _text(tester, const Key('verify-live-text')),
        ids.length > 1 ? '每台收到第 2 筆' : '收到第 2 筆',
      );
      // The checklist's small print: the pace and the seconds left.
      final footer = _text(tester, const Key('checklist-footer'))!;
      expect(footer, startsWith(verifyPaceText));
      expect(footer, contains('剩餘'));
      expect(find.textContaining('最多等待'), findsNothing);

      await _finish(tester, fake, run);
      expect(container.read(commissionProvider).step, 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a late row: red, its reason, the count kept', (tester) async {
      final fake = _Scripted(lateAt: {2}, holdAt: 3);
      final (container, c) = await _pageAtStep9(tester, fake);
      final (:run) = await _verifyUntil(tester, c, () => fake.held);
      await tester.pump(const Duration(seconds: 1));
      final s = container.read(commissionProvider);
      final ids = s.verifyCounts.keys.toList()..sort();
      for (final id in ids) {
        final late = s.verifyFeed.firstWhere((e) => e.id == id);
        expect(late.ok, isFalse);
        expect(
          _text(tester, ValueKey('verify-feed-reason-${late.serial}')),
          '原因：延遲 75 秒',
        );
        expect(
          _joined(tester, ValueKey('verify-feed-head-${late.serial}'), '  '),
          endsWith('未計入（維持 1/3）'),
        );
        expect(
          _joined(tester, ValueKey('verify-feed-values-${late.serial}')),
          '53.2 V・2.72 A・36 °C・落後 75 秒',
        );
        final box = tester.widget<Container>(
          find.byKey(ValueKey('verify-feed-row-${late.serial}')),
        );
        final colors = Theme.of(
          tester.element(
            find.byKey(ValueKey('verify-feed-row-${late.serial}')),
          ),
        ).colorScheme;
        expect(
          (box.decoration! as BoxDecoration).color,
          colors.errorContainer.withValues(alpha: 0.6),
        );
        expect(
          tester.widget<Text>(find.byKey(Key('verify-count-$id'))).data,
          '1/3',
        );
      }
      expect(
        _text(tester, const Key('verify-live-text')),
        ids.length > 1 ? '每台資料未計入：延遲 75 秒' : '資料未計入：延遲 75 秒',
      );
      final liveText = tester.widget<Text>(
        find.byKey(const Key('verify-live-text')),
      );
      expect(
        liveText.style?.color,
        Theme.of(
          tester.element(find.byKey(const Key('verify-live-text'))),
        ).colorScheme.error,
      );
      await _finish(tester, fake, run);
      expect(container.read(commissionProvider).verified, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('passed: the whole card green, 資料正常上傳 with a tick that '
        'scales in once', (tester) async {
      final fake = _Scripted(holdConfirm: true);
      final (container, c) = await _pageAtStep9(tester, fake);
      final card = find.byKey(const Key('verify-card-surface'));
      Color? surface() =>
          (tester.widget<AnimatedContainer>(card).decoration as BoxDecoration?)
              ?.color;
      expect(surface()!.a, 0);
      final (:run) = await _verifyUntil(tester, c, () => fake.held);
      expect(container.read(commissionProvider).verifyPassed, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(surface()!.a, greaterThan(0));
      expect(_text(tester, const Key('verify-live-text')), verifyPassedText);
      final tick = find.byKey(const Key('verify-passed-check'));
      expect(tick, findsOneWidget);
      double scale() => tester
          .widget<Transform>(
            find.descendant(of: tick, matching: find.byType(Transform)),
          )
          .transform
          .storage[0];
      expect(scale(), lessThan(1));
      await tester.pump(const Duration(seconds: 1));
      expect(scale(), closeTo(1, 0.001));
      await tester.pump(const Duration(seconds: 1));
      expect(scale(), closeTo(1, 0.001));
      await _finish(tester, fake, run);
      expect(container.read(commissionProvider).step, 7);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('5. animations run once and end', () {
    Widget app(
      List<VerifyFeedEntry> feed, {
      bool passed = false,
      bool still = false,
    }) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: Scaffold(
            body: ListView(
              children: [
                VerifyStepCard(
                  passed: passed,
                  children: [
                    VerifyLiveHeader(
                      feed: feed,
                      busy: true,
                      passed: passed,
                      ptus: 1,
                    ),
                    VerifyFeedRows(entries: feed),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('one click and one run per poll with new rows, none '
        'otherwise; pumpAndSettle settles', (tester) async {
      final calls = _platformCalls(tester);
      var feed = <VerifyFeedEntry>[];
      await tester.pumpWidget(app(feed));
      await tester.pumpAndSettle();
      expect(_clicks(calls), 0);
      expect(_dots(tester), [null, null]);
      for (var k = 1; k <= 6; k++) {
        feed = [_entry(k, count: k > 3 ? 3 : k), ...feed];
        if (feed.length > 5) feed = feed.sublist(0, 5);
        await tester.pumpWidget(app(feed));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_dots(tester).whereType<double>(), hasLength(1));
        // A rebuild without a new row: no click, no new run.
        await tester.pumpWidget(app(List.of(feed)));
        await tester.pumpAndSettle();
        expect(_clicks(calls), k);
        expect(_dots(tester), [null, null]);
      }
      expect(find.byType(VerifyFeedRow), findsNWidgets(5));
      await tester.pumpWidget(app(feed, passed: true));
      await tester.pumpAndSettle();
      expect(find.text(verifyPassedText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion: no dot, rows at once, the click stays', (
      tester,
    ) async {
      final calls = _platformCalls(tester);
      await tester.pumpWidget(app(const [], still: true));
      await tester.pumpWidget(app([_entry(1)], still: true));
      await tester.pump();
      expect(_dots(tester), [null, null]);
      expect(_clicks(calls), 1);
      final row = tester.getSize(find.byType(VerifyFeedRow));
      expect(row.height, greaterThan(20));
      final clip = tester.widget<Align>(
        find
            .ancestor(
              of: find.byType(VerifyFeedRow),
              matching: find.byType(Align),
            )
            .first,
      );
      expect(clip.heightFactor, 1);
    });

    testWidgets('a poll with a row not counted: the dot runs red', (
      tester,
    ) async {
      _platformCalls(tester);
      Color? dot() => [
        for (final paint in tester.widgetList<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('verify-flow')),
            matching: find.byType(CustomPaint),
          ),
        ))
          if (paint.painter case final VerifyFlowLinkPainter p
              when p.progress != null)
            p.dot,
      ].firstOrNull;
      final good = _entry(1);
      await tester.pumpWidget(app(const []));
      await tester.pumpWidget(app([good]));
      await tester.pump(const Duration(milliseconds: 100));
      final context = tester.element(find.byKey(const Key('verify-flow')));
      expect(dot(), isNot(Theme.of(context).colorScheme.error));
      await tester.pumpAndSettle();
      final late = _entry(2, ok: false, reasons: const ['延遲 75 秒']);
      await tester.pumpWidget(app([late, good]));
      await tester.pump(const Duration(milliseconds: 100));
      expect(dot(), Theme.of(context).colorScheme.error);
      expect(
        tester.widget<Text>(find.byKey(const Key('verify-live-text'))).data,
        '資料未計入：延遲 75 秒',
      );
      await tester.pumpAndSettle();
    });
  });
}
