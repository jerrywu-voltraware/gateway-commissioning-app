/// Human-readable diagnostics for commissioning step 7 (data verification).
///
/// Pure functions so the wording can be unit-tested without a controller.
library;

import '../core/mqtt_target.dart';
import '../l10n/l10n.dart';

/// Why the backend has no data (or no row) for this gateway, given what the
/// APP knows about the gateway's upload target.
///
/// [running] is the target the gateway last reported, [wanted] the target
/// matching the APP backend, [mqttConnected] the last `mqtt_connected` value.
/// "Another backend" is only suggested when the target is unknown or differs.
String missingGatewayCause({
  MqttTarget? running,
  MqttTarget? wanted,
  Object? mqttConnected,
}) {
  final l10n = L10n.current;
  if (running != null && wanted != null && running.sameAs(wanted)) {
    final state = switch (mqttConnected) {
      false => l10n.verifyDiagnosis_mqttDisconnected,
      true => l10n.verifyDiagnosis_mqttConnected,
      _ => '',
    };
    final hint = running.isLocal
        ? l10n.verifyDiagnosis_localHint('${running.port}', running.host)
        : l10n.verifyDiagnosis_productionHint('${running.port}');
    return l10n.verifyDiagnosis_sameTarget(running.label, state, hint);
  }
  if (wanted != null && !wanted.isLocal && running == null) {
    return l10n.verifyDiagnosis_causeProductionUnknown;
  }
  return l10n.verifyDiagnosis_causeOtherBackend;
}

/// Step 9: a row whose back office `lag_seconds` is this or more is late
/// (seconds) — while the gateway uploads every second (build mode).
/// 1.0.0+20: a gateway left at a longer interval gets a longer limit
/// (`verifyLagLimitFor` in the controller).
const verifyLagLimit = 60;

/// Reasons one PTU has not passed the current verification round.
///
/// [install] is the device row from `verify-installation`, [latest] the row
/// from `/api/latest`, [previous] the timestamp seen in the previous round;
/// [lagLimit] (seconds): a `lag_seconds` this or more is late.
List<String> ptuVerifyReasons({
  Map<String, dynamic>? install,
  Map<String, dynamic>? latest,
  DateTime? previous,
  int lagLimit = verifyLagLimit,
}) {
  final l10n = L10n.current;
  final reasons = <String>[];
  final noBackendData =
      install != null &&
      install['data_ok'] != true &&
      (install['last_seen'] == null || install['time_since_last'] == null);
  if (noBackendData) {
    reasons.add(l10n.verifyDiagnosis_reasonNoBackendData);
  } else if (install != null && install['data_ok'] != true) {
    reasons.add(
      l10n.verifyDiagnosis_reasonBackendLate('${install['time_since_last']}'),
    );
  }
  if (latest == null) {
    if (!noBackendData) reasons.add(l10n.verifyDiagnosis_reasonNotInLatest);
    return reasons;
  }
  if (latest['online'] != true) reasons.add(l10n.verifyDiagnosis_reasonOffline);
  final lag = latest['lag_seconds'] as num?;
  if (lag == null) {
    reasons.add(l10n.verifyDiagnosis_reasonLagUnknown);
  } else if (lag >= lagLimit) {
    reasons.add(l10n.verifyDiagnosis_reasonLag(lag.round()));
  }
  if (latest['error_num'] != 0) reasons.add('error_num=${latest['error_num']}');
  final stamp = DateTime.tryParse(latest['ts']?.toString() ?? '');
  if (stamp == null) {
    reasons.add(l10n.verifyDiagnosis_reasonBadTime);
  } else if (previous != null && !stamp.isAfter(previous)) {
    reasons.add(l10n.verifyDiagnosis_reasonNotUpdated('${latest['ts']}'));
  }
  return reasons;
}

/// Multi-line summary of why verification has not passed yet. [cause]
/// explains a gateway with no data at all (see [missingGatewayCause]).
String verifyDiagnosis({
  required Iterable<int> ids,
  required Map<String, dynamic> install,
  required List<Map<String, dynamic>> rows,
  required Map<String, dynamic>? fleet,
  required Map<int, DateTime> previous,
  required int site,
  required int gateway,
  required int consecutive,
  required String backend,
  String? cause,
  int lagLimit = verifyLagLimit,
}) {
  final l10n = L10n.current;
  final lines = <String>[];
  if (fleet == null && rows.isEmpty) {
    lines.add(
      l10n.verifyDiagnosis_noData(
        backend,
        site,
        gateway,
        cause ?? missingGatewayCause(),
      ),
    );
  } else if (fleet == null) {
    lines.add(l10n.verifyDiagnosis_noFleet(site, gateway));
  } else {
    if (fleet['online'] != true) {
      lines.add(
        l10n.verifyDiagnosis_offline(
          '${fleet['last_heartbeat'] ?? l10n.verifyDiagnosis_none}',
        ),
      );
    }
    if (fleet['upload_paused'] == true) {
      lines.add(l10n.verifyDiagnosis_uploadPaused);
    }
  }
  lines.add(l10n.verifyDiagnosis_consecutive(consecutive));
  final installRows = <int, Map<String, dynamic>>{};
  for (final item in (install['devices'] as List? ?? [])) {
    if (item is! Map) continue;
    final id = (item['device_id'] as num?)?.toInt();
    if (id != null) installRows[id] = Map<String, dynamic>.from(item);
  }
  for (final id in ids) {
    final latest = rows.where((r) => r['device_id'] == id).firstOrNull;
    final reasons = ptuVerifyReasons(
      install: installRows[id],
      latest: latest,
      previous: previous[id],
      lagLimit: lagLimit,
    );
    if (reasons.isEmpty &&
        install['all_ok'] != true &&
        !installRows.containsKey(id)) {
      reasons.add(l10n.verifyDiagnosis_installNoDetail);
    }
    lines.add(
      l10n.verifyDiagnosis_ptuLine(
        id,
        reasons.isEmpty
            ? l10n.verifyDiagnosis_roundOk
            : reasons.join(l10n.common_listSeparator),
      ),
    );
  }
  return lines.join('\n');
}
