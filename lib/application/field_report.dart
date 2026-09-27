/// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §2, §5): the APP tells
/// the back office where the installer is (session reports on every step /
/// status change and a heartbeat) and what went wrong (a diagnostics package
/// on a failure, a timeout, a step stuck for 2 minutes, or 「請後台協助」),
/// queued on the phone while there is no network or no login.
///
/// v1.1 (user decision: the installer is already on the phone, a code to
/// read out on top is odd): no help code any more. The back office finds
/// the session by site / gateway / the installer's name (`operator_name`,
/// the account the APP is logged in with); nothing is sent as `short_code`.
///
/// Nothing here may disturb the commissioning itself: every entry point
/// swallows its own errors, never touches [CommissionState], and never
/// sends a BLE command (the gateway runs one command at a time).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/assign_progress.dart';
import '../core/direct_mode.dart';
import '../core/gateway_identity.dart';
import '../core/gateway_net.dart';
import '../core/mqtt_target.dart';
import '../core/protocol.dart';
import '../core/rescue_code.dart';
import '../data/contracts.dart';
import '../data/network_watch.dart';
import 'backend_environment.dart';
import 'commissioning_controller.dart';
import 'field_journal.dart';
import 'install_report.dart';
import 'network_check.dart';

// ---- Build info (no package_info dependency) ----

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');

/// §6.3 fault injection (`scan_timeout_once`), only in debug and
/// LOCAL_DEVELOPMENT builds.
const fieldFault = String.fromEnvironment('FIELD_FAULT');
bool _fieldFaultUsed = false;

/// True once per process for the first `scan_ble_discover` when the build
/// injects `FIELD_FAULT=scan_timeout_once`.
bool takeFieldFault(String op) {
  if (_fieldFaultUsed ||
      fieldFault != 'scan_timeout_once' ||
      op != 'scan_ble_discover' ||
      !(kDebugMode || localDevelopmentBuild)) {
    return false;
  }
  _fieldFaultUsed = true;
  return true;
}

// ---- Contract constants ----

const fieldSessionsPath = '/api/field/sessions';
const fieldDiagnosticsPath = '/api/field/diagnostics';
const fieldSchemaVersion = 1;

/// SharedPreferences key of the outbox (§2.8).
const fieldOutboxKey = 'field_outbox_v1';

/// SharedPreferences key of the running session's counters, written on
/// every report so a killed APP never reuses a `seq`.
const fieldLiveSessionKey = 'field_session_v1';

const sessionReportMaxBytes = 8 * 1024;
const diagnosticsMaxBytes = 64 * 1024;

/// The APP trims a diagnostics package above this (§2.4 大小預算).
const diagnosticsTrimBytes = 60 * 1024;

const outboxSessionEventLimit = 50;
const outboxDiagLimit = 5;
const outboxMaxBytes = 256 * 1024;
const outboxMaxAge = Duration(hours: 24);

/// Network error back-off (§2.8): 5 → 10 → 20 → 60 s.
const fieldBackoff = [
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 60),
];

/// A 404 (backend without these endpoints) stops reporting to that backend
/// for this long.
const fieldDisableAfter404 = Duration(hours: 1);

/// At most one diagnostics package per session in this window (help
/// excepted).
const diagThrottle = Duration(seconds: 10);

/// Reports per session per minute above which status events are merged.
const statusBurstLimit = 20;

/// Round 24: a gateway restart found at most this long after a failure
/// explains it ([FieldReporter.onGatewayReboot]).
const rebootAmendWindow = Duration(minutes: 3);

/// Round 24: the codes a gateway restart found afterwards re-classifies as
/// [RescueCode.gwRebooted] — what a restart looks like from the phone
/// before it reconnects (the link drops, commands time out or are refused
/// while the gateway starts, monitoring cannot be confirmed).
const rebootExplainedCodes = {
  RescueCode.bleLinkDrop,
  RescueCode.bleReconnectFail,
  RescueCode.cmdTimeout,
  RescueCode.monitorUnconfirmed,
  RescueCode.gwBusy,
};

/// Timers of the reporter; injectable in tests.
class FieldReporterConfig {
  const FieldReporterConfig({
    this.heartbeat = const Duration(seconds: 60),
    this.stuckAfter = const Duration(seconds: 120),
    this.stuckAfterSlow = const Duration(seconds: 240),
    this.retryEvery = const Duration(seconds: 30),
    this.helpWait = const Duration(seconds: 20),
    this.allowDemoLink = false,
    this.now,
    this.phoneInfo,
    this.random,
    this.networkEvents,
  });

  /// Round 24: the phone's network changes ([phoneNetworkEvents] when
  /// null); a network coming back sends the outbox at once
  /// ([FieldReporter.onNetworkBack]).
  final Stream<String> Function()? networkEvents;

  final Duration heartbeat, stuckAfter, retryEvery;

  /// Steps 8 and 9 (assigning, data verification) take minutes by
  /// themselves: stuck only after this (§8 decision 5, as the backend's
  /// FIELD_STUCK_SECONDS_STEP8 / _STEP9).
  final Duration stuckAfterSlow;

  /// The stuck time of the displayed [step].
  Duration stuckFor(int step) =>
      step == 8 || step == 9 ? stuckAfterSlow : stuckAfter;

  /// The help sheet shows 「送不出去」 when the upload has not finished
  /// within this (it goes on in the background).
  final Duration helpWait;

  /// Tests drive the flow with the demo gateway: report anyway.
  final bool allowDemoLink;
  final DateTime Function()? now;
  final Future<Map<String, dynamic>> Function()? phoneInfo;
  final Random? random;
}

final fieldReporterConfigProvider = Provider<FieldReporterConfig>(
  (ref) => const FieldReporterConfig(),
);

// ---- Small helpers ----

String? _cut(Object? value, int limit) {
  if (value == null) return null;
  final text = value.toString();
  if (text.isEmpty) return null;
  return text.length > limit ? '${text.substring(0, limit - 1)}…' : text;
}

int? _inRange(Object? value, int lo, int hi) {
  if (value is! num || value != value.roundToDouble()) return null;
  final v = value.toInt();
  return v >= lo && v <= hi ? v : null;
}

int _jsonBytes(Object? value) => utf8.encode(jsonEncode(value)).length;

/// ISO 8601 with milliseconds and the phone's UTC offset
/// (`2026-09-26T14:03:10.412+08:00`).
String isoWithOffset(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final offset = t.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}'
      '${offset.isNegative ? '-' : '+'}${two(minutes ~/ 60)}:${two(minutes % 60)}';
}

