// Discovery keeps selection separate from Bluetooth and commissioning.
// Selection retains its outline, tint, haptics, semantics and frozen order.
// Explicit connection locks all cards until disconnect finishes; identify
// uses only that ready connection, and commissioning adopts the same peer.
// Action panels may move the card group, while card sizes/relative spacing,
// full gateway identity and the fixed bottom scan action remain readable.
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
/// a connect can be held ([hold]) or fail ([failConnects] times).
class _LiveLink extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];
  Completer<void>? hold;
  int failConnects = 0;

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
    if (failConnects > 0) {
      failConnects--;
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

Finder _start(GatewayPeer peer) =>
    find.byKey(ValueKey('gateway-start-${peer.id}'));
Finder get _scanButton => find.byKey(const Key('gateway-scan-toggle'));

String _startText(WidgetTester tester, GatewayPeer peer) => tester
    .widget<Text>(
      find.descendant(of: _start(peer), matching: find.byType(Text)),
    )
    .data!;

bool _startEnabled(WidgetTester tester, GatewayPeer peer) =>
    tester.widget<FilledButton>(_start(peer)).onPressed != null;

Future<void> _tapStart(WidgetTester tester, GatewayPeer peer) async {
  await tester.ensureVisible(_start(peer));
  await tester.pump();
  await tester.tap(_start(peer));
}

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

/// Card spacing relative to the first card — the page's scroll may
/// still be settling between two readings (ensureVisible can leave it past
/// its end for a while), the list's layout is what must not change.
Map<String, Rect> _listRects(WidgetTester tester, List<GatewayPeer> peers) {
  final origin = tester.getTopLeft(
    find.byKey(ValueKey('gateway-card-${peers.first.id}')),
  );
  return {
    for (final MapEntry(:key, :value) in _rects(tester, peers).entries)
      key: value.shift(-origin),
  };
}

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

/// The commissioning label stays whole inside the card owning its gateway.
void _startWhole(WidgetTester tester, GatewayPeer peer, String where) {
  final start = _start(peer);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: start, matching: find.byType(RichText)),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$where: start text cut',
  );
  expect(
    paragraph.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(paragraph.size.width + 0.5),
  );
  final card = tester.getRect(find.byKey(ValueKey('gateway-card-${peer.id}')));
  final action = tester.getRect(start);
  expect(action.left, greaterThanOrEqualTo(card.left));
  expect(action.right, lessThanOrEqualTo(card.right));
  expect(action.top, greaterThanOrEqualTo(card.top));
  expect(action.bottom, lessThanOrEqualTo(card.bottom));
}

Future<void> _connectForIdentify(WidgetTester tester) async {
  final connect = find.byKey(const Key('gateway-link-identify'));
  await tester.ensureVisible(connect);
  await tester.pump();
  await tester.tap(connect);
  await _settle(tester);
}

Future<void> _disconnectForSelection(WidgetTester tester) async {
  final disconnect = find.byKey(const Key('gateway-disconnect'));
  await tester.ensureVisible(disconnect);
  await tester.pump();
  await tester.tap(disconnect);
  await _settle(tester);
}

