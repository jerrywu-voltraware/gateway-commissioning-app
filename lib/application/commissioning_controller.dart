import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/assign_progress.dart';
import '../core/direct_calibration.dart';
import '../core/direct_mode.dart';
import '../core/gateway_net.dart';
import '../core/gateway_reboot.dart';
import '../core/gateway_topology.dart';
import '../core/ptu_rssi.dart';
import '../core/mqtt_target.dart';
import '../core/protocol.dart';
import '../core/rescue_code.dart';
import '../data/ble_gateway_link.dart';
import '../data/contracts.dart';
import '../data/recent_gateways.dart';
import '../data/dashboard_api.dart';
import '../data/demo_system.dart';
import '../data/ptu_inventory.dart';
import 'backend_environment.dart';
import 'field_report.dart';
import 'network_check.dart';
import 'topology_settings.dart';
import 'verify_diagnosis.dart';

class DemoMode extends Notifier<bool> {
  @override
  bool build() => const bool.fromEnvironment('DEMO_MODE');
  void set(bool value) => state = value;
}

final demoProvider = NotifierProvider<DemoMode, bool>(DemoMode.new);
final demoSystemProvider = Provider((ref) => DemoSystem());
final linkProvider = Provider<GatewayLink>(
  (ref) => ref.watch(demoProvider)
      ? ref.watch(demoSystemProvider)
      : BleGatewayLink(),
);
final apiProvider = Provider<GatewayApi>(
  (ref) =>
      ref.watch(demoProvider) ? ref.watch(demoSystemProvider) : DashboardApi(),
);

/// How [CommissioningController.suggestGateway] found its answer.
enum GatewaySuggestKind {
  /// Confirmed free by the backend (check-identity), or this gateway's own
  /// existing number on the same site.
  online,

  /// Backend unreachable: guessed from BLE peer names instead.
  offline,

  /// Backend reachable, but 1–kMaxGatewayId are all taken for that site.
  full,
}

/// Background polling of the gateway's upload (MQTT) state.
enum UploadWatch {
  /// Not polling (nothing pending, or no gateway connected).
  idle,

  /// Polling get_net_status until the gateway reports it is uploading.
  polling,

  /// Stopped after the time cap without the gateway connecting.
  gaveUp,

  /// Stopped because the BLE link to the gateway dropped.
  linkLost,
}

/// How often and how long the upload state is polled; injectable in tests.
class UploadWatchTiming {
  const UploadWatchTiming({
    this.interval = const Duration(seconds: 5),
    this.cap = const Duration(minutes: 2),
    this.slowAfter = const Duration(seconds: 30),
    this.confirmAfter = const Duration(seconds: 60),
    this.wifiGrace = const Duration(seconds: 20),
  });

  /// [slowAfter]: polling time without upload after which a guess about the
  /// cause (e.g. another subnet) may be shown.
  ///
  /// [confirmAfter]: the network check stops waiting for the upload and
  /// shows what to check instead.
  ///
  /// [wifiGrace]: after a connect or reboot, a gateway that has not joined
  /// its Wi-Fi yet is shown as 「正在連 Wi-Fi」 this long before it counts as
  /// a failure (unless it has been up for [wifiSettleSeconds]).
  final Duration interval, cap, slowAfter, confirmAfter, wifiGrace;
  int get maxTicks => (cap.inMilliseconds / interval.inMilliseconds).ceil();
  int get slowTicks =>
      (slowAfter.inMilliseconds / interval.inMilliseconds).ceil();
  int get lateTicks =>
      (confirmAfter.inMilliseconds / interval.inMilliseconds).ceil();
}

final uploadWatchTimingProvider = Provider<UploadWatchTiming>(
  (ref) => const UploadWatchTiming(),
);

/// Gateway 'busy' (firmware cmd_worker queue full): retry every
/// [busyRetryDelay], at most [busyRetryLimit] times (20 s in total).
const busyRetryDelay = Duration(seconds: 2);
const busyRetryLimit = 10;
const gatewayBusyText = '閘道器忙碌中，等待…';

/// Step 7 idle keep-alive ping interval (no RSSI traffic meanwhile).
const keepAliveInterval = Duration(seconds: 15);

final ptuSignalIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// Gateway network fields copied from get_net_status (firmware cmd_handler.c).
/// Connected PTUs first, then strongest RSSI (missing RSSI last). Used for
/// the default selection, trimming and 「依訊號重新排序」.
int comparePtuForSelection(Map<String, dynamic> a, Map<String, dynamic> b) {
  final connection =
      (b['connected'] == true ? 1 : 0) - (a['connected'] == true ? 1 : 0);
  if (connection != 0) return connection;
  return ((b['rssi'] as num?) ?? -127).compareTo((a['rssi'] as num?) ?? -127);
}

/// Step 8 failure that means the phone↔gateway BLE link is gone (not a PTU
/// problem): the link's own codes, the adapter switched off, or a
/// 'cancelled' raised by the link itself (its epoch was bumped by a
/// disconnect) while the controller's run is still [current].
bool isStep8LinkLoss(Object? error, bool current) =>
    isPhoneLinkFailure(error) ||
    (error is GatewayFailure &&
        (error.code == 'bluetooth_off' ||
            (current && error.code == 'cancelled')));

const gatewayNetKeys = [
  'wifi_state',
  'ip',
  'ssid',
  'rssi',
  'uptime_sec',
  // Firmware 1.7.32: why the Wi-Fi last dropped / failed.
  'wifi_last_disc_reason',
  'wifi_last_disc_age_s',
  // Firmware 1.7.6: restarts ([GatewayReboot]).
  'boot_count',
  'reset_reason',
];

/// 「沿用目前站點」 refused because the gateway cannot upload yet.
const reuseBlockedText =
    'Gateway 還沒連上 Wi-Fi 或還沒開始上傳資料，暫時不能沿用目前站點。'
    '請先用「保留站點，重設 Wi-Fi」，或回到網路體檢確認。';

/// Station kept after a Wi-Fi change: confirm upload before reviewing PTUs.
const uploadNotReadyText =
    '要等 Gateway 連上 Wi-Fi 並開始上傳資料，才能繼續選擇 PTU。'
    '請等「確認資料上傳」出現 ✓，或再重設一次 Wi-Fi。';

/// Step 7 after a backend switch: the earlier result belongs to the old one.
const backendSwitchedDoneText = '已切換連線環境，資料要在新的環境重新確認。';

/// Step 6 after a backend switch.
const backendSwitchedVerifyText = '已切換連線環境，請按「開始資料驗證」重新確認。';

/// PTU tile text when the automatic reset still failed after its retry.
const resetFailedText = '重置失敗（連線逾時），請靠近後重試';

/// 完成頁摘要：「掃到 X 台，本機配置 Y 台」，其他閘道器／重置失敗台數 >0 才顯示。
String commissionSummaryText(CommissionState s) =>
    '掃到 ${s.scannedTotal} 台，本機配置 ${s.ptus.length} 台'
    '${s.pendingNext > 0 ? '，${s.pendingNext} 台屬於其他閘道器' : ''}'
    '${s.resetFailed.isNotEmpty ? '，${s.resetFailed.length} 台重置失敗' : ''}';

/// Saved resume: the user cancelled the backend login.
const resumeWithoutLoginText = '未登入時無法自動收編殘留編號，將以手動模式繼續';

/// 'wifi_failed' after set_wifi, carrying the firmware reason (1.7.32,
/// [wifiDiscReasonOf]) only when it belongs to this attempt: reported no
/// earlier than [sinceSent] ago, and — once the gateway went back to its old
/// network ([ssid] no longer reported) — only if it joined that one again
/// (failing to rejoin an old network says nothing about the new one).
GatewayFailure wifiFailedFrom(
  Map<String, dynamic> net, {
  required String ssid,
  required Duration sinceSent,
}) {
  final reason = wifiDiscReasonOf(
    net,
    notOlderThan: sinceSent + const Duration(seconds: 5),
  );
  final reported = net['ssid'];
  final reverted = reported is String && reported != ssid;
  if (reason == null || (reverted && net['wifi_state'] != 'got_ip')) {
    return const GatewayFailure('wifi_failed');
  }
  return GatewayFailure('wifi_failed', detail: wifiFailedDetail(reason));
}

/// Step 8: automatic retries per PTU after a failed assign_device_id.
const assignRetries = 2;

/// Plain-language reason for a failed PTU command ([error] is a
/// [GatewayFailure], the ack's error/result text, or null).
String ptuFailureText(Object? error) {
  if (isPhoneLinkFailure(error)) return notAssignedLinkText;
  final raw = error is GatewayFailure
      ? '${error.code} ${error.detail ?? ''}'
      : error?.toString() ?? '';
  final text = raw.toLowerCase();
  if (isPtuConnectFailure(error)) {
    return 'PTU 連線失敗，請確認 PTU 電源與距離';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'PTU 沒有回應';
  }
  if (text.contains('not found') || text.contains('not_found')) {
    return 'Gateway 找不到這台 PTU，請重新掃描';
  }
  if (error is GatewayFailure && error.code != 'unexpected') {
    return error.message;
  }
  return 'PTU 設定未完成，請靠近後重試';
}

/// The gateway could not open its Bluetooth link to the PTU (GATT 133,
/// connection / service discovery timeout) — not the phone's link.
bool isPtuConnectFailure(Object? error) {
  if (isPhoneLinkFailure(error)) return false;
  final raw = error is GatewayFailure
      ? '${error.code} ${error.detail ?? ''}'
      : error?.toString() ?? '';
  final text = raw.toLowerCase();
  return text.contains('133') ||
      text.contains('connect') ||
      text.contains('discovery') ||
      text.contains('gatt');
}

/// Round 21: the row status of a failed assign try that is retried by
/// itself: a busy gateway, the gateway's link to the PTU, or anything else.
AssignPhase assignRetryPhase(Object? error) {
  final code = error is GatewayFailure ? error.code : error?.toString();
  if (code?.trim() == 'busy') return AssignPhase.busy;
  return isPtuConnectFailure(error) ? AssignPhase.linkRetry : AssignPhase.retry;
}

/// PTU tile text when step 8 stopped because the phone lost the gateway.
const notAssignedLinkText = '尚未指派（手機與閘道器斷線）';

/// Appends the link's first connect failure type (round 8 analysis aid).
String withFirstFailure(String detail, Object link) {
  final first = link is ConnectDiagnostics ? link.firstConnectFailure : null;
  return first == null ? detail : '$detail\n第一次連線失敗：$first';
}

/// Shown while the phone re-opens the BLE link to the gateway.
const reconnectingText = '正在重新連線閘道器';

/// Step 2 busy text once the BLE link is up and the gateway's first replies
/// (ping, get_config, get_net_status, get_ble_devices) are being read.
const linkConfirmingText = '藍牙已連線，正在確認閘道器回應與設定…';

/// Round 10: step 2 connect and reconnects keep retrying 133 / disconnected
/// for this long before showing the error.
Duration connectPersistence = const Duration(seconds: 60);

/// Pause between two persistent connect attempts.
Duration connectRetryGap = const Duration(milliseconds: 1500);

/// Busy text of the n-th connect attempt (n >= 2).
String connectingAttemptText(int attempt) => '連線中（第 $attempt 次）';

/// Round 18: the phone↔gateway link itself is gone (not a gateway reply).
bool isLinkDrop(Object error) =>
    error is GatewayFailure &&
    !error.fromGateway &&
    (error.code == 'disconnected' || error.code == 'not_connected');

/// Round 24: the gateway refused a command because it is busy (after the
/// automatic retries) or not ready yet — field rescue GW_BUSY; nothing was
/// changed on the gateway side.
bool isGatewayBusyFailure(Object error) =>
    error is GatewayFailure &&
    (error.code == 'busy' || error.code == 'not_ready');

/// Connect failures worth another attempt: GATT 133 / unknownError
/// (ble_error), a dropped link, a timeout.
bool isRetryableConnect(Object error) =>
    error is TimeoutException ||
    (error is GatewayFailure &&
        const {
          'disconnected',
          'ble_error',
          'timeout',
          'not_connected',
          'unexpected',
        }.contains(error.code));

/// Short type of a connect failure for 詳細資訊 (e.g. `ble_error 133`).
String connectFailureType(Object error) {
  if (error is GatewayFailure) {
    final detail = error.detail ?? '';
    return detail.startsWith('133') ? '${error.code} 133' : error.code;
  }
  return error.runtimeType.toString();
}

/// Overall budget for re-opening the phone↔gateway link. Must stay above
/// [BleGatewayLink]'s own worst-case retry budget (51s, see
/// ble_gateway_link.dart) plus headroom for _relink's own overhead; keep it
/// in sync with _reconnectBudget below.
const reconnectBudget = Duration(seconds: 80);

/// Banner after 「重新連線並繼續」 gave up (round 11).
String reconnectFailedAttemptsText(int attempts) =>
    '重新連線失敗（已嘗試 $attempts 次），請靠近閘道器後再按一次';

/// Shown while the phone's Bluetooth was just turned on (「重新連線並繼續」).
const waitingBluetoothText = '等待藍牙就緒';

/// Longest wait for a just-enabled phone Bluetooth before reconnecting.
const bluetoothReadyBudget = Duration(seconds: 10);

/// Done page: before the first health check has an answer.
const healthPendingText = '正在確認資料上傳…';

/// Normalised MAC for comparisons (case and separators ignored).
String macKey(Object? mac) =>
    (mac?.toString() ?? '').toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

bool sameMac(Object? a, Object? b) => macKey(a) == macKey(b);

const wrongDeviceText = '指派到錯誤裝置，請重試';

/// Firmware 1.7.15+ assign ack check: `mac` (the PTU written) and
/// `device_number` must match the request; absent fields (older firmware)
/// keep the old behaviour. Returns the failure reason, or null when fine.
/// `verified` is NOT a failure: the PTU has no read-back characteristic, so
/// firmware always sends false; get_ble_devices read-back decides instead
/// (see [ackNeedsReadback]).
String? assignAckMismatch(Map<String, dynamic> ack, String mac, int id) {
  final written = ack['mac'];
  if (written != null && !sameMac(written, mac)) return wrongDeviceText;
  final number = ack['device_number'];
  // Firmware writes new_id=255 (reset) but the slot's device_number comes
  // back as 0; either value is a match for a reset request.
  if (id == 255) {
    if (number != null &&
        (number is! num || (number.toInt() != 0 && number.toInt() != 255))) {
      return '裝置回報編號 #$number 與指派 #$id 不符，請重試';
    }
    return null;
  }
  if (number != null && (number is! num || number.toInt() != id)) {
    return '裝置回報編號 #$number 與指派 #$id 不符，請重試';
  }
  return null;
}

/// The ack only confirms the write was sent; confirm via read-back.
bool ackNeedsReadback(Map<String, dynamic> ack) => ack['verified'] == false;

String pendingReadbackText(int id) => '已送出 #$id，待回讀確認';

String readbackMismatchText(int actual, int wanted) =>
    '回讀編號為 #$actual，不是指派的 #$wanted，請重試';

/// Display labels for a saved [CommissionState.step] (restore prompt).
const _savedStepLabels = {
  1: '第 2 步（找到閘道器）',
  2: '第 3 步（Gateway 網路體檢）',
  3: '第 5 步（確認資料上傳）',
  4: '第 7 步（選擇 PTU）',
  5: '第 8 步（開始監控）',
  6: '第 9 步（驗證資料）',
};

/// Restore prompt after the APP was killed; [done] are the PTU numbers
/// already assigned, [pending] the selected ones still to configure.
/// Step 8 bottom button: always targets selected-but-not-yet-successfully-
/// assigned PTUs (newly checked ones after a disconnect included; already
/// assigned ones excluded so they are not re-sent).
String configureLabel(CommissionState s) {
  final rest = configureTargets(s).length;
  // Round 12: step 7 link loss — never 「掃描中…」 beside the banner.
  // Round 13: step 8 too — disabled 「重新連線中…」 while the automatic
  // reconnect (or any run on a lost link) runs; 「重新連線並繼續」 only once
  // it gave up.
  if (s.relinking && s.relinkStage == RelinkStage.reloading) {
    return relistingLabel;
  }
  // Round 22: once step 8 assigns again ([RelinkStage.resumed]) the button
  // is the run's own (field round 22: 「重新連線中…」 stayed while progress
  // went 2/5 → 5/5).
  if (relinkShown(s) ||
      (s.busy &&
          ((s.step == 4 && _step7Lost(s)) ||
              ((s.step == 4 || s.step == 5) && s.resumePending)))) {
    return relinkingLabel;
  }
  // Round 23: step 8 assigning — the run's own progress, disabled (field
  // round 23: a grey 「配置 5 台並開始監控」 beside 「0/5 完成，PTU #1 自動
  // 重試中」 read as not started).
  if (assigningShown(s)) return assigningLabel(s.assignStatus);
  if (step7LinkLost(s)) return rescanAfterLossLabel;
  // Phone link lost: the button reconnects first (same as the banner).
  if (s.resumePending) {
    return rest == 0 ? '重新連線並繼續' : '重新連線並繼續（剩 $rest 台）';
  }
  // Round 22: after a topology switch at step 7 the old mode's list is gone
  // — nothing to configure until the list is read again.
  if (s.relistReason.isNotEmpty && s.step == 4) {
    return s.busy ? relistingLabel : rescanLabel;
  }
  // Round 15: a step 7 scan that failed, timed out or found nothing is
  // over — 「重新掃描」, never a stuck 「掃描中…」.
  if (s.rescanNeeded && !s.busy && s.step == 4) return rescanLabel;
  // Round 9: everything assigned is not a dead end any more.
  if (rest == 0) {
    // Round 10: a rescan in progress is not 「恢復監控」 with 已選 0/5.
    if (s.busy || s.ptus.isEmpty) return scanningLabel;
    return s.monitoringOk ? '開始驗證' : '恢復監控';
  }
  // Round 16b: with some already done, 「剩餘」 — 「配置 1 台」 beside
  // 「已選 5 / 5 台」 read as if only one would be set up.
  final done = s.selected.length - rest;
  return done > 0 ? '配置剩餘 $rest 台並開始監控' : '配置 $rest 台並開始監控';
}

/// Round 23: a step 8 run is assigning ([CommissionState.assignRunning])
/// and the configure button shows its progress ([assigningLabel]).
bool assigningShown(CommissionState s) =>
    s.assignRunning && s.busy && s.step == 5 && s.assignStatus.isNotEmpty;

/// Round 23: the configure button while step 8 assigns — 「配置中… 4/5」,
/// the same count as the progress line above the list
/// ([assignProgressText]).
String assigningLabel(Map<String, AssignStatus> statuses) {
  final done = statuses.values.where((a) => a.phase == AssignPhase.done);
  return '配置中… ${done.length}/${statuses.length}';
}

/// Step 7/8 line above the configure button: 「已選 n / target 台」, or —
/// round 16b, once some selected PTUs are done — 「已選 5 台 · 已完成 4 台 ·
/// 將配置 1 台」 (field round 16: 「已選 5 / 5 台」 beside 「配置 1 台並開始
/// 監控」 read as a mismatch).
String selectionCountText(CommissionState s, int target) {
  // Round 22: while the list is read there is nothing to count (field
  // round 22: 「已選 0 / 5 台」 flashed during 「重新讀取 PTU 列表…」).
  if (s.relistReason.isNotEmpty && s.step == 4) {
    return topologyRelistText(s.relistReason, reading: s.busy || s.relinking);
  }
  if (ptuListLoading(s)) return ptuListLoadingText(target);
  // Round 24: nothing to count after a read refused as busy.
  if (s.step == 4 && s.ptus.isEmpty && s.ptuListBusy) return ptuListBusyText;
  final rest = configureTargets(s).length;
  final done = s.selected.length - rest;
  if (done == 0 || rest == 0) return '已選 ${s.selected.length} / $target 台';
  return '已選 ${s.selected.length} 台 · 已完成 $done 台 · 將配置 $rest 台';
}

/// Round 22: step 7 while the PTU list is (re)read — the list is empty
/// until the gateway answers ([selectionCountText] says so instead of
/// 「已選 0 / 5 台」).
bool ptuListLoading(CommissionState s) =>
    s.step == 4 && s.ptus.isEmpty && (s.busy || s.relinking);

/// Round 22: the count line while [ptuListLoading].
String ptuListLoadingText(int target) => '讀取中…（目標 $target 台）';

/// Round 23: the list card's count line — 「已連線 n 台／周邊未連線 m 台」
/// only once the list is read. While it is read with nothing in yet it is
/// [ptuCountReadingText] (field round 23: 「已連線 0 台／周邊未連線 0 台」
/// during the re-read after a topology switch read as nothing found);
/// after a topology switch whose read has not started,
/// [ptuCountUnreadText].
///
/// Round 24: after a list read refused as busy ([CommissionState.
/// ptuListBusy]) 「閘道器忙碌，列表暫時無法更新」 — with the kept list's
/// counts when there is one — never a bare 「0 台」.
String ptuCountText(CommissionState s) {
  if (s.ptus.isEmpty && (s.step == 4 || s.step == 5)) {
    if (s.busy || s.relinking) return ptuCountReadingText;
    if (s.relistReason.isNotEmpty) return ptuCountUnreadText;
    if (s.ptuListBusy) return ptuListBusyText;
  }
  final connected = s.ptus.where((p) => p['connected'] == true).length;
  final counts = '已連線 $connected 台／周邊未連線 ${s.ptus.length - connected} 台';
  if (s.ptuListBusy && s.step == 4 && !s.busy) {
    return '$ptuListBusyText（下面是上一次的列表：$counts）';
  }
  return counts;
}

/// Round 24: the count lines after a list read refused as busy.
const ptuListBusyText = '閘道器忙碌，列表暫時無法更新';

/// Round 23: [ptuCountText] while the PTU list is read.
const ptuCountReadingText = '讀取中…';

/// Round 23: [ptuCountText] after a topology switch, before the new read.
const ptuCountUnreadText = '尚未讀取 PTU 列表';

/// Round 23 (field round 23: switched back to star at step 7, the gateway
/// still connected one PTU — its max_connections is applied only by
/// 「配置」, by design — which read as a fault): at star step 7 while the
/// gateway's known max_connections is below the star range and the list
/// shows PTUs it has not connected, a line under the list count says that
/// 「配置」 connects them; null otherwise.
String? starApplyNote(CommissionState s, {required bool isStar}) {
  if (!isStar || s.step != 4) return null;
  if (!s.ptus.any((p) => p['connected'] != true)) return null;
  final limit = s.config['max_connections'];
  if (limit is! num || limit < 1 || limit >= maxStarPtuCount) return null;
  return starApplyText(limit.toInt());
}

/// Round 23: [starApplyNote]'s text for a gateway at [limit] connections.
String starApplyText(int limit) =>
    '閘道器目前只連 $limit 台；按下「配置」後，閘道器會切換為星狀並連線全部 PTU。';

/// Round 22: the count line after a topology switch at step 7
/// ([CommissionState.relistReason], e.g. 「已切換為星狀模式」): the old
/// mode's list is dropped and read again ([reading]); until a read starts
/// (a switch while a step ran) it only says the list needs reading.
String topologyRelistText(String reason, {required bool reading}) =>
    reading ? '$reason，重新讀取 PTU 列表…' : '$reason，PTU 列表需重新讀取';

/// Round 22: [CommissionState.relistReason] for a switch to [topology].
String topologySwitchedText(GatewayTopology topology) =>
    '已切換為${topology.shortLabel}';

/// Step 7 bottom button while a scan is still running.
const scanningLabel = '掃描中…';

/// Round 15: step 7 bottom button after a scan failed, timed out (e.g. the
/// get_ble_devices reply lost over BLE) or found no PTU.
const rescanLabel = '重新掃描';

/// Steps 7/8 bottom button while the automatic reconnect runs (disabled).
const relinkingLabel = '重新連線中…';

/// Round 21: step 7 bottom button once the phone is back and the PTU list
/// is read again (disabled).
const relistingLabel = '讀取列表中…';

/// Round 21: the automatic reconnect's stage ([CommissionState.relinkStage]).
enum RelinkStage {
  /// The phone reconnects to the gateway.
  reconnecting,

  /// Reconnected; the PTU list is read again (step 7 scan, step 8
  /// reconcile).
  reloading,

  /// Reconnected and read; step 8 goes on assigning (its own progress).
  resumed,
}

/// Round 21: bottom bar status while the phone reconnects by itself.
const relinkReconnectText = '手機與閘道器重新連線中…';

/// Round 21: bottom bar status once reconnected, while the list is read
/// again (field round 21: the list came 20 s after the reconnect).
const relinkReloadText = '重新讀取 PTU 列表…';

/// Round 22: the automatic reconnect's own texts (「重新連線中…」,
/// 「正在自動重新連線…」) only while it reconnects or reads the list again —
/// once step 8 assigns again ([RelinkStage.resumed]) the screen shows that
/// run (field round 22: both stayed while progress went 2/5 → 5/5).
bool relinkShown(CommissionState s) =>
    s.relinking && s.relinkStage != RelinkStage.resumed;

/// Round 22: the automatic reconnect got the phone back (it reads the list
/// again, or step 8 assigns again) — nothing may say 「已中斷」 any more.
bool relinkBack(CommissionState s) =>
    s.relinking && s.relinkStage != RelinkStage.reconnecting;

/// Round 21: the bottom bar's status line while [CommissionState.relinking]
/// (null otherwise, and once step 8 goes on assigning).
String? relinkStatusText(CommissionState s) {
  if (!s.relinking) return null;
  return switch (s.relinkStage) {
    RelinkStage.reconnecting => relinkReconnectText,
    RelinkStage.reloading => relinkReloadText,
    RelinkStage.resumed => null,
  };
}

/// Round 13: status card / rescan button while the automatic reconnect runs.
const autoRelinkingText = '正在自動重新連線…';

/// Round 13: most automatic reconnect rounds per phone↔gateway link loss
/// (steps 7 and 8, [CommissioningController] `_autoRelink`). Each round
/// keeps reconnecting for [connectPersistence]; only step 8 starts another
/// round, for a new loss after the previous round assigned more PTUs. A
/// give-up, or a loss that recurs without progress, ends them. Tests set 0
/// to exercise the manual 「重新連線並繼續」 path.
int autoRelinkRounds = 3;

/// Round 13: step 9 retries a backend that answers 5xx, cannot be reached
/// or times out every [backendRetryGap] until [backendRetryWindow] of
/// failures has accumulated, then stops with 「重試」.
Duration backendRetryGap = const Duration(seconds: 5);
Duration backendRetryWindow = const Duration(seconds: 60);

/// Step 9 busy text while the backend is retried automatically.
String backendRetryText(int attempt) => '後端暫時無回應，自動重試中（$attempt）';

/// A backend failure worth retrying by itself: HTTP 5xx (e.g. 502 while the
/// API container restarts), unreachable, or timed out.
bool isTransientBackendFailure(Object error) =>
    error is TimeoutException ||
    (error is GatewayFailure &&
        (error.code == 'network' ||
            (error.code == 'api' && (error.status ?? 0) >= 500)));

/// Step 7 bottom button after the automatic reconnect gave up. Round 15:
/// one name for every reconnect after a link loss (steps 7 and 8).
const rescanAfterLossLabel = '重新連線並繼續';

/// Round 15: step 7 idle link loss — after the first automatic reconnect
/// (immediate), a loss that recurs is retried after each of these gaps
/// (5 / 10 / 20 s, at most three retries) before the manual
/// 「重新連線並繼續」. Tests shorten them.
List<Duration> step7RetryGaps = const [
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
];

/// Round 15: a step 7 loss this soon after an automatic reconnect counts
/// as the same unstable spell (its retries are not reset).
Duration step7StableAfter = const Duration(seconds: 60);

/// Step 7 banner while waiting before an automatic retry.
String step7RetryText(int retry, int total, Duration gap) =>
    '藍牙連線又中斷，${gap.inSeconds} 秒後自動重新連線（第 $retry/$total 次重試）';

/// Round 15: direct flow (firmware 1.7.20+) polls get_status.direct this
/// often, at most [directPollLimit] times (~20 s), for the gateway's pick.
Duration directPollInterval = const Duration(milliseconds: 1500);
int directPollLimit = 14;

/// Round 16: 「不是這台？」 waits this long for the gateway to connect the
/// chosen PTU — exactly what the countdown shows. Round 15 field: the
/// switch took 24 s (five connect retries, status 133) while the APP gave
/// up after 14 polls (~21 s) with 「最多等待 42 秒」 still on screen.
Duration directSwitchWait = const Duration(seconds: 45);

/// Whole seconds of [directSwitchWait] for the countdown (at least 1).
int get directSwitchSeconds =>
    max(1, (directSwitchWait.inMilliseconds / 1000).ceil());

/// Header after [directSwitchWait] passed without the switch: the step 7
/// refresh keeps reading the gateway and clears the error once it has.
String directSwitchPendingText(String mac) =>
    '閘道器仍在改連 PTU ${formatMac(mac)}，連上後畫面會自動更新；也可改選其他 PTU。';

/// The gateway connected the PTU chosen under 「不是這台？」.
String directSwitchDoneText(String mac) =>
    '閘道器已改連 PTU $mac（已綁定），請按「辨識此樁」確認是眼前這台。';

/// Step 7 direct flow busy text while the gateway picks its PTU.
const directPickingText = '閘道器正在選擇最近的 PTU，請稍候';

/// Round 17: a new connected pick with no RSSI read yet (0 / null) keeps
/// 「辨識此樁」 at 「連線建立中…」 this long (field round 17: an identify
/// 0.9 s after the connect never reached the PTU). Tests shorten it.
Duration directSettleWindow = const Duration(seconds: 2);

/// Round 17: an identify whose PTU write came back `not_connected` in the
/// direct flow is sent once more after this long. Tests shorten it.
Duration identifyRetryDelay = const Duration(milliseconds: 1500);

/// Round 17: busy text while the gateway runs a new collection window
/// (「不是這台？」 without candidates, 「重新搜尋」 with a pick).
const directFreshWindowText = '閘道器正在重新收集附近的 PTU，請稍候';

/// The page's button that ends the run and goes back to the gateway list.
const endFlowLabel = '結束並重新選擇閘道器';

/// Round 17: 「結束並重新選擇閘道器」 after step 3 asks first (field round
/// 17: a late tap meant for 「改選其他 PTU」 landed on it once the layout
/// moved, and ended the whole flow).
const endFlowConfirmTitle = '結束目前配置？';

/// Body of the [endFlowConfirmTitle] dialog; [done] = PTUs configured.
///
/// Round 18: [restoresBind] ([endFlowRestoresBind]) — 結束 puts the binding
/// from before 「不是這台？」 back (field round 18: the text said the gateway
/// keeps its settings while 結束 sent set_config direct_bind_mac).
String endFlowConfirmText(int done, {bool restoresBind = false}) {
  if (restoresBind) {
    return done > 0
        ? '結束後會把閘道器的 PTU 綁定還原為改選前的狀態；已完成的 $done 台保留。'
        : '結束後會把閘道器的 PTU 綁定還原為改選前的狀態；目前尚未完成任何 PTU。';
  }
  return done > 0 ? '已完成的 $done 台會保留在閘道器。' : '目前尚未完成任何 PTU。';
}

/// Round 18: 結束 now would undo a temporary 「不是這台？」 binding
/// (the same test as `_releaseTempBind`: switched back to the binding from
/// before leaves nothing to undo).
bool endFlowRestoresBind(CommissionState s) {
  final temp = s.tempBoundMac;
  if (temp == null) return false;
  final restore = s.tempRestoreMac;
  return restore == null || !sameMac(restore, temp);
}

