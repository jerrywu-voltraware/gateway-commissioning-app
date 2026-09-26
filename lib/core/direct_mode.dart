/// Direct (one-to-one) mode as reported by firmware 1.7.20+: the gateway
/// picks the nearest PTU itself (RSSI threshold, optional MAC binding) and
/// reports `direct:{state, min_rssi, bound_mac, candidates}` in get_status /
/// get_ble_devices / the heartbeat. Older firmware sends none of this; every
/// helper here then returns null / false so the APP keeps its old behaviour.
library;

/// PTU number used for every direct-mode PTU (the firmware ignores the
/// number in direct mode; identity is the distance / bound MAC).
const directPtuId = 1;

/// `auto_connect_min_rssi` range and default (dBm).
const minDirectRssi = -100;
const maxDirectRssi = -20;
const defaultDirectRssi = -55;

/// get_config says the firmware selects the direct PTU by RSSI threshold.
bool directAutoConnectSupported(Map<String, dynamic> config) =>
    config['direct_autoconnect_supported'] == true;

/// get_config says identify can also blink the connected PTU.
bool identifyPtuSupported(Map<String, dynamic> config) =>
    config['identify_ptu_supported'] == true;

/// Saved threshold, clamped; the default when absent or malformed.
int directMinRssiOf(Map<String, dynamic> config) {
  final value = config['auto_connect_min_rssi'];
  if (value is! num) return defaultDirectRssi;
  return value.toInt().clamp(minDirectRssi, maxDirectRssi);
}

