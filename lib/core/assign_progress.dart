/// Round 21 (field round 21: star step 8 assigned 5 PTUs in 80 s, two of
/// them only after automatic retries — GATT 133 on one, 133 then a busy
/// gateway on the other — and the screen showed nothing but a spinner):
/// what each PTU's assignment is doing right now, and the whole run in one
/// line. The texts name no error code; [AssignStatus.detail] keeps the raw
/// failure for the PTU's details sheet.
library;

import '../l10n/l10n.dart';

/// What a step 8 PTU row's result text (`CommissionState.results`) says,
/// for [assignStatusText]. 2026-10-05 (i18n): replaces
/// `startsWith('尚未指派')` / `startsWith('正在指派')`, which broke once the
/// texts follow the screen language.
enum AssignResultKind {
  /// The run stopped on a phone link loss ([AppLocalizations.assign_notAssignedLink]).
  notAssigned,

  /// The number is being written ([AppLocalizations.assign_assigningResult]).
  assigning,

  /// Anything else (「已連線 #3」, 「已指派 #3，等待連線」…).
  other,
}

/// The kind of [result]. Compares with the fixed texts of every supported
/// language (not only the current one), so a row written before a language
/// switch is still recognised.
AssignResultKind assignResultKindOf(String? result) {
  if (result == null || result.isEmpty) return AssignResultKind.other;
  for (final language in AppLanguage.values) {
    final l10n = lookupAppLocalizations(language.locale);
    if (result == l10n.assign_notAssignedLink) {
      return AssignResultKind.notAssigned;
    }
    if (_matchesIdTemplate(result, l10n.assign_assigningResult)) {
      return AssignResultKind.assigning;
    }
  }
  return AssignResultKind.other;
}

/// [text] is [template] filled with some integer id.
bool _matchesIdTemplate(String text, String Function(int id) template) {
  const probe = 987654321;
  final filled = template(probe);
  final at = filled.indexOf('$probe');
  if (at < 0) return text == filled;
  final prefix = filled.substring(0, at);
  final suffix = filled.substring(at + '$probe'.length);
  if (text.length <= prefix.length + suffix.length ||
      !text.startsWith(prefix) ||
      !text.endsWith(suffix)) {
    return false;
  }
  final id = text.substring(prefix.length, text.length - suffix.length);
  return int.tryParse(id) != null;
}

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
    assignResultKindOf(result) == AssignResultKind.notAssigned
        ? result!
        : '等待中',
  AssignPhase.assigning => status.id == null ? '指派中' : '指派中 #${status.id}',
  AssignPhase.linkRetry => '藍牙連線失敗，自動重試 ${status.retry}/${status.retries}',
  AssignPhase.retry => '未完成，自動重試 ${status.retry}/${status.retries}',
  AssignPhase.busy => '閘道器忙碌，稍後重試',
  AssignPhase.done =>
    result != null &&
            result.isNotEmpty &&
            assignResultKindOf(result) != AssignResultKind.assigning
        ? '完成 · $result'
        : status.id == null
        ? '完成'
        : '完成 · #${status.id}',
  AssignPhase.failed =>
    failure == null || failure.isEmpty ? '失敗需處理' : '失敗需處理：$failure',
};

/// The whole run in one line: 「3/5 完成，1 台自動重試中」 (plus 「n 台
/// 失敗需處理」); null without an assignment to report.
///
/// Round 22 (field round 22: the retrying row was often below the fold and
/// 「1 台自動重試中」 did not say which): with [name] (MAC → the PTU as its
/// row shows it) the retrying PTUs are named — 「4/5 完成，PTU #5 自動重試中
/// （1/2）」, 「3/5 完成，PTU #4、PTU …74… 自動重試中」, from three on
/// 「PTU #1、PTU #2 等 3 台自動重試中」.
String? assignProgressText(
  Map<String, AssignStatus> statuses, {
  String Function(String mac)? name,
}) {
  if (statuses.isEmpty) return null;
  final all = statuses.values;
  final done = all.where((s) => s.phase == AssignPhase.done).length;
  final retrying = [
    for (final e in statuses.entries)
      if (e.value.retrying) e,
  ];
  final failed = all.where((s) => s.phase == AssignPhase.failed).length;
  return [
    '$done/${statuses.length} 完成',
    if (retrying.isNotEmpty)
      name == null
          ? '${retrying.length} 台自動重試中'
          : _retryingNamed(retrying, name),
    if (failed > 0) '$failed 台失敗需處理',
  ].join('，');
}

String _retryingNamed(
  List<MapEntry<String, AssignStatus>> retrying,
  String Function(String mac) name,
) {
  if (retrying.length == 1) {
    final status = retrying.single.value;
    // A busy gateway is sent again without counting a retry (its row says
    // 「閘道器忙碌，稍後重試」).
    final count = status.phase != AssignPhase.busy && status.retries > 0
        ? '（${status.retry}/${status.retries}）'
        : '';
    return '${name(retrying.single.key)} 自動重試中$count';
  }
  final names = retrying.take(2).map((e) => name(e.key)).join('、');
  return retrying.length == 2
      ? '$names 自動重試中'
      : '$names 等 ${retrying.length} 台自動重試中';
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
