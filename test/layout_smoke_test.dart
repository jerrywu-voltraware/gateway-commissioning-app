// 1.0.0+10 layout smoke test (phone SM-N950F: 360x740 dp at system text
// scale 1.1; 1.3 must not break either).
//
// Every page the installer sees, at 360x740 and 360x640, text scale 1.0,
// 1.1 and 1.3, measured with real fonts (Roboto + a Chinese font, see
// support/real_fonts.dart), scrolled top to bottom:
// - no exception (a RenderFlex overflow is one);
// - no one-line text (`maxLines: 1`) cut or wider than its box;
// - no text beyond the right edge of the screen (a sideways-scrolling
//   table's cells excepted);
// - the AppBar title whole, in the one AppBar size (titleMedium, 16).
//
// 1.0.0+14: the gateway list with a gateway selected (the fixed bottom
// scan button), one not configured selected, and while connecting.
//
// 1.0.0+15: the Wi-Fi-first page of a gateway not configured and the
// station page after it (「網路已正常，接著設定站號。」).
//
// 1.0.0+18: the verify page's live data flow — two rows in under each PTU,
// passed (the card green, 「資料正常上傳」), and one late row (red, its
// reason); the widest values (12.35 A, 255 °C, 落後 75 秒).
import 'dart:async';

import 'support/done_sections.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart' show GatewayFailure;
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart'
    show siteFieldLabel;
import 'package:gateway_commissioning/presentation/gateway_discovery.dart'
    show
        GatewayDiscovery,
        gatewayNotFoundText,
        gatewayRetryingText,
        gatewaySearchWindow,
        gatewaySearchingText;
import 'package:gateway_commissioning/presentation/gateway_status_page.dart';
import 'package:gateway_commissioning/presentation/recent_data_page.dart';

import 'round15_direct_flow_test.dart' show PickGateway;
import 'support/real_fonts.dart';

const _sizes = [Size(360, 740), Size(360, 640)];
const _scales = [1.0, 1.1, 1.3];

/// The AppBar title's one size (titleMedium).
const _appBarFontSize = 16.0;

/// Whether real fonts were found: without them the widths mean nothing
/// and only the exception check runs.
var _realFonts = false;

ThemeData _theme(Brightness b) => withRealFonts(gatewayTheme(b));

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

/// The demo gateway (81/1, strong) and a neighbour (80/2, weak) — the
/// phone screenshot's list.
class _TwoGateways extends DemoSystem {
  @override
  Future<List<GatewayPeer>> scan() async => const [
    GatewayPeer('demo-gateway', 'GIOS-S81-GW01', -41),
    GatewayPeer('A0:DD:6C:A3:70:F2', 'GIOS-S80-GW02', -62),
  ];
}

/// 1.0.0+13: [_TwoGateways] with station 80's gateways 1 and 2 held by
/// other devices — 1 offline for 3 hours ([offline]; else online too, the
/// sheet's 「本站沒有離線的閘道器可以取代」), 2 online.
class _SwapGateways extends _TwoGateways {
  _SwapGateways({this.offline = true});
  final bool offline;
  static const _held = {1: '11:22:33:44:55:01', 2: '11:22:33:44:55:02'};

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final identity = RegExp(
      r'^/api/gateways/80/(\d+)/check-identity$',
    ).firstMatch(path);
    if (identity != null) {
      final mac = _held[int.parse(identity[1]!)];
      return {'exists': mac != null, 'last_seen_mac': mac};
    }
    final result = await super.request(method, path, body);
    if (path.contains('fleet-status')) {
      final site = Uri.parse(path).queryParameters['site_id'];
      return {
        ...result,
        'gateways': [
          ...result['gateways'] as List,
          if (site == null || site == '80')
            for (final e in _held.entries)
              {
                'site_id': 80,
                'gateway_id': e.key,
                'last_seen_mac': e.value,
                'online': !(offline && e.key == 1),
                'last_heartbeat': DateTime.now()
                    .subtract(const Duration(hours: 3))
                    .toIso8601String(),
              },
        ],
      };
    }
    return result;
  }
}

/// 1.0.0+14: [_TwoGateways] with 81/1 in the back office (「站 81 · 閘道器
/// 1」; 80/2 is not: 「未配置閘道器 …70F0」); its connect can be held
/// ([hold]: the list's 「連線中…」).
class _SelectGateways extends _TwoGateways {
  Completer<void>? hold;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    await hold?.future;
    return super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final result = await super.request(method, path, body);
    if (!path.contains('fleet-status')) return result;
    return {
      ...result,
      'gateways': [
        ...result['gateways'] as List,
        {'site_id': 81, 'gateway_id': 1, 'online': true},
      ],
    };
  }
}