/// Bound PTU MAC, or null when unbound (`""` / absent).
String? directBoundMacOf(Map<String, dynamic> source) {
  final value = source['direct_bind_mac'] ?? source['bound_mac'];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

class DirectCandidate {
  const DirectCandidate(this.mac, this.rssiPeak, this.deviceNumber);
  final String mac;
  final int? rssiPeak;
  final int? deviceNumber;

  /// Round 17: 0 (not read yet) is no reading either.
  String get rssiText =>
      rssiPeak == null || rssiPeak! >= 0 ? 'RSSI —' : '峰值 $rssiPeak dBm';
}

/// Round 17: a gateway RSSI as the direct flow shows it — 「-48 dBm」, or
/// 「RSSI —」 for none / 0 (field round 17: 「0 dBm」 right after a connect,
/// before the gateway had read the link's RSSI).
String rssiLabel(Object? rssi) =>
    rssi is num && rssi < 0 && rssi >= -127 ? '$rssi dBm' : 'RSSI —';

enum DirectState {
  connected,
  connecting,
  noCandidate,
  scanning,
  boundMissing;

  /// `off` (star mode) and unknown values are null: nothing to show.
  static DirectState? parse(Object? value) => switch (value) {
    'connected' => DirectState.connected,
    'connecting' => DirectState.connecting,
    'no_candidate' => DirectState.noCandidate,
    'scanning' => DirectState.scanning,
    'bound_missing' => DirectState.boundMissing,
    _ => null,
  };

  /// Round 14: 「已連上同樁 PTU」 claimed more than the gateway knows (an
  /// ambiguous pick is only the strongest); the installer confirms with
  /// 「辨識此樁」.
  String get label => switch (this) {
    DirectState.connected => '已連上 PTU',
    DirectState.connecting => '正在連線 PTU',
    DirectState.noCandidate => '找不到夠近的 PTU',
    DirectState.scanning => '正在尋找最近的 PTU',
    DirectState.boundMissing => '已綁定的 PTU 不在場',
  };

  /// Field guidance; null when nothing needs doing.
  String? get hint => switch (this) {
    DirectState.noCandidate => '請靠近／確認同樁 PTU 已上電',
    DirectState.boundMissing => '已綁定的 PTU 不在場，請確認其電源；若已更換 PTU，請解除綁定',
    _ => null,
  };
}

/// Parsed `direct` object; null for firmware without it (or star mode,
/// `state:"off"`).
class DirectStatus {
  const DirectStatus({
    required this.state,
    this.minRssi,
    this.boundMac,
    this.selectReason = '',
    this.ptuMac,
    this.ptuRssi,
    this.ptuDeviceNumber,
    this.candidates = const [],
  });
  final DirectState state;
  final int? minRssi;
  final String? boundMac;

  /// Latest collection window: `ok` / `ambiguous` / `none` /
  /// `bound_missing`, `""` before the first window (cmd_contract.md §3A).
  /// `connected` + `ambiguous` = the gateway could not tell and took the
  /// strongest — not a clear pick.
  final String selectReason;

  /// The PTU the gateway is connected to (firmware 1.7.20 `ptu_mac`,
  /// `ptu_rssi`, `ptu_device_number`); null while not connected.
  final String? ptuMac;
  final int? ptuRssi;
  final int? ptuDeviceNumber;

  /// At most 5, as the firmware sends them (strongest first).
  final List<DirectCandidate> candidates;

  /// The gateway's own pick: connected and naming the PTU.
  String? get pickedMac =>
      state == DirectState.connected && ptuMac != null ? ptuMac : null;

  /// Signals too close to tell apart: the installer must confirm the pick
  /// with 「辨識此樁」 (not shown for a PTU the gateway is bound to).
  bool get ambiguous =>
      selectReason == 'ambiguous' &&
      !(boundMac != null && ptuMac != null && _same(boundMac!, ptuMac!));

  static bool _same(String a, String b) =>
      a.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '') ==
      b.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

  /// Why the gateway picked [pickedMac], for the installer; null when there
  /// is nothing useful to say.
  ///
  /// Round 17: always the gateway's own `select_reason` (field round 17:
  /// 「門檻內訊號明顯最強」 for a PTU kept after a binding was undone — it
  /// was not the strongest; the reason came from an older window).
  String? get reasonText {
    if (pickedMac == null) return null;
    if (boundMac != null && _same(boundMac!, pickedMac!)) {
      return directReasonText('bound');
    }
    return directReasonText(selectReason);
  }

  static DirectStatus? from(Object? source) {
    if (source is! Map) return null;
    final state = DirectState.parse(source['state']);
    if (state == null) return null;
    final rows = source['candidates'];
    final ptuMac = source['ptu_mac'];
    return DirectStatus(
      state: state,
      minRssi: (source['min_rssi'] as num?)?.toInt(),
      boundMac: directBoundMacOf({'bound_mac': source['bound_mac']}),
      selectReason: source['select_reason']?.toString() ?? '',
      ptuMac: ptuMac is String && ptuMac.trim().isNotEmpty
          ? ptuMac.trim()
          : null,
      ptuRssi: (source['ptu_rssi'] as num?)?.toInt(),
      ptuDeviceNumber: (source['ptu_device_number'] as num?)?.toInt(),
      candidates: [
        if (rows is List)
          for (final row in rows.whereType<Map>().take(5))
            if (row['mac'] != null)
              DirectCandidate(
                row['mac'].toString(),
                (row['rssi_peak'] as num?)?.toInt(),
                (row['device_number'] as num?)?.toInt(),
              ),
      ],
    );
  }
}

/// Round 17: `select_reason` → 「選台依據」 text; null for `""` (no window
/// yet) and unknown values. `bound` is the APP's own key for a pick equal
/// to the bound MAC.
String? directReasonText(String reason) => switch (reason) {
  'ok' => '訊號最強且明確',
  'ambiguous' => '附近訊號相近，閘道器暫選最強的一台',
  'bound' => '已綁定這台，閘道器只連它',
  'resume' => '延續既有連線',
  'none' => '找不到夠近的 PTU',
  'bound_missing' => '已綁定的 PTU 不在場',
  _ => null,
};

/// 「是這台，開始監控」 needs the PTU the installer identified (the MAC of
/// the last identify ack) — whenever the gateway can blink the PTU at all.
/// Firmware that cannot keeps the plain re-read check.
bool directIdentifyRequired(Map<String, dynamic> config) =>
    config['identify_supported'] == true && identifyPtuSupported(config);

/// The six bytes of [mac] as upper-case hex pairs, or null when it is not
/// 12 hex digits.
List<String>? _macBytes(Object? mac) {
  final hex = (mac?.toString() ?? '').toUpperCase().replaceAll(
    RegExp('[^0-9A-F]'),
    '',
  );
  if (hex.length != 12) return null;
  return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)];
}