void main() {
  setUpAll(() async => _realFonts = await loadRealFonts());

  test('the texts', () {
    expect(gatewaySelectedLabel, '已選取');
    expect(gatewayConnectingLabel, '連線中…');
    expect(gatewayPickFirstLabel, '請先選擇閘道器');
    expect(gatewayConnectLabel('站 80 · 閘道器 2'), '開始開通：站 80 · 閘道器 2');
    expect(
      gatewayConnectLabel(unconfiguredGatewayTitle('…70F0')),
      '開始開通：未配置閘道器 …70F0',
    );
  });

  testWidgets(
    'selection preserves identity cues; explicit disconnect enables switching and commissioning adopts only the ready gateway',
    (tester) async {
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

      // Scanning remains fixed at the bottom; every card's start is disabled
      // until that same peer has an explicitly ready Bluetooth connection.
      expect(find.byKey(const Key('gateway-connect-bar')), findsNothing);
      expect(find.byKey(const Key('gateway-scan-bar')), findsOneWidget);
      expect(_scanButton, findsOneWidget);
      expect(tester.getSize(_scanButton).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_scanButton).width, greaterThanOrEqualTo(360 - 32));
      for (final peer in [_gw81, _gw82, _new]) {
        expect(_startText(tester, peer), '開始開通');
        expect(_startEnabled(tester, peer), isFalse);
        expect(tester.getSize(_start(peer)).height, greaterThanOrEqualTo(48));
      }
      expect(_marks, findsNothing);
      // 81/1 is 「最近」: its green chip, no outline (1.0.0+10 had one).
      expect(
        find.byKey(ValueKey('gateway-nearest-${_gw81.id}')),
        findsOneWidget,
      );
      expect(_cardOf(tester, _gw81).shape, isNull);
      for (final peer in [_gw81, _gw82, _new]) {
        expect(tester.getSize(_card(peer)).height, greaterThanOrEqualTo(48));
      }
      await tester.ensureVisible(_card(_new));
      await tester.pump();
      // 1.0.0+22: settled first (ensureVisible can leave the page past its
      // end for a moment; the comparison below is after the connect).
      await _settle(tester, times: 3);
      final before = {
        for (final peer in [_gw81, _gw82, _new])
          peer.id: tester.getSize(
            find.byKey(ValueKey('gateway-card-${peer.id}')),
          ),
      };
      final inList = _listRects(tester, [_gw81, _gw82, _new]);

      await tester.tap(_card(_gw82));
      await tester.pump();
      expect(
        {
          for (final peer in [_gw81, _gw82, _new])
            peer.id: tester.getSize(
              find.byKey(ValueKey('gateway-card-${peer.id}')),
            ),
        },
        before,
        reason: 'selection actions keep each card size unchanged',
      );
      // Selection is local. Explicit connection then retains the same peer
      // for its bulb and commissioning, without entering that flow yet.
      expect(_mark(_gw82), findsOneWidget);
      expect(_marks, findsOneWidget);
      expect(
        find.descendant(
          of: _mark(_gw82),
          matching: find.text(gatewaySelectedLabel),
        ),
        findsOneWidget,
      );
      expect(link.connected, isEmpty, reason: 'selection is local');
      expect(_startEnabled(tester, _gw82), isFalse);
      await _connectForIdentify(tester);
      expect(link.connected, [_gw82.id]);
      expect(read().step, 1);
      expect(read().peer, isNull);
      expect(read().busy, isFalse);
      expect(link.scans.last.isClosed, isTrue, reason: 'the scan stopped');
      expect(
        find.descendant(of: _mark(_gw82), matching: find.text('已連線')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _mark(_gw82),
          matching: find.byIcon(Icons.bluetooth_connected),
        ),
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
        _listRects(tester, [_gw81, _gw82, _new]),
        inList,
        reason: 'nor connecting',
      );
      // The ready card owns its commissioning action.
      expect(_startText(tester, _gw82), '開始開通');
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('gateway-title-${_gw82.id}')))
            .data,
        '站 82 · 閘道器 1',
      );
      expect(_startEnabled(tester, _gw82), isTrue);
      expect(_startEnabled(tester, _gw81), isFalse);
      expect(_startEnabled(tester, _new), isFalse);

      // A held connection locks selection until its explicit disconnect.
      expect(tester.widget<InkWell>(_card(_gw81)).onTap, isNull);
      await _disconnectForSelection(tester);
      await tester.ensureVisible(_card(_gw81));
      await tester.pump();
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
      expect(_startText(tester, _gw81), '開始開通');
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('gateway-title-${_gw81.id}')))
            .data,
        '站 81 · 閘道器 1',
      );
      expect(link.connected, [
        _gw82.id,
      ], reason: 'selecting B does not connect');
      final clicksBeforeRepeat = platform.length;
      await _tapCard(tester, _gw81);
      expect(platform.length, greaterThan(clicksBeforeRepeat));
      await _connectForIdentify(tester);
      expect(link.connected, [_gw82.id, _gw81.id]);
      expect(
        find.descendant(of: _mark(_gw81), matching: find.text('已連線')),
        findsOneWidget,
      );
      // The same card again: still selected, no second connect.
      final clicks = platform.length;
      await tester.tap(_card(_gw81));
      await tester.pump();
      await _settle(tester);
      expect(_mark(_gw81), findsOneWidget);
      expect(_marks, findsOneWidget);
      expect(platform.length, clicks, reason: 'held cards are disabled');
      expect(link.connected, [_gw82.id, _gw81.id]);
      expect(read().step, 1);
      expect(_startText(tester, _gw81), '開始開通');

      // The button goes on with the selected gateway — that one only, over
      // its link (no connect again).
      await _tapStart(tester, _gw81);
      await _settle(tester, times: 10);
      expect(link.connected, [_gw82.id, _gw81.id]);
      expect(read().peer?.id, _gw81.id);
      expect(read().step, 2);
      expect(
        _start(_gw81),
        findsNothing,
        reason: 'discovery card actions only',
      );
      expect(find.byKey(const Key('gateway-scan-bar')), findsNothing);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'explicit connect shows progress, disables switching and commissioning; failure requires explicit retry',
    (tester) async {
      final (container, link) = await _pumpList(tester);
      CommissionState read() => container.read(commissionProvider);
      link
        ..hold = Completer<void>()
        ..failConnects = 1;
      await _tapCard(tester, _gw82);
      expect(link.connected, isEmpty);
      await _connectForIdentify(tester);
      expect(read().busy, isFalse);
      expect(read().discoveryLinkActive, isTrue);
      expect(_startEnabled(tester, _gw82), isFalse);
      expect(_startText(tester, _gw82), '開始開通');
      expect(
        find.descendant(
          of: _mark(_gw82),
          matching: find.text(gatewayConnectingLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _mark(_gw82),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      for (final peer in [_gw81, _gw82, _new]) {
        expect(tester.widget<InkWell>(_card(peer)).onTap, isNull);
      }
      expect(_opacity(tester, _gw82), 1);
      await tester.ensureVisible(_card(_gw81));
      await tester.pump();
      await tester.tap(_card(_gw81));
      await tester.pump();
      expect(_mark(_gw82), findsOneWidget);
      expect(_mark(_gw81), findsNothing);
      expect(link.connected, [_gw82.id]);
      link.hold!.complete();
      await _settle(tester, times: 10);
      expect(read().step, 1);
      expect(read().busy, isFalse);
      expect(read().error, isNotNull);
      expect(
        find.descendant(
          of: _mark(_gw82),
          matching: find.text(gatewayHoldFailedLabel),
        ),
        findsOneWidget,
      );
      expect(tester.widget<InkWell>(_card(_gw81)).onTap, isNotNull);
      expect(_startEnabled(tester, _gw82), isFalse);
      expect(find.byKey(const Key('gateway-hold-snack')), findsOneWidget);
      await _connectForIdentify(tester);
      expect(_startEnabled(tester, _gw82), isTrue);
      expect(link.connected, [_gw82.id, _gw82.id]);
      await _tapStart(tester, _gw82);
      await _settle(tester, times: 10);
      expect(read().peer?.id, _gw82.id);
      expect(read().step, 2);
      expect(link.connected, [
        _gw82.id,
        _gw82.id,
      ], reason: 'commissioning adopts the ready link');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the order is frozen while a gateway is selected: '
      'its link is kept, so the scan stops and the rows keep their last RSSI '
      '(card spacing stays); disconnect then 〔重新搜尋〕 clears the selection, '
      'and the signal orders again (a gateway heard since included)', (
    tester,
  ) async {
    final (_, link) = await _pumpList(tester);
    const gw83 = GatewayPeer('AA:BB:CC:DD:3D:02', 'GIOS-S83-GW01', -35);
    final all = [_gw81, _gw82, _new, gw83];
    expect(_order(tester, all), [_gw81.id, _gw82.id, _new.id]);
    await tester.ensureVisible(_card(_new));
    await tester.pump();
    await _settle(tester, times: 3);
    final before = _listRects(tester, [_gw81, _gw82, _new]);
    final scans = link.scans.length;
    await tester.tap(_card(_new));
    await tester.pump();
    await _connectForIdentify(tester);
    expect(link.connected, [_new.id]);
    expect(link.scans.last.isClosed, isTrue, reason: 'the scan stopped');
    expect(_signalText(tester, _new), '-70 dBm', reason: 'its last RSSI');
    expect(_signalText(tester, _gw81), '-41 dBm');
    expect(find.byKey(ValueKey('gateway-nearest-${_gw81.id}')), findsOneWidget);
    expect(_order(tester, all), [_gw81.id, _gw82.id, _new.id]);
    expect(_listRects(tester, [_gw81, _gw82, _new]), before);
    expect(_mark(_new), findsOneWidget);
    expect(_startText(tester, _new), '開始開通');
    // The search's panel stays, paused (the cards do not move).
    expect(find.text(gatewaySearchPausedText), findsOneWidget);
    // No scan while the link is kept.
    expect(link.scans.length, scans);

    // 〔重新搜尋〕: the link goes; a new list — nothing selected, ordered by
    // the signal.
    final disconnects = link.linkDisconnects;
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('gateway-scan-toggle')))
          .onPressed,
      isNull,
    );
    await _disconnectForSelection(tester);
    await tester.ensureVisible(find.text('重新搜尋'));
    await tester.pump();
    await tester.tap(find.text('重新搜尋'));
    await _settle(tester, times: 2);
    expect(link.linkDisconnects, greaterThan(disconnects));
    expect(link.scans.length, scans + 1);
    expect(_marks, findsNothing);
    for (final peer in [_gw81, _gw82, _new]) {
      expect(_startEnabled(tester, peer), isFalse);
    }
    expect(_scanButton, findsOneWidget);
    for (var i = 0; i < 3; i++) {
      link.hear([
        GatewayPeer(_gw81.id, _gw81.name, -75),
        _gw82,
        GatewayPeer(_new.id, _new.name, -30),
        gw83,
      ]);
      await tester.pump(const Duration(milliseconds: 200));
    }
    final order = _order(tester, all);
    expect(order.indexOf(_new.id), lessThan(order.indexOf(_gw81.id)));
    expect(order, contains(gw83.id));
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.1, 1.3]) {
    testWidgets(
      '@$scale a gateway not configured: 「未配置閘道器」 on one line, '
      '「…70F0」 on line 3 as every card\'s tail; its commissioning label whole',
      (tester) async {
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
          tester
                  .getRect(find.byKey(ValueKey('gateway-detail-${_new.id}')))
                  .left -
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
        expect(_startText(tester, _new), '開始開通');
        _startWhole(tester, _new, '@$scale');
        expect(_startEnabled(tester, _new), isFalse);
        _noCut(tester, '@$scale selected');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('〔辨識〕: the selected, connected card\'s bulb alone (no bulb on '
      'the other cards), over the kept link, the selection unchanged; its '
      'SnackBar sits above the fixed scan bar; 〔結束配置〕 at the end of the page is '
      'above the bar', (tester) async {
    final (container, link) = await _pumpList(tester);
    CommissionState read() => container.read(commissionProvider);
    // A PTU is connected to the gateway: the identify reaches it too, so the
    // SnackBar is the plain one (not the gateway-only warning).
    link.devices.first['connected'] = true;
    // 1.0.0+22 (the phone trial): no bulb before a card is selected and
    // its link is up.
    for (final peer in [_gw81, _gw82, _new]) {
      expect(find.byKey(ValueKey('identify-${peer.id}')), findsNothing);
    }
    await _tapCard(tester, _gw81);
    await _connectForIdentify(tester);
    expect(link.connected, [_gw81.id]);
    final identify = find.byKey(ValueKey('identify-${_gw81.id}'));
    expect(identify, findsOneWidget);
    expect(find.byKey(ValueKey('identify-${_new.id}')), findsNothing);
    expect(find.byKey(ValueKey('identify-${_gw82.id}')), findsNothing);
    // Its bulb uses the held link; repeated identification is guarded.
    await tester.ensureVisible(identify);
    await tester.pump();
    await tester.tap(identify);
    await _settle(tester);
    expect(read().busy, isFalse);
    expect(read().step, 1);
    expect(_mark(_gw81), findsOneWidget);
    expect(_mark(_new), findsNothing);
    expect(_marks, findsOneWidget);
    expect(_startText(tester, _gw81), '開始開通');
    expect(_startEnabled(tester, _gw81), isTrue);
    expect(link.connected, [_gw81.id], reason: 'the bulb: no connect');
    expect(link.identifyRequests, hasLength(1));
    final snack = find.byKey(const Key('gateway-identified-snack'));
    expect(snack, findsOneWidget);
    expect(
      find.descendant(of: snack, matching: find.text('站 81 · 閘道器 1 已送出')),
      findsOneWidget,
    );
    final bar = find.byKey(const Key('gateway-scan-bar'));
    expect(
      tester.getRect(snack).bottom,
      lessThanOrEqualTo(tester.getRect(bar).top + 0.5),
    );
    expect(
      tester.getRect(snack).bottom,
      lessThanOrEqualTo(tester.getRect(_scanButton).top),
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
      expect(_scanButton, findsOneWidget);
      for (final peer in [_gw81, _gw82, _new]) {
        expect(_startEnabled(tester, peer), isFalse);
      }
      for (final peer in [_gw81, _gw82, _new]) {
        expect(_cardOf(tester, peer).shape, isNull);
      }
    }

    // 〔結束配置〕 → 結束: the start page, no bar.
    await _tapCard(tester, _gw82);
    expect(_startText(tester, _gw82), '開始開通');
    final leave = find.byKey(const Key('page-cancel'));
    await tester.scrollUntilVisible(leave, 200, scrollable: _page);
    await tester.tap(leave);
    await _settle(tester, times: 2);
    await tester.tap(find.byKey(const Key('leave-confirm-end')));
    await _settle(tester);
    expect(read().step, 0);
    expect(find.byKey(const Key('gateway-scan-bar')), findsNothing);
    await _toList(tester, container, link);
    await nothingSelected();

    // 返回 (the system back) on the list: the start page.
    await _tapCard(tester, _gw81);
    expect(_startEnabled(tester, _gw81), isFalse);
    await tester.runAsync(() => tester.binding.handlePopRoute());
    await _settle(tester);
    expect(read().step, 0);
    await _toList(tester, container, link);
    await nothingSelected();

    // Connected, then 「結束並重新選擇閘道器」 back to the list: nothing kept.
    await _tapCard(tester, _gw81);
    await _connectForIdentify(tester);
    await _tapStart(tester, _gw81);
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
                  onHold: (_) async => true,
                ),
              ],
            ),
            bottomNavigationBar: GatewayScanBar(choice: choice),
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
    expect(_startText(tester, _gw82), '開始開通');

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
    expect(_startText(tester, _gw82), '開始開通');

    // The card can commission 82/1 only after its explicit connection.
    expect(_startEnabled(tester, _gw82), isFalse);
    await _connectForIdentify(tester);
    expect(_startEnabled(tester, _gw82), isTrue);
    await _tapStart(tester, _gw82);
    await _settle(tester);
    expect(connected?.id, _gw82.id);
    await tester.pumpWidget(const SizedBox());
    expect(choice.peer, isNull, reason: 'the list gone, its selection too');
  });
}
