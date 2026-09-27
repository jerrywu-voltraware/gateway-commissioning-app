/// Round 18 「校正門檻」 (direct mode, firmware 1.7.20+): with the piles set
/// up as they will stay, the APP reads `get_status.direct` for
/// [directCalibrationDuration] and compares this pile's confirmed PTU with
/// the strongest neighbour the gateway heard, then suggests an
/// `auto_connect_min_rssi` the installer writes back to the gateway
/// (set_config, kept in its flash; cmd_contract.md §3A).
///
/// Round 19 (field round 19: this pile's link-RSSI median against a
/// neighbour's advertising peak judged 「太接近」 where a threshold could
/// still work): the threshold is checked against how the firmware uses it
/// (`main/ble/direct_pick.c`):
///   (a) pick: a PTU's advertising *peak* in the 3 s window ≥ threshold;
///   (b) `ambiguous`: best and runner-up peaks < 6 dB apart (independent
///       of the threshold);
///   (c) drop: the connected link's RSSI median < threshold − 3.
/// So the threshold must lie in [lower, upper]:
///   upper = min(this pile's advertising median `self_adv_rssi_med`,
///               this pile's weakest link reading + 3) — it is picked and
///               not dropped once connected;
///   lower = the strongest neighbour's peak + 1 — with this pile's PTU off
///               the gateway never takes a neighbour.
/// Firmware before 1.7.27 has no `self_adv_rssi_med` / `neighbors`: upper
/// from the link readings only, neighbours from the last selection window
/// (`candidates`) — a reference value.
///
/// Round 20 (field round 20: `self_adv_age_s` 249–274 s at calibration):
/// `self_adv_rssi_med` is measured while the gateway selects and frozen
/// once it is connected. The sheet says how old it is (「本樁廣播值來自 N
/// 分鐘前選台」); older than [calibrationSelfAdvMaxAge] s or without an age
/// it no longer bounds the threshold — upper from the link readings only,
/// a reference value. Neighbours within [calibrationNeighborTieDb] of the
/// strongest are named together (at most [calibrationNeighborTieMax], in
/// MAC order) — two at -46 dBm were named in list order, so the named pile
/// flipped between runs.
///
/// Round 28 (field round 28: pile A's calibration heard no neighbour and
/// suggested -61 dBm — upper − 10 — exactly the peak pile A's PTU reached
/// at pile B's gateway; a connected PTU does not advertise, so the
/// neighbours are almost never heard and every calibration loosened the
/// threshold by about 10 dB): without neighbour data nothing shows that a
/// wider threshold is safe, so the suggestion is never wider than the
/// gateway's current threshold (or the default -55 dBm) — it holds it
/// ([DirectThresholdVerdict.noNeighbors]). With neighbour data the three
/// firmware rules above still decide.
library;

import 'dart:math' as math;

import 'direct_mode.dart';

/// Sampling length and read interval (tests shorten them).
Duration directCalibrationDuration = const Duration(seconds: 20);
Duration directCalibrationInterval = const Duration(milliseconds: 1500);

/// Firmware `DIRECT_DROP_HYST_DB`: a connected PTU is dropped only when
/// its link median falls this far under the threshold.
const calibrationDropHysteresis = 3;

/// The threshold stays this far above the strongest neighbour's peak (a
/// peak equal to the threshold is picked).
const calibrationNeighborMargin = 1;

/// [DirectThresholdSuggestion.upper] − [DirectThresholdSuggestion.lower]
/// under this: no threshold to recommend.
const calibrationMinRange = 2;

/// This pile's upper bound minus the strongest neighbour's peak it takes.
const calibrationMinGap = calibrationMinRange + calibrationNeighborMargin;

/// Firmware `DIRECT_PICK_AMBIGUOUS_DB`: best and runner-up peaks closer
/// than this make a pick `ambiguous`.
const calibrationAmbiguousDb = 6;

/// Round 28: without neighbour data the suggestion holds the gateway's
/// current threshold (never wider); `min_rssi` not reported: this.
const calibrationHoldDefault = defaultDirectRssi;

