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
    // Three slow breaths, then a steady outline. Background and reduced
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
    // Contrast with the blue action buttons instead of resembling a shadow.
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFD54F)
        : const Color(0xFFF59E0B);
    final glow = AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final breath = _pulse.isAnimating
            ? (1 - math.cos(_pulse.value * math.pi * 6)) / 2
            : 0.35;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.30 + breath * 0.30),
                      blurRadius: 8 + breath * 10,
                      spreadRadius: 2 + breath * 3,
                    ),
                  ]
                : const [],
          ),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: widget.active ? Border.all(color: color, width: 3) : null,
            ),
            child: child,
          ),
        );
      },
    );
    if (widget.hint == null) return glow;
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
        glow,
      ],
    );
  }
}

class NextActionHint extends StatelessWidget {
  const NextActionHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Text(
      '下一步：$text',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
