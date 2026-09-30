// Round 23 (after field round 23, APP 552fb6e, firmware 1.7.31):
// 1. While step 8 assigns (a busy retry included) the configure button
//    shows the run — a disabled 「配置中… 1/5」 with the same count as the
//    progress line — never the idle 「配置 5 台並開始監控」 (field: grey
//    beside 「0/5 完成，PTU #1 自動重試中」, read as not started).
// 2. The list card's count says 「讀取中…」 while the list is read and
//    counts only once it is in (field: 「已連線 0 台／周邊未連線 0 台」 during
//    the re-read after a topology switch, read as nothing found).
// 3. Back to star at step 7, the gateway still connects one PTU until
//    「配置」 (by design): a line under the count says 「配置」 switches it
//    to star and connects all.
// 4. After the gateway connect the page starts at its title (the connect
//    jumps to the top) and 「下一步：選擇站點」 was a swipe away: the
//    network check's 「下一步」 is pinned in the bottom bar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/assign_progress.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';

import 'link_loss_test.dart' show pumpApp, ready;
import 'network_check_test.dart' show WifiGateway;
import 'round13_fixes_test.dart' show Round13Link;
import 'round15_direct_flow_test.dart' show PickGateway;
import 'round21_fixes_test.dart' show R21Assign;
import 'support/pick_gateway.dart';

const _phone = Size(360, 640);

/// The direct flow's gateway; a star scan is held until [scanGate]
/// completes.
class _GatedPick extends PickGateway {
  Completer<void>? scanGate;
  bool scanWaiting = false;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final gate = scanGate;
    if (op == 'scan_ble_discover' && gate != null) {
      scanWaiting = true;
      await gate.future;
      scanWaiting = false;
    }
    return super.command(op, params);
  }
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200, version: '1');
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'condition not reached');
}

Text _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key)));

String _plain(Text text) => text.data ?? text.textSpan!.toPlainText();

/// 360x640 at the field phone's font scale 1.1.
void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// The page's own scroll view (the first one; the list inside is lazy).
Finder get _page => find
    .descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    )
    .first;

