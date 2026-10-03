import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual guidance only: never changes focus, enabled state, or tap handling.
class NextActionGuide extends StatefulWidget {
  const NextActionGuide({
    super.key,
    required this.active,
    required this.child,
    this.hint,
  });

  factory NextActionGuide.button({
    required ButtonStyleButton child,
    bool active = true,
    String? hint,
  }) => NextActionGuide(
    active: active && child.onPressed != null,
    hint: hint,
    child: child,
  );

  final bool active;
  final String? hint;
  final Widget child;

  @override
  State<NextActionGuide> createState() => _NextActionGuideState();
}

class _NextActionGuideState extends State<NextActionGuide>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _start() {
    _pulse.stop();
    // Three slow breaths, then the original button. Background and reduced
    // motion settings never keep a repeating animation alive.
    if (widget.active && !_reduceMotion) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _start();
  }

  @override
  void didUpdateWidget(NextActionGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.hint != widget.hint) {
      _start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final breath = widget.active && !_reduceMotion && _pulse.isAnimating
            ? (1 - math.cos(_pulse.value * math.pi * 6)) / 2
            : 0.0;
        // Tint only the existing pixels: preserve the exact button shape,
        // size and hit area, with no border or shadow outside the action.
        return ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.white.withValues(alpha: breath * 0.12),
            BlendMode.srcATop,
          ),
          child: child,
        );
      },
    );
    if (widget.hint == null) return action;
    // Keep the child's element in place when guidance switches off.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hint != null)
          Visibility(
            visible: widget.active,
            maintainSize: true,
            maintainState: true,
            maintainAnimation: true,
            child: NextActionHint(widget.hint!),
          ),
        action,
      ],
    );
  }
}

class NextActionHint extends StatelessWidget {
  const NextActionHint(this.text, {super.key, this.alignEnd = false});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final caption = switch (text) {
      '檢查並開始' => '從這裡開始',
      '確認目標閘道器，再點「藍牙連線」' => '確認目標後，點下方連線',
      '確認目標閘道器，再點「開始開通」' => '連線完成，可以開始開通',
      _ => text,
    };
    final arrow = Icon(Icons.arrow_downward_rounded, size: 16, color: color);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: alignEnd
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!alignEnd) ...[arrow, const SizedBox(width: 6)],
          Flexible(
            child: Text(
              caption,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          if (alignEnd) ...[const SizedBox(width: 6), arrow],
        ],
      ),
    );
  }
}
