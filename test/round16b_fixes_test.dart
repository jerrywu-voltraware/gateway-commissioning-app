// Round 16b (after field round 16, APP 98114b5, firmware 1.7.22):
// 1. The direct flow names PTUs by their full MAC (monospace): card
//    headline, candidate rows, 保留／解除 prompt, identify feedback. Field
//    round 16: five PTUs 90:xx:xx:xx:96:00 all read 「MAC 後 4 碼 9600」.
//    Only where the full MAC does not fit: the shortest run of bytes that
//    tells it apart from the current candidates
//    ([distinguishingMacSegment]), with the full MAC on tap / below.
// 2. 取消 / 返回 / 結束 after 「不是這台？」 put back the gateway's binding
//    from before the switch (none → none, a confirmed 2C → 2C again), not
//    always "" (field: the binding confirmed in B5 was lost in B6). Only
//    「是這台」 makes the new MAC count.
// 3. Step 8 with some PTUs done: 「已選 5 台 · 已完成 4 台 · 將配置 1 台」
//    and 「配置剩餘 1 台並開始監控」 (was 「已選 5 / 5 台」 beside 「配置 1
//    台…」).
// 4. The candidate sheet: every row, the last one included, is one tap
//    target (trailing 「改連這台」 too) above the system gesture bar; a tap
//    while the controller is busy keeps the sheet open instead of closing it
//    with nothing sent (field: one tap on the last row was lost).
import 'dart:async';

import 'support/direct_pick_actions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'compact_ptu_test.dart' show pumpSelection;
import 'round15_direct_flow_test.dart' show PickGateway;

/// Field round 16: five PTUs that only differ in bytes 2–4.
const _f5F = '90:5F:E8:9A:96:00';
const _f2C = '90:2C:00:54:96:00';
const _f08 = '90:08:1C:8E:96:00';
const _f3B = '90:3B:DA:12:96:00';
const _f74 = '90:74:03:11:96:00';
const _fleet = [_f5F, _f2C, _f08, _f3B, _f74];

/// Demo MACs (PickGateway): listed first, the gateway's pick, the weakest.
const _first = 'AA:BB:CC:00:00:01';
const _pick = 'AA:BB:CC:00:00:02';
const _third = 'AA:BB:CC:00:00:03';

/// The field bench: five PTUs side by side (5F strongest, 08 weakest).
class _FleetGateway extends PickGateway {
  _FleetGateway() {
    const rssi = {_f5F: -45, _f2C: -46, _f74: -46, _f3B: -47, _f08: -49};
    devices
      ..clear()
      ..addAll([
        for (final mac in _fleet)
          <String, dynamic>{
            'mac': mac,
            'rssi': rssi[mac],
            'device_number': 0,
            'connected': false,
            'notify_enabled': false,
            'zombie': false,
            'last_data_age_sec': 0,
          },
      ]);
  }
}

/// set_config putting a binding back (not clearing it) fails.
class _RestoreFailing extends PickGateway {
  bool failRestore = false;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    if (failRestore &&
        op == 'set_config' &&
        params['direct_bind_mac'] != null) {
      ops.add((op, Map.of(params)));
      return Future.error(const GatewayFailure.gateway('write_failed'));
    }
    return super.command(op, params);
  }
}

/// identify waits for [release] (the controller stays busy meanwhile).
class _SlowIdentify extends _FleetGateway {
  Completer<void>? hold;

  void release() => hold?.complete();

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'identify' && hold != null) await hold!.future;
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _toStep7(
  PickGateway fake, {
  Map<String, Object> prefs = const {},
  bool bindOnConfirm = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.direct);
  await topo.setDirectBindOnConfirm(bindOnConfirm);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  return (container, c);
}

/// Field B5 → B6: 「不是這台？」 → [mac], identify, 是這台 (a confirmed
/// binding), 結束, then step 7 again with the gateway bound to [mac].
Future<void> _confirmBindAndReenter(
  ProviderContainer container,
  CommissioningController c,
  String mac,
) async {
  await c.switchDirectPick(mac);
  await c.identify();
  await c.confirmDirectPick();
  expect(container.read(commissionProvider).step, 6);
  await c.cancel();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  final s = container.read(commissionProvider);
  expect(s.step, 4);
  expect(s.direct!.pickedMac, mac);
  expect(s.strayBindMac, isNull, reason: 'confirmed: not asked about');
}

