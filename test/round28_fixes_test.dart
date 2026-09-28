// Round 28 (one-to-one field drill, FW 1.7.38, APP 5409f39):
// 1. P0 — a pile whose own PTU is not powered could not be finished: the
//    gateway never joined the fleet and kept its upload paused, while
//    steps 5/6 said 「✓ 資料上傳中」. Now 〔先完成配置〕 finishes the gateway
//    (join_fleet, upload on, one-to-one, threshold kept, no binding) with
//    a done page that says the PTU connects once powered and the binding
//    is made later; reconnecting that gateway with its PTU connected but
//    unbound offers 〔辨識並綁定〕. A gateway not in service yet is never
//    「資料上傳中」 (upload paused until join_fleet).
// 2. P0 risk — the calibration heard no neighbour (a connected PTU does
//    not advertise) and suggested upper − 10 (-61 dBm, a neighbour's
//    peak): without neighbour data it holds the current threshold.
// 3. No PTU found: causes and what to do, 〔重新搜尋〕〔先完成配置〕
//    〔請後台協助〕; the help report says 直連選台 (DIRECT_PICK).
// 4. (a) the pick's signal 「讀取中」 / advertising RSSI instead of
//    「RSSI —」; (b) the system 返回 asks 「結束目前配置？」; (c) the resume
//    prompt counts only its own gateway's PTUs and names the gateway;
//    (d) the gateway's MAC tail is its Wi-Fi MAC (the back office's), the
//    Bluetooth one in brackets.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_calibration.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/direct_calibration_sheet.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

/// Pile B's PTU when powered (the demo's first PTU).
const _ownPtu = 'AA:BB:CC:00:00:01';

/// Field round 28's gateways: Bluetooth / Wi-Fi MACs.
const _gw1Ble = 'C8:F0:9E:4B:3A:02';
const _gw1Wifi = 'C8F09E4B3A00';
const _gw2Ble = 'A0:DD:6C:A3:70:F2';
const _gw2Wifi = 'A0DD6CA370F0';

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// Pile B (field round 28): a gateway not in service yet (a new identity
/// or after leave_fleet: `fleet_joined` false, its upload paused until
/// join_fleet), its own PTU not powered — every PTU it hears is under
/// -55 dBm (pile A's PTU at -61). Two gateways in the list (field round
/// 28's MACs); connecting one reports that gateway's identity.
class _PileB extends PickGateway {
  _PileB() : super(rssi: const [-61, -72, -80]) {
    config['fleet_joined'] = false;
  }

  /// join_fleet leaves the upload paused (a firmware that does not
  /// confirm the resume).
  bool keepPaused = false;

  @override
  Future<List<GatewayPeer>> scan() async => const [
    GatewayPeer(_gw1Ble, 'GIOS-S80-GW01', -30),
    GatewayPeer(_gw2Ble, 'GIOS-S80-GW02', -50),
  ];

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    config['gateway_uid'] = peer.id == _gw1Ble ? _gw1Wifi : _gw2Wifi;
    return super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final result = await super.command(op, params);
    if ((op == 'join_fleet' || op == 'set_data_upload') && keepPaused) {
      config['upload_paused'] = true;
    }
    return result;
  }

  /// Pile B's own PTU is powered now (and heard strongest).
  void powerOwnPtu() => device(_ownPtu)['rssi'] = -40;
}

GatewayPeer _peer(ProviderContainer container, String id) =>
    container.read(commissionProvider).peers.firstWhere((p) => p.id == id);

ProviderContainer _container(PickGateway fake) => ProviderContainer(
  overrides: [
    linkProvider.overrideWithValue(fake),
    apiProvider.overrideWithValue(fake),
  ],
);

/// Pile B commissioned as a new station (80/2) up to direct step 7,
/// where the gateway finds no PTU near enough.
Future<CommissioningController> _pileBToStep7(
  ProviderContainer container, {
  bool bindOnConfirm = true,
}) async {
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.direct);
  await topo.setDirectBindOnConfirm(bindOnConfirm);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(_peer(container, _gw2Ble));
  await c.passNetworkCheck(skip: true);
  await c.configureWifi(80, 2, 'Office-2G', 'password123');
  await c.online(skip: true);
  return c;
}

