/// Gateway MQTT upload target (firmware 1.7.3+, docs/mqtt_target.md).
///
/// Pure Dart: parsing of `get_config` / `get_net_status` / `set_mqtt_target`
/// payloads, mapping of the APP backend environment to the target the gateway
/// should upload to, and the user-facing texts shared by UI and controller.
///
/// i18n 範本（無 context 層，docs/i18n.md）：畫面文字用 [L10n.current]；
/// 安裝報告（上傳後台、分享、複製）的 [reportTargetText] 固定用 [L10n.zh]。
/// 字串在 lib/l10n/parts/mqttTarget_*.arb。
library;

import 'dart:convert';

import '../l10n/l10n.dart';

const defaultMqttPort = 8883;

/// Production API base; `--dart-define=API_BASE=...` overrides it.
/// 09-28: the production site stays on its public IP (no domain name); the
/// certificate is verified against the build's CA (`API_CA_PEM_B64`,
/// optionally pinned with `API_CERT_SHA256`; cert_pin.dart).
const productionApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://$productionApiHost',
);

/// Default production API host (public IPv4, never a local target).
const productionApiHost = '46.250.255.172';

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
  String get label => labelIn(L10n.current);

  /// [label] in [l10n] (the install report always uses [L10n.zh]).
  String labelIn(AppLocalizations l10n) => isLocal
      ? l10n.mqttTarget_localHostPort(host, '$port')
      : l10n.mqttTarget_production;

  /// 正式站 / 本地 host (button text).
  String get shortLabel => isLocal
      ? L10n.current.mqttTarget_localHost(host)
      : L10n.current.mqttTarget_production;

  /// Plain wording for non-developers: 正式站 / 本地測試主機（host）. The
  /// port is technical detail and never shown here.
  String get plainLabel => isLocal
      ? L10n.current.mqttTarget_plainLocal(host)
      : L10n.current.mqttTarget_plainProduction;

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
      (h == productionApiHost || h == _host(productionApiBase));
}

/// Maps the APP backend environment (`production` / `local` / `custom`, as
/// stored by the environment selector) and its URL to the gateway target.
AppUploadTarget desiredUploadTarget(String environment, String baseUrl) {
  if (environment == 'production') {
    return const AppUploadTarget.known(MqttTarget.production());
  }
  final host = _host(baseUrl);
  if (environment == 'local') {
    final l10n = L10n.current;
    if (host.isEmpty) {
      return AppUploadTarget.invalid(
        baseUrl.trim().isEmpty
            ? l10n.mqttTarget_localUrlEmpty
            : l10n.mqttTarget_localUrlUnparsable(baseUrl.trim()),
      );
    }
    if (!isPrivateIpv4Literal(host)) {
      return AppUploadTarget.invalid(
        l10n.mqttTarget_localHostNotPrivate(host),
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
String get localTargetShipWarning => L10n.current.mqttTarget_shipWarning;

/// Upload-target lines of the install report. The report goes to the back
/// office (and is shared / copied), so it stays in Chinese ([L10n.zh])
/// whatever the screen language (docs/i18n.md 「上傳後台維持中文」).
String reportTargetText(Map<String, dynamic> config) {
  final zh = L10n.zh;
  final target = parseMqttTarget(config);
  if (target == null) {
    return reportsMqttTarget(config)
        ? zh.mqttTarget_reportUnconfirmed
        : zh.mqttTarget_reportLegacy(
            '${config['fw_version'] ?? zh.common_unknown}',
          );
  }
  final where = target.isLocal || target.host.isEmpty
      ? target.labelIn(zh)
      : zh.mqttTarget_productionHostPort(target.host, '${target.port}');
  final line = zh.mqttTarget_reportLine(where);
  return target.isLocal
      ? '$line\n${zh.mqttTarget_reportNote(zh.mqttTarget_shipWarning)}'
      : line;
}

String legacyTargetText(Object? version) {
  final v = version?.toString() ?? '';
  return L10n.current.mqttTarget_legacyFirmware(
    v.isEmpty ? L10n.current.common_unknown : v,
  );
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
  final l10n = L10n.current;
  final text = switch (code) {
    'invalid_params' => l10n.mqttTarget_failInvalidParams,
    'invalid_target' => l10n.mqttTarget_failInvalidTarget,
    'invalid_host' => l10n.mqttTarget_failInvalidHost,
    'invalid_port' => l10n.mqttTarget_failInvalidPort,
    'ota_in_progress' => l10n.mqttTarget_failOtaInProgress,
    'nvs_write_failed' => l10n.mqttTarget_failNvsWrite,
    'ble_only' => l10n.mqttTarget_failBleOnly,
    'otp_required' => l10n.mqttTarget_failOtpRequired,
    'otp_invalid' => l10n.mqttTarget_failOtpInvalid,
    'otp_reused' => l10n.mqttTarget_failOtpReused,
    'otp_locked' => l10n.mqttTarget_failOtpLocked,
    'time_not_synced' => l10n.mqttTarget_failTimeNotSynced,
    'not_ready' => l10n.mqttTarget_failNotReady,
    'busy' => l10n.mqttTarget_failBusy,
    'invalid req_id' => l10n.mqttTarget_failInvalidReqId,
    'unknown op' => l10n.mqttTarget_failUnknownOp,
    '' => l10n.mqttTarget_failNoReason,
    _ => l10n.mqttTarget_failOther,
  };
  return '$text\n[set_mqtt_target · ${code.isEmpty ? '—' : code}]';
}
