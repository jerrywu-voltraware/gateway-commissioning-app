import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';

import 'support/real_fonts.dart';

const _mac = '9F:D3:E1:EF:96:00';
const _otherMac = '90:2F:E7:FB:96:01';
final _now = DateTime(2026, 10, 2, 20, 5, 12);

Map<String, dynamic> _row({
  String mac = _mac,
  String state = 'POWER_TRANSFER',
  num? voltage = 53200,
  num? current = 2720,
  num? temperature = 36,
  int age = 3,
  int? errorNum = 0,
}) => {
  'ts': _now.subtract(Duration(seconds: age)).toIso8601String(),
  'device_id': mac == _mac ? 1 : 2,
  'ptu_mac': mac,
  'ptu_state': state,
  'input_mv': voltage,
  'input_ma': current,
  'pru_iout': current,
  'pru_vrect': 4500,
  'pru_vbat': 480,
  'pru_Temp_degC': 29,
  'error_num': errorNum,
  'pru_mac': '3C:84:27:AA:BB:CC',
  'temp_c': temperature,
};

class _Api implements GatewayApi {
  _Api(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Future<void> login(String base, String password) async {}

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async => {
    'site_id': 50,
    'gateway_id': 1,
    'count': rows.length,
    'items': rows,
  };
}

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1.3,
  List<Map<String, dynamic>>? rows,
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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(DemoSystem()),
        apiProvider.overrideWithValue(_Api(rows ?? [_row(), _row(age: 8)])),
      ],
      child: MaterialApp(
        theme: withRealFonts(
          gatewayTheme(Brightness.light).copyWith(platform: TargetPlatform.iOS),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const Key('recent-compact-preview'),
            child: child!,
          ),
        ),
        home: RecentDataPage(site: 50, gateway: 1, now: () => _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String value) => find.byKey(Key(value));

String _text(WidgetTester tester, String key) {
  final text = tester.widget<Text>(_key(key));
  return text.data ?? text.textSpan!.toPlainText();
}

void _fullyPainted(WidgetTester tester, String key, String expected) {
  final finder = _key(key);
  expect(finder, findsOneWidget);
  expect(_text(tester, key), expected);
  final text = tester.widget<Text>(finder);
  expect(text.overflow, isNot(TextOverflow.ellipsis), reason: key);
  expect(text.overflow, isNot(TextOverflow.fade), reason: key);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: key);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: expected.length),
  );
  expect(boxes, isNotEmpty);
  // Glyph advances can round differently from paragraph layout by a
  // fractional logical pixel (PingFang commonly differs by 0.125 px).
  const glyphRounding = 0.5;
  for (final box in boxes) {
    expect(box.left, greaterThanOrEqualTo(-glyphRounding), reason: key);
    expect(
      box.right,
      lessThanOrEqualTo(paragraph.size.width + glyphRounding),
      reason: key,
    );
    expect(
      box.bottom,
      lessThanOrEqualTo(paragraph.size.height + glyphRounding),
      reason: key,
    );
  }
  final screenWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(screenWidth));
}

void _insideViewport(WidgetTester tester, String key) {
  final finder = _key(key);
  final viewport = tester.getRect(
    find.ancestor(of: finder, matching: find.byType(Viewport)).first,
  );
  final rect = tester.getRect(finder);
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
}

