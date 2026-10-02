// Round 17b (after field round 17, APP 7cf7913, firmware 1.7.24):
// 1. 「結束並重新選擇閘道器」 after step 3 asks first (「結束目前配置？已完成
//    的 N 台會保留在閘道器」 [繼續配置] [結束]); the direct step 7 bottom bar
//    keeps one layout while the gateway switches PTU and after (buttons
//    disabled, never removed or replaced) — field: a late tap on
//    「改選其他 PTU」 landed on 「結束並重新選擇閘道器」 and ended the flow.
// 2. The gateway kept its PTU with `candidates: []` (after a binding was
//    undone): 「不是這台？」 and 「重新搜尋」 stay, and make the gateway run a
//    new collection window (disconnect_device) before listing candidates;
//    「選台依據」 follows `select_reason`.
// 3. Right after a connect (ptu_rssi 0 / null, < 2 s) 「辨識此樁」 reads
//    「連線建立中…」 and is disabled; an identify whose PTU write says
//    not_connected is sent once more after 1.5 s; RSSI 0 shows 「—」.
// 4. The session token (not the password) survives an APP kill: 「重新連線
//    並繼續」 uses it before asking for the password.
// 5. An idle phone↔gateway drop found by 「辨識此樁」 reconnects by itself
//    (no red box waiting for a tap); the identification stays unless the
//    gateway now connects another PTU.
import 'dart:convert';
import 'dart:io';

import 'support/direct_pick_actions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/dashboard_api.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp;
import 'round15_direct_flow_test.dart' show PickGateway;

/// Listed first by the demo, weaker than [_pick].
const _first = 'AA:BB:CC:00:00:01';

/// The gateway's own pick (strongest, clearly: `ok`).
const _pick = 'AA:BB:CC:00:00:02';

/// Weakest.
const _third = 'AA:BB:CC:00:00:03';

/// Field round 17 E(3c): after 取消 the gateway kept its PTU (re-evaluate
/// "keep") and reported `candidates: []` until a new collection window;
/// `disconnect_device` makes it run one.
class _KeptGateway extends PickGateway {
  bool hideCandidates = true;
  final disconnects = <String>[];

  @override
  Map<String, dynamic>? directStatus() {
    final status = super.directStatus();
    if (status != null && hideCandidates) status['candidates'] = const [];
    return status;
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    if (op == 'disconnect_device') {
      disconnects.add(params['mac'].toString());
      hideCandidates = false;
    }
    return super.command(op, params);
  }
}

/// ptu_rssi reads 0 (not read yet right after a connect) for [zeroReads]
/// get_status answers with a connected PTU.
class _FreshLink extends PickGateway {
  int zeroReads = 1 << 20;

  @override
  Map<String, dynamic>? directStatus() {
    final status = super.directStatus();
    if (status != null && status['ptu_mac'] != null && zeroReads > 0) {
      zeroReads--;
      status['ptu_rssi'] = 0;
    }
    return status;
  }
}

/// identify's PTU write says not_connected [notConnected] times (the
/// gateway's GATT link to a PTU it just connected is not ready yet).
class _LateGatt extends PickGateway {
  int notConnected = 1;
  final identifyAt = <DateTime>[];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    if (op == 'identify') {
      identifyAt.add(DateTime.now());
      if (notConnected > 0) {
        notConnected--;
        ops.add((op, Map.of(params)));
        return Future.value({
          'duration_ms': 6000,
          'ptu_write': 'not_connected',
          'ptu_confirmed': false,
        });
      }
    }
    return super.command(op, params);
  }
}

/// The phone↔gateway link drops (0x08 while idle) and the next command —
/// here 「辨識此樁」 — fails; a reconnect brings it back. [onDrop] changes
/// the gateway meanwhile (e.g. it connects another PTU).
class _IdleDrop extends PickGateway {
  bool dropOnIdentify = false;
  bool down = false;
  void Function()? onDrop;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    down = false;
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    if (down) return Future.error(const GatewayFailure('disconnected'));
    if (op == 'identify' && dropOnIdentify) {
      dropOnIdentify = false;
      down = true;
      onDrop?.call();
      return Future.error(const GatewayFailure('disconnected'));
    }
    return super.command(op, params);
  }
}

