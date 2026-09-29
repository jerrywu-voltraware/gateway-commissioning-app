import 'package:flutter/material.dart';

import '../core/gateway_swap.dart';
import 'recent_data_page.dart' show recentAgeText;

/// 1.0.0+13 換機 (replaces 1.0.0+12's 〔修改〕 number picker: an installer
/// could pick a number in use and press 〔取代舊機〕 while the old gateway
/// was still online — two gateways on one station and number). Normal
/// installs are numbered automatically; 〔這台是來換掉壞掉的舊機〕 under
/// 「將配置為 站點 X / 閘道器 N」 opens this sheet, which lists only the
/// station's gateways the back office has as offline
/// ([CommissioningController.swapCandidates]); one picked is confirmed
/// ([swapConfirmText]) and sent through the existing replacement
/// (reserve-identity force_replace first, then set_site_identity).
const swapLabel = '這台是來換掉壞掉的舊機';

/// Under the assignment once an old gateway was chosen: back to the
/// automatic number.
const swapCancelLabel = '取消換機';

/// After 「將配置為 站點 X / 閘道器 N」 once an old gateway was chosen:
/// 「（取代舊機 …70F0）」.
String swapAssignmentHint(String? tail) =>
    tail == null ? '（取代舊機）' : '（取代舊機 $tail）';

/// Instead of [swapLabel] when the back office cannot be asked.
const swapNeedsNetworkText = '換機需要連上網路';

String swapSheetTitle(int site) => '選擇要取代的舊機（站 $site）';
const swapSheetHint = '只列出本站目前離線的閘道器；舊機必須已拆除或斷電。';
const swapNoneText = '本站沒有離線的閘道器可以取代';
const swapCloseLabel = '關閉';
const swapSheetCancelLabel = '取消';

/// 「閘道器 3」.
String swapRowTitle(SwapCandidate c) => '閘道器 ${c.gateway}';

/// 「最後上線 3 小時前 · MAC …70F0」 (「沒有上線紀錄」, no MAC part when the
/// back office has none).
String swapRowDetail(SwapCandidate c, DateTime now) {
  final seen = c.lastSeen;
  final tail = c.tail;
  return [
    seen == null ? '沒有上線紀錄' : '最後上線 ${recentAgeText(now.difference(seen))}前',
    if (tail != null) 'MAC $tail',
  ].join(' · ');
}

const swapConfirmTitle = '確定換機？';

/// 「這台將接手 站 80 · 閘道器 1。舊機（…70F0）必須已拆除或斷電。」
String swapConfirmText(int site, int gateway, String? tail) =>
    '這台將接手 站 $site · 閘道器 $gateway。'
    '${tail == null ? '舊機' : '舊機（$tail）'}必須已拆除或斷電。';
const swapConfirmOkLabel = '確定換機';

/// Sent no more: the old gateway came online after it was chosen.
String swapOnlineText(int gateway) => '閘道器 $gateway 目前在線上，請先把舊機斷電。';
const swapOnlineOkLabel = '知道了';

/// The old gateway picked, or null (closed / cancelled).
Future<SwapCandidate?> showGatewaySwapSheet(
  BuildContext context, {
  required int site,
  required List<SwapCandidate> candidates,
  DateTime? now,
}) => showModalBottomSheet<SwapCandidate>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => GatewaySwapSheet(
    site: site,
    candidates: candidates,
    now: now ?? DateTime.now(),
    onPicked: (c) => Navigator.pop(context, c),
    onClose: () => Navigator.pop(context),
  ),
);

class GatewaySwapSheet extends StatelessWidget {
  const GatewaySwapSheet({
    super.key,
    required this.site,
    required this.candidates,
    required this.now,
    required this.onPicked,
    required this.onClose,
  });

  final int site;
  final List<SwapCandidate> candidates;
  final DateTime now;
  final ValueChanged<SwapCandidate> onPicked;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final none = candidates.isEmpty;
    return ConstrainedBox(
      key: const Key('gateway-swap-sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              swapSheetTitle(site),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              none ? swapNoneText : swapSheetHint,
              key: Key(none ? 'gateway-swap-none' : 'gateway-swap-hint'),
              style: none ? null : TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          if (!none)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final c in candidates) _row(context, c)],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('gateway-swap-close'),
                style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: onClose,
                child: Text(none ? swapCloseLabel : swapSheetCancelLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SwapCandidate c) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      key: ValueKey('gateway-swap-${c.gateway}'),
      onTap: () => onPicked(c),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.power_off_outlined, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      swapRowTitle(c),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      swapRowDetail(c, now),
                      key: ValueKey('gateway-swap-detail-${c.gateway}'),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
