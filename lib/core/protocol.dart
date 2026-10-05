import 'dart:convert';
import 'backend_key.dart';
import 'gateway_identity.dart';
import 'gateway_net.dart';
import 'mqtt_target.dart';
import '../l10n/l10n.dart';

/// [GatewayFailure.network] `detail` for a timed-out request (a code, not
/// words: the screen shows `common_timeout`; see [GatewayFailure.isNetworkTimeout]).
const networkTimeoutDetail = 'timeout';

const nusService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const nusRx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const nusTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
const sensitiveOps = {
  'reboot',
  'set_wifi',
  'set_config',
  'set_site_identity',
  'ota_update',
  'join_fleet',
  'leave_fleet',
  'set_mqtt_target',
};

enum ProtocolProfile { legacy, current }

ProtocolProfile profileFor(String version) {
  final parts = version.split('.').map(int.tryParse).toList();
  return parts.length >= 2 && (parts[0] ?? 0) == 1 && (parts[1] ?? 0) >= 7
      ? ProtocolProfile.current
      : ProtocolProfile.legacy;
}

/// [version] (`fw_version`, e.g. `1.7.36`, `v1.7.37-dev`) is at least
/// [major].[minor].[patch]; false when it cannot be read.
bool firmwareAtLeast(Object? version, int major, int minor, int patch) {
  final match = RegExp(
    r'(\d+)\.(\d+)(?:\.(\d+))?',
  ).firstMatch(version?.toString() ?? '');
  if (match == null) return false;
  final got = [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.tryParse(match.group(3) ?? '') ?? 0,
  ];
  final want = [major, minor, patch];
  for (var i = 0; i < 3; i++) {
    if (got[i] != want[i]) return got[i] > want[i];
  }
  return true;
}

Duration commandTimeout(String op, Map<String, dynamic> params) => Duration(
  seconds: switch (op) {
    'ping' || 'set_wifi' => 5,
    'scan_ble_discover' => (params['duration'] as int? ?? 10) + 8,
    'assign_device_id' => 30,
    'get_ble_devices' => 20,
    'check_db_upload' => 15,
    _ => 12,
  },
);

class GatewayFailure implements Exception {
  const GatewayFailure(
    this.code, {
    this.status,
    this.endpoint,
    this.detail,
    this.backend,
    this.fromGateway = false,
    this.expected,
    this.cause,
  });

  /// HTTP error from the dashboard API (non-2xx other than 401/409).
  const GatewayFailure.http({
    required int this.status,
    required String this.endpoint,
    this.detail,
    this.backend,
    this.cause,
  }) : code = 'api',
       fromGateway = false,
       expected = null;

  /// Backend could not be reached (socket error, refused, TLS, timeout).
  const GatewayFailure.network({
    required String this.endpoint,
    this.detail,
    this.backend,
  }) : code = 'network',
       status = null,
       fromGateway = false,
       expected = null,
       cause = null;

  /// Fail ack sent by the gateway firmware over BLE; [detail] keeps the raw
  /// ack result when it was not a plain string.
  /// [GatewayFailure.network] whose request timed out: [detail] is the
  /// language-neutral [networkTimeoutDetail] (was the word 「逾時」, which
  /// logic compared against; 2026-10-05 i18n).
  bool get isNetworkTimeout =>
      code == 'network' && detail == networkTimeoutDetail;

  const GatewayFailure.gateway(String text, {this.detail})
    : code = text,
      status = null,
      endpoint = null,
      backend = null,
      fromGateway = true,
      expected = null,
      cause = null;

  /// Fail ack of `set_mqtt_target`; [reason] is the firmware code.
  const GatewayFailure.uploadTarget(String reason)
    : code = 'upload_target',
      detail = reason,
      status = null,
      endpoint = null,
      backend = null,
      fromGateway = true,
      expected = null,
      cause = null;

