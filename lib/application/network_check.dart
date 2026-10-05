/// 「Gateway 網路體檢」: the gated phase right after connecting (step 2,
/// before the station choice) — Wi-Fi, upload target, then data upload —
/// and the order of the steps as the installer sees them.
///
/// Pure Dart so every wording can be unit-tested without widgets.
library;

import '../core/gateway_identity.dart';
import '../core/gateway_net.dart';
import '../core/mqtt_target.dart';
import '../l10n/l10n.dart';
import 'backend_environment.dart';
import 'commissioning_controller.dart';
import 'connection_status.dart';

/// Steps in the order the installer sees them. The controller keeps its own
/// step numbers (0–7); [displayStep] maps them here: the network check is
/// step 2 before the station choice, and the old 確認上線 (step 3) is the
/// backend side of 確認資料上傳.
///
/// i18n：畫面用 [stepLabels]（目前語言）；上傳後台的 field `step_label`
/// 用 `stepLabelsIn(L10n.zh)`（docs/i18n.md §6）。
List<String> get stepLabels => stepLabelsIn(L10n.current);

/// [stepLabels] in [l10n].
List<String> stepLabelsIn(AppLocalizations l10n) => [
  l10n.networkCheck_stepPrepare,
  l10n.networkCheck_stepFindGateway,
  l10n.networkCheck_stepNetworkCheck,
  l10n.networkCheck_stepAlignTarget,
  l10n.networkCheck_stepConfirmUpload,
  l10n.networkCheck_stepChooseSite,
  l10n.networkCheck_stepChoosePtu,
  l10n.networkCheck_stepStartMonitoring,
  l10n.networkCheck_stepVerifyData,
  l10n.common_done,
];

/// The 「not sure」 mark of a [CheckLine] (a symbol, not a word).
const _unsureMark = '？'; // i18n-keep-zh（全形問號是符號，不翻）

enum CheckStage { wifi, target, upload }

/// One line of the check: a mark (✓ ⏳ ✗ ⚠ ？ —) and plain words.
class CheckLine {
  const CheckLine(this.mark, this.text, this.tone);
  final String mark, text;
  final StatusTone tone;
  String get line => '$mark $text';
}

class NetworkCheck {
  const NetworkCheck({
    required this.wifi,
    required this.target,
    required this.upload,
    required this.wifiVerdict,
    required this.wifiOk,
    required this.targetOk,
    required this.uploadOk,
    required this.need,
    required this.syncTarget,
    required this.uploadHint,
    required this.canSkip,
    this.wifiWeak,
    this.testMode = false,
    this.uploadPaused = false,
  });

  /// Round 26: the gateway is in test mode (the page shows the card with
  /// 〔切回正常模式〕); the upload item is not passed.
  final bool testMode;

  /// Round 26: a gateway in service with its upload paused — the upload
  /// item offers 〔恢復上傳〕 and is not passed.
  final bool uploadPaused;
  final CheckLine wifi, target, upload;

  /// Joined, but the signal is below [weakWifiRssiDbm]: the red warning with
  /// advice ([weakWifiText]); null otherwise. Advice only — it does not
  /// block the check.
  final String? wifiWeak;
  final WifiVerdict wifiVerdict;
  final bool wifiOk, targetOk, uploadOk;

  /// What 對準上傳目標 would do ([SyncNeed.sync]: switch to [syncTarget]).
  final SyncNeed need;
  final MqttTarget? syncTarget;

  /// What to check when the upload has not started (null: nothing to say).
  final String? uploadHint;

  /// Nothing is pending any more (or the flow is offline) and the check has
  /// not passed, so continuing without it may be offered where the next page
  /// does not verify data.
  final bool canSkip;

  bool get ready => wifiOk && targetOk && uploadOk;

  /// The first item that has not passed (upload when all have).
  CheckStage get stage => !wifiOk
      ? CheckStage.wifi
      : !targetOk
      ? CheckStage.target
      : CheckStage.upload;

  /// The Wi-Fi is known not to work (not just still joining).
  bool get wifiProblem =>
      wifiVerdict == WifiVerdict.failed ||
      wifiVerdict == WifiVerdict.notConfigured;

