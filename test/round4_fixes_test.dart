import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp, ready;

/// Firmware 1.7.15 style ack. [writeTo] makes the gateway write another PTU
/// than requested (the round-4 mix-up); [ackOverride] replaces ack fields;
/// [legacy] answers like firmware before 1.7.15 (no mac/device_number).
class AckLink extends DroppingLink {
  final writeTo = <String, String>{};
  Map<String, dynamic>? ackOverride;
  bool legacy = false;
  final stickNumber = <String, int>{};

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'assign_device_id' && !down) {
      final mac = params['mac'].toString();
      final target = writeTo[mac] ?? mac;
      await super.command(op, {
        ...params,
        'mac': target,
        if (stickNumber.containsKey(mac)) 'new_id': stickNumber[mac],
      });
      if (legacy) return {'success': true};
      return {
        'success': true,
        'mac': target.toLowerCase().replaceAll(':', '-'),
        'device_number': params['new_id'],
        ...?ackOverride,
      };
    }
    return super.command(op, params);
  }
}

/// [AckLink] whose get_ble_devices can hide MACs, keep a stale number, or
/// return custom slot rows.
class HidingAckLink extends AckLink {
  final hideFromList = <String>{};
  bool hideAfterAssign = false;
  List<Map<String, dynamic>>? slotRows;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'get_ble_devices' && slotRows != null) {
      commands.add(op);
      return {'devices': slotRows};
    }
    final r = await super.command(op, params);
    if (op == 'get_ble_devices' && hideAfterAssign) {
      return {
        'devices': [
          for (final d in r['devices'] as List)
            if (!hideFromList.contains(d['mac'])) d,
        ],
      };
    }
    return r;
  }
}

/// A link whose phone Bluetooth was just turned back on.
class SettlingLink extends DroppingLink implements BluetoothReadiness {
  bool settling = false;
  Duration? waited;
  @override
  Future<bool> adapterSettling() async => settling;
  @override
  Future<void> waitAdapterReady(Duration max) async {
    waited = max;
    settling = false;
  }
}

Map<String, Object> savedProgress(DroppingLink fake) => {
  'demo_progress': jsonEncode({
    'step': 5,
    'site': 1,
    'gateway': 1,
    'peer': 'demo-gateway',
    'peer_name': 'GIOS-S1-GW01',
    'selected': [for (final d in fake.devices) d['mac']],
    'done': {fake.devices.first['mac']: 1},
    'assignments': [],
  }),
};

