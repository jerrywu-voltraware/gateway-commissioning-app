// 1.0.0+14 (user on the phone: 「我在選擇這邊的時候沒有選擇的體感，會不知道
// 是不是真的選到我要選的」): a card's tap connected at once, the card itself
// did not change, and the only word (「正在連線並讀取設定…」) was at the top
// of the list, often off screen; the green outline of 「最近」 looked like a
// selection. Picking the neighbour's gateway (the wrong pile) is one of the
// worst field errors, so now: select, then connect.
//
// - a card's tap selects its gateway (a primary outline, a tint, 「✓ 已選取」,
//   a haptic click, Semantics selected) and connects nothing; another card
//   moves the selection, the same card again keeps it;
// - the fixed bottom button 〔連線到 站 S · 閘道器 N〕 (the card's title
//   source; disabled 「請先點選要連線的閘道器」 while none is) connects to the
//   selected gateway, that one only;
// - while it connects: the button a spinner and 「連線中…」 (disabled), the
//   card 「連線中…」, the other cards faded and not tappable; a failed
//   connect leaves the selection;
// - the order is frozen while a gateway is selected (RSSI and 「最近」 still
//   change; gateways heard since come after); the selected one stays
//   listed when not heard (「訊號中斷」) and whatever the filter;
// - 「最近」 is its green chip only — no outline;
// - a gateway not configured: 「未配置閘道器」 on one line, 「…70F0」 on line
//   3 like every card's tail;
// - 〔辨識〕 does not change the selection and its SnackBar sits above the
//   button; 〔結束配置〕, 返回, 〔重新搜尋〕 and a connected gateway given up
//   clear it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

import 'support/real_fonts.dart';

/// 81/1: in the back office, the strongest (「最近」).
const _gw81 = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -41);

/// 82/1: in the back office.
const _gw82 = GatewayPeer('AA:BB:CC:DD:3C:02', 'GIOS-S82-GW01', -60);

/// The factory name 1/1: not configured — 「未配置閘道器 …70F0」.
const _new = GatewayPeer('A0:DD:6C:A3:70:F2', 'GIOS-S1-GW01', -70);

var _realFonts = false;

ThemeData _theme(Brightness b) => withRealFonts(gatewayTheme(b));

/// A live scan (one stream per start); the back office lists 81/1 and 82/1;
/// a connect can be held ([hold]) or fail once ([failConnect]).
class _LiveLink extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];
  Completer<void>? hold;
  bool failConnect = false;

  /// Every gateway the link was asked to connect to (〔辨識〕 too).
  final connected = <String>[];

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final scan = StreamController<List<GatewayPeer>>();
    scans.add(scan);
    return scan.stream;
  }

  @override
  Future<void> stopScan() async {
    for (final scan in scans) {
      if (!scan.isClosed) unawaited(scan.close());
    }
  }

  void hear(List<GatewayPeer> peers) => scans.last.add(peers);

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    connected.add(peer.id);
    await hold?.future;
    if (failConnect) {
      failConnect = false;
      throw const GatewayFailure('permission');
    }
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
        {
          'site_id': 81,
          'gateway_id': 1,
          'last_seen_mac': 'AA:BB:CC:DD:3A:00',
          'online': true,
        },
        {
          'site_id': 82,
          'gateway_id': 1,
          'last_seen_mac': 'AA:BB:CC:DD:3C:00',
          'online': true,
        },
      ],
    };
  }
}

void _phone(WidgetTester tester, double scale) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Lets real async work (the list's stop / start, the controller) run.
Future<void> _settle(WidgetTester tester, {int times = 5}) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Logged in, star, on the gateway list; 81/1, 82/1 and a new gateway heard.
Future<void> _toList(
  WidgetTester tester,
  ProviderContainer container,
  _LiveLink link,
) async {
  await tester.runAsync(() async {
    await container
        .read(commissionProvider.notifier)
        .prepare(container.read(backendEnvProvider).base, 'pw');
  });
  await _settle(tester);
  expect(container.read(commissionProvider).step, 1);
  link.hear(const [_gw81, _gw82, _new]);
  await tester.pump();
}

/// The APP ([GatewayApp]) on the gateway list.
Future<(ProviderContainer, _LiveLink)> _pumpList(
  WidgetTester tester, {
  double scale = 1.1,
}) async {
  _phone(tester, scale);
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  final link = _LiveLink();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(link),
        apiProvider.overrideWithValue(link),
        backendKeyProvider.overrideWithValue('build-key'),
      ],
      child: const GatewayApp(theme: _theme),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  await tester.runAsync(() async {
    await container.read(backendEnvProvider.notifier).ready;
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.star);
  });
  await _toList(tester, container, link);
  return (container, link);
}

