/// Gateway MQTT upload target (firmware 1.7.3+, docs/mqtt_target.md).
///
/// Pure Dart: parsing of `get_config` / `get_net_status` / `set_mqtt_target`
/// payloads, mapping of the APP backend environment to the target the gateway
/// should upload to, and the user-facing texts shared by UI and controller.
library;

import 'dart:convert';

const defaultMqttPort = 8883;

/// Production API base; `--dart-define=API_BASE=...` overrides it.
const productionApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://dashboard.voltraware.com',
);
const _productionApiHost = 'dashboard.voltraware.com';

/// Keys the controller copies from `get_net_status` / `get_config` results.
const mqttStatusKeys = [
  'mqtt_target',
  'mqtt_host',
  'mqtt_port',
  'mqtt_connected',
];

/// APP-only `mqtt_target` value: a switch was sent but its result could not
/// be read back, so the running target is unknown until the next read.
const unconfirmedMqttTarget = 'unconfirmed';

enum MqttTargetKind { production, local }

class MqttTarget {
  const MqttTarget.production({this.host = '', this.port = defaultMqttPort})
    : kind = MqttTargetKind.production;
  const MqttTarget.local(this.host, {this.port = defaultMqttPort})
    : kind = MqttTargetKind.local;

  final MqttTargetKind kind;

  /// Broker host/port as reported by the firmware (informational for production).
  final String host;
  final int port;

  bool get isLocal => kind == MqttTargetKind.local;

  /// 正式站 / 本地 host:port
  String get label => isLocal ? '本地 $host:$port' : '正式站';

  /// 正式站 / 本地 host (button text).
  String get shortLabel => isLocal ? '本地 $host' : '正式站';

  /// Plain wording for non-developers: 正式站 / 本地測試主機（host）.
  String get plainLabel => isLocal
      ? '本地測試主機（$host${port == defaultMqttPort ? '' : ':$port'}）'
      : '正式站';

  /// `params` of the `set_mqtt_target` request.
  Map<String, dynamic> get params => isLocal
      ? {'target': 'local', 'host': host, 'port': port}
      : {'target': 'production'};

  /// The `mqtt_target` / `mqtt_host` / `mqtt_port` fields for the config.
  Map<String, dynamic> get fields => {
    'mqtt_target': kind.name,
    'mqtt_host': host,
    'mqtt_port': port,
  };

  /// Production is one target whatever host the firmware reports; local
  /// targets must agree on host and port.
  bool sameAs(MqttTarget other) =>
      kind == other.kind &&
      (!isLocal || (host == other.host && port == other.port));

  @override
  String toString() => 'MqttTarget(${kind.name} $host:$port)';
}

/// True when the firmware reports its upload target (1.7.3+). Older firmware
/// has no `mqtt_target` field and cannot switch.
bool reportsMqttTarget(Map<String, dynamic> json) =>
    json['mqtt_target'] is String;

/// Running target from a `get_config` / `get_net_status` result; null when
/// the field is missing (legacy firmware) or holds an unknown value.
MqttTarget? parseMqttTarget(Map<String, dynamic> json) {
  final port = json['mqtt_port'] is num
      ? (json['mqtt_port'] as num).toInt()
      : defaultMqttPort;
  final host = json['mqtt_host'] is String ? json['mqtt_host'] as String : '';
  return switch (json['mqtt_target']) {
    'production' => MqttTarget.production(host: host, port: port),
    'local' => MqttTarget.local(host, port: port),
    _ => null,
  };
}

/// Successful `set_mqtt_target` ACK result.
class SetTargetAck {
  const SetTargetAck(this.target, {required this.changed, this.rebootInMs = 0});
  final MqttTarget target;
  final bool changed;
  final int rebootInMs;
}

/// Parses the ok-ACK result, which the firmware sends as a JSON *string*.
///
/// Accepts the already-decoded map (the BLE link decodes string results) as
/// well as the raw string wrapped by the link (`message` / `value`). Returns
/// null when the payload does not follow the contract.
SetTargetAck? parseSetTargetAck(Object? payload) {
  Object? data = payload;
  if (data is Map && !data.containsKey('mqtt_target')) {
    data = data['message'] ?? data['value'];
  }
  if (data is String) {
    try {
      data = jsonDecode(data);
    } on FormatException {
      return null;
    }
  }
  if (data is! Map) return null;
  final map = Map<String, dynamic>.from(data);
  final target = parseMqttTarget(map);
  final changed = map['changed'];
  if (target == null || changed is! bool) return null;
  return SetTargetAck(
    target,
    changed: changed,
    rebootInMs: (map['reboot_in_ms'] as num?)?.toInt() ?? (changed ? 1500 : 0),
  );
}

final _ipv4 = RegExp(
  r'^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$',
);

