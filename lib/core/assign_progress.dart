/// Round 21 (field round 21: star step 8 assigned 5 PTUs in 80 s, two of
/// them only after automatic retries — GATT 133 on one, 133 then a busy
/// gateway on the other — and the screen showed nothing but a spinner):
/// what each PTU's assignment is doing right now, and the whole run in one
/// line. The texts name no error code; [AssignStatus.detail] keeps the raw
/// failure for the PTU's details sheet.
library;

/// Where one PTU's step 8 assignment stands.
enum AssignPhase {
  /// Not started yet (another PTU goes first).
  waiting,

  /// assign_device_id sent, first try.
  assigning,

  /// The gateway could not open its Bluetooth link to the PTU (GATT 133,
  /// connection / service discovery timeout): retried automatically.
  linkRetry,

  /// Any other failed try (no answer, a mismatching ack): retried
  /// automatically.
  retry,

  /// The gateway answered 'busy' (e.g. still connecting another PTU): sent
  /// again shortly, automatically.
  busy,

  /// Assigned.
  done,

  /// Out of automatic retries: the installer has to act (「重試這 N 台」).
  failed,
}

/// One PTU's [AssignPhase] with the number being written and, while
/// retrying, which automatic retry of how many ([retry] / [retries]).
class AssignStatus {
  const AssignStatus(
    this.phase, {
    this.id,
    this.retry = 0,
    this.retries = 0,
    this.detail,
  });

  final AssignPhase phase;

  /// The PTU number being written (#n), when known.
  final int? id;

  /// [AssignPhase.linkRetry] / [AssignPhase.retry]: this is automatic retry
  /// [retry] of at most [retries].
  final int retry, retries;

  /// The last failure as the gateway / link reported it (may hold error
  /// codes); only for the details sheet.
  final String? detail;

  /// Still being handled by the APP by itself (no tap needed).
  bool get retrying =>
      phase == AssignPhase.linkRetry ||
      phase == AssignPhase.retry ||
      phase == AssignPhase.busy;

  /// A spinner belongs next to it.
  bool get active => phase == AssignPhase.assigning || retrying;
}

/// The PTU row's status line for [status]. [result] is the row's own
/// result text (「已連線 #3」, 「已指派 #3，等待連線」, 「尚未指派（…）」),
/// [failure] the installer-facing reason of a failed PTU.
String assignStatusText(
  AssignStatus status, {
  String? result,
  String? failure,
}) => switch (status.phase) {
  AssignPhase.waiting =>
    result != null && result.startsWith('尚未指派') ? result : '等待中',
  AssignPhase.assigning => status.id == null ? '指派中' : '指派中 #${status.id}',
  AssignPhase.linkRetry => '藍牙連線失敗，自動重試 ${status.retry}/${status.retries}',
  AssignPhase.retry => '未完成，自動重試 ${status.retry}/${status.retries}',
  AssignPhase.busy => '閘道器忙碌，稍後重試',
  AssignPhase.done =>
    result != null && result.isNotEmpty && !result.startsWith('正在指派')
        ? '完成 · $result'
        : status.id == null
        ? '完成'
        : '完成 · #${status.id}',
  AssignPhase.failed =>
    failure == null || failure.isEmpty ? '失敗需處理' : '失敗需處理：$failure',
};

/// The whole run in one line: 「3/5 完成，1 台自動重試中」 (plus 「n 台
/// 失敗需處理」); null without an assignment to report.
String? assignProgressText(Map<String, AssignStatus> statuses) {
  if (statuses.isEmpty) return null;
  final all = statuses.values;
  final done = all.where((s) => s.phase == AssignPhase.done).length;
  final retrying = all.where((s) => s.retrying).length;
  final failed = all.where((s) => s.phase == AssignPhase.failed).length;
  return [
    '$done/${statuses.length} 完成',
    if (retrying > 0) '$retrying 台自動重試中',
    if (failed > 0) '$failed 台失敗需處理',
  ].join('，');
}

/// Done share of [statuses] for a progress bar (0 when empty).
double assignProgressValue(Map<String, AssignStatus> statuses) {
  if (statuses.isEmpty) return 0;
  final done = statuses.values.where((s) => s.phase == AssignPhase.done).length;
  return done / statuses.length;
}

/// Round 21: under the progress while the run goes on — the installer has
/// nothing to do, failed tries are retried by the APP itself.
const assignAutoHint = '系統自動處理中，失敗會自動重試，不用動手';

/// Round 21: under the progress once [failed] PTUs are out of retries.
String assignFailedHint(int failed) => '請確認 PTU 電源與距離，再按下方「重試這 $failed 台」';
