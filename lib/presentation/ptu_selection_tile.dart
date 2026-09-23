import 'package:flutter/material.dart';

/// Compact selection row; technical detail is available without making every
/// device row taller. RSSI zero is an unavailable reading, not a strong signal.
class PtuSelectionTile extends StatelessWidget {
  const PtuSelectionTile({
    super.key,
    required this.ptu,
    required this.selected,
    required this.onChanged,
    this.result,
  });

  final Map<String, dynamic> ptu;
  final bool selected;
  final ValueChanged<bool>? onChanged;
  final String? result;

  String get title => ((ptu['device_number'] as num?) ?? 0) > 0
      ? 'PTU #${ptu['device_number']}'
      : '未編號 PTU';

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
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SelectableText('MAC：${ptu['mac']}'),
              if (ptu['name'] != null) Text('名稱：${ptu['name']}'),
              Text(ptu['connected'] == true ? '已連線至此 Gateway' : '周邊未連線'),
              Text('訊號：${rssi is num && rssi < 0 ? '$rssi dBm' : '尚無讀值'}'),
              if (result?.isNotEmpty == true) Text(result!),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
          : Colors.transparent,
      child: Row(
        children: [
          Checkbox(
            value: selected,
            semanticLabel: '選擇 $title，${ptu['mac']}',
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
                        Text(title, style: theme.textTheme.titleSmall),
                        Text(
                          ptu['connected'] == true ? '已連線' : '未連線',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Text(
                      ptu['mac'].toString(),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (result?.isNotEmpty == true)
                      Text(result!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '$title 裝置資訊',
            onPressed: () => _showDetails(context),
            icon: const Icon(Icons.info_outline, size: 20),
          ),
        ],
      ),
    );
  }
}