Future<void> settle(
  WidgetTester tester,
  ProviderContainer container,
  bool Function(CommissionState) done,
) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 1));
    if (done(container.read(commissionProvider))) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resume to step 9', () {
    testWidgets('saved resume with login verifies step 9 by itself', (
      tester,
    ) async {
      final fake = DroppingLink();
      fake.devices.first['device_number'] = 1;
      final container = await pumpApp(
        tester,
        fake,
        prefs: savedProgress(fake),
      );
      await tester.runAsync(
        () => container.read(commissionProvider.notifier).restore(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-resume')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('resume-login')),
          matching: find.byType(TextField),
        ),
        'secret',
      );
      await tester.tap(find.byKey(const Key('resume-login-ok')));
      await settle(tester, container, (s) => s.step == 7);
      final s = container.read(commissionProvider);
      expect(s.step, 7, reason: 'no tap on 開始資料驗證 needed');
      expect(s.verified, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('manual resume: verify tap shows feedback by the button', (
      tester,
    ) async {
      final fake = DroppingLink();
      fake.devices.first['device_number'] = 1;
      final container = await pumpApp(
        tester,
        fake,
        prefs: savedProgress(fake),
      );
      await tester.runAsync(
        () => container.read(commissionProvider.notifier).restore(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saved-resume')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resume-login-cancel')));
      await settle(tester, container, (s) => s.step == 6 && !s.busy);
      expect(container.read(commissionProvider).step, 6);
      // A PTU without a number (the field case): verify fails at once.
      container.read(commissionProvider).ptus.last['device_number'] = 0;
      await tester.enterText(find.byType(TextField).first, 'secret');
      await tester.ensureVisible(find.text('開始資料驗證'));
      await tester.tap(find.text('開始資料驗證'));
      await settle(tester, container, (s) => !s.busy);
      await tester.pumpAndSettle();
      final feedback = find.byKey(const Key('verify-feedback'));
      expect(feedback, findsOneWidget);
      expect(
        find.descendant(of: feedback, matching: find.textContaining('裝置編號')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('assign ack check (firmware 1.7.15)', () {
    test('mac compare ignores case and separators', () {
      expect(sameMac('AA:BB:CC:00:00:01', 'aa-bb-cc-00-00-01'), isTrue);
      expect(sameMac('AA:BB:CC:00:00:01', 'aabbcc000002'), isFalse);
      expect(assignAckMismatch({'success': true}, 'AA:01', 3), isNull);
      expect(
        assignAckMismatch({'mac': 'aa:02', 'device_number': 3}, 'AA:01', 3),
        wrongDeviceText,
      );
      expect(
        assignAckMismatch({'mac': 'aa01', 'device_number': 4}, 'AA:01', 3),
        isNotNull,
      );
      expect(
        assignAckMismatch({'mac': 'aa01', 'device_number': 3}, 'AA:01', 3),
        isNull,
      );
    });

    test('OTP and expired ack codes map to firmware contract text', () {
      expect(
        const GatewayFailure(
          'otp_invalid',
          fromGateway: true,
        ).message,
        '一次性密碼錯誤',
      );
      expect(
        const GatewayFailure(
          'otp_locked',
          fromGateway: true,
        ).message,
        '一次性密碼已鎖定，請稍後再試',
      );
      expect(
        const GatewayFailure(
          'otp_reused',
          fromGateway: true,
        ).message,
        '一次性密碼已用過',
      );
      expect(
        const GatewayFailure('expired', fromGateway: true).message,
        '指令已逾期（手機時間與閘道器差異過大或傳送延遲），請重試',
      );
      expect(
        const GatewayFailure(
          'device connected but service not ready, try again',
          fromGateway: true,
        ).message,
        '閘道器藍牙服務尚未就緒，請稍後再試',
      );
    });

    test('new_id=255 (reset) matches device_number 0 or 255', () {
      expect(
        assignAckMismatch({'mac': 'aa01', 'device_number': 0}, 'AA:01', 255),
        isNull,
      );
      expect(
        assignAckMismatch(
          {'mac': 'aa01', 'device_number': 255},
          'AA:01',
          255,
        ),
        isNull,
      );
      expect(
        assignAckMismatch({'mac': 'aa01', 'device_number': 4}, 'AA:01', 255),
        isNotNull,
      );
    });

    test('ack of another PTU is a failure, not a success', () async {
      final fake = AckLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.writeTo[macs[1]] = macs[2];
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.assignFailed[macs[1]], wrongDeviceText);
      expect(s.results[macs[1]], contains(wrongDeviceText));
      expect(s.step, 4);
    });

    test('device_number in the ack must be the requested id', () async {
      final fake = AckLink()..ackOverride = {'device_number': 9};
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.assignFailed.length, 3);
      expect(s.step, 4);
      expect(s.results.values.first, contains('#9'));
    });

    test('old firmware ack without mac/device_number still passes', () async {
      final fake = AckLink()..legacy = true;
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.assignFailed, isEmpty);
      expect(s.step, 6);
    });

    test('read-back lists a PTU whose number differs', () async {
      final fake = AckLink()..legacy = true;
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      // Old firmware acks ok but writes the 2nd PTU's number onto the 3rd.
      fake.writeTo[macs[1]] = macs[2];
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.assignFailed.keys, contains(macs[1]));
      expect(s.results[macs[1]], contains('回讀編號'));
      expect(s.step, 4);
    });
  });

  group('round 5: verified:false ack (firmware 1.7.15)', () {
    test('verified:false with matching mac/number is not a failure', () {
      expect(
        assignAckMismatch(
          {'mac': 'aa01', 'device_number': 3, 'verified': false},
          'AA:01',
          3,
        ),
        isNull,
      );
    });

    test('read-back matches: success, no retries', () async {
      final fake = AckLink()..ackOverride = {'verified': false};
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.assignFailed, isEmpty);
      expect(fake.assigns, hasLength(3));
      expect(s.step, 6);
    });

    test('read-back without the MAC: success, waiting to connect', () async {
      final fake = HidingAckLink()..ackOverride = {'verified': false};
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.hideFromList.add(macs[0]);
      fake.hideAfterAssign = true;
      await c.configurePtus(skip: {macs[1], macs[2]});
      final s = container.read(commissionProvider);
      expect(s.assignFailed, isEmpty);
      expect(s.assignedOk, contains(macs[0]));
      expect(fake.commands, contains('set_config'));
    });

    test('read-back number differs: failure', () async {
      final fake = AckLink()..ackOverride = {'verified': false};
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.stickNumber[macs[1]] = 9;
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.assignFailed.keys, contains(macs[1]));
      expect(s.results[macs[1]], contains('回讀編號為 #9'));
      expect(s.step, 4);
    });

    test('pending read-back text while waiting', () {
      expect(ackNeedsReadback({'verified': false}), isTrue);
      expect(ackNeedsReadback({}), isFalse);
      expect(pendingReadbackText(2), contains('待回讀確認'));
    });

    test('0 successes: no set_config / join_fleet', () async {
      final fake = AckLink()..ackOverride = {'device_number': 9};
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.commands.clear();
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.assignFailed.length, 3);
      expect(fake.commands, isNot(contains('set_config')));
      expect(fake.commands, isNot(contains('join_fleet')));
      expect(s.step, 4);
    });

    test('partial success keeps max_connections at the star range (5)', () async {
      final fake = AckLink()..ackOverride = {'verified': false};
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.failing.add(macs[2]);
      await c.configurePtus();
      expect(fake.config['max_connections'], 5);
      expect(fake.commands, contains('join_fleet'));
    });

    test('stale number is not shown: scan device_number wins', () async {
      final fake = HidingAckLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final mac = fake.devices.first['mac'].toString();
      // Gateway slot table still lists #5 (not connected); scan says 0.
      fake.slotRows = [
        {'mac': mac, 'device_number': 5, 'connected': false},
      ];
      fake.devices.first['device_number'] = 0;
      await c.discover();
      final ptu = container
          .read(commissionProvider)
          .ptus
          .firstWhere((p) => p['mac'] == mac);
      expect(ptu['device_number'], 0);
    });

    test('saved progress numbers do not overlay a scanned 0', () async {
      final fake = DroppingLink();
      SharedPreferences.setMockInitialValues({});
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final mac = fake.devices.first['mac'].toString();
      SharedPreferences.setMockInitialValues({
        'demo_progress': jsonEncode({
          'step': 6,
          'assignments': [
            {'mac': mac, 'id': 5},
          ],
        }),
      });
      await c.restore();
      fake.devices.first['device_number'] = 0;
      await c.discover();
      final ptu = container
          .read(commissionProvider)
          .ptus
          .firstWhere((p) => p['mac'] == mac);
      expect(ptu['device_number'], 0);
    });
  });

  group('field friction', () {
    test('bottom button counts only the PTUs left after a link loss', () async {
      final fake = DroppingLink()..dropAfterAssigns = 1;
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.resumePending, isTrue);
      expect(configureLabel(s), '重新連線並繼續（剩 2 台）');
    });

    test('assigned and connected PTUs show 已連線 #n', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.devices.first
        ..['device_number'] = 1
        ..['connected'] = true;
      container.read(commissionProvider).ptus.first['device_number'] = 1;
      await c.configurePtus(skip: {macs[1], macs[2]});
      expect(container.read(commissionProvider).results[macs[0]], '已連線 #1');
    });

    test('reconnect waits for a just-enabled phone Bluetooth', () async {
      final fake = SettlingLink()..dropAfterAssigns = 1;
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      fake.settling = true;
      final messages = <String>[];
      container.listen(commissionProvider, (_, s) => messages.add(s.message));
      await c.resumeAssign();
      expect(fake.waited, bluetoothReadyBudget);
      expect(messages, contains(waitingBluetoothText));
      expect(container.read(commissionProvider).error, isNull);
    });

    testWidgets('done page skips 正在確認資料上傳 when verify saw a heartbeat', (
      tester,
    ) async {
      final fake = DroppingLink();
      final container = await pumpApp(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '');
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await tester.runAsync(
        () => c.configureWifi(1, 1, 'Office-2G', 'pw123456'),
      );
      await tester.runAsync(c.online);
      await c.discover();
      await tester.runAsync(c.configurePtus);
      await tester.pumpAndSettle();
      await tester.runAsync(() => c.verify('https://example.invalid', ''));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 7);
      // Step 9 already recorded a fresh heartbeat: show 上傳中 directly.
      expect(container.read(commissionProvider).backendSeenAt, isNotNull);
      expect(find.byKey(const Key('health-pending')), findsNothing);
      expect(find.textContaining('資料有異常'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
