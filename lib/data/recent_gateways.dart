import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gateway_identity.dart'
    show isFactoryGatewayName, parseGatewayName;
import '../l10n/l10n.dart';
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

/// The back office's view of a gateway, as the gateway list shows it
/// ([backendPresenceShort]).
///
/// 2026-10-05 (i18n): logic switches on this instead of comparing the
/// (now translated) texts 「後端在線」／「後端離線」／「後端無紀錄」／
/// 「後端已封存」／「後端未知」.
enum BackendPresence {
  /// 後端在線: one fleet row, online.
  online,

  /// 後端離線: one fleet row, offline.
  offline,

  /// 後端無紀錄: no fleet row (no heartbeat from this MAC / station).
  noRecord,

  /// 後端已封存: only an archived row.
  archived,

  /// 後端未知: not verified, several rows, a conflict, or no online flag.
  unknown;

  /// The list's short text (「後端在線」…) in the screen language.
  String get shortText => shortTextIn(L10n.current);

  /// [shortText] in [l10n].
  String shortTextIn(AppLocalizations l10n) => switch (this) {
    BackendPresence.online => l10n.recentGateways_shortOnline,
    BackendPresence.offline => l10n.recentGateways_shortOffline,
    BackendPresence.noRecord => l10n.recentGateways_shortNoRecord,
    BackendPresence.archived => l10n.recentGateways_shortArchived,
    BackendPresence.unknown => l10n.recentGateways_shortUnknown,
  };

  /// The kind of a short text ([backendPresenceShort]) in any supported
  /// language (a text made before a language switch is still recognised);
  /// null for any other text. For callers that only kept the text.
  static BackendPresence? ofShortText(String? text) {
    if (text == null || text.isEmpty) return null;
    for (final language in AppLanguage.values) {
      final l10n = lookupAppLocalizations(language.locale);
      for (final kind in BackendPresence.values) {
        if (kind.shortTextIn(l10n) == text) return kind;
      }
    }
    return null;
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
}) => _presence(uid, fleet, archived).text;

/// [backendPresence]'s text with its [BackendPresence] (the list's short
/// kind), computed together so the short form never parses the text.
({BackendPresence kind, String text}) _presence(
  String? uid,
  List<dynamic> fleet,
  List<dynamic> archived,
) {
  final l10n = L10n.current;
  final normalized = gatewayUid(uid);
  if (normalized.length != 12) {
    return (
      kind: BackendPresence.unknown,
      text: l10n.recentGateways_unknownUnverified,
    );
  }
  final matches = _matching(normalized, fleet);
  if (matches.isEmpty && _matching(normalized, archived).isNotEmpty) {
    return (kind: BackendPresence.archived, text: gatewayArchivedLabel);
  }
  if (matches.isEmpty) {
    return (
      kind: BackendPresence.noRecord,
      text: l10n.recentGateways_unknownNoHeartbeat,
    );
  }
  if (matches.length > 1) {
    return (
      kind: BackendPresence.unknown,
      text: l10n.recentGateways_unknownDuplicates(matches.length),
    );
  }
  if (_conflict(matches.single)) {
    return (
      kind: BackendPresence.unknown,
      text: l10n.recentGateways_unknownConflict,
    );
  }
  return switch (matches.single['online']) {
    true => (
      kind: BackendPresence.online,
      text: l10n.recentGateways_reportedOnline,
    ),
    false => (
      kind: BackendPresence.offline,
      text: l10n.recentGateways_reportedOffline,
    ),
    _ => (kind: BackendPresence.unknown, text: l10n.recentGateways_unknown),
  };
}

/// 1.0.0+9: the gateway list's short form of [backendPresence] — 「後端在線」
/// ／「後端離線」／「後端無紀錄」／「後端已封存」／「後端未知」 (the reason
/// stays in the list's footer line and the help panel).
/// When no verified UID exists, [advertisedName] may show the backend record
/// for that station/number as a reference. This never verifies the scanned
/// device or changes [gatewayConfigured]; the UI must mark it pending identity
/// verification. A known UID always takes precedence, including a mismatch.
String backendPresenceShort(
  String? uid,
  List<dynamic> fleet, {
  List<dynamic> archived = const [],
  String? advertisedName,
}) => backendPresenceKind(
  uid,
  fleet,
  archived: archived,
  advertisedName: advertisedName,
).shortText;

/// The [BackendPresence] behind [backendPresenceShort] (same arguments,
/// same rules); switch on this instead of on the text.
BackendPresence backendPresenceKind(
  String? uid,
  List<dynamic> fleet, {
  List<dynamic> archived = const [],
  String? advertisedName,
}) {
  if (gatewayUid(uid).length != 12 && advertisedName != null) {
    final id = parseGatewayName(advertisedName);
    // The shared factory name cannot identify a backend record.
    if (id == null || isFactoryGatewayName(advertisedName)) {
      return BackendPresence.unknown;
    }
    bool at(Map row) =>
        row['site_id'] == id.site && row['gateway_id'] == id.gateway;
    final matches = fleet.whereType<Map>().where(at).toList();
    final removed = archived.whereType<Map>().where(at).toList();
    if (matches.isEmpty && removed.isEmpty) return BackendPresence.noRecord;
    if (matches.isEmpty && removed.length == 1 && !_conflict(removed.single)) {
      return BackendPresence.archived;
    }
    if (matches.length != 1 ||
        removed.isNotEmpty ||
        _conflict(matches.single)) {
      return BackendPresence.unknown;
    }
    return switch (matches.single['online']) {
      true => BackendPresence.online,
      false => BackendPresence.offline,
      _ => BackendPresence.unknown,
    };
  }
  return _presence(uid, fleet, archived).kind;
}

/// 1.0.0+9: the list's short 「後端狀態未知」.
String get backendUnknownShort => BackendPresence.unknown.shortText;

/// r31: the mark of a station archived in the back office.
String get gatewayArchivedLabel => L10n.current.recentGateways_archivedLabel;

/// r31: the mark of a gateway already configured (known to the back office).
String get gatewayConfiguredLabel =>
    L10n.current.recentGateways_configuredLabel;

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
    return L10n.current.recentGateways_queryTimeout;
  }
  final short = text.length > 40 ? '${text.substring(0, 40)}…' : text;
  return L10n.current.recentGateways_queryFailed(short);
}

List<Map> _matching(String uid, List<dynamic> rows) => rows
    .whereType<Map>()
    .where((r) => gatewayUid(r['last_seen_mac']) == uid)
    .toList();

bool _conflict(Map row) =>
    row['conflict_flag'] == true || row['conflict_flag'] == 1;
