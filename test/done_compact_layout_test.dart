import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/install_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';

import 'support/real_fonts.dart';

const _mac = '9F:D3:E1:EF:96:00';

ThemeData _phoneTheme() {
  final theme = withRealFonts(
    gatewayTheme(Brightness.light).copyWith(platform: TargetPlatform.iOS),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(
      fontFamilyFallback: [...realFontFallback, 'GiosTestSymbols'],
    ),
  );
}

CommissionState _done({
  int site = 50,
  int gateway = 1,
  bool deferred = false,
  bool star = false,
  bool seen = true,
}) => CommissionState(
  step: 7,
  peer: const GatewayPeer('test-gateway', 'GIOS-S50-GW01', -42),
  loggedIn: true,
  online: true,
  verified: !deferred,
  checkPassed: true,
  message: deferred ? '' : '資料持續更新',
  messageKind: deferred ? MessageKind.none : MessageKind.dataStreaming,
  backendSeenAt: seen ? DateTime.now() : null,
  ptuDeferred: deferred,
  uploadIntervalMs: 300000,
  config: {
    ...DemoSystem().config,
    'fleet_joined': true,
    'mqtt_connected': true,
    'site_id': site,
    'gateway_id': gateway,
    'max_connections': star ? 5 : 1,
    'upload_paused': false,
    'direct_bind_mac': deferred || star ? '' : _mac,
  },
  net: const {
    'wifi_state': 'got_ip',
    'ip': '192.0.2.2',
    'ssid': 'Test-2.4G',
    'rssi': -40,
  },
  ptus: deferred
      ? const []
      : const [
          {'mac': _mac, 'rssi': -27, 'connected': true, 'device_number': 1},
        ],
  scannedTotal: deferred ? 0 : 1,
  assignedOk: deferred ? const {} : const {_mac},
  selected: deferred ? const {} : const {_mac},
);

class _SnapshotController extends CommissioningController {
  _SnapshotController(this.initial);
  final CommissionState initial;
  int healthRequests = 0, repairs = 0;
  final finishes = <bool>[];

  @override
  CommissionState build() {
    super.build();
    return initial;
  }

  @override
  bool get fieldHelpAvailable => true;

  @override
  Future<void> restore() async {}

  void show(CommissionState snapshot) => state = snapshot;

  @override
  Future<void> refreshHealth() async {
    healthRequests++;
  }

  @override
  Future<void> repair({String? base, String? password}) async {
    repairs++;
  }

  @override
  Future<void> finishDone({bool next = false}) async {
    finishes.add(next);
  }
}

class _Reporter extends FieldReporter {
  _Reporter(GatewayApi api) : super(api: api, enabled: false);
  int retries = 0;

  @override
  Future<void> resendInstallReport() async {
    retries++;
  }
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

Future<(_SnapshotController, ProviderContainer, _Reporter)> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1.3,
  CommissionState? snapshot,
  GatewayTopology topology = GatewayTopology.direct,
  InstallReportStatus? report,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  SharedPreferences.setMockInitialValues({});
  final fake = DemoSystem();
  final reporter = _Reporter(fake);
  final controller = _SnapshotController(snapshot ?? _done());
  final container = ProviderContainer(
    overrides: [
      commissionProvider.overrideWith(() => controller),
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      fieldReporterProvider.overrideWith((ref) {
        ref.onDispose(reporter.dispose);
        return reporter;
      }),
      localBackendProberProvider.overrideWithValue(_Prober()),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() async {
    final settings = container.read(topologyProvider.notifier);
    await settings.ready;
    await settings.setTopology(topology);
  });
  container
      .read(installReportProvider.notifier)
      .set(
        report ??
            InstallReportStatus(
              phase: InstallReportPhase.sent,
              sentAt: DateTime(2026, 10, 2, 19, 5),
            ),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: _phoneTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const Key('done-compact-preview'),
            child: child!,
          ),
        ),
        home: CommissioningPage(
          themeMode: ThemeMode.light,
          onThemeChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, container, reporter);
}

Finder _key(String value) => find.byKey(Key(value));

String _text(WidgetTester tester, String key) {
  final text = tester.widget<Text>(_key(key));
  return text.data ?? text.textSpan!.toPlainText();
}

void _insideBody(WidgetTester tester, String key) {
  final viewport = tester.getRect(
    find
        .ancestor(of: _key('done-summary'), matching: find.byType(Viewport))
        .first,
  );
  final rect = tester.getRect(_key(key));
  expect(
    viewport.contains(rect.topLeft),
    isTrue,
    reason: '$key top: $rect / $viewport',
  );
  expect(
    viewport.contains(rect.bottomRight - const Offset(0.1, 0.1)),
    isTrue,
    reason: '$key bottom: $rect / $viewport',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(tester.getRect(_key('done-actions')).top),
  );
}

