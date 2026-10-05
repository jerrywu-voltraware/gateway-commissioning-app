/// 09-28 (user request after the second rehearsal: 「正在確認閘道器上線，
/// 請稍候」 was one spinner and one sentence for up to 90 s): the automatic
/// steps as a checklist that fills in one item at a time — pending (grey
/// circle), running (spinner, 「進行中…」), done (green tick, its result or
/// the time), failed (red cross, the reason; the page keeps its retry).
///
/// Pure Dart: the controller ticks items on real events (an ack, a backend
/// reply, a heartbeat), the page only draws them.
library;

import '../l10n/l10n.dart';
import 'mqtt_target.dart';

enum CheckStatus { pending, running, done, failed }

/// Which automatic page a checklist belongs to.
enum ChecklistKind {
  /// 「正在連線並檢查網路」 (gateway list → network check).
  connect,

  /// 「正在確認閘道器上線」 (heartbeats reach the back office).
  online,

  /// 「正在完成設定」 / 「正在配置 PTU」 → data verification.
  finish,
}

class CheckItem {
  const CheckItem(
    this.id,
    this.label, {
    this.status = CheckStatus.pending,
    this.note = '',
    this.at,
  });

  final String id, label;
  final CheckStatus status;

  /// Running: its progress (「2/5 台」); done: its result (「心跳 2/2」);
  /// failed: the reason in plain words.
  final String note;

  /// When it was done ([note] empty: the page shows this time).
  final DateTime? at;

  CheckItem to(CheckStatus status, {String note = '', DateTime? at}) =>
      CheckItem(id, label, status: status, note: note, at: at);
}

class Checklist {
  const Checklist(this.kind, this.items);

  final ChecklistKind kind;
  final List<CheckItem> items;

  bool has(String id) => items.any((i) => i.id == id);

  CheckItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  bool isDone(String id) => item(id)?.status == CheckStatus.done;
  bool get running => items.any((i) => i.status == CheckStatus.running);
  bool get failed => items.any((i) => i.status == CheckStatus.failed);
  bool get allDone => items.every((i) => i.status == CheckStatus.done);
  int get doneCount => items.where((i) => i.status == CheckStatus.done).length;

  Checklist _map(CheckItem Function(CheckItem) change) =>
      Checklist(kind, [for (final i in items) change(i)]);

  /// [id] is running ([note]: its progress so far). Unknown ids: unchanged.
  Checklist start(String id, {String note = ''}) => has(id)
      ? _map((i) => i.id == id ? i.to(CheckStatus.running, note: note) : i)
      : this;

  /// A running (or pending) [id] shows [note] as its progress; a done or
  /// failed one is left alone.
  Checklist progress(String id, String note) => _map(
    (i) =>
        i.id == id &&
            (i.status == CheckStatus.running || i.status == CheckStatus.pending)
        ? i.to(CheckStatus.running, note: note)
        : i,
  );

  /// [id] is done: [note] its result ('' → the page shows the time).
  Checklist done(String id, {String note = '', DateTime? at}) => has(id)
      ? _map(
          (i) => i.id == id
              ? i.to(CheckStatus.done, note: note, at: at ?? DateTime.now())
              : i,
        )
      : this;

  /// Every item up to (not including) [id] that is not done yet is done
  /// with [note] — e.g. what an earlier run already finished.
  Checklist doneBefore(String id, {required String note}) {
    final index = items.indexWhere((i) => i.id == id);
    if (index < 0) return this;
    return Checklist(kind, [
      for (final (n, i) in items.indexed)
        n < index && i.status != CheckStatus.done
            ? i.to(CheckStatus.done, note: note)
            : i,
    ]);
  }

  /// [id] (default: the running item, else the first pending one) failed
  /// with [reason]; any other running item goes back to pending — nothing
  /// keeps spinning next to a red cross.
  Checklist fail(String reason, {String? id}) {
    final target =
        id ??
        items.where((i) => i.status == CheckStatus.running).firstOrNull?.id ??
        items.where((i) => i.status == CheckStatus.pending).firstOrNull?.id;
    if (target == null || !has(target)) return this;
    return _map(
      (i) => i.id == target
          ? i.to(CheckStatus.failed, note: reason)
          : i.status == CheckStatus.running
          ? i.to(CheckStatus.pending)
          : i,
    );
  }

  /// The run ended without an outcome for its running item (cancelled,
  /// superseded): back to pending.
  Checklist settle() => running
      ? _map(
          (i) =>
              i.status == CheckStatus.running ? i.to(CheckStatus.pending) : i,
        )
      : this;

  /// The first item not done yet starts running (with [note]).
  Checklist startNext({String note = ''}) {
    final next = items.where((i) => i.status != CheckStatus.done).firstOrNull;
    return next == null ? this : start(next.id, note: note);
  }
}

