import 'package:flutter/material.dart';
import '../core/ptu_rssi.dart';

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
    this.blockedText = '已屬於其他閘道器',
    this.resetLabel = '重置並納入',
  });

  final Map<String, dynamic> ptu;
  final bool selected;
  final ValueChanged<bool>? onChanged;
  final String? result;

  /// 星狀模式：此 PTU 編號已在其他閘道器的範圍內，不可直接勾選。
  final bool blocked;

  /// 「重置並納入」：把編號清掉並重新掃描，讓 [blocked] 的裝置可被勾選。
  final VoidCallback? onReset;

  /// [blocked] 時的說明：後端確認已登記才是「已屬於其他閘道器」；自動重置
  /// 失敗時改為「重置失敗…」。
  final String blockedText;

  /// [onReset] 按鈕文字（重置失敗時為「重試」）。
  final String resetLabel;

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
              Text('讀值狀態：${ptuRssiText(ptu)}'),
              const Text('此處為開啟時的讀值；動態數值請看清單。'),
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
                            blockedText,
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
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(resetLabel),
                            ),
                        ],
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