/// Round 16b: a PTU MAC as the direct flow shows it — upper case, colon
/// separated (「90:5F:E8:9A:96:00」); anything else as given.
String formatMac(Object? mac) =>
    _macBytes(mac)?.join(':') ?? (mac?.toString().trim() ?? '');

/// A MAC as [formatMac] writes it, inside a longer text.
final formattedMacPattern = RegExp(r'(?:[0-9A-F]{2}:){5}[0-9A-F]{2}');

/// Round 16b: the shortest run of whole bytes of [target] that no MAC in
/// [others] has at the same place — what tells it apart from the current
/// candidates when the full MAC does not fit. Ties go to the leftmost run
/// (read order; field round 16: 「5F」「2C」「08」「3B」「74」 for
/// 90:xx:xx:xx:96:00). Left-out bytes are marked 「…」: 「…5F…」,
/// 「…96:00」, 「90:5F…」.
///
/// [others] may contain [target] itself (ignored) and entries that are not
/// MACs (ignored). With nothing to tell apart, the last two bytes; the full
/// MAC when [target] is not one.
String distinguishingMacSegment(Object? target, Iterable<Object?> others) {
  final bytes = _macBytes(target);
  if (bytes == null) return formatMac(target);
  bool same(List<String> a, int from, int to) {
    for (var i = from; i < to; i++) {
      if (a[i] != bytes[i]) return false;
    }
    return true;
  }

  final rest = [
    for (final other in others)
      if (_macBytes(other) case final b? when !same(b, 0, 6)) b,
  ];
  String segment(int from, int to) =>
      '${from > 0 ? '…' : ''}'
      '${bytes.sublist(from, to).join(':')}'
      '${to < 6 ? '…' : ''}';
  if (rest.isEmpty) return segment(4, 6);
  for (var length = 1; length < 6; length++) {
    for (var from = 0; from + length <= 6; from++) {
      if (rest.every((b) => !same(b, from, from + length))) {
        return segment(from, from + length);
      }
    }
  }
  return bytes.join(':');
}

/// [text] with its (first) [formatMac] MAC replaced by
/// [distinguishingMacSegment] against [others]; unchanged without one.
String shortenMacIn(String text, Iterable<Object?> others) {
  final match = formattedMacPattern.firstMatch(text);
  if (match == null) return text;
  return text.replaceRange(
    match.start,
    match.end,
    distinguishingMacSegment(match.group(0), others),
  );
}

/// Step 7 direct flow: 「是這台」 button label until the shown PTU is
/// identified.
const directIdentifyFirstLabel = '請先按「辨識此樁」確認';

/// 「是這台」 pressed without identifying the shown PTU.
const directIdentifyFirstText = '請先按「辨識此樁」確認是眼前這台，再按「是這台，開始監控」。';

/// The gateway now connects a PTU other than the one identified.
String directSwitchedText(Object? mac) =>
    '閘道器已切換到另一顆 PTU（${formatMac(mac)}），請重新辨識';

/// Entering step 7: the gateway is bound to a PTU this APP never confirmed.
String directStrayBindText(Object? mac) => '閘道器目前綁定 PTU ${formatMac(mac)}';

const directStrayBindHint = '這個綁定不是在本機確認過的：保留則閘道器只連這台；解除則恢復自動選最近的 PTU。';

/// 取消 / 結束 could not undo the temporary binding of 「不是這台？」
/// ([mac]); [restore] is the binding it should have gone back to (null:
/// none).
String directUnbindFailedText(Object? mac, [Object? restore]) => restore == null
    ? '已取消，但閘道器的暫時綁定（PTU ${formatMac(mac)}）未能解除；'
          '下次進入第 7 步會再詢問是否解除。'
    : '已取消，但閘道器的暫時綁定（PTU ${formatMac(mac)}）未能還原成原本的'
          '綁定 ${formatMac(restore)}；下次進入第 7 步會再詢問。';

/// Step 7 direct flow: shown when the gateway's pick is ambiguous.
const directAmbiguousText = '附近有訊號相近的 PTU，請按「辨識此樁」確認是否為眼前這台';

/// Beside 「辨識此樁」 right after the tap, before the ack.
const identifySentText = '已送出，請看樁上燈號';

