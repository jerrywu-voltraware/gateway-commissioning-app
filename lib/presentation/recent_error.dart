import '../l10n/l10n.dart';

/// Device error codes supplied by the firmware team on 2026-10-06.
/// Completion/restart codes are notifications, not faults.
bool recentErrorIsFault(int? code) =>
    code != null && !const {0, 163, 178, 179}.contains(code);

String recentErrorText(int? code) {
  if (code == null) return '--';
  final l10n = L10n.current;
  final description = switch (code) {
    0 => l10n.recentDataPage_errorNone,
    1 => l10n.recentDataPage_errorPtuOtPa,
    2 => l10n.recentDataPage_errorPtuOtDcdc,
    3 => l10n.recentDataPage_errorPtuOtIc,
    16 => l10n.recentDataPage_errorPtuOcIn,
    17 => l10n.recentDataPage_errorPtuOcBus,
    18 => l10n.recentDataPage_errorPtuOcI1,
    19 => l10n.recentDataPage_errorPtuOcI3,
    32 => l10n.recentDataPage_errorPtuPhase,
    48 => l10n.recentDataPage_errorPtuComm,
    64 => l10n.recentDataPage_errorPtuTimeset,
    160 => l10n.recentDataPage_errorPruOv,
    161 => l10n.recentDataPage_errorPruOc,
    162 => l10n.recentDataPage_errorPruOt,
    163 => l10n.recentDataPage_errorPruCharged,
    176 => l10n.recentDataPage_errorPtuLpStuck,
    177 => l10n.recentDataPage_errorPtuPtStuck,
    178 => l10n.recentDataPage_errorChargeComplete,
    179 => l10n.recentDataPage_errorClearComplete,
    _ => l10n.recentDataPage_errorUnknown,
  };
  final hex = code.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '$description (0x$hex)';
}
