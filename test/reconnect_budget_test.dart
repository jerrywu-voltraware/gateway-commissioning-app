// Verifies the two "align timeout budgets" fixes:
// 1. BleGatewayLink's own worst-case retry time stays comfortably under the
//    commissioning_controller budgets that wrap it (_relinkBudget 50s,
//    reconnectBudget 60s), instead of being cut off mid-retry.
// 2. connect() reports reconnect stages in the documented order.
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';

import 'round6_fixes_test.dart' show StaleAdapterPlatform;
import 'link_loss_test.dart' show DroppingLink, ready;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const peer = GatewayPeer('AA:BB:CC:DD:EE:FF', 'GIOS-S1', -28);

  group('reconnect budgets', () {
    test(
      'worst-case connect time (all retries fail) fits inside the outer '
      'budgets with headroom',
      () {
        final worstCase =
            BleGatewayLink.connectTimeout * (BleGatewayLink.connectRetries + 1) +
            (BleGatewayLink.retryGap + BleGatewayLink.rescanWindow) *
                BleGatewayLink.connectRetries;
        expect(worstCase, lessThanOrEqualTo(const Duration(seconds: 45)));
        expect(worstCase, lessThan(reconnectBudget));
      },
    );

    test('reconnectBudget stays above the link retry budget', () {
      // reconnectBudget wraps _relink, which itself wraps _link.connect;
      // both outer numbers must have headroom over the link's own worst
      // case (documented in ble_gateway_link.dart).
      expect(reconnectBudget, const Duration(seconds: 60));
      expect(reconnectBudget, greaterThan(const Duration(seconds: 45)));
    });

    test(
      'connect() reports stages in order: clear stale, connecting, rescan, '
      'retry, connecting again',
      () async {
        BleGatewayLink.staleSettle = Duration.zero;
        BleGatewayLink.retryGap = Duration.zero;
        BleGatewayLink.rescanWindow = const Duration(milliseconds: 10);
        final platform = StaleAdapterPlatform()..failConnects = 1;
        UniversalBle.setInstance(platform);
        final link = BleGatewayLink();
        final stages = <String>[];
        await link.connect(peer, onStage: stages.add);
        expect(stages, [
          '清除舊連線',
          '正在連線閘道器',
          '找不到閘道器，重新掃描中',
          '第 1 次重試',
          '正在連線閘道器',
        ]);
        await link.disconnect();
      },
    );

    test('every failed attempt is preceded by a rescan stage', () async {
      BleGatewayLink.staleSettle = Duration.zero;
      BleGatewayLink.retryGap = Duration.zero;
      BleGatewayLink.rescanWindow = const Duration(milliseconds: 10);
      final platform = StaleAdapterPlatform()..failConnects = 9;
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      final stages = <String>[];
      await expectLater(
        link.connect(peer, onStage: stages.add),
        throwsA(anything),
      );
      expect(stages.where((s) => s == '找不到閘道器，重新掃描中'), hasLength(2));
      expect(stages.where((s) => s.startsWith('第')), hasLength(2));
      expect(stages.first, '清除舊連線');
    });

    test(
      'resumeAssign surfaces the link\'s reconnect stage into state.message',
      () async {
        final fake = DroppingLink();
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        fake.dropAfterAssigns = 1;
        await c.configurePtus();
        final messages = <String>[];
        container.listen(commissionProvider, (_, s) => messages.add(s.message));
        await c.resumeAssign();
        expect(messages, contains('正在連線閘道器'));
        expect(container.read(commissionProvider).error, isNull);
      },
    );
  });
}
