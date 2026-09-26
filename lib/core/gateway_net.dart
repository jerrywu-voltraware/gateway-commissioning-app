/// The gateway's own Wi-Fi as reported by `get_net_status` (firmware
/// cmd_handler.c): `wifi_state` is `got_ip`, `connecting` or `disconnected`
/// (the firmware also reports FAILED / IDLE as `disconnected`), plus `ssid`,
/// `ip`, `rssi` and `uptime_sec`; firmware 1.7.32 adds why the Wi-Fi last
/// dropped or failed (`wifi_last_disc_reason`, `wifi_last_disc_age_s`).
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
/// configured; null: not reported). [reason]: `wifi_last_disc_reason`
/// ([wifiDiscReasonOf]); without it (firmware before 1.7.32) the text names
/// every likely cause.
String wifiProblemText(String? ssid, {int? reason}) {
  if (ssid != null && ssid.isEmpty) {
    return 'Gateway 還沒有設定 Wi-Fi，所以沒辦法上傳資料。';
  }
  return switch (wifiFailKindOf(reason)) {
    WifiFailKind.password =>
      'Gateway 連不上 ${_named(ssid)}：密碼可能錯誤，請確認密碼（含大小寫）後重新輸入。',
    WifiFailKind.notFound =>
      'Gateway 找不到 ${_named(ssid)}。請確認名稱正確、是 2.4 GHz'
          '（Gateway 不支援 5 GHz），且基地台就在附近。',
    WifiFailKind.weakOrOther =>
      'Gateway 連不上 ${_named(ssid)}，可能是訊號太弱或基地台暫時拒絕連線。'
          '請把 Gateway 移近基地台、避開金屬遮蔽後再試。',
    null =>
      'Gateway 連不上 ${_named(ssid)}。這個 Wi-Fi 可能不在附近、密碼不對，'
          '或是 5 GHz（Gateway 只能用 2.4 GHz）。',
  };
}

// ---- Why the Wi-Fi failed (firmware 1.7.32 `wifi_last_disc_reason`) ----

/// The three things an installer can act on.
enum WifiFailKind {
  /// Wrong password (or a key the router refused).
  password,

  /// The network is not there (name, 5 GHz only, or out of range).
  notFound,

  /// Weak signal, or another refusal: move the gateway closer.
  weakOrOther,
}

/// `wifi_err_reason_t` values (ESP-IDF 5.4.1,
/// `components/esp_wifi/include/esp_wifi_types_generic.h`) meaning the
/// password / key exchange failed: AUTH_EXPIRE 2, MIC_FAILURE 14,
/// 4WAY_HANDSHAKE_TIMEOUT 15, 802_1X_AUTH_FAILED 23, AUTH_FAIL 202,
/// HANDSHAKE_TIMEOUT 204.
const wifiPasswordReasons = {2, 14, 15, 23, 202, 204};

/// No matching network: NO_AP_FOUND 201, NO_AP_FOUND_W_COMPATIBLE_SECURITY
/// 210, NO_AP_FOUND_IN_AUTHMODE_THRESHOLD 211. (NO_AP_FOUND_IN_RSSI_THRESHOLD
/// 212 is found-but-too-weak: [WifiFailKind.weakOrOther].)
const wifiNotFoundReasons = {201, 210, 211};

/// The gateway's own leave (AUTH_LEAVE 3, ASSOC_LEAVE 8, STA_LEAVING 36,
/// e.g. while switching networks) says nothing about why joining fails, so
/// it is treated like no reason at all.
const wifiLeaveReasons = {3, 8, 36};

/// Everything else — BEACON_TIMEOUT 200, ASSOC_FAIL 203, CONNECTION_FAIL
/// 205, NO_AP_FOUND_IN_RSSI_THRESHOLD 212, … — is weak signal or other.
WifiFailKind? wifiFailKindOf(int? reason) => reason == null
    ? null
    : wifiPasswordReasons.contains(reason)
    ? WifiFailKind.password
    : wifiNotFoundReasons.contains(reason)
    ? WifiFailKind.notFound
    : WifiFailKind.weakOrOther;

