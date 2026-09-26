/// A gateway restart the APP did not ask for: firmware 1.7.6+ counts every
/// boot in NVS (`boot_count`, in get_config and get_net_status) and reports
/// why the last one happened (`reset_reason`, get_net_status and the
/// heartbeat). A count that went up between two reads of the same gateway
/// means it restarted in between — after a command timed out or the phone's
/// Bluetooth link dropped, that is the real cause, not the PTU.
///
/// Pure Dart so every wording can be unit-tested without widgets.
library;

/// `boot_count` of a get_config / get_net_status result; null when the
/// firmware does not report it (before 1.7.6) or it is not a count.
int? bootCountOf(Map<String, dynamic> source) {
  final raw = source['boot_count'];
  return raw is num && raw >= 0 ? raw.toInt() : null;
}

/// `reset_reason` (firmware `boot_info.c`: the `esp_reset_reason()` name, or
/// `ble_stack_stuck` since 1.7.27) in plain words for the installer — the
/// raw code is never shown.
String resetReasonText(Object? raw) => switch (raw) {
  'ble_stack_stuck' => '藍牙功能卡住，閘道器自動重新啟動修復',
  'panic' => '閘道器程式發生錯誤，自動重新啟動',
  'task_wdt' || 'int_wdt' || 'wdt' => '閘道器程式卡住，看門狗保護機制自動重新啟動',
  'cpu_lockup' => '閘道器處理器卡住，自動重新啟動',
  'brownout' => '供電電壓不足（電源不穩或變壓器太弱）',
  'pwr_glitch' => '電源瞬間不穩',
  'poweron' => '曾經斷電後重新上電',
  'ext' => '有人按了重置鍵',
  'sw' => '收到重新啟動指令或設定變更',
  'deepsleep' => '從省電休眠中醒來',
  'usb' || 'jtag' => '接上電腦時被重置',
  _ => '原因不明',
};

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
String gatewayRebootText(GatewayReboot reboot) {
  final many = reboot.times > 1;
  return '閘道器剛重新啟動（原因：${resetReasonText(reboot.reason)}'
      '${many ? '；期間共重新啟動 ${reboot.times} 次' : ''}）。'
      '這不是 PTU 故障，閘道器上已完成的設定都會保留。'
      'APP 已重新連上，請從目前的步驟繼續，不用從頭開始，也不要拔電或重複按。'
      '${many ? '若短時間內一再重新啟動，請拍下這個畫面回報。' : ''}';
}

/// A command timed out because the gateway restarted meanwhile (the notice
/// above explains why).
const gatewayRebootRetryText = '剛才的操作因閘道器重新啟動而中斷（不是 PTU 故障），請再按一次剛才的按鈕繼續。';
