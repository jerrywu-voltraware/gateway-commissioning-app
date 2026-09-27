// Round 19 (after field round 19, APP f5e30eb, firmware 1.7.26):
// 1. 「校正門檻」 follows the firmware's own rules (direct_pick.c): a PTU is
//    picked when its advertising peak ≥ threshold, dropped when its link
//    median < threshold − 3; so the threshold lies in [lower, upper] with
//    upper = min(this pile's advertising median `self_adv_rssi_med`, its
//    weakest link reading + 3) and lower = the strongest neighbour's peak
//    + 1 (neighbours with ≥ 3 samples heard within 60 s). Range ≥ 2: the
//    midpoint; else no suggestion. This pile's advertising < 6 dB over the
//    neighbour: 「選台時可能判為不確定」. Firmware without the 1.7.27 fields:
//    upper from the link only, 「參考值（閘道器韌體較舊）」. Field: link
//    median against a neighbour's advertising peak read 「太接近」.
// 2. Too close in the installer's words (「鄰近樁 …2C… 比本樁還強 2 dB」, not
//    「相差 -2 dB」); the MAC never wraps (「）」 alone on a line).
// 3. 「結束並重新選擇閘道器」 at direct step 7 is the bottom bar's last row:
//    the card changing height no longer moves it (field: a tap missed by
//    7 px when the card's RSSI went 「RSSI —」 → 「-49 dBm」).
// 4. The back office's identify, relayed by the gateway, shows a passing
//    notice 「後台剛讓這台樁閃燈（請看樁上燈號）」 with the PTU's answer; the
//    flow is untouched.
// 5. 「辨識此樁」 reads 「已送出，等待 PTU 回應…」 at once (with a spinner)
//    until the ack (firmware 1.7.25+ waits up to 1.5 s for the PTU).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_calibration.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/direct_calibration_sheet.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

const _own = 'AA:BB:CC:00:00:01';
const _near = 'AA:BB:CC:00:00:02';
const _far = 'AA:BB:CC:00:00:03';

/// identify is held until [gate] completes (the firmware waits up to
/// 1.5 s for the PTU's answer before it acks).
class _SlowAck extends PickGateway {
  _SlowAck({super.rssi});
  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'identify' && gate != null) await gate!.future;
    return super.command(op, params);
  }
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

