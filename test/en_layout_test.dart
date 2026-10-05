// Phase C（docs/i18n.md §8.6）：英文版面抽查。
//
// 英文通常比中文長 30–80%。主要畫面在 360x640、字級 1.0 與 1.3 下用英文
// 各看一次（真字型，見 support/real_fonts.dart），從頂端捲到底：
// - 沒有例外（RenderFlex overflow 也是例外）；
// - 單行文字（maxLines: 1）沒有被截斷、沒有比自己的框寬；
// - 文字沒有超出螢幕右緣（可左右捲的表格除外）。
//
// 畫面：首頁、「更多」選單與語言對話框、模式設定、閘道器清單（找到／沒找到）、
// 網路體檢與站點、PTU 清單、一對一選 PTU 與辨識後單行、資料驗證（離線等待）、
// 完成頁與其詳細、請後台協助面板（紅框）、最近資料頁。
// 中文版面由 layout_smoke_test.dart 等既有測試負責。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart' show GatewayFailure;
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'round15_direct_flow_test.dart' show PickGateway;
import 'support/l10n.dart';
import 'support/real_fonts.dart';

const _size = Size(360, 640);
const _scales = [1.0, 1.3];

var _realFonts = false;

ThemeData _theme(Brightness b) => withRealFonts(gatewayTheme(b));

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _inSidewaysScroll(Element element) {
  var sideways = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Scrollable &&
        axisDirectionToAxis(widget.axisDirection) == Axis.horizontal) {
      sideways = true;
      return false;
    }
    return true;
  });
  return sideways;
}

/// 目前畫面上的文字（同 layout_smoke_test 的檢查）。
void _checkTexts(WidgetTester tester, String where) {
  expect(tester.takeException(), isNull, reason: '$where: exception');
  if (!_realFonts) return;
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph ||
        !paragraph.attached ||
        !paragraph.hasSize) {
      continue;
    }
    final text = paragraph.text.toPlainText();
    if (text.runes.length == 1 && text.runes.single >= 0xE000) continue;
    if (paragraph.maxLines == 1) {
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$where: "$text" cut',
      );
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: '$where: "$text" wider than its box',
      );
    }
    if (!_inSidewaysScroll(element)) {
      final box = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        Offset.zero & paragraph.size,
      );
      expect(
        box.right,
        lessThanOrEqualTo(width + 0.5),
        reason: '$where: "$text" beyond the right edge',
      );
    }
  }
}

ScrollPosition? _pageScroll(WidgetTester tester) {
  ScrollPosition? found;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.widget.axisDirection != AxisDirection.down) continue;
    final position = state.position;
    if (!position.hasViewportDimension || position.viewportDimension < 150) {
      continue;
    }
    found = position;
  }
  return found;
}

/// [page] 在兩種字級下，從頂端捲到底檢查。
Future<void> _checkPage(WidgetTester tester, String page) async {
  expect(L10n.language, AppLanguage.en, reason: '$page: English');
  for (final scale in _scales) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await _frames(tester);
    final where = '$page @$scale';
    final scroll = _pageScroll(tester);
    scroll?.jumpTo(0);
    await _frames(tester);
    _checkTexts(tester, where);
    while (scroll != null && scroll.pixels < scroll.maxScrollExtent - 0.5) {
      scroll.jumpTo(
        (scroll.pixels + scroll.viewportDimension * 0.8).clamp(
          0,
          scroll.maxScrollExtent,
        ),
      );
      await _frames(tester);
      _checkTexts(tester, '$where (scrolled ${scroll.pixels.round()})');
    }
    scroll?.jumpTo(0);
  }
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  await _frames(tester);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 沒有任何閘道器的掃描結果。
class _NoGateway extends DemoSystem {
  @override
  Future<List<GatewayPeer>> scan() async => const [];
}

/// 有後台登入、指定指令會逾時一次的閘道器（紅框＋〔請後台協助〕）。
class _FailingGateway extends DemoSystem implements SessionInfo {
  String? failOp;

  @override
  bool get hasSession => true;

  @override
  String? get origin => const BackendEnvState().base;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == failOp) {
      failOp = null;
      throw const GatewayFailure('timeout');
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.startsWith('/api/field/')) {
      if (path.endsWith('/support')) {
        return {
          'state': 'pending',
          'revision': 0,
          'supported': true,
          'events': [],
        };
      }
      return {'ok': true, 'duplicate': false};
    }
    return super.request(method, path, body);
  }
}

/// 英文的整個 APP（DemoSystem 當閘道器與後台）。
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, [
  DemoSystem? fake,
]) async {
  _phone(tester);
  addTearDown(L10n.reset);
  SharedPreferences.setMockInitialValues({
    'app_locale': 'en',
    'backend_environment': 'production',
  });
  final system = fake ?? DemoSystem();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(system),
        apiProvider.overrideWithValue(system),
        backendKeyProvider.overrideWithValue('build-key'),
        // AppBar 的〔請後台協助〕圖示（最寬的 AppBar）。
        fieldReporterConfigProvider.overrideWithValue(
          const FieldReporterConfig(allowDemoLink: true),
        ),
      ],
      child: const GatewayApp(theme: _theme),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  await tester.runAsync(
    () => container.read(backendEnvProvider.notifier).ready,
  );
  await tester.pumpAndSettle();
  expect(L10n.language, AppLanguage.en);
  return container;
}

