/// 09-28: which automatic checklist ([Checklist]) a page shows, and the
/// network check's part of 「正在連線並檢查網路」 — the Wi-Fi and back
/// office items follow what the gateway itself reports ([NetworkCheck]).
///
/// Pure Dart so the rules can be unit-tested without widgets.
library;

import '../core/gateway_identity.dart';
import '../core/gateway_net.dart';
import '../core/progress_checklist.dart';
import '../l10n/l10n.dart';
import 'commissioning_controller.dart';
import 'connection_status.dart';
import 'network_check.dart';

/// The checklist of the page [s] is on, or null (the page then shows its
/// plain 「處理中」 line while something runs).
///
/// - connect: while the gateway connects (gateway list, running), after a
///   failed connect (red box shown), and on the network check while it
///   runs by itself (「正在連線並檢查網路」) — once it names a problem
///   (Wi-Fi, where the data goes, the upload, test mode) that page has
///   the ✗ line and its fix, unchanged;
/// - online: on 確認上線 once it started;
/// - finish: on the configure and verify pages, and back on the PTU page
///   after a failure (red box shown).
Checklist? shownChecklist(CommissionState s, {NetworkCheck? check}) {
  final list = s.checklist;
  if (list == null) return null;
  switch (list.kind) {
    case ChecklistKind.connect:
      if (s.step == 1) {
        final connecting = s.busy && list.running;
        final failed = !s.busy && s.error != null && list.failed;
        return connecting || failed ? list : null;
      }
      if (s.step == 2 &&
          !s.checkPassed &&
          check != null &&
          !checkNamesProblem(s, check)) {
        return connectChecklistView(list, s, check);
      }
      return null;
    case ChecklistKind.online:
      if (s.step != 3) return null;
      return s.busy || list.failed || list.doneCount > 0 ? list : null;
    case ChecklistKind.finish:
      if (s.step == 5 || s.step == 6) return list;
      if (s.step == 4 && !s.busy && s.error != null && list.failed) {
        return list;
      }
      return null;
  }
}

/// The network check shows a problem with its fix (the page's title is
/// then that problem, not 「正在連線並檢查網路」).
bool checkNamesProblem(CommissionState s, NetworkCheck check) {
  if (s.testMode) return true;
  if (check.ready) return false;
  return check.wifiProblem ||
      !check.targetOk ||
      check.uploadPaused ||
      check.upload.tone == StatusTone.bad;
}

/// 「Wi-Fi 已連線」 and 「後台連線正常」 as the gateway reports them, once
/// the connect itself (Bluetooth, the status read) is done.
Checklist connectChecklistView(
  Checklist list,
  CommissionState s,
  NetworkCheck check,
) {
  if (!list.isDone(connectItemBle) || !list.isDone(connectItemStatus)) {
    return list;
  }
  final l10n = L10n.current;
  var view = list;
  // Old firmware cannot say; the data verification checks it later.
  if (!s.netCheckSupported) {
    final later = l10n.autoChecklist_oldFirmwareLater;
    return view
        .done(connectItemWifi, note: later)
        .done(connectItemBackend, note: later);
  }
  if (s.uploadWatch == UploadWatch.linkLost) {
    return view.fail(l10n.autoChecklist_linkLost, id: connectItemWifi);
  }
  if (check.wifiOk) {
    final ssid = gatewaySsid(s.net, s.config['wifi_ssid']) ?? '';
    view = view.done(
      connectItemWifi,
      note: ssid.isEmpty ? l10n.autoChecklist_wifiConnected : ssid,
    );
  } else if (check.wifiProblem) {
    return view.fail(
      check.wifiVerdict == WifiVerdict.notConfigured
          ? l10n.autoChecklist_wifiNotSet
          : l10n.autoChecklist_wifiFailed,
      id: connectItemWifi,
    );
  } else {
    return view.start(connectItemWifi);
  }
  if (check.testMode) {
    return view.fail(l10n.autoChecklist_testMode, id: connectItemBackend);
  }
  if (!check.targetOk) {
    return view.fail(
      l10n.autoChecklist_targetElsewhere,
      id: connectItemBackend,
    );
  }
  if (check.uploadPaused) {
    return view.fail(l10n.autoChecklist_uploadPaused, id: connectItemBackend);
  }
  if (check.uploadOk) {
    return view.done(
      connectItemBackend,
      note: uploadHeldUntilJoin(s.config)
          ? l10n.autoChecklist_uploadHeld
          : l10n.autoChecklist_uploading,
    );
  }
  if (check.upload.tone == StatusTone.bad) {
    return view.fail(
      l10n.autoChecklist_uploadNotStarted,
      id: connectItemBackend,
    );
  }
  return view.start(connectItemBackend);
}
