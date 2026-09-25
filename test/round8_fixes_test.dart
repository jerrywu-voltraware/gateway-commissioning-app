// Round 8 phone test fixes: resume count, step 9 back/cancel, step 7
// keep-alive and banner action, first reconnect retry, per-PTU verify
// progress and step 9 order.
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

import 'link_loss_test.dart' show DroppingLink, ready, pumpApp;
import 'round6_fixes_test.dart' show StaleAdapterPlatform;

/// The gateway takes (and connects) the [takeAt]-th assignment, then the
/// link drops before the APP sees the ack (like a kill right after it).
class TakeThenDrop extends DroppingLink {
  int? takeAt;
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (!down && op == 'assign_device_id' && takeAt == assigns.length) {
      takeAt = null;
      await super.command(op, params);
      devices.firstWhere((d) => d['mac'] == params['mac'])['connected'] = true;
      down = true;
      throw const GatewayFailure('not_connected');
    }
    final result = await super.command(op, params);
    // A real gateway connects each PTU right after its assignment.
    if (op == 'assign_device_id') {
      devices.firstWhere((d) => d['mac'] == params['mac'])['connected'] = true;
    }
    return result;
  }
}

Map<String, dynamic> row(int id, String ts, {bool online = true}) => {
  'device_id': id,
  'online': online,
  'lag_seconds': 5,
  'error_num': 0,
  'ts': ts,
};

