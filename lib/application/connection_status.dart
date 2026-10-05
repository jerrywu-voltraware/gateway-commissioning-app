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
import '../l10n/l10n.dart';
import 'backend_environment.dart';
import 'commissioning_controller.dart';

enum StatusTone { ok, pending, bad, warn, neutral }

class StatusRow {
  const StatusRow(this.where, this.status, this.tone, {this.uploading = false});

  /// 本地測試主機 / 正式站 / 其他網址.
  final String where;

  /// ✓ 已連線 / ⏳ 連線中… / ✗ 連不上 / ⚠ 送到別處 … (empty: name only).
  final String status;
  final StatusTone tone;

  /// The gateway row says 「✓ 資料上傳中」 ([uploadingStatusText]): PTU data
  /// is flowing. Logic checks this flag, never the (translated) [status].
  final bool uploading;
}

/// 「✓ 資料上傳中」 of the gateway row ([StatusRow.uploading]).
String get uploadingStatusText => L10n.current.connectionStatus_statusUploading;

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

String placeOf(MqttTarget target) => target.isLocal
    ? L10n.current.connectionStatus_placeLocal
    : L10n.current.backendEnvironment_labelProduction;

/// The gateway is on another /24 than the local test host, or null.
String? subnetHint(MqttTarget current, String gatewayIp, {String? wifiAction}) {
  final gatewayNet = ipv4Prefix24(gatewayIp);
  final hostNet = current.isLocal ? ipv4Prefix24(current.host) : null;
  if (gatewayNet == null || hostNet == null || gatewayNet == hostNet) {
    return null;
  }
  return L10n.current.connectionStatus_subnetHint(
    gatewayNet,
    current.host,
    wifiAction ?? L10n.current.connectionStatus_wifiActionOther,
  );
}

/// What to check when a gateway with Wi-Fi does not upload to [current].
String uploadCheckHint(MqttTarget current) => current.isLocal
    ? L10n.current.connectionStatus_uploadCheckLocal
    : L10n.current.connectionStatus_uploadCheckProduction;

/// Main hint when the gateway has no Wi-Fi: the cause first, then how to
/// get back to 「重設 Wi-Fi」 (after reconnecting Bluetooth if it dropped).
String wifiProblemHint(CommissionState state) {
  final ssid = gatewaySsid(state.net, state.config['wifi_ssid']);
  final reason = wifiDiscReasonOf(state.net);
  final l10n = L10n.current;
  final action = ssid?.isEmpty == true
      ? l10n.connectionStatus_wifiActionSet
      : l10n.connectionStatus_wifiActionReset;
  final next = state.uploadWatch == UploadWatch.linkLost && state.relinking
      ? l10n.connectionStatus_wifiLinkLostRelinking(autoRelinkingText)
      : state.uploadWatch == UploadWatch.linkLost
      ? l10n.connectionStatus_wifiLinkLostReconnect(action)
      : state.step == 2
      ? l10n.connectionStatus_wifiFixHere(action)
      : l10n.connectionStatus_wifiFixReconnect(action);
  return '${wifiProblemText(ssid, reason: reason)}\n$next';
}

/// 「連線狀態」 hint while the phone↔gateway Bluetooth is down. Round 13:
/// while the automatic reconnect runs ([CommissionState.relinking]) it says
/// so instead of asking for a tap; afterwards it names the button actually
/// shown (steps 7 / 8).
String linkLostHint(CommissionState state) {
  // Round 22: back already (the list is read again) — not 「已中斷」 any more.
  final l10n = L10n.current;
  if (relinkBack(state)) {
    return l10n.connectionStatus_linkBack(relinkReloadText);
  }
  if (state.relinking) {
    return l10n.connectionStatus_linkLostRelinking(autoRelinkingText);
  }
  final action = switch (state.step) {
    // Steps 4 and 5 both name 〔重新連線並繼續〕 ([rescanAfterLossLabel]).
    4 || 5 => l10n.connectionStatus_tapButton(rescanAfterLossLabel),
    _ => l10n.connectionStatus_reconnectThenCheck,
  };
  return l10n.connectionStatus_linkLostCannotRead(action);
}

String _envPlace(BackendEnv env) => switch (env) {
  BackendEnv.production => L10n.current.backendEnvironment_labelProduction,
  BackendEnv.local => L10n.current.connectionStatus_placeLocal,
  BackendEnv.custom => L10n.current.backendEnvironment_labelCustom,
};

