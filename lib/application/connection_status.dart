/// Plain-language 「連線狀態」 model: what the phone and the gateway are
/// connected to, one actionable hint, and the technical details.
///
/// Pure Dart so every wording can be unit-tested without widgets.
library;

import '../core/gateway_identity.dart';
import '../core/gateway_net.dart';
import '../core/gateway_reboot.dart';
import '../core/mqtt_target.dart';
import '../data/local_backend_probe.dart';
import 'backend_environment.dart';
import 'commissioning_controller.dart';

enum StatusTone { ok, pending, bad, warn, neutral }

class StatusRow {
  const StatusRow(this.where, this.status, this.tone);

  /// 本地測試主機 / 正式站 / 其他網址.
  final String where;

  /// ✓ 已連線 / ⏳ 連線中… / ✗ 連不上 / ⚠ 送到別處 … (empty: name only).
  final String status;
  final StatusTone tone;
}

/// What the one-tap 「同步」 would do.
enum SyncNeed {
  /// Nothing to do (already the same, or no gateway / nothing to compare).
  none,

  /// Connected gateway uploads elsewhere; [ConnectionStatus.syncTarget].
  sync,

  /// Firmware older than 1.7.3 cannot switch, and the APP wants local.
  legacy,

  /// The environment has no usable gateway target (e.g. invalid local IP).
  invalid,
}

class ConnectionStatus {
  const ConnectionStatus({
    required this.phone,
    required this.gateway,
    required this.hint,
    required this.need,
    required this.syncTarget,
    required this.shipWarning,
    required this.summary,
    required this.details,
    this.wifiWeak,
  });
  final StatusRow phone, gateway;

  /// The gateway's Wi-Fi works but is weak ([weakWifiWarning]), shown red
  /// under the gateway row; null otherwise, and while the network check
  /// (step 2) shows the same warning itself.
  final String? wifiWeak;

  /// The one plain actionable hint, or null when nothing needs doing.
  final String? hint;
  final SyncNeed need;
  final MqttTarget? syncTarget;

  /// Step 7: the gateway still uploads to a local test host. Round 29: a
  /// developer note on the done page of a local test build only
  /// ([EnvSwitchPolicy.localBuild]); the panel itself no longer shows it,
  /// and it does not keep the panel from its one-line all-OK summary.
  final bool shipWarning;

  /// One-line text for the collapsed all-OK panel, null when not all OK.
  final String? summary;

  /// 「技術細節」 lines.
  final List<String> details;

  bool get allOk => summary != null;
}

/// Decides whether the connected gateway must be switched to match [app].
(SyncNeed, MqttTarget?) uploadSyncNeed(
  CommissionState state,
  AppUploadTarget app,
) {
  if (state.peer == null || state.step < 2 || state.config.isEmpty) {
    return (SyncNeed.none, null);
  }
  if (!reportsMqttTarget(state.config)) {
    return (app.wantsLocal ? SyncNeed.legacy : SyncNeed.none, null);
  }
  if (app.error != null) return (SyncNeed.invalid, null);
  final wanted = app.target;
  if (wanted == null) return (SyncNeed.none, null);
  final current = parseMqttTarget(state.config);
  if (current != null && current.sameAs(wanted)) return (SyncNeed.none, null);
  return (SyncNeed.sync, wanted);
}

String placeOf(MqttTarget target) => target.isLocal ? '本地測試主機' : '正式站';

/// The gateway is on another /24 than the local test host, or null.
String? subnetHint(
  MqttTarget current,
  String gatewayIp, {
  String wifiAction = '保留站點，重設 Wi-Fi',
}) {
  final gatewayNet = ipv4Prefix24(gatewayIp);
  final hostNet = current.isLocal ? ipv4Prefix24(current.host) : null;
  if (gatewayNet == null || hostNet == null || gatewayNet == hostNet) {
    return null;
  }
  return 'Gateway 目前在 $gatewayNet.x 網段，可能連不到測試主機 ${current.host}。'
      '請確認 Gateway 和這台電腦連同一個 Wi-Fi（可用「$wifiAction」）。';
}

