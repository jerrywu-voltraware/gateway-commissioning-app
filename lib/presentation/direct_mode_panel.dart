import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/commissioning_controller.dart';
import '../application/topology_settings.dart';
import '../core/direct_calibration.dart';
import '../core/direct_mode.dart';
import '../core/ptu_rssi.dart';
import 'direct_calibration_sheet.dart';
import 'field_help_sheet.dart';

/// Step 7 (direct mode, firmware 1.7.20+): the PTU the gateway itself
/// picked — MAC, RSSI and why (`select_reason`). Round 15: no list to tick;
/// the nearby candidates (≤ 5) only appear under 「不是這台？」, where a tap
/// makes the gateway switch (a binding) so the installer can identify it.
/// Hidden for firmware without `direct` (the page keeps the old list).
///
/// Round 16: PTUs are named by MAC + RSSI, never by the old star number
/// they may still carry (round 15 showed #1–#5 here). With a pick,
/// 「不是這台？」 sits in the bottom bar ([DirectPickActions]) so it is
/// always on screen; this card keeps 「改選其他 PTU」 only while there is
/// no pick.
///
/// Round 16b: the full MAC in monospace ([MacText]) — 「MAC 後 4 碼」 read
/// 「9600」 for a whole fleet of 90:xx:xx:xx:96:00 PTUs.
///
/// Round 17: with [actionsInBar] (the page, whose bottom bar
/// [DirectPickActions] always offers 「重新搜尋」 and 「不是這台？」) the card
/// has no buttons of its own for them — field round 17: its 「改選其他
/// PTU」 vanished the moment a switch finished and a late tap landed on
/// 「結束並重新選擇閘道器」 that moved up into its place.
class DirectStatusPanel extends ConsumerStatefulWidget {
  const DirectStatusPanel({super.key, this.actionsInBar = false});

  /// 「重新搜尋」/「改選其他 PTU」 live in the bottom bar, not in the card.
  final bool actionsInBar;

  @override
  ConsumerState<DirectStatusPanel> createState() => _DirectStatusPanelState();
}

class _DirectStatusPanelState extends ConsumerState<DirectStatusPanel> {
  bool _others = false;

  // r31: 「連線訊號讀取中」 for longer than [directLinkRssiWait] → the last
  // pick / advertising RSSI marked 「（廣播值）」.
  String? _pickMac;
  DateTime? _pickSince;
  int? _lastAdv;
  Timer? _staleTimer;

  @override
  void dispose() {
    _staleTimer?.cancel();
    super.dispose();
  }

