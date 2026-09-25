import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/commissioning_controller.dart';
import '../core/direct_mode.dart';
import '../core/ptu_rssi.dart';

/// Step 7 (direct mode, firmware 1.7.20+): what the gateway reports about
/// its own nearest-PTU choice. Hidden for firmware without `direct`.
class DirectStatusPanel extends ConsumerWidget {
  const DirectStatusPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commissionProvider);
    final direct = state.direct;
    if (direct == null) return const SizedBox.shrink();
    final controller = ref.read(commissionProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final linked = state.ptus
        .where((p) => p['connected'] == true && p['mac'] != null)
        .firstOrNull;
    final hint = direct.state.hint;
    return Card(
      key: const Key('direct-status'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '閘道器回報：${direct.state.label}',
              key: const Key('direct-state'),
              style: text.titleSmall,
            ),
            if (direct.state == DirectState.connected && linked != null)
              Text(
                'PTU ${linked['mac']} · ${ptuRssiText(linked)}',
                key: const Key('direct-linked'),
              ),
            Text(
              [
                if (direct.minRssi != null) '門檻 ${direct.minRssi} dBm',
                direct.boundMac == null ? '未綁定' : '已綁定 ${direct.boundMac}',
              ].join(' · '),
              style: text.bodySmall,
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
            if (direct.state == DirectState.boundMissing)
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
            if (direct.candidates.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('附近候選（${direct.candidates.length}）', style: text.bodySmall),
              for (final c in direct.candidates)
                Text(
                  '${c.mac} · ${c.rssiText}'
                  '${c.deviceNumber != null && c.deviceNumber! > 0 ? ' · #${c.deviceNumber}' : ''}',
                  key: ValueKey('direct-candidate-${c.mac}'),
                  style: text.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Advanced direct-mode settings (next to the topology menu): the gateway's
/// auto-connect threshold and binding to the PTU connected now. Each change
/// is sent with set_config at once.
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('直連進階設定', style: Theme.of(context).textTheme.titleMedium),
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