/// A card's row (its [InkWell]).
Finder _card(GatewayPeer peer) => find.byKey(ValueKey(peer.id));

Card _cardOf(WidgetTester tester, GatewayPeer peer) =>
    tester.widget<Card>(find.byKey(ValueKey('gateway-card-${peer.id}')));

/// 「✓ 已選取」 (or 「連線中…」) on [peer]'s card.
Finder _mark(GatewayPeer peer) =>
    find.byKey(ValueKey('gateway-selected-${peer.id}'));

/// Every card's selection mark shown.
Finder get _marks => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('gateway-selected-'),
);

Finder get _button => find.byKey(const Key('gateway-connect'));

String _buttonText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('gateway-connect-text'))).data!;

bool _buttonEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_button).onPressed != null;

double _opacity(WidgetTester tester, GatewayPeer peer) => tester
    .widget<Opacity>(find.byKey(ValueKey('gateway-fade-${peer.id}')))
    .opacity;

String? _signalText(WidgetTester tester, GatewayPeer peer) =>
    tester.widget<Text>(find.byKey(ValueKey('gateway-signal-${peer.id}'))).data;

String _detail(WidgetTester tester, GatewayPeer peer) => tester
    .widget<Text>(find.byKey(ValueKey('gateway-detail-${peer.id}')))
    .data!;

/// The cards listed, top to bottom.
List<String> _order(WidgetTester tester, List<GatewayPeer> peers) {
  final shown = [
    for (final peer in peers)
      if (_card(peer).evaluate().isNotEmpty)
        (peer.id, tester.getRect(_card(peer)).top),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (id, _) in shown) id];
}

Map<String, Rect> _rects(WidgetTester tester, List<GatewayPeer> peers) => {
  for (final peer in peers)
    peer.id: tester.getRect(find.byKey(ValueKey('gateway-card-${peer.id}'))),
};

Future<void> _tapCard(WidgetTester tester, GatewayPeer peer) async {
  await tester.ensureVisible(_card(peer));
  await tester.pump();
  await tester.tap(_card(peer));
  await tester.pump();
}

Finder get _page => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

/// One-line text whole and the page's text inside the screen (as
/// layout_smoke_test).
void _noCut(WidgetTester tester, String where) {
  expect(tester.takeException(), isNull, reason: '$where: exception');
  expect(_realFonts, isTrue, reason: 'Roboto / a Chinese font not found');
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
        reason: '$where: 「$text」 cut',
      );
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: '$where: 「$text」 wider than its box',
      );
    }
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

/// The bottom button's text on one line, whole.
void _buttonWhole(WidgetTester tester, String where) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byKey(const Key('gateway-connect-text')),
      matching: find.byType(RichText),
    ),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: '$where: button cut');
  expect(
    paragraph.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(paragraph.size.width + 0.5),
    reason: '$where: 「${paragraph.text.toPlainText()}」 not on one line',
  );
}

