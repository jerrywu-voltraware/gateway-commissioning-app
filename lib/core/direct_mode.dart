/// Direct (one-to-one) mode as reported by firmware 1.7.20+: the gateway
/// picks the nearest PTU itself (RSSI threshold, optional MAC binding) and
/// reports `direct:{state, min_rssi, bound_mac, candidates}` in get_status /
/// get_ble_devices / the heartbeat. Older firmware sends none of this; every
/// helper here then returns null / false so the APP keeps its old behaviour.
library;

import 'identify.dart';

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
  const DirectCandidate(
    this.mac,
    this.rssiPeak,
    this.deviceNumber, {
    this.reason = '',
    this.rssiMed,
  });
  final String mac;
  final int? rssiPeak;
  final int? deviceNumber;

  /// Firmware 1.7.40 `reason` (`ok`／`denied`／`below_threshold_median`…);
  /// `""` from older firmware.
  final String reason;

  /// Firmware 1.7.40 window median (`rssi_med`).
  final int? rssiMed;

  /// Round 17: 0 (not read yet) is no reading either.
  String get rssiText =>
      rssiPeak == null || rssiPeak! >= 0 ? 'RSSI —' : '峰值 $rssiPeak dBm';
}

/// Round 19 (firmware 1.7.27): another PTU the gateway hears while it is
/// connected in direct mode (`direct.neighbors[]`, background scan; the
/// table drops a PTU not heard for 60 s): its advertising peak / latest /
/// median over [samples] readings, last heard [ageS] seconds ago. The
/// calibration uses the peak (the gateway picks by peak).
class DirectNeighbor {
  const DirectNeighbor(
    this.mac, {
    this.rssiMed,
    this.samples,
    this.rssiPeak,
    this.rssiLast,
    this.ageS,
  });
  final String mac;
  final int? rssiMed;
  final int? samples;
  final int? rssiPeak;
  final int? rssiLast;

  /// Seconds since the gateway last heard it.
  final num? ageS;
}

/// Round 17: a gateway RSSI as the direct flow shows it — 「-48 dBm」, or
/// 「RSSI —」 for none / 0 (field round 17: 「0 dBm」 right after a connect,
/// before the gateway had read the link's RSSI).
String rssiLabel(Object? rssi) =>
    rssi is num && rssi < 0 && rssi >= -127 ? '$rssi dBm' : 'RSSI —';

bool _validRssi(Object? rssi) => rssi is num && rssi < 0 && rssi >= -127;

/// Round 28: the pick's signal while the gateway has no link reading yet.
const directRssiReadingText = '訊號讀取中…';

/// Round 28: the pick's advertising RSSI shown meanwhile.
String directAdvRssiText(int rssi) => '廣播 $rssi dBm（連線訊號讀取中）';

/// Round 28 (field round 28: 「RSSI —」 for about 70 s after the gateway
/// connected its pick — `ptu_rssi` stayed 0 until a re-evaluation read
/// it): the signal of the gateway's pick on the step 7 card — the link
/// RSSI once read ([ptuText]: the row's own text for a valid reading),
/// else its advertising RSSI (this pile's `self_adv_rssi_med`, or the peak
/// the selection window heard, `candidates[]`), else
/// [directRssiReadingText]. Never 「0 dBm」 nor a blank.
String directPickRssiText(
  DirectStatus direct, {
  Object? rowRssi,
  String? ptuText,
  bool stale = false,
  int? lastAdv,
}) {
  if (_validRssi(rowRssi) && ptuText != null) return ptuText;
  if (_validRssi(direct.ptuRssi)) return rssiLabel(direct.ptuRssi);
  final adv =
      directPickAdvRssi(direct) ?? (_validRssi(lastAdv) ? lastAdv : null);
  if (adv == null) return directRssiReadingText;
  return stale ? directAdvStaleText(adv) : directAdvRssiText(adv);
}