/// A demo backend with a saved session token (round 17 #4).
class _TokenGateway extends DroppingLink implements SessionStore {
  bool hasSession = true;
  final restored = <String>[];

  @override
  Future<bool> restoreSession(String base) async {
    restored.add(base);
    return hasSession;
  }
}

/// A restored token the backend refuses once (401), then a login.
class _RefusedToken extends DemoSystem implements SessionStore {
  int refuse = 1;
  final logins = <(String, String)>[];

  @override
  Future<bool> restoreSession(String base) async => true;

  @override
  Future<void> login(String base, String password) async {
    logins.add((base, password));
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (refuse > 0) {
      refuse--;
      throw const GatewayFailure('authentication');
    }
    return super.request(method, path, body);
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

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

bool _enabled(WidgetTester tester, String key) =>
    directActionEnabled(tester, key);

String _label(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepSwitch, keepSettle, keepRetry, keepGap;
  late List<Duration> keepGaps;
  setUp(() {
    keepPoll = directPollInterval;
    keepSwitch = directSwitchWait;
    keepSettle = directSettleWindow;
    keepRetry = identifyRetryDelay;
    keepGap = connectRetryGap;
    keepGaps = step7RetryGaps;
    directPollInterval = const Duration(milliseconds: 1);
    directSwitchWait = const Duration(milliseconds: 200);
    directSettleWindow = const Duration(milliseconds: 1);
    identifyRetryDelay = const Duration(milliseconds: 1);
    connectRetryGap = const Duration(milliseconds: 1);
    step7RetryGaps = const [
      Duration(milliseconds: 1),
      Duration(milliseconds: 2),
      Duration(milliseconds: 3),
    ];
  });
  tearDown(() {
    directPollInterval = keepPoll;
    directSwitchWait = keepSwitch;
    directSettleWindow = keepSettle;
    identifyRetryDelay = keepRetry;
    connectRetryGap = keepGap;
    step7RetryGaps = keepGaps;
  });

  group('1. no layout jump, 結束 asks first', () {
    test('confirmation text names the PTUs kept', () {
      expect(endFlowConfirmTitle, '結束目前配置？');
      expect(endFlowConfirmText(3), '已完成的 3 台會保留在閘道器。');
      expect(endFlowConfirmText(0), isNot(contains('0 台')));
    });

    testWidgets('bottom bar: same buttons in the same places while the '
        'gateway switches and after; disabled, not removed', (tester) async {
      _phone(tester);
      final fake = PickGateway();
      late ProviderContainer container;
      late CommissioningController c;
      await tester.runAsync(() async {
        (container, c) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_screen(container));
      Rect at(String key) => tester.getRect(find.byKey(Key(key)));
      final bar = at('direct-pick-actions');
      final identify = at('direct-identify');
      final more = at('direct-more');
      final confirm = at('direct-confirm');
      final stop = at('direct-stop');
      expect(_enabled(tester, 'direct-identify'), isTrue);
      expect(_enabled(tester, 'direct-more'), isTrue);
      expect(_enabled(tester, 'direct-stop'), isFalse, reason: 'idle');
      await openDirectActions(tester);
      expect(_enabled(tester, 'direct-not-this'), isTrue);
      expect(_enabled(tester, 'direct-rescan-bottom'), isTrue);
      await dismissDirectActions(tester);

      // 「不是這台？」 → the gateway reports no pick while it switches.
      directSwitchWait = const Duration(seconds: 5);
      fake.directGapReads = 1 << 20;
      late Future<void> switching;
      await tester.runAsync(() async {
        switching = c.switchDirectPick(_first);
        await _until(
          () => container.read(commissionProvider).direct?.pickedMac == null,
        );
      });
      await tester.pump();
      var s = container.read(commissionProvider);
      expect(s.busy, isTrue);
      expect(s.direct!.pickedMac, isNull);
      expect(at('direct-pick-actions'), bar);
      expect(at('direct-identify').topLeft, identify.topLeft);
      expect(at('direct-more'), more);
      expect(at('direct-wait'), confirm);
      expect(at('direct-stop'), stop);
      for (final key in ['direct-identify', 'direct-more', 'direct-wait']) {
        expect(_enabled(tester, key), isFalse, reason: '$key while busy');
      }
      expect(_enabled(tester, 'direct-stop'), isTrue);
      expect(_label(tester, 'direct-wait'), directWaitingLabel);

      // The switch lands: the same places, enabled again.
      fake.directGapReads = 0;
      await tester.runAsync(() => switching);
      await tester.pump();
      s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.direct!.pickedMac, _first);
      expect(at('direct-pick-actions'), bar);
      expect(at('direct-identify'), identify);
      expect(at('direct-more'), more);
      expect(at('direct-confirm'), confirm);
      expect(at('direct-stop'), stop);
      expect(_enabled(tester, 'direct-identify'), isTrue);
      expect(_enabled(tester, 'direct-more'), isTrue);
      expect(_enabled(tester, 'direct-stop'), isFalse);
      await openDirectActions(tester);
      expect(_enabled(tester, 'direct-not-this'), isTrue);
      expect(_enabled(tester, 'direct-rescan-bottom'), isTrue);
      await dismissDirectActions(tester);
    });

    testWidgets('page: the end menu is disabled while switching; '
        'after step 3 it asks, 繼續配置 keeps the flow, 結束 ends it', (
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
      });
      await tester.pump();
      expect(container.read(commissionProvider).step, 4);
      // The card has no buttons of its own for these (bottom bar only).
      expect(find.byKey(const Key('direct-rescan')), findsNothing);
      final cancel = find.byKey(const Key('page-cancel'));
      await openDirectActions(tester);
      expect(cancel, findsOneWidget);
      expect(_enabled(tester, 'page-cancel'), isTrue);
      await dismissDirectActions(tester);

      // Switching: the menu entry stays fixed and disabled.
      directSwitchWait = const Duration(seconds: 5);
      fake.directGapReads = 1 << 20;
      late Future<void> switching;
      await tester.runAsync(() async {
        switching = c.switchDirectPick(_first);
        await _until(
          () => container.read(commissionProvider).direct?.pickedMac == null,
        );
      });
      await tester.pump();
      expect(container.read(commissionProvider).busy, isTrue);
      expect(cancel, findsNothing);
      expect(_enabled(tester, 'direct-more'), isFalse);
      expect(_enabled(tester, 'direct-stop'), isTrue);
      fake.directGapReads = 0;
      await tester.runAsync(() => switching);
      await tester.pump();

      // After step 3: a confirmation first; 繼續配置 changes nothing.
      final s = container.read(commissionProvider);
      expect(displayStep(s, container.read(backendEnvProvider)), 6);
      await tapDirectAction(tester, 'page-cancel');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end-confirm')), findsOneWidget);
      expect(find.text(endFlowConfirmTitle), findsOneWidget);
      expect(
        find.text(endFlowConfirmText(0, restoresBind: true)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('end-confirm-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end-confirm')), findsNothing);
      expect(container.read(commissionProvider).step, 4);
      expect(container.read(commissionProvider).tempBoundMac, _first);
      expect(fake.config['direct_bind_mac'], _first);

      // 結束: the flow ends (the temporary binding is put back).
      await tapDirectAction(tester, 'page-cancel');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-confirm-end')));
      await tester.runAsync(
        () => _until(() => container.read(commissionProvider).step == 1),
      );
      await tester.pump();
      expect(container.read(commissionProvider).step, 1);
      expect(fake.config['direct_bind_mac'], '');
    });

    testWidgets('before step 4 結束並重新選擇閘道器 does not ask', (tester) async {
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
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
      });
      await tester.pump();
      final s = container.read(commissionProvider);
      expect(s.step, 1);
      expect(displayStep(s, container.read(backendEnvProvider)), lessThan(3));
      // 09-29: on the gateway list the button is 〔結束配置〕 (its own short
      // question, then the start page) — never 「結束目前配置？」.
      expect(find.text(leaveListLabel), findsOneWidget);
      await tester.tap(find.byKey(const Key('page-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end-confirm')), findsNothing);
      expect(find.byKey(const Key('leave-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('leave-confirm-end')));
      await tester.runAsync(
        () => _until(() => container.read(commissionProvider).step == 0),
      );
      await tester.pump();
      expect(container.read(commissionProvider).step, 0);
      expect(container.read(commissionProvider).message, isEmpty);
    });
  });

  group('2. no candidates reported: no dead end', () {
    test('選台依據 follows select_reason (never a fixed 「明顯最強」)', () {
      String? reason(String r, {String bound = ''}) => DirectStatus.from({
        'state': 'connected',
        'ptu_mac': _pick,
        'bound_mac': bound,
        'select_reason': r,
      })!.reasonText;
      expect(reason('ok'), '訊號最強且明確');
      expect(reason('ambiguous'), contains('附近訊號相近'));
      expect(reason('resume'), '延續既有連線');
      expect(reason('none'), '找不到夠近的 PTU');
      expect(reason('ok', bound: _pick), contains('已綁定'));
      expect(reason('bound'), contains('已綁定'));
      expect(reason(''), isNull);
      for (final r in ['ok', 'ambiguous', 'resume', 'none', 'bound']) {
        expect(reason(r), isNot(contains('明顯最強')));
      }
    });

    testWidgets('kept PTU with candidates []: 不是這台？ and 重新搜尋 stay; '
        '不是這台？ runs a new window, then lists the candidates', (tester) async {
      _phone(tester);
      final fake = _KeptGateway();
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.direct!.pickedMac, _pick);
      expect(s.direct!.candidates, isEmpty);
      await tester.pumpWidget(_screen(container));
      expect(find.text('選台依據：訊號最強且明確'), findsOneWidget);
      await openDirectActions(tester);
      expect(find.byKey(const Key('direct-not-this')), findsOneWidget);
      expect(_enabled(tester, 'direct-not-this'), isTrue);
      expect(_enabled(tester, 'direct-rescan-bottom'), isTrue);

      await tapDirectAction(tester, 'direct-not-this');
      await tester.pump();
      expect(find.byKey(const Key('direct-candidates-sheet')), findsOneWidget);
      await _idle(tester, container);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(fake.disconnects, [_pick]);
      s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.direct!.candidates, hasLength(3));
      for (final mac in [_first, _pick, _third]) {
        expect(
          find.byKey(ValueKey('direct-candidate-$mac')),
          findsOneWidget,
          reason: mac,
        );
      }
      // The gateway picked again by its own rules (same PTU here).
      expect(s.direct!.pickedMac, _pick);
      expect(find.text('目前選中'), findsOneWidget);

      // And a candidate can be chosen from there.
      await tester.tap(find.byKey(const ValueKey('direct-candidate-$_first')));
      await tester.pump();
      await _idle(tester, container);
      expect(container.read(commissionProvider).direct!.pickedMac, _first);
    });

    test('重新搜尋 with a pick: a new window (disconnect_device), the '
        'gateway picks again; without a pick: the usual search', () async {
      final fake = _KeptGateway();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      fake.hideCandidates = false;
      await c.rescanDirect();
      var s = container.read(commissionProvider);
      expect(fake.disconnects, [_pick]);
      expect(s.direct!.pickedMac, _pick);
      expect(s.direct!.candidates, hasLength(3));
      expect(s.selected, {_pick});
      expect(s.error, isNull);
      expect(s.message, directPickMessage(s.direct));

      // No pick (nothing near enough): plain search, nothing disconnected.
      for (final d in fake.devices) {
        d['rssi'] = -90;
        d['connected'] = false;
      }
      fake.directReselect();
      await c.refreshPtuRssi();
      expect(container.read(commissionProvider).direct!.pickedMac, isNull);
      await c.rescanDirect();
      s = container.read(commissionProvider);
      expect(s.direct!.pickedMac, isNull);
      expect(fake.disconnects, [_pick]);
    });
  });

  group('3. identify right after a connect', () {
    test('RSSI 0 is shown as 「—」', () {
      expect(rssiLabel(0), 'RSSI —');
      expect(rssiLabel(null), 'RSSI —');
      expect(rssiLabel(-48), '-48 dBm');
      expect(const DirectCandidate(_pick, 0, null).rssiText, 'RSSI —');
      const ack = {'ptu_write': 'ok', 'mac': _pick, 'rssi': 0};
      expect(identifyLineText(ack), '$identifySentLine · $_pick · RSSI —');
      expect(identifyLineText(ack), isNot(contains('0 dBm')));
      expect(identifyNoteText(ack), contains('RSSI —'));
      expect(identifyNoteText(ack), isNot(contains('0 dBm')));
      expect(identifyAckText(ack), isNot(contains('0 dBm')));
    });

    testWidgets('new link, RSSI 0: 「連線建立中…」 disabled, then 辨識此樁', (
      tester,
    ) async {
      _phone(tester);
      directSettleWindow = const Duration(milliseconds: 300);
      final fake = _FreshLink();
      late ProviderContainer container;
      await tester.runAsync(() async {
        (container, _) = await _toStep7(fake);
      });
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).directSettling, isTrue);
      await tester.pumpWidget(_screen(container));
      expect(_label(tester, 'direct-identify'), directSettlingLabel);
      expect(_enabled(tester, 'direct-identify'), isFalse);
      // Round 28: the advertising RSSI of the pick meanwhile (was 「RSSI
      // —」 for ~70 s in the field).
      expect(find.text(directAdvRssiText(-38)), findsOneWidget);
      expect(find.text('RSSI —'), findsNothing);
      expect(find.textContaining(' 0 dBm'), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      expect(container.read(commissionProvider).directSettling, isFalse);
      expect(_label(tester, 'direct-identify'), '辨識此樁');
      expect(_enabled(tester, 'direct-identify'), isTrue);
    });

    test(
      'an RSSI reading ends it early; a known PTU never starts it',
      () async {
        directSettleWindow = const Duration(seconds: 30);
        final fake = _FreshLink();
        final (container, c) = await _toStep7(fake);
        addTearDown(container.dispose);
        expect(container.read(commissionProvider).directSettling, isTrue);
        fake.zeroReads = 0;
        await c.refreshPtuRssi();
        expect(container.read(commissionProvider).directSettling, isFalse);
        // Same PTU reading 0 again later: not a new link.
        fake.zeroReads = 1;
        await c.refreshPtuRssi();
        expect(container.read(commissionProvider).directSettling, isFalse);

        // A normal pick (RSSI known) is never settling.
        final plain = PickGateway();
        final (other, _) = await _toStep7(plain);
        addTearDown(other.dispose);
        expect(other.read(commissionProvider).directSettling, isFalse);
      },
    );

    test('ptu_write not_connected: sent once more after the delay, then '
        'the result of that one', () async {
      identifyRetryDelay = const Duration(milliseconds: 60);
      final fake = _LateGatt();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.identify();
      expect(fake.identifyAt, hasLength(2));
      expect(
        fake.identifyAt[1].difference(fake.identifyAt[0]),
        greaterThanOrEqualTo(const Duration(milliseconds: 55)),
      );
      var s = container.read(commissionProvider);
      expect(s.identifiedMac, _pick);
      expect(s.identifyLine, contains(_pick));
      expect(directConfirmReady(s), isTrue);

      // Still not_connected: two sends only, and it says so.
      fake
        ..notConnected = 5
        ..identifyAt.clear();
      await c.identify();
      s = container.read(commissionProvider);
      expect(fake.identifyAt, hasLength(2));
      expect(s.identifyLine, '已送出 · 只有閘道器閃燈，PTU 未收到');
      expect(s.identifiedMac, isNull);
      expect(s.error, isNull);
    });
  });

  group('4. session token across an APP kill', () {
    late HttpOverrides? saved;
    setUp(() {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() => HttpOverrides.global = saved);

    test('login stores the token (not the password) with an expiry; a new '
        'APP instance uses it until it expires or is refused', () async {
      FlutterSecureStorage.setMockInitialValues({});
      var accept = true;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path == '/api/auth/app-login') {
          req.response.write(jsonEncode({'api_key': 'k-123'}));
        } else if (accept && req.headers.value('X-API-Key') == 'k-123') {
          req.response.write(jsonEncode({'ok': true}));
        } else {
          req.response.statusCode = 401;
          req.response.write(jsonEncode({'detail': 'no'}));
        }
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';
      const storage = FlutterSecureStorage();

      await DashboardApi().login(base, 'secret-pw');
      final all = await storage.readAll();
      expect(all.values.join(), isNot(contains('secret-pw')));
      final record =
          jsonDecode(all[sessionStorageKey(Uri.parse(base))]!) as Map;
      expect(record['token'], 'k-123');
      final expires = DateTime.fromMillisecondsSinceEpoch(
        record['expires'] as int,
      );
      expect(
        expires.difference(DateTime.now()),
        greaterThan(sessionTokenTtl - const Duration(minutes: 1)),
      );

      // 「APP killed」: a fresh instance, no login.
      final next = DashboardApi();
      expect(await next.restoreSession(base), isTrue);
      expect(await next.request('GET', '/api/latest'), {'ok': true});

      // Expired: not used, dropped.
      final late = DashboardApi(
        now: () =>
            DateTime.now().add(sessionTokenTtl + const Duration(hours: 1)),
      );
      expect(await late.restoreSession(base), isFalse);
      expect(
        await storage.read(key: sessionStorageKey(Uri.parse(base))),
        isNull,
      );

      // Refused (401): dropped, the next start logs in again.
      await DashboardApi().login(base, 'secret-pw');
      final refused = DashboardApi();
      expect(await refused.restoreSession(base), isTrue);
      accept = false;
      await expectLater(
        refused.request('GET', '/api/latest'),
        throwsA(
          isA<GatewayFailure>().having((e) => e.code, 'code', 'authentication'),
        ),
      );
      expect(await DashboardApi().restoreSession(base), isFalse);

      // A plain-http remote host never gets a key.
      expect(
        await DashboardApi().restoreSession('http://example.com'),
        isFalse,
      );
    });

    testWidgets('重新連線並繼續 after a kill: the saved token, no login '
        'dialog', (tester) async {
      final fake = _TokenGateway();
      final container = await pumpApp(
        tester,
        fake,
        prefs: {
          'demo_progress': jsonEncode({
            'step': 5,
            'site': 1,
            'gateway': 1,
            'peer': 'demo-gateway',
            'peer_name': 'GIOS-S1-GW01',
            'selected': ['A', 'B', 'C'],
            'done': {'A': 1, 'B': 2},
            'assignments': [],
          }),
        },
      );
      await tester.runAsync(
        () => container.read(commissionProvider.notifier).restore(),
      );
      await tester.pumpAndSettle();
      final c = container.read(commissionProvider.notifier);
      expect(c.savedResumeNeedsLogin, isTrue);
      await tester.tap(find.byKey(const Key('saved-resume')));
      await tester.pump();
      expect(find.byKey(const Key('resume-login')), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(fake.restored, hasLength(1));
      final s = container.read(commissionProvider);
      expect(s.loggedIn, isTrue);
      expect(s.savedResume, isFalse);
      expect(find.text(resumeWithoutLoginText), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no saved token: the build credential logs in (09-28: no '
        'password dialog)', (tester) async {
      final fake = _TokenGateway()..hasSession = false;
      final container = await pumpApp(
        tester,
        fake,
        prefs: {
          'demo_progress': jsonEncode({
            'step': 5,
            'site': 1,
            'gateway': 1,
            'peer': 'demo-gateway',
            'peer_name': 'GIOS-S1-GW01',
            'selected': ['A'],
            'done': {},
            'assignments': [],
          }),
        },
      );
      await tester.runAsync(
        () => container.read(commissionProvider.notifier).restore(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-resume')));
      await tester.pumpAndSettle();
      expect(fake.restored, hasLength(1));
      expect(find.byKey(const Key('resume-login')), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).loggedIn, isTrue);
      expect(find.text(resumeWithoutLoginText), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test('a refused restored token is renewed with the given fallback '
        '(the existing automatic re-login)', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _RefusedToken();
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      const base = 'http://192.168.0.12:18000';
      expect(
        await c.restoreSession(base, fallbackPassword: 'fallback-key'),
        isTrue,
      );
      expect(container.read(commissionProvider).loggedIn, isTrue);
      await c.refreshHealth();
      expect(fake.logins, [(base, 'fallback-key')]);
      expect(fake.refuse, 0);
      expect(container.read(commissionProvider).loggedIn, isTrue);

      // A backend without stored sessions: nothing restored.
      final plain = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(DemoSystem()),
          apiProvider.overrideWithValue(DemoSystem()),
        ],
      );
      addTearDown(plain.dispose);
      expect(
        await plain.read(commissionProvider.notifier).restoreSession(base),
        isFalse,
      );
      expect(plain.read(commissionProvider).loggedIn, isFalse);
    });
  });

  group('5. idle link loss at direct step 7', () {
    test('found by 辨識此樁: reconnects by itself, identification kept', () async {
      final fake = _IdleDrop();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.identify();
      expect(container.read(commissionProvider).identifiedMac, _pick);
      final line = container.read(commissionProvider).identifyLine;
      final connects = fake.connects;

      fake.dropOnIdentify = true;
      await c.identify();
      await _until(() {
        final s = container.read(commissionProvider);
        return !s.busy && !s.relinking;
      });
      final s = container.read(commissionProvider);
      expect(fake.connects, greaterThan(connects), reason: 'reconnected');
      expect(s.error, isNull, reason: 'no red box waiting for a tap');
      expect(s.relinking, isFalse);
      expect(s.uploadWatch, isNot(UploadWatch.linkLost));
      expect(s.step, 4);
      expect(s.direct!.pickedMac, _pick);
      expect(s.identifiedMac, _pick);
      expect(s.identifyLine, line);
      expect(directConfirmReady(s), isTrue);
      expect(fake.sent('get_status'), isNotEmpty);
    });

    test('back with another PTU connected: identification cleared', () async {
      final fake = _IdleDrop();
      final (container, c) = await _toStep7(fake);
      addTearDown(container.dispose);
      await c.identify();
      expect(container.read(commissionProvider).identifiedMac, _pick);
      fake
        ..dropOnIdentify = true
        ..onDrop = () {
          fake.device(_pick)['connected'] = false;
          fake.device(_pick)['rssi'] = -70;
          fake.device(_first)['rssi'] = -30;
        };
      await c.identify();
      await _until(() {
        final s = container.read(commissionProvider);
        return !s.busy && !s.relinking;
      });
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.direct!.pickedMac, _first);
      expect(s.identifiedMac, isNull);
      expect(s.directNotice, directSwitchedText(_first));
      expect(directConfirmReady(s), isFalse);
    });
  });
}
