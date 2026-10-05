import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';

import 'ble_transport_test.dart' show FakePlatform;
import 'link_loss_test.dart'
    show DroppingLink, manualRelinkOnly, ready, pumpApp;

/// Android after Bluetooth off/on: the first [failConnects] connects fail
/// with "Failed to connect".
class StaleAdapterPlatform extends FakePlatform {
  int failConnects = 0;
  final calls = <String>[];
  @override
  Future<void> connect(
    String id, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    calls.add('connect');
    if (failConnects > 0) {
      failConnects--;
      throw UniversalBleException(
        code: UniversalBleErrorCode.unknownError,
        message: 'Failed to connect',
      );
    }
    await super.connect(id);
  }

  @override
  Future<void> disconnect(String id) async {
    calls.add('disconnect');
    await super.disconnect(id);
  }
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Manual 「重新連線並繼續」 path (round 13: automatic otherwise).
  manualRelinkOnly();

  group('1. reconnect after phone Bluetooth off/on', () {
    setUp(() {
      BleGatewayLink.staleSettle = Duration.zero;
      BleGatewayLink.retryGap = Duration.zero;
      BleGatewayLink.rescanWindow = const Duration(milliseconds: 10);
    });
    const peer = GatewayPeer('AA:BB:CC:DD:EE:FF', 'GIOS-S1', -28);

    test('drops the stale client first and retries twice', () async {
      // Round 8: the first failure is retried at once (no drop/rescan),
      // then the rescan retries follow.
      final platform = StaleAdapterPlatform()..failConnects = 3;
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await link.connect(peer);
      expect(platform.calls.first, 'disconnect');
      expect(platform.calls.where((c) => c == 'connect'), hasLength(4));
      // Every retry is preceded by a disconnect of the leftover client.
      expect(
        platform.calls.where((c) => c != 'connect').length,
        greaterThanOrEqualTo(3),
      );
      expect((await link.command('ping'))['message'], '測試成功');
      await link.disconnect();
    });

    test('gives up after 1 + 1 immediate + 2 attempts', () async {
      final platform = StaleAdapterPlatform()..failConnects = 9;
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await expectLater(link.connect(peer), throwsA(anything));
      expect(
        platform.calls.where((c) => c == 'connect'),
        hasLength(2 + BleGatewayLink.connectRetries),
      );
    });
  });

  group('2. reconcile with the gateway', () {
    test('resumeAssign counts what the gateway already took', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.dropAfterAssigns = 1;
      await c.configurePtus();
      expect(container.read(commissionProvider).resumePending, isTrue);
      // The firmware had accepted macs[1] as #2 before the link dropped.
      fake.devices[1]
        ..['device_number'] = 2
        ..['connected'] = true;
      fake.assigns.clear();
      await c.resumeAssign();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.assigns, [macs[2]]);
      expect(s.assignedOk, containsAll(macs));
      expect(s.step, 6);
    });

    test('resumeSaved: reconciled count in the prompt, no resend', () async {
      final fake = DroppingLink();
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      fake.devices[0]
        ..['device_number'] = 1
        ..['connected'] = true;
      // Killed after the gateway took #2 but before the APP saw the ack.
      fake.devices[1]
        ..['device_number'] = 2
        ..['connected'] = true;
      SharedPreferences.setMockInitialValues({
        'demo_progress': jsonEncode({
          'step': 5,
          'site': 1,
          'gateway': 1,
          'peer': 'demo-gateway',
          'peer_name': 'GIOS-S1-GW01',
          'selected': macs,
          'done': {macs[0]: 1},
          'assignments': [],
        }),
      });
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      final messages = <String>[];
      container.listen(commissionProvider, (_, s) => messages.add(s.message));
      await c.restore();
      await c.resumeSaved();
      expect(messages, contains(resumeText(5, [1, 2], 1)));
      expect(fake.assigns, [macs[2]]);
    });

    test(
      'a PTU checked after a link loss is saved with the progress',
      () async {
        final fake = DroppingLink();
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        final macs = fake.devices.map((d) => d['mac'].toString()).toList();
        c.select(macs[2], false);
        fake.dropAfterAssigns = 1;
        await c.configurePtus();
        c.select(macs[2], true);
        await flush();
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(prefs.getString('demo_progress')!) as Map;
        expect(saved['selected'], contains(macs[2]));
      },
    );
  });

  group('3. max_connections never shrinks', () {
    test('star mode with 3 PTUs still opens 5 slots', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      expect(container.read(commissionProvider).step, 6);
      expect(fake.config['max_connections'], 5);
    });

    test('direct mode is 1, star mode 5', () async {
      expect(monitorLimit(false), 1);
      expect(monitorLimit(true), 5);
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await container
          .read(topologyProvider.notifier)
          .setTopology(GatewayTopology.direct);
      await c.discover();
      await c.configurePtus();
      expect(fake.config['max_connections'], 1);
    });
  });

  group('4. link-loss banner carries the action', () {
    testWidgets('resume button inside the red banner; bottom button too', (
      tester,
    ) async {
      final fake = DroppingLink();
      final container = await pumpApp(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await tester.runAsync(
        () => c.configureWifi(1, 1, 'Office-2G', 'pw123456'),
      );
      // Provisioning logs in; this fixture intentionally continues offline.
      c.backendChanged('https://offline-fixture.invalid');
      await c.online(skip: true);
      await c.discover();
      fake.dropAfterAssigns = 1;
      await tester.runAsync(c.configurePtus);
      await tester.pumpAndSettle();
      final banner = find.byKey(const Key('error-banner'));
      expect(
        find.descendant(of: banner, matching: find.text(phoneLinkLostText)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.byKey(const Key('ptu-resume')),
        ),
        findsOneWidget,
      );
      expect(find.text('重新連線並繼續（剩 2 台）'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('ptu-resume')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 6);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('5. finished run is not offered as a resume', () {
    test('completed progress is a 上一台已完成 note (round 29), never a '
        'resume', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.verify('https://example.invalid', '');
      expect(container.read(commissionProvider).step, 7);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('demo_progress')!) as Map;
      expect(saved['completed'], isTrue);

      final again = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(again.dispose);
      final c2 = again.read(commissionProvider.notifier);
      await c2.restore();
      final s = again.read(commissionProvider);
      expect(s.savedResume, isFalse);
      expect(s.savedProgress, isFalse);
      expect(s.lastDone, lastDoneText(1, 1));
      expect(s.message, isNot(contains('已保留先前進度')));
      await c2.clearCompleted();
      expect(prefs.getString('demo_progress'), isNull);
    });
  });

  test('6. install report is ordered by PTU number', () {
    final rows = byDeviceNumber([
      {'device_number': 2, 'mac': 'b'},
      {'device_number': 1, 'mac': 'a'},
      {'device_number': 5, 'mac': 'e'},
      {'device_number': 3, 'mac': 'c'},
    ]);
    expect(rows.map((r) => r['device_number']), [1, 2, 3, 5]);
  });

  test('7. recent heartbeat skips 正在確認資料上傳', () {
    final now = DateTime(2026, 9, 25, 12);
    final base = CommissionState(loggedIn: true, message: verifiedText);
    expect(showHealthPending(base, now: now), isTrue);
    expect(
      showHealthPending(
        base.copy(backendSeenAt: now.subtract(const Duration(seconds: 5))),
        now: now,
      ),
      isFalse,
    );
    expect(
      showHealthPending(
        base.copy(backendSeenAt: now.subtract(const Duration(minutes: 2))),
        now: now,
      ),
      isTrue,
    );
  });
}