  /// Step 7 preflight: the gateway uploads to [gatewayTarget] while the APP
  /// verifies against [appTarget], so the data can never arrive.
  const GatewayFailure.targetMismatch({
    required String gatewayTarget,
    required String appTarget,
  }) : code = 'target_mismatch',
       detail = gatewayTarget,
       expected = appTarget,
       status = null,
       endpoint = null,
       backend = null,
       fromGateway = false,
       cause = null;

  /// After switching, the gateway reports [actual] instead of [wanted].
  const GatewayFailure.targetReadback({
    required String actual,
    required String wanted,
  }) : code = 'target_readback',
       detail = actual,
       expected = wanted,
       status = null,
       endpoint = null,
       backend = null,
       fromGateway = false,
       cause = null;

  /// Any non-GatewayFailure exception; keeps its type and a short text.
  factory GatewayFailure.unexpected(Object error) {
    var text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 120) text = '${text.substring(0, 120)}…';
    final type = error.runtimeType.toString();
    return GatewayFailure(
      'unexpected',
      detail: text.startsWith(type) ? text : '$type: $text',
    );
  }

  final String code;
  final int? status;
  final String? endpoint, detail, backend;
  final bool fromGateway;

  /// Upload target the APP expected (target_mismatch / target_readback).
  final String? expected;

  /// Known reason that replaces the generic "other backend" guess of the
  /// 404 gateway_not_found text (see [withCause]).
  final String? cause;

  /// Same HTTP failure with a [cause] the caller knows better.
  GatewayFailure withCause(String cause) => GatewayFailure.http(
    status: status ?? 0,
    endpoint: endpoint ?? '',
    detail: detail,
    backend: backend,
    cause: cause,
  );

  /// Backend 404 because it has no row for the gateway.
  bool get gatewayNotFound =>
      code == 'api' && status == 404 && detail == 'gateway_not_found';

  static final _gatewayPath = RegExp(r'^/api/gateways/(\d+)/(\d+)(/|$)');

  String get _backendText => backend ?? '目前設定的後端';

  String get _httpMessage {
    final path = endpoint ?? '';
    final match = _gatewayPath.firstMatch(path.split(' ').last);
    if (status == 404 && detail == 'gateway_not_found') {
      final where = match == null
          ? ''
          : '（站 ${match.group(1)} / 閘道器 ${match.group(2)}）';
      if (cause != null) {
        return '後端找不到此閘道器$where（APP 目前連的是 $_backendText）。$cause\n'
            '[HTTP 404 · $path · gateway_not_found]';
      }
      return '後端找不到此閘道器$where。閘道器的資料可能上傳到其他後端環境'
          '（例如正式站），而 APP 目前連的是 $_backendText。\n'
          '[HTTP 404 · $path · gateway_not_found]';
    }
    final extra = detail == null || detail!.isEmpty ? '' : ' · $detail';
    if (status != null && status! >= 500) {
      return '後端內部錯誤（HTTP $status），請查看後端紀錄後重試。\n'
          '[$path$extra · $_backendText]';
    }
    return '後端拒絕此請求（HTTP $status）。\n[$path$extra · $_backendText]';
  }

  String get message {
    if (code == 'upload_target') return uploadTargetFailureText(detail ?? '');
    if (fromGateway && !_knownCodes.contains(code)) {
      if (code.isEmpty) return '閘道器回報失敗（未提供原因）。';
      final lower = code.toLowerCase();
      if (lower.contains('service not ready')) {
        return '閘道器藍牙服務尚未就緒，請稍後再試';
      }
      if (lower.contains('133') ||
          lower.contains('connect') ||
          lower.contains('discovery')) {
        return 'PTU 連線失敗，請確認 PTU 電源與距離';
      }
      if (lower.contains('timeout')) return 'PTU 沒有回應';
      // Never show a raw JSON ack in the banner (it stays in detail).
      if (code.contains('{')) return '閘道器回報失敗，請查看詳細資訊。';
      return '閘道器回報失敗：$code';
    }
    return switch (code) {
      'api' when status != null => _httpMessage,
      'network' =>
        '無法連到 $_backendText。請確認手機與後端電腦在同一個 Wi-Fi 網段、'
            '電腦防火牆允許該連接埠，以及後端網址是否正確。\n'
            '[$endpoint${detail == null ? '' : ' · ${isNetworkTimeout ? L10n.current.common_timeout : detail}'}]',
      'bad_response' =>
        '後端回應格式無法解析（$_backendText）。\n'
            '[${endpoint ?? ''}${detail == null ? '' : ' · $detail'}]',
      'unexpected' => 'APP 發生未預期錯誤：${detail ?? '未知'}',
      'target_mismatch' =>
        '閘道器目前把資料送到$detail，但手機連的是$expected，'
            '資料到不了手機連的這個後端，所以直接停止驗證（不必空等）。\n'
            '請在「連線狀態」按「同步」，或點右上角的環境按鈕重新選一次，'
            '讓閘道器和手機連同一個地方後再驗證。',
      'target_readback' =>
        '閘道器重新連上後回報的資料上傳目的地是$detail，不是要求的$expected。'
            '設定可能沒有生效，請在「連線狀態」按重新讀取確認，或再同步一次。',
      'target_reconnect' =>
        '閘道器已收到切換指令並重新開機，但 45 秒內未能重新連上藍牙。'
            '請靠近閘道器，按「結束並重新選擇閘道器」重新連線後看「連線狀態」。',
      'target_unsupported' => legacyTargetText(detail),
      'ble_error' => bleErrorText(detail),
      _ => _baseMessage,
    };
  }

  static const _knownCodes = {
    'time_not_synced',
    'expired',
    'otp_required',
    'otp_invalid',
    'otp_locked',
    'otp_reused',
    'not_ready',
    'busy',
    'timeout',
    'ambiguous_target',
    'write_failed',
  };

  String get _baseMessage => switch (code) {
    'time_not_synced' => '閘道器時間尚未同步。若無可用網路，請先以 USB 更新韌體。',
    'expired' => '指令已逾期（手機時間與閘道器差異過大或傳送延遲），請重試',
    'otp_required' || 'otp_enabled' => '此閘道器已啟用一次性密碼，請聯絡管理員。',
    'otp_invalid' => '一次性密碼錯誤',
    'otp_locked' => '一次性密碼已鎖定，請稍後再試',
    'otp_reused' => '一次性密碼已用過',
    'not_ready' || 'busy' => '閘道器正在準備或處理其他操作，請稍後重試。',
    'permission' => '需要藍牙權限，請至系統設定允許後重試。',
    'bluetooth_off' => '請開啟手機藍牙後重試。',
    'ambiguous_target' => '閘道器同時連著多台 PTU，無法判斷要辨識哪一台，請指定 PTU 後重試。',
    'write_failed' => '寫入 PTU 失敗（閘道器未能送出辨識指令），請確認 PTU 電源與距離後重試。',
    'identify_no_ptu' => '閘道器尚未連上 PTU，無法讓 PTU 閃燈。請確認同樁 PTU 已上電並靠近後重試。',
    'direct_no_ptu' => '閘道器目前沒有連上 PTU，無法綁定。請等 PTU 連上後再試。',
    'direct_unsupported' => '此韌體尚未支援直連門檻與綁定，請先更新韌體（1.7.20 起）。',
    'direct_pick_missing' => '閘道器目前沒有連上 PTU，請確認 PTU 電源後按「重新搜尋」。',
    'direct_threshold_not_saved' => '門檻未寫入閘道器（回讀的值不同），請重試。',
    // Round 28: 〔先完成配置〕 did not end with the gateway in service.
    'direct_defer_unconfirmed' =>
      '閘道器沒有回報已加入運作並恢復上傳，配置尚未完成。請再按一次「先完成配置」；若仍不行，請按「請後台協助」。',
    // Round 30 (user rehearsal 09-27): the data passed, but the gateway
    // did not report `fleet_joined` even after the APP sent join_fleet.
    'fleet_unconfirmed' => fleetUnconfirmedText,
    'direct_switch_failed' =>
      '閘道器在等待時限內還沒改連這台 PTU（已暫時綁定它）。連上後畫面會自動更新；也可確認這台 PTU 已上電並靠近，或改選其他 PTU。',
    'invalid_identify_seconds' =>
      '辨識秒數必須是 0（關燈）或 2–10 的整數；1 秒會讓 PTU 燈恆亮，因此不提供。',
    'identify_duration_unsupported' =>
      '這台舊版閘道器不支援所選辨識秒數。支援 PTU 辨識的舊版僅可用 1–30 秒，更早版本固定 6 秒；其他秒數（含 0 秒關燈）請更新閘道器韌體。',
    'identify_unsupported' => '此韌體尚未支援辨識燈號，請先更新韌體。連線時的呼吸燈仍可協助辨識。',
    'location_off' => '此版本 Android 搜尋藍牙需要定位服務，請開啟手機定位後重新搜尋。',
    'disconnected' || 'not_connected' => '與閘道器的連線已中斷，請靠近後重新連線。',
    'phone_link_lost' => phoneLinkLostText,
    'identity_archived' => identityArchivedText,
    'reconnect_failed' => reconnectFailedText,
    'timeout' => '等待超時，請確認裝置與網路後重試。',
    'cancelled' => '操作已取消，可從最近完成的步驟重試。',
    'monitor_unconfirmed' => '30 秒內未確認閘道器已恢復監控，可按「重新連線並繼續」重試，或「略過」直接驗證資料。',
    'conflict' => '此站點或編號已被使用，請選擇其他編號。',
    'replace_unsupported' => '後端版本不支援取代舊機，請改用下一個編號。裝置設定未變更。',
    'replace_pending' => '後台已登記為新機，但寫入裝置失敗。請重新執行配置，系統會沿用取代設定。',
    'new_site_required' => '請輸入與目前站點不同的新站點 ID。',
    // Firmware 1.7.32 tells why (wifi_last_disc_reason, see [wifiFailedDetail]).
    'wifi_failed' => wifiSetFailedText(wifiFailedReason(detail)),
    // Round 30: the Wi-Fi to keep was gone by 「儲存」 (no password given).
    'wifi_password_needed' => '閘道器目前沒有連上這個 Wi-Fi，無法沿用。請輸入 Wi-Fi 密碼後再按「儲存並繼續」。',
    'no_devices' => '未找到 PTU。請確認已上電並靠近閘道器後重掃。',
    // Round 26: an old gateway in test mode never scans PTUs.
    'test_mode' => testModeText,
    'ptu_identity_mismatch' =>
      '後台資料的 PTU 身分與本次選擇不符，或缺少 MAC，尚未完成驗證。請返回確認本樁 PTU；若仍不符，請後台協助。',
    'test_mode_stuck' => '閘道器重新開機後仍在測試模式，請再按一次「$leaveTestModeLabel」；若仍不行，請按求助。',
    'upload_paused' => '閘道器仍回報資料上傳暫停，請再按一次「$resumeUploadLabel」；若仍不行，請按求助。',
    'gateway_full' => '本機已滿，請連另一台閘道器。',
    'incomplete' => '仍有 PTU 未連線或資料未到達，請查看各台狀態後重試。',
    'authentication' => '後台登入失敗或已失效，請稍後重試；若仍失敗，請聯絡管理員更新 APP。',
    'missing_backend_key' => missingBackendKeyText,
    'backend_unavailable' => backendUnavailableText,
    'https_required' => '正式環境需要有效的 HTTPS 網址。',
    _ => '操作未完成，請確認裝置狀態後重試。',
  };

  @override
  String toString() =>
      'GatewayFailure($code'
      '${status == null ? '' : ', $status'}'
      '${endpoint == null ? '' : ', $endpoint'}'
      '${detail == null ? '' : ', $detail'})';
}