Future<(ProviderContainer, CommissioningController)> _toStep7(
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

void _phone(WidgetTester tester, {Size size = const Size(360, 640)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _idle(WidgetTester tester, ProviderContainer container) =>
    tester.runAsync(() async {
      for (var i = 0; i < 400 && container.read(commissionProvider).busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

/// A 1.7.27 `direct` report: connected to [linked] ([rssi]) advertising at
/// [selfAdv] (the key left out when [legacy]), with [neighbors] as (MAC,
/// peak, samples, age_s); legacy: [neighbors] as `candidates`.
Map<String, dynamic> _report({
  String linked = _own,
  int rssi = -47,
  int? selfAdv = -47,
  List<(String, int, int, num)> neighbors = const [],
  bool legacy = false,
}) => {
  'state': 'connected',
  'min_rssi': -55,
  'bound_mac': '',
  'select_reason': 'ok',
  'ptu_mac': linked,
  'ptu_rssi': rssi,
  if (legacy)
    'candidates': [
      for (final (mac, peak, count, _) in neighbors)
        {'mac': mac, 'rssi_peak': peak, 'rssi_last': peak - 5, 'count': count},
    ]
  else ...{
    'candidates': [
      // The last selection window: never used once `neighbors` is there.
      {'mac': _far, 'rssi_peak': -30, 'rssi_last': -30, 'count': 3},
    ],
    'self_adv_rssi_med': selfAdv,
    'self_adv_age_s': selfAdv == null ? null : 1,
    'neighbors': [
      for (final (mac, peak, samples, age) in neighbors)
        {
          'mac': mac,
          'rssi_peak': peak,
          'rssi_last': peak - 4,
          'rssi_med': peak - 6,
          'samples': samples,
          'age_s': age,
        },
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepSwitch, keepSettle, keepRetry;
  late Duration keepDuration, keepInterval;
  setUp(() {
    keepPoll = directPollInterval;
    keepSwitch = directSwitchWait;
    keepSettle = directSettleWindow;
    keepRetry = identifyRetryDelay;
    keepDuration = directCalibrationDuration;
    keepInterval = directCalibrationInterval;
    directPollInterval = const Duration(milliseconds: 1);
    directSwitchWait = const Duration(milliseconds: 200);
    directSettleWindow = const Duration(milliseconds: 1);
    identifyRetryDelay = const Duration(milliseconds: 1);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    directSwitchWait = keepSwitch;
    directSettleWindow = keepSettle;
    identifyRetryDelay = keepRetry;
    directCalibrationDuration = keepDuration;
    directCalibrationInterval = keepInterval;
  });

  group('1. threshold from the firmware\'s pick / drop rules', () {
    test('separable: midpoint of [neighbour peak + 1, upper]', () {
      // upper = min(adv -44, weakest -48 + 3 = -45) = -45; lower = -59.
      final s = suggestDirectThreshold(
        ownLink: [-45, -46, -48],
        ownAdvertising: -44,
        neighborPeaks: [-70, -60],
      );
      expect(s.verdict, DirectThresholdVerdict.suggested);
      expect(s.upper, -45);
      expect(s.lower, -59);
      expect(s.threshold, -52);
      expect(s.mayBeAmbiguous, isFalse);
      // The firmware's rules hold: this pile's advertising is picked, its
      // link is not dropped, the neighbour is not picked.
      expect(-44, greaterThanOrEqualTo(s.threshold!));
      expect(-48, greaterThanOrEqualTo(s.threshold! - 3));
      expect(-60, lessThan(s.threshold!));
    });

    test('upper from the link when that is lower than the advertising', () {
      // upper = min(-40, -52 + 3 = -49) = -49; lower = -69 → -59.
      final s = suggestDirectThreshold(
        ownLink: [-50, -52],
        ownAdvertising: -40,
        neighborPeaks: [-70],
      );
      expect(s.upper, -49);
      expect(s.threshold, -59);
    });

    test('too close (field round 19 figures): no suggestion', () {
      // Own advertising -47, link weakest -48 (upper -47); neighbour 2C
      // peaks at -46 (lower -45).
      final s = suggestDirectThreshold(
        ownLink: [-47, -48, -47],
        ownAdvertising: -47,
        neighborPeaks: [-46],
      );
      expect(s.verdict, DirectThresholdVerdict.tooClose);
      expect(s.threshold, isNull);
      expect(s.gap, -1);
      // Range exactly 2: suggested; 1: too close.
      expect(
        suggestDirectThreshold(
          ownLink: [-50],
          ownAdvertising: -47,
          neighborPeaks: [-50],
        ).threshold,
        -48,
      );
      expect(
        suggestDirectThreshold(
          ownLink: [-50],
          ownAdvertising: -47,
          neighborPeaks: [-49],
        ).verdict,
        DirectThresholdVerdict.tooClose,
      );
    });

    test('only ambiguous: a threshold, and the hint to bind', () {
      // upper = min(-45, -37) = -45, lower = -48 → -47; advertising only
      // 4 dB over the neighbour: the pick may come out ambiguous.
      final s = suggestDirectThreshold(
        ownLink: [-40],
        ownAdvertising: -45,
        neighborPeaks: [-49],
      );
      expect(s.verdict, DirectThresholdVerdict.suggested);
      expect(s.threshold, -47);
      expect(s.mayBeAmbiguous, isTrue);
      // 6 dB apart: not ambiguous.
      expect(
        suggestDirectThreshold(
          ownLink: [-40],
          ownAdvertising: -43,
          neighborPeaks: [-49],
        ).mayBeAmbiguous,
        isFalse,
      );
    });

    test('older firmware: upper from the link readings only', () {
      final s = suggestDirectThreshold(ownLink: [-40], neighborPeaks: [-49]);
      expect(s.upper, -37);
      expect(s.threshold, -43);
      expect(s.mayBeAmbiguous, isFalse, reason: 'no advertising figure');
    });

    // Round 28: was upper − 10 (field: -61 dBm, a neighbour's peak).
    test('no neighbour: the current threshold held, never wider', () {
      var s = suggestDirectThreshold(
        ownLink: [-50, -60],
        ownAdvertising: -52,
        neighborPeaks: const [],
      );
      expect(s.verdict, DirectThresholdVerdict.noNeighbors);
      expect(s.threshold, -55);
      s = suggestDirectThreshold(
        ownLink: [-88],
        neighborPeaks: const [],
        current: -50,
      );
      expect(s.threshold, -50);
      expect(s.ownBelowHold, isTrue);
    });

    test('no link reading: no suggestion; invalid readings ignored', () {
      final s = suggestDirectThreshold(
        ownLink: [0, -130],
        ownAdvertising: 0,
        neighborPeaks: [-70, 5],
      );
      expect(s.verdict, DirectThresholdVerdict.noOwnSignal);
      expect(s.ownAdvertising, isNull);
      expect(s.neighborStrongest, -70);
    });

    test('never above -20', () {
      expect(
        suggestDirectThreshold(
          ownLink: [-5],
          neighborPeaks: const [],
          current: -10,
        ).threshold,
        -20,
      );
      // Midpoint -14 clamped to -20, still within [-21, -7].
      expect(
        suggestDirectThreshold(ownLink: [-10], neighborPeaks: [-22]).threshold,
        -20,
      );
      // Midpoint -10 clamped to -20 falls under lower -17: too close.
      expect(
        suggestDirectThreshold(ownLink: [-5], neighborPeaks: [-18]).verdict,
        DirectThresholdVerdict.tooClose,
      );
    });
  });

  group('1. samples: new and old payloads', () {
    test('1.7.27: advertising median, neighbours[] peaks (not candidates)', () {
      final samples = DirectCalibrationSamples(_own.toLowerCase());
      for (final adv in [-46, -47, -48]) {
        samples.add(
          _report(
            selfAdv: adv,
            neighbors: [(_near, -58, 5, 2), (_far, -66, 9, 1)],
          ),
        );
      }
      // Another PTU connected: neither its link nor its advertising count.
      samples.add(_report(linked: _near, rssi: -30, selfAdv: -30));
      samples.add(null);
      expect(samples.basis, CalibrationBasis.current);
      expect(samples.ownLink, [-47, -47, -47]);
      expect(samples.ownAdvertising, -47);
      expect(samples.neighbors, {_near: -58, _far: -66});
      expect(samples.strongestNeighborMac, _near);
      expect(samples.reads, 5);
      expect(samples.missed, 1);
      // upper = min(-47, -44) = -47; lower = -57 → -52.
      expect(samples.suggestion.threshold, -52);
      expect(samples.suggestion.mayBeAmbiguous, isFalse);
      expect(samples.staleNeighborAge, isNull);
    });

    test('1.7.27: stale (> 60 s) left out; thin (< 3 samples) still '
        'counted toward the lower bound (round 19 fix)', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(
          _report(
            selfAdv: -45,
            neighbors: [(_near, -44, 8, 75), (_far, -50, 2, 1)],
          ),
        );
      // _near is stale (75 s > 60 s): left out. _far has only 2 samples
      // but is heard recently: still counted (round 19 fix — excluding a
      // thin-but-strong neighbour used to let the suggestion come out
      // under that neighbour's own peak, so this pile could pick it up
      // while off).
      expect(samples.neighbors, {_far: -50});
      expect(samples.staleNeighborAge, 75);
      expect(samples.fewSampleNeighbors, 1);
      // upper = min(-45, -47 + 3 = -44) = -45; lower = -50 + 1 = -49.
      expect(samples.suggestion.lower, -49);
      expect(samples.suggestion.verdict, DirectThresholdVerdict.suggested);
      expect(samples.suggestion.threshold, -47);
      expect(samples.suggestion.threshold!, greaterThan(-50));
      // Heard again recently (and enough): both count either way.
      samples.add(
        _report(
          selfAdv: -45,
          neighbors: [(_near, -60, 9, 3), (_far, -50, 4, 1)],
        ),
      );
      expect(samples.staleNeighborAge, isNull);
      expect(samples.neighbors, {_near: -44, _far: -50});
      expect(samples.suggestion.verdict, DirectThresholdVerdict.tooClose);
      expect(calibrationStaleText(75), contains('請按「$calibrationRescanLabel」'));
    });

    test('round 19 fix: only a thin (< 3 samples) neighbour — the '
        'suggestion still clears its peak', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(_report(selfAdv: -40, neighbors: [(_near, -55, 1, 5)]));
      // A single reading, well within age: still counted.
      expect(samples.neighbors, {_near: -55});
      expect(samples.fewSampleNeighbors, 1);
      final s = samples.suggestion;
      expect(s.verdict, DirectThresholdVerdict.suggested);
      expect(s.threshold, isNotNull);
      // Before the fix this neighbour was excluded outright, so with no
      // other neighbour counted the suggestion could land at or under
      // its peak (upper - calibrationLoneMargin) instead of clearing it.
      expect(s.threshold!, greaterThan(-55));
    });

    test('1.7.27 without this pile\'s advertising: link only, a reference '
        'value', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(
          _report(rssi: -40, selfAdv: null, neighbors: [(_near, -49, 5, 1)]),
        );
      expect(samples.basis, CalibrationBasis.noOwnAdvertising);
      expect(samples.basis.referenceText, calibrationReferenceNoAdvText);
      expect(samples.suggestion.threshold, -43);
    });

    test('older firmware: candidates\' peaks, link only, 「參考值（閘道器韌體較'
        '舊）」', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(_report(rssi: -40, legacy: true, neighbors: [(_near, -49, 3, 0)]))
        ..add(
          _report(rssi: -41, legacy: true, neighbors: [(_near, -50, 3, 0)]),
        );
      expect(samples.basis, CalibrationBasis.legacy);
      expect(samples.basis.referenceText, '參考值（閘道器韌體較舊）');
      expect(samples.ownAdvertising, isNull);
      expect(samples.neighbors, {_near: -49});
      // upper = -41 + 3 = -38, lower = -48 → -43.
      expect(samples.suggestion.threshold, -43);
      expect(samples.staleNeighborAge, isNull);
    });

    test('DirectStatus reads the 1.7.27 fields; older reports have none', () {
      final s = DirectStatus.from(
        _report(selfAdv: -44, neighbors: [(_near, -58, 5, 2)]),
      )!;
      expect(s.selfAdvReported, isTrue);
      expect(s.selfAdvRssiMed, -44);
      expect(s.selfAdvAgeS, 1);
      final n = s.neighbors!.single;
      expect(
        (n.mac, n.rssiPeak, n.rssiLast, n.rssiMed, n.samples, n.ageS),
        (_near, -58, -62, -64, 5, 2),
      );
      final old = DirectStatus.from(_report(legacy: true))!;
      expect(old.selfAdvReported, isFalse);
      expect(old.neighbors, isNull);
    });
  });

  group('2. too close in words; the MAC does not wrap', () {
    test('stronger / as strong / not weaker enough', () {
      expect(calibrationGapText(-2, '…2C…'), startsWith('鄰近樁 '));
      expect(calibrationGapText(-2, '…2C…'), endsWith(' 比本樁還強 2 dB'));
      expect(calibrationGapText(0, '…2C…'), endsWith(' 和本樁一樣強'));
      expect(
        calibrationGapText(2, '…2C…'),
        endsWith(' 只比本樁弱 2 dB，餘裕不足（至少要弱 $calibrationMinGap dB）'),
      );
      expect(calibrationGapText(-2, '…2C…'), isNot(contains('-2')));
      // The segment is joined: no break inside it.
      expect(noBreak('…2C…'), '…\u20602\u2060C\u2060…');
      expect(dbm(-48), '-48\u00A0dBm');
    });

    test('round 19 fix: the -100\u2026-20 clamp gets its own wording, not the '
        '(here self-contradictory) gap text', () {
      // Margin genuinely too small: the gap wording fits.
      final small = suggestDirectThreshold(
        ownLink: [-47, -48, -47],
        ownAdvertising: -47,
        neighborPeaks: [-46],
      );
      expect(small.verdict, DirectThresholdVerdict.tooClose);
      expect(small.outOfRange, isFalse);
      expect(
        calibrationTooCloseReason(small, '\u20262C\u2026'),
        calibrationGapText(small.gap!, '\u20262C\u2026'),
      );

      // Field bug: a fine 16 dB gap, but the natural midpoint (-10)
      // clamps to -20 and lands under lower (-17) \u2014 \u300C\u53EA\u6BD4\u672C\u6A01\u5F31 16
      // dB\uFF0C\u9918\u88D5\u4E0D\u8DB3\uFF08\u81F3\u5C11\u8981\u5F31 3 dB\uFF09\u300D would contradict itself here.
      final clamped = suggestDirectThreshold(
        ownLink: [-5],
        neighborPeaks: [-18],
      );
      expect(clamped.verdict, DirectThresholdVerdict.tooClose);
      expect(clamped.outOfRange, isTrue);
      expect(clamped.gap, greaterThanOrEqualTo(calibrationMinGap));
      final text = calibrationTooCloseReason(clamped, '\u20262C\u2026');
      expect(text, calibrationOutOfRangeText);
      expect(text, isNot(contains('\u9918\u88D5\u4E0D\u8DB3')));
      expect(text, isNot(contains('\u6BD4\u672C\u6A01')));
    });

    Future<ProviderContainer> openSheet(
      WidgetTester tester,
      void Function(PickGateway) setUp,
    ) async {
      directCalibrationDuration = const Duration(seconds: 3);
      directCalibrationInterval = const Duration(seconds: 1);
      final fake = PickGateway(rssi: [-40, -49, -58]);
      setUp(fake);
      late ProviderContainer container;
      await tester.runAsync(() async {
        final (k, c) = await _toStep7(fake);
        container = k;
        await c.identify();
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openDirectCalibration(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('1.7.27 sheet: advertising figure, the MAC on its own line, '
        'no reference label', (tester) async {
      await openSheet(
        tester,
        (fake) => fake
          ..directNeighborsReport = true
          ..selfAdvOffset = -2,
      );
      expect(find.textContaining('取樣完成'), findsOneWidget);
      expect(find.text('中位數 ${dbm(-42)}'), findsOneWidget);
      expect(find.text('峰值 ${dbm(-49)}'), findsOneWidget);
      final mac = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('calibration-neighbor-mac')),
          matching: find.byType(Text),
        ),
      );
      expect(mac.data, _near, reason: 'no brackets to wrap');
      expect(find.byKey(const Key('calibration-reference')), findsNothing);
      // upper = min(-42, -37) = -42, lower = -48 → -45.
      expect(find.textContaining('建議門檻：-45 dBm'), findsOneWidget);
      expect(
        find.textContaining('可用範圍 ${dbm(-48)} ～ ${dbm(-42)}'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('calibration-ambiguous')), findsNothing);
    });

    testWidgets('1.7.27 sheet: only ambiguous — a threshold and the hint', (
      tester,
    ) async {
      await openSheet(
        tester,
        (fake) => fake
          ..directNeighborsReport = true
          ..selfAdvOffset = -5,
      );
      expect(find.textContaining('建議門檻：-47 dBm'), findsOneWidget);
      expect(find.byKey(const Key('calibration-ambiguous')), findsOneWidget);
      expect(find.textContaining('綁定後就不受影響'), findsOneWidget);
    });

    testWidgets('1.7.27 sheet: a stale neighbour is left out, 重新掃描鄰近', (
      tester,
    ) async {
      await openSheet(tester, (fake) {
        fake
          ..directNeighborsReport = true
          ..selfAdvOffset = -2;
        fake.neighborAges[_near] = 75;
      });
      expect(find.byKey(const Key('calibration-stale')), findsOneWidget);
      expect(find.text(calibrationStaleText(75)), findsOneWidget);
      expect(find.text(calibrationRescanLabel), findsOneWidget);
      // The next neighbour counts: lower -57, upper -42 → -50.
      expect(find.text('峰值 ${dbm(-58)}'), findsOneWidget);
      expect(find.textContaining('建議門檻：-50 dBm'), findsOneWidget);
    });

    testWidgets('older firmware sheet: 參考值（閘道器韌體較舊）', (tester) async {
      await openSheet(tester, (_) {});
      expect(find.text(calibrationReferenceLegacyText), findsOneWidget);
      expect(find.text('閘道器韌體較舊，未回報'), findsOneWidget);
      expect(find.textContaining('建議門檻：-43 dBm'), findsOneWidget);
    });

    testWidgets('too close: the neighbour named by its bytes, stronger by N '
        'dB, then bind', (tester) async {
      await openSheet(tester, (fake) {
        fake
          ..directNeighborsReport = true
          ..selfAdvOffset = -8;
        fake.devices[1]['rssi'] = -46;
      });
      // upper = min(-48, -37) = -48; the neighbour peaks at -46.
      final box = find.byKey(const Key('calibration-too-close'));
      expect(box, findsOneWidget);
      final text = tester
          .widget<Text>(find.descendant(of: box, matching: find.byType(Text)))
          .data!;
      expect(text, startsWith('鄰近樁 ${noBreak('…02')} 比本樁還強 2 dB。'));
      expect(text, endsWith('$calibrationTooCloseText。'));
      expect(text, isNot(contains('相差')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('calibration-write')))
            .onPressed,
        isNull,
      );
    });
  });

  group('3. 結束並重新選擇閘道器 does not move with the card', () {
    testWidgets('direct step 7: in the bottom bar, same place when the card '
        'shrinks', (tester) async {
      _phone(tester, size: const Size(411, 891));
      SharedPreferences.setMockInitialValues({});
      // Ambiguous: the card has its yellow box.
      final fake = PickGateway(rssi: [-40, -43, -70]);
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
      expect(container.read(commissionProvider).direct!.ambiguous, isTrue);
      final end = find.byKey(const Key('page-cancel'));
      expect(end, findsOneWidget);
      expect(
        find.descendant(of: find.byType(DirectPickActions), matching: end),
        findsOneWidget,
        reason: 'the bottom bar, not the scrolled page',
      );
      expect(
        find.descendant(of: end, matching: find.text(endFlowLabel)),
        findsOneWidget,
      );
      final before = tester.getRect(end);
      final card = tester.getRect(find.byKey(const Key('direct-status')));

      // 不是這台？ → bound to another PTU: no yellow box, a shorter card.
      await tester.runAsync(() => c.switchDirectPick(_near));
      await tester.pump();
      expect(container.read(commissionProvider).direct!.pickedMac, _near);
      expect(find.byKey(const Key('direct-ambiguous')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('direct-status'))).height,
        lessThan(card.height),
      );
      expect(tester.getRect(end), before);
      expect(tester.widget<TextButton>(end).onPressed, isNotNull);

      // Still asks first.
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('end-confirm-continue')));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 4);
    });

    Future<ProviderContainer> pumpStep7(
      WidgetTester tester, {
      required double textScale,
    }) async {
      _phone(tester, size: const Size(360, 640));
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
      return container;
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets(
        '360x640 at text scale $scale: the end button stays on screen, '
        'clear of the bar\'s other buttons',
        (tester) async {
          await pumpStep7(tester, textScale: scale);
          // No overflow (a row too wide for the phone, or the bar
          // clipped off the bottom) went unnoticed.
          expect(tester.takeException(), isNull);
          final end = find.byKey(const Key('page-cancel'));
          expect(end, findsOneWidget);
          const screen = Rect.fromLTWH(0, 0, 360, 640);
          final endRect = tester.getRect(end);
          expect(screen.contains(endRect.topLeft), isTrue);
          expect(screen.contains(endRect.bottomRight), isTrue);
          for (final key in const [
            'direct-identify',
            'direct-not-this',
            'direct-others-bottom',
            'direct-confirm',
            'direct-wait',
            'direct-rescan-bottom',
            'direct-stop',
          ]) {
            final finder = find.byKey(Key(key));
            if (finder.evaluate().isEmpty) continue;
            expect(
              endRect.overlaps(tester.getRect(finder)),
              isFalse,
              reason: '$key overlaps the end button at text scale $scale',
            );
          }
        },
      );
    }
  });

  group('4. the back office\'s identify', () {
    test('foreign acks: not this link\'s own req_id, result parsed', () {
      expect(
        foreignAckOf({
          'req_id': 'app-1a2b-7',
          'status': 'ok',
          'result': '{}',
        }, 'app-1a2b-'),
        isNull,
        reason: 'a late ack of our own',
      );
      expect(
        foreignAckOf({
          'req_id': '20260926-00007',
          'status': 'ok',
          'result': '{"ptu_write":"ok","ptu_confirm":"timeout","rssi":-46}',
        }, 'app-1a2b-'),
        {
          'ptu_write': 'ok',
          'ptu_confirm': 'timeout',
          'rssi': -46,
          'req_id': '20260926-00007',
          'status': 'ok',
        },
      );
      expect(foreignAckOf({'status': 'ok'}, 'app-'), isNull);
    });

    test('the text names the PTU\'s answer', () {
      const ack = {
        'gateway_led': 'ok',
        'ptu_write': 'ok',
        'ptu_confirmed': false,
        'ptu_confirm': 'timeout',
        'mac': _own,
        'rssi': -46,
      };
      expect(isIdentifyAck(ack), isTrue);
      // Round 24: the PTU that blinked is named (no list: its MAC).
      expect(
        remoteIdentifyText(ack),
        '後台讓 PTU $_own 閃燈（請看樁上燈號） · PTU 未回應確認（PTU 韌體尚未支援）'
        ' · -46 dBm',
      );
      expect(
        remoteIdentifyText({
          ...ack,
          'ptu_confirmed': true,
          'ptu_confirm': 'ok',
        }),
        contains(identifyConfirmedText),
      );
      // Round 24: only the gateway blinked — said so, no raw code.
      expect(
        remoteIdentifyText(const {'ptu_write': 'not_connected'}),
        '後台讓閘道器閃燈（請看閘道器上的燈）',
      );
      expect(isIdentifyAck(const {'free_heap': 1}), isFalse);
    });

    test('a notice, nothing else changes; other acks ignored', () async {
      final fake = PickGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.identify();
      final before = container.read(commissionProvider);
      final sent = fake.sent('identify').length;
      expect(before.identifiedMac, isNotNull);

      fake.relayForeignAck(const {
        'free_heap': 1000,
        'req_id': '20260926-00008',
        'status': 'ok',
      });
      fake.relayForeignAck(const {
        'message': 'not_connected',
        'req_id': '20260926-00009',
        'status': 'fail',
      });
      await Future<void>.delayed(Duration.zero);
      expect(container.read(commissionProvider).remoteIdentifyCount, 0);

      fake.remoteIdentify();
      await Future<void>.delayed(Duration.zero);
      final after = container.read(commissionProvider);
      expect(after.remoteIdentifyCount, 1);
      expect(after.remoteIdentifyNote, startsWith('後台讓 PTU '));
      expect(after.remoteIdentifyNote, contains('閃燈（請看樁上燈號）'));
      expect(after.remoteIdentifyNote, contains('PTU 未回應確認'));
      expect(after.step, before.step);
      expect(after.busy, before.busy);
      expect(after.error, before.error);
      expect(after.identifiedMac, before.identifiedMac);
      expect(after.identifyNote, before.identifyNote);
      expect(after.selected, before.selected);
      expect(fake.sent('identify'), hasLength(sent), reason: 'nothing sent');
    });

    // Round 20: at direct step 7 the notice is the bar's identify line
    // (round20_fixes_test.dart); the key, the text and the bar hold.
    testWidgets('page: a passing notice', (tester) async {
      _phone(tester, size: const Size(411, 891));
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
      });
      await tester.pump();
      final bar = tester.getRect(find.byType(DirectPickActions));
      await tester.runAsync(() async {
        fake.remoteIdentify(confirm: 'ok');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('remote-identify')), findsOneWidget);
      // Round 21: the bar shows the short first sentence.
      expect(find.textContaining('後台已讓此樁閃燈'), findsOneWidget);
      expect(find.textContaining('PTU 已確認'), findsOneWidget);
      expect(tester.getRect(find.byType(DirectPickActions)), bar);
      expect(container.read(commissionProvider).step, 4);
    });
  });

  group('5. 辨識此樁: sent, waiting for the PTU', () {
    testWidgets('the note and a spinner at once, the result after the ack', (
      tester,
    ) async {
      _phone(tester);
      final fake = _SlowAck()..identifyPtuConfirm = 'timeout';
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      fake.gate = Completer<void>();

      await tester.tap(find.byKey(const Key('direct-identify')));
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.busy, isTrue);
      expect(s.identifyNote, identifyPendingText);
      expect(s.identifyLine, identifyPendingText);
      expect(find.text(identifyPendingText), findsOneWidget);
      expect(find.byKey(const Key('direct-identify-pending')), findsOneWidget);

      fake.gate!.complete();
      await tester.pump();
      await _idle(tester, container);
      await tester.pump();
      final done = container.read(commissionProvider);
      expect(done.identifyLine, startsWith('已送出 · PTU 未回應確認 · 請看樁上燈號'));
      expect(find.byKey(const Key('direct-identify-pending')), findsNothing);
      expect(find.text(identifyPendingText), findsNothing);
    });

    test('gateway-only firmware: waiting for the gateway', () async {
      final fake = _SlowAck(rssi: const [-50, -38, -60]);
      fake.config.remove('identify_ptu_supported');
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      fake.gate = Completer<void>();
      final running = c.identify();
      expect(
        container.read(commissionProvider).identifyNote,
        identifyPendingGatewayText,
      );
      fake.gate!.complete();
      await running;
      expect(
        container.read(commissionProvider).identifyNote,
        isNot(identifyPendingGatewayText),
      );
    });
  });

  test('bench round 19: 5F -47/-48 against 2C -46 (peak) is too close on '
      'the old figures too', () {
    final s = suggestDirectThreshold(
      ownLink: [...List.filled(12, -47), -48],
      neighborPeaks: [-46],
    );
    // Older firmware: upper -45, lower -45.
    expect(s.verdict, DirectThresholdVerdict.tooClose);
  });
}
