/// 1.0.0+18 (phone: 「等待期間畫面幾乎不動」): step 9's live data flow on
/// the page itself (no dialog — it would cover the checklist and the
/// errors, and 返回 would close it by mistake).
///
/// - [VerifyLiveHeader]: 「PTU ──●──▶ 閘道器 ──●──▶ 後台」; a dot runs
///   left to right once per poll that brought new rows (with a
///   selection click), nothing moves while waiting; under it the live
///   line (Semantics liveRegion: 「收到第 k 筆」, then 「資料正常上傳」 with a
///   tick that scales in once).
/// - [VerifyFeedRows]: under each PTU, its last rows sliding in from the
///   top — data time, V / A / °C, the lag, 「第 k 筆」 or, red, why not.
/// - [VerifyStepCard]: the step's card, green once the data passed.
///
/// Presentation only: what the rows say comes from the verification's own
/// poll ([CommissionState.verifyFeed]); every animation runs once and ends
/// (none while waiting), and none runs when the system asks for reduced
/// motion ([MediaQuery.disableAnimationsOf]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/commissioning_controller.dart' show verifyPollSeconds;
import '../application/connection_status.dart' show StatusTone;
import '../application/verify_feed.dart';
import '../data/recent_data_api.dart' show recentClockText;
import 'connection_status_panel.dart' show toneColor;
import 'recent_data_page.dart'
    show recentAmpsText, recentTempText, recentVoltsBigText;

/// The step's sentence (was 「逐台檢查資料時間、落後秒數與錯誤碼。連續三次
/// 通過後才判定完成。」).
const verifyGoalText = '連續收到 3 筆正常資料就算完成';

/// The pace in plain words, from the poll the verification runs: one new
/// row per PTU per poll ([verifyPollSeconds]), three of them.
const verifyPaceText =
    '約每 $verifyPollSeconds 秒收一筆，通常 ${verifyPollSeconds * 3} 秒內完成';

/// The checklist's small print while the data check runs (was 「最多等待
/// N 秒」): the pace, then the seconds left.
String verifyFooterText(int seconds) => '$verifyPaceText・剩餘 $seconds 秒';

/// The live line once the data passed.
const verifyPassedText = '資料正常上傳';

/// The live line while no row has come in yet.
const verifyWaitingFirstText = '等待第一筆資料…';

/// The flow's three stops.
const verifyFlowLabels = ['PTU', '閘道器', '後台'];

/// The dot's run from PTU to 後台.
const verifyFlowDuration = Duration(milliseconds: 800);

/// A new row sliding in.
const verifyFeedSlideDuration = Duration(milliseconds: 300);

/// 「落後 1.0 秒」 (the back office's `lag_seconds`).
String verifyLagText(num lag) => '落後 ${lag.toStringAsFixed(1)} 秒';

/// A row's count part: 「第 2 筆」, 「重新計數：第 1/3 筆」, 「正常（已滿 3
/// 筆）」, or 「未計入（維持 2/3）」.
String verifyFeedCountText(VerifyFeedEntry e) {
  if (!e.ok) return '未計入（維持 ${e.count}/3）';
  if (!e.counted) return '正常（已滿 3 筆）';
  if (e.restart) return '重新計數：第 ${e.count}/3 筆';
  return '第 ${e.count} 筆';
}

/// The values of a row, each with the separator after it but the last
/// (「53.2 V・」「2.72 A・」「36 °C・」「落後 1.0 秒」): a narrow phone wraps
/// between them, never inside one. A value the row lacks is left out.
List<String> verifyFeedValueParts(VerifyFeedEntry e) {
  final parts = [
    if (e.inputMv case final mv?) '${recentVoltsBigText(mv)} V',
    if (e.inputMa case final ma?) '${recentAmpsText(ma)} A',
    if (e.tempC case final c?) '${recentTempText(c)} °C',
    if (e.lag case final lag?) verifyLagText(lag),
  ];
  return [
    for (final (i, part) in parts.indexed)
      i < parts.length - 1 ? '$part・' : part,
  ];
}

/// 「53.2 V・2.72 A・36 °C・落後 1.0 秒」 ([verifyFeedValueParts] in one).
String verifyFeedValuesText(VerifyFeedEntry e) =>
    verifyFeedValueParts(e).join();

/// Why a row was not counted, in the verification's own words
/// ([VerifyFeedEntry.reasons]).
String verifyFeedReasonText(VerifyFeedEntry e) =>
    '原因：${e.reasons.isEmpty ? '未通過檢查' : e.reasons.join('、')}';