/// What to check when a gateway with Wi-Fi does not upload to [current].
String uploadCheckHint(MqttTarget current) => current.isLocal
    ? '請確認電腦上的測試主機是否開著，以及 Gateway 是否連上和這台電腦同一個 Wi-Fi。'
    : '請確認 Gateway 所在的 Wi-Fi 可以上網。';

/// Main hint when the gateway has no Wi-Fi: the cause first, then how to
/// get back to 「重設 Wi-Fi」 (after reconnecting Bluetooth if it dropped).
String wifiProblemHint(CommissionState state) {
  final ssid = gatewaySsid(state.net, state.config['wifi_ssid']);
  final reason = wifiDiscReasonOf(state.net);
  final action = ssid?.isEmpty == true ? '設定 Wi-Fi' : '重設 Wi-Fi';
  final next = state.uploadWatch == UploadWatch.linkLost && state.relinking
      ? '手機和 Gateway 的藍牙也斷了，$autoRelinkingText'
      : state.uploadWatch == UploadWatch.linkLost
      ? '手機和 Gateway 的藍牙也斷了：請靠近 Gateway，按「結束並重新選擇閘道器」'
            '重新連線，再按「$action」。'
      : state.step == 2
      ? '請按「$action」，改成現場的 2.4 GHz Wi-Fi。'
      : '請按「結束並重新選擇閘道器」重新連線，在網路體檢按「$action」。';
  return '${wifiProblemText(ssid, reason: reason)}\n$next';
}

/// 「連線狀態」 hint while the phone↔gateway Bluetooth is down. Round 13:
/// while the automatic reconnect runs ([CommissionState.relinking]) it says
/// so instead of asking for a tap; afterwards it names the button actually
/// shown (steps 7 / 8).
String linkLostHint(CommissionState state) {
  // Round 22: back already (the list is read again) — not 「已中斷」 any more.
  if (relinkBack(state)) return '手機已重新連上 Gateway，$relinkReloadText';
  if (state.relinking) return '手機和 Gateway 的藍牙已中斷，$autoRelinkingText';
  final action = switch (state.step) {
    4 when !state.resumePending => '請按「$rescanAfterLossLabel」。',
    4 || 5 => '請按「重新連線並繼續」。',
    _ => '請重新連線 Gateway 後再確認。',
  };
  return '手機和 Gateway 的藍牙已中斷，無法讀取目前狀態。$action';
}

String _envPlace(BackendEnv env) => switch (env) {
  BackendEnv.production => '正式站',
  BackendEnv.local => '本地測試主機',
  BackendEnv.custom => '其他網址',
};

StatusRow _phoneRow(
  BackendEnvState env, {
  required ProbeResult? probe,
  required bool loggedIn,
  required bool demo,
}) {
  final where = _envPlace(env.environment);
  if (demo) return StatusRow(where, '✓ 已連線（模擬）', StatusTone.ok);
  if (probe == null) {
    return loggedIn
        ? StatusRow(where, '✓ 已連線', StatusTone.ok)
        : StatusRow(where, '⏳ 檢查中…', StatusTone.pending);
  }
  switch (probe.outcome) {
    case ProbeOutcome.healthy:
      return StatusRow(where, '✓ 已連線', StatusTone.ok);
    case ProbeOutcome.degraded:
      return StatusRow(where, '⚠ 連上了，但資料庫還沒準備好', StatusTone.warn);
    case ProbeOutcome.unreachable:
    case ProbeOutcome.timeout:
      return loggedIn
          ? StatusRow(where, '✓ 已連線', StatusTone.ok)
          : StatusRow(where, '✗ 連不上', StatusTone.bad);
    case ProbeOutcome.notBackend:
    case ProbeOutcome.httpError:
      if (loggedIn) return StatusRow(where, '✓ 已連線', StatusTone.ok);
      // A local test host must answer /healthz; other sites may not have it.
      return env.environment == BackendEnv.local
          ? StatusRow(where, '✗ 連不上', StatusTone.bad)
          : StatusRow(where, '', StatusTone.neutral);
  }
}