/// `wifi_last_disc_reason` of a get_net_status result, or null when the
/// firmware does not report it (before 1.7.32), reports none (0), or it is
/// the gateway's own leave ([wifiLeaveReasons]). [notOlderThan]: ignore a
/// reason whose `wifi_last_disc_age_s` says it happened before that (e.g.
/// before this set_wifi was sent); a null age is accepted.
int? wifiDiscReasonOf(Map<String, dynamic> net, {Duration? notOlderThan}) {
  final raw = net['wifi_last_disc_reason'];
  if (raw is! num || raw <= 0) return null;
  final reason = raw.toInt();
  if (wifiLeaveReasons.contains(reason)) return null;
  final age = net['wifi_last_disc_age_s'];
  if (notOlderThan != null && age is num && age > notOlderThan.inSeconds) {
    return null;
  }
  return reason;
}

/// 技術細節 line for the last Wi-Fi failure (the code is kept for the back
/// office), or null when not reported.
String? wifiDiscDetail(Map<String, dynamic> net) {
  final raw = net['wifi_last_disc_reason'];
  if (raw is! num || raw <= 0) return null;
  final reason = raw.toInt();
  final kind = wifiLeaveReasons.contains(reason)
      ? '閘道器自行中斷'
      : switch (wifiFailKindOf(reason)!) {
          WifiFailKind.password => '密碼可能錯誤',
          WifiFailKind.notFound => '找不到這個 Wi-Fi',
          WifiFailKind.weakOrOther => '訊號弱或其他',
        };
  final age = net['wifi_last_disc_age_s'];
  return 'Wi-Fi 最後斷線原因：$kind（代碼 $reason'
      '${age is num ? '，${age.toInt()} 秒前' : ''}）';
}

// ---- Weak gateway Wi-Fi ----

/// Gateway Wi-Fi RSSI (get_net_status `rssi`, dBm) below this is shown red
/// with advice. Basis: Wi-Fi site-survey practice treats about -67 dBm as
/// the floor for reliable data and -70 to -75 dBm as marginal; below -75 dBm
/// 2.4 GHz links retry and drop often. The ESP32 still joins far weaker
/// networks (down to about -90 dBm), so a gateway can pass the check at the
/// desk and then lose its MQTT upload once the pile body or enclosure costs
/// a few more dB — the check warns before that.
const weakWifiRssiDbm = -75;

/// A real reading (the firmware reports 0 when not joined) below
/// [weakWifiRssiDbm].
bool isWeakWifiRssi(Object? rssi) =>
    rssi is num && rssi < 0 && rssi < weakWifiRssiDbm;

/// The red warning with what to do about it.
String weakWifiText(num rssi) =>
    '⚠ Wi-Fi 訊號偏弱（${rssi.toInt()} dBm，低於 $weakWifiRssiDbm dBm），'
    '資料可能時斷時續。建議把 Gateway 移近基地台、避開金屬遮蔽，或在附近加裝 Wi-Fi 延伸器。';

/// [weakWifiText] when the gateway is joined and its signal is weak.
String? weakWifiWarning(Map<String, dynamic> net) {
  final rssi = net['rssi'];
  return net['wifi_state'] == 'got_ip' && isWeakWifiRssi(rssi)
      ? weakWifiText(rssi as num)
      : null;
}

/// set_wifi did not join the new network ([reason]: see [wifiDiscReasonOf]).
String wifiSetFailedText(int? reason) => switch (wifiFailKindOf(reason)) {
  WifiFailKind.password => '新 Wi-Fi 連線未成功：密碼可能錯誤，請確認密碼（含大小寫）後重試。',
  WifiFailKind.notFound =>
    '新 Wi-Fi 連線未成功：Gateway 找不到這個 Wi-Fi。請確認名稱正確、是 2.4 GHz'
        '（不支援 5 GHz），且基地台就在附近。',
  WifiFailKind.weakOrOther =>
    '新 Wi-Fi 連線未成功：可能是訊號太弱或基地台暫時拒絕連線，請把 Gateway 移近基地台後重試。',
  null => '新 WiFi 連線未成功，請檢查密碼與訊號後重試。',
};

/// Detail of a 'wifi_failed' failure that carries the firmware reason.
String wifiFailedDetail(int reason) => 'wifi_last_disc_reason=$reason';

/// The reason back from [wifiFailedDetail] (null for any other detail).
int? wifiFailedReason(String? detail) {
  final match = RegExp(r'wifi_last_disc_reason=(\d+)').firstMatch(detail ?? '');
  return match == null ? null : int.parse(match.group(1)!);
}
