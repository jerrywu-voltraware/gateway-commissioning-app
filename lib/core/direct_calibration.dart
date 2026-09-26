/// Round 18 「校正門檻」 (direct mode, firmware 1.7.20+): with the piles set
/// up as they will stay, the APP reads `get_status.direct` for
/// [directCalibrationDuration] and compares this pile's confirmed PTU (its
/// link RSSI, `ptu_rssi`) with the strongest neighbour the gateway heard
/// (`candidates[].rssi_peak` of any other MAC), then suggests an
/// `auto_connect_min_rssi` the installer writes back to the gateway
/// (set_config, kept in its flash; cmd_contract.md §3A).
library;

import 'dart:math' as math;

import 'direct_mode.dart';

/// Sampling length and read interval (tests shorten them).
Duration directCalibrationDuration = const Duration(seconds: 20);
Duration directCalibrationInterval = const Duration(milliseconds: 1500);

/// The threshold stays at least this far below this pile's weakest reading
/// (the gateway also drops a link only 3 dB under the threshold)…
const calibrationOwnMargin = 6;

/// …and at least this far above the strongest neighbour.
const calibrationNeighborMargin = 3;

/// This pile's weakest reading minus the strongest neighbour below this: no
/// threshold keeps both margins — no suggestion, a warning instead.
const calibrationMinGap = calibrationOwnMargin + calibrationNeighborMargin;

/// No neighbour heard: this pile's weakest reading minus this…
const calibrationLoneMargin = 10;

/// …but never below this.
const calibrationLoneFloor = -90;

const calibrationTitle = '校正門檻';

/// Signals too close for any threshold (yellow).
const calibrationTooCloseText = '本樁與鄰近訊號太接近，建議開啟綁定或調整擺放';

/// The written threshold was read back from the gateway.
const calibrationSavedText = '已寫入閘道器（重開機仍保留）';

const calibrationNoOwnText =
    '未取得本樁 PTU 的連線訊號（閘道器目前沒有連著已確認的 PTU），無法建議門檻。'
    '請確認本樁 PTU 已連上後重新取樣。';

const calibrationNoNeighborText = '未聽到鄰近 PTU：建議值取本樁最弱值再低 10 dB（不低於 -90 dBm）。';

/// No confirmed PTU yet: where to get one.
const calibrationNeedsOwnText = '請先在第 7 步按「辨識此樁」確認本樁 PTU，再校正門檻。';

enum DirectThresholdVerdict {
  /// Midpoint of this pile and the strongest neighbour, within both margins.
  suggested,

  /// No neighbour heard: this pile's weakest − 10 dB (floor -90).
  noNeighbors,

  /// Gap under [calibrationMinGap]: no suggestion.
  tooClose,

  /// No reading of this pile's PTU: no suggestion.
  noOwnSignal,
}

/// [suggestDirectThreshold]'s answer: the figures shown and the threshold
/// suggested (null for [DirectThresholdVerdict.tooClose] /
/// [DirectThresholdVerdict.noOwnSignal]).
class DirectThresholdSuggestion {
  const DirectThresholdSuggestion({
    required this.verdict,
    this.ownMedian,
    this.ownWeakest,
    this.ownCount = 0,
    this.neighborStrongest,
    this.threshold,
  });

  final DirectThresholdVerdict verdict;
  final int? ownMedian;
  final int? ownWeakest;
  final int ownCount;
  final int? neighborStrongest;
  final int? threshold;

  /// This pile's weakest reading minus the strongest neighbour.
  int? get gap => ownWeakest == null || neighborStrongest == null
      ? null
      : ownWeakest! - neighborStrongest!;
}

/// A gateway RSSI reading: negative and not below -127 (0 = not read yet).
bool validRssi(Object? rssi) => rssi is num && rssi < 0 && rssi >= -127;

