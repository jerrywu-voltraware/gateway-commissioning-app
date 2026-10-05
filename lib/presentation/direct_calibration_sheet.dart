import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/commissioning_controller.dart';
import '../core/direct_calibration.dart';
import '../core/direct_mode.dart';
import 'direct_mode_panel.dart';
import '../l10n/l10n.dart';

// i18n（docs/i18n.md）：字串在 lib/l10n/parts/directCalibrationSheet_*.arb。

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
    final l10n = context.l10n;

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
            // 1.0.0+10: a sheet's title (titleLarge).
            Text(calibrationTitle, style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.directCalibrationSheet_intro(seconds),
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
              macRichText(l10n.directCalibrationSheet_ownPtu(formatMac(own))),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                key: const Key('calibration-progress'),
                value: done ? 1 : progress,
              ),
              const SizedBox(height: 4),
              Text(
                done
                    ? l10n.directCalibrationSheet_sampleDone(samples!.reads)
                    : l10n.directCalibrationSheet_sampling(
                        left,
                        samples?.reads ?? 0,
                      ),
                key: const Key('calibration-status'),
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              figure(
                l10n.directCalibrationSheet_ownLink,
                suggestion?.ownLinkWeakest == null
                    ? l10n.directCalibrationSheet_notRead
                    : l10n.directCalibrationSheet_ownLinkValue(
                        dbm(suggestion!.ownLinkMedian!),
                        dbm(suggestion.ownLinkWeakest!),
                        suggestion.ownLinkCount,
                      ),
                const Key('calibration-own'),
              ),
              // Round 19: firmware 1.7.27's advertising median (the gateway
              // picks by advertising).
              figure(
                l10n.directCalibrationSheet_ownAdv,
                switch (basis) {
                  null => l10n.directCalibrationSheet_notRead,
                  CalibrationBasis.legacy =>
                    l10n.directCalibrationSheet_legacyFirmware,
                  CalibrationBasis.noOwnAdvertising =>
                    l10n.directCalibrationSheet_notReported,
                  CalibrationBasis.current =>
                    l10n.directCalibrationSheet_median(
                      dbm(samples!.ownAdvertising!),
                    ),
                  // Round 20: shown, but not used for the upper bound.
                  CalibrationBasis.staleOwnAdvertising ||
                  CalibrationBasis.undatedOwnAdvertising =>
                    l10n.directCalibrationSheet_medianSkipped(
                      dbm(samples!.ownAdvertising!),
                    ),
                },
                const Key('calibration-own-adv'),
              ),
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
                    SizedBox(
                      width: 104,
                      child: Text(
                        l10n.directCalibrationSheet_strongestNeighbor,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            neighborMac == null
                                ? l10n.directCalibrationSheet_noNeighbor
                                : l10n.directCalibrationSheet_peak(
                                    dbm(suggestion!.neighborStrongest!),
                                  ),
                            key: const Key('calibration-neighbor'),
                            style: bold,
                          ),
                          // Round 20: ties within 1 dB listed together.
                          if (neighborMacs.length > 1)
                            Text(
                              neighborTies > neighborMacs.length
                                  ? l10n.directCalibrationSheet_tiesListed(
                                      neighborTies,
                                      calibrationNeighborTieDb,
                                      neighborMacs.length,
                                    )
                                  : l10n.directCalibrationSheet_tiesAll(
                                      neighborMacs.length,
                                      calibrationNeighborTieDb,
                                    ),
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
                    ? l10n.directCalibrationSheet_neighborLegacy
                    : l10n.directCalibrationSheet_neighborLive(
                        calibrationNeighborMaxAge,
                      ),
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
                          l10n.directCalibrationSheet_tooClose(
                            calibrationTooCloseReason(
                              suggestion,
                              calibrationNeighborLabel([
                                for (final mac in neighborMacs)
                                  distinguishingMacSegment(mac, [
                                    own,
                                    ...samples!.neighborMacs,
                                  ]),
                              ], total: neighborTies),
                            ),
                            calibrationTooCloseText,
                          ),
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
                  l10n.directCalibrationSheet_suggestion(threshold, current),
                  key: const Key('calibration-suggestion'),
                  style: text.titleMedium,
                ),
                if (suggestion!.lower != null)
                  Text(
                    l10n.directCalibrationSheet_range(
                      dbm(suggestion.lower!),
                      dbm(suggestion.upper!),
                    ),
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
                          l10n.directCalibrationSheet_saved(
                            calibrationSavedText,
                            _saved!,
                          ),
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
                    state.error ?? l10n.directCalibrationSheet_saveFailed,
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
                    ? l10n.directCalibrationSheet_writing
                    : threshold == null
                    ? l10n.directCalibrationSheet_write
                    : threshold == current && _saved == null
                    ? calibrationHoldLabel(threshold)
                    : l10n.directCalibrationSheet_writeValue(threshold),
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
                        : l10n.directCalibrationSheet_resample,
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('calibration-cancel'),
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    _saved == null ? l10n.common_cancel : l10n.common_done,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
