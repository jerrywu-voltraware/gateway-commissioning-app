/// The gateway's own Wi-Fi as reported by `get_net_status` (firmware
/// cmd_handler.c): `wifi_state` is `got_ip`, `connecting` or `disconnected`
/// (the firmware also reports FAILED / IDLE as `disconnected`), plus `ssid`,
/// `ip`, `rssi` and `uptime_sec`.
///
/// Pure Dart so the wording can be unit-tested without widgets.
library;

enum WifiVerdict {
  /// Not read yet (or the firmware cannot report it).
  unknown,

  /// Not joined yet, but the gateway may still be joining (e.g. just booted).
  connecting,

  /// Joined and has an IP address.
  ok,

  /// The configured network was not joined after the grace period.
  failed,

  /// No Wi-Fi network is configured at all.
  notConfigured,
}

/// A gateway up at least this long has had time to join its Wi-Fi, so a
/// missing connection is reported at once instead of after the grace period.
/// The firmware retries forever with a backoff of up to 30 s and alternates
/// between `connecting` and `disconnected`, so the state alone cannot tell.
const wifiSettleSeconds = 60;

/// SSID the gateway is configured for ([net] first, then get_config's);
/// empty when none is configured, null when it was not reported.
String? gatewaySsid(Map<String, dynamic> net, Object? configSsid) {
  final reported = net['ssid'];
  if (reported is String) return reported;
  return configSsid is String ? configSsid : null;
}

/// Judges the gateway Wi-Fi from a get_net_status result. [settled]: the
/// APP has waited long enough (grace period over, or polling ended).
WifiVerdict wifiVerdictOf(
  Map<String, dynamic> net, {
  Object? configSsid,
  bool settled = false,
}) {
  final raw = net['wifi_state'];
  if (raw is! String) return WifiVerdict.unknown;
  if (raw == 'got_ip') return WifiVerdict.ok;
  if (gatewaySsid(net, configSsid)?.isEmpty == true) {
    return WifiVerdict.notConfigured;
  }
  final uptime = net['uptime_sec'];
  final booted = uptime is num && uptime >= wifiSettleSeconds;
  return settled || booted ? WifiVerdict.failed : WifiVerdict.connecting;
}

String _named(String? ssid) =>
    ssid == null || ssid.isEmpty ? 'Wi-Fi' : 'Wi-Fi「$ssid」';

/// Chinese Wi-Fi state with the raw firmware value (technical details only).
String wifiStateText(Object? raw) => switch (raw) {
  'got_ip' => '已連線（got_ip）',
  'connecting' => '連線中（connecting）',
  'disconnected' => '未連線（disconnected）',
  null => '未知',
  _ => '未知（$raw）',
};

String wifiOkText(String? ssid) => 'Gateway 已連上 ${_named(ssid)}';

const wifiConnectingText = 'Gateway 正在連 Wi-Fi…';

/// Why the gateway has no network, in plain words ([ssid] empty: none is
/// configured; null: not reported).
String wifiProblemText(String? ssid) => ssid != null && ssid.isEmpty
    ? 'Gateway 還沒有設定 Wi-Fi，所以沒辦法上傳資料。'
    : 'Gateway 連不上 ${_named(ssid)}。這個 Wi-Fi 可能不在附近、密碼不對，'
          '或是 5 GHz（Gateway 只能用 2.4 GHz）。';
