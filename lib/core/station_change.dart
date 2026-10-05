import '../l10n/l10n.dart';
import 'progress_checklist.dart';

/// An intentional identity update; never inferred from a generic link loss.
enum StationChangeStage { applying, restarting, reconnecting, confirming }

class StationChange {
  const StationChange({
    required this.site,
    required this.gateway,
    this.stage = StationChangeStage.applying,
  });

  final int site, gateway;
  final StationChangeStage stage;

  StationChange at(StationChangeStage next) =>
      StationChange(site: site, gateway: gateway, stage: next);

  bool get expectedDisconnect =>
      stage == StationChangeStage.restarting ||
      stage == StationChangeStage.reconnecting;

  String get title {
    final l10n = L10n.current;
    return switch (stage) {
      StationChangeStage.applying => l10n.stationChange_titleApplying,
      StationChangeStage.restarting => l10n.stationChange_titleRestarting,
      StationChangeStage.reconnecting => l10n.stationChange_titleReconnecting,
      StationChangeStage.confirming => l10n.stationChange_titleConfirming,
    };
  }

  List<CheckItem> get items {
    final l10n = L10n.current;
    return [
      CheckItem(
        'station-apply',
        l10n.stationChange_itemApply,
        status: stage == StationChangeStage.applying
            ? CheckStatus.running
            : CheckStatus.done,
      ),
      // Waiting for the restart and reconnecting share a row. Elapsed time
      // alone must never turn the restart into a claimed success.
      CheckItem(
        'station-restart',
        l10n.stationChange_itemRestart,
        status: switch (stage) {
          StationChangeStage.applying => CheckStatus.pending,
          StationChangeStage.restarting ||
          StationChangeStage.reconnecting => CheckStatus.running,
          StationChangeStage.confirming => CheckStatus.done,
        },
        note: stage == StationChangeStage.restarting
            ? l10n.stationChange_noteWaitBoot
            : stage == StationChangeStage.reconnecting
            ? l10n.stationChange_noteReconnecting
            : '',
      ),
      CheckItem(
        'station-confirm',
        l10n.stationChange_itemConfirm,
        status: stage == StationChangeStage.confirming
            ? CheckStatus.running
            : CheckStatus.pending,
      ),
    ];
  }
}
