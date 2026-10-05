import '../l10n/l10n.dart';

/// Gateway-to-PTU signal strength, never the phone-to-gateway RSSI.
String ptuRssiText(Map<String, dynamic> ptu) {
  final rssi = ptu['rssi'];
  if (rssi is! num || rssi < -127 || rssi >= 0) return 'RSSI —';
  final l10n = L10n.current;
  if (ptu['rssi_stale'] == true) return l10n.ptuRssi_last('$rssi');
  if (ptu['connected'] != true) return l10n.ptuRssi_scan('$rssi');
  final age = ptu['rssi_age_ms'];
  if (age is num && age >= 0 && age <= 15000) return '$rssi dBm';
  return age == null
      ? l10n.ptuRssi_cached('$rssi')
      : l10n.ptuRssi_last('$rssi');
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
