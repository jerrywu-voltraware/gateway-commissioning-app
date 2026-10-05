import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/commissioning_controller.dart';
import '../core/gateway_identity.dart';
import '../l10n/l10n.dart';

/// 〔恢復上傳〕 card's hint (what resuming does).
String get gatewayModeResumeHint => L10n.current.gatewayModeCard_resumeHint;

/// Round 26 (multi-gateway field test): the connected gateway's state that
/// stops the commissioning, each with its one way out —
///
/// * test mode (only test data, no PTU scan; the field saw 「PTU 沒有回應」
///   twice and only the back office could switch it): 〔切回正常模式〕;
/// * a gateway in service with its upload paused (the field saw 「✓ 資料
///   上傳中」 and 0 rows): 〔恢復上傳〕 — except on the network check, whose
///   upload item carries the same button.
///
/// Shown from the network check (step 2) to the data verification, above
/// the error banner, so it is read before anything else.
class GatewayModeCard extends ConsumerWidget {
  const GatewayModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(commissionProvider);
    final controller = ref.read(commissionProvider.notifier);
    if (state.peer == null || state.step < 2 || state.step > 6) {
      return const SizedBox.shrink();
    }
    final atCheck = state.step == 2 && !state.checkPassed;
    final String text, hint, label, key;
    final VoidCallback action;
    if (state.testMode) {
      text = testModeText;
      hint = testModeActionHint;
      label = leaveTestModeLabel;
      key = 'test-mode';
      action = controller.leaveTestMode;
    } else if (state.uploadPaused && !atCheck) {
      text = uploadPausedText;
      hint = gatewayModeResumeHint;
      label = resumeUploadLabel;
      key = 'upload-paused';
      action = controller.resumeUpload;
    } else {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.amber.shade100 : Colors.brown.shade900;
    final bg = dark
        ? Colors.amber.shade900.withValues(alpha: 0.35)
        : Colors.amber.shade100;
    return Container(
      key: Key('$key-card'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The red box right below already says it (e.g. a refused
          // 「下一步」): the card keeps only what to do.
          if (state.error != text) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    key: Key('$key-text'),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(hint, style: TextStyle(color: fg)),
          const SizedBox(height: 8),
          FilledButton(
            key: Key('$key-action'),
            onPressed: state.busy ? null : action,
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