/// Round 15: done page / install report line when the direct-mode gateway
/// is bound to a PTU MAC (「確認後綁定 PTU」, or kept from 「不是這台？」).
String? directBoundNote(CommissionState s) {
  final bound = directBoundMacOf(s.config) ?? s.direct?.boundMac;
  return bound == null ? null : '已綁定 PTU MAC：$bound（閘道器只連這台）';
}

/// Step 7 direct flow message once the gateway's pick has been polled.
String directPickMessage(DirectStatus? direct) {
  final mac = direct?.pickedMac;
  if (mac != null) {
    return direct!.ambiguous
        ? '閘道器選中 PTU $mac，但附近有訊號相近的 PTU，請按「辨識此樁」確認'
        : '閘道器選中 PTU $mac，請按「辨識此樁」確認是眼前這台';
  }
  return switch (direct?.state) {
    DirectState.noCandidate => '閘道器找不到夠近的 PTU：請確認同樁 PTU 已上電並靠近，再按「重新搜尋」。',
    DirectState.boundMissing => '閘道器綁定的 PTU 不在場：請確認它已上電，或解除綁定後按「重新搜尋」。',
    null => '閘道器尚未回報選台結果，請按「重新搜尋」。',
    _ => '閘道器仍在尋找 PTU，請稍候再按「重新搜尋」。',
  };
}

/// Step 7, not busy, phone↔gateway link lost (banner shown).
bool step7LinkLost(CommissionState s) => !s.busy && _step7Lost(s);

/// Direct flow step 7 with the gateway's pick and its bottom bar
/// ([directFlow]: `CommissioningController.directFlow`) — not while
/// relinking, resuming or after a link loss (the reconnect button instead).
bool directPickBarShown(CommissionState s, {required bool directFlow}) =>
    s.step == 4 &&
    directFlow &&
    !s.relinking &&
    !s.resumePending &&
    !step7LinkLost(s);

bool _step7Lost(CommissionState s) =>
    s.step == 4 &&
    !s.resumePending &&
    (s.scanResumePending || s.uploadWatch == UploadWatch.linkLost);

/// Round 22: a PTU in the step 8 progress line ([assignProgressText]) as
/// its row shows it — the row's number (「PTU #5」), or, unnumbered (row
/// 「未指派 PTU」), the MAC bytes that tell it apart from the listed ones
/// (「PTU …74…」 for 90:74:E8:9A:96:00 on the field bench).
String assignPtuName(CommissionState s, String mac) {
  final row = s.ptus.where((p) => sameMac(p['mac'], mac)).firstOrNull;
  final id = (row?['device_number'] as num?)?.toInt() ?? 0;
  if (id > 0 && id != 255) return 'PTU #$id';
  return 'PTU ${distinguishingMacSegment(mac, s.ptus.map((p) => p['mac']))}';
}

/// Round 22: the step 8 progress line with the retrying PTUs named.
String? assignProgressLine(CommissionState s) =>
    assignProgressText(s.assignStatus, name: (mac) => assignPtuName(s, mac));

/// 「配置」按鈕的目標集合：已勾選但尚未成功指派的 PTU MAC。
Set<String> configureTargets(CommissionState s) =>
    s.selected.difference(s.assignedOk);

/// Step 10 message right after verification, before any health answer.
const verifiedText = '開通驗證通過，已恢復自動監控';

/// Restart prompt when the saved run already finished (round 6: a finished
/// run still showed 「已保留先前進度」).
String completedText(Object? site, Object? gateway, int count) =>
    '上次配置已完成（site $site / gateway $gateway，$count 台）';

/// Step 8/max_connections policy: star mode always opens the full range (5)
/// so a later 5th PTU can still connect; direct mode is one PTU.
int monitorLimit(bool isStar) => isStar ? maxStarPtuCount : 1;

/// Done page: 「正在確認資料上傳…」 only while no recent heartbeat is known;
/// the step 9 verification already records one, so normally the status
/// panel's 「✓ 資料上傳中」 shows directly.
bool showHealthPending(CommissionState s, {DateTime? now}) {
  if (!s.loggedIn || s.message != verifiedText) return false;
  final seen = s.backendSeenAt;
  return seen == null ||
      (now ?? DateTime.now()).difference(seen) >= const Duration(seconds: 60);
}

/// Install report lines, ordered by PTU number.
List<Map<String, dynamic>> byDeviceNumber(
  Iterable<Map<String, dynamic>> ptus,
) => List.of(ptus)
  ..sort(
    (a, b) => ((a['device_number'] as num?) ?? 0).compareTo(
      (b['device_number'] as num?) ?? 0,
    ),
  );

String resumeText(
  int step,
  List<int> done,
  int pending, {
  List<int> inflight = const [],
  int? shown,
}) {
  // Round 12: [shown] is the 1-based step the installer saw (steps 3–6 all
  // live in controller step 2, which made every kill there 「第 3 步」).
  final where = shown != null && shown >= 2 && shown <= stepLabels.length - 1
      ? '第 $shown 步（${stepLabels[shown - 1]}）'
      : _savedStepLabels[step];
  if (where == null) return '已保留先前進度，請重新連線以核對裝置現況。';
  String list(List<int> v) =>
      (List<int>.of(v)..sort()).map((i) => '#$i').join('、');
  final doneText = done.isEmpty
      ? '尚未完成任何 PTU'
      : '已完成 ${done.length} 台（${list(done)}）';
  final inflightText = inflight.isEmpty
      ? ''
      : '，${list(inflight)} 指派中斷、重新連線後以閘道器核對為準';
  final pendingText = pending > 0 ? '，尚有 $pending 台未配置' : '';
  return '上次中斷於$where，$doneText$inflightText$pendingText。閘道器仍在運作，不需重新上電。';
}

/// Step 9 polls /api/latest this often (seconds).
const verifyPollSeconds = 10;

/// Step 9: a PTU without a new row for this long gets 「尚無資料」 (seconds).
const verifyIdleLimit = 60;

/// Step 9 per-PTU tally of one /api/latest answer: a fresh row with a newer
/// timestamp than any counted before adds one (max 3). Round 10: counts are
/// cumulative — a missing, offline, late or erroring row, or an unchanged
/// timestamp, keeps the count (the reset made 3/3 fall back to 0/3). [lastNew] records the
/// [elapsed] second of each PTU's latest new row.
void verifyTally({
  required Iterable<int> ids,
  required List<Map<String, dynamic>> rows,
  required Map<int, DateTime> previous,
  required Map<int, int> counts,
  required Map<int, int> lastNew,
  required int elapsed,
}) {
  for (final id in ids) {
    final found = rows.where((p) => p['device_id'] == id).toList();
    // Round 10: cumulative — no (good) new row neither adds nor resets.
    if (found.isEmpty) continue;
    final row = found.first;
    final stamp = DateTime.tryParse(row['ts']?.toString() ?? '');
    if (row['online'] != true ||
        ((row['lag_seconds'] as num?) ?? 999) >= 60 ||
        row['error_num'] != 0 ||
        stamp == null) {
      // Not counted, but its timestamp is not "new" later either.
      if (stamp != null) previous[id] = stamp;
      continue;
    }
    final seen = previous[id];
    previous[id] = stamp;
    if (seen == null || stamp.isAfter(seen)) {
      counts[id] = min(3, (counts[id] ?? 0) + 1);
      lastNew[id] = elapsed;
    }
  }
}

/// Step 9 busy text: 「#1 2/3、#2 1/3」 plus 「PTU #n 尚無資料」 lines and, for
/// any skipped PTU, 「PTU #n 未驗證（已略過）」 instead.
String verifyProgressText(
  Iterable<int> ids,
  Map<int, int> counts,
  Set<int> waiting, [
  Set<int> skipped = const {},
]) {
  final sorted = List.of(ids)..sort();
  final line = sorted.map((id) => '#$id ${counts[id] ?? 0}/3').join('、');
  final idle = [
    for (final id in sorted)
      if (skipped.contains(id))
        'PTU #$id 未驗證（已略過）'
      else if (waiting.contains(id))
        'PTU #$id 尚無資料',
  ];
  return ['資料驗證 $line', ...idle].join('\n');
}

/// Text for 「N 台在本次掃描未出現，已取消勾選」.
String absentSelectionText(int n) => '$n 台在本次掃描未出現，已取消勾選';

/// /api/latest rows show this gateway uploading within the last 60 s.
bool backendRowsFresh(Iterable<Map> rows) => rows.any(
  (r) => r['online'] == true && ((r['lag_seconds'] as num?) ?? 999) < 60,
);

/// Star mode: fleet-status could not tell whether out-of-range PTUs' owner
/// gateways are registered, so nothing was reset automatically.
const starOwnerUnknownText = '無法確認閘道器登記狀態，請手動重置';

/// [CommissionState.copy]: leave a nullable field as it is.
const _keep = Object();

/// Round 15b: 「是這台，開始監控」 is enabled — the gateway has a pick and,
/// when the firmware can blink the PTU, it is the one the installer
/// identified ([CommissionState.identifiedMac]).
bool directConfirmReady(CommissionState s) {
  final picked = s.direct?.pickedMac;
  if (picked == null) return false;
  if (!directIdentifyRequired(s.config)) return true;
  final identified = s.identifiedMac;
  return identified != null && sameMac(identified, picked);
}

class CommissionState {
  const CommissionState({
    this.step = 0,
    this.busy = false,
    this.message = '',
    this.error,
    this.seconds = 0,
    this.peers = const [],
    this.peer,
    this.config = const {},
    this.ptus = const [],
    this.selected = const {},
    this.results = const {},
    this.verified = false,
    this.report = '',
    this.online = false,
    this.missing = const [],
    this.uploadNotice = '',
    this.loggedIn = false,
    this.net = const {},
    this.uploadWatch = UploadWatch.idle,
    this.uploadSlow = false,
    this.uploadLate = false,
    this.checkPassed = false,
    this.wifiGraceOver = false,
    this.offline = false,
    this.autoRssi = true,
    this.scannedTotal = 0,
    this.pendingNext = 0,
    this.resetFailed = const {},
    this.backendSeenAt,
    this.starNotice = '',
    this.assignFailed = const {},
    this.errorDetail,
    this.absentNotice = '',
    this.unassigned = const {},
    this.assignedOk = const {},
    this.resumePending = false,
    this.monitoringOk = false,
    this.monitorUnconfirmed = false,
    this.scanResumePending = false,
    this.relinking = false,
    this.verifyBackendDown = false,
    this.reconnectFailed = false,
    this.savedResume = false,
    this.savedProgress = false,
    this.lastCompleted = false,
    this.verifyCounts = const {},
    this.verifyWaiting = const {},
    this.verifySkipped = const {},
    this.directRaw = const {},
    this.identifyNote = '',
    this.identifyLine = '',
    this.rescanNeeded = false,
    this.identifiedMac,
    this.tempBoundMac,
    this.tempRestoreMac,
    this.strayBindMac,
    this.directNotice = '',
    this.directSettling = false,
    this.remoteIdentifyNote = '',
    this.remoteIdentifyCount = 0,
    this.remoteIdentifyHead = '',
    this.remoteIdentifyPtu = '',
    this.assignStatus = const {},
    this.relinkStage = RelinkStage.reconnecting,
    this.relistReason = '',
    this.assignRunning = false,
    this.gatewayReboot,
    this.ptuListBusy = false,
  });

  /// Round 24 (field round 24: a rescan refused as busy left 「已連線 0 台
  /// ／周邊未連線 0 台 · 已選 0 / 5 台」, read as nothing found): the last
  /// step 7 list read was refused because the gateway was busy. The list
  /// before it is kept ([ptus] may be that list, or empty on a first read)
  /// and the count lines say the list could not be updated
  /// ([ptuListBusyText]). Cleared by the next list read.
  final bool ptuListBusy;

  /// The gateway restarted without being asked to (its boot_count went up
  /// between two reads, e.g. across a command timeout or a Bluetooth
  /// reconnect): the page shows [gatewayRebootText] until 「知道了」.
  final GatewayReboot? gatewayReboot;

  /// Round 23 (field round 23: a busy retry at 「0/5 完成，PTU #1 自動重試中」
  /// kept a grey 「配置 5 台並開始監控」 at the bottom, read as not started):
  /// a step 8 run is assigning PTUs (from its first assign until the run
  /// ends, monitoring start included); the configure button then shows the
  /// run's progress ([assigningLabel]).
  final bool assignRunning;

  /// Round 22 (field round 22: switched direct → star at step 7, the star
  /// list kept the direct pick — 1 PTU and 「配置 1 台並開始監控」): why the
  /// step 7 list was dropped (「已切換為星狀模式」) until it is read again;
  /// '' otherwise. The configure button waits for the new list.
  final String relistReason;

  /// Round 21 (field round 21: the one-line notice was cut after
  /// 「後台剛讓這台樁閃燈（請看樁上燈…」): the notice's short first sentence
  /// ([remoteIdentifyHeadText]) and its PTU MAC · RSSI
  /// ([remoteIdentifyPtuText]) for the direct bar's identify line;
  /// [remoteIdentifyNote] stays the full text (details, snack bar).
  final String remoteIdentifyHead, remoteIdentifyPtu;

  /// Round 21: step 8, each chosen PTU's assignment as shown on its row
  /// (「等待中」「指派中」「藍牙連線失敗，自動重試 1/2」…) and summed up above
  /// the list ([assignProgressText]). Empty outside an assignment run.
  final Map<String, AssignStatus> assignStatus;

  /// Round 21: while [relinking], whether the phone is still reconnecting
  /// or already reads the PTU list again (field round 21: back after 2.6 s,
  /// the list 20 s later, the screen said 「重新連線中」 all along).
  final RelinkStage relinkStage;

  /// Round 19: the back office made the connected pile blink (its identify
  /// ack, relayed by the gateway, answers no request of this APP) — shown
  /// as a passing notice, nothing else changes. [remoteIdentifyCount]
  /// counts them, so the page shows each one once.
  final String remoteIdentifyNote;
  final int remoteIdentifyCount;

  /// Round 17: the gateway reported its pick connected less than
  /// [directSettleWindow] ago and no RSSI yet (0 / null) — 「辨識此樁」
  /// reads 「連線建立中…」, disabled.
  final bool directSettling;

  /// Round 15b: MAC of the PTU the installer identified — the MAC the last
  /// 「辨識此樁」 ack named. 「是這台，開始監控」 only numbers the gateway's
  /// pick when it is this PTU; cleared as soon as the gateway connects
  /// another one (or none).
  final String? identifiedMac;

  /// Round 15b: binding set by 「不是這台？」 ([CommissioningController.
  /// switchDirectPick]) and not yet confirmed. 「是這台」 makes it permanent;
  /// cancelling undoes it on the gateway (round 16b: puts back
  /// [tempRestoreMac]).
  final String? tempBoundMac;

  /// Round 16b: the gateway's binding right before the first 「不是這台？」
  /// of this temporary binding (null: none) — what 取消 / 返回 / 結束
  /// put back (round 16 field: a binding confirmed earlier was cleared to
  /// "" instead). Only meaningful while [tempBoundMac] is set.
  final String? tempRestoreMac;

  /// Round 15b: entering step 7, the gateway was bound to this PTU with no
  /// confirmed record in this APP; the panel asks 「保留」/「解除」.
  final String? strayBindMac;

  /// Round 15b: yellow step 7 notice (the gateway switched away from the
  /// identified PTU, or 「是這台」 pressed before identifying).
  final String directNotice;

  /// Round 15: shown right beside 「辨識此樁」 — 「已送出，請看樁上燈號」 at
  /// once, then the acked PTU MAC / RSSI (or that only the gateway blinks).
  /// Step 7 hides [message], so this is the only place the ack shows there.
  final String identifyNote;

  /// Round 16: [identifyNote] in one line for the bottom bar (「已送出 ·
  /// 請看樁上燈號 · …MAC 後 4 碼 · RSSI」); the full note opens below it.
  /// Round 15: the four-line note grew the bar and hid 「不是這台？」.
  final String identifyLine;

  /// Round 15: the last step 7 scan failed, timed out or found nothing; the
  /// bottom button reads [rescanLabel] instead of a stuck 「掃描中…」.
  final bool rescanNeeded;

  /// Last `direct` object the gateway reported (firmware 1.7.20+ in direct
  /// mode); empty for older firmware or before the first read.
  final Map<String, dynamic> directRaw;

  /// Parsed [directRaw]; null when the firmware does not report it.
  DirectStatus? get direct => DirectStatus.from(directRaw);

  /// Step 9: fresh-data rounds seen per PTU number (0..3).
  final Map<int, int> verifyCounts;

  /// Step 9: PTU numbers with no new data for [verifyIdleLimit].
  final Set<int> verifyWaiting;

  /// Step 9: PTU numbers the installer skipped after staying idle
  /// ([verifyIdleLimit]) — marked 「未驗證（已略過）」; the pass/fail
  /// judgement and the install report both exclude them from the count and
  /// list them separately.
  final Set<int> verifySkipped;
  final int step, seconds;
  final bool busy, verified, online;
  final String message, report;

  /// Saved progress belongs to a run that finished (step 10 verified):
  /// offer 「重新開始」 instead of 「重新連線並繼續」.
  final bool lastCompleted;

  /// Round 16: progress of an unfinished run was restored (「上次中斷於…」),
  /// whether or not it can be resumed ([savedResume]): 「重新開始」 clears
  /// it (round 15: a record without a gateway had no way to clear it).
  final bool savedProgress;

  /// Logged in to the backend currently selected (reset on a switch).
  final bool loggedIn;

  /// Gateway network status (wifi_state / ip / ssid / rssi / uptime_sec)
  /// last read.
  final Map<String, dynamic> net;
  final UploadWatch uploadWatch;

  /// Still polling after [UploadWatchTiming.slowAfter] without upload.
  final bool uploadSlow;

  /// Polled for [UploadWatchTiming.confirmAfter] without upload.
  final bool uploadLate;

  /// Step 2: the network check (網路體檢 → 對準上傳目標 → 確認資料上傳)
  /// shown right after connecting has been passed or skipped, so the station
  /// choice or the identity/Wi-Fi form is shown. False again after a Wi-Fi
  /// change that keeps the station, whose upload is confirmed before PTU review.
  final bool checkPassed;

  /// The Wi-Fi grace period after a connect or reboot is over.
  final bool wifiGraceOver;

  /// Started with 「先離線配置，稍後驗證資料」 (no backend login).
  final bool offline;
  final bool autoRssi;

  /// 星狀強化：最近一次 discover() 掃到的 PTU 總數，以及可納入但目前不在本機
  /// 5 格範圍內、待下一台閘道器認領的台數（完成畫面的 X / Z 統計）。
  final int scannedTotal, pendingNext;

  /// 星狀模式：自動重置（含重試 1 次）後仍失敗的範圍外 PTU MAC；這些不算
  /// 「屬於其他閘道器」，pendingNext 也不含它們。
  final Set<String> resetFailed;

  /// 最近一次後端（fleet-status online 或 /api/latest 有新鮮資料）確認此
  /// gateway 有在上傳的時間；null＝尚未確認。
  final DateTime? backendSeenAt;

  /// 星狀模式：掃描後無法向後台確認範圍外 PTU 的所屬閘道器是否登記時的提示
  /// （此時不自動重置）；空字串代表不顯示。
  final String starNotice;

  /// 第 8 步：重試後仍指派失敗的 PTU（MAC → 人話原因）。
  final Map<String, String> assignFailed;

  /// 錯誤原始內容（放在橫幅的「詳細資訊」裡）；只跟著 [error] 存在。
  final String? errorDetail;

  /// 重掃後原本勾選但本次沒掃到的提示；空字串不顯示。
  final String absentNotice;

  /// 第 8 步因手機↔閘道器斷線而尚未處理的 PTU MAC。
  final Set<String> unassigned;

  /// 已成功指派（含 readback 通過）的 PTU MAC；續作按鈕以
  /// `selected - assignedOk` 決定還要配置哪些台。
  final Set<String> assignedOk;

  /// 第 8 步被手機斷線打斷，可按「重新連線並繼續」。
  final bool resumePending;

  /// Step 7 reconcile: every selected PTU is assigned, connected, and the
  /// gateway is monitoring (BLE on, upload not paused, limit set). With
  /// nothing left to assign the button reads 「開始驗證」, else 「恢復監控」.
  final bool monitoringOk;

  /// Resume at step 8: the gateway did not confirm monitoring within 30 s;
  /// the page offers 「重試」 (resumeAssign) and 「略過」 (skipMonitorConfirm).
  final bool monitorUnconfirmed;

  /// 星狀自動重置殘留編號時手機↔閘道器斷線；「重新連線並繼續」會重連並重掃。
  final bool scanResumePending;

  /// Round 12: step 7 automatic reconnect (+ rescan) after a link loss is
  /// running; the bottom button shows [relinkingLabel], disabled.
  final bool relinking;

  /// Round 13: step 9 stopped because the backend stayed unavailable
  /// (5xx / unreachable / timeout) through the automatic retries; the page
  /// offers 「重試」, which keeps the per-PTU progress.
  final bool verifyBackendDown;

  /// 最近一次重新連線閘道器逾時／失敗（顯示重試與回到找閘道器）。
  final bool reconnectFailed;

  /// APP 重開後有可續作的進度（第 1 步顯示「重新連線並繼續」）。
  final bool savedResume;

  /// Gateway Wi-Fi as the network check judges it.
  WifiVerdict get wifi => wifiVerdictOf(
    net,
    configSsid: config['wifi_ssid'],
    settled:
        wifiGraceOver ||
        uploadWatch == UploadWatch.gaveUp ||
        uploadWatch == UploadWatch.linkLost,
  );

  /// The firmware answers get_net_status (1.7+); older ones cannot be checked.
  bool get netCheckSupported =>
      profileFor(config['fw_version']?.toString() ?? '') ==
      ProtocolProfile.current;

  /// The gateway has Wi-Fi and uploads, so its data can be verified now
  /// (「沿用目前站點」, or the station kept after a Wi-Fi change). Always true
  /// for firmware that cannot report it: the data verification decides.
  bool get networkReady =>
      uploadWatch != UploadWatch.linkLost &&
      (!netCheckSupported ||
          (wifi == WifiVerdict.ok && config['mqtt_connected'] == true));

  /// Outcome of the last upload-target switch or refresh (shown in its card).
  final String uploadNotice;
  final String? error;
  final List<GatewayPeer> peers;
  final GatewayPeer? peer;
  final Map<String, dynamic> config;
  final List<Map<String, dynamic>> ptus;
  final Set<String> selected;
  final Map<String, String> results;
  final List<String> missing;
  CommissionState copy({
    int? step,
    bool? busy,
    String? message,
    String? error,
    int? seconds,
    List<GatewayPeer>? peers,
    GatewayPeer? peer,
    Map<String, dynamic>? config,
    List<Map<String, dynamic>>? ptus,
    Set<String>? selected,
    Map<String, String>? results,
    bool? verified,
    String? report,
    bool? online,
    List<String>? missing,
    String? uploadNotice,
    bool? loggedIn,
    Map<String, dynamic>? net,
    UploadWatch? uploadWatch,
    bool? uploadSlow,
    bool? uploadLate,
    bool? checkPassed,
    bool? wifiGraceOver,
    bool? offline,
    bool? autoRssi,
    int? scannedTotal,
    int? pendingNext,
    Set<String>? resetFailed,
    DateTime? backendSeenAt,
    String? starNotice,
    Map<String, String>? assignFailed,
    String? errorDetail,
    String? absentNotice,
    Set<String>? unassigned,
    Set<String>? assignedOk,
    bool? resumePending,
    bool? monitoringOk,
    bool? monitorUnconfirmed,
    bool? scanResumePending,
    bool? relinking,
    bool? verifyBackendDown,
    bool? reconnectFailed,
    bool? savedResume,
    bool? savedProgress,
    bool? lastCompleted,
    Map<int, int>? verifyCounts,
    Set<int>? verifyWaiting,
    Set<int>? verifySkipped,
    Map<String, dynamic>? directRaw,
    String? identifyNote,
    String? identifyLine,
    bool? rescanNeeded,
    Object? identifiedMac = _keep,
    Object? tempBoundMac = _keep,
    Object? tempRestoreMac = _keep,
    Object? strayBindMac = _keep,
    String? directNotice,
    bool? directSettling,
    String? remoteIdentifyNote,
    int? remoteIdentifyCount,
    String? remoteIdentifyHead,
    String? remoteIdentifyPtu,
    Map<String, AssignStatus>? assignStatus,
    RelinkStage? relinkStage,
    String? relistReason,
    bool? assignRunning,
    Object? gatewayReboot = _keep,
    bool? ptuListBusy,
  }) => CommissionState(
    ptuListBusy: ptuListBusy ?? this.ptuListBusy,
    gatewayReboot: identical(gatewayReboot, _keep)
        ? this.gatewayReboot
        : gatewayReboot as GatewayReboot?,
    relistReason: relistReason ?? this.relistReason,
    assignRunning: assignRunning ?? this.assignRunning,
    remoteIdentifyHead: remoteIdentifyHead ?? this.remoteIdentifyHead,
    remoteIdentifyPtu: remoteIdentifyPtu ?? this.remoteIdentifyPtu,
    assignStatus: assignStatus ?? this.assignStatus,
    relinkStage: relinkStage ?? this.relinkStage,
    remoteIdentifyNote: remoteIdentifyNote ?? this.remoteIdentifyNote,
    remoteIdentifyCount: remoteIdentifyCount ?? this.remoteIdentifyCount,
    directSettling: directSettling ?? this.directSettling,
    identifiedMac: identical(identifiedMac, _keep)
        ? this.identifiedMac
        : identifiedMac as String?,
    tempBoundMac: identical(tempBoundMac, _keep)
        ? this.tempBoundMac
        : tempBoundMac as String?,
    tempRestoreMac: identical(tempRestoreMac, _keep)
        ? this.tempRestoreMac
        : tempRestoreMac as String?,
    strayBindMac: identical(strayBindMac, _keep)
        ? this.strayBindMac
        : strayBindMac as String?,
    directNotice: directNotice ?? this.directNotice,
    directRaw: directRaw ?? this.directRaw,
    identifyNote: identifyNote ?? this.identifyNote,
    identifyLine: identifyLine ?? this.identifyLine,
    rescanNeeded: rescanNeeded ?? this.rescanNeeded,
    lastCompleted: lastCompleted ?? this.lastCompleted,
    verifyCounts: verifyCounts ?? this.verifyCounts,
    verifyWaiting: verifyWaiting ?? this.verifyWaiting,
    verifySkipped: verifySkipped ?? this.verifySkipped,
    unassigned: unassigned ?? this.unassigned,
    assignedOk: assignedOk ?? this.assignedOk,
    resumePending: resumePending ?? this.resumePending,
    monitoringOk: monitoringOk ?? this.monitoringOk,
    monitorUnconfirmed: monitorUnconfirmed ?? this.monitorUnconfirmed,
    scanResumePending: scanResumePending ?? this.scanResumePending,
    relinking: relinking ?? this.relinking,
    verifyBackendDown: verifyBackendDown ?? this.verifyBackendDown,
    reconnectFailed: reconnectFailed ?? this.reconnectFailed,
    savedResume: savedResume ?? this.savedResume,
    savedProgress: savedProgress ?? this.savedProgress,
    assignFailed: assignFailed ?? this.assignFailed,
    errorDetail: error == null ? null : (errorDetail ?? this.errorDetail),
    absentNotice: absentNotice ?? this.absentNotice,
    resetFailed: resetFailed ?? this.resetFailed,
    backendSeenAt: backendSeenAt ?? this.backendSeenAt,
    loggedIn: loggedIn ?? this.loggedIn,
    net: net ?? this.net,
    uploadWatch: uploadWatch ?? this.uploadWatch,
    uploadSlow: uploadSlow ?? this.uploadSlow,
    uploadLate: uploadLate ?? this.uploadLate,
    checkPassed: checkPassed ?? this.checkPassed,
    wifiGraceOver: wifiGraceOver ?? this.wifiGraceOver,
    offline: offline ?? this.offline,
    autoRssi: autoRssi ?? this.autoRssi,
    scannedTotal: scannedTotal ?? this.scannedTotal,
    pendingNext: pendingNext ?? this.pendingNext,
    starNotice: starNotice ?? this.starNotice,
    step: step ?? this.step,
    busy: busy ?? this.busy,
    message: message ?? this.message,
    error: error,
    seconds: seconds ?? this.seconds,
    peers: peers ?? this.peers,
    peer: peer ?? this.peer,
    config: config ?? this.config,
    ptus: ptus ?? this.ptus,
    selected: selected ?? this.selected,
    results: results ?? this.results,
    verified: verified ?? this.verified,
    report: report ?? this.report,
    online: online ?? this.online,
    missing: missing ?? this.missing,
    uploadNotice: uploadNotice ?? this.uploadNotice,
  );
}

final commissionProvider =
    NotifierProvider<CommissioningController, CommissionState>(
      CommissioningController.new,
    );

class CommissioningController extends Notifier<CommissionState> {
  late GatewayLink _link;
  late GatewayApi _api;

  /// Field rescue v1: session reports, diagnostics, help (never blocks or
  /// fails the commissioning).
  late FieldReporter _field;

  /// When get_net_status was last absorbed (diagnostics `net_read_age_s`).
  DateTime? _netReadAt;
  Timer? _clock, _health;
  int _generation = 0;
  // Topology changed while a step was running; applied when it ends.
  bool _topologyDeferred = false;
  // Round 22: that change switched direct ↔ star (not only the count).
  bool _topologySwitchDeferred = false;
  bool _provisioningMayBeActive = false;
  Future<bool>? _stopping;

  /// Step 8 assignments that succeeded in this run (MAC → number); saved so a
  /// restart knows which PTUs are done.
  final Map<String, int> _doneAssign = {};

  /// Step 8 assignments sent but not yet acked (MAC → number). Saved before
  /// each assign_ptu so a kill between the gateway's ack and the save is
  /// still reconciled on resume (round 8: the prompt said 2, gateway had 3).
  final Map<String, int> _inflightAssign = {};

  /// MACs whose ack had verified:false, awaiting get_ble_devices read-back.
  final Set<String> _pendingReadback = {};

  /// Saved progress read by [restore] (for 「重新連線並繼續」).
  Map? _saved;
  String _backend = describeBackend(null);
  // Latest step-7 diagnosis, tagged with the generation that produced it.
  (int, String)? _diagnosis;
  bool _loggedIn = false,
      _lease = false,
      _foreground = true,
      _healthBusy = false;

  /// Backend already reserved this (site, gateway) as a replacement, but
  /// writing it to the device itself has not been confirmed yet — set right
  /// after a successful force_replace reserve-identity, cleared once
  /// set_site_identity + readback succeed. The next 「儲存並連接 WiFi」 should
  /// retry with replaceExisting so it does not re-reserve (already granted).
  bool _pendingReplace = false;
  bool get pendingReplace => _pendingReplace;

  /// PTU 目標台數：直連固定 1，星狀依「每台 PTU 數」設定（預設 5）。
  int get targetPtuCount => ref.read(topologyProvider).targetCount;

  /// Round 15: direct mode on firmware that picks the PTU itself (1.7.20+,
  /// `direct_autoconnect_supported`). Step 7 then shows the gateway's own
  /// pick (「辨識此樁」 → 「是這台，開始監控」) instead of a list the APP
  /// preselects — round 14: the APP ticked one PTU while the gateway
  /// connected another. Older firmware keeps the list flow.
  bool get directFlow =>
      ref.read(topologyProvider).topology.isDirect &&
      directAutoConnectSupported(state.config);

