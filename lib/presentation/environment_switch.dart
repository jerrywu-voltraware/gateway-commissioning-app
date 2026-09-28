import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../core/local_backend_address.dart';
import 'local_backend_field.dart';

Color envColor(BuildContext context, BackendEnv env) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (env) {
    BackendEnv.local => dark ? Colors.amber.shade300 : Colors.orange.shade800,
    BackendEnv.production =>
      dark ? Colors.green.shade300 : Colors.green.shade700,
    BackendEnv.custom => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

/// AppBar chip showing the current environment; tap to switch.
class EnvironmentChip extends ConsumerWidget {
  const EnvironmentChip({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(backendEnvProvider).environment;
    final color = envColor(context, env);
    return Tooltip(
      message: '切換連線環境',
      child: ActionChip(
        key: const Key('env-chip'),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: color),
        avatar: Icon(Icons.circle, size: 12, color: color),
        label: Text(
          envLabel(env),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// Why a switch is refused while [s] is busy. 「取消操作」 is named only
/// where the page has that button (after the 準備 step).
String switchBlockedText(CommissionState s) =>
    '正在進行「${s.message}」，${s.step > 0 ? '完成或按「取消操作」後' : '完成後'}才能切換。';

/// Bottom sheet with 本地測試 / 正式站 / 其他網址. Returns the chosen
/// environment (its local IP or URL already stored), or null.
Future<BackendEnv?> showEnvironmentSheet(BuildContext context) =>
    showModalBottomSheet<BackendEnv>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const _EnvironmentSheet(),
    );

class _EnvironmentSheet extends ConsumerStatefulWidget {
  const _EnvironmentSheet();
  @override
  ConsumerState<_EnvironmentSheet> createState() => _EnvironmentSheetState();
}

class _EnvironmentSheetState extends ConsumerState<_EnvironmentSheet> {
  late final TextEditingController _host;
  late final TextEditingController _url;

  /// Staged like the IP: applied only by 「使用本地測試」.
  late int _port;

  /// Which environment's address is being filled in inside the sheet.
  BackendEnv? _editing;

  @override
  void initState() {
    super.initState();
    final env = ref.read(backendEnvProvider);
    _host = TextEditingController(text: env.localHost);
    _url = TextEditingController(text: env.customUrl);
    _port = env.localPort;
  }

  @override
  void dispose() {
    _host.dispose();
    _url.dispose();
    super.dispose();
  }

  void _choose(BackendEnv choice) {
    final env = ref.read(backendEnvProvider);
    if (choice == BackendEnv.local && !env.localValid) {
      setState(() => _editing = BackendEnv.local);
      return;
    }
    if (choice == BackendEnv.custom && env.customUrl.trim().isEmpty) {
      setState(() => _editing = BackendEnv.custom);
      return;
    }
    Navigator.pop(context, choice);
  }

  void _useLocal() {
    ref.read(backendEnvProvider.notifier)
      ..setLocalPort(_port)
      ..setLocalHost(_host.text.trim());
    Navigator.pop(context, BackendEnv.local);
  }

  void _useCustom() {
    ref.read(backendEnvProvider.notifier).setCustomUrl(_url.text.trim());
    Navigator.pop(context, BackendEnv.custom);
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(backendEnvProvider);
    final commission = ref.watch(commissionProvider);
    final busy = commission.busy;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final localAllowed = ref.read(envSwitchPolicyProvider).localAllowed;

    Widget option(
      BackendEnv value,
      String description, {
      bool available = true,
    }) {
      final selected = env.environment == value;
      final off = busy || !available;
      final color = envColor(context, value);
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? color : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: Key('env-option-${value.name}'),
          borderRadius: BorderRadius.circular(12),
          onTap: off ? null : () => _choose(value),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.circle, size: 14, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        available ? envLabel(value) : localUnavailableLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: off ? colors.onSurfaceVariant : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check, color: color),
              ],
            ),
          ),
        ),
      );
    }

    final children = <Widget>[
      Text('切換連線環境', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        '手機和已連上的 Gateway 會一起切換。',
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      if (busy)
        Container(
          key: const Key('env-sheet-busy'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          color: colors.secondaryContainer,
          child: Text(
            switchBlockedText(commission),
            style: TextStyle(color: colors.onSecondaryContainer),
          ),
        ),
      option(
        BackendEnv.local,
        !localAllowed
            ? localUnavailableText
            : env.localValid
            ? '資料送到這台電腦上的測試主機（${env.localHost}）'
            : '資料送到這台電腦上的測試主機（還沒設定電腦 IP）',
        available: localAllowed,
      ),
      if (!localAllowed)
        const SizedBox.shrink()
      else if (_editing == BackendEnv.local) ...[
        Text(env.localValid ? '可修改測試主機的 IP：' : '還沒有測試主機的 IP，請按「自動尋找」或直接輸入。'),
        const SizedBox(height: 8),
        LocalBackendField(
          hostController: _host,
          port: _port,
          enabled: !busy,
          onPortChanged: (port) => setState(() => _port = port),
          onHostPicked: () => setState(() {}),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _host,
          builder: (context, value, _) => FilledButton(
            onPressed: !busy && localHostError(value.text) == null
                ? _useLocal
                : null,
            child: const Text('使用本地測試'),
          ),
        ),
        const SizedBox(height: 12),
      ] else if (env.localValid)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy
                ? null
                : () => setState(() => _editing = BackendEnv.local),
            child: const Text('變更電腦 IP'),
          ),
        ),
      option(BackendEnv.production, '資料送到正式站，客戶看得到'),
      option(
        BackendEnv.custom,
        env.customUrl.trim().isEmpty
            ? '使用自訂的後端網址（尚未設定）'
            : '使用自訂的後端網址：${env.customUrl.trim()}',
      ),
      if (_editing == BackendEnv.custom) ...[
        BackendUrlField(controller: _url, label: '後端網址'),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _url,
          builder: (context, value, _) => FilledButton(
            onPressed:
                !busy && Uri.tryParse(value.text.trim())?.hasAuthority == true
                ? _useCustom
                : null,
            child: const Text('使用這個網址'),
          ),
        ),
        const SizedBox(height: 12),
      ],
      SwitchListTile(
        key: const Key('auto-sync-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('連線 Gateway 時自動同步上傳目標'),
        subtitle: const Text('連上 Gateway 後，自動讓它把資料送到和手機相同的地方'),
        value: env.autoSync,
        onChanged: (value) =>
            ref.read(backendEnvProvider.notifier).setAutoSync(value),
      ),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