/// Fewer readings (`samples`) than this still count toward
/// [DirectThresholdSuggestion.lower] (round 19 fix: the bound must stay
/// conservative even off a single reading) — only the rescan hint
/// ([calibrationFewSamplesText]) is shown.
const calibrationMinNeighborSamples = 3;

/// …heard within this many seconds (`age_s`); older: 「重新掃描鄰近」.
const calibrationNeighborMaxAge = 60;

/// Round 20: `self_adv_age_s` over this (seconds), or none: this pile's
/// advertising median no longer bounds the threshold (a reference value).
const calibrationSelfAdvMaxAge = 900;

/// Round 20: neighbours whose peak is within this of the strongest are
/// named together…
const calibrationNeighborTieDb = 1;

/// …at most this many.
const calibrationNeighborTieMax = 3;

const calibrationTitle = '校正門檻';

/// Signals too close for any threshold (yellow).
const calibrationTooCloseText = '鄰近樁訊號太強，無法只靠門檻區分，請在確認後綁定此 PTU';

/// Round 19 fix: [DirectThresholdVerdict.tooClose] only because the
/// gateway's -100…-20 write range clamped the natural midpoint outside
/// [DirectThresholdSuggestion.lower] / [DirectThresholdSuggestion.upper]
/// — the gap wording ([calibrationGapText]) would contradict itself here
/// (e.g. a 16 dB gap called 「餘裕不足」).
const calibrationOutOfRangeText = '本樁讀數已超出閘道器可用範圍（-100～-20 dBm），請重新取樣';

/// This pile's advertising and the strongest neighbour's peak are closer
/// than [calibrationAmbiguousDb] (firmware 1.7.27 only).
const calibrationAmbiguousText =
    '本樁與鄰近樁的廣播訊號相差不到 $calibrationAmbiguousDb dB：'
    '選台時可能判為不確定，綁定後就不受影響。';

/// The written threshold was read back from the gateway.
const calibrationSavedText = '已寫入閘道器（重開機仍保留）';

const calibrationNoOwnText =
    '未取得本樁 PTU 的連線訊號（閘道器目前沒有連著已確認的 PTU），無法建議門檻。'
    '請確認本樁 PTU 已連上後重新取樣。';

/// Round 28: no neighbour heard — the threshold is held at [hold] dBm.
String calibrationNoNeighborText(int hold) =>
    '未偵測到鄰近 PTU（已連線的 PTU 不會廣播），無法確認放寬是否安全，'
    '建議維持 $hold dBm。';

/// Round 28: no neighbour heard and this pile's own signal is under the
/// held threshold's reach ([upper] dBm): still not loosened.
String calibrationOwnBelowHoldText(int upper, int hold) =>
    '本樁 PTU 訊號偏弱（可用上限 $upper dBm，低於門檻 $hold dBm），'
    '但沒有鄰近資料不能放寬門檻：請確認已開啟「確認後綁定 PTU」（綁定後不受門檻影響），'
    '或調整 PTU 擺放後重新取樣。';

/// Round 28: the write button when the suggestion is the gateway's
/// current threshold.
String calibrationHoldLabel(int hold) => '維持目前門檻（$hold dBm），不需寫入';

/// No confirmed PTU yet: where to get one.
const calibrationNeedsOwnText = '請先在第 7 步按「辨識此樁」確認本樁 PTU，再校正門檻。';

/// Round 19: the resample button while neighbour data is stale.
const calibrationRescanLabel = '重新掃描鄰近';

/// Round 19: a suggestion not built on firmware 1.7.27's fields.
const calibrationReferenceLegacyText = '參考值（閘道器韌體較舊）';
const calibrationReferenceNoAdvText = '參考值（閘道器未回報本樁廣播訊號）';

/// Round 20: this pile's advertising median too old / without an age.
const calibrationReferenceStaleAdvText =
    '參考值（本樁廣播值超過 ${calibrationSelfAdvMaxAge ~/ 60} 分鐘，上限只用連線訊號）';
const calibrationReferenceUndatedAdvText = '參考值（本樁廣播值未附選台時間，上限只用連線訊號）';

