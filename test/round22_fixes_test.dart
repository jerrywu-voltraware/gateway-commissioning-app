// Round 22 (after field round 22, APP 150039d, firmware 1.7.31):
// 1. The automatic reconnect's texts end once the phone is back: step 8
//    went on assigning (2/5 → 5/5) while the list card still said
//    「正在自動重新連線…」 and the button 「重新連線中…」. Reconnected →
//    「重新讀取 PTU 列表…」, list read / assigning again → nothing left; a
//    new loss is 「重新連線中」 again at once.
// 2. The step 8 progress names the retrying PTU (「4/5 完成，PTU #5 自動
//    重試中（1/2）」) — its row was often below the fold and 「1 台自動重試
//    中」 did not say which.
// 3. No 「已選 0 / 5 台」 while the PTU list is read (「讀取中…」 instead).
// 4. Switching direct ↔ star at step 7 drops the old mode's list and reads
//    it again; until the new list is in, the configure button is disabled
//    and says why (field: direct → star kept 「配置 1 台並開始監控」).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/assign_progress.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';

import 'link_loss_test.dart' show pumpApp, ready;
import 'round12_fixes_test.dart' show ScanDropLink;
import 'round13_fixes_test.dart' show Round13Link;
import 'round15_direct_flow_test.dart' show PickGateway;
import 'round21_fixes_test.dart' show R21Assign;

const _pick = 'AA:BB:CC:00:00:02';
const _third = 'AA:BB:CC:00:00:03';

/// Round 13's step 8 link: after its drop, the assign that finds [holdAt]
/// PTUs assigned waits for [hold] (step 8 assigning again).
class _HoldAfterDrop extends Round13Link {
  int holdAt = 2;
  Completer<void>? hold;
  bool holding = false;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final gate = hold;
    if (op == 'assign_device_id' &&
        !down &&
        dropsAt.isEmpty &&
        assigns.length == holdAt &&
        gate != null &&
        !gate.isCompleted) {
      holding = true;
      await gate.future;
      holding = false;
    }
    return super.command(op, params);
  }
}

/// Step 7 scan held until [scanGate] completes.
class _GatedScan extends ScanDropLink {
  Completer<void>? scanGate;
  bool scanWaiting = false;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final gate = scanGate;
    if (op == 'scan_ble_discover' && !down && gate != null) {
      scanWaiting = true;
      await gate.future;
      scanWaiting = false;
    }
    return super.command(op, params);
  }
}

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
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// [items] without repeats in a row.
List<T> _changes<T>(Iterable<T?> items) {
  final out = <T>[];
  for (final t in items) {
    if (t != null && (out.isEmpty || out.last != t)) out.add(t);
  }
  return out;
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'condition not reached');
}

/// Direct flow step 7 (firmware 1.7.20+): the gateway's pick shown.
Future<(ProviderContainer, CommissioningController)> _directStep7(
  PickGateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.direct);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  return (container, c);
}

Text _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key)));