StatusRow _phoneRow(
  BackendEnvState env, {
  required ProbeResult? probe,
  required bool loggedIn,
  required bool demo,
}) {
  final l10n = L10n.current;
  final where = _envPlace(env.environment);
  final connected = l10n.connectionStatus_statusConnected;
  final unreachable = l10n.connectionStatus_statusUnreachable;
  if (demo) {
    return StatusRow(
      where,
      l10n.connectionStatus_statusConnectedDemo,
      StatusTone.ok,
    );
  }
  if (probe == null) {
    return loggedIn
        ? StatusRow(where, connected, StatusTone.ok)
        : StatusRow(
            where,
            l10n.connectionStatus_statusChecking,
            StatusTone.pending,
          );
  }
  switch (probe.outcome) {
    case ProbeOutcome.healthy:
      return StatusRow(where, connected, StatusTone.ok);
    case ProbeOutcome.degraded:
      return StatusRow(
        where,
        l10n.connectionStatus_statusDbNotReady,
        StatusTone.warn,
      );
    case ProbeOutcome.unreachable:
    case ProbeOutcome.timeout:
      return loggedIn
          ? StatusRow(where, connected, StatusTone.ok)
          : StatusRow(where, unreachable, StatusTone.bad);
    case ProbeOutcome.notBackend:
    case ProbeOutcome.httpError:
      if (loggedIn) return StatusRow(where, connected, StatusTone.ok);
      // A local test host must answer /healthz; other sites may not have it.
      return env.environment == BackendEnv.local
          ? StatusRow(where, unreachable, StatusTone.bad)
          : StatusRow(where, '', StatusTone.neutral);
  }
}

String _probeText(ProbeResult? probe) {
  final l10n = L10n.current;
  return switch (probe?.outcome) {
    null => l10n.connectionStatus_probeChecking,
    ProbeOutcome.healthy =>
      probe!.version == null
          ? l10n.connectionStatus_probeHealthy
          : l10n.connectionStatus_probeHealthyVersion(probe.version!),
    ProbeOutcome.degraded => l10n.connectionStatus_probeDegraded,
    ProbeOutcome.notBackend => l10n.connectionStatus_probeNotBackend(
      '${probe!.status}',
    ),
    ProbeOutcome.httpError => 'HTTP ${probe!.status}',
    ProbeOutcome.timeout => l10n.common_timeout,
    ProbeOutcome.unreachable =>
      probe!.detail == null
          ? l10n.connectionStatus_probeUnreachable
          : l10n.connectionStatus_probeUnreachableDetail(probe.detail!),
  };
}