  /// Round 15: retries used in the current step 7 unstable spell and when
  /// its last automatic reconnect succeeded ([step7StableAfter]).
  int _step7Retries = 0;
  DateTime? _step7RelinkedAt;

  /// Round 15: the saved record says 「上次配置已完成」; a later run does not
  /// overwrite it before it reaches the PTU steps (a connect or identify
  /// from the gateway list left 「上次中斷於第 5 步」 in round 14).
  bool _completedSticky = false;
  int get site => (state.config['site_id'] as num?)?.toInt() ?? 1;
  int get gateway => (state.config['gateway_id'] as num?)?.toInt() ?? 1;
  String get _path => '/api/gateways/$site/$gateway';
  late UploadWatchTiming _timing;
  Timer? _poll, _grace;
  int _pollTicks = 0;
  int _abnormalStreak = 0;
  bool _pollInFlight = false;
  Timer? _rssiTimer;
  bool _rssiInFlight = false;

  /// 星狀模式：最近一次 discover() 從 fleet-status 讀到、此 site 已登記的
  /// gateway id；null＝沒查或查不到（範圍外 PTU 一律當成屬於其他閘道器）。
  Set<int>? _ownerRegistry;

  /// 本輪 discover() 已自動把殘留編號歸零，需要再重掃一次（只做一輪）。
  bool _autoResetRescan = false;

  /// 本輪自動重置（重試後）仍失敗的 PTU MAC，跨重掃保留到下一輪 autoReset。
  final Set<String> _resetFailed = {};

  /// Base URL of the backend the login (if any) belongs to.
  String? _loginBase;

  /// Last boot_count read from a gateway (keyed by its peer id); null after
  /// a command that restarts it on purpose ([_expectReboot]). Saved with
  /// the progress, so a restart while the APP was closed is seen as well.
  ({String peer, int count})? _boot;

  /// Round 24: [_run] is classifying a failure (a restart found meanwhile
  /// is part of it — field rescue rule 1 — not a separate report).
  bool _classifyingFailure = false;

  @override
  CommissionState build() {
    _link = ref.watch(linkProvider);
    _api = ref.watch(apiProvider);
    _timing = ref.read(uploadWatchTimingProvider);
    _field = ref.watch(fieldReporterProvider);
    _field.attach(input: _fieldInput, sections: _fieldSections);
    // 切換拓撲（直連／星狀）或改星狀台數：先依新拓撲重算 pendingNext 與 selected
    // （沿用既有 ptus 清單，套用跟 _discover 相同的範圍過濾／預選邏輯，不重
    // 掃），再把已勾選裁到新的目標台數，只保留 RSSI 最強的前 N 台；顯示的
    // 「已選 x/y」跟著 topologyProvider 動態重繪。
    ref.listen(topologyProvider, (previous, next) {
      if (previous?.targetCount != next.targetCount ||
          previous?.topology != next.topology) {
        final switched = previous != null && previous.topology != next.topology;
        // 自動收編（重置迴圈＋重掃）進行中不在中途重算：延後到該步驟結束再套用。
        if (state.busy) {
          _topologyDeferred = true;
          _topologySwitchDeferred |= switched;
        } else {
          _onTopologyChanged(next, switched: switched);
        }
      }
    });
    // Round 11: persist on every step change (not only when a run ends), so
    // the restore prompt names the step actually reached. A pending saved
    // resume is not overwritten until it is consumed.
    // Round 12: keyed on the step the installer sees (displayStep), so the
    // network-check stages and the station page (all controller step 2) are
    // saved too. A pending saved resume is superseded once a fresh run
    // reaches the gateway (step >= 2) outside 「重新連線並繼續」.
    listenSelf((previous, next) {
      // Field rescue: decides (after this synchronous update) whether the
      // step / status / error changed enough for a session report.
      _field.onState();
      if (previous == null || next.step < 1) return;
      if (_shown(previous) == _shown(next)) return;
      if (_saved != null) {
        if (_resumingSaved || next.step < 2) return;
        _saved = null;
      }
      unawaited(_save());
    });
    // Round 19: the back office's identify during commissioning (backend
    // D5) — the gateway relays its ack to the phone.
    final link = _link;
    if (link is ForeignAcks) {
      final foreign = (link as ForeignAcks).foreignAcks.listen(_onForeignAck);
      ref.onDispose(foreign.cancel);
    }
    ref.onDispose(() {
      _generation++;
      _field.detach();
      _clock?.cancel();
      _health?.cancel();
      _poll?.cancel();
      _grace?.cancel();
      _rssiTimer?.cancel();
      _settleTimer?.cancel();
      unawaited(_link.disconnect());
    });
    return const CommissionState();
  }

  /// 拓撲（直連／星狀）或目標台數變動時：先用既有 ptus 清單，套用跟
  /// [_discover] 相同的範圍過濾（星狀模式下範圍外 PTU 不能選）重算
  /// pendingNext，並把已勾選中變成範圍外的部分丟掉；再裁到新的目標台數。
  ///
  /// Round 22: a switch direct ↔ star ([switched]) at step 7 drops the old
  /// mode's list, selection and pick instead ([_dropListForTopology]); the
  /// list is read again by [switchTopology] (or 「重新掃描」).
  void _onTopologyChanged(TopologySettingsState next, {bool switched = false}) {
    if (!ref.mounted) return;
    if (switched && state.step == 4) {
      _dropListForTopology(next.topology);
      return;
    }
    final isStar = next.topology.isStar;
    final pending = isStar
        ? state.ptus
              .where(
                (p) =>
                    _isOutOfRange(p) && !state.resetFailed.contains(p['mac']),
              )
              .length
        : 0;
    final selected = isStar
        ? state.ptus
              .where(
                (p) => state.selected.contains(p['mac']) && !_isOutOfRange(p),
              )
              .map((p) => p['mac'].toString())
              .toSet()
        : state.selected;
    if (selected.length != state.selected.length ||
        pending != state.pendingNext) {
      state = state.copy(selected: selected, pendingNext: pending);
    }
    _trimSelectionToTarget(next.targetCount);
  }

  /// Round 22 (field round 22: direct → star at step 7 left the direct
  /// pick as a star list of 1 with 「配置 1 台並開始監控」): the previous
  /// mode's step 7 list, selection, results, pick and notices are dropped;
  /// [CommissionState.relistReason] keeps the configure button waiting for
  /// the new list. A temporary 「不是這台？」 binding is undone by the star
  /// scan itself ([_listDiscover]).
  void _dropListForTopology(GatewayTopology topology) {
    state = state.copy(
      relistReason: topologySwitchedText(topology),
      ptus: [],
      selected: {},
      results: {},
      assignStatus: {},
      assignFailed: {},
      unassigned: {},
      missing: [],
      scannedTotal: 0,
      pendingNext: 0,
      resetFailed: {},
      starNotice: '',
      absentNotice: '',
      rescanNeeded: false,
      monitoringOk: false,
      directRaw: {},
      identifyNote: '',
      identifyLine: '',
      identifiedMac: null,
      directNotice: '',
      remoteIdentifyNote: '',
      remoteIdentifyHead: '',
      remoteIdentifyPtu: '',
      message: topologySwitchedText(topology),
      error: state.error,
    );
    _selectionTouched = false;
  }

  /// Round 22: the topology menu. At step 7 the switch drops the old mode's
  /// list ([_dropListForTopology]) and reads it again at once — the
  /// configure button stays disabled with the reason until the new list is
  /// in. Elsewhere it only changes the setting.
  Future<void> switchTopology(GatewayTopology topology) async {
    final settings = ref.read(topologyProvider.notifier);
    if (ref.read(topologyProvider).topology == topology) return;
    // The listener drops the list synchronously; the scan starts in the
    // same frame (never a tappable button in between).
    final saved = settings.setTopology(topology);
    if (ref.mounted &&
        state.step == 4 &&
        state.relistReason.isNotEmpty &&
        !state.busy &&
        !state.relinking &&
        !step7LinkLost(state)) {
      await discover();
    }
    await saved;
  }

  /// Keeps [target] selected PTUs (connected first, then strongest RSSI),
  /// dropping the rest;
  /// a no-op when already within the target (never auto-adds).
  void _trimSelectionToTarget(int target) {
    if (!ref.mounted || state.selected.length <= target) return;
    final kept =
        state.ptus.where((p) => state.selected.contains(p['mac'])).toList()
          ..sort(comparePtuForSelection);
    state = state.copy(
      selected: kept.take(target).map((p) => p['mac'].toString()).toSet(),
    );
  }

  /// Starts the Wi-Fi grace period: right after a connect or a reboot the
  /// gateway may still be joining its Wi-Fi.
  void _startWifiGrace() {
    _grace?.cancel();
    if (!ref.mounted) return;
    if (state.wifiGraceOver) {
      state = state.copy(wifiGraceOver: false, error: state.error);
    }
    _grace = Timer(_timing.wifiGrace, () {
      if (ref.mounted) {
        state = state.copy(wifiGraceOver: true, error: state.error);
      }
    });
  }

  void _setLoggedIn(bool value, [String? base]) {
    _loggedIn = value;
    if (value) _loginBase = base?.trim();
    if (ref.mounted && state.loggedIn != value) {
      state = state.copy(loggedIn: value, error: state.error);
    }
  }

  /// Round 13: the password that last logged in to a backend (memory only,
  /// never saved). A session the backend dropped (401, e.g. after the API
  /// was restarted) is renewed with it once before the installer is asked.
  (String, String)? _credentials;

  /// A successful login to [base] with [password].
  void _loginOk(String base, String password) {
    _setLoggedIn(true, base);
    _credentials = (base.trim(), password);
    // Field rescue: the password never reaches a report; what waited for
    // a login goes out now.
    _field.journal.addSecret(password);
    unawaited(_field.flush());
  }

  /// [password] as typed, or — left empty — the one that last logged in to
  /// this same [base].
  String _passwordFor(String base, String? password) {
    if ((password ?? '').isNotEmpty) return password!;
    final saved = _credentials;
    return saved != null && saved.$1 == base.trim() ? saved.$2 : '';
  }

