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

/// No neighbour counted: the upper bound minus this…
const calibrationLoneMargin = 10;

/// …but never below this.
const calibrationLoneFloor = -90;

/// Neighbours count only with at least this many readings (`samples`)…
const calibrationMinNeighborSamples = 3;

/// …heard within this many seconds (`age_s`); older: 「重新掃描鄰近」.
const calibrationNeighborMaxAge = 60;

const calibrationTitle = '校正門檻';

/// Signals too close for any threshold (yellow).
const calibrationTooCloseText = '鄰近樁訊號太強，無法只靠門檻區分，請在確認後綁定此 PTU';

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

const calibrationNoNeighborText =
    '未聽到鄰近 PTU：建議值取本樁可用上限再低 $calibrationLoneMargin dB'
    '（不低於 $calibrationLoneFloor dBm）。';

/// No confirmed PTU yet: where to get one.
const calibrationNeedsOwnText = '請先在第 7 步按「辨識此樁」確認本樁 PTU，再校正門檻。';

/// Round 19: the resample button while neighbour data is stale.
const calibrationRescanLabel = '重新掃描鄰近';

/// Round 19: a suggestion not built on firmware 1.7.27's fields.
const calibrationReferenceLegacyText = '參考值（閘道器韌體較舊）';
const calibrationReferenceNoAdvText = '參考值（閘道器未回報本樁廣播訊號）';

/// Round 19: [value] dBm that never breaks between the number and 「dBm」.
String dbm(int value) => '$value\u00A0dBm';

/// Round 19: [text] kept on one line (a word joiner between every
/// character; field round 19: 「）」 wrapped onto a line of its own).
String noBreak(String text) => text.split('').join('\u2060');

/// Round 19: the too-close comparison in the installer's words — [gap] is
/// this pile's upper bound minus the strongest neighbour's peak
/// ([DirectThresholdSuggestion.gap]), [neighbor] that neighbour's MAC
/// segment (kept on one line).
String calibrationGapText(int gap, String neighbor) {
  final who = '鄰近樁 ${noBreak(neighbor)} ';
  if (gap < 0) return '$who比本樁還強 ${-gap} dB';
  if (gap == 0) return '$who和本樁一樣強';
  return '$who只比本樁弱 $gap dB，餘裕不足（至少要弱 $calibrationMinGap dB）';
}

/// Round 19: neighbours left out for being heard too long ago ([ageS]: the
/// oldest, seconds).
String calibrationStaleText(int ageS) =>
    '鄰近資料已 $ageS 秒未更新（超過 $calibrationNeighborMaxAge 秒，未列入計算），'
    '請按「$calibrationRescanLabel」再取樣一次。';

/// Round 19: neighbours left out for too few readings.
String calibrationFewSamplesText(int count) =>
    '另有 $count 台鄰近 PTU 讀數不足 $calibrationMinNeighborSamples 筆，未列入計算。';

enum DirectThresholdVerdict {
  /// Midpoint of [DirectThresholdSuggestion.lower] and
  /// [DirectThresholdSuggestion.upper].
  suggested,

  /// No neighbour counted: upper − 10 dB (floor -90).
  noNeighbors,

  /// Upper − lower under [calibrationMinRange]: no suggestion.
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

