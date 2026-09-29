import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gateway_identity.dart'
    show isFactoryGatewayName, parseGatewayName;
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
///
/// r31: 「後端狀態未知」 says why (no record / several / conflict), and a
/// station archived in the back office ([archived], fleet-status
/// `archived_gateways`) reads [gatewayArchivedLabel].
String backendPresence(
  String? uid,
  List<dynamic> fleet, {
  List<dynamic> archived = const [],
}) {
  final normalized = gatewayUid(uid);
  if (normalized.length != 12) return '後端狀態未知・連線後確認身分';
  final matches = _matching(normalized, fleet);
  if (matches.isEmpty && _matching(normalized, archived).isNotEmpty) {
    return gatewayArchivedLabel;
  }
  if (matches.isEmpty) return '後端狀態未知・後台沒有這個 MAC 的心跳紀錄';
  if (matches.length > 1) {
    return '後端狀態未知・後台有 ${matches.length} 筆相同 MAC 的紀錄';
  }
  if (_conflict(matches.single)) return '後端狀態未知・後台標示身分衝突';
  return switch (matches.single['online']) {
    true => '後端回報在線上',
    false => '後端回報離線',
    _ => '後端狀態未知',
  };
}

/// 1.0.0+9: the gateway list's short form of [backendPresence] — 「後端在線」
/// ／「後端離線」／「後端無紀錄」／「後端已封存」／「後端未知」 (the reason
/// stays in the list's footer line and the help panel).
String backendPresenceShort(
  String? uid,
  List<dynamic> fleet, {
  List<dynamic> archived = const [],
}) {
  final full = backendPresence(uid, fleet, archived: archived);
  if (full == '後端回報在線上') return '後端在線';
  if (full == '後端回報離線') return '後端離線';
  if (full == gatewayArchivedLabel) return '後端已封存';
  if (full.contains('沒有這個 MAC')) return '後端無紀錄';
  return backendUnknownShort;
}

/// 1.0.0+9: the list's short 「後端狀態未知」.
const backendUnknownShort = '後端未知';

/// r31: the mark of a station archived in the back office.
const gatewayArchivedLabel = '已封存（後台已移除）';

/// r31: the mark of a gateway already configured (known to the back office).
const gatewayConfiguredLabel = '已配置';

/// r31: a gateway already configured — its verified [uid] is exactly one
/// fleet row without a conflict. Such a gateway is listed with
/// [gatewayConfiguredLabel]; 1.0.0+10: when it is the strongest it is still
/// marked 「最近」 and ranked first (r31 left it out).
bool gatewayConfigured(String? uid, List<dynamic> fleet) {
  final normalized = gatewayUid(uid);
  if (normalized.length != 12) return false;
  final matches = _matching(normalized, fleet);
  return matches.length == 1 && !_conflict(matches.single);
}

/// 1.0.0+12: a gateway known not to be configured — listed as 「未配置閘道器
/// …XXXX」 instead of the station / number it advertises ([name]), which
/// may be an old test identity left in its NVS. Known when its name is the
/// factory 1/1, or the back office's list is current ([backendKnown]) and
/// the gateway is not in it: its verified [uid] (a remembered connect) in
/// no row of [fleet] / [archived], or without one, no row with the station
/// and number of its [name]. A gateway already configured ([gatewayConfigured])
/// never is; with the back office unknown only the factory name counts.
bool gatewayKnownUnconfigured({
  required String name,
  String? uid,
  required List<dynamic> fleet,
  List<dynamic> archived = const [],
  required bool backendKnown,
}) {
  if (backendKnown && gatewayConfigured(uid, fleet)) return false;
  if (isFactoryGatewayName(name)) return true;
  if (!backendKnown) return false;
  final normalized = gatewayUid(uid);
  if (normalized.length == 12) {
    return _matching(normalized, fleet).isEmpty &&
        _matching(normalized, archived).isEmpty;
  }
  final id = parseGatewayName(name);
  if (id == null) return false;
  bool at(Map row) =>
      (row['site_id'] as num?)?.toInt() == id.site &&
      (row['gateway_id'] as num?)?.toInt() == id.gateway;
  return !fleet.whereType<Map>().any(at) && !archived.whereType<Map>().any(at);
}

/// r31: why the back-office query failed, for 「後端狀態未知・…」.
String backendQueryFailedText(Object error) {
  final text = error.toString();
  if (error is TimeoutException || text.contains('Timeout')) {
    return '後端狀態未知・查詢逾時（8 秒）';
  }
  final short = text.length > 40 ? '${text.substring(0, 40)}…' : text;
  return '後端狀態未知・查詢失敗（$short）';
}

List<Map> _matching(String uid, List<dynamic> rows) => rows
    .whereType<Map>()
    .where((r) => gatewayUid(r['last_seen_mac']) == uid)
    .toList();

bool _conflict(Map row) =>
    row['conflict_flag'] == true || row['conflict_flag'] == 1;