/// The announced line for [e]; 「PTU #n」 first when [ptus] > 1.
String verifyFeedAnnounce(VerifyFeedEntry e, {required int ptus}) {
  final who = ptus > 1 ? 'PTU #${e.id} ' : '';
  if (!e.ok) {
    return '$who資料未計入：'
        '${e.reasons.isEmpty ? '未通過檢查' : e.reasons.join('、')}';
  }
  if (!e.counted) return '$who收到新資料';
  if (e.restart) return '$who重新計數：第 ${e.count}/3 筆';
  return '$who收到第 ${e.count} 筆';
}

/// The announced line for the rows of one poll ([verifyFeedLastPoll]):
/// one row as [verifyFeedAnnounce]; several saying the same, 「每台…」
/// (every PTU) or 「PTU #1、PTU #2 …」; otherwise each in turn.
String verifyPollAnnounce(List<VerifyFeedEntry> rows, {required int ptus}) {
  if (rows.length == 1) return verifyFeedAnnounce(rows.single, ptus: ptus);
  final said = {for (final e in rows) verifyFeedAnnounce(e, ptus: 1)};
  if (said.length == 1) {
    return rows.length >= ptus
        ? '每台${said.single}'
        : '${rows.map((e) => 'PTU #${e.id}').join('、')} ${said.single}';
  }
  return [for (final e in rows) verifyFeedAnnounce(e, ptus: ptus)].join('；');
}

/// The live line: [verifyPassedText] once passed; while the check runs
/// the newest poll's rows of this verification ([verifyPollAnnounce]) or
/// [verifyWaitingFirstText]; otherwise none (a failure is the page's red
/// box, as before).
String? verifyLiveText({
  required bool busy,
  required bool passed,
  required List<VerifyFeedEntry> feed,
  required int ptus,
}) {
  if (passed) return verifyPassedText;
  if (!busy) return null;
  final rows = verifyFeedLastPoll(feed);
  if (rows.isEmpty) return verifyWaitingFirstText;
  return verifyPollAnnounce(rows, ptus: ptus);
}

/// Step 9's card: the page's card, its whole surface turning green (and
/// its border) once [passed].
class VerifyStepCard extends StatelessWidget {
  const VerifyStepCard({
    super.key,
    required this.passed,
    required this.children,
    this.padding = 16,
  });