/// r31: the link RSSI still unread after [directLinkRssiWait]: the last
/// pick / advertising RSSI, marked as such (not 「讀取中」 forever).
String directAdvStaleText(int rssi) => '$rssi dBm（廣播值）';

/// r31: how long 「連線訊號讀取中」 may show before [directAdvStaleText].
const directLinkRssiWait = Duration(seconds: 15);

/// The pick's advertising RSSI in [direct] (`self_adv_rssi_med`, else its
/// selection-window peak), null when none.
int? directPickAdvRssi(DirectStatus direct) {
  final mac = direct.pickedMac;
  if (_validRssi(direct.selfAdvRssiMed)) return direct.selfAdvRssiMed;
  return direct.candidates
      .where(
        (c) =>
            mac != null &&
            DirectStatus._same(c.mac, mac) &&
            _validRssi(c.rssiPeak),
      )
      .firstOrNull
      ?.rssiPeak;
}

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
    this.selfAdvReported = false,
    this.selfAdvRssiMed,
    this.selfAdvAgeS,
    this.neighbors,
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

  /// Round 19 (firmware 1.7.27): `self_adv_rssi_med` was in the report
  /// (null or not) — the firmware can report this pile's advertising
  /// median; [selfAdvRssiMed] is it (null: not heard), [selfAdvAgeS] its
  /// age in seconds.
  final bool selfAdvReported;
  final int? selfAdvRssiMed;
  final num? selfAdvAgeS;

  /// Round 19 (firmware 1.7.27): `neighbors[]`; null when the report has
  /// no such list (older firmware).
  final List<DirectNeighbor>? neighbors;

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
    final near = source['neighbors'];
    final ptuMac = source['ptu_mac'];
    int? whole(Object? value) => value is num ? value.toInt() : null;
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
                whole(row['rssi_peak']),
                whole(row['device_number']),
                reason: row['reason']?.toString() ?? '',
                rssiMed: whole(row['rssi_med']),
              ),
      ],
      selfAdvReported: source.containsKey('self_adv_rssi_med'),
      selfAdvRssiMed: whole(source['self_adv_rssi_med']),
      selfAdvAgeS: source['self_adv_age_s'] is num
          ? source['self_adv_age_s'] as num
          : null,
      neighbors: near is! List
          ? null
          : [
              for (final row in near.whereType<Map>())
                if (row['mac'] != null)
                  DirectNeighbor(
                    row['mac'].toString(),
                    rssiMed: whole(row['rssi_med']),
                    samples: whole(row['samples']),
                    rssiPeak: whole(row['rssi_peak']),
                    rssiLast: whole(row['rssi_last']),
                    ageS: row['age_s'] is num ? row['age_s'] as num : null,
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

/// The direct pick's main button (09-28: 「開始配置」 — binding, joining the
/// fleet and the data check all follow by themselves).
const directConfirmLabel = '是這台，開始配置';

/// 「是這台」 pressed without identifying the shown PTU.
const directIdentifyFirstText = '請先按「辨識此樁」確認是眼前這台，再按「$directConfirmLabel」。';

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
    // 1.0.0+10: 〔更換 PTU〕 left the gateway unbound (no temporary MAC).
    : (mac?.toString() ?? '').isEmpty
    ? '已取消，但閘道器的 PTU 綁定未能還原成原本的 ${formatMac(restore)}；'
          '請重新連線這台閘道器確認綁定。'
    : '已取消，但閘道器的暫時綁定（PTU ${formatMac(mac)}）未能還原成原本的'
          '綁定 ${formatMac(restore)}；下次進入第 7 步會再詢問。';

/// Step 7 direct flow: shown when the gateway's pick is ambiguous.
const directAmbiguousText = '附近有訊號相近的 PTU，請按「辨識此樁」確認是否為眼前這台';

/// Beside 「辨識此樁」 right after the tap, before the ack.
const identifySentText = '已送出，請看樁上燈號';

/// Round 16: [identifySentText] as the one-line bottom bar form.
const identifySentLine = '已送出 · 請看樁上燈號';

/// Round 19: beside 「辨識此樁」 (and in the bottom bar) from the tap until
/// the gateway command ack. PTU a2_seconds has no application reply.
/// Older gateway confirmations remain parseable for compatibility.
const identifyPendingText = '已送出，等待閘道器回應…';

/// Round 19: [identifyPendingText] for firmware that blinks the gateway
/// only (no PTU to wait for).
const identifyPendingGatewayText = '已送出，等待閘道器回應…';

/// Historical firmware 1.7.25..1.7.44 reported PTU confirmation.
/// (`ptu_confirmed`, `ptu_confirm` ok | unsupported_pattern | timeout,
/// `ptu_confirm_ms`); older firmware sends neither (`ptu_confirmed` there
/// is always false): [IdentifyConfirm.legacy], the texts from before.
enum IdentifyConfirm { confirmed, timeout, unsupportedPattern, legacy, sent }

IdentifyConfirm identifyConfirmOf(Map<String, dynamic> ack) {
  if (ack['ptu_reply_expected'] == false ||
      ack['identify_ptu_protocol'] == 'a2_seconds') {
    return IdentifyConfirm.sent;
  }
  if (ack['ptu_confirmed'] == true || ack['ptu_confirm'] == 'ok') {
    return IdentifyConfirm.confirmed;
  }
  return switch (ack['ptu_confirm']) {
    'timeout' => IdentifyConfirm.timeout,
    'unsupported_pattern' => IdentifyConfirm.unsupportedPattern,
    _ => IdentifyConfirm.legacy,
  };
}

/// Round 18: `ptu_confirmed:true`.
const identifyConfirmedText = 'PTU 已確認亮燈';

/// A legacy gateway timeout does not prove the PTU lacks support.
const identifyConfirmTimeoutText = '閘道器已送出；舊版閘道器未取得 PTU 確認，請看樁上燈號';

/// Round 18: `ptu_confirm:"unsupported_pattern"`.
const identifyUnsupportedPatternText = '閘道器已送出；PTU 不支援此燈效，請看樁上燈號';

/// Round 18: the head of the one-line bottom bar form per [IdentifyConfirm].
String _identifyLineHead(Map<String, dynamic> ack) =>
    switch (identifyConfirmOf(ack)) {
      IdentifyConfirm.confirmed => identifyConfirmedText,
      IdentifyConfirm.timeout => '已送出 · PTU 未回應確認 · 請看樁上燈號',
      IdentifyConfirm.unsupportedPattern => '已送出 · PTU 不支援此燈效 · 請看樁上燈號',
      IdentifyConfirm.legacy || IdentifyConfirm.sent => identifySentLine,
    };

/// Round 16: the identify ack in one line for the bottom bar — 「已送出 ·
/// 請看樁上燈號 · MAC · RSSI」; [identifyNoteText] is the detail.
/// Round 16b: the full MAC (was 「…後 4 碼」, the same on a whole fleet);
/// the bar shortens it with [shortenMacIn] only when the line does not fit.
String identifyLineText(Map<String, dynamic> ack) {
  final ptuWrite = ack['ptu_write'];
  if (identifySecondsOf(ack) == 0) {
    return ptuWrite != null && ptuWrite != 'ok'
        ? '閘道器已停止辨識 · PTU 關燈未送出'
        : '已送出關燈指令';
  }
  if (ptuWrite != null && ptuWrite != 'ok') {
    return '已送出 · 只有閘道器閃燈，PTU 未收到';
  }
  final mac = ack['mac'];
  if (mac == null) return '$identifySentLine · ${gatewayIdentifyText(ack)}';
  final rssi = ack['rssi'];
  return [
    _identifyLineHead(ack),
    formatMac(mac),
    if (rssi is num) rssiLabel(rssi),
  ].join(' · ');
}

/// Beside 「辨識此樁」 once the gateway acked. [ack] is the identify ack.
String identifyNoteText(Map<String, dynamic> ack) {
  final ptuWrite = ack['ptu_write'];
  if (identifySecondsOf(ack) == 0) {
    return ptuWrite != null && ptuWrite != 'ok'
        ? '${gatewayIdentifyText(ack)}；PTU 關燈未送出（${ptuWriteReasonText(ptuWrite)}）'
        : '已送出關燈指令；${gatewayIdentifyText(ack)}。PTU 不回覆，請查看燈號。';
  }
  if (ptuWrite != null && ptuWrite != 'ok') {
    return '已送出：只有閘道器在閃燈，PTU 未收到（${ptuWriteReasonText(ptuWrite)}）';
  }
  final mac = ack['mac'];
  if (mac == null) return '$identifySentText（${gatewayIdentifyText(ack)}）';
  final rssi = ack['rssi'];
  final ptu =
      'PTU ${formatMac(mac)}${rssi is num ? ' · ${rssiLabel(rssi)}' : ''}';
  final head = switch (identifyConfirmOf(ack)) {
    IdentifyConfirm.confirmed => identifyConfirmedText,
    IdentifyConfirm.timeout => identifyConfirmTimeoutText,
    IdentifyConfirm.unsupportedPattern => identifyUnsupportedPatternText,
    IdentifyConfirm.legacy || IdentifyConfirm.sent => identifySentText,
  };
  return '$head（$ptu）';
}

/// Round 24: a firmware `ptu_write` reason in words — the raw code
/// (`ambiguous_target`, `not_connected`…) never reaches the screen (field
/// round 24: 「PTU 未收到（ambiguous_target）」).
String ptuWriteReasonText(Object? reason) => switch (reason) {
  'not_connected' => '閘道器尚未連上 PTU',
  'ambiguous_target' => '閘道器連著多台 PTU，沒有指定哪一台',
  'write_failed' => '閘道器寫入 PTU 失敗',
  _ => 'PTU 沒有收到指令',
};

/// Round 19: the result of an identify ack in a few words (「PTU 已確認亮燈」,
/// 「PTU 未回應確認」…); null when the ack says nothing about the PTU.
/// Round 24: a PTU that was not written reads 「只有閘道器閃燈」 with the
/// reason in words ([ptuWriteReasonText]).
String? identifyResultText(Map<String, dynamic> ack) {
  final ptuWrite = ack['ptu_write'];
  if (ptuWrite != null && ptuWrite != 'ok') {
    return '只有閘道器閃燈（${ptuWriteReasonText(ptuWrite)}）';
  }
  return switch (identifyConfirmOf(ack)) {
    IdentifyConfirm.confirmed => identifyConfirmedText,
    IdentifyConfirm.timeout => '舊版閘道器未取得 PTU 確認',
    IdentifyConfirm.unsupportedPattern => 'PTU 不支援此燈效',
    IdentifyConfirm.legacy || IdentifyConfirm.sent =>
      ptuWrite == 'ok'
          ? (identifySecondsOf(ack) == 0 ? 'PTU 關燈指令已送出' : 'PTU 辨識指令已送出')
          : null,
  };
}

/// Round 24: the identify ack says a PTU was written — `ptu_write:"ok"`, a
/// PTU confirmation, or (no `ptu_write` at all) the PTU's MAC. Otherwise
/// only the gateway blinked (`ptu_write` not ok, or a gateway-only ack).
bool identifyWrotePtu(Map<String, dynamic> ack) {
  final ptuWrite = ack['ptu_write'];
  if (ptuWrite != null) return ptuWrite == 'ok';
  return ack.containsKey('ptu_confirm') ||
      ack.containsKey('ptu_confirmed') ||
      ack['mac'] != null;
}

/// Round 24: the PTU an identify ack names, as the installer can find it:
/// 「#3」 (the ack's `device_number`, else the number of the listed PTU
/// with that MAC), else the part of its MAC that tells it apart from the
/// other listed PTUs ([distinguishingMacSegment]; the whole MAC when no
/// other PTU is listed). Null when the ack names no PTU.
String? identifyPtuLabel(
  Map<String, dynamic> ack, {
  List<Map<String, dynamic>> ptus = const [],
}) {
  int? valid(Object? n) =>
      n is num && n.toInt() >= 1 && n.toInt() <= 250 ? n.toInt() : null;
  final number = valid(ack['device_number']);
  if (number != null) return '#$number';
  final mac = ack['mac'];
  final bytes = _macBytes(mac);
  if (mac == null) return null;
  if (bytes == null) return formatMac(mac);
  final key = bytes.join();
  for (final p in ptus) {
    if (_macBytes(p['mac'])?.join() == key) {
      final listed = valid(p['device_number']);
      if (listed != null) return '#$listed';
    }
  }
  final others = [
    for (final p in ptus)
      if (_macBytes(p['mac']) case final b? when b.join() != key) p['mac'],
  ];
  return others.isEmpty
      ? formatMac(mac)
      : distinguishingMacSegment(mac, others);
}

/// Round 24: [remoteIdentifyText] when only the gateway blinked.
const remoteIdentifyGatewayText = '後台讓閘道器閃燈（請看閘道器上的燈）';

/// Round 19: an identify ack the gateway relayed to the phone that answers
/// no request of this APP — the back office made the pile blink (backend
/// D5, allowed during commissioning). Only [ack] results shaped like an
/// identify ack (`ptu_write` / `ptu_confirm` / `ptu_confirmed` /
/// `gateway_led`) count.
bool isIdentifyAck(Map<String, dynamic> ack) =>
    ack.containsKey('ptu_write') ||
    ack.containsKey('ptu_confirm') ||
    ack.containsKey('ptu_confirmed') ||
    ack.containsKey('gateway_led');

/// Round 19: the non-blocking notice for [isIdentifyAck] acks the back
/// office sent.
///
/// Round 24 (field round 24: in star mode the back office's identify came
/// back `ptu_write:"ambiguous_target"` — only the gateway blinked — and the
/// notice read 「後台剛讓這台樁閃燈（請看樁上燈號） · 只有閘道器閃燈，PTU 未
/// 收到（ambiguous_target）」): what actually blinked, in words.
/// - No PTU written ([identifyWrotePtu] false): [remoteIdentifyGatewayText].
/// - A PTU written: 「後台讓 PTU #3 閃燈（請看樁上燈號）」 — its number, or
///   the distinguishing part of its MAC among [ptus] ([identifyPtuLabel]) —
///   then its confirmation as before (「PTU 已確認亮燈」／「PTU 未回應確認
///   （PTU 韌體尚未支援）」…) and its RSSI.
String remoteIdentifyText(
  Map<String, dynamic> ack, {
  List<Map<String, dynamic>> ptus = const [],
}) {
  if (identifySecondsOf(ack) == 0) {
    return identifyWrotePtu(ack)
        ? '後台已送出 PTU 關燈指令；${gatewayIdentifyText(ack)}'
        : '後台：${gatewayIdentifyText(ack)}；PTU 關燈未送出';
  }
  if (!identifyWrotePtu(ack)) return remoteIdentifyGatewayText;
  final label = identifyPtuLabel(ack, ptus: ptus);
  final rssi = ack['rssi'];
  return [
    '後台已送出 PTU${label == null ? '' : ' $label'} 辨識指令（請看樁上燈號）',
    ?identifyResultText(ack),
    if (rssi is num && rssi < 0) rssiLabel(rssi),
  ].join(' · ');
}

/// Round 21 (field round 21: the bar's one line was cut after
/// 「後台剛讓這台樁閃燈（請看樁上燈…」 — the PTU's answer, MAC and RSSI
/// behind the chevron): the notice's short first sentence, 「後台已讓此樁
/// 閃燈 · PTU 未回應確認」 (or 已確認…). At most [remoteIdentifyHeadMax]
/// characters, so it fits one line of a 360 dp bar at text scale 1 and two
/// at 1.3. [remoteIdentifyText] stays the full text (details, snack bar).
String remoteIdentifyHeadText(Map<String, dynamic> ack) {
  if (identifySecondsOf(ack) == 0) {
    return identifyWrotePtu(ack) ? '後台已送出關燈指令' : '後台已停止閘道器辨識';
  }
  final ptuWrite = ack['ptu_write'];
  if (ptuWrite != null && ptuWrite != 'ok') return remoteIdentifyHeads[4];
  return switch (identifyConfirmOf(ack)) {
    IdentifyConfirm.confirmed => remoteIdentifyHeads[0],
    IdentifyConfirm.timeout => remoteIdentifyHeads[1],
    IdentifyConfirm.unsupportedPattern => remoteIdentifyHeads[2],
    IdentifyConfirm.legacy || IdentifyConfirm.sent =>
      ptuWrite == 'ok' ? remoteIdentifyHeads[3] : remoteIdentifyHeads[5],
  };
}

/// Round 21: every [remoteIdentifyHeadText] (the direct bar sizes its
/// identify line for the longest).
const remoteIdentifyHeads = [
  '後台已讓此樁閃燈 · PTU 已確認',
  '後台已送出 · 舊版未取得確認',
  '後台已送出 · PTU 不支援燈效',
  '後台已送出 PTU 辨識指令',
  '後台已讓閘道器閃燈 · PTU 未收到',
  '後台已送出 · 請查看燈號',
  '後台已送出關燈指令',
  '後台已停止閘道器辨識',
];

/// Round 21: longest [remoteIdentifyHeads] entry, in characters.
const remoteIdentifyHeadMax = 20;

/// Round 21: the notice's second line — the PTU's MAC and RSSI (「PTU
/// 90:5F:E8:9A:96:00 · -46 dBm」); empty when the ack names neither.
String remoteIdentifyPtuText(Map<String, dynamic> ack) {
  final mac = ack['mac'];
  final rssi = ack['rssi'];
  return [
    if (mac != null) 'PTU ${formatMac(mac)}',
    if (rssi is num) rssiLabel(rssi),
  ].join(' · ');
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
/// Older firmware (no `ptu_confirm`): the PTU accepted the write but could
/// not confirm it blinked. Round 18: firmware 1.7.25+ says so
/// ([identifyConfirmOf]).
String identifyAckText(Map<String, dynamic> ack) {
  final note = identifyNoteText(ack);
  if (ack['mac'] == null || identifySecondsOf(ack) == 0) return note;
  final number = ack['device_number'];
  return '$note${number is num ? '（#$number）' : ''}；${gatewayIdentifyText(ack)}。';
}

/// identify ack (target both, firmware 1.7.20+) with the gateway LED lit
/// but the PTU write itself unsuccessful — `ptu_write` present and not
/// `"ok"` (e.g. `"not_connected"`, or a PTU error code). The firmware still
/// acks `status:ok` here (§ cmd_contract.md identify: "both 只有兩者都失敗才
/// fail"); this is not a failure the APP should resend or treat as a
/// dropped phone↔gateway link.
///
/// Round 24: [reason] in words ([ptuWriteReasonText]), never the raw code.
String identifyPtuFailedText(String reason, {int seconds = 6}) => seconds == 0
    ? '閘道器已停止辨識；PTU 關燈未送出（${ptuWriteReasonText(reason)}）。'
    : '閘道器正在閃燈（$seconds 秒）；PTU 指令未送出（${ptuWriteReasonText(reason)}）。';
