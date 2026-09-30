import 'package:flutter/material.dart';

import '../core/station_change.dart';
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
    final guidance = switch (progress.stage) {
      StationChangeStage.applying => '套用站號後，閘道器會重新啟動。請保持靠近，APP 會自動重新連線。',
      StationChangeStage.restarting || StationChangeStage.reconnecting =>
        '這是套用站號時的正常重啟，藍牙會短暫中斷。請保持靠近，APP 會自動重新連線。',
      StationChangeStage.confirming => '已重新連線，正在確認新站號與 Wi-Fi。確認完成後會自動繼續。',
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
                    '站點 ${progress.site} · 閘道器 ${progress.gateway}',
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
