import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/commissioning_controller.dart';
import '../core/direct_calibration.dart';
import '../core/direct_mode.dart';
import 'direct_mode_panel.dart';

/// Round 18: opens 「校正門檻」 ([DirectCalibrationSheet]).
Future<void> openDirectCalibration(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DirectCalibrationSheet(),
    );

/// Round 18 「校正門檻」 (direct mode): samples the gateway for
/// [directCalibrationDuration] as soon as it opens — this pile's confirmed
/// PTU (median and weakest link RSSI) against the strongest neighbour —
/// then suggests a threshold ([suggestDirectThreshold]). 「寫入閘道器」
/// sends it and reads it back; 「取消」 (or closing the sheet) writes
/// nothing. Signals too close for any threshold: a yellow warning and no
/// suggestion.
class DirectCalibrationSheet extends ConsumerStatefulWidget {
  const DirectCalibrationSheet({super.key});

  @override
  ConsumerState<DirectCalibrationSheet> createState() =>
      _DirectCalibrationSheetState();
}

class _DirectCalibrationSheetState
    extends ConsumerState<DirectCalibrationSheet> {
  StreamSubscription<DirectCalibrationSamples>? _sampling;
  DirectCalibrationSamples? _samples;
  String? _ownMac;
  bool _saving = false;

  /// The threshold read back after 「寫入閘道器」.
  int? _saved;

  /// 「寫入閘道器」 did not end with the value read back.
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _ownMac = ref.read(commissionProvider.notifier).calibrationOwnMac;
    _start();
  }

  void _start() {
    final own = _ownMac;
    if (own == null) return;
    unawaited(_sampling?.cancel());
    _samples = null;
    _saved = null;
    _saveFailed = false;
    _sampling = ref
        .read(commissionProvider.notifier)
        .sampleDirectCalibration(own)
        .listen((samples) {
          if (mounted) setState(() => _samples = samples);
        });
  }

  @override
  void dispose() {
    unawaited(_sampling?.cancel());
    super.dispose();
  }

  Future<void> _write(int threshold) async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final ok = await ref
        .read(commissionProvider.notifier)
        .saveDirectThreshold(threshold);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok ? threshold : null;
      _saveFailed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commissionProvider);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final warnFg = dark ? Colors.amber.shade200 : Colors.brown.shade900;
    final warnBg = dark
        ? Colors.amber.shade900.withValues(alpha: 0.35)
        : Colors.amber.shade100;
    final okFg = dark ? Colors.green.shade300 : Colors.green.shade800;
    final own = _ownMac;
    final samples = _samples;
    final done = samples?.done ?? false;
    final suggestion = samples?.suggestion;
    final threshold = done ? suggestion?.threshold : null;
    final current = directMinRssiOf(state.config);
    final seconds = directCalibrationDuration.inSeconds;
    final total = directCalibrationDuration.inMilliseconds;
    final elapsed = samples?.elapsed.inMilliseconds ?? 0;
    final progress = total <= 0 ? 1.0 : (elapsed / total).clamp(0.0, 1.0);
    final left = ((total - elapsed) / 1000).ceil().clamp(0, seconds);

    Widget figure(String label, String value, Key key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(label)),
          Expanded(
            child: macRichText(
              value,
              key: key,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('calibration-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(calibrationTitle, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              '本樁與鄰近樁請維持實際擺放與電源。取樣 $seconds 秒後建議門檻，'
              '確認後才寫入閘道器。',
              style: text.bodySmall,
            ),
            const SizedBox(height: 8),
            if (own == null)
              Text(
                calibrationNeedsOwnText,
                key: const Key('calibration-needs-own'),
                style: TextStyle(color: colors.error),
              )
            else ...[
              macRichText('本樁 PTU：${formatMac(own)}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                key: const Key('calibration-progress'),
                value: done ? 1 : progress,
              ),
              const SizedBox(height: 4),
              Text(
                done
                    ? '取樣完成（讀取 ${samples!.reads} 次）'
                    : '取樣中… 剩 $left 秒（已讀取 ${samples?.reads ?? 0} 次）',
                key: const Key('calibration-status'),
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              figure(
                '本樁 PTU 訊號',
                suggestion?.ownWeakest == null
                    ? '尚未讀到'
                    : '中位數 ${suggestion!.ownMedian} dBm · '
                          '最弱 ${suggestion.ownWeakest} dBm'
                          '（${suggestion.ownCount} 筆）',
                const Key('calibration-own'),
              ),
              figure(
                '最強鄰近訊號',
                suggestion?.neighborStrongest == null
                    ? '未聽到鄰近 PTU'
                    : '${suggestion!.neighborStrongest} dBm'
                          '（${formatMac(samples!.strongestNeighborMac)}）',
                const Key('calibration-neighbor'),
              ),
              Text(
                '鄰近訊號取自閘道器最近一次選台聽到的其他 PTU（峰值）。',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (done &&
                  suggestion!.verdict == DirectThresholdVerdict.tooClose)
                Container(
                  key: const Key('calibration-too-close'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: warnBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: warnFg,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$calibrationTooCloseText'
                          '（本樁最弱與鄰近最強相差 ${suggestion.gap} dB，'
                          '至少需 $calibrationMinGap dB）',
                          style: TextStyle(color: warnFg),
                        ),
                      ),
                    ],
                  ),
                ),
              if (done &&
                  suggestion!.verdict == DirectThresholdVerdict.noOwnSignal)
                Text(
                  calibrationNoOwnText,
                  key: const Key('calibration-no-own'),
                  style: TextStyle(color: colors.error),
                ),
              if (threshold != null) ...[
                Text(
                  '建議門檻：$threshold dBm（目前 $current dBm）',
                  key: const Key('calibration-suggestion'),
                  style: text.titleMedium,
                ),
                if (suggestion!.verdict == DirectThresholdVerdict.noNeighbors)
                  Text(calibrationNoNeighborText, style: text.bodySmall),
              ],
              if (_saved != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: okFg, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$calibrationSavedText：$_saved dBm',
                          key: const Key('calibration-saved'),
                          style: TextStyle(color: okFg),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_saveFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.error ?? '門檻未寫入閘道器，請重試。',
                    key: const Key('calibration-save-failed'),
                    style: TextStyle(color: colors.error),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('calibration-write'),
              onPressed:
                  threshold != null && _saved == null && !_saving && !state.busy
                  ? () => _write(threshold)
                  : null,
              child: Text(
                _saving
                    ? '寫入中…'
                    : threshold == null
                    ? '寫入閘道器'
                    : '寫入閘道器（$threshold dBm）',
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  key: const Key('calibration-resample'),
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: own != null && done && !_saving
                      ? () => setState(_start)
                      : null,
                  label: const Text('重新取樣'),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('calibration-cancel'),
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(_saved == null ? '取消' : '完成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
