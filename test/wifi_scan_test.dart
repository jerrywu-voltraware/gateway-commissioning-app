import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/wifi_scan.dart';

void main() {
  test('WiFi choices filter bands and hidden SSIDs, deduplicate and sort', () {
    final networks = selectableNetworks([
      {'ssid': 'Office', 'rssi': -80, 'frequency': 2412},
      {'ssid': 'Office', 'rssi': -40, 'frequency': 2437},
      {'ssid': 'Only5G', 'rssi': -20, 'frequency': 5180},
      {'ssid': '', 'rssi': -10, 'frequency': 2412},
      {'ssid': '中文 WiFi ', 'rssi': -50, 'frequency': 2462},
    ]);
    expect(networks.map((n) => n.ssid), ['Office', '中文 WiFi ']);
    expect(networks.first.rssi, -40);
  });
}
