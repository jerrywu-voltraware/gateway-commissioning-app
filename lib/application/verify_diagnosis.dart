/// Human-readable diagnostics for commissioning step 7 (data verification).
///
/// Pure functions so the wording can be unit-tested without a controller.
library;

import '../core/mqtt_target.dart';

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
  if (running != null && wanted != null && running.sameAs(wanted)) {
    final state = switch (mqttConnected) {
      false => 'Gateway 最近回報 MQTT 未連線。',
      true => 'Gateway 最近回報 MQTT 已連線，可能剛連上、心跳尚未送達，可稍候再驗證。',
      _ => '',
    };
    final hint = running.isLocal
        ? '請確認：Gateway 的 MQTT 已連線（按「重新讀取」查看）、電腦防火牆已開放 TCP '
              '${running.port}、本地 MQTT broker 已啟動，且 broker 憑證包含電腦目前的 IP '
              '${running.host}（電腦 IP 若因 DHCP 變更，需重新產生憑證並把 Gateway 切到新 IP）。'
        : '請確認現場網路可連到正式站（TCP ${running.port}），並按「重新讀取」查看 MQTT 是否已連線。';
    return 'Gateway 已確認上傳到${running.label}（與 APP 所連後端一致），'
        '但後端尚未收到它的心跳，表示 Gateway 還沒連上該 MQTT broker。$state\n$hint';
  }
  if (wanted != null && !wanted.isLocal && running == null) {
    return 'Gateway 可能尚未連上正式站的 MQTT，或上傳到其他後端環境（例如本地測試站）。';
  }
  return 'Gateway 可能上傳到其他後端環境（例如正式站）。';
}

/// Reasons one PTU has not passed the current verification round.
///
/// [install] is the device row from `verify-installation`, [latest] the row
/// from `/api/latest`, [previous] the timestamp seen in the previous round.
List<String> ptuVerifyReasons({
  Map<String, dynamic>? install,
  Map<String, dynamic>? latest,
  DateTime? previous,
}) {
  final reasons = <String>[];
  final noBackendData =
      install != null &&
      install['data_ok'] != true &&
      (install['last_seen'] == null || install['time_since_last'] == null);
  if (noBackendData) {
    reasons.add('後端無資料');
  } else if (install != null && install['data_ok'] != true) {
    reasons.add('後端資料延遲 ${install['time_since_last']} 秒');
  }
  if (latest == null) {
    if (!noBackendData) reasons.add('最新資料（/api/latest）無此 PTU');
    return reasons;
  }
  if (latest['online'] != true) reasons.add('離線');
  final lag = latest['lag_seconds'] as num?;
  if (lag == null) {
    reasons.add('延遲未知');
  } else if (lag >= 60) {
    reasons.add('延遲 ${lag.round()} 秒');
  }
  if (latest['error_num'] != 0) reasons.add('error_num=${latest['error_num']}');
  final stamp = DateTime.tryParse(latest['ts']?.toString() ?? '');
  if (stamp == null) {
    reasons.add('資料時間無法解析');
  } else if (previous != null && !stamp.isAfter(previous)) {
    reasons.add('資料未更新（最後 ${latest['ts']}）');
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
}) {
  final lines = <String>[];
  if (fleet == null && rows.isEmpty) {
    lines.add(
      'Gateway 的資料沒有進入目前連線的$backend：fleet-status 沒有站 $site / '
      'Gateway $gateway 的心跳，/api/latest 也沒有任何資料。'
      '${cause ?? missingGatewayCause()}',
    );
  } else if (fleet == null) {
    lines.add('fleet-status 沒有站 $site / Gateway $gateway 的心跳紀錄。');
  } else {
    if (fleet['online'] != true) {
      lines.add('Gateway 在後端顯示離線（最後心跳 ${fleet['last_heartbeat'] ?? '無'}）。');
    }
    if (fleet['upload_paused'] == true) {
      lines.add('Gateway 資料上傳為暫停狀態（已嘗試恢復）。');
    }
  }
  lines.add('連續通過 $consecutive / 3 次。');
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
    );
    if (reasons.isEmpty &&
        install['all_ok'] != true &&
        !installRows.containsKey(id)) {
      reasons.add('後端安裝驗證未通過（未回傳此 PTU 明細）');
    }
    lines.add('PTU #$id：${reasons.isEmpty ? '本輪正常' : reasons.join('、')}');
  }
  return lines.join('\n');
}
