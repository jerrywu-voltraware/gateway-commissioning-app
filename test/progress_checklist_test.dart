// 09-28 (user request after the second rehearsal: 第 5 步 「正在確認閘道器
// 上線，請稍候／處理中 · 最多等待 68 秒」 was one spinner and one sentence):
// the automatic steps as a checklist that fills in one item at a time.
// 1. The model: pending → running → done (result or time) / failed (the
//    reason; it stays on that item, nothing else keeps spinning).
// 2. The widget: grey circle / spinner 「進行中…」 / green tick / red cross,
//    and no overflow on a 360x640 phone.
// 3. The controller ticks items on real events: 確認上線 (連上後台 → 第 1
//    次心跳 → 第 2 次心跳 → 上傳目標), 正在連線並檢查網路 (藍牙 → 狀態 →
//    Wi-Fi → 後台), 正在配置 PTU (名單 → 指派 n/N → 加入監控 → 核對 →
//    驗證資料) and the one-to-one 正在完成設定 (綁定 → 設定 → 加入監控 →
//    核對 → 驗證資料); a failure stops on its item.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/auto_checklist.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/progress_checklist.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/progress_checklist.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// The back office always reports the same heartbeat: the second one
/// never comes.
class _StuckHeartbeat extends DemoSystem {
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final result = await super.request(method, path, body);
    if (path.contains('fleet-status')) {
      for (final row in (result['gateways'] as List)) {
        (row as Map)['last_heartbeat'] = 'same';
      }
    }
    return result;
  }
}

Future<(ProviderContainer, CommissioningController)> _toOnline(
  DemoSystem fake,
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
  await topo.setTopology(GatewayTopology.star);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'test', 'test-password');
  return (container, c);
}

/// Every checklist the controller published, in order.
List<Checklist> _record(ProviderContainer container) {
  final seen = <Checklist>[];
  container.listen<CommissionState>(commissionProvider, (previous, next) {
    final list = next.checklist;
    if (list != null && !identical(list, previous?.checklist)) seen.add(list);
  });
  return seen;
}

CheckStatus _status(Checklist list, String id) => list.item(id)!.status;

/// Items never skip ahead: whenever one is running or done, every item
/// before it is done (a failed or pending one stops the rest).
void _inOrder(List<Checklist> seen) {
  for (final list in seen) {
    var open = false;
    for (final item in list.items) {
      if (open) {
        expect(
          item.status,
          isNot(CheckStatus.running),
          reason: '${item.label} ran before an earlier item was done',
        );
      }
      if (item.status != CheckStatus.done) open = true;
    }
  }
}

Widget _app(List<CheckItem> items, {bool animate = true, String? footer}) =>
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ProgressChecklist(items: items, animate: animate, footer: footer),
          ],
        ),
      ),
    );

