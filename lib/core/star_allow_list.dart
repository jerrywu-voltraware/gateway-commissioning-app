import '../l10n/l10n.dart';
import 'protocol.dart';

/// Star-mode MAC allow list (`star_macs`, firmware 1.7.36, cmd_contract.md
/// §3B): the gateway only auto-connects a PTU whose number is in its range
/// AND whose MAC is listed. Fixes round 25's P0 「星狀連錯樁」 — the gateway
/// matched numbers only and took a neighbouring PTU still carrying an old
/// number. Firmware 1.7.37: until the list is set the gateway keeps the
/// number-only rule and `assign_device_id` does not create it, so the APP
/// sets it itself.
///
/// Round 27: the list goes to the gateway before step 8's first assign
/// ([starTargetList]: the chosen PTUs plus the ones configured earlier and
/// left untouched) — with foreign PTUs holding all five connections and no
/// list yet, every assign would fail with `No free slot` and the
/// verification that used to write the list could never be reached. The
/// verified list ([starAllowList], without failed or unverified PTUs) is
/// written again when the data verification passes. Firmware 1.7.36 (list
/// kept up by assigns, 「auto-collect」) and 1.7.37 (only an explicit list
/// counts) get the same writes.

/// `star_macs` holds at most this many MACs (`GIOS_MAX_CONNECTIONS`).
const starAllowListMax = 5;

/// Firmware 1.7.36+ takes `set_config star_macs`; older firmware counts the
/// unknown key as rejected, so the APP never sends it there.
bool starAllowListSupported(Map<String, dynamic> config) =>
    firmwareAtLeast(config['fw_version'], 1, 7, 36);

/// [mac] as `star_macs` spells it (`AA:BB:CC:DD:EE:FF`); null when it is
/// not 12 hex digits.
String? starMac(Object? mac) {
  final hex = (mac?.toString() ?? '')
      .replaceAll(RegExp('[^0-9a-fA-F]'), '')
      .toUpperCase();
  if (hex.length != 12) return null;
  return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
}

int _number(Map<String, dynamic> row) =>
    (row['device_number'] as num?)?.toInt() ?? 0;

/// The allow list to write when a star commissioning is verified: one MAC
/// per number of this gateway's range ([first] .. [first] + 4), read back
/// from the gateway's get_ble_devices [rows].
///
/// In order, each taking a number still free:
/// 1. PTUs of this run ([own]: chosen, assigned or reconciled — including
///    PTUs of an earlier, interrupted part of the run) the gateway reports
///    connected;
/// 2. [own] PTUs not connected right now (e.g. skipped at step 9 while
///    idle) with the number the APP knows from [known] — left out, the
///    gateway would take them for foreign ones once they come back;
/// 3. connected PTUs the gateway already lists (`star_listed`: configured
///    earlier, untouched by this run);
/// 4. unless the list is already enforced ([enforced], get_ble_devices
///    `star_enforced`): connected PTUs whose number no other connected PTU
///    carries — the gateway took them earlier by number (the APP's usual
///    rule for owned PTUs, and the firmware's own first-entry rule).
///
/// Round 27: [exclude] (PTUs whose assignment failed, or skipped at the
/// data verification) never make the list, whichever rule would take them.
///
/// Sorted by number; empty when nothing qualifies (never sent: an empty
/// list would clear it).
List<({int id, String mac})> starAllowList({
  required List<Map<String, dynamic>> rows,
  required Iterable<String> own,
  required int first,
  bool enforced = false,
  List<Map<String, dynamic>> known = const [],
  Iterable<String> exclude = const [],
}) {
  bool inRange(int id) => id >= first && id < first + starAllowListMax;
  final excluded = {for (final m in exclude) ?starMac(m)};
  final ownKeys = {for (final m in own) ?starMac(m)}.difference(excluded);
  final linked = [
    for (final row in rows)
      if (row['connected'] == true &&
          starMac(row['mac']) != null &&
          inRange(_number(row)))
        row,
  ];
  final linkedKeys = {for (final row in linked) starMac(row['mac'])!};
  final perNumber = <int, int>{};
  for (final row in linked) {
    perNumber.update(_number(row), (n) => n + 1, ifAbsent: () => 1);
  }
  final picked = <int, String>{};
  void take(Map<String, dynamic> row) {
    final key = starMac(row['mac']);
    final id = _number(row);
    if (key == null ||
        excluded.contains(key) ||
        !inRange(id) ||
        picked.containsKey(id) ||
        picked.containsValue(key) ||
        picked.length >= starAllowListMax) {
      return;
    }
    picked[id] = key;
  }

  for (final row in linked) {
    if (ownKeys.contains(starMac(row['mac']))) take(row);
  }
  for (final row in known) {
    final key = starMac(row['mac']);
    if (ownKeys.contains(key) && !linkedKeys.contains(key)) take(row);
  }
  for (final row in linked) {
    if (row['star_listed'] == true) take(row);
  }
  if (!enforced) {
    for (final row in linked) {
      if (perNumber[_number(row)] == 1) take(row);
    }
  }
  return [
    for (final id in picked.keys.toList()..sort()) (id: id, mac: picked[id]!),
  ];
}

