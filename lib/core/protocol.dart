import 'dart:convert';

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
  const GatewayFailure(this.code);
  final String code;
  String get message => switch (code) {
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