/// Suggested `auto_connect_min_rssi` from this pile's PTU readings [own]
/// (link RSSI, dBm) and the neighbours' advertising peaks [neighbors]
/// (dBm, any number of them; the strongest counts). Invalid readings are
/// ignored.
///
/// - The midpoint of this pile's median and the strongest neighbour
///   (rounded down), kept at least [calibrationOwnMargin] dB below this
///   pile's weakest reading and [calibrationNeighborMargin] dB above the
///   strongest neighbour.
/// - Weakest − strongest neighbour < [calibrationMinGap] dB: no threshold
///   keeps both margins → [DirectThresholdVerdict.tooClose], no suggestion.
/// - No neighbour: weakest − [calibrationLoneMargin], not below
///   [calibrationLoneFloor].
/// - Always within the gateway's -100…-20.
DirectThresholdSuggestion suggestDirectThreshold(
  Iterable<int> own,
  Iterable<int> neighbors,
) {
  final mine = [
    for (final r in own)
      if (validRssi(r)) r,
  ]..sort();
  final others = [
    for (final r in neighbors)
      if (validRssi(r)) r,
  ];
  final strongest = others.isEmpty ? null : others.reduce(math.max);
  if (mine.isEmpty) {
    return DirectThresholdSuggestion(
      verdict: DirectThresholdVerdict.noOwnSignal,
      neighborStrongest: strongest,
    );
  }
  final weakest = mine.first;
  final middle = mine.length ~/ 2;
  final median = mine.length.isOdd
      ? mine[middle]
      : ((mine[middle - 1] + mine[middle]) / 2).floor();
  DirectThresholdSuggestion result(DirectThresholdVerdict verdict, [int? t]) =>
      DirectThresholdSuggestion(
        verdict: verdict,
        ownMedian: median,
        ownWeakest: weakest,
        ownCount: mine.length,
        neighborStrongest: strongest,
        threshold: t,
      );
  if (strongest == null) {
    return result(
      DirectThresholdVerdict.noNeighbors,
      math
          .max(weakest - calibrationLoneMargin, calibrationLoneFloor)
          .clamp(minDirectRssi, maxDirectRssi),
    );
  }
  if (weakest - strongest < calibrationMinGap) {
    return result(DirectThresholdVerdict.tooClose);
  }
  final midpoint = ((median + strongest) / 2).floor();
  final threshold = math
      .max(
        math.min(midpoint, weakest - calibrationOwnMargin),
        strongest + calibrationNeighborMargin,
      )
      .clamp(minDirectRssi, maxDirectRssi);
  // Only the -100…-20 clamp can break a margin (signals near -20 dBm).
  if (threshold > weakest - calibrationOwnMargin ||
      threshold < strongest + calibrationNeighborMargin) {
    return result(DirectThresholdVerdict.tooClose);
  }
  return result(DirectThresholdVerdict.suggested, threshold);
}

String _key(Object? mac) =>
    (mac?.toString() ?? '').toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

/// What the calibration has read so far for the PTU [ownMac].
class DirectCalibrationSamples {
  DirectCalibrationSamples(this.ownMac);

  /// This pile's confirmed PTU.
  final String ownMac;

  /// Link RSSI of [ownMac] (only while the gateway reports it connected).
  final own = <int>[];

  /// Strongest advertising peak per neighbour MAC (candidates other than
  /// [ownMac]).
  final neighbors = <String, int>{};

  /// get_status reads made / that failed or carried no `direct`.
  int reads = 0;
  int missed = 0;

  /// Time sampled so far; [done] once [directCalibrationDuration] passed.
  Duration elapsed = Duration.zero;
  bool done = false;

  /// Takes one `get_status.direct` object (null / malformed: a missed read).
  void add(Object? direct) {
    reads++;
    final status = DirectStatus.from(direct);
    if (status == null) {
      missed++;
      return;
    }
    final linked = status.pickedMac;
    final rssi = status.ptuRssi;
    if (linked != null && _key(linked) == _key(ownMac) && validRssi(rssi)) {
      own.add(rssi!);
    }
    for (final c in status.candidates) {
      final peak = c.rssiPeak;
      if (_key(c.mac) == _key(ownMac) || !validRssi(peak)) continue;
      final before = neighbors[c.mac];
      neighbors[c.mac] = before == null ? peak! : math.max(before, peak!);
    }
  }

  /// A read that failed outright.
  void miss() {
    reads++;
    missed++;
  }

  /// MAC of the strongest neighbour, if any.
  String? get strongestNeighborMac {
    String? best;
    for (final e in neighbors.entries) {
      if (best == null || e.value > neighbors[best]!) best = e.key;
    }
    return best;
  }

  DirectThresholdSuggestion get suggestion =>
      suggestDirectThreshold(own, neighbors.values);
}