String _probeText(ProbeResult? probe) => switch (probe?.outcome) {
  null => '檢查中',
  ProbeOutcome.healthy =>
    '正常${probe!.version == null ? '' : '（版本 ${probe.version}）'}',
  ProbeOutcome.degraded => '資料庫未就緒（HTTP 503）',
  ProbeOutcome.notBackend => '不是本系統後端（HTTP ${probe!.status}）',
  ProbeOutcome.httpError => 'HTTP ${probe!.status}',
  ProbeOutcome.timeout => '逾時',
  ProbeOutcome.unreachable =>
    '無法連線${probe!.detail == null ? '' : '（${probe.detail}）'}',
};

/// Builds the panel model. [probe] is the `/healthz` result of the APP
/// backend (null while checking), [demo] the simulated system.
ConnectionStatus connectionStatus({
  required BackendEnvState env,
  required CommissionState state,
  ProbeResult? probe,
  bool demo = false,
  DateTime? now,
}) {
  final app = env.uploadTarget;
  // The backend saw this gateway's heartbeat or data within the last 60 s.
  final seen = state.backendSeenAt;
  final backendFresh =
      seen != null &&
      (now ?? DateTime.now()).difference(seen) < const Duration(seconds: 60);
  final config = state.config;
  final net = state.net;
  final phone = _phoneRow(
    env,
    probe: probe,
    loggedIn: state.loggedIn,
    demo: demo,
  );
  final (need, syncTarget) = uploadSyncNeed(state, app);
  final legacy = !reportsMqttTarget(config);
  final current = parseMqttTarget(config);
  final unconfirmed = config['mqtt_target'] == unconfirmedMqttTarget;
  final polling = state.uploadWatch == UploadWatch.polling;
  // Round 26 (field: 「✓ 資料上傳中」 while the gateway's upload was paused
  // — heartbeats only, 0 rows — or it was in test mode): connected to the
  // broker is not uploading PTU data then.
  final held = state.testMode || state.uploadPaused;
  // Round 28 (field: pile B read 「✓ 資料上傳中」 at steps 5 and 6 with its
  // upload paused until join_fleet): a gateway not in service yet uploads
  // heartbeats only — on purpose, not a warning, never 「資料上傳中」.
  final waitingJoin = !held && uploadHeldUntilJoin(config);
  final uploading = config['mqtt_connected'] == true && !held;

  StatusRow gateway;
  String? hint;
  if (legacy) {
    gateway = need == SyncNeed.legacy
        ? const StatusRow('正式站', '⚠ 送到別處', StatusTone.warn)
        : const StatusRow('正式站', '', StatusTone.neutral);
    if (need == SyncNeed.legacy) hint = legacyTargetText(config['fw_version']);
  } else if (current == null) {
    gateway = polling
        ? const StatusRow('確認中', '⏳ 確認中…', StatusTone.pending)
        : StatusRow(unconfirmed ? '未確認' : '無法辨識', '？ 未確認', StatusTone.neutral);
    // One action: 「同步」 settles it when the APP knows the target (no
    // reboot if it already matches); otherwise read it again.
    if (!polling) {
      hint = need == SyncNeed.sync
          ? '還不確定 Gateway 把資料送到哪裡。按「同步」讓 Gateway 改送到'
                '${placeOf(syncTarget!)}。'
          : '還不確定 Gateway 把資料送到哪裡，請按「連線狀態」這一列最右邊的'
                '重新讀取圖示（↻）。';
    }
  } else if (need == SyncNeed.sync) {
    gateway = StatusRow(placeOf(current), '⚠ 送到別處', StatusTone.warn);
    hint = current.plainLabel == syncTarget!.plainLabel
        // Same place, other port: the difference is in 技術細節.
        ? 'Gateway 的上傳設定和手機不一致（見技術細節）。按「同步」讓 Gateway 改送到'
              '${placeOf(syncTarget)}。'
        : 'Gateway 把資料送到${current.plainLabel}，但手機連的是'
              '${syncTarget.plainLabel}。按「同步」讓 Gateway 改送到'
              '${placeOf(syncTarget)}。';
  } else if (held) {
    gateway = StatusRow(
      placeOf(current),
      state.testMode ? '⚠ 測試模式' : '⚠ 上傳已暫停',
      StatusTone.warn,
    );
  } else if (waitingJoin && (uploading || backendFresh)) {
    // Connected, as the one-line summary says; not 「資料上傳中」.
    gateway = StatusRow(placeOf(current), uploadHeldStatus, StatusTone.ok);
  } else if (uploading || backendFresh) {
    // Round 28: 「先完成配置」 — uploading, but this pile's PTU is not
    // connected yet, so no PTU data so far.
    gateway = StatusRow(
      placeOf(current),
      state.ptuDeferred ? deferredUploadStatus : '✓ 資料上傳中',
      StatusTone.ok,
    );
  } else if (polling) {
    gateway = StatusRow(placeOf(current), '⏳ 連線中…', StatusTone.pending);
  } else if (config['mqtt_connected'] == false ||
      state.uploadWatch == UploadWatch.gaveUp ||
      state.uploadWatch == UploadWatch.linkLost) {
    gateway = StatusRow(placeOf(current), '✗ 連不上', StatusTone.bad);
  } else {
    gateway = StatusRow(placeOf(current), '？ 未確認', StatusTone.neutral);
  }

  // The gateway's own address, when it reported one (get_net_status).
  final gatewayIp = net['wifi_state'] == 'got_ip'
      ? (net['ip']?.toString() ?? '')
      : '';
  final wifi = state.wifi;
  // Known lack of Wi-Fi explains every missing upload, so it is the main
  // hint even when Bluetooth dropped too (the last Wi-Fi state is known).
  final noWifi =
      !uploading &&
      (wifi == WifiVerdict.failed || wifi == WifiVerdict.notConfigured);
  if (noWifi) {
    if (current != null || legacy) {
      gateway = StatusRow(gateway.where, '✗ Wi-Fi 沒連上', StatusTone.bad);
    }
    hint = wifiProblemHint(state);
  } else if (!legacy &&
      current != null &&
      need != SyncNeed.sync &&
      !uploading) {
    // Only a guess (a /16 network also works), so it waits until the
    // upload has had time to come up: polling gave up or ran >= 30 s.
    final waited =
        gateway.tone == StatusTone.bad || (polling && state.uploadSlow);
    final subnet = subnetHint(current, gatewayIp);
    if (waited && subnet != null) {
      hint = subnet;
    } else if (gateway.tone == StatusTone.bad) {
      if (state.uploadWatch == UploadWatch.linkLost) {
        hint = '手機和 Gateway 的藍牙斷了，請靠近 Gateway 後按「結束並重新選擇閘道器」重新連線。';
      } else if (wifi == WifiVerdict.connecting) {
        hint =
            'Gateway 還沒連上 Wi-Fi，請稍候；若一直連不上，請確認 Wi-Fi 名稱和密碼'
            '（可用「保留站點，重設 Wi-Fi」）。';
      } else {
        hint = uploadCheckHint(current);
      }
    }
  }
  if (held && gateway.tone == StatusTone.warn && !noWifi) {
    hint = state.testMode ? testModeStatusHint : uploadPausedStatusHint;
  }
  if (need == SyncNeed.invalid) hint = app.error;
  if (state.uploadWatch == UploadWatch.linkLost) {
    if (!noWifi) {
      gateway = StatusRow(
        gateway.where,
        relinkBack(state) ? '？ 上傳狀態待確認' : '？ 藍牙已中斷，上傳狀態待確認',
        StatusTone.warn,
      );
    }
    hint = wifi == WifiVerdict.failed || wifi == WifiVerdict.notConfigured
        ? wifiProblemHint(state)
        : linkLostHint(state);
  }
  if (hint == null && phone.tone == StatusTone.bad) {
    hint = env.environment == BackendEnv.local
        ? '手機連不到測試主機：請確認電腦上的測試主機是否開著，且手機和電腦連同一個 Wi-Fi。'
        : '手機連不到${env.label}，請確認手機可以上網。';
  }
  // 其他網址 the APP cannot map: show the gateway as is, never claim a match.
  if (hint == null &&
      !legacy &&
      current != null &&
      app.target == null &&
      app.error == null) {
    hint = 'APP 無法從這個網址判斷 Gateway 該送到哪裡，這裡只顯示 Gateway 目前的設定，不會自動切換。';
  }

  final shipWarning = state.step >= 7 && current?.isLocal == true;
  // The network check (step 2, not passed yet) shows it in its Wi-Fi item.
  final wifiWeak = state.step == 2 && !state.checkPassed
      ? null
      : weakWifiWarning(net);
  final summary =
      phone.tone == StatusTone.ok &&
          gateway.tone == StatusTone.ok &&
          hint == null &&
          wifiWeak == null
      ? '✓ ${env.label}：手機與 Gateway 都已連上'
      : null;
  final disc = wifi == WifiVerdict.ok ? null : wifiDiscDetail(net);
  final bootCount = bootCountOf(net);

  final details = <String>[
    '手機連線的後端：${env.base.isEmpty ? '（未設定）' : env.base}',
    '後端健康檢查（GET /healthz）：${demo ? '模擬' : _probeText(probe)}',
    if (legacy)
      'Gateway 上傳目標：正式站（韌體 ${config['fw_version'] ?? '未知'} 不支援切換）'
    else if (current != null)
      'Gateway 上傳目標：MQTT ${current.isLocal ? '本地' : '正式站'} '
          '${current.host.isEmpty ? '' : current.host}:${current.port}（TLS）'
    else
      'Gateway 上傳目標：${unconfirmed ? '未確認（切換結果尚未讀回）' : '無法辨識（${config['mqtt_target']}）'}',
    '${state.uploadWatch == UploadWatch.linkLost ? '中斷前最後讀到的 MQTT 連線' : 'MQTT 連線'}：${switch (config['mqtt_connected']) {
      true => '已連線',
      false => '未連線',
      _ => '未知',
    }}',
    if (net.isNotEmpty || config['wifi_ssid'] != null)
      'Gateway 網路：Wi-Fi「${net['ssid'] ?? config['wifi_ssid'] ?? ''}」'
          '${gatewayIp.isEmpty ? '' : ' · IP $gatewayIp'}'
          '${net['rssi'] is num && net['rssi'] != 0 ? ' · 訊號 ${net['rssi']} dBm${isWeakWifiRssi(net['rssi']) ? '（偏弱）' : ''}' : ''}'
          '${net['wifi_state'] == null ? '' : ' · ${wifiStateText(net['wifi_state'])}'}',
    ?disc,
    if (bootCount != null)
      'Gateway 開機次數：$bootCount'
          '${net['reset_reason'] is String ? '（上次開機原因：${resetReasonText(net['reset_reason'])}）' : ''}',
    '韌體版本：${config['fw_version'] ?? '未知'}',
    if (config['mode'] != null)
      '閘道器模式：${state.testMode ? '測試模式（只產生測試資料）' : '正常'}',
    if (config['upload_paused'] is bool)
      '資料上傳：${config['upload_paused'] == true ? '已暫停' : '開啟'}'
          '${config['pause_reason'] is String && (config['pause_reason'] as String).isNotEmpty ? '（${config['pause_reason']}）' : ''}',
    if (current?.isLocal == true)
      '本地 MQTT 連不上時請確認：電腦防火牆已開放 TCP ${current!.port}、'
          '本地 MQTT broker 已啟動，且 broker 憑證包含 ${current.host}。',
    if (app.error != null) app.error!,
  ];

  return ConnectionStatus(
    phone: phone,
    gateway: gateway,
    hint: hint,
    need: need,
    syncTarget: syncTarget,
    shipWarning: shipWarning,
    summary: summary,
    details: details,
    wifiWeak: wifiWeak,
  );
}