/// Round 20: how old this pile's advertising median is ([ageS]:
/// `self_adv_age_s`, null when not reported) — measured while the gateway
/// selected, frozen once connected.
String calibrationSelfAdvAgeText(num? ageS) {
  if (ageS == null) return '本樁廣播值未附選台時間';
  if (ageS < 60) return '本樁廣播值來自 ${ageS.round()} 秒前選台';
  return '本樁廣播值來自 ${ageS ~/ 60} 分鐘前選台';
}

/// Round 20: the neighbours named in [calibrationGapText] — each MAC
/// segment kept on one line ([noBreak]), joined by 「、」; [total] ties
/// beyond the ones named: 「等 N 台」.
String calibrationNeighborLabel(List<String> segments, {int? total}) {
  final named = segments.map(noBreak).join('、');
  return total != null && total > segments.length ? '$named 等 $total 台' : named;
}

/// Round 19: [value] dBm that never breaks between the number and 「dBm」.
String dbm(int value) => '$value\u00A0dBm';

/// Round 19: [text] kept on one line (a word joiner between every
/// character; field round 19: 「）」 wrapped onto a line of its own).
String noBreak(String text) => text.split('').join('\u2060');

/// Round 19: the too-close comparison in the installer's words — [gap] is
/// this pile's upper bound minus the strongest neighbour's peak
/// ([DirectThresholdSuggestion.gap]), [neighbor] that neighbour's MAC
/// segment (round 20: the tied neighbours, [calibrationNeighborLabel]).
String calibrationGapText(int gap, String neighbor) {
  final who = '鄰近樁 $neighbor ';
  if (gap < 0) return '$who比本樁還強 ${-gap} dB';
  if (gap == 0) return '$who和本樁一樣強';
  return '$who只比本樁弱 $gap dB，餘裕不足（至少要弱 $calibrationMinGap dB）';
}

/// Round 19 fix: the too-close reason in the installer's words — the gap
/// wording ([calibrationGapText]) only when the margin itself is what's
/// too small; the -100…-20 write-range clamp can also force
/// [DirectThresholdVerdict.tooClose] with a perfectly good gap
/// ([DirectThresholdSuggestion.outOfRange]), which needs its own,
/// non-contradictory wording instead.
String calibrationTooCloseReason(
  DirectThresholdSuggestion suggestion,
  String neighbor,
) => suggestion.outOfRange
    ? calibrationOutOfRangeText
    : calibrationGapText(suggestion.gap!, neighbor);

/// Round 19: neighbours left out for being heard too long ago ([ageS]: the
/// oldest, seconds).
String calibrationStaleText(int ageS) =>
    '鄰近資料已 $ageS 秒未更新（超過 $calibrationNeighborMaxAge 秒，未列入計算），'
    '請按「$calibrationRescanLabel」再取樣一次。';

/// Round 19 fix: neighbours counted toward the lower bound despite too
/// few readings — a rescan hint, not an exclusion (excluding them here
/// used to let the suggestion come out under that neighbour's own peak).
String calibrationFewSamplesText(int count) =>
    '有 $count 台鄰近 PTU 讀數較少（不足 $calibrationMinNeighborSamples 筆），'
    '已計入下限但可能不穩定，請按「$calibrationRescanLabel」再取樣一次。';

enum DirectThresholdVerdict {
  /// Midpoint of [DirectThresholdSuggestion.lower] and
  /// [DirectThresholdSuggestion.upper].
  suggested,

  /// No neighbour counted. Round 28: the gateway's current threshold
  /// held — never wider without neighbour data (was upper − 10 dB).
  noNeighbors,

  /// No suggestion: upper − lower under [calibrationMinRange], or the
  /// -100…-20 write range clamped the midpoint outside
  /// [DirectThresholdSuggestion.lower] / [DirectThresholdSuggestion.upper]
  /// ([DirectThresholdSuggestion.outOfRange] — the gap itself may be
  /// fine then).
  tooClose,

  /// No link reading of this pile's PTU: no suggestion.
  noOwnSignal,
}

