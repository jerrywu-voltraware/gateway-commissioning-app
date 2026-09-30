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

  String get title => switch (stage) {
    StationChangeStage.applying => '正在套用站號，請稍候',
    StationChangeStage.restarting => '閘道器重新啟動中，請稍候',
    StationChangeStage.reconnecting => '正在重新連線閘道器',
    StationChangeStage.confirming => '正在確認站號與 Wi-Fi',
  };

  List<CheckItem> get items => [
    CheckItem(
      'station-apply',
      '套用站點設定',
      status: stage == StationChangeStage.applying
          ? CheckStatus.running
          : CheckStatus.done,
    ),
    // Waiting for the restart and reconnecting share a row. Elapsed time
    // alone must never turn the restart into a claimed success.
    CheckItem(
      'station-restart',
      '重新啟動並連線',
      status: switch (stage) {
        StationChangeStage.applying => CheckStatus.pending,
        StationChangeStage.restarting ||
        StationChangeStage.reconnecting => CheckStatus.running,
        StationChangeStage.confirming => CheckStatus.done,
      },
      note: stage == StationChangeStage.restarting
          ? '等待閘道器啟動'
          : stage == StationChangeStage.reconnecting
          ? '正在自動重新連線'
          : '',
    ),
    CheckItem(
      'station-confirm',
      '確認站號與 Wi-Fi',
      status: stage == StationChangeStage.confirming
          ? CheckStatus.running
          : CheckStatus.pending,
    ),
  ];
}
