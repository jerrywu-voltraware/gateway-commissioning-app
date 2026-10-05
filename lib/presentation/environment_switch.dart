import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../core/local_backend_address.dart';
import '../l10n/l10n.dart';
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

/// 1.0.0+8: the start page's 正式站 line (no more 「客戶看得到」).
String get productionHintText => L10n.current.environmentSwitch_productionHint;

/// The sheet's 正式站 option description.
String get productionSheetHint =>
    L10n.current.environmentSwitch_productionSheetHint;

/// AppBar chip showing the current environment; tap to switch.
class EnvironmentChip extends ConsumerWidget {
  const EnvironmentChip({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(backendEnvProvider).environment;
    final color = envColor(context, env);
    return Tooltip(
      message: context.l10n.environmentSwitch_title,
      // 1.0.0+9: compact — the AppBar title must stay whole at 360 dp
      // beside it. 1.0.0+10: labelMedium (no fixed size), a smaller dot
      // box and less padding (the title whole at text scale 1.3).
      child: ActionChip(
        key: const Key('env-chip'),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        avatarBoxConstraints: const BoxConstraints.tightFor(
          width: 12,
          height: 12,
        ),
        side: BorderSide(color: color),
        avatar: Icon(Icons.circle, size: 8, color: color),
        label: Text(
          envLabel(env),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// Why a switch is refused while [s] is busy. 「取消操作」 is named only
/// where the page has that button (after the 準備 step).
String switchBlockedText(CommissionState s) => s.step > 0
    ? L10n.current.environmentSwitch_blocked(s.message)
    : L10n.current.environmentSwitch_blockedPrep(s.message);

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
    final l10n = context.l10n;

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
                          fontWeight: FontWeight.w700,
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
      Text(l10n.environmentSwitch_title, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        l10n.environmentSwitch_sheetSubtitle,
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
            ? l10n.environmentSwitch_localWithHost(env.localHost)
            : l10n.environmentSwitch_localNoHost,
        available: localAllowed,
      ),
      if (!localAllowed)
        const SizedBox.shrink()
      else if (_editing == BackendEnv.local) ...[
        Text(
          env.localValid
              ? l10n.environmentSwitch_editIp
              : l10n.environmentSwitch_noIp,
        ),
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
            child: Text(l10n.environmentSwitch_useLocal),
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
            child: Text(l10n.environmentSwitch_changeIp),
          ),
        ),
      option(BackendEnv.production, productionSheetHint),
      option(
        BackendEnv.custom,
        env.customUrl.trim().isEmpty
            ? l10n.environmentSwitch_customNotSet
            : l10n.environmentSwitch_customUrl(env.customUrl.trim()),
      ),
      if (_editing == BackendEnv.custom) ...[
        BackendUrlField(
          controller: _url,
          label: l10n.environmentSwitch_urlLabel,
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _url,
          builder: (context, value, _) => FilledButton(
            onPressed:
                !busy && Uri.tryParse(value.text.trim())?.hasAuthority == true
                ? _useCustom
                : null,
            child: Text(l10n.environmentSwitch_useUrl),
          ),
        ),
        const SizedBox(height: 12),
      ],
      // 1.0.0+8: the 「連線 Gateway 時自動同步上傳目標」 switch is gone;
      // the gateway's target is changed only by 「同步」 in the status
      // panel or an explicit environment switch ([EnvSwitchPolicy.autoSyncDefault]).
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
