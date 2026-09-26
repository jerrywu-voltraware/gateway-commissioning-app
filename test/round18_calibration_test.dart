// Round 18 (after field round 17b, APP 60ed0b3, firmware 1.7.25):
// 1. 「校正門檻」 (direct mode): piles side by side need a threshold that
//    depends on the actual housing. The APP samples get_status for 20 s —
//    this pile's confirmed PTU (link RSSI: median, weakest) against the
//    strongest neighbour (candidate peaks of other MACs) — and suggests
//    the midpoint, at least 6 dB under this pile's weakest and 3 dB over
//    the strongest neighbour; closer than 9 dB: a yellow warning, no
//    suggestion; no neighbour: weakest − 10 (not below -90). 「寫入閘道器」
//    sends set_config and reads get_config back; 「取消」 writes nothing.
// 2. identify ack (firmware 1.7.25): `ptu_confirmed:true` → 「PTU 已確認
//    亮燈」; `ptu_confirm:"timeout"` → 「閘道器已送出；PTU 未回應確認（PTU
//    韌體尚未支援），請看樁上燈號」; no such field → the texts from before.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_calibration.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/direct_calibration_sheet.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

/// The demo's PTUs: -40 (the gateway's pick), -49, -58 dBm.
const _own = 'AA:BB:CC:00:00:01';
const _near = 'AA:BB:CC:00:00:02';

/// Gateway 3 of site 80 in direct mode, recording every command.
/// [ignoreThreshold]: set_config of the threshold is acked but not kept
/// (get_config reads the old value back).
class _Gateway extends DemoSystem {
  _Gateway() {
    config.addAll({'fleet_joined': true, 'site_id': 80, 'gateway_id': 3});
  }

  final commands = <(String, Map<String, dynamic>)>[];
  bool ignoreThreshold = false;