/// Round 27: the allow list sent before step 8's first assign — the MACs
/// this gateway is meant to keep, from the step 7 list [rows] (nearby and
/// connected PTUs, `star_listed` where the gateway reported it):
/// 1. every [chosen] PTU (this run's selection, whatever number it carries
///    now — the assign gives it one of this gateway's numbers);
/// 2. PTUs configured here earlier and left untouched: not chosen, a number
///    in this gateway's range ([first] .. [first] + 4) that no chosen PTU
///    carries, and either already on the gateway's list (`star_listed`,
///    or named in [listed]: the list as get_config / the APP's last write
///    reported it — `star_listed` of the step 7 scan may predate a write)
///    or — only while no list is set ([listSet] false) — connected with a
///    number no other PTU of [rows] carries (the gateway took it earlier
///    by number; of two PTUs with one number the APP cannot tell which one
///    is ours, so neither is listed).
///
/// [dropped]: PTUs chosen by an earlier run of this commissioning that the
/// installer has left out since — never 「untouched」, so never kept.
///
/// At most [starAllowListMax], chosen first, then by number. `id` is the
/// number the PTU carries now (0 when none / out of range). The firmware
/// drops connected PTUs missing from the list within a second, which frees
/// the connections foreign PTUs held.
List<({String mac, int id})> starTargetList({
  required List<Map<String, dynamic>> rows,
  required Iterable<String> chosen,
  required int first,
  bool listSet = false,
  Iterable<String> listed = const [],
  Iterable<String> dropped = const [],
}) {
  bool inRange(int id) => id >= first && id < first + starAllowListMax;
  final listedKeys = {for (final m in listed) ?starMac(m)};
  final droppedKeys = {for (final m in dropped) ?starMac(m)};
  final out = <({String mac, int id})>[];
  final keys = <String>{};
  int numberOf(String key) {
    for (final row in rows) {
      if (starMac(row['mac']) == key) {
        final id = _number(row);
        return inRange(id) ? id : 0;
      }
    }
    return 0;
  }

  for (final mac in chosen) {
    final key = starMac(mac);
    if (key == null || keys.contains(key)) continue;
    if (out.length >= starAllowListMax) break;
    keys.add(key);
    out.add((mac: key, id: numberOf(key)));
  }
  final chosenKeys = {...keys};
  final taken = {
    for (final row in rows)
      if (chosenKeys.contains(starMac(row['mac'])) && inRange(_number(row)))
        _number(row),
  };
  final others = [
    for (final row in rows)
      if (starMac(row['mac']) case final key?)
        if (!chosenKeys.contains(key) &&
            !droppedKeys.contains(key) &&
            inRange(_number(row)) &&
            !taken.contains(_number(row)))
          row,
  ]..sort((a, b) => _number(a).compareTo(_number(b)));
  final perNumber = <int, int>{};
  for (final row in others) {
    perNumber.update(_number(row), (n) => n + 1, ifAbsent: () => 1);
  }
  void take(Map<String, dynamic> row) {
    final key = starMac(row['mac'])!;
    final id = _number(row);
    if (keys.contains(key) ||
        out.any((e) => e.id == id) ||
        out.length >= starAllowListMax) {
      return;
    }
    keys.add(key);
    out.add((mac: key, id: id));
  }

  for (final row in others) {
    if (row['star_listed'] == true ||
        listedKeys.contains(starMac(row['mac']))) {
      take(row);
    }
  }
  if (!listSet) {
    for (final row in others) {
      if (row['connected'] == true && perNumber[_number(row)] == 1) take(row);
    }
  }
  final kept = out.skip(chosenKeys.length).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return [...out.take(chosenKeys.length), ...kept];
}

