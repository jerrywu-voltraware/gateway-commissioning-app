/// 「Gateway 網路體檢」: the gated phase right after connecting (step 2,
/// before the station choice) — Wi-Fi, upload target, then data upload —
/// and the order of the steps as the installer sees them.
///
/// Pure Dart so every wording can be unit-tested without widgets.
library;

import '../core/gateway_net.dart';
import '../core/mqtt_target.dart';
import 'backend_environment.dart';
import 'commissioning_controller.dart';
import 'connection_status.dart';

/// Steps in the order the installer sees them. The controller keeps its own
/// step numbers (0–7); [displayStep] maps them here: the network check is
/// step 2 before the station choice, and the old 確認上線 (step 3) is the
/// backend side of 確認資料上傳.
const stepLabels = [
  '準備',
  '找到閘道器',
  'Gateway 網路體檢',
  '對準上傳目標',
  '確認資料上傳',
  '站點選擇',
  '選擇 PTU',
  '開始監控',
  '驗證資料',
  '完成',
];

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
  });
  final CheckLine wifi, target, upload;
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
      : !wifiOk
      ? 'Gateway 還沒連上 Wi-Fi'
      : !targetOk
      ? 'Gateway 的資料還沒送到手機連的地方'
      : 'Gateway 還沒開始上傳資料';
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

  // 1. Wi-Fi.
  final CheckLine wifi;
  final bool wifiOk;
  if (!supported) {
    wifi = CheckLine(
      '？',
      'APP 無法讀取這台 Gateway 的 Wi-Fi（韌體 ${config['fw_version'] ?? '未知'} '
          '較舊），最後的資料驗證會再確認。',
      StatusTone.neutral,
    );
    wifiOk = true;
  } else {
    wifiOk = verdict == WifiVerdict.ok;
    wifi = switch (verdict) {
      WifiVerdict.ok => CheckLine('✓', wifiOkText(ssid), StatusTone.ok),
      WifiVerdict.connecting => const CheckLine(
        '⏳',
        wifiConnectingText,
        StatusTone.pending,
      ),
      WifiVerdict.failed || WifiVerdict.notConfigured => CheckLine(
        '✗',
        wifiProblemText(ssid),
        StatusTone.bad,
      ),
      WifiVerdict.unknown =>
        polling
            ? const CheckLine('⏳', '正在讀取 Gateway 的網路狀態…', StatusTone.pending)
            : const CheckLine(
                '？',
                '還沒讀到 Gateway 的網路狀態，請按「重新檢查」。',
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
              '？',
              '還不確定 Gateway 把資料送到哪裡，要讓它改送到${placeOf(syncTarget!)}。',
              StatusTone.warn,
            )
          : CheckLine(
              '⚠',
              'Gateway 把資料送到${current.plainLabel}，但手機連的是'
                  '${syncTarget!.plainLabel}。',
              StatusTone.warn,
            );
    case SyncNeed.invalid:
      targetOk = false;
      target = CheckLine('✗', '${app.error}請點右上角的環境按鈕修正。', StatusTone.bad);
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
        target = const CheckLine('✓', 'Gateway 的資料送到正式站', StatusTone.ok);
      } else if (current == null) {
        target = const CheckLine(
          '？',
          '還不確定 Gateway 把資料送到哪裡。',
          StatusTone.neutral,
        );
      } else if (app.target == null) {
        target = CheckLine(
          '？',
          'Gateway 的資料送到${current.plainLabel}；APP 無法從這個網址判斷是否一致。',
          StatusTone.neutral,
        );
      } else {
        target = CheckLine(
          '✓',
          'Gateway 的資料送到${current.plainLabel}，和手機一致',
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
  if (!supported) {
    upload = const CheckLine('？', '無法確認，最後的資料驗證會再確認。', StatusTone.neutral);
    uploadOk = true;
  } else if (uploading) {
    upload = const CheckLine('✓', '資料上傳中', StatusTone.ok);
    uploadOk = true;
  } else if (!wifiOk) {
    upload = const CheckLine(
      '—',
      '等 Gateway 連上 Wi-Fi 後再確認',
      StatusTone.neutral,
    );
  } else if (!targetOk) {
    upload = const CheckLine('—', '對準上傳目標後再確認', StatusTone.neutral);
  } else if (state.uploadWatch == UploadWatch.linkLost) {
    upload = const CheckLine('✗', '手機和 Gateway 的藍牙斷了，無法確認。', StatusTone.bad);
    hint = '請靠近 Gateway，按「結束並重新選擇閘道器」重新連線。';
  } else if (late) {
    upload = const CheckLine('✗', 'Gateway 還沒開始上傳資料。', StatusTone.bad);
    final place = current ?? const MqttTarget.production();
    hint =
        subnetHint(place, gatewayIp, wifiAction: '重設 Wi-Fi') ??
        uploadCheckHint(place);
  } else if (polling) {
    upload = const CheckLine(
      '⏳',
      '等待 Gateway 開始上傳資料…（最多約 1 分鐘）',
      StatusTone.pending,
    );
    // Another subnet is only a guess, so it waits like the status panel.
    if (state.uploadSlow && current != null) {
      hint = subnetHint(current, gatewayIp, wifiAction: '重設 Wi-Fi');
    }
  } else {
    upload = const CheckLine('？', '還沒確認資料上傳，請按「重新檢查」。', StatusTone.neutral);
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
    canSkip: !ready && (state.offline || !pending),
  );
}

/// Index into [stepLabels] for the controller state.
int displayStep(CommissionState s, BackendEnvState env) => switch (s.step) {
  0 => 0,
  1 => 1,
  2 => s.checkPassed ? 5 : 2 + networkCheck(state: s, env: env).stage.index,
  3 => 4,
  4 => 6,
  5 => 7,
  6 => 8,
  _ => 9,
};
