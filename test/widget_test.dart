import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/gateway_app.dart';

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
    expect(find.byType(DropdownButtonFormField<BackendEnv>), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