/// Round 16: [identifySentText] as the one-line bottom bar form.
const identifySentLine = '已送出 · 請看樁上燈號';

/// Round 16: the identify ack in one line for the bottom bar — 「已送出 ·
/// 請看樁上燈號 · MAC · RSSI」; [identifyNoteText] is the detail.
/// Round 16b: the full MAC (was 「…後 4 碼」, the same on a whole fleet);
/// the bar shortens it with [shortenMacIn] only when the line does not fit.
String identifyLineText(Map<String, dynamic> ack) {
  final ptuWrite = ack['ptu_write'];
  if (ptuWrite != null && ptuWrite != 'ok') {
    return '已送出 · 只有閘道器閃燈，PTU 未收到';
  }
  final mac = ack['mac'];
  if (mac == null) return '$identifySentLine · 閘道器雙閃 6 秒';
  final rssi = ack['rssi'];
  return [
    identifySentLine,
    formatMac(mac),
    if (rssi is num) rssiLabel(rssi),
  ].join(' · ');
}

/// Beside 「辨識此樁」 once the gateway acked. [ack] is the identify ack.
String identifyNoteText(Map<String, dynamic> ack) {
  final ptuWrite = ack['ptu_write'];
  if (ptuWrite != null && ptuWrite != 'ok') {
    return '已送出：只有閘道器在閃燈，PTU 未收到（$ptuWrite）';
  }
  final mac = ack['mac'];
  if (mac == null) return '$identifySentText（閘道器雙閃 6 秒）';
  final rssi = ack['rssi'];
  return '$identifySentText（PTU ${formatMac(mac)}${rssi is num ? ' · ${rssiLabel(rssi)}' : ''}）';
}

/// Round 17: 「辨識此樁」 while the gateway's link to the PTU it just
/// connected is still being set up (field round 17: an identify 0.9 s
/// after the connect came back `ptu_write:not_connected`, one 2.7 s after
/// it read 0 dBm).
const directSettlingLabel = '連線建立中…';

/// Round 17: the bottom bar's main button while the gateway has no pick
/// (e.g. while it switches to the PTU chosen under 「不是這台？」).
const directWaitingLabel = '等待閘道器連上 PTU';

/// identify on firmware 1.7.20+ when target=ptu itself fails outright
/// (no PTU connected): the APP falls back to blinking the gateway only.
const identifyNoPtuText = '閘道器雙閃 6 秒；閘道器尚未連上 PTU，PTU 不會閃燈。';

/// identify ack → text for the installer, when the PTU write itself
/// succeeded (`ptu_write` absent — bare/gateway-only ack — or `"ok"`).
/// [ptuConfirmed] false means the PTU accepted the write but could not
/// confirm it blinked.
String identifyAckText(Map<String, dynamic> ack) {
  final mac = ack['mac'];
  if (mac == null) return '請找出雙閃藍燈的閘道器，6 秒後會恢復原本燈號。';
  final rssi = ack['rssi'];
  final number = ack['device_number'];
  final seconds = ((ack['duration_ms'] as num?) ?? 6000) / 1000;
  final confirmed = ack['ptu_confirmed'] == true;
  final parts = [
    'PTU $mac',
    if (rssi is num) rssiLabel(rssi),
    if (number is num && number > 0) '#$number',
  ];
  return 'PTU 與閘道器正在閃燈（${confirmed ? 'PTU 已確認閃燈' : 'PTU 燈效需新版 PTU 韌體'}），'
      '閘道器雙閃 ${seconds.toStringAsFixed(0)} 秒（${parts.join(' · ')}）。';
}

/// identify ack (target both, firmware 1.7.20+) with the gateway LED lit
/// but the PTU write itself unsuccessful — `ptu_write` present and not
/// `"ok"` (e.g. `"not_connected"`, or a PTU error code). The firmware still
/// acks `status:ok` here (§ cmd_contract.md identify: "both 只有兩者都失敗才
/// fail"); this is not a failure the APP should resend or treat as a
/// dropped phone↔gateway link.
String identifyPtuFailedText(String reason) => '閘道器正在閃燈；尚未連上 PTU（$reason）。';
