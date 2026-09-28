/// 1.0.0+5 「閘道器狀態」: the back office's gateway list for the phone —
/// `GET /api/gateways/fleet-status` through the APP's own session (the
/// APP key's allow list, `dashboard-api/app_key_auth.py`).
///
/// Fields read from each row of `gateways` (`dashboard-api/cmd_services.py`
/// `get_fleet_status`): `site_id`, `gateway_id`, `online`, `ble_connected`
/// (heartbeat count), `direct` (`{label, connected, …}`, direct mode only),
/// `device_last_seen` (the PTUs' newest row, r34), `last_heartbeat`. The
/// endpoint carries no gateway name.
library;

import 'contracts.dart';
import 'recent_data_api.dart' show parseRecentTs;

/// One gateway of fleet-status as the page needs it.
class FleetGateway {
  const FleetGateway({
    required this.site,
    required this.gateway,
    required this.online,
    required this.ptuConnected,
    this.directLabel = '',
    this.lastData,
    this.lastHeartbeat,
  });

  final int site, gateway;
  final bool online;

  /// `direct.connected`, else `ble_connected > 0`.
  final bool ptuConnected;

  /// `direct.label` (「已綁定」…), empty in the star mode.
  final String directLabel;

  /// `device_last_seen` (the newest PTU row) and `last_heartbeat`, local.
  final DateTime? lastData, lastHeartbeat;

  static FleetGateway? fromJson(Map row) {
    final site = row['site_id'], gateway = row['gateway_id'];
    if (site is! num || gateway is! num) return null;
    final direct = row['direct'];
    final directMap = direct is Map ? direct : const {};
    final ble = row['ble_connected'];
    final connected = directMap['connected'] == true || (ble is num && ble > 0);
    return FleetGateway(
      site: site.toInt(),
      gateway: gateway.toInt(),
      online: row['online'] == true,
      ptuConnected: connected,
      directLabel: directMap['label']?.toString() ?? '',
      lastData: parseRecentTs(row['device_last_seen']),
      lastHeartbeat: parseRecentTs(row['last_heartbeat']),
    );
  }
}

const fleetStatusPath = '/api/gateways/fleet-status';

/// The gateways the back office lists, by site then gateway. Throws the
/// [GatewayFailure] of [GatewayApi.request].
Future<List<FleetGateway>> fetchFleetStatus(GatewayApi api) async {
  final json = await api.request('GET', fleetStatusPath);
  final raw = json['gateways'];
  final rows = raw is List
      ? raw
            .whereType<Map>()
            .map(FleetGateway.fromJson)
            .whereType<FleetGateway>()
            .toList()
      : <FleetGateway>[];
  rows.sort((a, b) {
    final s = a.site.compareTo(b.site);
    return s != 0 ? s : a.gateway.compareTo(b.gateway);
  });
  return rows;
}
