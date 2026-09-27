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
/// PTU (link RSSI; round 19: also its advertising median, firmware
/// 1.7.27) against the strongest neighbour's peak — then suggests a
/// threshold ([suggestDirectThreshold]). 「寫入閘道器」 sends it and reads
/// it back; 「取消」 (or closing the sheet) writes nothing. Signals too
/// close for any threshold: a yellow warning and no suggestion. Round 19:
/// 「參考值（閘道器韌體較舊）」 without firmware 1.7.27's fields; stale
/// neighbours are left out and 「重新取樣」 reads 「重新掃描鄰近」.
/// Round 20: this pile's advertising value says how old it is (「本樁廣播
/// 值來自 N 分鐘前選台」) and, over 15 minutes or undated, is left out of
/// the upper bound (a reference value); neighbours within 1 dB of the
/// strongest are listed together (at most 3, MAC order).
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
    final neighborMac = samples?.strongestNeighborMac;
    // Round 20: every neighbour within 1 dB of the strongest (≤ 3, MAC
    // order) — field round 20 named one of two equal piles at random.
    final neighborMacs = samples?.strongestNeighborMacs ?? const <String>[];
    final neighborTies = samples?.strongestNeighborTies ?? 0;
    // Round 19: what the figures are built on; a reference value unless the
    // firmware reports everything its rules use (1.7.27).
    final basis = (samples?.reads ?? 0) == 0 ? null : samples!.basis;
    final reference =
        done &&
            suggestion != null &&
            suggestion.verdict != DirectThresholdVerdict.noOwnSignal
        ? basis?.referenceText
        : null;
    const bold = TextStyle(fontWeight: FontWeight.w600);

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
                '本樁連線訊號',
                suggestion?.ownLinkWeakest == null
                    ? '尚未讀到'
                    : '中位數 ${dbm(suggestion!.ownLinkMedian!)} · '
                          '最弱 ${dbm(suggestion.ownLinkWeakest!)}'
                          '（${suggestion.ownLinkCount} 筆）',
                const Key('calibration-own'),
              ),
              // Round 19: firmware 1.7.27's advertising median (the gateway
              // picks by advertising).
              figure('本樁廣播訊號', switch (basis) {
                null => '尚未讀到',
                CalibrationBasis.legacy => '閘道器韌體較舊，未回報',
                CalibrationBasis.noOwnAdvertising => '閘道器未回報',
                CalibrationBasis.current =>
                  '中位數 ${dbm(samples!.ownAdvertising!)}',
                // Round 20: shown, but not used for the upper bound.
                CalibrationBasis.staleOwnAdvertising ||
                CalibrationBasis.undatedOwnAdvertising =>
                  '中位數 ${dbm(samples!.ownAdvertising!)}（未列入上限）',
              }, const Key('calibration-own-adv')),
              // Round 20: firmware measures it while selecting and freezes
              // it once connected (field round 20: 249–274 s old).
              if (basis == CalibrationBasis.current ||
                  (basis?.ownAdvertisingSkipped ?? false))
                Padding(
                  padding: const EdgeInsets.only(left: 104),
                  child: Text(
                    calibrationSelfAdvAgeText(samples!.ownAdvertisingAgeS),
                    key: const Key('calibration-own-adv-age'),
                    style: text.bodySmall?.copyWith(
                      color: basis == CalibrationBasis.current
                          ? colors.onSurfaceVariant
                          : warnFg,
                    ),
                  ),
                ),
              // Round 19: the value on one line, the MAC on its own (field
              // round 19: 「）」 wrapped onto a line of its own).
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 104, child: Text('最強鄰近訊號')),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            neighborMac == null
                                ? '未聽到鄰近 PTU'
                                : '峰值 ${dbm(suggestion!.neighborStrongest!)}',
                            key: const Key('calibration-neighbor'),
                            style: bold,
                          ),
                          // Round 20: ties within 1 dB listed together.
                          if (neighborMacs.length > 1)
                            Text(
                              neighborTies > neighborMacs.length
                                  ? '$neighborTies 台相差 $calibrationNeighborTieDb dB 內，'
                                        '列出 ${neighborMacs.length} 台'
                                  : '${neighborMacs.length} 台相差 '
                                        '$calibrationNeighborTieDb dB 內，一併列出',
                              key: const Key('calibration-neighbor-ties'),
                              style: text.bodySmall,
                            ),
                          for (final (i, mac) in neighborMacs.indexed)
                            MacText(
                              mac,
                              key: Key(
                                i == 0
                                    ? 'calibration-neighbor-mac'
                                    : 'calibration-neighbor-mac-${i + 1}',
                              ),
                              others: [own, ...samples!.neighborMacs],
                              style: bold,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                basis == CalibrationBasis.legacy
                    ? '鄰近訊號取自閘道器最近一次選台聽到的其他 PTU（峰值），'
                          '連線後不再更新。'
                    : '鄰近訊號為閘道器連線中持續聽到的其他 PTU（峰值；'
                          '$calibrationNeighborMaxAge 秒內都列入計算）。',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (samples?.staleNeighborAge case final age?)
                Text(
                  calibrationStaleText(age),
                  key: const Key('calibration-stale'),
                  style: text.bodySmall?.copyWith(color: warnFg),
                ),
              if ((samples?.fewSampleNeighbors ?? 0) > 0)
                Text(
                  calibrationFewSamplesText(samples!.fewSampleNeighbors),
                  key: const Key('calibration-few-samples'),
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              if (reference != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    reference,
                    key: const Key('calibration-reference'),
                    style: text.labelLarge?.copyWith(color: warnFg),
                  ),
                ),
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
                          // Round 19: in the installer's words (was 「相差
                          // -2 dB，至少需 9 dB」). Round 19 fix: the
                          // -100…-20 write-range clamp can also force
                          // 太接近 with a perfectly fine gap —
                          // calibrationTooCloseReason picks
                          // non-contradictory wording then.
                          // Round 20: the tied neighbours named together.
                          '${calibrationTooCloseReason(suggestion, calibrationNeighborLabel([
                            for (final mac in neighborMacs) distinguishingMacSegment(mac, [own, ...samples!.neighborMacs]),
                          ], total: neighborTies))}。$calibrationTooCloseText。',
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
                if (suggestion!.lower != null)
                  Text(
                    '可用範圍 ${dbm(suggestion.lower!)} ～ '
                    '${dbm(suggestion.upper!)}：本樁選得到、連上後不會被踢，'
                    '本樁關機時也不會連到鄰近樁。',
                    key: const Key('calibration-range'),
                    style: text.bodySmall,
                  ),
                // Round 28: no neighbour data — held, never wider.
                if (suggestion.verdict == DirectThresholdVerdict.noNeighbors)
                  Text(
                    calibrationNoNeighborText(threshold),
                    key: const Key('calibration-no-neighbor'),
                    style: text.bodySmall,
                  ),
                if (suggestion.ownBelowHold)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      calibrationOwnBelowHoldText(suggestion.upper!, threshold),
                      key: const Key('calibration-own-below-hold'),
                      style: text.bodySmall?.copyWith(color: warnFg),
                    ),
                  ),
                if (suggestion.mayBeAmbiguous)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      calibrationAmbiguousText,
                      key: const Key('calibration-ambiguous'),
                      style: text.bodySmall?.copyWith(color: warnFg),
                    ),
                  ),
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
              // Round 28: the suggestion is the gateway's own threshold
              // (held): nothing to write.
              onPressed:
                  threshold != null &&
                      threshold != current &&
                      _saved == null &&
                      !_saving &&
                      !state.busy
                  ? () => _write(threshold)
                  : null,
              child: Text(
                _saving
                    ? '寫入中…'
                    : threshold == null
                    ? '寫入閘道器'
                    : threshold == current && _saved == null
                    ? calibrationHoldLabel(threshold)
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
                  label: Text(
                    samples?.staleNeighborAge != null
                        ? calibrationRescanLabel
                        : '重新取樣',
                  ),
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
