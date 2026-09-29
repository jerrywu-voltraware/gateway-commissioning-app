import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';

class InventoryGateway extends DemoSystem {
  InventoryGateway() {
    config.addAll({'fleet_joined': true, 'site_id': 80});
  }

  final operations = <String>[];
  final requests = <String>[];
  int phoneScans = 0;
  bool failScan = false;
  List<Map<String, dynamic>> nearby = [
    {'mac': 'AA:BB:CC:00:00:01', 'device_number': 0, 'rssi': -40},
  ];
  List<Map<String, dynamic>> attached = [];

  @override
  Future<List<GatewayPeer>> scan() async {
    phoneScans++;
    return super.scan();
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    operations.add(op);
    if (op == 'scan_ble_discover') {
      if (failScan) throw const GatewayFailure('disconnected');
      return {'devices': nearby.map(Map<String, dynamic>.from).toList()};
    }
    if (op == 'get_ble_devices') {
      return {'devices': attached.map(Map<String, dynamic>.from).toList()};
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    requests.add('$method $path');
    return super.request(method, path, body);
  }
}

Future<(ProviderContainer, CommissioningController)> connect(
  InventoryGateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final controller = container.read(commissionProvider.notifier);
  await controller.prepare('https://example.invalid', '', offline: true);
  await controller.scan();
  await controller.connect(container.read(commissionProvider).peers.single);
  return (container, controller);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Round 15: these cases pin one automatic step 7 reconnect; the retries
  // after a recurring loss (step7RetryGaps) are covered in
  // round15_direct_flow_test.dart.
  late List<Duration> keepGaps;
  setUp(() {
    keepGaps = step7RetryGaps;
    step7RetryGaps = const [];
  });
  tearDown(() => step7RetryGaps = keepGaps);

  test(
    'empty existing station asks 閘道器 to discover before verification',
    () async {
      final fake = InventoryGateway();
      final (container, controller) = await connect(fake);
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).ptus, isEmpty);
      fake.operations.clear();
      await controller.chooseStation(newStation: false);
      final state = container.read(commissionProvider);
      expect(state.step, 4);
      expect(state.ptus.single['mac'], fake.nearby.single['mac']);
      expect(fake.operations, ['scan_ble_discover', 'get_ble_devices']);
      expect(fake.phoneScans, 1, reason: 'phone only scans for the 閘道器');
      expect(fake.requests, isEmpty);
      expect(fake.config['site_id'], 80);
    },
  );

  test(
    '閘道器 results include all seven nearby and connected-only PTUs',
    () async {
      final fake = InventoryGateway();
      fake.nearby = List.generate(
        7,
        (i) => {
          'mac': 'AA:BB:CC:00:00:0${i + 1}',
          'device_number': 0,
          'rssi': -40 - i,
        },
      );
      fake.attached = [
        {'mac': 'aa:bb:cc:00:00:01', 'device_number': 1, 'connected': true},
        {'mac': 'AA:BB:CC:00:00:08', 'device_number': 2, 'connected': true},
      ];
      final (container, controller) = await connect(fake);
      addTearDown(container.dispose);
      await controller.chooseStation(newStation: false);
      final state = container.read(commissionProvider);
      expect(
        state.ptus,
        hasLength(8),
        reason: 'display is not limited to five',
      );
      expect(state.selected, hasLength(5), reason: 'monitoring limit only');
      expect(state.ptus.where((p) => p['connected'] == true), hasLength(2));
      expect(fake.operations, isNot(contains('assign_device_id')));
    },
  );

  test(
    'failed rescan clears stale candidates and leaves retry available',
    () async {
      final fake = InventoryGateway();
      final (container, controller) = await connect(fake);
      addTearDown(container.dispose);
      await controller.chooseStation(newStation: false);
      expect(container.read(commissionProvider).selected, isNotEmpty);
      fake.failScan = true;
      await controller.rescanPtus();
      var state = container.read(commissionProvider);
      expect(state.step, 4);
      expect(state.error, isNotNull);
      expect(state.ptus, isEmpty);
      expect(state.selected, isEmpty);
      expect(state.uploadWatch, UploadWatch.linkLost);
      expect(state.networkReady, isFalse);
      expect(state.message, contains('閘道器掃描未完成'));
      final status = connectionStatus(
        env: const BackendEnvState(),
        state: state,
      );
      expect(status.allOk, isFalse);
      expect(status.gateway.status, contains('藍牙已中斷'));
      expect(status.details.join('\n'), contains('中斷前最後讀到的 MQTT 連線'));
      expect(
        networkCheck(state: state, env: const BackendEnvState()).ready,
        isFalse,
      );
      final before = fake.connects;
      fake.failScan = false;
      await controller.discover();
      state = container.read(commissionProvider);
      expect(state.error, isNull);
      expect(state.ptus, hasLength(1));
      expect(fake.connects, before + 1);
      expect(state.uploadWatch, isNot(UploadWatch.linkLost));
    },
  );

  test(
    'zero candidates return to selection before touching backend monitoring',
    () async {
      final fake = InventoryGateway()..nearby = [];
      final (container, controller) = await connect(fake);
      addTearDown(container.dispose);
      await controller.chooseStation(newStation: false);
      await controller.verify('https://example.invalid', '');
      expect(container.read(commissionProvider).step, 4);
      expect(container.read(commissionProvider).error, isNotNull);
      expect(fake.requests, isEmpty);
    },
  );

  testWidgets(
    'scan disconnect shows stale status and offers reconnect instead of green success',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final fake = InventoryGateway()..failScan = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      container.read(demoProvider.notifier).set(true);
      await tester.pumpAndSettle();
      final controller = container.read(commissionProvider.notifier);
      await controller.prepare('https://example.invalid', '', offline: true);
      await controller.scan();
      await controller.connect(container.read(commissionProvider).peers.single);
      await controller.chooseStation(newStation: false);
      await tester.pumpAndSettle();
      expect(find.text('閘道器正在掃描周邊 PTU，請稍候'), findsNothing);
      expect(find.textContaining('手機與閘道器都已連上'), findsNothing);
      expect(find.textContaining('藍牙已中斷，上傳狀態待確認'), findsOneWidget);
      // Round 12: the automatic reconnect + rescan already ran (and failed
      // again); the banner and the bottom button both offer the retry.
      expect(fake.connects, 2);
      final retry = find.text(rescanAfterLossLabel).first;
      await tester.ensureVisible(retry);
      fake.failScan = false;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.connects, 3);
      expect(find.text('AA:BB:CC:00:00:01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'verification page rescans on 閘道器 and shows returned candidate',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ProviderScope(child: GatewayApp()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      container.read(demoProvider.notifier).set(true);
      await tester.pumpAndSettle();
      final controller = container.read(commissionProvider.notifier);
      await controller.prepare('https://example.invalid', '', offline: true);
      await controller.scan();
      await controller.connect(container.read(commissionProvider).peers.single);
      await tester.runAsync(
        () => controller.configureWifi(1, 1, 'Office-2G', 'password123'),
      );
      await controller.online(skip: true);
      await controller.discover();
      await tester.runAsync(controller.configurePtus);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 6);
      final button = find.text('返回選擇 PTU，由閘道器重新掃描');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 4);
      expect(find.text('AA:BB:CC:00:00:01'), findsOneWidget);
      expect(find.text('由閘道器重新掃描 PTU'), findsOneWidget);
      expect(find.text('開始資料驗證'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
