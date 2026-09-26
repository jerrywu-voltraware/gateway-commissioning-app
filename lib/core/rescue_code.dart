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
  phoneBtOff('PHONE_BT_OFF'),
  phonePermission('PHONE_PERMISSION'),
  gwNotFound('GW_NOT_FOUND'),
  bleConnectFail('BLE_CONNECT_FAIL'),
  bleLinkDrop('BLE_LINK_DROP'),
  bleReconnectFail('BLE_RECONNECT_FAIL'),
  // Gateway.
  gwRebooted('GW_REBOOTED'),
  gwBusy('GW_BUSY'),
  gwLowMemory('GW_LOW_MEMORY'),
  gwAuthRefused('GW_AUTH_REFUSED'),
  gwRejected('GW_REJECTED'),
  gwFull('GW_FULL'),
  cmdTimeout('CMD_TIMEOUT'),
  fwTooOld('FW_TOO_OLD'),
  // Wi-Fi and upload.
  wifiPassword('WIFI_PASSWORD'),
  wifiNotFound('WIFI_NOT_FOUND'),
  wifiWeak('WIFI_WEAK'),
  wifiUnknown('WIFI_UNKNOWN'),
  uploadNotStarted('UPLOAD_NOT_STARTED'),
  uploadTarget('UPLOAD_TARGET'),
  // Identity.
  identityConflict('IDENTITY_CONFLICT'),
  identityReplace('IDENTITY_REPLACE'),
  // PTU.
  ptuNoneFound('PTU_NONE_FOUND'),
  ptuConnectFail('PTU_CONNECT_FAIL'),
  ptuNoResponse('PTU_NO_RESPONSE'),
  ptuWrongDevice('PTU_WRONG_DEVICE'),
  ptuResidual('PTU_RESIDUAL'),
  directPick('DIRECT_PICK'),
  // Monitoring, verification, backend.
  monitorUnconfirmed('MONITOR_UNCONFIRMED'),
  verifyIncomplete('VERIFY_INCOMPLETE'),
  backendDown('BACKEND_DOWN'),
  backendAuth('BACKEND_AUTH'),
  gwNotInBackend('GW_NOT_IN_BACKEND'),
  // Other.
  appUnexpected('APP_UNEXPECTED'),
  stepStuck('STEP_STUCK'),
  helpOnly('HELP_ONLY');

  const RescueCode(this.wire);

  /// Upper-case name sent as `error_code` / `error.code`.
  final String wire;
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
  if (safe == false || code == 'monitor_unconfirmed') {
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
  if (f.gatewayNotFound) return RescueCode.gwNotInBackend;
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
