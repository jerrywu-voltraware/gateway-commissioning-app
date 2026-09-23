/// Gateway-to-PTU signal strength, never the phone-to-gateway RSSI.
String ptuRssiText(Map<String, dynamic> ptu) {
  final rssi = ptu['rssi'];
  if (rssi is! num || rssi < -127 || rssi >= 0) return 'RSSI —';
  if (ptu['rssi_stale'] == true) return '上次 $rssi dBm';
  if (ptu['connected'] != true) return '掃描 $rssi dBm';
  final age = ptu['rssi_age_ms'];
  if (age is num && age >= 0 && age <= 15000) return '$rssi dBm';
  return '${age == null ? '快取' : '上次'} $rssi dBm';
}

String _mac(Object? value) =>
    value.toString().replaceAll(':', '').toUpperCase();

/// Update existing rows in place, without reordering, selecting new devices,
/// or discarding unconnected candidates from the last discovery scan.
List<Map<String, dynamic>> refreshPtuSignals(
  List<Map<String, dynamic>> existing,
  List<dynamic> reported,
) {
  final live = {
    for (final row in reported.whereType<Map>()) _mac(row['mac']): row,
  };
  return existing.map((row) {
    final next = live[_mac(row['mac'])];
    if (next == null) {
      return row['connected'] == true
          ? {...row, 'connected': false, 'rssi_stale': true}
          : row;
    }
    return <String, dynamic>{
      ...row,
      'rssi': next['rssi'],
      'connected': next['connected'] == true,
      'rssi_age_ms': next['rssi_age_ms'],
      'rssi_stale': false,
    };
  }).toList();
}
