import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';

/// Demo gateway whose phone BLE link drops after [dropAfterAssigns]
/// successful assign_device_id calls (every command then fails with
/// not_connected until the APP reconnects). [failConnect] makes reconnects
/// fail; [failing] PTUs always fail their assign (a real PTU failure).
class DroppingLink extends DemoSystem {
  int? dropAfterAssigns;
  bool down = false;
  bool failConnect = false;
  final failing = <String>{};
  final assigns = <String>[];
  final commands = <String>[];

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    if (failConnect) {
      throw const GatewayFailure('ble_error', detail: '133 Unknown Error 133');
    }
    down = false;
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (down) throw const GatewayFailure('not_connected');
    commands.add(op);
    if (op == 'assign_device_id') {
      final mac = params['mac'].toString();
      if (failing.contains(mac)) {
        throw gatewayAckFailure({
          'mac': mac,
          'success': false,
          'error': 'connection/service discovery timeout',
        });
      }
      if (dropAfterAssigns != null && assigns.length >= dropAfterAssigns!) {
        down = true;
        dropAfterAssigns = null;
        throw const GatewayFailure('not_connected');
      }
      assigns.add(mac);
    }
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> ready(
  DroppingLink fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'test', 'test-password');
  await c.online();
  await c.discover();
  return (container, c);
}

Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  DemoSystem fake, {
  Size size = const Size(800, 2400),
  double ratio = 1,
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [demoSystemProvider.overrideWithValue(fake)],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  container.read(demoProvider.notifier).set(true);
  await tester.pumpAndSettle();
  return container;
}

/// Round 13: step 8 (like step 7) reconnects by itself after a phone link
/// loss. Tests of the manual 「重新連線並繼續」 path — what is left once the
/// automatic reconnect gave up — switch the automatic rounds off.
void manualRelinkOnly() {
  late int keep;
  setUp(() {
    keep = autoRelinkRounds;
    autoRelinkRounds = 0;
  });
  tearDown(() => autoRelinkRounds = keep);
}

