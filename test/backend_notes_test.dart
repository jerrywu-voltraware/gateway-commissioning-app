import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

import 'support/real_fonts.dart';

// Approved copy is intentionally independent of the production constants.
const _offlineNote = '後台目前未收到此設備的連線訊號。請確認電源與 Wi-Fi；若已更換網路環境，請重新設定 Wi-Fi。';
const _noRecordNote = '目前後台查無此設備紀錄。若尚未開通，請點選『開始開通』；若已開通，請確認連線狀態與所選站點。';
const _a = GatewayPeer('AA:BB:CC:DD:3A:02', 'GIOS-S50-GW01', -40);
const _b = GatewayPeer('AA:BB:CC:DD:3B:02', 'GIOS-S51-GW01', -55);
const _aUid = 'AABBCCDD3A00';

Map<String, dynamic> _aRow({Object? online = false, bool conflict = false}) => {
  'site_id': 50,
  'gateway_id': 1,
  'last_seen_mac': _aUid,
  'online': online,
  if (conflict) 'conflict_flag': true,
};

/// Only transport data is fake; the real page chooses and renders its status.
class _Backend extends DemoSystem {
  @override
  bool get demo => false;

  List<GatewayPeer> peers = const [_a];
  List<Map<String, dynamic>> fleet = [_aRow()];
  List<Map<String, dynamic>> archived = [];
  Completer<void>? fleetGate;
  GatewayFailure? fleetFailure;
  int fleetRequests = 0;
  final commands = <String>[];

  @override
  Future<List<GatewayPeer>> scan() async => peers;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!path.contains('fleet-status')) {
      return super.request(method, path, body);
    }
    fleetRequests++;
    await fleetGate?.future;
    final failure = fleetFailure;
    if (failure != null) throw failure;
    return {'gateways': fleet, 'archived_gateways': archived};
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    commands.add(op);
    return super.command(op, params);
  }
}

ThemeData _theme(Brightness brightness) =>
    withRealFonts(gatewayTheme(brightness));

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Backend fake, {
  Size size = const Size(360, 740),
  double scale = 1,
  double bottomPadding = 0,
  bool loggedIn = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: bottomPadding);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({
    'backend_environment': 'production',
    'recent_gateways': jsonEncode([
      {'id': _a.id, 'name': _a.name, 'uid': _aUid},
      {'id': _b.id, 'name': _b.name, 'uid': 'AABBCCDD3B00'},
    ]),
    'progress': jsonEncode({
      'step': 1,
      'shown': 1,
      'completed': false,
      'site': 50,
      'gateway': 1,
      'gateway_label': '站 50 · 閘道器 1 · …3A00',
      'selected': <String>[],
      'done': <String, int>{},
      'inflight': <String, int>{},
    }),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        backendKeyProvider.overrideWithValue('test-build-key'),
        envSwitchPolicyProvider.overrideWithValue(
          const EnvSwitchPolicy(
            autoSyncDefault: false,
            confirmGatewaySwitch: true,
            localBuild: false,
          ),
        ),
      ],
      child: const GatewayApp(theme: _theme),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  // Finish the preference Future in the zone that created it, as in Build36.
  container.read(backendEnvProvider);
  await _frames(tester);
  await tester.pumpAndSettle();
  expect(container.read(backendEnvProvider).loaded, isTrue);
  await tester.runAsync(
    () => container
        .read(commissionProvider.notifier)
        .prepare(
          container.read(backendEnvProvider).base,
          '',
          offline: !loggedIn,
        ),
  );
  await _frames(tester);
  expect(container.read(commissionProvider).step, 1);
  expect(container.read(commissionProvider).loggedIn, loggedIn);
  expect(find.byType(GatewayDiscovery), findsOneWidget);
  expect(_card(_a), findsOneWidget);
  return container;
}

Finder _card(GatewayPeer peer) =>
    find.byKey(ValueKey('gateway-card-${peer.id}'));
Finder _note(GatewayPeer peer) =>
    find.byKey(ValueKey('gateway-backend-note-${peer.id}'));
Finder _start(GatewayPeer peer) =>
    find.byKey(ValueKey('gateway-start-${peer.id}'));
Finder get _page => find.byType(ListView).first;
Finder get _footer => find.byKey(const Key('gateway-scan-bar'));
Finder get _scan => find.byKey(const Key('gateway-scan-toggle'));

void _expectPresence(GatewayPeer peer, String label) {
  expect(
    find.descendant(of: _card(peer), matching: find.text(label)),
    findsOneWidget,
  );
}

void _expectNoNotes() {
  expect(find.text(_offlineNote), findsNothing);
  expect(find.text(_noRecordNote), findsNothing);
}

void _expectNoHardwareActions(_Backend fake) {
  expect(fake.connects, 0);
  expect(fake.commands, isEmpty);
}

Future<void> _close(WidgetTester tester, _Backend fake) async {
  final gate = fake.fleetGate;
  if (gate != null && !gate.isCompleted) gate.complete();
  await _frames(tester);
  _expectNoHardwareActions(fake);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
}

