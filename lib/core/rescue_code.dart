/// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §3): the error codes the
/// back office's rescue page shows a flow card for. The wire names are the
/// contract — they must equal the backend's `field_cards.FIELD_CODES` word
/// for word (§3.1 「碼表的單一來源」).
///
/// Pure Dart (no application layer) so every rule can be unit-tested.
library;

import 'gateway_net.dart';
import 'protocol.dart';

enum RescueCode {
  // Phone and Bluetooth.
  phoneBtOff('PHONE_BT_OFF', '手機藍牙沒開'),
  phonePermission('PHONE_PERMISSION', 'APP 沒有藍牙／定位權限'),
  gwNotFound('GW_NOT_FOUND', '手機找不到閘道器'),
  bleConnectFail('BLE_CONNECT_FAIL', '手機連不上閘道器（藍牙錯誤）'),
  bleLinkDrop('BLE_LINK_DROP', '手機和閘道器的藍牙斷了'),
  bleReconnectFail('BLE_RECONNECT_FAIL', '重新連線失敗'),
  // Gateway.
  gwRebooted('GW_REBOOTED', '閘道器剛重新啟動'),
  gwBusy('GW_BUSY', '閘道器忙碌（已自動重試 20 秒）'),
  gwLowMemory('GW_LOW_MEMORY', '閘道器記憶體不足'),
  gwAuthRefused('GW_AUTH_REFUSED', '閘道器拒絕指令（一次性密碼或時間未同步）'),
  gwRejected('GW_REJECTED', '閘道器回報失敗'),
  gwFull('GW_FULL', '這台閘道器已滿'),
  cmdTimeout('CMD_TIMEOUT', '閘道器沒有回應'),
  fwTooOld('FW_TOO_OLD', '韌體太舊，不支援這個功能'),
  // Wi-Fi and upload.
  wifiPassword('WIFI_PASSWORD', 'Wi-Fi 密碼可能錯'),
  wifiNotFound('WIFI_NOT_FOUND', '閘道器找不到這個 Wi-Fi'),
  wifiWeak('WIFI_WEAK', 'Wi-Fi 訊號弱或基地台拒絕'),
  wifiUnknown('WIFI_UNKNOWN', 'Wi-Fi 沒連上（原因不明）'),
  uploadNotStarted('UPLOAD_NOT_STARTED', 'Wi-Fi 已連上，但資料還沒送到後台'),
  uploadTarget('UPLOAD_TARGET', '閘道器資料送錯地方（跟手機連的後台不同）'),
  // Identity.
  identityConflict('IDENTITY_CONFLICT', '站號已被別台使用'),
  identityReplace('IDENTITY_REPLACE', '取代舊機沒完成'),
  // PTU.
  ptuNoneFound('PTU_NONE_FOUND', '掃不到 PTU'),
  ptuConnectFail('PTU_CONNECT_FAIL', '閘道器連不上 PTU'),
  ptuNoResponse('PTU_NO_RESPONSE', 'PTU 沒回應'),
  ptuWrongDevice('PTU_WRONG_DEVICE', '編號寫到別台，或回讀不符'),
  ptuResidual('PTU_RESIDUAL', '有 PTU 帶舊編號，或屬於其他閘道器'),
  directPick('DIRECT_PICK', '直連選台失敗'),
  // Monitoring, verification, backend.
  monitorUnconfirmed('MONITOR_UNCONFIRMED', '還沒確認閘道器已恢復監控'),
  verifyIncomplete('VERIFY_INCOMPLETE', '有 PTU 資料沒進來'),
  backendDown('BACKEND_DOWN', 'APP 連不到後台'),
  backendAuth('BACKEND_AUTH', '後台登入失效'),
  gwNotInBackend('GW_NOT_IN_BACKEND', '後台沒有這台閘道器的資料'),
  // Other.
  appUnexpected('APP_UNEXPECTED', 'APP 發生未預期錯誤'),
  stepStuck('STEP_STUCK', '同一步停太久'),
  helpOnly('HELP_ONLY', '畫面沒有錯誤，現場主動求助');

  const RescueCode(this.wire, this.label);

  /// Upper-case name sent as `error_code` / `error.code`.
  final String wire;

  /// Round 24: the code in words for the installer (the §3.2 card title) —
  /// the help sheet shows this, never [wire] (field round 24: 「狀況代碼：
  /// HELP_ONLY」). The wire name stays in the sheet's details and in what
  /// goes to the back office.
  final String label;