/// Same as [manualRelinkOnly], for a single test.
void manualRelinkInThisTest() {
  final keep = autoRelinkRounds;
  autoRelinkRounds = 0;
  addTearDown(() => autoRelinkRounds = keep);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  manualRelinkOnly();

  test('phone link loss is not a PTU failure', () {
    expect(
      ptuFailureText(const GatewayFailure('not_connected')),
      notAssignedLinkText,
    );
    expect(
      ptuFailureText(const GatewayFailure('disconnected')),
      notAssignedLinkText,
    );
    expect(const GatewayFailure('phone_link_lost').message, phoneLinkLostText);
    expect(
      isPhoneLinkFailure(gatewayAckFailure('{"error":"status 133"}')),
      isFalse,
    );
  });

  test('step 8 stops at a phone link loss and resumes only the rest', () async {
    final fake = DroppingLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final macs = fake.devices.map((d) => d['mac'].toString()).toList();
    fake.dropAfterAssigns = 1;
    await c.configurePtus();
    var s = container.read(commissionProvider);
    expect(fake.assigns, [macs[0]]);
    // No command was sent after the loss.
    expect(fake.commands.where((o) => o == 'assign_device_id'), hasLength(2));
    expect(s.error, phoneLinkLostText);
    expect(s.results[macs[0]], startsWith('已指派 #'));
    expect(s.results[macs[1]], notAssignedLinkText);
    expect(s.results[macs[2]], notAssignedLinkText);
    expect(s.assignFailed, isEmpty);
    expect(s.unassigned, {macs[1], macs[2]});
    expect(s.resumePending, isTrue);
    for (final r in s.results.values) {
      expect(r, isNot(contains('PTU 連線失敗')));
    }

    fake.assigns.clear();
    await c.resumeAssign();
    s = container.read(commissionProvider);
    expect(s.error, isNull);
    expect(fake.assigns, [macs[1], macs[2]]);
    expect(fake.commands, contains('join_fleet'));
    expect(fake.config['max_connections'], 5);
    expect(s.step, 6);
    expect(s.resumePending, isFalse);
  });

  test(
    'resumeAssign also configures a PTU checked after the disconnect',
    () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      // macs[2] starts unselected, so it is not part of the first pass.
      c.select(macs[2], false);
      fake.dropAfterAssigns = 1;
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.assignedOk, {macs[0]});
      expect(s.unassigned, {macs[1]});
      expect(s.resumePending, isTrue);

      // Checked only after the disconnect: not in unassigned/assignFailed,
      // but still not yet successfully assigned.
      c.select(macs[2], true);
      s = container.read(commissionProvider);
      expect(configureTargets(s), {macs[1], macs[2]});
      expect(configureLabel(s), '重新連線並繼續（剩 2 台）');

      fake.assigns.clear();
      await c.resumeAssign();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.assigns.toSet(), {macs[1], macs[2]});
      expect(s.assignedOk, {macs[0], macs[1], macs[2]});
      expect(s.resumePending, isFalse);
      expect(s.step, 6);
    },
  );

  test('link loss after a real PTU failure keeps the failed list', () async {
    final fake = DroppingLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final macs = fake.devices.map((d) => d['mac'].toString()).toList();
    fake.failing.add(macs[0]);
    fake.dropAfterAssigns = 1;
    await c.configurePtus();
    final s = container.read(commissionProvider);
    expect(s.assignFailed.keys, [macs[0]]);
    expect(s.results[macs[1]], startsWith('已指派 #'));
    expect(s.unassigned, {macs[2]});
  });

  test('reconnect failure offers retry instead of a silent scan', () async {
    final fake = DroppingLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    fake.dropAfterAssigns = 0;
    await c.configurePtus();
    fake.failConnect = true;
    final keep = connectPersistence;
    connectPersistence = const Duration(milliseconds: 50);
    addTearDown(() => connectPersistence = keep);
    await c.discover();
    var s = container.read(commissionProvider);
    expect(s.busy, isFalse);
    expect(s.reconnectFailed, isTrue);
    expect(s.error, reconnectFailedText);
    expect(s.message, reconnectFailedText);
    // The list was not cleared by a scan that never ran.
    expect(s.ptus, hasLength(3));
    expect(fake.commands.where((o) => o == 'scan_ble_discover'), hasLength(1));

    fake.failConnect = false;
    await c.resumeAssign();
    s = container.read(commissionProvider);
    expect(s.error, isNull);
    expect(s.reconnectFailed, isFalse);
    expect(s.step, 6);
  });

  test('UniversalBleException 133 becomes a plain BLE failure', () {
    final f = normalizeBleError(ConnectionException('Unknown Error 133'));
    expect(f, isA<GatewayFailure>());
    f as GatewayFailure;
    expect(f.code, 'ble_error');
    expect(f.message, '無法連上閘道器（藍牙錯誤 133），請靠近閘道器後重試');
    expect(f.detail, contains('Unknown Error 133'));
    final lost = normalizeBleError(
      UniversalBleException(
        code: UniversalBleErrorCode.deviceDisconnected,
        message: 'x',
      ),
    );
    expect((lost as GatewayFailure).code, 'disconnected');
  });

  testWidgets('link loss page: resume button, no PTU failure text', (
    tester,
  ) async {
    final fake = DroppingLink();
    final container = await pumpApp(tester, fake);
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await tester.runAsync(() => c.configureWifi(1, 1, 'Office-2G', 'pw123456'));
    await c.online(skip: true);
    await c.discover();
    final bad = fake.devices.first['mac'].toString();
    fake.failing.add(bad);
    fake.dropAfterAssigns = 1;
    await tester.runAsync(c.configurePtus);
    await tester.pumpAndSettle();
    expect(find.text(phoneLinkLostText), findsOneWidget);
    expect(find.byKey(const Key('ptu-resume')), findsOneWidget);
    expect(find.byKey(const Key('assign-failed-list')), findsOneWidget);
    expect(find.text('重試這 1 台'), findsOneWidget);
    expect(find.text(notAssignedLinkText), findsOneWidget);

    fake.failing.clear();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('ptu-resume')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final s = container.read(commissionProvider);
    expect(s.error, isNull);
    expect(s.step, 6);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reconnect failure shows retry and back to gateway search', (
    tester,
  ) async {
    final fake = DroppingLink();
    final container = await pumpApp(tester, fake);
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await tester.runAsync(() => c.configureWifi(1, 1, 'Office-2G', 'pw123456'));
    await c.online(skip: true);
    await c.discover();
    fake.dropAfterAssigns = 0;
    await tester.runAsync(c.configurePtus);
    fake.failConnect = true;
    await tester.runAsync(c.discover);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reconnect-retry')), findsOneWidget);
    expect(find.byKey(const Key('back-to-gateway')), findsOneWidget);
    expect(find.textContaining('正在掃描'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('back-to-gateway')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).step, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('done page summary is on screen of a real phone (full flow)', (
    tester,
  ) async {
    final fake = DroppingLink();
    // 1080 x 2220 px at 2.75 dpr (the field phone).
    final container = await pumpApp(
      tester,
      fake,
      size: const Size(1080, 2220),
      ratio: 2.75,
    );
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '');
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await tester.runAsync(() => c.configureWifi(1, 1, 'Office-2G', 'pw123456'));
    await tester.runAsync(c.online);
    await c.discover();
    await tester.runAsync(c.configurePtus);
    await tester.pumpAndSettle();
    await tester.runAsync(() => c.verify('https://example.invalid', ''));
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).step, 7);
    final summary = find.byKey(const Key('commission-summary'));
    expect(summary, findsOneWidget);
    expect(find.text('掃到 3 台，本機配置 3 台'), findsOneWidget);
    // Visible without scrolling: inside the first screen.
    final rect = tester.getRect(summary);
    expect(rect.bottom, lessThan(2220 / 2.75));
    await tester.pumpWidget(const SizedBox());
  });

  test('restart prompt names the step and the PTUs done', () async {
    expect(
      resumeText(5, [2, 1], 3),
      '上次中斷於第 8 步（開始監控），已完成 2 台（#1、#2），尚有 3 台未配置。'
      '閘道器仍在運作，不需重新上電。',
    );
  });

  test('restore + 重新連線並繼續 configures only unfinished PTUs', () async {
    final fake = DroppingLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final macs = fake.devices.map((d) => d['mac'].toString()).toList();
    fake.dropAfterAssigns = 1;
    await c.configurePtus();
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('demo_progress')!) as Map;
    expect(saved['step'], 5);
    expect((saved['done'] as Map).keys, [macs[0]]);

    // A fresh APP instance (the old one was killed).
    final second = ProviderContainer(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(second.dispose);
    final c2 = second.read(commissionProvider.notifier);
    await c2.restore();
    var s = second.read(commissionProvider);
    expect(
      s.message,
      // Round 8: #2 was in flight when the link dropped; the gateway decides.
      '上次中斷於第 8 步（開始監控），已完成 1 台（#1），'
      '#2 指派中斷、重新連線後以閘道器核對為準，尚有 1 台未配置。'
      '閘道器仍在運作，不需重新上電。',
    );
    expect(s.savedResume, isTrue);

    fake.assigns.clear();
    await c2.resumeSaved();
    s = second.read(commissionProvider);
    expect(s.error, isNull);
    expect(fake.assigns, [macs[1], macs[2]]);
    expect(s.step, 6);
  });

  testWidgets('restart shows 重新連線並繼續 on the first page', (tester) async {
    final fake = DroppingLink();
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
    // The page restores on start; the demo switch rebuilt the controller.
    await tester.runAsync(
      () => container.read(commissionProvider.notifier).restore(),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('上次中斷於第 8 步（開始監控），已完成 2 台（#1、#2），尚有 1 台未配置'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('saved-resume')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  Future<ProviderContainer> savedApp(
    WidgetTester tester,
    DemoSystem fake,
  ) async {
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
    return container;
  }

  testWidgets('saved resume without login asks to log in first', (
    tester,
  ) async {
    final container = await savedApp(tester, DroppingLink());
    expect(container.read(commissionProvider).loggedIn, isFalse);
    await tester.tap(find.byKey(const Key('saved-resume')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('resume-login')), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('resume-login')),
        matching: find.byType(TextField),
      ),
      'secret',
    );
    await tester.tap(find.byKey(const Key('resume-login-ok')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();
    final s = container.read(commissionProvider);
    expect(s.loggedIn, isTrue);
    expect(s.savedResume, isFalse);
    expect(find.text(resumeWithoutLoginText), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saved resume: cancelling login continues in manual mode', (
    tester,
  ) async {
    final container = await savedApp(tester, DroppingLink());
    await tester.tap(find.byKey(const Key('saved-resume')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resume-login-cancel')));
    await tester.pump();
    expect(find.text(resumeWithoutLoginText), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();
    final s = container.read(commissionProvider);
    expect(s.loggedIn, isFalse);
    expect(s.savedResume, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
