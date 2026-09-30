import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

const updatePackageName = 'com.voltraware.gateway_commissioning';
const updateSignerSha256 =
    '2ae194573a906afd0a4e3ce347a275551e3e5b27a6d4a2644d36d07d102f4b64';
const maxUpdateBytes = 150 * 1024 * 1024;

class AppUpdateException implements Exception {
  const AppUpdateException(this.code);
  final String code;
}

class InstalledAndroidApp {
  const InstalledAndroidApp(
    this.versionCode,
    this.versionName,
    this.packageName,
  );
  final int versionCode;
  final String versionName, packageName;
}

class AndroidAppRelease {
  const AndroidAppRelease({
    required this.versionCode,
    required this.versionName,
    required this.tag,
    required this.notes,
    required this.path,
    required this.sha256Hex,
    required this.sizeBytes,
  });
  final int versionCode, sizeBytes;
  final String versionName, tag, notes, path, sha256Hex;

  static AndroidAppRelease? parseLatest(
    Map<String, dynamic> response,
    InstalledAndroidApp installed,
  ) {
    if (response['available'] == false) return null;
    final r = response['release'];
    if (response['available'] != true || r is! Map) {
      throw const AppUpdateException('metadata');
    }
    final apk = r['apk'];
    final code = r['version_code'];
    final name = r['version_name'];
    final tag = r['release_tag'];
    final notes = r['release_notes'];
    if (r['schema_version'] != 1 ||
        r['platform'] != 'android' ||
        r['package_name'] != updatePackageName ||
        installed.packageName != updatePackageName ||
        code is! int ||
        code < 1 ||
        code > 2100000000 ||
        name is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(name) ||
        tag != 'android-v$name-b$code' ||
        notes is! String ||
        notes.length > 20000 ||
        apk is! Map ||
        apk['signing_certificate_sha256'] != updateSignerSha256 ||
        apk['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(apk['sha256'] as String) ||
        apk['size_bytes'] is! int ||
        (apk['size_bytes'] as int) < 1 ||
        (apk['size_bytes'] as int) > maxUpdateBytes ||
        apk['url'] != '/api/app/updates/android/$tag/apk') {
      throw const AppUpdateException('metadata');
    }
    if (code <= installed.versionCode) return null;
    return AndroidAppRelease(
      versionCode: code,
      versionName: name,
      tag: tag as String,
      notes: notes,
      path: apk['url'] as String,
      sha256Hex: apk['sha256'] as String,
      sizeBytes: apk['size_bytes'] as int,
    );
  }
}

class UpdateCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get cancelled => _cancelled;
  void check() {
    if (_cancelled) throw const AppUpdateException('cancelled');
  }

  void Function() listen(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List.of(_listeners)) {
      callback();
    }
    _listeners.clear();
  }
}

abstract interface class AndroidUpdateDownload {
  Future<void> downloadAndroidUpdate(
    AndroidAppRelease release,
    File destination,
    UpdateCancellation cancellation,
    void Function(int received) onProgress,
  );
}

Stream<List<int>> _untilCancelled(
  Stream<List<int>> source,
  UpdateCancellation cancellation,
) {
  late StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  void Function()? removeCancellation;
  controller = StreamController<List<int>>(
    onListen: () {
      removeCancellation = cancellation.listen(() {
        if (!controller.isClosed) {
          controller.addError(const AppUpdateException('cancelled'));
          controller.close();
        }
        subscription?.cancel();
      });
      if (cancellation.cancelled) return;
      subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          removeCancellation?.call();
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      removeCancellation?.call();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

/// Bounded streaming into a partial file. No unverified APK is installable.
Future<void> writeVerifiedUpdate(
  Stream<List<int>> bytes,
  File destination,
  AndroidAppRelease release,
  UpdateCancellation cancellation,
  void Function(int) onProgress,
) async {
  final partial = File('${destination.path}.part');
  IOSink? sink;
  try {
    cancellation.check();
    if (release.sizeBytes < 1 || release.sizeBytes > maxUpdateBytes) {
      throw const AppUpdateException('metadata');
    }
    sink = partial.openWrite();
    var received = 0;
    await for (final chunk in _untilCancelled(bytes, cancellation)) {
      cancellation.check();
      received += chunk.length;
      if (received > release.sizeBytes) {
        throw const AppUpdateException('integrity');
      }
      sink.add(chunk);
      // Flush bounds queued memory even if storage is slower than the network.
      await sink.flush();
      onProgress(received);
    }
    await sink.close();
    sink = null;
    cancellation.check();
    if (received != release.sizeBytes ||
        (await sha256.bind(partial.openRead()).first).toString() !=
            release.sha256Hex) {
      throw const AppUpdateException('integrity');
    }
    cancellation.check();
    if (await destination.exists()) await destination.delete();
    await partial.rename(destination.path);
  } finally {
    try {
      await sink?.close();
    } catch (_) {}
    if (await partial.exists()) await partial.delete();
  }
}

abstract class AndroidUpdatePlatform {
  Future<InstalledAndroidApp> installed();
  Future<File> downloadFile();
  Future<String> install(AndroidAppRelease release, File file);
  Future<void> cancelInstall() async {}
}

class MethodChannelAndroidUpdate extends AndroidUpdatePlatform {
  static const channel = MethodChannel('voltraware/app_update');
  @override
  Future<void> cancelInstall() async {
    try {
      await channel.invokeMethod<void>('cancelInstall');
    } catch (_) {}
  }

  @override
  Future<InstalledAndroidApp> installed() async {
    final result = await channel.invokeMapMethod<String, dynamic>('installed');
    if (result == null ||
        result['versionCode'] is! int ||
        result['versionName'] is! String ||
        result['packageName'] != updatePackageName) {
      throw const AppUpdateException('metadata');
    }
    return InstalledAndroidApp(
      result['versionCode'] as int,
      result['versionName'] as String,
      result['packageName'] as String,
    );
  }

  @override
  Future<File> downloadFile() async {
    final path = await channel.invokeMethod<String>('downloadPath');
    if (path == null) throw const AppUpdateException('storage');
    return File(path);
  }

  @override
  Future<String> install(AndroidAppRelease release, File file) async {
    return await channel.invokeMethod<String>('install', {
          'path': file.path,
          'sha256': release.sha256Hex,
          'versionCode': release.versionCode,
        }) ??
        'failed';
  }
}
