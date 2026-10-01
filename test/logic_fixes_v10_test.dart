// 1.0.0+10 (logic fixes after the review of 1.0.0+9):
// P1-1 the list 〔辨識〕 (budget, generation, busy retry, old firmware,
//      guidance text, 「已閃燈」, 〔取消操作〕);
// P1-2 〔更換 PTU〕 unbinds only right before step 7 and puts the old
//      binding back on 取消;
// P2-3 the bound PTU counts only with its own MAC; still looking right
//      after a boot is neutral;
// P2-5 the gateway list's live scan resumes after 〔辨識〕 and back from
//      another page;
// P2-8 ⋮「閘道器狀態…」 greyed while busy or connected;
// P2-9 recent data ages (never negative, hours / days, the back office's
//      clock).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/recent_data_api.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

/// The demo's first PTU: this pile's, bound to the gateway.
const _ownPtu = 'AA:BB:CC:00:00:01';
const _otherPtu = 'AA:BB:CC:00:00:02';

/// A gateway to 〔辨識〕 on the list: [holds] keeps a connect pending until
/// completed; [abortOnDisconnect] makes a disconnect end a pending connect
/// (as the BLE link's epoch does); [busyAnswers] identify answers 'busy'
/// first. Field reports are recorded in [reports].
class _Link extends PickGateway implements SessionInfo {
  final holds = <String, Completer<void>>{};
  final _pending = <Completer<void>>[];
  bool abortOnDisconnect = true;
  int disconnects = 0;
  int busyAnswers = 0;

  /// get_status answered with this instead of the demo's (P2-3).
  Map<String, dynamic>? status;
  final reports = <Map<String, dynamic>>[];

  @override
  bool get hasSession => true;

  @override
  String? get origin => 'https://example.invalid';

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    final hold = holds.remove(peer.id);
    if (hold != null) {
      _pending.add(hold);
      try {
        await hold.future;
      } finally {
        _pending.remove(hold);
      }
    }
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    if (!abortOnDisconnect) return;
    for (final hold in [..._pending]) {
      if (!hold.isCompleted) {
        hold.completeError(const GatewayFailure('cancelled'));
      }
    }
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'identify' && busyAnswers > 0) {
      busyAnswers--;
      ops.add((op, Map.of(params)));
      throw const GatewayFailure.gateway('busy');
    }
    final override = status;
    if (op == 'get_status' && override != null) {
      ops.add((op, Map.of(params)));
      return Map<String, dynamic>.from(override);
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == fieldSessionsPath) {
      reports.add(Map<String, dynamic>.from(body ?? const {}));
      return {'ok': true};
    }
    return super.request(method, path, body);
  }
}

/// A gateway in service, one-to-one, bound to [_ownPtu]; [present] false
/// takes that PTU away.
_Link _bound({bool present = false}) {
  final link = _Link();
  link.config['max_connections'] = 1;
  link.config['direct_bind_mac'] = _ownPtu;
  if (!present) link.devices.removeWhere((d) => d['mac'] == _ownPtu);
  return link;
}

Map<String, dynamic> _status(String state, {Object? uptime, String? ptu}) => {
  'uptime_sec': ?uptime,
  'direct': {
    'active': true,
    'state': state,
    'min_rssi': -55,
    'bound_mac': _ownPtu,
    'select_reason': state == 'connected' ? 'ok' : '',
    'ptu_mac': ?ptu,
    'candidates': const [],
  },
};

Future<(ProviderContainer, CommissioningController)> _list(_Link fake) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      fieldReporterConfigProvider.overrideWithValue(
        const FieldReporterConfig(allowDemoLink: true),
      ),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.direct);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  return (container, c);
}

