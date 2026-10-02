import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';

import 'support/real_fonts.dart';

const _mac = '9F:D3:E1:EF:96:00';
const _other = '90:2F:E7:FB:96:00';

CommissionState _picked({bool identified = false}) => CommissionState(
  step: 4,
  peer: const GatewayPeer('test-gateway', 'GIOS-S80-GW03', -42),
  offline: true,
  checkPassed: true,
  config: {
    ...DemoSystem().config,
    'fleet_joined': true,
    'mqtt_connected': true,
    'site_id': 80,
    'gateway_id': 3,
    'max_connections': 1,
    'upload_paused': false,
  },
  net: const {
    'wifi_state': 'got_ip',
    'ip': '192.0.2.2',
    'ssid': 'Test-2.4G',
    'rssi': -40,
  },
  directRaw: const {
    'state': 'connected',
    'ptu_mac': _mac,
    'ptu_rssi': -27,
    'min_rssi': -55,
    'select_reason': 'ok',
    'candidates': [
      {'mac': _mac, 'rssi_peak': -27},
      {'mac': _other, 'rssi_peak': -46},
    ],
  },
  ptus: const [
    {'mac': _mac, 'rssi': -27, 'connected': true},
  ],
  selected: const {_mac},
  identifiedMac: identified ? _mac : null,
  identifyNote: identified ? '已送出辨識，請看樁上燈號。PTU $_mac，訊號 -27 dBm。' : '',
  identifyLine: identified ? '已送出 · 請看樁上燈號 · $_mac · -27 dBm' : '',
);

class _SnapshotController extends CommissioningController {
  _SnapshotController(this.initial);
  final CommissionState initial;
  int scans = 0, stops = 0, endings = 0, confirmations = 0;
  String? switchedMac;

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
  Future<void> identify({String target = 'both'}) async =>
      state = _picked(identified: true);

  @override
  Future<void> rescanDirect() async {
    scans++;
  }

  @override
  Future<void> stopStep8() async {
    stops++;
    state = _picked();
  }

  @override
  Future<void> switchDirectPick(String mac) async {
    switchedMac = mac;
  }

  @override
  Future<void> cancel() async {
    endings++;
  }

  @override
  Future<void> confirmDirectPick() async {
    confirmations++;
  }
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

Future<_SnapshotController> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1.3,
  bool identified = false,
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
  final controller = _SnapshotController(_picked(identified: identified));
  final container = ProviderContainer(
    overrides: [
      commissionProvider.overrideWith(() => controller),
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      localBackendProberProvider.overrideWithValue(_Prober()),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() async {
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.direct);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: withRealFonts(
          gatewayTheme(Brightness.light).copyWith(platform: TargetPlatform.iOS),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const Key('compact-page-preview'),
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
  return controller;
}

Finder _key(String name) => find.byKey(Key(name));

Rect _bodyViewport(WidgetTester tester) => tester.getRect(
  find
      .ancestor(of: _key('direct-linked'), matching: find.byType(Viewport))
      .first,
);

void _insideBody(WidgetTester tester, String key) {
  final viewport = _bodyViewport(tester);
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
  final bar = tester.getRect(_key('direct-pick-actions'));
  expect(rect.bottom, lessThanOrEqualTo(bar.top));
}

void _touchTargets(WidgetTester tester) {
  for (final key in [
    'direct-identify',
    'direct-stop',
    'direct-more',
    'direct-confirm',
  ]) {
    final rect = tester.getRect(_key(key));
    expect(rect.width, greaterThanOrEqualTo(48), reason: '$key width');
    expect(rect.height, greaterThanOrEqualTo(48), reason: '$key height');
  }
}

Map<String, Rect> _buttons(WidgetTester tester) => {
  for (final key in [
    'direct-identify',
    'direct-stop',
    'direct-more',
    'direct-confirm',
  ])
    key: tester.getRect(_key(key)),
};

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(_key('direct-more'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(await loadRealFonts(), isTrue);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    // The test engine has no system fallback for production's monospace
    // family. Load it explicitly so both MAC measurements and pixels are real.
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
  });

  for (final size in [const Size(393, 852), const Size(360, 640)]) {
    for (final scale in size.height > 740 ? [1.0, 1.3, 1.6] : [1.0, 1.3]) {
      testWidgets(
        'complete page: MAC and RSSI initially visible at $size / $scale',
        (tester) async {
          final previewPath = size.width == 393 && scale == 1.3
              ? Platform.environment['GIOS_PTU_PREVIEW']
              : null;
          final oldShadows = debugDisableShadows;
          if (previewPath != null) debugDisableShadows = false;
          try {
            final controller = await _pumpPage(
              tester,
              size: size,
              scale: scale,
            );
            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(_key('direct-pick-actions')).height,
              lessThanOrEqualTo(scale > 1.3 ? 200 : 180),
            );
            _insideBody(tester, 'direct-linked');
            _insideBody(tester, 'direct-rssi');
            _touchTargets(tester);
            expect(
              tester.widget<FilledButton>(_key('direct-confirm')).onPressed,
              isNull,
            );

            controller.show(_picked(identified: true));
            await tester.pumpAndSettle();
            _insideBody(tester, 'direct-linked');
            _insideBody(tester, 'direct-rssi');
            expect(
              tester.widget<FilledButton>(_key('direct-confirm')).onPressed,
              isNotNull,
            );

            if (previewPath != null) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                _key('compact-page-preview'),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 2);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  previewPath,
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            debugDisableShadows = oldShadows;
          }
        },
      );
    }
  }