/// A connected gateway state for the pure status / check functions.
CommissionState _state({
  bool joined = false,
  bool? paused = true,
  bool deferred = false,
  int step = 2,
}) => CommissionState(
  step: step,
  peer: const GatewayPeer(_gw2Ble, 'GIOS-S80-GW02', -40),
  ptuDeferred: deferred,
  config: {
    'fw_version': '1.7.38',
    'fleet_joined': joined,
    'upload_paused': ?paused,
    'mqtt_target': 'production',
    'mqtt_host': demoProductionMqttHost,
    'mqtt_port': 8883,
    'mqtt_connected': true,
    'wifi_ssid': 'Xiaomi_WU',
  },
  net: const {
    'wifi_state': 'got_ip',
    'ssid': 'Xiaomi_WU',
    'ip': '192.168.0.50',
    'rssi': -50,
  },
  wifiGraceOver: true,
);

const _production = BackendEnvState(loaded: true);

void _phone(WidgetTester tester, {Size size = const Size(360, 640)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// The whole APP, pile B at direct step 7 without a PTU.
Future<ProviderContainer> _pumpPileB(
  WidgetTester tester,
  _PileB fake, {
  bool help = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        localBackendProberProvider.overrideWithValue(_Prober()),
        if (help)
          fieldReporterConfigProvider.overrideWithValue(
            const FieldReporterConfig(allowDemoLink: true),
          ),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  await tester.runAsync(() => _pileBToStep7(container));
  await tester.pump();
  return container;
}

Future<void> _idle(WidgetTester tester, ProviderContainer container) =>
    tester.runAsync(() async {
      for (var i = 0; i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (!container.read(commissionProvider).busy) break;
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepDuration, keepInterval, keepSwitch;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    keepPoll = directPollInterval;
    keepSwitch = directSwitchWait;
    keepDuration = directCalibrationDuration;
    keepInterval = directCalibrationInterval;
    directPollInterval = const Duration(milliseconds: 1);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    directSwitchWait = keepSwitch;
    directCalibrationDuration = keepDuration;
    directCalibrationInterval = keepInterval;
  });

  group('1. P0: 先完成配置 — the gateway without its PTU', () {
    test('pile B: no PTU near enough, the pages never say 「資料上傳中」', () async {
      final fake = _PileB();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _pileBToStep7(container);
      final s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.direct!.state, DirectState.noCandidate);
      expect(directNoPtu(s, directFlow: c.directFlow), isTrue);
      expect(fake.config['fleet_joined'], isFalse);
      expect(fake.uploadPaused, isTrue);
      // The upload is paused until join_fleet: connected, not uploading.
      final check = networkCheck(state: _state(), env: _production);
      expect(check.upload.line, '✓ $uploadHeldText');
      expect(check.upload.line, isNot(contains('資料上傳中')));
      expect(check.uploadOk, isTrue, reason: 'on purpose: the check passes');
      final status = connectionStatus(env: _production, state: _state());
      expect(status.gateway.status, uploadHeldStatus);
      expect(status.gateway.status, isNot(contains('資料上傳中')));
      // In service: unchanged.
      expect(
        connectionStatus(
          env: _production,
          state: _state(joined: true, paused: false),
        ).gateway.status,
        '✓ 資料上傳中',
      );
      expect(uploadHeldUntilJoin(const {'upload_paused': true}), isTrue);
      expect(
        uploadHeldUntilJoin(const {
          'fleet_joined': true,
          'upload_paused': true,
        }),
        isFalse,
      );
    });

    test('先完成配置: join_fleet, upload on, one-to-one, threshold kept, no '
        'binding; the done page says the PTU connects once powered', () async {
      final fake = _PileB();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _pileBToStep7(container);
      final before = fake.ops.length;
      await c.finishWithoutPtu();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.ptuDeferred, isTrue);
      expect(s.verified, isFalse);
      expect(s.message, deferredDoneText);
      final sent = fake.ops.sublist(before);
      expect(sent.map((e) => e.$1), contains('join_fleet'));
      // No binding, no threshold change.
      expect(
        fake.sent('set_config').where((p) => p.containsKey('direct_bind_mac')),
        isEmpty,
      );
      expect(
        fake
            .sent('set_config')
            .where((p) => p.containsKey('auto_connect_min_rssi')),
        isEmpty,
      );
      expect(fake.config['direct_bind_mac'], '');
      expect(fake.config['auto_connect_min_rssi'], -55);
      // In service, uploading, one-to-one.
      expect(fake.config['fleet_joined'], isTrue);
      expect(fake.uploadPaused, isFalse);
      expect(fake.config['max_connections'], 1);
      expect(s.config['fleet_joined'], isTrue);
      expect(s.config['upload_paused'], isFalse);
      // Done page texts and report.
      expect(commissionSummaryText(s), deferredSummaryText);
      expect(s.report, contains('站點 80 / 閘道器 2'));
      expect(s.report, contains(deferredReportLine));
      expect(s.report, contains(deferredDetailText(-55)));
      expect(
        connectionStatus(
          env: _production,
          state: _state(joined: true, paused: false, deferred: true, step: 7),
        ).gateway.status,
        deferredUploadStatus,
      );
      // The field session ends as completed (no STEP_STUCK on the page).
      expect(
        sessionStatusOf(FieldInput(state: s, env: _production)),
        'completed',
      );
      // Saved as a finished run that says so; the gateway is remembered.
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('demo_progress')!) as Map;
      expect(saved['completed'], isTrue);
      expect(saved['ptu_deferred'], isTrue);
      expect(prefs.getString('demo_direct_deferred_ptu'), contains(_gw2Wifi));
      expect(
        lastDoneText(80, 2, ptuDeferred: true),
        allOf(startsWith('上一台已完成：站 80 閘道器 2'), contains('本樁 PTU 尚未連線')),
      );
    });

    test('a gateway that does not confirm the resume: an error, never a done '
        'page', () async {
      final fake = _PileB()..keepPaused = true;
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _pileBToStep7(container);
      await c.finishWithoutPtu();
      final s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.ptuDeferred, isFalse);
      expect(s.error, const GatewayFailure('direct_defer_unconfirmed').message);
      // The resume was tried and read back.
      expect(fake.sent('set_data_upload'), [
        {'enabled': true},
      ]);
      expect(
        rescueCodeOf(
          const GatewayFailure('direct_defer_unconfirmed'),
          rebooted: false,
          safe: true,
          ctlStep: 4,
        ),
        RescueCode.monitorUnconfirmed,
      );
    });

    test('not offered while the gateway has a pick', () async {
      final fake = PickGateway();
      final container = _container(fake);
      addTearDown(container.dispose);
      final topo = container.read(topologyProvider.notifier);
      await topo.ready;
      await topo.setTopology(GatewayTopology.direct);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
      final s = container.read(commissionProvider);
      expect(s.direct!.pickedMac, isNotNull);
      expect(directNoPtu(s, directFlow: c.directFlow), isFalse);
      await c.finishWithoutPtu();
      expect(fake.sent('join_fleet'), isEmpty);
      expect(container.read(commissionProvider).step, 4);
    });

    test('a temporary 「不是這台？」 binding is put back first', () async {
      final fake = _PileB();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _pileBToStep7(container);
      directSwitchWait = const Duration(milliseconds: 20);
      // The chosen PTU never connects (too weak to be picked? bound: the
      // demo connects it) — simulate a switch that did not connect.
      fake.devices.removeWhere((d) => d['mac'] == 'AA:BB:CC:00:00:02');
      await c.switchDirectPick('AA:BB:CC:00:00:02');
      expect(container.read(commissionProvider).tempBoundMac, isNotNull);
      await _untilIdle(container);
      await c.finishWithoutPtu();
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.tempBoundMac, isNull);
      expect(fake.config['direct_bind_mac'], '');
      expect(fake.sent('set_config').last, {'direct_bind_mac': ''});
    });

    test(
      'later: reconnected with the PTU powered — 〔辨識並綁定〕 identifies '
      'and binds it (also with 「確認後綁定」 off); the record is cleared',
      () async {
        final fake = _PileB();
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _pileBToStep7(container, bindOnConfirm: false);
        await c.finishWithoutPtu();
        await c.cancel();
        // Nobody reran the APP; the PTU is powered and the gateway takes it.
        fake.powerOwnPtu();
        await c.connect(_peer(container, _gw2Ble));
        var s = container.read(commissionProvider);
        expect(s.step, 2);
        expect(s.bindLaterMac, _ownPtu);
        expect(s.bindLaterDeferred, isTrue);
        expect(bindLaterTitle(_ownPtu), contains(_ownPtu));
        await c.startBindLater();
        s = container.read(commissionProvider);
        expect(s.step, 4);
        expect(s.direct!.pickedMac, _ownPtu);
        await c.identify();
        await c.confirmDirectPick();
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 6);
        expect(fake.config['direct_bind_mac'], _ownPtu);
        expect(fake.device(_ownPtu)['device_number'], directPtuId);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('demo_direct_deferred_ptu') ?? '',
          isNot(contains(_gw2Wifi)),
        );
        expect(s.bindLaterDeferred, isFalse);
        // Reconnected once more: bound now, no card.
        await c.cancel();
        await c.connect(_peer(container, _gw2Ble));
        s = container.read(commissionProvider);
        expect(s.bindLaterMac, isNull);
        expect(s.bindLaterDeferred, isFalse);
      },
    );

    test(
      'later, the PTU still off: the card says so (recorded here)',
      () async {
        final fake = _PileB();
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = await _pileBToStep7(container);
        await c.finishWithoutPtu();
        await c.cancel();
        await c.connect(_peer(container, _gw2Ble));
        final s = container.read(commissionProvider);
        expect(s.bindLaterMac, isNull);
        expect(s.bindLaterDeferred, isTrue);
      },
    );

    test('done page, still on site: 〔PTU 已上電：辨識並綁定〕 goes back to '
        'step 7', () async {
      final fake = _PileB();
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = await _pileBToStep7(container, bindOnConfirm: false);
      await c.finishWithoutPtu();
      fake.powerOwnPtu();
      await c.bindDeferredNow();
      var s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.ptuDeferred, isFalse);
      expect(s.direct!.pickedMac, _ownPtu);
      await c.identify();
      await c.confirmDirectPick();
      s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(fake.config['direct_bind_mac'], _ownPtu);
    });

    testWidgets('360x640 at 1.1: the help, the confirm dialog, then the done '
        'page', (tester) async {
      _phone(tester);
      final fake = _PileB();
      final container = await _pumpPileB(tester, fake, help: true);
      await tester.pumpAndSettle();
      final help = find.byKey(const Key('direct-no-ptu-help'));
      // The page's list (the first Scrollable: the body).
      await tester.scrollUntilVisible(
        help,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(help, findsOneWidget);
      expect(find.text(directNoPtuTitle), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.byKey(Key('direct-no-ptu-cause-$i')), findsOneWidget);
      }
      // The strongest PTU it heard is named with its peak (not taken).
      expect(
        find.textContaining('訊號太弱（-61 dBm', findRichText: true),
        findsOneWidget,
      );
      for (final key in ['no-ptu-rescan', 'no-ptu-defer', 'no-ptu-help']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(tester.takeException(), isNull);

      // Asks first; 取消 changes nothing.
      await tester.ensureVisible(find.byKey(const Key('no-ptu-defer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('no-ptu-defer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('defer-confirm')), findsOneWidget);
      expect(find.text(deferConfirmText(-55)), findsOneWidget);
      await tester.tap(find.byKey(const Key('defer-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(fake.sent('join_fleet'), isEmpty);

      await tester.tap(find.byKey(const Key('no-ptu-defer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('defer-confirm-ok')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pumpAndSettle();
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.ptuDeferred, isTrue);
      expect(fake.sent('join_fleet'), hasLength(1));
      expect(
        tester.widget<Text>(find.byKey(const Key('done-title'))).data,
        deferredDoneTitle,
      );
      expect(find.text(deferredDoneText), findsOneWidget);
      // Round 29: the done page starts at its summary (title, the PTU
      // line, the note); the details and the action are below it.
      expect(find.text(deferredSummaryText), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(deferredDetailText(-55)),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(deferredDetailText(-55)), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('deferred-bind-now')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('deferred-bind-now')), findsOneWidget);
      expect(find.byKey(const Key('done-calibrate')), findsNothing);
      expect(find.text('重新連線並驗證'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('結束 on a gateway not in service yet warns it will upload '
        'nothing, and names 先完成配置', (tester) async {
      _phone(tester, size: const Size(411, 891));
      final fake = _PileB();
      await _pumpPileB(tester, fake);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-cancel')));
      await tester.pumpAndSettle();
      final text = tester
          .widget<Text>(find.byKey(const Key('end-confirm-text')))
          .data!;
      expect(text, contains(endFlowHeldUploadText));
      expect(text, contains(endFlowDeferHint));
      await tester.tap(find.byKey(const Key('end-confirm-continue')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the bind-later card on the network check', (tester) async {
      _phone(tester, size: const Size(411, 891));
      final fake = _PileB();
      final container = await _pumpPileB(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(() async {
        await c.finishWithoutPtu();
        await c.cancel();
        fake.powerOwnPtu();
        await c.connect(_peer(container, _gw2Ble));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bind-later')), findsOneWidget);
      expect(
        find.textContaining(bindLaterTitle(_ownPtu), findRichText: true),
        findsOneWidget,
      );
      expect(find.text(bindLaterHint), findsOneWidget);
      expect(find.byKey(const Key('bind-later-go')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('2. calibration without neighbour data never loosens', () {
    test('the field numbers: own link -54, advertising -50, no neighbour → '
        'hold -55 (was -61)', () {
      final s = suggestDirectThreshold(
        ownLink: List.filled(12, -54),
        ownAdvertising: -50,
        neighborPeaks: const [],
        current: -55,
      );
      expect(s.verdict, DirectThresholdVerdict.noNeighbors);
      expect(s.upper, -51);
      expect(s.threshold, -55);
      expect(s.ownBelowHold, isFalse);
      expect(
        calibrationNoNeighborText(-55),
        '未偵測到鄰近 PTU（已連線的 PTU 不會廣播），無法確認放寬是否安全，建議維持 -55 dBm。',
      );
    });

    test('never wider than the current threshold (or -55); a tighter current '
        'one is kept too', () {
      for (final own in [-30, -54, -70, -90]) {
        for (final current in [null, -45, -55, -65]) {
          final s = suggestDirectThreshold(
            ownLink: [own],
            neighborPeaks: const [],
            current: current,
          );
          final hold = current ?? defaultDirectRssi;
          expect(s.threshold, hold, reason: 'own $own current $current');
          expect(s.threshold! >= hold, isTrue);
        }
      }
      // Weak own signal under the held threshold: flagged, not loosened.
      final weak = suggestDirectThreshold(
        ownLink: [-70],
        neighborPeaks: const [],
      );
      expect(weak.threshold, -55);
      expect(weak.ownBelowHold, isTrue);
    });

    test('with neighbour data the three rules still decide', () {
      final s = suggestDirectThreshold(
        ownLink: [-40, -41],
        ownAdvertising: -40,
        neighborPeaks: const [-70],
        current: -55,
      );
      expect(s.verdict, DirectThresholdVerdict.suggested);
      // upper = min(-40, -38) = -40, lower = -69 → -55 (midpoint -54.5↓).
      expect(s.threshold, -55);
      final wider = suggestDirectThreshold(
        ownLink: [-60],
        neighborPeaks: const [-80],
        current: -55,
      );
      expect(wider.verdict, DirectThresholdVerdict.suggested);
      // upper = -57, lower = -79 → -68.
      expect(wider.threshold, -68, reason: 'a neighbour measured: may widen');
    });

    test('samples: the gateway\'s own min_rssi is the one held', () {
      final samples = DirectCalibrationSamples(_ownPtu)
        ..add({
          'state': 'connected',
          'min_rssi': -48,
          'bound_mac': '',
          'select_reason': 'ok',
          'ptu_mac': _ownPtu,
          'ptu_rssi': -40,
          'candidates': const [],
          'self_adv_rssi_med': -38,
          'self_adv_age_s': 5,
          'neighbors': const [],
        });
      expect(samples.gatewayThreshold, -48);
      expect(samples.suggestion.threshold, -48);
    });

    testWidgets('the sheet: 「建議維持」, nothing to write', (tester) async {
      directCalibrationDuration = const Duration(seconds: 3);
      directCalibrationInterval = const Duration(seconds: 1);
      final fake = PickGateway(rssi: const [-54, -110, -110])
        ..directNeighborsReport = true
        ..selfAdvOffset = 4;
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = _container(fake);
        final topo = container.read(topologyProvider.notifier);
        await topo.ready;
        await topo.setTopology(GatewayTopology.direct);
        final c = container.read(commissionProvider.notifier);
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.chooseStation(newStation: false);
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
      expect(find.text('未聽到鄰近 PTU'), findsOneWidget);
      expect(find.textContaining('建議門檻：-55 dBm'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('calibration-no-neighbor')))
            .data,
        calibrationNoNeighborText(-55),
      );
      final write = tester.widget<FilledButton>(
        find.byKey(const Key('calibration-write')),
      );
      expect(write.onPressed, isNull);
      expect(find.text(calibrationHoldLabel(-55)), findsOneWidget);
      expect(find.textContaining('-61'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('3. no PTU found: causes and ways on', () {
    test('the causes: power, housing, the threshold (a heard PTU named, '
        'never loosen), the back office, 先完成配置', () {
      final lines = directNoPtuCauses(
        DirectStatus.from({
          'state': 'no_candidate',
          'min_rssi': -55,
          'bound_mac': '',
          'select_reason': 'none',
          'candidates': [
            {'mac': '90:5F:E8:9A:96:00', 'rssi_peak': -61},
          ],
        }),
      );
      expect(lines, hasLength(5));
      expect(lines[0], contains('上電'));
      expect(lines[1], contains('機殼'));
      expect(lines[2], contains('訊號太弱（-61 dBm，門檻 -55）'));
      expect(lines[2], contains('90:5F:E8:9A:96:00'));
      expect(lines[2], contains('請不要為了連上而放寬門檻'));
      expect(lines[3], contains('請後台協助'));
      expect(lines[4], contains(deferFinishLabel));
      // Nothing heard at all / bound to a missing PTU.
      expect(
        directNoPtuCauses(
          DirectStatus.from({'state': 'no_candidate', 'min_rssi': -50}),
        )[2],
        contains('沒有聽到任何 PTU，請確認本樁 PTU 電源'),
      );
      // r31: heard, but bound to another pile (denied) is not 「沒有聽到」.
      final denied = directNoPtuCauses(
        DirectStatus.from({
          'state': 'no_candidate',
          'min_rssi': -55,
          'candidates': [
            {'mac': '90:5F:E8:9A:96:00', 'rssi_peak': -56, 'reason': 'denied'},
          ],
        }),
      )[2];
      expect(denied, contains('附近的 PTU 已綁定給其他充電樁（已自動略過）'));
      expect(denied, isNot(contains('沒有聽到')));
      expect(
        directNoPtuCauses(
          DirectStatus.from({
            'state': 'no_candidate',
            'min_rssi': -55,
            'candidates': [
              {
                'mac': '90:5F:E8:9A:96:00',
                'rssi_peak': -54,
                'rssi_med': -56,
                'reason': 'below_threshold_median',
              },
            ],
          }),
        )[2],
        contains('訊號太弱（-56 dBm，門檻 -55）'),
      );
      expect(
        directNoPtuCauses(
          DirectStatus.from({
            'state': 'bound_missing',
            'bound_mac': '90:5F:E8:9A:96:00',
          }),
        )[2],
        contains('解除綁定'),
      );
    });

    test('the help report says 直連選台 (DIRECT_PICK), not STEP_STUCK', () async {
      final fake = _PileB();
      final container = _container(fake);
      addTearDown(container.dispose);
      await _pileBToStep7(container);
      final s = container.read(commissionProvider);
      expect(
        sessionRescueCode(
          FieldInput(state: s, env: _production, directMode: true),
        ),
        RescueCode.directPick,
      );
      // The help report carries the step 7 line (field: 「（APP 沒有提供錯誤
      // 文字）」).
      final body = buildSessionReport(
        sessionId: '0' * 32,
        seq: 1,
        event: 'help',
        now: DateTime(2026, 9, 27, 13, 47),
        input: FieldInput(state: s, env: _production, directMode: true),
        status: 'help',
        code: RescueCode.directPick,
      );
      expect(body['error_code'], 'DIRECT_PICK');
      // r31: the gateway's direct reason, not fail_code null.
      expect(body['fail_code'], 'direct_no_ptu');
      expect(body['error_message'], directPickMessage(s.direct));
      // With a pick: nothing to report.
      expect(
        sessionRescueCode(
          FieldInput(
            state: s.copy(
              directRaw: {
                'state': 'connected',
                'ptu_mac': _ownPtu,
                'ptu_rssi': -40,
              },
            ),
            env: _production,
            directMode: true,
          ),
        ),
        isNull,
      );
    });
  });

  group('4a. the pick\'s signal right after a connect', () {
    test('link RSSI, else the advertising RSSI, else 「讀取中」', () {
      DirectStatus status(Map<String, dynamic> extra) => DirectStatus.from({
        'state': 'connected',
        'ptu_mac': _ownPtu,
        ...extra,
      })!;
      expect(directPickRssiText(status({'ptu_rssi': -48})), '-48 dBm');
      expect(
        directPickRssiText(
          status({'ptu_rssi': 0}),
          rowRssi: -47,
          ptuText: '-47 dBm',
        ),
        '-47 dBm',
      );
      expect(
        directPickRssiText(status({'ptu_rssi': 0, 'self_adv_rssi_med': -49})),
        directAdvRssiText(-49),
      );
      expect(
        directPickRssiText(
          status({
            'ptu_rssi': 0,
            'candidates': [
              {'mac': 'AA:BB:CC:00:00:09', 'rssi_peak': -30},
              {'mac': _ownPtu.toLowerCase(), 'rssi_peak': -51},
            ],
          }),
        ),
        directAdvRssiText(-51),
      );
      expect(
        directPickRssiText(status({'ptu_rssi': 0}), rowRssi: 0),
        directRssiReadingText,
      );
      expect(directRssiReadingText, isNot(contains('RSSI —')));
    });
  });

  group('4b. the system 返回 asks first', () {
    testWidgets('step 7: 「結束目前配置？」 — 繼續配置 stays, 結束 ends; the '
        'gateway list goes to the start page (09-29)', (tester) async {
      _phone(tester, size: const Size(411, 891));
      final fake = _PileB();
      final container = await _pumpPileB(tester, fake);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('end-confirm-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end-confirm')), findsNothing);
      expect(container.read(commissionProvider).step, 4);

      await tester.runAsync(() => tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-confirm-end')));
      await tester.pump();
      await _idle(tester, container);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 1);

      // The gateway list: nothing running, 返回 does not ask — 09-29: it
      // is 〔結束配置〕, the start page (the list had no way back).
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end-confirm')), findsNothing);
      expect(find.byKey(const Key('leave-confirm')), findsNothing);
      expect(container.read(commissionProvider).step, 0);
      expect(find.byType(GatewayApp), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4c. the resume prompt is per gateway', () {
    test('pile A done, pile B interrupted at step 7: B\'s record has none of '
        'A\'s PTUs and names B', () async {
      final fake = _PileB()..powerOwnPtu();
      final container = _container(fake);
      addTearDown(container.dispose);
      final topo = container.read(topologyProvider.notifier);
      await topo.ready;
      await topo.setTopology(GatewayTopology.direct);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      // Pile A (in service): identified and confirmed (#1).
      fake.config['fleet_joined'] = true;
      await c.connect(_peer(container, _gw1Ble));
      await c.chooseStation(newStation: false);
      await c.identify();
      await c.confirmDirectPick();
      expect(container.read(commissionProvider).assignedOk, {_ownPtu});
      await c.cancel();
      // Pile B: its own gateway, nothing done there.
      fake.devices.first['rssi'] = -61;
      fake.config['direct_bind_mac'] = '';
      await c.connect(_peer(container, _gw2Ble));
      expect(container.read(commissionProvider).assignedOk, isEmpty);
      await c.chooseStation(newStation: false);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('demo_progress')!) as Map;
      expect(saved['peer'], _gw2Ble);
      expect(saved['done_peer'], _gw2Ble);
      expect(saved['done'], isEmpty);
      expect(saved['gateway_mac'], _gw2Wifi);
      expect(saved['gateway_label'], contains('MAC 後 4 碼 70F0（藍牙 70F2）'));

      // The APP is killed and opened again.
      final again = _container(fake);
      addTearDown(again.dispose);
      await again.read(commissionProvider.notifier).restore();
      final s = again.read(commissionProvider);
      expect(s.message, startsWith('上次中斷於第 7 步（選擇 PTU），尚未完成任何 PTU'));
      expect(s.message, isNot(contains('#1')));
      expect(s.savedGateway, saved['gateway_label']);
    });

    test('a record written before the fix (numbers of another gateway) '
        'counts none of them', () async {
      SharedPreferences.setMockInitialValues({
        'demo_progress': jsonEncode({
          'step': 4,
          'shown': 7,
          'completed': false,
          'count': 0,
          'site': 80,
          'gateway': 2,
          'peer': _gw2Ble,
          'peer_name': 'GIOS-S80-GW02',
          'done_peer': _gw1Ble,
          'selected': const [],
          'done': {_ownPtu: 1},
          'inflight': const {},
          'assignments': const [],
        }),
      });
      final container = _container(PickGateway());
      addTearDown(container.dispose);
      await container.read(commissionProvider.notifier).restore();
      final s = container.read(commissionProvider);
      expect(s.message, contains('尚未完成任何 PTU'));
      expect(s.message, isNot(contains('已完成 1 台')));
    });

    testWidgets('the start page names the gateway', (tester) async {
      _phone(tester, size: const Size(411, 891));
      SharedPreferences.setMockInitialValues({
        'demo_progress': jsonEncode({
          'step': 4,
          'shown': 7,
          'completed': false,
          'count': 0,
          'site': 80,
          'gateway': 2,
          'peer': _gw2Ble,
          'peer_name': 'GIOS-S80-GW02',
          'done_peer': _gw2Ble,
          'gateway_label': '站 80 · 閘道器 2 · MAC 後 4 碼 70F0（藍牙 70F2）',
          'selected': const [],
          'done': const {},
          'inflight': const {},
          'assignments': const [],
        }),
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(PickGateway()),
            apiProvider.overrideWithValue(PickGateway()),
            localBackendProberProvider.overrideWithValue(_Prober()),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('saved-gateway'))).data,
        '上次配置的閘道器：站 80 · 閘道器 2 · MAC 後 4 碼 70F0（藍牙 70F2）',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4d. the gateway\'s MAC tail is its Wi-Fi MAC', () {
    test('derived from the Bluetooth MAC (ESP32: Bluetooth = Wi-Fi + 2)', () {
      expect(wifiMacFromBle(_gw1Ble), _gw1Wifi);
      expect(wifiMacFromBle(_gw2Ble), _gw2Wifi);
      expect(wifiMacFromBle('a0dd6ca37001'), 'A0DD6CA370FF', reason: 'wraps');
      expect(wifiMacFromBle('demo-gateway'), isNull);
      expect(gatewayMacText(bleId: _gw2Ble), 'MAC 後 4 碼 70F0（藍牙 70F2）');
      // The gateway's own gateway_uid wins over the derivation.
      expect(
        gatewayMacText(uid: 'A0:DD:6C:A3:70:F0', bleId: _gw2Ble),
        'MAC 後 4 碼 70F0（藍牙 70F2）',
      );
      expect(
        gatewayMacText(uid: _gw2Wifi, bleId: _gw2Ble, withBle: false),
        'MAC 後 4 碼 70F0',
      );
      expect(
        gatewayMacText(uid: _gw2Wifi, bleId: 'ios-uuid'),
        'MAC 後 4 碼 70F0',
      );
      expect(gatewayMacText(bleId: 'ios-uuid'), isNull);
    });

    test('header, help panel and list agree with the back office (70F0)', () {
      expect(
        gatewayHeaderText(
          name: 'GIOS-S80-GW02',
          id: _gw2Ble,
          config: const {
            'site_id': 80,
            'gateway_id': 2,
            'fw_version': '1.7.38',
          },
        ),
        '站 80 · 閘道器 2 · MAC 後 4 碼 70F0 · 1.7.38',
      );
      final lines = fieldHelpLines(
        FieldInput(
          state: CommissionState(
            step: 4,
            peer: const GatewayPeer(_gw2Ble, 'GIOS-S80-GW02', -50),
            config: const {'site_id': 80, 'gateway_id': 2},
          ),
          env: _production,
        ),
      );
      expect(lines.first, '站 80 / 閘道器 2（MAC 後 4 碼 70F0）');
    });
  });
}

Future<void> _untilIdle(ProviderContainer container) async {
  for (var i = 0; i < 400 && container.read(commissionProvider).busy; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
