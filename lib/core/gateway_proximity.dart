/// Round 30 (user rehearsal 09-27, D: the first 4 min 53 s went on
/// switching between two gateways, blinking them five times, before this
/// pile's own one was found): the gateway list is ranked by the Bluetooth
/// signal the phone receives, the strongest marked [gatewayNearestLabel],
/// with [gatewayNearestHint]; when the two strongest are within
/// [gatewayCloseDb] also [gatewayCloseHint].
///
/// The signal is smoothed (mean of the last readings) and a row only
/// overtakes the one above by [GatewaySignalRanker.hysteresisDb], so rows
/// do not jump under the finger on every advertisement.
///
/// Pure Dart so every rule can be unit-tested without widgets.
library;

/// Two gateways heard within this many dB: too close to tell by signal.
const gatewayCloseDb = 6;

/// The strongest gateway's mark in the list.
/// 1.0.0+9: 「最近」 — the filled chip beside the strongest row's dBm.
const gatewayNearestLabel = '最近';

/// Above the list once two or more gateways are heard. 1.0.0+22: the bulb
/// is on the selected card once its link is up — the advice says so.
const gatewayNearestHint = '本樁的閘道器通常是訊號最強的那台；不確定就點選它，連線後按燈泡看哪台閃燈';

/// With [gatewayNearestHint] when the two strongest are within
/// [gatewayCloseDb].
const gatewayCloseHint = '兩台距離相近，請連線後按燈泡辨識確認';

/// A phone RSSI reading that means something (−127 / 0: unknown).
bool validGatewayRssi(int rssi) => rssi > -127 && rssi < 0;

/// Ranks the gateways heard by the phone, strongest first.
class GatewaySignalRanker {
  GatewaySignalRanker({
    this.window = const Duration(seconds: 8),
    this.maxSamples = 5,
    this.hysteresisDb = 3,
    this.sampleGap = const Duration(seconds: 1),
  });

  /// Readings older than this no longer count.
  final Duration window;

  /// At most this many readings per gateway are averaged.
  final int maxSamples;

  /// A gateway moves above the one before it only when stronger by this.
  final double hysteresisDb;

  /// The scan reports every gateway again on each advertisement of any of
  /// them: the same value is taken again only after this gap.
  final Duration sampleGap;

  final _samples = <String, List<(DateTime, int)>>{};
  var _order = <String>[];

  /// Records [rssi] of gateway [id] seen at [at] (invalid values ignored).
  void add(String id, int rssi, DateTime at) {
    if (!validGatewayRssi(rssi)) return;
    final list = _samples.putIfAbsent(id, () => []);
    if (list.isNotEmpty) {
      final (lastAt, lastRssi) = list.last;
      if (lastRssi == rssi && at.difference(lastAt) < sampleGap) return;
    }
    list.add((at, rssi));
    if (list.length > maxSamples) list.removeAt(0);
  }

  /// Mean RSSI of [id] over [window] before [now]; null when not heard.
  double? strength(String id, DateTime now) {
    final recent = (_samples[id] ?? const <(DateTime, int)>[])
        .where((s) => now.difference(s.$1) <= window)
        .map((s) => s.$2)
        .toList();
    if (recent.isEmpty) return null;
    return recent.reduce((a, b) => a + b) / recent.length;
  }

  /// [ids] ranked, strongest first, gateways not heard last (in the given
  /// order). New gateways are placed by signal; a known one overtakes the
  /// one above it only when stronger by [hysteresisDb].
  List<String> rank(List<String> ids, DateTime now) {
    final present = ids.toSet();
    final known = _order.where(present.contains).toList();
    final fresh = ids.where((id) => !known.contains(id)).toList();
    _stableSort(fresh, (a, b) => _compare(a, b, now));
    final order = [...known];
    for (final id in fresh) {
      // Placed by signal among the known ones (no hysteresis for a
      // newcomer): before the first weaker or unheard one.
      final s = strength(id, now);
      final at = s == null
          ? order.length
          : order.indexWhere((o) {
              final so = strength(o, now);
              return so == null || so < s;
            });
      order.insert(at < 0 ? order.length : at, id);
    }
    // Bottom up, so a clearly stronger gateway rises in one pass.
    for (var pass = 0; pass < order.length; pass++) {
      var swapped = false;
      for (var i = order.length - 1; i >= 1; i--) {
        final above = strength(order[i - 1], now);
        final here = strength(order[i], now);
        if (here == null) continue;
        if (above == null || here - above >= hysteresisDb) {
          final id = order[i];
          order[i] = order[i - 1];
          order[i - 1] = id;
          swapped = true;
        }
      }
      if (!swapped) break;
    }
    _order = order;
    return order;
  }

  /// Dart's sort is not stable: equals keep the order they came in.
  static void _stableSort(List<String> ids, int Function(String, String) by) {
    final index = {for (final (i, id) in ids.indexed) id: i};
    ids.sort((a, b) {
      final c = by(a, b);
      return c != 0 ? c : index[a]!.compareTo(index[b]!);
    });
  }

  int _compare(String a, String b, DateTime now) {
    final sa = strength(a, now), sb = strength(b, now);
    if (sa == null && sb == null) return 0;
    if (sa == null) return 1;
    if (sb == null) return -1;
    return sb.compareTo(sa);
  }

  /// The nearest of [ids] ([rank]'s first heard one) and whether the two
  /// strongest are within [gatewayCloseDb]; null with fewer than two heard.
  ({String nearest, bool close})? nearest(List<String> ids, DateTime now) {
    final ranked = rank(ids, now);
    final heard = [
      for (final id in ranked)
        if (strength(id, now) case final s?) (id, s),
    ];
    if (heard.length < 2) return null;
    final values = heard.map((h) => h.$2).toList()
      ..sort((a, b) => b.compareTo(a));
    return (
      nearest: heard.first.$1,
      close: values[0] - values[1] < gatewayCloseDb,
    );
  }
}
