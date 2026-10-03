import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/wifi_password_store.dart';
import 'package:gateway_commissioning/presentation/wifi_credentials_form.dart';

import 'support/real_fonts.dart';

class ProbeStore implements WifiPasswordStore {
  final values = <String, String>{};
  int writes = 0;
  bool failDelete = false;

  @override
  Future<String?> read(String ssid) async => values[ssid];

  @override
  Future<void> write(String ssid, String password) async {
    writes++;
    values[ssid] = password;
  }

  @override
  Future<void> delete(String ssid) async {
    if (failDelete) throw const WifiPasswordStoreException();
    values.remove(ssid);
  }
}

void main() {
  setUpAll(() async {
    expect(await loadRealFonts(), isTrue);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> form(
    WidgetTester tester,
    TextEditingController ssid,
    TextEditingController password,
    ProbeStore store,
    Future<bool> Function() onSave, {
    double scale = 1,
    double keyboard = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: withRealFonts(ThemeData(useMaterial3: true)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const Key('wifi-review-preview'),
          child: Scaffold(
            body: SingleChildScrollView(
              child: WifiCredentialsForm(
                ssid: ssid,
                password: password,
                enabled: true,
                canSave: true,
                onSave: onSave,
                onNetworkEdited: () {},
                saveLabel: 'Save Wi-Fi',
                passwordStore: store,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('opt out remains effective when deleting the old record fails', (
    tester,
  ) async {
    final ssid = TextEditingController(text: 'Review-only A');
    final password = TextEditingController(text: 'review-new-password');
    final store = ProbeStore()
      ..values[ssid.text] = 'review-old-password'
      ..failDelete = true;
    addTearDown(ssid.dispose);
    addTearDown(password.dispose);
    await form(tester, ssid, password, store, () async => true);
    await tap(tester, 'wifi-remember-password');
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('wifi-remember-password')),
          )
          .value,
      isFalse,
    );
    await tap(tester, 'wifi-save');
    expect(store.writes, 0);
    expect(store.values[ssid.text], 'review-old-password');
  });

  testWidgets('forget in a new form revokes an older pending save', (
    tester,
  ) async {
    final ssid = TextEditingController(text: 'Review-only late');
    final password = TextEditingController(text: 'review-pending-password');
    final store = ProbeStore()..values[ssid.text] = 'review-prior-password';
    final pending = Completer<bool>();
    addTearDown(ssid.dispose);
    addTearDown(password.dispose);
    await form(tester, ssid, password, store, () => pending.future);
    await tap(tester, 'wifi-save');
    await tester.pumpWidget(const SizedBox());
    await form(tester, ssid, password, store, () async => true);
    await tap(tester, 'wifi-forget-password');
    expect(store.values[ssid.text], isNull);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(store.values[ssid.text], isNull);
    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 2x text and keyboard keep password controls reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ssid = TextEditingController(text: 'Review-only narrow');
    final password = TextEditingController(text: 'review-layout-password');
    final store = ProbeStore();
    addTearDown(ssid.dispose);
    addTearDown(password.dispose);
    await form(
      tester,
      ssid,
      password,
      store,
      () async => false,
      scale: 2,
      keyboard: 260,
    );
    await tap(tester, 'wifi-password-visibility');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('wifi-password')))
          .obscureText,
      isFalse,
    );
    await tap(tester, 'wifi-remember-password');
    await tap(tester, 'wifi-save');
    expect(tester.takeException(), isNull);
    expect(store.writes, 0);
    if (!tester
        .widget<TextField>(find.byKey(const Key('wifi-password')))
        .obscureText) {
      await tap(tester, 'wifi-password-visibility');
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('wifi-password')))
          .obscureText,
      isTrue,
    );
    final preview = Platform.environment['GIOS_WIFI_PASSWORD_PREVIEW'];
    if (preview != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('wifi-review-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  });
}
