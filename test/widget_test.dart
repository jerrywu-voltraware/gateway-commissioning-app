import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/next_action_guide.dart'
    show nextActionStartCaption;

import 'support/l10n.dart';

void main() {
  testWidgets('saved USB URL migrates to LAN backend', (tester) async {
    SharedPreferences.setMockInitialValues({
      'backend_environment': 'local',
      'backend_local_url': 'http://127.0.0.1:18000',
    });
    await tester.pumpWidget(const ProviderScope(child: GatewayApp()));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_local_url'), 'http://192.168.0.12:18000');
    expect(find.text('http://127.0.0.1:18000'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('initial screen renders on narrow device', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: GatewayApp()));
    await tester.pumpAndSettle();
    // 1.0.0+8: no environment dropdown and no demo switch on the start
    // page; the offline checkbox is still there.
    expect(find.byType(DropdownButtonFormField<BackendEnv>), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  // i18n Phase B2 (commissioning_page): the start page and the 更多 menu
  // follow the APP language; the hint row above 〔檢查並開始〕 shows its own
  // caption (not the button name a second time).
  testWidgets('start page and 更多 menu in English; one start button', (
    tester,
  ) async {
    await pumpApp(tester, prefs: {'app_locale': 'en'});
    expect(find.text('Check and start'), findsOneWidget);
    expect(find.text(nextActionStartCaption), findsOneWidget);
    expect(find.text('Log in to the back office to start'), findsOneWidget);
    expect(find.text('檢查並開始'), findsNothing);
    await tester.tap(find.byKey(const Key('topology-menu')));
    await pumpFrames(tester);
    expect(find.text('Connection mode'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('繁中 start page: 〔檢查並開始〕 once, its caption above it', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('檢查並開始'), findsOneWidget);
    expect(find.text(nextActionStartCaption), findsOneWidget);
    expect(find.text('登入後台，開始配置'), findsOneWidget);
  });
}
