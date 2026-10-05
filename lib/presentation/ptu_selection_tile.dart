import 'package:flutter/material.dart';
import '../core/assign_progress.dart';
import '../core/ptu_rssi.dart';
import '../l10n/l10n.dart';

/// Compact selection row; technical detail is available without making every
/// device row taller. RSSI zero is an unavailable reading, not a strong signal.
class PtuSelectionTile extends StatelessWidget {
  const PtuSelectionTile({
    super.key,
    required this.ptu,
    required this.selected,
    required this.onChanged,
    this.result,
    this.blocked = false,
    this.onReset,
    this.blockedText,
    this.resetLabel,
    this.status,
    this.statusText,
  });

  /// Round 21: this PTU's step 8 assignment; with [statusText] it replaces
  /// [result] on the row (the details sheet keeps both and the raw failure).
  final AssignStatus? status;
  final String? statusText;

  final Map<String, dynamic> ptu;
  final bool selected;
  final ValueChanged<bool>? onChanged;
  final String? result;

  /// 星狀模式：此 PTU 編號已在其他閘道器的範圍內，不可直接勾選。
  final bool blocked;

  /// 「重置並納入」：把編號清掉並重新掃描，讓 [blocked] 的裝置可被勾選。
  final VoidCallback? onReset;

  /// [blocked] 時的說明：後端確認已登記才是「已屬於其他閘道器」；自動重置
  /// 失敗時改為「重置失敗…」。null＝預設「已屬於其他閘道器」（跟著語言）。
  final String? blockedText;

  /// [onReset] 按鈕文字（重置失敗時為「重試」）；null＝預設「重置並納入」。
  final String? resetLabel;

  String get title {
    final id = (ptu['device_number'] as num?)?.toInt() ?? 0;
    return id > 0 && id != 255
        ? 'PTU #$id'
        : L10n.current.ptuSelectionTile_unassigned;
  }

  void _showDetails(BuildContext context) {
    final rssi = ptu['rssi'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (context) {
        final l10n = context.l10n;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                SelectableText(l10n.ptuSelectionTile_mac('${ptu['mac']}')),
                if (ptu['name'] != null)
                  Text(l10n.ptuSelectionTile_name('${ptu['name']}')),
                Text(
                  ptu['connected'] == true
                      ? l10n.ptuSelectionTile_connectedHere
                      : l10n.ptuSelectionTile_peripheralNotConnected,
                ),
                Text(
                  l10n.ptuSelectionTile_signal(
                    rssi is num && rssi < 0
                        ? '$rssi dBm'
                        : l10n.ptuSelectionTile_noReading,
                  ),
                ),
                Text(l10n.ptuSelectionTile_readingState(ptuRssiText(ptu))),
                Text(l10n.ptuSelectionTile_snapshotNote),
                if (statusText != null)
                  Text(l10n.ptuSelectionTile_status(statusText!)),
                if (result?.isNotEmpty == true && result != statusText)
                  Text(result!),
                if (status?.detail?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.ptuSelectionTile_detailTitle,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  SelectableText(
                    status!.detail!,
                    key: const Key('ptu-assign-detail'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.common_close),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
          : Colors.transparent,
      child: Row(
        children: [
          Checkbox(
            value: selected,
            semanticLabel: l10n.ptuSelectionTile_selectSemantic(
              title,
              '${ptu['mac']}',
            ),
            onChanged: onChanged == null
                ? null
                : (value) => onChanged!(value ?? false),
          ),
          Expanded(
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(!selected),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // 1.0.0+10: a list row's title (titleMedium w700).
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          ptu['connected'] == true
                              ? l10n.ptuSelectionTile_connected
                              : l10n.ptuSelectionTile_notConnected,
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          ptuRssiText(ptu),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Text(
                      ptu['mac'].toString(),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (blocked)
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            blockedText ?? l10n.ptuSelectionTile_blocked,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                          if (onReset != null)
                            TextButton(
                              onPressed: onReset,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                resetLabel ?? l10n.ptuSelectionTile_reset,
                              ),
                            ),
                        ],
                      ),
                    if (statusText != null && status != null)
                      AssignStatusLine(status: status!, text: statusText!)
                    else if (result?.isNotEmpty == true)
                      Text(result!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.ptuSelectionTile_infoTooltip(title),
            onPressed: () => _showDetails(context),
            icon: const Icon(Icons.info_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Round 21: a PTU row's assignment status — a spinner while the APP works
/// on it (first try or an automatic retry), a mark once done or failed.
class AssignStatusLine extends StatelessWidget {
  const AssignStatusLine({super.key, required this.status, required this.text});

  final AssignStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = switch (status.phase) {
      AssignPhase.waiting => colors.onSurfaceVariant,
      AssignPhase.assigning => colors.primary,
      AssignPhase.linkRetry ||
      AssignPhase.retry ||
      AssignPhase.busy => colors.tertiary,
      AssignPhase.done => colors.primary,
      AssignPhase.failed => colors.error,
    };
    final Widget mark = status.active
        ? SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : Icon(
            switch (status.phase) {
              AssignPhase.done => Icons.check_circle_outline,
              AssignPhase.failed => Icons.error_outline,
              _ => Icons.schedule,
            },
            size: 14,
            color: color,
          );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              key: const Key('ptu-assign-status'),
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