/// `scheme://host:port` of [base] (never user info), or null.
String? originOf(String? base) {
  final uri = Uri.tryParse((base ?? '').trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  try {
    return _cut(uri.origin, 128);
  } catch (_) {
    return null;
  }
}

/// 32 lower-case hex characters (16 random bytes).
String newSessionId(Random random) => [
  for (var i = 0; i < 16; i++)
    random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

// ---- What the controller hands over ----

/// The commissioning as the reporter sees it (built by the controller on
/// demand; pure data).
class FieldInput {
  const FieldInput({
    required this.state,
    required this.env,
    this.directMode = false,
    this.targetCount = 5,
    this.loggedIn = false,
  });

  final CommissionState state;
  final BackendEnvState env;

  /// Topology setting is 直連.
  final bool directMode;

  /// PTUs this gateway should get (star count, or 1 in direct mode).
  final int targetCount;
  final bool loggedIn;
}

/// 1-based step on screen (「第 N 步」).
int fieldStep(FieldInput i) =>
    (displayStep(i.state, i.env) + 1).clamp(1, stepLabels.length);

/// The network check page (steps 3–5) is showing.
bool inNetworkCheck(CommissionState s) =>
    (s.step == 2 && !s.checkPassed) || s.step == 3;

/// The network check shows a ✗ line.
bool networkCheckFailed(FieldInput i) {
  if (!inNetworkCheck(i.state)) return false;
  final check = networkCheck(state: i.state, env: i.env);
  return [check.wifi, check.target, check.upload].any((l) => l.mark == '✗');
}

/// §3.1 「沒有紅框、但要回報的情況」 (STEP_STUCK / HELP_ONLY are the
/// reporter's own).
RescueCode? sessionRescueCode(FieldInput i) {
  final s = i.state;
  if (s.step == 1 &&
      !s.busy &&
      s.peers.isEmpty &&
      s.message.startsWith('未找到閘道器')) {
    return RescueCode.gwNotFound;
  }
  if (inNetworkCheck(s)) {
    if (s.uploadWatch == UploadWatch.linkLost) return RescueCode.bleLinkDrop;
    final check = networkCheck(state: s, env: i.env);
    if (check.wifiProblem) return wifiRescueCode(wifiDiscReasonOf(s.net));
    if (!check.targetOk) return RescueCode.uploadTarget;
    if (s.uploadLate || s.uploadWatch == UploadWatch.gaveUp) {
      return RescueCode.uploadNotStarted;
    }
  }
  if (s.step == 4 &&
      !i.directMode &&
      (s.resetFailed.isNotEmpty || s.pendingNext > 0)) {
    return RescueCode.ptuResidual;
  }
  if (s.step == 5 && s.assignFailed.isNotEmpty) {
    return ptuAssignRescueCode(s.assignFailed.values.first);
  }
  // Round 28 (field round 28: 〔請後台協助〕 at 「找不到夠近的 PTU」 reached the
  // back office as STEP_STUCK with no text): the direct step 7 settled
  // without this pile's PTU — the rescue page's 直連選台 card.
  if (s.step == 4 && i.directMode && !s.busy && !s.relinking) {
    final direct = s.direct;
    if (direct != null &&
        direct.pickedMac == null &&
        (direct.state == DirectState.noCandidate ||
            direct.state == DirectState.boundMissing)) {
      return RescueCode.directPick;
    }
  }
  return null;
}

/// §2.2 status (abandoned is only sent when a session ends). [quiet]: the
/// red box is the installer's own cancel (rule 27), not a failure.
String sessionStatusOf(FieldInput i, {bool help = false, bool quiet = false}) {
  final s = i.state;
  // Round 28: 〔先完成配置〕 ends the run too.
  if (s.step == 7 && (s.verified || s.ptuDeferred)) return 'completed';
  if (help) return 'help';
  if ((s.error != null && !quiet) ||
      (s.step == 5 && s.assignFailed.isNotEmpty) ||
      networkCheckFailed(i)) {
    return 'failed';
  }
  return s.busy ? 'running' : 'idle';
}

/// Site / gateway / MAC / name / firmware / mode / target count, `null`
/// when unknown or outside the contract's range.
Map<String, dynamic> fieldIdentity(FieldInput i) {
  final s = i.state;
  final c = s.config;
  return {
    'site_id': _inRange(c['site_id'], 1, 65535),
    'gateway_id': _inRange(c['gateway_id'], 1, 50),
    'gateway_mac': _cut(c['gateway_uid'], 32),
    'gateway_name': _cut(s.peer?.name, 32),
    'fw_version': _cut(c['fw_version'], 16),
    'mode': i.directMode ? 'direct' : 'star',
    'target_ptu_count': _inRange(i.targetCount, 1, 5),
  };
}

Map<String, dynamic> fieldProgress(FieldInput i) {
  final s = i.state;
  final total = s.selected.isNotEmpty ? s.selected.length : i.targetCount;
  final done = s.step == 6
      ? s.verifyCounts.values.where((n) => n >= 3).length
      : s.assignedOk.where(s.selected.contains).length;
  return {'done': done, 'total': total};
}

/// §2.3 body. [secrets] are masked wherever they show. v1.1: no
/// `short_code`; [operatorName] (the logged-in account, at most 64
/// characters) as `operator_name`, null when unknown.
Map<String, dynamic> buildSessionReport({
  required String sessionId,
  required int seq,
  required String event,
  required DateTime now,
  required FieldInput input,
  required String status,
  RescueCode? code,
  GatewayFailure? failure,
  Map<String, dynamic> app = const {},
  Map<String, dynamic> phone = const {},
  Map<String, dynamic>? lastCommand,
  Iterable<String> secrets = const [],
  String? errorMessage,
  String? operatorName,
}) {
  final s = input.state;
  final step = fieldStep(input);
  final body = <String, dynamic>{
    'schema': fieldSchemaVersion,
    'session_id': sessionId,
    'operator_name': operatorNameOf(operatorName),
    'seq': seq,
    'event': event,
    'client_ts': isoWithOffset(now),
    'queued_ms': 0,
    'app': app,
    'phone': phone,
    ...fieldIdentity(input),
    'step': step,
    'step_label': _cut(stepLabels[step - 1], 32),
    'ctl_step': s.step.clamp(0, 7),
    'status': status,
    'busy_label': s.busy ? _cut(s.message, 120) : null,
    'error_code': code?.wire,
    'fail_code': _cut(failure?.code, 48),
    // Round 28 (field round 28: 「（APP 沒有提供錯誤文字）」 for a pile
    // without its PTU): the step 7 line the installer reads.
    'error_message': _cut(
      errorMessage ??
          s.error ??
          (code == RescueCode.directPick && s.step == 4 ? s.message : null),
      500,
    ),
    'progress': fieldProgress(input),
    'last_command': lastCommand,
  };
  final masked = Map<String, dynamic>.from(
    scrubSecrets(redactKeys(body), secrets) as Map,
  );
  if (_jsonBytes(masked) > sessionReportMaxBytes) {
    masked['error_message'] = _cut(masked['error_message'], 120);
    masked['busy_label'] = _cut(masked['busy_label'], 60);
    masked['last_command'] = null;
  }
  return masked;
}

/// get_config fields kept in `gateway.config` (§2.4).
const gatewayConfigKeys = [
  'fw_version',
  'site_id',
  'gateway_id',
  'gateway_uid',
  'fleet_joined',
  'ble_enabled',
  'upload_paused',
  'max_connections',
  'otp_enabled',
  'identify_supported',
  'identify_ptu_supported',
  'direct_autoconnect_supported',
  'mqtt_target',
  'mqtt_host',
  'mqtt_port',
  'mqtt_connected',
  'boot_count',
];

String _assignOf(CommissionState s, String mac) {
  if (s.results[mac]?.contains('待回讀確認') == true) return 'pending_readback';
  final a = s.assignStatus[mac];
  if (a != null) {
    return switch (a.phase) {
      AssignPhase.waiting => 'waiting',
      AssignPhase.assigning => 'running',
      AssignPhase.linkRetry || AssignPhase.retry || AssignPhase.busy => 'retry',
      AssignPhase.done => 'done',
      AssignPhase.failed => 'failed',
    };
  }
  if (s.assignFailed.containsKey(mac)) return 'failed';
  if (s.assignedOk.contains(mac)) return 'done';
  return 'none';
}

/// The `gateway`, `ptus`, `ptu_summary`, `phone_link` and `verify` blocks,
/// from what the APP already read (never a new command).
Map<String, dynamic> diagnosticSections(
  CommissionState s, {
  required DateTime now,
  List<String> connectLog = const [],
  String? firstConnectFailure,
  bool? signalConnected,
  DateTime? netReadAt,
}) {
  final reason = wifiDiscReasonOf(s.net);
  final rssi = s.net['rssi'];
  final prov = s.net['prov_fail_reason'] ?? s.config['prov_fail_reason'];
  final reboot = s.gatewayReboot;
  return {
    'gateway': {
      'config': {
        for (final k in gatewayConfigKeys)
          if (s.config.containsKey(k)) k: s.config[k],
      },
      'net': {
        for (final k in [...gatewayNetKeys, ...mqttStatusKeys])
          if (s.net.containsKey(k)) k: s.net[k],
      },
      'net_read_age_s': netReadAt == null
          ? null
          : now.difference(netReadAt).inSeconds.clamp(0, 1 << 30),
      'reboot': reboot == null
          ? null
          : {'from': reboot.from, 'to': reboot.to, 'reason': reboot.reason},
      'wifi': {
        'verdict': s.wifi.name,
        'fail_kind': wifiFailKindOf(reason)?.name,
        'reason': reason,
        'prov_fail_reason': prov is num ? prov.toInt() : null,
        'rssi': rssi is num ? rssi.toInt() : null,
        'weak': isWeakWifiRssi(rssi),
      },
    },
    'ptus': [
      for (final p in s.ptus.take(12))
        {
          'mac': p['mac']?.toString() ?? '',
          'rssi': p['rssi'] is num ? (p['rssi'] as num).toInt() : null,
          'connected': p['connected'] is bool ? p['connected'] as bool : null,
          'device_number': p['device_number'] is num
              ? (p['device_number'] as num).toInt()
              : null,
          'selected': s.selected.contains(p['mac']?.toString()),
          'assign': _assignOf(s, p['mac']?.toString() ?? ''),
          'fail_text': _cut(
            s.assignFailed[p['mac']?.toString()] ??
                (s.resetFailed.contains(p['mac']?.toString())
                    ? resetFailedText
                    : null),
            120,
          ),
        },
    ],
    'ptu_summary': {
      'scanned': s.scannedTotal,
      'selected': s.selected.length,
      'assigned_ok': s.assignedOk.length,
      'failed': s.assignFailed.length,
      'owned_elsewhere': s.pendingNext,
      'reset_failed': s.resetFailed.length,
    },
    'phone_link': {
      'connected': signalConnected,
      'first_connect_failure': _cut(firstConnectFailure, 200),
      'connect_log': [
        for (final line in connectLog.skip(max(0, connectLog.length - 10)))
          _cut(line, 120) ?? '',
      ],
    },
    'verify': s.step == 6
        ? {
            'counts': {
              for (final e in s.verifyCounts.entries) '${e.key}': e.value,
            },
            'waiting': s.verifyWaiting.toList()..sort(),
            'skipped': s.verifySkipped.toList()..sort(),
          }
        : null,
  };
}

/// A failure the reporter classified, and the red box it produced.
class FieldFailure {
  const FieldFailure({
    this.code,
    this.failure,
    this.rebooted = false,
    this.safe,
    this.runLabel,
    this.errorText,
    this.at,
    this.note,
  });

  /// Round 24: when it was classified.
  final DateTime? at;

  /// Round 24: the text for the package's `error.message` when no red box
  /// is on screen any more (the restart notice of [FieldReporter.
  /// onGatewayReboot]).
  final String? note;

  /// Null: the installer cancelled (rule 27) — nothing to report.
  final RescueCode? code;
  final GatewayFailure? failure;
  final bool rebooted;
  final bool? safe;
  final String? runLabel;

  /// `state.error` right after the failure (the failure applies while the
  /// same text is on screen).
  final String? errorText;
}

/// §2.4 body: masked (§2.5, whole package) and trimmed (§2.4 大小預算).
/// v1.1: no `short_code`; [operatorName] as `context.operator_name`.
Map<String, dynamic> buildDiagnostics({
  required String sessionId,
  required int diagSeq,
  required String trigger,
  required DateTime now,
  required FieldInput input,
  required RescueCode code,
  FieldFailure? failure,
  List<Map<String, dynamic>> commands = const [],
  Map<String, dynamic> sections = const {},
  Map<String, dynamic> app = const {},
  Map<String, dynamic> phone = const {},
  Iterable<String> secrets = const [],
  String? operatorName,
}) {
  final s = input.state;
  final step = fieldStep(input);
  final f = failure?.failure;
  final identity = fieldIdentity(input);
  final body = <String, dynamic>{
    'schema': fieldSchemaVersion,
    'session_id': sessionId,
    'diag_seq': diagSeq,
    'trigger': trigger,
    'client_ts': isoWithOffset(now),
    'queued_ms': 0,
    'step': step,
    'step_label': stepLabels[step - 1],
    'ctl_step': s.step,
    'busy': s.busy,
    'run_label': _cut(failure?.runLabel ?? (s.busy ? s.message : null), 120),
    'error': {
      'code': code.wire,
      'fail_code': _cut(f?.code, 48),
      'from_gateway': f?.fromGateway ?? false,
      'http_status': f?.status,
      'endpoint': _cut(f?.endpoint?.split('?').first, 96),
      'message': _cut(s.error ?? failure?.note, 500),
      'detail': _cut(s.errorDetail, 2000),
      'rebooted': failure?.rebooted ?? false,
      'safe_stop': failure?.safe,
    },
    'context': {
      for (final k in const [
        'site_id',
        'gateway_id',
        'gateway_mac',
        'gateway_name',
        'mode',
        'target_ptu_count',
      ])
        k: identity[k],
      'offline': s.offline,
      'logged_in': input.loggedIn,
      'operator_name': operatorNameOf(operatorName),
      'app': app,
      'phone': phone,
    },
    'commands': commands
        .skip(max(0, commands.length - journalCapacity))
        .toList(),
    for (final k in const [
      'gateway',
      'ptus',
      'ptu_summary',
      'phone_link',
      'verify',
    ])
      if (sections.containsKey(k)) k: sections[k],
  };
  final masked = Map<String, dynamic>.from(
    scrubSecrets(redactKeys(body), secrets) as Map,
  );
  return fitDiagnostics(masked);
}

/// Trims [d] below [diagnosticsTrimBytes] in the §2.4 order: command
/// results to 120 characters, the last 15 commands, `error.detail` to 500;
/// then (never expected) whatever else is large.
Map<String, dynamic> fitDiagnostics(Map<String, dynamic> d) {
  if (_jsonBytes(d) <= diagnosticsTrimBytes) return d;
  final out = Map<String, dynamic>.from(d);
  List<Map<String, dynamic>> commands() => [
    for (final c in (out['commands'] as List? ?? const []))
      Map<String, dynamic>.from(c as Map),
  ];
  out['commands'] = [
    for (final c in commands()) {...c, 'result': _cut(c['result'], 120)},
  ];
  if (_jsonBytes(out) <= diagnosticsTrimBytes) return out;
  final list = commands();
  out['commands'] = list.skip(max(0, list.length - 15)).toList();
  if (_jsonBytes(out) <= diagnosticsTrimBytes) return out;
  final error = Map<String, dynamic>.from(out['error'] as Map? ?? const {});
  error['detail'] = _cut(error['detail'], 500);
  out['error'] = error;
  if (_jsonBytes(out) <= diagnosticsTrimBytes) return out;
  final rest = commands();
  out['commands'] = [
    for (final c in rest.skip(max(0, rest.length - 5)))
      {
        ...c,
        'params': const <String, dynamic>{},
        'result': _cut(c['result'], 60),
      },
  ];
  out['ptus'] = [
    for (final p in (out['ptus'] as List? ?? const []))
      {...Map<String, dynamic>.from(p as Map), 'fail_text': null},
  ];
  final link = out['phone_link'];
  if (link is Map) out['phone_link'] = {...link, 'connect_log': const []};
  return out;
}

/// 「請唸給後台」 lines of the help sheet (shown whether or not the upload
/// worked).
///
/// Round 24 (field round 24: 「狀況代碼：HELP_ONLY」 on the sheet): the
/// code is said in words ([RescueCode.label]); [errorCode] (its wire name)
/// only shows in the sheet's details ([fieldHelpDetailLines]).
List<String> fieldHelpLines(FieldInput i, {String? errorCode}) {
  final s = i.state;
  final id = fieldIdentity(i);
  final site = id['site_id'], gw = id['gateway_id'];
  // Round 28: the Wi-Fi MAC (as the back office shows it) — read, else
  // derived from the Bluetooth MAC; the same tail as the gateway list.
  final wifi = gatewayWifiMac(uid: s.config['gateway_uid'], bleId: s.peer?.id);
  final tail = wifi?.substring(8);
  final lines = <String>[];
  if (s.peer != null && site != null && gw != null) {
    lines.add('站 $site / 閘道器 $gw${tail == null ? '' : '（MAC 後 4 碼 $tail）'}');
  } else if (s.peer != null) {
    lines.add('閘道器 ${s.peer!.name}${tail == null ? '' : '（MAC 後 4 碼 $tail）'}');
  } else {
    lines.add('還沒連上閘道器');
  }
  final step = fieldStep(i);
  lines.add('目前第 $step 步：${stepLabels[step - 1]}');
  final code = RescueCode.ofWire(errorCode);
  if (s.error != null) {
    lines.add('錯誤：${s.error!.split('\n').first}');
  } else if (code != null) {
    lines.add('狀況：${code.label}');
  }
  if (s.peer != null) {
    final fw = id['fw_version'] ?? '未知';
    lines.add('韌體 $fw · ${i.directMode ? '直連' : '星狀 ${i.targetCount} 台'}');
  }
  return lines;
}

/// Round 24: the help sheet's 「詳細資訊」 — the code's wire name for the
/// back office (read out when the upload did not go through); empty
/// without one.
List<String> fieldHelpDetailLines({String? errorCode}) => [
  if (errorCode != null && errorCode.isNotEmpty) '狀況代碼：$errorCode',
];

// ---- Session and outbox ----

/// One commissioning of one gateway (§2.2).
class FieldSession {
  FieldSession({
    required this.id,
    required this.createdMs,
    this.seq = 0,
    this.diagSeq = 0,
  });

  final String id;
  final int createdMs;
  int seq, diagSeq;

  /// Runtime only: the step last entered and when.
  int? step;
  DateTime? stepEnteredAt;
  bool diagSentThisStep = false;

  /// STEP_STUCK for the current step.
  bool stuck = false;

  /// 求助 pressed at [step] while [base] was the code: status stays `help`
  /// until either changes.
  ({int step, RescueCode? base})? help;

  Map<String, dynamic> toJson() => {
    'id': id,
    'seq': seq,
    'diag_seq': diagSeq,
    'created_ms': createdMs,
  };

  static final _id = RegExp(r'^[0-9a-f]{32}$');

  /// A session saved by v1 still carries its help code (`code`): ignored.
  static FieldSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || !_id.hasMatch(id)) return null;
    final seq = raw['seq'], diag = raw['diag_seq'], created = raw['created_ms'];
    return FieldSession(
      id: id,
      seq: seq is int && seq >= 0 ? seq : 0,
      diagSeq: diag is int && diag >= 0 ? diag : 0,
      createdMs: created is int ? created : 0,
    );
  }
}