/// 「d/n」 of a progress line or an [assigningLabel].
String? _count(String? text) =>
    text == null ? null : RegExp(r'\d+/\d+').firstMatch(text)?.group(0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepGap, keepPoll, keepSwitch;
  setUp(() {
    keepGap = connectRetryGap;
    keepPoll = directPollInterval;
    keepSwitch = directSwitchWait;
    connectRetryGap = const Duration(milliseconds: 1);
    directPollInterval = const Duration(milliseconds: 1);
    directSwitchWait = const Duration(milliseconds: 60);
  });
  tearDown(() {
    connectRetryGap = keepGap;
    directPollInterval = keepPoll;
    directSwitchWait = keepSwitch;
  });

  group('1. the configure button shows the assignment run', () {
    test(
      'a busy retry at 1/5: 配置中… 1/5 like the progress line; the '
      'idle 配置 n 台 never shows while it runs, and it ends with the run',
      () async {
        final fake = R21Assign()
          ..plan[1] = ['busy']
          ..holdIndex = 1
          ..holdTry = 2
          ..hold = Completer<void>();
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        final states = <CommissionState>[];
        container.listen(commissionProvider, (_, s) => states.add(s));
        expect(
          configureLabel(container.read(commissionProvider)),
          '配置 5 台並開始監控',
        );

        final run = c.configurePtus();
        await _until(() => fake.holding);
        var s = container.read(commissionProvider);
        expect(s.busy, isTrue);
        expect(s.step, 5);
        expect(s.assignRunning, isTrue);
        expect(assignProgressLine(s), startsWith('1/5 完成'));
        expect(configureLabel(s), '配置中… 1/5');
        expect(configureLabel(s), assigningLabel(s.assignStatus));

        fake.hold!.complete();
        await run;
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 6);
        expect(s.busy, isFalse);
        expect(s.assignRunning, isFalse);

        final running = states.where((x) => x.busy && x.step == 5).toList();
        expect(running, isNotEmpty);
        for (final x in running) {
          final label = configureLabel(x);
          expect(label, startsWith('配置中… '), reason: label);
          expect(label, isNot(contains('並開始監控')));
          expect(_count(label), _count(assignProgressText(x.assignStatus)));
        }
        // The progress went on under the same button (0/5 → 5/5).
        expect(
          running.map((x) => configureLabel(x)).toSet(),
          containsAll(['配置中… 0/5', '配置中… 1/5', '配置中… 5/5']),
        );
      },
    );

    test('after an automatic reconnect it assigns again under 配置中…, and a '
        'new loss is 重新連線中… at once', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      fake.dropsAt.add(1);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(s.assignRunning, isFalse);
      final resumed = states
          .where(
            (x) =>
                x.relinking &&
                x.relinkStage == RelinkStage.resumed &&
                x.busy &&
                x.step == 5 &&
                !x.resumePending,
          )
          .toList();
      expect(resumed, isNotEmpty);
      for (final x in resumed) {
        expect(configureLabel(x), startsWith('配置中… '));
      }
      // While it reconnects the button still says so (the run's own
      // label only once it assigns again).
      final reconnecting = states.where(
        (x) => x.relinking && x.relinkStage == RelinkStage.reconnecting,
      );
      expect(reconnecting, isNotEmpty);
      for (final x in reconnecting) {
        expect(configureLabel(x), relinkingLabel);
      }
    });

    test('labels: 配置中… d/n only while a step 8 run is busy', () {
      final statuses = {
        'a': const AssignStatus(AssignPhase.done, id: 1),
        'b': const AssignStatus(AssignPhase.busy),
        'c': const AssignStatus(AssignPhase.waiting),
      };
      expect(assigningLabel(statuses), '配置中… 1/3');
      final base = CommissionState(
        step: 5,
        busy: true,
        assignRunning: true,
        assignStatus: statuses,
        selected: const {'a', 'b', 'c'},
        assignedOk: const {'a'},
      );
      expect(assigningShown(base), isTrue);
      expect(configureLabel(base), '配置中… 1/3');
      expect(assigningShown(base.copy(busy: false)), isFalse);
      expect(assigningShown(base.copy(assignRunning: false)), isFalse);
      expect(assigningShown(base.copy(step: 4)), isFalse);
      expect(configureLabel(base.copy(busy: false)), '配置剩餘 2 台並開始監控');
    });

    testWidgets('page 360x640 at scale 1.1: during a busy retry the bottom '
        'button is a disabled 配置中… 1/5 matching the top', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fake = R21Assign()
        ..plan[1] = ['busy']
        ..holdIndex = 1
        ..holdTry = 2
        ..hold = Completer<void>();
      final container = await pumpApp(tester, fake, size: _phone);
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(() async {
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.configureWifi(1, 1, 'Office-2G', 'pw123456');
        // Provisioning logs in; this fixture intentionally continues offline.
        c.backendChanged('https://offline-fixture.invalid');
        await c.online(skip: true);
        await c.discover();
      });
      await tester.pump();
      final configure = find.byKey(const Key('ptu-configure'));
      expect(
        find.descendant(of: configure, matching: find.text('配置 5 台並開始監控')),
        findsOneWidget,
      );

      late Future<void> run;
      await tester.runAsync(() async {
        run = c.configurePtus();
        await _until(() => fake.holding);
      });
      await tester.pump();
      expect(configure.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(configure).onPressed, isNull);
      expect(
        find.descendant(of: configure, matching: find.text('配置中… 1/5')),
        findsOneWidget,
      );
      // The idle button texts (「配置 5 台…」「配置剩餘 4 台…」) are gone.
      expect(find.textContaining(RegExp(r'^配置(剩餘)? \d+ 台並')), findsNothing);
      final header = find.byKey(const Key('assign-progress'));
      await tester.scrollUntilVisible(header, 60, scrollable: _page);
      await tester.pump();
      final progress = _plain(_text(tester, 'assign-progress-text'));
      expect(progress, startsWith('1/5 完成'));
      expect(_count(progress), '1/5');
      expect(tester.takeException(), isNull);

      fake.hold!.complete();
      await tester.runAsync(() => run);
      await tester.pump();
      expect(container.read(commissionProvider).step, 6);
      expect(find.textContaining('配置中…'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('2. the list count says 讀取中… until the list is read', () {
    test('ptuCountText: reading, not read after a switch, then the count', () {
      const reading = CommissionState(step: 4, busy: true);
      expect(ptuCountText(reading), ptuCountReadingText);
      expect(ptuCountText(reading.copy(busy: false, relinking: true)), '讀取中…');
      expect(
        ptuCountText(reading.copy(step: 5, busy: true)),
        ptuCountReadingText,
      );
      const switched = CommissionState(step: 4, relistReason: '已切換為星狀模式');
      expect(ptuCountText(switched), ptuCountUnreadText);
      final listed = reading.copy(
        busy: false,
        ptus: [
          {'mac': 'a', 'connected': true},
          {'mac': 'b', 'connected': false},
          {'mac': 'c'},
        ],
      );
      expect(ptuCountText(listed), '已連線 1 台／周邊未連線 2 台');
      // A rescan keeps the rows on screen: they are what is counted.
      expect(ptuCountText(listed.copy(busy: true)), '已連線 1 台／周邊未連線 2 台');
      // A read that is over and found nothing says so.
      expect(ptuCountText(reading.copy(busy: false)), '已連線 0 台／周邊未連線 0 台');
    });

    test('a first scan: no state reading the list shows 已連線 0 台', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.discover();
      final reading = states
          .where((x) => x.step == 4 && x.busy && x.ptus.isEmpty)
          .toList();
      expect(reading, isNotEmpty);
      for (final x in reading) {
        expect(ptuCountText(x), ptuCountReadingText);
      }
      expect(
        ptuCountText(container.read(commissionProvider)),
        matches(RegExp(r'^已連線 \d+ 台／周邊未連線 \d+ 台$')),
      );
    });
  });

  group('3. star step 7 says 配置 connects all while the gateway is at 1', () {
    test('starApplyNote: star step 7, gateway below the star range, a PTU '
        'not connected', () {
      final s = CommissionState(
        step: 4,
        config: const {'max_connections': 1},
        ptus: const [
          {'mac': 'a', 'connected': true},
          {'mac': 'b', 'connected': false},
        ],
      );
      expect(starApplyNote(s, isStar: true), starApplyText(1));
      expect(starApplyText(1), contains('按下「配置」後，閘道器會切換為星狀並連線全部 PTU'));
      expect(starApplyNote(s, isStar: false), isNull);
      expect(starApplyNote(s.copy(step: 5), isStar: true), isNull);
      expect(
        starApplyNote(
          s.copy(config: const {'max_connections': maxStarPtuCount}),
          isStar: true,
        ),
        isNull,
      );
      expect(
        starApplyNote(s.copy(config: const {}), isStar: true),
        isNull,
        reason: 'unknown limit',
      );
      expect(
        starApplyNote(
          s.copy(
            ptus: const [
              {'mac': 'a', 'connected': true},
            ],
          ),
          isStar: true,
        ),
        isNull,
        reason: 'everything listed is connected',
      );
    });

    test(
      'direct → star: the note until 配置, which opens the star range',
      () async {
        final fake = PickGateway();
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
        await topo.setTopology(GatewayTopology.direct);
        final c = container.read(commissionProvider.notifier);
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.chooseStation(newStation: false);
        expect(fake.config['max_connections'], 1);

        await c.switchTopology(GatewayTopology.star);
        var s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.ptus.where((p) => p['connected'] != true), isNotEmpty);
        expect(starApplyNote(s, isStar: true), starApplyText(1));
        // The switch itself does not change the gateway (by design).
        expect(fake.config['max_connections'], 1);

        await c.configurePtus();
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(fake.config['max_connections'], maxStarPtuCount);
        expect(starApplyNote(s, isStar: true), isNull);
      },
    );

    testWidgets('page 360x640 at scale 1.1: 拓撲 → 星狀 — 讀取中… while the '
        'list is read, then the count and the 配置 note', (tester) async {
      _phoneView(tester);
      SharedPreferences.setMockInitialValues({});
      final fake = _GatedPick();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
            localBackendProberProvider.overrideWithValue(_Prober()),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(() async {
        final topo = container.read(topologyProvider.notifier);
        await topo.ready;
        await topo.setTopology(GatewayTopology.direct);
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.chooseStation(newStation: false);
      });
      await tester.pump();

      fake.scanGate = Completer<void>();
      await tester.tap(find.byKey(const Key('topology-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<String>,
          GatewayTopology.star.label,
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fake.scanWaiting, isTrue);
      final count = find.byKey(const Key('ptu-list-count'));
      await tester.scrollUntilVisible(count, 60, scrollable: _page);
      await tester.pump();
      expect(_plain(_text(tester, 'ptu-list-count')), ptuCountReadingText);
      expect(find.textContaining('已連線 0 台'), findsNothing);
      expect(find.textContaining('周邊未連線 0 台'), findsNothing);
      expect(find.byKey(const Key('star-apply-note')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ptu-configure')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);

      fake.scanGate!.complete();
      for (var i = 0; i < 50 && container.read(commissionProvider).busy; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.ptus, hasLength(3));
      await tester.scrollUntilVisible(count, 60, scrollable: _page);
      await tester.pump();
      final connected = s.ptus.where((p) => p['connected'] == true).length;
      expect(
        _plain(_text(tester, 'ptu-list-count')),
        '已連線 $connected 台／周邊未連線 ${3 - connected} 台',
      );
      final note = find.byKey(const Key('star-apply-note'));
      await tester.scrollUntilVisible(note, 60, scrollable: _page);
      await tester.pump();
      expect(note.hitTestable(), findsOneWidget);
      expect(_plain(_text(tester, 'star-apply-note')), starApplyText(1));
      // The note sits under the count, above the rows.
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getTopLeft(count).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ptu-configure')),
          matching: find.text('配置 3 台並開始監控'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. the network check\'s 下一步 is pinned at the bottom', () {
    Future<ProviderContainer> pumpCheckApp(
      WidgetTester tester,
      WifiGateway fake,
    ) async {
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'production',
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
            envSwitchPolicyProvider.overrideWithValue(
              const EnvSwitchPolicy(
                autoSyncDefault: false,
                confirmGatewaySwitch: false,
              ),
            ),
            localBackendProberProvider.overrideWithValue(_Prober()),
            phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(GatewayApp)));
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    String title(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('step-title'))).data!;

    testWidgets('automatic check waits in background and resumes once', (
      tester,
    ) async {
      final fake = WifiGateway.station();
      final container = await pumpCheckApp(tester, fake);
      await tap(tester, find.text('檢查並開始'));
      final c = container.read(commissionProvider.notifier);
      unawaited(c.scan());
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      unawaited(c.connect(container.read(commissionProvider).peers.single));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).checkPassed, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).checkPassed, isTrue);
      final count = fake.commands.length;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 2);
      expect(
        fake.commands.length,
        count,
        reason: 'waiting for the site choice',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dialog blocks automatic check until dismissed', (
      tester,
    ) async {
      final fake = WifiGateway.station();
      final container = await pumpCheckApp(tester, fake);
      await tap(tester, find.text('檢查並開始'));
      unawaited(container.read(commissionProvider.notifier).scan());
      await tester.pumpAndSettle();
      final context = tester.element(find.byKey(const Key('step-title')));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Review'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        container
            .read(commissionProvider.notifier)
            .connect(container.read(commissionProvider).peers.single),
      );
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).checkPassed, isFalse);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).checkPassed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360x640 at scale 1.1: connected from a scrolled gateway list, '
        '繼續設定站點 is on screen without a swipe and stays put', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway.station()..config['wifi_ssid'] = 'Office-2G';
      final container = await pumpCheckApp(tester, fake);
      CommissionState read() => container.read(commissionProvider);
      BackendEnvState readEnv() => container.read(backendEnvProvider);
      await tap(tester, find.text('檢查並開始'));
      final gateway = find.byKey(const ValueKey('demo-gateway'));
      await tester.ensureVisible(gateway);
      await tester.pumpAndSettle();
      final scrolled = tester.widget<Scrollable>(_page).controller!.offset;
      await tester.tap(gateway);
      await tester.pumpAndSettle();
      // 1.0.0+14: the card's tap selects; the fixed bottom button connects.
      await tester.tap(gatewayConnectButton);
      await tester.pumpAndSettle();

      expect(title(tester), '6 / 10   站點選擇');
      expect(read().checkPassed, isTrue);
      expect(find.byKey(const Key('check-next')), findsNothing);
      // The page itself starts from the step title (the connect's jump to
      // the top, from where the gateway list was scrolled to).
      expect(tester.widget<Scrollable>(_page).controller!.offset, 0);
      expect(scrolled, greaterThan(0));
      expect(find.byKey(const Key('step-title')).hitTestable(), findsOneWidget);
      // Explicitly reviewing the check must not bounce straight forward.
      // 09-28: 「回到網路體檢」 is in 「設備與連線資訊」 while the check passed.
      await tester.scrollUntilVisible(
        find.text('設備與連線資訊'),
        120,
        scrollable: _page,
      );
      await tap(tester, find.text('設備與連線資訊'));
      await tap(tester, find.byKey(const Key('details-review-check')));
      expect(read().checkPassed, isFalse);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(read().checkPassed, isFalse);
      final next = find.byKey(const Key('check-next'));
      expect(next.hitTestable(), findsOneWidget);
      final rect = tester.getRect(next);
      expect(rect.bottom, lessThanOrEqualTo(_phone.height));
      expect(tester.takeException(), isNull);

      await tester.tap(next);
      await tester.pumpAndSettle();
      // The title may be scrolled away (the list builds lazily).
      expect(stepLabels[displayStep(read(), readEnv())], '站點選擇');
      expect(find.byKey(const Key('check-next')), findsNothing);
      // A later check on the same peer is automatic again.
      container.read(commissionProvider.notifier).backToNetworkCheck();
      await tester.pumpAndSettle();
      expect(read().checkPassed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360x640: a check that is not ready has no pinned 下一步 '
        '(重新檢查 in the card instead)', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      await pumpCheckApp(tester, fake);
      await tap(tester, find.text('檢查並開始'));
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      expect(find.byKey(const Key('check-next')), findsNothing);
      final refresh = find.byKey(const Key('check-refresh'));
      await tester.scrollUntilVisible(refresh, 120, scrollable: _page);
      await tester.pumpAndSettle();
      expect(refresh, findsOneWidget);
      expect(find.textContaining('下一步：'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