  testWidgets(
    'large text: readable PTU data can be scrolled above fixed actions',
    (tester) async {
      await _pumpPage(tester, size: const Size(360, 640), scale: 1.6);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(_key('direct-pick-actions')).height,
        lessThanOrEqualTo(200),
      );
      _touchTargets(tester);
      // Scroll the beginning of the information group into view. Anchoring
      // RSSI itself at the viewport top would intentionally scroll MAC away.
      await tester.ensureVisible(_key('direct-linked'));
      await tester.pumpAndSettle();
      _insideBody(tester, 'direct-linked');
      _insideBody(tester, 'direct-rssi');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'more menu retains candidate switching, rescan and confirmed ending',
    (tester) async {
      final controller = await _pumpPage(tester);
      await _openMore(tester);
      await tester.tap(_key('direct-not-this'));
      await tester.pumpAndSettle();
      expect(_key('direct-candidates-sheet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('direct-candidate-$_other')));
      await tester.pumpAndSettle();
      expect(controller.switchedMac, _other);

      await _openMore(tester);
      await tester.tap(_key('direct-rescan-bottom'));
      await tester.pumpAndSettle();
      expect(controller.scans, 1);

      await _openMore(tester);
      await tester.tap(_key('page-cancel'));
      await tester.pumpAndSettle();
      expect(_key('end-confirm'), findsOneWidget);
      expect(controller.endings, 0);
      await tester.tap(_key('end-confirm-continue'));
      await tester.pumpAndSettle();
      expect(controller.endings, 0);
      await _openMore(tester);
      await tester.tap(_key('page-cancel'));
      await tester.pumpAndSettle();
      await tester.tap(_key('end-confirm-end'));
      await tester.pumpAndSettle();
      expect(controller.endings, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pending identification and remote notices keep actions fixed; busy cancel works',
    (tester) async {
      final controller = await _pumpPage(tester);
      final before = _buttons(tester);
      final bar = tester.getRect(_key('direct-pick-actions'));
      expect(tester.widget<IconButton>(_key('direct-stop')).onPressed, isNull);
      controller.show(
        _picked().copy(
          busy: true,
          identifyNote: identifyPendingText,
          identifyLine: identifyPendingText,
        ),
      );
      await tester.pump();
      expect(_buttons(tester), before);
      expect(tester.getRect(_key('direct-pick-actions')), bar);
      expect(_key('direct-identify-pending'), findsOneWidget);
      expect(
        tester.widget<IconButton>(_key('direct-stop')).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<FilledButton>(_key('direct-identify')).onPressed,
        isNull,
      );
      await tester.tap(_key('direct-stop'));
      await tester.pumpAndSettle();
      expect(controller.stops, 1);
      expect(_buttons(tester), before);

      controller.show(
        _picked().copy(
          remoteIdentifyCount: 1,
          remoteIdentifyNote: '後台已讓此樁閃燈 · PTU 已確認。PTU $_mac · -27 dBm。',
          remoteIdentifyHead: remoteIdentifyHeads.first,
          remoteIdentifyPtu: 'PTU $_mac · -27 dBm',
        ),
      );
      await tester.pump();
      expect(_key('remote-identify'), findsOneWidget);
      expect(_buttons(tester), before);
      expect(tester.getRect(_key('direct-pick-actions')), bar);
      await tester.tap(_key('direct-identify-toggle'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_key('remote-identify-detail'), findsOneWidget);
      expect(_buttons(tester), before);
      expect(tester.getRect(_key('direct-pick-actions')), bar);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('menu opened before busy cannot start stale actions', (
    tester,
  ) async {
    final controller = await _pumpPage(tester);
    for (final key in [
      'direct-not-this',
      'direct-rescan-bottom',
      'page-cancel',
    ]) {
      await _openMore(tester);
      controller.show(_picked().copy(busy: true));
      await tester.pump();
      await tester.tap(_key(key));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.scans, 0);
      expect(controller.endings, 0);
      expect(controller.switchedMac, isNull);
      expect(_key('direct-candidates-sheet'), findsNothing);
      expect(_key('end-confirm'), findsNothing);
      controller.show(_picked());
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
