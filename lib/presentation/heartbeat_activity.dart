import 'package:flutter/material.dart';

import '../core/progress_checklist.dart';
import '../l10n/l10n.dart';

/// Decorative motion while waiting; receipt marks only follow backend events.
class HeartbeatActivity extends StatefulWidget {
  const HeartbeatActivity({super.key, required this.busy, this.checklist});

  final bool busy;
  final Checklist? checklist;

  @override
  State<HeartbeatActivity> createState() => _HeartbeatActivityState();
}

class _HeartbeatActivityState extends State<HeartbeatActivity>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  Checklist? get _online =>
      widget.checklist?.kind == ChecklistKind.online ? widget.checklist : null;

  bool _confirmed(Checklist? checklist) =>
      checklist != null &&
      [
        onlineItemBackend,
        onlineItemBeat1,
        onlineItemBeat2,
        onlineItemTarget,
      ].every(checklist.isDone);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant HeartbeatActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    final checklist = _online;
    final animate =
        widget.busy &&
        checklist != null &&
        !checklist.failed &&
        !_confirmed(checklist) &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  String _message(AppLocalizations l10n, Checklist? checklist, int received) {
    if (checklist?.failed == true) return l10n.heartbeatActivity_paused;
    if (_confirmed(checklist)) return l10n.heartbeatActivity_confirmed;
    if (!widget.busy || checklist == null) {
      return received == 0
          ? l10n.heartbeatActivity_waitingStart
          : l10n.heartbeatActivity_notDone;
    }
    if (!checklist.isDone(onlineItemBackend)) {
      return l10n.heartbeatActivity_connectingBackend;
    }
    if (received == 0) return l10n.heartbeatActivity_waitingFirst;
    if (received == 1) return l10n.heartbeatActivity_gotOne;
    return l10n.heartbeatActivity_gotTwo;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final checklist = _online;
    final receipts = [
      checklist?.isDone(onlineItemBeat1) == true,
      checklist?.isDone(onlineItemBeat2) == true,
    ];
    final received = receipts.where((done) => done).length;
    final l10n = context.l10n;
    final message = _message(l10n, checklist, received);
    final success = theme.brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _endpoint(
                  context,
                  Icons.router_outlined,
                  l10n.directPickActivity_gatewayEndpoint,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    child: AnimatedBuilder(
                      animation: _motion,
                      builder: (context, child) => _SignalPath(
                        moving: _motion.isAnimating,
                        position: _motion.value,
                        color: colors.primary,
                        trackColor: colors.outlineVariant,
                      ),
                    ),
                  ),
                ),
                _endpoint(
                  context,
                  Icons.cloud_outlined,
                  l10n.heartbeatActivity_backOffice,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (index, done) in receipts.indexed) ...[
                Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  key: ValueKey('heartbeat-receipt-${index + 1}'),
                  color: done ? success : colors.outline,
                  size: 20,
                ),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 4),
              Text(
                l10n.heartbeatActivity_count(received),
                key: const Key('heartbeat-count'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          key: const Key('heartbeat-announcement'),
          liveRegion: true,
          label: l10n.heartbeatActivity_announcement(received, message),
          child: ExcludeSemantics(
            child: Text(
              message,
              key: const Key('heartbeat-message'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: checklist?.failed == true
                    ? colors.error
                    : colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _endpoint(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: theme.colorScheme.primary),
          // 英文（Back office）比 58 dp 寬：一行縮小顯示，不換行撐高；
          // 中文放得下時 scaleDown 不改變大小。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPath extends StatelessWidget {
  const _SignalPath({
    required this.moving,
    required this.position,
    required this.color,
    required this.trackColor,
  });

  final bool moving;
  final double position;
  final Color color, trackColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(height: 2, color: trackColor),
          Positioned(
            right: 0,
            child: Icon(Icons.chevron_right, size: 20, color: trackColor),
          ),
          if (moving)
            Positioned(
              left: (constraints.maxWidth - 10) * position,
              child: Container(
                key: const Key('heartbeat-flow-packet'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