void _phone(WidgetTester tester, {double scale = 1.0}) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Finder _mark(String id, CheckStatus status) =>
    find.byKey(ValueKey('check-$id-${status.name}'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. the model', () {
    test('pending → running → done, one item after the other', () {
      var list = onlineChecklist();
      expect(
        list.items.map((i) => i.status),
        everyElement(CheckStatus.pending),
      );
      list = list.start(onlineItemBackend);
      expect(_status(list, onlineItemBackend), CheckStatus.running);
      list = list.done(onlineItemBackend).start(onlineItemBeat1);
      expect(_status(list, onlineItemBackend), CheckStatus.done);
      expect(list.item(onlineItemBackend)!.at, isNotNull);
      expect(_status(list, onlineItemBeat1), CheckStatus.running);
      list = list
          .done(onlineItemBeat1, note: '心跳 1/2')
          .start(onlineItemBeat2)
          .done(onlineItemBeat2, note: '心跳 2/2')
          .start(onlineItemTarget)
          .done(onlineItemTarget, note: '本地測試');
      expect(list.allDone, isTrue);
      expect(list.running, isFalse);
      expect(list.item(onlineItemBeat2)!.note, '心跳 2/2');
      expect(list.doneCount, 4);
    });

    test('a failure stops on the running item; nothing else keeps running; '
        'later items stay pending', () {
      var list = onlineChecklist()
          .start(onlineItemBackend)
          .done(onlineItemBackend)
          .done(onlineItemBeat1, note: '心跳 1/2')
          .start(onlineItemBeat2);
      list = list.fail('等待超時，請確認裝置與網路後重試。');
      expect(_status(list, onlineItemBackend), CheckStatus.done);
      expect(_status(list, onlineItemBeat1), CheckStatus.done);
      expect(_status(list, onlineItemBeat2), CheckStatus.failed);
      expect(list.item(onlineItemBeat2)!.note, '等待超時，請確認裝置與網路後重試。');
      expect(_status(list, onlineItemTarget), CheckStatus.pending);
      expect(list.failed, isTrue);
      expect(list.running, isFalse);

      // A named item fails; the running one goes back to pending.
      final named = onlineChecklist()
          .start(onlineItemBackend)
          .fail('資料送到別的後台', id: onlineItemTarget);
      expect(_status(named, onlineItemBackend), CheckStatus.pending);
      expect(_status(named, onlineItemTarget), CheckStatus.failed);
    });

    test('settle, progress, doneBefore, startNext; unknown ids change '
        'nothing', () {
      var list = finishChecklist(direct: false, starList: true, total: 5);
      expect(list.items.map((i) => i.label), [
        '寫入 PTU 名單',
        '指派 PTU（共 5 台）',
        '加入監控',
        '核對已加入監控',
        '驗證資料上傳',
      ]);
      expect(identical(list.start(finishItemBind), list), isTrue);
      list = list.startNext();
      expect(_status(list, finishItemList), CheckStatus.running);
      list = list.settle();
      expect(_status(list, finishItemList), CheckStatus.pending);
      list = list
          .done(finishItemList, note: '5 台')
          .progress(finishItemAssign, '2/5 台');
      expect(_status(list, finishItemAssign), CheckStatus.running);
      expect(list.item(finishItemAssign)!.note, '2/5 台');
      final done = list.done(finishItemAssign, note: '5/5 台');
      expect(identical(done.progress(finishItemAssign, 'x'), done), isFalse);
      expect(
        done.progress(finishItemAssign, 'x').item(finishItemAssign)!.note,
        '5/5 台',
        reason: 'a done item keeps its result',
      );
      final later = finishChecklist(
        direct: true,
      ).doneBefore(finishItemData, note: '先前已完成');
      expect(later.doneCount, 4);
      expect(_status(later, finishItemData), CheckStatus.pending);
      expect(finishChecklist(direct: true).items.map((i) => i.label), [
        '寫入 PTU 綁定',
        '寫入 PTU 設定',
        '加入監控',
        '核對已加入監控',
        '驗證資料上傳',
      ]);
      expect(connectChecklist().items.map((i) => i.label), [
        '藍牙連線',
        '讀取閘道器狀態',
        'Wi-Fi 已連線',
        '後台連線正常',
      ]);
    });

    test('the reason is what happened, from the first sentence of the '
        'error; the advice stays in the red box below', () {
      expect(checklistReason('等待超時，請確認裝置與網路後重試。'), '等待超時');
      expect(
        checklistReason('後端找不到此閘道器。可能在別的後台。\n[HTTP 404 · /x]'),
        '後端找不到此閘道器',
      );
      expect(checklistReason('資料驗證未通過：\n#1 沒有資料'), '資料驗證未通過');
      expect(
        checklistReason('手機與閘道器的藍牙連線中斷，請靠近閘道器後按「重新連線並繼續」'),
        '手機與閘道器的藍牙連線中斷',
      );
      expect(checklistReason(null), '沒有完成');
      expect(uploadTargetNote(null), '送到目前的後台');
    });
  });

  group('2. the widget', () {
    testWidgets('pending grey circle, running spinner 「進行中…」, done green '
        'tick with its result or time, failed red cross with the reason', (
      tester,
    ) async {
      _phone(tester);
      final list = onlineChecklist()
          .done(onlineItemBackend, at: DateTime(2026, 9, 28, 14, 3, 5))
          .done(onlineItemBeat1, note: '心跳 1/2')
          .start(onlineItemBeat2);
      await tester.pumpWidget(_app(list.items, footer: '最多等待 68 秒'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_mark(onlineItemBackend, CheckStatus.done), findsOneWidget);
      expect(find.textContaining('14:03:05 完成'), findsOneWidget);
      expect(find.textContaining('心跳 1/2'), findsOneWidget);
      expect(_mark(onlineItemBeat2, CheckStatus.running), findsOneWidget);
      expect(
        find.descendant(
          of: _mark(onlineItemBeat2, CheckStatus.running),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('進行中…'), findsOneWidget);
      expect(_mark(onlineItemTarget, CheckStatus.pending), findsOneWidget);
      // The total wait stays, in small print.
      expect(find.text('最多等待 68 秒'), findsOneWidget);
      final footer = tester.widget<Text>(
        find.byKey(const Key('checklist-footer')),
      );
      expect(footer.style!.fontSize, lessThan(14));

      // The next state: 第 2 次心跳 done (a short scale-in), the target
      // runs, then the failure of the last one stays on it.
      await tester.pumpWidget(
        _app(
          list
              .done(onlineItemBeat2, note: '心跳 2/2')
              .start(onlineItemTarget)
              .items,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ScaleTransition), findsWidgets);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_mark(onlineItemBeat2, CheckStatus.done), findsOneWidget);
      expect(find.textContaining('心跳 2/2'), findsOneWidget);
      expect(_mark(onlineItemTarget, CheckStatus.running), findsOneWidget);

      await tester.pumpWidget(
        _app(
          list
              .done(onlineItemBeat2, note: '心跳 2/2')
              .start(onlineItemTarget)
              .fail('資料送到別的後台，請依下方提示處理')
              .items,
          animate: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(_mark(onlineItemTarget, CheckStatus.failed), findsOneWidget);
      expect(find.textContaining('資料送到別的後台，請依下方提示處理'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('not animated (the network check waits with nothing running): '
        'an hourglass, no spinner — the page can settle', (tester) async {
      _phone(tester);
      final list = connectChecklist()
          .done(connectItemBle)
          .done(connectItemStatus, note: '韌體 1.7.41')
          .done(connectItemWifi, note: 'Xiaomi_WU')
          .start(connectItemBackend);
      await tester.pumpWidget(_app(list.items, animate: false));
      await tester.pumpAndSettle();
      expect(_mark(connectItemBackend, CheckStatus.running), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('進行中…'), findsOneWidget);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('360x640 at text scale $scale: long labels and reasons wrap, '
          'no overflow', (tester) async {
        _phone(tester, scale: scale);
        final list = finishChecklist(direct: false, starList: true, total: 5)
            .done(finishItemList, note: '5 台')
            .progress(finishItemAssign, '3/5 台')
            .fail('與閘道器的藍牙連線中斷，已完成的 3 台會保留，請靠近閘道器後按「重新連線並繼續」');
        await tester.pumpWidget(_app(list.items, footer: '最多等待 240 秒'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        final box = tester.getRect(find.byType(ProgressChecklist));
        expect(box.right, lessThanOrEqualTo(360));
        expect(_mark(finishItemAssign, CheckStatus.failed), findsOneWidget);
      });
    }
  });

  group('3. the controller ticks items on real events', () {
    late Duration keepPoll, keepGap, keepBackendGap, keepSwitch;
    late List<Duration> keepGaps;
    setUp(() {
      keepPoll = directPollInterval;
      keepSwitch = directSwitchWait;
      directSwitchWait = const Duration(milliseconds: 60);
      keepGaps = step7RetryGaps;
      keepGap = connectRetryGap;
      keepBackendGap = backendRetryGap;
      directPollInterval = const Duration(milliseconds: 1);
      step7RetryGaps = const [
        Duration(milliseconds: 1),
        Duration(milliseconds: 2),
        Duration(milliseconds: 3),
      ];
      connectRetryGap = const Duration(milliseconds: 1);
      backendRetryGap = const Duration(milliseconds: 1);
    });
    tearDown(() {
      directPollInterval = keepPoll;
      directSwitchWait = keepSwitch;
      step7RetryGaps = keepGaps;
      connectRetryGap = keepGap;
      backendRetryGap = keepBackendGap;
    });

    test('正在連線並檢查網路: 藍牙連線 → 讀取閘道器狀態, then Wi-Fi and 後台 '
        'from what the gateway reports', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = DemoSystem();
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '');
      await c.scan();
      final seen = _record(container);
      await c.connect(container.read(commissionProvider).peers.single);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      _inOrder(seen);
      expect(seen.first.kind, ChecklistKind.connect);
      expect(_status(seen.first, connectItemBle), CheckStatus.running);
      expect(
        seen.any(
          (l) =>
              l.isDone(connectItemBle) &&
              _status(l, connectItemStatus) == CheckStatus.running,
        ),
        isTrue,
      );
      final list = s.checklist!;
      expect(list.isDone(connectItemBle), isTrue);
      expect(list.isDone(connectItemStatus), isTrue);
      expect(list.item(connectItemStatus)!.note, startsWith('韌體 '));
      // Wi-Fi and 後台 follow the network check.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final now = container.read(commissionProvider);
      final env = container.read(backendEnvProvider);
      final check = networkCheck(state: now, env: env);
      final shown = shownChecklist(now, check: check)!;
      expect(shown.isDone(connectItemWifi), check.wifiOk);
      expect(shown.isDone(connectItemBackend), check.ready);
    });

    test('確認上線: 連上後台 → 第 1 次心跳 → 第 2 次心跳 → 上傳目標, each '
        'after the one before', () async {
      final (container, c) = await _toOnline(DemoSystem());
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).step, 3);
      final seen = _record(container);
      await c.online();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, greaterThanOrEqualTo(4));
      _inOrder(seen);
      expect(seen.first.kind, ChecklistKind.online);
      expect(_status(seen.first, onlineItemBackend), CheckStatus.running);
      // Seen one after the other: 第 1 次 done while 第 2 次 runs.
      expect(
        seen.any(
          (l) =>
              l.isDone(onlineItemBeat1) &&
              _status(l, onlineItemBeat2) == CheckStatus.running,
        ),
        isTrue,
      );
      final list = s.checklist!;
      expect(list.kind, ChecklistKind.online);
      expect(list.allDone, isTrue);
      expect(list.item(onlineItemBeat1)!.note, '心跳 1/2');
      expect(list.item(onlineItemBeat2)!.note, '心跳 2/2');
      expect(list.item(onlineItemTarget)!.note, isNotEmpty);
    });

    test('確認上線 fails at 第 2 次心跳: it stays there with the reason, '
        'the page keeps its retry; nothing spins after the run', () async {
      final (container, c) = await _toOnline(_StuckHeartbeat());
      addTearDown(container.dispose);
      await c.online();
      final s = container.read(commissionProvider);
      expect(s.error, isNotNull);
      expect(s.step, 3, reason: 'no automatic advance on a failure');
      final list = s.checklist!;
      expect(_status(list, onlineItemBackend), CheckStatus.done);
      expect(_status(list, onlineItemBeat1), CheckStatus.done);
      expect(_status(list, onlineItemBeat2), CheckStatus.failed);
      expect(list.item(onlineItemBeat2)!.note, checklistReason(s.error));
      expect(_status(list, onlineItemTarget), CheckStatus.pending);
      expect(list.running, isFalse);
      // Shown on 確認上線 with the red box.
      expect(identical(shownChecklist(s), list), isTrue);
    });

    test('正在配置 PTU (star): 指派 PTU n/N → 加入監控 → 核對 → 驗證資料 '
        '(收到 N 筆)', () async {
      final (container, c) = await _toOnline(DemoSystem());
      addTearDown(container.dispose);
      await c.online();
      await c.discover();
      final picked = container.read(commissionProvider).selected.length;
      expect(picked, greaterThan(1));
      final seen = _record(container);
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      _inOrder(seen);
      expect(
        seen.any(
          (l) =>
              _status(l, finishItemAssign) == CheckStatus.running &&
              l.item(finishItemAssign)!.note.contains('/$picked 台'),
        ),
        isTrue,
      );
      var list = s.checklist!;
      expect(list.kind, ChecklistKind.finish);
      expect(list.item(finishItemAssign)!.note, '$picked/$picked 台');
      expect(list.isDone(finishItemJoin), isTrue);
      expect(list.isDone(finishItemJoined), isTrue);
      expect(list.item(finishItemJoined)!.note, contains('台 PTU 已連上'));
      expect(_status(list, finishItemData), CheckStatus.pending);
      expect(identical(shownChecklist(s), list), isTrue);

      await c.verify('https://example.invalid', '');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      list = s.checklist!;
      expect(list.allDone, isTrue);
      expect(list.item(finishItemData)!.note, '每台 3/3 筆');
      expect(shownChecklist(s), isNull, reason: 'not on the done page');
    });

    test('正在完成設定 (one-to-one): 寫入 PTU 綁定 → 寫入 PTU 設定 → 加入監控 '
        '→ 核對已加入監控 → 驗證資料上傳', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = PickGateway();
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
      await topo.setDirectBindOnConfirm(true);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '');
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
      fake.config.putIfAbsent('upload_paused', () => true);
      expect(c.directFlow, isTrue);
      await c.identify();
      final seen = _record(container);
      await c.confirmDirectPick();
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      _inOrder(seen);
      var list = s.checklist!;
      expect(list.items.first.label, '寫入 PTU 綁定');
      expect(list.item(finishItemBind)!.note, '已綁定 PTU #$directPtuId');
      expect(list.item(finishItemSettings)!.note, '一對一');
      expect(list.isDone(finishItemJoin), isTrue);
      expect(list.item(finishItemJoined)!.note, 'PTU 已連上閘道器');
      expect(_status(list, finishItemData), CheckStatus.pending);

      await c.verify('https://example.invalid', '');
      s = container.read(commissionProvider);
      expect(s.step, 7);
      list = s.checklist!;
      expect(list.allDone, isTrue);
      expect(list.item(finishItemData)!.note, '收到 3/3 筆');
    });
  });

  group('4. on the page', () {
    testWidgets('360x640, 確認上線 without a second heartbeat: the list '
        'replaces 「處理中」, stops on 第 2 次心跳 with the reason; the red box '
        'and the retry in the bottom bar stay; no overflow', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'production',
      });
      final fake = _StuckHeartbeat();
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
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(() async {
        await c.prepare(container.read(backendEnvProvider).base, 'pw');
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.configureWifi(1, 1, 'test', 'test-password');
      });
      expect(container.read(commissionProvider).step, 3);
      // The page starts 確認上線 by itself; let it run out.
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 400; i++) {
          final s = container.read(commissionProvider);
          if (!s.busy && s.checklist?.kind == ChecklistKind.online) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      final s = container.read(commissionProvider);
      expect(s.step, 3);
      expect(s.error, isNotNull);
      expect(find.byKey(const Key('auto-checklist')), findsOneWidget);
      expect(_mark(onlineItemBackend, CheckStatus.done), findsOneWidget);
      expect(_mark(onlineItemBeat1, CheckStatus.done), findsOneWidget);
      expect(_mark(onlineItemBeat2, CheckStatus.failed), findsOneWidget);
      expect(_mark(onlineItemTarget, CheckStatus.pending), findsOneWidget);
      expect(find.textContaining(checklistReason(s.error)), findsWidgets);
      expect(find.textContaining('處理中 · 最多等待'), findsNothing);
      expect(find.byKey(const Key('error-banner')), findsOneWidget);
      // The retry is where it was (the bottom bar).
      expect(find.byKey(const Key('check-next')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('check-next')),
          matching: find.text(confirmOnlineLabel),
        ),
        findsOneWidget,
      );
      final list = tester.getRect(find.byKey(const Key('auto-checklist')));
      expect(list.right, lessThanOrEqualTo(360));
      expect(list.top, lessThan(640));
      expect(tester.takeException(), isNull);
    });
  });
}