String _plain(Text text) => text.data ?? text.textSpan!.toPlainText();

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

  group('1. the automatic reconnect\'s texts end once the phone is back', () {
    test('step 8: reconnecting → reading → assigning again, and once it '
        'assigns nothing says 重新連線中 / 正在自動重新連線 / 已中斷', () async {
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
      expect(s.relinking, isFalse);

      final relinking = states.where((x) => x.relinking).toList();
      expect(_changes(relinking.map((x) => x.relinkStage)), [
        RelinkStage.reconnecting,
        RelinkStage.reloading,
        RelinkStage.resumed,
      ]);
      final back = relinking
          .where((x) => x.relinkStage != RelinkStage.reconnecting)
          .toList();
      final resumed = back
          .where((x) => x.relinkStage == RelinkStage.resumed)
          .toList();
      // It really assigned while resumed (field: 2/5 → 5/5).
      expect(
        _changes(resumed.map((x) => assignProgressText(x.assignStatus))),
        hasLength(greaterThan(1)),
      );
      for (final x in back) {
        expect(configureLabel(x), isNot(relinkingLabel));
        expect(linkLostHint(x), isNot(contains('已中斷')));
        expect(relinkBack(x), isTrue);
      }
      for (final x in resumed) {
        expect(relinkShown(x), isFalse);
        expect(relinkStatusText(x), isNull);
        expect(configureLabel(x), isNot(relistingLabel));
      }
      // While it reconnects it still says so.
      final reconnecting = relinking.firstWhere(
        (x) => x.relinkStage == RelinkStage.reconnecting,
      );
      expect(relinkShown(reconnecting), isTrue);
      expect(configureLabel(reconnecting), relinkingLabel);
    });

    test('a new loss while assigning again is 重新連線中 at once', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      fake.dropsAt.addAll([1, 2]);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(
        _changes(states.where((x) => x.relinking).map((x) => x.relinkStage)),
        [
          RelinkStage.reconnecting,
          RelinkStage.reloading,
          RelinkStage.resumed,
          RelinkStage.reconnecting,
          RelinkStage.reloading,
          RelinkStage.resumed,
        ],
      );
      // Between the rounds: never idle with the resumed stage (no text at
      // all) nor a tappable 重新連線並繼續.
      final between = states
          .where((x) => x.relinking && !x.busy && x.step == 5)
          .toList();
      expect(between, isNotEmpty);
      for (final x in between) {
        expect(x.relinkStage, RelinkStage.reconnecting);
        expect(configureLabel(x), relinkingLabel);
      }
    });

    test('step 7: the list read by the automatic reconnect ends it — an '
        'empty list is 重新掃描, not a stuck 掃描中…', () async {
      final fake = ScanDropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.scanDrops = 1;
      fake.devices.clear();
      await c.discover();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.relinking, isFalse);
      expect(s.ptus, isEmpty);
      expect(s.rescanNeeded, isTrue);
      expect(configureLabel(s), rescanLabel);
    });

    testWidgets('page: assigning again after the reconnect — the list card, '
        'the button and the status card no longer say it reconnects', (
      tester,
    ) async {
      final fake = _HoldAfterDrop();
      final container = await pumpApp(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await tester.runAsync(
        () => c.configureWifi(1, 1, 'Office-2G', 'pw123456'),
      );
      // Provisioning logs in; this fixture intentionally continues offline.
      c.backendChanged('https://offline-fixture.invalid');
      await c.online(skip: true);
      await c.discover();
      fake.dropsAt.add(1);
      fake.hold = Completer<void>();
      late Future<void> run;
      await tester.runAsync(() async {
        run = c.configurePtus();
        await _until(() => fake.holding);
      });
      await tester.pump();

      var s = container.read(commissionProvider);
      expect(s.busy, isTrue);
      expect(s.relinking, isTrue);
      expect(s.relinkStage, RelinkStage.resumed);
      final configure = find.byKey(const Key('ptu-configure'));
      expect(tester.widget<FilledButton>(configure).onPressed, isNull);
      expect(
        find.descendant(of: configure, matching: find.text(relinkingLabel)),
        findsNothing,
      );
      expect(find.text(autoRelinkingText), findsNothing);
      expect(find.byKey(const Key('relink-status')), findsNothing);
      expect(find.textContaining('已中斷'), findsNothing);
      expect(find.textContaining('重新連線中'), findsNothing);
      expect(find.byKey(const Key('assign-progress-text')), findsOneWidget);
      expect(tester.takeException(), isNull);

      fake.hold!.complete();
      await tester.runAsync(() => run);
      await tester.pump();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(s.relinking, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('2. the progress names the retrying PTU', () {
    const done = AssignStatus(AssignPhase.done, id: 1);
    String name(String mac) =>
        {'m3': 'PTU #3', 'm4': 'PTU #4', 'm5': 'PTU …3B…'}[mac] ?? mac;

    test('texts: one with its retry, busy without, two, three, failed', () {
      const retry = AssignStatus(
        AssignPhase.linkRetry,
        id: 5,
        retry: 1,
        retries: 2,
      );
      final four = {'m1': done, 'm2': done, 'm3': done, 'm4': done};
      expect(
        assignProgressText({...four, 'm5': retry}, name: name),
        '4/5 完成，PTU …3B… 自動重試中（1/2）',
      );
      expect(
        assignProgressText({
          ...four,
          'm5': const AssignStatus(AssignPhase.busy, id: 5, retries: 2),
        }, name: name),
        '4/5 完成，PTU …3B… 自動重試中',
      );
      expect(
        assignProgressText({
          'm1': done,
          'm2': done,
          'm3': done,
          'm4': const AssignStatus(AssignPhase.retry, retry: 1, retries: 2),
          'm5': retry,
        }, name: name),
        '3/5 完成，PTU #4、PTU …3B… 自動重試中',
      );
      expect(
        assignProgressText({
          'm1': done,
          'm2': done,
          'm3': const AssignStatus(AssignPhase.busy),
          'm4': const AssignStatus(AssignPhase.retry, retry: 1, retries: 2),
          'm5': retry,
        }, name: name),
        '2/5 完成，PTU #3、PTU #4 等 3 台自動重試中',
      );
      expect(
        assignProgressText({
          'm1': done,
          'm2': done,
          'm3': done,
          'm4': const AssignStatus(AssignPhase.retry, retry: 2, retries: 2),
          'm5': const AssignStatus(AssignPhase.failed),
        }, name: name),
        '3/5 完成，PTU #4 自動重試中（2/2），1 台失敗需處理',
      );
      // Unnamed (a count only) stays as before.
      expect(assignProgressText({...four, 'm5': retry}), '4/5 完成，1 台自動重試中');
    });

    test('assignPtuName: the row\'s number, else the MAC bytes that tell it '
        'apart (field bench 90:xx:E8:9A:96:00)', () {
      final fleet = [
        for (final b in ['5F', '2C', '08', '3B', '74']) '90:$b:E8:9A:96:00',
      ];
      final s = CommissionState(
        ptus: [
          for (final (i, mac) in fleet.indexed)
            {'mac': mac, 'device_number': i == 4 ? 0 : (i == 3 ? 255 : i + 1)},
        ],
      );
      expect(assignPtuName(s, fleet[0]), 'PTU #1');
      expect(assignPtuName(s, fleet[2]), 'PTU #3');
      // Reset (255) and unassigned (0) rows read 「未指派 PTU」: by MAC.
      expect(assignPtuName(s, fleet[3]), 'PTU …3B…');
      expect(assignPtuName(s, fleet[4]), 'PTU …74…');
      expect(
        assignProgressLine(
          s.copy(
            assignStatus: {
              for (final mac in fleet.take(4)) mac: done,
              fleet[4]: const AssignStatus(
                AssignPhase.linkRetry,
                id: 5,
                retry: 1,
                retries: 2,
              ),
            },
          ),
        ),
        '4/5 完成，PTU …74… 自動重試中（1/2）',
      );
    });

    testWidgets('411x891 at text scale 1.1: the 5th PTU retries — the top '
        'names it as its row shows it', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fake = R21Assign()
        ..plan[4] = ['133']
        ..holdIndex = 4
        ..holdTry = 2
        ..hold = Completer<void>();
      final container = await pumpApp(tester, fake, size: const Size(411, 891));
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
      late Future<void> run;
      await tester.runAsync(() async {
        run = c.configurePtus();
        await _until(() => fake.holding);
      });
      await tester.pump();
      final retrying = fake.order[4];
      final s = container.read(commissionProvider);
      expect(s.assignStatus[retrying]!.phase, AssignPhase.linkRetry);
      final page = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      final header = find.byKey(const Key('assign-progress'));
      await tester.scrollUntilVisible(header, 60, scrollable: page);
      await tester.pump();
      final text = _plain(_text(tester, 'assign-progress-text'));
      // Unassigned rows (「未指派 PTU」): the bytes of the row's MAC.
      final tail = retrying.substring(retrying.length - 2);
      expect(text, '4/5 完成，PTU …$tail 自動重試中（1/2）');
      expect(
        find.descendant(
          of: find.byKey(ValueKey('ptu-$retrying')),
          matching: find.textContaining(tail),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);

      fake.hold!.complete();
      await tester.runAsync(() => run);
      await tester.pump();
      expect(container.read(commissionProvider).step, 6);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('3. no 已選 0 / 5 台 while the list is read', () {
    test('a first scan and a reconnect\'s list read say 讀取中…', () async {
      final fake = ScanDropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.discover();
      fake.scanDrops = 1;
      await c.discover();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.ptus, isNotEmpty);
      expect(selectionCountText(s, 5), startsWith('已選 '));
      final reading = states
          .where((x) => x.step == 4 && (x.busy || x.relinking))
          .toList();
      expect(reading.where((x) => x.ptus.isEmpty), isNotEmpty);
      for (final x in reading) {
        expect(selectionCountText(x, 5), isNot(startsWith('已選 0')));
      }
      for (final x in reading.where((x) => x.ptus.isEmpty)) {
        expect(selectionCountText(x, 5), ptuListLoadingText(5));
      }
      // The reconnect's list read in particular (field: 已選 0 / 5 台
      // beside 重新讀取 PTU 列表…).
      final reload = states
          .where((x) => relinkStatusText(x) == relinkReloadText)
          .toList();
      expect(reload, isNotEmpty);
      for (final x in reload) {
        expect(selectionCountText(x, 5), isNot(startsWith('已選 0')));
      }
    });

    testWidgets('page: the bottom bar says 讀取中… during 重新讀取 PTU 列表…', (
      tester,
    ) async {
      final fake = _GatedScan();
      final container = await pumpApp(tester, fake, size: const Size(411, 891));
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
      expect(_plain(_text(tester, 'ptu-selection-count')), startsWith('已選 '));
      // A drop during the scan; the reconnect's list read is held.
      fake.scanDrops = 1;
      late Future<void> run;
      await tester.runAsync(() async {
        run = c.discover();
        await _until(() => fake.down);
        fake.scanGate = Completer<void>();
        await _until(() => fake.scanWaiting);
      });
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.relinking, isTrue);
      expect(s.ptus, isEmpty);
      expect(_plain(_text(tester, 'relink-status')), relinkReloadText);
      expect(
        _plain(_text(tester, 'ptu-selection-count')),
        ptuListLoadingText(5),
      );
      expect(find.textContaining('已選 0'), findsNothing);
      expect(tester.takeException(), isNull);

      fake.scanGate!.complete();
      await tester.runAsync(() => run);
      await tester.pump();
      expect(_plain(_text(tester, 'ptu-selection-count')), startsWith('已選 '));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. a topology switch at step 7 reads the list again', () {
    test('direct → star: the direct pick is dropped, the star list read; '
        'the button waits for it and says why', () async {
      final fake = _GatedPick();
      final (container, c) = await _directStep7(fake);
      addTearDown(container.dispose);
      await c.identify();
      var s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(c.directFlow, isTrue);
      expect(s.selected, {_pick});
      expect(s.identifyNote, isNotEmpty);

      fake.scanGate = Completer<void>();
      final switching = c.switchTopology(GatewayTopology.star);
      await _until(() => fake.scanWaiting);
      s = container.read(commissionProvider);
      expect(container.read(topologyProvider).topology, GatewayTopology.star);
      expect(s.busy, isTrue);
      expect(s.ptus, isEmpty);
      expect(s.selected, isEmpty);
      expect(s.identifyNote, isEmpty);
      expect(s.direct, isNull);
      expect(s.relistReason, '已切換為星狀模式');
      expect(configureLabel(s), relistingLabel);
      expect(selectionCountText(s, 5), '已切換為星狀模式，重新讀取 PTU 列表…');

      fake.scanGate!.complete();
      await switching;
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.relistReason, isEmpty);
      expect(s.ptus, hasLength(3));
      expect(s.selected, hasLength(3));
      expect(configureLabel(s), '配置 3 台並開始監控');
      expect(selectionCountText(s, 5), '已選 3 / 5 台');
    });

    test('direct → star undoes a temporary 不是這台？ binding first', () async {
      final fake = PickGateway();
      final (container, c) = await _directStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick(_third);
      expect(container.read(commissionProvider).tempBoundMac, _third);
      final before = fake.ops.length;
      await c.switchTopology(GatewayTopology.star);
      final s = container.read(commissionProvider);
      expect(s.tempBoundMac, isNull);
      final after = fake.ops.skip(before).toList();
      final unbind = after.indexWhere(
        (e) => e.$1 == 'set_config' && e.$2['direct_bind_mac'] == '',
      );
      expect(unbind, isNot(-1));
      expect(
        unbind,
        lessThan(after.indexWhere((e) => e.$1 == 'scan_ble_discover')),
      );
      expect(s.ptus, hasLength(3));
    });

    test(
      'star → direct: the star list is dropped, the gateway picks again',
      () async {
        final fake = PickGateway();
        final (container, c) = await _directStep7(fake);
        addTearDown(container.dispose);
        await c.switchTopology(GatewayTopology.star);
        expect(container.read(commissionProvider).selected, hasLength(3));
        await c.switchTopology(GatewayTopology.direct);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.relistReason, isEmpty);
        expect(s.selected, {_pick});
        expect(s.ptus.map((p) => p['mac']), [_pick]);
        expect(fake.config['max_connections'], 1);
      },
    );

    test('a switch that could not read at once: the list stays dropped, the '
        'button is 重新掃描 (never the old count)', () async {
      final fake = PickGateway();
      final (container, c) = await _directStep7(fake);
      addTearDown(container.dispose);
      // Not through the menu (e.g. applied after a running step).
      await container
          .read(topologyProvider.notifier)
          .setTopology(GatewayTopology.star);
      var s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.ptus, isEmpty);
      expect(s.selected, isEmpty);
      expect(configureLabel(s), rescanLabel);
      expect(selectionCountText(s, 5), '已切換為星狀模式，PTU 列表需重新讀取');
      await c.discover();
      s = container.read(commissionProvider);
      expect(s.relistReason, isEmpty);
      expect(s.ptus, hasLength(3));
      expect(configureLabel(s), '配置 3 台並開始監控');
    });

    test('outside step 7 a switch only changes the setting', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      expect(container.read(commissionProvider).step, 6);
      final ptus = container.read(commissionProvider).ptus;
      await c.switchTopology(GatewayTopology.direct);
      final s = container.read(commissionProvider);
      expect(container.read(topologyProvider).topology, GatewayTopology.direct);
      expect(s.step, 6);
      expect(s.ptus, ptus);
      expect(s.relistReason, isEmpty);
    });

    testWidgets('page 411x891: 拓撲 → 星狀 at step 7 — the button is disabled '
        'with the reason until the star list is in, never 配置 1 台', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      expect(container.read(commissionProvider).selected, {_pick});

      fake.scanGate = Completer<void>();
      await tester.tap(find.byKey(const Key('topology-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topology-settings-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topology-option-star')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fake.scanWaiting, isTrue);
      final configure = find.byKey(const Key('ptu-configure'));
      expect(tester.widget<FilledButton>(configure).onPressed, isNull);
      expect(
        find.descendant(of: configure, matching: find.text(relistingLabel)),
        findsOneWidget,
      );
      expect(
        _plain(_text(tester, 'ptu-selection-count')),
        '已切換為星狀模式，重新讀取 PTU 列表…',
      );
      expect(find.textContaining('配置 1 台'), findsNothing);
      expect(find.textContaining('已選 1'), findsNothing);
      expect(tester.takeException(), isNull);

      fake.scanGate!.complete();
      for (var i = 0; i < 50 && container.read(commissionProvider).busy; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.ptus, hasLength(3));
      expect(tester.widget<FilledButton>(configure).onPressed, isNotNull);
      expect(
        find.descendant(of: configure, matching: find.text('配置 3 台並開始監控')),
        findsOneWidget,
      );
      expect(_plain(_text(tester, 'ptu-selection-count')), '已選 3 / 5 台');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
