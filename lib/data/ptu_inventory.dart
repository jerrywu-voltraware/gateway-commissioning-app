List<Map<String, dynamic>> mergePtuInventory(
  List<dynamic> scanned,
  List<dynamic> connected,
) {
  final merged = <String, Map<String, dynamic>>{};
  final scannedNumbers = <String, Object?>{};
  for (final source in [scanned, connected]) {
    for (final raw in source.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final key =
          row['mac']
              ?.toString()
              .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
              .toUpperCase() ??
          '';
      if (key.length != 12) continue;
      if (identical(source, scanned) && row.containsKey('device_number')) {
        scannedNumbers[key] = row['device_number'];
      }
      merged[key] = {...?merged[key], ...row};
    }
  }
  // A gateway slot that is not connected may still carry a stale number
  // from an earlier round; this scan's advertised number wins then.
  for (final e in scannedNumbers.entries) {
    final row = merged[e.key]!;
    if (row['connected'] != true) row['device_number'] = e.value;
  }
  return merged.values.toList()..sort((a, b) {
    final connectionOrder =
        (b['connected'] == true ? 1 : 0) - (a['connected'] == true ? 1 : 0);
    return connectionOrder != 0
        ? connectionOrder
        : ((b['rssi'] as num?) ?? -127).compareTo((a['rssi'] as num?) ?? -127);
  });
}