  bool _trackPick(DirectStatus? direct) {
    final mac = direct?.pickedMac;
    if (mac == null || !sameMac(mac, _pickMac)) {
      _pickMac = mac;
      _pickSince = mac == null ? null : DateTime.now();
      _lastAdv = null;
      _staleTimer?.cancel();
      if (mac != null) {
        _staleTimer = Timer(directLinkRssiWait, () {
          if (mounted) setState(() {});
        });
      }
    }
    final adv = direct == null ? null : directPickAdvRssi(direct);
    if (adv != null) _lastAdv = adv;
    final since = _pickSince;
    return since != null &&
        DateTime.now().difference(since) >= directLinkRssiWait;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commissionProvider);
    final controller = ref.read(commissionProvider.notifier);
    if (!directAutoConnectSupported(state.config)) {
      return const SizedBox.shrink();
    }
    final direct = state.direct;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final picked = direct?.pickedMac;
    final row = picked == null
        ? null
        : state.ptus.where((p) => sameMac(p['mac'], picked)).firstOrNull;
    final stale = _trackPick(direct);
    final hint = direct?.state.hint;
    final others = [for (final c in direct?.candidates ?? const []) c.mac];
    final warnFg = dark ? Colors.amber.shade200 : Colors.brown.shade900;
    final warnBg = dark
        ? Colors.amber.shade900.withValues(alpha: 0.35)
        : Colors.amber.shade100;
    return Card(
      key: const Key('direct-status'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('閘道器選中的 PTU', style: text.titleSmall),
            const SizedBox(height: 4),
            if (direct == null)
              Text(
                state.busy ? '正在讀取閘道器的選台結果…' : '尚未取得閘道器的選台結果，請按「重新搜尋」。',
                key: const Key('direct-state'),
              )
            else if (picked != null) ...[
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MacText(
                    picked,
                    key: const Key('direct-linked'),
                    others: others,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // Round 28: 「讀取中」 / the advertising RSSI until the
                  // gateway reads the link (field: 「RSSI —」 for ~70 s).
                  Text(
                    directPickRssiText(
                      direct,
                      rowRssi: row?['rssi'],
                      ptuText: row == null ? null : ptuRssiText(row),
                      stale: stale,
                      lastAdv: _lastAdv,
                    ),
                    key: const Key('direct-rssi'),
                    style: text.titleMedium,
                  ),
                ],
              ),
              if (direct.reasonText != null)
                Text(
                  '選台依據：${direct.reasonText}',
                  key: const Key('direct-reason'),
                  style: text.bodySmall,
                ),
            ] else
              Text(
                direct.state.label,
                key: const Key('direct-state'),
                style: text.titleMedium,
              ),
            if (picked != null && direct!.ambiguous)
              Container(
                key: const Key('direct-ambiguous'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: warnBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: warnFg, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        directAmbiguousText,
                        style: TextStyle(color: warnFg),
                      ),
                    ),
                  ],
                ),
              ),
            // Round 15b: the gateway switched away from the identified PTU
            // (or 是這台 pressed before identifying).
            if (state.directNotice.isNotEmpty)
              _WarnBox(
                key: const Key('direct-notice'),
                fg: warnFg,
                bg: warnBg,
                child: macRichText(
                  state.directNotice,
                  style: TextStyle(color: warnFg),
                ),
              ),
            // Round 15b: a binding this APP never confirmed — the installer
            // decides (never cleared by itself).
            if (state.strayBindMac != null)
              _WarnBox(
                key: const Key('direct-stray-bind'),
                fg: warnFg,
                bg: warnBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    macRichText(
                      directStrayBindText(state.strayBindMac),
                      style: TextStyle(
                        color: warnFg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      directStrayBindHint,
                      style: text.bodySmall?.copyWith(color: warnFg),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          key: const Key('direct-stray-keep'),
                          onPressed: state.busy
                              ? null
                              : controller.keepStrayBind,
                          child: const Text('保留'),
                        ),
                        OutlinedButton(
                          key: const Key('direct-stray-release'),
                          onPressed: state.busy || state.relinking
                              ? null
                              : controller.releaseStrayBind,
                          child: const Text('解除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  hint,
                  key: const Key('direct-hint'),
                  style: TextStyle(color: colors.error),
                ),
              ),
            if (direct != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (direct.minRssi != null) '門檻 ${direct.minRssi} dBm',
                    direct.boundMac == null
                        ? '未綁定'
                        : '已綁定 ${formatMac(direct.boundMac)}',
                  ].join(' · '),
                  style: text.bodySmall,
                ),
              ),
            // Round 28: this pile's PTU not found — causes, what to do,
            // 〔重新搜尋〕〔先完成配置〕〔請後台協助〕.
            if (directNoPtu(state, directFlow: controller.directFlow))
              const DirectNoPtuHelp(),
            if (direct?.state == DirectState.boundMissing)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('direct-unbind'),
                  onPressed: state.busy
                      ? null
                      : () => controller.setDirectBind(false),
                  child: const Text('解除綁定'),
                ),
              ),
            if (picked == null && !widget.actionsInBar)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.tonalIcon(
                  key: const Key('direct-rescan'),
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: state.busy || state.relinking
                      ? null
                      : controller.discover,
                  label: const Text('重新搜尋'),
                ),
              ),
            // With a pick, 「不是這台？」 is in the bottom bar (round 16).
            if (picked == null &&
                !widget.actionsInBar &&
                direct != null &&
                direct.candidates.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('direct-not-this'),
                  icon: Icon(
                    _others ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _others = !_others),
                  label: const Text('改選其他 PTU'),
                ),
              ),
              if (_others) ...[
                Text(
                  directCandidatesHint(direct.candidates.length),
                  style: text.bodySmall,
                ),
                for (final c in direct.candidates)
                  DirectCandidateTile(
                    c,
                    onPicked: () => setState(() => _others = false),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Round 28 (field round 28: pile B's PTU was not powered; step 7 only
/// said 「請靠近／確認同樁 PTU 已上電」 and the pile could not be finished):
/// why this pile's PTU may not be found and what to do, in the installer's
/// words, with 〔重新搜尋〕, 〔先完成配置〕 (asks first; the gateway is
/// finished without its PTU — [CommissioningController.finishWithoutPtu])
/// and 〔請後台協助〕.
class DirectNoPtuHelp extends ConsumerWidget {
  const DirectNoPtuHelp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commissionProvider);
    final controller = ref.read(commissionProvider.notifier);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final direct = state.direct;
    final lines = directNoPtuCauses(direct);
    final enabled = !state.busy && !state.relinking;
    return Container(
      key: const Key('direct-no-ptu-help'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(directNoPtuTitle, style: text.titleSmall),
          const SizedBox(height: 4),
          for (final (i, line) in lines.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: macRichText(
                '${i + 1}. $line',
                key: Key('direct-no-ptu-cause-${i + 1}'),
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: const Key('no-ptu-rescan'),
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: enabled ? controller.rescanDirect : null,
                label: const Text('重新搜尋'),
              ),
              FilledButton.tonalIcon(
                key: const Key('no-ptu-defer'),
                icon: const Icon(Icons.task_alt, size: 18),
                onPressed: enabled
                    ? () => confirmFinishWithoutPtu(context, ref)
                    : null,
                label: const Text(deferFinishLabel),
              ),
              if (controller.fieldHelpAvailable)
                OutlinedButton.icon(
                  key: const Key('no-ptu-help'),
                  icon: const Icon(Icons.support_agent, size: 18),
                  onPressed: () => openFieldHelp(context, ref),
                  label: const Text('請後台協助'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Round 28: 〔先完成配置〕 asks first (what the gateway is left with), then
/// finishes the gateway without its PTU.
Future<void> confirmFinishWithoutPtu(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(commissionProvider);
  final threshold = state.direct?.minRssi ?? directMinRssiOf(state.config);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('defer-confirm'),
      title: const Text(deferConfirmTitle),
      content: Text(deferConfirmText(threshold)),
      actions: [
        TextButton(
          key: const Key('defer-confirm-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('defer-confirm-ok'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(deferFinishLabel),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await ref.read(commissionProvider.notifier).finishWithoutPtu();
}

/// Round 28: the title of [DirectNoPtuHelp].
const directNoPtuTitle = '找不到本樁 PTU：可能原因與處理';

/// Round 28: [DirectNoPtuHelp]'s lines for the gateway's report [direct]:
/// power, placement / housing, the threshold (with the strongest PTU it
/// did hear, which may be a neighbour's — never loosen the threshold to
/// take it), the back office, and 〔先完成配置〕.
List<String> directNoPtuCauses(DirectStatus? direct) {
  final min = direct?.minRssi ?? defaultDirectRssi;
  final bound = direct?.boundMac;
  bool valid(int? r) => r != null && r < 0;
  final rows = direct?.candidates ?? const <DirectCandidate>[];
  // r31: a PTU the gateway heard but skipped because it is bound to
  // another pile (`denied`) is not 「沒有聽到」.
  final weak = rows
      .where(
        (c) =>
            c.reason != 'denied' &&
            (valid(c.rssiMed) || valid(c.rssiPeak)) &&
            (c.reason.startsWith('below_threshold') || c.reason.isEmpty),
      )
      .firstOrNull;
  final denied = rows.any((c) => c.reason == 'denied');
  final String threshold;
  if (bound != null) {
    threshold = '已綁定 PTU ${formatMac(bound)}：閘道器只連這台。若本樁已更換 PTU，請按「解除綁定」後重新搜尋。';
  } else if (weak != null) {
    final rssi = valid(weak.rssiMed) ? weak.rssiMed : weak.rssiPeak;
    threshold =
        '附近 PTU 訊號太弱（$rssi dBm，門檻 $min）：PTU '
        '${formatMac(weak.mac)} 可能是鄰近樁的 PTU——請不要為了連上而放寬門檻。';
  } else if (denied) {
    threshold = '附近的 PTU 已綁定給其他充電樁（已自動略過）；本樁 PTU 可能尚未上電。';
  } else {
    threshold = '沒有聽到任何 PTU，請確認本樁 PTU 電源（門檻 $min dBm）。';
  }
  return [
    '本樁 PTU 沒有上電：確認 PTU 電源開啟、指示燈有亮。',
    '擺放或機殼遮蔽：PTU 要和閘道器裝在同一個機殼內；金屬外殼、天線被擋住都會讓訊號變弱。',
    threshold,
    '仍找不到：按「請後台協助」，後台可看到閘道器狀態協助判斷。',
    'PTU 暫時不在場（尚未安裝或斷電）：按「$deferFinishLabel」，閘道器照常加入運作，PTU 上電後會自動連上。',
  ];
}

/// Above the nearby candidates of 「不是這台？」 / 「改選其他 PTU」.
String directCandidatesHint(int count) =>
    '附近候選（$count）：點選後閘道器會綁定並改連那一台，再按「辨識此樁」確認。';

/// One nearby candidate: the full MAC (monospace) with 「峰值 RSSI」 below
/// (round 16: no old star number); a tap makes the gateway switch to it.
///
/// Round 16b: the whole row — trailing 「改連這台」 included — is one tap
/// target; busy is checked again at the tap and [onPicked] (closing the
/// sheet) only runs when the switch really starts (field round 16: a tap
/// on the last row closed the sheet and sent nothing).
///
/// Round 17: while busy the whole row is dimmed (0.5 opacity) — [onTap]
/// alone gave no cue the tap did nothing (the row just looked unresponsive).
/// [DirectCandidatesSheet] shows the matching 「處理中」 line above the list;
/// both clear on their own once [CommissionState.busy] does.
class DirectCandidateTile extends ConsumerWidget {
  const DirectCandidateTile(this.candidate, {super.key, this.onPicked});

  final DirectCandidate candidate;

  /// Called right before the switch starts (collapse / close the sheet).
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commissionProvider);
    final controller = ref.read(commissionProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final picked = state.direct?.pickedMac;
    final c = candidate;
    final current = picked != null && sameMac(picked, c.mac);
    final others = [
      for (final o in state.direct?.candidates ?? const []) o.mac,
    ];
    final enabled = !current && !state.busy && !state.relinking;
    return Opacity(
      // Round 17: busy has no other cue on this row (onTap already null);
      // dim the whole row so it does not look merely unresponsive.
      opacity: state.busy ? 0.5 : 1.0,
      child: InkWell(
        key: ValueKey('direct-candidate-${c.mac}'),
        onTap: enabled
            ? () {
                final now = ref.read(commissionProvider);
                if (now.busy || now.relinking) return;
                onPicked?.call();
                controller.switchDirectPick(c.mac);
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MacText(
                        c.mac,
                        others: others,
                        fullBelow: true,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        c.rssiText,
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  current ? '目前選中' : '改連這台',
                  style: TextStyle(
                    color: current ? colors.onSurfaceVariant : colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round 16: 「不是這台？」 from the bottom bar — the nearby candidates in a
/// sheet (the bar itself stays small and always on screen).
Future<void> showDirectCandidates(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DirectCandidatesSheet(),
    );

/// Round 17: the sheet while a new collection window runs.
const directCandidatesCollectingText = '閘道器正在重新收集附近的 PTU，約需 5–10 秒…';

/// Round 17: 「不是這台？」 / 「改選其他 PTU」. With no candidates reported
/// (field round 17: the gateway kept its PTU after a binding was undone
/// and reported none) the gateway first runs a new collection window
/// ([CommissioningController.freshDirectWindow]); the sheet opens at once
/// and fills when the window reports.
void openDirectCandidates(BuildContext context, WidgetRef ref) {
  final state = ref.read(commissionProvider);
  if (state.busy || state.relinking) return;
  if (state.direct?.candidates.isEmpty ?? true) {
    unawaited(ref.read(commissionProvider.notifier).freshDirectWindow());
  }
  showDirectCandidates(context);
}

/// Round 16b: room below the last candidate — the largest of the system
/// bar and the gesture area, plus a margin — so the last row never sits
/// on the navigation / gesture bar.
double candidatesSheetBottom(MediaQueryData media) =>
    16 +
    [
      media.padding.bottom,
      media.viewPadding.bottom,
      media.systemGestureInsets.bottom,
    ].reduce(math.max);

class DirectCandidatesSheet extends ConsumerWidget {
  const DirectCandidatesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commissionProvider);
    final candidates = state.direct?.candidates ?? const <DirectCandidate>[];
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        key: const Key('direct-candidates-sheet'),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          candidatesSheetBottom(MediaQuery.of(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('不是這台？', style: text.titleMedium),
            const SizedBox(height: 4),
            // Round 17: the rows go dim while busy but give no reason why
            // a tap does nothing; this line (with the gateway's own
            // progress) says so, and clears itself once busy does.
            if (state.busy)
              Padding(
                key: const Key('direct-candidates-busy'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '閘道器處理中，請稍候…',
                        style: text.bodySmall?.copyWith(color: colors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              candidates.isEmpty
                  ? state.busy
                        ? directCandidatesCollectingText
                        : '閘道器目前沒有回報附近候選，請按「重新搜尋」或稍後再試。'
                  : directCandidatesHint(candidates.length),
              key: const Key('direct-candidates-hint'),
              style: text.bodySmall,
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in candidates)
                    DirectCandidateTile(
                      c,
                      onPicked: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round 16b: PTU MACs in the direct flow are monospace.
const macFont = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Courier'],
);

/// [text] as spans, every MAC in it ([formattedMacPattern]) in [macFont].
TextSpan macSpan(String text, [TextStyle? style]) {
  final children = <InlineSpan>[];
  var at = 0;
  for (final match in formattedMacPattern.allMatches(text)) {
    if (match.start > at) {
      children.add(TextSpan(text: text.substring(at, match.start)));
    }
    children.add(TextSpan(text: match.group(0), style: macFont));
    at = match.end;
  }
  if (at < text.length) children.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: children);
}

/// Whether [span] fits on one line of [maxWidth], drawn as a [Text] here
/// would draw it (default text style, text scale).
bool fitsOneLine(BuildContext context, InlineSpan span, double maxWidth) {
  if (!maxWidth.isFinite) return true;
  final painter = TextPainter(
    text: TextSpan(style: DefaultTextStyle.of(context).style, children: [span]),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final fits = painter.width <= maxWidth;
  painter.dispose();
  return fits;
}

/// A text naming PTU MACs: the MACs in [macFont] (a [Text], so finders and
/// [Text.textSpan] see the whole text).
Text macRichText(
  String text, {
  Key? key,
  TextStyle? style,
  int? maxLines,
  TextOverflow? overflow,
}) => Text.rich(
  macSpan(text),
  key: key,
  style: style,
  maxLines: maxLines,
  overflow: overflow,
);

/// Round 16b: a PTU MAC in full, monospace (field round 16: 「MAC 後 4
/// 碼」 read 「9600」 for five PTUs). Only when the full MAC does not fit
/// on one line: the shortest run of bytes telling it apart from [others]
/// ([distinguishingMacSegment]) — tap for the full MAC, or, with
/// [fullBelow] (inside a tap target), the full MAC in small type below.
class MacText extends StatefulWidget {
  const MacText(
    this.mac, {
    super.key,
    this.others = const [],
    this.style,
    this.fullBelow = false,
  });

  final String mac;
  final Iterable<Object?> others;
  final TextStyle? style;
  final bool fullBelow;

  @override
  State<MacText> createState() => _MacTextState();
}

class _MacTextState extends State<MacText> {
  bool _open = false;

  @override
  void didUpdateWidget(MacText old) {
    super.didUpdateWidget(old);
    // Another PTU (e.g. the gateway switched): short again.
    if (!sameMac(old.mac, widget.mac)) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? const TextStyle()).merge(macFont);
    final full = formatMac(widget.mac);
    return LayoutBuilder(
      builder: (context, box) {
        if (_open ||
            fitsOneLine(
              context,
              TextSpan(text: full, style: style),
              box.maxWidth,
            )) {
          return Text(full, style: style);
        }
        final segment = Text(
          distinguishingMacSegment(widget.mac, widget.others),
          key: const Key('mac-segment'),
          style: style,
        );
        if (widget.fullBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              segment,
              Text(
                full,
                style: Theme.of(context).textTheme.bodySmall?.merge(macFont),
              ),
            ],
          );
        }
        return InkWell(
          key: const Key('mac-expand'),
          onTap: () => setState(() => _open = true),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: segment),
              const Icon(Icons.unfold_more, size: 18),
            ],
          ),
        );
      },
    );
  }
}

/// Yellow step 7 box (same look as the ambiguous hint).
class _WarnBox extends StatelessWidget {
  const _WarnBox({
    super.key,
    required this.fg,
    required this.bg,
    required this.child,
  });

  final Color fg, bg;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, color: fg, size: 20),
        const SizedBox(width: 6),
        Expanded(child: child),
      ],
    ),
  );
}

/// Round 15: direct flow bottom bar actions at step 7 — 「辨識此樁」 with its
/// note, then 「是這台，開始監控」 for the PTU the gateway picked.
///
/// Round 16: 「不是這台？」 sits beside 「辨識此樁」 (always on screen, also
/// at 360 dp) and the note is one line (「已送出 · 請看樁上燈號 · MAC ·
/// RSSI」); tapping it shows the full note. Round 15: the four-line note
/// grew the bar over 「不是這台？」. Round 16b: the MAC is shortened to
/// the bytes that tell it apart only when the line does not fit.
///
/// Round 17: one fixed layout in every state (field round 17: while the
/// gateway switched PTU the bar held 「重新搜尋」 + 「取消操作」, and when
/// the switch finished other buttons took their places under the finger).
/// Every button keeps its place and is disabled rather than removed or
/// replaced:
///   1. 「辨識此樁」（「連線建立中…」 right after a connect） · 「不是這台？」
///      (with no candidates the gateway first collects a new window)
///   2. the identify note, one line
///   3. 「是這台，開始監控」（「請先按「辨識此樁」確認」 / 「等待閘道器連上
///      PTU」）
///   4. 「重新搜尋」 · 「取消操作」（only while something runs）
///   5. 「結束並重新選擇閘道器」 ([onEnd]; disabled while something runs)
///
/// Round 19: row 5 moved here from below the page's card (field round 19:
/// the card grew when its RSSI went 「RSSI —」 → 「-49 dBm」 and the button
/// slid away from under a tap; the ambiguous / notice boxes appearing and
/// vanishing move it further). The bar is anchored to the bottom of the
/// screen and this is its last row, so nothing above it can move it. The
/// note while an identify waits for its ack: [identifyPendingText] with a
/// spinner.
///
/// Round 20 (field round 20: the back office's identify snack bar sat
/// over the card's yellow box for 8 s): here the notice
/// ([CommissionState.remoteIdentifyNote]) takes row 2's one line for
/// [remoteIdentifyNoticeDuration] instead — nothing is covered and no row
/// moves; a tap shows the whole text. The installer's own identify (a new
/// [CommissionState.identifyNote]) replaces it at once.
class DirectPickActions extends ConsumerStatefulWidget {
  const DirectPickActions({super.key, this.onEnd});

  /// 「結束並重新選擇閘道器」 (asks first); no row 5 when null.
  final VoidCallback? onEnd;

  @override
  ConsumerState<DirectPickActions> createState() => _DirectPickActionsState();
}

/// Round 20: how long the back office's identify notice holds row 2.
const remoteIdentifyNoticeDuration = Duration(seconds: 8);

/// Round 21: row 2's width taken beside its text — the back office icon
/// (16 + 6) and the chevron (18).
const identifyLineChrome = 40.0;

/// Round 21: whether every [remoteIdentifyHeads] fits one line of [width]
/// here (else row 2 is two lines high).
bool remoteIdentifyHeadsFit(BuildContext context, double width) =>
    remoteIdentifyHeads.every(
      (head) => fitsOneLine(context, TextSpan(text: head), width),
    );

/// Round 21: the height of [lines] lines of the default text style here.
double textLinesHeight(BuildContext context, int lines) {
  final painter = TextPainter(
    text: TextSpan(
      style: DefaultTextStyle.of(context).style,
      text: List.filled(lines, ' ').join('\n'),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Round 21 (field round 21: 「後台剛讓這台樁閃燈（請看樁上燈…」 cut in
/// one line): the back office's identify notice in the direct bar — the
/// short first sentence ([head], 「後台已讓此樁閃燈 · PTU 未回應確認」) never
/// cut, the PTU's MAC · RSSI ([ptu]) after it, below it, or behind the tap.
///
/// One line ([twoLines] false): 「head · ptu」 when it fits (the MAC
/// shortened against [others] if needed), else [head]. Two lines: [head]
/// then [ptu]; a [head] too long for one line takes both, broken after
/// 「閃燈」, and [ptu] opens with a tap.
class RemoteIdentifyLines extends StatelessWidget {
  const RemoteIdentifyLines({
    super.key,
    required this.head,
    required this.ptu,
    required this.others,
    required this.twoLines,
    required this.width,
    this.style,
  });

  final String head, ptu;
  final List<Object?> others;
  final bool twoLines;
  final double width;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    bool fits(String text) => fitsOneLine(context, macSpan(text, style), width);
    final shortPtu = shortenMacIn(ptu, others);
    Text line(String text, Key key, {int lines = 1}) => macRichText(
      text,
      key: key,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    const headKey = Key('remote-identify');
    const ptuKey = Key('remote-identify-ptu');
    if (!twoLines) {
      final full = '$head · $ptu', short = '$head · $shortPtu';
      return line(
        ptu.isEmpty
            ? head
            : fits(full)
            ? full
            : fits(short)
            ? short
            : head,
        headKey,
      );
    }
    if (!fits(head)) {
      return line(head.replaceFirst(' · ', '\n'), headKey, lines: 2);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(head, headKey),
        if (ptu.isNotEmpty) line(fits(ptu) ? ptu : shortPtu, ptuKey),
      ],
    );
  }
}

class _DirectPickActionsState extends ConsumerState<DirectPickActions> {
  bool _detail = false;

  /// Round 20: the back office's identify notice shown in row 2, if any.
  String? _remote;

  /// Round 21: its short first sentence and its PTU MAC · RSSI line.
  String _remoteHead = '', _remotePtu = '';
  Timer? _remoteTimer;

  void _showRemote(String note, {String head = '', String ptu = ''}) {
    _remoteTimer?.cancel();
    _remoteTimer = null;
    setState(() {
      _remote = note;
      _remoteHead = head.isEmpty ? note : head;
      _remotePtu = ptu;
      _detail = false;
    });
    // Timed from the frame that shows it (the ack may arrive in another
    // zone than the frames, e.g. a widget test's real-async block).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _remote != note || _remoteTimer != null) return;
      _remoteTimer = Timer(remoteIdentifyNoticeDuration, _clearRemote);
    });
  }

  void _clearRemote() {
    _remoteTimer?.cancel();
    _remoteTimer = null;
    if (!mounted || _remote == null) return;
    setState(() {
      _remote = null;
      _detail = false;
    });
  }

  @override
  void dispose() {
    _remoteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commissionProvider);
    final controller = ref.read(commissionProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    // Round 20: a new back-office identify takes row 2; the installer's own
    // identify (a new note) hands it back at once.
    ref.listen(commissionProvider.select((s) => s.remoteIdentifyCount), (
      previous,
      next,
    ) {
      final now = ref.read(commissionProvider);
      final note = now.remoteIdentifyNote;
      if (previous != null && next != previous && note.isNotEmpty) {
        _showRemote(
          note,
          head: now.remoteIdentifyHead,
          ptu: now.remoteIdentifyPtu,
        );
      }
    });
    ref.listen(
      commissionProvider.select((s) => s.identifyNote),
      (previous, next) => _clearRemote(),
    );
    final picked = state.direct?.pickedMac;
    final shown = state.selected.firstOrNull;
    final ready = picked != null && shown != null && sameMac(picked, shown);
    final enabled = !state.busy && !state.relinking;
    // Round 17: the gateway's link to this PTU is still being set up.
    final settling = ready && state.directSettling;
    // Round 15b: 是這台 only for the PTU the installer identified.
    final confirmable = ready && directConfirmReady(state);
    final identifySupported = state.config['identify_supported'] == true;
    final others = [
      for (final c in state.direct?.candidates ?? const []) c.mac,
    ];
    final remote = _remote;
    final note = remote ?? (ready ? state.identifyNote : '');
    final line =
        remote ??
        (!ready
            ? state.busy
                  ? '閘道器處理中，請稍候…'
                  : '閘道器尚未連上 PTU'
            : note.isEmpty
            ? '按下後請看樁上 PTU 與閘道器的燈號'
            : state.identifyLine.isEmpty
            ? note
            : state.identifyLine);
    // Round 20: the back office's notice can always be opened in full.
    final expandable = note.isNotEmpty && (remote != null || note != line);
    final showDetail = _detail && expandable;
    // Round 19: sent, the ack not back yet.
    final pending =
        remote == null &&
        state.busy &&
        (line == identifyPendingText || line == identifyPendingGatewayText);
    return Column(
      key: const Key('direct-pick-actions'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (identifySupported)
              FilledButton.tonalIcon(
                key: const Key('direct-identify'),
                icon: const Icon(Icons.lightbulb_outline, size: 20),
                onPressed: enabled && ready && !settling
                    ? controller.identify
                    : null,
                label: Text(settling ? directSettlingLabel : '辨識此樁'),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: Key(ready ? 'direct-not-this' : 'direct-others-bottom'),
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  onPressed: enabled && state.direct != null
                      ? () => openDirectCandidates(context, ref)
                      : null,
                  // Same label with or without a pick: same size, same
                  // place (the sheet lists the nearby candidates).
                  label: const Text('不是這台？'),
                ),
              ),
            ),
          ],
        ),
        if (identifySupported)
          InkWell(
            key: const Key('direct-identify-toggle'),
            onTap: expandable ? () => setState(() => _detail = !_detail) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              // Round 21: two lines high whenever the back office's longest
              // notice needs them here (360 dp at text scale 1.3) — also
              // without a notice, so its arrival moves no button.
              child: LayoutBuilder(
                builder: (context, row) {
                  final twoLines = !remoteIdentifyHeadsFit(
                    context,
                    row.maxWidth - identifyLineChrome,
                  );
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: twoLines ? textLinesHeight(context, 2) : 0,
                    ),
                    child: Row(
                      children: [
                        // Round 20: the back office's identify, not this phone's.
                        if (remote != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.support_agent,
                              key: const Key('remote-identify-icon'),
                              size: 16,
                              color: colors.tertiary,
                            ),
                          ),
                        if (pending)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: SizedBox(
                              key: const Key('direct-identify-pending'),
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        Expanded(
                          // Round 16b: the full MAC when the line fits, else the
                          // bytes telling it apart (the full note opens below).
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final style = TextStyle(
                                color: remote != null
                                    ? colors.tertiary
                                    : note.isEmpty
                                    ? colors.onSurfaceVariant
                                    : colors.primary,
                              );
                              if (remote != null) {
                                return RemoteIdentifyLines(
                                  head: _remoteHead,
                                  ptu: _remotePtu,
                                  others: others,
                                  twoLines: twoLines,
                                  width: box.maxWidth,
                                  style: style,
                                );
                              }
                              return macRichText(
                                fitsOneLine(
                                      context,
                                      macSpan(line, style),
                                      box.maxWidth,
                                    )
                                    ? line
                                    : shortenMacIn(line, others),
                                key: Key(
                                  remote != null
                                      ? 'remote-identify'
                                      : 'direct-identify-note',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style,
                              );
                            },
                          ),
                        ),
                        if (expandable)
                          Icon(
                            showDetail ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        if (showDetail)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: macRichText(
              note,
              key: Key(
                remote != null
                    ? 'remote-identify-detail'
                    : 'direct-identify-detail',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 4),
        FilledButton(
          key: Key(ready ? 'direct-confirm' : 'direct-wait'),
          onPressed: enabled && confirmable
              ? controller.confirmDirectPick
              : null,
          child: Text(
            !ready
                ? directWaitingLabel
                : confirmable
                ? directConfirmLabel
                : directIdentifyFirstLabel,
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              key: const Key('direct-rescan-bottom'),
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: enabled ? controller.rescanDirect : null,
              label: const Text('重新搜尋'),
            ),
            const Spacer(),
            TextButton(
              key: const Key('direct-stop'),
              // Step 7: ends the run like 「結束並重新選擇閘道器」 (a
              // temporary binding is put back).
              onPressed: state.busy ? controller.stopStep8 : null,
              child: const Text('取消操作'),
            ),
          ],
        ),
        if (widget.onEnd != null)
          TextButton(
            key: const Key('page-cancel'),
            // Disabled (not removed) while something runs (round 17).
            onPressed: enabled ? widget.onEnd : null,
            child: const Text(endFlowLabel),
          ),
      ],
    );
  }
}

/// Advanced direct-mode settings (next to the topology menu): the gateway's
/// auto-connect threshold and binding to the PTU connected now. Each change
/// is sent with set_config at once. Round 18: 「校正門檻」 measures the site
/// and suggests the threshold ([DirectCalibrationSheet]).
class DirectSettingsSheet extends ConsumerStatefulWidget {
  const DirectSettingsSheet({super.key});

  @override
  ConsumerState<DirectSettingsSheet> createState() =>
      _DirectSettingsSheetState();
}

class _DirectSettingsSheetState extends ConsumerState<DirectSettingsSheet> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commissionProvider);
    final controller = ref.read(commissionProvider.notifier);
    final saved = directMinRssiOf(state.config);
    final value = _dragging ?? saved.toDouble();
    final bound = directBoundMacOf(state.config) ?? state.direct?.boundMac;
    final linkedMac = controller.directConnectedMac;
    final ownMac = controller.calibrationOwnMac;
    // 1.0.0+10 (review: at text scale 1.3 on 360x640 the sheet was taller
    // than the screen): it scrolls; the title as every sheet's
    // (titleLarge).
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('direct-settings-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('直連進階設定', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('自動連線門檻：${value.round()} dBm（預設 $defaultDirectRssi）'),
            Slider(
              key: const Key('direct-min-rssi'),
              min: minDirectRssi.toDouble(),
              max: maxDirectRssi.toDouble(),
              divisions: maxDirectRssi - minDirectRssi,
              value: value.clamp(
                minDirectRssi.toDouble(),
                maxDirectRssi.toDouble(),
              ),
              label: '${value.round()} dBm',
              onChanged: state.busy
                  ? null
                  : (v) => setState(() => _dragging = v),
              onChangeEnd: state.busy
                  ? null
                  : (v) async {
                      await controller.setDirectMinRssi(v.round());
                      if (mounted) setState(() => _dragging = null);
                    },
            ),
            const Text('閘道器只自動連線訊號強於門檻的 PTU；數值越大（越接近 -20）要越靠近。'),
            // Round 18: the right threshold depends on the site (piles side
            // by side, the actual housing): measure it here.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('direct-calibrate'),
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: state.busy || ownMac == null
                      ? null
                      : () => openDirectCalibration(context),
                  label: Text(
                    '$calibrationTitle（現場取樣 '
                    '${directCalibrationDuration.inSeconds} 秒）',
                  ),
                ),
              ),
            ),
            if (ownMac == null)
              Text(
                calibrationNeedsOwnText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            SwitchListTile(
              key: const Key('direct-bind'),
              contentPadding: EdgeInsets.zero,
              title: const Text('綁定目前 PTU'),
              subtitle: Text(
                bound != null
                    ? '已綁定 $bound，只連這台'
                    : linkedMac != null
                    ? '目前連線：$linkedMac'
                    : '尚未連上 PTU，無法綁定',
              ),
              value: bound != null,
              onChanged: state.busy || (bound == null && linkedMac == null)
                  ? null
                  : controller.setDirectBind,
            ),
            // Round 15: applied by 「是這台，開始監控」 (not at once).
            // 2026-09: default on — off 的後果要讓現場人員看得到（本樁 PTU
            // 關機時，閘道器可能改連鄰近樁的 PTU）。
            SwitchListTile(
              key: const Key('direct-bind-on-confirm'),
              contentPadding: EdgeInsets.zero,
              title: const Text('確認後綁定 PTU'),
              subtitle: Text(
                ref.watch(topologyProvider).directBindOnConfirm
                    ? '按「$directConfirmLabel」時把該 PTU 的 MAC 存進閘道器，之後只連這台'
                    : '關閉後不會鎖定 MAC：本樁 PTU 關機或斷線時，閘道器可能改連鄰近樁的 PTU',
              ),
              value: ref.watch(topologyProvider).directBindOnConfirm,
              onChanged: ref
                  .read(topologyProvider.notifier)
                  .setDirectBindOnConfirm,
            ),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