/// [suggestDirectThreshold]'s answer: the figures shown and the threshold
/// suggested (null for [DirectThresholdVerdict.tooClose] /
/// [DirectThresholdVerdict.noOwnSignal]).
class DirectThresholdSuggestion {
  const DirectThresholdSuggestion({
    required this.verdict,
    this.ownLinkMedian,
    this.ownLinkWeakest,
    this.ownLinkCount = 0,
    this.ownAdvertising,
    this.neighborStrongest,
    this.upper,
    this.lower,
    this.threshold,
    this.outOfRange = false,
  });

  final DirectThresholdVerdict verdict;

  /// This pile's link readings.
  final int? ownLinkMedian;
  final int? ownLinkWeakest;
  final int ownLinkCount;

  /// This pile's advertising median (firmware 1.7.27), if reported.
  final int? ownAdvertising;

  /// The strongest counted neighbour's advertising peak.
  final int? neighborStrongest;

  /// The highest threshold that keeps this pile (picked, not dropped) and
  /// the lowest that keeps every counted neighbour out.
  final int? upper;
  final int? lower;
  final int? threshold;

  /// [verdict] is [DirectThresholdVerdict.tooClose] only because the
  /// gateway's -100…-20 write range clamped the natural midpoint outside
  /// [lower] / [upper] — not because the margin ([gap]) was itself too
  /// small, so [calibrationGapText] would not fit
  /// ([calibrationTooCloseReason] picks the right wording).
  final bool outOfRange;

  /// [upper] minus the strongest neighbour's peak.
  int? get gap => upper == null || neighborStrongest == null
      ? null
      : upper! - neighborStrongest!;

  /// Round 28: [DirectThresholdVerdict.noNeighbors] with this pile's upper
  /// bound under the held threshold — its own signal is weak for it, and
  /// without neighbour data the threshold is not loosened either
  /// ([calibrationOwnBelowHoldText]).
  bool get ownBelowHold =>
      verdict == DirectThresholdVerdict.noNeighbors &&
      upper != null &&
      threshold != null &&
      upper! < threshold!;

  /// Firmware 1.7.27: this pile's advertising within
  /// [calibrationAmbiguousDb] of the strongest neighbour's peak — the pick
  /// may come out `ambiguous` (a binding is not affected).
  bool get mayBeAmbiguous =>
      ownAdvertising != null &&
      neighborStrongest != null &&
      ownAdvertising! - neighborStrongest! < calibrationAmbiguousDb;
}

/// A gateway RSSI reading: negative and not below -127 (0 = not read yet).
bool validRssi(Object? rssi) => rssi is num && rssi < 0 && rssi >= -127;

/// The median of [values] (not empty), the middle two rounded down.
int _median(List<int> values) {
  final sorted = List.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : ((sorted[middle - 1] + sorted[middle]) / 2).floor();
}

