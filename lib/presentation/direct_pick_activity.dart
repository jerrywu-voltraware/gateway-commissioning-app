import 'package:flutter/material.dart';

import '../core/direct_mode.dart';
import '../l10n/l10n.dart';
import 'wireless_charging_pad_icon.dart';

/// The gateway's reported PTU pick, never an installer confirmation.
class DirectPickActivity extends StatefulWidget {
  const DirectPickActivity({
    super.key,
    required this.direct,
    this.busy = false,
    this.identifiedMac,
    this.identifyAvailable = true,
    this.unavailable = false,
  });

  final DirectStatus? direct;
  final bool busy;
  final String? identifiedMac;
  final bool identifyAvailable;
  final bool unavailable;

  @override
  State<DirectPickActivity> createState() => _DirectPickActivityState();
}

class _DirectPickActivityState extends State<DirectPickActivity>
    with SingleTickerProviderStateMixin {
  late final AnimationController _search = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _picked => !widget.unavailable && widget.direct?.pickedMac != null;
  bool get _searching =>
      widget.busy &&
      !widget.unavailable &&
      (widget.direct?.state == DirectState.scanning ||
          widget.direct?.state == DirectState.connecting ||
          (widget.direct == null && widget.busy));

  bool get _motionAllowed =>
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant DirectPickActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (_searching && _motionAllowed) {
      if (!_search.isAnimating) _search.repeat();
    } else {
      _search.stop();
      _search.value = 0;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _message(AppLocalizations l10n) {
    if (widget.unavailable) return l10n.directPickActivity_unavailable;
    if (_picked) {
      if (!widget.identifyAvailable) return l10n.directPickActivity_foundConfirm;
      if (widget.identifiedMac != null &&
          formatMac(widget.identifiedMac) ==
              formatMac(widget.direct!.pickedMac)) {
        return l10n.directPickActivity_identifySent;
      }
      return widget.direct!.ambiguous
          ? l10n.directPickActivity_ambiguousIdentify
          : l10n.directPickActivity_foundIdentify;
    }
    return switch (widget.direct?.state) {
      DirectState.scanning => l10n.directPickActivity_scanning,
      DirectState.connecting => l10n.directPickActivity_connecting,
      DirectState.noCandidate => l10n.directPickActivity_noCandidate,
      DirectState.boundMissing => l10n.directPickActivity_boundMissing,
      DirectState.connected => l10n.directPickActivity_connected,
      null =>
        widget.busy
            ? l10n.directPickActivity_reading
            : l10n.directPickActivity_noStatus,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selectedColor = colors.primary;
    final mutedColor = colors.onSurfaceVariant;
    final ambiguous = _picked && widget.direct!.ambiguous;
    final duration = _motionAllowed
        ? const Duration(milliseconds: 280)
        : Duration.zero;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: IntrinsicHeight(
            child: Row(
              children: [
                _endpoint(
                  context,
                  icon: Icons.router_outlined,
                  label: context.l10n.directPickActivity_gatewayEndpoint,
                  color: _picked ? selectedColor : mutedColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    child: AnimatedBuilder(
                      animation: _search,
                      builder: (context, child) => Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            height: 16,
                            width: double.infinity,
                            child: CustomPaint(
                              key: Key(
                                _picked
                                    ? 'direct-pick-link-selected'
                                    : 'direct-pick-link-pending',
                              ),
                              painter: _LinkPainter(
                                selected: _picked,
                                color: _picked
                                    ? selectedColor
                                    : colors.outlineVariant,
                              ),
                            ),
                          ),
                          if (_search.isAnimating)
                            Opacity(
                              opacity: (1 - _search.value) * 0.7,
                              child: Transform.scale(
                                key: const Key('direct-pick-search-wave'),
                                scale: 0.6 + _search.value * 0.8,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selectedColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        key: const Key('direct-pick-ptu-frame'),
                        duration: duration,
                        width: 52,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: _picked
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest,
                          border: Border.all(
                            color: _picked
                                ? selectedColor
                                : colors.outlineVariant,
                            width: _picked ? 2 : 1,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            WirelessChargingPadIcon(
                              color: _picked ? selectedColor : mutedColor,
                            ),
                            if (ambiguous)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Icon(
                                  Icons.priority_high,
                                  key: const Key('direct-pick-ambiguous'),
                                  size: 13,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('PTU', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: true,
          child: Text(
            _message(context.l10n),
            key: const Key('direct-pick-message'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: widget.unavailable ? colors.error : colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _endpoint(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) => SizedBox(
    width: 72,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 36, child: Icon(icon, size: 30, color: color)),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _LinkPainter extends CustomPainter {
  const _LinkPainter({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = selected ? 2.5 : 1.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (selected) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      canvas.drawLine(
        Offset(size.width - 5, y - 4),
        Offset(size.width, y),
        paint,
      );
      canvas.drawLine(
        Offset(size.width - 5, y + 4),
        Offset(size.width, y),
        paint,
      );
    } else {
      for (var x = 0.0; x < size.width; x += 10) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + 4).clamp(0, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LinkPainter oldDelegate) =>
      selected != oldDelegate.selected || color != oldDelegate.color;
}
