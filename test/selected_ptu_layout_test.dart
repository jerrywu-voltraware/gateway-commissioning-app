import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';

import 'support/real_fonts.dart';

const _mac = '90:2F:E7:FB:96:00';

CommissionState _state({
  Map<String, dynamic> direct = const {},
  List<Map<String, dynamic>> ptus = const [],
}) => CommissionState(
  step: 4,
  config: const {
    'direct_autoconnect_supported': true,
    'identify_supported': true,
    'identify_ptu_supported': true,
  },
  directRaw: {
    'state': 'connected',
    'ptu_mac': _mac,
    'self_adv_rssi_med': -30,
    'min_rssi': -55,
    'select_reason': 'ok',
    ...direct,
  },
  ptus: ptus,
);

class _SnapshotController extends CommissioningController {
  _SnapshotController(this.snapshot);
  final CommissionState snapshot;

  @override
  CommissionState build() => snapshot;

  @override
  bool get directFlow => true;
}

Future<void> _pump(
  WidgetTester tester, {
  required CommissionState state,
  double width = 360,
  double scale = 1.1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        commissionProvider.overrideWith(() => _SnapshotController(state)),
      ],
      child: MaterialApp(
        theme: withRealFonts(gatewayTheme(brightness)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('GIOS 現場開通')),
          body: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: RepaintBoundary(
              key: Key('ptu-card-preview'),
              child: DirectStatusPanel(actionsInBar: true),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _signal(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('direct-rssi')))
    .textSpan!
    .toPlainText();

void main() {
  setUpAll(() async {
    expect(await loadRealFonts(), isTrue);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final mono = File('C:/Windows/Fonts/consola.ttf');
    if (mono.existsSync()) {
      await (FontLoader(
        'monospace',
      )..addFont(mono.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'readable PTU card at small widths and large text: $brightness',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final width in [320.0, 360.0]) {
          for (final scale in [1.1, 1.3, 2.0]) {
            await _pump(
              tester,
              state: _state(),
              width: width,
              scale: scale,
              brightness: brightness,
            );
            expect(tester.takeException(), isNull);
            expect(find.text('裝置編號（MAC）'), findsOneWidget);
            expect(find.text(_mac), findsOneWidget);
            expect(find.text('選台依據：訊號最強且明確'), findsOneWidget);
            expect(directConfirmReady(_state()), isFalse);
            final card = tester.getRect(find.byKey(const Key('direct-status')));
            for (final element in find.byType(RichText).evaluate()) {
              final render = element.renderObject;
              if (render is! RenderParagraph) continue;
              expect(render.didExceedMaxLines, isFalse);
              final origin = render.localToGlobal(Offset.zero);
              expect(origin.dx + render.size.width, lessThanOrEqualTo(width));
            }
            expect(card.width, lessThanOrEqualTo(width - 32));
            // A readable full MAC is above the signal, not forced into a wrap
            // alongside a second headline-size number.
            expect(
              tester.getBottomLeft(find.byKey(const Key('direct-linked'))).dy,
              lessThan(
                tester.getTopLeft(find.byKey(const Key('direct-rssi'))).dy,
              ),
            );
            final exportDir = Platform.environment['GIOS_PTU_PREVIEW_DIR'];
            if (exportDir != null && width == 360 && scale == 1.1) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('ptu-card-preview')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 2);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$exportDir/ptu_card_${brightness.name}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('signal presentation retains reading source and freshness', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final example in [
      (_state(), '廣播 -30 dBm（連線訊號讀取中）'),
      (_state(direct: {'self_adv_rssi_med': null}), '訊號讀取中…'),
      (_state(direct: {'ptu_rssi': -42}), '-42 dBm'),
      (
        _state(
          ptus: [
            {'mac': _mac, 'rssi': -43, 'rssi_stale': true},
          ],
        ),
        '上次 -43 dBm',
      ),
      (
        _state(
          ptus: [
            {'mac': _mac, 'rssi': -44, 'connected': false},
          ],
        ),
        '掃描 -44 dBm',
      ),
      (
        _state(
          ptus: [
            {'mac': _mac, 'rssi': -45, 'connected': true},
          ],
        ),
        '快取 -45 dBm',
      ),
    ]) {
      await _pump(tester, state: example.$1);
      expect(_signal(tester), example.$2);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