Future<(ProviderContainer, CommissioningController)> atStep7(
  WidgetTester tester,
  DroppingLink fake,
) async {
  final container = await pumpApp(tester, fake);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await tester.runAsync(() => c.configureWifi(1, 1, 'Office-2G', 'pw123456'));
  await c.online(skip: true);
  await c.discover();
  return (container, c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. resume count follows the gateway', () {
    test('in-flight assignment is saved and reconciled on resume', () async {
      final fake = TakeThenDrop();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.takeAt = 1; // the 2nd assign reaches the gateway, ack is lost
      await c.configurePtus();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('demo_progress')!) as Map;
      expect((saved['done'] as Map).keys, [macs[0]]);
      expect(saved['inflight'], {macs[1]: 2});

      final second = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(second.dispose);
      final c2 = second.read(commissionProvider.notifier);
      await c2.restore();
      expect(
        second.read(commissionProvider).message,
        contains('#2 指派中斷、重新連線後以閘道器核對為準'),
      );
      fake.assigns.clear();
      final messages = <String>[];
      second.listen(commissionProvider, (_, s) => messages.add(s.message));
      await c2.resumeSaved();
      // Reconciled: #2 counts (the gateway has it) and is not re-sent.
      expect(messages, contains(startsWith('上次中斷於第 8 步（開始監控），已完成 2 台（#1、#2）')));
      expect(fake.assigns, [macs[2]]);
      expect(second.read(commissionProvider).step, 6);
    });

    test('resumeText lists in-flight numbers separately', () {
      expect(
        resumeText(5, [2, 1], 1, inflight: [3]),
        '上次中斷於第 8 步（開始監控），已完成 2 台（#1、#2），'
        '#3 指派中斷、重新連線後以閘道器核對為準，尚有 1 台未配置。'
        '閘道器仍在運作，不需重新上電。',
      );
    });
  });

  group('2. step 9 back to step 7', () {
    test('backToSelection keeps selection and assignedOk', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.step, 6);
      final selected = s.selected, ok = s.assignedOk;
      expect(ok, isNotEmpty);
      await c.backToSelection();
      s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.selected, selected);
      expect(s.assignedOk, ok);
      expect(s.peer, isNotNull);
    });

    test('cancel during verification returns to step 7, not step 2', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final run = c.verify('https://example.invalid', '');
      await Future<void>.delayed(Duration.zero);
      await c.backToSelection();
      await run;
      final s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.assignedOk, isNotEmpty);
      expect(s.peer, isNotNull);
    });

    testWidgets('step 9 shows 返回選擇 PTU', (tester) async {
      final fake = DroppingLink();
      final (container, c) = await atStep7(tester, fake);
      await tester.runAsync(c.configurePtus);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 6);
      await tester.ensureVisible(find.byKey(const Key('verify-back')));
      await tester.tap(find.byKey(const Key('verify-back')));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 4);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('3. step 7 keep-alive and banner action', () {
    test('idle step 7 pings every 15 s when RSSI polling is off', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      c.setAutoRssi(false);
      fake.commands.clear();
      final now = DateTime.now().add(const Duration(seconds: 16));
      await c.keepAlive(now: now);
      expect(fake.commands, ['ping']);
      await c.keepAlive(now: now.add(const Duration(seconds: 5)));
      expect(fake.commands, ['ping']);
      expect(keepAliveInterval, const Duration(seconds: 15));
    });

    test('a drop seen at step 7 offers the reconnect action', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.down = true;
      await c.refreshPtuRssi();
      final s = container.read(commissionProvider);
      expect(s.error, isNotNull);
      expect(s.scanResumePending, isTrue);
      expect(s.uploadWatch, UploadWatch.linkLost);
      await c.discover();
      expect(container.read(commissionProvider).error, isNull);
    });

    testWidgets('step 7 drop banner has a reconnect button', (tester) async {
      final fake = DroppingLink();
      final (_, c) = await atStep7(tester, fake);
      fake.down = true;
      await c.refreshPtuRssi();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('error-banner')), findsOneWidget);
      expect(find.byKey(const Key('ptu-resume')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. first connect failure', () {
    setUp(() {
      BleGatewayLink.staleSettle = Duration.zero;
      BleGatewayLink.retryGap = Duration.zero;
      BleGatewayLink.rescanWindow = const Duration(milliseconds: 10);
    });
    const peer = GatewayPeer('AA:BB:CC:DD:EE:FF', 'GIOS-S1', -28);

    test('is retried at once and its type is kept', () async {
      final platform = StaleAdapterPlatform()..failConnects = 1;
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      final stages = <String>[];
      await link.connect(peer, onStage: stages.add);
      expect(platform.calls.where((c) => c == 'connect'), hasLength(2));
      expect(stages, ['清除舊連線', '正在連線閘道器']);
      expect(link.firstConnectFailure, contains('Failed to connect'));
      expect(
        withFirstFailure('x', link),
        allOf(startsWith('x\n第一次連線失敗：'), contains('Exception')),
      );
      await link.disconnect();
    });

    test('a clean connect clears it', () async {
      final platform = StaleAdapterPlatform();
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await link.connect(peer);
      expect(link.firstConnectFailure, isNull);
      expect(withFirstFailure('x', link), 'x');
      await link.disconnect();
    });
  });

  group('5. per-PTU verification progress', () {
    test('one PTU without a new row does not reset the others', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      final lastNew = <int, int>{};
      void tick(int elapsed, List<Map<String, dynamic>> rows) => verifyTally(
        ids: [1, 2],
        rows: rows,
        previous: previous,
        counts: counts,
        lastNew: lastNew,
        elapsed: elapsed,
      );
      tick(0, [row(1, '2030-01-01T00:00:00'), row(2, '2030-01-01T00:00:00')]);
      expect(counts, {1: 1, 2: 1});
      // 10 s later only #1 has a new row: #2 keeps 1, not 0.
      tick(10, [row(1, '2030-01-01T00:00:10'), row(2, '2030-01-01T00:00:00')]);
      expect(counts, {1: 2, 2: 1});
      tick(20, [row(1, '2030-01-01T00:00:20'), row(2, '2030-01-01T00:00:30')]);
      expect(counts, {1: 3, 2: 2});
      tick(30, [row(1, '2030-01-01T00:00:30'), row(2, '2030-01-01T00:00:40')]);
      expect(counts, {1: 3, 2: 3});
      // An offline row resets only that PTU.
      tick(40, [
        row(1, '2030-01-01T00:00:40', online: false),
        row(2, '2030-01-01T00:00:50'),
      ]);
      expect(counts, {1: 0, 2: 3});
    });

    test('text shows each PTU and 尚無資料 after 60 s', () {
      final previous = <int, DateTime>{};
      final counts = <int, int>{};
      final lastNew = <int, int>{};
      for (var t = 0; t <= 60; t += verifyPollSeconds) {
        verifyTally(
          ids: [3, 1],
          rows: [row(1, '2030-01-01T00:00:${t.toString().padLeft(2, '0')}')],
          previous: previous,
          counts: counts,
          lastNew: lastNew,
          elapsed: t,
        );
      }
      final waiting = {
        for (final id in [3, 1])
          if (60 - (lastNew[id] ?? 0) >= verifyIdleLimit) id,
      };
      expect(waiting, {3});
      expect(
        verifyProgressText([3, 1], counts, waiting),
        '資料驗證 #1 3/3、#3 0/3\nPTU #3 尚無資料',
      );
      expect(verifyPollSeconds, 10);
    });

    test('demo verification ends with every PTU at 3/3', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.verifyCounts.values, everyElement(3));
    });
  });

  group('6. step 9 list order', () {
    testWidgets('PTUs are listed by number', (tester) async {
      final fake = DroppingLink();
      final (container, c) = await atStep7(tester, fake);
      await tester.runAsync(c.configurePtus);
      final ptus = container.read(commissionProvider).ptus;
      expect(ptus.length, greaterThanOrEqualTo(3));
      // Make the list order #3, #1, #2.
      final ids = ptus.map((p) => p['device_number'] as int).toList();
      ptus[0]['device_number'] = ids[2];
      ptus[1]['device_number'] = ids[0];
      ptus[2]['device_number'] = ids[1];
      c.setAutoRssi(false); // any state change re-renders
      await tester.pumpAndSettle();
      final sorted = List.of(ids)..sort();
      final ys = [
        for (final id in sorted)
          tester.getTopLeft(find.byKey(Key('verify-ptu-$id'))).dy,
      ];
      expect(ys, orderedEquals(List.of(ys)..sort()));
      expect(ys.toSet(), hasLength(ys.length));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