/// 1.0.0+17: [_TwoGateways] scanning live, one scan per start: the first
/// [silent] scans end at once with nothing heard, the others stay open and
/// hear [heard].
class _SearchGateways extends _TwoGateways implements GatewayScanner {
  _SearchGateways({this.silent = 0, this.heard = const []});
  final int silent;
  final List<GatewayPeer> heard;
  final sessions = <StreamController<List<GatewayPeer>>>[];

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final scan = StreamController<List<GatewayPeer>>();
    sessions.add(scan);
    if (sessions.length <= silent) {
      unawaited(scan.close());
    } else if (heard.isNotEmpty) {
      scan.add(heard);
    }
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    for (final scan in sessions) {
      if (!scan.isClosed) unawaited(scan.close());
    }
  }
}

/// 1.0.0+18: [_TwoGateways] whose /api/latest rows carry the widest PTU
/// values (12.35 A, 255 °C); poll [holdAt] — or, [holdConfirm], the
/// read-back once the data passed — waits for [hold]; polls in [lateAt]
/// answer a lag of 75 s.
class _VerifyGateways extends _TwoGateways {
  _VerifyGateways({
    this.holdAt,
    this.holdConfirm = false,
    this.lateAt = const {},
    this.fallbackFails = false,
  });
  final int? holdAt;
  final bool holdConfirm;
  final Set<int> lateAt;

  /// 1.0.0+20: the build-mode fallback answers 404 (an older back office):
  /// the demo reports no ds_* — the 5-minute pace.
  final bool fallbackFails;
  final hold = Completer<void>();
  bool held = false;
  int latestCalls = 0;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (fallbackFails && path.startsWith('/api/app/build-mode/')) {
      throw GatewayFailure.http(
        status: 404,
        endpoint: 'POST $path',
        detail: 'Not Found',
      );
    }
    final result = await super.request(method, path, body);
    if (!path.startsWith('/api/latest')) return result;
    final n = ++latestCalls;
    if (n == holdAt) {
      held = true;
      await hold.future;
    }
    return {
      'items': [
        for (final raw in result['items'] as List)
          {
            ...Map<String, dynamic>.from(raw as Map),
            'ptu': {
              ...Map<String, dynamic>.from(raw['ptu'] as Map),
              'ptu_inputVoltage_mV': 53200,
              'ptu_inputCurrent_mA': 12345,
              'ptu_ampTemp_degC': 255,
            },
            'lag_seconds': lateAt.contains(n) ? 75 : 1,
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (holdConfirm && op == 'get_config' && latestCalls >= 3) {
      held = true;
      await hold.future;
    }
    return super.command(op, params);
  }
}

/// r34's gateway in service, one-to-one, bound to a PTU that is gone.
class _BoundGateway extends PickGateway implements SessionInfo {
  _BoundGateway() {
    config['max_connections'] = 1;
    config['direct_bind_mac'] = _ownPtu;
    devices.removeWhere((d) => d['mac'] == _ownPtu);
  }

  static const _ownPtu = 'AA:BB:CC:00:00:01';

  @override
  bool get hasSession => true;

  @override
  String? get origin => 'https://example.invalid';

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == fieldSessionsPath) return {'ok': true};
    return super.request(method, path, body);
  }
}

/// The back office for the recent-data and status pages.
class _Api implements GatewayApi {
  _Api(this.now, {this.star = false, this.intervalMs, this.empty = false});
  final DateTime now;
  final bool star;

  /// 1.0.0+20: `upload_interval_ms` of the recent-data answer (none when
  /// null); [empty]: nothing received yet.
  final int? intervalMs;
  final bool empty;

  @override
  Future<void> login(String base, String password) async {}

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.startsWith('/api/app/recent/') && empty) {
      return {
        'site_id': 81,
        'gateway_id': 1,
        'count': 0,
        'items': [],
        if (intervalMs != null) 'upload_interval_ms': intervalMs,
      };
    }
    if (path.startsWith('/api/app/recent/')) {
      return {
        if (intervalMs != null) 'upload_interval_ms': intervalMs,
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
              'device_id': star ? i % 3 + 1 : 1,
              'ptu_mac': star
                  ? '90:5F:E8:9A:96:0${i % 3 + 1}'
                  : '90:5F:E8:9A:96:00',
              'ptu_state': i % 7 == 3 ? 'EXCEEDED_RANGE' : 'POWER_TRANSFER',
              'input_mv': 53200 + i * 10,
              // The widest values first: 12.35 A, 255 °C.
              'input_ma': i == 0 ? 12345 : 2720,
              'bus_mv': 53000,
              'temp_c': i == 0 ? 255 : 36,
            },
        ],
      };
    }
    String ago(Duration d) => now.subtract(d).toIso8601String();
    return {
      'gateways': [
        {
          'site_id': 81,
          'gateway_id': 1,
          'online': true,
          'ble_connected': 1,
          'max_connections': 1,
          'device_last_seen': ago(const Duration(seconds: 7)),
          'last_heartbeat': ago(const Duration(seconds: 7)),
          'last_seen': ago(const Duration(seconds: 7)),
        },
        {
          'site_id': 80,
          'gateway_id': 2,
          'online': false,
          'ble_connected': 0,
          'max_connections': 5,
          'last_heartbeat': ago(const Duration(minutes: 23)),
          'last_seen': ago(const Duration(minutes: 23)),
        },
      ],
      'total': 2,
    };
  }
}

