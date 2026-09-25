import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gateway_net.dart';
import '../core/gateway_topology.dart';
import '../core/ptu_rssi.dart';
import '../core/mqtt_target.dart';
import '../core/protocol.dart';
import '../data/ble_gateway_link.dart';
import '../data/contracts.dart';
import '../data/recent_gateways.dart';
import '../data/dashboard_api.dart';
import '../data/demo_system.dart';
import '../data/ptu_inventory.dart';
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

const gatewayNetKeys = ['wifi_state', 'ip', 'ssid', 'rssi', 'uptime_sec'];

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
  if (text.contains('133') ||
      text.contains('connect') ||
      text.contains('discovery') ||
      text.contains('gatt')) {
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

/// PTU tile text when step 8 stopped because the phone lost the gateway.
const notAssignedLinkText = '尚未指派（手機與閘道器斷線）';

/// Appends the link's first connect failure type (round 8 analysis aid).
String withFirstFailure(String detail, Object link) {
  final first = link is ConnectDiagnostics ? link.firstConnectFailure : null;
  return first == null ? detail : '$detail\n第一次連線失敗：$first';
}

/// Shown while the phone re-opens the BLE link to the gateway.
const reconnectingText = '正在重新連線閘道器';

/// Overall budget for re-opening the phone↔gateway link. Must stay above
/// [BleGatewayLink]'s own worst-case retry budget (51s, see
/// ble_gateway_link.dart) plus headroom for _relink's own overhead; keep it
/// in sync with _reconnectBudget below.
const reconnectBudget = Duration(seconds: 66);

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
  // Phone link lost: the button reconnects first (same as the banner).
  if (s.resumePending) {
    return rest == 0 ? '重新連線並繼續' : '重新連線並繼續（剩 $rest 台）';
  }
  if (rest == 0) return '全部已配置';
  return '配置 $rest 台並開始監控';
}

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
}) {
  final where = _savedStepLabels[step];
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
/// timestamp adds one (max 3); an offline, late or erroring row resets that
/// PTU only; an unchanged timestamp keeps its count. [lastNew] records the
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
    if (found.isEmpty) {
      counts[id] = 0;
      continue;
    }
    final row = found.first;
    final stamp = DateTime.tryParse(row['ts']?.toString() ?? '');
    if (row['online'] != true ||
        ((row['lag_seconds'] as num?) ?? 999) >= 60 ||
        row['error_num'] != 0 ||
        stamp == null) {
      if (stamp != null) previous[id] = stamp;
      counts[id] = 0;
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
    this.monitorUnconfirmed = false,
    this.scanResumePending = false,
    this.reconnectFailed = false,
    this.savedResume = false,
    this.lastCompleted = false,
    this.verifyCounts = const {},
    this.verifyWaiting = const {},
    this.verifySkipped = const {},
  });

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

  /// Resume at step 8: the gateway did not confirm monitoring within 30 s;
  /// the page offers 「重試」 (resumeAssign) and 「略過」 (skipMonitorConfirm).
  final bool monitorUnconfirmed;

  /// 星狀自動重置殘留編號時手機↔閘道器斷線；「重新連線並繼續」會重連並重掃。
  final bool scanResumePending;

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
    bool? monitorUnconfirmed,
    bool? scanResumePending,
    bool? reconnectFailed,
    bool? savedResume,
    bool? lastCompleted,
    Map<int, int>? verifyCounts,
    Set<int>? verifyWaiting,
    Set<int>? verifySkipped,
  }) => CommissionState(
    lastCompleted: lastCompleted ?? this.lastCompleted,
    verifyCounts: verifyCounts ?? this.verifyCounts,
    verifyWaiting: verifyWaiting ?? this.verifyWaiting,
    verifySkipped: verifySkipped ?? this.verifySkipped,
    unassigned: unassigned ?? this.unassigned,
    assignedOk: assignedOk ?? this.assignedOk,
    resumePending: resumePending ?? this.resumePending,
    monitorUnconfirmed: monitorUnconfirmed ?? this.monitorUnconfirmed,
    scanResumePending: scanResumePending ?? this.scanResumePending,
    reconnectFailed: reconnectFailed ?? this.reconnectFailed,
    savedResume: savedResume ?? this.savedResume,
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
  Timer? _clock, _health;
  int _generation = 0;
  // Topology changed while a step was running; applied when it ends.
  bool _topologyDeferred = false;
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

  @override
  CommissionState build() {
    _link = ref.watch(linkProvider);
    _api = ref.watch(apiProvider);
    _timing = ref.read(uploadWatchTimingProvider);
    // 切換拓撲（直連／星狀）或改星狀台數：先依新拓撲重算 pendingNext 與 selected
    // （沿用既有 ptus 清單，套用跟 _discover 相同的範圍過濾／預選邏輯，不重
    // 掃），再把已勾選裁到新的目標台數，只保留 RSSI 最強的前 N 台；顯示的
    // 「已選 x/y」跟著 topologyProvider 動態重繪。
    ref.listen(topologyProvider, (previous, next) {
      if (previous?.targetCount != next.targetCount ||
          previous?.topology != next.topology) {
        // 自動收編（重置迴圈＋重掃）進行中不在中途重算：延後到該步驟結束再套用。
        if (state.busy) {
          _topologyDeferred = true;
        } else {
          _onTopologyChanged(next);
        }
      }
    });
    ref.onDispose(() {
      _generation++;
      _clock?.cancel();
      _health?.cancel();
      _poll?.cancel();
      _grace?.cancel();
      _rssiTimer?.cancel();
      unawaited(_link.disconnect());
    });
    return const CommissionState();
  }

  /// 拓撲（直連／星狀）或目標台數變動時：先用既有 ptus 清單，套用跟
  /// [_discover] 相同的範圍過濾（星狀模式下範圍外 PTU 不能選）重算
  /// pendingNext，並把已勾選中變成範圍外的部分丟掉；再裁到新的目標台數。
  void _onTopologyChanged(TopologySettingsState next) {
    if (!ref.mounted) return;
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
  ]) async {
    _check(generation);
    if (sensitiveOps.contains(op) && state.config['otp_enabled'] == true) {
      throw const GatewayFailure('otp_enabled');
    }
    final result = await _link.command(op, params);
    _check(generation);
    return result;
  }

  Future<Map<String, dynamic>> _request(
    int generation,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    _check(generation);
    final result = await _api.request(method, path, body);
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
        await _link.command('set_ble_enabled', {'enabled': true});
        await _link.command('set_data_upload', {'enabled': true});
        final config = await _link.command('get_config');
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

  Future<void> _run(
    String label,
    int timeout,
    Future<void> Function(int) action,
  ) async {
    if (state.busy) return;
    final generation = ++_generation;
    _diagnosis = null;
    state = state.copy(
      busy: true,
      message: label,
      seconds: timeout,
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
        state = state.copy(resumePending: true);
        unawaited(_save());
        if (!(error is GatewayFailure &&
            (error.code == 'phone_link_lost' ||
                error.code == 'reconnect_failed'))) {
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
      if (ref.mounted) {
        final linkIssue =
            failure.code == 'phone_link_lost' ||
            failure.code == 'reconnect_failed' ||
            failure.code == 'monitor_unconfirmed';
        state = state.copy(
          errorDetail: failure.toString(),
          reconnectFailed: failure.code == 'reconnect_failed',
          error: linkIssue
              ? failure.message
              : !safe
              ? '尚未確認 Gateway 已恢復監控，請重新連線核對設定。'
              : detailed
              ? '資料驗證未通過：\n${diagnosis.$2}'
              : failure.message,
        );
      }
    } finally {
      _clock?.cancel();
      if (ref.mounted) {
        state = state.copy(busy: false, seconds: 0, error: state.error);
        if (_topologyDeferred) {
          _topologyDeferred = false;
          _onTopologyChanged(ref.read(topologyProvider));
        }
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _link.demo ? 'demo_progress' : 'progress',
      jsonEncode({
        'step': state.step,
        'completed': state.step == 7 && state.verified,
        'count': state.ptus.length,
        'site': site,
        'gateway': gateway,
        'peer': state.peer?.id,
        'peer_name': state.peer?.name,
        'selected': state.selected.toList(),
        'done': _doneAssign,
        'inflight': _inflightAssign,
        'assignments': state.ptus
            .map((p) => {'mac': p['mac'], 'id': p['device_number']})
            .toList(),
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
        message: resumeText(
          step,
          done.values.toList(),
          pending,
          inflight: inflight.values.toList(),
        ),
      );
    }
  }

  /// 「重新開始」 after a finished run: forget the saved progress.
  Future<void> clearCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_link.demo ? 'demo_progress' : 'progress');
    _saved = null;
    if (ref.mounted) {
      state = state.copy(lastCompleted: false, savedResume: false, message: '');
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
      state = state.copy(
        error: error is GatewayFailure
            ? error.message
            : GatewayFailure.unexpected(error).message,
      );
      return;
    }
    await _connect(peer);
    if (!ref.mounted || state.error != null || state.step != 2) return;
    _saved = null;
    state = state.copy(
      step: 4,
      checkPassed: true,
      savedResume: false,
      config: {...state.config, 'choose_station': false},
      results: {},
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
    if (merged.every(done.contains)) return;
    await configurePtus(skip: done.intersection(merged));
  }

  Future<void> prepare(String base, String password, {bool offline = false}) =>
      _run('檢查藍牙與後端連線', 30, (generation) async {
        await _link.prepare();
        _check(generation);
        _backend = describeBackend(Uri.tryParse(base.trim()));
        if (!offline) {
          await _api.login(base, password);
          _check(generation);
          _setLoggedIn(true, base);
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
  Future<void> identify() => _run('辨識閘道器', 12, (generation) async {
    if (state.config['identify_supported'] != true) {
      throw const GatewayFailure('identify_unsupported');
    }
    await _command(generation, 'identify');
    state = state.copy(message: '請找出雙閃藍燈的閘道器，6 秒後會恢復原本燈號。');
  });

  Future<void> connect(GatewayPeer peer) async {
    if (state.busy) return;
    _stopWatch(UploadWatch.idle);
    state = state.copy(
      net: const {},
      checkPassed: false,
      uploadLate: false,
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
    } catch (_) {
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
    await _link.connect(peer, onStage: _stageFor(generation));
    _check(generation);
    state = state.copy(message: '藍牙已連線，正在確認閘道器回應與設定…');
    for (int attempt = 0; ; attempt++) {
      try {
        await _command(generation, 'ping');
        break;
      } catch (_) {
        if (attempt == 4) rethrow;
        await _wait(3, generation);
      }
    }
    final config = await _command(generation, 'get_config');
    _check(generation);
    try {
      await RecentGateways.remember(_link.demo, peer, config['gateway_uid']);
    } catch (_) {
      /* Recents must not block a successful BLE connection. */
    }
    _check(generation);
    // 網路體檢: the gateway's own Wi-Fi and upload state.
    final net = await _readNet(generation, config);
    if (config['fleet_joined'] == true) {
      final existing = await _command(generation, 'get_ble_devices');
      final devices = (existing['devices'] as List? ?? [])
          .map((d) => Map<String, dynamic>.from(d as Map))
          .toList();
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
        return;
      }
      state = state.copy(
        step: 4,
        checkPassed: true,
        results: {},
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
        throw const GatewayFailure('wifi_failed');
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
    if (!connected) throw const GatewayFailure('wifi_failed');
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
  }) => _run('確認閘道器持續上線', 90, (generation) async {
    if (!skip && !_loggedIn && base != null && (password ?? '').isNotEmpty) {
      _backend = describeBackend(Uri.tryParse(base.trim()));
      await _api.login(base.trim(), password!);
      _check(generation);
      _setLoggedIn(true, base);
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
    state = state.copy(step: 4, verified: false, report: '', results: {});
    await discover();
  }

  Future<void> discover() async {
    _rssiTimer ??= Timer.periodic(ref.read(ptuSignalIntervalProvider), (_) {
      unawaited(refreshPtuRssi());
      unawaited(keepAlive());
    });
    _autoResetRescan = false;
    final before = Set<String>.of(state.selected);
    await _discover();
    if (ref.mounted && _autoResetRescan && state.error == null) {
      // 殘留編號已歸零：重掃一次讓它們變成可勾選；這次不再自動重置。
      _autoResetRescan = false;
      await _discover(autoReset: false);
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
            ? 'Gateway 掃描未完成：藍牙連線已中斷。請靠近 Gateway，再按「重新連線並掃描 PTU」。'
            : 'Gateway 掃描未完成，請查看錯誤後重新掃描。',
        error: state.error,
      );
    }
    if (ref.mounted && state.error == null) {
      final seen = state.ptus.map((p) => p['mac'].toString()).toSet();
      final absent = before.where((m) => !seen.contains(m)).length;
      state = state.copy(
        selected: state.selected.where(seen.contains).toSet(),
        absentNotice: absent > 0 ? absentSelectionText(absent) : '',
      );
    }
  }

  Future<void> _discover({
    bool autoReset = true,
  }) => _run('Gateway 正在掃描周邊 PTU，請稍候', 75, (generation) async {
    if (state.uploadWatch == UploadWatch.linkLost || state.resumePending) {
      await _reconnect(generation);
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
    state = state.copy(
      message: 'Gateway 正在掃描周邊 PTU，請稍候',
      ptus: [],
      selected: {},
      results: {},
      missing: [],
      starNotice: '',
    );
    final response = await _command(generation, 'scan_ble_discover', {
      'duration': 10,
    });
    _check(generation);
    final connected = await _command(generation, 'get_ble_devices');
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
    final selected = _preselect(ptus, target);
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
  Future<String?> _assignOne(int generation, String mac, int id) async {
    String? reason;
    for (int attempt = 0; attempt <= assignRetries; attempt++) {
      if (attempt > 0) await _wait(2, generation);
      _check(generation);
      try {
        final result = await _command(generation, 'assign_device_id', {
          'mac': mac,
          'new_id': id,
        });
        if (result['success'] == true) {
          // Firmware 1.7.15+: the ack names the PTU actually written.
          reason = assignAckMismatch(result, mac, id);
          if (reason == null) {
            if (ackNeedsReadback(result)) _pendingReadback.add(mac);
            return null;
          }
          continue;
        }
        reason = ptuFailureText(result['error'] ?? result['result']);
      } catch (e) {
        if (e is GatewayFailure && e.code == 'cancelled') rethrow;
        _check(generation);
        // Phone↔gateway link down: not this PTU's fault, stop retrying.
        if (isPhoneLinkFailure(e)) rethrow;
        reason = ptuFailureText(e);
      }
    }
    return reason ?? ptuFailureText(null);
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
    for (final (index, p) in targets.indexed) {
      _check(generation);
      final mac = p['mac'].toString();
      final old = (p['device_number'] as num?)?.toInt() ?? 0;
      final id = old >= first && old < first + 5 && !used.contains(old)
          ? old
          : List.generate(5, (i) => first + i).firstWhere(
              (id) => !used.contains(id),
              orElse: () => throw const GatewayFailure('gateway_full'),
            );
      used.add(id);
      results[mac] = '正在指派 #$id';
      state = state.copy(results: Map.of(results));
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
      _run('逐台編號並開始監控', 240, (generation) async {
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
        state = state.copy(
          step: 5,
          results: {
            for (final p in chosen)
              if (skip.contains(p['mac']))
                p['mac'].toString(): '已指派 #${p['device_number']}',
          },
          assignFailed: {},
          unassigned: {},
          assignedOk: skip,
          resumePending: false,
        );
        final targets = chosen.where((p) => !skip.contains(p['mac'])).toList();
        final failed = await _assignAll(generation, targets);
        await _startMonitoring(generation, chosen, failed);
      });

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
      final inRange = id >= first && id < first + 5;
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
  Future<void> _reconnect(int generation) async {
    final peer = state.peer;
    if (peer == null) throw const GatewayFailure('reconnect_failed');
    final Object link = _link;
    if (link is BluetoothReadiness && await link.adapterSettling()) {
      state = state.copy(message: waitingBluetoothText);
      await link.waitAdapterReady(bluetoothReadyBudget);
      _check(generation);
    }
    state = state.copy(message: reconnectingText);
    try {
      await _relink(generation, peer).timeout(reconnectBudget);
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
  Future<void> resumeAssign() =>
      _run(reconnectingText, 240, (generation) async {
        await _reconnect(generation);
        await _reconcile(generation);
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
      _run('重試指派失敗的 PTU', 240, (generation) async {
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
        state = state.copy(step: 5);
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
          return id >= first && id < first + 5;
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
              ? '未連上任何 PTU，請確認 PTU 電源與距離後重試；Gateway 仍維持監控。'
              : '已調整為 ${connected.length} 台；請重新選擇已連線裝置或修復缺少的 PTU。',
        );
        throw const GatewayFailure('incomplete');
      }
    }
  }

  /// [environment] is the selector value (`production` / `local` / `custom`);
  /// when omitted the target is derived from [base] alone.
  Future<void> verify(
    String base,
    String password, {
    String? environment,
  }) => _run('確認每台 PTU 的資料持續進入後端', 180, (generation) async {
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
    if (!_loggedIn) {
      await _api.login(base, password);
      _check(generation);
      _setLoggedIn(true, base);
    }
    try {
      // Renew the lease for every verification attempt; a cached flag may have expired.
      await _request(generation, 'PATCH', '$_path/bot-monitor', {
        'enabled': false,
        'ttl_minutes': 30,
      });
      _lease = true;
    } on GatewayFailure catch (error) {
      if (error.gatewayNotFound) throw error.withCause(cause);
      rethrow;
    }
    final previous = <int, DateTime>{};
    // Per PTU (round 8: one PTU without a new row reset everyone to 0/3).
    final counts = <int, int>{};
    final lastNew = <int, int>{};
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
    state = state.copy(
      verifyCounts: {for (final id in ids) id: 0},
      verifyWaiting: {},
      verifySkipped: {},
    );
    for (int elapsed = 0; elapsed < 180; elapsed += verifyPollSeconds) {
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
      state = state.copy(
        message: verifyProgressText(ids, counts, waiting, skipped),
        verifyCounts: Map.of(counts),
        verifyWaiting: waiting,
      );
      if (good) {
        await _request(generation, 'PATCH', '$_path/bot-monitor', {
          'enabled': true,
        });
        _lease = false;
        final skippedIds = ids.where(skipped.contains).toList()..sort();
        final skippedNote = skippedIds.isEmpty
            ? ''
            : '\n未驗證（已略過）：${skippedIds.map((id) => "#$id").join('、')}，'
                  '請現場確認 ${skippedIds.map((id) => "PTU #$id").join('、')} 電源與位置';
        _reportBody =
            '${_link.demo ? "模擬安裝報告（非實機驗證）" : "安裝報告"}\n站點 $site / 閘道器 $gateway\n${byDeviceNumber(state.ptus).map((p) => "#${p['device_number']}  ${p['mac']}").join('\n')}\n驗證時間：${DateTime.now().toIso8601String()}\n驗證後端：$_backend\n每台連續三次資料更新通過$skippedNote';
        state = state.copy(
          step: 7,
          verified: true,
          online: true,
          report: _report(),
          message: verifiedText,
        );
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
    throw const GatewayFailure('incomplete');
  });
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
    final next = base.trim();
    if (_loginBase == next && _loggedIn) return;
    if (!state.busy) _backend = describeBackend(Uri.tryParse(next));
    _setLoggedIn(false);
    if (!ref.mounted || state.busy) return;
    if (state.step == 7) {
      state = state.copy(online: false, message: backendSwitchedDoneText);
    } else if (state.step == 6) {
      state = state.copy(message: backendSwitchedVerifyText);
    }
  }

  /// Logs in to [base] outside a step (after switching environments).
  Future<void> login(String base, String password) =>
      _sideTask('登入後端', 30, (generation) async {
        await _api.login(base.trim(), password);
        _check(generation);
        _backend = describeBackend(Uri.tryParse(base.trim()));
        _setLoggedIn(true, base);
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

  /// Copies the gateway's own network fields (get_net_status only).
  void _absorbNet(Map<String, dynamic> source) {
    final update = {
      for (final key in gatewayNetKeys)
        if (source.containsKey(key)) key: source[key],
    };
    if (update.isEmpty) return;
    state = state.copy(net: {...state.net, ...update}, error: state.error);
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
    if (ref.mounted && generation == _generation) {
      state = state.copy(message: stage, error: state.error);
    }
  };

  static const _relinkBudget = Duration(seconds: 56);

  Future<void> _relink(int generation, GatewayPeer peer) async {
    await _link.disconnect();
    _check(generation);
    try {
      // The link itself retries (stale client drop, rescan, 3 attempts).
      await _link
          .connect(peer, onStage: _stageFor(generation))
          .timeout(_relinkBudget);
    } on GatewayFailure {
      rethrow;
    } catch (_) {
      await _link.disconnect();
      _check(generation);
      throw const GatewayFailure('disconnected');
    }
    _check(generation);
    await _command(generation, 'ping');
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
        state.ptus.isEmpty ||
        state.busy ||
        _pollInFlight ||
        _rssiInFlight ||
        state.uploadWatch == UploadWatch.linkLost) {
      return;
    }
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

  /// Step 7 link drop seen by a background poll: banner with 「重新連線並
  /// 繼續」 (round 8: this banner only had 「詳細資訊」).
  void _stepSevenLinkLost(GatewayFailure error) {
    _stopWatch(UploadWatch.linkLost);
    state = state.copy(
      error: error.message,
      errorDetail: error.toString(),
      scanResumePending: state.step == 4 ? true : null,
    );
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value) _markRssiStale();
  }

  Future<void> refreshHealth() async {
    if (!_foreground || _healthBusy || state.busy || !_loggedIn) return;
    _healthBusy = true;
    final loginBase = _loginBase;
    // A switch of backend while the request runs makes its answer stale.
    bool stale() => !_loggedIn || _loginBase != loginBase;
    try {
      final latest = await _api.request(
        'GET',
        '/api/latest?site_id=$site&gateway_id=$gateway',
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
    if (!_loggedIn && base != null && (password ?? '').isNotEmpty) {
      _backend = describeBackend(Uri.tryParse(base.trim()));
      await _api.login(base.trim(), password!);
      _check(generation);
      _setLoggedIn(true, base);
    }
    // After an environment switch the old login must not reach the new
    // site.
    if (!_loggedIn) throw const GatewayFailure('authentication');
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
    state = state.copy(
      step: 4,
      busy: false,
      seconds: 0,
      verified: false,
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
    _grace?.cancel();
    _stopWatch(UploadWatch.idle);
    final safe = await _safeStop();
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
        error: safe ? null : '尚未確認 Gateway 已恢復監控，請重新連線核對。',
        message: '已取消。請重新連線核對進度；未成功恢復的監控會話最晚於到期時恢復。',
      );
    }
  }
}
