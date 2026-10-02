// Round 20 (after field round 20, APP 1f79459, firmware 1.7.30):
// 1. Delivery: tools/build_apk.ps1 signs and verifies every APK (local:
//    LOCAL_DEVELOPMENT=true + the field-test debug key) — a script, run by
//    hand; nothing to unit test here.
// 2. `self_adv_rssi_med` is measured while the gateway selects and frozen
//    once connected (field: `self_adv_age_s` 249–274 s at calibration).
//    The sheet says 「本樁廣播值來自 N 分鐘前選台」; over 900 s or without an
//    age it no longer bounds the threshold — upper from the link readings
//    only, marked 參考值.
// 3. Neighbours within 1 dB of the strongest are named together (at most 3,
//    MAC order) — field: …2C… and …74… both at -46 dBm, one of them named
//    by list order, so the named pile flipped between runs.
// 4. The back office's identify notice no longer covers the card's yellow
//    box at direct step 7 (field: a snack bar over it for 8 s): it takes
//    the bottom bar's identify line; every button and the box stay visible.
import 'dart:async';

import 'support/direct_pick_actions.dart';

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
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/direct_calibration_sheet.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

const _own = 'AA:BB:CC:00:00:01';
const _near = 'AA:BB:CC:00:00:02';
const _far = 'AA:BB:CC:00:00:03';
const _fourth = 'AA:BB:CC:00:00:04';
const _fifth = 'AA:BB:CC:00:00:05';

// Field round 20's bench (5F confirmed; 2C and 74 both peaked at -46).
const _b5F = '90:5F:E8:9A:96:00';
const _b2C = '90:2C:5A:3E:96:00';
const _b74 = '90:74:03:11:96:00';
const _b3B = '90:3B:11:27:96:00';
const _b08 = '90:08:77:C1:96:00';

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// A firmware 1.7.27+ `direct` report: connected to [linked] ([rssi]),
/// advertising median [selfAdv] measured [age] s ago (null: no age), with
/// [neighbors] as (MAC, peak, samples, age_s).
Map<String, dynamic> _report({
  String linked = _own,
  int rssi = -47,
  int? selfAdv = -47,
  num? age = 1,
  List<(String, int, int, num)> neighbors = const [],
}) => {
  'state': 'connected',
  'min_rssi': -55,
  'bound_mac': '',
  'select_reason': 'ok',
  'ptu_mac': linked,
  'ptu_rssi': rssi,
  'candidates': const [],
  'self_adv_rssi_med': selfAdv,
  'self_adv_age_s': age,
  'neighbors': [
    for (final (mac, peak, samples, ageS) in neighbors)
      {
        'mac': mac,
        'rssi_peak': peak,
        'rssi_last': peak - 4,
        'rssi_med': peak - 6,
        'samples': samples,
        'age_s': ageS,
      },
  ],
};

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

/// The whole page at the PTU step (direct step 7 unless [topology]).
Future<(ProviderContainer, CommissioningController)> _pumpPage(
  WidgetTester tester,
  PickGateway fake, {
  GatewayTopology topology = GatewayTopology.direct,
}) async {
  SharedPreferences.setMockInitialValues({});
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
    await topo.setTopology(topology);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await c.chooseStation(newStation: false);
  });
  await tester.pump();
  return (container, c);
}

