// Round 11 fixes:
// 1. 「重新連線並繼續」 keeps retrying for [connectPersistence] even when the
//    link drops again right after connecting (during the reconcile); a final
//    failure shows 「重新連線失敗（已嘗試 n 次）…」 and no stale
//    「連線中（第 n 次）」.
// 2. PTUs the gateway finished by itself during the drop are not re-sent.
// 3. The saved progress follows every step change.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';

import 'link_loss_test.dart' show DroppingLink, manualRelinkOnly, ready;

/// Drops the link again on the first [reconcileDrops] get_ble_devices after
/// a reconnect.
class RedropLink extends DroppingLink {
  int reconcileDrops = 0;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (!down && op == 'get_ble_devices' && reconcileDrops > 0) {
      reconcileDrops--;
      down = true;
      throw const GatewayFailure('disconnected');
    }
    return super.command(op, params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Manual 「重新連線並繼續」 path (round 13: automatic otherwise).
  manualRelinkOnly();

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

  group('1. resume reconnect persistence', () {
    test('a drop right after reconnecting is retried, no manual tap', () async {
      final fake = RedropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.dropAfterAssigns = 1;
      await c.configurePtus();
      expect(container.read(commissionProvider).resumePending, isTrue);
      fake.reconcileDrops = 2;
      final messages = <String>[];
      container.listen(commissionProvider, (_, s) => messages.add(s.message));
      await c.resumeAssign();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.reconcileDrops, 0);
      expect(messages, contains(connectingAttemptText(3)));
    });

    test('giving up: attempts in the banner, no stale progress text', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.dropAfterAssigns = 1;
      await c.configurePtus();
      connectPersistence = const Duration(milliseconds: 80);
      fake.failConnect = true;
      await c.resumeAssign();
      final s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.reconnectFailed, isTrue);
      expect(s.error, startsWith('重新連線失敗（已嘗試 '));
      expect(s.error, endsWith('次），請靠近閘道器後再按一次'));
      expect(s.error, isNot(reconnectFailedAttemptsText(1)));
      expect(s.message, isNot(contains('連線中（第')));
      expect(s.message, isEmpty);
    });

    test('attempt text', () {
      expect(reconnectFailedAttemptsText(4), '重新連線失敗（已嘗試 4 次），請靠近閘道器後再按一次');
    });
  });

  test(
    '2. PTUs the gateway finished during the drop are not re-sent',
    () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.dropAfterAssigns = 1;
      await c.configurePtus();
      expect(fake.assigns, [macs[0]]);
      // Meanwhile the gateway connected the rest with their numbers.
      for (final (i, d) in fake.devices.indexed) {
        d['device_number'] = i + 1;
        d['connected'] = true;
        d['notify_enabled'] = true;
      }
      fake.commands.clear();
      await c.resumeAssign();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.commands, isNot(contains('assign_device_id')));
      expect(s.assignedOk, containsAll(macs));
    },
  );

  test('3. a step change is saved before the run ends', () async {
    final fake = _PeekLink();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    await c.configurePtus();
    // At the first assign (step 8, run still going) the saved step is 5.
    expect(fake.savedAtAssign, 5);
  });
}

/// Reads the saved step when the first assign_device_id is sent.
class _PeekLink extends DroppingLink {
  int? savedAtAssign;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'assign_device_id' && savedAtAssign == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(demo ? 'demo_progress' : 'progress');
      savedAtAssign = raw == null
          ? -1
          : (jsonDecode(raw) as Map)['step'] as int;
    }
    return super.command(op, params);
  }
}