/// Verify complete text, including its final glyph, fits between card contents.
/// No maxLines/overflow implementation choice is assumed by the acceptance test.
void _expectFullWrappedNote(
  WidgetTester tester,
  GatewayPeer peer,
  String expected,
) {
  expect(tester.widget<Text>(_note(peer)).data, expected);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: _note(peer), matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  final lines = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: expected.length),
  );
  expect(lines.length, greaterThan(1));
  final ending = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: expected.length - 1,
      extentOffset: expected.length,
    ),
  );
  expect(
    ending,
    isNotEmpty,
    reason: 'The approved note must include its ending.',
  );
  // Fallback glyph metrics can extend beyond the paragraph's line box.
  // Judge their actual screen bounds against the card and neighboring content,
  // rather than adding an arbitrary tolerance to that typographic box.
  final card = tester.getRect(_card(peer));
  final metadata = tester.getRect(
    find.byKey(ValueKey('gateway-line3-${peer.id}')),
  );
  final actions = tester.getRect(
    find.byKey(ValueKey('gateway-actions-${peer.id}')),
  );
  final available = Rect.fromLTRB(
    card.left,
    metadata.bottom,
    card.right,
    actions.top,
  );
  expect(available.height, greaterThan(0));
  for (final box in [...lines, ...ending]) {
    final glyph = Rect.fromPoints(
      paragraph.localToGlobal(Offset(box.left, box.top)),
      paragraph.localToGlobal(Offset(box.right, box.bottom)),
    );
    expect(glyph.left, greaterThanOrEqualTo(available.left));
    expect(glyph.top, greaterThanOrEqualTo(available.top));
    expect(glyph.right, lessThanOrEqualTo(available.right));
    expect(glyph.bottom, lessThanOrEqualTo(available.bottom));
  }
}