/// One queued upload (§2.8 `{kind, body, created_ms, tries}`; [origin]
/// keeps it on the backend it was made for).
class OutboxItem {
  OutboxItem({
    required this.kind,
    required this.body,
    required this.createdMs,
    this.tries = 0,
    this.origin,
    this.transient = false,
  }) : bytes = _jsonBytes(body);

  /// `session`, `diag` or `install` (09-28: the install report).
  final String kind;
  Map<String, dynamic> body;
  final int createdMs;
  int tries;
  final String? origin;

  /// A heartbeat: sent once, never queued or saved.
  final bool transient;
  final int bytes;

  String get path => switch (kind) {
    'diag' => fieldDiagnosticsPath,
    'install' => installReportsPath,
    _ => fieldSessionsPath,
  };
  String? get sessionId => body['session_id'] as String?;
  String? get event => body['event'] as String?;
  String? get trigger => body['trigger'] as String?;
  bool get isHelp => event == 'help' || trigger == 'help';

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'body': body,
    'created_ms': createdMs,
    'tries': tries,
    if (origin != null) 'origin': origin,
  };

  static OutboxItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'], body = raw['body'], created = raw['created_ms'];
    if ((kind != 'session' && kind != 'diag' && kind != 'install') ||
        body is! Map ||
        created is! int) {
      return null;
    }
    return OutboxItem(
      kind: kind as String,
      body: Map<String, dynamic>.from(body),
      createdMs: created,
      tries: raw['tries'] is int ? raw['tries'] as int : 0,
      origin: raw['origin'] as String?,
    );
  }
}

