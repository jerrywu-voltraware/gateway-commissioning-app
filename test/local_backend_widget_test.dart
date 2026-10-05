import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'package:gateway_commissioning/presentation/local_backend_field.dart';
import 'support/l10n.dart';

const healthy = ProbeResult(
  ProbeOutcome.healthy,
  status: 200,
  version: '1.1.0',
);

class FakeProber implements LocalBackendProber {
  FakeProber(this.results);
  final Map<String, ProbeResult> results;
  final probed = <Uri>[];
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async {
    probed.add(base);
    return results[base.host] ??
        const ProbeResult(ProbeOutcome.unreachable, detail: 'refused');
  }
}

class HangingProber extends FakeProber {
  HangingProber(this.pending) : super({});
  final Future<ProbeResult> pending;
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) {
    probed.add(base);
    return pending;
  }
}

Future<void> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {
    'backend_environment': 'local',
    'backend_local_url': 'http://192.168.0.12:18000',
  },
  FakeProber? prober,
  String? ownIp = '192.168.1.23',
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localBackendProberProvider.overrideWithValue(prober ?? FakeProber({})),
        phoneIpv4Provider.overrideWithValue(() async => ownIp),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get hostField => find.byKey(const Key('local-backend-host'));

String hostText(WidgetTester tester) =>
    tester.widget<TextField>(hostField).controller!.text;

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saved local URL is split into IP field and preview', (
    tester,
  ) async {
    await pumpApp(
      tester,
      prefs: {
        'backend_environment': 'local',
        'backend_local_url': 'http://192.168.1.187:18000',
      },
    );
    expect(hostText(tester), '192.168.1.187');
    expect(find.text('將連線：http://192.168.1.187:18000'), findsOneWidget);
    // r31: no prefix / suffix squeezing the IP (「192.168.0.:18000」).
    expect(find.text('http://'), findsNothing);
    expect(find.text(':18000'), findsNothing);
    // 09-28: no password (nor a shown test password); the build carries
    // the backend credential.
    expect(find.textContaining('本地測試密碼'), findsNothing);
    expect(find.textContaining('登入密碼'), findsNothing);

    await tester.enterText(hostField, '8.8.8.8');
    await tester.pump();
    expect(find.textContaining('只接受區域網路位址'), findsOneWidget);

    await tester.enterText(hostField, '10.0.0.5');
    await tester.pump();
    expect(find.text('將連線：http://10.0.0.5:18000'), findsOneWidget);

    // Leaving local mode (1.0.0+8: through the AppBar chip's sheet, the
    // prep page has no dropdown) persists the full URL for the rest of
    // the app.
    expect(find.byType(DropdownButtonFormField<BackendEnv>), findsNothing);
    await tester.tap(find.byKey(const Key('env-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('env-option-production')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_local_url'), 'http://10.0.0.5:18000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('local mode fits a narrow screen without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    for (final label in ['自動尋找', '測試連線', '進階：連接埠 18000']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
    }
    await tapText(tester, '測試連線');
    expect(find.textContaining('✗ 無法連線'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-find fills the single backend', (tester) async {
    final prober = FakeProber({'192.168.1.187': healthy});
    await pumpApp(tester, prober: prober);
    await tapText(tester, '自動尋找');
    expect(hostText(tester), '192.168.1.187');
    expect(find.textContaining('找到本地後端 192.168.1.187'), findsOneWidget);
    expect(prober.probed, hasLength(253));
    expect(prober.probed.every((u) => u.userInfo.isEmpty), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_local_url'), 'http://192.168.1.187:18000');
  });

  testWidgets('auto-find lets the user pick among several', (tester) async {
    await pumpApp(
      tester,
      prober: FakeProber({'192.168.1.187': healthy, '192.168.1.40': healthy}),
    );
    await tapText(tester, '自動尋找');
    expect(find.text('找到 2 台本地後端'), findsOneWidget);
    await tester.tap(find.text('192.168.1.40'));
    await tester.pumpAndSettle();
    expect(hostText(tester), '192.168.1.40');
  });

  testWidgets('auto-find explains when nothing is found', (tester) async {
    await pumpApp(tester);
    await tapText(tester, '自動尋找');
    expect(find.textContaining('在 192.168.1.x 網段找不到本地後端'), findsOneWidget);
    expect(find.textContaining('allow_local_api_lan.ps1'), findsOneWidget);
    expect(hostText(tester), '192.168.0.12');
  });

  testWidgets('auto-find shows progress and can be cancelled', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hang = Completer<ProbeResult>();
    await pumpApp(tester, prober: HangingProber(hang.future));
    await tester.ensureVisible(find.text('自動尋找'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自動尋找'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('正在搜尋 192.168.1.'), findsOneWidget);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('已取消搜尋。'), findsOneWidget);
    expect(find.textContaining('正在搜尋'), findsNothing);
    expect(tester.takeException(), isNull);
    hang.complete(const ProbeResult(ProbeOutcome.timeout));
    await tester.pumpAndSettle();
    expect(hostText(tester), '192.168.0.12');
  });

  testWidgets('auto-find without Wi-Fi IP', (tester) async {
    await pumpApp(tester, ownIp: null);
    await tapText(tester, '自動尋找');
    expect(find.textContaining('找不到手機的 Wi-Fi IP'), findsOneWidget);
  });

  testWidgets('test connection reports success', (tester) async {
    await pumpApp(tester, prober: FakeProber({'192.168.0.12': healthy}));
    await tapText(tester, '測試連線');
    expect(find.text('✓ 已連上本地後端（版本 1.1.0）'), findsOneWidget);
  });

  testWidgets('advanced port changes suffix and saved URL', (tester) async {
    await pumpApp(tester);
    await tapText(tester, '進階：連接埠 18000');
    await tester.enterText(find.byType(TextField).last, '9000');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(find.text('進階：連接埠 9000'), findsOneWidget);
    expect(find.text('將連線：http://192.168.0.12:9000'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_local_url'), 'http://192.168.0.12:9000');
  });

  testWidgets('custom URL field wraps long URLs', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const url =
        'https://very-long-backend-hostname.example-company.com:8443/api';
    await pumpApp(
      tester,
      prefs: {'backend_environment': 'custom', 'backend_custom_url': url},
    );
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, '後端網址'),
    );
    expect(field.maxLines, 3);
    expect(field.keyboardType, TextInputType.url);
    expect(field.controller!.text, url);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English (i18n B2): local back office field', (tester) async {
    useLanguage(AppLanguage.en);
    final host = TextEditingController(text: '192.168.1.187');
    addTearDown(host.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: wrapWithL10n(
          Scaffold(
            body: LocalBackendField(
              hostController: host,
              port: 18000,
              onPortChanged: (_) {},
              onHostPicked: () {},
            ),
          ),
          language: AppLanguage.en,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Auto find'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Advanced: port 18000'), findsOneWidget);
    expect(
      find.text('Will connect to: http://192.168.1.187:18000'),
      findsOneWidget,
    );
  });
}