  /// Runs a backend [call]; a 401 on a session believed valid logs in again
  /// once with the stored password and repeats it. Only a refused re-login
  /// ends the session (「登入失敗或已失效」, the password field kept).
  Future<T> _withRelogin<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on GatewayFailure catch (error) {
      final saved = _credentials;
      if (error.code != 'authentication' ||
          !_loggedIn ||
          saved == null ||
          saved.$1 != _loginBase) {
        rethrow;
      }
      try {
        await _api.login(saved.$1, saved.$2);
      } on GatewayFailure catch (failure) {
        // Unreachable backend: keep the session and let the caller retry.
        if (failure.code == 'authentication') {
          _credentials = null;
          _setLoggedIn(false);
        }
        rethrow;
      }
      return await call();
    }
  }

  Future<void> _wait(int seconds, int generation) async {
    await Future<void>.delayed(
      _link.demo ? const Duration(milliseconds: 1) : Duration(seconds: seconds),
    );
    if (generation != _generation || !ref.mounted) {
      throw const GatewayFailure('cancelled');
    }
  }

  void _check(int generation) {
    if (generation != _generation || !ref.mounted) {
      throw const GatewayFailure('cancelled');
    }
  }

  String _mac(dynamic value) =>
      value.toString().replaceAll(':', '').toUpperCase();

  Future<Map<String, dynamic>> _command(
    int generation,
    String op, [
    Map<String, dynamic> params = const {},
  ]) => _commandBusy(generation, op, params);

  /// [_command]; [onBusy] runs each time the gateway answers 'busy' (before
  /// the command is sent again).
  Future<Map<String, dynamic>> _commandBusy(
    int generation,
    String op,
    Map<String, dynamic> params, {
    void Function()? onBusy,
  }) async {
    _check(generation);
    if (sensitiveOps.contains(op) && state.config['otp_enabled'] == true) {
      throw const GatewayFailure('otp_enabled');
    }
    // Round 9: the firmware's single cmd_worker queue answers 'busy' while
    // it finishes earlier work (e.g. assigns left over from a killed run).
    // That is transient for every op: wait and retry before giving up.
    String? before;
    try {
      for (int attempt = 0; ; attempt++) {
        // Field rescue: every try is journaled (params masked) for the
        // diagnostics package.
        final watch = Stopwatch()..start();
        var answered = false;
        try {
          if (takeFieldFault(op)) {
            await Future<void>.delayed(const Duration(seconds: 3));
            throw const GatewayFailure('timeout');
          }
          final result = await _link.command(op, params);
          answered = true;
          _journalBle(op, params, 'ok', watch, result: result);
          _check(generation);
          return result;
        } on GatewayFailure catch (error) {
          if (!answered) {
            _journalBle(op, params, _journalStatus(error), watch, error: error);
          }
          if (error.code != 'busy' || attempt >= busyRetryLimit) rethrow;
          _check(generation);
          before ??= state.message;
          state = state.copy(message: gatewayBusyText, error: state.error);
          onBusy?.call();
          await Future<void>.delayed(
            _link.demo ? const Duration(milliseconds: 1) : busyRetryDelay,
          );
          _check(generation);
        } catch (error) {
          if (!answered) {
            _journalBle(op, params, _journalStatus(error), watch, error: error);
          }
          rethrow;
        }
      }
    } finally {
      if (before != null && ref.mounted && state.message == gatewayBusyText) {
        state = state.copy(message: before, error: state.error);
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    int generation,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    _check(generation);
    final watch = Stopwatch()..start();
    final Map<String, dynamic> result;
    try {
      result = await _withRelogin(() => _api.request(method, path, body));
      _journalHttp(method, path, watch);
    } catch (error) {
      _journalHttp(method, path, watch, error: error);
      rethrow;
    }
    if (generation != _generation &&
        path.endsWith('/bot-monitor') &&
        body?['enabled'] == false) {
      try {
        await _api.request('PATCH', path, {'enabled': true});
      } catch (_) {}
    }
    _check(generation);
    return result;
  }

  Future<bool> _safeStop() async {
    if (!_provisioningMayBeActive) return true;
    if (_stopping != null) return _stopping!;
    final future = () async {
      try {
        // Never leave the gateway with BLE or upload switched off: an
        // interrupted step 8 turns monitoring back on.
        await _rawCommand('set_ble_enabled', {'enabled': true});
        await _rawCommand('set_data_upload', {'enabled': true});
        final config = await _rawCommand('get_config');
        final safe =
            config['ble_enabled'] != false && config['upload_paused'] != true;
        if (safe) _provisioningMayBeActive = false;
        return safe;
      } catch (_) {
        return false;
      }
    }();
    _stopping = future;
    try {
      return await future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
    } finally {
      _stopping = null;
    }
  }

  /// [relinkStep] (4 = step 7 scan, 5 = step 8): a link loss ending this run
  /// hands over to the automatic reconnect ([_autoRelink]) of that step.
  ///
  /// [countdown] (default [timeout]): the 「最多等待 N 秒」 shown when the
  /// action keeps its own, shorter deadline (the overall [timeout] then
  /// only guards against a hung command).
  Future<void> _run(
    String label,
    int timeout,
    Future<void> Function(int) action, {
    int? relinkStep,
    int? countdown,
  }) async {
    if (state.busy) return;
    final generation = ++_generation;
    _diagnosis = null;
    // Field rescue rule 1: a restart notice that appears during this run.
    final rebootBefore = state.gatewayReboot?.to;
    state = state.copy(
      busy: true,
      message: label,
      seconds: countdown ?? timeout,
      reconnectFailed: false,
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ref.mounted && state.seconds > 0) {
        state = state.copy(seconds: state.seconds - 1);
      }
    });
    // Only the verify loop's own end or this overall timeout may be explained
    // by the data diagnosis; a BLE/HTTP command timeout keeps its own text.
    bool timedOut = false;
    try {
      await action(generation).timeout(
        Duration(seconds: timeout),
        onTimeout: () {
          if (generation == _generation) _generation++;
          timedOut = true;
          throw const GatewayFailure('timeout');
        },
      );
      _check(generation);
      await _save();
    } catch (rawError) {
      var error = rawError;
      // Superseded by cancel() (or a newer run): cancel() sets its own text.
      if (error is GatewayFailure &&
          error.code == 'cancelled' &&
          generation != _generation &&
          !timedOut) {
        return;
      }
      // Step 8: any phone↔gateway link failure (adapter off, a dropped GATT
      // client, or the link's own epoch bump surfacing as 'cancelled' while
      // this run is still current) is a link loss: keep assignedOk, show the
      // banner and 「重新連線並繼續（剩 N 台）」, never fall back to step 2
      // (round 7b).
      if (ref.mounted &&
          state.step == 5 &&
          isStep8LinkLoss(error, generation == _generation)) {
        // Round 13: remembered so the automatic reconnect starts only for
        // the loss of the run still current (not after 「取消操作」).
        _step8LossGeneration = generation;
        state = state.copy(resumePending: true);
        unawaited(_save());
        if (!(error is GatewayFailure &&
            (error.code == 'phone_link_lost' ||
                error.code == 'reconnect_failed'))) {
          error = GatewayFailure('phone_link_lost', detail: error.toString());
        }
      }
      // Round 12: step 7 (scan running) — same link-loss handling as step 8.
      if (ref.mounted &&
          state.step == 4 &&
          isStep8LinkLoss(error, generation == _generation) &&
          !(error is GatewayFailure && error.code == 'reconnect_failed')) {
        if (!(error is GatewayFailure && error.code == 'phone_link_lost')) {
          error = GatewayFailure('phone_link_lost', detail: error.toString());
        }
      }
      if (error is GatewayFailure && error.code == 'authentication') {
        _setLoggedIn(false);
      }
      if (error is GatewayFailure &&
          (error.code == 'disconnected' ||
              error.code == 'not_connected' ||
              error.code == 'phone_link_lost')) {
        _stopWatch(UploadWatch.linkLost);
      }
      _classifyingFailure = true;
      final safe = await _safeStop();
      final failure = error is GatewayFailure
          ? error
          : GatewayFailure.unexpected(error);
      final diagnosis = _diagnosis;
      final detailed =
          diagnosis != null &&
          diagnosis.$1 == generation &&
          ((failure.code == 'timeout' && timedOut) ||
              failure.code == 'incomplete');
      // A plain timeout may be the gateway restarting: say so instead of
      // 「等待超時」 (the notice names the reason).
      final rebooted =
          failure.code == 'timeout' &&
          !detailed &&
          ref.mounted &&
          await _rebootedAfterTimeout();
      if (ref.mounted) {
        final linkIssue =
            failure.code == 'phone_link_lost' ||
            failure.code == 'reconnect_failed' ||
            failure.code == 'monitor_unconfirmed';
        final log = _connectLog;
        state = state.copy(
          errorDetail: log != null && log.$1 == generation && log.$2.isNotEmpty
              ? '${failure.toString()}\n連線失敗紀錄：${log.$2.join('、')}'
              : failure.toString(),
          reconnectFailed: failure.code == 'reconnect_failed',
          // Round 11: no 「連線中（第 n 次）」 left beside the banner.
          message: linkIssue && _resumeGeneration == generation
              ? ''
              : state.message,
          error:
              failure.code == 'reconnect_failed' &&
                  _resumeGeneration == generation &&
                  log != null &&
                  log.$1 == generation &&
                  log.$2.isNotEmpty
              ? reconnectFailedAttemptsText(log.$2.length)
              : linkIssue
              ? failure.message
              : rebooted
              ? gatewayRebootRetryText
              : !safe
              ? '尚未確認 Gateway 已恢復監控，請重新連線核對設定。'
              : detailed
              ? '資料驗證未通過：\n${diagnosis.$2}'
              : failure.message,
        );
        // Field rescue: classified after the red box is set, so the report
        // carries the very text on screen. Never throws.
        final rebootNow = state.gatewayReboot?.to;
        _field.onFailure(
          failure,
          rebooted:
              rebooted || (rebootNow != null && rebootNow != rebootBefore),
          // A link issue's red box is the link text, not 「尚未確認…監控」.
          safe: linkIssue ? null : safe,
          timedOut: timedOut,
          runLabel: label,
          ctlStep: state.step,
        );
      }
    } finally {
      _classifyingFailure = false;
      _clock?.cancel();
      if (ref.mounted) {
        // Round 13: the automatic reconnect follows at once — relinking is
        // set with busy:false in one update, so the button never flashes
        // 「重新連線並繼續」 during the hand-over.
        final lost =
            relinkStep != null && _linkLostAt(relinkStep, running: true);
        final follows = lost && autoRelinkRounds > 0 && !_autoRelinking;
        state = state.copy(
          busy: false,
          seconds: 0,
          error: state.error,
          relinking: follows ? true : null,
          // Round 22: a new loss inside the automatic reconnect's round
          // (e.g. while step 8 assigned again) is 「重新連線中」 again at once.
          relinkStage: follows || (lost && state.relinking)
              ? RelinkStage.reconnecting
              : null,
        );
        if (_topologyDeferred) {
          final switched = _topologySwitchDeferred;
          _topologyDeferred = false;
          _topologySwitchDeferred = false;
          _onTopologyChanged(ref.read(topologyProvider), switched: switched);
        }
      }
    }
  }

  /// 1-based step number on screen (the step list / 「第 N 步」).
  int _shown(CommissionState s) =>
      displayStep(s, ref.read(backendEnvProvider)) + 1;

  /// 「重新連線並繼續」 of a saved run is in progress.
  bool _resumingSaved = false;

  Future<void> _save() async {
    final shown = _shown(state);
    final completed = state.step == 7 && state.verified;
    // Round 15: a finished run keeps 「上次配置已完成」 until a later run
    // reaches the PTU steps; its resume data is dropped (nothing to resume).
    if (completed) {
      _completedSticky = true;
    } else if (_completedSticky && state.step < 4) {
      return;
    } else {
      _completedSticky = false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (completed) {
      await prefs.setString(
        _link.demo ? 'demo_progress' : 'progress',
        jsonEncode({
          'step': state.step,
          'shown': shown,
          'completed': true,
          'count': state.ptus.length,
          'site': site,
          'gateway': gateway,
        }),
      );
      return;
    }
    await prefs.setString(
      _link.demo ? 'demo_progress' : 'progress',
      jsonEncode({
        'step': state.step,
        'shown': shown,
        'completed': false,
        'count': state.ptus.length,
        'site': site,
        'gateway': gateway,
        'peer': state.peer?.id,
        'peer_name': state.peer?.name,
        if (_boot != null && _boot!.peer == state.peer?.id)
          'boot_count': _boot!.count,
        'selected': state.selected.toList(),
        'done': _doneAssign,
        'inflight': _inflightAssign,
        'assignments': state.ptus
            .map((p) => {'mac': p['mac'], 'id': p['device_number']})
            .toList(),
        // Field rescue: 「重新連線並繼續」 keeps the same help code.
        'field_session': ?_field.persisted(),
      }),
    );
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_link.demo ? 'demo_progress' : 'progress');
    if (value != null && ref.mounted) {
      Map data;
      try {
        data = jsonDecode(value) as Map;
      } catch (_) {
        return;
      }
      if (data['completed'] == true) {
        _completedSticky = true;
        state = state.copy(
          savedResume: false,
          lastCompleted: true,
          message: completedText(
            data['site'],
            data['gateway'],
            (data['count'] as num?)?.toInt() ?? 0,
          ),
        );
        return;
      }
      _saved = data;
      await _field.restore(data['field_session']);
      if (!ref.mounted) return;
      // Compared on 「重新連線並繼續」: restarted while the APP was closed?
      if (data['peer'] is String && data['boot_count'] is int) {
        _boot = (
          peer: data['peer'] as String,
          count: data['boot_count'] as int,
        );
      }
      final step = data['step'] is int ? data['step'] as int : 0;
      final done = <String, int>{
        for (final e in ((data['done'] as Map?) ?? const {}).entries)
          if (e.value is int) e.key.toString(): e.value as int,
      };
      final selected = ((data['selected'] as List?) ?? const [])
          .map((m) => m.toString())
          .toSet();
      final inflight = <String, int>{
        for (final e in ((data['inflight'] as Map?) ?? const {}).entries)
          if (e.value is int && !done.containsKey(e.key.toString()))
            e.key.toString(): e.value as int,
      };
      final pending = step == 5
          ? selected
                .where((m) => !done.containsKey(m) && !inflight.containsKey(m))
                .length
          : 0;
      state = state.copy(
        config: {'site_id': data['site'], 'gateway_id': data['gateway']},
        savedResume: data['peer'] is String && step >= 4 && step <= 5,
        savedProgress: true,
        message: resumeText(
          step,
          done.values.toList(),
          pending,
          inflight: inflight.values.toList(),
          shown: data['shown'] is int ? data['shown'] as int : null,
        ),
      );
    }
  }

  /// 「重新開始」 after a finished run: forget the saved progress.
  Future<void> clearCompleted() async {
    _field.end('abandoned');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_link.demo ? 'demo_progress' : 'progress');
    _saved = null;
    _completedSticky = false;
    if (ref.mounted) {
      state = state.copy(
        lastCompleted: false,
        savedResume: false,
        savedProgress: false,
        message: '',
      );
    }
  }

  /// Saved resume skips the login of steps 5/6: ask for it first when star
  /// auto-reset or later steps (step 9 verify) need the backend.
  bool get savedResumeNeedsLogin {
    final data = _saved;
    if (data == null || _loggedIn) return false;
    final step = data['step'] as int? ?? 0;
    return ref.read(topologyProvider).topology.isStar || step >= 4;
  }

  /// 「重新連線並繼續」 after a restart: reconnect the saved gateway, jump
  /// back to the PTU list, and at step 8 configure only the unfinished PTUs.
  Future<void> resumeSaved() async {
    final data = _saved;
    if (state.busy || data == null || data['peer'] is! String) return;
    final peer = GatewayPeer(
      data['peer'] as String,
      (data['peer_name'] as String?) ?? 'Gateway',
      0,
    );
    final step = data['step'] as int? ?? 0;
    final done = <String>{};
    for (final e in ((data['done'] as Map?) ?? const {}).entries) {
      if (e.value is int) {
        done.add(e.key.toString());
        _doneAssign[e.key.toString()] = e.value as int;
      }
    }
    // In flight when killed: the gateway may or may not have taken it; only
    // the reconcile below (get_ble_devices) decides.
    _inflightAssign.clear();
    for (final e in ((data['inflight'] as Map?) ?? const {}).entries) {
      if (e.value is int && !done.contains(e.key.toString())) {
        _inflightAssign[e.key.toString()] = e.value as int;
      }
    }
    final wanted = ((data['selected'] as List?) ?? const [])
        .map((m) => m.toString())
        .toSet();
    try {
      await _link.prepare();
    } catch (error) {
      final failure = error is GatewayFailure
          ? error
          : GatewayFailure.unexpected(error);
      state = state.copy(error: failure.message);
      _field.onFailure(failure, ctlStep: state.step);
      return;
    }
    _resumingSaved = true;
    try {
      await _connect(peer);
    } finally {
      _resumingSaved = false;
    }
    if (!ref.mounted || state.error != null || state.step != 2) return;
    _saved = null;
    state = state.copy(
      step: 4,
      checkPassed: true,
      savedResume: false,
      savedProgress: false,
      config: {...state.config, 'choose_station': false},
      results: {},
      assignStatus: {},
      message: '已重新連線，由 Gateway 重新掃描 PTU。',
    );
    await discover();
    if (!ref.mounted || state.error != null || step != 5) return;
    final seen = state.ptus.map((p) => p['mac'].toString()).toSet();
    final keep = wanted.where(seen.contains).toSet();
    if (keep.isEmpty) return;
    // Merge the saved choice with this scan's connected in-range PTUs
    // (round 7b: a connected one was left unticked after a restore).
    final merged = {...keep};
    for (final mac in _preselect(state.ptus, targetPtuCount)) {
      if (merged.length >= targetPtuCount) break;
      final row = state.ptus.firstWhere((p) => p['mac'] == mac);
      if (row['connected'] == true) merged.add(mac);
    }
    state = state.copy(selected: merged);
    // Round 9: saved 'done' the gateway now contradicts (re-deployed site,
    // number reset) no longer counts as configured.
    final staleDone = _staleAssigned(done, state.ptus);
    done.removeAll(staleDone);
    for (final mac in staleDone) {
      _doneAssign.remove(mac);
    }
    // The gateway may have taken assignments the APP never saw acked (killed
    // mid-step): what it reports connected with a matching number counts.
    // The prompt counts what the gateway reports, not the saved file.
    final confirmed = _reconcileFrom(state.ptus, merged);
    done.addAll(confirmed);
    _inflightAssign.clear();
    final ids = [
      for (final m in confirmed)
        if (_doneAssign[m] != null) _doneAssign[m]!,
    ];
    state = state.copy(
      message: resumeText(5, ids, merged.difference(done).length),
    );
    if (merged.every(done.contains)) {
      // Nothing left to assign: decide 「開始驗證」 vs 「恢復監控」.
      final generation = _generation;
      try {
        await _computeMonitoringOk(generation, state.ptus);
      } catch (_) {}
      return;
    }
    await configurePtus(skip: done.intersection(merged));
  }

  Future<void> prepare(String base, String password, {bool offline = false}) =>
      _run('檢查藍牙與後端連線', 30, (generation) async {
        await _link.prepare();
        _check(generation);
        _backend = describeBackend(Uri.tryParse(base.trim()));
        if (!offline) {
          final secret = _passwordFor(base, password);
          await _api.login(base, secret);
          _check(generation);
          _loginOk(base, secret);
        }
        state = state.copy(
          step: 1,
          offline: offline,
          message: offline ? '離線模式：最後仍需登入驗證資料' : '準備完成',
        );
      });
  Future<void> scan() => _run('搜尋附近的閘道器', 30, (generation) async {
    final peers = await _link.scan();
    _check(generation);
    state = state.copy(
      peers: peers,
      message: peers.isEmpty ? '未找到閘道器，請靠近並確認電源後重掃。' : '請選擇要開通的閘道器',
    );
  });

  /// Blinks the gateway LED; firmware 1.7.20+ (`identify_ptu_supported`)
  /// also writes the connected PTU ([target] ptu | gateway | both) and acks
  /// its MAC/RSSI. Older firmware gets the bare op, as before.
  ///
  /// Per cmd_contract.md's identify section: with target=ptu, no PTU
  /// connected is a fail ack (`not_connected`) — handled below by falling
  /// back to a gateway-only identify. With target=both (the default, and
  /// the only target this APP's UI sends), the gateway does **not** fail
  /// the ack just because the PTU write didn't land; it still acks ok and
  /// blinks its own LED, reporting the PTU write outcome in `ptu_write`
  /// (`"ok"` on success, otherwise a reason such as `"not_connected"`).
  /// Only when *both* the gateway LED and the PTU write fail does the ack
  /// itself fail. So for target=both a non-ok `ptu_write` is read out of a
  /// successful ack, not caught as an exception — never resent, never
  /// treated as a dropped phone↔gateway link.
  ///
  /// Round 15: [CommissionState.identifyNote] (beside the button) reads
  /// 「已送出，請看樁上燈號」 as soon as it is tapped, then the acked PTU;
  /// cleared again when the identify fails.
  ///
  /// Round 17: at step 7 a phone↔gateway link loss here reconnects by
  /// itself like any other step 7 loss (field round 17: the identify was
  /// the first command after ~11 s idle, the link had dropped with 0x08 and
  /// the red box waited for a tap); the identification made before stands.
  Future<void> identify({String target = 'both'}) async {
    await _run('辨識閘道器', 12, relinkStep: 4, (generation) async {
      if (state.config['identify_supported'] != true) {
        throw const GatewayFailure('identify_unsupported');
      }
      final note = state.identifyNote, line = state.identifyLine;
      // Round 19: at once, until the ack (firmware 1.7.25+ waits up to
      // 1.5 s for the PTU's answer before it acks).
      final pending = identifyPtuSupported(state.config)
          ? identifyPendingText
          : identifyPendingGatewayText;
      state = state.copy(identifyNote: pending, identifyLine: pending);
      try {
        await _identify(generation, target);
      } catch (error) {
        if (ref.mounted) {
          state = isStep8LinkLoss(error, true)
              ? state.copy(identifyNote: note, identifyLine: line)
              : state.copy(identifyNote: '', identifiedMac: null);
        }
        rethrow;
      }
    });
    if (ref.mounted && !_autoRelinking && _linkLostAt(4)) {
      await _autoRelink(4);
    }
  }

  /// Round 19 (field round 19: the back office flashed the pile and the
  /// installer was not told): an identify ack of the back office's, while a
  /// gateway is connected, becomes [CommissionState.remoteIdentifyNote] —
  /// nothing else (step, busy, error, identification) changes. Other
  /// foreign acks are ignored.
  ///
  /// Round 24: the note names what blinked — the gateway only, or 「PTU #3」
  /// found in the list on screen ([remoteIdentifyText]).
  void _onForeignAck(Map<String, dynamic> ack) {
    if (!ref.mounted || state.peer == null) return;
    if (ack['status'] != 'ok' || !isIdentifyAck(ack)) return;
    state = state.copy(
      error: state.error,
      remoteIdentifyNote: remoteIdentifyText(ack, ptus: state.ptus),
      remoteIdentifyHead: remoteIdentifyHeadText(ack),
      remoteIdentifyPtu: remoteIdentifyPtuText(ack),
      remoteIdentifyCount: state.remoteIdentifyCount + 1,
    );
  }

  Future<void> _identify(int generation, String target) async {
    if (!identifyPtuSupported(state.config)) {
      await _command(generation, 'identify');
      state = state.copy(
        message: '請找出雙閃藍燈的閘道器，6 秒後會恢復原本燈號。',
        identifyNote: identifyNoteText(const {}),
        identifyLine: identifyLineText(const {}),
      );
      return;
    }
    Map<String, dynamic> ack;
    try {
      ack = await _command(generation, 'identify', {'target': target});
      // Round 17: right after a (re)connect the PTU write can come back
      // not_connected (the gateway's GATT link is not ready yet): once
      // more after [identifyRetryDelay], then show whatever that says.
      if (directFlow &&
          state.step == 4 &&
          ack['ptu_write'] == 'not_connected') {
        await Future<void>.delayed(identifyRetryDelay);
        _check(generation);
        ack = await _command(generation, 'identify', {'target': target});
      }
    } on GatewayFailure catch (e) {
      // The gateway's own not_connected means "no PTU connected", not a
      // phone link loss: never let it trigger the relink handling.
      // Kept for target=ptu (which does fail outright on it) and as a
      // safety net for a future/older firmware that fails target=both
      // too.
      if (!e.fromGateway || e.code != 'not_connected') rethrow;
      if (target != 'both') throw const GatewayFailure('identify_no_ptu');
      await _command(generation, 'identify', {'target': 'gateway'});
      state = state.copy(
        message: identifyNoPtuText,
        identifyNote: identifyNoteText(const {'ptu_write': 'not_connected'}),
        identifyLine: identifyLineText(const {'ptu_write': 'not_connected'}),
        identifiedMac: null,
      );
      return;
    }
    final ptuWrite = ack['ptu_write'];
    state = state.copy(
      message: ptuWrite == null || ptuWrite == 'ok'
          ? identifyAckText(ack)
          : identifyPtuFailedText(ptuWrite.toString()),
      identifyNote: identifyNoteText(ack),
      identifyLine: identifyLineText(ack),
    );
    // Direct flow: the ack names the PTU that actually blinks. If the
    // gateway has switched since the pick was shown, show its new pick.
    final blinked = ack['mac'];
    final shown = state.selected.firstOrNull;
    if (directFlow &&
        state.step == 4 &&
        blinked != null &&
        shown != null &&
        !sameMac(blinked, shown)) {
      final status = await _command(generation, 'get_status');
      _takeDirect(status['direct']);
      _syncDirectPick();
      state = state.copy(
        identifyNote: identifyNoteText(ack),
        identifyLine: identifyLineText(ack),
      );
    }
    // Round 15b: the PTU that blinked is the identified one, as long as it
    // is still the gateway's pick (no ack MAC: the PTU did not blink).
    if (directFlow && state.step == 4) {
      final picked = state.direct?.pickedMac;
      final ok = blinked != null && picked != null && sameMac(blinked, picked);
      state = state.copy(
        identifiedMac: ok ? blinked.toString() : null,
        directNotice: ok ? '' : state.directNotice,
      );
    }
  }

  Future<void> connect(GatewayPeer peer) async {
    if (state.busy) return;
    _stopWatch(UploadWatch.idle);
    _settleTimer?.cancel();
    state = state.copy(
      net: const {},
      // A notice from before is not repeated; [_connect] compares again.
      gatewayReboot: null,
      directRaw: const {},
      directSettling: false,
      checkPassed: false,
      uploadLate: false,
      identifiedMac: null,
      tempBoundMac: null,
      tempRestoreMac: null,
      strayBindMac: null,
      directNotice: '',
      error: state.error,
    );
    await _connect(peer);
    if (ref.mounted &&
        state.step == 2 &&
        state.error == null &&
        identical(state.peer, peer)) {
      _startWifiGrace();
    }
    _watchUploadIfPending();
  }

  /// get_net_status for the network check; null when the firmware cannot
  /// answer it (before 1.7) or is not ready yet (polling reads it later).
  Future<Map<String, dynamic>?> _readNet(
    int generation,
    Map<String, dynamic> config,
  ) async {
    if (profileFor(config['fw_version']?.toString() ?? '') !=
        ProtocolProfile.current) {
      return null;
    }
    try {
      return await _command(generation, 'get_net_status');
    } catch (error) {
      // Round 18: a dropped link is not "cannot answer": the persistent
      // connect ([_connect]) reconnects and reads it again.
      if (isLinkDrop(error)) rethrow;
      _check(generation);
      return null;
    }
  }

  /// get_config plus what get_net_status says about the upload (MQTT).
  static Map<String, dynamic> _withUpload(
    Map<String, dynamic> config,
    Map<String, dynamic>? net,
  ) => {
    ...config,
    if (net != null)
      for (final key in mqttStatusKeys)
        if (net.containsKey(key)) key: net[key],
  };

  static Map<String, dynamic> _netFields(Map<String, dynamic>? net) => {
    if (net != null)
      for (final key in gatewayNetKeys)
        if (net.containsKey(key)) key: net[key],
  };

  Future<void> _connect(
    GatewayPeer peer,
  ) => _run('正在連線 ${peer.name}，請保持靠近', 120, (generation) async {
    // Stage text (清除舊連線／正在連線／第 n 次重試) on the first connect too,
    // not only on a relink (round 7b saw none here).
    // Round 10: 133 / disconnected is retried until [connectPersistence].
    // Round 18: the reads right after the link came up (get_config,
    // get_net_status, get_ble_devices) are part of that persistent connect
    // (field round 18: the link dropped 5 s after connecting, right after
    // the get_config ACK, and step 2 stopped until the gateway was picked
    // again). A reconnect shows 「連線中（第 n 次）」 and reads them again.
    late Map<String, dynamic> config;
    Map<String, dynamic>? net;
    List<Map<String, dynamic>> devices = const [];
    try {
      await _persistentLink(generation, peer, () async {
        state = state.copy(message: linkConfirmingText);
        for (int attempt = 0; ; attempt++) {
          try {
            await _command(generation, 'ping');
            break;
          } catch (error) {
            // A dropped link is not answered by more pings: reconnect.
            if (isLinkDrop(error)) rethrow;
            if (attempt == 4) rethrow;
            await _wait(3, generation);
          }
        }
        config = await _command(generation, 'get_config');
        _check(generation);
        // Restarted since the last read (link drop, timeout, APP closed)?
        _noteBoot(config, peerId: peer.id);
        try {
          await RecentGateways.remember(
            _link.demo,
            peer,
            config['gateway_uid'],
          );
        } catch (_) {
          /* Recents must not block a successful BLE connection. */
        }
        _check(generation);
        // 網路體檢: the gateway's own Wi-Fi and upload state.
        final read = await _readNet(generation, config);
        net = read;
        if (read != null) _noteBoot(read, peerId: peer.id);
        if (config['fleet_joined'] == true) {
          final existing = await _command(generation, 'get_ble_devices');
          devices = (existing['devices'] as List? ?? [])
              .map((d) => Map<String, dynamic>.from(d as Map))
              .toList();
        }
      });
    } catch (_) {
      // Round 18: 「藍牙已連線，正在確認…」 (or 「連線中（第 n 次）」) must not
      // stay beside the error once the connect has given up.
      if (ref.mounted && generation == _generation) {
        state = state.copy(message: '', error: state.error);
      }
      rethrow;
    }
    if (config['fleet_joined'] == true) {
      state = state.copy(
        step: 2,
        peer: peer,
        config: {..._withUpload(config, net), 'choose_station': true},
        net: _netFields(net),
        checkPassed: false,
        ptus: devices,
        selected: devices.map((d) => d['mac'].toString()).toSet(),
        message: '已連線，此閘道器已有站點設定。先做網路體檢，再選擇沿用或設定新站。',
        uploadNotice: '',
      );
      return;
    }
    if (config['fleet_joined'] != true) {
      // Initial guess for a brand-new gateway: find some free site+gateway
      // slot to prefill, through the same suggestGateway the site field
      // uses later (one source of truth, see GatewaySuggestKind).
      int? site;
      int gw = 1;
      var offline = !_loggedIn;
      if (_loggedIn) {
        try {
          final discover = await _request(
            generation,
            'GET',
            '/api/gateways/discover',
          );
          final fleet = await _request(
            generation,
            'GET',
            '/api/gateways/fleet-status',
          );
          final occupied = <String>{};
          for (final row in [
            ...(discover['items'] as List? ?? []),
            ...(fleet['gateways'] as List? ?? []),
          ]) {
            final uid = row['mac'] ?? row['last_seen_mac'];
            if (uid == null || _mac(uid) != _mac(config['gateway_uid'])) {
              occupied.add('${row['site_id']}/${row['gateway_id']}');
            }
          }
          candidate:
          for (int s = 1; s <= 65535; s++) {
            if (List.generate(
              kMaxGatewayId,
              (i) => i + 1,
            ).every((g) => occupied.contains('$s/$g'))) {
              continue; // known fully occupied: skip without a network call
            }
            final (g, kind) = await suggestGateway(s);
            _check(generation);
            if (kind == GatewaySuggestKind.online) {
              site = s;
              gw = g;
              break candidate;
            }
            if (kind == GatewaySuggestKind.offline) {
              site = s;
              gw = g;
              offline = true;
              break candidate;
            }
            // full: this site has no free 1–kMaxGatewayId slot, try the next one.
          }
        } catch (_) {
          offline = true;
        }
      }
      if (site == null) {
        site = 1;
        gw = _offlineGatewaySuggestion(1);
        offline = true;
      }
      config['suggested_site_id'] = site;
      config['suggested_gateway_id'] = gw;
      config['suggested_offline'] = offline;
    }
    state = state.copy(
      step: 2,
      peer: peer,
      config: _withUpload(config, net),
      net: _netFields(net),
      checkPassed: false,
      message: '已連線。先做網路體檢，再設定身份與 Wi-Fi。',
      uploadNotice: '',
    );
  });

  // ---- 網路體檢 (step 2 before the station choice) ----

  bool get _atCheck => !state.busy && state.step == 2 && !state.checkPassed;

  /// Leaves the network check: to the station choice, the identity/Wi-Fi
  /// form (new gateway), or, after a Wi-Fi change that keeps the station, to
  /// a fresh gateway PTU scan. [skip] continues although the check has not
  /// passed; the Wi-Fi-only path still requires a successful network check.
  Future<void> passNetworkCheck({bool skip = false}) async {
    if (!_atCheck) return;
    if (state.config['wifi_only'] == true) {
      if (!state.networkReady) {
        state = state.copy(error: uploadNotReadyText);
        _field.noteErrorCode(_notReadyCode());
        return;
      }
      state = state.copy(
        step: 4,
        checkPassed: true,
        results: {},
        assignStatus: {},
        verified: false,
        report: '',
        message: 'Wi-Fi 已更新，站點設定保留。接著由 Gateway 搜尋 PTU，請確認要監控的裝置。',
      );
      await discover();
      return;
    }
    final station = state.config['choose_station'] == true;
    final String message;
    if (station) {
      message = skip ? '網路體檢未通過：可重設 Wi-Fi 或設定新站點；沿用要等網路正常。' : '網路體檢通過，請選擇站點。';
    } else {
      message = skip ? '網路體檢未通過，仍可設定新站點；之後會再確認資料上傳。' : '網路體檢通過，請設定身份與 Wi-Fi。';
    }
    state = state.copy(checkPassed: true, message: message);
  }

  /// 「重設 Wi-Fi」 from the network check. A station that is set up keeps
  /// its site / gateway numbers and PTUs (Wi-Fi only); a new gateway gets the
  /// identity + Wi-Fi form.
  ///
  /// [target]: the upload target must change too. It is sent FIRST, without
  /// waiting for the upload: set_mqtt_target always reboots, and the boot
  /// reads the Wi-Fi from NVS, while set_wifi reconnects in place without a
  /// reboot. So target-then-Wi-Fi costs one reboot and the gateway starts
  /// uploading to the right place as soon as the new Wi-Fi works; the other
  /// order would also reboot once but first upload to the old place.
  Future<void> startWifiFix({MqttTarget? target}) async {
    if (!_atCheck) return;
    if (target != null) {
      await switchUploadTarget(target, waitUpload: false);
      // Reconnect or read-back failed: stay on the check with its message.
      if (!ref.mounted || state.error != null || state.step != 2) return;
    }
    if (!_atCheck) return;
    final station = state.config['fleet_joined'] == true;
    state = state.copy(
      checkPassed: true,
      config: {
        ...state.config,
        'choose_station': false,
        'new_station': false,
        'wifi_only': station,
      },
      results: {},
      assignStatus: {},
      verified: false,
      report: '',
      message: station
          ? '保留目前站點與 PTU，只重設 Wi-Fi。請選 2.4 GHz 的 Wi-Fi。'
          : '請設定身份與 Wi-Fi（Gateway 只能用 2.4 GHz）。',
    );
  }

  /// Back to the network check from the station choice or a Wi-Fi form.
  /// A station gets its PTU selection back (only a new station clears it).
  void backToNetworkCheck() {
    if (state.busy || state.step != 2 || !state.checkPassed) return;
    final station = state.config['fleet_joined'] == true;
    state = state.copy(
      checkPassed: false,
      config: {
        ...state.config,
        'choose_station': station,
        'new_station': false,
        'wifi_only': false,
      },
      selected: station
          ? state.ptus.map((d) => d['mac'].toString()).toSet()
          : null,
      message: '網路體檢：確認 Gateway 的 Wi-Fi 與資料上傳。',
    );
    _watchUploadIfPending();
  }

  /// From the upload re-check after a Wi-Fi change back to the station choice.
  void backToStationChoice() {
    if (!_atCheck || state.config['fleet_joined'] != true) return;
    state = state.copy(
      checkPassed: true,
      config: {
        ...state.config,
        'choose_station': true,
        'new_station': false,
        'wifi_only': false,
      },
      message: '請選擇站點。沿用要等 Gateway 開始上傳資料。',
    );
  }

  Future<void> chooseStation({
    required bool newStation,
    bool wifiOnly = false,
  }) async {
    if (state.busy || state.config['choose_station'] != true) return;
    // Keep the network gate before proceeding with an existing station.
    if (!newStation && !wifiOnly && !state.networkReady) {
      state = state.copy(error: reuseBlockedText);
      _field.noteErrorCode(_notReadyCode());
      return;
    }
    state = state.copy(
      step: newStation || wifiOnly ? 2 : 4,
      checkPassed: true,
      config: {
        ...state.config,
        'choose_station': false,
        'new_station': newStation,
        'wifi_only': wifiOnly && !newStation,
      },
      selected: newStation ? <String>{} : state.selected,
      results: {},
      assignStatus: {},
      verified: false,
      report: '',
      message: newStation
          ? '請輸入新的站點 ID 與 Wi-Fi；儲存後才會變更閘道器。'
          : wifiOnly
          ? '保留目前站點與 PTU，僅更新 Wi-Fi。'
          : '沿用目前站點，由 Gateway 搜尋 PTU，請確認要監控的裝置。',
    );
    if (!newStation && !wifiOnly) await discover();
  }

  Future<void> configureWifi(
    int newSite,
    int newGateway,
    String ssid,
    String password, {
    bool replaceExisting = false,
  }) async {
    await _configureWifi(newSite, newGateway, ssid, password, replaceExisting);
    _watchUploadIfPending();
  }

  /// Auto-picks the gateway number for [forSite] so the user only enters the
  /// site ID: keeps this gateway's own existing number when it is already
  /// assigned to this site (avoids re-numbering and moving its data row),
  /// otherwise asks the backend for the first free 1–kMaxGatewayId slot. When the
  /// backend cannot be reached, falls back to parsing BLE peer names
  /// (`GIOS-S{site}-GW{n}`, from the step-1 scan) for the smallest unused n.
  /// This is the single source of truth for the auto-number: both the
  /// initial post-connect guess and the user-typed-site lookup call it.
  Future<(int, GatewaySuggestKind)> suggestGateway(int forSite) async {
    final curSite = (state.config['site_id'] as num?)?.toInt() ?? 0;
    if (curSite != 0 && curSite == forSite) {
      return (gateway, GatewaySuggestKind.online);
    }
    if (_loggedIn) {
      try {
        // Prefer fleet-status (one call) to find the smallest unused id,
        // confirmed by a single check-identity; only fall back to checking
        // every 1–kMaxGatewayId slot one by one when fleet-status itself is
        // unavailable, or its pick turns out stale.
        final picked = await _pickFreeGatewayId(forSite);
        if (picked != null) {
          final identity = await _api.request(
            'GET',
            '/api/gateways/$forSite/$picked/check-identity',
          );
          if (identity['exists'] != true ||
              (identity['last_seen_mac'] != null &&
                  _mac(identity['last_seen_mac']) ==
                      _mac(state.config['gateway_uid']))) {
            return (picked, GatewaySuggestKind.online);
          }
        }
        for (int g = 1; g <= kMaxGatewayId; g++) {
          final identity = await _api.request(
            'GET',
            '/api/gateways/$forSite/$g/check-identity',
          );
          if (identity['exists'] != true ||
              (identity['last_seen_mac'] != null &&
                  _mac(identity['last_seen_mac']) ==
                      _mac(state.config['gateway_uid']))) {
            return (g, GatewaySuggestKind.online);
          }
        }
        return (0, GatewaySuggestKind.full);
      } catch (_) {
        /* backend unreachable: fall through to the offline guess */
      }
    }
    return (_offlineGatewaySuggestion(forSite), GatewaySuggestKind.offline);
  }

  /// Smallest 1–[kMaxGatewayId] gateway id not already used by another
  /// gateway at [forSite], read from fleet-status; null when fleet-status
  /// itself fails (caller falls back to the one-by-one scan).
  Future<int?> _pickFreeGatewayId(int forSite) async {
    try {
      final fleet = await _api.request(
        'GET',
        '/api/gateways/fleet-status?site_id=$forSite',
      );
      final used = <int>{};
      for (final item in (fleet['gateways'] as List? ?? [])) {
        final row = Map<String, dynamic>.from(item as Map);
        if (row['site_id'] != forSite) continue;
        final uid = row['mac'] ?? row['last_seen_mac'];
        if (uid != null && _mac(uid) == _mac(state.config['gateway_uid'])) {
          continue;
        }
        final g = (row['gateway_id'] as num?)?.toInt();
        if (g != null) used.add(g);
      }
      for (int g = 1; g <= kMaxGatewayId; g++) {
        if (!used.contains(g)) return g;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Offline fallback: the smallest 1–[kMaxGatewayId] gateway number not
  /// already seen advertising for [forSite] in the last BLE scan (step 1's
  /// peer list).
  int _offlineGatewaySuggestion(int forSite) {
    final used = <int>{};
    final pattern = RegExp(r'^GIOS-S(\d+)-GW(\d+)$');
    for (final p in state.peers) {
      final m = pattern.firstMatch(p.name);
      if (m != null && int.tryParse(m.group(1)!) == forSite) {
        final gw = int.tryParse(m.group(2)!);
        if (gw != null) used.add(gw);
      }
    }
    for (int g = 1; g <= kMaxGatewayId; g++) {
      if (!used.contains(g)) return g;
    }
    return 1;
  }

  /// Read-only pre-check (no BLE command) before committing a new station:
  /// the MAC already on record at (site, gw), or null when it is free or
  /// already this gateway's own record. Used to offer 「取代舊機」 /
  /// 「下一個編號」 before [configureWifi] is called.
  Future<String?> conflictingMac(int site, int gw) async {
    if (!_loggedIn) return null;
    final identity = await _api.request(
      'GET',
      '/api/gateways/$site/$gw/check-identity',
    );
    if (identity['exists'] == true &&
        identity['last_seen_mac'] != null &&
        _mac(identity['last_seen_mac']) != _mac(state.config['gateway_uid'])) {
      return identity['last_seen_mac'].toString();
    }
    return null;
  }

  Future<void> _configureWifi(
    int newSite,
    int newGateway,
    String ssid,
    String password,
    bool replaceExisting,
  ) => _run('設定身份與 WiFi', 150, (generation) async {
    final wifiOnly = state.config['wifi_only'] == true;
    if (wifiOnly && (newSite != site || newGateway != gateway)) {
      throw const GatewayFailure('conflict');
    }
    if (state.config['new_station'] == true && newSite == site) {
      throw const GatewayFailure('new_site_required');
    }
    if (newSite < 1 ||
        newSite > 65535 ||
        newGateway < 1 ||
        newGateway > kMaxGatewayId ||
        utf8.encode(ssid).isEmpty ||
        utf8.encode(ssid).length > 32 ||
        utf8.encode(password).length < 8 ||
        utf8.encode(password).length > 63) {
      throw const GatewayFailure('wifi_failed');
    }
    if (state.config['otp_enabled'] == true) {
      throw const GatewayFailure('otp_enabled');
    }
    if (_loggedIn && !wifiOnly && !replaceExisting) {
      final check = await _request(
        generation,
        'GET',
        '/api/gateways/$newSite/$newGateway/check-identity',
      );
      if (check['exists'] == true &&
          (check['last_seen_mac'] == null ||
              _mac(check['last_seen_mac']) !=
                  _mac(state.config['gateway_uid']))) {
        throw const GatewayFailure('conflict');
      }
    }
    // 「取代舊機」：先讓後端承認覆寫（force_replace），成功才動裝置；後端不支援
    // （409 / 不認得參數）就中止，不呼叫 set_site_identity，裝置維持原樣。
    if (_loggedIn && !wifiOnly && replaceExisting) {
      try {
        await _request(
          generation,
          'POST',
          '/api/gateways/$newSite/$newGateway/reserve-identity'
              '?mac=${Uri.encodeComponent(state.config['gateway_uid']?.toString() ?? '')}'
              '&force_replace=true',
        );
      } on GatewayFailure catch (error) {
        // 409 identity_conflict（force_replace 未生效或後端仍拒絕）或後端不認得
        // force_replace 參數（同樣以一般 4xx 回應）都視為不支援取代。
        if (error.code == 'api' && (error.status ?? 0) < 500) {
          throw const GatewayFailure('replace_unsupported');
        }
        rethrow;
      }
      // Backend has granted the replacement; only writing it to the device
      // is left. A failure past this point must not re-run the reserve.
      _pendingReplace = true;
    }
    if (newSite != site || newGateway != gateway) {
      try {
        _expectReboot();
        await _command(generation, 'set_site_identity', {
          'site_id': newSite,
          'gateway_id': newGateway,
        });
        await _wait(15, generation);
        await _link.connect(state.peer!, onStage: _stageFor(generation));
        await _wait(3, generation);
        await _command(generation, 'ping');
        state = state.copy(config: await _command(generation, 'get_config'));
        if (site != newSite || gateway != newGateway) {
          throw const GatewayFailure('conflict');
        }
      } catch (error) {
        if (replaceExisting) throw const GatewayFailure('replace_pending');
        rethrow;
      }
    }
    final wifiDeadline = Stopwatch()..start();
    // Once sent, even a lost ACK may mean the network has changed. Do not
    // retain a successful check from the previous Wi-Fi while reading back.
    state = state.copy(
      config: {...state.config}..remove('mqtt_connected'),
      net: const {},
      uploadLate: false,
    );
    _startWifiGrace();
    await _command(generation, 'set_wifi', {
      'ssid': ssid,
      'password': password,
    });
    final current =
        profileFor(state.config['fw_version']?.toString() ?? '') ==
        ProtocolProfile.current;
    if (!current) await _wait(16, generation);
    bool connected = false;
    while (wifiDeadline.elapsed < const Duration(seconds: 60)) {
      try {
        await _wait(
          3,
          generation,
        ).timeout(const Duration(seconds: 60) - wifiDeadline.elapsed);
      } on TimeoutException {
        break;
      }
      final remaining = const Duration(seconds: 60) - wifiDeadline.elapsed;
      if (remaining <= Duration.zero) break;
      Map<String, dynamic> net;
      try {
        net = await _command(
          generation,
          current ? 'get_net_status' : 'get_status',
        ).timeout(remaining);
      } on GatewayFailure catch (error) {
        if (['busy', 'not_ready', 'timeout'].contains(error.code)) continue;
        rethrow;
      } on TimeoutException {
        break;
      }
      _absorbTarget(net);
      if (current) _absorbNet(net);
      if ((net['last_wifi_error']?.toString() ?? '').isNotEmpty) {
        throw wifiFailedFrom(net, ssid: ssid, sinceSent: wifiDeadline.elapsed);
      }
      if (current
          ? net['wifi_state'] == 'got_ip' &&
                (net['ip']?.toString() ?? '').isNotEmpty &&
                net['ssid'] == ssid
          : net['mqtt_connected'] == true) {
        if (!current) {
          final remainingRead =
              const Duration(seconds: 60) - wifiDeadline.elapsed;
          if (remainingRead <= Duration.zero) break;
          final readback = await _command(generation, 'get_config').timeout(
            remainingRead,
            onTimeout: () => throw const GatewayFailure('wifi_failed'),
          );
          if (readback['wifi_ssid'] != ssid) {
            throw const GatewayFailure('wifi_failed');
          }
        }
        // Keep the reported upload target; MQTT is still coming up here.
        _absorbTarget({...net}..remove('mqtt_connected'));
        if (current) _absorbNet(net);
        connected = true;
        break;
      }
    }
    if (!connected) {
      throw wifiFailedFrom(
        state.net,
        ssid: ssid,
        sinceSent: wifiDeadline.elapsed,
      );
    }
    // The MQTT client reconnects over the new Wi-Fi: an earlier
    // mqtt_connected no longer applies until it is read again.
    state = state.copy(
      config: {...state.config, 'wifi_ssid': ssid}..remove('mqtt_connected'),
      uploadLate: false,
    );
    if (wifiOnly) {
      // The station is kept and the next page verifies data, so the upload
      // is confirmed first (網路體檢 → 確認資料上傳).
      state = state.copy(
        checkPassed: false,
        message: 'Wi-Fi 已更新，站點與 PTU 設定保留。接著確認資料有上傳。',
      );
      return;
    }
    if (_loggedIn && !replaceExisting) {
      await _request(
        generation,
        'POST',
        '$_path/reserve-identity?mac=${Uri.encodeComponent(state.config['gateway_uid']?.toString() ?? '')}',
      );
    }
    _pendingReplace = false;
    state = state.copy(step: 3, message: 'WiFi 已連線，下一步確認後端看得到閘道器');
  });
  Future<Map<String, dynamic>?> _fleet(int generation) async {
    final response = await _request(
      generation,
      'GET',
      '/api/gateways/fleet-status?site_id=$site',
    );
    for (final item in (response['gateways'] as List? ?? [])) {
      final row = Map<String, dynamic>.from(item as Map);
      if (row['site_id'] == site && row['gateway_id'] == gateway) {
        return {
          ...row,
          'mqtt_connected': row['mqtt_connected'] ?? response['mqtt_connected'],
        };
      }
    }
    return null;
  }

  /// [base] / [environment] are the APP backend URL and selector value; when
  /// given, a known upload-target mismatch fails fast instead of waiting 90 s.
  ///
  /// [password] logs in again when the backend was switched since the last
  /// login (or the flow started offline); empty keeps the old skip behaviour.
  Future<void> online({
    bool skip = false,
    String? base,
    String? environment,
    String? password,
  }) async {
    await _online(skip, base, environment, password);
    // Round 15: direct flow — entering step 7 starts the gateway's own PTU
    // pick at once (max_connections 1), no 「掃描」 tap needed.
    if (ref.mounted && state.step == 4 && state.error == null && directFlow) {
      await discover();
    }
  }

  Future<void> _online(
    bool skip,
    String? base,
    String? environment,
    String? password,
  ) => _run('確認閘道器持續上線', 90, (generation) async {
    final secret = base == null ? '' : _passwordFor(base, password);
    if (!skip && !_loggedIn && base != null && secret.isNotEmpty) {
      _backend = describeBackend(Uri.tryParse(base.trim()));
      await _api.login(base.trim(), secret);
      _check(generation);
      _loginOk(base, secret);
    }
    if (skip || !_loggedIn) {
      state = state.copy(step: 4, message: '後端尚未確認；完成配置後仍需驗證');
      return;
    }
    if (base != null) _checkUploadTarget(base, environment);
    await _command(generation, 'heartbeat_boost', {'duration': 300});
    String? previous;
    for (int elapsed = 0; elapsed < 90; elapsed += 5) {
      final row = await _fleet(generation);
      _check(generation);
      final heartbeat = row?['last_heartbeat']?.toString();
      if (row?['online'] == true &&
          row?['mqtt_connected'] == true &&
          previous != null &&
          heartbeat != null &&
          heartbeat != previous) {
        await _request(generation, 'PATCH', '$_path/bot-monitor', {
          'enabled': false,
          'ttl_minutes': 30,
        });
        _lease = true;
        state = state.copy(
          step: 4,
          online: true,
          message: '閘道器持續上線，可搜尋 PTU',
          // Heartbeats reached this backend, so the gateway is uploading.
          config: reportsMqttTarget(state.config)
              ? {...state.config, 'mqtt_connected': true}
              : null,
        );
        _stopWatch(UploadWatch.idle);
        return;
      }
      previous = heartbeat;
      await _wait(5, generation);
    }
    throw const GatewayFailure('timeout');
  });

  /// Return from verification to a fresh gateway-side inventory, without
  /// changing the site, Wi-Fi or PTU assignments until the user confirms.
  Future<void> rescanPtus() async {
    if (state.busy || state.step < 4) return;
    _health?.cancel();
    _verifyCarry = null;
    state = state.copy(
      step: 4,
      verified: false,
      report: '',
      results: {},
      assignStatus: {},
      verifyBackendDown: false,
    );
    await discover();
  }

  /// [keep]: a selection to carry over (step 9 「返回選擇 PTU」) instead of
  /// the default preselection; connected in-range PTUs still fill it up.
  Future<void> discover({Set<String>? keep}) async {
    try {
      await _discoverFlow(keep);
    } finally {
      // Round 22: the list was read again (or failed with its own error):
      // a topology switch's reason is over.
      if (ref.mounted && state.relistReason.isNotEmpty) {
        state = state.copy(relistReason: '', error: state.error);
      }
    }
  }

  Future<void> _discoverFlow(Set<String>? keep) async {
    _rssiTimer ??= Timer.periodic(ref.read(ptuSignalIntervalProvider), (_) {
      unawaited(refreshPtuRssi());
      unawaited(keepAlive());
    });
    _autoResetRescan = false;
    final before = Set<String>.of(state.selected);
    if (state.rescanNeeded) {
      state = state.copy(rescanNeeded: false, error: state.error);
    }
    await _discover(keep: keep);
    if (ref.mounted && _autoResetRescan && state.error == null) {
      // 殘留編號已歸零：重掃一次讓它們變成可勾選；這次不再自動重置。
      _autoResetRescan = false;
      await _discover(autoReset: false, keep: keep);
    }
    if (ref.mounted) {
      final lost = _linkLostAt(4);
      if (lost && !_autoRelinking) {
        // Round 12: a drop during the scan reconnects and rescans by itself.
        await _autoRelink(4, keep: keep);
        return;
      }
      // Round 22: the list is read — the reconnect's texts end here, also
      // inside the automatic reconnect (a new loss keeps them for its retry
      // wait), so an empty list still turns into 「重新掃描」 below.
      if (!lost && state.relinking) {
        state = state.copy(relinking: false, error: state.error);
      }
    }
    if (ref.mounted &&
        (state.step == 4 || state.step == 5) &&
        state.error != null) {
      state = state.copy(
        message: state.reconnectFailed
            ? reconnectFailedText
            : state.scanResumePending
            ? phoneLinkLostText
            : state.uploadWatch == UploadWatch.linkLost
            ? 'Gateway 掃描未完成：藍牙連線已中斷。請靠近 Gateway，再按「$rescanAfterLossLabel」。'
            : directFlow
            ? '閘道器選台未完成，請查看錯誤後按「重新搜尋」。'
            : 'Gateway 掃描未完成，請查看錯誤後按「$rescanLabel」。',
        error: state.error,
      );
    }
    if (ref.mounted && state.error == null) {
      final seen = state.ptus.map((p) => p['mac'].toString()).toSet();
      final absent = before.where((m) => !seen.contains(m)).length;
      state = state.copy(
        selected: state.selected.where(seen.contains).toSet(),
        // Direct flow: the gateway's pick simply replaces the last one.
        absentNotice: absent > 0 && !directFlow
            ? absentSelectionText(absent)
            : '',
      );
    }
    // Round 15: a scan that failed (e.g. get_ble_devices lost over BLE),
    // timed out or found nothing is over: 「重新掃描」 instead of a stuck
    // 「掃描中…」 (a link loss has its own 「重新連線並繼續」).
    if (ref.mounted &&
        state.step == 4 &&
        !state.busy &&
        !state.relinking &&
        !directFlow &&
        state.ptus.isEmpty &&
        !_step7Lost(state)) {
      state = state.copy(rescanNeeded: true, error: state.error);
    }
    // A scan the installer started that worked: a later loss gets the full
    // automatic retries again.
    if (ref.mounted && !_autoRelinking && state.error == null) {
      _step7Retries = 0;
      _step7RelinkedAt = null;
    }
  }

  Future<void> _discover({bool autoReset = true, Set<String>? keep}) =>
      directFlow
      ? _directDiscover()
      : _listDiscover(autoReset: autoReset, keep: keep);

  /// Round 15: step 7 in direct mode on firmware 1.7.20+ — the gateway
  /// picks the PTU itself (the strongest over its threshold, or the bound
  /// MAC). Entering step 7 therefore switches it to direct mode at once
  /// (max_connections 1, BLE scanning on) and polls get_status.direct for
  /// its pick ([directPollInterval] × [directPollLimit], ~20 s) instead of a
  /// list the APP preselects (round 14: the APP ticked one PTU, the gateway
  /// connected another and both ended up #1).
  ///
  /// Round 17: after a phone↔gateway link loss (automatic or 「重新連線並
  /// 繼續」) the PTU shown and the installer's identification are kept;
  /// the fresh get_status only clears the identification when the gateway
  /// now connects another PTU ([_syncDirectPick]).
  Future<void> _directDiscover() =>
      _run(relinkStep: 4, directPickingText, 45, (generation) async {
        final relink =
            state.uploadWatch == UploadWatch.linkLost || state.resumePending;
        if (relink) {
          await _reconnect(generation);
          state = state.copy(relinkStage: RelinkStage.reloading);
          final net = await _command(
            generation,
            state.netCheckSupported ? 'get_net_status' : 'get_status',
          );
          _absorbTarget(net);
          _absorbNet(net);
          _stopWatch(UploadWatch.idle);
        }
        state = state.copy(
          message: directPickingText,
          ptus: relink ? null : [],
          selected: relink ? null : {},
          results: {},
          assignStatus: {},
          missing: [],
          starNotice: '',
          identifyNote: relink ? null : '',
          identifiedMac: relink ? state.identifiedMac : null,
          directNotice: relink ? null : '',
        );
        final config = await _command(generation, 'get_config');
        state = state.copy(
          config: {
            ...state.config,
            for (final key in const [
              'max_connections',
              'ble_enabled',
              'upload_paused',
              'auto_connect_min_rssi',
              'direct_bind_mac',
            ])
              if (config.containsKey(key)) key: config[key],
          },
        );
        await _checkStrayBind(generation, config);
        if (config['max_connections'] != 1) {
          await _command(generation, 'set_config', {'max_connections': 1});
          state = state.copy(config: {...state.config, 'max_connections': 1});
        }
        // A new identity (set_site_identity) leaves BLE off until
        // join_fleet: scanning must run for the gateway to pick. Upload
        // stays paused until 「是這台，開始監控」 sends join_fleet.
        if (config['ble_enabled'] == false) {
          await _command(generation, 'set_ble_enabled', {'enabled': true});
          state = state.copy(config: {...state.config, 'ble_enabled': true});
        }
        await _pollDirectPick(generation);
        _syncDirectPick();
        final direct = state.direct;
        final seen = state.ptus.map((p) => p['mac'].toString()).toSet();
        state = state.copy(
          scannedTotal: max(direct?.candidates.length ?? 0, state.ptus.length),
          pendingNext: 0,
          resetFailed: {},
          assignFailed: {
            for (final e in state.assignFailed.entries)
              if (seen.contains(e.key)) e.key: e.value,
          },
          unassigned: {},
          resumePending: false,
          scanResumePending: false,
          message: directPickMessage(direct),
        );
        await _reconcileAssigned(generation, state.ptus);
      });

  /// Polls get_status.direct until the gateway reports a connected pick
  /// ([want]: that MAC); false when [directPollLimit] polls pass without,
  /// or once two polls in a row say no_candidate / bound_missing (the
  /// gateway keeps scanning; the step 7 refresh shows a later pick).
  ///
  /// Round 16: with [until] the polls run up to that moment instead (the
  /// last one right at it) and never end early — a switch to a bound PTU
  /// can pass through several failed connects (round 15: 24 s).
  Future<bool> _pollDirectPick(
    int generation, {
    String? want,
    DateTime? until,
  }) async {
    var negative = 0;
    for (var i = 0; ; i++) {
      if (i > 0) {
        var gap = directPollInterval;
        if (until != null) {
          final left = until.difference(DateTime.now());
          if (left < gap) gap = left.isNegative ? Duration.zero : left;
        }
        await Future<void>.delayed(gap);
        _check(generation);
      }
      final status = await _command(generation, 'get_status');
      _check(generation);
      _takeDirect(status['direct']);
      final direct = state.direct;
      final picked = direct?.pickedMac;
      if (picked != null && (want == null || sameMac(picked, want))) {
        return true;
      }
      if (until != null) {
        if (!DateTime.now().isBefore(until)) return false;
        continue;
      }
      final settled =
          direct?.state == DirectState.noCandidate ||
          direct?.state == DirectState.boundMissing;
      negative = settled ? negative + 1 : 0;
      if (negative >= 2 || i + 1 >= directPollLimit) return false;
    }
  }

  /// Round 17: [CommissionState.directSettling] timer.
  Timer? _settleTimer;

  /// Keeps a `direct` report. Round 17: a pick newly reported connected
  /// with no RSSI yet (0 / null) starts [directSettleWindow] of
  /// 「連線建立中…」; an RSSI reading, another pick or none ends it.
  void _takeDirect(Object? direct) {
    if (!ref.mounted || direct is! Map) return;
    final raw = Map<String, dynamic>.from(direct);
    final before = state.direct?.pickedMac;
    final next = DirectStatus.from(raw);
    final picked = next?.pickedMac;
    final rssi = next?.ptuRssi;
    var settling = state.directSettling;
    if (picked == null || (rssi != null && rssi < 0)) {
      settling = false;
      _settleTimer?.cancel();
    } else if (before == null || !sameMac(before, picked)) {
      settling = true;
      _settleTimer?.cancel();
      _settleTimer = Timer(directSettleWindow, () {
        if (ref.mounted && state.directSettling) {
          state = state.copy(directSettling: false, error: state.error);
        }
      });
    }
    state = state.copy(
      directRaw: raw,
      directSettling: settling,
      error: state.error,
    );
  }

  /// Direct flow: state.ptus / selected follow the gateway's own pick (one
  /// row, or none); a new pick clears the identify note. Round 15b: a pick
  /// other than the identified PTU clears [CommissionState.identifiedMac]
  /// at once (yellow 「閘道器已切換到另一顆 PTU…請重新辨識」).
  void _syncDirectPick() {
    if (!ref.mounted || !directFlow || state.step != 4) return;
    final direct = state.direct;
    final mac = direct?.pickedMac;
    // Round 16: 「不是這台？」 gave up before the gateway switched; the
    // first later read with the chosen PTU connected clears the red error
    // (round 15: it stayed 20 s+ beside a card already showing that PTU).
    final want = state.tempBoundMac;
    if (mac != null &&
        want != null &&
        sameMac(mac, want) &&
        state.error == const GatewayFailure('direct_switch_failed').message) {
      state = state.copy(error: null, message: directSwitchDoneText(mac));
    }
    final identified = state.identifiedMac;
    if (identified != null && (mac == null || !sameMac(mac, identified))) {
      state = state.copy(
        identifiedMac: null,
        directNotice: mac == null ? '' : directSwitchedText(mac),
        error: state.error,
      );
    }
    if (mac == null) {
      if (state.ptus.isEmpty && state.selected.isEmpty) return;
      state = state.copy(
        ptus: const [],
        selected: const {},
        identifyNote: '',
        error: state.error,
      );
      return;
    }
    final current = state.ptus.length == 1 ? state.ptus.single : null;
    if (current != null && sameMac(current['mac'], mac)) {
      final key = current['mac'].toString();
      final rssi = direct!.ptuRssi;
      state = state.copy(
        ptus: [
          {
            ...current,
            'connected': true,
            if (rssi != null && rssi < 0) 'rssi': rssi,
            if (rssi != null && rssi < 0) 'rssi_age_ms': 0,
            'rssi_stale': false,
          },
        ],
        selected: {key},
        error: state.error,
      );
      return;
    }
    state = state.copy(
      ptus: [
        {
          'mac': mac,
          'rssi': direct!.ptuRssi,
          'device_number': direct.ptuDeviceNumber ?? 0,
          'connected': true,
          'rssi_age_ms': 0,
        },
      ],
      selected: {mac},
      identifyNote: '',
      error: state.error,
    );
  }

  Future<void> _listDiscover({
    bool autoReset = true,
    Set<String>? keep,
  }) => _run(relinkStep: 4, 'Gateway 正在掃描周邊 PTU，請稍候', 75, (generation) async {
    final relink =
        state.uploadWatch == UploadWatch.linkLost || state.resumePending;
    if (relink) {
      await _reconnect(generation);
      // Round 21: back — say so while the list is read again.
      state = state.copy(
        message: relinkReloadText,
        relinkStage: RelinkStage.reloading,
      );
      // Re-establish the same gateway link and read fresh network status;
      // never turn the last MQTT snapshot green just because ping succeeds.
      final net = await _command(
        generation,
        state.netCheckSupported ? 'get_net_status' : 'get_status',
      );
      _absorbTarget(net);
      _absorbNet(net);
      _stopWatch(UploadWatch.idle);
    }
    // Round 22: a temporary 「不是這台？」 binding of the direct flow
    // (switched to star at step 7) is undone before the star list, as
    // 「取消」 would; a failure keeps it recorded for the next undo.
    if (state.tempBoundMac != null &&
        ref.read(topologyProvider).topology.isStar) {
      await _releaseTempBind();
      _check(generation);
    }
    // Round 24: the list on screen, put back when the gateway refuses the
    // read as busy (nothing changed on the gateway side).
    final before = (
      ptus: state.ptus,
      selected: state.selected,
      results: state.results,
      assignStatus: state.assignStatus,
      missing: state.missing,
      starNotice: state.starNotice,
    );
    state = state.copy(
      message: relink ? relinkReloadText : 'Gateway 正在掃描周邊 PTU，請稍候',
      ptus: [],
      selected: {},
      results: {},
      assignStatus: {},
      missing: [],
      starNotice: '',
      ptuListBusy: false,
    );
    final Map<String, dynamic> response, connected;
    try {
      response = await _command(generation, 'scan_ble_discover', {
        'duration': 10,
      });
      _check(generation);
      connected = await _command(generation, 'get_ble_devices');
    } on GatewayFailure catch (error) {
      if (ref.mounted &&
          generation == _generation &&
          isGatewayBusyFailure(error)) {
        state = state.copy(
          ptus: before.ptus,
          selected: before.selected,
          results: before.results,
          assignStatus: before.assignStatus,
          missing: before.missing,
          starNotice: before.starNotice,
          ptuListBusy: true,
          error: state.error,
        );
      }
      rethrow;
    }
    await _absorbDirect(generation);
    final ptus = mergePtuInventory(
      response['devices'] as List? ?? [],
      connected['devices'] as List? ?? [],
    );
    // This scan's device_number is authoritative: never overlay numbers
    // from saved progress (round 5 showed a stale 「PTU #5」 for a PTU the
    // gateway had just reset to 0).
    final target = targetPtuCount;
    final isStar = ref.read(topologyProvider).topology.isStar;
    if (autoReset) {
      _ownerRegistry = null;
      _resetFailed.clear();
    }
    final outOfRange = isStar ? ptus.where(_isOutOfRange).toList() : const [];
    if (autoReset && outOfRange.isNotEmpty) {
      _ownerRegistry = await _siteGatewayIds(generation);
      final registry = _ownerRegistry;
      if (registry != null) {
        final stale = outOfRange
            .where((p) => !registry.contains(_ownerGateway(p)))
            .toList();
        if (stale.isNotEmpty) {
          state = state.copy(message: '發現 ${stale.length} 台殘留編號的 PTU，自動重置中');
          for (final p in stale) {
            final mac = p['mac'].toString();
            var ok = false;
            // 實機常見 BLE 133 / provision timeout：每顆自動重試 1 次（間隔 2 秒）。
            for (int attempt = 0; attempt < 2 && !ok; attempt++) {
              if (attempt > 0) await _wait(2, generation);
              try {
                final result = await _command(generation, 'assign_device_id', {
                  'mac': mac,
                  'new_id': 255,
                });
                ok = result['success'] == true;
              } catch (e) {
                // Cancellation (generation changed / widget disposed) must
                // still abort the whole discover flow; any other failure
                // (GatewayFailure or not) just marks this one PTU as a
                // failed reset and we move on to the next stale PTU.
                if (e is GatewayFailure && e.code == 'cancelled') rethrow;
                _check(generation);
                // Phone↔gateway link down (same as step 8): stop the whole
                // loop at once instead of timing out on every PTU; resets
                // that already succeeded stay on the PTUs.
                if (isPhoneLinkFailure(e)) {
                  state = state.copy(scanResumePending: true);
                  throw GatewayFailure('phone_link_lost', detail: e.toString());
                }
              }
            }
            if (ok) {
              _autoResetRescan = true;
            } else {
              _resetFailed.add(mac);
            }
          }
        }
      }
    }
    // Connected in-range PTUs are always preselected first (round 7: a
    // connected #1 was left unticked); the order shown stays [ptus].
    var selected = _preselect(ptus, target);
    if (keep != null) {
      final seen = ptus.map((p) => p['mac'].toString()).toSet();
      final merged = keep.where(seen.contains).toSet();
      for (final mac in selected) {
        if (merged.length >= target) break;
        final row = ptus.firstWhere((p) => p['mac'] == mac);
        if (row['connected'] == true) merged.add(mac);
      }
      selected = merged;
    }
    _selectionTouched = false;
    final failed = isStar
        ? ptus
              .where((p) => _isOutOfRange(p) && _resetFailed.contains(p['mac']))
              .map((p) => p['mac'].toString())
              .toSet()
        : <String>{};
    final pending = isStar
        ? ptus.where(_isOutOfRange).length - failed.length
        : 0;
    final seenMacs = ptus.map((p) => p['mac'].toString()).toSet();
    state = state.copy(
      ptus: ptus,
      selected: selected,
      // Failed PTUs stay listed (with 「重試這 N 台」) while still in range.
      assignFailed: {
        for (final e in state.assignFailed.entries)
          if (seenMacs.contains(e.key)) e.key: e.value,
      },
      unassigned: {},
      resumePending: false,
      scanResumePending: false,
      scannedTotal: ptus.length,
      pendingNext: pending,
      resetFailed: failed,
      starNotice: outOfRange.isNotEmpty && _ownerRegistry == null
          ? starOwnerUnknownText
          : '',
      message: ptus.isEmpty
          ? const GatewayFailure('no_devices').message
          : 'Gateway 已回傳 ${ptus.length} 台 PTU，請選擇要監控的裝置，最多 $target 台',
    );
    await _reconcileAssigned(generation, ptus);
  });

  /// Round 9: after every scan (entering step 7, resume, rescan) drop
  /// assignedOk entries the gateway contradicts, then work out whether the
  /// gateway already monitors the whole selection ([monitoringOk]).
  Future<void> _reconcileAssigned(
    int generation,
    List<Map<String, dynamic>> ptus,
  ) async {
    final stale = _staleAssigned(state.assignedOk, ptus);
    for (final mac in stale) {
      _doneAssign.remove(mac);
      _inflightAssign.remove(mac);
    }
    state = state.copy(
      assignedOk: state.assignedOk.difference(stale),
      results: {
        for (final e in state.results.entries)
          if (!stale.contains(e.key)) e.key: e.value,
      },
      monitoringOk: false,
    );
    if (stale.isNotEmpty) await _save();
    await _computeMonitoringOk(generation, ptus);
  }

  Future<void> _computeMonitoringOk(
    int generation,
    List<Map<String, dynamic>> ptus,
  ) async {
    final selected = state.selected;
    if (selected.isEmpty || !state.assignedOk.containsAll(selected)) return;
    final allConnected = selected.every(
      (m) => ptus.any((p) => sameMac(p['mac'], m) && p['connected'] == true),
    );
    if (!allConnected) return;
    try {
      final config = await _command(generation, 'get_config');
      final limit = monitorLimit(ref.read(topologyProvider).topology.isStar);
      state = state.copy(
        monitoringOk:
            config['upload_paused'] != true &&
            config['ble_enabled'] != false &&
            config['max_connections'] == limit,
      );
    } catch (e) {
      if (e is GatewayFailure && e.code == 'cancelled') rethrow;
      _check(generation);
    }
  }

  /// assignedOk / saved-done MACs the scan [rows] contradict: listed with a
  /// device_number other than the one the APP assigned (or, when that is
  /// unknown, outside this gateway's range).
  Set<String> _staleAssigned(
    Iterable<String> macs,
    List<Map<String, dynamic>> rows,
  ) {
    final first = (gateway - 1) * 5 + 1;
    final stale = <String>{};
    for (final mac in macs) {
      final found = rows.where((p) => sameMac(p['mac'], mac));
      if (found.isEmpty) continue;
      final id = (found.first['device_number'] as num?)?.toInt() ?? 0;
      final expected = _doneAssign[mac] ?? _inflightAssign[mac];
      final bad = expected != null ? id != expected : !_ownsNumber(id, first);
      if (bad) stale.add(mac);
    }
    return stale;
  }

  /// Step 7 with every selected PTU already assigned (round 9 dead end):
  /// 「開始驗證」 goes straight to step 9 when the gateway already monitors
  /// them; otherwise 「恢復監控」 sends join_fleet first. Never re-assigns.
  Future<void> finishConfigured() =>
      _step8Run('正在確認 Gateway 監控狀態', 90, (generation) async {
        final chosen = state.ptus
            .where((p) => state.selected.contains(p['mac']))
            .toList();
        if (chosen.isEmpty) throw const GatewayFailure('no_devices');
        state = state.copy(step: 5);
        if (await _alreadyMonitoring(generation, chosen)) return;
        _provisioningMayBeActive = true;
        final isStar = ref.read(topologyProvider).topology.isStar;
        final config = await _command(generation, 'get_config');
        if (config['max_connections'] != monitorLimit(isStar)) {
          await _command(generation, 'set_config', {
            'max_connections': monitorLimit(isStar),
          });
        }
        await _command(generation, 'join_fleet');
        await _waitConnected(generation, chosen, limitSec: 30);
      });

  /// Default selection: in-range PTUs, connected first, then RSSI; capped.
  Set<String> _preselect(List<Map<String, dynamic>> ptus, int target) {
    final isStar = ref.read(topologyProvider).topology.isStar;
    return (ptus.where((p) => !isStar || !_isOutOfRange(p)).toList()
          ..sort(comparePtuForSelection))
        .take(target)
        .map((p) => p['mac'].toString())
        .toSet();
  }

  /// Adds connected in-range PTUs missing from [selected]; when full, each
  /// replaces the weakest unconnected selected one. Otherwise unchanged (no
  /// churn on RSSI updates).
  Set<String> _promoteConnected(
    List<Map<String, dynamic>> ptus,
    Set<String> selected,
    int target,
  ) {
    final isStar = ref.read(topologyProvider).topology.isStar;
    final next = {...selected};
    final missing = ptus.where(
      (p) =>
          p['connected'] == true &&
          !next.contains(p['mac']) &&
          !(isStar && _isOutOfRange(p)),
    );
    for (final p in missing) {
      if (next.length >= target) {
        final weak =
            ptus
                .where((q) => next.contains(q['mac']) && q['connected'] != true)
                .toList()
              ..sort(comparePtuForSelection);
        if (weak.isEmpty) break;
        next.remove(weak.last['mac']);
      }
      next.add(p['mac'].toString());
    }
    return next.length == selected.length && next.containsAll(selected)
        ? selected
        : next;
  }

  /// The user changed the step 7 selection since the last scan.
  bool _selectionTouched = false;

  /// PTU 已被編號（0＝未編號、255＝「重置並納入」後的暫時狀態，兩者都算可納入）
  /// 且編號不在本 gateway 的 5 格範圍內，代表它掛在別的 gateway 底下。
  bool _isOutOfRange(Map<String, dynamic> ptu) {
    final id = (ptu['device_number'] as num?)?.toInt() ?? 0;
    if (id == 0 || id == 255) return false;
    final first = (gateway - 1) * 5 + 1;
    return id < first || id >= first + 5;
  }

  /// 範圍外 PTU 的編號所屬 gateway id：(device_number-1) ~/ 5 + 1。
  int _ownerGateway(Map<String, dynamic> ptu) =>
      (((ptu['device_number'] as num?)?.toInt() ?? 0) - 1) ~/ 5 + 1;

  /// 此 site 在後台 fleet-status 已登記的 gateway id；未登入、離線、逾時或
  /// 非 2xx 時回 null（呼叫端不自動重置）。
  Future<Set<int>?> _siteGatewayIds(int generation) async {
    if (!_loggedIn) return null;
    try {
      final fleet = await _request(
        generation,
        'GET',
        '/api/gateways/fleet-status?site_id=$site',
      ).timeout(const Duration(seconds: 10));
      final ids = <int>{};
      for (final item in (fleet['gateways'] as List? ?? [])) {
        final row = Map<String, dynamic>.from(item as Map);
        if (row['site_id'] != site) continue;
        final g = (row['gateway_id'] as num?)?.toInt();
        if (g != null) ids.add(g);
      }
      return ids;
    } catch (_) {
      _check(generation);
      return null;
    }
  }

  /// 星狀模式下，[ptu] 是否已屬於其他 gateway（範圍外，不可直接勾選）。
  /// 直連模式恆為 false。
  bool ptuOutOfRange(Map<String, dynamic> ptu) =>
      ref.read(topologyProvider).topology.isStar && _isOutOfRange(ptu);

  /// 範圍外 PTU 的所屬閘道器是否經後端 fleet-status 確認已登記；只有此時才
  /// 顯示「已屬於其他閘道器」。
  bool ptuOwnerConfirmed(Map<String, dynamic> ptu) =>
      ptuOutOfRange(ptu) &&
      (_ownerRegistry?.contains(_ownerGateway(ptu)) ?? false);

  /// 星狀模式：本機 5 格是否已被「已配置且在範圍內」的 PTU 佔滿，此時若又
  /// 勾了新裝置（未編號），送出前要提示改連別台 gateway。
  String? get starFullWarning {
    if (!ref.read(topologyProvider).topology.isStar) return null;
    final first = (gateway - 1) * 5 + 1;
    final occupied = state.ptus.where((p) {
      final id = (p['device_number'] as num?)?.toInt() ?? 0;
      return id >= first && id < first + 5;
    }).length;
    final addsNew = state.ptus.any((p) {
      if (!state.selected.contains(p['mac'])) return false;
      final id = (p['device_number'] as num?)?.toInt() ?? 0;
      return id == 0 || id == 255;
    });
    if (occupied >= 5 && addsNew) return '本機已滿，請連另一台閘道器。';
    return null;
  }

  /// 「重置並納入」：把範圍外 PTU 的編號清成 255，再重新掃描，讓它可被本機
  /// 勾選。呼叫端（page）只在 [ptuOutOfRange] 為 true 時提供這個動作。
  Future<void> resetAndInclude(String mac) async {
    await _run('重置編號，準備重新掃描', 20, (generation) async {
      final result = await _command(generation, 'assign_device_id', {
        'mac': mac,
        'new_id': 255,
      });
      if (result['success'] != true) throw const GatewayFailure('incomplete');
    });
    if (ref.mounted && state.error == null) {
      await discover();
    }
  }

  void select(String mac, bool selected) {
    if (state.busy) return;
    final next = Set<String>.of(state.selected);
    if (selected &&
        next.length < targetPtuCount &&
        !ptuOutOfRange(
          state.ptus.firstWhere((p) => p['mac'] == mac, orElse: () => const {}),
        )) {
      next.add(mac);
    } else if (!selected) {
      next.remove(mac);
    }
    _selectionTouched = true;
    state = state.copy(selected: next);
    // Mid step 8 (e.g. added after a link loss): keep the choice across an
    // APP restart (round 6 lost a PTU checked after the disconnect).
    if (state.step == 5) unawaited(_save());
  }

  /// 逐台指派一台 PTU：失敗自動重試 [assignRetries] 次（間隔 2 秒）。
  /// 成功回 null，否則回給前線看的失敗原因；取消一律往外丟。
  ///
  /// Round 21: the row shows each automatic retry (「藍牙連線失敗，自動重試
  /// 1/2」, 「閘道器忙碌，稍後重試」); the raw failure goes to
  /// [_assignDetail] for the details sheet. Retries unchanged.
  Future<String?> _assignOne(int generation, String mac, int id) async {
    String? reason;
    void failedTry(int attempt, Object? error, String detail) {
      _assignDetail[mac] = detail;
      if (attempt >= assignRetries) return; // no retry follows
      _setAssign(
        mac,
        AssignStatus(
          assignRetryPhase(error),
          id: id,
          retry: attempt + 1,
          retries: assignRetries,
          detail: detail,
        ),
      );
    }

    for (int attempt = 0; attempt <= assignRetries; attempt++) {
      if (attempt > 0) await _wait(2, generation);
      _check(generation);
      try {
        final result = await _commandBusy(
          generation,
          'assign_device_id',
          {'mac': mac, 'new_id': id},
          onBusy: () => _setAssign(
            mac,
            AssignStatus(
              AssignPhase.busy,
              id: id,
              retry: attempt,
              retries: assignRetries,
              detail: _assignDetail[mac],
            ),
          ),
        );
        if (result['success'] == true) {
          // Firmware 1.7.15+: the ack names the PTU actually written.
          reason = assignAckMismatch(result, mac, id);
          if (reason == null) {
            if (ackNeedsReadback(result)) _pendingReadback.add(mac);
            return null;
          }
          failedTry(attempt, null, jsonEncode(result));
          continue;
        }
        final error = result['error'] ?? result['result'];
        reason = ptuFailureText(error);
        failedTry(attempt, error, jsonEncode(result));
      } catch (e) {
        if (e is GatewayFailure && e.code == 'cancelled') rethrow;
        _check(generation);
        // Phone↔gateway link down: not this PTU's fault, stop retrying.
        if (isPhoneLinkFailure(e)) rethrow;
        reason = ptuFailureText(e);
        failedTry(attempt, e, e.toString());
      }
    }
    return reason ?? ptuFailureText(null);
  }

  /// Round 21: the last raw failure per PTU of the current assignment run
  /// (details sheet only).
  final Map<String, String> _assignDetail = {};

  /// Round 21: one PTU row's assignment status.
  void _setAssign(String mac, AssignStatus status) {
    if (!ref.mounted) return;
    state = state.copy(
      assignStatus: {...state.assignStatus, mac: status},
      error: state.error,
    );
  }

  /// Round 21: a step 8 run that ended early (stopped, phone link lost,
  /// timed out) leaves no row 「指派中」 / 「自動重試」 with a spinner: those
  /// wait again for the next run.
  void _settleAssign() {
    if (!ref.mounted || state.busy) return;
    final stale = {
      for (final e in state.assignStatus.entries)
        if (e.value.active) e.key: e.value,
    };
    if (stale.isEmpty) return;
    state = state.copy(
      assignStatus: {
        ...state.assignStatus,
        for (final e in stale.entries)
          e.key: AssignStatus(
            AssignPhase.waiting,
            id: e.value.id,
            detail: e.value.detail,
          ),
      },
      error: state.error,
    );
  }

  /// Round 21: the rows of an assignment run over [chosen] — [targets]
  /// wait their turn, the others are done already.
  Map<String, AssignStatus> _assignStart(
    List<Map<String, dynamic>> chosen,
    List<Map<String, dynamic>> targets,
  ) {
    _assignDetail.clear();
    final pending = targets.map((p) => p['mac'].toString()).toSet();
    return {
      for (final p in chosen)
        p['mac'].toString(): pending.contains(p['mac'].toString())
            ? const AssignStatus(AssignPhase.waiting)
            : AssignStatus(
                AssignPhase.done,
                id: (p['device_number'] as num?)?.toInt(),
              ),
    };
  }

  /// 指派 [targets]；單台失敗不中止。回傳失敗 MAC → 原因。
  Future<Map<String, String>> _assignAll(
    int generation,
    List<Map<String, dynamic>> targets,
  ) async {
    final results = Map<String, String>.of(state.results);
    final targetMacs = targets.map((p) => p['mac']).toSet();
    final used = state.ptus
        .where((p) => !targetMacs.contains(p['mac']))
        .map((p) => (p['device_number'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .toSet();
    final failed = <String, String>{};
    final first = (gateway - 1) * 5 + 1;
    final direct = _directFixedId;
    // Round 23: the configure button shows this run's progress until the
    // run ends ([assigningLabel]); the runs set it with their first rows
    // already, this keeps any other caller covered.
    if (!state.assignRunning) {
      state = state.copy(assignRunning: true, error: state.error);
    }
    for (final (index, p) in targets.indexed) {
      _check(generation);
      final mac = p['mac'].toString();
      final old = (p['device_number'] as num?)?.toInt() ?? 0;
      // Direct mode: always #1 (the firmware ignores the number there and
      // picks the PTU by distance / bound MAC).
      final id = direct
          ? directPtuId
          : old >= first && old < first + 5 && !used.contains(old)
          ? old
          : List.generate(5, (i) => first + i).firstWhere(
              (id) => !used.contains(id),
              orElse: () => throw const GatewayFailure('gateway_full'),
            );
      used.add(id);
      results[mac] = '正在指派 #$id';
      state = state.copy(
        results: Map.of(results),
        assignStatus: {
          ...state.assignStatus,
          mac: AssignStatus(AssignPhase.assigning, id: id),
        },
      );
      _inflightAssign[mac] = id;
      await _save();
      final String? reason;
      try {
        reason = await _assignOne(generation, mac, id);
      } catch (e) {
        if (!isStep8LinkLoss(e, generation == _generation)) rethrow;
        // Stop at once: keep what succeeded, mark the rest as not done.
        final rest = targets
            .skip(index)
            .map((t) => t['mac'].toString())
            .toSet();
        for (final m in rest) {
          results[m] = notAssignedLinkText;
        }
        state = state.copy(
          results: Map.of(results),
          assignFailed: Map.of(failed),
          unassigned: rest,
          resumePending: true,
          assignStatus: {
            ...state.assignStatus,
            for (final m in rest) m: const AssignStatus(AssignPhase.waiting),
          },
        );
        await _save();
        throw GatewayFailure('phone_link_lost', detail: e.toString());
      }
      _inflightAssign.remove(mac);
      if (reason != null) {
        await _save();
        failed[mac] = reason;
        results[mac] = '指派失敗：$reason';
        state = state.copy(
          results: Map.of(results),
          assignFailed: {...state.assignFailed, mac: reason},
          assignStatus: {
            ...state.assignStatus,
            mac: AssignStatus(
              AssignPhase.failed,
              id: id,
              detail: _assignDetail[mac],
            ),
          },
        );
        continue;
      }
      p['device_number'] = id;
      _doneAssign[mac] = id;
      results[mac] = _pendingReadback.contains(mac)
          ? pendingReadbackText(id)
          : '已指派 #$id，等待連線';
      final stillFailed = Map<String, String>.of(state.assignFailed)
        ..remove(mac);
      state = state.copy(
        results: Map.of(results),
        assignFailed: stillFailed,
        unassigned: state.unassigned.difference({mac}),
        assignedOk: {...state.assignedOk, mac},
        assignStatus: {
          ...state.assignStatus,
          mac: AssignStatus(AssignPhase.done, id: id),
        },
      );
      await _save();
    }
    await _readBack(generation, targets, results, failed);
    return failed;
  }

  /// After the assignments, reads get_ble_devices once and checks every
  /// assigned MAC carries the number the APP sent; a mismatch (the firmware
  /// wrote another PTU) goes to [failed]. Connected ones show 已連線 #n.
  Future<void> _readBack(
    int generation,
    List<Map<String, dynamic>> targets,
    Map<String, String> results,
    Map<String, String> failed,
  ) async {
    if (targets.isEmpty) return;
    final List<Map<String, dynamic>> devices;
    try {
      final response = await _command(generation, 'get_ble_devices');
      devices = (response['devices'] as List? ?? [])
          .map((d) => Map<String, dynamic>.from(d as Map))
          .toList();
    } catch (e) {
      if (e is GatewayFailure && e.code == 'cancelled') rethrow;
      _check(generation);
      if (isPhoneLinkFailure(e)) {
        state = state.copy(assignFailed: Map.of(failed), resumePending: true);
        await _save();
        throw GatewayFailure('phone_link_lost', detail: e.toString());
      }
      // Old firmware or a busy gateway: keep the ack result.
      _settlePending(results);
      state = state.copy(results: Map.of(results));
      return;
    }
    _check(generation);
    final mismatched = <String>{};
    for (final entry in Map.of(_doneAssign).entries) {
      final found = devices.where((d) => sameMac(d['mac'], entry.key));
      // Not listed yet: the gateway has not connected it; success, waiting.
      if (found.isEmpty) continue;
      final device = found.first;
      final actual = (device['device_number'] as num?)?.toInt();
      if (actual != null && actual != entry.value) {
        final reason = readbackMismatchText(actual, entry.value);
        _doneAssign.remove(entry.key);
        mismatched.add(entry.key);
        failed[entry.key] = reason;
        results[entry.key] = '指派失敗：$reason';
        for (final p in state.ptus.where((p) => p['mac'] == entry.key)) {
          p['device_number'] = actual;
        }
      } else if (device['connected'] == true) {
        results[entry.key] = '已連線 #${entry.value}';
      }
    }
    _settlePending(results);
    state = state.copy(
      results: Map.of(results),
      assignFailed: {...state.assignFailed, ...failed},
      assignedOk: state.assignedOk.difference(mismatched),
      assignStatus: {
        ...state.assignStatus,
        for (final mac in mismatched)
          mac: AssignStatus(
            AssignPhase.failed,
            detail: 'get_ble_devices: ${failed[mac]}',
          ),
      },
    );
    await _save();
  }

  /// Read-back done: unverified acks that did not mismatch are successes
  /// still waiting for the gateway to connect.
  void _settlePending(Map<String, String> results) {
    for (final mac in _pendingReadback) {
      final id = _doneAssign[mac];
      if (id != null && results[mac] == pendingReadbackText(id)) {
        results[mac] = '已指派 #$id，等待連線';
      }
    }
    _pendingReadback.clear();
  }

  /// [skip]: PTUs already assigned before the APP restarted (not re-sent).
  Future<void> configurePtus({Set<String> skip = const {}}) =>
      _step8Run('逐台編號並開始監控', 240, (generation) async {
        final chosen = state.ptus
            .where((p) => state.selected.contains(p['mac']))
            .toList();
        if (chosen.isEmpty || chosen.length > targetPtuCount) {
          throw const GatewayFailure('no_devices');
        }
        _provisioningMayBeActive = true;
        if (skip.isEmpty) {
          _doneAssign.clear();
          _inflightAssign.clear();
        }
        final targets = chosen.where((p) => !skip.contains(p['mac'])).toList();
        state = state.copy(
          step: 5,
          results: {
            for (final p in chosen)
              if (skip.contains(p['mac']))
                p['mac'].toString(): '已指派 #${p['device_number']}',
          },
          assignRunning: true,
          assignStatus: _assignStart(chosen, targets),
          assignFailed: {},
          unassigned: {},
          assignedOk: skip,
          resumePending: false,
          monitoringOk: false,
        );
        final failed = await _assignAll(generation, targets);
        await _startMonitoring(generation, chosen, failed);
      });

  /// Direct mode on firmware 1.7.20+: keeps the gateway's `direct` report
  /// (state, threshold, bound MAC, candidates). `get_status` is the only op
  /// that carries `direct` (get_ble_devices does not, despite once being
  /// assumed to — cmd_contract.md's identify section clarifies this), so
  /// this reads it directly rather than probing a get_ble_devices reply
  /// first. Never fails the caller: the report is advisory.
  Future<void> _absorbDirect(int generation) async {
    if (!ref.read(topologyProvider).topology.isDirect ||
        !directAutoConnectSupported(state.config)) {
      return;
    }
    Object? direct;
    try {
      direct = (await _link.command('get_status'))['direct'];
    } catch (_) {
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    if (direct is Map && DirectStatus.from(direct) != null) {
      _takeDirect(direct);
    }
  }

  /// Direct mode: sets the gateway's auto-connect threshold
  /// (`auto_connect_min_rssi`, dBm) and reads the config back.
  Future<void> setDirectMinRssi(int dbm) => _directConfig({
    'auto_connect_min_rssi': dbm.clamp(minDirectRssi, maxDirectRssi),
  });

  /// Round 18 「校正門檻」: this pile's confirmed PTU — the one the
  /// installer identified (「辨識此樁」 made it blink), else the one
  /// 「是這台」 assigned, else the gateway's binding; null while none is
  /// known (the calibration then asks to identify it first).
  String? get calibrationOwnMac {
    final identified = state.identifiedMac;
    if (identified != null) return identified;
    if (directFlow && state.assignedOk.length == 1) {
      return state.assignedOk.single;
    }
    return gatewayBindMac;
  }

  /// Round 18 「校正門檻」: reads `get_status.direct` every
  /// [directCalibrationInterval] for [directCalibrationDuration] and yields
  /// the samples of [ownMac] (link RSSI) and its neighbours (candidate
  /// peaks) after each read; the last one is [DirectCalibrationSamples.done].
  /// Cancelling the subscription stops it. Reads only — nothing is written
  /// and the page is not marked busy; a failed read is skipped.
  ///
  /// Time sampled: the wall clock, or the pauses waited when more (the
  /// same in the field; under a fake test clock only the pauses advance).
  Stream<DirectCalibrationSamples> sampleDirectCalibration(
    String ownMac,
  ) async* {
    final samples = DirectCalibrationSamples(ownMac);
    final clock = Stopwatch()..start();
    var waited = Duration.zero;
    while (ref.mounted) {
      try {
        samples.add((await _link.command('get_status'))['direct']);
      } catch (_) {
        samples.miss();
      }
      if (!ref.mounted) return;
      final elapsed = clock.elapsed > waited ? clock.elapsed : waited;
      samples.elapsed = elapsed;
      samples.done = elapsed >= directCalibrationDuration;
      yield samples;
      if (samples.done) return;
      final left = directCalibrationDuration - elapsed;
      final pause = left < directCalibrationInterval
          ? left
          : directCalibrationInterval;
      await Future<void>.delayed(pause);
      waited += pause;
    }
  }

  /// Round 18 「校正門檻」 → 「寫入閘道器」: sends `auto_connect_min_rssi`
  /// [dbm] and reads get_config back; true only when the gateway reports
  /// that value (it keeps it in flash). Otherwise false with the error
  /// shown (a read-back with another value: `direct_threshold_not_saved`).
  Future<bool> saveDirectThreshold(int dbm) async {
    if (state.busy) return false;
    final wanted = dbm.clamp(minDirectRssi, maxDirectRssi);
    var saved = false;
    await _sideTask('正在寫入門檻 $wanted dBm', 20, (generation) async {
      if (!directAutoConnectSupported(state.config)) {
        throw const GatewayFailure('direct_unsupported');
      }
      await _command(generation, 'set_config', {
        'auto_connect_min_rssi': wanted,
      });
      final config = await _command(generation, 'get_config');
      state = state.copy(config: {...state.config, ...config});
      final readBack = config['auto_connect_min_rssi'];
      if (readBack is! num || readBack.toInt() != wanted) {
        throw GatewayFailure(
          'direct_threshold_not_saved',
          detail: '寫入 $wanted，回讀 ${readBack ?? '（無）'}',
        );
      }
      saved = true;
      await _absorbDirect(generation);
      _syncDirectPick();
    });
    return saved && ref.mounted && state.error == null;
  }

  /// Direct mode: binds the gateway to the PTU it is connected to now
  /// ([bind] true) or clears the binding (`direct_bind_mac: ""`).
  ///
  /// Round 15b: an explicit bind is recorded as confirmed (entering step 7
  /// later does not ask about it); either way the binding is no longer a
  /// temporary one nor a leftover to ask about.
  Future<void> setDirectBind(bool bind) async {
    final mac = bind ? directConnectedMac : null;
    if (bind && mac == null) {
      const failure = GatewayFailure('direct_no_ptu');
      state = state.copy(error: failure.message);
      _field.onFailure(failure, ctlStep: state.step);
      return;
    }
    await _directConfig({'direct_bind_mac': mac ?? ''});
    if (!ref.mounted) return;
    final bound = directBoundMacOf(state.config);
    if (bind ? bound != null && sameMac(bound, mac) : bound == null) {
      await _rememberBind(bound);
      if (!ref.mounted) return;
      state = state.copy(
        tempBoundMac: null,
        strayBindMac: null,
        error: state.error,
      );
    }
  }

  /// MAC of the PTU the gateway is connected to (direct mode), if any.
  String? get directConnectedMac {
    final row = state.ptus
        .where((p) => p['connected'] == true && p['mac'] != null)
        .firstOrNull;
    return row?['mac'].toString();
  }

  Future<void> _directConfig(Map<String, dynamic> params) =>
      _sideTask('正在更新直連設定', 20, (generation) async {
        if (!directAutoConnectSupported(state.config)) {
          throw const GatewayFailure('direct_unsupported');
        }
        await _command(generation, 'set_config', params);
        final config = await _command(generation, 'get_config');
        state = state.copy(config: {...state.config, ...config});
        await _absorbDirect(generation);
        _syncDirectPick();
      });

  /// Round 15 「是這台，開始監控」 (direct flow): number the PTU the gateway
  /// itself picked (#1), bind it when 「確認後綁定 PTU」 is on, then
  /// join_fleet and wait for its data — no waiting for a PTU the APP chose.
  /// The pick is read again first: when the gateway switched meanwhile the
  /// new one is shown and nothing is assigned (confirm it with 「辨識此樁」).
  ///
  /// Round 15b: only the PTU the installer identified (the last 「辨識此樁」
  /// ack's MAC) is confirmed — never identified: 「請先按「辨識此樁」確認」
  /// and nothing is sent; the gateway switched meanwhile (read again here,
  /// or seen by the step 7 refresh): the identification is dropped, a
  /// yellow 「閘道器已切換到另一顆 PTU…請重新辨識」 shows and nothing is
  /// assigned.
  Future<void> confirmDirectPick() async {
    if (state.busy) return;
    if (directFlow &&
        directIdentifyRequired(state.config) &&
        state.identifiedMac == null) {
      state = state.copy(
        directNotice: state.directNotice.isEmpty
            ? directIdentifyFirstText
            : state.directNotice,
        error: state.error,
      );
      return;
    }
    await _confirmDirectPick();
    // A link loss before step 8 began (re-reading the pick) is a step 7
    // loss: the same automatic reconnect as there.
    if (ref.mounted && !_autoRelinking && _linkLostAt(4)) {
      await _autoRelink(4);
    }
  }

  Future<void> _confirmDirectPick() =>
      _step8Run('正在指派 #$directPtuId 並開始監控', 150, (generation) async {
        if (!directFlow) throw const GatewayFailure('direct_unsupported');
        final shown = state.selected.firstOrNull;
        final identified = state.identifiedMac;
        final required = directIdentifyRequired(state.config);
        final status = await _command(generation, 'get_status');
        _check(generation);
        _takeDirect(status['direct']);
        final picked = state.direct?.pickedMac;
        _syncDirectPick();
        if (picked == null) {
          state = state.copy(message: directPickMessage(state.direct));
          throw const GatewayFailure('direct_pick_missing');
        }
        if (required
            ? identified == null || !sameMac(identified, picked)
            : shown == null || !sameMac(shown, picked)) {
          final notice = required
              ? directSwitchedText(picked)
              : '閘道器目前連的是 PTU $picked，請先按「辨識此樁」確認是眼前這台，再按「是這台，開始監控」。';
          state = state.copy(
            identifiedMac: null,
            directNotice: notice,
            message: notice,
          );
          return;
        }
        final row = state.ptus.single;
        final mac = row['mac'].toString();
        // Round 15b: confirmed — a temporary 「不是這台？」 binding (or a
        // leftover one the installer did not answer) becomes permanent.
        final gatewayBound = directBoundMacOf(state.config);
        if (gatewayBound != null && sameMac(gatewayBound, mac)) {
          await _rememberBind(gatewayBound);
        }
        state = state.copy(
          tempBoundMac: null,
          tempRestoreMac: null,
          strayBindMac: null,
          directNotice: '',
        );
        final done =
            state.assignedOk.any((m) => sameMac(m, mac)) &&
            (row['device_number'] as num?)?.toInt() == directPtuId;
        _provisioningMayBeActive = true;
        if (!done) {
          _doneAssign.clear();
          _inflightAssign.clear();
        }
        state = state.copy(
          step: 5,
          results: done ? {mac: '已指派 #$directPtuId'} : {},
          assignRunning: true,
          assignStatus: _assignStart([row], done ? const [] : [row]),
          assignFailed: {},
          unassigned: {},
          assignedOk: done ? {mac} : {},
          resumePending: false,
          monitoringOk: false,
          identifyNote: '',
        );
        final failed = done
            ? <String, String>{}
            : await _assignAll(generation, [row]);
        final bound = directBoundMacOf(state.config);
        if (failed.isEmpty &&
            ref.read(topologyProvider).directBindOnConfirm &&
            (bound == null || !sameMac(bound, mac))) {
          await _command(generation, 'set_config', {'direct_bind_mac': mac});
          state = state.copy(config: {...state.config, 'direct_bind_mac': mac});
          await _rememberBind(mac);
        }
        await _startMonitoring(generation, [row], failed);
      });

  /// Round 16b: the gateway's PTU binding as last read — the step 7 status
  /// (`direct.bound_mac`, refreshed while step 7 is open), else get_config;
  /// null when unbound.
  String? get gatewayBindMac => state.directRaw.containsKey('bound_mac')
      ? state.direct?.boundMac
      : directBoundMacOf(state.config);

  /// Round 15 「不是這台？」 → a candidate: bind the gateway to [mac] (a
  /// temporary binding that makes it switch) and wait until it reports that
  /// PTU connected; the installer then identifies it again. The binding is
  /// kept afterwards — the installer chose this PTU explicitly — and the
  /// done page names it.
  ///
  /// Round 16: waits [directSwitchWait] (the countdown shows the same); if
  /// the gateway is still switching then, the step 7 refresh clears the
  /// error as soon as it reports the chosen PTU ([_syncDirectPick]).
  Future<void> switchDirectPick(String mac) async {
    final wait = directSwitchWait;
    await _run(
      relinkStep: 4,
      countdown: directSwitchSeconds,
      '正在讓閘道器改連 PTU $mac',
      directSwitchSeconds + 10,
      (generation) async {
        final until = DateTime.now().add(wait);
        if (!directFlow) throw const GatewayFailure('direct_unsupported');
        // Round 15b: temporary until 「是這台」 (set before sending, so a lost
        // ack is still undone by a cancel). Round 16b: remember the
        // binding from before the first switch — 取消 puts it back (a
        // second switch keeps it: still the binding before this one).
        state = state.copy(
          identifyNote: '',
          identifiedMac: null,
          directNotice: '',
          tempRestoreMac: state.tempBoundMac == null
              ? gatewayBindMac
              : state.tempRestoreMac,
          tempBoundMac: mac,
          strayBindMac: null,
        );
        await _command(generation, 'set_config', {'direct_bind_mac': mac});
        state = state.copy(config: {...state.config, 'direct_bind_mac': mac});
        final ok = await _pollDirectPick(generation, want: mac, until: until);
        _syncDirectPick();
        if (!ok) {
          state = state.copy(message: directSwitchPendingText(mac));
          throw const GatewayFailure('direct_switch_failed');
        }
        state = state.copy(message: directSwitchDoneText(mac));
      },
    );
    if (ref.mounted && !_autoRelinking && _linkLostAt(4)) {
      await _autoRelink(4);
    }
  }

  /// Round 17: 「重新搜尋」 in the direct flow — with a pick the gateway runs
  /// a new collection window ([freshDirectWindow]); without one, the usual
  /// [discover].
  Future<void> rescanDirect() async {
    if (state.busy) return;
    if (!directFlow || state.direct?.pickedMac == null) return discover();
    await freshDirectWindow();
  }

  /// Round 17: 「不是這台？」 with no candidates, or 「重新搜尋」 with a pick.
  /// Field round 17: after a binding was undone the gateway kept its PTU
  /// (re-evaluate "keep"), reported `candidates: []` and ran no further
  /// collection window (none runs while connected), so step 7 had no way
  /// to pick another PTU. Disconnecting the connected PTU makes the
  /// gateway resume scanning and pick again by its own rules
  /// (cmd_contract.md §3A); this polls until that window's candidates are
  /// reported. The identification stays when the same PTU comes back.
  Future<void> freshDirectWindow() async {
    await _run(relinkStep: 4, directFreshWindowText, 45, (generation) async {
      if (!directFlow) throw const GatewayFailure('direct_unsupported');
      final before = state.direct;
      final picked = before?.pickedMac;
      if (picked != null) {
        try {
          await _command(generation, 'disconnect_device', {
            'mac': formatMac(picked),
          });
        } on GatewayFailure catch (e) {
          // Already gone (dropped meanwhile): the scan runs anyway.
          if (!e.fromGateway) rethrow;
        }
      }
      await _pollFreshWindow(generation, before);
      _syncDirectPick();
      state = state.copy(message: directPickMessage(state.direct));
    });
    if (ref.mounted && !_autoRelinking && _linkLostAt(4)) {
      await _autoRelink(4);
    }
  }

  /// Polls get_status until a collection window newer than [before] has
  /// reported its candidates and the gateway decided (connected, or none /
  /// bound missing) — at most [directPollLimit] reads. Newer: the pick
  /// went away (or changed) at least once, or candidates appeared where
  /// [before] had none.
  Future<void> _pollFreshWindow(int generation, DirectStatus? before) async {
    final was = before?.pickedMac;
    var gap = was == null;
    for (var i = 0; ; i++) {
      if (i > 0) {
        await Future<void>.delayed(directPollInterval);
        _check(generation);
      }
      final status = await _command(generation, 'get_status');
      _check(generation);
      _takeDirect(status['direct']);
      final direct = state.direct;
      final picked = direct?.pickedMac;
      final candidates = direct?.candidates ?? const [];
      if (picked == null || !sameMac(picked, was)) gap = true;
      final fresh =
          gap ||
          ((before?.candidates.isEmpty ?? true) && candidates.isNotEmpty);
      final decided =
          picked != null ||
          direct?.state == DirectState.noCandidate ||
          direct?.state == DirectState.boundMissing;
      if (fresh && decided && candidates.isNotEmpty) return;
      if (i + 1 >= directPollLimit) return;
    }
  }

  /// Round 15b, entering step 7 (direct flow): a gateway binding that is
  /// neither this run's temporary one nor recorded as confirmed here is
  /// shown as 「閘道器目前綁定 PTU…」 with 「保留」/「解除」 — never cleared
  /// by itself.
  Future<void> _checkStrayBind(
    int generation,
    Map<String, dynamic> config,
  ) async {
    final bound = directBoundMacOf(config);
    final temp = state.tempBoundMac;
    String? stray;
    if (bound != null && (temp == null || !sameMac(temp, bound))) {
      final remembered = await _rememberedBind();
      _check(generation);
      if (remembered == null || !sameMac(remembered, bound)) stray = bound;
    }
    // The temporary binding is gone (or replaced): nothing to undo later.
    final keep = temp != null && bound != null && sameMac(temp, bound);
    state = state.copy(
      strayBindMac: stray,
      tempBoundMac: keep ? temp : null,
      tempRestoreMac: keep ? state.tempRestoreMac : null,
    );
  }

  /// 「保留」 a leftover binding: recorded as confirmed, not asked again.
  Future<void> keepStrayBind() async {
    final mac = state.strayBindMac;
    if (mac == null || state.busy) return;
    await _rememberBind(mac);
    if (ref.mounted) {
      state = state.copy(strayBindMac: null, error: state.error);
    }
  }

  /// 「解除」 a leftover binding: clear it on the gateway and wait for its
  /// new pick (identify it again).
  Future<void> releaseStrayBind() async {
    if (state.strayBindMac == null) return;
    await _run(relinkStep: 4, '正在解除閘道器的 PTU 綁定', 45, (generation) async {
      await _command(generation, 'set_config', {'direct_bind_mac': ''});
      state = state.copy(
        config: {...state.config, 'direct_bind_mac': ''},
        strayBindMac: null,
        tempBoundMac: null,
        identifiedMac: null,
        identifyNote: '',
        directNotice: '',
      );
      await _rememberBind(null);
      await _pollDirectPick(generation);
      _syncDirectPick();
      state = state.copy(message: directPickMessage(state.direct));
    });
    if (ref.mounted && !_autoRelinking && _linkLostAt(4)) {
      await _autoRelink(4);
    }
  }

  /// Round 15b: 取消 / 結束 / 返回 before 「是這台」 — a temporary
  /// 「不是這台？」 binding is undone on the gateway. Never blocks: returns
  /// the failure text (for 詳細資訊), null when there was nothing to undo
  /// or it was undone.
  ///
  /// Round 16b: undone means the binding from before the switch is put
  /// back ([CommissionState.tempRestoreMac]): a MAC bound before is bound
  /// again, none is cleared — never cleared regardless (round 16 field: a
  /// binding confirmed earlier was lost). Also with 「確認後綁定 PTU」 on:
  /// only 「是這台」 makes the new MAC count.
  Future<String?> _releaseTempBind() async {
    final mac = state.tempBoundMac;
    if (mac == null || !ref.mounted) return null;
    final restore = state.tempRestoreMac;
    if (restore != null && sameMac(restore, mac)) {
      // Switched back to the binding from before: nothing to undo.
      state = state.copy(
        tempBoundMac: null,
        tempRestoreMac: null,
        error: state.error,
      );
      return null;
    }
    try {
      await _rawCommand('set_config', {
        'direct_bind_mac': restore ?? '',
      }).timeout(const Duration(seconds: 8));
    } catch (error) {
      return error.toString();
    }
    // A binding put back keeps its confirmed record (or its question).
    if (restore == null) await _rememberBind(null);
    if (ref.mounted) {
      state = state.copy(
        tempBoundMac: null,
        tempRestoreMac: null,
        config: {...state.config, 'direct_bind_mac': restore ?? ''},
        error: state.error,
      );
    }
    return null;
  }

  String get _bindPrefsKey =>
      _link.demo ? 'demo_direct_confirmed_bind' : 'direct_confirmed_bind';

  String get _bindGatewayKey =>
      state.config['gateway_uid']?.toString() ??
      state.peer?.id ??
      '$site/$gateway';

  /// PTU MAC this APP confirmed as the gateway's binding (「是這台」 with a
  /// binding, 「綁定目前 PTU」, 「保留」), or null.
  Future<String?> _rememberedBind() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bindPrefsKey);
      if (raw == null) return null;
      final value = (jsonDecode(raw) as Map)[_bindGatewayKey];
      return value is String && value.isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Records (or with null forgets) the confirmed binding of this gateway.
  Future<void> _rememberBind(String? mac) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bindPrefsKey);
      final map = <String, dynamic>{
        if (raw != null) ...Map<String, dynamic>.from(jsonDecode(raw) as Map),
      };
      if (mac == null) {
        map.remove(_bindGatewayKey);
      } else {
        map[_bindGatewayKey] = mac;
      }
      await prefs.setString(_bindPrefsKey, jsonEncode(map));
    } catch (_) {}
  }

  /// [id] is a number this gateway assigns: #1 in direct mode, else its
  /// five-number range starting at [first].
  bool _ownsNumber(int id, int first) =>
      _directFixedId ? id == directPtuId : id >= first && id < first + 5;

  /// Direct mode on firmware that picks the PTU itself (1.7.20+): every PTU
  /// is #1. Older firmware only accepts its group's first number, so it
  /// keeps the range numbering.
  bool get _directFixedId =>
      ref.read(topologyProvider).topology.isDirect &&
      directAutoConnectSupported(state.config);

  /// Selected PTUs that [devices] (get_ble_devices rows) show connected with
  /// the number the APP assigned, or, when the ack was lost, with a unique
  /// number inside this gateway's range. Marks them assigned (「已連線 #n」).
  Set<String> _reconcileFrom(
    Iterable<Map<String, dynamic>> devices,
    Set<String> selected,
  ) {
    final first = (gateway - 1) * 5 + 1;
    final rows = devices.where((d) => d['connected'] == true).toList();
    final ok = <String>{};
    final results = Map<String, String>.of(state.results);
    for (final mac in selected) {
      final found = rows.where((d) => sameMac(d['mac'], mac));
      if (found.isEmpty) continue;
      final id = (found.first['device_number'] as num?)?.toInt() ?? 0;
      final expected = _doneAssign[mac] ?? _inflightAssign[mac];
      final inRange = _ownsNumber(id, first);
      final unique =
          rows
              .where((d) => (d['device_number'] as num?)?.toInt() == id)
              .length ==
          1;
      if (expected != null ? id != expected : !(inRange && unique)) continue;
      _doneAssign[mac] = id;
      ok.add(mac);
      results[mac] = '已連線 #$id';
      for (final p in state.ptus.where((p) => sameMac(p['mac'], mac))) {
        p['device_number'] = id;
      }
    }
    if (ok.isNotEmpty) {
      state = state.copy(
        results: results,
        assignStatus: {
          ...state.assignStatus,
          for (final mac in ok)
            if (state.assignStatus.containsKey(mac))
              mac: AssignStatus(AssignPhase.done, id: _doneAssign[mac]),
        },
        assignedOk: {...state.assignedOk, ...ok},
        unassigned: state.unassigned.difference(ok),
        assignFailed: {
          for (final e in state.assignFailed.entries)
            if (!ok.contains(e.key)) e.key: e.value,
        },
      );
    }
    return ok;
  }

  /// After a link loss: read the gateway's view before resending anything.
  Future<void> _reconcile(int generation) async {
    final Map<String, dynamic> response;
    try {
      response = await _command(generation, 'get_ble_devices');
    } catch (e) {
      if (e is GatewayFailure && e.code == 'cancelled') rethrow;
      if (isPhoneLinkFailure(e)) rethrow;
      return; // Old firmware / busy: fall back to the APP's own record.
    }
    _check(generation);
    _reconcileFrom(
      (response['devices'] as List? ?? []).map(
        (d) => Map<String, dynamic>.from(d as Map),
      ),
      state.selected,
    );
    await _save();
  }

  /// Re-opens the phone↔gateway BLE link within [reconnectBudget]; a
  /// failure becomes 'reconnect_failed' (retry / back to gateway search).
  Future<void> _reconnect(
    int generation, {
    Future<void> Function()? after,
  }) async {
    final peer = state.peer;
    if (peer == null) throw const GatewayFailure('reconnect_failed');
    final Object link = _link;
    if (link is BluetoothReadiness && await link.adapterSettling()) {
      state = state.copy(message: waitingBluetoothText);
      await link.waitAdapterReady(bluetoothReadyBudget);
      _check(generation);
    }
    state = state.copy(
      message: reconnectingText,
      relinkStage: RelinkStage.reconnecting,
    );
    try {
      await _relink(generation, peer, after: after).timeout(reconnectBudget);
    } catch (e) {
      if (e is GatewayFailure && e.code == 'cancelled') rethrow;
      _check(generation);
      unawaited(_link.disconnect());
      throw GatewayFailure(
        'reconnect_failed',
        detail: withFirstFailure(e.toString(), _link),
      );
    }
    _stopWatch(UploadWatch.idle);
  }

  /// 「重新連線並繼續」: reconnect the gateway, then assign every selected
  /// PTU not yet successfully assigned (including ones checked after the
  /// disconnect), then set_config / join_fleet.
  /// Generation of the current 「重新連線並繼續」 run (round 11 banner).
  int? _resumeGeneration;

  Future<void> resumeAssign() =>
      _step8Run(reconnectingText, 240, (generation) async {
        _resumeGeneration = generation;
        // Round 11: the reconcile (get_ble_devices) runs inside the
        // persistent link loop, so a link that drops right after connecting
        // is retried for the whole [connectPersistence] instead of ending
        // the run after one round.
        await _reconnect(
          generation,
          after: () async {
            // Round 21: back; the list is read again.
            state = state.copy(
              relinkStage: RelinkStage.reloading,
              error: state.error,
            );
            // A gateway restart (not the PTUs) may have cut the link.
            await _checkBoot(generation);
            await _reconcile(generation);
          },
        );
        final chosen = state.ptus
            .where((p) => state.selected.contains(p['mac']))
            .toList();
        final targets = chosen
            .where((p) => !state.assignedOk.contains(p['mac']))
            .toList();
        state = state.copy(
          step: 5,
          resumePending: false,
          monitorUnconfirmed: false,
          relinkStage: RelinkStage.resumed,
          assignRunning: true,
          assignStatus: _assignStart(chosen, targets),
          message: targets.isEmpty
              ? '正在確認 Gateway 監控狀態'
              : '繼續指派 ${targets.length} 台',
        );
        // Round 7b: everything already assigned and the gateway already
        // monitors all of them with upload running → done, no join_fleet.
        if (targets.isEmpty && await _alreadyMonitoring(generation, chosen)) {
          return;
        }
        _provisioningMayBeActive = true;
        final failed = await _assignAll(generation, targets);
        state = state.copy(unassigned: {});
        await _startMonitoring(
          generation,
          chosen,
          failed,
          resumed: targets.isEmpty,
        );
      });

  /// After a resume with nothing left to assign: true (and step 9) when the
  /// gateway already reports every chosen PTU connected, BLE on, upload not
  /// paused and the monitoring limit set.
  Future<bool> _alreadyMonitoring(
    int generation,
    List<Map<String, dynamic>> chosen,
  ) async {
    final response = await _command(generation, 'get_ble_devices');
    final actual = (response['devices'] as List? ?? [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
    final allConnected = chosen.every(
      (c) => actual.any(
        (p) => sameMac(p['mac'], c['mac']) && p['connected'] == true,
      ),
    );
    if (!allConnected) return false;
    final config = await _command(generation, 'get_config');
    final limit = monitorLimit(ref.read(topologyProvider).topology.isStar);
    if (config['upload_paused'] == true ||
        config['ble_enabled'] == false ||
        config['max_connections'] != limit) {
      return false;
    }
    _provisioningMayBeActive = false;
    final owned = _ownedConnected(actual);
    state = state.copy(
      step: 6,
      config: {...state.config, ...config},
      ptus: owned,
      results: {
        for (final p in owned)
          p['mac'].toString(): '已連線 #${p['device_number']}',
      },
      message: '配置完成，請驗證後端資料',
    );
    return true;
  }

  /// Step 9 「略過此台」: an idle PTU ([CommissionState.verifyWaiting]) no
  /// longer blocks the rest of verification — marked 「未驗證（已略過）」, the
  /// overall pass/fail judgement and the install report both exclude it.
  void skipVerifyPtu(int id) {
    if (state.step != 6 || !state.verifyWaiting.contains(id)) return;
    if (state.verifySkipped.contains(id)) return;
    state = state.copy(verifySkipped: {...state.verifySkipped, id});
  }

  /// 「略過」 after [CommissionState.monitorUnconfirmed]: go on to data
  /// verification with the chosen PTUs; verification shows what is missing.
  void skipMonitorConfirm() {
    if (state.busy || !state.monitorUnconfirmed) return;
    _provisioningMayBeActive = false;
    state = state.copy(
      step: 6,
      monitorUnconfirmed: false,
      resumePending: false,
      ptus: state.ptus
          .where(
            (p) =>
                state.selected.contains(p['mac']) ||
                state.assignedOk.contains(p['mac']),
          )
          .toList(),
      message: '已略過監控確認，請在資料驗證確認各台是否上傳。',
    );
    unawaited(_save());
  }

  /// 「重試這 N 台」：只對上次指派失敗的 PTU 重跑指派，再 set_config/join_fleet。
  Future<void> retryFailedAssign() =>
      _step8Run('重試指派失敗的 PTU', 240, (generation) async {
        final chosen = state.ptus
            .where(
              (p) =>
                  state.selected.contains(p['mac']) ||
                  state.assignFailed.containsKey(p['mac']),
            )
            .toList();
        final targets = chosen
            .where((p) => state.assignFailed.containsKey(p['mac']))
            .toList();
        if (targets.isEmpty) throw const GatewayFailure('no_devices');
        state = state.copy(
          selected: chosen.map((p) => p['mac'].toString()).toSet(),
        );
        _provisioningMayBeActive = true;
        state = state.copy(
          step: 5,
          assignRunning: true,
          assignStatus: _assignStart(chosen, targets),
        );
        final failed = await _assignAll(generation, targets);
        await _startMonitoring(generation, chosen, failed);
      });

  /// set_config（成功台數，至少 1）＋ join_fleet；有失敗時先讓成功的上線、
  /// 停在選擇頁列出失敗台；全部成功才等連線並進入驗證。
  Future<void> _startMonitoring(
    int generation,
    List<Map<String, dynamic>> chosen,
    Map<String, String> failed, {
    bool resumed = false,
  }) async {
    final ok = chosen.where((p) => !failed.containsKey(p['mac'])).length;
    if (ok == 0) {
      // Nothing succeeded: do NOT send set_config (it would drop the gateway
      // to max_connections=1) nor join_fleet; back to selection to retry.
      _provisioningMayBeActive = false;
      state = state.copy(
        step: 4,
        assignFailed: failed,
        message:
            '${failed.length} 台都指派失敗，Gateway 設定未變更；請確認 PTU 後按「重試這 ${failed.length} 台」。',
      );
      return;
    }
    // Round 9: back at step 4 (「返回選擇 PTU」) and 「配置」 pressed again
    // without new failures — if the gateway already reports every chosen
    // PTU connected with the right max_connections (join_fleet done, per
    // the existing _alreadyMonitoring check), skip re-sending
    // set_config/join_fleet and go straight to step 9; only PTUs newly
    // assigned this round (not yet reflected there) fall through to the
    // full flow below.
    if (failed.isEmpty && await _alreadyMonitoring(generation, chosen)) {
      return;
    }
    final isStar = ref.read(topologyProvider).topology.isStar;
    try {
      await _command(generation, 'set_config', {
        // Never shrink to the success count (round 6: 4 PTUs locked the
        // gateway at 4 and a 5th could never connect).
        'max_connections': monitorLimit(isStar),
      });
      await _command(generation, 'join_fleet');
    } catch (e) {
      if (!isPhoneLinkFailure(e)) rethrow;
      state = state.copy(assignFailed: failed, resumePending: true);
      throw GatewayFailure('phone_link_lost', detail: e.toString());
    }
    state = state.copy(assignFailed: failed);
    if (failed.isNotEmpty) {
      _provisioningMayBeActive = false;
      state = state.copy(
        step: 4,
        message:
            '已先讓 $ok 台上線；${failed.length} 台指派失敗，可按「重試這 ${failed.length} 台」。',
      );
      return;
    }
    await _waitConnected(
      generation,
      chosen,
      limitSec: resumed ? 30 : 90,
      confirmOnly: resumed,
    );
  }

  Future<void> _waitConnected(
    int generation,
    List<Map<String, dynamic>> chosen, {
    int limitSec = 90,
    bool confirmOnly = false,
  }) async {
    try {
      await _waitConnectedLoop(generation, chosen, limitSec, confirmOnly);
    } catch (e) {
      // Round 7b: a link loss while waiting for the PTUs used to surface as a
      // bare 'disconnected' (「尚未確認 Gateway 已恢復監控」, no resume
      // button). It is a step 8 link loss like one during the assignments.
      if (!isStep8LinkLoss(e, generation == _generation) ||
          (e is GatewayFailure && e.code == 'reconnect_failed')) {
        rethrow;
      }
      state = state.copy(resumePending: true);
      await _save();
      throw GatewayFailure('phone_link_lost', detail: e.toString());
    }
  }

  /// Connected rows this gateway owns: the chosen PTUs plus any other
  /// connected PTU carrying a unique number in this gateway's range (the
  /// gateway took it earlier). Marks them assigned (reconciled).
  List<Map<String, dynamic>> _ownedConnected(List<Map<String, dynamic>> rows) {
    final first = (gateway - 1) * 5 + 1;
    final extra = rows
        .where((p) {
          if (p['connected'] != true) return false;
          if (state.selected.any((m) => sameMac(m, p['mac']))) return false;
          final id = (p['device_number'] as num?)?.toInt() ?? 0;
          return _ownsNumber(id, first);
        })
        .map((p) => p['mac'].toString())
        .toSet();
    if (extra.isNotEmpty) _reconcileFrom(rows, extra);
    return rows
        .where(
          (p) =>
              p['connected'] == true &&
              (state.selected.any((m) => sameMac(m, p['mac'])) ||
                  state.assignedOk.any((m) => sameMac(m, p['mac']))),
        )
        .toList();
  }

  Future<void> _waitConnectedLoop(
    int generation,
    List<Map<String, dynamic>> chosen,
    int limitSec,
    bool confirmOnly,
  ) async {
    for (int elapsed = 0; elapsed < limitSec; elapsed += 5) {
      await _wait(5, generation);
      final response = await _command(generation, 'get_ble_devices');
      final actual = (response['devices'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      final connected = actual
          .where(
            (p) =>
                state.selected.any((m) => sameMac(m, p['mac'])) &&
                p['connected'] == true &&
                p['notify_enabled'] == true &&
                p['zombie'] != true &&
                ((p['last_data_age_sec'] as num?) ?? 999) < 30,
          )
          .toList();
      if (connected.length == chosen.length) {
        final config = await _command(generation, 'get_config');
        if (config['max_connections'] !=
            monitorLimit(ref.read(topologyProvider).topology.isStar)) {
          throw const GatewayFailure('incomplete');
        }
        await _command(generation, 'check_db_upload');
        _provisioningMayBeActive = false;
        final owned = _ownedConnected(actual);
        state = state.copy(
          step: 6,
          config: config,
          ptus: owned,
          results: {
            for (final p in owned)
              p['mac'].toString(): '已連線 #${p['device_number']}',
          },
          message: '配置完成，請驗證後端資料',
        );
        return;
      }
      if (elapsed >= limitSec - 5 && confirmOnly) {
        // Resume with nothing left to assign: never re-trim the gateway;
        // offer 「重試」 / 「略過」 instead.
        state = state.copy(monitorUnconfirmed: true, resumePending: true);
        await _save();
        throw const GatewayFailure('monitor_unconfirmed');
      }
      if (elapsed >= limitSec - 5) {
        // Never leave a target above actual connections after a failed installation.
        // Never switch BLE or upload off here: the gateway keeps monitoring.
        if (connected.isNotEmpty) {
          final limit = monitorLimit(
            ref.read(topologyProvider).topology.isStar,
          );
          await _command(generation, 'set_config', {'max_connections': limit});
          final readback = await _command(generation, 'get_config');
          if (readback['max_connections'] != limit) {
            throw const GatewayFailure('incomplete');
          }
          _provisioningMayBeActive = false;
        }
        state = state.copy(
          step: 4,
          ptus: actual,
          missing: chosen
              .where((p) => !connected.any((c) => c['mac'] == p['mac']))
              .map((p) => p['mac'].toString())
              .toList(),
          message: connected.isEmpty
              ? directFlow
                    ? '閘道器還沒收到這台 PTU 的資料，請確認 PTU 電源後再按「是這台，開始監控」重試；Gateway 仍維持監控。'
                    : '未連上任何 PTU，請確認 PTU 電源與距離後重試；Gateway 仍維持監控。'
              : '已調整為 ${connected.length} 台；請重新選擇已連線裝置或修復缺少的 PTU。',
        );
        throw const GatewayFailure('incomplete');
      }
    }
  }

  /// [environment] is the selector value (`production` / `local` / `custom`);
  /// when omitted the target is derived from [base] alone.
  ///
  /// Round 13: a backend that answers 5xx, cannot be reached or times out is
  /// retried every [backendRetryGap] (「後端暫時無回應，自動重試中（n）」)
  /// until [backendRetryWindow] of failures has accumulated; the per-PTU
  /// progress is kept, also for the 「重試」 after that.
  Future<void> verify(String base, String password, {String? environment}) =>
      _run('確認每台 PTU 的資料持續進入後端', _verifyRunSeconds, (generation) async {
        state = state.copy(verifyBackendDown: false);
        try {
          await _verify(generation, base, password, environment);
        } on GatewayFailure catch (error) {
          if (error.code == 'backend_unavailable' && ref.mounted) {
            state = state.copy(verifyBackendDown: true);
          }
          rethrow;
        }
      });

  /// Step 9 poll window (seconds of successful polls).
  static const _verifyWindow = 180;

  /// Overall step 9 budget: the poll window, the backend retry window and
  /// one slow failing request on top.
  int get _verifyRunSeconds =>
      _verifyWindow + backendRetryWindow.inSeconds + 40;

  /// Step 9 progress kept when the backend stayed unavailable
  /// ('backend_unavailable'); the next verification of the same PTUs
  /// continues it instead of starting from 0/3.
  ({
    Set<int> ids,
    Map<int, DateTime> previous,
    Map<int, int> counts,
    Map<int, int> lastNew,
    int elapsed,
  })?
  _verifyCarry;

  Future<void> _verify(
    int generation,
    String base,
    String password,
    String? environment,
  ) async {
    if (!state.ptus.any((p) => state.selected.contains(p['mac']))) {
      state = state.copy(step: 4, verified: false, report: '');
      throw const GatewayFailure('no_devices');
    }
    _backend = describeBackend(Uri.tryParse(base.trim()));
    final wanted = _checkUploadTarget(base, environment);
    final running = parseMqttTarget(state.config);
    // Why a gateway can be missing from this backend, from what the APP knows.
    final cause = missingGatewayCause(
      running: running,
      wanted: wanted,
      mqttConnected: state.config['mqtt_connected'],
    );
    // Round 13: time spent on a failing backend in this run (5xx /
    // unreachable / timeout); never counted as the PTUs being idle.
    final outage = Stopwatch();
    var retries = 0;
    // Round 15: the per-PTU progress stays visible under the retry line.
    var progress = '';
    Future<T> backend<T>(Future<T> Function() call) async {
      while (true) {
        try {
          final result = await call();
          outage.stop();
          return result;
        } catch (error) {
          if (!isTransientBackendFailure(error)) rethrow;
          _check(generation);
          outage.start();
          if (outage.elapsed >= backendRetryWindow) {
            throw GatewayFailure(
              'backend_unavailable',
              detail: error is GatewayFailure
                  ? '${error.message}\n$error'
                  : error.toString(),
            );
          }
          retries++;
          state = state.copy(
            message: [
              backendRetryText(retries),
              if (progress.isNotEmpty) progress,
            ].join('\n'),
            error: state.error,
          );
          await Future<void>.delayed(backendRetryGap);
          _check(generation);
        }
      }
    }

    if (!_loggedIn) {
      final secret = _passwordFor(base, password);
      await backend(() => _api.login(base, secret));
      _check(generation);
      _loginOk(base, secret);
    }
    try {
      // Renew the lease for every verification attempt; a cached flag may have expired.
      await backend(
        () => _request(generation, 'PATCH', '$_path/bot-monitor', {
          'enabled': false,
          'ttl_minutes': 30,
        }),
      );
      _lease = true;
    } on GatewayFailure catch (error) {
      if (error.gatewayNotFound) throw error.withCause(cause);
      rethrow;
    }
    final chosen = state.ptus
        .where((p) => state.selected.contains(p['mac']))
        .toList();
    final ids = chosen
        .map((p) => (p['device_number'] as num?)?.toInt() ?? 0)
        .toSet();
    if (ids.isEmpty) throw const GatewayFailure('no_devices');
    final unnumbered = chosen
        .where((p) => ((p['device_number'] as num?)?.toInt() ?? 0) == 0)
        .map((p) => 'PTU ${p['mac']}：PTU 未取得裝置編號（device_number=0）')
        .toList();
    if (unnumbered.isNotEmpty) {
      // A PTU without a number can never pass; report it instead of waiting.
      _diagnosis = (generation, unnumbered.join('\n'));
      throw const GatewayFailure('incomplete');
    }
    // Round 13: continue the progress a backend outage interrupted.
    final carry = _verifyCarry;
    _verifyCarry = null;
    final resume =
        carry != null &&
        carry.ids.length == ids.length &&
        carry.ids.containsAll(ids);
    final previous = resume ? carry.previous : <int, DateTime>{};
    // Per PTU (round 8: one PTU without a new row reset everyone to 0/3).
    final counts = resume ? carry.counts : <int, int>{};
    final lastNew = resume ? carry.lastNew : <int, int>{};
    final start = resume ? carry.elapsed : 0;
    state = state.copy(
      verifyCounts: {for (final id in ids) id: counts[id] ?? 0},
      verifyWaiting: resume ? null : {},
      verifySkipped: resume ? null : {},
    );
    progress = verifyProgressText(
      ids,
      counts,
      state.verifyWaiting,
      state.verifySkipped,
    );
    var elapsed = start;
    try {
      for (; elapsed < start + _verifyWindow; elapsed += verifyPollSeconds) {
        final (fleet, install, latest) = await backend(() async {
          final fleet = await _fleet(generation);
          if (fleet?['upload_paused'] == true) {
            await _command(generation, 'set_data_upload', {'enabled': true});
          }
          final install = await _request(
            generation,
            'GET',
            '$_path/verify-installation?threshold_minutes=2&device_ids=${ids.join(',')}',
          );
          final latest = await _request(
            generation,
            'GET',
            '/api/latest?site_id=$site&gateway_id=$gateway',
          );
          return (fleet, install, latest);
        });
        _check(generation);
        final rows = (latest['items'] as List? ?? [])
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        if (fleet?['online'] == true || backendRowsFresh(rows)) {
          state = state.copy(backendSeenAt: DateTime.now());
        }
        final before = Map<int, DateTime>.of(previous);
        verifyTally(
          ids: ids,
          rows: rows,
          previous: previous,
          counts: counts,
          lastNew: lastNew,
          elapsed: elapsed,
        );
        final waiting = {
          for (final id in ids)
            if (elapsed - (lastNew[id] ?? 0) >= verifyIdleLimit) id,
        };
        // Round 9: a PTU the installer skipped (after staying idle) no longer
        // blocks the rest — judge pass/fail on the remaining, active PTUs only.
        final skipped = state.verifySkipped;
        final active = ids.where((id) => !skipped.contains(id)).toList();
        final installDevices = (install['devices'] as List? ?? [])
            .whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        // No per-device breakdown (older backend, or the demo stub): fall
        // back to the overall flag for every active PTU.
        final allOkActive = active.every(
          (id) => installDevices.isEmpty
              ? install['all_ok'] == true
              : installDevices.any(
                  (d) => d['device_id'] == id && d['data_ok'] == true,
                ),
        );
        final consecutive = active.isEmpty
            ? 0
            : active.map((id) => counts[id] ?? 0).reduce(min);
        final good = active.isNotEmpty && allOkActive && consecutive >= 3;
        _diagnosis = (
          generation,
          verifyDiagnosis(
            ids: ids,
            install: install,
            rows: rows,
            fleet: fleet,
            previous: before,
            site: site,
            gateway: gateway,
            consecutive: consecutive,
            backend: _backend,
            cause: cause,
          ),
        );
        progress = verifyProgressText(ids, counts, waiting, skipped);
        state = state.copy(
          message: progress,
          verifyCounts: Map.of(counts),
          verifyWaiting: waiting,
        );
        if (good) {
          await backend(
            () => _request(generation, 'PATCH', '$_path/bot-monitor', {
              'enabled': true,
            }),
          );
          _lease = false;
          final skippedIds = ids.where(skipped.contains).toList()..sort();
          final skippedNote = skippedIds.isEmpty
              ? ''
              : '\n未驗證（已略過）：${skippedIds.map((id) => "#$id").join('、')}，'
                    '請現場確認 ${skippedIds.map((id) => "PTU #$id").join('、')} 電源與位置';
          _reportBody =
              '${_link.demo ? "模擬安裝報告（非實機驗證）" : "安裝報告"}\n站點 $site / 閘道器 $gateway\n${byDeviceNumber(state.ptus).map((p) => "#${p['device_number']}  ${p['mac']}").join('\n')}${directBoundNote(state) == null ? '' : '\n${directBoundNote(state)}'}\n驗證時間：${DateTime.now().toIso8601String()}\n驗證後端：$_backend\n每台連續三次資料更新通過$skippedNote';
          state = state.copy(
            step: 7,
            verified: true,
            online: true,
            report: _report(),
            message: verifiedText,
          );
          _field.end('completed');
          _health?.cancel();
          _abnormalStreak = 0;
          _health = Timer.periodic(
            const Duration(seconds: 15),
            (_) => unawaited(refreshHealth()),
          );
          return;
        }
        await _wait(verifyPollSeconds, generation);
      }
    } on GatewayFailure catch (error) {
      if (error.code == 'backend_unavailable') {
        _verifyCarry = (
          ids: ids,
          previous: previous,
          counts: counts,
          lastNew: lastNew,
          elapsed: elapsed,
        );
      }
      rethrow;
    }
    throw const GatewayFailure('incomplete');
  }

  // ---- Gateway upload target (firmware 1.7.3, docs/mqtt_target.md) ----

  static const _reconnectBudget = Duration(seconds: 45);

  /// Copies mqtt_target / mqtt_host / mqtt_port (and mqtt_connected) from a
  /// get_net_status or get_config result into the gateway config.
  void _absorbTarget(Map<String, dynamic> source) {
    final update = {
      for (final key in mqttStatusKeys)
        if (source.containsKey(key)) key: source[key],
    };
    if (update.isEmpty) return;
    state = state.copy(
      config: {...state.config, ...update},
      error: state.error,
    );
  }

  /// Fails fast when the gateway is known to upload elsewhere than the APP
  /// backend ([base] / [environment]): the data can never arrive, so waiting
  /// the full window only hides why. Returns the wanted target (null = unknown).
  MqttTarget? _checkUploadTarget(String base, String? environment) {
    final wanted = desiredUploadTarget(environment ?? 'custom', base).target;
    final running = parseMqttTarget(state.config);
    if (wanted != null && running != null && !running.sameAs(wanted)) {
      throw GatewayFailure.targetMismatch(
        gatewayTarget: running.plainLabel,
        appTarget: wanted.plainLabel,
      );
    }
    return wanted;
  }

  /// The APP backend was switched to [base]. A login belongs to the old
  /// backend, so every later backend call logs in again first. A monitoring
  /// lease on the old backend is not handed back here (a fire-and-forget
  /// request could race a new login's key); it expires by its TTL or is
  /// returned by 「結束並重新選擇閘道器」. The running step is not touched.
  ///
  /// On step 6/7 the shown result (verification error, 「開通驗證通過」,
  /// data health) came from the old backend, so it is cleared.
  void backendChanged(String base) {
    _field.onBackendChanged(base);
    final next = base.trim();
    if (_loginBase == next && _loggedIn) return;
    if (!state.busy) _backend = describeBackend(Uri.tryParse(next));
    _setLoggedIn(false);
    // Progress kept for 「重試」 belongs to the old backend.
    _verifyCarry = null;
    if (!ref.mounted || state.busy) return;
    if (state.step == 7) {
      state = state.copy(online: false, message: backendSwitchedDoneText);
    } else if (state.step == 6) {
      state = state.copy(
        message: backendSwitchedVerifyText,
        verifyBackendDown: false,
      );
    }
  }

  /// Round 17: 「重新連線並繼續」 after the APP was killed uses the session
  /// token the last login to [base] saved (never the password) before
  /// asking for the password (field round 17: a login dialog on every
  /// resume). A 401 later ends it like any expired session — renewed with
  /// [fallbackPassword] when given (the local test host's known password),
  /// else the installer is asked again. False when there is none.
  Future<bool> restoreSession(String base, {String? fallbackPassword}) async {
    final trimmed = base.trim();
    if (_loggedIn && _loginBase == trimmed) return true;
    final api = _api;
    if (api is! SessionStore) return false;
    bool ok;
    try {
      ok = await (api as SessionStore).restoreSession(trimmed);
    } catch (_) {
      ok = false;
    }
    if (!ok || !ref.mounted) return false;
    _backend = describeBackend(Uri.tryParse(trimmed));
    _setLoggedIn(true, trimmed);
    if ((fallbackPassword ?? '').isNotEmpty) {
      _credentials = (trimmed, fallbackPassword!);
      _field.journal.addSecret(fallbackPassword);
    }
    unawaited(_field.flush());
    return true;
  }

  /// Logs in to [base] outside a step (after switching environments).
  Future<void> login(String base, String password) =>
      _sideTask('登入後端', 30, (generation) async {
        await _api.login(base.trim(), password);
        _check(generation);
        _backend = describeBackend(Uri.tryParse(base.trim()));
        _loginOk(base, password);
      });

  // ---- Background upload-state polling ----

  bool get _canWatch =>
      ref.mounted &&
      state.peer != null &&
      state.step >= 2 &&
      state.netCheckSupported;

  /// Starts (or restarts) polling when the gateway's upload is not yet
  /// confirmed; called after a connect, Wi-Fi change, switch or refresh.
  void _watchUploadIfPending() {
    if (ref.mounted && state.uploadWatch == UploadWatch.linkLost) return;
    if (!_canWatch || state.networkReady) {
      if (ref.mounted && state.uploadWatch == UploadWatch.polling) {
        _stopWatch(UploadWatch.idle);
      }
      return;
    }
    _poll?.cancel();
    _pollTicks = 0;
    state = state.copy(
      uploadWatch: UploadWatch.polling,
      uploadSlow: false,
      uploadLate: false,
      error: state.error,
    );
    _poll = Timer.periodic(_timing.interval, (_) => unawaited(_pollTick()));
    Timer.run(() => unawaited(_pollTick(count: false)));
  }

  void _stopWatch(UploadWatch reason) {
    _poll?.cancel();
    _poll = null;
    final clearLate = reason == UploadWatch.idle && state.uploadLate;
    if (ref.mounted &&
        (state.uploadWatch != reason || state.uploadSlow || clearLate)) {
      state = state.copy(
        uploadWatch: reason,
        uploadSlow: false,
        uploadLate: clearLate ? false : null,
        error: state.error,
      );
    }
  }

  /// One poll: only while no step or command runs on the BLE link.
  Future<void> _pollTick({bool count = true}) async {
    if (!ref.mounted || _poll == null) return;
    if (!_canWatch) return _stopWatch(UploadWatch.idle);
    if (state.networkReady) {
      return _stopWatch(UploadWatch.idle);
    }
    // Time spent under a running step (or in the background) does not count.
    if (state.busy || _pollInFlight || _rssiInFlight || !_foreground) return;
    if (count) _pollTicks++;
    if (_pollTicks > _timing.maxTicks) return _stopWatch(UploadWatch.gaveUp);
    if (!state.uploadSlow && _pollTicks >= _timing.slowTicks) {
      state = state.copy(uploadSlow: true, error: state.error);
    }
    if (!state.uploadLate && _pollTicks >= _timing.lateTicks) {
      state = state.copy(uploadLate: true, error: state.error);
    }
    _pollInFlight = true;
    final generation = _generation;
    try {
      final net = await _link.command('get_net_status');
      if (generation != _generation || !ref.mounted || state.busy) return;
      if (_poll == null) return;
      _absorbTarget(net);
      _absorbNet(net);
      if (state.networkReady) {
        _stopWatch(UploadWatch.idle);
      }
    } on GatewayFailure catch (error) {
      if (generation != _generation || !ref.mounted || _poll == null) return;
      if (error.code == 'disconnected' || error.code == 'not_connected') {
        _stopWatch(UploadWatch.linkLost);
      }
      // busy / not_ready / timeout: skip this round.
    } catch (_) {
      // Unexpected; try again next round.
    } finally {
      _pollInFlight = false;
    }
  }

  /// Copies the gateway's own network fields (get_net_status only); true
  /// when its boot_count shows a restart not seen before ([_noteBoot]).
  bool _absorbNet(Map<String, dynamic> source) {
    final update = {
      for (final key in gatewayNetKeys)
        if (source.containsKey(key)) key: source[key],
    };
    if (update.isEmpty) return false;
    _netReadAt = DateTime.now();
    state = state.copy(net: {...state.net, ...update}, error: state.error);
    return _noteBoot(source);
  }

  // ---- Gateway restarts (boot_count, docs/cmd_contract.md §4.1) ----

  /// Compares the boot_count of [source] (get_config / get_net_status of the
  /// gateway [peerId], default the connected one) with the last one read
  /// from it: a higher count means it restarted in between, shown as
  /// [CommissionState.gatewayReboot]. True when this read found it.
  bool _noteBoot(Map<String, dynamic> source, {String? peerId}) {
    final key = peerId ?? state.peer?.id;
    final count = bootCountOf(source);
    if (key == null || count == null || !ref.mounted) return false;
    final raw = source['reset_reason'];
    final reason = raw is String && raw.isNotEmpty ? raw : null;
    final last = _boot;
    _boot = (peer: key, count: count);
    final shown = state.gatewayReboot;
    if (last != null && last.peer == key && count > last.count) {
      final reboot = GatewayReboot(
        // Not acknowledged yet: one notice counts every restart since.
        from: shown != null && shown.to == last.count ? shown.from : last.count,
        to: count,
        reason: reason,
      );
      state = state.copy(gatewayReboot: reboot, error: state.error);
      // Round 24: found after the failure it caused was reported (e.g. the
      // link drop, seen only on reconnect): re-classified GW_REBOOTED. A
      // failure being classified right now gets GW_REBOOTED by itself
      // (§3.1 rule 1).
      if (!_classifyingFailure) {
        _field.onGatewayReboot(to: count, text: gatewayRebootText(reboot));
      }
      return true;
    }
    // get_config told of the restart; get_net_status right after says why.
    if (shown != null &&
        shown.to == count &&
        shown.reason == null &&
        reason != null) {
      state = state.copy(
        gatewayReboot: shown.withReason(reason),
        error: state.error,
      );
    }
    return false;
  }

  /// Before a command that restarts the gateway on purpose
  /// (set_site_identity, set_mqtt_target, reconnect_ble): the next read
  /// starts a new baseline instead of reporting that restart.
  void _expectReboot() => _boot = null;

  /// 「知道了」 on the restart notice.
  void dismissGatewayReboot() {
    if (state.gatewayReboot == null) return;
    state = state.copy(gatewayReboot: null, error: state.error);
  }

  /// Right after a reconnect that reads nothing else from the gateway
  /// (step 8 resume): get_net_status, to see whether it restarted. A dropped
  /// link goes to the caller's reconnect; anything else skips the check.
  Future<void> _checkBoot(int generation) async {
    if (_boot == null || !state.netCheckSupported) return;
    try {
      _absorbNet(await _command(generation, 'get_net_status'));
    } catch (error) {
      if (error is GatewayFailure && error.code == 'cancelled') rethrow;
      if (isLinkDrop(error)) rethrow;
      _check(generation);
    }
  }

  /// A command timed out: did the gateway restart meanwhile? One bounded
  /// get_net_status on the link as it is (a dead link just gives no answer;
  /// the reconnect later compares again).
  Future<bool> _rebootedAfterTimeout() async {
    if (_boot == null || state.peer == null || !state.netCheckSupported) {
      return false;
    }
    try {
      final net = await _rawCommand(
        'get_net_status',
      ).timeout(const Duration(seconds: 6));
      return ref.mounted && _absorbNet(net);
    } catch (_) {
      return false;
    }
  }

  /// Install report text (set on step 7); empty before the first pass.
  String _reportBody = '';
  String _report() => '$_reportBody\n${reportTargetText(state.config)}';

  /// Keeps the step-7 report's upload-target lines in sync after a switch.
  void _refreshReport() {
    if (state.step == 7 && _reportBody.isNotEmpty) {
      state = state.copy(report: _report(), error: state.error);
    }
  }

  /// Runs a gateway-side task that must not replace the step's guidance
  /// text, whether it succeeds or fails (a cancel sets its own message).
  Future<void> _sideTask(
    String label,
    int timeout,
    Future<void> Function(int) action,
  ) async {
    final resume = state.message;
    await _run(label, timeout, action);
    if (!ref.mounted) return;
    if (state.message == label) {
      state = state.copy(message: resume, error: state.error);
    }
    _refreshReport();
  }

  String get _uploadText => state.config['mqtt_connected'] == true
      ? 'Gateway 已開始上傳資料。'
      : 'Gateway 正在連線，APP 會自動確認（最多約 2 分鐘）。';

  /// Re-reads the running upload target and upload state.
  Future<void> refreshUploadTarget() async {
    await _sideTask('重新讀取 Gateway 狀態', 20, (generation) async {
      final net = await _command(generation, 'get_net_status');
      _absorbTarget(net);
      _absorbNet(net);
      _stopWatch(UploadWatch.idle);
      final target = parseMqttTarget(state.config);
      state = state.copy(
        uploadNotice: target == null ? '' : '已重新讀取。$_uploadText',
      );
    });
    _watchUploadIfPending();
  }

  /// Sends `set_mqtt_target`; on a change the gateway reboots, so reconnect to
  /// the same gateway and confirm the running target by reading it back.
  ///
  /// [waitUpload]: after reading the target back, briefly wait for the
  /// upload to start. False when the Wi-Fi is changed next anyway (the
  /// upload cannot start before), so no time is spent waiting for it.
  Future<void> switchUploadTarget(
    MqttTarget wanted, {
    bool waitUpload = true,
  }) async {
    await _switchUploadTarget(wanted, waitUpload);
    _watchUploadIfPending();
  }

  Future<void> _switchUploadTarget(
    MqttTarget wanted,
    bool waitUpload,
  ) => _sideTask('正在把 Gateway 切到${wanted.plainLabel}（會重新開機，約 1 分鐘）', 120, (
    generation,
  ) async {
    final peer = state.peer;
    if (peer == null) throw const GatewayFailure('disconnected');
    if (!reportsMqttTarget(state.config)) {
      throw GatewayFailure(
        'target_unsupported',
        detail: state.config['fw_version']?.toString(),
      );
    }
    SetTargetAck? ack;
    _expectReboot();
    for (int attempt = 0; ; attempt++) {
      try {
        ack = parseSetTargetAck(
          await _command(generation, 'set_mqtt_target', wanted.params),
        );
      } on GatewayFailure catch (error) {
        if (error.fromGateway) throw GatewayFailure.uploadTarget(error.code);
        if (error.code == 'not_connected' && attempt == 0) {
          // The link had already dropped, so nothing reached the gateway:
          // reconnect, then send the command once more.
          await _relink(generation, peer);
          continue;
        }
        // ACK lost: the gateway may already be rebooting. Reconnect and
        // read back instead of guessing.
        if (error.code != 'disconnected' && error.code != 'timeout') rethrow;
      }
      break;
    }
    if (ack != null && !ack.changed) {
      final status = await _command(generation, 'get_net_status');
      _absorbTarget(status);
      _absorbNet(status);
      final now = parseMqttTarget(state.config) ?? ack.target;
      if (!now.sameAs(wanted)) {
        throw GatewayFailure.targetReadback(
          actual: now.plainLabel,
          wanted: wanted.plainLabel,
        );
      }
      _stopWatch(UploadWatch.idle);
      state = state.copy(
        uploadNotice:
            '不用切換：Gateway 本來就送到${now.plainLabel}（沒有重新開機）。$_uploadText',
      );
      return;
    }
    // Changed (or outcome unknown): the old MQTT state no longer applies.
    // The firmware commits the target to NVS before a changed:true ACK, so
    // the gateway boots with it even if the reconnect below fails; with no
    // ACK the running target is unknown until it is read back.
    final config = {...state.config}..remove('mqtt_connected');
    if (ack != null) {
      config.addAll(ack.target.fields);
    } else {
      config
        ..['mqtt_target'] = unconfirmedMqttTarget
        ..remove('mqtt_host')
        ..remove('mqtt_port');
    }
    state = state.copy(config: config, net: const {}, uploadNotice: '');
    await _reconnectAfterReboot(generation, peer, ack?.rebootInMs ?? 1500);
    // Rebooted: the Wi-Fi is joined again from scratch.
    _startWifiGrace();
    final confirmed = await _readBackTarget(generation, wanted, waitUpload);
    state = state.copy(
      uploadNotice:
          '已把 Gateway 切到${confirmed.plainLabel}，Gateway 已重新開機並重新連上。'
          '${waitUpload ? _uploadText : '接著設定 Wi-Fi。'}',
    );
  });

  /// Reconnects a link that dropped while idle (no reboot involved). Times
  /// out above the link's own worst-case retry budget (51s, see
  /// ble_gateway_link.dart); keep in sync with [reconnectBudget] above.
  /// Shows the link's connect stage as the busy text of [generation]'s run.
  void Function(String) _stageFor(int generation) => (stage) {
    // A late stage from an abandoned connect must not outlive the run.
    if (ref.mounted && generation == _generation && state.busy) {
      state = state.copy(message: stage, error: state.error);
    }
  };

  Future<void> _relink(
    int generation,
    GatewayPeer peer, {
    Future<void> Function()? after,
  }) async {
    await _link.disconnect();
    _check(generation);
    await _persistentLink(generation, peer, () async {
      await _command(generation, 'ping');
      if (after != null) await after();
    });
  }

  /// Failure types of the latest [_persistentLink] run (for 詳細資訊).
  (int, List<String>)? _connectLog;

  /// Round 10: connects (the link's own retries included) and runs [after];
  /// a retryable failure (133 / unknownError / disconnected / timeout) is
  /// retried — disconnect, [connectRetryGap], short rescan inside the link —
  /// until [connectPersistence] has passed, showing 「連線中（第 n 次）」.
  Future<void> _persistentLink(
    int generation,
    GatewayPeer peer,
    Future<void> Function() after,
  ) async {
    final watch = Stopwatch()..start();
    final failures = <String>[];
    _connectLog = (generation, failures);
    for (int attempt = 1; ; attempt++) {
      _check(generation);
      final stage = _stageFor(generation);
      if (attempt > 1) stage(connectingAttemptText(attempt));
      try {
        final remaining = connectPersistence - watch.elapsed;
        await _link
            .connect(
              peer,
              onStage: attempt == 1
                  ? stage
                  : (text) => stage('${connectingAttemptText(attempt)}：$text'),
            )
            .timeout(
              remaining > const Duration(seconds: 5)
                  ? remaining
                  : const Duration(seconds: 5),
            );
        _check(generation);
        await after();
        return;
      } catch (error) {
        if (error is GatewayFailure && error.code == 'cancelled') rethrow;
        _check(generation);
        failures.add('第 $attempt 次：${connectFailureType(error)}');
        if (state.relinkStage != RelinkStage.reconnecting) {
          state = state.copy(
            relinkStage: RelinkStage.reconnecting,
            error: state.error,
          );
        }
        final retry =
            isRetryableConnect(error) &&
            watch.elapsed + connectRetryGap < connectPersistence;
        if (!retry) {
          if (error is TimeoutException) {
            await _link.disconnect();
            throw const GatewayFailure('disconnected');
          }
          rethrow;
        }
        await _link.disconnect();
        _check(generation);
        await Future<void>.delayed(connectRetryGap);
      }
    }
  }

  Future<void> _reconnectAfterReboot(
    int generation,
    GatewayPeer peer,
    int rebootMs,
  ) async {
    await _link.disconnect();
    _check(generation);
    // The firmware restarts rebootMs after the ACK; advertising resumes a
    // couple of seconds later.
    await _wait(((rebootMs + 2500) / 1000).ceil(), generation);
    final deadline = Stopwatch()..start();
    for (int attempt = 0; ; attempt++) {
      try {
        final remaining = _reconnectBudget - deadline.elapsed;
        await _link
            .connect(peer)
            .timeout(
              remaining > const Duration(seconds: 5)
                  ? remaining
                  : const Duration(seconds: 5),
            );
        _check(generation);
        await _command(generation, 'ping');
        return;
      } on TimeoutException {
        await _link.disconnect();
      } catch (_) {
        // Retried below; cancellation is detected by _check.
      }
      _check(generation);
      if (attempt >= 14 || deadline.elapsed >= _reconnectBudget) {
        throw const GatewayFailure('target_reconnect');
      }
      await _wait(3, generation);
    }
  }

  /// Reads the running target after a reboot. get_net_status is refused with
  /// not_ready until boot finishes; get_config already reports the target, so
  /// it is used meanwhile. Polls briefly for mqtt_connected unless
  /// [waitUpload] is false.
  Future<MqttTarget> _readBackTarget(
    int generation,
    MqttTarget wanted,
    bool waitUpload,
  ) async {
    const transient = ['not_ready', 'busy', 'timeout'];
    MqttTarget? seen;
    for (int attempt = 0; attempt < 10; attempt++) {
      if (attempt > 0) await _wait(3, generation);
      Map<String, dynamic> status;
      bool fromNet = true;
      try {
        status = await _command(generation, 'get_net_status');
      } on GatewayFailure catch (error) {
        if (!transient.contains(error.code)) rethrow;
        try {
          status = await _command(generation, 'get_config');
          fromNet = false;
        } on GatewayFailure catch (error) {
          if (!transient.contains(error.code)) rethrow;
          continue;
        }
      }
      _absorbTarget(status);
      if (fromNet) _absorbNet(status);
      final target = parseMqttTarget(status);
      if (target == null || !target.sameAs(wanted)) {
        throw GatewayFailure.targetReadback(
          actual: target?.plainLabel ?? '（未回報）',
          wanted: wanted.plainLabel,
        );
      }
      seen = target;
      _stopWatch(UploadWatch.idle);
      if (!waitUpload || status['mqtt_connected'] == true) break;
    }
    if (seen == null) {
      throw GatewayFailure.targetReadback(
        actual: '（無法讀取）',
        wanted: wanted.plainLabel,
      );
    }
    return seen;
  }

  void _markRssiStale() {
    if (!ref.mounted || state.ptus.isEmpty) return;
    state = state.copy(
      ptus: [
        for (final ptu in state.ptus) {...ptu, 'rssi_stale': true},
      ],
      error: state.error,
    );
  }

  void setAutoRssi(bool value) {
    state = state.copy(autoRssi: value, error: state.error);
    if (!value) _markRssiStale();
  }

  /// 「依訊號重新排序」: the only place besides a fresh scan where the PTU
  /// list order changes; periodic RSSI refreshes keep the order.
  void sortPtusBySignal() {
    if (!ref.mounted || state.busy || state.ptus.length < 2) return;
    state = state.copy(
      ptus: List.of(state.ptus)..sort(comparePtuForSelection),
      error: state.error,
    );
  }

  Future<void> refreshPtuRssi() async {
    if (!ref.mounted ||
        !state.autoRssi ||
        !_foreground ||
        state.step != 4 ||
        state.peer == null ||
        (state.ptus.isEmpty && !directFlow) ||
        state.busy ||
        _pollInFlight ||
        _rssiInFlight ||
        state.uploadWatch == UploadWatch.linkLost) {
      return;
    }
    if (directFlow) return _refreshDirect();
    _rssiInFlight = true;
    final generation = _generation;
    try {
      _lastLinkTraffic = DateTime.now();
      final result = await _link.command('get_ble_devices');
      if (!ref.mounted ||
          generation != _generation ||
          state.busy ||
          !_foreground ||
          !state.autoRssi ||
          state.step != 4) {
        return;
      }
      final rows = result['devices'];
      if (rows is! List) {
        _markRssiStale();
        return;
      }
      await _absorbDirect(generation);
      if (!ref.mounted || generation != _generation || state.busy) return;
      final ptus = refreshPtuSignals(state.ptus, rows);
      // Round 7b: a PTU that the gateway reconnects after the scan (e.g. one
      // it had already taken) must still be preselected, unless the user
      // already edited the selection.
      state = state.copy(
        ptus: ptus,
        selected: _selectionTouched
            ? state.selected
            : _promoteConnected(ptus, state.selected, targetPtuCount),
        error: state.error,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _markRssiStale();
      if (error is GatewayFailure &&
          (error.code == 'disconnected' ||
              error.code == 'not_connected' ||
              error.code == 'phone_link_lost')) {
        _stepSevenLinkLost(error);
      }
    } finally {
      _rssiInFlight = false;
    }
  }

  /// Round 15 direct flow at step 7: follow the gateway's own pick (and its
  /// RSSI) with get_status alone — a new pick (e.g. after a threshold
  /// change, or the PTU dropped) replaces the one shown.
  Future<void> _refreshDirect() async {
    _rssiInFlight = true;
    final generation = _generation;
    try {
      _lastLinkTraffic = DateTime.now();
      final status = await _link.command('get_status');
      if (!ref.mounted ||
          generation != _generation ||
          state.busy ||
          state.step != 4) {
        return;
      }
      _takeDirect(status['direct']);
      _syncDirectPick();
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      if (error is GatewayFailure &&
          (error.code == 'disconnected' ||
              error.code == 'not_connected' ||
              error.code == 'phone_link_lost')) {
        _stepSevenLinkLost(error);
      }
    } finally {
      _rssiInFlight = false;
    }
  }

  /// Last command traffic on the phone↔gateway link at step 7 (RSSI poll
  /// or keep-alive ping).
  DateTime _lastLinkTraffic = DateTime.now();

  /// Step 7 keep-alive: when the RSSI poll is off (or has nothing to poll),
  /// a light ping every [keepAliveInterval] keeps the link in use and
  /// notices a drop early (with the banner's reconnect action).
  Future<void> keepAlive({DateTime? now}) async {
    final at = now ?? DateTime.now();
    if (!ref.mounted ||
        !_foreground ||
        state.step != 4 ||
        state.peer == null ||
        state.busy ||
        _pollInFlight ||
        _rssiInFlight ||
        state.uploadWatch == UploadWatch.linkLost ||
        at.difference(_lastLinkTraffic) < keepAliveInterval) {
      return;
    }
    _rssiInFlight = true;
    _lastLinkTraffic = at;
    final generation = _generation;
    try {
      await _link.command('ping');
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      if (error is GatewayFailure &&
          (error.code == 'disconnected' ||
              error.code == 'not_connected' ||
              error.code == 'phone_link_lost')) {
        _stepSevenLinkLost(error);
      }
    } finally {
      _rssiInFlight = false;
    }
  }

  /// Step 7 link drop seen by a background poll: banner, then (round 12)
  /// the same automatic persistent reconnect + rescan as a drop mid-scan.
  void _stepSevenLinkLost(GatewayFailure error) {
    _stopWatch(UploadWatch.linkLost);
    state = state.copy(
      error: error.message,
      errorDetail: error.toString(),
      scanResumePending: state.step == 4 ? true : null,
    );
    _field.onFailure(error, ctlStep: state.step);
    if (state.step == 4) {
      final keep = Set.of(state.selected);
      unawaited(_autoRelink(4, keep: keep.isEmpty ? null : keep));
    }
  }

  bool _autoRelinking = false;

  /// Generation of the step 8 run that last ended in a phone link loss.
  int? _step8LossGeneration;

  /// A step 8 action ([configurePtus], [resumeAssign], [retryFailedAssign],
  /// [finishConfigured]); round 13: a phone↔gateway link loss that ends it
  /// starts the automatic reconnect at once (no tap, like step 7).
  Future<void> _step8Run(
    String label,
    int timeout,
    Future<void> Function(int) action,
  ) async {
    await _run(label, timeout, action, relinkStep: 5);
    // Round 23: the run is over (a run refused because another one is busy
    // leaves that one's flag alone).
    if (ref.mounted && state.assignRunning && !state.busy) {
      state = state.copy(assignRunning: false, error: state.error);
    }
    _settleAssign();
    if (!ref.mounted || _autoRelinking) return;
    if (_linkLostAt(5)) {
      await _autoRelink(5);
    } else if (state.relinking) {
      state = state.copy(relinking: false, error: state.error);
    }
  }

  /// The phone↔gateway link is lost at [step] (4 = step 7, 5 = step 8) and
  /// the automatic reconnect may (still) run: nothing running, not given up
  /// ('reconnect_failed'), and — step 8 — lost by the current run, not
  /// stopped by 「取消操作」 or waiting for the monitor confirmation.
  ///
  /// [running]: asked from inside the run that just failed (still busy).
  bool _linkLostAt(int step, {bool running = false}) {
    if (!ref.mounted || state.reconnectFailed) return false;
    if (state.busy && !running) return false;
    if (step == 4) return _step7Lost(state) && state.error != null;
    return state.step == 5 &&
        state.resumePending &&
        !state.monitorUnconfirmed &&
        _step8LossGeneration == _generation;
  }

  /// Round 12 (step 7) / round 13 (step 8): one automatic reconnect after a
  /// phone↔gateway link loss, shared by both steps. Keeps reconnecting for
  /// [connectPersistence] ([_persistentLink]); step 7 then rescans
  /// ([discover]), step 8 reconciles with the gateway and assigns the rest
  /// ([resumeAssign]). While it runs [CommissionState.relinking] keeps the
  /// button a disabled 「重新連線中…」. At step 8 a new loss after a round
  /// that assigned more PTUs starts another round (at most
  /// [autoRelinkRounds]); once the reconnect gives up (or the loss recurs
  /// without progress) the banner offers the manual 「重新連線並掃描 PTU」
  /// / 「重新連線並繼續」.
  Future<void> _autoRelink(int step, {Set<String>? keep}) async {
    if (_autoRelinking ||
        autoRelinkRounds <= 0 ||
        !ref.mounted ||
        state.step != step ||
        state.busy) {
      return;
    }
    _autoRelinking = true;
    state = state.copy(
      relinking: true,
      relinkStage: RelinkStage.reconnecting,
      error: state.error,
    );
    try {
      if (step == 4) {
        await _autoRelinkStep7(keep);
      } else {
        for (var round = 0; round < autoRelinkRounds; round++) {
          final done = state.assignedOk.length;
          await resumeAssign();
          // A loss that recurs without progress is not chased.
          if (!_linkLostAt(step) || state.assignedOk.length <= done) break;
        }
      }
    } finally {
      _autoRelinking = false;
      if (ref.mounted) {
        state = state.copy(relinking: false, error: state.error);
      }
    }
  }

  /// Round 15 (step 7): the first automatic reconnect runs at once. A loss
  /// that recurs — during that rescan, or idle within [step7StableAfter] of
  /// the last automatic reconnect (round 14: two drops 11 s apart ended in
  /// a tap) — is retried after each [step7RetryGaps] gap (5 / 10 / 20 s);
  /// only then does the banner wait for 「重新連線並繼續」. A reconnect that
  /// gave up ('reconnect_failed') is not retried.
  Future<void> _autoRelinkStep7(Set<String>? keep) async {
    final last = _step7RelinkedAt;
    final spell =
        last != null && DateTime.now().difference(last) < step7StableAfter;
    if (!spell) _step7Retries = 0;
    var wait = spell;
    while (true) {
      if (wait) {
        if (_step7Retries >= step7RetryGaps.length) return;
        final gap = step7RetryGaps[_step7Retries++];
        state = state.copy(
          message: step7RetryText(_step7Retries, step7RetryGaps.length, gap),
          error: state.error,
        );
        await Future<void>.delayed(gap);
        if (!ref.mounted || state.step != 4 || !_linkLostAt(4)) return;
      }
      wait = true;
      await discover(keep: keep);
      if (!ref.mounted) return;
      if (!_linkLostAt(4)) {
        if (state.error == null) _step7RelinkedAt = DateTime.now();
        return;
      }
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    _field.setForeground(value);
    if (!value) _markRssiStale();
  }

  Future<void> refreshHealth() async {
    if (!_foreground || _healthBusy || state.busy || !_loggedIn) return;
    _healthBusy = true;
    final loginBase = _loginBase;
    // A switch of backend while the request runs makes its answer stale.
    bool stale() => !_loggedIn || _loginBase != loginBase;
    try {
      final latest = await _withRelogin(
        () => _api.request(
          'GET',
          '/api/latest?site_id=$site&gateway_id=$gateway',
        ),
      );
      if (stale()) return;
      final rows = (latest['items'] as List? ?? []).cast<Map>();
      if (ref.mounted && backendRowsFresh(rows)) {
        state = state.copy(backendSeenAt: DateTime.now());
      }
      final expected = state.ptus.map((p) => p['device_number']).toSet();
      final complete =
          expected.isNotEmpty &&
          expected.every((id) => rows.any((r) => r['device_id'] == id));
      final fresh =
          complete &&
          rows.every((r) => ((r['lag_seconds'] as num?) ?? 999) < 30);
      final abnormal =
          !complete ||
          rows.any(
            (r) =>
                r['online'] != true ||
                ((r['error_num'] as num?) ?? 0) > 0 ||
                ((r['lag_seconds'] as num?) ?? 999) > 300,
          );
      // The first answer right after verification may still lag behind:
      // report 資料有異常 only when it is seen twice in a row.
      _abnormalStreak = abnormal ? _abnormalStreak + 1 : 0;
      if (ref.mounted) {
        state = state.copy(
          online: fresh,
          message: abnormal && _abnormalStreak < 2
              ? healthPendingText
              : abnormal
              ? '資料有異常，請檢查 PTU 與網路。'
              : fresh
              ? '資料持續更新'
              : '資料暫未更新',
        );
      }
    } catch (_) {
      if (ref.mounted && !stale()) {
        state = state.copy(online: false, message: '無法確認最新資料，請檢查網路');
      }
    } finally {
      _healthBusy = false;
    }
  }

  /// [base] / [password] log in first when the backend was switched since
  /// the last login (step 7 offers the password field for that).
  Future<void> repair({String? base, String? password}) => _run('重新連接閘道器', 60, (
    generation,
  ) async {
    final secret = base == null ? '' : _passwordFor(base, password);
    if (!_loggedIn && base != null && secret.isNotEmpty) {
      _backend = describeBackend(Uri.tryParse(base.trim()));
      await _api.login(base.trim(), secret);
      _check(generation);
      _loginOk(base, secret);
    }
    // After an environment switch the old login must not reach the new
    // site.
    if (!_loggedIn) throw const GatewayFailure('authentication');
    _expectReboot();
    await _request(generation, 'POST', '$_path/commands', {
      'op': 'reconnect_ble',
      'params': {'target_mac': state.config['gateway_uid']},
      'ttl': 30,
    });
    state = state.copy(step: 3, verified: false, message: '已要求重新連線，請重新確認上線與資料');
  });

  /// 「取消操作」 during step 8: stop the run but keep assignedOk and the
  /// selection; the page then offers 「重新連線並繼續（剩 N 台）」.
  Future<void> stopStep8() async {
    if (state.step != 5) return cancel();
    _generation++;
    _stopWatch(UploadWatch.idle);
    final safe = await _safeStop();
    if (!ref.mounted) return;
    state = state.copy(
      resumePending: true,
      error: safe ? null : '尚未確認 Gateway 已恢復監控，請按「重新連線並繼續」核對。',
      message: '已停止。已完成的 ${state.assignedOk.length} 台保留，可按「重新連線並繼續」接續。',
    );
    await _save();
  }

  /// Step 9 「返回選擇 PTU」 / 「取消操作」: back to step 7 keeping the
  /// selection and assignedOk (round 8: a cancel here dropped to step 2).
  /// Stops a running verification but never disconnects the gateway.
  Future<void> backToSelection() async {
    if (state.step != 6) return;
    final wasBusy = state.busy;
    _generation++;
    _clock?.cancel();
    _health?.cancel();
    _verifyCarry = null;
    state = state.copy(
      step: 4,
      busy: false,
      seconds: 0,
      verified: false,
      verifyBackendDown: false,
      report: '',
      verifyCounts: const {},
      verifyWaiting: const {},
      verifySkipped: const {},
      message: wasBusy ? '已停止驗證，可調整勾選後重新配置。' : '',
    );
    if (_lease) {
      try {
        await _api.request('PATCH', '$_path/bot-monitor', {'enabled': true});
        _lease = false;
      } catch (_) {}
    }
    // Round 9: the gateway may have connected more PTUs meanwhile (a 5th
    // missing until a manual rescan): rescan once, keeping the selection
    // and assignedOk.
    if (ref.mounted && state.step == 4) {
      await discover(keep: Set.of(state.selected));
    }
  }

  /// Banner 「重新連線」 outside steps 7/8: re-open the BLE link and read
  /// fresh network status, keeping the current step.
  Future<void> reconnectLink() => _sideTask('重新連線閘道器', 70, (generation) async {
    await _reconnect(generation);
    final net = await _command(
      generation,
      state.netCheckSupported ? 'get_net_status' : 'get_status',
    );
    _absorbTarget(net);
    _absorbNet(net);
    state = state.copy(reconnectFailed: false);
  });

  Future<void> cancel() async {
    _generation++;
    _health?.cancel();
    _verifyCarry = null;
    _grace?.cancel();
    _stopWatch(UploadWatch.idle);
    final safe = await _safeStop();
    // Round 15b: before the link goes, undo a temporary 「不是這台？」
    // binding (round 16b: back to the binding from before); a failure only
    // notes it (asked again at the next step 7).
    final tempBound = state.tempBoundMac;
    final restore = state.tempRestoreMac;
    final unbindFailure = await _releaseTempBind();
    await _link.disconnect();
    if (_lease) {
      try {
        await _api.request('PATCH', '$_path/bot-monitor', {'enabled': true});
        _lease = false;
      } catch (_) {}
    }
    if (ref.mounted) {
      state = state.copy(
        step: 1,
        net: const {},
        checkPassed: false,
        wifiGraceOver: false,
        identifiedMac: null,
        tempBoundMac: null,
        tempRestoreMac: null,
        strayBindMac: null,
        directNotice: '',
        error: !safe
            ? '尚未確認 Gateway 已恢復監控，請重新連線核對。'
            : unbindFailure != null
            ? directUnbindFailedText(tempBound, restore)
            : null,
        errorDetail: unbindFailure == null
            ? null
            : restore == null
            ? '暫時綁定 $tempBound 未能解除：$unbindFailure'
            : '暫時綁定 $tempBound 未能還原成 $restore：$unbindFailure',
        message: '已取消。請重新連線核對進度；未成功恢復的監控會話最晚於到期時恢復。',
      );
      if (!safe) {
        _field.noteErrorCode(RescueCode.monitorUnconfirmed);
      } else if (unbindFailure != null) {
        _field.noteErrorCode(RescueCode.directPick);
      }
      // Field rescue: 「結束並重新選擇閘道器」 ends this session.
      _field.end('abandoned');
    }
  }

  // ---- Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §5) ----

  /// 「打電話給後台前按這裡」 / 「找後台幫忙」: a help report and package
  /// (the session is created if there is none yet); the sheet follows
  /// [fieldHelpProvider]. Never throws, never changes the commissioning.
  Future<void> requestHelp() async {
    try {
      await _field.requestHelp();
    } catch (_) {}
  }

  /// 〔重新傳送〕 on the help sheet.
  Future<void> resendHelp() async {
    try {
      await _field.resendHelp();
    } catch (_) {}
  }

  /// Uploads are on (not the demo gateway): the help buttons are shown.
  bool get fieldHelpAvailable => _field.enabled;

  FieldInput? _fieldInput() {
    if (!ref.mounted) return null;
    final topology = ref.read(topologyProvider);
    return FieldInput(
      state: state,
      env: ref.read(backendEnvProvider),
      directMode: topology.topology.isDirect,
      targetCount: topology.targetCount,
      loggedIn: _loggedIn,
    );
  }

  /// Diagnostics blocks from what was already read (no new command).
  Map<String, dynamic> _fieldSections() {
    final link = _link;
    return diagnosticSections(
      state,
      now: DateTime.now(),
      connectLog: _connectLog?.$2 ?? const [],
      firstConnectFailure: link is ConnectDiagnostics
          ? (link as ConnectDiagnostics).firstConnectFailure
          : null,
      signalConnected: link is GatewaySignalSource
          ? (link as GatewaySignalSource).signalConnected
          : null,
      netReadAt: _netReadAt,
    );
  }

  /// Why the gateway cannot be used yet (「沿用目前站點」 / upload gate).
  RescueCode _notReadyCode() => state.wifi == WifiVerdict.ok
      ? RescueCode.uploadNotStarted
      : wifiRescueCode(wifiDiscReasonOf(state.net));

  /// A BLE command outside [_commandBusy] (safe stop, restart check,
  /// temporary binding), journaled the same way.
  Future<Map<String, dynamic>> _rawCommand(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    final watch = Stopwatch()..start();
    try {
      final result = await _link.command(op, params);
      _journalBle(op, params, 'ok', watch, result: result);
      return result;
    } catch (error) {
      _journalBle(op, params, _journalStatus(error), watch, error: error);
      rethrow;
    }
  }

  static String _journalStatus(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is! GatewayFailure) return 'error';
    if (error.code == 'timeout') return 'timeout';
    if (error.code == 'busy') return 'busy';
    return error.fromGateway ? 'fail' : 'error';
  }

  void _journalBle(
    String op,
    Map<String, dynamic> params,
    String status,
    Stopwatch watch, {
    Object? result,
    Object? error,
  }) {
    try {
      _field.journal.ble(
        op,
        params,
        status: status,
        durMs: watch.elapsedMilliseconds,
        result:
            result ??
            (error is GatewayFailure && error.fromGateway
                ? error.detail
                : null),
        error: error is GatewayFailure
            ? (error.fromGateway ? error.code : error.toString())
            : error?.toString(),
      );
    } catch (_) {}
  }

  void _journalHttp(
    String method,
    String path,
    Stopwatch watch, {
    Object? error,
  }) {
    try {
      final failure = error is GatewayFailure ? error : null;
      final String status;
      if (error == null) {
        status = 'ok';
      } else if (failure == null) {
        status = error is TimeoutException ? 'timeout' : 'error';
      } else if (failure.code == 'network') {
        status = failure.detail == '逾時' ? 'timeout' : 'error';
      } else if (const {
        'api',
        'authentication',
        'conflict',
      }.contains(failure.code)) {
        status = 'fail';
      } else {
        status = 'error';
      }
      _field.journal.http(
        method,
        path,
        status: status,
        durMs: watch.elapsedMilliseconds,
        httpStatus: error == null
            ? 200
            : failure?.code == 'authentication'
            ? 401
            : failure?.code == 'conflict'
            ? 409
            : failure?.status,
        error: failure == null
            ? error?.toString()
            : '${failure.code}${failure.detail == null ? '' : ' ${failure.detail}'}',
      );
    } catch (_) {}
  }
}
