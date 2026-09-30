import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/android_app_update.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/android_app_update.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'android_app_update_test.dart' show updateResponse, installedBuild20;

class _Api implements GatewayApi, AndroidUpdateDownload {
  Map<String, dynamic> response = updateResponse();
  int checks = 0;
  bool offline = false;
  Completer<void>? gate;
  Completer<void>? downloadGate;
  int downloads = 0, failDownloads = 0;
  UpdateCancellation? downloadCancellation;
  @override
  Future<void> downloadAndroidUpdate(
    AndroidAppRelease release,
    File destination,
    UpdateCancellation cancellation,
    void Function(int) onProgress,
  ) async {
    downloads++;
    downloadCancellation = cancellation;
    if (failDownloads > 0) {
      failDownloads--;
      throw const AppUpdateException('download');
    }
    onProgress(release.sizeBytes);
    await downloadGate?.future;
    cancellation.check();
  }

  @override
  Future<void> login(String base, String password) async {}
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path != '/api/app/updates/android/latest') return {};
    checks++;
    await gate?.future;
    if (offline) throw const SocketException('offline');
    return response;
  }
}

class _Platform extends AndroidUpdatePlatform {
  int reads = 0;
  int installs = 0;
  bool permissionRequired = false;
  PlatformException? installError;
  @override
  Future<InstalledAndroidApp> installed() async {
    reads++;
    return installedBuild20;
  }

  @override
  Future<File> downloadFile() async => File('synthetic-app-update.apk');
  @override
  Future<String> install(AndroidAppRelease release, File file) async {
    installs++;
    if (installError != null) throw installError!;
    return permissionRequired ? 'permission_required' : 'opened';
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Api api,
  _Platform platform, {
  bool android = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(api),
        linkProvider.overrideWithValue(DemoSystem()),
        androidUpdateSupportedProvider.overrideWithValue(android),
        androidUpdatePlatformProvider.overrideWithValue(platform),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(GatewayApp)));
}

void main() {
  testWidgets('native verification failure is not presented as a network error', (
    tester,
  ) async {
    final api = _Api();
    final platform = _Platform()
      ..installError = PlatformException(code: 'update_verification_failed');
    await _pump(tester, api, platform);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(api.downloads, 1);
    expect(platform.installs, 1);
    expect(find.text('更新檔的版本或簽章驗證失敗，請聯絡管理人員。'), findsOneWidget);
    expect(find.textContaining('確認網路'), findsNothing);
  });
  testWidgets(
    'failed download retries, then permission return continues without redownload',
    (tester) async {
      final api = _Api()..failDownloads = 1;
      final platform = _Platform()..permissionRequired = true;
      await _pump(tester, api, platform);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即更新'));
      await tester.pumpAndSettle();
      expect(find.text('重新下載'), findsOneWidget);
      expect(platform.installs, 0);
      await tester.tap(find.text('重新下載'));
      await tester.pumpAndSettle();
      expect(platform.installs, 1);
      expect(api.downloads, 2);
      expect(find.text('請允許安裝此來源的應用程式，返回後按「繼續安裝」。'), findsOneWidget);
      platform.permissionRequired = false;
      await tester.tap(find.text('繼續安裝'));
      await tester.pumpAndSettle();
      expect(platform.installs, 2);
      expect(api.downloads, 2);
      expect(find.text('請在系統畫面確認安裝。若已取消，可再按「繼續安裝」。'), findsOneWidget);
    },
  );
  testWidgets('cancelled download never opens the installer', (tester) async {
    final api = _Api()..downloadGate = Completer<void>();
    final platform = _Platform();
    await _pump(tester, api, platform);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(find.text('取消下載'), findsOneWidget);
    await tester.tap(find.text('取消下載'));
    await tester.pumpAndSettle();
    expect(api.downloadCancellation!.cancelled, isTrue);
    api.downloadGate!.complete();
    await tester.pumpAndSettle();
    expect(platform.installs, 0);
    expect(find.byKey(const Key('android-app-update-dialog')), findsNothing);
  });
  testWidgets('idle home offers 20 to 21 once and Later keeps the app usable', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api, _Platform());
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('目前版本：1.0.0（20）'), findsOneWidget);
    expect(find.text('最新版本：1.0.0（21）'), findsOneWidget);
    await tester.tap(find.text('稍後'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(api.checks, 1);
    expect(find.byKey(const Key('android-app-update-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('same build, unavailable and offline do not interrupt home', (
    tester,
  ) async {
    for (final response in [
      updateResponse(code: 20),
      {'available': false},
      updateResponse(),
    ]) {
      final api = _Api()..response = response;
      if (response['release'] is Map &&
          response['release']['version_code'] == 21) {
        api.offline = true;
      }
      await _pump(tester, api, _Platform());
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('android-app-update-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
  testWidgets('a result arriving after commissioning starts is discarded', (
    tester,
  ) async {
    final api = _Api()..gate = Completer<void>();
    final container = await _pump(tester, api, _Platform());
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(api.checks, 1);
    final prepare = container
        .read(commissionProvider.notifier)
        .prepare('https://example.invalid', '', offline: true);
    await tester.pumpAndSettle();
    await prepare;
    expect(container.read(commissionProvider).step, 1);
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('android-app-update-dialog')), findsNothing);
    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<String>>(
      find.byKey(const Key('app-update-menu')),
    );
    expect(item.enabled, isFalse);
  });
  testWidgets('iOS does not read Android metadata or expose the update menu', (
    tester,
  ) async {
    final platform = _Platform();
    final api = _Api();
    await _pump(tester, api, platform, android: false);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('topology-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-update-menu')), findsNothing);
    expect(platform.reads, 0);
    expect(api.checks, 0);
  });
}
