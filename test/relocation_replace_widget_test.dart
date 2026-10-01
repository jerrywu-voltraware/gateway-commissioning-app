// Build38 UI entry/confirmation tests. Every BLE/API operation uses the fake.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/app_theme.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/gateway_app.dart';

import 'support/real_fonts.dart';

import 'relocation_replace_test.dart' show RelocationGateway, relocationOldPtu;

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
  RelocationGateway fake, {
  required bool wifiForm,
  double scale = 1.1,
}) async {
  tester.view.physicalSize = const Size(320, 658);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
      ],
      child: const GatewayApp(theme: _theme),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  container.read(backendEnvProvider);
  await _frames(tester);
  expect(container.read(backendEnvProvider).loaded, isTrue);
  await tester.runAsync(() async {
    final topology = container.read(topologyProvider.notifier);
    await topology.ready;
    await topology.setTopology(GatewayTopology.direct);
    final c = container.read(commissionProvider.notifier);
    await c.prepare(container.read(backendEnvProvider).base, '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
  });
  await _frames(tester);
  // Keep the user on the check first; changing Wi-Fi is independently optional.
  if (find.byKey(const Key('wifi-reset-prompt')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('wifi-reset-later')));
    await tester.pumpAndSettle();
  }
  if (wifiForm) {
    await tester.runAsync(
      () => container.read(commissionProvider.notifier).startWifiFix(),
    );
    await _frames(tester);
    expect(container.read(commissionProvider).config['wifi_only'], isTrue);
    final wifiField = find.byKey(const Key('wifi-selected'));
    if (wifiField.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        wifiField,
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 30,
      );
    }
    expect(wifiField, findsOneWidget);
  }
  expect(container.read(commissionProvider).ptuMissingMac, relocationOldPtu);
  expect(container.read(commissionProvider).networkReady, isFalse);
  fake.ops.clear();
  return container;
}

Finder get _replace => find.byKey(const Key('ptu-missing-replace'));

Future<void> _dialog(WidgetTester tester) async {
  if (_replace.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      _replace,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 30,
    );
  }
  await tester.ensureVisible(_replace);
  await tester.pump();
  expect(tester.widget<FilledButton>(_replace).onPressed, isNotNull);
  await tester.tap(_replace);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  expect(find.text(replacePtuConfirmText(relocationOldPtu)), findsOneWidget);
  for (final label in ['取消', replacePtuLabel]) {
    final button = _dialogAction(label);
    await tester.ensureVisible(button);
    await tester.pump();
    expect(button.hitTestable(), findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(658));
  }
  expect(tester.takeException(), isNull);
}

Finder _dialogAction(String text) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(TextButton, text),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => expect(await loadRealFonts(), isTrue));
  late Duration savedPoll;
  setUp(() {
    savedPoll = directPollInterval;
    directPollInterval = const Duration(milliseconds: 1);
  });
  tearDown(() => directPollInterval = savedPoll);

  for (final (wifiForm, scale) in [(false, 1.1), (true, 1.1), (true, 2.0)]) {
    testWidgets('${wifiForm ? 'Wi-Fi form' : 'network check'} offers explicit '
        'local replace at font $scale; dialog cancel changes nothing', (
      tester,
    ) async {
      final fake = RelocationGateway();
      final container = await _open(
        tester,
        fake,
        wifiForm: wifiForm,
        scale: scale,
      );
      await _dialog(tester);
      expect(find.text(ptuMissingHint, skipOffstage: false), findsOneWidget);
      expect(fake.sent('set_config'), isEmpty);
      await tester.tap(_dialogAction('取消'));
      await tester.pumpAndSettle();
      expect(fake.config['direct_bind_mac'], relocationOldPtu);
      expect(fake.sent('set_config'), isEmpty);
      expect(container.read(commissionProvider).step, 2);
      await _dialog(tester);
      await tester.tap(_dialogAction(replacePtuLabel));
      await _frames(tester);
      await _frames(tester);
      final state = container.read(commissionProvider);
      expect(state.error, isNull);
      expect(state.step, 4);
      expect(state.networkReady, isFalse);
      expect(state.verified, isFalse);
      expect(fake.sent('set_wifi'), isEmpty);
      expect(fake.sent('set_site_identity'), isEmpty);
      await tester.runAsync(
        () => container.read(commissionProvider.notifier).cancel(),
      );
      expect(fake.config['direct_bind_mac'], relocationOldPtu);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'confirmation for the old MAC cannot unbind a freshly changed MAC',
    (tester) async {
      final fake = RelocationGateway();
      final container = await _open(tester, fake, wifiForm: true);
      await _dialog(tester);
      const changed = 'AA:BB:CC:00:00:03';
      fake.config['direct_bind_mac'] = changed;
      await tester.tap(_dialogAction(replacePtuLabel));
      await _frames(tester);
      final state = container.read(commissionProvider);
      expect(fake.sent('set_config'), isEmpty);
      expect(fake.config['direct_bind_mac'], changed);
      expect(state.step, 2);
      expect(state.error, isNotNull);
      expect(state.verified, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
