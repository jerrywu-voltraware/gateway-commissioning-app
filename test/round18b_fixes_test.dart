// Round 18b (after field round 18, firmware 1.7.24):
// 1. Step 2: a link that drops while the gateway's first replies are read
//    (ping, get_config, get_net_status, get_ble_devices — field round 18:
//    0x08 five seconds after connecting, right after the get_config ACK) is
//    reconnected like steps 7/8 ([connectPersistence], 「連線中（第 n 次）」)
//    and the reads continue; once the connect gives up, 「藍牙已連線，正在
//    確認…」 is not left beside 「與閘道器的連線已中斷」.
// 2. 「結束目前配置？」 says what 結束 does: a temporary 「不是這台？」
//    binding is put back (「還原為改選前的狀態」), done PTUs are kept.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp;

/// Demo gateway whose phone link drops (GATT disconnected) when one of
/// [dropOn] is sent: each entry once, in order; [dropAlways] on every send.
class _ConfirmDropLink extends DroppingLink {
  final dropOn = <String>[];
  String? dropAlways;
  final sent = <String>[];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    sent.add(op);
    if (op == dropAlways || (dropOn.isNotEmpty && dropOn.first == op)) {
      if (op != dropAlways) dropOn.removeAt(0);
      down = true;
      throw const GatewayFailure('disconnected');
    }
    return super.command(op, params);
  }
}

