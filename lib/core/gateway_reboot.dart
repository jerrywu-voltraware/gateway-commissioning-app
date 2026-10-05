/// A gateway restart the APP did not ask for: firmware 1.7.6+ counts every
/// boot in NVS (`boot_count`, in get_config and get_net_status) and reports
/// why the last one happened (`reset_reason`, get_net_status and the
/// heartbeat). A count that went up between two reads of the same gateway
/// means it restarted in between — after a command timed out or the phone's
/// Bluetooth link dropped, that is the real cause, not the PTU.
///
/// Pure Dart so every wording can be unit-tested without widgets.
///
/// i18n：[resetReasonText]／[gatewayRebootText] 也上傳後台（field 報告的
/// `error_message`），上傳端傳 `l10n: L10n.zh`；畫面用預設的 [L10n.current]。
library;

import '../l10n/l10n.dart';

/// `boot_count` of a get_config / get_net_status result; null when the
/// firmware does not report it (before 1.7.6) or it is not a count.
int? bootCountOf(Map<String, dynamic> source) {
  final raw = source['boot_count'];
  return raw is num && raw >= 0 ? raw.toInt() : null;
}

/// `reset_reason` (firmware `boot_info.c`: the `esp_reset_reason()` name, or
/// `ble_stack_stuck` since 1.7.27) in plain words for the installer — the
/// raw code is never shown.
///
/// [l10n]: 預設畫面語言；上傳後台用 [L10n.zh]。
String resetReasonText(Object? raw, {AppLocalizations? l10n}) {
  final t = l10n ?? L10n.current;
  return switch (raw) {
    'ble_stack_stuck' => t.gatewayReboot_reasonBleStackStuck,
    'panic' => t.gatewayReboot_reasonPanic,
    'task_wdt' || 'int_wdt' || 'wdt' => t.gatewayReboot_reasonWatchdog,
    'cpu_lockup' => t.gatewayReboot_reasonCpuLockup,
    'brownout' => t.gatewayReboot_reasonBrownout,
    'pwr_glitch' => t.gatewayReboot_reasonPowerGlitch,
    'poweron' => t.gatewayReboot_reasonPowerOn,
    'ext' => t.gatewayReboot_reasonResetButton,
    'sw' => t.gatewayReboot_reasonSoftware,
    'deepsleep' => t.gatewayReboot_reasonDeepSleep,
    'usb' || 'jtag' => t.gatewayReboot_reasonUsb,
    _ => t.gatewayReboot_reasonUnknown,
  };
}

/// The gateway restarted between two reads: boot_count went [from] → [to].
class GatewayReboot {
  const GatewayReboot({required this.from, required this.to, this.reason});
  final int from, to;

  /// Raw `reset_reason` of the latest boot (null until get_net_status is
  /// read: get_config has boot_count but no reason).
  final String? reason;

  /// Restarts between the two reads (usually 1).
  int get times => to - from;

  GatewayReboot withReason(String? value) =>
      GatewayReboot(from: from, to: to, reason: value);
}

/// The notice after a restart: the cause in plain words, that it is not a
/// PTU fault, and to carry on from the current step.
///
/// [l10n]: 預設畫面語言；上傳後台（`onGatewayReboot`）用 [L10n.zh]。
String gatewayRebootText(GatewayReboot reboot, {AppLocalizations? l10n}) {
  final t = l10n ?? L10n.current;
  final reason = resetReasonText(reboot.reason, l10n: t);
  return reboot.times > 1
      ? t.gatewayReboot_noticeMany(reason, reboot.times)
      : t.gatewayReboot_notice(reason);
}

/// A command timed out because the gateway restarted meanwhile (the notice
/// above explains why).
String get gatewayRebootRetryText => L10n.current.gatewayReboot_retry;
