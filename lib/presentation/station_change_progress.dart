import 'package:flutter/material.dart';

import '../core/station_change.dart';
import '../l10n/l10n.dart';
import 'progress_checklist.dart';

/// A focused view of an intentional restart, driven by controller events.
class StationChangeProgress extends StatelessWidget {
  const StationChangeProgress({super.key, required this.progress});

  final StationChange progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final icon = switch (progress.stage) {
      StationChangeStage.applying => Icons.save_outlined,
      StationChangeStage.restarting => Icons.restart_alt,
      StationChangeStage.reconnecting => Icons.bluetooth_searching,
      StationChangeStage.confirming => Icons.fact_check_outlined,
    };
    final l10n = context.l10n;
    final guidance = switch (progress.stage) {
      StationChangeStage.applying => l10n.stationChangeProgress_applying,
      StationChangeStage.restarting || StationChangeStage.reconnecting =>
        l10n.stationChangeProgress_restarting,
      StationChangeStage.confirming => l10n.stationChangeProgress_confirming,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      icon,
                      key: ValueKey(progress.stage),
                      color: colors.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.stationChangeProgress_target(
                      progress.site,
                      progress.gateway,
                    ),
                    key: const Key('station-change-target'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(guidance, key: const Key('station-change-guidance')),
            ),
            const SizedBox(height: 16),
            ProgressChecklist(
              key: const Key('station-change-checklist'),
              items: progress.items,
            ),
          ],
        ),
      ),
    );
  }
}
