// Round 10 fixes:
// 1. Step 2 connect / reconnect keeps retrying 133 and disconnected until
//    [connectPersistence] passes, showing 「連線中（第 n 次）」, and logs every
//    failure type in 詳細資訊.
// 2. Step 9 counts are cumulative: a round without a new row never resets.
// 3. Step 7 while a scan runs: 「掃描中…」, not 「恢復監控」 with 已選 0/5.
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';

import 'link_loss_test.dart' show DroppingLink, ready;

/// The first [failures] connects fail with the listed errors.
class FlakyConnectLink extends DroppingLink {
  final failures = <GatewayFailure>[];
  int attempts = 0;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    attempts++;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    await super.connect(peer, onStage: onStage);
  }
}

const gatt133 = GatewayFailure('ble_error', detail: '133 Unknown Error 133');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. persistent connect', () {
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

    test('133, disconnected, 133 then success: reaches the gateway', () async {
      final flaky = FlakyConnectLink();
      final (container2, c2) = await ready(flaky);
      addTearDown(container2.dispose);
      final peer = container2.read(commissionProvider).peer!;
      await c2.cancel();
      flaky.attempts = 0;
      flaky.failures.addAll([
        gatt133,
        const GatewayFailure('disconnected'),
        gatt133,
      ]);
      final messages = <String>[];
      container2.listen(commissionProvider, (_, s) => messages.add(s.message));
      await c2.connect(peer);
      final s = container2.read(commissionProvider);
      expect(s.error, isNull);
      expect(flaky.failures, isEmpty);
      expect(flaky.attempts, 4);
      expect(messages, contains(connectingAttemptText(2)));
      expect(messages, contains(connectingAttemptText(4)));
    });

    test('still failing after the budget: error with failure log', () async {
      final flaky = FlakyConnectLink();
      final (container, c) = await ready(flaky);
      addTearDown(container.dispose);
      final peer = container.read(commissionProvider).peer!;
      await c.cancel();
      connectPersistence = const Duration(milliseconds: 80);
      flaky.failures.addAll(List.filled(10000, gatt133));
      flaky.attempts = 0;
      await c.connect(peer);
      final s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.error, gatt133.message);
      expect(flaky.attempts, greaterThan(1));
      expect(s.errorDetail, contains('連線失敗紀錄：第 1 次：ble_error 133'));
      expect(s.errorDetail, contains('第 2 次：ble_error 133'));
    });

    test('a non-retryable failure stops at once', () async {
      final flaky = FlakyConnectLink();
      final (container, c) = await ready(flaky);
      addTearDown(container.dispose);
      final peer = container.read(commissionProvider).peer!;
      await c.cancel();
      flaky.failures.add(const GatewayFailure('bluetooth_off'));
      flaky.attempts = 0;
      await c.connect(peer);
      expect(flaky.attempts, 1);
      expect(container.read(commissionProvider).error, isNotNull);
    });

    test('retryable errors', () {
      expect(isRetryableConnect(gatt133), isTrue);
      expect(isRetryableConnect(const GatewayFailure('disconnected')), isTrue);
      expect(isRetryableConnect(const GatewayFailure('cancelled')), isFalse);
      expect(connectFailureType(gatt133), 'ble_error 133');
    });
  });
}
