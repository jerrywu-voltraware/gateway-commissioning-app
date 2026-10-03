import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/presentation/wifi_credentials_form.dart';
import 'package:gateway_commissioning/data/wifi_password_store.dart';

class FakePasswordStore implements WifiPasswordStore {
  final values = <String, String>{};
  final writes = <String>[];
  Completer<String?>? pendingRead;
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read(String ssid) async {
    if (failRead) throw StateError('test-only storage error');
    final pending = pendingRead;
    pendingRead = null;
    return pending == null ? values[ssid] : await pending.future;
  }

  @override
  Future<void> write(String ssid, String password) async {
    if (failWrite) throw StateError('test-only storage error');
    writes.add(ssid);
    values[ssid] = password;
  }

  @override
  Future<void> delete(String ssid) async => values.remove(ssid);
}

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
  late FakePasswordStore store;
  late int storageErrors;
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
    store = FakePasswordStore();
    storageErrors = 0;
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

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    Future<bool> Function()? onSave,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WifiCredentialsForm(
              ssid: ssid,
              password: password,
              enabled: enabled,
              canSave: true,
              onSave:
                  onSave ??
                  () async {
                    saves++;
                    return true;
                  },
              passwordStore: store,
              onStorageError: () => storageErrors++,
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

  bool isPasswordHidden(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('wifi-password')))
      .obscureText;

  testWidgets('remembered password loads only for the exact SSID', (
    tester,
  ) async {
    store.values['Old-2G'] = 'test-only saved';
    password.clear();
    await pump(tester);
    expect(password.text, 'test-only saved');
    expect(isPasswordHidden(tester), isTrue);
    expect(find.textContaining('已帶入這支手機記住的密碼'), findsOneWidget);
    await tap(tester, 'wifi-manual');
    await tester.enterText(find.byKey(const Key('wifi-ssid')), 'old-2g');
    await tester.pumpAndSettle();
    expect(password.text, isEmpty);
    await tester.enterText(find.byKey(const Key('wifi-ssid')), 'Old-2G');
    await tester.pumpAndSettle();
    expect(password.text, 'test-only saved');
    expect(saves, 0);
  }, variant: platforms);

  testWidgets('late stored password never overwrites manual edits', (
    tester,
  ) async {
    password.clear();
    final read = Completer<String?>();
    store.pendingRead = read;
    await pump(tester);
    await tester.enterText(
      find.byKey(const Key('wifi-password')),
      'test-only typed',
    );
    read.complete('test-only saved');
    await tester.pumpAndSettle();
    expect(password.text, 'test-only typed');
  }, variant: platforms);

  for (final change in ['network', 'disable', 'dispose']) {
    testWidgets('late stored password is discarded after $change', (
      tester,
    ) async {
      password.clear();
      final read = Completer<String?>();
      store.pendingRead = read;
      await pump(tester);
      if (change == 'network') {
        await tap(tester, 'wifi-manual');
        await tester.enterText(
          find.byKey(const Key('wifi-ssid')),
          'Different-2G',
        );
      } else if (change == 'disable') {
        await pump(tester, enabled: false);
        await pump(tester);
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      read.complete('test-only stale');
      await tester.pumpAndSettle();
      expect(password.text, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'verified submission stores its snapshot even after clearing and leaving',
    (tester) async {
      final saved = Completer<bool>();
      await pump(tester, onSave: () => saved.future);
      await tap(tester, 'wifi-save');
      expect(store.writes, isEmpty);
      password.clear();
      await tester.pumpWidget(const SizedBox());
      ssid.text = 'Next-2G';
      saved.complete(true);
      await tester.pumpAndSettle();
      expect(store.values['Old-2G'], 'old-password');
      expect(store.values['Next-2G'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unverified or cancelled submission preserves the saved password',
    (tester) async {
      store.values['Old-2G'] = 'test-only valid';
      await pump(tester, onSave: () async => false);
      await tap(tester, 'wifi-save');
      expect(store.writes, isEmpty);
      expect(store.values['Old-2G'], 'test-only valid');
    },
  );

  testWidgets(
    'forget deletes the saved password and invalidates in-flight reads',
    (tester) async {
      store.values['Old-2G'] = 'test-only saved';
      password.clear();
      await pump(tester);
      await pump(tester, enabled: false);
      final read = Completer<String?>();
      store.pendingRead = read;
      await pump(tester);
      await tap(tester, 'wifi-forget-password');
      read.complete('test-only stale');
      await tester.pumpAndSettle();
      expect(password.text, isEmpty);
      expect(store.values, isEmpty);
      expect(find.byKey(const Key('wifi-forget-password')), findsNothing);
    },
  );

  testWidgets('turning remember off deletes the record but keeps this input', (
    tester,
  ) async {
    store.values['Old-2G'] = 'test-only saved';
    await pump(tester);
    await tap(tester, 'wifi-remember-password');
    expect(store.values, isEmpty);
    expect(password.text, 'old-password');
    await tap(tester, 'wifi-save');
    expect(store.writes, isEmpty);
  });

  testWidgets(
    'storage failures keep manual entry usable and never expose exceptions',
    (tester) async {
      store.failRead = true;
      await pump(tester);
      expect(find.textContaining('請手動輸入'), findsWidgets);
      expect(find.textContaining('test-only storage error'), findsNothing);
      store.failWrite = true;
      await tap(tester, 'wifi-save');
      expect(storageErrors, 1);
      expect(find.textContaining('無法記住密碼'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'password visibility changes without changing credentials or submitting',
    (tester) async {
      password.text = '  test-only 中文 !  ';
      await pump(tester);
      expect(isPasswordHidden(tester), isTrue);
      expect(find.byTooltip('顯示密碼'), findsOneWidget);
      await tap(tester, 'wifi-password-visibility');
      expect(isPasswordHidden(tester), isFalse);
      expect(find.byTooltip('隱藏密碼'), findsOneWidget);
      expect(password.text, '  test-only 中文 !  ');
      await tap(tester, 'wifi-password-visibility');
      expect(isPasswordHidden(tester), isTrue);
      expect(password.text, '  test-only 中文 !  ');
      expect(edits, 0);
      expect(saves, 0);
      expect(calls, isEmpty);
    },
    variant: platforms,
  );

  testWidgets(
    'leaving the app or disabling the form hides a revealed password',
    (tester) async {
      await pump(tester);
      await tap(tester, 'wifi-password-visibility');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(isPasswordHidden(tester), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(isPasswordHidden(tester), isTrue);
      await tap(tester, 'wifi-password-visibility');
      await pump(tester, enabled: false);
      expect(isPasswordHidden(tester), isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('wifi-password-visibility')),
            )
            .onPressed,
        isNull,
      );
      await pump(tester);
      expect(isPasswordHidden(tester), isTrue);
      expect(password.text, 'old-password');
    },
    variant: platforms,
  );

  testWidgets(
    'changing network or reopening the form resets password visibility',
    (tester) async {
      await pump(tester);
      await tap(tester, 'wifi-password-visibility');
      await tap(tester, 'wifi-manual');
      await tester.enterText(find.byKey(const Key('wifi-ssid')), 'New-2G');
      await tester.pumpAndSettle();
      expect(isPasswordHidden(tester), isTrue);
      expect(password.text, isEmpty);
      await tester.enterText(
        find.byKey(const Key('wifi-password')),
        'test-only',
      );
      await tap(tester, 'wifi-password-visibility');
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(isPasswordHidden(tester), isTrue);
      expect(password.text, 'test-only');
    },
    variant: platforms,
  );

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
