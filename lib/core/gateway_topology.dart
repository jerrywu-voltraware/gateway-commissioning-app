import '../l10n/l10n.dart';

/// Gateway ↔ PTU topology written into the gateway's `max_connections`
/// during commissioning. Firmware and backend are unchanged; only the target
/// PTU count commissioning aims for differs.
enum GatewayTopology {
  /// One gateway to one PTU (公司政策的預設方向).
  direct,

  /// One gateway to several PTUs (既有星狀布線，仍需維護).
  star;

  bool get isDirect => this == GatewayTopology.direct;
  bool get isStar => this == GatewayTopology.star;

  /// 直連固定 1 台；星狀採 [starCount]（使用者可設定的每台 PTU 數）。
  int targetCount(int starCount) => isDirect ? 1 : starCount;

  String get shortLabel => switch (this) {
    GatewayTopology.direct => L10n.current.gatewayTopology_directShort,
    GatewayTopology.star => L10n.current.gatewayTopology_starShort,
  };

  String get label => switch (this) {
    GatewayTopology.direct => L10n.current.gatewayTopology_directLabel,
    GatewayTopology.star => L10n.current.gatewayTopology_starLabel,
  };
}

/// 星狀模式「每台 PTU 數」的允許範圍與預設值。
const minStarPtuCount = 2;
const maxStarPtuCount = 5;
const defaultStarPtuCount = 5;

/// 一站可配置的閘道器編號上限（1–[kMaxGatewayId]）。一對一模式一站可能超過
/// 6 台 gateway，故由舊的 6 放寬到 50。
const kMaxGatewayId = 50;

/// r33 (a fresh install defaults to star; a one-to-one gateway configured
/// with it was silently switched to max_connections 5): the mode the
/// connected gateway already runs in when it differs from the APP's [app]
/// mode, else null. One-to-one: `max_connections` 1 (the firmware default
/// is 5, so 1 was set on purpose; its direct state is never `off`). Star:
/// `max_connections` above 1 on a gateway in service (`fleet_joined`) — a
/// factory gateway (5, not in service) is not asked about.
GatewayTopology? gatewayTopologyMismatch(
  Map<String, dynamic> config,
  GatewayTopology app,
) {
  final max = (config['max_connections'] as num?)?.toInt();
  if (max == null || max < 1) return null;
  if (max == 1) return app.isStar ? GatewayTopology.direct : null;
  if (config['fleet_joined'] == true && app.isDirect) {
    return GatewayTopology.star;
  }
  return null;
}

/// The PTU MAC a one-to-one gateway is bound to (`direct_bind_mac`), or
/// null when unbound.
String? gatewayBoundMac(Map<String, dynamic> config) {
  final mac = config['direct_bind_mac']?.toString().trim() ?? '';
  return mac.isEmpty ? null : mac;
}
