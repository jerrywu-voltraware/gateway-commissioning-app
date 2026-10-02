import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/presentation/wifi_credentials_form.dart';

void main() {
  const wifi = MethodChannel('voltraware/wifi');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const platforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late TextEditingController ssid;
  late TextEditingController password;
  late List<String> calls;
  late int edits;
  late int saves;
  late int permission;
  late int service;
  String? current;
  PlatformException? failure;
  Completer<String?>? pending;

  setUp(() {
    ssid = TextEditingController(text: 'Old-2G');
    password = TextEditingController(text: 'old-password');
    edits = saves = 0;
    permission = service = 1;
    current = 'Office-2G';
    failure = null;
    pending = null;
    calls = [];
    messenger.setMockMethodCallHandler(permissions, (call) async {
      calls.add(call.method);
      if (call.method == 'checkServiceStatus') return service;
      if (call.method == 'requestPermissions') return {5: permission};
      if (call.method == 'openAppSettings') return true;
      throw StateError('Unexpected permission operation');
    });
    messenger.setMockMethodCallHandler(wifi, (call) async {
      calls.add(call.method);
      if (failure != null) throw failure!;
      if (call.method == 'requestLocation') {
        if (service == 0) throw PlatformException(code: 'location_off');
        if (permission != 1) {
          throw PlatformException(code: 'permission_permanently_denied');
        }
        return null;
      }
      if (call.method == 'current') return pending?.future ?? current;
      throw StateError('Unexpected Wi-Fi operation');
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(wifi, null);
    messenger.setMockMethodCallHandler(permissions, null);
    ssid.dispose();
    password.dispose();
  });

  Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WifiCredentialsForm(
              ssid: ssid,
              password: password,
              enabled: enabled,
              canSave: true,
              onSave: () => saves++,
              onNetworkEdited: () => edits++,
              saveLabel: '儲存並連接 Wi-Fi',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'phone Wi-Fi requires an explicit choice, preserves SSID, and clears old password',
    (tester) async {
      current = '  中文 "Office"  ';
      await pump(tester);
      expect(calls, isEmpty);
      expect(find.text('Old-2G'), findsOneWidget);
      await tap(tester, 'wifi-use-phone');
      expect(ssid.text, current);
      expect(password.text, isEmpty);
      expect(edits, 1);
      expect(
        calls,
        defaultTargetPlatform == TargetPlatform.iOS
            ? ['requestLocation', 'current']
            : ['checkServiceStatus', 'requestPermissions', 'current'],
      );
      expect(find.textContaining('請確認此網路支援 2.4 GHz'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Wi-Fi 密碼'),
        'new-password',
      );
      await tap(tester, 'wifi-save');
      expect(saves, 1);
    },
    variant: platforms,
  );

  testWidgets(
    'rereading the same SSID keeps the entered password; a changed phone network replaces it',
    (tester) async {
      current = 'Old-2G';
      await pump(tester);
      await tap(tester, 'wifi-use-phone');
      expect(password.text, 'old-password');
      current = 'Changed-2G';
      await tap(tester, 'wifi-use-phone');
      expect(ssid.text, 'Changed-2G');
      expect(password.text, isEmpty);
    },
    variant: platforms,
  );

  testWidgets(
    'manual entry needs no permissions and changes only after editing',
    (tester) async {
      await pump(tester);
      await tap(tester, 'wifi-manual');
      expect(password.text, 'old-password');
      await tester.enterText(find.byKey(const Key('wifi-ssid')), 'Manual-2G');
      expect(ssid.text, 'Manual-2G');
      expect(password.text, isEmpty);
      expect(calls, isEmpty);
    },
    variant: platforms,
  );

  for (final scenario in [
    'none',
    'denied',
    'permanent',
    'precise',
    'location',
    'wifi_off',
    'failure',
  ]) {
    testWidgets(
      '$scenario leaves credentials intact and allows manual fallback',
      (tester) async {
        switch (scenario) {
          case 'none':
            current = null;
          case 'denied':
            permission = 0;
          case 'permanent':
            permission = 4;
          case 'precise':
            failure = PlatformException(code: 'precise_location');
          case 'location':
            service = 0;
          case 'wifi_off':
            failure = PlatformException(code: 'wifi_off');
          case 'failure':
            failure = PlatformException(code: 'unavailable');
        }
        await pump(tester);
        await tap(tester, 'wifi-use-phone');
        expect(ssid.text, 'Old-2G');
        expect(password.text, 'old-password');
        expect(edits, 0);
        expect(find.byKey(const Key('wifi-phone-message')), findsOneWidget);
        await tap(tester, 'wifi-manual');
        await tester.enterText(find.byKey(const Key('wifi-ssid')), 'Manual-2G');
        expect(ssid.text, 'Manual-2G');
        expect(tester.takeException(), isNull);
      },
      variant: platforms,
    );
  }

  testWidgets(
    'pending read blocks save and its late result is discarded after leaving',
    (tester) async {
      pending = Completer<String?>();
      await pump(tester);
      await tap(tester, 'wifi-use-phone');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('wifi-save')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      pending!.complete('Late-2G');
      await tester.pumpAndSettle();
      expect(ssid.text, 'Old-2G');
      expect(edits, 0);
      expect(tester.takeException(), isNull);
    },
    variant: platforms,
  );

  testWidgets(
    'disabling form invalidates pending read even after it is re-enabled',
    (tester) async {
      pending = Completer<String?>();
      await pump(tester);
      await tap(tester, 'wifi-use-phone');
      await pump(tester, enabled: false);
      await pump(tester);
      pending!.complete('Late-2G');
      await tester.pumpAndSettle();
      expect(ssid.text, 'Old-2G');
      expect(edits, 0);
    },
    variant: platforms,
  );

  testWidgets(
    'native read timeout enables retry without changing credentials',
    (tester) async {
      pending = Completer<String?>();
      await pump(tester);
      await tap(tester, 'wifi-use-phone');
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.textContaining('讀取 Wi-Fi 逾時'), findsOneWidget);
      expect(ssid.text, 'Old-2G');
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('wifi-use-phone')))
            .onPressed,
        isNotNull,
      );
      pending!.complete('Late-2G');
      await tester.pumpAndSettle();
      expect(ssid.text, 'Old-2G');
    },
  );

  testWidgets(
    'both platforms show current Wi-Fi and manual entry, without a scan action',
    (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('wifi-use-phone')), findsOneWidget);
      expect(find.byKey(const Key('wifi-manual')), findsOneWidget);
      expect(find.byKey(const Key('wifi-pick')), findsNothing);
      expect(calls, isEmpty);
    },
    variant: platforms,
  );
}