List<Map<String, dynamic>> _bindWrites(PickGateway fake) => [
  for (final p in fake.sent('set_config'))
    if (p.containsKey('direct_bind_mac')) p,
];

/// Step 7 as on the phone: the card scrolls, the actions are the bottom bar.
Widget _screen(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: DirectStatusPanel()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: DirectPickActions(),
        ),
      ),
    ),
  ),
);

Future<void> _idle(WidgetTester tester, ProviderContainer container) =>
    tester.runAsync(() async {
      for (var i = 0; i < 400 && container.read(commissionProvider).busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

void _phone(WidgetTester tester, {Size size = const Size(360, 640)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Every span of [text] (a [Text.rich]) that is exactly [mac].
Iterable<TextSpan> _macSpans(Text text, String mac) sync* {
  final spans = <InlineSpan>[text.textSpan!];
  while (spans.isNotEmpty) {
    final span = spans.removeLast();
    if (span is TextSpan) {
      if (span.text == mac) yield span;
      spans.addAll(span.children ?? const []);
    }
  }
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepSwitch;
  setUp(() {
    keepPoll = directPollInterval;
    keepSwitch = directSwitchWait;
    directPollInterval = const Duration(milliseconds: 1);
    directSwitchWait = const Duration(milliseconds: 80);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    directSwitchWait = keepSwitch;
  });

  group('1. full MAC; the distinguishing bytes only when it does not fit', () {
    test('distinguishingMacSegment: the field fleet 90:xx:xx:xx:96:00', () {
      String seg(String mac) => distinguishingMacSegment(mac, _fleet);
      expect(seg(_f5F), '…5F…');
      expect(seg(_f2C), '…2C…');
      expect(seg(_f08), '…08…');
      expect(seg(_f3B), '…3B…');
      expect(seg(_f74), '…74…');
      // Never the shared tail.
      for (final mac in _fleet) {
        expect(seg(mac), isNot(contains('96')));
      }
    });

    test(
      'distinguishingMacSegment: shortest run, leftmost on a tie, edges',
      () {
        // Same OUI, only the last byte differs.
        expect(
          distinguishingMacSegment('AA:BB:CC:12:34:56', ['AA:BB:CC:12:34:78']),
          '…56',
        );
        // Only the first byte differs.
        expect(
          distinguishingMacSegment('12:34:56:78:9A:BC', ['99:34:56:78:9A:BC']),
          '12…',
        );
        // No single byte is unique: two bytes (5F:E8).
        expect(
          distinguishingMacSegment(_f5F, [
            '90:5F:00:9A:96:00',
            '90:11:E8:9A:96:00',
          ]),
          '…5F:E8…',
        );
        // Two bytes differ everywhere: the leftmost wins.
        expect(
          distinguishingMacSegment('AA:BB:CC:11:22:33', ['AA:BB:CC:44:22:55']),
          '…11…',
        );
        // Lower case / dashes; the target itself and non-MACs are ignored.
        expect(
          distinguishingMacSegment('90-5f-e8-9a-96-00', [
            _f5F,
            '90:2c:00:54:96:00',
            null,
            'junk',
          ]),
          '…5F…',
        );
        // Nothing to tell apart: the familiar tail.
        expect(distinguishingMacSegment(_f5F, const []), '…96:00');
        expect(distinguishingMacSegment(_f5F, [_f5F]), '…96:00');
        // Not a MAC: as given.
        expect(distinguishingMacSegment('PTU-7', [_f5F]), 'PTU-7');
      },
    );

    test('formatMac, shortenMacIn and the texts name the full MAC', () {
      expect(formatMac('90:5f:e8:9a:96:00'), _f5F);
      expect(formatMac('905FE89A9600'), _f5F);
      expect(formatMac(' ptu '), 'ptu');
      expect(
        shortenMacIn('已送出 · 請看樁上燈號 · $_f5F · -45 dBm', _fleet),
        '已送出 · 請看樁上燈號 · …5F… · -45 dBm',
      );
      expect(shortenMacIn('沒有 MAC', _fleet), '沒有 MAC');
      expect(directStrayBindText('90:3b:da:12:96:00'), '閘道器目前綁定 PTU $_f3B');
      expect(directSwitchedText(_f2C), contains(_f2C));
      expect(directSwitchPendingText(_f2C), contains(_f2C));
      expect(
        identifyLineText({'mac': _f2C, 'rssi': -46}),
        '已送出 · 請看樁上燈號 · $_f2C · -46 dBm',
      );
      expect(identifyNoteText({'mac': _f2C, 'rssi': -46}), contains(_f2C));
      for (final text in [
        directStrayBindText(_f3B),
        directSwitchedText(_f2C),
        directSwitchPendingText(_f2C),
        directUnbindFailedText(_f74, _f2C),
        identifyLineText({'mac': _f2C}),
      ]) {
        expect(text, isNot(contains('後 4 碼')));
      }
    });

    testWidgets('360 dp field fleet: card headline, 保留／解除 prompt and '
        'candidate rows show the full MAC in monospace; the one-line identify '
        'note the distinguishing bytes, the full MAC on tap', (tester) async {
      _phone(tester);
      // A binding this APP never confirmed (field B7): 3B.
      final fake = _FleetGateway()..config['direct_bind_mac'] = _f3B;
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).strayBindMac, _f3B);
      await tester.pumpWidget(_screen(container));

      // Card headline: the full MAC, monospace.
      final headline = find.descendant(
        of: find.byKey(const Key('direct-linked')),
        matching: find.text(_f3B),
      );
      expect(headline, findsOneWidget);
      expect(tester.widget<Text>(headline).style?.fontFamily, 'monospace');
      expect(find.textContaining('後 4 碼'), findsNothing);
      expect(find.textContaining('9600'), findsNothing);

      // 保留／解除 prompt: the full MAC, monospace.
      final stray = find.descendant(
        of: find.byKey(const Key('direct-stray-bind')),
        matching: find.text(directStrayBindText(_f3B)),
      );
      expect(stray, findsOneWidget);
      expect(
        _macSpans(tester.widget<Text>(stray), _f3B).single.style?.fontFamily,
        'monospace',
      );

      // Identify: the line does not fit at 360 dp → 「…3B…」; the full note
      // (full MAC, monospace) on tap.
      await tester.tap(find.byKey(const Key('direct-identify')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.identifyLine, '已送出 · 請看樁上燈號 · $_f3B · -47 dBm');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('direct-identify-note')))
            .textSpan!
            .toPlainText(),
        '已送出 · 請看樁上燈號 · …3B… · -47 dBm',
      );
      await tester.tap(find.byKey(const Key('direct-identify-toggle')));
      await tester.pump();
      final detail = tester.widget<Text>(
        find.byKey(const Key('direct-identify-detail')),
      );
      expect(detail.textSpan!.toPlainText(), contains(_f3B));
      expect(_macSpans(detail, _f3B).single.style?.fontFamily, 'monospace');

      await closeIdentifyDetails(tester);

      // Candidates: every row its own full MAC, monospace; no 9600.
      await tapDirectAction(tester, 'direct-not-this');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (final mac in _fleet) {
        final text = find.descendant(
          of: find.byKey(ValueKey('direct-candidate-$mac')),
          matching: find.text(mac),
        );
        expect(text, findsOneWidget, reason: mac);
        expect(tester.widget<Text>(text).style?.fontFamily, 'monospace');
      }
      expect(find.byKey(const Key('mac-segment')), findsNothing);
      expect(find.textContaining('後 4 碼'), findsNothing);
    });

    testWidgets('wide screen: the identify note keeps the full MAC', (
      tester,
    ) async {
      _phone(tester, size: const Size(800, 640));
      final fake = _FleetGateway();
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tester.tap(find.byKey(const Key('direct-identify')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('direct-identify-note')))
            .textSpan!
            .toPlainText(),
        '已送出 · 請看樁上燈號 · $_f5F · -45 dBm',
      );
    });

    testWidgets('MacText too narrow: the distinguishing bytes, tap for the '
        'full MAC; inside a row the full MAC below instead', (tester) async {
      Widget box(Widget child) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 120, child: child),
          ),
        ),
      );
      await tester.pumpWidget(box(const MacText(_f5F, others: _fleet)));
      expect(find.text('…5F…'), findsOneWidget);
      expect(find.text(_f5F), findsNothing);
      await tester.tap(find.byKey(const Key('mac-expand')));
      await tester.pump();
      expect(find.text(_f5F), findsOneWidget);
      expect(find.text('…5F…'), findsNothing);

      await tester.pumpWidget(
        box(const MacText(_f08, others: _fleet, fullBelow: true)),
      );
      expect(find.text('…08…'), findsOneWidget);
      expect(find.text(_f08), findsOneWidget);
      expect(find.byKey(const Key('mac-expand')), findsNothing);

      // Room enough: the full MAC only.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MacText(_f2C, others: _fleet)),
        ),
      );
      expect(find.text(_f2C), findsOneWidget);
      expect(find.byKey(const Key('mac-segment')), findsNothing);
    });
  });

  group('2. 取消 puts back the binding from before 不是這台？', () {
    test('confirmed A → temporary B → 取消: bound to A again, still '
        'confirmed (field B6)', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await _confirmBindAndReenter(container, c, _first);
      final before = _bindWrites(fake).length;

      await c.switchDirectPick(_third);
      var s = container.read(commissionProvider);
      expect(s.tempBoundMac, _third);
      expect(s.tempRestoreMac, _first);
      expect(fake.config['direct_bind_mac'], _third);
      await c.cancel();
      s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.error, isNull);
      expect(_bindWrites(fake).skip(before), [
        {'direct_bind_mac': _third},
        {'direct_bind_mac': _first},
      ]);
      expect(fake.config['direct_bind_mac'], _first);
      expect(s.tempBoundMac, isNull);
      expect(s.tempRestoreMac, isNull);

      // Still the confirmed binding: step 7 shows A, no 保留／解除.
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
      s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.direct!.pickedMac, _first);
      expect(s.strayBindMac, isNull);
    });

    test('no binding → temporary B → 取消: unbound again', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.switchDirectPick(_first);
      expect(container.read(commissionProvider).tempRestoreMac, isNull);
      await c.cancel();
      expect(_bindWrites(fake), [
        {'direct_bind_mac': _first},
        {'direct_bind_mac': ''},
      ]);
      expect(fake.config['direct_bind_mac'], '');
    });

    test(
      'A → B → C → 取消: back to A (the binding before the first switch)',
      () async {
        final fake = PickGateway();
        final (container, c) = await _toStep7(fake);
        addTearDown(container.dispose);
        await _confirmBindAndReenter(container, c, _first);
        await c.switchDirectPick(_pick);
        await c.switchDirectPick(_third);
        final s = container.read(commissionProvider);
        expect(s.tempBoundMac, _third);
        expect(s.tempRestoreMac, _first);
        await c.cancel();
        expect(_bindWrites(fake).last, {'direct_bind_mac': _first});
        expect(fake.config['direct_bind_mac'], _first);
      },
    );

    test('A → B → back to A → 取消: nothing to undo, nothing sent', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await _confirmBindAndReenter(container, c, _first);
      await c.switchDirectPick(_third);
      await c.switchDirectPick(_first);
      final before = _bindWrites(fake).length;
      await c.cancel();
      expect(_bindWrites(fake), hasLength(before));
      expect(fake.config['direct_bind_mac'], _first);
      expect(container.read(commissionProvider).error, isNull);
    });

    test('with 「確認後綁定」 on: A is put back as well', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake, bindOnConfirm: true);
      addTearDown(container.dispose);
      await _confirmBindAndReenter(container, c, _first);
      await c.switchDirectPick(_third);
      await c.cancel();
      expect(fake.config['direct_bind_mac'], _first);
    });

    test(
      'A → temporary B → 是這台: B counts from then on, nothing put back',
      () async {
        final fake = PickGateway();
        final (container, c) = await _toStep7(fake);
        addTearDown(container.dispose);
        await _confirmBindAndReenter(container, c, _first);
        await c.switchDirectPick(_third);
        await c.identify();
        await c.confirmDirectPick();
        var s = container.read(commissionProvider);
        expect(s.step, 6);
        expect(s.tempBoundMac, isNull);
        final before = _bindWrites(fake).length;
        await c.cancel();
        expect(_bindWrites(fake), hasLength(before));
        expect(fake.config['direct_bind_mac'], _third);
        await c.connect(container.read(commissionProvider).peers.single);
        await c.chooseStation(newStation: false);
        s = container.read(commissionProvider);
        expect(s.direct!.pickedMac, _third);
        expect(s.strayBindMac, isNull);
      },
    );

    test('putting A back fails: not blocked, the notice names both', () async {
      final fake = _RestoreFailing();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await _confirmBindAndReenter(container, c, _first);
      await c.switchDirectPick(_third);
      fake.failRestore = true;
      await c.cancel();
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(s.error, directUnbindFailedText(_third, _first));
      expect(s.error, contains(_first));
      expect(s.error, contains(_third));
      expect(s.errorDetail, contains('write_failed'));
      expect(fake.config['direct_bind_mac'], _third);
    });

    testWidgets('system 返回 after a temporary switch puts A back', (
      tester,
    ) async {
      _phone(tester, size: const Size(800, 2400));
      SharedPreferences.setMockInitialValues({});
      final fake = PickGateway();
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
        await _confirmBindAndReenter(container, c, _first);
        await c.switchDirectPick(_third);
      });
      await tester.pump();
      expect(container.read(commissionProvider).tempBoundMac, _third);
      expect(fake.config['direct_bind_mac'], _third);

      await tester.runAsync(() async {
        await tester.binding.handlePopRoute();
      });
      await tester.pumpAndSettle();
      // Round 28: 返回 asks 「結束目前配置？」 first (the APP stays).
      expect(find.byKey(const Key('end-confirm')), findsOneWidget);
      expect(container.read(commissionProvider).step, 4);
      await tester.tap(find.byKey(const Key('end-confirm-end')));
      await tester.runAsync(() async {
        for (var i = 0; i < 400; i++) {
          if (container.read(commissionProvider).step == 1) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(_bindWrites(fake).last, {'direct_bind_mac': _first});
      expect(fake.config['direct_bind_mac'], _first);
    });
  });

  group('3. step 8 wording with some PTUs done', () {
    test('「已選 5 台 · 已完成 4 台 · 將配置 1 台」 and 「配置剩餘 1 台」', () {
      const partial = CommissionState(
        selected: {'A', 'B', 'C', 'D', 'E'},
        assignedOk: {'A', 'B', 'C', 'D'},
      );
      expect(selectionCountText(partial, 5), '已選 5 台 · 已完成 4 台 · 將配置 1 台');
      expect(configureLabel(partial), '配置剩餘 1 台並開始監控');
      // Nothing done yet: unchanged.
      const fresh = CommissionState(selected: {'A', 'B', 'C', 'D', 'E'});
      expect(selectionCountText(fresh, 5), '已選 5 / 5 台');
      expect(configureLabel(fresh), '配置 5 台並開始監控');
      // A done PTU no longer selected does not count.
      const unticked = CommissionState(selected: {'B', 'C'}, assignedOk: {'A'});
      expect(selectionCountText(unticked, 5), '已選 2 / 5 台');
      expect(configureLabel(unticked), '配置 2 台並開始監控');
      // All done: the count, 開始驗證／恢復監控.
      const all = CommissionState(
        selected: {'A', 'B'},
        assignedOk: {'A', 'B'},
        ptus: [
          {'mac': 'A'},
          {'mac': 'B'},
        ],
      );
      expect(selectionCountText(all, 5), '已選 2 / 5 台');
    });

    testWidgets('page: one PTU lost its number after a run → the new line '
        'and button', (tester) async {
      final container = await pumpSelection(tester, 1);
      final c = container.read(commissionProvider.notifier);
      final fake = container.read(linkProvider) as DemoSystem;
      await tester.runAsync(() async {
        await c.configurePtus();
        await c.backToSelection();
        final first = fake.devices.first;
        first['device_number'] = 0;
        first['connected'] = false;
        await c.discover();
      });
      await tester.pumpAndSettle();
      final s = container.read(commissionProvider);
      expect(s.selected, hasLength(5));
      expect(configureTargets(s), hasLength(1));
      expect(
        tester.widget<Text>(find.byKey(const Key('ptu-selection-count'))).data,
        '已選 5 台 · 已完成 4 台 · 將配置 1 台',
      );
      expect(find.text('配置剩餘 1 台並開始監控'), findsOneWidget);
      expect(find.text('已選 5 / 5 台'), findsNothing);
    });
  });

  group('4. candidate sheet: the last row', () {
    void gestureBar(WidgetTester tester) {
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      tester.view.systemGestureInsets = const FakeViewPadding(bottom: 60);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetSystemGestureInsets);
    }

    Future<ProviderContainer> openSheet(
      WidgetTester tester,
      PickGateway fake,
    ) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      await tapDirectAction(tester, 'direct-not-this');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('direct-candidates-sheet')), findsOneWidget);
      return container;
    }

    for (final part in ['trailing', 'middle', 'right edge']) {
      testWidgets('360 dp with a gesture bar: the last row sits above it and '
          'a tap on its $part switches', (tester) async {
        _phone(tester);
        gestureBar(tester);
        final fake = _FleetGateway();
        final container = await openSheet(tester, fake);
        // Strongest first: 08 (-49 dBm) is the last row.
        final rows = find.byType(DirectCandidateTile);
        expect(rows, findsNWidgets(5));
        final last = find.byKey(const ValueKey('direct-candidate-$_f08'));
        expect(
          tester.getRect(last).top,
          greaterThan(tester.getRect(rows.at(3)).top),
        );
        final rect = tester.getRect(last);
        expect(rect.bottom, lessThanOrEqualTo(640 - 60));
        expect(
          tester
              .getRect(find.byKey(const Key('direct-candidates-sheet')))
              .bottom,
          640,
        );
        // One tap target per row (the trailing text inside it).
        expect(
          find.descendant(of: last, matching: find.byType(InkWell)),
          findsNothing,
        );
        expect(
          find.descendant(of: last, matching: find.text('改連這台')),
          findsOneWidget,
        );
        switch (part) {
          case 'trailing':
            await tester.tap(
              find.descendant(of: last, matching: find.text('改連這台')),
            );
          case 'middle':
            await tester.tap(last);
          default:
            await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
        }
        await tester.pump();
        await _idle(tester, container);
        await tester.pump(const Duration(milliseconds: 500));
        expect(fake.sent('set_config').last, {'direct_bind_mac': _f08});
        expect(container.read(commissionProvider).selected, {_f08});
        expect(find.byKey(const Key('direct-candidates-sheet')), findsNothing);
      });
    }

    testWidgets('busy at the tap: the sheet stays open, a later tap switches', (
      tester,
    ) async {
      _phone(tester);
      final fake = _SlowIdentify();
      final container = await openSheet(tester, fake);
      final c = container.read(commissionProvider.notifier);
      final last = find.byKey(const ValueKey('direct-candidate-$_f08'));
      // The controller turns busy after the rows were built (no rebuild
      // before the tap).
      fake.hold = Completer<void>();
      unawaited(c.identify());
      expect(container.read(commissionProvider).busy, isTrue);
      await tester.tap(last);
      await tester.pump();
      expect(find.byKey(const Key('direct-candidates-sheet')), findsOneWidget);
      expect(_bindWrites(fake), isEmpty);

      fake.release();
      await _idle(tester, container);
      await tester.pump();
      expect(container.read(commissionProvider).busy, isFalse);
      await tester.tap(last);
      await tester.pump();
      await _idle(tester, container);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_bindWrites(fake), [
        {'direct_bind_mac': _f08},
      ]);
      expect(find.byKey(const Key('direct-candidates-sheet')), findsNothing);
    });

    test('sheet bottom room: the larger of the bars plus a margin', () {
      const media = MediaQueryData(
        padding: EdgeInsets.only(bottom: 24),
        viewPadding: EdgeInsets.only(bottom: 48),
        systemGestureInsets: EdgeInsets.only(bottom: 32),
      );
      expect(candidatesSheetBottom(media), 64);
      expect(candidatesSheetBottom(const MediaQueryData()), 16);
    });
  });
}
