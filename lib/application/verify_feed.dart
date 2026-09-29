/// 1.0.0+18: the data verification's live feed — each new row the step's
/// own `/api/latest` poll brought in, as the installer sees it (the data
/// time, V / A / °C, the lag, counted or why not).
///
/// Built only from what the poll already read and what [verifyTally] made
/// of it (the counts before and after): nothing here judges, and nothing
/// here is read back by the verification.
library;

import 'verify_diagnosis.dart' show ptuVerifyReasons;

/// Rows kept (and shown) per PTU, newest first.
const verifyFeedPerPtu = 5;

/// New rows a PTU needs (the verification's 3).
const verifyFeedNeed = 3;

/// One new row of one PTU.
class VerifyFeedEntry {
  const VerifyFeedEntry({
    required this.serial,
    this.poll = 0,
    required this.id,
    this.mac = '',
    this.ts,
    this.inputMv,
    this.inputMa,
    this.tempC,
    this.lag,
    required this.ok,
    this.counted = false,
    required this.count,
    this.restart = false,
    this.reasons = const [],
    this.earlier = false,
  });

  /// Grows by one per entry (an entry slides in once: its widget key).
  final int serial;

  /// Grows by one per poll that brought new rows (the rows of one poll
  /// are announced together).
  final int poll;

  /// The PTU's number, and the selection's MAC for it.
  final int id;
  final String mac;

  /// The row's data time (`ts`, local).
  final DateTime? ts;

  /// `ptu.ptu_inputVoltage_mV` / `ptu_inputCurrent_mA` /
  /// `ptu_ampTemp_degC` of the row; null when it has none (not shown).
  final num? inputMv, inputMa, tempC;

  /// The row's `lag_seconds`, as the back office computed it.
  final num? lag;

  /// A good row: counted, or (the PTU already at 3/3) one that would be.
  final bool ok;

  /// This row raised the PTU's count.
  final bool counted;

  /// The PTU's count after this row (0..3).
  final int count;

  /// The first row of a new count after an earlier count of this PTU (a
  /// new verification started from 0): 「重新計數：第 1/3 筆」.
  final bool restart;

  /// Why the row was not counted ([ptuVerifyReasons]' words).
  final List<String> reasons;

  /// Read by an earlier verification (shown dimmed, never announced).
  final bool earlier;

  /// This entry, from an earlier verification.
  VerifyFeedEntry asEarlier() => VerifyFeedEntry(
    serial: serial,
    poll: poll,
    id: id,
    mac: mac,
    ts: ts,
    inputMv: inputMv,
    inputMa: inputMa,
    tempC: tempC,
    lag: lag,
    ok: ok,
    counted: counted,
    count: count,
    restart: restart,
    reasons: reasons,
    earlier: true,
  );
}

num? _num(Object? v) => v is num ? v : null;

/// The PTU values of a `/api/latest` row: nested under `ptu` (the
/// back office's `PTUData`), or flat as `/api/app/recent` names them.
({num? mv, num? ma, num? c}) _values(Map<String, dynamic> row) {
  final ptu = row['ptu'];
  final nested = ptu is Map ? ptu : const {};
  return (
    mv: _num(nested['ptu_inputVoltage_mV']) ?? _num(row['input_mv']),
    ma: _num(nested['ptu_inputCurrent_mA']) ?? _num(row['input_ma']),
    c: _num(nested['ptu_ampTemp_degC']) ?? _num(row['temp_c']),
  );
}

