// 1.0.0+17 (user on the phone: after 〔檢查並開始〕 the list scanned about
// 8 s with only a small 「持續搜尋中・RSSI 隨廣播更新」, then showed
// 「搜尋已停止・未發現附近閘道器」 — no sense of progress; the filter box and
// the leftover 「準備完成」 were noise; HANDOFF §5.3 P2: the first scan after
// an install sometimes found nothing and 〔重新搜尋〕 did):
// 1. While the search runs: a progress area — 「正在搜尋附近的閘道器…」, a
//    determinate bar (elapsed / [gatewaySearchWindow]) and 「已找到 N 台」
//    counted live (a live region).
// 2. Found: the area goes, one line 「找到 N 台，請點選本樁的那台」 (only
//    「找到 N 台」 when the nearest hint says which one); the scan goes on.
// 3. Nothing found: searched once more (「沒找到，再搜尋一次…」) after
//    [gatewayRescanDelay]; nothing again: [gatewayNotFoundText] and
//    〔重新搜尋〕 as the main, full-width button. 〔停止搜尋〕 is never
//    followed by a second search.
// 4. No filter box; 5. no 「準備完成」 on the list.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/gateway_proximity.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

/// A live scan per start; the first [endAtOnce] scans end at once with
/// nothing heard (the phone's scan that 「stopped」 by itself).
class _Sessions extends DemoSystem implements GatewayScanner {
  _Sessions({this.endAtOnce = 0, this.failWith});
  final int endAtOnce;

  /// The first scan fails with it (then ends, as the phone's link does).
  final Object? failWith;
  final sessions = <StreamController<List<GatewayPeer>>>[];
  int stops = 0;

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final scan = StreamController<List<GatewayPeer>>();
    sessions.add(scan);
    if (sessions.length == 1 && failWith != null) {
      scan.addError(failWith!);
      unawaited(scan.close());
    } else if (sessions.length <= endAtOnce) {
      unawaited(scan.close());
    }
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    stops++;
    for (final scan in sessions) {
      if (!scan.isClosed) unawaited(scan.close());
    }
  }

  void hear(List<GatewayPeer> peers) => sessions.last.add(peers);
}

const _a = GatewayPeer('AA:BB:CC:DD:EE:01', 'GIOS-S81-GW01', -45);
const _b = GatewayPeer('AA:BB:CC:DD:EE:02', 'GIOS-S82-GW02', -75);

final _progressArea = find.byKey(const Key('gateway-search-progress'));
final _bar = find.byKey(const Key('gateway-search-bar'));
final _count = find.byKey(const Key('gateway-found-count'));
final _head = find.byKey(const Key('gateway-search-head'));
final _status = find.byKey(const Key('gateway-search-status'));
final _notFound = find.byKey(const Key('gateway-not-found'));
final _rescanMain = find.byKey(const Key('gateway-rescan-primary'));
final _toggle = find.byKey(const Key('gateway-scan-toggle'));

