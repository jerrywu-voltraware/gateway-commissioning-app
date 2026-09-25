import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/commissioning_controller.dart';
import '../application/topology_settings.dart';
import '../core/direct_mode.dart';
import '../core/ptu_rssi.dart';

/// Step 7 (direct mode, firmware 1.7.20+): the PTU the gateway itself
/// picked — MAC, RSSI and why (`select_reason`). Round 15: no list to tick;
/// the nearby candidates (≤ 5) only appear under 「不是這台？」, where a tap
/// makes the gateway switch (a binding) so the installer can identify it.
/// Hidden for firmware without `direct` (the page keeps the old list).
class DirectStatusPanel extends ConsumerStatefulWidget {
  const DirectStatusPanel({super.key});

  @override
  ConsumerState<DirectStatusPanel> createState() => _DirectStatusPanelState();
}

class _DirectStatusPanelState extends ConsumerState<DirectStatusPanel> {
  bool _others = false;

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
    final hint = direct?.state.hint;
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
              Text(
                picked,
                key: const Key('direct-linked'),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                row != null
                    ? ptuRssiText(row)
                    : direct.ptuRssi != null && direct.ptuRssi! < 0
                    ? '${direct.ptuRssi} dBm'
                    : 'RSSI —',
                key: const Key('direct-rssi'),
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
                child: Text(
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
                    Text(
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
                    direct.boundMac == null ? '未綁定' : '已綁定 ${direct.boundMac}',
                  ].join(' · '),
                  style: text.bodySmall,
                ),
              ),
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
            if (picked == null)
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
            if (direct != null && direct.candidates.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('direct-not-this'),
                  icon: Icon(
                    _others ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _others = !_others),
                  label: Text(picked != null ? '不是這台？' : '改選其他 PTU'),
                ),
              ),
              if (_others) ...[
                Text(
                  '附近候選（${direct.candidates.length}）：點選後閘道器會綁定並改連那一台，'
                  '再按「辨識此樁」確認。',
                  style: text.bodySmall,
                ),
                for (final c in direct.candidates)
                  ListTile(
                    key: ValueKey('direct-candidate-${c.mac}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.mac),
                    subtitle: Text(
                      '${c.rssiText}'
                      '${c.deviceNumber != null && c.deviceNumber! > 0 ? ' · #${c.deviceNumber}' : ''}',
                    ),
                    trailing: Text(
                      picked != null && sameMac(picked, c.mac)
                          ? '目前選中'
                          : '改連這台',
                      style: TextStyle(
                        color: picked != null && sameMac(picked, c.mac)
                            ? colors.onSurfaceVariant
                            : colors.primary,
                      ),
                    ),
                    onTap:
                        state.busy ||
                            state.relinking ||
                            (picked != null && sameMac(picked, c.mac))
                        ? null
                        : () {
                            setState(() => _others = false);
                            controller.switchDirectPick(c.mac);
                          },
                  ),
              ],
            ],
          ],
        ),
      ),
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
/// note right beside it, then 「是這台，開始監控」 for the PTU the gateway
/// picked; 「重新搜尋」 while it has none.
class DirectPickActions extends ConsumerWidget {
  const DirectPickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commissionProvider);
    final controller = ref.read(commissionProvider.notifier);
    final picked = state.direct?.pickedMac;
    final shown = state.selected.firstOrNull;
    final ready = picked != null && shown != null && sameMac(picked, shown);
    final enabled = !state.busy && !state.relinking;
    // Round 15b: 是這台 only for the PTU the installer identified.
    final confirmable = directConfirmReady(state);
    if (!ready) {
      return FilledButton.icon(
        key: const Key('direct-rescan-bottom'),
        icon: const Icon(Icons.refresh, size: 20),
        onPressed: enabled ? controller.discover : null,
        label: const Text('重新搜尋'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.config['identify_supported'] == true)
          Row(
            children: [
              FilledButton.tonalIcon(
                key: const Key('direct-identify'),
                icon: const Icon(Icons.lightbulb_outline, size: 20),
                onPressed: enabled ? controller.identify : null,
                label: const Text('辨識此樁'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.identifyNote.isEmpty
                      ? '按下後請看樁上 PTU 與閘道器的燈號'
                      : state.identifyNote,
                  key: const Key('direct-identify-note'),
                  style: TextStyle(
                    color: state.identifyNote.isEmpty
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        FilledButton(
          key: const Key('direct-confirm'),
          onPressed: enabled && confirmable
              ? controller.confirmDirectPick
              : null,
          child: Text(confirmable ? '是這台，開始監控' : directIdentifyFirstLabel),
        ),
      ],
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
            // Round 15: applied by 「是這台，開始監控」 (not at once).
            SwitchListTile(
              key: const Key('direct-bind-on-confirm'),
              contentPadding: EdgeInsets.zero,
              title: const Text('確認後綁定 PTU'),
              subtitle: const Text('按「是這台，開始監控」時把該 PTU 的 MAC 存進閘道器，之後只連這台'),
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