Future<void> _scrollTo(
  WidgetTester tester,
  String key, {
  double delta = 180,
}) async {
  await tester.scrollUntilVisible(
    _key(key),
    delta,
    scrollable: find
        .descendant(of: _key('recent-body'), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
  _insideViewport(tester, key);
}

void _readings(
  WidgetTester tester, {
  String prefix = 'recent-latest',
  List<String> values = const ['53.2 V', '2.72 A', '36 °C'],
}) {
  for (final (index, value) in values.indexed) {
    _fullyPainted(tester, '$prefix-value-$index', value);
    _fullyPainted(tester, '$prefix-label-$index', ['電壓', '電流', '發射端溫度'][index]);
  }
  expect(
    tester.getRect(_key('$prefix-value-0')).bottom,
    lessThanOrEqualTo(tester.getRect(_key('$prefix-value-1')).top),
    reason: 'each measurement has its own readable row',
  );
  expect(
    tester.getRect(_key('$prefix-value-1')).bottom,
    lessThanOrEqualTo(tester.getRect(_key('$prefix-value-2')).top),
  );
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
  });

  for (final size in [const Size(393, 852), const Size(360, 640)]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets(
        'complete measurements and compact status at $size / $scale',
        (tester) async {
          final preview = size.width == 393 && scale == 1.3
              ? Platform.environment['GIOS_RECENT_PREVIEW']
              : null;
          final oldShadows = debugDisableShadows;
          if (preview != null) debugDisableShadows = false;
          try {
            await _pumpPage(tester, size: size, scale: scale);
            expect(tester.takeException(), isNull);
            expect(find.text('上傳正常'), findsOneWidget);
            expect(
              tester.getRect(_key('recent-banner')).height,
              lessThanOrEqualTo(64),
            );
            expect(_key('recent-trend'), findsNothing);
            expect(_key('recent-table'), findsNothing);
            _readings(tester);
            for (var index = 0; index < 3; index++) {
              _insideViewport(tester, 'recent-latest-value-$index');
            }
            _fullyPainted(tester, 'recent-latest-line-mac', _mac);
            _fullyPainted(
              tester,
              'recent-latest-line-state',
              _text(tester, 'recent-latest-line-state'),
            );
            _fullyPainted(
              tester,
              'recent-latest-line-time',
              _text(tester, 'recent-latest-line-time'),
            );
            _fullyPainted(
              tester,
              'recent-latest-line-age',
              _text(tester, 'recent-latest-line-age'),
            );
            expect(_text(tester, 'recent-latest-line-state'), contains('充電中'));
            expect(
              _text(tester, 'recent-latest-line-time'),
              contains('20:05:09'),
            );
            expect(_text(tester, 'recent-latest-line-age'), contains('3 秒前'));

            if (preview != null) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                _key('recent-compact-preview'),
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
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            debugDisableShadows = oldShadows;
          }
        },
      );
    }
  }

  testWidgets(
    '320 dp large text preserves long values and every metadata field by scrolling',
    (tester) async {
      await _pumpPage(
        tester,
        size: const Size(320, 640),
        scale: 1.6,
        rows: [_row(voltage: 123456700, current: 98765430, temperature: -1234)],
      );
      expect(tester.takeException(), isNull);
      _readings(tester, values: ['123456.7 V', '98765.43 A', '-1234 °C']);
      for (final key in [
        'recent-latest-value-0',
        'recent-latest-value-1',
        'recent-latest-value-2',
        'recent-latest-line-mac',
        'recent-latest-line-state',
        'recent-latest-line-time',
        'recent-latest-line-age',
      ]) {
        await _scrollTo(tester, key);
        _fullyPainted(tester, key, _text(tester, key));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'history keeps trend inside its collapsed section and expands on demand',
    (tester) async {
      await _pumpPage(tester, size: const Size(360, 640), scale: 1.3);
      expect(_key('recent-trend'), findsNothing);
      expect(_key('recent-table'), findsNothing);
      await _scrollTo(tester, 'recent-table-tile');
      final header = find
          .descendant(
            of: _key('recent-table-tile'),
            matching: find.byType(ListTile),
          )
          .first;
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(_key('recent-table'), findsOneWidget);
      expect(_key('recent-trend'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('recent-table-tile'),
          matching: _key('recent-trend'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(header);
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(_key('recent-trend'), findsNothing);
      expect(_key('recent-table'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [320.0, 600.0]) {
    testWidgets(
      'multiple PTUs and long fault status remain complete at $width dp / large text',
      (tester) async {
        const fault = 'CUSTOM_VENDOR_LATCH_FAULT_WITH_ADDITIONAL_STATUS';
        await _pumpPage(
          tester,
          size: Size(width, 640),
          scale: 1.6,
          rows: [
            _row(),
            // No error_num: the line then shows only the PTU fault text, which is
            // what this long-status case measures (a wrapped " · " separator
            // adds a trailing-space box that the painted-width check rejects).
            _row(
              mac: _otherMac,
              state: fault,
              temperature: 255,
              errorNum: null,
            ),
          ],
        );
        expect(_key('recent-latest-grid'), findsOneWidget);
        expect(_key('recent-latest'), findsNothing);
        for (final (suffix, mac, state, temp) in [
          ('9600', _mac, '充電中', '36 °C'),
          ('9601', _otherMac, fault, '255 °C'),
        ]) {
          final prefix = 'recent-latest-$suffix';
          _readings(tester, prefix: prefix, values: ['53.2 V', '2.72 A', temp]);
          for (final part in [
            'value-0',
            'value-1',
            'value-2',
            'line-mac',
            'line-state',
            'line-time',
            'line-age',
          ]) {
            final key = '$prefix-$part';
            await _scrollTo(tester, key);
            _fullyPainted(tester, key, _text(tester, key));
          }
          expect(_text(tester, '$prefix-line-mac'), mac);
          expect(_text(tester, '$prefix-line-state'), contains(state));
        }
        await _scrollTo(tester, 'recent-latest-9601-fault');
        _fullyPainted(tester, 'recent-latest-9601-fault', recentDataFaultText);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('missing measurements remain explicit with their units', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      size: const Size(360, 640),
      scale: 1.6,
      rows: [_row(voltage: null, current: null, temperature: null)],
    );
    _readings(tester, values: ['-- V', '-- A', '-- °C']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
