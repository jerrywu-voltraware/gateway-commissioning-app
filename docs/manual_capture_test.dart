// Documentation rendering only. All services use local fixture data.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/application/verify_feed.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/backend_key.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';
import '../test/support/real_fonts.dart';

const mac = 'AA:BB:CC:DD:00:01';
const peer = GatewayPeer('AA:BB:CC:DD:64:5C', 'GIOS-S50-GW01', -42);
Map<String, dynamic> get cfg => {
  ...DemoSystem().config,
  'fw_version': '1.7.46', 'gateway_uid': 'AABBCCDD645C',
  'site_id': 50, 'gateway_id': 1, 'max_connections': 1,
  'fleet_joined': true, 'mqtt_connected': true, 'upload_paused': false,
  'wifi_ssid': 'Site-WiFi', 'direct_bind_mac': mac,
};
const net = {'wifi_state': 'got_ip', 'ssid': 'Site-WiFi',
  'ip': '192.0.2.20', 'rssi': -40, 'mqtt_connected': true};
const ptus = [{'mac': mac, 'rssi': -35, 'connected': true, 'device_number': 1}];

class GuideApi extends DemoSystem {
  @override
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    if (path.endsWith('/support')) {
      return {'state': 'waiting_field', 'revision': 2,
        'request_at': '2026-10-04T08:00:00+08:00', 'events': [
          {'action': 'instruct', 'role': 'backend', 'step': 6,
           'at': '2026-10-04T08:01:00+08:00',
           'message': '請確認工單站號。若本次在站 50 施工，請按「使用此站點」。',
           'context': {'gateway_mac': 'AABBCCDD645C','site_id': 50,'gateway_id': 1}}
        ]};
    }
    return super.request(method, path, body);
  }
}

class Snapshot extends CommissioningController {
  Snapshot(this.initial);
  final CommissionState initial;
  @override
  CommissionState build() { super.build(); return initial; }
  @override
  Future<void> restore() async {}
  @override
  bool get fieldHelpAvailable => true;
  @override
  Future<bool> holdPeer(GatewayPeer peer) async => true;
}

