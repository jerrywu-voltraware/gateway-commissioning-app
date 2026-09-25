import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'contracts.dart';

String gatewayUid(Object? value) =>
    value?.toString().replaceAll(RegExp('[^a-fA-F0-9]'), '').toUpperCase() ??
    '';

class RecentGateway {
  const RecentGateway(this.peer, this.uid);
  final GatewayPeer peer;
  final String uid;
}

class RecentGateways {
  static String key(bool demo) =>
      demo ? 'demo_recent_gateways' : 'recent_gateways';
  static Future<List<RecentGateway>> load(bool demo) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rows = jsonDecode(prefs.getString(key(demo)) ?? '[]') as List;
      return rows
          .whereType<Map>()
          .where(
            (r) =>
                r['id'] is String && r['name'] is String && r['uid'] is String,
          )
          .take(5)
          .map(
            (r) =>
                RecentGateway(GatewayPeer(r['id'], r['name'], -127), r['uid']),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> remember(bool demo, GatewayPeer peer, Object? uid) async {
    final rows = await load(demo);
    final value = gatewayUid(uid);
    if (value.length != 12) return;
    final updated = [
      RecentGateway(peer, value),
      ...rows.where((r) => r.peer.id != peer.id && r.uid != value),
    ].take(5);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key(demo),
      jsonEncode(
        updated
            .map((r) => {'id': r.peer.id, 'name': r.peer.name, 'uid': r.uid})
            .toList(),
      ),
    );
  }
}

/// Only a previously BLE-verified UID can associate a row with backend status.
/// Never infer hardware identity from the advertising name or Android BLE MAC.
String backendPresence(String? uid, List<dynamic> fleet) {
  final normalized = gatewayUid(uid);
  if (normalized.length != 12) return '後端狀態未知・連線後確認身分';
  final matches = fleet
      .whereType<Map>()
      .where((r) => gatewayUid(r['last_seen_mac']) == normalized)
      .toList();
  if (matches.length != 1 ||
      matches.single['conflict_flag'] == true ||
      matches.single['conflict_flag'] == 1) {
    return '後端狀態未知・尚無唯一紀錄';
  }
  return switch (matches.single['online']) {
    true => '後端回報在線上',
    false => '後端回報離線',
    _ => '後端狀態未知',
  };
}