/// A failed item's reason: what happened, from the page's error — its
/// first line and sentence, without the 「，請…」 advice (the red box
/// right below keeps the full text, what to do and its retry).
///
/// 2026-10-05 (i18n): the error follows the screen language, so both
/// languages are cut — a sentence ends at 「。」 or at an English period
/// followed by a space (not inside 1.7.36); the advice starts at 「，請」 or
/// 「, please」.
String checklistReason(String? error) {
  var line = (error ?? '').trim().split('\n').first.trim();
  final end = _sentenceEnd(line);
  if (end >= 0) line = line.substring(0, end);
  for (final marker in _adviceMarkers) {
    final advice = line.toLowerCase().indexOf(marker);
    if (advice > 0) line = line.substring(0, advice);
  }
  line = line.trim();
  while (_reasonTails.any(line.endsWith)) {
    line = line.substring(0, line.length - 1).trim();
  }
  return line.isEmpty ? L10n.current.coreProgressChecklist_notDone : line;
}

/// Where the advice of an error starts (compared in lower case).
const _adviceMarkers = [
  '，請', // i18n-keep-zh（辨識中文錯誤訊息的建議段，不是顯示文字）
  ', please',
];

/// Punctuation dropped from the end of a reason.
const _reasonTails = [
  '：', // i18n-keep-zh（全形標點，辨識用）
  ':',
  '。', // i18n-keep-zh（全形標點，辨識用）
  '.',
];

/// End of the first sentence of [line]: 「。」, or 「.」 followed by white
/// space; -1 when it is one sentence.
int _sentenceEnd(String line) {
  final zh = line.indexOf('。'); // i18n-keep-zh（全形句號，辨識用）
  final en = RegExp(r'\.\s').firstMatch(line)?.start ?? -1;
  if (zh < 0) return en;
  if (en < 0) return zh;
  return zh < en ? zh : en;
}

// ---- The items of each automatic page (plain words, no codes) ----

/// 第 2 步 「正在連線並檢查網路」.
const connectItemBle = 'ble',
    connectItemStatus = 'status',
    connectItemWifi = 'wifi',
    connectItemBackend = 'backend';

Checklist connectChecklist() {
  final l10n = L10n.current;
  return Checklist(ChecklistKind.connect, [
    CheckItem(connectItemBle, l10n.coreProgressChecklist_connectBle),
    CheckItem(connectItemStatus, l10n.coreProgressChecklist_connectStatus),
    CheckItem(connectItemWifi, l10n.coreProgressChecklist_connectWifi),
    CheckItem(connectItemBackend, l10n.coreProgressChecklist_connectBackend),
  ]);
}

/// 第 5 步 「確認閘道器上線」.
const onlineItemBackend = 'backend',
    onlineItemBeat1 = 'beat1',
    onlineItemBeat2 = 'beat2',
    onlineItemTarget = 'target';

Checklist onlineChecklist() {
  final l10n = L10n.current;
  return Checklist(ChecklistKind.online, [
    CheckItem(onlineItemBackend, l10n.coreProgressChecklist_onlineBackend),
    CheckItem(onlineItemBeat1, l10n.coreProgressChecklist_onlineBeat1),
    CheckItem(onlineItemBeat2, l10n.coreProgressChecklist_onlineBeat2),
    CheckItem(onlineItemTarget, l10n.coreProgressChecklist_onlineTarget),
  ]);
}

/// 上傳目標確認's result: where the heartbeats arrived.
String uploadTargetNote(MqttTarget? target) => target == null
    ? L10n.current.coreProgressChecklist_targetCurrent
    : target.isLocal
    ? L10n.current.coreProgressChecklist_targetLocal
    : L10n.current.mqttTarget_production;

/// 「正在完成設定」 (one-to-one, after 〔是這台，開始配置〕) and 「正在配置
/// PTU」 (star, and old firmware's list) — through the data verification.
const finishItemList = 'list',
    finishItemAssign = 'assign',
    finishItemBind = 'bind',
    finishItemSettings = 'settings',
    finishItemJoin = 'join',
    finishItemJoined = 'joined',
    finishItemData = 'data';

/// [direct]: the one-to-one flow (bind, its setting, join); otherwise the
/// PTU list flow — [starList]: the gateway takes a PTU list first (star,
/// firmware 1.7.36+); [total]: PTUs to number.
Checklist finishChecklist({
  required bool direct,
  bool starList = false,
  int total = 1,
}) {
  final l10n = L10n.current;
  return Checklist(ChecklistKind.finish, [
    if (direct) ...[
      CheckItem(finishItemBind, l10n.coreProgressChecklist_finishBind),
      CheckItem(finishItemSettings, l10n.coreProgressChecklist_finishSettings),
    ] else ...[
      if (starList)
        CheckItem(finishItemList, l10n.coreProgressChecklist_finishList),
      CheckItem(
        finishItemAssign,
        total > 1
            ? l10n.coreProgressChecklist_finishAssignTotal(total)
            : l10n.coreProgressChecklist_finishAssign,
      ),
    ],
    CheckItem(finishItemJoin, l10n.coreProgressChecklist_finishJoin),
    CheckItem(finishItemJoined, l10n.coreProgressChecklist_finishJoined),
    CheckItem(finishItemData, l10n.coreProgressChecklist_finishData),
  ]);
}

/// 「收到 1/3 筆」 (one PTU) / 「每台 1/3 筆」 (several).
String dataCountNote(int count, int need, {required int ptus}) => ptus > 1
    ? L10n.current.coreProgressChecklist_dataEach(count, need)
    : L10n.current.coreProgressChecklist_dataReceived(count, need);