/// Suggested `auto_connect_min_rssi` (library doc: the firmware's pick /
/// ambiguous / drop rules) from this pile's link readings [ownLink] (dBm),
/// its advertising median [ownAdvertising] (firmware 1.7.27; null on older
/// firmware) and the counted neighbours' advertising peaks
/// [neighborPeaks] (the strongest decides). Invalid readings are ignored.
///
/// - upper = min([ownAdvertising], weakest link reading + 3);
///   lower = strongest neighbour peak + 1.
/// - upper − lower ≥ [calibrationMinRange]: their midpoint, rounded down.
///   Otherwise [DirectThresholdVerdict.tooClose], no suggestion.
/// - No neighbour (round 28): the gateway's [current] threshold (null:
///   [calibrationHoldDefault]) held — never wider, since nothing shows a
///   wider one is safe (a connected PTU does not advertise).
/// - No link reading: [DirectThresholdVerdict.noOwnSignal].
/// - Always within the gateway's -100…-20 (a clamp that leaves
///   [lower, upper]: [DirectThresholdVerdict.tooClose] with
///   [DirectThresholdSuggestion.outOfRange] — the gap itself may be
///   fine).
DirectThresholdSuggestion suggestDirectThreshold({
  required Iterable<int> ownLink,
  int? ownAdvertising,
  required Iterable<int> neighborPeaks,
  int? current,
}) {
  final link = [
    for (final r in ownLink)
      if (validRssi(r)) r,
  ]..sort();
  final adv = validRssi(ownAdvertising) ? ownAdvertising : null;
  final others = [
    for (final r in neighborPeaks)
      if (validRssi(r)) r,
  ];
  final strongest = others.isEmpty ? null : others.reduce(math.max);
  if (link.isEmpty) {
    return DirectThresholdSuggestion(
      verdict: DirectThresholdVerdict.noOwnSignal,
      ownAdvertising: adv,
      neighborStrongest: strongest,
    );
  }
  final weakest = link.first;
  final byLink = weakest + calibrationDropHysteresis;
  final upper = adv == null ? byLink : math.min(adv, byLink);
  final lower = strongest == null
      ? null
      : strongest + calibrationNeighborMargin;
  DirectThresholdSuggestion result(
    DirectThresholdVerdict verdict, [
    int? t,
    bool outOfRange = false,
  ]) => DirectThresholdSuggestion(
    verdict: verdict,
    ownLinkMedian: _median(link),
    ownLinkWeakest: weakest,
    ownLinkCount: link.length,
    ownAdvertising: adv,
    neighborStrongest: strongest,
    upper: upper,
    lower: lower,
    threshold: t,
    outOfRange: outOfRange,
  );
  if (lower == null) {
    // Round 28: hold, never wider (field: upper − 10 gave -61 dBm, the
    // peak pile A's PTU reached at pile B's gateway).
    return result(
      DirectThresholdVerdict.noNeighbors,
      (current ?? calibrationHoldDefault).clamp(minDirectRssi, maxDirectRssi),
    );
  }
  if (upper - lower < calibrationMinRange) {
    return result(DirectThresholdVerdict.tooClose);
  }
  final threshold = ((upper + lower) / 2).floor().clamp(
    minDirectRssi,
    maxDirectRssi,
  );
  // Only the -100…-20 clamp can leave the range (signals near -20 dBm) —
  // the gap itself can still be fine, so this gets its own outOfRange
  // flag rather than the (otherwise self-contradictory) gap wording.
  if (threshold > upper || threshold < lower) {
    return result(DirectThresholdVerdict.tooClose, null, true);
  }
  return result(DirectThresholdVerdict.suggested, threshold);
}

String _key(Object? mac) =>
    (mac?.toString() ?? '').toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

/// Round 19: what a calibration is built on ([DirectCalibrationSamples.basis]).
enum CalibrationBasis {
  /// Firmware 1.7.27: this pile's advertising median and link readings,
  /// the neighbours from `neighbors[]` (heard while connected).
  current,

  /// Firmware 1.7.27 that did not report this pile's advertising median:
  /// upper from the link readings only (a reference value).
  noOwnAdvertising,

  /// Firmware without the fields: upper from the link readings only, the
  /// neighbours from the last selection window (a reference value).
  legacy,

  /// Round 20: this pile's advertising median older than
  /// [calibrationSelfAdvMaxAge] s (frozen since the gateway selected):
  /// upper from the link readings only (a reference value).
  staleOwnAdvertising,

  /// Round 20: this pile's advertising median without `self_adv_age_s`:
  /// upper from the link readings only (a reference value).
  undatedOwnAdvertising;

  /// Not built on everything the firmware's rules use: [referenceText].
  bool get reference => this != current;

  /// Round 20: this pile's advertising median was read but is not used.
  bool get ownAdvertisingSkipped =>
      this == staleOwnAdvertising || this == undatedOwnAdvertising;

  String? get referenceText => switch (this) {
    current => null,
    noOwnAdvertising => calibrationReferenceNoAdvText,
    legacy => calibrationReferenceLegacyText,
    staleOwnAdvertising => calibrationReferenceStaleAdvText,
    undatedOwnAdvertising => calibrationReferenceUndatedAdvText,
  };
}

/// One neighbour over the sampling: its strongest peak and its latest
/// `samples` / `age_s` (null: not reported — `candidates` carry neither).
class _Neighbor {
  _Neighbor(this.mac);
  final String mac;
  int? peak;
  int? samples;
  num? ageS;

