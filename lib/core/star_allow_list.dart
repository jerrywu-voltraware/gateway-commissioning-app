import 'protocol.dart';

/// Star-mode MAC allow list (`star_macs`, firmware 1.7.36, cmd_contract.md
/// §3B): the gateway only auto-connects a PTU whose number is in its range
/// AND whose MAC is listed. Fixes round 25's P0 「星狀連錯樁」 — the gateway
/// matched numbers only and took a neighbouring PTU still carrying an old
/// number. Firmware 1.7.37: until the list is set the gateway keeps the
/// number-only rule and `assign_device_id` does not create it, so the APP
/// writes it when a star commissioning is verified.

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
/// Sorted by number; empty when nothing qualifies (never sent: an empty
/// list would clear it).
List<({int id, String mac})> starAllowList({
  required List<Map<String, dynamic>> rows,
  required Iterable<String> own,
  required int first,
  bool enforced = false,
  List<Map<String, dynamic>> known = const [],
}) {
  bool inRange(int id) => id >= first && id < first + starAllowListMax;
  final ownKeys = {for (final m in own) ?starMac(m)};
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

const starListWritingText = '正在寫入 PTU 綁定名單';

/// Completion page, the write failed after its retries (never blocks the
/// completion itself).
const starListFailedText =
    'PTU 綁定名單未寫入，請重試。'
    '未寫入前閘道器只看編號，附近帶相同編號的其他 PTU 仍可能被連走。';

const starListRetryLabel = '重試寫入綁定名單';

/// Step 8, direct → star: the list sent right after the switch failed; the
/// verified list is written again when the data verification passes.
const starListSwitchFailedText = '切回星狀後 PTU 綁定名單未寫入，資料驗證完成後會再寫一次。';

/// Completion page after a successful write ([ids]: the listed numbers).
String starListWrittenText(List<int> ids) =>
    'PTU 綁定名單已寫入：${ids.map((id) => '#$id').join('、')}'
    '（閘道器只連這幾台，附近編號相同的其他 PTU 不會被連走）';

/// Install report line; null when this run wrote no list.
String? starListReportText(StarListStatus status, List<int> ids) =>
    switch (status) {
      StarListStatus.written =>
        'PTU 綁定名單：已寫入 ${ids.map((id) => '#$id').join('、')}',
      StarListStatus.failed => 'PTU 綁定名單：未寫入（請在完成頁重試）',
      _ => null,
    };

/// Step 7 star list: the gateway ignores PTUs carrying one of its numbers
/// but not on its allow list — [foreign]: heard nearby in the last 10
/// minutes (get_status `star.foreign_ptus`); [unlisted]: connected, not
/// listed while the list is enforced (dropped within a second). Null when
/// both are 0. Never shows firmware codes.
String? foreignPtuText({required int foreign, required int unlisted}) {
  if (foreign <= 0 && unlisted <= 0) return null;
  return [
    if (foreign > 0) '附近有 $foreign 台編號相同的其他 PTU，已被閘道器忽略（不會連線）。',
    if (unlisted > 0) '有 $unlisted 台已連線的 PTU 不在這台閘道器的綁定名單，閘道器會自動斷開。',
    '若其中有這台閘道器要接的 PTU，請勾選它後重新配置。',
  ].join();
}