  /// Why 「沿用目前站點」 cannot be used now (null when it can).
  String? get reuseBlockedReason => ready
      ? null
      : testMode
      ? L10n.current.networkCheck_reuseTestMode
      : uploadPaused && wifiOk && targetOk
      ? L10n.current.networkCheck_reuseUploadPaused
      : !wifiOk
      ? L10n.current.networkCheck_reuseNoWifi
      : !targetOk
      ? L10n.current.networkCheck_reuseTargetMismatch
      : L10n.current.networkCheck_reuseNotUploading;
}

NetworkCheck networkCheck({
  required CommissionState state,
  required BackendEnvState env,
}) {
  final config = state.config;
  final app = env.uploadTarget;
  final (need, syncTarget) = uploadSyncNeed(state, app);
  final current = parseMqttTarget(config);
  final supported = state.netCheckSupported;
  final verdict = supported ? state.wifi : WifiVerdict.unknown;
  final ssid = gatewaySsid(state.net, config['wifi_ssid']);
  final polling = state.uploadWatch == UploadWatch.polling;
  final l10n = L10n.current;

  // 1. Wi-Fi.
  final CheckLine wifi;
  final bool wifiOk;
  if (!supported) {
    wifi = CheckLine(
      _unsureMark,
      l10n.networkCheck_wifiUnsupported(
        '${config['fw_version'] ?? l10n.common_unknown}',
      ),
      StatusTone.neutral,
    );
    wifiOk = true;
  } else {
    wifiOk = verdict == WifiVerdict.ok;
    wifi = switch (verdict) {
      WifiVerdict.ok => CheckLine('✓', wifiOkText(ssid), StatusTone.ok),
      WifiVerdict.connecting => CheckLine(
        '⏳',
        wifiConnectingText,
        StatusTone.pending,
      ),
      WifiVerdict.failed || WifiVerdict.notConfigured => CheckLine(
        '✗',
        wifiProblemText(ssid, reason: wifiDiscReasonOf(state.net)),
        StatusTone.bad,
      ),
      WifiVerdict.unknown =>
        polling
            ? CheckLine('⏳', l10n.networkCheck_wifiReading, StatusTone.pending)
            : CheckLine(
                _unsureMark,
                l10n.networkCheck_wifiNotRead,
                StatusTone.neutral,
              ),
    };
  }

  // 2. Upload target.
  final CheckLine target;
  final bool targetOk;
  switch (need) {
    case SyncNeed.sync:
      targetOk = false;
      target = current == null
          ? CheckLine(
              _unsureMark,
              l10n.networkCheck_targetUnknownSync(placeOf(syncTarget!)),
              StatusTone.warn,
            )
          : CheckLine(
              '⚠',
              l10n.networkCheck_targetMismatch(
                current.plainLabel,
                syncTarget!.plainLabel,
              ),
              StatusTone.warn,
            );
    case SyncNeed.invalid:
      targetOk = false;
      target = CheckLine(
        '✗',
        l10n.networkCheck_targetInvalid('${app.error}'),
        StatusTone.bad,
      );
    case SyncNeed.legacy:
      // Cannot be switched; the data verification decides.
      targetOk = true;
      target = CheckLine(
        '⚠',
        legacyTargetText(config['fw_version']),
        StatusTone.warn,
      );
    case SyncNeed.none:
      targetOk = true;
      if (!reportsMqttTarget(config)) {
        target = CheckLine(
          '✓',
          l10n.networkCheck_targetProductionFixed,
          StatusTone.ok,
        );
      } else if (current == null) {
        target = CheckLine(
          _unsureMark,
          l10n.networkCheck_targetUnknown,
          StatusTone.neutral,
        );
      } else if (app.target == null) {
        target = CheckLine(
          _unsureMark,
          l10n.networkCheck_targetUndecidable(current.plainLabel),
          StatusTone.neutral,
        );
      } else {
        target = CheckLine(
          '✓',
          l10n.networkCheck_targetMatch(current.plainLabel),
          StatusTone.ok,
        );
      }
  }

  // 3. Data upload (the gateway's own MQTT state over Bluetooth).
  final uploading = config['mqtt_connected'] == true;
  final late =
      state.uploadLate ||
      state.uploadWatch == UploadWatch.gaveUp ||
      (!polling && config['mqtt_connected'] == false);
  final gatewayIp = state.net['wifi_state'] == 'got_ip'
      ? (state.net['ip']?.toString() ?? '')
      : '';
  String? hint;
  final CheckLine upload;
  bool uploadOk = false;
  if (state.uploadWatch == UploadWatch.linkLost) {
    upload = CheckLine('✗', l10n.networkCheck_uploadLinkLost, StatusTone.bad);
    hint = l10n.networkCheck_uploadLinkLostHint;
  } else if (state.testMode) {
    // Round 26 (field: 「✓ 資料上傳中」 from a gateway in test mode).
    upload = CheckLine('⚠', testModeUploadText, StatusTone.warn);
  } else if (state.uploadPaused) {
    // Round 26 (field: 「✓ 資料上傳中」 with the upload paused, 0 rows).
    upload = CheckLine('⚠', uploadPausedText, StatusTone.warn);
  } else if (!supported) {
    upload = CheckLine(
      _unsureMark,
      l10n.networkCheck_uploadUnsupported,
      StatusTone.neutral,
    );
    uploadOk = true;
  } else if (uploading &&
      state.uploadWatch != UploadWatch.linkLost &&
      uploadHeldUntilJoin(config)) {
    // Round 28 (field: a new identity — upload paused until join_fleet —
    // read 「✓ 資料上傳中」): connected to the broker is heartbeats only
    // until the commissioning sends join_fleet; on purpose, so the check
    // passes, in words that say so.
    upload = CheckLine('✓', uploadHeldText, StatusTone.ok);
    uploadOk = true;
  } else if (uploading && state.uploadWatch != UploadWatch.linkLost) {
    upload = CheckLine('✓', l10n.networkCheck_uploading, StatusTone.ok);
    uploadOk = true;
  } else if (!wifiOk) {
    upload = CheckLine(
      '—',
      l10n.networkCheck_uploadAfterWifi,
      StatusTone.neutral,
    );
  } else if (!targetOk) {
    upload = CheckLine(
      '—',
      l10n.networkCheck_uploadAfterTarget,
      StatusTone.neutral,
    );
  } else if (late) {
    upload = CheckLine('✗', l10n.networkCheck_uploadNotStarted, StatusTone.bad);
    final place = current ?? const MqttTarget.production();
    hint =
        subnetHint(
          place,
          gatewayIp,
          wifiAction: l10n.networkCheck_wifiResetAction,
        ) ??
        uploadCheckHint(place);
  } else if (polling) {
    upload = CheckLine(
      '⏳',
      l10n.networkCheck_uploadWaiting,
      StatusTone.pending,
    );
    // Another subnet is only a guess, so it waits like the status panel.
    if (state.uploadSlow && current != null) {
      hint = subnetHint(
        current,
        gatewayIp,
        wifiAction: l10n.networkCheck_wifiResetAction,
      );
    }
  } else {
    upload = CheckLine(
      _unsureMark,
      l10n.networkCheck_uploadNotConfirmed,
      StatusTone.neutral,
    );
  }

  final pending =
      wifi.tone == StatusTone.pending || upload.tone == StatusTone.pending;
  final ready = wifiOk && targetOk && uploadOk;
  return NetworkCheck(
    wifi: wifi,
    target: target,
    upload: upload,
    wifiVerdict: verdict,
    wifiOk: wifiOk,
    targetOk: targetOk,
    uploadOk: uploadOk,
    need: need,
    syncTarget: syncTarget,
    uploadHint: hint,
    canSkip: !ready && (state.offline || !pending) && !state.testMode,
    wifiWeak: supported && wifiOk ? weakWifiWarning(state.net) : null,
    testMode: state.testMode,
    uploadPaused: state.uploadPaused,
  );
}

/// 1.0.0+15: the Wi-Fi form opened by 〔重設 Wi-Fi〕 on the check — a station
/// kept (`wifi_only`) or a gateway not in service fixing its network before
/// its station ([wifiFirstKey]). Part of the network check, never shown as
/// 「站點選擇」.
bool wifiFormOfCheck(CommissionState s) =>
    s.step == 2 &&
    s.checkPassed &&
    (s.config['wifi_only'] == true || s.config[wifiFirstKey] == true);

/// Index into [stepLabels] for the controller state.
int displayStep(CommissionState s, BackendEnvState env) => switch (s.step) {
  0 => 0,
  1 => 1,
  2 when wifiFormOfCheck(s) => 2,
  2 => s.checkPassed ? 5 : 2 + networkCheck(state: s, env: env).stage.index,
  3 => 4,
  4 => 6,
  5 => 7,
  6 => 8,
  _ => 9,
};
