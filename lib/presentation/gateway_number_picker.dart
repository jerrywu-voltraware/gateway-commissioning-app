import 'package:flutter/material.dart';

import '../core/gateway_topology.dart' show kMaxGatewayId;

/// 1.0.0+12 (field: the automatic number did not match the label on the
/// pile, and could not be changed): 〔修改〕 beside 「將配置為 站點 X /
/// 閘道器 N」 opens this picker — the numbers 1–[kMaxGatewayId] as buttons
/// (at least 48 dp), the current one filled. A number another gateway of
/// the station holds says 「已使用」 and can still be picked (the page then
/// asks 〔取代舊機〕／〔改用閘道器 N〕); without the back office every
/// number can be picked, with 「目前無法檢查是否重複」.
const gatewayNumberChangeLabel = '修改';
String gatewayNumberPickerTitle(int site) => '選擇站點 $site 的閘道器編號';
const gatewayNumberPickerHint = '可改成與現場標示相同的編號';
const gatewayNumberUsedLabel = '已使用';
const gatewayNumberUncheckedText = '目前無法檢查是否重複';
const gatewayNumberCancelLabel = '取消';

/// The picked number, or null (cancelled). [used]: the numbers another
/// gateway holds (null: the back office could not be asked).
Future<int?> showGatewayNumberPicker(
  BuildContext context, {
  required int site,
  required int current,
  Map<int, String>? used,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => GatewayNumberPicker(
    site: site,
    current: current,
    used: used,
    onPicked: (n) => Navigator.pop(context, n),
    onCancel: () => Navigator.pop(context),
  ),
);

class GatewayNumberPicker extends StatelessWidget {
  const GatewayNumberPicker({
    super.key,
    required this.site,
    required this.current,
    required this.onPicked,
    required this.onCancel,
    this.used,
  });

  final int site, current;
  final Map<int, String>? used;
  final ValueChanged<int> onPicked;
  final VoidCallback onCancel;

  /// Least width of a number button (4 per row on a 360 dp phone).
  static const _cellMin = 72.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final used = this.used;
    return ConstrainedBox(
      key: const Key('gateway-number-picker'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              gatewayNumberPickerTitle(site),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              gatewayNumberPickerHint,
              key: const Key('gateway-number-hint'),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          if (used == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                '⚠ $gatewayNumberUncheckedText',
                key: const Key('gateway-number-unchecked'),
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, box) {
                  final columns = ((box.maxWidth + _gap) / (_cellMin + _gap))
                      .floor()
                      .clamp(1, 10);
                  final width =
                      ((box.maxWidth - _gap * (columns - 1)) / columns)
                          .floorToDouble();
                  return Wrap(
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (var n = 1; n <= kMaxGatewayId; n++)
                        SizedBox(
                          width: width,
                          child: _numberButton(
                            context,
                            n,
                            taken: used?.containsKey(n) ?? false,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('gateway-number-cancel'),
                style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: onCancel,
                child: const Text(gatewayNumberCancelLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberButton(BuildContext context, int n, {required bool taken}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = n == current;
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$n',
          maxLines: 1,
          softWrap: false,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? colors.onPrimary : null,
          ),
        ),
        if (taken)
          Text(
            gatewayNumberUsedLabel,
            key: ValueKey('gateway-number-used-$n'),
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? colors.onPrimary : colors.error,
            ),
          ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
    final key = ValueKey('gateway-number-$n');
    return selected
        ? FilledButton(
            key: key,
            style: style,
            onPressed: () => onPicked(n),
            child: label,
          )
        : OutlinedButton(
            key: key,
            style: style.copyWith(
              side: taken
                  ? WidgetStatePropertyAll(BorderSide(color: colors.error))
                  : null,
            ),
            onPressed: () => onPicked(n),
            child: label,
          );
  }
}
