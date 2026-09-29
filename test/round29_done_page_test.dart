// Round 29 (field drill, the owner as the installer: 「配置結束後 APP 最後的
// 畫面會讓我不知道該如何結束」 — the done page opened on 「本地測試主機 ✓ 資料
// 上傳中」, a red 「出貨前請切回正式站」 and its biggest button 「手機和
// Gateway 都切回正式站」; 「開通完成」 came after, with no way to end):
// 1. The done page starts with the success summary (done, station/gateway,
//    mode, PTU and binding, data upload); 〔完成〕 (main) and 〔配置下一台〕
//    are fixed at the bottom, on the first screen at 360x640, font 1.0/1.3.
// 2. 〔完成〕 lets the gateway go, clears the progress and goes to the start
//    page: 「上一台已完成：站 80 閘道器 1」. 〔配置下一台〕 goes to the
//    gateway list keeping the station for the next new gateway.
// 3. 「切回正式站」 is a small developer note of a local test build only,
//    below the summary, never a main button; a production build has none.
// 4. The system 返回 on the done page is 〔完成〕 (no question); a finished
//    run is never a 「上次配置」 card after a restart.
// 5. The one-to-one 〔先完成配置〕 done page (waiting for the pile's PTU)
//    has the same 〔完成〕 and says the PTU connects once powered and the
//    binding is confirmed on site with 〔辨識〕.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// A new gateway (factory 1/1) with three PTUs; counts the disconnects.
class _Gateway extends DemoSystem {
  int disconnects = 0;

  /// Uploads to the local test host (as a local test build leaves it).
  void uploadLocal() =>
      config.addAll({'mqtt_target': 'local', 'mqtt_host': '192.168.1.50'});

  /// The next gateway on the bench: another new one, factory 1/1.
  void nextFactoryGateway() => config.addAll({
    'site_id': 1,
    'gateway_id': 1,
    'fleet_joined': false,
    'gateway_uid': 'A0DD6CA370F0',
  });

  @override
  Future<void> disconnect() async {
    disconnects++;
    await super.disconnect();
  }
}

/// [_Gateway] whose `/api/latest` answer waits for [latestGate].
class _SlowLatest extends _Gateway {
  Completer<void>? latestGate;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.startsWith('/api/latest') && latestGate != null) {
      await latestGate!.future;
    }
    return super.request(method, path, body);
  }
}

/// Pile B of field round 28: one-to-one, a new gateway whose own PTU is
/// not powered (every PTU heard is under -55 dBm).
class _PileNoPtu extends PickGateway {
  _PileNoPtu() : super(rssi: const [-61, -72, -80]) {
    config['fleet_joined'] = false;
  }
}

const _localPrefs = <String, Object>{
  'backend_environment': 'local',
  'backend_local_url': 'http://192.168.1.50:18000',
};

const _localBuild = EnvSwitchPolicy(
  autoSyncDefault: false,
  confirmGatewaySwitch: false,
  localBuild: true,
);
const _productionBuild = EnvSwitchPolicy(
  autoSyncDefault: false,
  confirmGatewaySwitch: true,
  localBuild: false,
);

void _phone(WidgetTester tester, double scale) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  DemoSystem fake, {
  Map<String, Object> prefs = const {},
  EnvSwitchPolicy policy = _productionBuild,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        envSwitchPolicyProvider.overrideWithValue(policy),
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

/// Star: a new gateway commissioned as station 80 / gateway 1 and
/// verified — the done page.
Future<ProviderContainer> _pumpStarDone(
  WidgetTester tester,
  _Gateway fake, {
  Map<String, Object> prefs = const {},
  EnvSwitchPolicy policy = _productionBuild,
}) async {
  final container = await _pumpApp(tester, fake, prefs: prefs, policy: policy);
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

/// One-to-one without the pile's PTU: 〔先完成配置〕 — the done page.
Future<ProviderContainer> _pumpDeferredDone(
  WidgetTester tester,
  _PileNoPtu fake,
) async {
  final container = await _pumpApp(tester, fake);
  await tester.runAsync(() async {
    final topo = container.read(topologyProvider.notifier);
    await topo.ready;
    await topo.setTopology(GatewayTopology.direct);
    await topo.setDirectBindOnConfirm(true);
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await c.passNetworkCheck(skip: true);
    await c.configureWifi(80, 2, 'Office-2G', 'password123');
    await c.online(skip: true);
    await c.finishWithoutPtu();
  });
  await tester.pumpAndSettle();
  final s = container.read(commissionProvider);
  expect(s.step, 7, reason: 'done page');
  expect(s.ptuDeferred, isTrue);
  return container;
}

Future<void> _settle(WidgetTester tester, ProviderContainer container) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 400; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (!container.read(commissionProvider).busy) break;
    }
  });
  await tester.pumpAndSettle();
}