Future<void> _run(
  WidgetTester tester,
  ProviderContainer container,
  Future<void> Function(CommissioningController c) steps,
) async {
  await tester.runAsync(
    () => steps(container.read(commissionProvider.notifier)),
  );
  await tester.pumpAndSettle();
}

Future<void> _star(ProviderContainer container) async {
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.star);
}

/// 最近資料頁的後台：一台 PTU、20 筆資料（最寬的值在第一筆）。
class _RecentApi implements GatewayApi {
  _RecentApi(this.now);
  final DateTime now;

  @override
  Future<void> login(String base, String password) async {}

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.startsWith('/api/app/recent/')) {
      return {
        'site_id': 81,
        'gateway_id': 1,
        'count': 20,
        'items': [
          for (var i = 0; i < 20; i++)
            {
              'ts': now
                  .subtract(Duration(milliseconds: 550 * i))
                  .toIso8601String(),
              'seq': 200 - i,
              'device_id': 1,
              'ptu_mac': '90:5F:E8:9A:96:00',
              'ptu_state': switch (i % 7) {
                3 => 'EXCEEDED_RANGE',
                5 => 'POWER_SAVE',
                6 => 'LOW_POWER',
                _ => 'POWER_TRANSFER',
              },
              'input_mv': 53200 + i * 10,
              'input_ma': i == 0 ? 12345 : 2720,
              'bus_mv': 53000,
              'temp_c': i == 0 ? 255 : 36,
            },
        ],
      };
    }
    final seen = now.subtract(const Duration(seconds: 7)).toIso8601String();
    return {
      'gateways': [
        {
          'site_id': 81,
          'gateway_id': 1,
          'online': true,
          'ble_connected': 1,
          'max_connections': 1,
          'device_last_seen': seen,
          'last_heartbeat': seen,
          'last_seen': seen,
        },
      ],
      'total': 1,
    };
  }
}