/// At the gateway list (step 2), nothing connected yet.
Future<(ProviderContainer, CommissioningController)> _atList(
  _ConfirmDropLink fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  return (container, c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPersistence;
  late Duration keepGap;
  setUp(() {
    keepPersistence = connectPersistence;
    keepGap = connectRetryGap;
    connectRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() {
    connectPersistence = keepPersistence;
    connectRetryGap = keepGap;
  });

  group('1. step 2 link drop while confirming', () {
    for (final op in ['ping', 'get_config', 'get_net_status']) {
      test('drop at $op: reconnects by itself and finishes step 2', () async {
        final fake = _ConfirmDropLink()..dropOn.add(op);
        final (container, c) = await _atList(fake);
        addTearDown(container.dispose);
        final seen = <CommissionState>[];
        container.listen(commissionProvider, (_, s) => seen.add(s));
        final before = fake.connects;
        await c.connect(container.read(commissionProvider).peers.single);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.busy, isFalse);
        expect(s.step, 2);
        expect(fake.connects - before, 2);
        expect(s.message, '已連線。先做網路體檢，再設定身份與 Wi-Fi。');
        // The reads start over on the new link and complete.
        expect(fake.sent.where((o) => o == op), hasLength(2));
        expect(fake.sent.last, 'get_net_status');
        expect(s.net, isNotEmpty);
        expect(s.config['gateway_uid'], isNotNull);
        final texts = seen.map((s) => s.message).toList();
        expect(texts, contains(connectingAttemptText(2)));
        // 「正在確認」 again after the reconnect, then the result.
        expect(
          texts.lastIndexOf(linkConfirmingText),
          greaterThan(texts.indexOf(connectingAttemptText(2))),
        );
        expect(seen.where((s) => s.error != null), isEmpty);
      });
    }

    test(
      'drop at get_ble_devices (station set up): reconnects, PTUs read',
      () async {
        final fake = _ConfirmDropLink();
        fake.config.addAll({
          'fleet_joined': true,
          'site_id': 1,
          'gateway_id': 1,
        });
        fake.dropOn.add('get_ble_devices');
        final (container, c) = await _atList(fake);
        addTearDown(container.dispose);
        final before = fake.connects;
        await c.connect(container.read(commissionProvider).peers.single);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 2);
        expect(fake.connects - before, 2);
        expect(fake.sent.where((o) => o == 'get_ble_devices'), hasLength(2));
        expect(s.config['choose_station'], isTrue);
        expect(s.ptus, isNotEmpty);
        expect(s.message, startsWith('已連線，此閘道器已有站點設定'));
      },
    );

    test('two drops in a row: 第 3 次 connects and continues', () async {
      final fake = _ConfirmDropLink()
        ..dropOn.addAll(['get_config', 'get_net_status']);
      final (container, c) = await _atList(fake);
      addTearDown(container.dispose);
      final texts = <String>[];
      container.listen(commissionProvider, (_, s) => texts.add(s.message));
      final before = fake.connects;
      await c.connect(container.read(commissionProvider).peers.single);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 2);
      expect(fake.connects - before, 3);
      expect(texts, contains(connectingAttemptText(3)));
    });

    test('still dropping after the budget: error only, no 「正在確認」 beside '
        'it, failure log in 詳細資訊', () async {
      final fake = _ConfirmDropLink()..dropAlways = 'get_config';
      final (container, c) = await _atList(fake);
      addTearDown(container.dispose);
      connectPersistence = const Duration(milliseconds: 80);
      final seen = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => seen.add(s));
      final before = fake.connects;
      await c.connect(container.read(commissionProvider).peers.single);
      final s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.error, const GatewayFailure('disconnected').message);
      expect(s.message, isEmpty);
      expect(fake.connects - before, greaterThan(1));
      expect(s.errorDetail, contains('連線失敗紀錄：第 1 次：disconnected'));
      // Never both at once.
      expect(
        seen.where(
          (s) =>
              s.error != null &&
              (s.message == linkConfirmingText ||
                  s.message.startsWith('連線中（第')),
        ),
        isEmpty,
      );
    });

    test('cancel during the reconnect: 已取消, no error', () async {
      final fake = _ConfirmDropLink()..dropAlways = 'get_config';
      final (container, c) = await _atList(fake);
      addTearDown(container.dispose);
      connectPersistence = const Duration(seconds: 30);
      connectRetryGap = const Duration(milliseconds: 20);
      final running = c.connect(
        container.read(commissionProvider).peers.single,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(container.read(commissionProvider).busy, isTrue);
      await c.cancel();
      await running;
      final s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.error, isNull);
      expect(s.message, startsWith('已取消'));
    });

    test('isLinkDrop: phone link only, not a gateway reply', () {
      expect(isLinkDrop(const GatewayFailure('disconnected')), isTrue);
      expect(isLinkDrop(const GatewayFailure('not_connected')), isTrue);
      expect(isLinkDrop(const GatewayFailure('timeout')), isFalse);
      expect(
        isLinkDrop(gatewayAckFailure({'error': 'not_connected'})),
        isFalse,
      );
    });

    testWidgets('page after giving up: the error banner without 「藍牙已連線，'
        '正在確認…」', (tester) async {
      final fake = _ConfirmDropLink()..dropAlways = 'get_config';
      final container = await pumpApp(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      connectPersistence = const Duration(milliseconds: 80);
      await tester.runAsync(
        () => c.connect(container.read(commissionProvider).peers.single),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('error-banner')), findsOneWidget);
      expect(find.textContaining('與閘道器的連線已中斷，請靠近後重新連線。'), findsOneWidget);
      expect(find.textContaining('正在確認閘道器回應'), findsNothing);
      expect(find.textContaining('連線中（第'), findsNothing);
    });
  });

  group('2. 結束目前配置？ text', () {
    test('a temporary binding is put back; done PTUs are kept', () {
      expect(
        endFlowConfirmText(2, restoresBind: true),
        '結束後會把閘道器的 PTU 綁定還原為改選前的狀態；已完成的 2 台保留。',
      );
      expect(
        endFlowConfirmText(0, restoresBind: true),
        startsWith('結束後會把閘道器的 PTU 綁定還原為改選前的狀態'),
      );
      expect(endFlowConfirmText(0, restoresBind: true), isNot(contains('0 台')));
      expect(endFlowConfirmText(3), '已完成的 3 台會保留在閘道器。');
      // No claim that the gateway keeps its settings (it may not).
      expect(endFlowConfirmText(0), isNot(contains('維持')));
      expect(endFlowConfirmText(0), isNot(contains('0 台')));
    });

    test('restores only a binding that differs from the one before', () {
      const a = 'AA:BB:CC:00:00:01';
      const b = 'AA:BB:CC:00:00:02';
      const s = CommissionState();
      expect(endFlowRestoresBind(s), isFalse);
      expect(endFlowRestoresBind(s.copy(tempBoundMac: a)), isTrue);
      expect(
        endFlowRestoresBind(s.copy(tempBoundMac: a, tempRestoreMac: b)),
        isTrue,
      );
      // Switched back to the binding from before: nothing to undo.
      expect(
        endFlowRestoresBind(
          s.copy(tempBoundMac: a, tempRestoreMac: a.toLowerCase()),
        ),
        isFalse,
      );
    });
  });
}
