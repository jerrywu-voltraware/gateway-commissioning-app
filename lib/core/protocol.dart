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

  String get _backendText => backend ?? L10n.current.protocol_currentBackend;

  String get _httpMessage {
    final l10n = L10n.current;
    final path = endpoint ?? '';
    final match = _gatewayPath.firstMatch(path.split(' ').last);
    if (status == 404 && detail == 'gateway_not_found') {
      final where = match == null
          ? ''
          : l10n.protocol_notFoundWhere(
              int.parse(match.group(1)!),
              int.parse(match.group(2)!),
            );
      if (cause != null) {
        return '${l10n.protocol_gatewayNotFoundCause(where, _backendText, cause!)}\n'
            '[HTTP 404 · $path · gateway_not_found]';
      }
      return '${l10n.protocol_gatewayNotFound(where, _backendText)}\n'
          '[HTTP 404 · $path · gateway_not_found]';
    }
    final extra = detail == null || detail!.isEmpty ? '' : ' · $detail';
    if (status != null && status! >= 500) {
      return '${l10n.protocol_httpServerError(status!)}\n'
          '[$path$extra · $_backendText]';
    }
    return '${l10n.protocol_httpRejected(status ?? 0)}\n'
        '[$path$extra · $_backendText]';
  }

  String get message {
    final l10n = L10n.current;
    if (code == 'upload_target') return uploadTargetFailureText(detail ?? '');
    if (fromGateway && !_knownCodes.contains(code)) {
      if (code.isEmpty) return l10n.protocol_gatewayFailedNoReason;
      final lower = code.toLowerCase();
      if (lower.contains('service not ready')) {
        return l10n.protocol_gatewayServiceNotReady;
      }
      if (lower.contains('133') ||
          lower.contains('connect') ||
          lower.contains('discovery')) {
        return l10n.protocol_ptuConnectFailed;
      }
      if (lower.contains('timeout')) return l10n.protocol_ptuNoResponse;
      // Never show a raw JSON ack in the banner (it stays in detail).
      if (code.contains('{')) return l10n.protocol_gatewayFailedSeeDetails;
      return l10n.protocol_gatewayFailedWithCode(code);
    }
    return switch (code) {
      'api' when status != null => _httpMessage,
      'network' =>
        '${l10n.protocol_networkUnreachable(_backendText)}\n'
            '[$endpoint${detail == null ? '' : ' · ${isNetworkTimeout ? l10n.common_timeout : detail}'}]',
      'bad_response' =>
        '${l10n.protocol_badResponse(_backendText)}\n'
            '[${endpoint ?? ''}${detail == null ? '' : ' · $detail'}]',
      'unexpected' => l10n.protocol_unexpected(detail ?? l10n.common_unknown),
      'target_mismatch' => l10n.protocol_targetMismatch('$detail', '$expected'),
      'target_readback' => l10n.protocol_targetReadback('$detail', '$expected'),
      'target_reconnect' => l10n.protocol_targetReconnect,
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

  String get _baseMessage {
    final l10n = L10n.current;
    return switch (code) {
      'time_not_synced' => l10n.protocol_timeNotSynced,
      'expired' => l10n.protocol_expired,
      'otp_required' || 'otp_enabled' => l10n.protocol_otpRequired,
      'otp_invalid' => l10n.protocol_otpInvalid,
      'otp_locked' => l10n.protocol_otpLocked,
      'otp_reused' => l10n.protocol_otpReused,
      'not_ready' || 'busy' => l10n.protocol_gatewayBusy,
      'permission' => l10n.protocol_permission,
      'bluetooth_off' => l10n.protocol_bluetoothOff,
      'ambiguous_target' => l10n.protocol_ambiguousTarget,
      'write_failed' => l10n.protocol_writeFailed,
      'identify_no_ptu' => l10n.protocol_identifyNoPtu,
      'direct_no_ptu' => l10n.protocol_directNoPtu,
      'direct_unsupported' => l10n.protocol_directUnsupported,
      'direct_pick_missing' => l10n.protocol_directPickMissing,
      'direct_threshold_not_saved' => l10n.protocol_directThresholdNotSaved,
      // Round 28: 〔先完成配置〕 did not end with the gateway in service.
      'direct_defer_unconfirmed' => l10n.protocol_directDeferUnconfirmed,
      // Round 30 (user rehearsal 09-27): the data passed, but the gateway
      // did not report `fleet_joined` even after the APP sent join_fleet.
      'fleet_unconfirmed' => fleetUnconfirmedText,
      'direct_switch_failed' => l10n.protocol_directSwitchFailed,
      'invalid_identify_seconds' => l10n.protocol_invalidIdentifySeconds,
      'identify_duration_unsupported' =>
        l10n.protocol_identifyDurationUnsupported,
      'identify_unsupported' => l10n.protocol_identifyUnsupported,
      'location_off' => l10n.protocol_locationOff,
      'disconnected' || 'not_connected' => l10n.protocol_disconnected,
      'phone_link_lost' => phoneLinkLostText,
      'identity_archived' => identityArchivedText,
      'reconnect_failed' => reconnectFailedText,
      'timeout' => l10n.protocol_timeout,
      'cancelled' => l10n.protocol_cancelled,
      'monitor_unconfirmed' => l10n.protocol_monitorUnconfirmed,
      'conflict' => l10n.protocol_conflict,
      'replace_unsupported' => l10n.protocol_replaceUnsupported,
      'replace_pending' => l10n.protocol_replacePending,
      'new_site_required' => l10n.protocol_newSiteRequired,
      // Firmware 1.7.32 tells why (wifi_last_disc_reason, see [wifiFailedDetail]).
      'wifi_failed' => wifiSetFailedText(wifiFailedReason(detail)),
      // Round 30: the Wi-Fi to keep was gone by 「儲存」 (no password given).
      'wifi_password_needed' => l10n.protocol_wifiPasswordNeeded,
      'no_devices' => l10n.protocol_noDevices,
      // Round 26: an old gateway in test mode never scans PTUs.
      'test_mode' => testModeText,
      'ptu_identity_mismatch' => l10n.protocol_ptuIdentityMismatch,
      'test_mode_stuck' => l10n.protocol_testModeStuck(leaveTestModeLabel),
      'upload_paused' => l10n.protocol_uploadPaused(resumeUploadLabel),
      'gateway_full' => l10n.protocol_gatewayFull,
      'incomplete' => l10n.protocol_incomplete,
      'authentication' => l10n.protocol_authentication,
      'missing_backend_key' => missingBackendKeyText,
      'backend_unavailable' => backendUnavailableText,
      'https_required' => l10n.protocol_httpsRequired,
      _ => l10n.protocol_otherFailure,
    };
  }

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
String get fleetUnconfirmedText => L10n.current.protocol_fleetUnconfirmed;

/// Step 8: the phone's BLE link to the gateway dropped (not a PTU failure).
String get phoneLinkLostText => L10n.current.protocol_phoneLinkLost;

/// 09-28 (GC 刪除 56/1, then the same gateway configured again): 確認上線
/// found the station archived in the back office — its heartbeats are not
/// recorded, so they would never arrive. The first sentence is the
/// checklist item's reason ([checklistReason]).
String get identityArchivedText => L10n.current.protocol_identityArchived;

/// Step 9 stopped: the backend stayed unavailable (5xx / unreachable /
/// timeout) through the automatic retries (round 13).
String get backendUnavailableText => L10n.current.protocol_backendUnavailable;

/// Reconnecting the phone to the gateway did not succeed in time.
String get reconnectFailedText => L10n.current.protocol_reconnectFailed;

/// Phone could not open the BLE link (UniversalBleException, e.g. GATT 133).
String bleErrorText(String? detail) {
  final code = RegExp(r'^(\d{1,3}) ').firstMatch(detail ?? '')?.group(1);
  return code == null
      ? L10n.current.protocol_bleErrorNoCode
      : L10n.current.protocol_bleErrorCode(code);
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
