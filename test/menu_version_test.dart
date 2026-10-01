import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/android_app_update.dart';
import 'package:gateway_commissioning/application/ios_app_version.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/android_app_update.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _VersionPlatform extends AndroidUpdatePlatform {
  _VersionPlatform({
    this.value = const InstalledAndroidApp(31, '1.0.11', updatePackageName),
  });

  final InstalledAndroidApp value;
  Completer<InstalledAndroidApp>? pending;
  bool fail = false;
  int reads = 0;

  @override
  Future<InstalledAndroidApp> installed() async {
    reads++;
    if (fail) throw const AppUpdateException('metadata');
    return pending == null ? value : pending!.future;
  }

  @override
  Future<File> downloadFile() => throw UnimplementedError();

  @override
  Future<String> install(AndroidAppRelease release, File file) =>
      throw UnimplementedError();
}

class _MenuGateway extends DemoSystem {
  int updateChecks = 0;
  Completer<void>? scanning;

  @override
  Future<List<GatewayPeer>> scan() async {
    await scanning?.future;
    return super.scan();
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    if (path == '/api/app/updates/android/latest') {
      updateChecks++;
      return Future.value({'available': false});
    }
    return super.request(method, path, body);
  }
}

Future<(ProviderContainer, _MenuGateway)> _pump(
  WidgetTester tester,
  _VersionPlatform platform, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool android = true,
  bool ios = false,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({
    'theme_mode': brightness == Brightness.dark
        ? ThemeMode.dark.index
        : ThemeMode.light.index,
  });
  final gateway = _MenuGateway();
  await tester.pumpWidget(
    ProviderScope(
      key: ObjectKey(platform),
      overrides: [
        apiProvider.overrideWithValue(gateway),
        linkProvider.overrideWithValue(gateway),
        androidUpdateSupportedProvider.overrideWithValue(android),
        iosAppVersionSupportedProvider.overrideWithValue(ios),
        androidUpdatePlatformProvider.overrideWithValue(platform),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (
    ProviderScope.containerOf(tester.element(find.byType(GatewayApp))),
    gateway,
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('topology-menu')));
  await tester.pumpAndSettle();
}

PopupMenuItem<String> _updateItem(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('app-update-menu')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const iosChannel = MethodChannel('voltraware/app_info');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(iosChannel, null));

  for (final brightness in Brightness.values) {
    testWidgets('iOS ${brightness.name}: installed version fits the menu '
        'during commissioning without using Android updates', (tester) async {
      var reads = 0;
      messenger.setMockMethodCallHandler(iosChannel, (call) async {
        expect(call.method, 'installed');
        reads++;
        return {'versionName': '1.0.11', 'buildNumber': '21.3'};
      });
      final androidPlatform = _VersionPlatform();
      final (container, gateway) = await _pump(
        tester,
        androidPlatform,
        android: false,
        ios: true,
        brightness: brightness,
        scale: 1.3,
      );
      expect(reads, 0, reason: 'metadata is only read when the menu opens');
      await container
          .read(commissionProvider.notifier)
          .prepare('https://example.invalid', '', offline: true);
      await tester.pumpAndSettle();
      await _open(tester);
      expect(find.text('App 版本'), findsOneWidget);
      expect(find.text('版本 1.0.11 · Build 21.3'), findsOneWidget);
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
      expect(find.byKey(const Key('app-update-menu')), findsNothing);
      expect(find.text('返回首頁且結束配置後可用'), findsNothing);
      final item = tester.widget<PopupMenuItem<String>>(
        find.byKey(const Key('app-version-menu')),
      );
      expect(item.enabled, isFalse, reason: 'version is informational');
      for (final key in ['app-version-menu', 'app-installed-version']) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(640));
      }
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _open(tester);
      expect(reads, 1);
      expect(androidPlatform.reads, 0);
      expect(gateway.updateChecks, 0);
    });
  }

  testWidgets('iOS open menu receives native metadata without a guessed '
      'version or network check', (tester) async {
    final pending = Completer<Map<String, String>>();
    messenger.setMockMethodCallHandler(iosChannel, (_) => pending.future);
    final platform = _VersionPlatform();
    final (_, gateway) = await _pump(
      tester,
      platform,
      android: false,
      ios: true,
    );
    await _open(tester);
    expect(find.text('讀取中…'), findsOneWidget);
    expect(find.byKey(const Key('app-installed-version')), findsNothing);
    pending.complete({'versionName': '1.0.0', 'buildNumber': '22'});
    await tester.pumpAndSettle();
    expect(find.text('版本 1.0.0 · Build 22'), findsOneWidget);
    expect(find.text('讀取中…'), findsNothing);
    expect(platform.reads, 0);
    expect(gateway.updateChecks, 0);
  });

  testWidgets('iOS missing or malformed bundle metadata has an honest '
      'fallback and no Android update action', (tester) async {
    for (final metadata in <Map<String, Object?>?>[
      null,
      {'versionName': '', 'buildNumber': '22'},
      {'versionName': '1.0.0', 'buildNumber': ' '},
      {'versionName': '1.0.0', 'buildNumber': 22},
    ]) {
      messenger.setMockMethodCallHandler(iosChannel, (_) async {
        if (metadata == null) throw PlatformException(code: 'metadata');
        return metadata;
      });
      final platform = _VersionPlatform();
      final (_, gateway) = await _pump(
        tester,
        platform,
        android: false,
        ios: true,
      );
      await _open(tester);
      expect(find.text('暫時無法讀取版本'), findsOneWidget);
      expect(find.byKey(const Key('app-installed-version')), findsNothing);
      expect(find.byKey(const Key('app-update-menu')), findsNothing);
      expect(platform.reads, 0);
      expect(gateway.updateChecks, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('360x640 ${brightness.name} $scale: disabled update retains '
          'installed version, reason and four menu entries', (tester) async {
        final platform = _VersionPlatform();
        final (container, gateway) = await _pump(
          tester,
          platform,
          brightness: brightness,
          scale: scale,
        );
        await container
            .read(commissionProvider.notifier)
            .prepare('https://example.invalid', '', offline: true);
        await tester.pumpAndSettle();
        await _open(tester);
        expect(find.text('版本 1.0.11 · Build 31'), findsOneWidget);
        expect(find.text('返回首頁且結束配置後可用'), findsOneWidget);
        expect(_updateItem(tester).enabled, isFalse);
        expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
        for (final key in [
          'topology-settings-menu',
          'gateway-status-menu',
          'app-update-menu',
          'app-installed-version',
          'theme-settings-menu',
        ]) {
          final rect = tester.getRect(find.byKey(Key(key)));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(640));
        }
        expect(tester.takeException(), isNull);
        expect(platform.reads, 1);
        expect(gateway.updateChecks, 0);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await _open(tester);
        expect(platform.reads, 1, reason: 'installed metadata is cached');
        expect(gateway.updateChecks, 0);
      });
    }
  }

  testWidgets('an already open menu updates when installed metadata arrives '
      'without checking for updates', (tester) async {
    final platform = _VersionPlatform()
      ..pending = Completer<InstalledAndroidApp>();
    final (_, gateway) = await _pump(tester, platform);
    await _open(tester);
    expect(_updateItem(tester).enabled, isTrue);
    expect(find.byKey(const Key('app-installed-version')), findsNothing);
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('app-installed-version')), findsNothing);
    platform.pending!.complete(
      const InstalledAndroidApp(412, '9.7.2', updatePackageName),
    );
    await tester.pumpAndSettle();
    expect(find.text('版本 9.7.2 · Build 412'), findsOneWidget);
    expect(find.text('版本 1.0.11 · Build 31'), findsNothing);
    expect(gateway.updateChecks, 0);
    expect(platform.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same version name with a different installed build uses the '
      'native build code, independently of pubspec', (tester) async {
    for (final build in [7, 850]) {
      final platform = _VersionPlatform(
        value: InstalledAndroidApp(build, '4.2.1', updatePackageName),
      );
      final (_, gateway) = await _pump(tester, platform);
      await _open(tester);
      expect(find.text('版本 4.2.1 · Build $build'), findsOneWidget);
      expect(gateway.updateChecks, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('metadata failure or invalid metadata never shows a guessed '
      'version and keeps the unavailable reason', (tester) async {
    for (final platform in [
      _VersionPlatform()..fail = true,
      _VersionPlatform(
        value: const InstalledAndroidApp(31, '', updatePackageName),
      ),
      _VersionPlatform(
        value: const InstalledAndroidApp(0, '4.2.1', updatePackageName),
      ),
    ]) {
      final (container, gateway) = await _pump(tester, platform);
      await container
          .read(commissionProvider.notifier)
          .prepare('https://example.invalid', '', offline: true);
      await tester.pumpAndSettle();
      await _open(tester);
      expect(find.byKey(const Key('app-installed-version')), findsNothing);
      expect(find.text('返回首頁且結束配置後可用'), findsOneWidget);
      expect(_updateItem(tester).enabled, isFalse);
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
      expect(gateway.updateChecks, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a busy operation keeps updates disabled while version remains '
      'readable', (tester) async {
    final (container, gateway) = await _pump(tester, _VersionPlatform());
    final controller = container.read(commissionProvider.notifier);
    await controller.prepare('https://example.invalid', '', offline: true);
    gateway.scanning = Completer<void>();
    final scan = controller.scan();
    await tester.pump();
    expect(container.read(commissionProvider).busy, isTrue);
    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('版本 1.0.11 · Build 31'), findsOneWidget);
    expect(_updateItem(tester).enabled, isFalse);
    expect(find.text('返回首頁且結束配置後可用'), findsOneWidget);
    expect(find.text('操作完成後可切換'), findsOneWidget);
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
    expect(gateway.updateChecks, 0);
    gateway.scanning!.complete();
    await tester.pump();
    await scan;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-Android menu does not read Android package metadata', (
    tester,
  ) async {
    final platform = _VersionPlatform();
    final (_, gateway) = await _pump(tester, platform, android: false);
    await _open(tester);
    expect(find.byKey(const Key('app-update-menu')), findsNothing);
    expect(find.byKey(const Key('app-installed-version')), findsNothing);
    expect(platform.reads, 0);
    expect(gateway.updateChecks, 0);
  });
}
