import 'package:flutter/material.dart';
import '../core/mqtt_target.dart';

/// Compact card: where the gateway uploads (MQTT target) versus the backend
/// the APP is using, with a switch button when they disagree.
class UploadTargetCard extends StatelessWidget {
  const UploadTargetCard({
    super.key,
    required this.config,
    required this.app,
    required this.enabled,
    required this.onSwitch,
    this.onRefresh,
    this.notice = '',
    this.shipCheck = false,
  });

  /// Step 7 (commissioning passed): judge the target for shipping instead of
  /// against the APP backend; a local target must be switched back.
  final bool shipCheck;

  /// Gateway config / status holding mqtt_target, mqtt_host, mqtt_port.
  final Map<String, dynamic> config;
  final AppUploadTarget app;
  final bool enabled;
  final ValueChanged<MqttTarget> onSwitch;
  final VoidCallback? onRefresh;
  final String notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final legacy = !reportsMqttTarget(config);
    final current = parseMqttTarget(config);
    final wanted = app.target;
    final connected = config['mqtt_connected'];
    final matches = current != null && wanted != null && current.sameAs(wanted);

    Widget warning(String text) => Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      color: colors.errorContainer,
      child: Text(text, style: TextStyle(color: colors.onErrorContainer)),
    );

    final children = <Widget>[
      Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Gateway 上傳目標', style: theme.textTheme.titleSmall),
          ),
          if (!legacy && onRefresh != null)
            TextButton(
              onPressed: enabled ? onRefresh : null,
              child: const Text('重新讀取'),
            ),
        ],
      ),
      const SizedBox(height: 4),
    ];

    if (legacy) {
      children.add(Text(legacyTargetText(config['fw_version'])));
      if (app.wantsLocal) {
        children.add(
          warning('APP 目前選擇本地測試站，但這台 Gateway 只會上傳正式站，第 7 步資料驗證將無法通過。'),
        );
      }
    } else {
      final mqtt = switch (connected) {
        true => ' · MQTT 已連線',
        false => ' · MQTT 未連線',
        _ => '',
      };
      final unconfirmed = config['mqtt_target'] == unconfirmedMqttTarget;
      children.add(
        Text(
          '目前：${current?.label ?? (unconfirmed ? '未確認（切換結果尚未讀回，請重新連線後按「重新讀取」）' : '無法辨識（${config['mqtt_target']}）')}$mqtt',
        ),
      );
      if (shipCheck) {
        if (current?.isLocal == true) {
          children.add(warning(localTargetShipWarning));
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: enabled
                      ? () => onSwitch(const MqttTarget.production())
                      : null,
                  child: const Text('將 Gateway 切回正式站'),
                ),
              ),
            ),
          );
        } else if (current != null) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                wanted?.isLocal == true
                    ? '已上傳到正式站，可出貨；APP 目前連的本地測試站不會再收到此 Gateway 的資料。'
                    : '已上傳到正式站，可出貨。',
              ),
            ),
          );
        }
      } else if (app.error != null) {
        children.add(warning(app.error!));
      } else if (wanted == null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'APP 的後端網址無法對應到 Gateway 上傳目標，僅顯示目前設定。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        );
      } else if (matches) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text('與 APP 連線環境一致（${wanted.label}）')),
              ],
            ),
          ),
        );
      } else {
        children.add(
          warning(
            'Gateway 目前上傳到${current?.label ?? '無法辨識的目標'}，'
            '但 APP 連線的是${wanted.label}；資料不會進入 APP 所連的後端，'
            '第 7 步資料驗證將無法通過。',
          ),
        );
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: enabled ? () => onSwitch(wanted) : null,
                child: Text('將 Gateway 切換到${wanted.shortLabel}'),
              ),
            ),
          ),
        );
      }
    }
    if (notice.isNotEmpty) {
      children.add(
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(notice)),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Asks before switching: explains the effect on the production site and
/// the reboot / BLE reconnect.
Future<bool> confirmUploadTargetSwitch(
  BuildContext context, {
  required MqttTarget wanted,
  MqttTarget? current,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('切換 Gateway 上傳目標'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '將 Gateway 的資料上傳目標從「${current?.label ?? '目前設定'}」切換到「${wanted.label}」。',
            ),
            const SizedBox(height: 12),
            Text(
              wanted.isLocal
                  ? '切換到本地後，正式站將收不到這台 Gateway 的資料，直到切回正式站為止。'
                  : '切回正式站後，本地後端將不再收到這台 Gateway 的資料。',
            ),
            const SizedBox(height: 12),
            const Text(
              'Gateway 會在收到指令約 1.5 秒後重新開機，藍牙連線會中斷；'
              'APP 會自動重新連線並讀回設定確認，整個過程可能需要約 1 分鐘（最多 2 分鐘）。'
              '期間請留在 Gateway 旁邊，不要關閉 APP。',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('確認切換'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
