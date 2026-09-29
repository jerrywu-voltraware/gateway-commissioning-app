import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_session.dart';
import '../application/field_report.dart';
import '../core/gateway_identity.dart' show gatewayIdText;
import '../data/recent_data_api.dart';

/// Title of the done page's button.
const recentDataLabel = '查看最近資料';

/// 1.0.0+10 (phone: 「站 81 閘道器 1 …」 cut in the AppBar): the AppBar
/// says 「最近資料」; the gateway is the first line under it
/// ([recentDataSubtitle]).
const recentDataPageTitle = '最近資料';

/// 「站 81 · 閘道器 1」, the line under the AppBar.
String recentDataSubtitle(int site, int gateway) =>
    gatewayIdText(site, gateway);

/// `count` 0: the back office has nothing from this gateway yet (1.0.0+20:
/// no fixed number of seconds — the interval can be up to 5 minutes).
const recentDataEmptyText = '後台尚未收到這台閘道器的資料，請稍等一下再重新整理';

/// 1.0.0+20: the empty page's sentence; with the back office's interval
/// ([RecentData.uploadIntervalMs]) it says how often a row comes.
String recentEmptyText(int? intervalMs) => intervalMs == null
    ? recentDataEmptyText
    : '後台尚未收到這台閘道器的資料；閘道器約每 ${intervalWords(intervalMs)}'
          '上傳一筆，請稍後再重新整理';
const recentDataOkText = '資料正常上傳中';
const recentDataFaultText = 'PTU 回報故障';
const recentDataRefreshLabel = '重新整理';
const recentDataRetryLabel = '重試';
const recentDataLoadingText = '正在向後台查詢…';
const recentDataTableTitle = '最近資料';

/// Fresh: the newest row is younger than this.
const recentFreshAge = Duration(seconds: 30);

/// Stopped: the newest row is older than this (red, not yellow).
const recentStoppedAge = Duration(minutes: 10);

/// 1.0.0+20 (docs/design/upload_interval_5min_2026-09-29.md §4): green
/// while the newest row is at most `G = max(30, 2·I + 10)` seconds old,
/// for the back office's interval I ([RecentData.uploadIntervalMs]).
Duration recentGreenAge(int intervalMs) =>
    Duration(milliseconds: max(30000, 2 * intervalMs + 10000));

/// 1.0.0+20: yellow up to `R = max(600, G + 2·I)` seconds, red after.
Duration recentRedAge(int intervalMs) => Duration(
  milliseconds: max(
    600000,
    recentGreenAge(intervalMs).inMilliseconds + 2 * intervalMs,
  ),
);

// ---------------------------------------------------------------------------
// PTU state words
// ---------------------------------------------------------------------------

/// The firmware's `ptu_state` strings (`ble_multi_wifi_gateway/main/http/
/// mqtt_uploader.c` `ptu_state_to_string`, index 0-9 plus `UNKNOWN`) in
/// the installer's words. Names not listed are shown as sent.
const ptuStateLabels = <String, String>{
  'CONFIGURATION': '設定中',
  'POWER_SAVE': '省電',
  'LOW_POWER': '低功率',
  'POWER_TRANSFER': '充電中',
  'LATCH_FAULT': '鎖定故障',
  'LATCHING_FAULT': '鎖定故障',
  'LOCAL_FAULT': '本地故障',
  'OTA_MODE': 'OTA 更新中',
  'COOLING': '冷卻中',
  'EXCEEDED_RANGE': 'PRU 超出範圍',
  'UNKNOWN': '未知',
};

/// The state in words; `--` for none, the raw string when unknown.
String ptuStateLabel(String state) {
  final s = state.trim();
  if (s.isEmpty || s.toUpperCase() == 'NULL') return '--';
  return ptuStateLabels[s.toUpperCase()] ?? s;
}

/// A fault state (`*_FAULT`).
bool ptuStateIsFault(String state) => state.toUpperCase().contains('FAULT');