String? _text(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data;

double? _value(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(_bar).value;

Future<_Sessions> _pumpList(
  WidgetTester tester, {
  int endAtOnce = 0,
  Object? failWith,
}) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final link = _Sessions(endAtOnce: endAtOnce, failWith: failWith);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [linkProvider.overrideWithValue(link)],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GatewayDiscovery(
                enabled: true,
                onConnect: (_) async {},
                onIdentify: (_) async => true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return link;
}

/// Pumps [total] in steps (the bar, the timers), letting the list's real
/// async work (its stop / start) run between them.
Future<void> _wait(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 250);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
    await _settle(tester);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 2)),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the search is the nearby scan\'s window; one retry after 1 s', () {
    expect(gatewaySearchWindow, const Duration(seconds: 8));
    expect(GatewayDiscovery.searchWindow, gatewaySearchWindow);
    expect(gatewayRescanDelay, const Duration(seconds: 1));
    expect(gatewayFoundText(1), '找到 1 台，請點選本樁的那台');
    expect(gatewayFoundText(2, withHint: true), '找到 2 台');
  });

  testWidgets('searching: the bar fills with time, 「已找到 N 台」 counts the '
      'gateways as their cards appear; a live region', (tester) async {
    final link = await _pumpList(tester);
    expect(_progressArea, findsOneWidget);
    expect(_text(tester, _head), gatewaySearchingText);
    expect(_text(tester, _count), '已找到 0 台');
    expect(
      tester.widget<Semantics>(_progressArea).properties.liveRegion,
      isTrue,
    );
    expect(find.text('持續搜尋中・RSSI 隨廣播更新'), findsNothing);

    await _wait(tester, const Duration(seconds: 1));
    final early = _value(tester)!;
    expect(early, greaterThan(0));
    expect(early, lessThan(0.3));

    link.hear(const [_a]);
    await tester.pump();
    expect(_text(tester, _count), '已找到 1 台');
    expect(find.byKey(ValueKey('gateway-card-${_a.id}')), findsOneWidget);

    await _wait(tester, const Duration(seconds: 3));
    final later = _value(tester)!;
    expect(later, greaterThan(early));
    expect(later, closeTo(4 / 8, 0.1));

    link.hear(const [_a, _b]);
    await tester.pump();
    expect(_text(tester, _count), '已找到 2 台');
    expect(find.byKey(ValueKey('gateway-card-${_b.id}')), findsOneWidget);
    expect(_value(tester)!, greaterThanOrEqualTo(later));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('found: after the window the progress area goes, one line '
      'says how many; the scan goes on', (tester) async {
    final link = await _pumpList(tester);
    link.hear(const [_a]);
    await tester.pump();
    await _wait(tester, const Duration(seconds: 9));
    expect(_progressArea, findsNothing);
    expect(_bar, findsNothing);
    expect(_text(tester, _status), '找到 1 台，請點選本樁的那台');
    expect(find.text(gatewayNotFoundText), findsNothing);
    // Still scanning (RSSI updates): 〔停止搜尋〕, secondary place kept.
    expect(link.sessions, hasLength(1));
    expect(link.sessions.single.isClosed, isFalse);
    expect(find.text('停止搜尋'), findsOneWidget);
    expect(_toggle, findsOneWidget);
    expect(_rescanMain, findsNothing);
    // Two heard, one clearly nearest: the hint says which — the line only
    // counts (no two lines saying the same).
    for (var i = 0; i < 3; i++) {
      link.hear(const [_a, _b]);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text(gatewayNearestHint), findsOneWidget);
    expect(_text(tester, _status), '找到 2 台');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nothing found: searched again exactly once, then 「未發現」 and '
      '〔重新搜尋〕 as the main button', (tester) async {
    final link = await _pumpList(tester);
    expect(link.sessions, hasLength(1));
    await _wait(tester, const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 100));
    // Waiting for the second search: said so, the bar moving, no
    // 「未發現」 yet.
    expect(_progressArea, findsOneWidget);
    expect(_text(tester, _head), gatewayRetryingText);
    expect(_value(tester), isNull);
    expect(_notFound, findsNothing);
    expect(find.text('停止搜尋'), findsOneWidget);
    await _wait(tester, gatewayRescanDelay);
    await tester.pump();
    expect(link.sessions, hasLength(2), reason: 'searched once more');
    expect(_text(tester, _head), gatewayRetryingText);
    expect(_value(tester), isNotNull);
    await _wait(tester, const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_progressArea, findsNothing);
    expect(_notFound, findsOneWidget);
    expect(find.text(gatewayNotFoundText), findsOneWidget);
    expect(_rescanMain, findsOneWidget);
    expect(tester.widget(_rescanMain), isA<FilledButton>());
    final rect = tester.getRect(_rescanMain);
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.width, greaterThan(300), reason: 'full width');
    expect(_toggle, findsNothing, reason: 'one 〔重新搜尋〕 only');
    expect(find.text('重新搜尋'), findsOneWidget);
    expect(link.sessions.every((s) => s.isClosed), isTrue, reason: 'stopped');
    // No third search by itself.
    await _wait(tester, const Duration(seconds: 20));
    expect(link.sessions, hasLength(2));
    // The main button: a new search (and its own one retry).
    await tester.tap(_rescanMain);
    await _settle(tester);
    await _settle(tester);
    expect(link.sessions, hasLength(3));
    expect(_text(tester, _head), gatewaySearchingText);
    expect(_notFound, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a scan that ended by itself with nothing (P2) is searched '
      'again at once, and what it finds is listed', (tester) async {
    final link = await _pumpList(tester, endAtOnce: 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(link.sessions, hasLength(1));
    expect(_text(tester, _head), gatewayRetryingText);
    expect(_notFound, findsNothing);
    await _wait(tester, gatewayRescanDelay);
    await tester.pump();
    expect(link.sessions, hasLength(2));
    link.hear(const [_a]);
    await tester.pump();
    expect(_text(tester, _count), '已找到 1 台');
    await _wait(tester, const Duration(seconds: 9));
    expect(_progressArea, findsNothing);
    expect(_text(tester, _status), '找到 1 台，請點選本樁的那台');
    expect(_notFound, findsNothing);
    expect(link.sessions, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('〔停止搜尋〕 is never followed by a second search', (tester) async {
    final link = await _pumpList(tester);
    await _wait(tester, const Duration(seconds: 2));
    await tester.tap(find.text('停止搜尋'));
    await _settle(tester);
    await _settle(tester);
    expect(_progressArea, findsNothing);
    expect(_text(tester, _status), gatewayStoppedText);
    await _wait(tester, const Duration(seconds: 20));
    expect(link.sessions, hasLength(1));
    expect(find.text(gatewayRetryingText), findsNothing);
    expect(_notFound, findsNothing);
    expect(_rescanMain, findsNothing);
    expect(find.text('重新搜尋'), findsOneWidget);
    // Also while the second search waits: 〔停止搜尋〕 cancels it.
    await tester.tap(find.text('重新搜尋'));
    await _settle(tester);
    await _settle(tester);
    expect(link.sessions, hasLength(2));
    await _wait(tester, const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_text(tester, _head), gatewayRetryingText);
    await tester.tap(find.text('停止搜尋'));
    await _settle(tester);
    await _wait(tester, const Duration(seconds: 5));
    expect(link.sessions, hasLength(2), reason: 'the retry was cancelled');
    expect(_text(tester, _status), gatewayStoppedText);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // A failed scan is not 「nothing found」: never searched again by itself,
  // its error and guidance stay.
  for (final (name, error, text, settings) in [
    (
      'Bluetooth off',
      const GatewayFailure('bluetooth_off') as Object,
      '請開啟手機藍牙後重試',
      false,
    ),
    (
      'permission denied',
      const GatewayFailure('permission') as Object,
      '需要藍牙權限',
      true,
    ),
    ('a scan exception', StateError('scan broke') as Object, '搜尋失敗', true),
  ]) {
    testWidgets('$name: no second search, the error stays', (tester) async {
      final link = await _pumpList(tester, failWith: error);
      await _settle(tester);
      expect(find.textContaining(text), findsOneWidget);
      expect(_progressArea, findsNothing);
      expect(find.text(gatewayRetryingText), findsNothing);
      await _wait(tester, const Duration(seconds: 20));
      expect(link.sessions, hasLength(1), reason: 'not searched again');
      expect(find.textContaining(text), findsOneWidget);
      expect(find.text(gatewayRetryingText), findsNothing);
      expect(_notFound, findsNothing);
      expect(_rescanMain, findsNothing);
      expect(
        find.byKey(const Key('gateway-open-settings')),
        settings ? findsOneWidget : findsNothing,
      );
      expect(find.text('重新搜尋'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('no filter box', (tester) async {
    final link = await _pumpList(tester);
    link.hear(const [_a, _b]);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('篩選名稱或位址'), findsNothing);
    expect(find.text('沒有符合的裝置'), findsNothing);
    expect(find.byKey(ValueKey('gateway-card-${_a.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('gateway-card-${_b.id}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the list page shows no 「準備完成」 (the step before\'s message); '
      'the controller still has it', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'backend_environment': 'production',
    });
    final link = DemoSystem();
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
      await container
          .read(commissionProvider.notifier)
          .prepare(container.read(backendEnvProvider).base, 'pw');
    });
    await tester.pumpAndSettle();
    final s = container.read(commissionProvider);
    expect(s.step, 1);
    expect(s.message, preparedText);
    expect(find.byType(GatewayDiscovery), findsOneWidget);
    expect(find.text(preparedText), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
