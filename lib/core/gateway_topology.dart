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
    GatewayTopology.direct => '直連模式',
    GatewayTopology.star => '星狀模式',
  };

  String get label => switch (this) {
    GatewayTopology.direct => '直連模式（一對一）',
    GatewayTopology.star => '星狀模式（一對多）',
  };
}

/// 星狀模式「每台 PTU 數」的允許範圍與預設值。
const minStarPtuCount = 2;
const maxStarPtuCount = 5;
const defaultStarPtuCount = 5;

/// 一站可配置的閘道器編號上限（1–[kMaxGatewayId]）。一對一模式一站可能超過
/// 6 台 gateway，故由舊的 6 放寬到 50。
const kMaxGatewayId = 50;