/// get_ble_devices [response]: connected PTUs not on the allow list while
/// it is enforced (`star_enforced`; the gateway drops them within a
/// second). 0 when the list is not enforced — every PTU is unlisted then.
int unlistedStarPtus(Map<String, dynamic> response) {
  if (response['star_enforced'] != true) return 0;
  return (response['devices'] as List? ?? const [])
      .whereType<Map>()
      .where((d) => d['connected'] == true && d['star_listed'] == false)
      .length;
}

/// The MACs a `set_config star_macs` ack / get_config read-back names, as a
/// set in [starMac] spelling; null when [value] is not a list.
Set<String>? starMacSet(Object? value) =>
    value is List ? {for (final m in value) ?starMac(m)} : null;

/// `set_config` answers `config updated: N params changed, M rejected
/// (invalid)` (always status ok): true when a key was refused.
bool setConfigRejected(Map<String, dynamic> ack) =>
    RegExp(r'[1-9]\d*\s+rejected').hasMatch(ack['message']?.toString() ?? '');

/// Which write [StarListStatus] is about.
enum StarListStage {
  /// Round 27: step 8, before the first assign ([starTargetList]).
  beforeAssign,

  /// Step 8, right after a direct gateway was switched back to star.
  afterSwitch,

  /// After the star verification passed (completion page).
  verified,
}

/// Where the allow list stands for the installer.
enum StarListStatus {
  /// Not written by this APP in this run (star with firmware 1.7.36+ only).
  none,

  /// Being written.
  writing,

  /// Written and read back.
  written,

  /// Retried and still not written (the gateway keeps its previous list, or
  /// the number-only rule).
  failed,
}

String get starListWritingText => L10n.current.starAllowList_writing;

/// Completion page, the write failed after its retries (never blocks the
/// completion itself).
String get starListFailedText => L10n.current.starAllowList_failed;

String get starListRetryLabel => L10n.current.starAllowList_retryButton;

/// Step 8, direct → star: the list sent right after the switch failed; the
/// verified list is written again when the data verification passes.
String get starListSwitchFailedText => L10n.current.starAllowList_switchFailed;

/// Round 27: step 8, the list sent before the first assign failed after
/// its retries; the assignment goes on (never blocked by it).
String get starListBeforeFailedText => L10n.current.starAllowList_beforeFailed;

/// Completion page after a successful write ([ids]: the listed numbers).
String starListWrittenText(List<int> ids) => L10n.current.starAllowList_written(
  ids.map((id) => '#$id').join(L10n.current.starAllowList_idSeparator),
);

/// Install report line; null when this run wrote no list.
///
/// i18n：安裝報告上傳後台、分享、複製，固定中文（docs/i18n.md §6）。
String? starListReportText(StarListStatus status, List<int> ids) =>
    switch (status) {
      // i18n-keep-zh-begin
      StarListStatus.written =>
        'PTU 綁定名單：已寫入 ${ids.map((id) => '#$id').join('、')}',
      StarListStatus.failed => 'PTU 綁定名單：未寫入（請在完成頁重試）',
      // i18n-keep-zh-end
      _ => null,
    };

/// Step 7 star list: the gateway ignores PTUs carrying one of its numbers
/// but not on its allow list — [foreign]: heard nearby in the last 10
/// minutes (get_status `star.foreign_ptus`); [unlisted]: connected, not
/// listed while the list is enforced (dropped within a second). Null when
/// both are 0. Never shows firmware codes.
String? foreignPtuText({required int foreign, required int unlisted}) {
  if (foreign <= 0 && unlisted <= 0) return null;
  final l10n = L10n.current;
  return [
    if (foreign > 0) l10n.starAllowList_foreignIgnored(foreign),
    if (unlisted > 0) l10n.starAllowList_unlistedDropped(unlisted),
    l10n.starAllowList_reselectHint,
  ].join(l10n.starAllowList_sentenceSeparator);
}
