// 1.0.0+11 (phone, 360x740 dp at text scale 1.1): 〔辨識〕 on the gateway
// list paused the scan for 2–4 s, and meanwhile every row read 「未收到廣播」
// (cutting the title to 「站 80・閘道…」), the hint above the list went away
// and came back (the list jumped), and the row's 「已送出」 was often off
// screen. The busy row above the step card had also rebuilt the list from
// scratch, losing all of it.
//
// Now, with real fonts (support/real_fonts.dart) at 1.1 and 1.3:
// - 1.0.0+22: the card's tap connects and keeps the link (the scan stops),
//   the bulb is on that card once it is up; meanwhile the rows keep their
//   last RSSI (grey), the hint stays and nothing in the list moves; after
//   the bulb a SnackBar 「站 80 · 閘道器 2 已送出」 (the row's mark stays too);
// - a remembered gateway never heard has no row; an unselected gateway
//   leaves after 30 s without a signal, while the selected one stays with
//   「訊號中斷」; a stopped scan keeps its rows; no title cut.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

import 'support/real_fonts.dart';

const _scales = [1.1, 1.3];

/// 80/2: used before (「最近使用」), the one blinked in the field.
const _gw80 = GatewayPeer('A0:DD:6C:A3:70:F2', 'GIOS-S80-GW02', -62);

/// 81/1: nearby, the strongest.
const _gw81 = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S81-GW01', -41);

const _recent80 =
    '{"id":"A0:DD:6C:A3:70:F2","name":"GIOS-S80-GW02","uid":"A0DD6CA370F0"}';

var _realFonts = false;

ThemeData _theme(Brightness b) => withRealFonts(gatewayTheme(b));