/// [finder]'s centre reaches it: nothing is drawn over it there.
bool _uncovered(WidgetTester tester, Finder finder) {
  final target = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == target);
}

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

  group('2. this pile\'s advertising value: its age, stale ones left out', () {
    test('the age in the installer\'s words', () {
      expect(calibrationSelfAdvAgeText(249), '本樁廣播值來自 4 分鐘前選台');
      expect(calibrationSelfAdvAgeText(274), '本樁廣播值來自 4 分鐘前選台');
      expect(calibrationSelfAdvAgeText(60), '本樁廣播值來自 1 分鐘前選台');
      expect(calibrationSelfAdvAgeText(12), '本樁廣播值來自 12 秒前選台');
      expect(calibrationSelfAdvAgeText(null), '本樁廣播值未附選台時間');
      expect(calibrationSelfAdvMaxAge, 900);
      expect(calibrationReferenceStaleAdvText, startsWith('參考值'));
      expect(calibrationReferenceStaleAdvText, contains('15 分鐘'));
      expect(calibrationReferenceUndatedAdvText, startsWith('參考值'));
    });

    test('fresh (field: 249–274 s): it bounds the threshold, not a '
        'reference value', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(
          _report(
            rssi: -40,
            selfAdv: -47,
            age: 249,
            neighbors: [(_near, -60, 8, 2)],
          ),
        )
        ..add(
          _report(
            rssi: -40,
            selfAdv: -47,
            age: 274,
            neighbors: [(_near, -60, 8, 1)],
          ),
        );
      expect(samples.basis, CalibrationBasis.current);
      expect(samples.basis.reference, isFalse);
      expect(samples.ownAdvertisingAgeS, 274, reason: 'the latest read');
      expect(samples.usableOwnAdvertising, -47);
      // upper = min(-47, -40 + 3) = -47; lower = -59 → -53.
      final s = samples.suggestion;
      expect(s.upper, -47);
      expect(s.threshold, -53);
    });

    test('over 900 s: upper from the link only, 參考值', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(
          _report(
            rssi: -40,
            selfAdv: -47,
            age: 901,
            neighbors: [(_near, -60, 8, 2)],
          ),
        );
      expect(samples.basis, CalibrationBasis.staleOwnAdvertising);
      expect(samples.basis.reference, isTrue);
      expect(samples.basis.ownAdvertisingSkipped, isTrue);
      expect(samples.basis.referenceText, calibrationReferenceStaleAdvText);
      expect(samples.ownAdvertising, -47, reason: 'still shown as read');
      expect(samples.usableOwnAdvertising, isNull);
      final s = samples.suggestion;
      expect(s.ownAdvertising, isNull);
      // upper = -40 + 3 = -37 (the frozen -47 no longer counts); lower
      // -59 → -48.
      expect(s.upper, -37);
      expect(s.threshold, -48);
      expect(s.mayBeAmbiguous, isFalse);
    });

    test('900 s still counts; the latest read\'s age decides', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(
          _report(
            rssi: -40,
            selfAdv: -47,
            age: 900,
            neighbors: [(_near, -60, 8, 2)],
          ),
        );
      expect(samples.basis, CalibrationBasis.current);
      expect(samples.suggestion.upper, -47);
      samples.add(
        _report(
          rssi: -40,
          selfAdv: -47,
          age: 902,
          neighbors: [(_near, -60, 8, 2)],
        ),
      );
      expect(samples.basis, CalibrationBasis.staleOwnAdvertising);
      expect(samples.suggestion.upper, -37);
    });

    test('no age (null): upper from the link only, 參考值', () {
      final samples = DirectCalibrationSamples(_own)
        ..add(
          _report(
            rssi: -40,
            selfAdv: -47,
            age: null,
            neighbors: [(_near, -60, 8, 2)],
          ),
        );
      expect(samples.basis, CalibrationBasis.undatedOwnAdvertising);
      expect(samples.basis.referenceText, calibrationReferenceUndatedAdvText);
      expect(samples.ownAdvertisingAgeS, isNull);
      expect(samples.usableOwnAdvertising, isNull);
      expect(samples.suggestion.upper, -37);
      expect(samples.suggestion.threshold, -48);
      // Nothing heard at all stays 「閘道器未回報」.
      final none = DirectCalibrationSamples(_own)
        ..add(_report(rssi: -40, selfAdv: null, age: null));
      expect(none.basis, CalibrationBasis.noOwnAdvertising);
    });
  });

  group('3. neighbours within 1 dB named together', () {
    List<String> named(List<(String, int, int, num)> near) =>
        (DirectCalibrationSamples(
          _own,
        )..add(_report(neighbors: near))).strongestNeighborMacs;

    test('equal peaks: both, in MAC order, whatever the report order', () {
      expect(
        named([(_far, -46, 8, 1), (_near, -46, 8, 1), (_fourth, -48, 8, 1)]),
        [_near, _far],
      );
      expect(named([(_near, -46, 8, 1), (_far, -46, 8, 1)]), [_near, _far]);
      // Peaks trading 1 dB between runs: the same two, the same order.
      expect(named([(_near, -47, 8, 1), (_far, -46, 8, 1)]), [_near, _far]);
      expect(named([(_far, -47, 8, 1), (_near, -46, 8, 1)]), [_near, _far]);
      // 2 dB apart: the strongest alone.
      expect(named([(_near, -48, 8, 1), (_far, -46, 8, 1)]), [_far]);
      expect(named(const []), isEmpty);
      // A stale neighbour is not named.
      expect(named([(_near, -46, 8, 75), (_far, -46, 8, 1)]), [_far]);
    });

    test('more than 3 within 1 dB: 3 named (the strongest kept), 等 N 台', () {
      final s = DirectCalibrationSamples(_own)
        ..add(
          _report(
            neighbors: [
              (_fourth, -47, 8, 1),
              (_far, -47, 8, 1),
              (_near, -47, 8, 1),
              (_fifth, -46, 8, 1),
            ],
          ),
        );
      expect(s.strongestNeighborMac, _fifth);
      expect(s.strongestNeighborTies, 4);
      expect(s.strongestNeighborMacs, [_near, _far, _fifth]);
      expect(
        calibrationNeighborLabel(['…02', '…03', '…05'], total: 4),
        '${noBreak('…02')}、${noBreak('…03')}、${noBreak('…05')} 等 4 台',
      );
      expect(calibrationNeighborLabel(['…02'], total: 1), noBreak('…02'));
      expect(calibrationNeighborLabel(['…02']), noBreak('…02'));
    });

    test('bench round 20: …2C… and …74… (both -46) named together every '
        'run; the figures still match the firmware', () {
      String reason(List<(String, int, int, num)> near) {
        final s = DirectCalibrationSamples(_b5F);
        for (final rssi in [-46, -46, -47, -48, -46]) {
          s.add(
            _report(
              linked: _b5F,
              rssi: rssi,
              selfAdv: -47,
              age: 249,
              neighbors: near,
            ),
          );
        }
        final others = [_b5F, ...s.neighborMacs];
        return calibrationTooCloseReason(
          s.suggestion,
          calibrationNeighborLabel([
            for (final mac in s.strongestNeighborMacs)
              distinguishingMacSegment(mac, others),
          ], total: s.strongestNeighborTies),
        );
      }

      final expected = '鄰近樁 ${noBreak('…2C…')}、${noBreak('…74…')} 比本樁還強 1 dB';
      // upper = min(-47, -48 + 3) = -47; lower = -45: too close, gap -1.
      expect(
        reason([
          (_b2C, -46, 9, 1),
          (_b74, -46, 9, 0),
          (_b3B, -48, 9, 2),
          (_b08, -53, 9, 1),
        ]),
        expected,
      );
      expect(
        reason([
          (_b74, -46, 9, 0),
          (_b3B, -48, 9, 2),
          (_b2C, -46, 9, 1),
          (_b08, -53, 9, 1),
        ]),
        expected,
      );
    });
  });

  group('2/3. the calibration sheet', () {
    Future<void> openSheet(
      WidgetTester tester,
      List<int> rssi,
      void Function(PickGateway) setUp,
    ) async {
      directCalibrationDuration = const Duration(seconds: 3);
      directCalibrationInterval = const Duration(seconds: 1);
      final fake = PickGateway(rssi: rssi)..directNeighborsReport = true;
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
      expect(find.textContaining('取樣完成'), findsOneWidget);
    }

    testWidgets('fresh: 「本樁廣播值來自 4 分鐘前選台」, used, no reference label', (
      tester,
    ) async {
      await openSheet(tester, [-40, -49, -58], (fake) {
        fake
          ..selfAdvOffset = -2
          ..selfAdvAgeS = 249;
      });
      expect(find.text('中位數 ${dbm(-42)}'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('calibration-own-adv-age')))
            .data,
        '本樁廣播值來自 4 分鐘前選台',
      );
      expect(find.byKey(const Key('calibration-reference')), findsNothing);
      // upper = min(-42, -37) = -42, lower = -48 → -45.
      expect(find.textContaining('建議門檻：-45 dBm'), findsOneWidget);
    });

    testWidgets('over 15 minutes: shown, left out of the upper bound, 參考值', (
      tester,
    ) async {
      await openSheet(tester, [-40, -49, -58], (fake) {
        fake
          ..selfAdvOffset = -2
          ..selfAdvAgeS = 1000;
      });
      expect(find.text('中位數 ${dbm(-42)}（未列入上限）'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('calibration-own-adv-age')))
            .data,
        '本樁廣播值來自 16 分鐘前選台',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('calibration-reference')))
            .data,
        calibrationReferenceStaleAdvText,
      );
      // upper = -40 + 3 = -37, lower = -48 → -43 (fresh it was -45).
      expect(find.textContaining('建議門檻：-43 dBm'), findsOneWidget);
      expect(
        find.textContaining('可用範圍 ${dbm(-48)} ～ ${dbm(-37)}'),
        findsOneWidget,
      );
    });

    testWidgets('no age: 參考值（…未附選台時間…）', (tester) async {
      await openSheet(tester, [-40, -49, -58], (fake) {
        fake
          ..selfAdvOffset = -2
          ..selfAdvAgeS = null;
      });
      expect(find.text('本樁廣播值未附選台時間'), findsOneWidget);
      expect(find.text(calibrationReferenceUndatedAdvText), findsOneWidget);
      expect(find.textContaining('建議門檻：-43 dBm'), findsOneWidget);
    });

    testWidgets('two neighbours within 1 dB: both listed and named in the '
        'yellow box', (tester) async {
      await openSheet(tester, [-40, -46, -47], (fake) {
        fake.selfAdvOffset = -8;
      });
      // upper = min(-48, -37) = -48; the neighbours peak at -46 / -47.
      expect(find.text('峰值 ${dbm(-46)}'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('calibration-neighbor-ties')))
            .data,
        '2 台相差 1 dB 內，一併列出',
      );
      String mac(String key) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(mac('calibration-neighbor-mac'), _near);
      expect(mac('calibration-neighbor-mac-2'), _far);
      final box = find.byKey(const Key('calibration-too-close'));
      final text = tester
          .widget<Text>(find.descendant(of: box, matching: find.byType(Text)))
          .data!;
      expect(
        text,
        startsWith('鄰近樁 ${noBreak('…02')}、${noBreak('…03')} 比本樁還強 2 dB。'),
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('calibration-write')))
            .onPressed,
        isNull,
      );
    });
  });

  group('4. the back office\'s identify does not cover the card', () {
    const buttons = [
      'direct-identify',
      'direct-more',
      'direct-confirm',
      'direct-stop',
    ];

    for (final size in const [Size(360, 640), Size(411, 891)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('$label: the notice takes the bar\'s identify line; the '
          'yellow box and every button stay visible, uncovered', (
        tester,
      ) async {
        _phone(tester, size);
        // Ambiguous: the card has its yellow box.
        final fake = PickGateway(rssi: [-40, -43, -70]);
        final (container, _) = await _pumpPage(tester, fake);
        expect(container.read(commissionProvider).direct!.ambiguous, isTrue);

        // As on the phone (field c01): the card scrolled up, its yellow
        // box right above the bottom bar.
        final page = find
            .ancestor(
              of: find.byKey(const Key('task-title')),
              matching: find.byType(Scrollable),
            )
            .first;
        final box = find.byKey(const Key('direct-ambiguous'));
        await tester.scrollUntilVisible(box, 80, scrollable: page);
        unawaited(Scrollable.ensureVisible(tester.element(box), alignment: 1));
        await tester.pump();
        // 09-28: the page is shorter (details collapsed) and may not scroll
        // that far: it settles at its end first, as a finger would leave it.
        final scroll = tester
            .state<ScrollableState>(
              find.ancestor(of: box, matching: find.byType(Scrollable)).first,
            )
            .position;
        if (scroll.pixels > scroll.maxScrollExtent) {
          scroll.jumpTo(scroll.maxScrollExtent);
          await tester.pump();
        }
        // Round 28: the page's list, found from the box (the header may
        // take one more line with the Wi-Fi MAC tail, so the banner at the
        // top of the list is no longer built once scrolled this far).
        final viewport = tester.getRect(
          find.ancestor(of: box, matching: find.byType(Scrollable)).first,
        );
        final boxRect = tester.getRect(box);
        expect(viewport.top, lessThanOrEqualTo(boxRect.top));
        expect(viewport.bottom, greaterThanOrEqualTo(boxRect.bottom));
        expect(_uncovered(tester, box), isTrue);
        final before = {
          for (final key in buttons) key: tester.getRect(find.byKey(Key(key))),
        };
        final bar = tester.getRect(find.byType(DirectPickActions));

        await tester.runAsync(() async {
          fake.remoteIdentify(confirm: 'timeout');
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(SnackBar), findsNothing);
        final notice = find.byKey(const Key('remote-identify'));
        expect(notice, findsOneWidget);
        expect(
          find.descendant(of: find.byType(DirectPickActions), matching: notice),
          findsOneWidget,
        );
        expect(find.byKey(const Key('remote-identify-icon')), findsOneWidget);
        // Round 21: the short first sentence (full text behind the tap).
        expect(find.textContaining('後台已送出'), findsOneWidget);
        final screen = Offset.zero & size;
        final noticeRect = tester.getRect(notice);
        expect(screen.contains(noticeRect.topLeft), isTrue);
        expect(
          screen.contains(noticeRect.bottomRight - const Offset(1, 1)),
          isTrue,
        );
        expect(_uncovered(tester, notice), isTrue);
        // The yellow box: same place, fully in view, nothing over it.
        expect(tester.getRect(box), boxRect);
        expect(noticeRect.overlaps(boxRect), isFalse);
        expect(_uncovered(tester, box), isTrue);
        // Every button: same place, on screen, nothing over it.
        expect(tester.getRect(find.byType(DirectPickActions)), bar);
        for (final key in buttons) {
          final button = find.byKey(Key(key));
          expect(tester.getRect(button), before[key], reason: key);
          expect(
            screen.contains(
              tester.getRect(button).bottomRight - const Offset(1, 1),
            ),
            isTrue,
            reason: key,
          );
          expect(
            noticeRect.overlaps(tester.getRect(button)),
            isFalse,
            reason: key,
          );
          expect(_uncovered(tester, button), isTrue, reason: key);
        }
        expect(container.read(commissionProvider).step, 4);

        // A tap shows the whole text.
        await tester.tap(find.byKey(const Key('direct-identify-toggle')));
        await tester.pump();
        final detail = find.byKey(const Key('remote-identify-detail'));
        expect(detail, findsOneWidget);
        expect(
          find.descendant(
            of: detail,
            matching: find.textContaining('舊版閘道器未取得 PTU 確認'),
            matchRoot: true,
          ),
          findsOneWidget,
        );

        await closeIdentifyDetails(tester);

        // 8 s later the installer's own line is back.
        await tester.pump(remoteIdentifyNoticeDuration);
        await tester.pump();
        expect(notice, findsNothing);
        expect(detail, findsNothing);
        expect(find.byKey(const Key('direct-identify-note')), findsOneWidget);
        expect(tester.getRect(find.byType(DirectPickActions)), bar);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the installer\'s own identify takes the line back at once', (
      tester,
    ) async {
      _phone(tester, const Size(411, 891));
      final fake = PickGateway();
      final (container, c) = await _pumpPage(tester, fake);
      await tester.runAsync(() async {
        fake.remoteIdentify(confirm: 'ok');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(find.byKey(const Key('remote-identify')), findsOneWidget);
      expect(find.textContaining('PTU 已確認'), findsOneWidget);

      await tester.runAsync(c.identify);
      await tester.pump();
      expect(find.byKey(const Key('remote-identify')), findsNothing);
      expect(find.byKey(const Key('direct-identify-note')), findsOneWidget);
      expect(container.read(commissionProvider).identifyNote, isNotEmpty);
      await tester.pump(remoteIdentifyNoticeDuration);
    });

    testWidgets('star mode PTU list (no identify line): still a passing '
        'snack bar', (tester) async {
      _phone(tester, const Size(411, 891));
      final fake = PickGateway();
      final (container, _) = await _pumpPage(
        tester,
        fake,
        topology: GatewayTopology.star,
      );
      expect(container.read(commissionProvider).step, 4);
      expect(find.byType(DirectPickActions), findsNothing);
      await tester.runAsync(() async {
        fake.remoteIdentify(confirm: 'timeout');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byKey(const Key('remote-identify')), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
