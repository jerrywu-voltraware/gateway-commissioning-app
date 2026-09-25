import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';

/// assign_device_id fails [failures] times per MAC (-1 = always) with the
/// firmware's BLE 133 ack.
class FlakyAssign extends DemoSystem {
  final failures = <String, int>{};
  final commands = <String>[];
  final assigns = <String>[];
  final disabled = <String>[];
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add(op);
    if ((op == 'set_ble_enabled' || op == 'set_data_upload') &&
        params['enabled'] == false) {
      disabled.add(op);
    }
    if (op == 'assign_device_id') {
      final mac = params['mac'].toString();
      assigns.add(mac);
      final left = failures[mac] ?? 0;
      if (left != 0) {
        if (left > 0) failures[mac] = left - 1;
        throw gatewayAckFailure({
          'mac': mac,
          'success': false,
          'error': 'connection/service discovery timeout',
        });
      }
    }
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> ready(
  FlakyAssign fake,
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

Future<ProviderContainer> pumpApp(WidgetTester tester, FlakyAssign fake) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a PTU failing once is retried and the batch completes', () async {
    final fake = FlakyAssign();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final mac = fake.devices[1]['mac'].toString();
    fake.failures[mac] = 1;
    await c.configurePtus();
    final s = container.read(commissionProvider);
    expect(s.error, isNull);
    expect(s.step, 6);
    expect(fake.assigns.where((m) => m == mac), hasLength(2));
    expect(fake.disabled, isEmpty);
  });

  test('a PTU failing after retries does not abort the batch', () async {
    final fake = FlakyAssign();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    final bad = fake.devices[1]['mac'].toString();
    fake.failures[bad] = -1;
    await c.configurePtus();
    var s = container.read(commissionProvider);
    expect(s.error, isNull);
    // 1 try + 2 automatic retries.
    expect(fake.assigns.where((m) => m == bad), hasLength(1 + assignRetries));
    // The PTU after the failing one was still assigned.
    expect(fake.assigns.toSet(), hasLength(3));
    expect(fake.config['max_connections'], 5);
    expect(fake.commands, contains('join_fleet'));
    expect(fake.disabled, isEmpty);
    expect(fake.config['ble_enabled'], isNot(false));
    expect(fake.config['upload_paused'], isNot(true));
    expect(s.assignFailed.keys, [bad]);
    expect(s.assignFailed[bad], 'PTU 連線失敗，請確認 PTU 電源與距離');
    expect(s.step, 4);

    // 「重試這 1 台」 only reassigns the failed PTU.
    fake.failures[bad] = 0;
    fake.assigns.clear();
    await c.retryFailedAssign();
    s = container.read(commissionProvider);
    expect(fake.assigns, [bad]);
    expect(s.error, isNull);
    expect(s.assignFailed, isEmpty);
    expect(fake.config['max_connections'], 5);
    expect(s.step, 6);
    expect(s.ptus.map((p) => p['device_number']).toSet(), hasLength(3));
  });

  test('every PTU failing sends neither set_config nor join_fleet', () async {
    final fake = FlakyAssign();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    for (final d in fake.devices) {
      fake.failures[d['mac'].toString()] = -1;
    }
    await c.configurePtus();
    final s = container.read(commissionProvider);
    expect(s.assignFailed, hasLength(3));
    expect(fake.commands, isNot(contains('set_config')));
    expect(fake.commands, isNot(contains('join_fleet')));
    expect(s.step, 4);
    expect(fake.disabled, isEmpty);
  });

  test('cancel during step 8 turns BLE and upload back on', () async {
    final fake = FlakyAssign();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    fake.config['ble_enabled'] = false;
    fake.config['upload_paused'] = true;
    final op = c.configurePtus();
    await Future<void>.delayed(Duration.zero);
    await c.cancel();
    await op;
    expect(fake.disabled, isEmpty);
    expect(fake.config['ble_enabled'], true);
    expect(fake.config['upload_paused'], false);
  });

  test('ack failures read as plain language, raw JSON only in detail', () {
    final f = gatewayAckFailure({
      'mac': 'AA',
      'success': false,
      'error': 'connection/service discovery timeout',
    });
    expect(f.message, 'PTU 連線失敗，請確認 PTU 電源與距離');
    expect(f.detail, contains('"success":false'));
    expect(
      gatewayAckFailure('{"success":false,"error":"status 133"}').message,
      'PTU 連線失敗，請確認 PTU 電源與距離',
    );
    expect(gatewayAckFailure('{broken').message, isNot(contains('{')));
    expect(gatewayAckFailure('assign timeout').message, 'PTU 沒有回應');
    expect(ptuFailureText(const GatewayFailure('timeout')), 'PTU 沒有回應');
    expect(ptuFailureText('gatt error 133'), 'PTU 連線失敗，請確認 PTU 電源與距離');
  });

  test('rescan drops selected PTUs that did not show up again', () async {
    final fake = FlakyAssign();
    final (container, c) = await ready(fake);
    addTearDown(container.dispose);
    expect(container.read(commissionProvider).selected, hasLength(3));
    final gone = fake.devices.removeAt(2)['mac'];
    await c.discover();
    final s = container.read(commissionProvider);
    expect(s.selected, isNot(contains(gone)));
    expect(s.selected, hasLength(2));
    expect(s.absentNotice, absentSelectionText(1));
    await c.discover();
    expect(container.read(commissionProvider).absentNotice, '');
  });

  testWidgets('error banner hides raw ack JSON behind 詳細資訊', (tester) async {
    final fake = FlakyAssign();
    final container = await pumpApp(tester, fake);
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await tester.runAsync(() => c.configureWifi(1, 1, 'Office-2G', 'pw123456'));
    await c.online(skip: true);
    await c.discover();
    final mac = fake.devices.first['mac'].toString();
    fake.failures[mac] = -1;
    await tester.runAsync(() => c.resetAndInclude(mac));
    await tester.pumpAndSettle();
    final s = container.read(commissionProvider);
    expect(s.error, 'PTU 連線失敗，請確認 PTU 電源與距離');
    expect(s.errorDetail, contains('connection/service discovery timeout'));
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.text('詳細資訊'), findsOneWidget);
    expect(find.textContaining('"success"'), findsNothing);
    await tester.tap(find.text('詳細資訊'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"success":false'), findsOneWidget);
  });

  testWidgets('failed PTUs are listed with a 重試這 N 台 button', (tester) async {
    final fake = FlakyAssign();
    final container = await pumpApp(tester, fake);
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await tester.runAsync(() => c.configureWifi(1, 1, 'Office-2G', 'pw123456'));
    await c.online(skip: true);
    await c.discover();
    final bad = fake.devices.last['mac'].toString();
    fake.failures[bad] = -1;
    await tester.runAsync(c.configurePtus);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assign-failed-list')), findsOneWidget);
    expect(find.text('PTU $bad：PTU 連線失敗，請確認 PTU 電源與距離'), findsOneWidget);
    expect(find.text('重試這 1 台'), findsOneWidget);
    fake.failures[bad] = 0;
    await tester.runAsync(() async {
      await tester.tap(find.text('重試這 1 台'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).assignFailed, isEmpty);
    expect(find.text('重試這 1 台'), findsNothing);
  });

  testWidgets('done page shows 掃到 X 台，本機配置 Y 台', (tester) async {
    final fake = FlakyAssign();
    final container = await pumpApp(tester, fake);
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
    final s = container.read(commissionProvider);
    expect(s.step, 7);
    expect(s.results, isNotEmpty);
    expect(s.scannedTotal, 3);
    expect(find.byKey(const Key('commission-summary')), findsOneWidget);
    expect(find.text('掃到 3 台，本機配置 3 台'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