/// 1.0.0+5: the table's short state words (the 「狀態」 column must fit
/// a 360 dp phone with the other columns). Same keys as [ptuStateLabels];
/// `IDLE` reads 「待機」; any other `*_FAULT` 「故障」; the rest as sent,
/// cut to 4 characters.
const ptuStateShortLabels = <String, String>{
  'CONFIGURATION': '設定',
  'POWER_SAVE': '省電',
  'LOW_POWER': '低功率',
  'POWER_TRANSFER': '充電',
  'IDLE': '待機',
  'LATCH_FAULT': '故障',
  'LATCHING_FAULT': '故障',
  'LOCAL_FAULT': '故障',
  'OTA_MODE': 'OTA',
  'COOLING': '冷卻',
  'EXCEEDED_RANGE': '超範圍',
  'UNKNOWN': '未知',
};

/// The short state word for the table; `--` for none.
String ptuStateShort(String state) {
  final s = state.trim();
  if (s.isEmpty || s.toUpperCase() == 'NULL') return '--';
  final known = ptuStateShortLabels[s.toUpperCase()];
  if (known != null) return known;
  if (ptuStateIsFault(s)) return '故障';
  return s.length > 4 ? s.substring(0, 4) : s;
}

// ---------------------------------------------------------------------------
// Pure view helpers (tested without widgets)
// ---------------------------------------------------------------------------

/// `input_ma` in amps with two decimals, or `--`.
String recentAmpsText(num? ma) =>
    ma == null ? '--' : (ma / 1000).toStringAsFixed(2);

/// `input_mv` in volts with one decimal (the big number), or `--`.
String recentVoltsBigText(num? mv) =>
    mv == null ? '--' : (mv / 1000).toStringAsFixed(1);

/// `temp_c` as an integer, or `--`.
String recentTempText(num? c) => c == null ? '--' : c.round().toString();

/// 「N 秒」 under a minute, 「N 分鐘」 under an hour, 「N 小時」 under a
/// day, then 「N 天」 (1.0.0+10); never negative (a phone clock behind the
/// back office's reads as 0 秒).
String recentAgeText(Duration age) {
  final s = age.inSeconds < 0 ? 0 : age.inSeconds;
  if (s < 60) return '$s 秒';
  if (s < 3600) return '${s ~/ 60} 分鐘';
  if (s < 86400) return '${s ~/ 3600} 小時';
  return '${s ~/ 86400} 天';
}

/// 1.0.0+10 (review P2-9: a phone clock 30 s fast read fresh data as
/// yellow): 「now」 for the ages of [data] — the phone's [phoneNow] moved to
/// the back office's clock when its answer carried a `Date`
/// ([RecentData.serverOffset]), else the phone's own.
DateTime recentServerNow(RecentData data, DateTime phoneNow) {
  final offset = data.serverOffset;
  return offset == null ? phoneNow : phoneNow.add(offset);
}

enum RecentBannerKind { ok, stale, stopped, empty, error, unknown }

/// The status banner: one colour, one sentence.
class RecentBanner {
  const RecentBanner(this.kind, this.text);
  final RecentBannerKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is RecentBanner && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'RecentBanner($kind, $text)';
}

/// The banner for [data] at [now]: fresh (<30 s) green, 30 s – 10 min
/// yellow, older red, count 0 grey. 1.0.0+20: with the back office's
/// interval ([RecentData.uploadIntervalMs]) green up to [recentGreenAge],
/// yellow up to [recentRedAge]; without it as before.
RecentBanner recentBanner(RecentData data, DateTime now) {
  final interval = data.uploadIntervalMs;
  if (data.isEmpty) {
    return RecentBanner(RecentBannerKind.empty, recentEmptyText(interval));
  }
  final latest = data.latest;
  if (latest == null) {
    return const RecentBanner(RecentBannerKind.unknown, '最近一筆的時間不明');
  }
  // 1.0.0+10: a row newer than now (clock skew) is 0 s old.
  final raw = now.difference(latest);
  final age = raw.isNegative ? Duration.zero : raw;
  final fresh = interval == null
      ? age < recentFreshAge
      : age <= recentGreenAge(interval);
  if (fresh) {
    return const RecentBanner(RecentBannerKind.ok, recentDataOkText);
  }
  final stale = interval == null
      ? age < recentStoppedAge
      : age <= recentRedAge(interval);
  final text = '最近 ${recentAgeText(age)}沒有新資料';
  return RecentBanner(
    stale ? RecentBannerKind.stale : RecentBannerKind.stopped,
    text,
  );
}

