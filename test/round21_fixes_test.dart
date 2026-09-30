// Round 21 (after field round 21, APP 38664ec, firmware 1.7.31):
// 1. Star step 8: every PTU row says where its assignment stands (等待中 /
//    指派中 / 藍牙連線失敗，自動重試 n/N / 閘道器忙碌，稍後重試 / 完成 /
//    失敗需處理) and the list's top sums it up (「3/5 完成，1 台自動重試中」)
//    — field: 08 failed once (GATT 133), 3B twice (133, then busy), the APP
//    retried by itself and the screen showed a spinner only for 80 s. No
//    error code in the texts; the raw failure stays in the row's details.
//    The retries themselves are unchanged.
// 2. Step 7 automatic reconnect: 「手機與閘道器重新連線中…」 until the phone
//    is back, then 「重新讀取 PTU 列表…」 while the list is read again —
//    field: back after 2.6 s, the list 20 s later, 「重新連線中」 all along.
// 3. The back office's identify notice in the direct bar: the short first
//    sentence 「後台已讓此樁閃燈 · PTU 未回應確認」 never cut (two lines at
//    360 dp and text scale 1.3), MAC · dBm on a second line or behind the
//    tap; the bar and its buttons do not move when it comes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/assign_progress.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'link_loss_test.dart' show pumpApp, ready;
import 'round12_fixes_test.dart' show ScanDropLink;
import 'round15_direct_flow_test.dart' show PickGateway;

/// Field round 21's bench: five PTUs. assign_device_id of the n-th PTU
/// assigned (0-based, [plan]) first fails with the queued acks — '133':
/// the firmware's `connection/service discovery timeout` (GATT 133 twice
/// inside), 'busy': `busy` (a star connect still in flight). [holdIndex] /
/// [holdTry] hold that PTU's try (1-based) until [hold] completes.
class R21Assign extends ScanDropLink {
  R21Assign() {
    devices.addAll([
      for (final i in [4, 5])
        <String, dynamic>{
          'mac': 'AA:BB:CC:00:00:0$i',
          'rssi': -40 - (i - 1) * 5,
          'device_number': 0,
          'connected': false,
          'notify_enabled': false,
          'zombie': false,
          'last_data_age_sec': 0,
        },
    ]);
  }

  final plan = <int, List<String>>{};
  final order = <String>[];
  final tries = <String>[];
  int holdIndex = -1, holdTry = 0;
  Completer<void>? hold;
  bool holding = false;

  int triesOf(String mac) => tries.where((m) => m == mac).length;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'assign_device_id' && !down) {
      final mac = params['mac'].toString();
      if (!order.contains(mac)) order.add(mac);
      tries.add(mac);
      final index = order.indexOf(mac);
      if (index == holdIndex && triesOf(mac) == holdTry && hold != null) {
        holding = true;
        await hold!.future;
        holding = false;
      }
      final queue = plan[index];
      if (queue != null && queue.isNotEmpty) {
        final error = queue.removeAt(0);
        throw gatewayAckFailure({
          'mac': mac,
          'requested_mac': mac,
          'new_id': params['new_id'],
          'conn_slot': -1,
          'success': false,
          'error': error == 'busy'
              ? 'busy'
              : 'connection/service discovery timeout',
        });
      }
    }
    return super.command(op, params);
  }
}

String? _rowText(CommissionState s, String mac) {
  final status = s.assignStatus[mac];
  if (status == null) return null;
  return assignStatusText(
    status,
    result: s.results[mac],
    failure: s.assignFailed[mac],
  );
}

/// [texts] without repeats in a row.
List<String> _changes(Iterable<String?> texts) {
  final out = <String>[];
  for (final t in texts) {
    if (t != null && (out.isEmpty || out.last != t)) out.add(t);
  }
  return out;
}

final _errorCode = RegExp(r'133|0x');

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

