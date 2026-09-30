import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/android_app_update.dart';
import 'app_session.dart';
import 'commissioning_controller.dart' show CommissionState;

final androidUpdateSupportedProvider = Provider<bool>(
  (ref) => Platform.isAndroid,
);
final androidUpdatePlatformProvider = Provider<AndroidUpdatePlatform>(
  (ref) => MethodChannelAndroidUpdate(),
);

/// Installed package metadata only; opening the menu never checks the network.
final installedAndroidAppProvider = FutureProvider<InstalledAndroidApp?>((
  ref,
) async {
  if (!ref.watch(androidUpdateSupportedProvider)) return null;
  final platform = ref.watch(androidUpdatePlatformProvider);
  try {
    final installed = await platform.installed();
    return installed.versionName.trim().isEmpty || installed.versionCode < 1
        ? null
        : installed;
  } catch (_) {
    // A missing platform response must not become a guessed build number.
    return null;
  }
});

final androidUpdateServiceProvider = Provider<AndroidUpdateService>(
  (ref) => AndroidUpdateService(
    ref.read(appSessionProvider),
    ref.read(androidUpdatePlatformProvider),
  ),
);

bool appUpdateHomeAllowed(CommissionState state, {bool connected = false}) =>
    state.step == 0 &&
    !state.busy &&
    state.peer == null &&
    !state.resumePending &&
    !connected;

class AndroidUpdateCheck {
  const AndroidUpdateCheck(this.installed, this.release);
  final InstalledAndroidApp installed;
  final AndroidAppRelease? release;
}

class AndroidUpdateService {
  AndroidUpdateService(this.session, this.platform);
  final AppSession session;
  final AndroidUpdatePlatform platform;
  bool _downloading = false;

  Future<AndroidUpdateCheck> check() async {
    final installed = await platform.installed();
    final response = await session.run(
      (api) => api.request('GET', '/api/app/updates/android/latest'),
    );
    return AndroidUpdateCheck(
      installed,
      AndroidAppRelease.parseLatest(response, installed),
    );
  }

  Future<File> download(
    AndroidAppRelease release,
    UpdateCancellation cancellation,
    void Function(int) onProgress,
  ) async {
    if (_downloading) throw const AppUpdateException('download');
    _downloading = true;
    try {
      cancellation.check();
      final file = await platform.downloadFile();
      await session.run((api) async {
        cancellation.check();
        if (api is! AndroidUpdateDownload) {
          throw const AppUpdateException('unavailable');
        }
        await (api as AndroidUpdateDownload).downloadAndroidUpdate(
          release,
          file,
          cancellation,
          onProgress,
        );
      });
      cancellation.check();
      return file;
    } finally {
      _downloading = false;
    }
  }
}
