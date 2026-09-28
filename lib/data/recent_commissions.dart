import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 1.0.0+5 「閘道器狀態」: the gateways this phone finished commissioning
/// (the done page's 〔完成〕／〔配置下一台〕), newest first, at most
/// [RecentCommissions.max] — so the installer can open 〔查看最近資料〕
/// again after the done page is gone. Kept in [SharedPreferences] beside
/// `recent_gateways` (demo and real runs apart).
class RecentCommission {
  const RecentCommission({
    required this.site,
    required this.gateway,
    required this.gatewayName,
    required this.doneAt,
  });

  final int site, gateway;

  /// The gateway's BLE name (`GW-1234`); may be empty.
  final String gatewayName;

  /// When 〔完成〕 was pressed (local time).
  final DateTime doneAt;

  Map<String, Object?> toJson() => {
    'site': site,
    'gateway': gateway,
    'gateway_name': gatewayName,
    'done_at': doneAt.toIso8601String(),
  };

  /// null when a required field is missing or malformed.
  static RecentCommission? fromJson(Map row) {
    final site = row['site'], gateway = row['gateway'], at = row['done_at'];
    if (site is! num || gateway is! num || at is! String) return null;
    final doneAt = DateTime.tryParse(at);
    if (doneAt == null) return null;
    return RecentCommission(
      site: site.toInt(),
      gateway: gateway.toInt(),
      gatewayName: row['gateway_name']?.toString() ?? '',
      doneAt: doneAt.toLocal(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecentCommission &&
      other.site == site &&
      other.gateway == gateway &&
      other.gatewayName == gatewayName &&
      other.doneAt == doneAt;

  @override
  int get hashCode => Object.hash(site, gateway, gatewayName, doneAt);

  @override
  String toString() => 'RecentCommission($site/$gateway $gatewayName $doneAt)';
}

class RecentCommissions {
  static const max = 10;

  static String key(bool demo) =>
      demo ? 'demo_recent_commissions' : 'recent_commissions';

  /// Newest first; an unreadable store reads as empty.
  static Future<List<RecentCommission>> load(bool demo) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rows = jsonDecode(prefs.getString(key(demo)) ?? '[]') as List;
      return rows
          .whereType<Map>()
          .map(RecentCommission.fromJson)
          .whereType<RecentCommission>()
          .take(max)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Puts [entry] first; an older entry of the same site / gateway is
  /// dropped; the list is cut to [max].
  static Future<void> remember(bool demo, RecentCommission entry) async {
    final rows = await load(demo);
    final updated = [
      entry,
      ...rows.where((r) => r.site != entry.site || r.gateway != entry.gateway),
    ].take(max).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key(demo),
      jsonEncode(updated.map((r) => r.toJson()).toList()),
    );
  }
}