/// §2.8 caps, applied whenever the outbox changes: 24 h expiry, 50 events
/// per session (status events go first), 5 packages (help kept longest),
/// 256 KiB in all. 09-28: install reports expire after
/// [installReportMaxAge], at most [outboxInstallLimit] of them, and are the
/// last to go when the outbox is too big.
void pruneOutbox(List<OutboxItem> items, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  items.removeWhere(
    (i) =>
        nowMs - i.createdMs >
        (i.kind == 'install' ? installReportMaxAge : outboxMaxAge)
            .inMilliseconds,
  );
  while (items.where((i) => i.kind == 'install').length > outboxInstallLimit) {
    items.remove(items.firstWhere((i) => i.kind == 'install'));
  }
  final sessions = {
    for (final i in items)
      if (i.kind == 'session') i.sessionId,
  };
  for (final id in sessions) {
    bool mine(OutboxItem i) => i.kind == 'session' && i.sessionId == id;
    while (items.where(mine).length > outboxSessionEventLimit) {
      final drop = items.where(
        (i) => mine(i) && (i.event == 'status' || i.event == 'heartbeat'),
      );
      if (drop.isEmpty) break;
      items.remove(drop.first);
    }
  }
  while (items.where((i) => i.kind == 'diag').length > outboxDiagLimit) {
    final diags = items.where((i) => i.kind == 'diag');
    final plain = diags.where((i) => !i.isHelp);
    items.remove(plain.isNotEmpty ? plain.first : diags.first);
  }
  int size() => items.fold(0, (sum, i) => sum + i.bytes);
  while (items.isNotEmpty && size() > outboxMaxBytes) {
    final plainDiag = items.where((i) => i.kind == 'diag' && !i.isHelp);
    final status = items.where((i) => i.event == 'status');
    final other = items.where((i) => i.kind != 'install');
    items.remove(
      plainDiag.isNotEmpty
          ? plainDiag.first
          : status.isNotEmpty
          ? status.first
          : other.isNotEmpty
          ? other.first
          : items.first,
    );
  }
}

// ---- Help sheet state ----

enum FieldHelpPhase {
  /// Nothing asked yet.
  idle,

  /// Uploading the help report and package.
  sending,

  /// The back office has them.
  sent,

  /// Queued on the phone (no network / not logged in).
  queued,

  /// The backend has no rescue endpoints yet (404).
  unsupported,

  /// Demo mode: nothing is sent.
  disabled,
}

class FieldHelpState {
  const FieldHelpState({
    this.phase = FieldHelpPhase.idle,
    this.reason = '',
    this.errorCode,
  });

  final FieldHelpPhase phase;

  /// Why it is queued (「尚未登入後台」…).
  final String reason;

  /// The code sent with the help report (shown with the error line).
  final String? errorCode;

  FieldHelpState copyWith({
    FieldHelpPhase? phase,
    String? reason,
    Object? errorCode = _keepValue,
  }) => FieldHelpState(
    phase: phase ?? this.phase,
    reason: reason ?? this.reason,
    errorCode: identical(errorCode, _keepValue)
        ? this.errorCode
        : errorCode as String?,
  );
}

const _keepValue = Object();

class FieldHelpNotifier extends Notifier<FieldHelpState> {
  @override
  FieldHelpState build() => const FieldHelpState();
  void set(FieldHelpState value) => state = value;
}

final fieldHelpProvider = NotifierProvider<FieldHelpNotifier, FieldHelpState>(
  FieldHelpNotifier.new,
);

