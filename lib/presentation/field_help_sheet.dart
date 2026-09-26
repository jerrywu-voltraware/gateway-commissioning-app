import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/field_report.dart';
import '../application/topology_settings.dart';

/// 「請後台協助」: the help button (red box, AppBar) and the sheet's title.
const fieldHelpLabel = '請後台協助';

/// The help report reached the back office.
const fieldHelpSentText = '✓ 已通知後台';

/// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §5.3): asks the
/// controller to send a help report and opens [FieldHelpSheet]. The sheet
/// opens at once; the upload goes on behind it.
Future<void> openFieldHelp(BuildContext context, WidgetRef ref) {
  final controller = ref.read(commissionProvider.notifier);
  unawaited(controller.requestHelp());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const FieldHelpSheet(),
  );
}

/// 「請後台協助」: whether the back office has been told (「已通知後台」,
/// with the current situation) and — always, sent or not — what to tell
/// them on the phone. v1.1: no help code (user decision: the installer is
/// already on the phone; the back office finds the session by site,
/// gateway or name).
class FieldHelpSheet extends ConsumerWidget {
  const FieldHelpSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final help = ref.watch(fieldHelpProvider);
    final state = ref.watch(commissionProvider);
    final env = ref.watch(backendEnvProvider);
    final topology = ref.watch(topologyProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lines = fieldHelpLines(
      FieldInput(
        state: state,
        env: env,
        directMode: topology.topology.isDirect,
        targetCount: topology.targetCount,
        loggedIn: state.loggedIn,
      ),
      errorCode: help.errorCode,
    );
    final details = fieldHelpDetailLines(errorCode: help.errorCode);
    final (statusText, statusColor) = switch (help.phase) {
      FieldHelpPhase.sent => (fieldHelpSentText, colors.primary),
      FieldHelpPhase.queued => (
        '⚠ 目前送不出去（${help.reason.isEmpty ? '沒有網路／尚未登入後台' : help.reason}），'
            '後台暫時看不到。請在電話中直接唸下面的資訊。',
        colors.error,
      ),
      FieldHelpPhase.unsupported => ('後台版本還不支援線上通知，請直接唸下面的資訊。', colors.error),
      FieldHelpPhase.disabled => (
        '示範模式不會傳送，請直接唸下面的資訊。',
        colors.onSurfaceVariant,
      ),
      FieldHelpPhase.idle ||
      FieldHelpPhase.sending => ('正在通知後台…', colors.onSurfaceVariant),
    };
    return SingleChildScrollView(
      key: const Key('field-help-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fieldHelpLabel, style: theme.textTheme.titleLarge),
          const Divider(),
          Text(
            statusText,
            key: const Key('field-help-status'),
            style: theme.textTheme.titleMedium?.copyWith(color: statusColor),
          ),
          if (help.phase == FieldHelpPhase.queued)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('field-help-resend'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () =>
                    ref.read(commissionProvider.notifier).resendHelp(),
                label: const Text('重新傳送'),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '請唸給後台：',
            key: const Key('field-help-read'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('・$line'),
            ),
          // Round 24: the code's wire name only here, folded (the lines
          // above say it in words).
          if (details.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('field-help-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                expandedAlignment: Alignment.centerLeft,
                title: Text('詳細資訊', style: theme.textTheme.bodyMedium),
                children: [
                  for (final line in details)
                    SelectableText(
                      line,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            )
          else
            const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '不會傳送 Wi-Fi 密碼。',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              TextButton(
                key: const Key('field-help-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('關閉'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
