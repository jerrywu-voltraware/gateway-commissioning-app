import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ios_app_version.dart';

final iosAppVersionSupportedProvider = Provider<bool>((ref) => Platform.isIOS);

/// Package metadata stays valid for the lifetime of this app process.
final installedIosAppVersionProvider = FutureProvider<InstalledIosAppVersion?>((
  ref,
) async {
  if (!ref.watch(iosAppVersionSupportedProvider)) return null;
  try {
    return await readInstalledIosAppVersion();
  } catch (_) {
    return null;
  }
});
