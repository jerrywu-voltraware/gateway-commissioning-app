import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// 測試用開關：true 時提示文字不做無限重複的閃爍（等同系統「移除動畫」）。
///
/// APP 執行時永遠是 false，不改變畫面行為；`test/flutter_test_config.dart`
/// 在所有測試前設成 true，避免 `pumpAndSettle` 被無限動畫卡到逾時
/// （docs/i18n.md §8.5）。要測閃爍本身的測試可在該測試內設回 false。
@visibleForTesting
bool debugDisableHintPulse = false;

// 提示列的固定說法（取代按鈕名）。呼叫端以 `caption:` 傳入，不再依按鈕中文
// 反查（docs/i18n.md §8.2）。字串在 lib/l10n/parts/nextActionGuide_*.arb。

/// 首頁〔檢查並開始〕上方的提示。
String get nextActionStartCaption => L10n.current.nextActionGuide_captionStart;

/// 閘道器卡片：選好目標、還沒連線時的提示（指向〔藍牙連線〕）。
String get nextActionConnectCaption =>
    L10n.current.nextActionGuide_captionConnect;

/// 閘道器卡片：已連線、可以〔開始開通〕時的提示。
String get nextActionBeginCaption => L10n.current.nextActionGuide_captionBegin;

/// Visual guidance only: never changes focus, enabled state, or tap handling.
class NextActionGuide extends StatefulWidget {
  const NextActionGuide({
    super.key,
    required this.active,
    required this.child,
    this.hint,
    this.caption,
  });

  factory NextActionGuide.button({
    required ButtonStyleButton child,
    bool active = true,
    String? hint,
    String? caption,
  }) => NextActionGuide(
    active: active && child.onPressed != null,
    hint: hint,
    caption: caption,
    child: child,
  );

  final bool active;
  final String? hint;

  /// 提示列實際顯示的文字；null 時顯示 [hint]。
  final String? caption;
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
    if (oldWidget.active != widget.active ||
        oldWidget.hint != widget.hint ||
        oldWidget.caption != widget.caption) {
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
            child: NextActionHint(
              widget.caption ?? widget.hint!,
              active: widget.active,
            ),
          ),
        action,
      ],
    );
  }
}

class NextActionHint extends StatelessWidget {
  const NextActionHint(
    this.text, {
    super.key,
    this.alignEnd = false,
    this.active = true,
  });

  final String text;
  final bool alignEnd;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Use a deeper gold on light surfaces so yellow text remains readable.
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFD54F)
        : const Color(0xFFA66A00);
    // 顯示的就是 [text]；固定說法由呼叫端以 caption 傳入（不再比對中文）。
    final caption = text;
    final arrow = Icon(Icons.arrow_downward_rounded, size: 18, color: color);
    return _HintPulse(
      active: active,
      child: Padding(
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            if (alignEnd) ...[const SizedBox(width: 6), arrow],
          ],
        ),
      ),
    );
  }
}

/// Keep the caption readable and its layout fixed while drawing attention.
class _HintPulse extends StatefulWidget {
  const _HintPulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_HintPulse> createState() => _HintPulseState();
}

class _HintPulseState extends State<_HintPulse>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );
  late final Animation<double> _opacity = _pulse.drive(
    Tween<double>(
      begin: 0.65,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeInOut)),
  );
  bool _motionAllowed = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void _syncAnimation() {
    if (widget.active && _motionAllowed && _foreground) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionAllowed =
        !debugDisableHintPulse &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.of(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_HintPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncAnimation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    alwaysIncludeSemantics: true,
    child: widget.child,
  );
}