  List<Map<String, dynamic>> sent(String op) => [
    for (final (o, p) in commands)
      if (o == op) p,
  ];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    commands.add((op, Map.of(params)));
    if (op == 'set_config' &&
        ignoreThreshold &&
        params.containsKey('auto_connect_min_rssi')) {
      return Future.value({});
    }
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _connect(
  _Gateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  await container
      .read(topologyProvider.notifier)
      .setTopology(GatewayTopology.direct);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  return (container, c);
}

/// A get_status `direct` object: [linked] connected at [rssi], and
/// [candidates] as (MAC, peak).
Map<String, dynamic> _direct(
  String? linked,
  int? rssi,
  List<(String, int)> candidates,
) => {
  'state': linked == null ? 'scanning' : 'connected',
  'min_rssi': -55,
  'bound_mac': '',
  'select_reason': 'ok',
  'ptu_mac': ?linked,
  'ptu_rssi': ?rssi,
  'candidates': [
    for (final (mac, peak) in candidates)
      {'mac': mac, 'rssi_peak': peak, 'rssi_last': peak, 'count': 3},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final duration = directCalibrationDuration;
  final interval = directCalibrationInterval;
  tearDown(() {
    directCalibrationDuration = duration;
    directCalibrationInterval = interval;
  });

  group('suggestDirectThreshold', () {
    test('midpoint of this pile\'s median and the strongest neighbour', () {
      // Median -45, weakest -48; neighbours -75 / -80: midpoint -60, within
      // both margins (≤ -54, ≥ -72).
      final s = suggestDirectThreshold([-44, -45, -48, -43, -46], [-80, -75]);
      expect(s.verdict, DirectThresholdVerdict.suggested);
      expect(s.ownMedian, -45);
      expect(s.ownWeakest, -48);
      expect(s.ownCount, 5);
      expect(s.neighborStrongest, -75);
      expect(s.threshold, -60);
    });

    test('kept 6 dB under this pile\'s weakest reading', () {
      // Median -48, weakest -52, neighbour -66: midpoint -57 → -58.
      final s = suggestDirectThreshold([-45, -48, -50, -47, -52], [-66, -70]);
      expect(s.threshold, -58);
      expect(s.threshold, lessThanOrEqualTo(s.ownWeakest! - 6));
      expect(s.threshold, greaterThanOrEqualTo(s.neighborStrongest! + 3));
    });

    test('gap of exactly 9 dB: suggested at both margins', () {
      final s = suggestDirectThreshold([-50], [-59]);
      expect(s.verdict, DirectThresholdVerdict.suggested);
      expect(s.gap, 9);
      expect(s.threshold, -56);
    });

    test('gap under 9 dB: too close, no suggestion', () {
      final s = suggestDirectThreshold([-48, -50, -45], [-58, -62]);
      expect(s.verdict, DirectThresholdVerdict.tooClose);
      expect(s.gap, 8);
      expect(s.threshold, isNull);
      expect(s.ownMedian, -48);
      expect(s.neighborStrongest, -58);
      // A neighbour stronger than this pile: too close too.
      expect(
        suggestDirectThreshold([-60], [-50]).verdict,
        DirectThresholdVerdict.tooClose,
      );
    });

    test('no neighbour: weakest − 10, not below -90', () {
      var s = suggestDirectThreshold([-50, -60, -55], const []);
      expect(s.verdict, DirectThresholdVerdict.noNeighbors);
      expect(s.threshold, -70);
      s = suggestDirectThreshold([-78, -85], const []);
      expect(s.threshold, -90);
      s = suggestDirectThreshold([-80], const []);
      expect(s.threshold, -90);
    });

    test('no reading of this pile: no suggestion', () {
      final s = suggestDirectThreshold(const [], [-70]);
      expect(s.verdict, DirectThresholdVerdict.noOwnSignal);
      expect(s.threshold, isNull);
      expect(s.neighborStrongest, -70);
    });

    test('0 (not read yet) and out-of-range readings are ignored', () {
      final s = suggestDirectThreshold([0, -50, -130], [0, 5]);
      expect(s.ownCount, 1);
      expect(s.neighborStrongest, isNull);
      expect(s.threshold, -60);
    });

    test('even count: median between the middle two, rounded down', () {
      final s = suggestDirectThreshold([-50, -47], [-80]);
      expect(s.ownMedian, -49);
      // Midpoint (-49 − 80) / 2 = -64.5 → -65.
      expect(s.threshold, -65);
    });

    test('never above -20', () {
      expect(suggestDirectThreshold([-5], const []).threshold, -20);
      final s = suggestDirectThreshold([-12], [-24]);
      expect(s.threshold, -20);
      // The clamp would break the neighbour margin: too close.
      expect(
        suggestDirectThreshold([-8], [-21]).verdict,
        DirectThresholdVerdict.tooClose,
      );
    });
  });

  group('calibration samples', () {
    test('own link RSSI only while connected; neighbours by peak', () {
      final samples = DirectCalibrationSamples('aa:bb:cc:00:00:01');
      samples.add(_direct(_own, -44, [(_own, -40), (_near, -70)]));
      samples.add(_direct(_own, 0, [(_near, -66), ('AA:BB:CC:00:00:03', -80)]));
      samples.add(_direct(_near, -50, [(_near, -68)]));
      samples.add(_direct(null, null, const []));
      samples.add(null);
      samples.miss();
      expect(samples.own, [-44]);
      expect(samples.neighbors, {_near: -66, 'AA:BB:CC:00:00:03': -80});
      expect(samples.strongestNeighborMac, _near);
      expect(samples.reads, 6);
      expect(samples.missed, 2);
      // Gap 22: midpoint (-44 − 66) / 2 = -55.
      expect(samples.suggestion.threshold, -55);
    });
  });

  group('calibration flow', () {
    test('samples for the set time, reads only, writes nothing', () async {
      directCalibrationDuration = const Duration(milliseconds: 40);
      directCalibrationInterval = const Duration(milliseconds: 10);
      final fake = _Gateway();
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      // Not confirmed yet: nothing to calibrate against.
      expect(c.calibrationOwnMac, isNull);
      await c.identify();
      expect(c.calibrationOwnMac, _own);
      final writes = fake.sent('set_config').length;
      final reads = fake.sent('get_status').length;
      final last = await c.sampleDirectCalibration(_own).last;
      expect(last.done, isTrue);
      expect(last.elapsed, greaterThanOrEqualTo(directCalibrationDuration));
      expect(last.reads, greaterThanOrEqualTo(2));
      expect(fake.sent('get_status').length - reads, last.reads);
      expect(fake.sent('set_config'), hasLength(writes));
      expect(container.read(commissionProvider).busy, isFalse);
      final s = last.suggestion;
      expect(s.ownMedian, -40);
      expect(s.ownWeakest, -40);
      expect(s.neighborStrongest, -49);
      // Gap 9: midpoint -44.5 → -45, kept 6 dB under -40 → -46.
      expect(s.threshold, -46);
    });

    test('write: set_config, then get_config reads the value back', () async {
      final fake = _Gateway();
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      expect(await c.saveDirectThreshold(-46), isTrue);
      expect(fake.sent('set_config').last, {'auto_connect_min_rssi': -46});
      final (lastOp, _) = fake.commands.lastWhere(
        (e) => e.$1 == 'set_config' || e.$1 == 'get_config',
      );
      expect(lastOp, 'get_config');
      final state = container.read(commissionProvider);
      expect(directMinRssiOf(state.config), -46);
      expect(state.error, isNull);
    });

    test('write not read back: false and an error, never "saved"', () async {
      final fake = _Gateway()..ignoreThreshold = true;
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      expect(await c.saveDirectThreshold(-46), isFalse);
      final state = container.read(commissionProvider);
      expect(directMinRssiOf(state.config), -55);
      expect(state.error, contains('門檻未寫入閘道器'));
    });

    test('write on firmware without direct mode: nothing sent', () async {
      final fake = _Gateway();
      fake.config.remove('direct_autoconnect_supported');
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      expect(await c.saveDirectThreshold(-60), isFalse);
      expect(
        fake
            .sent('set_config')
            .where((p) => p.containsKey('auto_connect_min_rssi')),
        isEmpty,
      );
    });
  });

  group('calibration sheet', () {
    Future<(ProviderContainer, _Gateway)> open(
      WidgetTester tester, {
      void Function(_Gateway)? setUp,
    }) async {
      directCalibrationDuration = const Duration(seconds: 3);
      directCalibrationInterval = const Duration(seconds: 1);
      final fake = _Gateway();
      setUp?.call(fake);
      late ProviderContainer container;
      await tester.runAsync(() async {
        final (k, c) = await _connect(fake);
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
      return (container, fake);
    }

    Future<void> sampleAll(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('suggests, writes and shows it saved', (tester) async {
      final (container, fake) = await open(tester);
      expect(find.byKey(const Key('calibration-progress')), findsOneWidget);
      // While sampling: nothing to write yet.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('calibration-write')))
            .onPressed,
        isNull,
      );
      await sampleAll(tester);
      expect(find.textContaining('取樣完成'), findsOneWidget);
      expect(find.textContaining('中位數 -40 dBm · 最弱 -40 dBm'), findsOneWidget);
      expect(find.textContaining('-49 dBm（$_near）'), findsOneWidget);
      expect(find.textContaining('建議門檻：-46 dBm（目前 -55 dBm）'), findsOneWidget);
      final writes = fake.sent('set_config').length;
      await tester.tap(find.byKey(const Key('calibration-write')));
      await tester.pumpAndSettle();
      expect(fake.sent('set_config'), hasLength(writes + 1));
      expect(fake.sent('set_config').last, {'auto_connect_min_rssi': -46});
      expect(find.textContaining(calibrationSavedText), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(directMinRssiOf(container.read(commissionProvider).config), -46);
    });

    testWidgets('取消 closes the sheet and writes nothing', (tester) async {
      final (container, fake) = await open(tester);
      await sampleAll(tester);
      expect(find.byKey(const Key('calibration-suggestion')), findsOneWidget);
      final writes = fake.sent('set_config').length;
      await tester.tap(find.byKey(const Key('calibration-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calibration-sheet')), findsNothing);
      expect(fake.sent('set_config'), hasLength(writes));
      expect(directMinRssiOf(container.read(commissionProvider).config), -55);
    });

    testWidgets('取消 while sampling stops the reads', (tester) async {
      final (_, fake) = await open(tester);
      final writes = fake.sent('set_config').length;
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('calibration-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calibration-sheet')), findsNothing);
      final reads = fake.sent('get_status').length;
      await sampleAll(tester);
      // At most the read already under way when it closed.
      expect(fake.sent('get_status').length, lessThanOrEqualTo(reads + 1));
      expect(fake.sent('set_config'), hasLength(writes));
    });

    testWidgets('signals too close: yellow warning, nothing to write', (
      tester,
    ) async {
      // The neighbour 5 dB under this pile.
      await open(tester, setUp: (fake) => fake.devices[1]['rssi'] = -45);
      await sampleAll(tester);
      expect(find.byKey(const Key('calibration-too-close')), findsOneWidget);
      expect(find.textContaining(calibrationTooCloseText), findsOneWidget);
      expect(find.byKey(const Key('calibration-suggestion')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('calibration-write')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('advanced settings: 校正門檻 once this pile is confirmed', (
      tester,
    ) async {
      final fake = _Gateway();
      late ProviderContainer container;
      late CommissioningController c;
      await tester.runAsync(() async {
        (container, c) = await _connect(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: DirectSettingsSheet())),
        ),
      );
      OutlinedButton button() => tester.widget<OutlinedButton>(
        find.byKey(const Key('direct-calibrate')),
      );
      expect(button().onPressed, isNull);
      expect(find.text(calibrationNeedsOwnText), findsOneWidget);
      await tester.runAsync(c.identify);
      await tester.pump();
      expect(button().onPressed, isNotNull);
      expect(find.text(calibrationNeedsOwnText), findsNothing);
    });
  });

  group('identify confirmation (firmware 1.7.25)', () {
    const ack = {
      'duration_ms': 6000,
      'ptu_write': 'ok',
      'mac': _own,
      'rssi': -44,
      'device_number': 1,
    };

    test('ptu_confirmed true: PTU 已確認亮燈', () {
      final a = {...ack, 'ptu_confirmed': true, 'ptu_confirm': 'ok'};
      expect(identifyConfirmOf(a), IdentifyConfirm.confirmed);
      expect(identifyNoteText(a), startsWith('PTU 已確認亮燈（PTU $_own'));
      expect(identifyLineText(a), startsWith('PTU 已確認亮燈 · $_own'));
      expect(identifyAckText(a), startsWith('PTU 已確認亮燈；閘道器雙閃 6 秒'));
    });

    test('ptu_confirm timeout: sent, the PTU did not confirm', () {
      final a = {...ack, 'ptu_confirmed': false, 'ptu_confirm': 'timeout'};
      expect(identifyConfirmOf(a), IdentifyConfirm.timeout);
      expect(
        identifyNoteText(a),
        startsWith('閘道器已送出；PTU 未回應確認（PTU 韌體尚未支援），請看樁上燈號'),
      );
      expect(identifyLineText(a), startsWith('已送出 · PTU 未回應確認 · 請看樁上燈號'));
      expect(
        identifyAckText(a),
        startsWith('閘道器已送出；PTU 未回應確認（PTU 韌體尚未支援），請看樁上燈號'),
      );
    });

    test('no ptu_confirm (firmware before 1.7.25): texts as before', () {
      final a = {...ack, 'ptu_confirmed': false};
      expect(identifyConfirmOf(a), IdentifyConfirm.legacy);
      expect(identifyNoteText(a), '已送出，請看樁上燈號（PTU $_own · -44 dBm）');
      expect(identifyLineText(a), '已送出 · 請看樁上燈號 · $_own · -44 dBm');
      expect(identifyAckText(a), contains('PTU 燈效需新版 PTU 韌體'));
      expect(identifyAckText(a), isNot(contains('已確認亮燈')));
    });

    test('a failed PTU write keeps its own text', () {
      const a = {
        'duration_ms': 6000,
        'ptu_write': 'not_connected',
        'ptu_confirmed': false,
        'ptu_confirm': 'timeout',
      };
      expect(identifyNoteText(a), contains('PTU 未收到（not_connected）'));
      expect(identifyLineText(a), '已送出 · 只有閘道器閃燈，PTU 未收到');
    });

    for (final (confirm, text) in [
      ('ok', identifyConfirmedText),
      ('timeout', identifyConfirmTimeoutText),
      (null, identifySentText),
    ]) {
      test('step 7 identify with ptu_confirm $confirm', () async {
        final fake = _Gateway()..identifyPtuConfirm = confirm;
        final (container, c) = await _connect(fake);
        addTearDown(container.dispose);
        await c.identify();
        final state = container.read(commissionProvider);
        expect(state.identifyNote, startsWith(text));
        expect(
          state.message,
          startsWith(confirm == null ? 'PTU 與閘道器正在閃燈' : text),
        );
        // Confirmed or not, the PTU that blinked is the identified one.
        expect(state.identifiedMac, _own);
      });
    }
  });
}