/// A live scan (one stream per start) whose connect can be held — the
/// phone's 2–4 s 〔辨識〕.
class _LiveLink extends DemoSystem implements GatewayScanner {
  final scans = <StreamController<List<GatewayPeer>>>[];
  Completer<void>? hold;

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
    await hold?.future;
    return super.connect(peer, onStage: onStage);
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

/// No one-line text cut or wider than its box, none beyond the right edge
/// (as layout_smoke_test).
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

Finder _signal(GatewayPeer peer) =>
    find.byKey(ValueKey('gateway-signal-${peer.id}'));

String? _signalText(WidgetTester tester, GatewayPeer peer) =>
    tester.widget<Text>(_signal(peer)).data;

/// Whether the row's RSSI is grey (not heard live).
bool _grey(WidgetTester tester, GatewayPeer peer) {
  final color = tester.widget<Text>(_signal(peer)).style?.color;
  return color == Theme.of(tester.element(_signal(peer))).colorScheme.outline;
}

/// Where the hint and each row sit inside the list (a jump changes them).
List<double> _places(WidgetTester tester) {
  final top = tester.getTopLeft(find.byType(GatewayDiscovery)).dy;
  return [
    for (final finder in [
      find.byKey(const Key('gateway-nearest-hint')),
      find.byKey(ValueKey('gateway-card-${_gw80.id}')),
      find.byKey(ValueKey('gateway-card-${_gw81.id}')),
    ])
      tester.getTopLeft(finder).dy - top,
  ];
}

void main() {
  setUpAll(() async => _realFonts = await loadRealFonts());

  test('real fonts are loaded (widths are checked)', () {
    expect(_realFonts, isTrue, reason: 'Roboto / a Chinese font not found');
  });

  test('the SnackBar names the gateway blinked', () {
    expect(identifiedSnackText('GIOS-S80-GW02'), '站 80 · 閘道器 2 已送出');
    expect(identifiedSnackText('GIOS-X'), 'GIOS-X 已送出');
  });

  for (final scale in _scales) {
    testWidgets('@$scale a card\'s tap connects, then its bulb: the rows keep '
        'their RSSI (grey), the hint stays, nothing moves; then a SnackBar', (
      tester,
    ) async {
      _phone(tester, scale);
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'production',
        'demo_recent_gateways': '[$_recent80]',
      });
      // A PTU is connected to the gateway: the identify reaches it too, so
      // the row and the SnackBar say the plain 「已送出」 (not the
      // gateway-only warning).
      final link = _LiveLink()..devices.first['connected'] = true;
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
      CommissionState read() => container.read(commissionProvider);
      await tester.runAsync(() async {
        await container.read(backendEnvProvider.notifier).ready;
        final topology = container.read(topologyProvider.notifier);
        await topology.ready;
        await topology.setTopology(GatewayTopology.star);
        await container
            .read(commissionProvider.notifier)
            .prepare(container.read(backendEnvProvider).base, 'pw');
      });
      await _settle(tester);
      expect(read().step, 1);
      // History alone must not create a nearby gateway card.
      expect(find.byKey(ValueKey('gateway-card-${_gw80.id}')), findsNothing);
      expect(_signal(_gw80), findsNothing);
      expect(find.text('最近使用'), findsNothing);
      expect(find.text('未收到廣播'), findsNothing);

      link.hear(const [_gw81, _gw80]);
      await tester.pump();
      final bulb80 = find.byKey(ValueKey('identify-${_gw80.id}'));
      final bulb81 = find.byKey(ValueKey('identify-${_gw81.id}'));
      // 1.0.0+22: no bulb before a card is selected and its link is up.
      expect(bulb80, findsNothing);
      expect(bulb81, findsNothing);
      await tester.ensureVisible(find.byKey(ValueKey(_gw80.id)));
      await tester.pump();
      expect(_signalText(tester, _gw80), '-62 dBm');
      expect(_signalText(tester, _gw81), '-41 dBm');
      expect(_grey(tester, _gw80), isFalse);
      expect(find.byKey(const Key('gateway-nearest-hint')), findsOneWidget);
      final before = _places(tester);
      _noCut(tester, '@$scale heard');

      // 80/2's tap, its connect held: the scan is paused (a hold is not a
      // run: nothing busy), the rows keep their RSSI (grey), the hint
      // stays, nothing moves, still no bulb.
      link.hold = Completer<void>();
      await tester.tap(find.byKey(ValueKey(_gw80.id)));
      await _settle(tester);
      expect(read().busy, isFalse);
      expect(find.text(gatewayConnectingLabel), findsOneWidget);
      expect(bulb80, findsNothing);
      expect(_signalText(tester, _gw80), '-62 dBm');
      expect(_signalText(tester, _gw81), '-41 dBm');
      expect(_grey(tester, _gw80), isTrue);
      expect(_grey(tester, _gw81), isTrue);
      expect(find.text('未收到廣播'), findsNothing);
      expect(find.byKey(const Key('gateway-nearest-hint')), findsOneWidget);
      expect(
        find.byKey(ValueKey('gateway-nearest-${_gw81.id}')),
        findsOneWidget,
      );
      expect(_places(tester), before, reason: 'the list does not move');
      _noCut(tester, '@$scale connecting');

      // Connected: 「已連線」 and the bulb on 80/2 alone; nothing moves.
      link.hold!.complete();
      await _settle(tester);
      expect(find.text(gatewayHeldLabel), findsOneWidget);
      expect(bulb80, findsOneWidget);
      expect(bulb81, findsNothing);
      expect(_places(tester), before, reason: 'the bulb moves nothing');
      _noCut(tester, '@$scale connected');

      // The bulb: over the kept link; the row's mark and a SnackBar at the
      // bottom; the scan stays paused.
      await tester.tap(bulb80);
      await _settle(tester);
      expect(read().busy, isFalse);
      expect(read().step, 1);
      final snack = find.byKey(const Key('gateway-identified-snack'));
      expect(snack, findsOneWidget);
      // 1.0.0+12: 80/2 is not in the back office's list (this fake's
      // fleet-status has only its own row): the row and the SnackBar say
      // 「未配置閘道器 …70F0」, never the old 80/2 it advertises.
      expect(
        find.descendant(of: snack, matching: find.text('未配置閘道器 …70F0 已送出')),
        findsOneWidget,
      );
      final rect = tester.getRect(snack);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(740 + 0.5));
      expect(
        find.descendant(
          of: find.byKey(ValueKey('gateway-presence-${_gw80.id}')),
          matching: find.text(identifiedHint),
        ),
        findsOneWidget,
      );
      expect(link.scans, hasLength(1), reason: 'no scan while the link is kept');
      expect(_signalText(tester, _gw80), '-62 dBm');
      expect(_grey(tester, _gw80), isTrue);
      expect(find.byKey(const Key('gateway-nearest-hint')), findsOneWidget);
      expect(
        find.byKey(ValueKey('gateway-nearest-${_gw81.id}')),
        findsOneWidget,
      );
      expect(_places(tester), before);
      _noCut(tester, '@$scale blinked');

      // Both marks go after 3 s.
      await tester.pump(identifiedHintFor + const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(identifiedHint), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  group('a row not heard', () {
    /// The list as on the page (list padding 16, the step card's padding
    /// 16), with a clock.
    Future<_LiveLink> pumpList(
      WidgetTester tester,
      double scale,
      DateTime Function() now,
    ) async {
      _phone(tester, scale);
      SharedPreferences.setMockInitialValues({
        // 80/2 and 81/1 used before; 81/1 is never heard here.
        'demo_recent_gateways':
            '[$_recent80,{"id":"AA:BB:CC:DD:3A:02","name":"GIOS-S81-GW01",'
            '"uid":"AABBCCDD3A00"}]',
      });
      final link = _LiveLink();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkProvider.overrideWithValue(link)],
          child: MaterialApp(
            theme: _theme(Brightness.light),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: GatewayDiscovery(
                        enabled: true,
                        now: now,
                        onConnect: (_) async {},
                        onIdentify: (_) async => true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _settle(tester, times: 2);
      return link;
    }

    const gw82 = GatewayPeer('AA:BB:CC:DD:3B:02', 'GIOS-S82-GW03', -70);

    for (final scale in _scales) {
      testWidgets('@$scale history alone has no row; unselected remembered '
          'and nearby gateways leave after 30 s without a signal', (
        tester,
      ) async {
        var clock = DateTime(2026, 9, 29, 3);
        final link = await pumpList(tester, scale, () => clock);
        expect(find.byKey(ValueKey('gateway-card-${_gw80.id}')), findsNothing);
        expect(find.byKey(ValueKey('gateway-card-${_gw81.id}')), findsNothing);
        expect(find.text('最近使用'), findsNothing);
        link.hear(const [_gw80, gw82]);
        await tester.pump();
        expect(_signalText(tester, _gw80), '-62 dBm');
        expect(find.byKey(ValueKey('gateway-card-${_gw81.id}')), findsNothing);
        expect(_signal(_gw81), findsNothing);
        expect(find.byKey(ValueKey('gateway-card-${gw82.id}')), findsOneWidget);
        _noCut(tester, '@$scale heard');

        // 20 s without 80/2 or 82/3: still their last RSSI, grey.
        clock = clock.add(const Duration(seconds: 20));
        link.hear(const []);
        await tester.pump(const Duration(seconds: 5));
        expect(_signalText(tester, _gw80), '-62 dBm');
        expect(_grey(tester, _gw80), isTrue);
        expect(find.byKey(ValueKey('gateway-card-${gw82.id}')), findsOneWidget);

        // Past 30 s: neither history nor a former scan result keeps a row.
        clock = clock.add(const Duration(seconds: 11));
        await tester.pump(const Duration(seconds: 5));
        expect(find.byKey(ValueKey('gateway-card-${_gw80.id}')), findsNothing);
        expect(find.byKey(ValueKey('gateway-card-${_gw81.id}')), findsNothing);
        expect(find.byKey(ValueKey('gateway-card-${gw82.id}')), findsNothing);
        expect(find.text('最近使用'), findsNothing);
        expect(find.text('未收到廣播'), findsNothing);
        _noCut(tester, '@$scale lost');
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a stopped scan keeps its rows however long; the RSSI column '
        'is as wide for every text', (tester) async {
      var clock = DateTime(2026, 9, 29, 3);
      final link = await pumpList(tester, 1.1, () => clock);
      link.hear(const [_gw80, gw82]);
      await tester.pump();
      final width = tester.getSize(_signal(_gw80)).width;
      expect(tester.getSize(_signal(gw82)).width, width, reason: 'live RSSI');
      expect(_signal(_gw81), findsNothing);
      await tester.tap(find.text('停止搜尋'));
      await _settle(tester, times: 2);
      expect(find.text('重新搜尋'), findsOneWidget);
      clock = clock.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(_signalText(tester, _gw80), '-62 dBm');
      expect(_grey(tester, _gw80), isTrue);
      expect(find.byKey(ValueKey('gateway-card-${gw82.id}')), findsOneWidget);
      // Started again: the pause does not count — 20 s later still there.
      await tester.tap(find.text('重新搜尋'));
      await _settle(tester, times: 2);
      clock = clock.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 5));
      expect(_signalText(tester, _gw80), '-62 dBm');
      expect(find.byKey(ValueKey('gateway-card-${gw82.id}')), findsOneWidget);
      // Only an explicit selection keeps a gateway after its signal is lost.
      await tester.ensureVisible(find.byKey(ValueKey(_gw80.id)));
      await tester.tap(find.byKey(ValueKey(_gw80.id)));
      await tester.pump();
      expect(
        find.byKey(ValueKey('gateway-selected-${_gw80.id}')),
        findsOneWidget,
      );
      // 11 s more: the selected gateway stays; the other one leaves.
      clock = clock.add(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 5));
      expect(_signalText(tester, _gw80), gatewaySignalLostLabel);
      expect(tester.getSize(_signal(_gw80)).width, width, reason: '訊號中斷');
      expect(find.byKey(ValueKey('gateway-card-${gw82.id}')), findsNothing);
      expect(_signal(_gw81), findsNothing);
      _noCut(tester, 'selected signal lost');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