class MarkPainter extends CustomPainter {
  MarkPainter(this.rects);
  final List<Rect> rects;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFF09B18)
      ..style = PaintingStyle.stroke..strokeWidth = 2.8;
    for (final r in rects) {
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(3), const Radius.circular(7)), p);
    }
  }
  @override
  bool shouldRepaint(MarkPainter old) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadRealFonts();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('monospace')..addFont(File('C:/Windows/Fonts/consola.ttf').readAsBytes().then(ByteData.sublistView))).load();
  });

  testWidgets('render the current interface for the field manual', (tester) async {
    tester.view.physicalSize = const Size(420, 820);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('voltraware/wifi'), (call) async => call.method == 'current' ? 'Site-WiFi' : null);
    messenger.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async => call.method == 'requestPermissions' ? {5: 1} : 1);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    ProviderContainer? container;
    final marks = ValueNotifier<List<Rect>>([]);
    Future<void> page(CommissionState state) async {
      await tester.pumpWidget(const SizedBox());
      container?.dispose();
      SharedPreferences.setMockInitialValues({'gateway_topology': 'direct'});
      final fake = GuideApi();
      container = ProviderContainer(overrides: [
        commissionProvider.overrideWith(() => Snapshot(state)),
        linkProvider.overrideWithValue(fake), apiProvider.overrideWithValue(fake),
        backendKeyProvider.overrideWithValue('documentation-fixture'),
      ]);
      await tester.runAsync(() async => await container!.read(topologyProvider.notifier).ready);
      marks.value = [];
      await tester.pumpWidget(UncontrolledProviderScope(container: container!, child:
        MaterialApp(debugShowCheckedModeBanner: false,
          theme: withRealFonts(gatewayTheme(Brightness.light)),
          builder: (context, child) => RepaintBoundary(key: const Key('guide-capture'),
            child: MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Stack(children: [child!, Positioned.fill(child: IgnorePointer(child:
                ValueListenableBuilder<List<Rect>>(valueListenable: marks,
                  builder: (_, value, __) => CustomPaint(painter: MarkPainter(value)))))]))),
          home: CommissioningPage(themeMode: ThemeMode.light, onThemeChanged: (_) {}))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    Future<void> shot(String name, [List<Finder> highlight = const []]) async {
      marks.value = highlight.where((f) => f.evaluate().isNotEmpty).map((f) => tester.getRect(f.first)).where((r) => r.top >= 0 && r.bottom <= 820).toList();
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('guide-capture')));
        final img = await boundary.toImage(pixelRatio: 2);
        final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
        await Directory('docs/field_guide_assets').create(recursive: true);
        await File('docs/field_guide_assets/$name.png').writeAsBytes(bytes.buffer.asUint8List());
        img.dispose();
      });
      marks.value = [];
    }
    CommissionState ready(int step, {bool identified = false}) => CommissionState(
      step: step, peer: peer, config: cfg, net: net, ptus: ptus,
      selected: const {mac}, loggedIn: true, online: true, checkPassed: true,
      identifiedMac: identified ? mac : null,
      directRaw: const {'state': 'connected', 'ptu_mac': mac, 'ptu_rssi': -35,
        'min_rssi': -55, 'select_reason': 'bound', 'bound_mac': mac},
    );

    await page(const CommissionState());
    await shot('01_start', [find.widgetWithText(FilledButton, '檢查並開始')]);
    await tester.tap(find.byKey(const Key('topology-menu'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topology-settings-menu'))); await tester.pumpAndSettle();
    await shot('02_mode', [find.byKey(const Key('topology-option-direct'))]);

    await page(const CommissionState(step: 1, peers: [peer], loggedIn: true));
    await shot('03_gateway', [find.widgetWithText(FilledButton, '藍牙連線')]);
    await tester.tap(find.text('藍牙連線')); await tester.pumpAndSettle();
    await shot('04_connected', [find.byTooltip('閃燈辨識'), find.widgetWithText(FilledButton, '開始開通')]);

    await page(CommissionState(step: 2, peer: peer, config: {...cfg, 'wifi_only': true}, net: net, checkPassed: true, loggedIn: true));
    await tester.tap(find.text('使用手機目前的 Wi-Fi')); await tester.pumpAndSettle();
    await shot('05_wifi', [find.text('使用手機目前的 Wi-Fi'), find.byTooltip('顯示密碼')]);

    await page(CommissionState(step: 2, peer: peer, config: {...cfg, 'choose_station': true}, net: net, checkPassed: true, loggedIn: true));
    await shot('06_station', [find.byKey(const Key('station-use')), find.byKey(const Key('station-change'))]);

    await page(ready(4));
    await shot('07_identify', [find.byKey(const Key('direct-identify')), find.byKey(const Key('direct-more'))]);
    await page(ready(4, identified: true));
    await shot('08_confirm', [find.byKey(const Key('direct-confirm'))]);

    await page(CommissionState(step: 6, peer: peer, config: cfg, net: net,
      ptus: ptus, selected: const {mac}, assignedOk: const {mac}, busy: true,
      loggedIn: true, online: true, checkPassed: true, seconds: 120,
      message: '資料驗證 #1 1/3', verifyCounts: const {1: 1}, verifyFeed: [
        VerifyFeedEntry(serial: 2, poll: 2, id: 1, mac: mac,
          ts: DateTime(2026,10,4,8,30,5), inputMv: 54200,inputMa: 2300,tempC: 36,
          ok: true, counted: true, count: 1),
        VerifyFeedEntry(serial: 1, poll: 1, id: 1, mac: mac,
          ts: DateTime(2026,10,4,8,30),ok: false,count: 0,reasons: const ['error_num=1']),
      ]));
    await shot('09_verify', [find.textContaining('查看未計入資料')]);

    await page(CommissionState(step: 7, peer: peer, config: cfg, net: net,
      ptus: ptus, selected: const {mac}, assignedOk: const {mac}, verified: true,
      online: true, loggedIn: true, checkPassed: true, uploadIntervalMs: 30000,
      backendSeenAt: DateTime.now()));
    await shot('10_done', [find.byKey(const Key('done-label'))]);

    await page(CommissionState(step: 2, peer: peer, config: {...cfg, 'choose_station': true}, net: net, checkPassed: true, loggedIn: true));
    container!.read(fieldHelpProvider.notifier).set(const FieldHelpState(phase: FieldHelpPhase.sent, sessionId: 'manual-preview'));
    await tester.tap(find.byTooltip('請後台協助')); await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await shot('11_help', [find.widgetWithText(FilledButton, '已解決'), find.widgetWithText(TextButton, '仍需協助')]);
    await tester.pumpWidget(const SizedBox()); container?.dispose();
    marks.dispose();
    tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
}
