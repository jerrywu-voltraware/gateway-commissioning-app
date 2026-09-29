/// 1.0.0+13 換機 (a broken gateway replaced by a new one): the new gateway
/// may take over only the number of a gateway the back office lists as
/// offline. `reserve-identity force_replace` does not check whether the old
/// gateway is still online; two gateways on one station and number mix
/// their data, overwrite each other's heartbeats and both run every command
/// sent to that number (unbind, restart, settings) — a wrong-pile incident.
///
/// Read from `GET /api/gateways/fleet-status?site_id=S` (`gateways[]`:
/// `site_id`, `gateway_id`, `online`, `last_seen_mac`, `last_heartbeat`,
/// `last_seen`). Pure Dart so the rules can be unit-tested without widgets.
library;

import 'gateway_identity.dart' show gatewayMacKey, macTail;

/// An offline gateway of the station that this gateway may replace.
class SwapCandidate {
  const SwapCandidate({
    required this.site,
    required this.gateway,
    this.mac = '',
    this.lastSeen,
  });

  final int site, gateway;

  /// The MAC the back office has on record (`last_seen_mac`), '' when none.
  final String mac;

  /// Its last sign of life, local: `last_heartbeat`, else `last_seen`; null
  /// when the back office has neither.
  final DateTime? lastSeen;

  /// 「…70F0」 (the MAC's last 4 digits), null when no MAC is on record.
  String? get tail {
    final t = macTail(mac);
    return t == null ? null : '…$t';
  }
}

List<Map> _rows(Map<String, dynamic> fleet) =>
    (fleet['gateways'] as List? ?? const []).whereType<Map>().toList();

DateTime? _time(Object? ts) =>
    ts is String && ts.isNotEmpty ? DateTime.tryParse(ts)?.toLocal() : null;

/// The gateways at [site] that fleet-status lists as offline (`online` is
/// false — a row without `online` is not listed: it cannot be told), other
/// than the gateway [ownUid] (this one), by number.
List<SwapCandidate> offlineSwapCandidates(
  Map<String, dynamic> fleet,
  int site,
  Object? ownUid,
) {
  final own = gatewayMacKey(ownUid);
  final found = <SwapCandidate>[];
  for (final row in _rows(fleet)) {
    if ((row['site_id'] as num?)?.toInt() != site) continue;
    final gateway = (row['gateway_id'] as num?)?.toInt();
    if (gateway == null || gateway < 1) continue;
    if (row['online'] != false) continue;
    final mac = (row['last_seen_mac'] ?? row['mac'])?.toString() ?? '';
    if (own.isNotEmpty && gatewayMacKey(mac) == own) continue;
    found.add(
      SwapCandidate(
        site: site,
        gateway: gateway,
        mac: mac,
        lastSeen: _time(row['last_heartbeat']) ?? _time(row['last_seen']),
      ),
    );
  }
  found.sort((a, b) => a.gateway.compareTo(b.gateway));
  return found;
}

/// fleet-status `online` of [site] / [gateway]: true or false; null when
/// there is no such row or it carries no `online`.
bool? fleetRowOnline(Map<String, dynamic> fleet, int site, int gateway) {
  for (final row in _rows(fleet)) {
    if ((row['site_id'] as num?)?.toInt() != site ||
        (row['gateway_id'] as num?)?.toInt() != gateway) {
      continue;
    }
    final online = row['online'];
    return online is bool ? online : null;
  }
  return null;
}