void main() {
  setUpAll(() async => _realFonts = await loadRealFonts());

  test('real fonts are loaded (widths are checked)', () {
    expect(_realFonts, isTrue, reason: 'Roboto / a Chinese font not found');
  });

  testWidgets('start page, the ⋮ menu, language and mode settings', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _checkPage(tester, 'start');

    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pumpAndSettle();
    await _checkPage(tester, '⋮ menu');

    await tester.tap(find.byKey(const Key('language-settings-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('language-options')), findsOneWidget);
    await _checkPage(tester, 'language dialog');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topology-settings-menu')));
    await tester.pumpAndSettle();
    await _checkPage(tester, 'mode settings');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gateway list, nothing found', (tester) async {
    final container = await _pumpApp(tester, _NoGateway());
    await _run(tester, container, (c) async {
      await _star(container);
      await c.prepare(container.read(backendEnvProvider).base, 'pw');
      await c.scan();
    });
    await _checkPage(tester, 'gateway list (none found)');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gateway list, network check / site, PTU list, done (star) '
      '', (tester) async {
    final container = await _pumpApp(tester);
    CommissionState read() => container.read(commissionProvider);
    await _run(tester, container, (c) async {
      await _star(container);
      await c.prepare(container.read(backendEnvProvider).base, 'pw');
      await c.scan();
    });
    expect(read().step, 1);
    await _checkPage(tester, 'gateway list');

    await _run(tester, container, (c) => c.connect(read().peers.first));
    expect(read().step, 2);
    await _checkPage(tester, 'network check / site');

    await _run(tester, container, (c) async {
      await c.configureWifi(80, 1, 'Office-2G', 'pw123456');
      await c.online();
      await c.discover();
    });
    expect(read().ptus, isNotEmpty);
    await _checkPage(tester, 'PTU list');

    await _run(tester, container, (c) => c.configurePtus());
    expect(read().step, 7);
    await _checkPage(tester, 'done');
    // 展開「設備與連線資訊」（openDoneSection 依中文標題找，這裡直接點區塊）。
    final details = find.byKey(const Key('commission-details'));
    await tester.scrollUntilVisible(
      details,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(details);
    await tester.pumpAndSettle();
    await _checkPage(tester, 'done details');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one-to-one: the PTU the gateway picked (step 7 panel)', (
    tester,
  ) async {
    final container = await _pumpApp(tester, PickGateway());
    await _run(tester, container, (c) async {
      final topo = container.read(topologyProvider.notifier);
      await topo.ready;
      await topo.setTopology(GatewayTopology.direct);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
    });
    expect(container.read(commissionProvider).direct?.pickedMac, isNotNull);
    await _checkPage(tester, 'one-to-one pick');
    await tester.pumpWidget(const SizedBox());
  });

  // 一對一按〔辨識此樁〕後底部單行（direct-identify-note）：英文 @1.3 不能被截斷，
  // MAC 尾碼與 RSSI（dBm）都要看得到（i18n 驗收 2026-10-06 #1）。
  for (final (confirm, head) in [
    (null, () => L10n.current.directMode_identifySentLine),
    ('timeout', () => L10n.current.directMode_lineTimeout),
    (
      'unsupported_pattern',
      () => L10n.current.directMode_lineUnsupportedPattern,
    ),
  ]) {
    testWidgets(
      'one-to-one: identify line after the ack (${confirm ?? 'sent'})',
      (tester) async {
        final fake = PickGateway()..identifyPtuConfirm = confirm;
        final container = await _pumpApp(tester, fake);
        await _run(tester, container, (c) async {
          final topo = container.read(topologyProvider.notifier);
          await topo.ready;
          await topo.setTopology(GatewayTopology.direct);
          await c.prepare('https://example.invalid', '', offline: true);
          await c.scan();
          await c.connect(container.read(commissionProvider).peers.single);
          await c.chooseStation(newStation: false);
          await c.identify();
        });
        final s = container.read(commissionProvider);
        expect(s.identifyLine, startsWith(head()));
        final mac = (s.direct?.pickedMac ?? '')
            .replaceAll(':', '')
            .toUpperCase();
        expect(mac, hasLength(12));
        final rssi = fake.devices.firstWhere(
          (d) => '${d['mac']}'.replaceAll(':', '').toUpperCase() == mac,
        )['rssi'];
        for (final scale in _scales) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await _frames(tester);
          final note = find.byKey(const Key('direct-identify-note'));
          expect(note, findsOneWidget, reason: '@$scale');
          final rich = find.descendant(
            of: note,
            matching: find.byType(RichText),
          );
          final p = tester.renderObject<RenderParagraph>(
            rich.evaluate().isEmpty ? note : rich.first,
          );
          final shown = p.text.toPlainText();
          final where =
              '${confirm ?? 'sent'} @$scale: "$shown" '
              '(${p.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(1)} '
              'in ${p.size.width.toStringAsFixed(1)})';
          if (_realFonts) {
            expect(p.didExceedMaxLines, isFalse, reason: '$where cut');
            expect(
              p.getMaxIntrinsicWidth(double.infinity),
              lessThanOrEqualTo(p.size.width + 0.5),
              reason: '$where wider than its box',
            );
          }
          expect(shown, startsWith(head()), reason: where);
          expect(shown, endsWith('$rssi dBm'), reason: where);
          expect(
            shown.replaceAll(':', '').toUpperCase(),
            contains(mac.substring(10)),
            reason: '$where: MAC tail',
          );
        }
        await _checkPage(tester, 'one-to-one identify (${confirm ?? 'sent'})');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('red box and the 〔Ask back office〕 help panel', (tester) async {
    final fake = _FailingGateway();
    final container = await _pumpApp(tester, fake);
    await _run(tester, container, (c) async {
      await c.prepare(container.read(backendEnvProvider).base, 'pw');
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.first);
    });
    fake.failOp = 'get_net_status';
    await _run(tester, container, (c) => c.refreshUploadTarget());
    final banner = find.byKey(const Key('error-banner'), skipOffstage: false);
    expect(banner, findsOneWidget);
    await tester.ensureVisible(banner);
    await tester.pumpAndSettle();
    await _checkPage(tester, 'red box');
    final help = find.byKey(const Key('field-help'));
    await tester.ensureVisible(help);
    await tester.pumpAndSettle();
    await tester.tap(help);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('field-help-sheet')), findsOneWidget);
    await _checkPage(tester, 'help panel');
    await tester.pumpWidget(const SizedBox());
    // 上傳／求助等待的計時器跑完再結束（!timersPending）。
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('data check page (offline run waits)', (tester) async {
    final container = await _pumpApp(tester);
    await _run(tester, container, (c) async {
      await _star(container);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.first);
      await c.configureWifi(80, 1, 'Office-2G', 'pw123456');
      // 佈置刻意維持離線（同 verify_live_feed_test 的 _pageAtStep9）。
      c.backendChanged('https://offline-fixture.invalid');
      await c.online(skip: true);
      await c.discover();
      await c.configurePtus();
    });
    expect(container.read(commissionProvider).step, 6);
    await _checkPage(tester, 'data check');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recent data page, table open', (tester) async {
    _phone(tester);
    useLanguage(AppLanguage.en);
    final now = DateTime(2026, 9, 29, 1, 34, 53);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkProvider.overrideWithValue(DemoSystem()),
          apiProvider.overrideWithValue(_RecentApi(now)),
          backendKeyProvider.overrideWithValue('build-key'),
        ],
        child: wrapWithL10n(
          RecentDataPage(site: 81, gateway: 1, now: () => now),
          language: AppLanguage.en,
          theme: _theme(Brightness.light),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(recentDataPageTitle), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('recent-table-tile')),
      200,
    );
    await tester.tap(find.byKey(const Key('recent-table-tile')));
    await tester.pumpAndSettle();
    await _checkPage(tester, 'recent data');
  });
}