// ---------------------------------------------------------------------------
// The checks
// ---------------------------------------------------------------------------

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Inside something that scrolls sideways (the recent-data table).
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

/// The texts on screen now.
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
    // Icons are RichText too (one private-use glyph).
    if (text.runes.length == 1 && text.runes.single >= 0xE000) continue;
    final sideways = _inSidewaysScroll(element);
    if (paragraph.maxLines == 1) {
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$where: 「$text」 cut',
      );
      final needed = paragraph.getMaxIntrinsicWidth(double.infinity);
      expect(
        needed,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: '$where: 「$text」 wider than its box',
      );
    }
    if (!sideways) {
      final box = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        Offset.zero & paragraph.size,
      );
      expect(
        box.right,
        lessThanOrEqualTo(width + 0.5),
        reason: '$where: 「$text」 beyond the right edge',
      );
    }
  }
}

/// The top route's AppBar title: whole and titleMedium.
void _checkAppBar(WidgetTester tester, String where) {
  final bars = find.byType(AppBar);
  if (bars.evaluate().isEmpty) return;
  final bar = tester.widget<AppBar>(bars.last);
  final title = find.descendant(
    of: find.byWidget(bar.title!),
    matching: find.byType(RichText),
    matchRoot: true,
  );
  final paragraph = tester.renderObject<RenderParagraph>(title.first);
  final text = paragraph.text.toPlainText();
  expect(
    paragraph.text.style?.fontSize,
    _appBarFontSize,
    reason: '$where: AppBar 「$text」 size',
  );
  expect(paragraph.maxLines, 1, reason: '$where: AppBar one line');
  if (!_realFonts) return;
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$where: AppBar 「$text」 cut',
  );
  expect(
    paragraph.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(paragraph.size.width + 0.5),
    reason: '$where: AppBar 「$text」 wider than its box',
  );
}

/// The last tall vertical scrollable (the page, or the sheet on top).
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

/// [page] at every size and text scale, scrolled top to bottom; [also]
/// checks more at each place (1.0.0+14: the list's bottom button).
Future<void> _checkPage(
  WidgetTester tester,
  String page, {
  List<String>? covered,
  void Function(String where)? also,
}) async {
  for (final size in _sizes) {
    for (final scale in _scales) {
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await _frames(tester);
      final where =
          '$page ${size.width.toInt()}x${size.height.toInt()} @$scale';
      _checkAppBar(tester, where);
      final scroll = _pageScroll(tester);
      scroll?.jumpTo(0);
      await _frames(tester);
      _checkTexts(tester, where);
      also?.call(where);
      while (scroll != null && scroll.pixels < scroll.maxScrollExtent - 0.5) {
        scroll.jumpTo(
          (scroll.pixels + scroll.viewportDimension * 0.8).clamp(
            0,
            scroll.maxScrollExtent,
          ),
        );
        await _frames(tester);
        _checkTexts(tester, '$where (scrolled ${scroll.pixels.round()})');
        also?.call('$where (scrolled ${scroll.pixels.round()})');
      }
      scroll?.jumpTo(0);
      covered?.add(where);
    }
  }
  await _frames(tester);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = _sizes.first;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

// ---------------------------------------------------------------------------
// Getting to each page
// ---------------------------------------------------------------------------

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  DemoSystem fake, {
  Map<String, Object> prefs = const {'backend_environment': 'production'},
}) async {
  _phone(tester);
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        backendKeyProvider.overrideWithValue('build-key'),
        envSwitchPolicyProvider.overrideWithValue(
          const EnvSwitchPolicy(
            autoSyncDefault: false,
            confirmGatewaySwitch: true,
            localBuild: false,
          ),
        ),
        localBackendProberProvider.overrideWithValue(_Prober()),
        phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
        // The AppBar's 請後台協助 icon (the widest AppBar).
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
  return container;
}

Future<void> _topology(ProviderContainer container, GatewayTopology t) async {
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(t);
}

