/// Install report to the back office (09-28, user request: 「安裝報告能直接
///送給後台」). When the commissioning reaches the done page (verified, or
/// 〔先完成配置〕) the report goes to `POST /api/field/install-reports` on
/// its own, through the field reporter's outbox ([FieldReporter]): queued
/// on the phone while there is no network or no login, sent again when the
/// network comes back. The done page shows where it is
/// ([InstallReportStatus]); 〔分享安裝報告〕 stays as the secondary way.
///
/// The JSON carries site, gateway, MAC, mode, the PTUs and their binding,
/// the verify time, the backend and upload target, firmware / APP versions
/// and the phone model — never the Wi-Fi password or a token (masked again
/// with the journal's secrets, and a second time by the backend).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/direct_mode.dart';
import '../core/mqtt_target.dart';
import '../l10n/l10n.dart';
import 'commissioning_controller.dart';
import 'field_journal.dart';
import 'field_report.dart';

const installReportsPath = '/api/field/install-reports';
const installReportSchemaVersion = 1;

/// Longer than session events ([outboxMaxAge]): the report is the record
/// of the installation.
const installReportMaxAge = Duration(days: 7);

/// Install reports kept in the outbox at most (oldest dropped first).
const outboxInstallLimit = 10;

/// Backend limit of `report_text`.
const installReportTextMax = 8000;

String? _cut(Object? value, int limit) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return text.length <= limit ? text : text.substring(0, limit);
}

/// Where the gateway uploads, as one short line (`upload_target`).
///
/// i18n：只上傳後台，固定中文（docs/i18n.md §6）。
String uploadTargetOf(Map<String, dynamic> config) {
  final target = parseMqttTarget(config);
  // i18n-keep-zh-begin
  if (target == null) {
    return reportsMqttTarget(config) ? '未確認' : '正式站（韌體固定）';
  }
  if (target.isLocal) return '本地 ${target.host}:${target.port}';
  return target.host.isEmpty ? '正式站' : '正式站 ${target.host}:${target.port}';
  // i18n-keep-zh-end
}

/// The report of the done page on screen, or null when there is none
/// (not on the done page, no report text, or no site / gateway number).
/// [reportId]: 32 hex characters (a resend of the same report is the same
/// row on the backend). [app] / [phone]: the reporter's blocks.
Map<String, dynamic>? buildInstallReport({
  required String reportId,
  required FieldInput input,
  required DateTime now,
  Map<String, dynamic> app = const {},
  Map<String, dynamic> phone = const {},
  String? sessionId,
  Iterable<String> secrets = const [],
}) {
  final s = input.state;
  if (s.step != 7 || !(s.verified || s.ptuDeferred)) return null;
  if (s.report.trim().isEmpty) return null;
  final identity = fieldIdentity(input);
  if (identity['site_id'] == null || identity['gateway_id'] == null) {
    return null;
  }
  final deferred = !s.verified && s.ptuDeferred;
  final direct = input.directMode;
  final bound = direct
      ? directBoundMacOf(s.config) ?? s.direct?.boundMac
      : null;
  final body = <String, dynamic>{
    'schema': installReportSchemaVersion,
    'report_id': reportId,
    'result': deferred ? 'deferred' : 'verified',
    'site_id': identity['site_id'],
    'gateway_id': identity['gateway_id'],
    'gateway_mac': identity['gateway_mac'],
    'gateway_name': identity['gateway_name'],
    'mode': identity['mode'],
    'fw_version': identity['fw_version'],
    'ptus': deferred
        ? const <Map<String, dynamic>>[]
        : [
            for (final p in byDeviceNumber(s.ptus))
              {
                'device_number': (p['device_number'] as num?)?.toInt(),
                'mac': _cut(p['mac'], 32),
                'verified': !s.verifySkipped.contains(
                  (p['device_number'] as num?)?.toInt(),
                ),
              },
          ],
    'direct_bound_mac': _cut(bound, 32),
    if (!direct) 'star_list': s.starList.name,
    'verified_at': isoWithOffset(now),
    'backend': {
      'env': input.env.environment.name,
      'origin': app['backend_origin'],
    },
    'upload_target': _cut(uploadTargetOf(s.config), 80),
    'app': app,
    'phone': phone,
    'session_id': sessionId,
    'report_text': _cut(s.report, installReportTextMax),
    'client_ts': isoWithOffset(now),
    'queued_ms': 0,
  };
  return Map<String, dynamic>.from(
    scrubSecrets(redactKeys(body), secrets) as Map,
  );
}

// ---- Done page status ----

enum InstallReportPhase {
  /// No report made yet (not on the done page).
  idle,

  /// Being uploaded.
  sending,

  /// The back office has it ([InstallReportStatus.sentAt]).
  sent,

  /// Waiting on the phone (no network / not logged in); sent on its own.
  queued,

  /// The backend refused it (or has no install reports yet): 〔重送〕.
  failed,

  /// Demo gateway: nothing is sent.
  disabled,
}

class InstallReportStatus {
  const InstallReportStatus({
    this.phase = InstallReportPhase.idle,
    this.sentAt,
    this.reason = '',
    this.reportId,
  });

  final InstallReportPhase phase;
  final DateTime? sentAt;

  /// Why it is queued / failed.
  final String reason;
  final String? reportId;

  bool get canResend =>
      phase == InstallReportPhase.queued || phase == InstallReportPhase.failed;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// The done page line (screen only: follows the screen language).
String installReportStatusText(InstallReportStatus s) {
  final l10n = L10n.current;
  return switch (s.phase) {
    InstallReportPhase.idle => '',
    InstallReportPhase.sending => l10n.installReport_sending,
    InstallReportPhase.sent =>
      s.sentAt == null
          ? l10n.installReport_sent
          : l10n.installReport_sentAt(
              '${_two(s.sentAt!.hour)}:${_two(s.sentAt!.minute)}',
            ),
    InstallReportPhase.queued =>
      s.reason.isEmpty
          ? l10n.installReport_queued
          : l10n.installReport_queuedReason(s.reason),
    InstallReportPhase.failed =>
      s.reason.isEmpty
          ? l10n.installReport_failed
          : l10n.installReport_failedReason(s.reason),
    InstallReportPhase.disabled => l10n.installReport_demo,
  };
}

class InstallReportNotifier extends Notifier<InstallReportStatus> {
  @override
  InstallReportStatus build() => const InstallReportStatus();
  void set(InstallReportStatus value) => state = value;
}

final installReportProvider =
    NotifierProvider<InstallReportNotifier, InstallReportStatus>(
      InstallReportNotifier.new,
    );