/// Same rule as the firmware (`nvs_config_is_private_ipv4`): a literal
/// dotted-quad in 10/8, 172.16/12 or 192.168/16, no leading zeros, nothing
/// else (no hostname, port or whitespace).
bool isPrivateIpv4Literal(String value) {
  final match = _ipv4.firstMatch(value);
  if (match == null) return false;
  final o = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
  if (o.any((v) => v > 255)) return false;
  return o[0] == 10 ||
      (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
      (o[0] == 192 && o[1] == 168);
}

/// Upload target that matches the backend the APP talks to.
class AppUploadTarget {
  const AppUploadTarget.known(MqttTarget this.target) : error = null;
  const AppUploadTarget.unknown() : target = null, error = null;
  const AppUploadTarget.invalid(String this.error) : target = null;

  /// Null when unknown or invalid.
  final MqttTarget? target;

  /// Why the local backend URL cannot be used as a gateway target.
  final String? error;

  /// The APP is (or tries to be) on a local backend.
  bool get wantsLocal => target?.isLocal == true || error != null;
}

String _host(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri != null && uri.hasAuthority ? uri.host : '';
}

bool _isProductionHost(String host) {
  final h = host.toLowerCase();
  return h.isNotEmpty &&
      (h == _productionApiHost || h == _host(productionApiBase));
}

/// Maps the APP backend environment (`production` / `local` / `custom`, as
/// stored by the environment selector) and its URL to the gateway target.
AppUploadTarget desiredUploadTarget(String environment, String baseUrl) {
  if (environment == 'production') {
    return const AppUploadTarget.known(MqttTarget.production());
  }
  final host = _host(baseUrl);
  if (environment == 'local') {
    if (host.isEmpty) {
      return AppUploadTarget.invalid(
        baseUrl.trim().isEmpty
            ? '尚未輸入本地測試站網址，無法決定 Gateway 的上傳目標。'
            : '本地測試站網址「${baseUrl.trim()}」無法解析主機位址，'
                  '請輸入如 http://192.168.1.10:18000 的網址。',
      );
    }
    if (!isPrivateIpv4Literal(host)) {
      return AppUploadTarget.invalid(
        '本地測試站網址的主機「$host」不是區網私有 IPv4 位址'
        '（10.x.x.x、172.16–31.x.x、192.168.x.x），Gateway 無法上傳到此後端。'
        '請把網址改成電腦的區網 IP。',
      );
    }
    return AppUploadTarget.known(MqttTarget.local(host));
  }
  if (isPrivateIpv4Literal(host)) {
    return AppUploadTarget.known(MqttTarget.local(host));
  }
  if (_isProductionHost(host)) {
    return const AppUploadTarget.known(MqttTarget.production());
  }
  return const AppUploadTarget.unknown();
}

/// Step 7 warning when the gateway still uploads to a local test backend.
const localTargetShipWarning = '此 Gateway 目前上傳到本地測試站，出貨前請切回正式站。';

/// Upload-target lines of the install report.
String reportTargetText(Map<String, dynamic> config) {
  final target = parseMqttTarget(config);
  if (target == null) {
    return reportsMqttTarget(config)
        ? '資料上傳目標：未確認'
        : '資料上傳目標：正式站（韌體 ${config['fw_version'] ?? '未知'} 固定）';
  }
  final where = target.isLocal || target.host.isEmpty
      ? target.label
      : '正式站 ${target.host}:${target.port}';
  return target.isLocal
      ? '資料上傳目標：$where\n注意：$localTargetShipWarning'
      : '資料上傳目標：$where';
}

String legacyTargetText(Object? version) {
  final v = version?.toString() ?? '';
  return '這台 Gateway 韌體太舊（版本 ${v.isEmpty ? '未知' : v}），'
      '只能送到正式站，請更新到 1.7.3 以上。';
}

/// First three octets of a dotted-quad IPv4 (`192.168.0`), null otherwise.
String? ipv4Prefix24(String ip) {
  final match = _ipv4.firstMatch(ip.trim());
  if (match == null) return null;
  final o = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
  if (o.any((v) => v > 255)) return null;
  return '${o[0]}.${o[1]}.${o[2]}';
}

/// Fail codes of `set_mqtt_target` (docs/mqtt_target.md §2).
String uploadTargetFailureText(String code) {
  final text = switch (code) {
    'invalid_params' => 'Gateway 拒絕切換：指令參數格式錯誤。請更新 APP 後重試。',
    'invalid_target' => 'Gateway 拒絕切換：上傳目標名稱無效。請更新 APP 後重試。',
    'invalid_host' =>
      'Gateway 拒絕切換：本地後端位址必須是區網私有 IPv4'
          '（10.x、172.16–31.x、192.168.x），不可使用主機名稱或公網 IP。',
    'invalid_port' => 'Gateway 拒絕切換：MQTT 連接埠必須是 1–65535 的整數。',
    'ota_in_progress' => 'Gateway 正在更新韌體（OTA），更新完成前無法切換上傳目標，請稍後重試。',
    'nvs_write_failed' => 'Gateway 儲存設定失敗，上傳目標未變更、也沒有重新開機。請重試；若持續失敗請回報。',
    'ble_only' => '上傳目標只能在現場透過藍牙切換，不接受遠端指令。',
    'otp_required' => '此 Gateway 已啟用一次性密碼（OTP），切換上傳目標需要 OTP，請聯絡管理員。',
    'otp_invalid' => '一次性密碼（OTP）錯誤，Gateway 拒絕切換。',
    'otp_reused' => '此一次性密碼已使用過，請等下一組 OTP 後重試。',
    'otp_locked' => 'OTP 錯誤次數過多，Gateway 暫時鎖定，請稍後再試。',
    'time_not_synced' =>
      'Gateway 已啟用 OTP 但時間尚未同步（NTP），無法驗證。'
          '若目前 Wi-Fi 無法連到網際網路，請先改用可連外的網路。',
    'not_ready' => 'Gateway 仍在開機初始化，請稍候數秒後重試。',
    'busy' => 'Gateway 正在處理其他指令，請稍候重試。',
    'invalid req_id' => 'APP 送出的指令編號無效，請重新連線後重試。',
    'unknown op' => 'Gateway 韌體不支援切換上傳目標，需更新至 1.7.3 以上。',
    '' => 'Gateway 拒絕切換上傳目標（未提供原因）。',
    _ => 'Gateway 拒絕切換上傳目標。',
  };
  return '$text\n[set_mqtt_target · ${code.isEmpty ? '—' : code}]';
}