final fieldReporterProvider = Provider<FieldReporter>((ref) {
  final link = ref.watch(linkProvider);
  final config = ref.watch(fieldReporterConfigProvider);
  final reporter = FieldReporter(
    api: ref.watch(apiProvider),
    enabled: !link.demo || config.allowDemoLink,
    config: config,
    onHelp: (value) {
      if (!ref.mounted) return;
      try {
        ref.read(fieldHelpProvider.notifier).set(value);
      } catch (_) {}
    },
    onInstall: (value) {
      if (!ref.mounted) return;
      try {
        ref.read(installReportProvider.notifier).set(value);
      } catch (_) {}
    },
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});

/// `manufacturer model` / `Android x` / SDK of this phone (Android only;
/// read once).
Future<Map<String, dynamic>> defaultPhoneInfo() async {
  if (kIsWeb || !Platform.isAndroid) return const {};
  final info = await DeviceInfoPlugin().androidInfo;
  return {
    'model': _cut('${info.manufacturer} ${info.model}', 64),
    'os': _cut('Android ${info.version.release}', 32),
    'sdk': info.version.sdkInt,
  };
}

Random _secureRandom() {
  try {
    return Random.secure();
  } catch (_) {
    return Random();
  }
}

class _Reported {
  const _Reported(this.step, this.status, this.code);
  final int step;
  final String status;
  final String? code;
}

// ---- The reporter ----

/// Builds, queues and sends the session reports and diagnostics packages.
/// Every public method is safe to call at any time: it never throws and
/// never waits on the network unless it says so (`Future`s).
class FieldReporter {
  FieldReporter({
    required this._api,
    required this._enabled,
    FieldReporterConfig config = const FieldReporterConfig(),
    this._onHelp,
    this._onInstall,
  }) : _config = config,
       _now = config.now ?? DateTime.now,
       _random = config.random ?? _secureRandom(),
       journal = CommandJournal(now: config.now) {
    _loaded = _enabled ? _load() : Future<void>.value();
    if (_enabled) {
      unawaited(_loadPhone());
      try {
        _networkSub = (config.networkEvents ?? phoneNetworkEvents)().listen((
          event,
        ) {
          if (isNetworkBackEvent(event)) onNetworkBack();
        }, onError: (Object _) {});
      } catch (_) {}
    }
  }

  /// Round 24: [FieldReporterConfig.networkEvents].
  StreamSubscription<String>? _networkSub;

  final GatewayApi _api;
  final bool _enabled;
  final FieldReporterConfig _config;
  final void Function(FieldHelpState)? _onHelp;
  final void Function(InstallReportStatus)? _onInstall;
  final DateTime Function() _now;
  final Random _random;

  /// Commands for the diagnostics package (kept even when disabled; cheap).
  final CommandJournal journal;

  late final Future<void> _loaded;
  bool _loadDone = false;
  final List<OutboxItem> _items = [], _early = [];

  FieldInput? Function()? _input;
  Map<String, dynamic> Function()? _sections;

  FieldSession? _session;
  _Reported? _last;
  bool _lastBusy = false, _checkFailed = false, _assignFailed = false;
  FieldFailure? _failure;
  FieldHelpState _help = const FieldHelpState();

  /// 09-28: the install report of the done page on screen ([_installId]
  /// is its `report_id`, [_installBody] kept for 〔重送〕 after a refusal,
  /// [_installText] the report text it was made from — the same completion
  /// is sent once).
  InstallReportStatus _install = const InstallReportStatus();
  String? _installId, _installText;
  Map<String, dynamic>? _installBody;
  Map<String, dynamic> _phone = const {};
  String? _lastOrigin;

  final Map<String, DateTime> _disabledUntil = {};
  DateTime? _backoffUntil;
  int _backoffStep = 0;
  final List<DateTime> _recent = [];
  DateTime? _lastDiagAt;
  (String, RescueCode, FieldFailure?)? _pendingDiag;

  /// Round 24: boot_count of the last restart [onGatewayReboot] handled.
  int? _rebootSeen;

  Timer? _heartbeatTimer, _retryTimer, _stuckTimer, _throttleTimer;
  Timer? _diagTimer, _wakeTimer;
  bool _foreground = true, _disposed = false, _evalScheduled = false;
  Future<void>? _draining;
  bool _drainAgain = false;

  bool get enabled => _enabled;
  FieldSession? get session => _session;
  FieldHelpState get help => _help;
  InstallReportStatus get install => _install;

  /// Queued uploads (oldest first); for tests and the help sheet.
  List<OutboxItem> get outbox => List.unmodifiable(_items);

  /// The outbox saved by an earlier run has been read.
  Future<void> get ready => _loaded;

  void _guard(void Function() action) {
    try {
      action();
    } catch (error) {
      debugPrint('FIELD reporter error: $error');
    }
  }

  /// The controller supplies the current commissioning ([input]) and the
  /// gateway / PTU / phone-link blocks of a package ([sections]).
  void attach({
    required FieldInput? Function() input,
    Map<String, dynamic> Function()? sections,
  }) {
    _input = input;
    _sections = sections;
  }

  /// The controller is gone: stop the timers that read it.
  void detach() {
    _input = null;
    _sections = null;
    _heartbeatTimer?.cancel();
    _stuckTimer?.cancel();
    _throttleTimer?.cancel();
    _diagTimer?.cancel();
    _heartbeatTimer = _stuckTimer = _throttleTimer = _diagTimer = null;
  }

  void dispose() {
    _disposed = true;
    detach();
    _retryTimer?.cancel();
    _wakeTimer?.cancel();
    _retryTimer = _wakeTimer = null;
    unawaited(_networkSub?.cancel());
    _networkSub = null;
  }

  FieldInput? _read() {
    try {
      return _input?.call();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPhone() async {
    try {
      _phone = await (_config.phoneInfo ?? defaultPhoneInfo)().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {}
  }

  Map<String, dynamic> _app(FieldInput i) => {
    'version': _cut(appVersion, 32),
    'build': _cut(appBuild, 40),
    'env': i.env.environment.name,
    'backend_origin': _originFor(i),
  };

  String? _apiOrigin() {
    final api = _api;
    return api is SessionInfo ? (api as SessionInfo).origin : null;
  }

  /// v1.1 `operator_name`: the account the APP is logged in with.
  String? _operator() {
    final api = _api;
    if (api is! OperatorInfo) return null;
    try {
      return (api as OperatorInfo).operatorName;
    } catch (_) {
      return null;
    }
  }

  String? _originFor(FieldInput i) {
    final origin = _apiOrigin() ?? originOf(i.env.base);
    if (origin != null) _lastOrigin = origin;
    return origin;
  }

  String get _originKey => _apiOrigin() ?? _lastOrigin ?? '';

  void _setHelp(FieldHelpState value) {
    _help = value;
    _onHelp?.call(value);
  }

  void _setInstall(InstallReportStatus value) {
    _install = value;
    _onInstall?.call(value);
  }

  // ---- persistence ----

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(fieldOutboxKey);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final entry in list) {
            final item = OutboxItem.fromJson(entry);
            if (item != null) _items.add(item);
          }
        }
      }
    } catch (_) {}
    _loadDone = true;
    _items.addAll(_early);
    _early.clear();
    pruneOutbox(_items, _now());
    // 09-28: an install report left from before the APP was closed is still
    // on its way; the done page (if shown again) says so.
    final install = _items.where((i) => i.kind == 'install').lastOrNull;
    if (install != null && _installId == null) {
      _installId = install.body['report_id'] as String?;
      _installBody = install.body;
      _installText = install.body['report_text'] as String?;
      _setInstall(
        InstallReportStatus(
          phase: InstallReportPhase.queued,
          reportId: _installId,
        ),
      );
    }
    if (_items.isNotEmpty) _ensureRetryTimer();
  }

  void _persist() {
    if (!_loadDone || _disposed) return;
    final saved = [
      for (final i in _items)
        if (!i.transient) i.toJson(),
    ];
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(fieldOutboxKey, jsonEncode(saved));
      } catch (_) {}
    }());
  }

  void _saveLive() {
    final json = _session?.toJson();
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (json == null) {
          await prefs.remove(fieldLiveSessionKey);
        } else {
          await prefs.setString(fieldLiveSessionKey, jsonEncode(json));
        }
      } catch (_) {}
    }());
  }

  // ---- session lifecycle ----

  FieldSession _startSession() {
    final session = FieldSession(
      id: newSessionId(_random),
      createdMs: _now().millisecondsSinceEpoch,
    );
    _open(session);
    return session;
  }

  void _open(FieldSession session) {
    _session = session;
    _last = null;
    _rebootSeen = null;
    _lastBusy = false;
    _checkFailed = false;
    _assignFailed = false;
    _recent.clear();
    _startHeartbeat();
    _saveLive();
    _setHelp(const FieldHelpState());
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_session == null || !_foreground || _disposed) return;
    _heartbeatTimer = Timer.periodic(_config.heartbeat, (_) => heartbeat());
  }

  void _enterStep(FieldSession session, int step) {
    session.step = step;
    session.stepEnteredAt = _now();
    session.diagSentThisStep = false;
    session.stuck = false;
    _checkFailed = false;
    _stuckTimer?.cancel();
    _stuckTimer = Timer(_config.stuckFor(step), checkStuck);
  }

  /// The running session for the progress file (null when none).
  Map<String, dynamic>? persisted() => _enabled ? _session?.toJson() : null;

  /// 「重新連線並繼續」 after the APP was killed: the same session as
  /// before; its counters continue past anything already sent.
  Future<void> restore(Object? raw) async {
    if (!_enabled) return;
    try {
      final saved = FieldSession.fromJson(raw);
      if (saved == null || _session != null) return;
      final age = _now().millisecondsSinceEpoch - saved.createdMs;
      if (age > outboxMaxAge.inMilliseconds) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final live = prefs.getString(fieldLiveSessionKey);
        final other = live == null
            ? null
            : FieldSession.fromJson(jsonDecode(live));
        if (other != null && other.id == saved.id) {
          saved.seq = max(saved.seq, other.seq);
          saved.diagSeq = max(saved.diagSeq, other.diagSeq);
        }
      } catch (_) {}
      if (_session != null || _disposed) return;
      _open(saved);
      onState();
    } catch (_) {}
  }

  /// The session ended: `completed` (step 10 verified) or `abandoned`
  /// (cancel / 重新開始).
  void end(String status) => _guard(() {
    // 09-28: the done page's install report goes to the back office.
    if (status == 'completed') _queueInstallReport();
    final session = _session;
    if (!_enabled || session == null) return;
    final i = _read();
    if (i != null) {
      final step = fieldStep(i);
      final code = status == 'completed' ? null : _current(i, step).code;
      _report(session, 'end', i, status: status, code: code);
    }
    _session = null;
    _last = null;
    _failure = null;
    _pendingDiag = null;
    for (final t in [
      _heartbeatTimer,
      _stuckTimer,
      _throttleTimer,
      _diagTimer,
    ]) {
      t?.cancel();
    }
    _heartbeatTimer = _stuckTimer = _throttleTimer = _diagTimer = null;
    _saveLive();
    _setHelp(const FieldHelpState());
    unawaited(flush());
  });

  // ---- state changes ----

  /// The commissioning state changed; the report (if any) is decided once
  /// the current synchronous work is done (a failure is classified first).
  void onState() {
    if (!_enabled || _evalScheduled || _disposed) return;
    _evalScheduled = true;
    scheduleMicrotask(() {
      _evalScheduled = false;
      _guard(_evaluate);
    });
  }

  RescueCode? _baseCode(FieldInput i) {
    final s = i.state;
    final failure = _failure;
    if (s.error != null) {
      if (failure != null && failure.errorText == s.error) return failure.code;
      return sessionRescueCode(i) ?? RescueCode.appUnexpected;
    }
    final code = sessionRescueCode(i);
    if (code != null) return code;
    return _session?.stuck == true ? RescueCode.stepStuck : null;
  }

  ({RescueCode? code, bool help}) _current(FieldInput i, int step) {
    final base = _baseCode(i);
    final session = _session;
    final help = session?.help;
    if (session != null && help != null) {
      if (help.step == step && help.base == base) {
        return (code: base ?? RescueCode.helpOnly, help: true);
      }
      session.help = null;
    }
    return (code: base, help: false);
  }

  /// The red box on screen is a cancel (rule 27).
  bool _quiet(FieldInput i) {
    final failure = _failureFor(i);
    return failure != null && failure.code == null;
  }

  String _status(FieldInput i, bool help) =>
      sessionStatusOf(i, help: help, quiet: _quiet(i));

  FieldFailure? _failureFor(FieldInput i) {
    final failure = _failure;
    return failure != null &&
            i.state.error != null &&
            failure.errorText == i.state.error
        ? failure
        : null;
  }

  void _evaluate() {
    if (!_enabled || _disposed) return;
    final i = _read();
    if (i == null) return;
    final s = i.state;
    final step = fieldStep(i);
    final completed = s.step == 7 && (s.verified || s.ptuDeferred);
    var session = _session;
    if (session == null) {
      if (completed || s.step < 1 || step < 2) return;
      session = _startSession();
      // A new commissioning (not 〔請後台協助〕 on the done page): the last
      // done page's report status is not this one's (a report still queued
      // goes out on its own).
      _installId = null;
      _installBody = null;
      if (_install.phase != InstallReportPhase.idle) {
        _setInstall(const InstallReportStatus());
      }
    }
    if (completed) {
      end('completed');
      return;
    }
    if (session.step != step) _enterStep(session, step);
    final cur = _current(i, step);
    final status = _status(i, cur.help);
    final busyStarted = s.busy && !_lastBusy;
    _lastBusy = s.busy;

    // Packages without a red box: the network check's first ✗, a step 8
    // PTU that failed after its retries.
    final checkFailed = networkCheckFailed(i);
    if (checkFailed && !_checkFailed) {
      _diagnose('error', i, cur.code ?? RescueCode.appUnexpected);
    }
    _checkFailed = checkFailed;
    final assignFailed = s.step == 5 && s.assignFailed.isNotEmpty;
    if (assignFailed && !_assignFailed && s.error == null) {
      _diagnose(
        'error',
        i,
        cur.code ?? ptuAssignRescueCode(s.assignFailed.values.first),
      );
    }
    _assignFailed = assignFailed;

    final last = _last;
    String? event;
    if (last == null || last.step != step) {
      event = 'step';
    } else if (last.code != cur.code?.wire) {
      event = 'error';
    } else if (last.status != status || busyStarted) {
      event = 'status';
    }
    if (event == null) return;
    if (event == 'status' && !_allowStatus()) return;
    _report(session, event, i, status: status, code: cur.code);
  }

  bool _allowStatus() {
    final now = _now();
    _recent.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (_recent.length < statusBurstLimit) return true;
    _throttleTimer ??= Timer(
      const Duration(minutes: 1) - now.difference(_recent.first),
      () {
        _throttleTimer = null;
        onState();
      },
    );
    return false;
  }

  /// [failure] / [message]: the failure and text of a report about a red
  /// box no longer on screen ([onGatewayReboot]). [remember] false keeps
  /// [_last] (the next report is decided as if this one was not sent).
  void _report(
    FieldSession session,
    String event,
    FieldInput i, {
    required String status,
    RescueCode? code,
    GatewayFailure? failure,
    String? message,
    bool remember = true,
  }) {
    final now = _now();
    session.seq++;
    final body = buildSessionReport(
      sessionId: session.id,
      seq: session.seq,
      event: event,
      now: now,
      input: i,
      status: status,
      code: code,
      failure: failure ?? _failureFor(i)?.failure,
      app: _app(i),
      phone: _phone,
      lastCommand: journal.lastCommand(now),
      secrets: journal.secrets,
      errorMessage: message,
      operatorName: _operator(),
    );
    if (remember) _last = _Reported(fieldStep(i), status, code?.wire);
    _recent.add(now);
    _saveLive();
    _enqueue(
      OutboxItem(
        kind: 'session',
        body: body,
        createdMs: now.millisecondsSinceEpoch,
        origin: _originFor(i),
        transient: event == 'heartbeat',
      ),
    );
  }

  void _diagnose(
    String trigger,
    FieldInput i,
    RescueCode code, {
    FieldFailure? failure,
  }) {
    final session = _session;
    if (session == null) return;
    final now = _now();
    final lastAt = _lastDiagAt;
    if (trigger != 'help' &&
        lastAt != null &&
        now.difference(lastAt) < diagThrottle) {
      _pendingDiag = (trigger, code, failure);
      _diagTimer ??= Timer(diagThrottle - now.difference(lastAt), () {
        _diagTimer = null;
        final pending = _pendingDiag;
        _pendingDiag = null;
        final input = _read();
        if (pending == null || input == null || _session == null) return;
        _guard(
          () => _diagnose(pending.$1, input, pending.$2, failure: pending.$3),
        );
      });
      return;
    }
    session.diagSeq++;
    Map<String, dynamic> sections = const {};
    try {
      sections = _sections?.call() ?? const {};
    } catch (_) {}
    final body = buildDiagnostics(
      sessionId: session.id,
      diagSeq: session.diagSeq,
      trigger: trigger,
      now: now,
      input: i,
      code: code,
      failure: failure ?? _failureFor(i),
      commands: journal.snapshot(),
      sections: sections,
      app: _app(i),
      phone: _phone,
      secrets: journal.secrets,
      operatorName: _operator(),
    );
    _lastDiagAt = now;
    session.diagSentThisStep = true;
    _saveLive();
    _enqueue(
      OutboxItem(
        kind: 'diag',
        body: body,
        createdMs: now.millisecondsSinceEpoch,
        origin: _originFor(i),
      ),
    );
  }

  /// A run ended with [failure] (its red box is already on screen). A
  /// cancel is not reported.
  void onFailure(
    GatewayFailure failure, {
    bool rebooted = false,
    bool? safe,
    bool timedOut = false,
    String? runLabel,
    required int ctlStep,
  }) => _guard(() {
    if (!_enabled) return;
    final i = _read();
    if (i == null) return;
    final code = rescueCodeOf(
      failure,
      rebooted: rebooted,
      safe: safe,
      ctlStep: ctlStep,
      assignFailTexts: i.state.assignFailed.values,
    );
    if (code == null) {
      // Rule 27: the installer's own cancel — its red box is not reported
      // as an error, and no package is sent.
      _failure = FieldFailure(failure: failure, errorText: i.state.error);
      onState();
      return;
    }
    final record = FieldFailure(
      code: code,
      failure: failure,
      rebooted: rebooted,
      safe: safe,
      runLabel: runLabel,
      errorText: i.state.error,
      at: _now(),
    );
    _failure = record;
    _evaluate();
    if (_session == null) return;
    _diagnose(
      failure.code == 'timeout' ? 'timeout' : 'error',
      i,
      code,
      failure: record,
    );
  });

  /// A red box set outside a run (e.g. 「沿用目前站點」 refused) is [code].
  void noteErrorCode(RescueCode code) => _guard(() {
    if (!_enabled) return;
    final i = _read();
    _failure = FieldFailure(code: code, errorText: i?.state.error, at: _now());
    onState();
  });

  /// Round 24 (field round 24: a gateway restart during 「配置」 was
  /// recorded as BLE_LINK_DROP): the controller found a restart
  /// (boot_count [to] is higher than before) outside a failure it is
  /// classifying — usually only once the phone has reconnected, after the
  /// link drop the restart caused was reported. Adds to the timeline:
  /// - a failure of [rebootExplainedCodes] classified within
  ///   [rebootAmendWindow] is re-classified GW_REBOOTED (its red box, if
  ///   still on screen, reports GW_REBOOTED from now on);
  /// - an `error` report with error_code GW_REBOOTED (the session's latest
  ///   code; fail_code stays the failure's own, error_message is [text],
  ///   the restart notice) and a package with `error.rebooted: true`.
  /// A restart without such a failure is reported the same way.
  void onGatewayReboot({required int to, String? text}) => _guard(() {
    final session = _session;
    if (!_enabled || session == null || _rebootSeen == to) return;
    _rebootSeen = to;
    final i = _read();
    if (i == null) return;
    final now = _now();
    final last = _failure;
    final at = last?.at;
    final amend =
        last != null &&
        rebootExplainedCodes.contains(last.code) &&
        at != null &&
        now.difference(at) <= rebootAmendWindow;
    final record = FieldFailure(
      code: RescueCode.gwRebooted,
      failure: amend ? last.failure : null,
      rebooted: true,
      safe: amend ? last.safe : null,
      runLabel: amend ? last.runLabel : null,
      errorText: amend ? last.errorText : null,
      at: amend ? at : now,
      note: text,
    );
    if (amend) _failure = record;
    final step = fieldStep(i);
    if (session.step != step) _enterStep(session, step);
    if (amend && _failureFor(i) != null) {
      // Its red box is still up: the usual report says GW_REBOOTED now.
      _evaluate();
    } else {
      final cur = _current(i, step);
      _report(
        session,
        'error',
        i,
        status: _status(i, cur.help),
        code: RescueCode.gwRebooted,
        failure: record.failure,
        message: text,
        remember: false,
      );
    }
    _diagnose('error', i, RescueCode.gwRebooted, failure: record);
  });

  // ---- timers ----

  /// Heartbeat (every [FieldReporterConfig.heartbeat]): the latest state,
  /// sent once, never queued. Skipped while reports of this session wait
  /// in the outbox (they carry the state and go first).
  void heartbeat() => _guard(() {
    final session = _session;
    if (!_enabled || session == null || !_foreground || _disposed) return;
    if (_items.any(
      (it) => it.kind == 'session' && it.sessionId == session.id,
    )) {
      unawaited(flush());
      return;
    }
    final i = _read();
    if (i == null) return;
    final step = fieldStep(i);
    if (session.step != step) {
      onState();
      return;
    }
    final cur = _current(i, step);
    _report(
      session,
      'heartbeat',
      i,
      status: _status(i, cur.help),
      code: cur.code,
    );
  });

  /// The step has not changed for [FieldReporterConfig.stuckFor] and no
  /// package was sent in it: a `stuck` package and STEP_STUCK.
  void checkStuck() => _guard(() {
    _stuckTimer = null;
    final session = _session;
    if (!_enabled || session == null) return;
    final i = _read();
    if (i == null) return;
    final step = fieldStep(i);
    final entered = session.stepEnteredAt;
    if (session.step != step || session.diagSentThisStep || entered == null) {
      return;
    }
    final waited = _now().difference(entered);
    final limit = _config.stuckFor(step);
    if (waited < limit) {
      _stuckTimer = Timer(limit - waited, checkStuck);
      return;
    }
    session.stuck = true;
    final cur = _current(i, step);
    _diagnose('stuck', i, cur.code ?? RescueCode.stepStuck);
    _evaluate();
  });

  void setForeground(bool value) => _guard(() {
    if (!_enabled) return;
    _foreground = value;
    if (value) {
      _startHeartbeat();
      unawaited(flush());
    } else {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  });

  /// Round 24 (field round 24: a help queued offline reached the backend
  /// 54.5 s after the network came back — the back-off had grown to 60 s):
  /// the phone's network is back ([FieldReporterConfig.networkEvents]).
  /// The back-off is dropped and what is queued goes out at once; the timed
  /// retry ([FieldReporterConfig.retryEvery]) stays as the fallback. A try
  /// that still fails (the network is not routable yet) backs off from the
  /// first step again (5 s), and Android's `validated` event right after
  /// sends it again.
  void onNetworkBack() => _guard(() {
    if (!_enabled || _disposed) return;
    _backoffUntil = null;
    _backoffStep = 0;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    if (_items.isEmpty && _early.isEmpty) return;
    unawaited(flush());
  });

  /// Another backend was selected: what was queued for the old one is
  /// dropped (never sent across environments).
  void onBackendChanged(String base) => _guard(() {
    if (!_enabled) return;
    final origin = originOf(base);
    _lastOrigin = origin;
    _items.removeWhere((i) => i.origin != null && i.origin != origin);
    _early.removeWhere((i) => i.origin != null && i.origin != origin);
    _backoffUntil = null;
    _backoffStep = 0;
    _persist();
    final id = _installId;
    if (id != null &&
        _install.reportId == id &&
        (_install.phase == InstallReportPhase.sending ||
            _install.phase == InstallReportPhase.queued) &&
        !_installQueued(id)) {
      _setInstall(
        InstallReportStatus(
          phase: InstallReportPhase.failed,
          reportId: id,
          reason: '已切換後台，報告沒有送出',
        ),
      );
    }
  });

  // ---- help ----

  /// 「請後台協助」: a session (created if none yet), a `help` report and a
  /// `help` package, then the outcome for the sheet (「已通知後台」).
  Future<void> requestHelp() async {
    if (!_enabled) {
      _setHelp(const FieldHelpState(phase: FieldHelpPhase.disabled));
      return;
    }
    try {
      await _loaded;
      final i = _read();
      final session = _session ?? _startSession();
      final step = i == null ? (session.step ?? 1) : fieldStep(i);
      if (session.step != step) _enterStep(session, step);
      final base = i == null ? null : _baseCode(i);
      session.help = (step: step, base: base);
      final code = base ?? RescueCode.helpOnly;
      _setHelp(
        FieldHelpState(phase: FieldHelpPhase.sending, errorCode: code.wire),
      );
      if (i != null) {
        _report(session, 'help', i, status: 'help', code: code);
        _diagnose('help', i, code, failure: _failureFor(i));
      }
      await flush().timeout(_config.helpWait, onTimeout: () {});
      _setHelp(_helpOutcome());
    } catch (_) {
      _setHelp(
        _help.copyWith(phase: FieldHelpPhase.queued, reason: '沒有網路或後台沒有回應'),
      );
    }
  }

  /// 〔重新傳送〕 on the help sheet.
  Future<void> resendHelp() async {
    if (!_enabled) return;
    try {
      _backoffUntil = null;
      await flush().timeout(_config.helpWait, onTimeout: () {});
      _setHelp(_helpOutcome());
    } catch (_) {}
  }

  FieldHelpState _helpOutcome() {
    final session = _session;
    final key = _originKey;
    final until = _disabledUntil[key];
    if (until != null && _now().isBefore(until)) {
      return _help.copyWith(phase: FieldHelpPhase.unsupported, reason: '');
    }
    final pending = _items.any(
      (it) => it.isHelp && (session == null || it.sessionId == session.id),
    );
    if (!pending) {
      return _help.copyWith(phase: FieldHelpPhase.sent, reason: '');
    }
    final api = _api;
    final noLogin = api is SessionInfo && !(api as SessionInfo).hasSession;
    return _help.copyWith(
      phase: FieldHelpPhase.queued,
      reason: noLogin ? '尚未登入後台' : '沒有網路或後台沒有回應',
    );
  }

  // ---- install report (09-28) ----

  /// The done page is on screen: its report is queued and sent (once per
  /// completion; demo: [InstallReportPhase.disabled]).
  void _queueInstallReport() {
    if (!_enabled) {
      _setInstall(
        const InstallReportStatus(phase: InstallReportPhase.disabled),
      );
      return;
    }
    final i = _read();
    if (i == null || _disposed) return;
    final report = i.state.report;
    if (report.isEmpty || report == _installText) return;
    final now = _now();
    final body = buildInstallReport(
      reportId: newSessionId(_random),
      input: i,
      now: now,
      app: _app(i),
      phone: _phone,
      sessionId: _session?.id,
      secrets: journal.secrets,
    );
    if (body == null) return;
    _installText = report;
    _installId = body['report_id'] as String;
    _installBody = body;
    _setInstall(
      InstallReportStatus(
        phase: InstallReportPhase.sending,
        reportId: _installId,
      ),
    );
    _enqueue(
      OutboxItem(
        kind: 'install',
        body: body,
        createdMs: now.millisecondsSinceEpoch,
        origin: _originFor(i),
      ),
    );
  }

  bool _installQueued(String id) => [
    ..._items,
    ..._early,
  ].any((it) => it.kind == 'install' && it.body['report_id'] == id);

  /// 〔重送〕 on the done page: now, without waiting for the back-off (a
  /// refused report is queued again — the same `report_id`, so the backend
  /// keeps one row).
  Future<void> resendInstallReport() async {
    if (!_enabled || _disposed) return;
    try {
      await _loaded;
      final id = _installId, body = _installBody;
      if (id == null || body == null) return;
      if (!_installQueued(id)) {
        final i = _read();
        _enqueue(
          OutboxItem(
            kind: 'install',
            body: body,
            createdMs: _now().millisecondsSinceEpoch,
            origin: i == null ? _lastOrigin : _originFor(i),
          ),
        );
      }
      _backoffUntil = null;
      _backoffStep = 0;
      _disabledUntil.remove(_originKey);
      _setInstall(
        InstallReportStatus(phase: InstallReportPhase.sending, reportId: id),
      );
      await flush().timeout(_config.helpWait, onTimeout: () {});
      _setInstall(_installOutcome());
    } catch (_) {}
  }

  /// Where the report on the done page is after a try (sent / failed are
  /// set when the answer comes).
  InstallReportStatus _installOutcome() {
    final id = _installId;
    final current = _install;
    if (id == null ||
        current.reportId != id ||
        current.phase == InstallReportPhase.sent ||
        current.phase == InstallReportPhase.failed) {
      return current;
    }
    if (!_installQueued(id)) {
      return InstallReportStatus(
        phase: InstallReportPhase.failed,
        reportId: id,
        reason: '已從手機的待送清單移除',
      );
    }
    final until = _disabledUntil[_originKey];
    if (until != null && _now().isBefore(until)) {
      return InstallReportStatus(
        phase: InstallReportPhase.failed,
        reportId: id,
        reason: '後台尚未支援（請更新後台）',
      );
    }
    final api = _api;
    final noLogin = api is SessionInfo && !(api as SessionInfo).hasSession;
    return InstallReportStatus(
      phase: InstallReportPhase.queued,
      reportId: id,
      reason: noLogin ? '尚未登入後台' : '沒有網路或後台沒有回應',
    );
  }

  /// The answer to an install report: sent, or refused ([reason]).
  void _installAnswered(OutboxItem item, {String? reason}) {
    final id = item.body['report_id'];
    if (id != _installId) return;
    _setInstall(
      reason == null
          ? InstallReportStatus(
              phase: InstallReportPhase.sent,
              sentAt: _now(),
              reportId: id as String?,
            )
          : InstallReportStatus(
              phase: InstallReportPhase.failed,
              reportId: id as String?,
              reason: reason,
            ),
    );
  }

  // ---- outbox ----

  void _enqueue(OutboxItem item) {
    if (_loadDone) {
      _items.add(item);
      pruneOutbox(_items, _now());
      _persist();
    } else {
      _early.add(item);
    }
    unawaited(flush());
  }

  void _ensureRetryTimer() {
    if (_retryTimer != null || _disposed) return;
    _retryTimer = Timer.periodic(_config.retryEvery, (_) => flush());
  }

  void _stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _backoff() {
    final wait = fieldBackoff[min(_backoffStep, fieldBackoff.length - 1)];
    _backoffStep++;
    _backoffUntil = _now().add(wait);
    _wakeTimer?.cancel();
    if (!_disposed) {
      _wakeTimer = Timer(wait, () {
        _wakeTimer = null;
        unawaited(flush());
      });
    }
  }

  /// Sends what is queued, one request at a time (reports first, then
  /// packages; each in the order made). Never throws.
  Future<void> flush() {
    if (!_enabled || _disposed) return Future<void>.value();
    final running = _draining;
    if (running != null) {
      _drainAgain = true;
      return running;
    }
    final future = () async {
      try {
        do {
          _drainAgain = false;
          await _drain();
        } while (_drainAgain && !_disposed);
      } catch (error) {
        debugPrint('FIELD flush error: $error');
      } finally {
        _draining = null;
      }
      // A queued help went out on a later try: the sheet says so.
      if (_help.phase == FieldHelpPhase.queued) _setHelp(_helpOutcome());
      if (_install.phase == InstallReportPhase.sending ||
          _install.phase == InstallReportPhase.queued) {
        _setInstall(_installOutcome());
      }
    }();
    _draining = future;
    return future;
  }

  OutboxItem? _next() {
    for (final i in _items) {
      if (i.kind == 'session') return i;
    }
    // 09-28: the install report before packages.
    for (final i in _items) {
      if (i.kind == 'install') return i;
    }
    return _items.isEmpty ? null : _items.first;
  }

  /// Heartbeats are never kept for a later try.
  void _dropTransient() => _items.removeWhere((i) => i.transient);

  Future<void> _drain() async {
    await _loaded;
    if (_disposed) return;
    final now = _now();
    pruneOutbox(_items, now);
    if (_items.isEmpty) {
      _stopRetryTimer();
      return;
    }
    _ensureRetryTimer();
    final backoff = _backoffUntil;
    final until = _disabledUntil[_originKey];
    final api = _api;
    if ((backoff != null && now.isBefore(backoff)) ||
        (until != null && now.isBefore(until)) ||
        (api is SessionInfo && !(api as SessionInfo).hasSession)) {
      _dropTransient();
      return;
    }
    // Everything queued goes to the backend logged in now: items of another
    // environment were already dropped when it was switched
    // ([onBackendChanged]).
    final origin = _apiOrigin();
    while (!_disposed) {
      final item = _next();
      if (item == null) break;
      final body = {
        ...item.body,
        'queued_ms': max(0, _now().millisecondsSinceEpoch - item.createdMs),
      }..remove('short_code'); // v1 items queued before the update
      try {
        await _api.request('POST', item.path, body);
        _items.remove(item);
        _backoffStep = 0;
        _backoffUntil = null;
        if (item.kind == 'install') _installAnswered(item);
        if (item.kind == 'diag') {
          debugPrint(
            'FIELD diag sent ${item.trigger} #${item.body['diag_seq']} '
            '${item.sessionId ?? ''}',
          );
        }
      } on GatewayFailure catch (f) {
        // v1.1: a 409 (no longer sent for a help code) is an ordinary
        // failure: kept and tried again after the back-off.
        if (item.transient) _items.remove(item);
        if (f.code == 'authentication') break;
        // 09-28: a backend without install reports (older than the APP)
        // refuses only this one; the rescue uploads keep going.
        if (item.kind == 'install' && f.code == 'api' && f.status == 404) {
          _items.remove(item);
          _installAnswered(item, reason: '後台尚未支援（請更新後台）');
          continue;
        }
        if (f.code == 'api' && f.status == 404) {
          _disabledUntil[origin ?? _originKey] = _now().add(
            fieldDisableAfter404,
          );
          break;
        }
        if (f.code == 'api' && (f.status == 413 || f.status == 422)) {
          _items.remove(item);
          debugPrint('FIELD dropped ${item.kind}: HTTP ${f.status}');
          if (item.kind == 'install') {
            _installAnswered(item, reason: '後台拒收（HTTP ${f.status}）');
          }
          continue;
        }
        item.tries++;
        _backoff();
        break;
      } catch (error) {
        if (item.transient) _items.remove(item);
        item.tries++;
        _backoff();
        break;
      }
    }
    _dropTransient();
    _persist();
    if (_items.any((i) => !i.transient)) {
      _ensureRetryTimer();
    } else {
      _stopRetryTimer();
    }
  }
}
