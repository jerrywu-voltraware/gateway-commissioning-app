import 'package:flutter/material.dart';

import '../application/connection_status.dart';
import '../core/progress_checklist.dart';
import '../l10n/l10n.dart';
import 'connection_status_panel.dart';

/// 09-28: an automatic step as a checklist that fills in one item at a
/// time ([Checklist]): a grey circle (pending), a spinner and 「進行中…」
/// (running), a green tick with its result or time (done), a red cross
/// with the reason (failed; the page's red box below keeps the full text
/// and its retry). A mark that changes scales in briefly; the running row
/// is highlighted, so the progress moves down the list.
///
/// One line per item (its note after the label, wrapping on a narrow
/// phone), so the list stays short above the page's own content.
///
/// [animate]: the running item spins (only while a run is going — the
/// network check waits on the gateway with nothing running; it then shows
/// an hourglass). [footer]: e.g. 「最多等待 68 秒」, in small print.
class ProgressChecklist extends StatelessWidget {
  const ProgressChecklist({
    super.key,
    required this.items,
    this.animate = true,
    this.footer,
  });

  final List<CheckItem> items;
  final bool animate;
  final String? footer;

  static const _duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items) _row(context, item),
          if (footer case final text?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
              child: Text(
                text,
                key: const Key('checklist-footer'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, CheckItem item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final note = noteText(item);
    final background = switch (item.status) {
      CheckStatus.running => colors.primaryContainer.withValues(alpha: 0.45),
      CheckStatus.failed => colors.errorContainer.withValues(alpha: 0.6),
      _ => colors.primaryContainer.withValues(alpha: 0),
    };
    final labelStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: item.status == CheckStatus.pending
              ? colors.onSurfaceVariant
              : colors.onSurface,
          fontWeight: item.status == CheckStatus.running
              ? FontWeight.w700
              : FontWeight.w400,
        );
    final noteColor = switch (item.status) {
      CheckStatus.done => toneColor(context, StatusTone.ok),
      CheckStatus.failed => colors.error,
      CheckStatus.running => colors.primary,
      CheckStatus.pending => colors.onSurfaceVariant,
    };
    return AnimatedContainer(
      key: ValueKey('check-item-${item.id}'),
      duration: _duration,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: AnimatedSwitcher(
              duration: _duration,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: _mark(context, item),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: _duration,
              style: labelStyle,
              child: Text.rich(
                key: ValueKey('check-text-${item.id}'),
                TextSpan(
                  children: [
                    TextSpan(text: item.label),
                    if (note.isNotEmpty)
                      TextSpan(
                        text: '  $note',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: noteColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mark(BuildContext context, CheckItem item) {
    final colors = Theme.of(context).colorScheme;
    final key = ValueKey('check-${item.id}-${item.status.name}');
    return switch (item.status) {
      CheckStatus.pending => Icon(
        Icons.radio_button_unchecked,
        key: key,
        size: 20,
        color: colors.outline,
      ),
      CheckStatus.running =>
        animate
            ? Padding(
                key: key,
                padding: const EdgeInsets.all(2),
                child: const CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Icon(
                Icons.hourglass_top,
                key: key,
                size: 20,
                color: colors.primary,
              ),
      CheckStatus.done => Icon(
        Icons.check_circle,
        key: key,
        size: 20,
        color: toneColor(context, StatusTone.ok),
      ),
      CheckStatus.failed => Icon(
        Icons.cancel,
        key: key,
        size: 20,
        color: colors.error,
      ),
    };
  }

  /// What follows an item's label: 「進行中…」 (with its progress), the
  /// result or the time it was done, or the reason it failed.
  static String noteText(CheckItem item) => switch (item.status) {
    CheckStatus.pending => '',
    CheckStatus.running =>
      item.note.isEmpty
          ? L10n.current.uiProgressChecklist_running
          : L10n.current.uiProgressChecklist_runningNote(item.note),
    CheckStatus.done =>
      item.note.isNotEmpty
          ? item.note
          : item.at == null
          ? ''
          : L10n.current.uiProgressChecklist_doneAt(_clock(item.at!)),
    CheckStatus.failed => item.note,
  };

  static String _clock(DateTime t) =>
      [t.hour, t.minute, t.second].map((v) => '$v'.padLeft(2, '0')).join(':');
}