  /// [upper] minus the strongest neighbour's peak.
  int? get gap => upper == null || neighborStrongest == null
      ? null
      : upper! - neighborStrongest!;

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
/// - No neighbour: upper − [calibrationLoneMargin], not below
///   [calibrationLoneFloor] (nor above upper).
/// - No link reading: [DirectThresholdVerdict.noOwnSignal].
/// - Always within the gateway's -100…-20 (a clamp that leaves the range:
///   too close).
DirectThresholdSuggestion suggestDirectThreshold({
  required Iterable<int> ownLink,
  int? ownAdvertising,
  required Iterable<int> neighborPeaks,
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
  DirectThresholdSuggestion result(DirectThresholdVerdict verdict, [int? t]) =>
      DirectThresholdSuggestion(
        verdict: verdict,
        ownLinkMedian: _median(link),
        ownLinkWeakest: weakest,
        ownLinkCount: link.length,
        ownAdvertising: adv,
        neighborStrongest: strongest,
        upper: upper,
        lower: lower,
        threshold: t,
      );
  if (lower == null) {
    return result(
      DirectThresholdVerdict.noNeighbors,
      math
          .min(
            math.max(upper - calibrationLoneMargin, calibrationLoneFloor),
            upper,
          )
          .clamp(minDirectRssi, maxDirectRssi),
    );
  }
  if (upper - lower < calibrationMinRange) {
    return result(DirectThresholdVerdict.tooClose);
  }
  final threshold = ((upper + lower) / 2).floor().clamp(
    minDirectRssi,
    maxDirectRssi,
  );
  // Only the -100…-20 clamp can leave the range (signals near -20 dBm).
  if (threshold > upper || threshold < lower) {
    return result(DirectThresholdVerdict.tooClose);
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
  legacy;

  /// Not built on everything the firmware's rules use: [referenceText].
  bool get reference => this != current;

  String? get referenceText => switch (this) {
    current => null,
    noOwnAdvertising => calibrationReferenceNoAdvText,
    legacy => calibrationReferenceLegacyText,
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

  /// Counted: a peak, heard recently enough, often enough.
  bool get counts => peak != null && !stale && !fewSamples;
}

/// What the calibration has read so far for the PTU [ownMac].
///
/// Round 19: this pile's link readings and, firmware 1.7.27, its
/// advertising medians (`self_adv_rssi_med`); the neighbours from
/// `neighbors[]` (firmware 1.7.27, kept up to date while connected; only
/// those with ≥ [calibrationMinNeighborSamples] readings heard within
/// [calibrationNeighborMaxAge] s count, by their latest listing) or else
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

  /// Round 19: a read connected to [ownMac] carried `self_adv_rssi_med`
  /// (even null) / a read carried `neighbors`.
  bool selfAdvReported = false;
  bool neighborsReported = false;

  final _neighbors = <String, _Neighbor>{};

  /// get_status reads made / that failed or carried no `direct`.
  int reads = 0;
  int missed = 0;

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
    final linked = status.pickedMac;
    final mine = linked != null && _key(linked) == _key(ownMac);
    if (mine && validRssi(status.ptuRssi)) ownLink.add(status.ptuRssi!);
    if (mine && status.selfAdvReported) {
      selfAdvReported = true;
      if (validRssi(status.selfAdvRssiMed)) {
        ownAdvertisingReads.add(status.selfAdvRssiMed!);
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
  /// medians read), or null.
  int? get ownAdvertising =>
      ownAdvertisingReads.isEmpty ? null : _median(ownAdvertisingReads);

  /// The counted neighbours' peaks (MAC → dBm).
  Map<String, int> get neighbors => {
    for (final n in _neighbors.values)
      if (n.counts) n.mac: n.peak!,
  };

  /// MAC of the strongest counted neighbour, if any.
  String? get strongestNeighborMac {
    String? best;
    int? strongest;
    for (final MapEntry(key: mac, value: dbm) in neighbors.entries) {
      if (strongest == null || dbm > strongest) {
        best = mac;
        strongest = dbm;
      }
    }
    return best;
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

  /// Round 19: neighbours left out for too few readings (not stale).
  int get fewSampleNeighbors => _neighbors.values
      .where((n) => n.peak != null && !n.stale && n.fewSamples)
      .length;

  CalibrationBasis get basis => !selfAdvReported || !neighborsReported
      ? CalibrationBasis.legacy
      : ownAdvertisingReads.isEmpty
      ? CalibrationBasis.noOwnAdvertising
      : CalibrationBasis.current;

  DirectThresholdSuggestion get suggestion => suggestDirectThreshold(
    ownLink: ownLink,
    ownAdvertising: ownAdvertising,
    neighborPeaks: neighbors.values,
  );
}
