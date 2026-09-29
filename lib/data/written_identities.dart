import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'recent_gateways.dart' show gatewayUid;

/// 1.0.0+12: an identity this phone wrote to a gateway — `set_site_identity`
/// acked — so a gateway that is not in service yet keeps it as the proposal
/// when it is connected again (round 26: 80/2 was written, the reconnect
/// after the restart failed, and the form offered 「站點 1／閘道器 1」 again).
/// Any other identity a gateway not in service carries (e.g. an old test
/// identity left in its NVS) is never proposed.
class WrittenIdentity {
  const WrittenIdentity({
    required this.uid,
    required this.peerId,
    required this.site,
    required this.gateway,
    required this.at,
  });

  /// The gateway's Wi-Fi MAC (`gateway_uid`, [gatewayUid] form; may be '').
  final String uid;

  /// The gateway's Bluetooth id (the peer the phone was connected to).
  final String peerId;
  final int site, gateway;

  /// When the identity was written (local time).
  final DateTime at;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'peer': peerId,
    'site': site,
    'gateway': gateway,
    'at': at.toIso8601String(),
  };

  /// null when a required field is missing or malformed.
  static WrittenIdentity? fromJson(Map row) {
    final site = row['site'], gateway = row['gateway'], at = row['at'];
    if (site is! num || gateway is! num || at is! String) return null;
    final time = DateTime.tryParse(at);
    if (time == null) return null;
    return WrittenIdentity(
      uid: gatewayUid(row['uid']),
      peerId: row['peer']?.toString() ?? '',
      site: site.toInt(),
      gateway: gateway.toInt(),
      at: time.toLocal(),
    );
  }

  /// The same gateway: its Wi-Fi MAC when both are known, else its
  /// Bluetooth id.
  bool sameGateway({Object? uid, String? peerId}) {
    final other = gatewayUid(uid);
    if (this.uid.length == 12 && other.length == 12) return this.uid == other;
    return peerId != null && peerId.isNotEmpty && this.peerId == peerId;
  }

  /// Written at most [WrittenIdentities.window] before [now].
  bool freshAt(DateTime now) {
    final age = now.difference(at);
    return !age.isNegative && age <= WrittenIdentities.window;
  }
}

/// The store of [WrittenIdentity]s (SharedPreferences, demo and real runs
/// apart, newest first, at most [max], one per gateway).
class WrittenIdentities {
  /// How long a written identity is kept as the proposal (or until the
  /// gateway is in service, see [forget]).
  static const window = Duration(minutes: 30);
  static const max = 10;

  static String key(bool demo) =>
      demo ? 'demo_written_identities' : 'written_identities';

  /// Newest first; an unreadable store reads as empty.
  static Future<List<WrittenIdentity>> load(bool demo) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rows = jsonDecode(prefs.getString(key(demo)) ?? '[]') as List;
      return rows
          .whereType<Map>()
          .map(WrittenIdentity.fromJson)
          .whereType<WrittenIdentity>()
          .take(max)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// The fresh record ([WrittenIdentity.freshAt]) of this gateway, if any.
  static Future<WrittenIdentity?> find(
    bool demo, {
    Object? uid,
    String? peerId,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    for (final row in await load(demo)) {
      if (row.sameGateway(uid: uid, peerId: peerId)) {
        return row.freshAt(at) ? row : null;
      }
    }
    return null;
  }

  /// Puts [entry] first; an older record of the same gateway and stale
  /// ones are dropped.
  static Future<void> remember(bool demo, WrittenIdentity entry) async {
    final now = DateTime.now();
    final rows = await load(demo);
    final updated = [
      entry,
      ...rows.where(
        (r) =>
            !r.sameGateway(uid: entry.uid, peerId: entry.peerId) &&
            r.freshAt(now),
      ),
    ].take(max).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key(demo),
      jsonEncode(updated.map((r) => r.toJson()).toList()),
    );
  }

  /// Drops the record of this gateway (it is in service now).
  static Future<void> forget(bool demo, {Object? uid, String? peerId}) async {
    final rows = await load(demo);
    final kept = rows
        .where((r) => !r.sameGateway(uid: uid, peerId: peerId))
        .toList();
    if (kept.length == rows.length) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key(demo),
      jsonEncode(kept.map((r) => r.toJson()).toList()),
    );
  }
}
