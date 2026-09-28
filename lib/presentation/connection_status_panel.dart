import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/connection_status.dart';
import '../core/mqtt_target.dart';

Color toneColor(BuildContext context, StatusTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final colors = Theme.of(context).colorScheme;
  return switch (tone) {
    StatusTone.ok => dark ? Colors.green.shade300 : Colors.green.shade800,
    StatusTone.pending => dark ? Colors.amber.shade300 : Colors.amber.shade900,
    StatusTone.warn =>
      dark ? Colors.orange.shade300 : Colors.deepOrange.shade700,
    StatusTone.bad => colors.error,
    StatusTone.neutral => colors.onSurfaceVariant,
  };
}

/// 「連線狀態」: where the phone and the gateway are connected, in plain
/// words, with one hint and the technical details collapsed.
class ConnectionStatusPanel extends ConsumerStatefulWidget {
  const ConnectionStatusPanel({
    super.key,
    required this.state,
    required this.env,
    required this.onSync,
    required this.onRefresh,
    this.demo = false,
  });
  final CommissionState state;
  final BackendEnvState env;
  final bool demo;

  /// 「同步」: bring the gateway in line with the APP environment.
  final VoidCallback onSync;
  final VoidCallback onRefresh;

  @override
  ConsumerState<ConnectionStatusPanel> createState() =>
      _ConnectionStatusPanelState();
}

class _ConnectionStatusPanelState extends ConsumerState<ConnectionStatusPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = widget.env.base;
    final probe = widget.demo
        ? null
        : ref.watch(backendProbeProvider(base)).value;
    final status = connectionStatus(
      env: widget.env,
      state: widget.state,
      probe: probe,
      demo: widget.demo,
    );
    final enabled = !widget.state.busy;

    void refresh() {
      if (!widget.demo) ref.invalidate(backendProbeProvider(base));
      widget.onRefresh();
    }

    if (status.allOk && !_expanded) {
      return Card(
        key: const Key('connection-status-ok'),
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => setState(() => _expanded = true),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status.summary!,
                    style: TextStyle(color: toneColor(context, StatusTone.ok)),
                  ),
                ),
                const Icon(Icons.expand_more, semanticLabel: '展開'),
              ],
            ),
          ),
        ),
      );
    }

    Widget row(String title, StatusRow value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              Text(
                value.where,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (value.status.isNotEmpty)
                Text(
                  value.status,
                  style: TextStyle(color: toneColor(context, value.tone)),
                ),
            ],
          ),
        ],
      ),
    );

    final children = <Widget>[
      Row(
        children: [
          const Icon(Icons.sensors, size: 20),
          const SizedBox(width: 8),
          // 1.0.0+10: a card title (titleSmall w700).
          Expanded(
            child: Text(
              '連線狀態',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (status.allOk)
            IconButton(
              tooltip: '收合',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _expanded = false),
              icon: const Icon(Icons.expand_less),
            ),
          IconButton(
            key: const Key('connection-status-refresh'),
            tooltip: '重新讀取',
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      row('手機 → 後端', status.phone),
      row('Gateway → 資料上傳', status.gateway),
      if (status.wifiWeak != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            status.wifiWeak!,
            key: const Key('status-wifi-weak'),
            style: TextStyle(color: toneColor(context, StatusTone.bad)),
          ),
        ),
    ];
    if (status.hint != null) {
      children.add(
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          color: colors.secondaryContainer,
          child: Text(
            status.hint!,
            style: TextStyle(color: colors.onSecondaryContainer),
          ),
        ),
      );
    }
    if (status.need == SyncNeed.sync) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: enabled ? widget.onSync : null,
              child: const Text('同步'),
            ),
          ),
        ),
      );
    }
    // Round 29: 「出貨前切回正式站」 is no longer here (field drill: its red
    // box and full-width button read as the done page's next step); the
    // done page of a local test build carries it as a developer note.
    if (widget.state.uploadNotice.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(widget.state.uploadNotice),
        ),
      );
    }
    children.add(
      Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('technical-details'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            '技術細節',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          children: [
            SelectableText(
              status.details.join('\n'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );

    return Card(
      key: const Key('connection-status'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Release builds: one short question before the gateway reboots into a new
/// upload target.
Future<bool> confirmUploadTargetSwitch(
  BuildContext context, {
  required MqttTarget wanted,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('同時切換 Gateway？'),
      content: Text(
        'Gateway 會改把資料送到${wanted.plainLabel}，並重新開機約 1 分鐘，'
        '期間請留在 Gateway 旁。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('先不要'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('切換'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