Future<void> _showWholeCard(WidgetTester tester, GatewayPeer peer) async {
  // Saved work follows discovery in the real page, so host maxScrollExtent is
  // not the last gateway. Align the requested card explicitly, as in Build36.
  await Scrollable.ensureVisible(tester.element(_card(peer)), alignment: 1);
  await tester.pump();
  final viewport = tester.getRect(_page);
  final footer = tester.getRect(_footer);
  final card = tester.getRect(_card(peer));
  final note = tester.getRect(_note(peer));
  final start = tester.getRect(_start(peer));
  expect(viewport.bottom, lessThanOrEqualTo(footer.top));
  for (final rect in [card, note, start]) {
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.bottom, lessThanOrEqualTo(footer.top));
    expect(rect.left, greaterThanOrEqualTo(viewport.left));
    expect(rect.right, lessThanOrEqualTo(viewport.right));
  }
  expect(_start(peer).hitTestable(), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(await loadRealFonts(), isTrue);
  });

  testWidgets('offline and no-record cards show only their approved note', (
    tester,
  ) async {
    final fake = _Backend()..peers = const [_a, _b];
    await _open(tester, fake);
    _expectPresence(_a, '後端離線');
    _expectPresence(_b, '後端無紀錄');
    expect(tester.widget<Text>(_note(_a)).data, _offlineNote);
    expect(tester.widget<Text>(_note(_b)).data, _noRecordNote);
    expect(find.text(_offlineNote), findsOneWidget);
    expect(find.text(_noRecordNote), findsOneWidget);
    for (final peer in [_a, _b]) {
      expect(tester.widget<FilledButton>(_start(peer)).onPressed, isNull);
    }
    await _close(tester, fake);
  });

  for (final scenario in [
    (
      name: 'online',
      fleet: [_aRow(online: true)],
      archived: <Map<String, dynamic>>[],
      presence: '後端在線',
    ),
    (
      name: 'unknown online value',
      fleet: [_aRow(online: null)],
      archived: <Map<String, dynamic>>[],
      presence: '後端未知',
    ),
    (
      name: 'identity conflict',
      fleet: [_aRow(conflict: true)],
      archived: <Map<String, dynamic>>[],
      presence: '後端未知',
    ),
    (
      name: 'duplicate UID',
      fleet: [_aRow(), _aRow()],
      archived: <Map<String, dynamic>>[],
      presence: '後端未知',
    ),
    (
      name: 'archived',
      fleet: <Map<String, dynamic>>[],
      archived: [_aRow()],
      presence: '後端已封存',
    ),
  ]) {
    testWidgets('${scenario.name} is not mislabeled offline or unregistered', (
      tester,
    ) async {
      final fake = _Backend()
        ..fleet = scenario.fleet
        ..archived = scenario.archived;
      await _open(tester, fake);
      _expectPresence(_a, scenario.presence);
      _expectNoNotes();
      await _close(tester, fake);
    });
  }

  testWidgets('initial backend loading does not imply no record', (
    tester,
  ) async {
    final fake = _Backend()..fleetGate = Completer<void>();
    await _open(tester, fake);
    expect(fake.fleetRequests, greaterThan(0));
    _expectPresence(_a, '後端未知');
    _expectNoNotes();
    fake.fleetGate!.complete();
    await _frames(tester);
    _expectPresence(_a, '後端離線');
    expect(find.text(_offlineNote), findsOneWidget);
    await _close(tester, fake);
  });

  for (final code in ['network', 'authentication']) {
    testWidgets('$code query failure does not imply no record', (tester) async {
      final fake = _Backend()..fleetFailure = GatewayFailure(code);
      await _open(tester, fake);
      expect(fake.fleetRequests, greaterThan(0));
      expect(find.byKey(const Key('gateway-backend-error')), findsOneWidget);
      _expectPresence(_a, '後端未知');
      _expectNoNotes();
      await _close(tester, fake);
    });
  }

  testWidgets('no backend login does not imply no record', (tester) async {
    final fake = _Backend();
    await _open(tester, fake, loggedIn: false);
    expect(fake.fleetRequests, 0);
    _expectPresence(_a, '後端未知');
    _expectNoNotes();
    await _close(tester, fake);
  });

  testWidgets(
    'fresh cached status stays during refresh and clears on failure',
    (tester) async {
      final fake = _Backend();
      await _open(tester, fake);
      expect(find.text(_offlineNote), findsOneWidget);
      final queriesBefore = fake.fleetRequests;
      fake.fleetGate = Completer<void>();
      await tester.pump(const Duration(seconds: 15));
      await _frames(tester);
      expect(fake.fleetRequests, greaterThan(queriesBefore));
      // The existing 30-second cache stays usable while a refresh is pending.
      // This is distinct from the first-load unknown state tested above.
      expect(find.text(_offlineNote), findsOneWidget);
      fake.fleetFailure = const GatewayFailure('network');
      fake.fleetGate!.complete();
      await _frames(tester);
      _expectPresence(_a, '後端未知');
      _expectNoNotes();
      await _close(tester, fake);
    },
  );

  test('stale status resolved to unknown receives no actionable note', () {
    // _tile already maps stale or logged-out backend state to this label.
    // Its native DateTime clock is unchanged by Build37; this asserts only the
    // new presentation boundary and does not claim a simulated cache expiry.
    expect(gatewayBackendNoteFor('後端未知'), isNull);
  });

  for (final scenario in const [
    (size: Size(320, 658), scale: 1.1),
    (size: Size(320, 640), scale: 1.3),
    (size: Size(360, 640), scale: 1.0),
  ]) {
    testWidgets(
      '${scenario.size.width.toInt()}x${scenario.size.height.toInt()} '
      '@${scenario.scale} complete notes wrap without clipping or footer overlap',
      (tester) async {
        final fake = _Backend()..peers = const [_a, _b];
        await _open(
          tester,
          fake,
          size: scenario.size,
          scale: scenario.scale,
          bottomPadding: 34,
        );
        final footerBefore = tester.getRect(_footer);
        if (scenario.size == const Size(320, 658) && scenario.scale == 1.1) {
          // At the measured phone size, the first note and action are visible
          // immediately; no ensureVisible or scroll has run yet.
          for (final element in [_note(_a), _start(_a)]) {
            final rect = tester.getRect(element);
            expect(rect.top, greaterThanOrEqualTo(tester.getRect(_page).top));
            expect(rect.bottom, lessThanOrEqualTo(footerBefore.top));
          }
          expect(_start(_a).hitTestable(), findsOneWidget);
          final scrolling = tester.state<ScrollableState>(
            find.descendant(of: _page, matching: find.byType(Scrollable)).first,
          );
          expect(scrolling.position.pixels, 0);
        }
        for (final entry in [(_a, _offlineNote), (_b, _noRecordNote)]) {
          await _showWholeCard(tester, entry.$1);
          _expectFullWrappedNote(tester, entry.$1, entry.$2);
          expect(tester.getRect(_footer), footerBefore);
          expect(_scan.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(_scan).bottom,
            lessThanOrEqualTo(scenario.size.height - 34),
          );
        }
        await _close(tester, fake);
      },
    );
  }

  testWidgets('long-list final no-record note and actions remain reachable', (
    tester,
  ) async {
    const last = GatewayPeer('AA:BB:CC:DD:49:02', 'GIOS-S99-GW01', -90);
    final fake = _Backend()
      ..peers = [
        _a,
        _b,
        for (var i = 2; i < 8; i++)
          GatewayPeer('peer-$i', 'GIOS-S${60 + i}-GW01', -60 - i),
        last,
      ];
    await _open(
      tester,
      fake,
      size: const Size(320, 640),
      scale: 1.3,
      bottomPadding: 34,
    );
    final footerBefore = tester.getRect(_footer);
    await _showWholeCard(tester, last);
    _expectFullWrappedNote(tester, last, _noRecordNote);
    _expectPresence(last, '後端無紀錄');
    final scrolling = tester.state<ScrollableState>(
      find.descendant(of: _page, matching: find.byType(Scrollable)).first,
    );
    expect(scrolling.position.pixels, greaterThan(0));
    expect(tester.getRect(_footer), footerBefore);
    expect(_scan.hitTestable(), findsOneWidget);
    await _close(tester, fake);
  });
}