/// The feed after one poll: [feed] plus, newest first, one entry per PTU
/// of [ids] whose row in [rows] (the rows the poll judged; the first one
/// per PTU, as [verifyTally] takes it) carries a time newer than [before]
/// (the times known before [verifyTally] ran). [countsBefore] /
/// [countsAfter]: the counts before and after [verifyTally]; [macs]: the
/// selection's MAC per PTU. At most [verifyFeedPerPtu] entries per PTU
/// are kept. Reads its arguments only.
List<VerifyFeedEntry> verifyFeedAfterPoll({
  required List<VerifyFeedEntry> feed,
  required Iterable<int> ids,
  required List<Map<String, dynamic>> rows,
  required Map<int, DateTime> before,
  required Map<int, int> countsBefore,
  required Map<int, int> countsAfter,
  Map<int, String> macs = const {},
}) {
  var serial = 0, poll = 0;
  for (final e in feed) {
    if (e.serial > serial) serial = e.serial;
    if (e.poll > poll) poll = e.poll;
  }
  poll++;
  final added = <VerifyFeedEntry>[];
  for (final id in List.of(ids)..sort()) {
    final row = rows.where((r) => r['device_id'] == id).firstOrNull;
    if (row == null) continue;
    final stamp = DateTime.tryParse(row['ts']?.toString() ?? '');
    if (stamp == null) continue;
    final seen = before[id];
    if (seen != null && !stamp.isAfter(seen)) continue;
    final was = countsBefore[id] ?? 0;
    final now = countsAfter[id] ?? was;
    final reasons = ptuVerifyReasons(latest: row);
    final counted = now > was;
    final ok = counted || (was >= verifyFeedNeed && reasons.isEmpty);
    final values = _values(row);
    added.add(
      VerifyFeedEntry(
        serial: ++serial,
        poll: poll,
        id: id,
        mac: macs[id] ?? row['ptu_mac']?.toString() ?? '',
        ts: stamp.toLocal(),
        inputMv: values.mv,
        inputMa: values.ma,
        tempC: values.c,
        lag: _num(row['lag_seconds']),
        ok: ok,
        counted: counted,
        count: now,
        restart:
            counted && now == 1 && feed.any((e) => e.id == id && e.count > 0),
        reasons: ok ? const [] : reasons,
      ),
    );
  }
  if (added.isEmpty) return feed;
  return _trim([...added, ...feed]);
}

/// At most [verifyFeedPerPtu] entries per PTU, order kept.
List<VerifyFeedEntry> _trim(List<VerifyFeedEntry> entries) {
  final seen = <int, int>{};
  final out = <VerifyFeedEntry>[];
  for (final e in entries) {
    final n = (seen[e.id] ?? 0) + 1;
    seen[e.id] = n;
    if (n <= verifyFeedPerPtu) out.add(e);
  }
  return out;
}

String _macKey(String mac) =>
    mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

/// The feed a new verification (not a continued one) starts with: the
/// entries of the PTUs it verifies again ([macs]: number → MAC), marked
/// [VerifyFeedEntry.earlier], so a count that starts over reads
/// 「重新計數」 above the rows before it.
List<VerifyFeedEntry> verifyFeedForRun(
  List<VerifyFeedEntry> feed,
  Map<int, String> macs,
) => [
  for (final e in feed)
    if (macs[e.id] case final mac?
        when e.mac.isEmpty || _macKey(e.mac) == _macKey(mac))
      e.earlier ? e : e.asEarlier(),
];

/// The newest entry of this verification (the one the page announces),
/// or null; [all]: also one of an earlier verification.
VerifyFeedEntry? verifyFeedNewest(
  List<VerifyFeedEntry> feed, {
  bool all = false,
}) {
  VerifyFeedEntry? best;
  for (final e in feed) {
    if (e.earlier && !all) continue;
    if (best == null || e.serial > best.serial) best = e;
  }
  return best;
}

/// The rows of this verification's newest poll that brought any, by PTU
/// number (empty when none yet).
List<VerifyFeedEntry> verifyFeedLastPoll(List<VerifyFeedEntry> feed) {
  final newest = verifyFeedNewest(feed);
  if (newest == null) return const [];
  return [
    for (final e in feed)
      if (!e.earlier && e.poll == newest.poll) e,
  ]..sort((a, b) => a.id.compareTo(b.id));
}
