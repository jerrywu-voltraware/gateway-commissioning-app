import 'package:flutter/services.dart';

class InstalledIosAppVersion {
  const InstalledIosAppVersion(this.versionName, this.buildNumber);

  final String versionName, buildNumber;
}

/// Read the installed bundle, including Xcode build-time version overrides.
Future<InstalledIosAppVersion> readInstalledIosAppVersion() async {
  const channel = MethodChannel('voltraware/app_info');
  final metadata = await channel.invokeMapMethod<String, dynamic>('installed');
  final version = metadata?['versionName'];
  final build = metadata?['buildNumber'];
  if (version is! String ||
      build is! String ||
      version.trim().isEmpty ||
      build.trim().isEmpty) {
    throw const FormatException('Installed iOS version is unavailable.');
  }
  // CFBundleVersion can contain dots; do not coerce it to an Android build code.
  return InstalledIosAppVersion(version.trim(), build.trim());
}
