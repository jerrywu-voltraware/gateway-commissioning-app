import 'dart:convert';
import 'mqtt_target.dart';

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
  });

  /// HTTP error from the dashboard API (non-2xx other than 401/409).
  const GatewayFailure.http({
    required int this.status,
    required String this.endpoint,
    this.detail,
    this.backend,
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
       expected = null;

  /// Fail ack sent by the gateway firmware over BLE.
  const GatewayFailure.gateway(String text)
    : code = text,
      status = null,
      endpoint = null,
      detail = null,
      backend = null,
      fromGateway = true,
      expected = null;

  /// Fail ack of `set_mqtt_target`; [reason] is the firmware code.
  const GatewayFailure.uploadTarget(String reason)
    : code = 'upload_target',
      detail = reason,
      status = null,
      endpoint = null,
      backend = null,
      fromGateway = true,
      expected = null;

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
       fromGateway = false;

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
       fromGateway = false;

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

  static final _gatewayPath = RegExp(r'^/api/gateways/(\d+)/(\d+)(/|$)');

  String get _backendText => backend ?? '目前設定的後端';

  String get _httpMessage {
    final path = endpoint ?? '';
    final match = _gatewayPath.firstMatch(path.split(' ').last);
    if (status == 404 && detail == 'gateway_not_found') {
      final where = match == null
          ? ''
          : '（站 ${match.group(1)} / Gateway ${match.group(2)}）';
      return '後端找不到此 Gateway$where。Gateway 的資料可能上傳到其他後端環境'
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
      return code.isEmpty ? 'Gateway 回報失敗（未提供原因）。' : 'Gateway 回報失敗：$code';
    }
    return switch (code) {
      'api' when status != null => _httpMessage,
      'network' =>
        '無法連到 $_backendText。請確認手機與後端電腦在同一個 Wi-Fi 網段、'
            '電腦防火牆允許該連接埠，以及後端網址是否正確。\n'
            '[$endpoint${detail == null ? '' : ' · $detail'}]',
      'bad_response' =>
        '後端回應格式無法解析（$_backendText）。\n'
            '[${endpoint ?? ''}${detail == null ? '' : ' · $detail'}]',
      'unexpected' => 'APP 發生未預期錯誤：${detail ?? '未知'}',
      'target_mismatch' =>
        'Gateway 目前上傳到$detail，但 APP 連線的是$expected，'
            '資料不會進入這個後端，因此不等待、直接停止驗證。\n'
            '請先在「Gateway 上傳目標」將 Gateway 切換到$expected，'
            '或把 APP 的連線環境改成與 Gateway 一致後再驗證。',
      'target_readback' =>
        'Gateway 重新連線後回報的上傳目標是$detail，不是要求的$expected。'
            '設定可能未生效，請按「重新讀取」確認或再切換一次。',
      'target_reconnect' =>
        'Gateway 已收到切換指令並重新開機，但 45 秒內未能重新連上藍牙。'
            '請靠近 Gateway，按「結束並重新選擇閘道器」重新連線後確認上傳目標。',
      'target_unsupported' => legacyTargetText(detail),
      _ => _baseMessage,
    };
  }

  static const _knownCodes = {
    'time_not_synced',
    'expired',
    'otp_required',
    'otp_enabled',
    'not_ready',
    'busy',
    'timeout',
  };

  String get _baseMessage => switch (code) {
    'time_not_synced' || 'expired' => '閘道器時間尚未同步。若無可用網路，請先以 USB 更新韌體。',
    'otp_required' || 'otp_enabled' => '此閘道器已啟用一次性密碼，請聯絡管理員。',
    'not_ready' || 'busy' => '閘道器正在準備或處理其他操作，請稍後重試。',
    'permission' => '需要藍牙權限，請至系統設定允許後重試。',
    'bluetooth_off' => '請開啟手機藍牙後重試。',
    'disconnected' => '與閘道器的連線已中斷，請靠近後重新連線。',
    'timeout' => '等待超時，請確認裝置與網路後重試。',
    'cancelled' => '操作已取消，可從最近完成的步驟重試。',
    'conflict' => '此站點或編號已被使用，請選擇其他編號。',
    'new_site_required' => '請輸入與目前站點不同的新站點 ID。',
    'wifi_failed' => '新 WiFi 連線未成功，請檢查密碼與訊號後重試。',
    'no_devices' => '未找到 PTU。請確認已上電並靠近閘道器後重掃。',
    'incomplete' => '仍有 PTU 未連線或資料未到達，請查看各台狀態後重試。',
    'authentication' => '登入失敗或已失效，請重新輸入登入資訊。',
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
