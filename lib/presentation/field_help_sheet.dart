import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/field_report.dart';
import '../application/topology_settings.dart';
import '../core/gateway_identity.dart';
import '../l10n/l10n.dart';
import 'field_support_panel.dart';

/// 「請後台協助」: the help button (red box, AppBar) and the sheet's title.
String get fieldHelpLabel => L10n.current.fieldHelpSheet_label;

/// The help report reached the back office.
String get fieldHelpSentText => L10n.current.fieldHelpSheet_sent;

/// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §5.3): asks the
/// controller to send a help report and opens [FieldHelpSheet]. The sheet
/// opens at once; the upload goes on behind it.
Future<void> openFieldHelp(BuildContext context, WidgetRef ref) {
  final controller = ref.read(commissionProvider.notifier);
  if (ref.read(fieldHelpProvider).sessionId == null) {
    unawaited(controller.requestHelp());
  }
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
    final l10n = context.l10n;
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
        l10n.fieldHelpSheet_queued(
          help.reason.isEmpty ? l10n.fieldHelpSheet_queuedNoReason : help.reason,
        ),
        colors.error,
      ),
      FieldHelpPhase.unsupported => (
        l10n.fieldHelpSheet_unsupported,
        colors.error,
      ),
      FieldHelpPhase.needsConnection => (
        l10n.fieldHelpSheet_needsConnection,
        colors.error,
      ),
      FieldHelpPhase.disabled => (
        l10n.fieldHelpSheet_demo,
        colors.onSurfaceVariant,
      ),
      FieldHelpPhase.idle ||
      FieldHelpPhase.sending => (
        l10n.fieldHelpSheet_sending,
        colors.onSurfaceVariant,
      ),
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
                label: Text(l10n.fieldHelpSheet_resend),
              ),
            ),
          if (help.phase == FieldHelpPhase.sent && help.sessionId != null)
            FieldSupportPanel(
              key: ValueKey('${env.base}/${help.sessionId}'),
              sessionId: help.sessionId!,
              currentGatewayMac: gatewayWifiMac(
                uid: state.config['gateway_uid'],
                bleId: state.peer?.id,
              ),
              onRequestAgain: () => unawaited(
                ref.read(commissionProvider.notifier).requestHelp(),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            l10n.fieldHelpSheet_readOut,
            key: const Key('field-help-read'),
            // 1.0.0+10: a section title (titleSmall w600).
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
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
                title: Text(
                  l10n.fieldHelpSheet_details,
                  style: theme.textTheme.bodyMedium,
                ),
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
                  l10n.fieldHelpSheet_noPassword,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              TextButton(
                key: const Key('field-help-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.common_close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