/// Star: prepared, on the gateway list.
Future<ProviderContainer> _toList(
  WidgetTester tester, {
  DemoSystem? fake,
}) async {
  final container = await _pumpApp(
    tester,
    fake ?? _TwoGateways(),
    prefs: {
      'backend_environment': 'production',
      // 80/2 was used before: 「最近使用」 and 「附近裝置」 both shown.
      'demo_recent_gateways':
          '[{"id":"A0:DD:6C:A3:70:F2","name":"GIOS-S80-GW02",'
          '"uid":"A0DD6CA370F0"}]',
    },
  );
  await tester.runAsync(() async {
    await _topology(container, GatewayTopology.star);
    await container
        .read(commissionProvider.notifier)
        .prepare(container.read(backendEnvProvider).base, 'pw');
  });
  await tester.pumpAndSettle();
  expect(container.read(commissionProvider).step, 1);
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

GatewayPeer _demoPeer(ProviderContainer container) => container
    .read(commissionProvider)
    .peers
    .firstWhere((p) => p.id == 'demo-gateway');

/// 1.0.0+17: star, prepared, on the gateway list while its search runs —
/// frames only (settling would run the search to its end); [time]: how
/// long the list has searched, its stop / start let run.
Future<ProviderContainer> _toSearchingList(
  WidgetTester tester,
  DemoSystem fake, {
  Duration time = const Duration(milliseconds: 600),
}) async {
  final container = await _pumpApp(
    tester,
    fake,
    prefs: {
      'backend_environment': 'production',
      'demo_recent_gateways':
          '[{"id":"A0:DD:6C:A3:70:F2","name":"GIOS-S80-GW02",'
          '"uid":"A0DD6CA370F0"}]',
    },
  );
  await tester.runAsync(() async {
    await _topology(container, GatewayTopology.star);
    await container
        .read(commissionProvider.notifier)
        .prepare(container.read(backendEnvProvider).base, 'pw');
  });
  const step = Duration(milliseconds: 200);
  for (var t = Duration.zero; t < time; t += step) {
    await tester.pump(step);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
  await tester.pump();
  expect(container.read(commissionProvider).step, 1);
  return container;
}

String? _keyText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

/// 1.0.0+14: selects the gateway [id] on the list (its card's tap).
Future<void> _select(WidgetTester tester, String id) async {
  final card = find.byKey(ValueKey(id));
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Finder _startButton(String id) => find.byKey(ValueKey('gateway-start-$id'));

String _startText(WidgetTester tester, String id) => tester
    .widget<Text>(
      find.descendant(of: _startButton(id), matching: find.byType(Text)),
    )
    .data!;

/// Fixed scanning remains on screen, >=48 dp, and above the safe bottom edge.
/// The end action at the end of the scroll remains above this bar.
void _checkScanBar(WidgetTester tester, String where) {
  final button = find.byKey(const Key('gateway-scan-toggle'));
  expect(button, findsOneWidget, reason: '$where: unique scan button');
  expect(find.byKey(const Key('gateway-connect-bar')), findsNothing);
  final rect = tester.getRect(button);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.height, greaterThanOrEqualTo(48), reason: '$where: 48 dp');
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(screen.height + 0.5));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(screen.width + 0.5));
  final bar = tester.getRect(find.byKey(const Key('gateway-scan-bar')));
  final leave = find.byKey(const Key('page-cancel'));
  final scroll = _pageScroll(tester);
  if (scroll != null &&
      scroll.pixels >= scroll.maxScrollExtent - 0.5 &&
      leave.evaluate().isNotEmpty) {
    expect(
      tester.getRect(leave).bottom,
      lessThanOrEqualTo(bar.top + 0.5),
      reason: '$where: end action under the scan bar',
    );
  }
  if (!_realFonts) return;
  final text = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.descendant(of: button, matching: find.byType(Text)),
      matching: find.byType(RichText),
    ),
  );
  expect(text.didExceedMaxLines, isFalse, reason: '$where: scan label cut');
  expect(
    text.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(text.size.width + 0.5),
    reason: '$where: scan label wider than its box',
  );
}

/// Commissioning stays inside the card whose identity it operates on.
void _checkCardStart(WidgetTester tester, String id) {
  final start = _startButton(id);
  expect(start, findsOneWidget);
  expect(_startText(tester, id), '開始開通');
  final action = tester.getRect(start);
  final card = tester.getRect(find.byKey(ValueKey('gateway-card-$id')));
  expect(action.height, greaterThanOrEqualTo(48));
  expect(action.left, greaterThanOrEqualTo(card.left));
  expect(action.right, lessThanOrEqualTo(card.right));
  expect(action.top, greaterThanOrEqualTo(card.top));
  expect(action.bottom, lessThanOrEqualTo(card.bottom));
  final text = tester.renderObject<RenderParagraph>(
    find.descendant(of: start, matching: find.byType(RichText)),
  );
  expect(text.didExceedMaxLines, isFalse);
  expect(
    text.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(text.size.width + 0.5),
  );
}