/// Round 30 (user rehearsal 09-27, P0 candidate A): step 9 found the
/// gateway not in service (`fleet_joined` false) and join_fleet sent once
/// did not change it — no done page.
const fleetUnconfirmedText =
    '資料已上傳，但閘道器沒有回報「已加入監控」（APP 已自動補送一次），開通尚未完成。'
    '請靠近閘道器後按「開始資料驗證」重試；若仍不行，請按「請後台協助」。';

/// Step 8: the phone's BLE link to the gateway dropped (not a PTU failure).
const phoneLinkLostText = '手機與閘道器的藍牙連線中斷，請靠近閘道器後按「重新連線並繼續」';

/// 09-28 (GC 刪除 56/1, then the same gateway configured again): 確認上線
/// found the station archived in the back office — its heartbeats are not
/// recorded, so they would never arrive. The first sentence is the
/// checklist item's reason ([checklistReason]).
const identityArchivedText =
    '這台閘道器之前在後台被移除（封存），後台不會記錄它的心跳。'
    '請按下方「重新加入」，恢復記錄後會繼續確認上線。';

/// Step 9 stopped: the backend stayed unavailable (5xx / unreachable /
/// timeout) through the automatic retries (round 13).
const backendUnavailableText =
    '後端暫時無回應，已自動重試 60 秒仍未恢復。請確認後端後按「重試」，已累計的驗證進度會保留。';