void _singleLine(WidgetTester tester, String key) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: _key(key), matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: key);
  final text = _text(tester, key);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  // Chinese and Latin fallback runs can have different ascent values even
  // on the same line. Their vertical glyph boxes must still overlap.
  expect(boxes, isNotEmpty);
  expect(
    boxes.map((box) => box.top).reduce(math.max),
    lessThan(boxes.map((box) => box.bottom).reduce(math.min)),
    reason: '$key must not split into lines',
  );
}

void _bottomActions(WidgetTester tester) {
  final bar = _key('done-actions');
  expect(tester.getRect(bar).height, lessThanOrEqualTo(100));
  expect(
    find.descendant(
      of: bar,
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    ),
    findsNWidgets(2),
  );
  expect(find.descendant(of: bar, matching: _key('done-recent')), findsNothing);
  for (final key in ['done-next', 'done-finish']) {
    expect(find.descendant(of: bar, matching: _key(key)), findsOneWidget);
    final rect = tester.getRect(_key(key));
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(_key(key).hitTestable(), findsOneWidget);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(await loadRealFonts(), isTrue);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    var loadedMono = false;
    for (final path in [
      '/System/Library/Fonts/Menlo.ttc',
      'C:/Windows/Fonts/consola.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    ]) {
      final font = File(path);
      if (!font.existsSync()) continue;
      await (FontLoader(
        'monospace',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      loadedMono = true;
      break;
    }
    expect(loadedMono, isTrue);
    // iOS resolves checkmarks through system symbol fallback. Flutter tests
    // have no such fallback, so load a platform symbol font for the preview.
    for (final path in [
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      'C:/Windows/Fonts/seguisym.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ]) {
      final font = File(path);
      if (!font.existsSync()) continue;
      await (FontLoader(
        'GiosTestSymbols',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      break;
    }
  });

  for (final size in [const Size(393, 852), const Size(360, 640)]) {
    for (final scale in size.height > 740 ? [1.0, 1.3, 1.6] : [1.0, 1.3]) {
      testWidgets(
        'first screen has identity, upload and report at $size / $scale',
        (tester) async {
          final preview = size.width == 393 && scale == 1.3
              ? Platform.environment['GIOS_DONE_PREVIEW']
              : null;
          final oldShadows = debugDisableShadows;
          if (preview != null) debugDisableShadows = false;
          try {
            final (_, container, reporter) = await _pumpPage(
              tester,
              size: size,
              scale: scale,
            );
            expect(tester.takeException(), isNull);
            for (final key in [
              'done-site-id',
              'done-gateway-id',
              'done-ptu-mac',
              'done-upload',
              'install-report-status',
            ]) {
              _insideBody(tester, key);
            }
            _singleLine(tester, 'done-site-id');
            _singleLine(tester, 'done-gateway-id');
            _bottomActions(tester);
            expect(_text(tester, 'done-site-id'), '站點 50');
            expect(_text(tester, 'done-gateway-id'), '閘道器 1');
            expect(_text(tester, 'done-upload'), '✓ 資料持續上傳（正式站）');
            expect(
              _text(tester, 'install-report-status-text'),
              '報告已送到後台 19:05',
            );
            expect(_key('done-message'), findsNothing);
            expect(_key('done-upload-rate'), findsNothing);

            if (preview != null) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                _key('done-compact-preview'),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 2);
                try {
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
                } finally {
                  image.dispose();
                }
              });
            }

            container
                .read(installReportProvider.notifier)
                .set(
                  const InstallReportStatus(
                    phase: InstallReportPhase.failed,
                    reason: '後台拒收（HTTP 422）',
                  ),
                );
            await tester.pumpAndSettle();
            _insideBody(tester, 'install-report-status');
            _insideBody(tester, 'install-report-resend');
            expect(_key('install-report-resend').hitTestable(), findsOneWidget);
            await tester.tap(_key('install-report-resend'));
            await tester.pumpAndSettle();
            expect(reporter.retries, 1);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            debugDisableShadows = oldShadows;
          }
        },
      );
    }
  }

  for (final scale in [1.0, 1.3, 1.6]) {
    testWidgets(
      'long station/gateway identifiers remain intact at scale $scale',
      (tester) async {
        await _pumpPage(
          tester,
          size: const Size(360, 640),
          scale: scale,
          snapshot: _done(site: 65535, gateway: 255),
        );
        _singleLine(tester, 'done-site-id');
        _singleLine(tester, 'done-gateway-id');
        expect(_text(tester, 'done-site-id'), '站點 65535');
        expect(_text(tester, 'done-gateway-id'), '閘道器 255');
        expect(tester.takeException(), isNull);
        _bottomActions(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'details and advanced checks are expandable; recent data still opens',
    (tester) async {
      final (controller, _, _) = await _pumpPage(tester);
      expect(_key('done-refresh-health'), findsNothing);
      expect(_key('done-repair'), findsNothing);
      expect(_key('connection-status-ok'), findsNothing);
      expect(
        find.descendant(
          of: _key('done-summary'),
          matching: _key('done-recent'),
        ),
        findsOneWidget,
      );

      final detailsHeader = find
          .descendant(
            of: _key('commission-details'),
            matching: find.byType(ListTile),
          )
          .first;
      await tester.ensureVisible(detailsHeader);
      await tester.tap(detailsHeader);
      await tester.pumpAndSettle();
      expect(_key('done-upload-rate'), findsOneWidget);
      expect(_key('connection-status-ok'), findsOneWidget);
      expect(find.textContaining('閘道器只連這台'), findsOneWidget);
      await tester.ensureVisible(detailsHeader);
      await tester.tap(detailsHeader);
      await tester.pumpAndSettle();

      await tester.ensureVisible(_key('done-advanced'));
      await tester.tap(_key('done-advanced'));
      await tester.pumpAndSettle();
      expect(_key('done-calibrate'), findsOneWidget);
      await tester.ensureVisible(_key('done-refresh-health'));
      await tester.tap(_key('done-refresh-health'));
      await tester.pumpAndSettle();
      expect(controller.healthRequests, 1);
      await tester.ensureVisible(_key('done-repair'));
      await tester.tap(_key('done-repair'));
      await tester.pumpAndSettle();
      expect(controller.repairs, 1);

      await tester.scrollUntilVisible(
        _key('done-recent'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(_key('done-recent'));
      await tester.pumpAndSettle();
      expect(find.byType(RecentDataPage), findsOneWidget);
      expect(find.text(recentDataSubtitle(50, 1)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unknown and paused upload stay explicit, health warnings are retained',
    (tester) async {
      final unknown = _done(seen: false);
      final (controller, _, _) = await _pumpPage(
        tester,
        snapshot: unknown.copy(
          config: {...unknown.config, 'mqtt_connected': null},
        ),
      );
      expect(_text(tester, 'done-upload'), contains('未確認'));
      expect(_key('done-upload-confirmed-at'), findsNothing);
      expect(_key('connection-status'), findsOneWidget);

      final paused = _done();
      controller.show(
        paused.copy(config: {...paused.config, 'upload_paused': true}),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, 'done-upload'), contains('上傳已暫停'));
      expect(_text(tester, 'done-upload'), isNot(contains('持續上傳')));
      expect(_key('connection-status'), findsOneWidget);

      for (final online in [false, true]) {
        // Fresh backend data can still contain a PTU fault. An online
        // gateway must not hide the health warning either.
        controller.show(_done().copy(message: '資料有異常，請檢查 PTU', online: online));
        await tester.pumpAndSettle();
        expect(_text(tester, 'done-message'), '資料有異常，請檢查 PTU');
        _insideBody(tester, 'done-message');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('recent upload confirmation is labeled as a confirmation time', (
    tester,
  ) async {
    final stamp = DateTime.now();
    await _pumpPage(
      tester,
      snapshot: _done().copy(
        backendSeenAt: stamp,
        message: verifiedText,
        messageKind: MessageKind.verified,
      ),
    );
    final expected =
        '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}';
    expect(_text(tester, 'done-upload-confirmed-at'), '最近確認上傳：$expected');
    expect(_key('done-message'), findsNothing);
    expect(_key('health-pending'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'star completion keeps its mode and PTU count without direct binding',
    (tester) async {
      await _pumpPage(
        tester,
        topology: GatewayTopology.star,
        snapshot: _done(star: true),
      );
      expect(_text(tester, 'done-mode'), contains('星狀模式'));
      expect(_text(tester, 'commission-summary'), contains('本機配置 1 台'));
      expect(_key('done-ptu-mac'), findsNothing);
      expect(_key('direct-bound-note'), findsNothing);
      _insideBody(tester, 'done-upload');
      _insideBody(tester, 'install-report-status');
      _bottomActions(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'deferred PTU remains explicitly pending and never appears bound',
    (tester) async {
      await _pumpPage(tester, snapshot: _done(deferred: true));
      expect(_text(tester, 'done-title'), deferredDoneTitle);
      expect(_key('done-ptu-mac'), findsNothing);
      expect(_key('direct-bound-note'), findsNothing);
      expect(_text(tester, 'done-upload'), contains(deferredUploadStatus));
      expect(_text(tester, 'commission-summary'), deferredSummaryText);
      expect(_key('deferred-note'), findsOneWidget);
      expect(_key('done-advanced'), findsNothing);
      _bottomActions(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