Future<(ProviderContainer, CommissioningController)> _connected(
  _Link fake,
) async {
  final (container, c) = await _list(fake);
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

Future<void> _settle([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

const _peerA = GatewayPeer('gw-a', 'GIOS-S1-GW02', -80);

/// A live scanner whose every scan is its own stream ([scans]);
/// [stopScan] ends them all (as another page's scan does).
class _ScanLink extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final scan = StreamController<List<GatewayPeer>>();
    scans.add(scan);
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    for (final scan in scans) {
      if (!scan.isClosed) unawaited(scan.close());
    }
  }

  void hear(List<GatewayPeer> peers) => scans.last.add(peers);
}

Future<_ScanLink> _pumpList(
  WidgetTester tester, {
  Future<bool> Function(GatewayPeer)? onIdentify,
}) async {
  SharedPreferences.setMockInitialValues({});
  final link = _ScanLink();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [linkProvider.overrideWithValue(link)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GatewayDiscovery(
              enabled: true,
              onConnect: (_) async {},
              onIdentify: onIdentify ?? (_) async => true,
              // 1.0.0+22: the bulb is on the selected card once its link
              // is up (the card's tap stops the scan and keeps the link).
              onHold: (_) async => true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  link.hear(const [GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -40)]);
  await tester.pump();
  return link;
}

/// Lets the list's real async stop / start run.
Future<void> _run(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P1-1 list 〔辨識〕', () {
    tearDown(() => identifyPeerTimeout = reconnectBudget);

    test('the limit is at least 70 s: a slow connect still blinks, the '
        'list text comes back', () async {
      expect(identifyPeerTimeout.inSeconds, greaterThanOrEqualTo(70));
      final fake = _Link();
      final (container, c) = await _list(fake);
      addTearDown(container.dispose);
      CommissionState read() => container.read(commissionProvider);
      final listText = read().message;
      expect(read().step, 1);
      final config = read().config;
      final hold = fake.holds[_peerA.id] = Completer<void>();
      final done = c.identifyPeer(_peerA);
      await _settle();
      expect(read().busy, isTrue);
      expect(read().message, identifyPeerLabel);
      expect(read().seconds, greaterThanOrEqualTo(70));
      hold.complete();
      expect(await done, isTrue);
      expect(fake.identifyRequests, [
        {'target': 'both', 'duration_ms': 4000},
      ]);
      final s = read();
      expect(s.error, isNull);
      expect(s.busy, isFalse);
      expect(s.step, 1);
      expect(s.peer, isNull);
      expect(s.message, listText, reason: 'the list guidance is back');
      expect(s.config, config, reason: 'nothing absorbed');
    });

    test('a gateway answering busy is asked again; old firmware gets the '
        'bare op', () async {
      final fake = _Link()..busyAnswers = 1;
      fake.config.remove('identify_ptu_supported');
      final (container, c) = await _list(fake);
      addTearDown(container.dispose);
      // Pre-PTU firmware takes only its fixed six seconds (the APP default
      // 4 is refused; see identify_seconds_test), so pick 6 here.
      await container.read(topologyProvider.notifier).setIdentifySeconds(6);
      expect(await c.identifyPeer(_peerA), isTrue);
      expect(fake.sent('identify'), [<String, dynamic>{}, <String, dynamic>{}]);
      expect(container.read(commissionProvider).error, isNull);
    });

    test('timed out, then another gateway chosen: the late identify never '
        'disconnects it', () async {
      identifyPeerTimeout = const Duration(seconds: 1);
      final fake = _Link()..abortOnDisconnect = false;
      final (container, c) = await _list(fake);
      addTearDown(container.dispose);
      CommissionState read() => container.read(commissionProvider);
      final hold = fake.holds[_peerA.id] = Completer<void>();
      expect(await c.identifyPeer(_peerA), isFalse);
      expect(read().busy, isFalse);
      // The row B (the demo gateway) is chosen now.
      await c.connect(read().peers.single);
      expect(read().step, 2);
      expect(read().peer?.id, 'demo-gateway');
      final before = fake.disconnects;
      // A's connect finally returns in the background.
      hold.complete();
      await _settle();
      expect(fake.disconnects, before, reason: 'B stays connected');
      expect(read().peer?.id, 'demo-gateway');
      expect(read().step, 2);
    });

    test('〔取消操作〕 stops only the blink: the list stays, no 已取消, no '
        'session end', () async {
      final fake = _Link();
      final (container, c) = await _list(fake);
      addTearDown(container.dispose);
      CommissionState read() => container.read(commissionProvider);
      final listText = read().message;
      fake.holds[_peerA.id] = Completer<void>();
      final done = c.identifyPeer(_peerA);
      await _settle();
      expect(read().busy, isTrue);
      await c.cancel();
      expect(await done, isFalse, reason: 'no 「已閃燈」');
      final s = read();
      expect(s.busy, isFalse);
      expect(s.step, 1);
      expect(s.error, isNull);
      expect(s.message, listText);
      expect(s.message, isNot(contains('已取消')));
      expect(s.peers, isNotEmpty);
      expect(fake.identifyRequests, isEmpty);
      await _settle();
      expect(fake.reports.where((r) => r['event'] == 'end'), isEmpty);
    });
  });

  group('P1-2 〔更換 PTU〕', () {
    test(
      'network not ready: no unbind is sent and the red box says why',
      () async {
        final fake = _bound()..mqttConnected = false;
        final (container, c) = await _connected(fake);
        addTearDown(container.dispose);
        CommissionState read() => container.read(commissionProvider);
        expect(read().ptuMissingMac, _ownPtu);
        await c.replaceBoundPtu();
        final s = read();
        expect(
          fake
              .sent('set_config')
              .where((p) => p.containsKey('direct_bind_mac')),
          isEmpty,
        );
        expect(fake.config['direct_bind_mac'], _ownPtu);
        expect(s.step, 2);
        expect(s.error, reuseBlockedText);
        expect(s.ptuMissingMac, _ownPtu, reason: 'the card stays');
        expect(s.tempBoundMac, isNull);
      },
    );

    test('step 7 取消 puts the old binding back', () async {
      final fake = _bound();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      CommissionState read() => container.read(commissionProvider);
      await c.replaceBoundPtu();
      var s = read();
      expect(s.error, isNull);
      expect(s.step, 4);
      expect(fake.config['direct_bind_mac'], '');
      expect(s.tempBoundMac, replacedBindMarker);
      expect(s.tempRestoreMac, _ownPtu);
      expect(s.strayBindMac, isNull);
      expect(endFlowRestoresBind(s), isTrue);
      await c.cancel();
      s = read();
      expect(fake.config['direct_bind_mac'], _ownPtu);
      expect(fake.sent('set_config').last, {'direct_bind_mac': _ownPtu});
      expect(s.error, isNull);
      expect(s.tempBoundMac, isNull);
    });
  });

  group('P2-3 bound PTU presence', () {
    DirectStatus report(String state, {String? ptu}) =>
        DirectStatus.from(_status(state, ptu: ptu)['direct'])!;

    test('boundPtuPresence', () {
      expect(
        boundPtuPresence(report('connected', ptu: _ownPtu), _ownPtu),
        BoundPtuPresence.present,
      );
      expect(
        boundPtuPresence(report('connected', ptu: _otherPtu), _ownPtu),
        BoundPtuPresence.other,
      );
      expect(
        boundPtuPresence(report('scanning'), _ownPtu, uptimeSec: 60),
        BoundPtuPresence.searching,
      );
      expect(
        boundPtuPresence(report('connecting'), _ownPtu, uptimeSec: 89),
        BoundPtuPresence.searching,
      );
      expect(
        boundPtuPresence(report('scanning'), _ownPtu, uptimeSec: 200),
        BoundPtuPresence.missing,
      );
      expect(
        boundPtuPresence(
          report('scanning'),
          _ownPtu,
          uptimeSec: 200,
          changed: true,
        ),
        BoundPtuPresence.searching,
      );
      // No uptime: connecting only.
      expect(
        boundPtuPresence(report('connecting'), _ownPtu),
        BoundPtuPresence.searching,
      );
      expect(
        boundPtuPresence(report('scanning'), _ownPtu),
        BoundPtuPresence.missing,
      );
      expect(
        boundPtuPresence(report('bound_missing'), _ownPtu, uptimeSec: 10),
        BoundPtuPresence.missing,
      );
    });

    test('connected to another MAC: no green card, 「不是綁定的 PTU」', () async {
      final fake = _bound(present: true)
        ..status = _status('connected', uptime: 3600, ptu: _otherPtu);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      CommissionState read() => container.read(commissionProvider);
      var s = read();
      expect(s.ptuMissingMac, _ownPtu);
      expect(s.ptuMissingBack, isFalse);
      expect(s.ptuMissingOther, _otherPtu);
      var view = ptuCardView(s)!;
      expect(view.tone, PtuCardTone.missing);
      expect(view.title, contains('不是綁定的 PTU'));
      expect(view.replace, isTrue);
      // Re-check, still the other PTU: not green.
      await c.recheckBoundPtu();
      s = read();
      expect(s.ptuMissingBack, isFalse);
      expect(ptuCardView(s)!.tone, PtuCardTone.missing);
      // The bound PTU itself: green.
      fake.status = _status('connected', uptime: 3600, ptu: _ownPtu);
      await c.recheckBoundPtu();
      s = read();
      expect(s.ptuMissingBack, isTrue);
      view = ptuCardView(s)!;
      expect(view.tone, PtuCardTone.ok);
      expect(view.recheck, isEmpty);
    });

    test('60 s after a boot, scanning: neutral 「正在尋找」 with 〔重新檢查〕, '
        'red once past 90 s', () async {
      final fake = _bound(present: true)
        ..status = _status('scanning', uptime: 60);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      CommissionState read() => container.read(commissionProvider);
      var s = read();
      expect(s.ptuMissingMac, _ownPtu);
      expect(s.ptuMissingSearching, isTrue);
      final view = ptuCardView(s)!;
      expect(view.tone, PtuCardTone.searching);
      expect(view.title, ptuSearchingTitle);
      expect(view.replace, isFalse);
      expect(view.recheck, ptuSearchingRecheckLabel);
      await _settle();
      bool reported() => fake.reports.any(
        (r) => r['error_message'] == ptuMissingReportText(_ownPtu),
      );
      expect(reported(), isFalse, reason: 'not missing yet');
      // Still scanning 200 s after the boot: red and reported.
      fake.status = _status('scanning', uptime: 200);
      await c.recheckBoundPtu();
      s = read();
      expect(s.ptuMissingSearching, isFalse);
      expect(ptuCardView(s)!.tone, PtuCardTone.missing);
      await _settle();
      expect(reported(), isTrue);
    });
  });

  group('P2-5 list scan paused while the link is kept / 「已閃燈」 only when '
      'sent', () {
    testWidgets('after the card\'s tap the scan stays stopped (the link is '
        'kept); its bulb: 「已閃燈」 shown', (tester) async {
      final link = await _pumpList(tester);
      expect(link.scans, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('AA:BB:CC:DD:3A:02')));
      await _run(tester);
      expect(link.scans, hasLength(1), reason: 'no scan while held');
      expect(link.scans.last.isClosed, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('identify-AA:BB:CC:DD:3A:02')),
      );
      await _run(tester);
      expect(link.scans, hasLength(1), reason: 'still held: no scan');
      // 1.0.0+11: on its row and in a SnackBar.
      expect(
        find.byKey(const ValueKey('gateway-presence-AA:BB:CC:DD:3A:02')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('gateway-presence-AA:BB:CC:DD:3A:02')),
          matching: find.text(identifiedHint),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('gateway-identified-snack')), findsOneWidget);
      // The rows heard before stay.
      expect(find.byKey(const ValueKey('AA:BB:CC:DD:3A:02')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an identify not sent (cancelled / failed): no 「已閃燈」', (
      tester,
    ) async {
      final link = await _pumpList(tester, onIdentify: (_) async => false);
      await tester.tap(find.byKey(const ValueKey('AA:BB:CC:DD:3A:02')));
      await _run(tester);
      await tester.tap(
        find.byKey(const ValueKey('identify-AA:BB:CC:DD:3A:02')),
      );
      await _run(tester);
      expect(find.textContaining(identifiedHint), findsNothing);
      expect(link.scans, hasLength(1), reason: 'the link is still kept');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('back from another page that stopped the scan: it starts '
        'again', (tester) async {
      final link = await _pumpList(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('閘道器狀態')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // That page's own scan ends the list's.
      await link.stopScan();
      await _run(tester);
      expect(link.scans, hasLength(1), reason: 'not while covered');
      navigator.pop();
      // The list scans again (its progress bar never settles).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await _run(tester);
      expect(link.scans, hasLength(2));
      expect(link.scans.last.isClosed, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stopped by the installer: not started again', (tester) async {
      final link = await _pumpList(tester);
      await tester.tap(find.text('停止搜尋'));
      await _run(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      await _run(tester);
      expect(link.scans, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('P2-8 ⋮「閘道器狀態…」', () {
    test('greyed while busy or once a gateway is connected', () {
      expect(gatewayStatusMenuEnabled(const CommissionState()), isTrue);
      expect(gatewayStatusMenuEnabled(const CommissionState(step: 1)), isTrue);
      expect(
        gatewayStatusMenuEnabled(const CommissionState(step: 1, busy: true)),
        isFalse,
      );
      expect(gatewayStatusMenuEnabled(const CommissionState(step: 2)), isFalse);
      expect(gatewayStatusMenuEnabled(const CommissionState(step: 7)), isFalse);
      expect(
        gatewayStatusMenuText(const CommissionState(step: 1, busy: true)),
        contains(gatewayStatusBusyText),
      );
      expect(gatewayStatusMenuText(const CommissionState()), '查看上傳資料…');
    });
  });

  group('P2-9 recent data ages', () {
    test('never negative; hours and days', () {
      expect(recentAgeText(const Duration(seconds: -5)), '0 秒');
      expect(recentAgeText(const Duration(seconds: 59)), '59 秒');
      expect(recentAgeText(const Duration(minutes: 59)), '59 分鐘');
      expect(recentAgeText(const Duration(minutes: 90)), '1 小時');
      expect(recentAgeText(const Duration(hours: 2)), '2 小時');
      expect(recentAgeText(const Duration(days: 3, hours: 5)), '3 天');
    });

    RecentData data(DateTime latest, {Duration? offset}) => RecentData(
      siteId: 56,
      gatewayId: 1,
      count: 1,
      items: [RecentItem(ts: latest)],
      serverOffset: offset,
    );

    test('a row newer than the phone (its clock behind): fresh', () {
      final now = DateTime(2026, 9, 29, 12);
      final banner = recentBanner(
        data(now.add(const Duration(seconds: 5))),
        now,
      );
      expect(banner.kind, RecentBannerKind.ok);
    });

    test('the phone 30 s fast: the back office Date keeps fresh data '
        'green', () {
      final server = DateTime(2026, 9, 29, 12);
      final phone = server.add(const Duration(seconds: 30));
      final latest = server.subtract(const Duration(seconds: 5));
      // Without the Date: yellow (35 s by the phone's clock).
      final plain = data(latest);
      expect(
        recentBanner(plain, recentServerNow(plain, phone)).kind,
        RecentBannerKind.stale,
      );
      final dated = data(latest, offset: const Duration(seconds: -30));
      expect(recentServerNow(dated, phone), server);
      expect(
        recentBanner(dated, recentServerNow(dated, phone)).kind,
        RecentBannerKind.ok,
      );
    });

    test('fetchRecentData carries the API clock offset', () async {
      final api = _DatedApi(const Duration(seconds: -30));
      final got = await fetchRecentData(api, site: 56, gateway: 1);
      expect(got.serverOffset, const Duration(seconds: -30));
      final none = await fetchRecentData(_DatedApi(null), site: 56, gateway: 1);
      expect(none.serverOffset, isNull);
    });
  });
}

class _DatedApi implements GatewayApi, ServerClock {
  _DatedApi(this.serverClockOffset);

  @override
  final Duration? serverClockOffset;

  @override
  Future<void> login(String base, String password) async {}

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async => {'site_id': 56, 'gateway_id': 1, 'count': 0, 'items': const []};
}