/// Reconnecting the phone to the gateway did not succeed in time.
const reconnectFailedText = '重新連線失敗，請靠近閘道器後重試，或回到找閘道器。';

/// Phone could not open the BLE link (UniversalBleException, e.g. GATT 133).
String bleErrorText(String? detail) {
  final code = RegExp(r'^(\d{1,3}) ').firstMatch(detail ?? '')?.group(1);
  return code == null
      ? '無法連上閘道器（藍牙錯誤），請靠近閘道器後重試'
      : '無法連上閘道器（藍牙錯誤 $code），請靠近閘道器後重試';
}

/// True for failures meaning the phone↔gateway BLE link itself is down.
bool isPhoneLinkFailure(Object? error) =>
    error is GatewayFailure &&
    const {
      'not_connected',
      'disconnected',
      'phone_link_lost',
      'reconnect_failed',
      'ble_error',
    }.contains(error.code);

/// Fail ack → [GatewayFailure]: a map result (e.g. assign_device_id's
/// `{mac, success:false, error}`) uses its `error` text as the code and keeps
/// the raw JSON as detail.
GatewayFailure gatewayAckFailure(Object? result) {
  if (result is String && result.trimLeft().startsWith('{')) {
    try {
      result = jsonDecode(result);
    } on FormatException {
      // keep the text
    }
  }
  if (result is Map) {
    final error = result['error'] ?? result['reason'] ?? result['message'];
    return GatewayFailure.gateway(
      error?.toString() ?? '',
      detail: jsonEncode(result),
    );
  }
  return GatewayFailure.gateway(result?.toString() ?? '');
}

