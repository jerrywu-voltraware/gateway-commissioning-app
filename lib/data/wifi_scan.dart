import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiNetwork {
  const WifiNetwork(this.ssid, this.rssi);
  final String ssid;
  final int rssi;
}

bool get canScanWifiNetworks =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Reads only the phone's connected SSID. Permission is requested only after
/// the user chooses to use it; no password, scan results or location is read.
Future<String?> readCurrentWifiSsid() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    throw PlatformException(code: 'unsupported');
  }
  const channel = MethodChannel('voltraware/wifi');
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // CoreLocation authorization is handled by the native bridge, independent
    // of permission_handler's cached Swift Package permission build flags.
    await channel.invokeMethod<void>('requestLocation');
  } else {
    if (!await Permission.locationWhenInUse.serviceStatus.isEnabled) {
      throw PlatformException(code: 'location_off');
    }
    final permission = await Permission.locationWhenInUse.request();
    if (!permission.isGranted) {
      throw PlatformException(
        code: permission.isPermanentlyDenied
            ? 'permission_permanently_denied'
            : 'permission',
      );
    }
  }
  final ssid = await channel
      .invokeMethod<String>('current')
      .timeout(const Duration(seconds: 8));
  // SSIDs may intentionally contain leading/trailing spaces or quotes.
  return ssid == null || ssid.isEmpty ? null : ssid;
}

List<WifiNetwork> selectableNetworks(List<dynamic> rows) {
  final found = <String, WifiNetwork>{};
  for (final row in rows.whereType<Map>()) {
    final ssid = row['ssid'] as String? ?? '';
    final frequency = row['frequency'] as int? ?? 0;
    final rssi = row['rssi'] as int? ?? -127;
    if (ssid.isEmpty || frequency < 2400 || frequency > 2500) continue;
    if (!found.containsKey(ssid) || rssi > found[ssid]!.rssi) {
      found[ssid] = WifiNetwork(ssid, rssi);
    }
  }
  return found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
}

Future<List<WifiNetwork>> scanWifiNetworks() async {
  if (!canScanWifiNetworks) {
    throw PlatformException(
      code: 'unsupported',
      message: 'Wi-Fi scanning is only available on Android.',
    );
  }
  if (!await Permission.locationWhenInUse.request().isGranted) {
    throw PlatformException(code: 'permission');
  }
  final rows = await const MethodChannel(
    'voltraware/wifi',
  ).invokeListMethod<dynamic>('scan');
  return selectableNetworks(rows ?? []);
}