void main() {
  setUpAll(() async => _realFonts = await loadRealFonts());

  test('the texts', () {
    expect(gatewaySelectedLabel, '已選取');
    expect(gatewayConnectingLabel, '連線中…');
    expect(gatewayPickFirstLabel, '請先點選要連線的閘道器');
    expect(gatewayConnectLabel('站 80 · 閘道器 2'), '連線到 站 80 · 閘道器 2');
    expect(
      gatewayConnectLabel(unconfiguredGatewayTitle('…70F0')),
      '連線到 未配置閘道器 …70F0',
    );
  });

  testWidgets('a card\'s tap selects (outline, tint, 「✓ 已選取」, a haptic '
      'click, Semantics) and connects nothing; the bottom button names it; '
      'another card moves the selection, the same one again keeps it; the '
      'button connects to the selected gateway only', (tester) async {
    final platform = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platform.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final semantics = tester.ensureSemantics();
    final (container, link) = await _pumpList(tester);
    CommissionState read() => container.read(commissionProvider);

    // Nothing selected: the bar is there, disabled, saying what to do.
    expect(_buttonText(tester), gatewayPickFirstLabel);
    expect(_buttonEnabled(tester), isFalse);
    expect(tester.getSize(_button).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(_button).width, greaterThanOrEqualTo(360 - 32));
    expect(_marks, findsNothing);
    // 81/1 is 「最近」: its green chip, no outline (1.0.0+10 had one).
    expect(find.byKey(ValueKey('gateway-nearest-${_gw81.id}')), findsOneWidget);
    expect(_cardOf(tester, _gw81).shape, isNull);
    for (final peer in [_gw81, _gw82, _new]) {
      expect(tester.getSize(_card(peer)).height, greaterThanOrEqualTo(48));
    }
    await tester.ensureVisible(_card(_new));
    await tester.pump();
    final before = _rects(tester, [_gw81, _gw82, _new]);

    await tester.tap(_card(_gw82));
    await tester.pump();
    // Selected, not connected: the scan goes on, nothing busy.
    expect(link.connected, isEmpty);
    expect(read().step, 1);
    expect(read().busy, isFalse);
    expect(link.scans.last.isClosed, isFalse);
    expect(_mark(_gw82), findsOneWidget);
    expect(_marks, findsOneWidget);
    expect(
      find.descendant(of: _mark(_gw82), matching: find.text('已選取')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _mark(_gw82), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    final colors = Theme.of(tester.element(_card(_gw82))).colorScheme;
    final shape = _cardOf(tester, _gw82).shape! as RoundedRectangleBorder;
    expect(shape.side.color, colors.primary);
    expect(shape.side.width, 2);
    expect(_cardOf(tester, _gw82).color, isNotNull);
    expect(_cardOf(tester, _gw81).shape, isNull);
    expect(_cardOf(tester, _gw81).color, isNull);
    expect(
      tester.getSemantics(find.byKey(ValueKey('gateway-select-${_gw82.id}'))),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.byKey(ValueKey('gateway-select-${_gw81.id}'))),
      isSemantics(isSelected: false),
    );
    expect(
      platform,
      contains(
        isMethodCall(
          'HapticFeedback.vibrate',
          arguments: 'HapticFeedbackType.selectionClick',
        ),
      ),
    );
    expect(
      _rects(tester, [_gw81, _gw82, _new]),
      before,
      reason: 'selecting moves nothing',
    );
    // The bottom button: the card's title.
    expect(_buttonText(tester), '連線到 站 82 · 閘道器 1');
    expect(_buttonEnabled(tester), isTrue);

    // Another card: the selection moves.
    await tester.tap(_card(_gw81));
    await tester.pump();
    expect(_mark(_gw81), findsOneWidget);
    expect(_mark(_gw82), findsNothing);
    expect(_marks, findsOneWidget);
    expect(_cardOf(tester, _gw82).shape, isNull);
    expect(
      (_cardOf(tester, _gw81).shape! as RoundedRectangleBorder).side.color,
      colors.primary,
    );
    expect(_buttonText(tester), '連線到 站 81 · 閘道器 1');
    // The same card again: still selected, still nothing connected.
    final clicks = platform.length;
    await tester.tap(_card(_gw81));
    await tester.pump();
    expect(_mark(_gw81), findsOneWidget);
    expect(_marks, findsOneWidget);
    expect(platform.length, greaterThan(clicks));
    expect(link.connected, isEmpty);
    expect(read().step, 1);
    expect(_buttonText(tester), '連線到 站 81 · 閘道器 1');

    // The button connects to the selected gateway — that one only.
    await tester.tap(_button);
    await _settle(tester, times: 10);
    expect(link.connected, [_gw81.id]);
    expect(read().peer?.id, _gw81.id);
    expect(read().step, 2);
    expect(_button, findsNothing, reason: 'the list\'s bar only');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while it connects: the button a spinner and 「連線中…」 '
      '(disabled), the card 「連線中…」, the others faded and not tappable; '
      'a failed connect keeps the selection', (tester) async {
    final (container, link) = await _pumpList(tester);
    CommissionState read() => container.read(commissionProvider);
    await _tapCard(tester, _gw82);
    link
      ..hold = Completer<void>()
      ..failConnect = true;
    await tester.tap(_button);
    await _settle(tester);
    expect(read().busy, isTrue);
    expect(_buttonEnabled(tester), isFalse);
    expect(_buttonText(tester), gatewayConnectingLabel);
    expect(
      find.descendant(
        of: _button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _mark(_gw82), matching: find.text('連線中…')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _mark(_gw82),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(_opacity(tester, _gw82), 1);
    for (final peer in [_gw81, _new]) {
      expect(_opacity(tester, peer), lessThan(0.5));
      expect(tester.widget<InkWell>(_card(peer)).onTap, isNull);
    }
    // A tap on another card changes nothing.
    await tester.ensureVisible(_card(_gw81));
    await tester.pump();
    await tester.tap(_card(_gw81));
    await tester.pump();
    expect(_mark(_gw82), findsOneWidget);
    expect(_mark(_gw81), findsNothing);

    // It fails: back to the selection and the button.
    link.hold!.complete();
    await _settle(tester, times: 10);
    expect(read().step, 1);
    expect(read().busy, isFalse);
    expect(read().error, isNotNull);
    expect(_mark(_gw82), findsOneWidget);
    expect(
      find.descendant(of: _mark(_gw82), matching: find.text('已選取')),
      findsOneWidget,
    );
    for (final peer in [_gw81, _gw82, _new]) {
      expect(_opacity(tester, peer), 1);
    }
    expect(tester.widget<InkWell>(_card(_gw81)).onTap, isNotNull);
    expect(_buttonText(tester), '連線到 站 82 · 閘道器 1');
    expect(_buttonEnabled(tester), isTrue);
    expect(link.connected, [_gw82.id]);

    // Pressed again: connected to 82/1.
    await tester.tap(_button);
    await _settle(tester, times: 10);
    expect(read().peer?.id, _gw82.id);
    expect(read().step, 2);
    expect(link.connected, [_gw82.id, _gw82.id]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the order is frozen while a gateway is selected (RSSI and '
      '「最近」 still change, a gateway heard since comes after); '
      '〔重新搜尋〕 clears the selection and the signal orders again', (
    tester,
  ) async {
    final (_, link) = await _pumpList(tester);
    const gw83 = GatewayPeer('AA:BB:CC:DD:3D:02', 'GIOS-S83-GW01', -35);
    final all = [_gw81, _gw82, _new, gw83];
    expect(_order(tester, all), [_gw81.id, _gw82.id, _new.id]);
    await _tapCard(tester, _new);
    await tester.ensureVisible(_card(_gw81));
    await tester.pump();
    final before = _rects(tester, [_gw81, _gw82, _new]);

    // The selected (weakest) gateway now much the strongest.
    link.hear([
      GatewayPeer(_gw81.id, _gw81.name, -75),
      _gw82,
      GatewayPeer(_new.id, _new.name, -30),
    ]);
    await tester.pump();
    expect(_signalText(tester, _new), '-30 dBm');
    expect(_signalText(tester, _gw81), '-75 dBm');
    expect(
      find.byKey(ValueKey('gateway-nearest-${_new.id}')),
      findsOneWidget,
      reason: '「最近」 follows the signal',
    );
    expect(find.byKey(ValueKey('gateway-nearest-${_gw81.id}')), findsNothing);
    expect(_order(tester, all), [_gw81.id, _gw82.id, _new.id]);
    expect(_rects(tester, [_gw81, _gw82, _new]), before);

    // A gateway heard since: after the others.
    link.hear([
      GatewayPeer(_gw81.id, _gw81.name, -75),
      _gw82,
      GatewayPeer(_new.id, _new.name, -30),
      gw83,
    ]);
    await tester.pump();
    expect(_order(tester, all), [_gw81.id, _gw82.id, _new.id, gw83.id]);
    expect(_mark(_new), findsOneWidget);
    expect(_buttonText(tester), '連線到 未配置閘道器 …70F0');

    // 〔停止搜尋〕 keeps it.
    await tester.ensureVisible(find.text('停止搜尋'));
    await tester.pump();
    await tester.tap(find.text('停止搜尋'));
    await _settle(tester, times: 2);
    expect(_mark(_new), findsOneWidget);
    expect(_order(tester, all), [_gw81.id, _gw82.id, _new.id, gw83.id]);
    // 〔重新搜尋〕: a new list — nothing selected, ordered by the signal.
    await tester.tap(find.text('重新搜尋'));
    await _settle(tester, times: 2);
    expect(_marks, findsNothing);
    expect(_buttonText(tester), gatewayPickFirstLabel);
    expect(_buttonEnabled(tester), isFalse);
    final order = _order(tester, all);
    expect(order.indexOf(_new.id), lessThan(order.indexOf(_gw81.id)));
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.1, 1.3]) {
    testWidgets('@$scale a gateway not configured: 「未配置閘道器」 on one line, '
        '「…70F0」 on line 3 as every card\'s tail; the button 〔連線到 '
        '未配置閘道器 …70F0〕 whole', (tester) async {
      final (_, _) = await _pumpList(tester, scale: scale);
      final title = find.byKey(ValueKey('gateway-title-${_new.id}'));
      expect(tester.widget<Text>(title).data, unconfiguredGatewayText);
      expect(tester.widget<Text>(title).maxLines, 1);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: title, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.5),
      );
      expect(find.textContaining('未配置閘道器 …'), findsNothing);
      expect(_detail(tester, _new), '…70F0');
      expect(_detail(tester, _gw81), '…3A00');
      // Line 3 as a configured card's: right under the marks, same style
      // (the title line's height differs by the fonts' metrics only).
      double line3(GatewayPeer peer) =>
          tester
              .getRect(find.byKey(ValueKey('gateway-detail-${peer.id}')))
              .top -
          tester
              .getRect(find.byKey(ValueKey('gateway-marks-${peer.id}')))
              .bottom;
      expect(line3(_new), closeTo(line3(_gw81), 0.5));
      TextStyle? style(GatewayPeer peer) => tester
          .widget<Text>(find.byKey(ValueKey('gateway-detail-${peer.id}')))
          .style;
      expect(style(_new), style(_gw81));
      expect(
        tester.getRect(find.byKey(ValueKey('gateway-detail-${_new.id}'))).left -
            tester.getRect(_card(_new)).left,
        closeTo(
          tester
                  .getRect(find.byKey(ValueKey('gateway-detail-${_gw81.id}')))
                  .left -
              tester.getRect(_card(_gw81)).left,
          0.5,
        ),
      );
      await _tapCard(tester, _new);
      expect(_buttonText(tester), '連線到 未配置閘道器 …70F0');
      _buttonWhole(tester, '@$scale');
      _noCut(tester, '@$scale selected');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('〔辨識〕 does not change the selection; its SnackBar sits above '
      'the button; 〔結束配置〕 at the end of the page is above the bar', (
    tester,
  ) async {
    final (container, link) = await _pumpList(tester);
    CommissionState read() => container.read(commissionProvider);
    await _tapCard(tester, _gw81);
    // 〔辨識〕 on another gateway, held: nothing to press meanwhile.
    link.hold = Completer<void>();
    final identify = find.byKey(ValueKey('identify-${_new.id}'));
    await tester.ensureVisible(identify);
    await tester.pump();
    await tester.tap(identify);
    await _settle(tester);
    expect(read().busy, isTrue);
    expect(_buttonEnabled(tester), isFalse);
    expect(_mark(_gw81), findsOneWidget);
    expect(_mark(_new), findsNothing);
    link.hold!.complete();
    await _settle(tester);
    expect(read().busy, isFalse);
    expect(read().step, 1);
    expect(_mark(_gw81), findsOneWidget);
    expect(_mark(_new), findsNothing);
    expect(_marks, findsOneWidget);
    expect(_buttonText(tester), '連線到 站 81 · 閘道器 1');
    expect(_buttonEnabled(tester), isTrue);
    expect(link.connected, [_new.id], reason: 'the blink only');
    final snack = find.byKey(const Key('gateway-identified-snack'));
    expect(snack, findsOneWidget);
    expect(
      find.descendant(of: snack, matching: find.text('未配置閘道器 …70F0 已閃燈')),
      findsOneWidget,
    );
    final bar = find.byKey(const Key('gateway-connect-bar'));
    expect(
      tester.getRect(snack).bottom,
      lessThanOrEqualTo(tester.getRect(bar).top + 0.5),
    );
    expect(
      tester.getRect(snack).bottom,
      lessThanOrEqualTo(tester.getRect(_button).top),
    );
    // 〔結束配置〕: at the end of the page, above the bar.
    final leave = find.byKey(const Key('page-cancel'));
    await tester.scrollUntilVisible(leave, 200, scrollable: _page);
    final scroll = Scrollable.of(tester.element(leave)).position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pump();
    expect(
      tester.getRect(leave).bottom,
      lessThanOrEqualTo(tester.getRect(bar).top + 0.5),
    );
    expect(tester.getSize(leave).height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('〔結束配置〕, 返回 and a connected gateway given up clear the '
      'selection', (tester) async {
    final (container, link) = await _pumpList(tester);
    CommissionState read() => container.read(commissionProvider);
    Future<void> nothingSelected() async {
      expect(read().step, 1);
      expect(_marks, findsNothing);
      expect(_buttonText(tester), gatewayPickFirstLabel);
      expect(_buttonEnabled(tester), isFalse);
      for (final peer in [_gw81, _gw82, _new]) {
        expect(_cardOf(tester, peer).shape, isNull);
      }
    }

    // 〔結束配置〕 → 結束: the start page, no bar.
    await _tapCard(tester, _gw82);
    expect(_buttonText(tester), '連線到 站 82 · 閘道器 1');
    final leave = find.byKey(const Key('page-cancel'));
    await tester.scrollUntilVisible(leave, 200, scrollable: _page);
    await tester.tap(leave);
    await _settle(tester, times: 2);
    await tester.tap(find.byKey(const Key('leave-confirm-end')));
    await _settle(tester);
    expect(read().step, 0);
    expect(_button, findsNothing);
    await _toList(tester, container, link);
    await nothingSelected();

    // 返回 (the system back) on the list: the start page.
    await _tapCard(tester, _gw81);
    expect(_buttonEnabled(tester), isTrue);
    await tester.runAsync(() => tester.binding.handlePopRoute());
    await _settle(tester);
    expect(read().step, 0);
    await _toList(tester, container, link);
    await nothingSelected();

    // Connected, then 「結束並重新選擇閘道器」 back to the list: nothing kept.
    await _tapCard(tester, _gw81);
    await tester.tap(_button);
    await _settle(tester, times: 10);
    expect(read().step, 2);
    await tester.runAsync(
      () => container.read(commissionProvider.notifier).cancel(),
    );
    await _settle(tester);
    link.hear(const [_gw81, _gw82, _new]);
    await tester.pump();
    await nothingSelected();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the selected gateway stays listed when not heard (「訊號中斷」) '
      'and when heard again; the others follow the rules', (tester) async {
    _phone(tester, 1.1);
    SharedPreferences.setMockInitialValues({});
    var clock = DateTime(2026, 9, 29, 3);
    final link = _LiveLink();
    final choice = GatewayChoice();
    addTearDown(choice.dispose);
    GatewayPeer? connected;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [linkProvider.overrideWithValue(link)],
        child: MaterialApp(
          theme: _theme(Brightness.light),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GatewayDiscovery(
                  enabled: true,
                  now: () => clock,
                  choice: choice,
                  onConnect: (peer) async => connected = peer,
                  onIdentify: (_) async => true,
                ),
              ],
            ),
            bottomNavigationBar: GatewayConnectBar(choice: choice),
          ),
        ),
      ),
    );
    await _settle(tester, times: 2);
    link.hear(const [_gw81, _gw82]);
    await tester.pump();
    await _tapCard(tester, _gw82);
    expect(choice.peer?.id, _gw82.id);
    expect(choice.title, '站 82 · 閘道器 1');

    // 31 s of scanning without either: 81/1 leaves, 82/1 (selected) stays.
    clock = clock.add(const Duration(seconds: 31));
    link.hear(const []);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(ValueKey('gateway-card-${_gw81.id}')), findsNothing);
    expect(find.byKey(ValueKey('gateway-card-${_gw82.id}')), findsOneWidget);
    expect(_signalText(tester, _gw82), gatewaySignalLostLabel);
    expect(_mark(_gw82), findsOneWidget);
    expect(_buttonText(tester), '連線到 站 82 · 閘道器 1');

    // Heard again with 81/1 and a new one: all listed (1.0.0+17: no filter
    // box), 82/1 still selected.
    link.hear(const [_gw81, _gw82, _new]);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    for (final peer in [_gw81, _gw82, _new]) {
      expect(
        find.byKey(ValueKey('gateway-card-${peer.id}'), skipOffstage: false),
        findsOneWidget,
      );
    }
    expect(_mark(_gw82), findsOneWidget);
    expect(_buttonText(tester), '連線到 站 82 · 閘道器 1');

    // The button connects to 82/1.
    await tester.tap(_button);
    await _settle(tester);
    expect(connected?.id, _gw82.id);
    await tester.pumpWidget(const SizedBox());
    expect(choice.peer, isNull, reason: 'the list gone, its selection too');
  });
}