/// Byte framing keeps split UTF-8 characters intact and respects JSON strings.
class JsonFrames {
  final List<int> _buffer = [];
  void clear() => _buffer.clear();
  List<Map<String, dynamic>> add(List<int> bytes) {
    _buffer.addAll(bytes);
    if (_buffer.length > 65536) {
      clear();
      throw const GatewayFailure('frame_size');
    }
    final frames = <Map<String, dynamic>>[];
    int start = -1, depth = 0, consumed = 0;
    bool quoted = false, escaped = false;
    for (int i = 0; i < _buffer.length; i++) {
      final c = _buffer[i];
      if (start < 0) {
        if (c != 123) {
          consumed = i + 1;
          continue;
        }
        start = i;
      }
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == 92) {
          escaped = true;
        } else if (c == 34) {
          quoted = false;
        }
      } else if (c == 34) {
        quoted = true;
      } else if (c == 123) {
        depth++;
      } else if (c == 125) {
        depth--;
        if (depth == 0) {
          try {
            frames.add(
              jsonDecode(utf8.decode(_buffer.sublist(start, i + 1)))
                  as Map<String, dynamic>,
            );
          } on FormatException {
            /* Discard only the malformed complete frame. */
          }
          consumed = i + 1;
          start = -1;
        }
      }
    }
    if (consumed > 0) _buffer.removeRange(0, consumed);
    return frames;
  }
}