void _scale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Steps 1-7 of the star flow on the page (demo link [fake]).
Future<(ProviderContainer, CommissioningController)> _toStarList(
  WidgetTester tester,
  DemoSystem fake, {
  Size size = const Size(360, 640),
}) async {
  final container = await pumpApp(tester, fake, size: size);
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
  expect(container.read(commissionProvider).step, 4);
  return (container, c);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepGap;
  setUp(() {
    keepGap = connectRetryGap;
    connectRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() => connectRetryGap = keepGap);

  group('1. step 8: each PTU\'s assignment and the whole run', () {
    test('texts: phases, progress, no error codes', () {
      const retry = AssignStatus(
        AssignPhase.linkRetry,
        id: 4,
        retry: 1,
        retries: 2,
        detail: 'GatewayFailure(connection/service discovery timeout) 133',
      );
      expect(assignStatusText(const AssignStatus(AssignPhase.waiting)), '等待中');
      expect(
        assignStatusText(const AssignStatus(AssignPhase.assigning, id: 3)),
        '指派中 #3',
      );
      expect(assignStatusText(retry), '藍牙連線失敗，自動重試 1/2');
      expect(
        assignStatusText(
          const AssignStatus(AssignPhase.busy, id: 5, retry: 1, retries: 2),
        ),
        '閘道器忙碌，稍後重試',
      );
      expect(
        assignStatusText(
          const AssignStatus(AssignPhase.done, id: 3),
          result: '已連線 #3',
        ),
        '完成 · 已連線 #3',
      );
      expect(
        assignStatusText(
          const AssignStatus(AssignPhase.failed, id: 3),
          failure: 'PTU 連線失敗，請確認 PTU 電源與距離',
        ),
        '失敗需處理：PTU 連線失敗，請確認 PTU 電源與距離',
      );
      // A stop on a phone link loss keeps its own words.
      expect(
        assignStatusText(
          const AssignStatus(AssignPhase.waiting),
          result: notAssignedLinkText,
        ),
        notAssignedLinkText,
      );
      const done = AssignStatus(AssignPhase.done);
      expect(
        assignProgressText({
          'a': done,
          'b': done,
          'c': done,
          'd': retry,
          'e': const AssignStatus(AssignPhase.waiting),
        }),
        '3/5 完成，1 台自動重試中',
      );
      expect(
        assignProgressText({
          'a': done,
          'b': const AssignStatus(AssignPhase.failed),
        }),
        '1/2 完成，1 台失敗需處理',
      );
      expect(assignProgressText({}), isNull);
      // Busy / the gateway's link to the PTU / anything else.
      expect(
        assignRetryPhase(
          gatewayAckFailure({'success': false, 'error': 'busy'}),
        ),
        AssignPhase.busy,
      );
      expect(
        assignRetryPhase(
          gatewayAckFailure({
            'success': false,
            'error': 'connection/service discovery timeout',
          }),
        ),
        AssignPhase.linkRetry,
      );
      expect(
        assignRetryPhase(const GatewayFailure('timeout')),
        AssignPhase.retry,
      );
    });

    test('field round 21: the 4th PTU fails once (133), the 5th twice '
        '(133, busy) — every retry on its row, the run completes', () async {
      final fake = R21Assign()
        ..plan[3] = ['133']
        ..plan[4] = ['133', 'busy'];
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      expect(container.read(commissionProvider).selected, hasLength(5));

      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      final [m1, _, _, m4, m5] = fake.order;

      final rows4 = _changes(states.map((x) => _rowText(x, m4)));
      expect(rows4.take(3), ['等待中', '指派中 #4', '藍牙連線失敗，自動重試 1/2']);
      expect(rows4.skip(3), everyElement(startsWith('完成')));
      final rows5 = _changes(states.map((x) => _rowText(x, m5)));
      expect(rows5.take(4), ['等待中', '指派中 #5', '藍牙連線失敗，自動重試 1/2', '閘道器忙碌，稍後重試']);
      expect(rows5.skip(4), everyElement(startsWith('完成')));
      expect(s.assignStatus[m4]!.phase, AssignPhase.done);
      expect(s.assignStatus[m5]!.phase, AssignPhase.done);
      expect(_changes(states.map((x) => _rowText(x, m1))).first, '等待中');

      final progress = _changes(
        states.map((x) => assignProgressText(x.assignStatus)),
      );
      expect(
        progress,
        containsAllInOrder([
          '0/5 完成',
          '3/5 完成',
          '3/5 完成，1 台自動重試中',
          '4/5 完成',
          '4/5 完成，1 台自動重試中',
          '5/5 完成',
        ]),
      );
      expect(assignProgressText(s.assignStatus), '5/5 完成');

      // No error code on screen; the raw failure is kept for the details.
      for (final x in states) {
        for (final mac in fake.order) {
          expect(_rowText(x, mac) ?? '', isNot(contains(_errorCode)));
        }
        expect(
          assignProgressText(x.assignStatus) ?? '',
          isNot(contains('133')),
        );
      }
      final retrying = states
          .map((x) => x.assignStatus[m4])
          .firstWhere((a) => a?.phase == AssignPhase.linkRetry)!;
      expect(retrying.detail, contains('connection/service discovery timeout'));

      // Retries unchanged: 1 + 1 for the 4th; the 5th's busy answer is sent
      // again by the busy loop (field: 28.24 fail, 35.15 busy, 40.25 ok).
      expect(fake.triesOf(m4), 2);
      expect(fake.triesOf(m5), 3);
    });

    test('out of retries: 失敗需處理 on the row, the top says so', () async {
      final fake = R21Assign()..plan[1] = ['133', '133', '133'];
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      final bad = fake.order[1];
      expect(fake.triesOf(bad), 1 + assignRetries);
      expect(s.assignStatus[bad]!.phase, AssignPhase.failed);
      expect(_rowText(s, bad), '失敗需處理：PTU 連線失敗，請確認 PTU 電源與距離');
      expect(s.assignStatus[bad]!.detail, contains('discovery timeout'));
      expect(assignProgressText(s.assignStatus), '4/5 完成，1 台失敗需處理');
      expect(s.assignFailed.keys, [bad]);
    });

    test('stopped mid-run: no row keeps 指派中 with a spinner', () async {
      final fake = R21Assign()
        ..holdIndex = 2
        ..holdTry = 1
        ..hold = Completer<void>();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final run = c.configurePtus();
      await _until(() => fake.holding);
      final held = fake.order[2];
      expect(
        container.read(commissionProvider).assignStatus[held]!.phase,
        AssignPhase.assigning,
      );
      final stop = c.stopStep8();
      fake.hold!.complete();
      await stop;
      await run;
      final s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.assignStatus.values.where((a) => a.active), isEmpty);
      expect(s.assignStatus[held]!.phase, AssignPhase.waiting);
      expect(assignProgressText(s.assignStatus), '2/5 完成');
    });

    testWidgets('360x640 at text scale 1.3: the row and the top show the '
        'automatic retry while it runs', (tester) async {
      _scale(tester, 1.3);
      final fake = R21Assign()
        ..plan[3] = ['133']
        ..holdIndex = 3
        ..holdTry = 2
        ..hold = Completer<void>();
      final (container, c) = await _toStarList(tester, fake);
      late Future<void> run;
      await tester.runAsync(() async {
        run = c.configurePtus();
        await _until(() => fake.holding);
      });
      await tester.pump();
      expect(tester.takeException(), isNull);

      final s = container.read(commissionProvider);
      expect(s.busy, isTrue);
      expect(s.step, 5);
      // At the top of the PTU list, above the rows; each comes into view
      // above the bottom bar, uncut.
      final page = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      const screen = Rect.fromLTWH(0, 0, 360, 640);
      final bar = tester.getRect(find.byKey(const Key('ptu-selection-count')));
      final header = find.byKey(const Key('assign-progress'));
      final row = find.text('藍牙連線失敗，自動重試 1/2');
      for (final target in [header, row]) {
        await tester.scrollUntilVisible(target, 60, scrollable: page);
        await tester.pump();
        expect(target, findsOneWidget);
        final rect = tester.getRect(target);
        expect(screen.contains(rect.topLeft), isTrue);
        expect(rect.bottom, lessThanOrEqualTo(bar.top));
      }
      // Round 22: the retrying PTU by its row (unnumbered: its MAC bytes).
      final retrying = fake.order[3];
      expect(
        _plain(_text(tester, 'assign-progress-text')),
        '3/5 完成，PTU …${retrying.substring(retrying.length - 2)} 自動重試中（1/2）',
      );
      expect(_plain(_text(tester, 'assign-progress-hint')), assignAutoHint);
      expect(
        tester.getRect(header).bottom,
        lessThanOrEqualTo(tester.getRect(row).top),
      );
      expect(find.text('等待中'), findsOneWidget);
      expect(find.textContaining('133'), findsNothing);
      expect(tester.takeException(), isNull);

      // The details keep the raw failure.
      final info = find.descendant(
        of: find.byKey(ValueKey('ptu-${fake.order[3]}')),
        matching: find.byIcon(Icons.info_outline),
      );
      // 09-28: the page starts with its task title, so the scroll above
      // can leave the row's icon under the app bar; bring it in first.
      await tester.ensureVisible(info);
      await tester.pump();
      await tester.tap(info);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('ptu-assign-detail')),
          matching: find.textContaining('discovery timeout'),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      // 關閉 below a long detail.
      await tester.ensureVisible(find.text('關閉'));
      await tester.pump();
      await tester.tap(find.text('關閉'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('ptu-assign-detail')), findsNothing);

      fake.hold!.complete();
      await tester.runAsync(() => run);
      await tester.pump();
      expect(container.read(commissionProvider).step, 6);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('2. step 7 automatic reconnect: reconnecting, then reading', () {
    test('a drop during the list: 重新連線中… then 重新讀取 PTU 列表…', () async {
      final fake = ScanDropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      final before = fake.connects;
      fake.scanDrops = 1;
      await c.discover();

      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.relinking, isFalse);
      expect(s.ptus, isNotEmpty);
      expect(fake.connects, before + 1);
      expect(relinkStatusText(s), isNull);

      final stages = _changes(states.map(relinkStatusText));
      expect(stages, [relinkReconnectText, relinkReloadText]);
      final firstReload = states.indexWhere(
        (x) => relinkStatusText(x) == relinkReloadText,
      );
      // Once back it never says 「重新連線中」 again, and the button agrees.
      for (final x in states.skip(firstReload).where((x) => x.relinking)) {
        expect(x.relinkStage, RelinkStage.reloading);
        expect(configureLabel(x), relistingLabel);
      }
      for (final x in states.take(firstReload).where((x) => x.relinking)) {
        expect(configureLabel(x), relinkingLabel);
      }
      expect(states.any((x) => x.message == relinkReloadText), isTrue);
    });

    testWidgets('360x640 at text scale 1.3: the bottom bar says it', (
      tester,
    ) async {
      _scale(tester, 1.3);
      final fake = _GatedScanDrop();
      final (container, c) = await _toStarList(tester, fake);
      fake.scanDrops = 1;
      fake.connectGate = Completer<void>();
      late Future<void> run;
      await tester.runAsync(() async {
        run = c.discover();
        await _until(() => fake.connectWaiting);
      });
      await tester.pump();
      const screen = Rect.fromLTWH(0, 0, 360, 640);
      final status = find.byKey(const Key('relink-status'));
      expect(_plain(tester.widget<Text>(status)), relinkReconnectText);
      expect(screen.contains(tester.getRect(status).bottomRight), isTrue);
      final configure = find.byKey(const Key('ptu-configure'));
      expect(tester.widget<FilledButton>(configure).onPressed, isNull);
      expect(
        find.descendant(of: configure, matching: find.text(relinkingLabel)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Back: the list is read again (held here).
      fake.scanGate = Completer<void>();
      await tester.runAsync(() async {
        fake.connectGate!.complete();
        await _until(() => fake.scanWaiting);
      });
      await tester.pump();
      expect(container.read(commissionProvider).relinking, isTrue);
      expect(_plain(tester.widget<Text>(status)), relinkReloadText);
      expect(screen.contains(tester.getRect(status).bottomRight), isTrue);
      expect(
        find.descendant(of: configure, matching: find.text(relistingLabel)),
        findsOneWidget,
      );
      expect(find.text(autoRelinkingText), findsNothing);
      expect(tester.takeException(), isNull);

      fake.scanGate!.complete();
      await tester.runAsync(() => run);
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.relinking, isFalse);
      expect(s.ptus, isNotEmpty);
      expect(status, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('3. the back office\'s identify: short first sentence, never cut', () {
    const ack = {
      'gateway_led': 'ok',
      'ptu_write': 'ok',
      'ptu_confirmed': false,
      'ptu_confirm': 'timeout',
      'mac': 'AA:BB:CC:00:00:01',
      'rssi': -46,
    };

    test('texts', () {
      expect(remoteIdentifyHeadText(ack), '後台已讓此樁閃燈 · PTU 未回應確認');
      expect(
        remoteIdentifyHeadText({
          ...ack,
          'ptu_confirmed': true,
          'ptu_confirm': 'ok',
        }),
        '後台已讓此樁閃燈 · PTU 已確認',
      );
      expect(
        remoteIdentifyHeadText(const {'ptu_write': 'not_connected'}),
        '後台已讓閘道器閃燈 · PTU 未收到',
      );
      expect(remoteIdentifyPtuText(ack), 'PTU AA:BB:CC:00:00:01 · -46 dBm');
      expect(remoteIdentifyPtuText(const {'ptu_write': 'not_connected'}), '');
      for (final head in remoteIdentifyHeads) {
        expect(head.length, lessThanOrEqualTo(remoteIdentifyHeadMax));
        expect(head, isNot(contains(RegExp(r'\d'))));
      }
      // The full text (details, snack bar) names the PTU (round 24).
      expect(
        remoteIdentifyText(ack),
        startsWith('後台讓 PTU AA:BB:CC:00:00:01 閃燈（請看樁上燈號）'),
      );
    });

    Future<PickGateway> pumpDirect(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final fake = PickGateway(rssi: [-40, -49, -58]);
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
      expect(container.read(commissionProvider).step, 4);
      expect(find.byType(DirectPickActions), findsOneWidget);
      return fake;
    }

    const buttons = [
      'direct-identify',
      'direct-not-this',
      'direct-confirm',
      'direct-rescan-bottom',
      'direct-stop',
      'page-cancel',
    ];

    for (final (size, scale) in const [
      (Size(360, 640), 1.3),
      (Size(360, 640), 1.0),
      (Size(411, 891), 1.0),
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()} at $scale';
      testWidgets('$label: the first sentence in full, nothing moves', (
        tester,
      ) async {
        _scale(tester, scale);
        final fake = await pumpDirect(tester, size);
        final bar = tester.getRect(find.byType(DirectPickActions));
        final before = {
          for (final key in buttons) key: tester.getRect(find.byKey(Key(key))),
        };
        await tester.runAsync(() async {
          fake.remoteIdentify();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        final head = find.byKey(const Key('remote-identify'));
        expect(head, findsOneWidget);
        final text = _plain(tester.widget<Text>(head));
        expect(text, contains('後台已讓此樁閃燈'));
        expect(text, contains('PTU 未回應確認'));
        expect(text, isNot(contains('…')));
        // Drawn in full: no line cut off, no ellipsis.
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: head, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final screen = Offset.zero & size;
        final rect = tester.getRect(head);
        expect(screen.contains(rect.topLeft), isTrue);
        expect(screen.contains(rect.bottomRight - const Offset(1, 1)), isTrue);

        // The bar and every button stay where they were.
        expect(tester.getRect(find.byType(DirectPickActions)), bar);
        for (final key in buttons) {
          expect(
            tester.getRect(find.byKey(Key(key))),
            before[key],
            reason: key,
          );
          expect(rect.overlaps(tester.getRect(find.byKey(Key(key)))), isFalse);
        }

        if (scale > 1.2) {
          // Two lines: the sentence broken after 「閃燈」; MAC · dBm behind
          // the tap.
          expect(text, '後台已讓此樁閃燈\nPTU 未回應確認');
          expect(find.byKey(const Key('remote-identify-ptu')), findsNothing);
        }
        // MAC and dBm are always one tap away.
        await tester.tap(find.byKey(const Key('direct-identify-toggle')));
        await tester.pump();
        final detail = find.byKey(const Key('remote-identify-detail'));
        expect(detail, findsOneWidget);
        final full = _plain(tester.widget<Text>(detail));
        expect(full, contains('AA:BB:CC:00:00:01'));
        expect(full, contains('dBm'));
        expect(tester.takeException(), isNull);

        await tester.pump(remoteIdentifyNoticeDuration);
        await tester.pump();
        expect(head, findsNothing);
        expect(tester.getRect(find.byType(DirectPickActions)), bar);
      });
    }

    testWidgets('a wide screen at 1.3: one line, nothing reserved', (
      tester,
    ) async {
      _scale(tester, 1.3);
      final fake = await pumpDirect(tester, const Size(600, 900));
      // Every sentence fits one line here: no second line is reserved; the
      // PTU joins it only when the whole line fits.
      final bar = tester.getRect(find.byType(DirectPickActions));
      await tester.runAsync(() async {
        fake.remoteIdentify(confirm: 'ok');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final head = find.byKey(const Key('remote-identify'));
      final text = _plain(tester.widget<Text>(head));
      expect(text, startsWith('後台已讓此樁閃燈 · PTU 已確認'));
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.descendant(of: head, matching: find.byType(RichText)),
            )
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.getRect(find.byType(DirectPickActions)), bar);
      await tester.pump(remoteIdentifyNoticeDuration);
      await tester.pump();
    });

    testWidgets('RemoteIdentifyLines: head, then PTU line when two lines '
        'are reserved and the head fits one', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: RemoteIdentifyLines(
                head: '後台已讓此樁閃燈 · PTU 未回應確認',
                ptu: 'PTU AA:BB:CC:00:00:01 · -46 dBm',
                others: ['AA:BB:CC:00:00:02'],
                twoLines: true,
                width: 400,
              ),
            ),
          ),
        ),
      );
      expect(
        _plain(tester.widget<Text>(find.byKey(const Key('remote-identify')))),
        '後台已讓此樁閃燈 · PTU 未回應確認',
      );
      final ptu = _plain(
        tester.widget<Text>(find.byKey(const Key('remote-identify-ptu'))),
      );
      expect(ptu, contains('-46 dBm'));
      expect(ptu, contains('01'));
    });
  });
}

/// [ScanDropLink] whose reconnect waits for [connectGate] and whose next
/// scan (after the drop) waits for [scanGate].
class _GatedScanDrop extends ScanDropLink {
  Completer<void>? connectGate, scanGate;
  bool connectWaiting = false, scanWaiting = false;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    final gate = connectGate;
    if (gate != null && !gate.isCompleted) {
      connectWaiting = true;
      await gate.future;
      connectWaiting = false;
    }
    await super.connect(peer, onStage: onStage);
  }

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