  void take(int? rssiPeak, {int? samples, num? ageS}) {
    if (validRssi(rssiPeak)) {
      peak = peak == null ? rssiPeak : math.max(peak!, rssiPeak!);
    }
    this.samples = samples;
    this.ageS = ageS;
  }

  bool get stale => ageS != null && ageS! > calibrationNeighborMaxAge;
  bool get fewSamples =>
      samples != null && samples! < calibrationMinNeighborSamples;

  /// Counted: a peak, heard recently enough. Round 19 fix: `samples` no
  /// longer excludes a neighbour here — the lower bound must stay
  /// conservative even off a single reading (excluding a thin-but-strong
  /// neighbour let the suggested threshold come out under that
  /// neighbour's own peak, so this pile could pick it up while off).
  bool get counts => peak != null && !stale;
}

/// What the calibration has read so far for the PTU [ownMac].
///
/// Round 19: this pile's link readings and, firmware 1.7.27, its
/// advertising medians (`self_adv_rssi_med`); the neighbours from
/// `neighbors[]` (firmware 1.7.27, kept up to date while connected;
/// heard within [calibrationNeighborMaxAge] s count regardless of
/// `samples`, by their latest listing — round 19 fix, the lower bound
/// must stay conservative even off a single reading; fewer than
/// [calibrationMinNeighborSamples] only adds a rescan hint) or else
/// `candidates[]` (the last selection window), each by its advertising
/// peak.
class DirectCalibrationSamples {
  DirectCalibrationSamples(this.ownMac);

  /// This pile's confirmed PTU.
  final String ownMac;

  /// Link RSSI of [ownMac] (only while the gateway reports it connected).
  final ownLink = <int>[];

  /// Round 19: `self_adv_rssi_med` of [ownMac] (only while the gateway
  /// reports it connected to [ownMac]).
  final ownAdvertisingReads = <int>[];

  /// Round 20: `self_adv_age_s` of the latest [ownAdvertisingReads] entry
  /// (null: not reported).
  num? ownAdvertisingAgeS;

  /// Round 19: a read connected to [ownMac] carried `self_adv_rssi_med`
  /// (even null) / a read carried `neighbors`.
  bool selfAdvReported = false;
  bool neighborsReported = false;

  final _neighbors = <String, _Neighbor>{};

  /// get_status reads made / that failed or carried no `direct`.
  int reads = 0;
  int missed = 0;

  /// Round 28: the gateway's threshold (`direct.min_rssi`, latest read);
  /// null until reported — [suggestion] holds it without neighbour data.
  int? gatewayThreshold;

  /// Time sampled so far; [done] once [directCalibrationDuration] passed.
  Duration elapsed = Duration.zero;
  bool done = false;

  _Neighbor _neighbor(String mac) =>
      _neighbors.putIfAbsent(_key(mac), () => _Neighbor(mac));

  /// Takes one `get_status.direct` object (null / malformed: a missed read).
  void add(Object? direct) {
    reads++;
    final status = DirectStatus.from(direct);
    if (status == null) {
      missed++;
      return;
    }
    if (status.minRssi != null) gatewayThreshold = status.minRssi;
    final linked = status.pickedMac;
    final mine = linked != null && _key(linked) == _key(ownMac);
    if (mine && validRssi(status.ptuRssi)) ownLink.add(status.ptuRssi!);
    if (mine && status.selfAdvReported) {
      selfAdvReported = true;
      if (validRssi(status.selfAdvRssiMed)) {
        ownAdvertisingReads.add(status.selfAdvRssiMed!);
        ownAdvertisingAgeS = status.selfAdvAgeS;
      }
    }
    final near = status.neighbors;
    if (near != null) {
      // The last selection window's candidates no longer count.
      if (!neighborsReported) _neighbors.clear();
      neighborsReported = true;
      for (final n in near) {
        if (_key(n.mac) == _key(ownMac)) continue;
        _neighbor(n.mac).take(n.rssiPeak, samples: n.samples, ageS: n.ageS);
      }
    } else if (!neighborsReported) {
      for (final c in status.candidates) {
        if (_key(c.mac) == _key(ownMac)) continue;
        _neighbor(c.mac).take(c.rssiPeak);
      }
    }
  }

