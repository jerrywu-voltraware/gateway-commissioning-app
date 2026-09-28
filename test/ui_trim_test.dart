// 1.0.0+8: the interface trim — no 「客戶」 wording, no demo switch, no
// environment dropdown on the start page, no auto-sync switch in the
// sheet, a two-line gateway tile, the whole PTU MAC on the recent-data
// card, and an AppBar title shown whole at 360 dp.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/recent_data_api.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';
import 'package:gateway_commissioning/presentation/environment_switch.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200, version: '1.1.0');
}

class _LiveLink extends DemoSystem implements GatewayScanner {
  final events = StreamController<List<GatewayPeer>>();
  @override
  Stream<List<GatewayPeer>> scanLive() => events.stream;
  @override
  Future<void> stopScan() async {}
}

void _phone(WidgetTester tester, {Size size = const Size(360, 800)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {'backend_environment': 'production'},
  EnvSwitchPolicy policy = const EnvSwitchPolicy(
    autoSyncDefault: false,
    confirmGatewaySwitch: true,
  ),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendKeyProvider.overrideWithValue('build-key'),
        envSwitchPolicyProvider.overrideWithValue(policy),
        localBackendProberProvider.overrideWithValue(_Prober()),
        phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(GatewayApp)));
}

/// Every Text on screen, joined (Text.rich included).
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('start page', () {
    testWidgets('no 客戶, no demo switch, no environment dropdown; the '
        'production URL stays as one small line', (tester) async {
      _phone(tester);
      await _pumpApp(tester);
      expect(_allText(tester), isNot(contains('客戶')));
      expect(find.text(productionHintText), findsOneWidget);
      expect(find.text('使用模擬設備練習'), findsNothing);
      expect(find.text('不需要連接閘道器'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(DropdownButtonFormField<BackendEnv>), findsNothing);
      expect(find.text('連線環境'), findsNothing);
      expect(find.byKey(const Key('env-base-line')), findsOneWidget);
      expect(find.text(productionApiBase), findsOneWidget);
      expect(find.byKey(const Key('env-chip')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sheet has no 客戶 and no auto-sync switch', (
      tester,
    ) async {
      _phone(tester);
      await _pumpApp(tester);
      await tester.tap(find.byKey(const Key('env-chip')));
      await tester.pumpAndSettle();
      expect(find.text('切換連線環境'), findsOneWidget);
      expect(find.text(productionSheetHint), findsOneWidget);
      expect(_allText(tester), isNot(contains('客戶')));
      expect(find.byKey(const Key('auto-sync-switch')), findsNothing);
      expect(find.text('連線 Gateway 時自動同步上傳目標'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('auto sync is off by default and a saved switch value is ignored', () async {
      expect(const EnvSwitchPolicy().autoSyncDefault, isFalse);
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'production',
        'auto_sync_upload_target': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(backendEnvProvider.notifier).ready;
      expect(container.read(backendEnvProvider).loaded, isTrue);
      expect(container.read(backendEnvProvider).autoSync, isFalse);
    });

    testWidgets('AppBar title is shown whole at 360 dp (no ellipsis)', (
      tester,
    ) async {
      _phone(tester);
      await _pumpApp(tester);
      final title = find.byKey(const Key('appbar-title'));
      expect(title, findsOneWidget);
      expect(tester.widget<Text>(title).data, appBarTitle);
      expect(find.text('GIOS …'), findsNothing);
      // The whole text is laid out: no line was cut (RenderParagraph
      // reports an overflow when it elides).
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: title, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.text.toPlainText(), appBarTitle);
      // The FittedBox may scale it down, but not below 14 px in effect.
      final shown = tester.getSize(title).width;
      final scale = (shown / paragraph.size.width).clamp(0.0, 1.0);
      final fontSize = paragraph.text.style?.fontSize ?? 22;
      expect(fontSize * scale, greaterThanOrEqualTo(14));
      expect(tester.takeException(), isNull);
    });
  });

  group('gateway list', () {
    testWidgets('two-line tiles: 4 fit a 360x800 screen, whole MAC tail, '
        'icon button identifies, tap selects', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({});
      final link = _LiveLink();
      addTearDown(link.events.close);
      GatewayPeer? connected, identified;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GatewayDiscovery(
                  enabled: true,
                  onConnect: (peer) async => connected = peer,
                  onIdentify: (peer) async => identified = peer,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      link.events.add(const [
        GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -34),
        GatewayPeer('AA:BB:CC:DD:3B:02', 'GIOS-S81-GW02', -50),
        GatewayPeer('AA:BB:CC:DD:3C:02', 'GIOS-S81-GW03', -60),
        GatewayPeer('AA:BB:CC:DD:3D:02', 'GIOS-S81-GW04', -70),
      ]);
      await tester.pump();
      // Line 1: 「站 81・閘道器 1」 bold, the signal, 「未配置」.
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('gateway-title-AA:BB:CC:DD:3A:02')),
      );
      expect(title.data, gatewayIdText(81, 1));
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(find.text('-34 dBm'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('gateway-unconfigured-AA:BB:CC:DD:3B:02')),
        findsOneWidget,
      );
      expect(find.text(gatewayUnconfiguredLabel), findsWidgets);
      // Line 2: name・MAC …3A00 (the Wi-Fi MAC)・backend status.
      expect(find.text('GIOS-S81-GW01'), findsOneWidget);
      expect(find.text('MAC …3A00'), findsOneWidget);
      expect(find.text('MAC …3B00'), findsOneWidget);
      expect(find.textContaining('後端狀態未知'), findsNWidgets(4));
      expect(find.textContaining('MAC 後 4 碼'), findsNothing);
      // Compact: each card at most 72 dp, all four inside 800 dp.
      for (final id in [
        'AA:BB:CC:DD:3A:02',
        'AA:BB:CC:DD:3B:02',
        'AA:BB:CC:DD:3C:02',
        'AA:BB:CC:DD:3D:02',
      ]) {
        final tile = find.byKey(ValueKey(id));
        expect(tester.getSize(tile).height, lessThanOrEqualTo(72));
        expect(tester.getRect(tile).bottom, lessThanOrEqualTo(800));
      }
      // The row's action stops the scanner first (a real async stop).
      Future<void> settle() async {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The identify icon button (tooltip only, no text).
      expect(find.text('辨識閘道器'), findsNothing);
      expect(find.byTooltip(identifyGatewayLabel), findsNWidgets(4));
      await tester.tap(
        find.byKey(const ValueKey('identify-AA:BB:CC:DD:3B:02')),
      );
      await settle();
      expect(identified?.id, 'AA:BB:CC:DD:3B:02');
      expect(connected, isNull);
      // Tapping the row selects it.
      await tester.tap(find.byKey(const ValueKey('AA:BB:CC:DD:3A:02')));
      await settle();
      expect(connected?.id, 'AA:BB:CC:DD:3A:02');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    test('gatewayMacTail', () {
      expect(gatewayMacTail(bleId: 'AA:BB:CC:DD:3A:02'), 'MAC …3A00');
      expect(gatewayMacTail(uid: 'AABBCCDD70F0', bleId: 'x'), 'MAC …70F0');
      expect(gatewayMacTail(bleId: 'not-a-mac'), isNull);
    });
  });

  group('recent data', () {
    test('the latest line carries the whole MAC', () {
      final now = DateTime(2026, 9, 29, 0, 52, 33);
      final item = RecentItem.fromJson({
        'ts': now.toIso8601String(),
        'ptu_mac': '905fe89a9600',
        'ptu_state': 'POWER_TRANSFER',
      });
      expect(
        recentLatestLine(item, now),
        'PTU 90:5F:E8:9A:96:00・充電中・00:52:33（0 秒前）',
      );
      expect(recentLatestParts(item, now).$1, 'PTU 90:5F:E8:9A:96:00');
    });
  });
}