/// The grouping key of a row: the PTU's MAC, else its device number.
String recentDeviceKey(RecentItem item) =>
    item.ptuMac.isNotEmpty ? item.ptuMac.toUpperCase() : 'dev-${item.deviceId}';

/// The newest row of each PTU, newest PTU first (one entry in the direct
/// mode, one per PTU in the star mode).
List<RecentItem> recentLatestPerDevice(RecentData data) {
  final best = <String, RecentItem>{};
  for (final item in data.items) {
    final key = recentDeviceKey(item);
    final cur = best[key];
    if (cur == null) {
      best[key] = item;
      continue;
    }
    final a = item.ts, b = cur.ts;
    if (b == null || (a != null && a.isAfter(b))) best[key] = item;
  }
  final out = best.values.toList();
  out.sort((x, y) {
    final a = x.ts, b = y.ts;
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  });
  return out;
}

/// The rows with a time, oldest first (the summary's span).
List<RecentItem> recentChronological(RecentData data) {
  final rows = data.items.where((i) => i.ts != null).toList();
  rows.sort((a, b) => a.ts!.compareTo(b.ts!));
  return rows;
}

/// 「最近 20 筆・跨 N 秒・平均每秒 X 筆」 — the small line under the
/// banner (1.0.0+5: the mA chart is gone, the installer did not use it).
String recentTrendText(RecentData data) {
  final rows = recentChronological(data);
  final n = data.items.length;
  if (rows.length < 2) return '最近 $n 筆';
  final span = rows.last.ts!.difference(rows.first.ts!);
  final seconds = span.inMilliseconds / 1000;
  final rate = seconds > 0 ? rows.length / seconds : null;
  final rateText = rate == null ? '--' : rate.toStringAsFixed(1);
  return '最近 $n 筆・跨 ${recentAgeText(span)}・平均每秒 $rateText 筆';
}

/// 「PTU 90:5F:E8:9A:96:00・充電中・13:00:03（7 秒前）」 (1.0.0+8: the whole
/// MAC on the line itself; 1.0.0+5's 「MAC …」 small print is gone). The
/// card shows the two parts on two lines ([recentLatestParts]).
String recentLatestLine(RecentItem item, DateTime now) {
  final (mac, rest) = recentLatestParts(item, now);
  return '$mac・$rest';
}

/// The line's two pieces: 「PTU 90:5F:E8:9A:96:00」 and
/// 「充電中・13:00:03（7 秒前）」 (1.0.0+10: no leading 「・」 — on the phone
/// the second line started with it).
(String, String) recentLatestParts(RecentItem item, DateTime now) {
  final mac = item.ptuMacText.isEmpty ? '--:--:--' : item.ptuMacText;
  final ts = item.ts;
  final ago = ts == null ? '時間不明' : '${recentAgeText(now.difference(ts))}前';
  return (
    'PTU $mac',
    '${ptuStateLabel(item.ptuState)}・${recentClockText(ts)}（$ago）',
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// 09-28 〔查看最近資料〕 (one thing, one page): is the data coming in, what
/// is the newest row, is the PTU fine. Top to bottom: the status banner
/// with the 「最近 N 筆」 summary under it, the newest row per PTU in big
/// digits, and the last rows as a collapsed table (1.0.0+5: no chart).
/// No polling: 〔重新整理〕 at the top right, 〔重試〕 on an error.
class RecentDataPage extends ConsumerStatefulWidget {
  const RecentDataPage({
    super.key,
    required this.site,
    required this.gateway,
    this.now,
  });

  final int site, gateway;

  /// Clock for the 「N 秒前」 texts; tests inject one.
  final DateTime Function()? now;

  /// Opens the page for [site]/[gateway].
  static Future<void> open(BuildContext context, int site, int gateway) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecentDataPage(site: site, gateway: gateway),
        ),
      );

  @override
  ConsumerState<RecentDataPage> createState() => _RecentDataPageState();
}

