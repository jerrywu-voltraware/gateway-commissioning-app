// 1.0.0+8: the interface trim — no 「客戶」 wording, no demo switch, no
// environment dropdown on the start page, no auto-sync switch in the
// sheet, a two-line gateway tile, the whole PTU MAC on the recent-data
// card, and an AppBar title shown whole at 360 dp.
// 1.0.0+9 (phone screenshots): the title at its normal size (no FittedBox),
// the topology menu inside ⋮, a compact environment chip; the tile's line 2
// one Text with one ellipsis, the badge beside the title; 〔辨識〕 blinks and
// stays on the list; 「最近」 chip on the strongest; light theme by default.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:gateway_commissioning/data/recent_gateways.dart';
import 'package:gateway_commissioning/core/gateway_proximity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
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
  // 1.0.0+10: broadcast — the list listens again when its scan resumes
  // (after 〔辨識〕, or back from 「閘道器狀態」).
  final events = StreamController<List<GatewayPeer>>.broadcast();
  @override
  Stream<List<GatewayPeer>> scanLive() => events.stream;
  @override
  Future<void> stopScan() async {}
}

/// [_LiveLink] whose back office knows 81/1 (`AABBCCDD3A00`, online).
class _FleetLink extends _LiveLink {
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.startsWith('/api/gateways/fleet-status')) {
      return {
        'gateways': [
          {
            'site_id': 81,
            'gateway_id': 1,
            'last_seen_mac': 'AA:BB:CC:DD:3A:00',
            'online': true,
          },
        ],
        'archived_gateways': [],
      };
    }
    return super.request(method, path, body);
  }
}

/// The SDK's Roboto, so Latin text measures as on the phone: the test
/// font gives every glyph 1 em (about twice Roboto's width), which would
/// wrap a line that fits 360 dp on the device. Found through FLUTTER_ROOT
/// or upward from the test runner's executable; skipped when absent.
Future<void> _loadRoboto() async {
  const fonts = 'bin/cache/artifacts/material_fonts';
  Directory? root;
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && Directory('$env/$fonts').existsSync()) {
    root = Directory(env);
  } else {
    var dir = File(Platform.resolvedExecutable).parent;
    while (root == null && dir.path != dir.parent.path) {
      if (Directory('${dir.path}/$fonts').existsSync()) root = dir;
      dir = dir.parent;
    }
  }
  if (root == null) return;
  final loader = FontLoader('Roboto');
  for (final name in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]) {
    final file = File('${root.path}/$fonts/$name');
    if (!file.existsSync()) continue;
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
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
  DemoSystem? fake,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendKeyProvider.overrideWithValue('build-key'),
        envSwitchPolicyProvider.overrideWithValue(policy),
        localBackendProberProvider.overrideWithValue(_Prober()),
        phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
        if (fake != null) ...[
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(GatewayApp)));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The AppBar title's paragraph.
RenderParagraph _titleParagraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(const Key('appbar-title')),
        matching: find.byType(RichText),
      ),
    );

void _titleIsWhole(WidgetTester tester) {
  final title = find.byKey(const Key('appbar-title'));
  expect(title, findsOneWidget);
  final text = tester.widget<Text>(title);
  expect(text.data, appBarTitle);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  // 1.0.0+9: not scaled — no FittedBox above it inside the AppBar.
  expect(
    find.ancestor(of: title, matching: find.byType(FittedBox)),
    findsNothing,
  );
  final paragraph = _titleParagraph(tester);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.text.toPlainText(), appBarTitle);
  // Normal size: titleLarge (22) or, at the least, titleMedium (16).
  expect(paragraph.text.style?.fontSize, greaterThanOrEqualTo(16));
  expect(tester.getSize(title).height, greaterThanOrEqualTo(20));
  expect(tester.getRect(title).right, lessThanOrEqualTo(360));
  expect(tester.takeException(), isNull);
}

