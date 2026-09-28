import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/commissioning_controller.dart';
import '../application/field_report.dart';
import '../data/recent_data_api.dart';

/// Title of the page and of the done page's button.
const recentDataLabel = '查看最近資料';
String recentDataTitle(int site, int gateway) => '站 $site 閘道器 $gateway 最近資料';

/// `count` 0: the back office has nothing from this gateway yet.
const recentDataEmptyText = '後台尚未收到這台閘道器的資料，請稍等 20 秒再重新整理';
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

/// 「N 秒」 under a minute, 「N 分鐘」 from then on (never negative).
String recentAgeText(Duration age) {
  final s = age.inSeconds < 0 ? 0 : age.inSeconds;
  return s < 60 ? '$s 秒' : '${s ~/ 60} 分鐘';
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
/// yellow, older red, count 0 grey.
RecentBanner recentBanner(RecentData data, DateTime now) {
  if (data.isEmpty) {
    return const RecentBanner(RecentBannerKind.empty, recentDataEmptyText);
  }
  final latest = data.latest;
  if (latest == null) {
    return const RecentBanner(RecentBannerKind.unknown, '最近一筆的時間不明');
  }
  final age = now.difference(latest);
  if (age < recentFreshAge) {
    return const RecentBanner(RecentBannerKind.ok, recentDataOkText);
  }
  final text = '最近 ${recentAgeText(age)}沒有新資料';
  return RecentBanner(
    age < recentStoppedAge ? RecentBannerKind.stale : RecentBannerKind.stopped,
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

/// The rows with a time, oldest first (the chart's x axis).
List<RecentItem> recentChronological(RecentData data) {
  final rows = data.items.where((i) => i.ts != null).toList();
  rows.sort((a, b) => a.ts!.compareTo(b.ts!));
  return rows;
}

/// 「最近 20 筆・跨 N 秒・平均每秒 X 筆」.
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

/// 「PTU 9600・充電中・13:00:03（7 秒前）」.
String recentLatestLine(RecentItem item, DateTime now) {
  final tail = item.ptuTail.isEmpty ? '----' : item.ptuTail;
  final ts = item.ts;
  final ago = ts == null ? '時間不明' : '${recentAgeText(now.difference(ts))}前';
  return 'PTU $tail・${ptuStateLabel(item.ptuState)}・${recentClockText(ts)}（$ago）';
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// 09-28 〔查看最近資料〕 (one thing, one page): is the data coming in, what
/// is the newest row, is the PTU fine. Top to bottom: the status banner,
/// the newest row per PTU in big digits, the trend line (mA), and the last
/// rows as a collapsed table. No polling: 〔重新整理〕 at the top right,
/// 〔重試〕 on an error.
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
      data = await fetchRecentData(
        ref.read(apiProvider),
        site: widget.site,
        gateway: widget.gateway,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(recentDataTitle(widget.site, widget.gateway)),
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
            child: _body(context),
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
            text: recentDataEmptyText,
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
    final now = (widget.now ?? DateTime.now)();
    final banner = recentBanner(data, now);
    final latest = recentLatestPerDevice(data);
    return ListView(
      key: const Key('recent-body'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Banner(kind: banner.kind, text: banner.text),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: latest.length == 1
              ? _LatestCard(item: latest.single, now: now, big: true)
              : _LatestGrid(items: latest, now: now),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _TrendCard(data: data),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _RecentTable(data: data),
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

/// The newest row of one PTU: three big numbers, then the PTU / state /
/// time line. A fault state turns the border red and adds a warning line.
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
            Row(
              children: [
                Expanded(
                  child: _BigNumber(
                    value: recentVoltsBigText(item.inputMv),
                    unit: 'V',
                    big: big,
                  ),
                ),
                Expanded(
                  child: _BigNumber(
                    value: recentAmpsText(item.inputMa),
                    unit: 'A',
                    big: big,
                  ),
                ),
                Expanded(
                  child: _BigNumber(
                    value: recentTempText(item.tempC),
                    unit: '°C',
                    big: big,
                  ),
                ),
              ],
            ),
            SizedBox(height: big ? 12 : 8),
            Text(
              recentLatestLine(item, now),
              key: Key('$key-line'),
              style:
                  (big ? theme.textTheme.bodyLarge : theme.textTheme.bodySmall)
                      ?.merge(_tabular)
                      .copyWith(color: colors.onSurfaceVariant),
              maxLines: 2,
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

class _BigNumber extends StatelessWidget {
  const _BigNumber({
    required this.value,
    required this.unit,
    required this.big,
  });
  final String value, unit;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          text: value,
          style:
              (big
                      ? theme.textTheme.displaySmall
                      : theme.textTheme.headlineSmall)
                  ?.merge(_tabular)
                  .copyWith(fontWeight: FontWeight.w600),
          children: [
            TextSpan(
              text: ' $unit',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Star mode: one tile per PTU (last 4 digits, three numbers, state).
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
// 3. Trend
// ---------------------------------------------------------------------------

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.data});
  final RecentData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = recentChronological(data);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              recentTrendText(data),
              key: const Key('recent-trend'),
              style: theme.textTheme.bodyMedium?.merge(_tabular),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: CustomPaint(
                key: const Key('recent-trend-chart'),
                painter: RecentSparklinePainter(
                  points: [
                    for (final r in rows)
                      if (r.inputMa != null)
                        (
                          r.ts!.millisecondsSinceEpoch.toDouble(),
                          r.inputMa!.toDouble(),
                        ),
                  ],
                  color: theme.colorScheme.primary,
                  grid: theme.colorScheme.outlineVariant,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '電流 mA（左舊右新）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A line of `input_ma` over time, no package: x by time (oldest left),
/// y from the rows' min to max with a little headroom, a dot on the newest.
class RecentSparklinePainter extends CustomPainter {
  const RecentSparklinePainter({
    required this.points,
    required this.color,
    required this.grid,
  });

  /// `(time in ms, mA)` pairs, oldest first.
  final List<(double, double)> points;
  final Color color, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      gridPaint,
    );
    if (points.isEmpty) return;
    var minY = points.first.$2, maxY = points.first.$2;
    var minX = points.first.$1, maxX = points.first.$1;
    for (final (x, y) in points) {
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
    }
    if (maxY == minY) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.1;
    minY -= pad;
    maxY += pad;
    const inset = 4.0;
    Offset at(int i) {
      final (x, y) = points[i];
      final fx = maxX == minX
          ? i / math.max(points.length - 1, 1)
          : (x - minX) / (maxX - minX);
      final fy = (y - minY) / (maxY - minY);
      return Offset(
        inset + fx * (size.width - 2 * inset),
        inset + (1 - fy) * (size.height - 2 * inset),
      );
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final p = at(i);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(points.length - 1), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(RecentSparklinePainter old) =>
      old.points != points || old.color != color || old.grid != grid;
}

// ---------------------------------------------------------------------------
// 4. Recent rows table (collapsed)
// ---------------------------------------------------------------------------

class _RecentTable extends StatelessWidget {
  const _RecentTable({required this.data});
  final RecentData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cell = theme.textTheme.bodyMedium?.merge(_tabular);
    final head = theme.textTheme.labelLarge;
    DataCell text(String s, {TextAlign align = TextAlign.left}) => DataCell(
      Text(s, style: cell, maxLines: 1, softWrap: false, textAlign: align),
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
        title: Text('$recentDataTableTitle（${data.items.length} 筆）'),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('recent-table'),
              columnSpacing: 14,
              horizontalMargin: 16,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 32,
              columns: [
                DataColumn(label: Text('時間', style: head)),
                DataColumn(label: Text('PTU', style: head)),
                DataColumn(label: Text('V', style: head), numeric: true),
                DataColumn(label: Text('A', style: head), numeric: true),
                DataColumn(label: Text('°C', style: head), numeric: true),
                DataColumn(label: Text('狀態', style: head)),
              ],
              rows: [
                for (final (i, item) in data.items.indexed)
                  DataRow(
                    key: ValueKey('recent-row-$i'),
                    cells: [
                      text(recentClockText(item.ts)),
                      text(item.ptuTail.isEmpty ? '----' : item.ptuTail),
                      text(item.inputVoltsText, align: TextAlign.right),
                      text(
                        recentAmpsText(item.inputMa),
                        align: TextAlign.right,
                      ),
                      text(recentTempText(item.tempC), align: TextAlign.right),
                      text(ptuStateLabel(item.ptuState)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