  final bool passed;
  final List<Widget> children;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final ok = toneColor(context, StatusTone.ok);
    final still = MediaQuery.disableAnimationsOf(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: passed
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: ok, width: 1.5),
            )
          : null,
      child: AnimatedContainer(
        key: const Key('verify-card-surface'),
        duration: still ? Duration.zero : const Duration(milliseconds: 400),
        color: ok.withValues(alpha: passed ? 0.12 : 0),
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// The flow 「PTU → 閘道器 → 後台」 and the live line under it.
class VerifyLiveHeader extends StatefulWidget {
  const VerifyLiveHeader({
    super.key,
    required this.feed,
    required this.busy,
    required this.passed,
    required this.ptus,
  });

  final List<VerifyFeedEntry> feed;
  final bool busy, passed;

  /// PTUs in the verification (「PTU #n」 in the live line when > 1).
  final int ptus;

  @override
  State<VerifyLiveHeader> createState() => _VerifyLiveHeaderState();
}

class _VerifyLiveHeaderState extends State<VerifyLiveHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: verifyFlowDuration,
  );

  /// The newest serial seen: rows already there when the page was built
  /// run no dot.
  int _serial = 0;

  /// The last run's colour: every new row good.
  bool _flowOk = true;

  static int _newest(List<VerifyFeedEntry> feed) =>
      verifyFeedNewest(feed, all: true)?.serial ?? 0;

  @override
  void initState() {
    super.initState();
    _serial = _newest(widget.feed);
  }

  @override
  void didUpdateWidget(covariant VerifyLiveHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serial = _newest(widget.feed);
    if (serial > _serial) {
      final seen = _serial;
      _flowOk = widget.feed.where((e) => e.serial > seen).every((e) => e.ok);
      unawaited(HapticFeedback.selectionClick());
      if (!MediaQuery.disableAnimationsOf(context)) _flow.forward(from: 0);
    }
    _serial = serial;
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ok = toneColor(context, StatusTone.ok);
    final live = verifyLiveText(
      busy: widget.busy,
      passed: widget.passed,
      feed: widget.feed,
      ptus: widget.ptus,
    );
    final icons = [Icons.sensors, Icons.router_outlined, Icons.cloud_outlined];
    Widget link(int index) => SizedBox(
      height: 36,
      child: AnimatedBuilder(
        animation: _flow,
        builder: (context, _) {
          // One run crosses both links: the first half, then the second.
          final v = Curves.easeInOut.transform(_flow.value);
          final p = index == 0 ? v * 2 : v * 2 - 1;
          return CustomPaint(
            painter: VerifyFlowLinkPainter(
              line: widget.passed ? ok : colors.outline,
              dot: _flowOk ? ok : colors.error,
              progress: _flow.isAnimating && p >= 0 && p <= 1 ? p : null,
            ),
          );
        },
      ),
    );
    Widget node(int index) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.passed
                ? ok.withValues(alpha: 0.18)
                : colors.primaryContainer,
          ),
          child: Icon(
            icons[index],
            size: 20,
            color: widget.passed ? ok : colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 2),
        Text(verifyFlowLabels[index], style: theme.textTheme.labelMedium),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          key: const Key('verify-flow'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            node(0),
            Expanded(child: link(0)),
            node(1),
            Expanded(child: link(1)),
            node(2),
          ],
        ),
        if (live != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              key: const Key('verify-live-status'),
              container: true,
              liveRegion: true,
              child: Row(
                children: [
                  if (widget.passed) ...[
                    TweenAnimationBuilder<double>(
                      key: const Key('verify-passed-check'),
                      tween: Tween(begin: 0, end: 1),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Icon(Icons.check_circle, color: ok, size: 28),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      live,
                      key: const Key('verify-live-text'),
                      style: widget.passed
                          ? theme.textTheme.titleMedium?.copyWith(
                              color: ok,
                              fontWeight: FontWeight.w700,
                            )
                          : theme.textTheme.bodyLarge?.copyWith(
                              // A row of the newest poll not counted: red.
                              color:
                                  verifyFeedLastPoll(
                                    widget.feed,
                                  ).every((e) => e.ok)
                                  ? colors.primary
                                  : colors.error,
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A link: a line with an arrow head and, while a run crosses it, the dot
/// at [progress] (0..1; null: no dot).
class VerifyFlowLinkPainter extends CustomPainter {
  VerifyFlowLinkPainter({required this.line, required this.dot, this.progress});

  final Color line, dot;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Level with the nodes' circles (36 high).
    const y = 18.0;
    const start = 4.0;
    final end = size.width - 4;
    if (end - start < 12) return;
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(start, y), Offset(end - 2, y), stroke);
    final head = Path()
      ..moveTo(end, y)
      ..lineTo(end - 7, y - 5)
      ..lineTo(end - 7, y + 5)
      ..close();
    canvas.drawPath(head, Paint()..color = line);
    final p = progress;
    if (p == null) return;
    final x = start + (end - 8 - start) * p;
    canvas.drawCircle(
      Offset(x, y),
      9,
      Paint()..color = dot.withValues(alpha: 0.25),
    );
    canvas.drawCircle(Offset(x, y), 5, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(VerifyFlowLinkPainter old) =>
      old.line != line || old.dot != dot || old.progress != progress;
}

/// One PTU's rows, newest on top, each sliding in once.
class VerifyFeedRows extends StatelessWidget {
  const VerifyFeedRows({super.key, required this.entries});

  final List<VerifyFeedEntry> entries;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in entries)
          _SlideIn(
            key: ValueKey('verify-feed-slide-${e.serial}'),
            child: VerifyFeedRow(entry: e),
          ),
      ],
    ),
  );
}

/// A new row growing in from the top (once, when it first appears).
class _SlideIn extends StatelessWidget {
  const _SlideIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : verifyFeedSlideDuration,
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => ClipRect(
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: t,
        child: Opacity(opacity: t, child: child),
      ),
    ),
    child: child,
  );
}

/// One row: 「13:00:03  第 2 筆」, 「53.2 V・2.72 A・36 °C・落後 1.0 秒」
/// under it (wrapping on a narrow phone), and, for a row not counted, red,
/// its reason.
class VerifyFeedRow extends StatelessWidget {
  const VerifyFeedRow({super.key, required this.entry});

  final VerifyFeedEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ok = toneColor(context, StatusTone.ok);
    final tone = e.ok ? ok : colors.error;
    final values = verifyFeedValueParts(e);
    final small = theme.textTheme.bodySmall;
    Widget row = Container(
      key: ValueKey('verify-feed-row-${e.serial}'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: e.ok
            ? colors.surfaceContainerHighest.withValues(alpha: 0.45)
            : colors.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              e.ok ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: tone,
              semanticLabel: e.ok ? '正常' : '異常',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The time and the count wrap as wholes (360 dp at 1.3).
                Wrap(
                  key: ValueKey('verify-feed-head-${e.serial}'),
                  spacing: 8,
                  children: [
                    Text(
                      recentClockText(e.ts),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      verifyFeedCountText(e),
                      style: TextStyle(
                        color: tone,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (values.isNotEmpty)
                  Wrap(
                    key: ValueKey('verify-feed-values-${e.serial}'),
                    children: [
                      for (final part in values) Text(part, style: small),
                    ],
                  ),
                if (!e.ok)
                  Text(
                    verifyFeedReasonText(e),
                    key: ValueKey('verify-feed-reason-${e.serial}'),
                    style: small?.copyWith(color: colors.error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (e.earlier) row = Opacity(opacity: 0.55, child: row);
    return row;
  }
}
