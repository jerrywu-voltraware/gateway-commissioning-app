import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiNetwork {
  const WifiNetwork(this.ssid, this.rssi);
  final String ssid;
  final int rssi;
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
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    throw PlatformException(
      code: 'unsupported',
      message: 'Wi-Fi scanning is not available on iOS.',
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