/// Builds the panel model. [probe] is the `/healthz` result of the APP
/// backend (null while checking), [demo] the simulated system.
ConnectionStatus connectionStatus({
  required BackendEnvState env,
  required CommissionState state,
  ProbeResult? probe,
  bool demo = false,
  DateTime? now,
}) {
  final l10n = L10n.current;
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
    final production = l10n.backendEnvironment_labelProduction;
    gateway = need == SyncNeed.legacy
        ? StatusRow(
            production,
            l10n.connectionStatus_statusElsewhere,
            StatusTone.warn,
          )
        : StatusRow(production, '', StatusTone.neutral);
    if (need == SyncNeed.legacy) hint = legacyTargetText(config['fw_version']);
  } else if (current == null) {
    gateway = polling
        ? StatusRow(
            l10n.connectionStatus_whereChecking,
            l10n.connectionStatus_statusConfirming,
            StatusTone.pending,
          )
        : StatusRow(
            unconfirmed
                ? l10n.connectionStatus_whereUnconfirmed
                : l10n.connectionStatus_whereUnknown,
            l10n.connectionStatus_statusUnconfirmed,
            StatusTone.neutral,
          );
    // One action: 「同步」 settles it when the APP knows the target (no
    // reboot if it already matches); otherwise read it again.
    if (!polling) {
      hint = need == SyncNeed.sync
          ? l10n.connectionStatus_hintUnknownSync(placeOf(syncTarget!))
          : l10n.connectionStatus_hintUnknownReread;
    }
  } else if (need == SyncNeed.sync) {
    gateway = StatusRow(
      placeOf(current),
      l10n.connectionStatus_statusElsewhere,
      StatusTone.warn,
    );
    // Same place (same [MqttTarget.plainLabel]: both production, or the
    // same local host), other port: the difference is in 技術細節.
    final samePlace =
        current.kind == syncTarget!.kind &&
        (!current.isLocal || current.host == syncTarget.host);
    hint = samePlace
        ? l10n.connectionStatus_hintPortMismatch(placeOf(syncTarget))
        : l10n.connectionStatus_hintTargetMismatch(
            current.plainLabel,
            syncTarget.plainLabel,
            placeOf(syncTarget),
          );
  } else if (held) {
    gateway = StatusRow(
      placeOf(current),
      state.testMode
          ? l10n.connectionStatus_statusTestMode
          : l10n.connectionStatus_statusUploadPaused,
      StatusTone.warn,
    );
  } else if (waitingJoin && (uploading || backendFresh)) {
    // Connected, as the one-line summary says; not 「資料上傳中」.
    gateway = StatusRow(placeOf(current), uploadHeldStatus, StatusTone.ok);
  } else if (uploading || backendFresh) {
    // Round 28: 「先完成配置」 — uploading, but this pile's PTU is not
    // connected yet, so no PTU data so far.
    gateway = state.ptuDeferred
        ? StatusRow(placeOf(current), deferredUploadStatus, StatusTone.ok)
        : StatusRow(
            placeOf(current),
            uploadingStatusText,
            StatusTone.ok,
            uploading: true,
          );
  } else if (polling) {
    gateway = StatusRow(
      placeOf(current),
      l10n.connectionStatus_statusConnecting,
      StatusTone.pending,
    );
  } else if (config['mqtt_connected'] == false ||
      state.uploadWatch == UploadWatch.gaveUp ||
      state.uploadWatch == UploadWatch.linkLost) {
    gateway = StatusRow(
      placeOf(current),
      l10n.connectionStatus_statusUnreachable,
      StatusTone.bad,
    );
  } else {
    gateway = StatusRow(
      placeOf(current),
      l10n.connectionStatus_statusUnconfirmed,
      StatusTone.neutral,
    );
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
      gateway = StatusRow(
        gateway.where,
        l10n.connectionStatus_statusWifiDown,
        StatusTone.bad,
      );
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
        hint = l10n.connectionStatus_hintLinkLostReconnect;
      } else if (wifi == WifiVerdict.connecting) {
        hint = l10n.connectionStatus_hintWifiConnecting(
          l10n.connectionStatus_wifiActionOther,
        );
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
        relinkBack(state)
            ? l10n.connectionStatus_statusUploadUnknown
            : l10n.connectionStatus_statusLinkLostUploadUnknown,
        StatusTone.warn,
      );
    }
    hint = wifi == WifiVerdict.failed || wifi == WifiVerdict.notConfigured
        ? wifiProblemHint(state)
        : linkLostHint(state);
  }
  if (hint == null && phone.tone == StatusTone.bad) {
    hint = env.environment == BackendEnv.local
        ? l10n.connectionStatus_hintPhoneNoLocal
        : l10n.connectionStatus_hintPhoneNoBackend(env.label);
  }
  // 其他網址 the APP cannot map: show the gateway as is, never claim a match.
  if (hint == null &&
      !legacy &&
      current != null &&
      app.target == null &&
      app.error == null) {
    hint = l10n.connectionStatus_hintCustomUnknown;
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
      ? l10n.connectionStatus_summary(env.label)
      : null;
  final disc = wifi == WifiVerdict.ok ? null : wifiDiscDetail(net);
  final bootCount = bootCountOf(net);

  final unknown = l10n.common_unknown;
  final rssi = net['rssi'];
  final pauseReason = config['pause_reason'];
  final mqtt = switch (config['mqtt_connected']) {
    true => l10n.connectionStatus_mqttConnected,
    false => l10n.connectionStatus_mqttDisconnected,
    _ => unknown,
  };
  final details = <String>[
    l10n.connectionStatus_detailPhoneBackend(
      env.base.isEmpty ? l10n.connectionStatus_detailNotSet : env.base,
    ),
    l10n.connectionStatus_detailHealth(
      demo ? l10n.connectionStatus_detailDemo : _probeText(probe),
    ),
    if (legacy)
      l10n.connectionStatus_detailTargetLegacy(
        '${config['fw_version'] ?? unknown}',
      )
    else if (current != null)
      current.isLocal
          ? l10n.connectionStatus_detailTargetLocal(
              '${current.host}:${current.port}',
            )
          : l10n.connectionStatus_detailTargetProduction(
              '${current.host}:${current.port}',
            )
    else if (unconfirmed)
      l10n.connectionStatus_detailTargetUnconfirmed
    else
      l10n.connectionStatus_detailTargetUnknown('${config['mqtt_target']}'),
    state.uploadWatch == UploadWatch.linkLost
        ? l10n.connectionStatus_detailMqttLastRead(mqtt)
        : l10n.connectionStatus_detailMqtt(mqtt),
    if (net.isNotEmpty || config['wifi_ssid'] != null)
      l10n.connectionStatus_detailGatewayNet(
            '${net['ssid'] ?? config['wifi_ssid'] ?? ''}',
          ) +
          (gatewayIp.isEmpty ? '' : ' · IP $gatewayIp') +
          (rssi is num && rssi != 0
              ? l10n.connectionStatus_detailSignal('$rssi') +
                    (isWeakWifiRssi(rssi)
                        ? l10n.connectionStatus_detailSignalWeak
                        : '')
              : '') +
          (net['wifi_state'] == null
              ? ''
              : ' · ${wifiStateText(net['wifi_state'])}'),
    ?disc,
    if (bootCount != null)
      l10n.connectionStatus_detailBootCount(bootCount) +
          (net['reset_reason'] is String
              ? l10n.connectionStatus_detailLastReset(
                  resetReasonText(net['reset_reason']),
                )
              : ''),
    l10n.connectionStatus_detailFirmware('${config['fw_version'] ?? unknown}'),
    if (config['mode'] != null)
      state.testMode
          ? l10n.connectionStatus_detailModeTest
          : l10n.connectionStatus_detailModeNormal,
    if (config['upload_paused'] is bool)
      (config['upload_paused'] == true
              ? l10n.connectionStatus_detailUploadPaused
              : l10n.connectionStatus_detailUploadOn) +
          (pauseReason is String && pauseReason.isNotEmpty
              ? l10n.connectionStatus_detailPauseReason(pauseReason)
              : ''),
    if (current?.isLocal == true)
      l10n.connectionStatus_detailLocalMqttCheck(
        '${current!.port}',
        current.host,
      ),
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