final _finish = find.byKey(const Key('done-finish'));
final _next = find.byKey(const Key('done-next'));

/// Fully on the 360x640 screen and tappable.
void _onFirstScreen(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(640));
  expect(finder.hitTestable(), findsOneWidget);
}

const _progressKey = 'demo_progress';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    keepPoll = directPollInterval;
    directPollInterval = const Duration(milliseconds: 1);
  });
  tearDown(() => directPollInterval = keepPoll);

  group('1. the summary on top, 〔完成〕 on the first screen', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('star done page at 360x640, font $scale', (tester) async {
        _phone(tester, scale);
        final container = await _pumpStarDone(tester, _Gateway());
        _onFirstScreen(tester, _finish);
        _onFirstScreen(tester, _next);
        _onFirstScreen(tester, find.byKey(const Key('done-title')));
        expect(
          tester.widget<Text>(find.byKey(const Key('done-title'))).data,
          '開通完成',
        );
        // The main action is the one filled button; 配置下一台 beside it.
        expect(tester.widget(_finish), isA<FilledButton>());
        expect(tester.widget(_next), isA<OutlinedButton>());
        expect(
          find.byWidgetPredicate((w) => w is FilledButton),
          findsOneWidget,
        );
        expect(
          tester.getRect(_next).top,
          moreOrLessEquals(tester.getRect(_finish).top, epsilon: 1),
        );
        // The summary: done, station/gateway, mode, PTU, upload.
        final summary = tester.getRect(find.byKey(const Key('done-summary')));
        expect(summary.top, lessThan(120));
        expect(find.text('站 80 · 閘道器 1'), findsOneWidget);
        expect(find.text('模式：${GatewayTopology.star.label}'), findsOneWidget);
        expect(find.text('掃到 3 台，本機配置 3 台'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('done-upload'))).data,
          startsWith('資料上傳：✓ 資料上傳中'),
        );
        // Everything else is below the summary; no 結束並重新選擇閘道器.
        // 1.0.0+13: the summary's label card (「請在機殼上標示：…」) pushes
        // it further down at font 1.3 — scrolled to (the page builds
        // lazily).
        final status = find.byKey(const Key('connection-status-ok'));
        final page = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(status, 100, scrollable: page);
        expect(status, findsOneWidget);
        final scrolled = tester.state<ScrollableState>(page).position.pixels;
        expect(
          tester.getRect(status).top + scrolled,
          greaterThan(summary.bottom - 1),
        );
        expect(find.byKey(const Key('page-cancel')), findsNothing);
        expect(find.byKey(const Key('step-title')), findsNothing);
        expect(container.read(commissionProvider).step, 7);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('waiting-for-PTU done page at 360x640, font $scale', (
        tester,
      ) async {
        _phone(tester, scale);
        await _pumpDeferredDone(tester, _PileNoPtu());
        _onFirstScreen(tester, _finish);
        _onFirstScreen(tester, _next);
        _onFirstScreen(tester, find.byKey(const Key('done-title')));
        expect(
          tester.widget<Text>(find.byKey(const Key('done-title'))).data,
          deferredDoneTitle,
        );
        expect(find.text('站 80 · 閘道器 2'), findsOneWidget);
        expect(find.text(deferredSummaryText), findsOneWidget);
        // The reminder: the PTU connects once powered, bind on site later.
        expect(find.text(deferredDoneText), findsOneWidget);
        expect(deferredDoneText, contains('PTU 上電後會自動連線，之後到現場按〔辨識〕確認綁定'));
        expect(
          find.byWidgetPredicate((w) => w is FilledButton),
          findsOneWidget,
          reason: '〔PTU 已上電：辨識並綁定〕 is secondary now',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('2. 〔完成〕 and 〔配置下一台〕', () {
    testWidgets('〔完成〕: start page, 上一台已完成, progress cleared, gateway '
        'let go', (tester) async {
      _phone(tester, 1.0);
      final fake = _Gateway();
      final container = await _pumpStarDone(tester, fake);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_progressKey), isNotNull);
      final before = fake.disconnects;

      await tester.tap(_finish);
      await _settle(tester, container);
      final s = container.read(commissionProvider);
      expect(s.step, 0);
      expect(s.peer, isNull);
      expect(s.verified, isFalse);
      expect(s.lastDone, '上一台已完成：站 80 閘道器 1');
      expect(s.savedResume, isFalse);
      expect(s.savedProgress, isFalse);
      expect(fake.disconnects, greaterThan(before));
      expect(prefs.getString(_progressKey), isNull);
      expect(container.read(commissionProvider.notifier).keptSite, isNull);
      // The start page says so, with no card to resume or restart.
      expect(find.text('上一台已完成：站 80 閘道器 1'), findsOneWidget);
      expect(find.byKey(const Key('restart-after-done')), findsNothing);
      expect(find.byKey(const Key('saved-resume')), findsNothing);
      expect(find.text('檢查並開始'), findsOneWidget);
      expect(_finish, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    // 09-29: 〔結束配置〕 on that gateway list keeps the note.
    testWidgets('〔配置下一台〕 then 〔結束配置〕: the start page still says '
        '「上一台已完成」', (tester) async {
      _phone(tester, 1.0);
      final fake = _Gateway();
      final container = await _pumpStarDone(tester, fake);
      await tester.tap(_next);
      await _settle(tester, container);
      expect(container.read(commissionProvider).step, 1);
      final leave = find.byKey(const Key('page-cancel'));
      await tester.scrollUntilVisible(
        leave,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      // 1.0.0+17 (no filter box: the list is shorter): scrolled clear of
      // the fixed bottom bar before the tap.
      await tester.ensureVisible(leave);
      await tester.pumpAndSettle();
      expect(find.text(leaveListLabel), findsOneWidget);
      await tester.tap(leave);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave-confirm-end')));
      await _settle(tester, container);
      final s = container.read(commissionProvider);
      expect(s.step, 0);
      expect(s.peer, isNull);
      expect(s.message, isEmpty);
      expect(s.lastDone, '上一台已完成：站 80 閘道器 1');
      expect(find.byKey(const Key('last-done-text')), findsOneWidget);
      expect(find.text('上一台已完成：站 80 閘道器 1'), findsOneWidget);
      expect(find.text('檢查並開始'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('〔配置下一台〕: the gateway list, the station kept for the '
        'next new gateway', (tester) async {
      _phone(tester, 1.0);
      final fake = _Gateway();
      final container = await _pumpStarDone(tester, fake);

      await tester.tap(_next);
      await _settle(tester, container);
      final c = container.read(commissionProvider.notifier);
      var s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.peer, isNull);
      expect(s.loggedIn, isTrue, reason: 'no new login for the next one');
      expect(s.lastDone, '上一台已完成：站 80 閘道器 1');
      expect(c.keptSite, 80);
      expect(find.text('上一台已完成：站 80 閘道器 1'), findsOneWidget);
      expect(find.text(nextGatewayText(80)), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_progressKey), isNull);

      // The next new gateway (factory 1/1) is proposed on station 80.
      fake.nextFactoryGateway();
      await tester.runAsync(() async {
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
      });
      await tester.pumpAndSettle();
      s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.config['suggested_site_id'], 80);
      expect(s.config['suggested_gateway_id'], isA<int>());
      // Saved again once the next run reached a gateway.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      expect(prefs.getString(_progressKey), isNotNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('waiting-for-PTU: 〔完成〕 notes the PTU is not connected yet', (
      tester,
    ) async {
      _phone(tester, 1.3);
      final container = await _pumpDeferredDone(tester, _PileNoPtu());
      await tester.tap(_finish);
      await _settle(tester, container);
      final s = container.read(commissionProvider);
      expect(s.step, 0);
      expect(s.lastDone, lastDoneText(80, 2, ptuDeferred: true));
      expect(s.lastDone, startsWith('上一台已完成：站 80 閘道器 2'));
      expect(find.text(s.lastDone), findsOneWidget);
      // The gateway stays remembered for 〔辨識並綁定〕 on a later connect.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('demo_direct_deferred_ptu'), isNotNull);
      expect(prefs.getString(_progressKey), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('a health answer arriving after 〔完成〕 is dropped (no 資料持續更新 '
      'on the start page)', () async {
    final fake = _SlowLatest();
    final container = ProviderContainer(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', 'pw');
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await c.configureWifi(80, 1, 'Office-2G', 'pw123456');
    await c.online();
    await c.discover();
    await c.configurePtus();
    await c.verify('https://example.invalid', '');
    expect(container.read(commissionProvider).step, 7);
    fake.latestGate = Completer<void>();
    final health = c.refreshHealth();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.finishDone();
    fake.latestGate!.complete();
    await health;
    final s = container.read(commissionProvider);
    expect(s.step, 0);
    expect(s.message, isEmpty);
    expect(s.lastDone, '上一台已完成：站 80 閘道器 1');
  });

  group('3. 切回正式站: a developer note of a local test build only', () {
    testWidgets('local build: a small note below the summary, a text '
        'button, never the main one', (tester) async {
      _phone(tester, 1.3);
      final fake = _Gateway()..uploadLocal();
      final container = await _pumpStarDone(
        tester,
        fake,
        prefs: _localPrefs,
        policy: _localBuild,
      );
      final note = find.byKey(const Key('dev-ship-note'));
      await tester.scrollUntilVisible(
        note,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(devShipNoteText), findsOneWidget);
      expect(devShipNoteText, startsWith('開發環境提示'));
      final summary = find.byKey(const Key('done-summary'));
      // Never above the summary (scrolled: the summary may be off screen,
      // compare in the list's order).
      if (summary.evaluate().isNotEmpty) {
        expect(
          tester.getRect(note).top,
          greaterThan(tester.getRect(summary).bottom),
        );
      }
      final switchBack = find.byKey(const Key('dev-ship-switch'));
      expect(tester.widget(switchBack), isA<TextButton>());
      expect(tester.widget(switchBack), isNot(isA<FilledButton>()));
      final area = tester.getSize(switchBack);
      final main = tester.getSize(_finish);
      expect(area.width * area.height, lessThan(main.width * main.height));
      expect(
        find.byWidgetPredicate((w) => w is FilledButton),
        findsOneWidget,
        reason: 'the only filled button is 〔完成〕',
      );
      // Not the red box of before.
      expect(find.text(localTargetShipWarning), findsNothing);
      expect(find.text('手機和閘道器都切回正式站'), findsNothing);
      // The note's order in the page: after the summary.
      await tester.scrollUntilVisible(
        summary,
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getRect(summary).top, lessThan(tester.getRect(note).top));

      // It still works: phone and gateway both to 正式站, the note goes.
      await tester.ensureVisible(switchBack);
      await tester.pumpAndSettle();
      await tester.tap(switchBack);
      await _settle(tester, container);
      expect(fake.targetRequests.last, {'target': 'production'});
      expect(
        container.read(backendEnvProvider).environment,
        BackendEnv.production,
      );
      expect(find.byKey(const Key('dev-ship-note')), findsNothing);
      expect(container.read(commissionProvider).step, 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('production build: no note, no 切回正式站, same gateway', (
      tester,
    ) async {
      _phone(tester, 1.0);
      final fake = _Gateway()..uploadLocal();
      await _pumpStarDone(
        tester,
        fake,
        prefs: _localPrefs,
        policy: _productionBuild,
      );
      final list = find.byType(Scrollable).first;
      // Scroll the whole page through.
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dev-ship-note')), findsNothing);
        expect(find.textContaining('切回正式站'), findsNothing);
        expect(find.textContaining('出貨前'), findsNothing);
      }
      expect(find.byKey(const Key('dev-ship-switch')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. 返回 is 〔完成〕; a finished run is never a resume card', () {
    testWidgets('返回 on the done page: no question, the start page', (
      tester,
    ) async {
      _phone(tester, 1.0);
      final container = await _pumpStarDone(tester, _Gateway());
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await _settle(tester, container);
      expect(find.byKey(const Key('end-confirm')), findsNothing);
      final s = container.read(commissionProvider);
      expect(s.step, 0);
      expect(s.lastDone, '上一台已完成：站 80 閘道器 1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_progressKey), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('left with 〔完成〕, the APP opened again: no 上次配置 card', (
      tester,
    ) async {
      _phone(tester, 1.0);
      final fake = _Gateway();
      final container = await _pumpStarDone(tester, fake);
      await tester.tap(_finish);
      await _settle(tester, container);
      await tester.pumpWidget(const SizedBox());

      // A new APP start on the same phone (same saved preferences).
      final again = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(again.dispose);
      await again.read(commissionProvider.notifier).restore();
      final s = again.read(commissionProvider);
      expect(s.savedResume, isFalse);
      expect(s.savedProgress, isFalse);
      expect(s.lastDone, isEmpty);
      expect(s.message, isEmpty);
    });

    testWidgets('closed on the done page: the start page notes it, no card '
        'to resume or restart', (tester) async {
      _phone(tester, 1.0);
      final container = await _pumpApp(
        tester,
        _Gateway(),
        prefs: {
          _progressKey: jsonEncode({
            'step': 7,
            'shown': 10,
            'completed': true,
            'count': 3,
            'site': 80,
            'gateway': 1,
          }),
        },
      );
      await tester.runAsync(
        () => container.read(commissionProvider.notifier).restore(),
      );
      await tester.pumpAndSettle();
      final s = container.read(commissionProvider);
      expect(s.step, 0);
      expect(s.lastDone, '上一台已完成：站 80 閘道器 1');
      expect(s.savedResume, isFalse);
      expect(s.savedProgress, isFalse);
      expect(find.byKey(const Key('last-done')), findsOneWidget);
      expect(find.byKey(const Key('restart-after-done')), findsNothing);
      expect(find.byKey(const Key('saved-resume')), findsNothing);
      expect(find.textContaining('上次配置'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
