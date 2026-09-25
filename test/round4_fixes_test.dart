import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/contracts.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp, ready;

/// Firmware 1.7.15 style ack. [writeTo] makes the gateway write another PTU
/// than requested (the round-4 mix-up); [ackOverride] replaces ack fields;
/// [legacy] answers like firmware before 1.7.15 (no mac/device_number).
class AckLink extends DroppingLink {
  final writeTo = <String, String>{};
  Map<String, dynamic>? ackOverride;
  bool legacy = false;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'assign_device_id' && !down) {
      final mac = params['mac'].toString();
      final target = writeTo[mac] ?? mac;
      await super.command(op, {...params, 'mac': target});
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

  group('field friction', () {
    test('bottom button counts only the PTUs left after a link loss', () async {
      final fake = DroppingLink()..dropAfterAssigns = 1;
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.resumePending, isTrue);
      expect(configureLabel(s), '配置 2 台並開始監控');
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

    testWidgets('done page says 正在確認資料上傳 before the first health check', (
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
      expect(find.byKey(const Key('health-pending')), findsOneWidget);
      expect(find.textContaining('資料有異常'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