class _RecentDataPageState extends ConsumerState<RecentDataPage> {
  RecentData? _data;
  Object? _error;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // Field rescue: tell the back office the installer is checking the
    // data (skipped once the session ended on the done page).
    ref.read(fieldReporterProvider).noteRecentDataViewed();
    _load();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    RecentData? data;
    Object? error;
    try {
      // 1.0.0+7: logs in by itself when the flow has not.
      data = await ref
          .read(appSessionProvider)
          .run(
            (api) => fetchRecentData(
              api,
              site: widget.site,
              gateway: widget.gateway,
            ),
          );
    } catch (e) {
      error = e;
    }
    if (!mounted || gen != _generation) return;
    setState(() {
      _loading = false;
      if (error != null) {
        _error = error;
      } else {
        _data = data;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          recentDataPageTitle,
          key: Key('recent-appbar-title'),
          maxLines: 1,
          softWrap: false,
        ),
        actions: [
          IconButton(
            key: const Key('recent-refresh'),
            tooltip: recentDataRefreshLabel,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                  key: Key('recent-progress'),
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1.0.0+10: which gateway, the first line under the AppBar.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Text(
                    recentDataSubtitle(widget.site, widget.gateway),
                    key: const Key('recent-subtitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(child: _body(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final error = _error;
    final data = _data;
    if (_loading && data == null && error == null) {
      return const Center(
        key: Key('recent-loading'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(recentDataLoadingText),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      return ListView(
        key: const Key('recent-error'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Banner(
            kind: RecentBannerKind.error,
            text: recentDataErrorText(error),
            textKey: const Key('recent-error-text'),
            action: FilledButton.tonalIcon(
              key: const Key('recent-retry'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text(recentDataRetryLabel),
            ),
          ),
        ],
      );
    }
    if (data == null || data.isEmpty) {
      return ListView(
        key: const Key('recent-empty'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Banner(
            kind: RecentBannerKind.empty,
            text: recentEmptyText(data?.uploadIntervalMs),
            action: OutlinedButton.icon(
              key: const Key('recent-empty-refresh'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text(recentDataRefreshLabel),
            ),
          ),
        ],
      );
    }
    final now = recentServerNow(data, (widget.now ?? DateTime.now)());
    final banner = recentBanner(data, now);
    final latest = recentLatestPerDevice(data);
    return ListView(
      key: const Key('recent-body'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Banner(kind: banner.kind, text: banner.text),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            recentTrendText(data),
            key: const Key('recent-trend'),
            style: Theme.of(context).textTheme.bodySmall
                ?.merge(_tabular)
                .copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: latest.length == 1
              ? _LatestCard(item: latest.single, now: now, big: true)
              : _LatestGrid(items: latest, now: now),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _RecentTable(data: data, singlePtu: latest.length == 1),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Status banner
// ---------------------------------------------------------------------------

class _Banner extends StatelessWidget {
  const _Banner({
    required this.kind,
    required this.text,
    this.textKey,
    this.action,
  });
  final RecentBannerKind kind;
  final String text;
  final Key? textKey;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (kind) {
      RecentBannerKind.ok => (
        const Color(0xFF2E7D32),
        Colors.white,
        Icons.check_circle,
      ),
      RecentBannerKind.stale => (
        const Color(0xFFF9A825),
        Colors.black87,
        Icons.schedule,
      ),
      RecentBannerKind.stopped => (colors.error, colors.onError, Icons.error),
      RecentBannerKind.error => (colors.error, colors.onError, Icons.cloud_off),
      RecentBannerKind.empty || RecentBannerKind.unknown => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        Icons.hourglass_empty,
      ),
    };
    return Container(
      key: const Key('recent-banner'),
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: fg,
                size: 26,
                key: Key('recent-banner-${kind.name}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  key: textKey,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Latest row per PTU
// ---------------------------------------------------------------------------

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// The newest row of one PTU: three big numbers and the PTU (whole MAC) /
/// state / time line. A fault state turns the border red and adds a
/// warning line.
class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.item, required this.now, required this.big});
  final RecentItem item;
  final DateTime now;

  /// The direct mode's one card (bigger digits) or a star-mode tile.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fault = ptuStateIsFault(item.ptuState);
    final key = big ? 'recent-latest' : 'recent-latest-${item.ptuTail}';
    return Card(
      key: Key(key),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: fault ? colors.error : colors.outlineVariant,
          width: fault ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(big ? 16 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BigNumbers(
              keyPrefix: key,
              big: big,
              values: [
                (recentVoltsBigText(item.inputMv), 'V', '電壓'),
                (recentAmpsText(item.inputMa), 'A', '電流'),
                (recentTempText(item.tempC), '°C', '溫度'),
              ],
            ),
            SizedBox(height: big ? 12 : 8),
            // 1.0.0+8: the whole MAC. 1.0.0+10 (phone: the wrapped part
            // started with 「・」): two lines — 「PTU 90:5F:E8:9A:96:00」 and
            // 「充電中・01:34:53（0 秒前）」.
            Builder(
              builder: (context) {
                final (mac, rest) = recentLatestParts(item, now);
                final style =
                    (big
                            ? theme.textTheme.bodyLarge
                            : theme.textTheme.bodySmall)
                        ?.merge(_tabular)
                        .copyWith(color: colors.onSurfaceVariant);
                return Column(
                  key: Key('$key-line'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mac, key: Key('$key-line-mac'), style: style),
                    Text(rest, key: Key('$key-line-rest'), style: style),
                  ],
                );
              },
            ),
            if (fault) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.warning_amber, size: 18, color: colors.error),
                  const SizedBox(width: 6),
                  Text(
                    recentDataFaultText,
                    key: Key('$key-fault'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 1.0.0+10 (phone: 「53.2V2.72A36°C」 ran together, each number scaled
/// by its own FittedBox): three equal columns — the value (one size for
/// all three, bold) with its unit small on the same baseline, and 「電壓」
/// ／「電流」／「溫度」 under it. The size is headlineMedium (the direct
/// mode's card) or titleLarge (a star tile); when one value does not fit
/// its column, all three drop one step (titleLarge / titleMedium).
class _BigNumbers extends StatelessWidget {
  const _BigNumbers({
    required this.keyPrefix,
    required this.big,
    required this.values,
  });
  final String keyPrefix;
  final bool big;

  /// (value, unit, label).
  final List<(String, String, String)> values;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final unitStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    TextSpan span(String value, String unit, TextStyle? style) => TextSpan(
      text: value,
      style: style?.merge(_tabular).copyWith(fontWeight: FontWeight.w700),
      children: [TextSpan(text: ' $unit', style: unitStyle)],
    );
    return LayoutBuilder(
      key: Key('$keyPrefix-numbers'),
      builder: (context, box) {
        final column =
            (box.maxWidth - _gap * (values.length - 1)) / values.length;
        bool fits(TextStyle? style) => values.every((v) {
          final painter = TextPainter(
            text: span(v.$1, v.$2, style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final ok = painter.width <= column;
          painter.dispose();
          return ok;
        });
        final large = big
            ? theme.textTheme.headlineMedium
            : theme.textTheme.titleLarge;
        final style = fits(large)
            ? large
            : big
            ? theme.textTheme.titleLarge
            : theme.textTheme.titleMedium;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, (value, unit, label)) in values.indexed) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      span(value, unit, style),
                      key: Key('$keyPrefix-value-$i'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      label,
                      key: Key('$keyPrefix-label-$i'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Star mode: one tile per PTU (MAC's last 3 groups, three numbers, state).
class _LatestGrid extends StatelessWidget {
  const _LatestGrid({required this.items, required this.now});
  final List<RecentItem> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('recent-latest-grid'),
      builder: (context, box) {
        final columns = box.maxWidth >= 520 ? 2 : 1;
        final width = (box.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _LatestCard(item: item, now: now, big: false),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Recent rows table (collapsed)
// ---------------------------------------------------------------------------

/// 1.0.0+5: fixed column widths, one line per row, no wrapping. One PTU
/// (the direct mode): 時間｜V｜A｜°C｜狀態, 286 dp with the margins — it fits
/// a 360 dp phone without a horizontal scroll (the 「狀態」 column was cut
/// off before). Several PTUs: a 「PTU」 column (MAC's last 3 groups) is
/// added and the table scrolls sideways.
///
/// 1.0.0+10 (review: at text scale 1.3 the fixed widths silently clipped
/// the digits): the widths grow with the text scale, a cell too long ends
/// in 「…」, and one PTU's table scrolls sideways too once it no longer
/// fits the width.
class _RecentTable extends StatelessWidget {
  const _RecentTable({required this.data, required this.singlePtu});
  final RecentData data;
  final bool singlePtu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cell = theme.textTheme.bodyMedium?.merge(_tabular);
    final head = theme.textTheme.labelLarge;
    const gap = 8.0;
    // The widths were measured at text scale 1 (14 px cells).
    final size = cell?.fontSize ?? 14;
    final scale = MediaQuery.textScalerOf(context).scale(size) / size;
    final columns = <_Col>[
      const _Col('時間', 66),
      if (!singlePtu) const _Col('PTU', 72),
      const _Col('V', 42, numeric: true),
      const _Col('A', 42, numeric: true),
      const _Col('°C', 30, numeric: true),
      const _Col('狀態', 58),
    ];
    Widget text(String s, _Col col, TextStyle? style) => SizedBox(
      width: (col.width * scale).ceilToDouble(),
      child: Text(
        s,
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: col.numeric ? TextAlign.right : TextAlign.left,
      ),
    );
    final tableWidth =
        32 +
        gap * (columns.length - 1) +
        columns.fold<double>(0, (w, c) => w + (c.width * scale).ceil());
    Widget row(List<String> values, TextStyle? style, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, col) in columns.indexed) ...[
            if (i > 0) const SizedBox(width: gap),
            text(values[i], col, style),
          ],
        ],
      ),
    );
    final table = Column(
      key: const Key('recent-table'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row([for (final c in columns) c.title], head),
        const Divider(height: 1),
        for (final (i, item) in data.items.indexed)
          row(
            [
              recentClockText(item.ts),
              if (!singlePtu)
                item.ptuShort.isEmpty ? '--:--:--' : item.ptuShort,
              item.inputVoltsText,
              recentAmpsText(item.inputMa),
              recentTempText(item.tempC),
              ptuStateShort(item.ptuState),
            ],
            cell,
            key: ValueKey('recent-row-$i'),
          ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        key: const Key('recent-table-tile'),
        initiallyExpanded: false,
        // 1.0.0+10: a collapsed section's title (bodyMedium).
        title: Text(
          '$recentDataTableTitle（${data.items.length} 筆）',
          style: theme.textTheme.bodyMedium,
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, box) => singlePtu && tableWidth <= box.maxWidth
                ? table
                : SingleChildScrollView(
                    key: const Key('recent-table-scroll'),
                    scrollDirection: Axis.horizontal,
                    child: table,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Col {
  const _Col(this.title, this.width, {this.numeric = false});
  final String title;
  final double width;
  final bool numeric;
}