  /// The code whose [wire] is [wire]; null for none (or an unknown one).
  static RescueCode? ofWire(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// The Wi-Fi code for a firmware `wifi_last_disc_reason` (null: the
/// firmware gave none, [RescueCode.wifiUnknown]).
RescueCode wifiRescueCode(int? reason) => switch (wifiFailKindOf(reason)) {
  WifiFailKind.password => RescueCode.wifiPassword,
  WifiFailKind.notFound => RescueCode.wifiNotFound,
  WifiFailKind.weakOrOther => RescueCode.wifiWeak,
  null => RescueCode.wifiUnknown,
};

/// Rule 25: a step 8 PTU that failed after its automatic retries, from the
/// text on its row (the controller's `ptuFailureText`, `wrongDeviceText`,
/// read-back mismatch …) — the gateway could not connect to it, it did not
/// answer, or the number went to / read back from the wrong device.
RescueCode ptuAssignRescueCode(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('錯誤裝置') ||
      lower.contains('回讀編號') ||
      lower.contains('裝置回報編號')) {
    return RescueCode.ptuWrongDevice;
  }
  if (lower.contains('連線失敗') ||
      lower.contains('133') ||
      lower.contains('connect') ||
      lower.contains('discovery') ||
      lower.contains('gatt')) {
    return RescueCode.ptuConnectFail;
  }
  return RescueCode.ptuNoResponse;
}

const _linkDropCodes = {'phone_link_lost', 'disconnected', 'not_connected'};
const _authRefusedCodes = {
  'otp_enabled',
  'otp_required',
  'otp_invalid',
  'otp_locked',
  'otp_reused',
  'time_not_synced',
  'expired',
};
const _uploadTargetCodes = {
  'target_readback',
  'upload_target',
  'target_unsupported',
};
const _directPickCodes = {
  'direct_no_ptu',
  'direct_pick_missing',
  'direct_switch_failed',
  'direct_threshold_not_saved',
  'identify_no_ptu',
};
const _backendDownCodes = {
  'network',
  'backend_unavailable',
  'bad_response',
  'https_required',
  'api',
};

/// §3.1 rules 1–28, first match wins; null for rule 27 (the installer
/// cancelled — nothing to report).
///
/// [rebooted]: the gateway restarted during this run (the controller's
/// `_rebootedAfterTimeout()`, or a restart notice that appeared meanwhile).
/// [safe]: `_safeStop()` (false: monitoring not confirmed back on).
/// [ctlStep]: the controller's step (0–7). [assignFailTexts]: step 8 PTU
/// rows that failed (rule 25).
RescueCode? rescueCodeOf(
  GatewayFailure f, {
  required bool rebooted,
  required bool? safe,
  required int ctlStep,
  Iterable<String> assignFailTexts = const [],
}) {
  final code = f.code;
  if (code == 'cancelled') return null;
  if (rebooted) return RescueCode.gwRebooted;
  // Round 28: 〔先完成配置〕 not confirmed by the gateway.
  // Round 30: step 9's in-service check (fleet_joined) did not pass.
  if (safe == false ||
      code == 'monitor_unconfirmed' ||
      code == 'direct_defer_unconfirmed' ||
      code == 'fleet_unconfirmed') {
    return RescueCode.monitorUnconfirmed;
  }
  if (code == 'bluetooth_off') return RescueCode.phoneBtOff;
  if (code == 'permission' || code == 'location_off') {
    return RescueCode.phonePermission;
  }
  if (code == 'ble_error') return RescueCode.bleConnectFail;
  if (_linkDropCodes.contains(code)) return RescueCode.bleLinkDrop;
  if (code == 'reconnect_failed' || code == 'target_reconnect') {
    return RescueCode.bleReconnectFail;
  }
  if (f.fromGateway &&
      '$code ${f.detail ?? ''}'.toLowerCase().contains('low_memory')) {
    return RescueCode.gwLowMemory;
  }
  if (code == 'busy' || code == 'not_ready') return RescueCode.gwBusy;
  if (_authRefusedCodes.contains(code)) return RescueCode.gwAuthRefused;
  if (code == 'wifi_failed') {
    return wifiRescueCode(wifiFailedReason(f.detail));
  }
  if ((code == 'target_mismatch' && !f.fromGateway) ||
      _uploadTargetCodes.contains(code)) {
    return RescueCode.uploadTarget;
  }
  if (code == 'conflict' || code == 'new_site_required') {
    return RescueCode.identityConflict;
  }
  if (code == 'replace_unsupported' || code == 'replace_pending') {
    return RescueCode.identityReplace;
  }
  if (code == 'no_devices') return RescueCode.ptuNoneFound;
  if (code == 'gateway_full') return RescueCode.gwFull;
  if (_directPickCodes.contains(code)) return RescueCode.directPick;
  if (code == 'direct_unsupported' || code == 'identify_unsupported') {
    return RescueCode.fwTooOld;
  }
  if (code == 'incomplete') return RescueCode.verifyIncomplete;
  if (code == 'authentication') return RescueCode.backendAuth;
  // 09-28: the station is archived in the back office (GC 刪除).
  if (f.gatewayNotFound || code == 'identity_archived') {
    return RescueCode.gwNotInBackend;
  }
  if (_backendDownCodes.contains(code) && !f.fromGateway) {
    return RescueCode.backendDown;
  }
  if (code == 'timeout' && !f.fromGateway) {
    if (ctlStep == 3) return RescueCode.uploadNotStarted;
    if (ctlStep == 5 && assignFailTexts.isNotEmpty) {
      return ptuAssignRescueCode(assignFailTexts.first);
    }
    return RescueCode.cmdTimeout;
  }
  if (ctlStep == 5 && assignFailTexts.isNotEmpty) {
    return ptuAssignRescueCode(assignFailTexts.first);
  }
  if (f.fromGateway) return RescueCode.gwRejected;
  return RescueCode.appUnexpected;
}
