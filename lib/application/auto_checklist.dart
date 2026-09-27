/// 09-28: which automatic checklist ([Checklist]) a page shows, and the
/// network check's part of 「正在連線並檢查網路」 — the Wi-Fi and back
/// office items follow what the gateway itself reports ([NetworkCheck]).
///
/// Pure Dart so the rules can be unit-tested without widgets.
library;

import '../core/gateway_identity.dart';
import '../core/gateway_net.dart';
import '../core/progress_checklist.dart';
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
  var view = list;
  // Old firmware cannot say; the data verification checks it later.
  if (!s.netCheckSupported) {
    const later = '這台韌體無法回報，最後驗證資料時會確認';
    return view
        .done(connectItemWifi, note: later)
        .done(connectItemBackend, note: later);
  }
  if (s.uploadWatch == UploadWatch.linkLost) {
    return view.fail('藍牙斷線，無法確認', id: connectItemWifi);
  }
  if (check.wifiOk) {
    final ssid = gatewaySsid(s.net, s.config['wifi_ssid']) ?? '';
    view = view.done(connectItemWifi, note: ssid.isEmpty ? '已連上' : ssid);
  } else if (check.wifiProblem) {
    return view.fail(
      check.wifiVerdict == WifiVerdict.notConfigured
          ? '還沒設定 Wi-Fi，請按下方設定 Wi-Fi'
          : '連不上 Wi-Fi，請按下方重設 Wi-Fi',
      id: connectItemWifi,
    );
  } else {
    return view.start(connectItemWifi);
  }
  if (check.testMode) {
    return view.fail('閘道器在測試模式，請先切回正常模式', id: connectItemBackend);
  }
  if (!check.targetOk) {
    return view.fail('資料送到別的後台，請依下方提示處理', id: connectItemBackend);
  }
  if (check.uploadPaused) {
    return view.fail('資料上傳已暫停，請按下方恢復上傳', id: connectItemBackend);
  }
  if (check.uploadOk) {
    return view.done(
      connectItemBackend,
      note: uploadHeldUntilJoin(s.config) ? '已連上，完成配置後開始上傳資料' : '資料上傳中',
    );
  }
  if (check.upload.tone == StatusTone.bad) {
    return view.fail('還沒開始上傳資料，請依下方提示處理', id: connectItemBackend);
  }
  return view.start(connectItemBackend);
}