  /// A read that failed outright.
  void miss() {
    reads++;
    missed++;
  }

  /// This pile's advertising median over the sampling (the median of the
  /// medians read), or null. Shown as read; the threshold uses
  /// [usableOwnAdvertising].
  int? get ownAdvertising =>
      ownAdvertisingReads.isEmpty ? null : _median(ownAdvertisingReads);

  /// Round 20: [ownAdvertising] only while it is recent enough to bound
  /// the threshold ([CalibrationBasis.current]).
  int? get usableOwnAdvertising =>
      basis == CalibrationBasis.current ? ownAdvertising : null;

  /// The counted neighbours' peaks (MAC → dBm).
  Map<String, int> get neighbors => {
    for (final n in _neighbors.values)
      if (n.counts) n.mac: n.peak!,
  };

  /// Counted neighbours, strongest first; equal peaks in MAC order.
  List<MapEntry<String, int>> get _byStrength =>
      neighbors.entries.toList()..sort((a, b) {
        final byPeak = b.value.compareTo(a.value);
        return byPeak != 0 ? byPeak : _key(a.key).compareTo(_key(b.key));
      });

  /// MAC of the strongest counted neighbour, if any (equal peaks: the
  /// lowest MAC, the same one every run).
  String? get strongestNeighborMac => _byStrength.firstOrNull?.key;

  /// Round 20: how many counted neighbours are within
  /// [calibrationNeighborTieDb] of the strongest peak (itself included).
  int get strongestNeighborTies {
    final order = _byStrength;
    if (order.isEmpty) return 0;
    final top = order.first.value;
    return order.where((e) => e.value >= top - calibrationNeighborTieDb).length;
  }

  /// Round 20 (field round 20: two neighbours at -46 dBm, named in list
  /// order, so the named pile flipped between runs): the strongest
  /// neighbours named together — within [calibrationNeighborTieDb] of the
  /// strongest, at most [calibrationNeighborTieMax] (the strongest always
  /// kept), listed in MAC order so the same piles read the same way every
  /// run.
  List<String> get strongestNeighborMacs {
    final kept = _byStrength.take(
      math.min(strongestNeighborTies, calibrationNeighborTieMax),
    );
    return [for (final e in kept) e.key]
      ..sort((a, b) => _key(a).compareTo(_key(b)));
  }

  /// MACs of every neighbour heard (counted or not).
  List<String> get neighborMacs => [for (final n in _neighbors.values) n.mac];

  /// Round 19: the oldest `age_s` (seconds) of the neighbours left out as
  /// stale, or null.
  int? get staleNeighborAge {
    final old = [
      for (final n in _neighbors.values)
        if (n.peak != null && n.stale) n.ageS!,
    ];
    return old.isEmpty ? null : old.reduce(math.max).round();
  }

  /// Round 19 fix: neighbours counted toward the lower bound (not stale)
  /// despite too few readings — a rescan hint, not an exclusion.
  int get fewSampleNeighbors => _neighbors.values
      .where((n) => n.peak != null && !n.stale && n.fewSamples)
      .length;

  CalibrationBasis get basis {
    if (!selfAdvReported || !neighborsReported) return CalibrationBasis.legacy;
    if (ownAdvertisingReads.isEmpty) return CalibrationBasis.noOwnAdvertising;
    final age = ownAdvertisingAgeS;
    if (age == null) return CalibrationBasis.undatedOwnAdvertising;
    if (age > calibrationSelfAdvMaxAge) {
      return CalibrationBasis.staleOwnAdvertising;
    }
    return CalibrationBasis.current;
  }

  /// Round 20: this pile's advertising median bounds the threshold only
  /// while recent ([usableOwnAdvertising]); else upper from the link
  /// readings alone.
  DirectThresholdSuggestion get suggestion => suggestDirectThreshold(
    ownLink: ownLink,
    ownAdvertising: usableOwnAdvertising,
    neighborPeaks: neighbors.values,
    current: gatewayThreshold,
  );
}
