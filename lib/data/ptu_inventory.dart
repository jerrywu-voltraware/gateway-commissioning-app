List<Map<String, dynamic>> mergePtuInventory(
  List<dynamic> scanned,
  List<dynamic> connected,
) {
  final merged = <String, Map<String, dynamic>>{};
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
      merged[key] = {...?merged[key], ...row};
    }
  }
  return merged.values.toList()..sort((a, b) {
    final connectionOrder =
        (b['connected'] == true ? 1 : 0) - (a['connected'] == true ? 1 : 0);
    return connectionOrder != 0
        ? connectionOrder
        : ((b['rssi'] as num?) ?? -127).compareTo((a['rssi'] as num?) ?? -127);
  });
}