/// Every Text on screen, joined (Text.rich included).
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  setUpAll(_loadRoboto);
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

    testWidgets('the sheet has no 客戶 and no auto-sync switch', (tester) async {
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

    test(
      'auto sync is off by default and a saved switch value is ignored',
      () async {
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
      },
    );

    testWidgets('AppBar title is shown whole at 360 dp, normal size, '
        'no FittedBox; topology and theme live in the ⋮ menu', (tester) async {
      _phone(tester);
      await _pumpApp(tester);
      _titleIsWhole(tester);
      expect(find.text('GIOS …'), findsNothing);
      // The compact chip: 12 px label.
      final chipLabel = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('env-chip')),
          matching: find.byType(Text),
        ),
      );
      expect(chipLabel.style?.fontSize, 12);
      // One ⋮ button holds the topology items, 「閘道器狀態…」 and the theme.
      expect(find.byIcon(Icons.hub_outlined), findsNothing);
      await tester.tap(find.byKey(const Key('topology-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topology-heading')), findsOneWidget);
      expect(find.text(GatewayTopology.direct.label), findsOneWidget);
      expect(find.text(GatewayTopology.star.label), findsOneWidget);
      expect(find.byKey(const Key('gateway-status-menu')), findsOneWidget);
      expect(find.text('跟隨系統'), findsOneWidget);
      expect(find.text('淺色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);
      final items = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      final firstTopology = tester.getTopLeft(
        find.ancestor(
          of: find.text(GatewayTopology.direct.label),
          matching: items,
        ),
      );
      final status = tester.getTopLeft(
        find.byKey(const Key('gateway-status-menu')),
      );
      expect(firstTopology.dy, lessThan(status.dy));
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppBar title stays whole at 360 dp on the gateway list '
        '(with the help icon)', (tester) async {
      _phone(tester);
      final fake = DemoSystem();
      await _pumpApp(tester, fake: fake);
      await _tap(tester, find.text('檢查並開始'));
      expect(find.byKey(const ValueKey('demo-gateway')), findsOneWidget);
      _titleIsWhole(tester);
    });

    testWidgets('theme: light when nothing is stored, the stored choice '
        'otherwise', (tester) async {
      expect(defaultThemeMode, ThemeMode.light);
      await _pumpApp(tester);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      await tester.pumpWidget(const SizedBox());
      await _pumpApp(
        tester,
        prefs: {
          'backend_environment': 'production',
          'theme_mode': ThemeMode.dark.index,
        },
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
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
                  onIdentify: (peer) async {
                    identified = peer;
                    return true;
                  },
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
      // 1.0.0+10 — line 1: 「站 81・閘道器 1」 bold (titleMedium) and the
      // signal (bodyMedium) at its right end, one line.
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('gateway-title-AA:BB:CC:DD:3A:02')),
      );
      expect(title.data, gatewayIdText(81, 1));
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(title.style?.fontSize, 16);
      expect(title.maxLines, 1);
      expect(find.text('-34 dBm'), findsOneWidget);
      expect(tester.widget<Text>(find.text('-34 dBm')).style?.fontSize, 14);
      final titleRect = tester.getRect(
        find.byKey(const ValueKey('gateway-title-AA:BB:CC:DD:3A:02')),
      );
      final dbmRect = tester.getRect(find.text('-34 dBm'));
      expect((titleRect.center.dy - dbmRect.center.dy).abs(), lessThan(4));
      expect(dbmRect.left, greaterThanOrEqualTo(titleRect.right));
      // Line 2: the marks as chips (labelMedium, 12 px): 「未配置」 and the
      // back office's short phrase.
      final badge = find.byKey(
        const ValueKey('gateway-unconfigured-AA:BB:CC:DD:3B:02'),
      );
      expect(badge, findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: badge, matching: find.byType(Text)),
            )
            .style
            ?.fontSize,
        12,
      );
      expect(find.text(gatewayUnconfiguredLabel), findsWidgets);
      expect(
        tester.getRect(badge).top,
        greaterThanOrEqualTo(
          tester
              .getRect(
                find.byKey(const ValueKey('gateway-head-AA:BB:CC:DD:3B:02')),
              )
              .bottom,
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('gateway-presence-AA:BB:CC:DD:3A:02')),
          matching: find.text(backendUnknownShort),
        ),
        findsOneWidget,
      );
      // Line 3: 「…3A00」 only — the advertised name is not repeated.
      expect(find.textContaining('GIOS-S81-GW01'), findsNothing);
      expect(find.text('MAC …3A00'), findsNothing);
      expect(find.textContaining('MAC 後 4 碼'), findsNothing);
      expect(find.textContaining('後端狀態未知'), findsNothing);
      for (final (id, line) in [
        ('AA:BB:CC:DD:3A:02', '…3A00'),
        ('AA:BB:CC:DD:3B:02', '…3B00'),
      ]) {
        final detail = find.byKey(ValueKey('gateway-detail-$id'));
        final text = tester.widget<Text>(detail);
        expect(text.data, line);
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: detail, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout();
        expect(painter.width, lessThanOrEqualTo(tester.getSize(detail).width));
        painter.dispose();
        expect(tester.getRect(detail).right, lessThanOrEqualTo(360));
        final marks = tester.getRect(find.byKey(ValueKey('gateway-marks-$id')));
        expect(tester.getRect(detail).top, greaterThanOrEqualTo(marks.bottom));
        final head = tester.getRect(find.byKey(ValueKey('gateway-head-$id')));
        expect(marks.top, greaterThanOrEqualTo(head.bottom));
        expect(head.right, lessThanOrEqualTo(360));
      }
      // Compact: each card at most 88 dp (three short lines), all four
      // inside 800 dp.
      for (final id in [
        'AA:BB:CC:DD:3A:02',
        'AA:BB:CC:DD:3B:02',
        'AA:BB:CC:DD:3C:02',
        'AA:BB:CC:DD:3D:02',
      ]) {
        final tile = find.byKey(ValueKey(id));
        expect(tester.getSize(tile).height, lessThanOrEqualTo(88));
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

    test('backendPresenceShort: 在線／離線／無紀錄／已封存／未知', () {
      const uid = 'AABBCCDDEEFF';
      Map<String, Object?> row(bool? online) => {
        'last_seen_mac': 'AA:BB:CC:DD:EE:FF',
        'online': online,
      };
      expect(backendPresenceShort(uid, [row(true)]), '後端在線');
      expect(backendPresenceShort(uid, [row(false)]), '後端離線');
      expect(backendPresenceShort(uid, const []), '後端無紀錄');
      expect(
        backendPresenceShort(uid, const [], archived: [row(false)]),
        '後端已封存',
      );
      expect(backendPresenceShort(null, [row(true)]), backendUnknownShort);
      expect(
        backendPresenceShort(uid, [row(true), row(true)]),
        backendUnknownShort,
      );
    });

    testWidgets('1.0.0+10 (phone: 81/1 at -41 dBm configured, 80/2 at '
        '-62 new — no 「最近」, 80/2 first): the strongest is 「最近」 and '
        'first in 「最近使用」 even when configured', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({
        'demo_recent_gateways':
            '[{"id":"A0:DD:6C:A3:70:F2","name":"GIOS-S80-GW02",'
            '"uid":"A0DD6CA370F0"},'
            '{"id":"AA:BB:CC:DD:3A:02","name":"GIOS-S81-GW01",'
            '"uid":"AABBCCDD3A00"}]',
      });
      final link = _FleetLink();
      addTearDown(link.events.close);
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(link),
          apiProvider.overrideWithValue(link),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container
            .read(commissionProvider.notifier)
            .prepare('https://example.invalid', 'pw'),
      );
      expect(container.read(commissionProvider).loggedIn, isTrue);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GatewayDiscovery(
                  enabled: true,
                  onConnect: (peer) async {},
                  onIdentify: (peer) async => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      link.events.add(const [
        GatewayPeer('A0:DD:6C:A3:70:F2', 'GIOS-S80-GW02', -62),
        GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -41),
      ]);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('gateway-configured-AA:BB:CC:DD:3A:02')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gateway-nearest-AA:BB:CC:DD:3A:02')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gateway-nearest-A0:DD:6C:A3:70:F2')),
        findsNothing,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('AA:BB:CC:DD:3A:02'))).top,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('A0:DD:6C:A3:70:F2'))).top,
        ),
      );
      // No scan failure: no 〔開啟權限設定〕.
      expect(find.text('開啟權限設定'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the strongest gateway alone carries the 「最近」 chip and '
        'is listed first', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({});
      final link = _LiveLink();
      addTearDown(link.events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GatewayDiscovery(
                  enabled: true,
                  onConnect: (peer) async {},
                  onIdentify: (peer) async => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      link.events.add(const [
        GatewayPeer('AA:BB:CC:DD:3B:02', 'GIOS-S81-GW02', -70),
        GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -40),
      ]);
      await tester.pump();
      final chip = find.byKey(
        const ValueKey('gateway-nearest-AA:BB:CC:DD:3A:02'),
      );
      expect(chip, findsOneWidget);
      expect(find.text(gatewayNearestLabel), findsOneWidget);
      expect(gatewayNearestLabel, '最近');
      expect(
        find.byKey(const ValueKey('gateway-nearest-AA:BB:CC:DD:3B:02')),
        findsNothing,
      );
      // 1.0.0+10: first of the marks on line 2 (under the title and the
      // dBm), filled green.
      final chipRect = tester.getRect(chip);
      final dbm = tester.getRect(find.text('-40 dBm'));
      expect(chipRect.top, greaterThanOrEqualTo(dbm.bottom));
      expect(
        chipRect.left,
        lessThanOrEqualTo(
          tester
              .getRect(
                find.byKey(
                  const ValueKey('gateway-unconfigured-AA:BB:CC:DD:3A:02'),
                ),
              )
              .left,
        ),
      );
      final box = tester.widget<Container>(
        find.descendant(of: chip, matching: find.byType(Container)).first,
      );
      expect((box.decoration as BoxDecoration).color, gatewayNearestColor);
      // First in the list, its card outlined.
      expect(
        tester.getRect(find.byKey(const ValueKey('AA:BB:CC:DD:3A:02'))).top,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('AA:BB:CC:DD:3B:02'))).top,
        ),
      );
      final card = tester.widget<Card>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('AA:BB:CC:DD:3A:02')),
              matching: find.byType(Card),
            )
            .first,
      );
      expect(card.shape, isA<RoundedRectangleBorder>());
      // 30 dB apart: no 「差距小」 warning.
      expect(find.byKey(const Key('gateway-close-hint')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('〔辨識〕 blinks the gateway and stays on the list; the row '
        'tap then chooses it', (tester) async {
      _phone(tester);
      final fake = DemoSystem();
      final container = await _pumpApp(tester, fake: fake);
      await _tap(tester, find.text('檢查並開始'));
      CommissionState read() => container.read(commissionProvider);
      expect(read().step, 1);
      final row = find.byKey(const ValueKey('demo-gateway'));
      expect(row, findsOneWidget);
      // 〔辨識〕: connect → identify (target both) → disconnect, step 1 kept.
      await _tap(tester, find.byKey(const ValueKey('identify-demo-gateway')));
      expect(fake.identifyRequests, [
        {'target': 'both'},
      ]);
      expect(read().step, 1);
      expect(read().peer, isNull);
      expect(read().error, isNull);
      expect(read().busy, isFalse);
      expect(row, findsOneWidget);
      // 1.0.0+11: on its row and in a SnackBar.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('gateway-presence-demo-gateway')),
          matching: find.text(identifiedHint),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('gateway-identified-snack')), findsOneWidget);
      // The hint goes after 3 s.
      await tester.pump(identifiedHintFor + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.textContaining(identifiedHint), findsNothing);
      // The row's tap chooses the gateway and goes on.
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      expect(read().peer?.id, 'demo-gateway');
      expect(read().step, greaterThanOrEqualTo(2));
      expect(fake.identifyRequests.length, 1);
      expect(tester.takeException(), isNull);
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