void main() {
  setUpAll(() async => _realFonts = await loadRealFonts());

  test('real fonts are loaded (widths are checked)', () {
    // Without them only the exception check runs; say so.
    expect(_realFonts, isTrue, reason: 'Roboto / a Chinese font not found');
  });

  testWidgets('start page', (tester) async {
    await _pumpApp(tester, _TwoGateways());
    await _checkPage(tester, 'start');
  });

  testWidgets('environment sheet', (tester) async {
    await _pumpApp(tester, _TwoGateways());
    await tester.tap(find.byKey(const Key('env-chip')));
    await tester.pumpAndSettle();
    expect(find.text('切換連線環境'), findsOneWidget);
    await _checkPage(tester, 'environment sheet');
  });

  testWidgets('gateway list: the strongest marked 「最近」, first in its '
      'group; no 〔開啟權限設定〕', (tester) async {
    await _toList(tester);
    // 81/1 (-41 dBm) is the strongest: 「最近」, whatever its group.
    expect(
      find.byKey(const ValueKey('gateway-nearest-demo-gateway')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-nearest-A0:DD:6C:A3:70:F2')),
      findsNothing,
    );
    expect(find.byKey(const Key('gateway-open-settings')), findsNothing);
    expect(find.text('開啟權限設定'), findsNothing);
    expect(find.byKey(const Key('field-help-appbar')), findsOneWidget);
    await _checkPage(tester, 'gateway list');
    await tester.pumpWidget(const SizedBox());
  });

  // Selection alone never enables card commissioning; scanning stays fixed.
  testWidgets('gateway list: selected card owns commissioning; scanning '
      'fixed at the bottom, end action above it', (tester) async {
    await _toList(tester, fake: _SelectGateways());
    await _select(tester, 'demo-gateway');
    expect(
      find.byKey(const ValueKey('gateway-selected-demo-gateway')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('gateway-title-demo-gateway')),
          )
          .data,
      '站 81 · 閘道器 1',
    );
    _checkCardStart(tester, 'demo-gateway');
    expect(
      tester.widget<FilledButton>(_startButton('demo-gateway')).onPressed,
      isNull,
    );
    await _checkPage(
      tester,
      'gateway list, selected',
      also: (where) => _checkScanBar(tester, where),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gateway list, a gateway not configured selected: 「未配置閘道器」 '
      'on one line, full identity and card commissioning action whole', (
    tester,
  ) async {
    await _toList(tester, fake: _SelectGateways());
    const id = 'A0:DD:6C:A3:70:F2';
    await _select(tester, id);
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('gateway-title-$id')),
    );
    expect(title.data, '未配置閘道器');
    expect(title.maxLines, 1);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('gateway-detail-$id')))
          .data,
      '…70F0',
    );
    _checkCardStart(tester, id);
    expect(tester.widget<FilledButton>(_startButton(id)).onPressed, isNull);
    await _checkPage(
      tester,
      'gateway list, not configured selected',
      also: (where) => _checkScanBar(tester, where),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gateway list while connecting: commissioning disabled and card '
      '「連線中…」', (tester) async {
    final fake = _SelectGateways()..hold = Completer<void>();
    final container = await _toList(tester, fake: fake);
    const id = 'A0:DD:6C:A3:70:F2';
    await _select(tester, id);
    final connect = find.byKey(const Key('gateway-link-identify'));
    await tester.ensureVisible(connect);
    await tester.pump();
    await tester.tap(connect);
    await _frames(tester);
    expect(container.read(commissionProvider).discoveryLinkActive, isTrue);
    expect(tester.widget<FilledButton>(_startButton(id)).onPressed, isNull);
    _checkCardStart(tester, id);
    expect(tester.widget<FilledButton>(_startButton(id)).onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('gateway-selected-$id')),
        matching: find.text('連線中…'),
      ),
      findsOneWidget,
    );
    await _checkPage(
      tester,
      'gateway list, connecting',
      also: (where) => _checkScanBar(tester, where),
    );
    fake.hold!.complete();
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).step, 1);
    expect(tester.widget<FilledButton>(_startButton(id)).onPressed, isNotNull);
    await tester.ensureVisible(_startButton(id));
    await tester.pump();
    await tester.tap(_startButton(id));
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).step, 2);
    await tester.pumpWidget(const SizedBox());
  });

  // 1.0.0+17: the list's search — its progress area, the second search,
  // and 「未發現」 with the main 〔重新搜尋〕.
  testWidgets('gateway list while searching: the progress area, 「已找到 1 台」', (
    tester,
  ) async {
    GatewayDiscovery.searchWindow = const Duration(minutes: 10);
    addTearDown(() => GatewayDiscovery.searchWindow = gatewaySearchWindow);
    await _toSearchingList(
      tester,
      _SearchGateways(
        heard: const [GatewayPeer('demo-gateway', 'GIOS-S81-GW01', -41)],
      ),
    );
    expect(find.byKey(const Key('gateway-search-progress')), findsOneWidget);
    expect(_keyText(tester, 'gateway-search-head'), gatewaySearchingText);
    expect(_keyText(tester, 'gateway-found-count'), '已找到 1 台');
    await _checkPage(tester, 'gateway list, searching');
    expect(find.byKey(const Key('gateway-search-progress')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gateway list, nothing found: 「沒找到，再搜尋一次…」', (tester) async {
    GatewayDiscovery.searchWindow = const Duration(minutes: 10);
    addTearDown(() => GatewayDiscovery.searchWindow = gatewaySearchWindow);
    final fake = _SearchGateways(silent: 1);
    await _toSearchingList(tester, fake, time: const Duration(seconds: 2));
    expect(fake.sessions, hasLength(2), reason: 'searching once more');
    expect(_keyText(tester, 'gateway-search-head'), gatewayRetryingText);
    expect(_keyText(tester, 'gateway-found-count'), '已找到 0 台');
    await _checkPage(tester, 'gateway list, searching again');
    expect(_keyText(tester, 'gateway-search-head'), gatewayRetryingText);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gateway list, nothing found twice: 「未發現」 and the main '
      '〔重新搜尋〕 (≥ 48 dp, full width)', (tester) async {
    final fake = _SearchGateways(silent: 2);
    await _toSearchingList(tester, fake, time: const Duration(seconds: 3));
    expect(fake.sessions, hasLength(2));
    expect(find.text(gatewayNotFoundText), findsOneWidget);
    final button = find.byKey(const Key('gateway-scan-toggle'));
    expect(button, findsOneWidget);
    expect(find.byKey(const Key('gateway-scan-bar')), findsOneWidget);
    expect(find.byKey(const Key('gateway-rescan-primary')), findsNothing);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(
      find.descendant(of: button, matching: find.text('重新搜尋')),
      findsOneWidget,
    );
    await _checkPage(
      tester,
      'gateway list, not found',
      also: (where) {
        expect(button.hitTestable(), findsOneWidget, reason: where);
        final rect = tester.getRect(button);
        final width =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        expect(rect.height, greaterThanOrEqualTo(48), reason: where);
        expect(rect.width, greaterThan(width - 80), reason: where);
      },
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact ⋮ menu and its mode / appearance choices', (
    tester,
  ) async {
    await _toList(tester);
    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gateway-status-menu')), findsOneWidget);
    await _checkPage(
      tester,
      '⋮ menu',
      also: (where) {
        final items = find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem<String>,
        );
        final bounds = items
            .evaluate()
            .map((element) {
              return tester.getRect(find.byWidget(element.widget));
            })
            .reduce((a, b) => a.expandToInclude(b));
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(
          bounds.height,
          lessThan(screen.height / 2),
          reason: '$where: menu covers more than half the screen',
        );
      },
    );
    await tester.tap(find.byKey(const Key('topology-settings-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('topology-options')), findsOneWidget);
    expect(find.byKey(const Key('identify-seconds-input')), findsOneWidget);
    expect(find.byKey(const Key('identify-seconds-save')), findsOneWidget);
    await _checkPage(tester, 'connection mode choices');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-settings-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-options')), findsOneWidget);
    await _checkPage(tester, 'appearance choices');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('network check (the gateway off its Wi-Fi)', (tester) async {
    final container = await _toList(
      tester,
      fake: _TwoGateways()..simulateWifi('disconnected'),
    );
    CommissionState read() => container.read(commissionProvider);
    await _run(tester, container, (c) async {
      await c.scan();
      await c.connect(_demoPeer(container));
    });
    expect(read().step, 2);
    expect(read().checkPassed, isFalse);
    expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
    await _checkPage(tester, 'Wi-Fi reset prompt');
    await tester.tap(find.byKey(const Key('wifi-reset-later')));
    await tester.pumpAndSettle();
    await _checkPage(tester, 'network check');
    await tester.pumpWidget(const SizedBox());
  });

  // 1.0.0+15: a gateway not configured, off its Wi-Fi — 〔重設 Wi-Fi〕 opens
  // the Wi-Fi page first, then the station page says 「網路已正常」.
  testWidgets('Wi-Fi first (a gateway not configured), then the station', (
    tester,
  ) async {
    final container = await _toList(
      tester,
      fake: _TwoGateways()..simulateWifi('disconnected'),
    );
    CommissionState read() => container.read(commissionProvider);
    await _run(tester, container, (c) async {
      await c.scan();
      await c.connect(_demoPeer(container));
    });
    expect(read().checkPassed, isFalse);
    expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
    final fix = find.byKey(const Key('wifi-reset-confirm'));
    await tester.tap(fix);
    await tester.pumpAndSettle();
    expect(read().config[wifiFirstKey], isTrue);
    expect(find.byKey(const Key('wifi-first-intro')), findsOneWidget);
    await _checkPage(tester, 'Wi-Fi first');

    await _run(
      tester,
      container,
      (c) => c.configureWifiFirst('Office-2G', 'pw123456'),
    );
    expect(read().error, isNull);
    expect(read().checkPassed, isTrue);
    expect(find.byKey(const Key('wifi-first-done')), findsOneWidget);
    await _checkPage(tester, 'station after the Wi-Fi');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('station, PTU list, verify, done (star)', (tester) async {
    final container = await _toList(tester);
    CommissionState read() => container.read(commissionProvider);
    await _run(tester, container, (c) async {
      await c.scan();
      await c.connect(_demoPeer(container));
    });
    expect(read().step, 2);
    expect(read().checkPassed, isTrue);
    await _checkPage(tester, 'station');

    await _run(tester, container, (c) async {
      await c.configureWifi(80, 1, 'Office-2G', 'pw123456');
      await c.online();
      await c.discover();
    });
    expect(read().ptus, isNotEmpty);
    await _checkPage(tester, 'PTU list');

    // Logged in, the data check runs right after the assignment.
    await _run(tester, container, (c) => c.configurePtus());
    expect(read().step, 7);
    expect(read().verified, isTrue);
    // 1.0.0+13: 「請在機殼上標示：」 and 「站 80 · 閘道器 1」 in large type.
    expect(find.byKey(const Key('done-label')), findsOneWidget);
    // Secondary upload details are collapsed until explicitly opened.
    expect(find.byKey(const Key('done-upload-rate')), findsNothing);
    await _checkPage(tester, 'done');
    await openDoneSection(tester, 'commission-details');
    expect(find.byKey(const Key('done-upload-rate')), findsOneWidget);
    expect(find.text('資料上傳頻率由後台控制（目前每 5 秒）'), findsOneWidget);
    await _checkPage(tester, 'done details');
    await tester.pumpWidget(const SizedBox());
  });

  // 1.0.0+13: 「將配置為 站點 80 / 閘道器 3」 with 〔這台是來換掉壞掉的舊機〕
  // (offline: 「換機需要連上網路」), its sheet (an offline gateway 1, or
  // none) and the confirmation.
  for (final offline in [false, true]) {
    testWidgets('station with 〔這台是來換掉壞掉的舊機〕'
        '${offline ? ' (offline: 換機需要連上網路)' : ''}', (tester) async {
      final container = offline
          ? await _pumpApp(tester, _SwapGateways())
          : await _toList(tester, fake: _SwapGateways());
      CommissionState read() => container.read(commissionProvider);
      await _run(tester, container, (c) async {
        if (offline) {
          await _topology(container, GatewayTopology.star);
          await c.prepare('https://example.invalid', '', offline: true);
        }
        await c.scan();
        await c.connect(_demoPeer(container));
      });
      expect(read().step, 2);
      expect(read().checkPassed, isTrue);
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '80',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('gateway-swap')),
        offline ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const Key('gateway-swap-offline')),
        offline ? findsOneWidget : findsNothing,
      );
      await _checkPage(tester, 'station with 換機${offline ? ' offline' : ''}');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final none in [false, true]) {
    testWidgets(
      '換機 sheet (${none ? 'no offline gateway' : 'gateway 1 '
                'offline'})${none ? '' : ' and its confirmation'}',
      (tester) async {
        final container = await _toList(
          tester,
          fake: _SwapGateways(offline: !none),
        );
        await _run(tester, container, (c) async {
          await c.scan();
          await c.connect(_demoPeer(container));
        });
        await tester.enterText(
          find.widgetWithText(TextField, siteFieldLabel),
          '80',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        final swap = find.byKey(const Key('gateway-swap'));
        await tester.ensureVisible(swap);
        await tester.pumpAndSettle();
        await tester.tap(swap);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('gateway-swap-sheet')), findsOneWidget);
        expect(
          find.byKey(const Key('gateway-swap-none')),
          none ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('gateway-swap-1')),
          none ? findsNothing : findsOneWidget,
        );
        await _checkPage(tester, '換機 sheet${none ? ' (none)' : ''}');
        if (!none) {
          await tester.tap(find.byKey(const ValueKey('gateway-swap-1')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('swap-confirm')), findsOneWidget);
          await _checkPage(tester, '換機 confirmation');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('verify page (offline run: the data check waits)', (
    tester,
  ) async {
    final container = await _pumpApp(tester, _TwoGateways());
    CommissionState read() => container.read(commissionProvider);
    await _run(tester, container, (c) async {
      await _topology(container, GatewayTopology.star);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(_demoPeer(container));
      await c.configureWifi(81, 1, 'Office-2G', 'pw123456');
      // Provisioning logs in; this fixture intentionally continues offline.
      c.backendChanged('https://offline-fixture.invalid');
      await c.online(skip: true);
      await c.discover();
      await c.configurePtus();
    });
    expect(read().step, 6);
    await _checkPage(tester, 'verify');
    await tester.pumpWidget(const SizedBox());
  });

  // 1.0.0+18: the live data flow while the check runs (star, three PTUs).
  for (final (page, make) in [
    ('verify: 2 rows in', () => _VerifyGateways(holdAt: 3)),
    (
      'verify: passed, the card green',
      () => _VerifyGateways(holdConfirm: true),
    ),
    ('verify: one late row', () => _VerifyGateways(holdAt: 3, lateAt: {2})),
    // 1.0.0+20: build mode not on, the fallback refused: the 5-minute pace.
    (
      'verify: 5-minute pace',
      () => _VerifyGateways(holdAt: 3, fallbackFails: true),
    ),
  ]) {
    testWidgets(page, (tester) async {
      final fake = make();
      final container = await _pumpApp(tester, fake);
      CommissionState read() => container.read(commissionProvider);
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(() async {
        await _topology(container, GatewayTopology.star);
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        await c.connect(_demoPeer(container));
        await c.configureWifi(81, 1, 'Office-2G', 'pw123456');
        // Provisioning logs in; this fixture intentionally continues offline.
        c.backendChanged('https://offline-fixture.invalid');
        await c.online(skip: true);
        await c.discover();
        await c.configurePtus();
      });
      await tester.pumpAndSettle();
      expect(read().step, 6);
      late Future<void> run;
      await tester.runAsync(() async {
        final env = container.read(backendEnvProvider);
        run = c.verify(env.base, '', environment: env.environment.name);
        for (var i = 0; i < 400 && !fake.held; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      expect(fake.held, isTrue);
      await _frames(tester);
      final s = read();
      expect(s.busy, isTrue);
      expect(s.verifyCounts.length, greaterThan(1));
      final ids = s.verifyCounts.keys;
      if (fake.holdConfirm) {
        expect(s.verifyPassed, isTrue);
        expect(find.byKey(const Key('verify-passed-check')), findsOneWidget);
        for (final id in ids) {
          expect(s.verifyFeed.where((e) => e.id == id), hasLength(3));
        }
      } else {
        for (final id in ids) {
          final rows = s.verifyFeed.where((e) => e.id == id).toList();
          expect(rows, hasLength(2));
          expect(rows.first.ok, fake.lateAt.isEmpty);
        }
        // 3b320c7 起未計入的列（含「原因：延遲 75 秒」）收在每台 PTU 下
        // 可展開的「詳細」裡：看展開入口在不在。
        for (final id in ids) {
          expect(
            find.byKey(ValueKey('verify-feed-details-$id')),
            fake.lateAt.isEmpty ? findsNothing : findsOneWidget,
          );
        }
      }
      expect(s.verifyIntervalMs, fake.fallbackFails ? 300000 : isNull);
      if (fake.fallbackFails) {
        expect(
          _keyText(tester, 'checklist-footer'),
          startsWith('約每 5 分鐘收一筆，通常 15 分鐘內完成・剩餘 '),
        );
      }
      await _checkPage(tester, page);
      fake.hold.complete();
      await tester.runAsync(() => run);
      await tester.pumpAndSettle();
      expect(read().step, 7);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('PTU-missing card (one-to-one) and 直連進階設定', (tester) async {
    final fake = _BoundGateway();
    final container = await _pumpApp(tester, fake);
    await tester.runAsync(() async {
      await _topology(container, GatewayTopology.direct);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
    });
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).ptuMissingMac, isNotNull);
    expect(find.byKey(const Key('ptu-missing')), findsOneWidget);
    await _checkPage(tester, 'PTU missing');

    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topology-settings-menu')));
    await tester.pumpAndSettle();
    final settings = find.byKey(const Key('direct-settings'));
    expect(settings, findsOneWidget);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.text('直連進階設定'), findsOneWidget);
    await _checkPage(tester, '直連進階設定');
    await tester.pumpWidget(const SizedBox());
  });

  for (final star in [false, true]) {
    testWidgets('recent data (${star ? 'star' : 'one PTU'}), table open', (
      tester,
    ) async {
      _phone(tester);
      final now = DateTime(2026, 9, 29, 1, 34, 53);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(_Api(now, star: star)),
            backendKeyProvider.overrideWithValue('build-key'),
          ],
          child: MaterialApp(
            theme: _theme(Brightness.light),
            home: RecentDataPage(site: 81, gateway: 1, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(recentDataPageTitle), findsOneWidget);
      expect(find.text('站 81 · 閘道器 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('recent-table-tile')),
        200,
      );
      await tester.tap(find.byKey(const Key('recent-table-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-table')), findsOneWidget);
      await _checkPage(tester, 'recent data${star ? ' (star)' : ''}');
    });
  }

  // 1.0.0+20: a 5-minute interval — the data 11 minutes old (yellow) with
  // the table open, and nothing received yet (the longer empty sentence).
  for (final empty in [false, true]) {
    testWidgets('recent data, 5-minute interval${empty ? ', empty' : ''}', (
      tester,
    ) async {
      _phone(tester);
      final now = DateTime(2026, 9, 29, 1, 34, 53);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(DemoSystem()),
            apiProvider.overrideWithValue(
              _Api(
                now.add(const Duration(minutes: -11)),
                intervalMs: 300000,
                empty: empty,
              ),
            ),
            backendKeyProvider.overrideWithValue('build-key'),
          ],
          child: MaterialApp(
            theme: _theme(Brightness.light),
            home: RecentDataPage(site: 81, gateway: 1, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (empty) {
        expect(find.text(recentEmptyText(300000)), findsOneWidget);
      } else {
        expect(find.byKey(const Key('recent-banner-stale')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('recent-table-tile')),
          200,
        );
        await tester.tap(find.byKey(const Key('recent-table-tile')));
        await tester.pumpAndSettle();
      }
      await _checkPage(
        tester,
        'recent data, 5 minutes${empty ? ', empty' : ''}',
      );
    });
  }

  testWidgets('gateway status', (tester) async {
    _phone(tester);
    final now = DateTime(2026, 9, 29, 1, 34, 53);
    SharedPreferences.setMockInitialValues({
      'demo_recent_commissions':
          '[{"site":81,"gateway":1,"gateway_name":"GIOS-S81-GW01",'
          '"done_at":"2026-09-29T01:15:00"}]',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkProvider.overrideWithValue(_TwoGateways()),
          apiProvider.overrideWithValue(_Api(now)),
          backendKeyProvider.overrideWithValue('build-key'),
        ],
        child: MaterialApp(
          theme: _theme(Brightness.light),
          home: GatewayStatusPage(now: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gs-recent-81-1')), findsOneWidget);
    expect(
      find.byKey(const Key('gs-nearby-nearest-demo-gateway')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('gs-fleet-81-1-line'))).data,
      '在線・PTU 已連線・7 秒前',
    );
    await _checkPage(tester, 'gateway status');
  });
}
