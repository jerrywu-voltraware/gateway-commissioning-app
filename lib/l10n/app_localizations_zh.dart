// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get androidAppUpdateDialog_cancelDownload => '取消下載';

  @override
  String get androidAppUpdateDialog_continueInstall => '繼續安裝';

  @override
  String androidAppUpdateDialog_currentVersion(String name, String code) {
    return '目前版本：$name（$code）';
  }

  @override
  String get androidAppUpdateDialog_defaultNotes => '改善 APP 使用體驗。';

  @override
  String get androidAppUpdateDialog_downloadFailed => '更新下載未完成，請確認網路後重試。';

  @override
  String androidAppUpdateDialog_downloading(int percent) {
    return '正在下載 $percent%';
  }

  @override
  String get androidAppUpdateDialog_installFailed => '無法開啟系統安裝畫面，請返回 APP 後重試。';

  @override
  String get androidAppUpdateDialog_installerOpened =>
      '請在系統畫面確認安裝。若已取消，可再按「繼續安裝」。';

  @override
  String get androidAppUpdateDialog_integrityFailed => '更新檔驗證失敗，請重新下載。';

  @override
  String androidAppUpdateDialog_latestVersion(String name, String code) {
    return '最新版本：$name（$code）';
  }

  @override
  String get androidAppUpdateDialog_permissionRequired =>
      '請允許安裝此來源的應用程式，返回後按「繼續安裝」。';

  @override
  String get androidAppUpdateDialog_prepareFailed => '無法準備更新檔，請確認手機儲存空間後重試。';

  @override
  String get androidAppUpdateDialog_redownload => '重新下載';

  @override
  String get androidAppUpdateDialog_startFailed => '無法啟動更新安裝，請聯絡管理人員。';

  @override
  String get androidAppUpdateDialog_title => '有新版 APP';

  @override
  String get androidAppUpdateDialog_updateNow => '立即更新';

  @override
  String get androidAppUpdateDialog_verificationFailed =>
      '更新檔的版本或簽章驗證失敗，請聯絡管理人員。';

  @override
  String get androidAppUpdateDialog_verifying => '正在驗證更新檔…';

  @override
  String get appInfo_title => 'GIOS 設備助手';

  @override
  String get assign_assigning => '指派中';

  @override
  String assign_assigningId(int id) {
    return '指派中 #$id';
  }

  @override
  String assign_assigningResult(int id) {
    return '正在指派 #$id';
  }

  @override
  String get assign_autoHint => '系統自動處理中，失敗會自動重試，不用動手';

  @override
  String get assign_busy => '閘道器忙碌，稍後重試';

  @override
  String assign_doneId(int id) {
    return '完成 · #$id';
  }

  @override
  String assign_doneResult(String result) {
    return '完成 · $result';
  }

  @override
  String get assign_failed => '失敗需處理';

  @override
  String assign_failedHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '請確認 PTU 電源與距離，再按下方「重試這 $count 台」',
    );
    return '$_temp0';
  }

  @override
  String assign_failedReason(String reason) {
    return '失敗需處理：$reason';
  }

  @override
  String assign_linkRetry(int retry, int retries) {
    return '藍牙連線失敗，自動重試 $retry/$retries';
  }

  @override
  String get assign_notAssignedLink => '尚未指派（手機與閘道器斷線）';

  @override
  String assign_progressDone(int done, int total) {
    return '$done/$total 完成';
  }

  @override
  String assign_progressFailed(int count) {
    return '$count 台失敗需處理';
  }

  @override
  String assign_progressRetrying(int count) {
    return '$count 台自動重試中';
  }

  @override
  String get assign_progressSeparator => '，';

  @override
  String assign_retry(int retry, int retries) {
    return '未完成，自動重試 $retry/$retries';
  }

  @override
  String assign_retryAttempt(int retry, int retries) {
    return '（$retry/$retries）';
  }

  @override
  String assign_retryingMany(String names, int count) {
    return '$names 等 $count 台自動重試中';
  }

  @override
  String assign_retryingOne(String name, String attempt) {
    return '$name 自動重試中$attempt';
  }

  @override
  String assign_retryingTwo(String names) {
    return '$names 自動重試中';
  }

  @override
  String get assign_waiting => '等待中';

  @override
  String get autoChecklist_linkLost => '藍牙斷線，無法確認';

  @override
  String get autoChecklist_oldFirmwareLater => '這台韌體無法回報，最後驗證資料時會確認';

  @override
  String get autoChecklist_targetElsewhere => '資料送到別的後台，請依下方提示處理';

  @override
  String get autoChecklist_testMode => '閘道器在測試模式，請先切回正常模式';

  @override
  String get autoChecklist_uploadHeld => '已連上，完成配置後開始上傳資料';

  @override
  String get autoChecklist_uploadNotStarted => '還沒開始上傳資料，請依下方提示處理';

  @override
  String get autoChecklist_uploadPaused => '資料上傳已暫停，請按下方恢復上傳';

  @override
  String get autoChecklist_uploading => '資料上傳中';

  @override
  String get autoChecklist_wifiConnected => '已連上';

  @override
  String get autoChecklist_wifiFailed => '連不上 Wi-Fi，請按下方重設 Wi-Fi';

  @override
  String get autoChecklist_wifiNotSet => '還沒設定 Wi-Fi，請按下方設定 Wi-Fi';

  @override
  String backendEnvironment_changeHint(String label) {
    return '連線環境：$label（沿用上次的設定，可在右上角切換）';
  }

  @override
  String get backendEnvironment_invalidUrl => '網址無效';

  @override
  String get backendEnvironment_labelCustom => '其他網址';

  @override
  String get backendEnvironment_labelLocal => '本地測試';

  @override
  String get backendEnvironment_labelProduction => '正式站';

  @override
  String get backendEnvironment_localUnavailable =>
      '正式版 APP 不能連本地測試站，請改用本地測試版 APK。';

  @override
  String get backendEnvironment_localUnavailableLabel => '本地測試（此版本不可用）';

  @override
  String get backendKey_missing => '此建置缺少後台憑證，請重新建置';

  @override
  String get bleGatewayLink_stageClearing => '清除舊連線';

  @override
  String get bleGatewayLink_stageConnecting => '正在連線閘道器';

  @override
  String get bleGatewayLink_stageRescanning => '找不到閘道器，重新掃描中';

  @override
  String bleGatewayLink_stageRetry(int attempt) {
    return '第 $attempt 次重試';
  }

  @override
  String get commissioning_advancedCheck => '進階檢查';

  @override
  String get commissioning_appVersion => 'App 版本';

  @override
  String commissioning_archivedConfirmText(int site, int gateway) {
    return '站點 $site／閘道器 $gateway 在後台已被移除（封存）。封存的閘道器，後台不會記錄它的心跳，配置會停在「確認閘道器上線」。重新加入後會恢復記錄，原本的歷史資料不變。';
  }

  @override
  String get commissioning_archivedConfirmTitle => '這台閘道器之前在後台被移除（封存），要重新加入嗎？';

  @override
  String get commissioning_archivedRejoinLabel => '重新加入並繼續';

  @override
  String commissioning_assignFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台指派失敗：',
    );
    return '$_temp0';
  }

  @override
  String commissioning_assignFailedRow(String id, String reason) {
    return 'PTU $id：$reason';
  }

  @override
  String commissioning_assignmentLine(
    String site,
    String gateway,
    String hint,
  ) {
    return '將配置為 站點 $site / 閘道器 $gateway$hint';
  }

  @override
  String get commissioning_backToGatewaySearch => '回到找閘道器';

  @override
  String get commissioning_backToNetworkCheck => '回到網路體檢';

  @override
  String get commissioning_backToPtuRescan => '返回選擇 PTU，由閘道器重新掃描';

  @override
  String get commissioning_backToPtuSelect => '返回選擇 PTU';

  @override
  String commissioning_backToSite(int site) {
    return '改回站號 $site';
  }

  @override
  String get commissioning_backToStationChoice => '回到站點選擇';

  @override
  String get commissioning_backendUrl => '後端網址';

  @override
  String get commissioning_boundPtu => '已綁定 PTU';

  @override
  String commissioning_busyWaitUpTo(int seconds) {
    return '處理中 · 最多等待 $seconds 秒';
  }

  @override
  String get commissioning_cancelAction => '取消操作';

  @override
  String get commissioning_checkAndStart => '檢查並開始';

  @override
  String get commissioning_checkContinueLabel => '繼續設定站點';

  @override
  String get commissioning_checkIntro => '先確認閘道器能上網、資料送對地方，再選擇站點。';

  @override
  String get commissioning_checkPassedTaskTitle => '網路檢查通過，看完請按下方繼續';

  @override
  String get commissioning_checkTargetItem => '資料送到哪裡';

  @override
  String get commissioning_checkUpdate => '檢查更新';

  @override
  String get commissioning_checkUploadItem => '資料上傳';

  @override
  String get commissioning_checkWifiItem => '閘道器的 Wi-Fi';

  @override
  String get commissioning_checkingTaskTitle => '正在連線並檢查網路，請稍候';

  @override
  String get commissioning_checkingUpdate => '正在檢查更新…';

  @override
  String get commissioning_confirmTargetHint => '確認資料上傳目的地';

  @override
  String get commissioning_confirmUploadTitle => '確認資料上傳';

  @override
  String get commissioning_continueCommissioning => '繼續配置';

  @override
  String get commissioning_copied => '已複製，可貼上分享';

  @override
  String get commissioning_copyReport => '複製安裝報告';

  @override
  String commissioning_currentMode(String mode) {
    return '目前模式：$mode';
  }

  @override
  String get commissioning_demoBanner => '模擬模式 · 不會設定真實設備或驗證正式資料';

  @override
  String get commissioning_demoWifiConnected => '已連上';

  @override
  String get commissioning_demoWifiConnecting => '剛開機，正在連';

  @override
  String get commissioning_demoWifiDisconnected => '連不上（Wi-Fi 不在附近）';

  @override
  String get commissioning_demoWifiLabel => '模擬閘道器的 Wi-Fi';

  @override
  String get commissioning_detailsTitle => '設備與連線資訊';

  @override
  String get commissioning_directPickTaskTitle => '請辨識眼前的充電樁，確認後開始配置';

  @override
  String get commissioning_directSettings => '直連進階設定';

  @override
  String get commissioning_doneLabelHead => '請在機殼上標示：';

  @override
  String get commissioning_doneLabelHint => '後台人員靠這個標示找到這台';

  @override
  String commissioning_doneLabelText(String label) {
    return '請在機殼上標示：$label';
  }

  @override
  String commissioning_doneMode(String mode) {
    return '模式：$mode';
  }

  @override
  String get commissioning_doneTitle => '開通完成';

  @override
  String get commissioning_doneTitleDemo => '模擬開通完成';

  @override
  String get commissioning_end => '結束';

  @override
  String commissioning_envSwitched(String env) {
    return '已切換到$env。';
  }

  @override
  String commissioning_envSwitchedAutoSync(String env) {
    return '已切換到$env。連上閘道器後會自動讓它一起切換。';
  }

  @override
  String commissioning_envSwitchedManualSync(String env) {
    return '已切換到$env。連上閘道器後可在「連線狀態」按「同步」。';
  }

  @override
  String get commissioning_finishingTaskTitle => '正在完成設定並確認資料上傳';

  @override
  String commissioning_gatewayN(int gateway) {
    return '閘道器 $gateway';
  }

  @override
  String get commissioning_gatewayNumberComputing => '正在計算閘道器編號…';

  @override
  String commissioning_gatewayReports(String line) {
    return '閘道器自己回報：$line';
  }

  @override
  String commissioning_gatewaySwitching(String target) {
    return '正在把閘道器切到$target，約 1 分鐘，請留在閘道器旁。';
  }

  @override
  String commissioning_identifyGateway(int seconds) {
    return '辨識這台・$seconds 秒';
  }

  @override
  String get commissioning_identifyPile => '辨識此樁（PTU 與閘道器閃燈）';

  @override
  String get commissioning_identifyUnsupported => '連線時藍燈呼吸；更新韌體後可使用雙閃辨識。';

  @override
  String commissioning_identityConflictHint(int site, int gateway) {
    return '若舊機已拆除或換掉，按〔取代舊機〕由這台接手站 $site／閘道器 $gateway；否則請先找出另一台同編號的閘道器，或改用其他站號。';
  }

  @override
  String get commissioning_identityConflictTitle => '身分衝突';

  @override
  String commissioning_lastUploadConfirmed(String time) {
    return '最近確認上傳：$time';
  }

  @override
  String get commissioning_liveRssi => '動態 RSSI · 每 5 秒更新（順序不變）';

  @override
  String get commissioning_localHint =>
      '手機與電腦需連同一個 Wi-Fi；電腦 IP 若變更，可在上方修改或按「自動尋找」。';

  @override
  String get commissioning_loginAndCheck => '登入並確認資料';

  @override
  String commissioning_messageRemaining(String message, int seconds) {
    return '$message（剩餘 $seconds 秒）';
  }

  @override
  String get commissioning_networkCheckTitle => '閘道器網路體檢';

  @override
  String commissioning_newSiteConfirmText(int site) {
    return '後台還沒有站號 $site 的任何閘道器。請確認站號沒有打錯；確定是新站再繼續。';
  }

  @override
  String get commissioning_newSiteConfirmTitle => '確定是新站？';

  @override
  String commissioning_newSiteOk(int site) {
    return '是新站，使用站號 $site';
  }

  @override
  String get commissioning_noDataYet => '尚無資料';

  @override
  String get commissioning_noPtuFound => '未掃到 PTU，請確認 PTU 已上電後重新掃描';

  @override
  String commissioning_notConnectedList(String list) {
    return '尚未連線：$list';
  }

  @override
  String commissioning_notLoggedIn(String env) {
    return '尚未登入$env：站號衝突檢查會先略過，之後需要時會自動登入。';
  }

  @override
  String get commissioning_notVerifiedSkipped => '未驗證（已略過）';

  @override
  String commissioning_numberTakenMac(int taken, String mac) {
    return '（閘道器 $taken 目前登記的 MAC：$mac）';
  }

  @override
  String commissioning_numberTakenNextLabel(int gateway) {
    return '改用閘道器 $gateway';
  }

  @override
  String commissioning_numberTakenOnlineText(int taken) {
    return '閘道器 $taken 目前在線上，不能取代；如果這台是來換掉它，請先把舊機斷電。';
  }

  @override
  String commissioning_numberTakenOnlyText(int site, int taken) {
    return '站 $site 的閘道器 $taken 已被其他設備使用。';
  }

  @override
  String commissioning_numberTakenReplaceHint(int taken) {
    return '若這台是來取代那台舊機（舊機已拆除或斷電），按〔取代舊機〕沿用閘道器 $taken。';
  }

  @override
  String commissioning_numberTakenReplaceLabel(int taken) {
    return '取代舊機（沿用閘道器 $taken）';
  }

  @override
  String commissioning_numberTakenText(int site, int taken, int gateway) {
    return '站 $site 的閘道器 $taken 已被其他設備使用，改用閘道器 $gateway。';
  }

  @override
  String get commissioning_numberTakenTitle => '閘道器編號已被使用';

  @override
  String get commissioning_offlineFirst => '先離線配置，稍後驗證資料';

  @override
  String get commissioning_offlineNumber => '（離線配號，上線後會再核對）';

  @override
  String get commissioning_offlineNumberNoList => '（無法取得同站閘道器清單，暫配 1 號，請上線核對）';

  @override
  String get commissioning_oneToMany => '一對多';

  @override
  String get commissioning_oneToOne => '一對一';

  @override
  String get commissioning_onlineAuto => '即將自動確認上線，請稍候。';

  @override
  String get commissioning_onlineFailed => '檢查尚未通過。請依提示修正後，按下方按鈕重新檢查。';

  @override
  String get commissioning_onlineIntro => '確認閘道器不只連上 WiFi，後端也持續收到心跳。';

  @override
  String get commissioning_onlineOffline => '目前為離線配置，請選擇確認上線或稍後驗證。';

  @override
  String get commissioning_onlineRunning => '正在確認後台收到心跳，成功後會自動尋找 PTU，請稍候。';

  @override
  String get commissioning_onlineRunningTaskTitle => '正在確認閘道器上線，請稍候';

  @override
  String get commissioning_onlineTapStart => '請按下方按鈕開始檢查。';

  @override
  String get commissioning_onlineTaskTitle => '確認閘道器上線';

  @override
  String get commissioning_otherSiteLabel => '改用其他站號';

  @override
  String get commissioning_otherWifiLabel => '改用其他 Wi-Fi';

  @override
  String get commissioning_pickGatewayTaskTitle => '選擇閘道器';

  @override
  String get commissioning_powerOffOldFirst => '請先確認舊機已斷電，否則後台會再次標記衝突。';

  @override
  String commissioning_ptuCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台',
    );
    return '$_temp0';
  }

  @override
  String get commissioning_ptuOtherGateway => '已屬於其他閘道器';

  @override
  String get commissioning_ptuOutOfRange => '編號不在本機範圍，所屬閘道器未確認';

  @override
  String get commissioning_ptusPerGateway => '每台 PTU 數';

  @override
  String get commissioning_recheck => '重新檢查';

  @override
  String get commissioning_recheckIntro =>
      'Wi-Fi 已更新。等閘道器開始上傳資料，再確認站點（沿用或設定新站點）。';

  @override
  String get commissioning_reconfigureAll => '全部重新配置';

  @override
  String get commissioning_reconfigureAllText => '已成功指派的台也會重新指派一次，確定要繼續嗎？';

  @override
  String get commissioning_reconfigureAllTitle => '全部重新配置？';

  @override
  String get commissioning_reconnect => '重新連線';

  @override
  String get commissioning_reconnectContinue => '重新連線並繼續';

  @override
  String get commissioning_reconnectVerify => '重新連線並驗證';

  @override
  String get commissioning_reenter => '重新輸入';

  @override
  String get commissioning_refreshHealth => '更新健康狀態';

  @override
  String get commissioning_rejoinHintText =>
      '這台閘道器在後台被移除（封存），心跳不會被記錄。按下方「重新加入」後會繼續確認上線。';

  @override
  String get commissioning_rejoinLabel => '重新加入';

  @override
  String get commissioning_replaceFailedText => '取代舊機沒有成功，請確認網路後重試';

  @override
  String get commissioning_replaceOldKeepNumber => '取代舊機（沿用此編號）';

  @override
  String get commissioning_replaceOldLabel => '取代舊機';

  @override
  String commissioning_replacedText(int site, int gateway) {
    return '已由這台接手站 $site／閘道器 $gateway';
  }

  @override
  String get commissioning_reportSubtitle => '全文；也可分享或複製';

  @override
  String get commissioning_reportTitle => '安裝報告';

  @override
  String get commissioning_reportTitleDemo => '模擬安裝報告';

  @override
  String get commissioning_rescanPtus => '由閘道器重新掃描 PTU';

  @override
  String get commissioning_resetInclude => '重置並納入';

  @override
  String get commissioning_resetWifi => '重設 Wi-Fi';

  @override
  String get commissioning_restart => '重新開始';

  @override
  String commissioning_resumeMissingKey(String missing, String resume) {
    return '$missing。\n$resume';
  }

  @override
  String commissioning_retryFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '重試這 $count 台',
    );
    return '$_temp0';
  }

  @override
  String get commissioning_retryReconnect => '重試重新連線';

  @override
  String commissioning_reuseBlockedTapAbove(String button, String reason) {
    return '要使用此站點，請先按上方「$button」（目前：$reason）。';
  }

  @override
  String commissioning_reuseBlockedWifi(
    String reason,
    String otherWifi,
    String review,
  ) {
    return '要使用此站點，閘道器必須先連上 Wi-Fi 並開始上傳資料（目前：$reason）。請按「$otherWifi」，或按「$review」。';
  }

  @override
  String commissioning_saveNumberTakenText(int site, int gateway, String mac) {
    return '站點 $site / 閘道器 $gateway 目前登記給另一台裝置（MAC $mac）。';
  }

  @override
  String get commissioning_saveNumberTakenTitle => '編號已被使用';

  @override
  String get commissioning_saveWifiLabel => '儲存並繼續';

  @override
  String commissioning_savedGateway(String name) {
    return '上次配置的閘道器：$name';
  }

  @override
  String get commissioning_scanHelpDirect =>
      '由閘道器掃描附近的 PTU，再透過藍牙把清單傳回手機。直連模式：已自動選定訊號最強的一台。RSSI 是閘道器與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。';

  @override
  String get commissioning_scanHelpDirectFlow =>
      '由閘道器掃描附近的 PTU，再透過藍牙把清單傳回手機。直連模式：由閘道器自己選最近的 PTU（門檻內最強，或已綁定的那台），這裡只顯示它的選擇；請用「辨識此樁」確認是眼前這台，不是的話按「不是這台？」改選。RSSI 是閘道器與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。';

  @override
  String commissioning_scanHelpStar(int max) {
    return '由閘道器掃描附近的 PTU，再透過藍牙把清單傳回手機。最多可選 $max 台。RSSI 是閘道器與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。';
  }

  @override
  String get commissioning_scanHelpTitle => '掃描說明與完整流程';

  @override
  String get commissioning_setWifi => '設定 Wi-Fi';

  @override
  String get commissioning_shareFailed => '無法開啟分享，可改用複製報告。';

  @override
  String get commissioning_shareReport => '分享安裝報告';

  @override
  String get commissioning_siteFieldLabel => '站號（1–65535）';

  @override
  String commissioning_siteN(int site) {
    return '站點 $site';
  }

  @override
  String commissioning_siteNumbersFull(int site, int max) {
    return '站點 $site 的 1–$max 號閘道器都已被使用，請確認站點 ID 是否正確。';
  }

  @override
  String get commissioning_skipChooseSite => '先選擇站點（沿用要等網路正常）';

  @override
  String get commissioning_skipNewNote =>
      '⚠ 閘道器的網路還沒確認好。設定完新站點後會再確認資料上傳，最後的「驗證資料」也會檢查。';

  @override
  String get commissioning_skipNewSite => '仍要繼續設定新站點（稍後再確認上傳）';

  @override
  String get commissioning_skipOfflineNewSite => '先離線配置新站點（稍後再確認上傳）';

  @override
  String get commissioning_skipOnline => '暫未確認，先配置 PTU';

  @override
  String get commissioning_skipOnlineHint => '略過的話，最後「驗證資料」仍會確認資料有沒有上傳。';

  @override
  String get commissioning_skipStationNote =>
      '沒有通過網路體檢時不能沿用目前站點；可以重設 Wi-Fi 或設定新站點。';

  @override
  String get commissioning_skipThisPtu => '略過此台';

  @override
  String get commissioning_sortBySignal => '依訊號重新排序';

  @override
  String get commissioning_starAssignTaskTitle => '正在配置 PTU 並開始監控';

  @override
  String commissioning_starCountChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '星狀模式每台 PTU 數已改為 $count 台',
    );
    return '$_temp0';
  }

  @override
  String get commissioning_starCountTitle => '星狀模式：每台 PTU 數';

  @override
  String get commissioning_starPickTaskTitle => '請選擇本閘道器負責的 PTU';

  @override
  String get commissioning_starVerifyTaskTitle => '正在確認資料上傳';

  @override
  String get commissioning_startPowerHint => '先確認現場 WiFi 路由器與裝置電源已開啟。';

  @override
  String get commissioning_startTaskTitle => '登入後台，開始配置';

  @override
  String get commissioning_startVerify => '開始資料驗證';

  @override
  String commissioning_stationFull(int max, String swap) {
    return '本站閘道器已滿（1–$max 皆已使用），請確認站點 ID 或改用「$swap」。';
  }

  @override
  String get commissioning_stationHintBlocked => '改用其他站號，或先處理上方提示再沿用此站';

  @override
  String get commissioning_stationHintCanUse => '請選擇：使用此站點，或改用其他站號';

  @override
  String get commissioning_stationInputTitle => '請輸入這台要配置的站號';

  @override
  String commissioning_stationKeep(String site, String gateway) {
    return '沿用站點 $site／閘道器 $gateway，原站資料不變。';
  }

  @override
  String commissioning_stationQuestionTitle(int site) {
    return '目前站號是 $site，這台要配置在本站嗎？';
  }

  @override
  String get commissioning_stayOnList => '留在清單';

  @override
  String commissioning_syncFirstHint(String place) {
    return '按下後會先讓閘道器改送到$place（重新開機一次），再設定 Wi-Fi。';
  }

  @override
  String commissioning_syncTo(String place) {
    return '讓閘道器改送到$place（重新開機約 1 分鐘）';
  }

  @override
  String get commissioning_targetTaskTitle => '請讓閘道器把資料送到目前的後台';

  @override
  String get commissioning_testModeTaskTitle => '閘道器在測試模式，請先切回正常模式';

  @override
  String commissioning_topologyAskDirectBound(String mac) {
    return '這台閘道器目前是一對一模式（已綁定 PTU $mac），要改成星狀嗎？\n\n選〔維持一對一〕：APP 改用直連模式，閘道器的設定不變。';
  }

  @override
  String get commissioning_topologyAskDirectTitle => '這台閘道器是一對一模式';

  @override
  String get commissioning_topologyAskDirectUnbound =>
      '這台閘道器目前是一對一模式（尚未綁定 PTU），要改成星狀嗎？\n\n選〔維持一對一〕：APP 改用直連模式，閘道器的設定不變。';

  @override
  String commissioning_topologyAskStarText(int max) {
    return '這台閘道器目前是星狀模式（最多 $max 台 PTU），要改成一對一嗎？\n\n選〔維持星狀〕：APP 改用星狀模式，閘道器的設定不變。';
  }

  @override
  String get commissioning_topologyAskStarTitle => '這台閘道器是星狀模式';

  @override
  String get commissioning_topologyBusy => '操作進行中，完成後才能切換。';

  @override
  String get commissioning_topologyChangeToDirect => '改成一對一';

  @override
  String get commissioning_topologyChangeToStar => '改成星狀';

  @override
  String get commissioning_topologyKeepDirect => '維持一對一';

  @override
  String get commissioning_topologyKeepStar => '維持星狀';

  @override
  String commissioning_topologyKeptText(String mode) {
    return 'APP 已改用$mode，這台閘道器維持原模式';
  }

  @override
  String get commissioning_topologyMenuBusy => '操作完成後可切換';

  @override
  String get commissioning_topologyMenuDirect => '直連 · 一對一';

  @override
  String get commissioning_topologyMenuStar => '星狀 · 一對多';

  @override
  String get commissioning_topologyTitle => '連接模式';

  @override
  String get commissioning_updateAfterHome => '返回首頁且結束配置後可用';

  @override
  String get commissioning_updateCheckFailed => '暫時無法檢查更新，請確認網路後重試';

  @override
  String get commissioning_updateLatest => '目前已是最新版本';

  @override
  String get commissioning_uploadBadTaskTitle => '閘道器還沒開始上傳資料，請依下方提示處理';

  @override
  String commissioning_uploadOngoing(String where) {
    return '✓ 資料持續上傳（$where）';
  }

  @override
  String get commissioning_uploadPausedTaskTitle => '閘道器的資料上傳已暫停，請恢復上傳';

  @override
  String get commissioning_uploadRateHead => '資料上傳頻率由後台控制';

  @override
  String commissioning_uploadRateNow(String seconds) {
    return '資料上傳頻率由後台控制（目前每 $seconds 秒）';
  }

  @override
  String commissioning_uploadStatusWhere(String status, String where) {
    return '資料上傳：$status（$where）';
  }

  @override
  String commissioning_uploadWhere(String where) {
    return '資料上傳：$where';
  }

  @override
  String get commissioning_useNextFreeNumber => '改用下一個可用編號';

  @override
  String get commissioning_useSiteEmptyLabel => '使用站點';

  @override
  String commissioning_useSiteLabel(int site) {
    return '使用站點 $site';
  }

  @override
  String get commissioning_useStationLabel => '使用此站點';

  @override
  String commissioning_verifyBackend(String env) {
    return '驗證後端：$env';
  }

  @override
  String commissioning_verifyBackendLocal(String env) {
    return '驗證後端：$env（這台電腦上的測試主機）';
  }

  @override
  String get commissioning_verifyLoginTaskTitle => '請登入後台，確認資料上傳';

  @override
  String commissioning_versionBuild(String version, String build) {
    return '版本 $version · Build $build';
  }

  @override
  String get commissioning_versionUnavailable => '暫時無法讀取版本';

  @override
  String get commissioning_viewNetworkStatus => '查看網路狀態';

  @override
  String get commissioning_viewUploadData => '查看上傳資料…';

  @override
  String commissioning_waitUpTo(int seconds) {
    return '最多等待 $seconds 秒';
  }

  @override
  String get commissioning_wifi24Only => '閘道器只能用 2.4 GHz 的 Wi-Fi，5 GHz 的網路連不上。';

  @override
  String get commissioning_wifiBackKeep => '不改 Wi-Fi，返回';

  @override
  String get commissioning_wifiBackSite => '返回修改站號';

  @override
  String get commissioning_wifiFirstPageText => '先讓閘道器連上 Wi-Fi，網路正常後再設定站號。';

  @override
  String commissioning_wifiOnlyKeep(String site, String gateway) {
    return '保留站點 $site／閘道器 $gateway，只更新 Wi-Fi。';
  }

  @override
  String get commissioning_wifiPasswordNotSaved => 'Wi-Fi 已連線，但無法記住密碼；下次請重新輸入。';

  @override
  String get commissioning_wifiProblemTaskTitle => '閘道器沒有連上 Wi-Fi，請設定 Wi-Fi';

  @override
  String get commissioning_wifiResetConfirm => '是，重設 Wi-Fi';

  @override
  String get commissioning_wifiResetGoHint => '按「是，重設 Wi-Fi」將前往 Wi-Fi 設定。';

  @override
  String get commissioning_wifiResetLater => '暫不重設';

  @override
  String get commissioning_wifiResetTitle => '是否重設 Wi-Fi？';

  @override
  String get commissioning_wifiSavedWaiting =>
      'Wi-Fi 已儲存，正在等待閘道器恢復資料上傳。確認完成後會自動顯示下一步，請稍候。';

  @override
  String get commissioning_wifiTaskTitle => '設定閘道器的 Wi-Fi';

  @override
  String get commissioning_wifiUploadWaitTitle => 'Wi-Fi 已連線，正在確認資料上傳';

  @override
  String get common_back => '返回';

  @override
  String get common_cancel => '取消';

  @override
  String get common_close => '關閉';

  @override
  String get common_confirm => '確認';

  @override
  String get common_continue => '繼續';

  @override
  String get common_copy => '複製';

  @override
  String get common_details => '詳細資訊';

  @override
  String get common_done => '完成';

  @override
  String get common_dotSeparator => '・';

  @override
  String get common_gotIt => '知道了';

  @override
  String get common_languageEnglish => 'English';

  @override
  String get common_languageZhHant => '繁體中文';

  @override
  String get common_later => '稍後';

  @override
  String get common_listSeparator => '、';

  @override
  String get common_loading => '讀取中…';

  @override
  String get common_ok => '確定';

  @override
  String get common_refresh => '重新整理';

  @override
  String get common_retry => '重試';

  @override
  String get common_settings => '設定';

  @override
  String get common_skip => '略過';

  @override
  String get common_timeout => '逾時';

  @override
  String get common_unknown => '未知';

  @override
  String get connectionStatusPanel_collapse => '收合';

  @override
  String get connectionStatusPanel_details => '技術細節';

  @override
  String get connectionStatusPanel_expand => '展開';

  @override
  String get connectionStatusPanel_gatewayRow => '閘道器 → 資料上傳';

  @override
  String get connectionStatusPanel_notNow => '先不要';

  @override
  String get connectionStatusPanel_phoneRow => '手機 → 後端';

  @override
  String get connectionStatusPanel_reload => '重新讀取';

  @override
  String connectionStatusPanel_switchBody(String target) {
    return '閘道器會改把資料送到$target，並重新開機約 1 分鐘，期間請留在閘道器旁。';
  }

  @override
  String get connectionStatusPanel_switchButton => '切換';

  @override
  String get connectionStatusPanel_switchTitle => '同時切換閘道器？';

  @override
  String get connectionStatusPanel_sync => '同步';

  @override
  String get connectionStatusPanel_title => '連線狀態';

  @override
  String connectionStatus_detailBootCount(int count) {
    return '閘道器開機次數：$count';
  }

  @override
  String get connectionStatus_detailDemo => '模擬';

  @override
  String connectionStatus_detailFirmware(String version) {
    return '韌體版本：$version';
  }

  @override
  String connectionStatus_detailGatewayNet(String ssid) {
    return '閘道器網路：Wi-Fi「$ssid」';
  }

  @override
  String connectionStatus_detailHealth(String result) {
    return '後端健康檢查（GET /healthz）：$result';
  }

  @override
  String connectionStatus_detailLastReset(String reason) {
    return '（上次開機原因：$reason）';
  }

  @override
  String connectionStatus_detailLocalMqttCheck(String port, String host) {
    return '本地 MQTT 連不上時請確認：電腦防火牆已開放 TCP $port、本地 MQTT broker 已啟動，且 broker 憑證包含 $host。';
  }

  @override
  String get connectionStatus_detailModeNormal => '閘道器模式：正常';

  @override
  String get connectionStatus_detailModeTest => '閘道器模式：測試模式（只產生測試資料）';

  @override
  String connectionStatus_detailMqtt(String state) {
    return 'MQTT 連線：$state';
  }

  @override
  String connectionStatus_detailMqttLastRead(String state) {
    return '中斷前最後讀到的 MQTT 連線：$state';
  }

  @override
  String get connectionStatus_detailNotSet => '（未設定）';

  @override
  String connectionStatus_detailPauseReason(String reason) {
    return '（$reason）';
  }

  @override
  String connectionStatus_detailPhoneBackend(String base) {
    return '手機連線的後端：$base';
  }

  @override
  String connectionStatus_detailSignal(String rssi) {
    return ' · 訊號 $rssi dBm';
  }

  @override
  String get connectionStatus_detailSignalWeak => '（偏弱）';

  @override
  String connectionStatus_detailTargetLegacy(String version) {
    return '閘道器上傳目標：正式站（韌體 $version 不支援切換）';
  }

  @override
  String connectionStatus_detailTargetLocal(String hostPort) {
    return '閘道器上傳目標：MQTT 本地 $hostPort（TLS）';
  }

  @override
  String connectionStatus_detailTargetProduction(String hostPort) {
    return '閘道器上傳目標：MQTT 正式站 $hostPort（TLS）';
  }

  @override
  String get connectionStatus_detailTargetUnconfirmed =>
      '閘道器上傳目標：未確認（切換結果尚未讀回）';

  @override
  String connectionStatus_detailTargetUnknown(String value) {
    return '閘道器上傳目標：無法辨識（$value）';
  }

  @override
  String get connectionStatus_detailUploadOn => '資料上傳：開啟';

  @override
  String get connectionStatus_detailUploadPaused => '資料上傳：已暫停';

  @override
  String get connectionStatus_hintCustomUnknown =>
      'APP 無法從這個網址判斷閘道器該送到哪裡，這裡只顯示閘道器目前的設定，不會自動切換。';

  @override
  String get connectionStatus_hintLinkLostReconnect =>
      '手機和閘道器的藍牙斷了，請靠近閘道器後按「結束並重新選擇閘道器」重新連線。';

  @override
  String connectionStatus_hintPhoneNoBackend(String label) {
    return '手機連不到$label，請確認手機可以上網。';
  }

  @override
  String get connectionStatus_hintPhoneNoLocal =>
      '手機連不到測試主機：請確認電腦上的測試主機是否開著，且手機和電腦連同一個 Wi-Fi。';

  @override
  String connectionStatus_hintPortMismatch(String place) {
    return '閘道器的上傳設定和手機不一致（見技術細節）。按「同步」讓閘道器改送到$place。';
  }

  @override
  String connectionStatus_hintTargetMismatch(
    String current,
    String wanted,
    String place,
  ) {
    return '閘道器把資料送到$current，但手機連的是$wanted。按「同步」讓閘道器改送到$place。';
  }

  @override
  String get connectionStatus_hintUnknownReread =>
      '還不確定閘道器把資料送到哪裡，請按「連線狀態」這一列最右邊的重新讀取圖示（↻）。';

  @override
  String connectionStatus_hintUnknownSync(String place) {
    return '還不確定閘道器把資料送到哪裡。按「同步」讓閘道器改送到$place。';
  }

  @override
  String connectionStatus_hintWifiConnecting(String action) {
    return '閘道器還沒連上 Wi-Fi，請稍候；若一直連不上，請確認 Wi-Fi 名稱和密碼（可用「$action」）。';
  }

  @override
  String connectionStatus_linkBack(String reload) {
    return '手機已重新連上閘道器，$reload';
  }

  @override
  String connectionStatus_linkLostCannotRead(String action) {
    return '手機和閘道器的藍牙已中斷，無法讀取目前狀態。$action';
  }

  @override
  String connectionStatus_linkLostRelinking(String relinking) {
    return '手機和閘道器的藍牙已中斷，$relinking';
  }

  @override
  String get connectionStatus_mqttConnected => '已連線';

  @override
  String get connectionStatus_mqttDisconnected => '未連線';

  @override
  String get connectionStatus_placeLocal => '本地測試主機';

  @override
  String get connectionStatus_probeChecking => '檢查中';

  @override
  String get connectionStatus_probeDegraded => '資料庫未就緒（HTTP 503）';

  @override
  String get connectionStatus_probeHealthy => '正常';

  @override
  String connectionStatus_probeHealthyVersion(String version) {
    return '正常（版本 $version）';
  }

  @override
  String connectionStatus_probeNotBackend(String status) {
    return '不是本系統後端（HTTP $status）';
  }

  @override
  String get connectionStatus_probeUnreachable => '無法連線';

  @override
  String connectionStatus_probeUnreachableDetail(String detail) {
    return '無法連線（$detail）';
  }

  @override
  String get connectionStatus_reconnectThenCheck => '請重新連線閘道器後再確認。';

  @override
  String get connectionStatus_statusChecking => '⏳ 檢查中…';

  @override
  String get connectionStatus_statusConfirming => '⏳ 確認中…';

  @override
  String get connectionStatus_statusConnected => '✓ 已連線';

  @override
  String get connectionStatus_statusConnectedDemo => '✓ 已連線（模擬）';

  @override
  String get connectionStatus_statusConnecting => '⏳ 連線中…';

  @override
  String get connectionStatus_statusDbNotReady => '⚠ 連上了，但資料庫還沒準備好';

  @override
  String get connectionStatus_statusElsewhere => '⚠ 送到別處';

  @override
  String get connectionStatus_statusLinkLostUploadUnknown => '？ 藍牙已中斷，上傳狀態待確認';

  @override
  String get connectionStatus_statusTestMode => '⚠ 測試模式';

  @override
  String get connectionStatus_statusUnconfirmed => '？ 未確認';

  @override
  String get connectionStatus_statusUnreachable => '✗ 連不上';

  @override
  String get connectionStatus_statusUploadPaused => '⚠ 上傳已暫停';

  @override
  String get connectionStatus_statusUploadUnknown => '？ 上傳狀態待確認';

  @override
  String get connectionStatus_statusUploading => '✓ 資料上傳中';

  @override
  String get connectionStatus_statusWifiDown => '✗ Wi-Fi 沒連上';

  @override
  String connectionStatus_subnetHint(
    String subnet,
    String host,
    String action,
  ) {
    return '閘道器目前在 $subnet.x 網段，可能連不到測試主機 $host。請確認閘道器和這台電腦連同一個 Wi-Fi（可用「$action」）。';
  }

  @override
  String connectionStatus_summary(String label) {
    return '✓ $label：手機與閘道器都已連上';
  }

  @override
  String connectionStatus_tapButton(String button) {
    return '請按「$button」。';
  }

  @override
  String get connectionStatus_uploadCheckLocal =>
      '請確認電腦上的測試主機是否開著，以及閘道器是否連上和這台電腦同一個 Wi-Fi。';

  @override
  String get connectionStatus_uploadCheckProduction => '請確認閘道器所在的 Wi-Fi 可以上網。';

  @override
  String get connectionStatus_whereChecking => '確認中';

  @override
  String get connectionStatus_whereUnconfirmed => '未確認';

  @override
  String get connectionStatus_whereUnknown => '無法辨識';

  @override
  String get connectionStatus_wifiActionOther => '改用其他 Wi-Fi';

  @override
  String get connectionStatus_wifiActionReset => '重設 Wi-Fi';

  @override
  String get connectionStatus_wifiActionSet => '設定 Wi-Fi';

  @override
  String connectionStatus_wifiFixHere(String action) {
    return '請按「$action」，改成現場的 2.4 GHz Wi-Fi。';
  }

  @override
  String connectionStatus_wifiFixReconnect(String action) {
    return '請按「結束並重新選擇閘道器」重新連線，在網路體檢按「$action」。';
  }

  @override
  String connectionStatus_wifiLinkLostReconnect(String action) {
    return '手機和閘道器的藍牙也斷了：請靠近閘道器，按「結束並重新選擇閘道器」重新連線，再按「$action」。';
  }

  @override
  String connectionStatus_wifiLinkLostRelinking(String relinking) {
    return '手機和閘道器的藍牙也斷了，$relinking';
  }

  @override
  String controller_absentSelection(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台在本次掃描未出現，已取消勾選',
    );
    return '$_temp0';
  }

  @override
  String controller_ackNumberMismatch(String reported, int wanted) {
    return '裝置回報編號 #$reported 與指派 #$wanted 不符，請重試';
  }

  @override
  String controller_adjustedTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已調整為 $count 台；請重新選擇已連線裝置或修復缺少的 PTU。',
    );
    return '$_temp0';
  }

  @override
  String controller_allAssignFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台都指派失敗，閘道器設定未變更；請確認 PTU 後按「重試這 $count 台」。',
    );
    return '$_temp0';
  }

  @override
  String get controller_alreadyMonitoring => '已在監控';

  @override
  String controller_assignCount(int done, int total) {
    return '$done/$total 台';
  }

  @override
  String controller_assignFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台指派失敗',
    );
    return '$_temp0';
  }

  @override
  String controller_assignFailedReason(String reason) {
    return '指派失敗：$reason';
  }

  @override
  String controller_assignedNumber(String id) {
    return '已指派 #$id';
  }

  @override
  String controller_assignedPtu(int id) {
    return '已指派 PTU #$id';
  }

  @override
  String controller_assignedWaiting(int id) {
    return '已指派 #$id，等待連線';
  }

  @override
  String controller_assigningDirect(int id) {
    return '正在指派 #$id 並開始監控';
  }

  @override
  String controller_assigningLabel(int done, int total) {
    return '配置中… $done/$total';
  }

  @override
  String get controller_autoRelinking => '正在自動重新連線…';

  @override
  String controller_backendRetry(int attempt) {
    return '後端暫時無回應，自動重試中（$attempt）';
  }

  @override
  String get controller_backendSwitchedDone => '已切換連線環境，資料要在新的環境重新確認。';

  @override
  String get controller_backendSwitchedVerify => '已切換連線環境，請按「開始資料驗證」重新確認。';

  @override
  String get controller_backendUnconfirmed => '後端尚未確認；完成配置後仍需驗證';

  @override
  String get controller_bindLaterBlocked => '目前無法進入「選擇 PTU」，請先完成網路體檢後再按一次。';

  @override
  String get controller_bindLaterHint =>
      '請按〔辨識並綁定〕：到選擇 PTU 時按「辨識此樁」確認是眼前這台，再按「是這台，開始配置」即會綁定並把它編為 #1。';

  @override
  String get controller_bindLaterLabel => '辨識並綁定';

  @override
  String get controller_bindLaterNoStation => '這台閘道器目前不能沿用站點，請先完成站點與 Wi-Fi 設定。';

  @override
  String controller_bindLaterTitle(String mac) {
    return '這台閘道器已連上 PTU $mac，但尚未綁定';
  }

  @override
  String get controller_bindLaterWaitingHint =>
      '請確認本樁 PTU 已上電、與閘道器放在同一個機殼內；連上後按〔辨識並綁定〕。';

  @override
  String get controller_bindLaterWaitingTitle =>
      '上次配置時本樁 PTU 尚未連線，閘道器目前仍未連上 PTU';

  @override
  String controller_bleCleanupDone(String done, String next) {
    return '藍牙清理未完成，請按「$done」或「$next」重試斷開。';
  }

  @override
  String get controller_bleCleanupIncomplete => '藍牙清理未完成，請重試斷開。';

  @override
  String get controller_bleConnectIncomplete => '藍牙連線未完成，請重試。';

  @override
  String controller_boundPtu(int id) {
    return '已綁定 PTU #$id';
  }

  @override
  String get controller_busyTryAgain => '另一個動作還在進行，請等它結束後再按一次。';

  @override
  String controller_cancelRestoreRetry(String failure) {
    return '$failure 請保持靠近並再次取消以重試還原，或重開 APP 後重新連線。';
  }

  @override
  String get controller_cancelled => '已取消。請重新連線核對進度；未成功恢復的監控會話最晚於到期時恢復。';

  @override
  String get controller_checkFailedNew => '網路體檢未通過，仍可設定新站點；之後會再確認資料上傳。';

  @override
  String get controller_checkFailedStation =>
      '網路體檢未通過：可重設 Wi-Fi 或設定新站點；沿用要等網路正常。';

  @override
  String get controller_checkPassedNew => '網路體檢通過，請設定身份與 Wi-Fi。';

  @override
  String get controller_checkPassedStation => '網路體檢通過，請選擇站點。';

  @override
  String get controller_checkingMonitor => '正在確認閘道器監控狀態';

  @override
  String get controller_chooseGateway => '請選擇要開通的閘道器';

  @override
  String get controller_chooseStationWaitUpload => '請選擇站點。沿用要等閘道器開始上傳資料。';

  @override
  String controller_configureCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '配置 $count 台並開始監控',
    );
    return '$_temp0';
  }

  @override
  String controller_configureRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '配置剩餘 $count 台並開始監控',
    );
    return '$_temp0';
  }

  @override
  String get controller_configureRun => '逐台編號並開始監控';

  @override
  String get controller_configureWifiRun => '設定身份與 WiFi';

  @override
  String get controller_configuredVerify => '配置完成，請驗證後端資料';

  @override
  String controller_connectLogDetail(String log) {
    return '連線失敗紀錄：$log';
  }

  @override
  String controller_connectLogLine(int attempt, String type) {
    return '第 $attempt 次：$type';
  }

  @override
  String get controller_connectedHasStation =>
      '已連線，此閘道器已有站點設定。先做網路體檢，再選擇沿用或設定新站。';

  @override
  String get controller_connectedNew => '已連線。先做網路體檢，再設定身份與 Wi-Fi。';

  @override
  String controller_connectedNumber(String id) {
    return '已連線 #$id';
  }

  @override
  String controller_connectingAttempt(int attempt) {
    return '連線中（第 $attempt 次）';
  }

  @override
  String controller_connectingPeer(String name) {
    return '正在連線 $name，請保持靠近';
  }

  @override
  String controller_connectingStage(String attempt, String stage) {
    return '$attempt：$stage';
  }

  @override
  String controller_continueAssign(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '繼續指派 $count 台',
    );
    return '$_temp0';
  }

  @override
  String get controller_dataStale => '資料暫未更新';

  @override
  String get controller_dataStreaming => '資料持續更新';

  @override
  String controller_deferConfirm(int threshold) {
    return '閘道器會照常完成配置：加入運作、恢復上傳，維持一對一模式與目前門檻（$threshold dBm），但不綁定 PTU。\n本樁 PTU 上電後，閘道器會自動連上它；綁定需之後到現場按〔辨識並綁定〕確認。';
  }

  @override
  String get controller_deferConfirmTitle => '先完成配置，稍後 PTU 上電自動連線？';

  @override
  String get controller_deferFinishLabel => '先完成配置';

  @override
  String get controller_deferredBindNowLabel => 'PTU 已上電：辨識並綁定';

  @override
  String controller_deferredDetail(int threshold) {
    return '閘道器已加入運作並恢復上傳，維持一對一模式（門檻 $threshold dBm），尚未綁定 PTU。';
  }

  @override
  String get controller_deferredDone =>
      '本樁 PTU 尚未連線。PTU 上電後會自動連線，之後到現場按〔辨識並綁定〕確認綁定。';

  @override
  String get controller_deferredDoneTitle => '閘道器配置完成';

  @override
  String get controller_deferredLater =>
      '之後補做綁定：PTU 上電後，用 APP 重新連上這台閘道器，會出現〔辨識並綁定〕。人還在現場且 PTU 已上電，可直接按下方按鈕。';

  @override
  String get controller_deferredSummary => '本樁 PTU 尚未連線（上電後自動連上）';

  @override
  String get controller_deferredUploadStatus => '✓ 已恢復上傳（等本樁 PTU 連上）';

  @override
  String get controller_deferring => '正在完成閘道器配置（本樁 PTU 尚未連線）';

  @override
  String get controller_devShipNote =>
      '開發環境提示（本地測試版才會出現，現場人員不用處理）：這台閘道器目前上傳到本地測試站，出貨前需由開發人員把手機和閘道器一起切回正式站。';

  @override
  String get controller_devShipSwitchLabel => '切回正式站';

  @override
  String get controller_directBoundMissing =>
      '閘道器綁定的 PTU 不在場：請確認它已上電，或解除綁定後按「重新搜尋」。';

  @override
  String controller_directBoundNote(String mac) {
    return '已綁定 PTU MAC：$mac（閘道器只連這台）';
  }

  @override
  String get controller_directFreshWindow => '閘道器正在重新收集附近的 PTU，請稍候';

  @override
  String get controller_directNoCandidate =>
      '閘道器找不到夠近的 PTU：請確認同樁 PTU 已上電並靠近，再按「重新搜尋」。';

  @override
  String get controller_directNoData =>
      '閘道器還沒收到這台 PTU 的資料，請確認 PTU 電源後再按「是這台，開始配置」重試；閘道器仍維持監控。';

  @override
  String get controller_directNoReport => '閘道器尚未回報選台結果，請按「重新搜尋」。';

  @override
  String get controller_directPickIncomplete => '閘道器選台未完成，請查看錯誤後按「重新搜尋」。';

  @override
  String controller_directPicked(String mac) {
    return '閘道器選中 PTU $mac，請按「辨識此樁」確認是眼前這台';
  }

  @override
  String controller_directPickedAmbiguous(String mac) {
    return '閘道器選中 PTU $mac，但附近有訊號相近的 PTU，請按「辨識此樁」確認';
  }

  @override
  String get controller_directPicking => '閘道器正在選擇最近的 PTU，請稍候';

  @override
  String get controller_directStillSearching => '閘道器仍在尋找 PTU，請稍候再按「重新搜尋」。';

  @override
  String controller_directSwitchDone(String mac) {
    return '閘道器已改連 PTU $mac（已綁定），請按「辨識此樁」確認是眼前這台。';
  }

  @override
  String controller_directSwitchPending(String mac) {
    return '閘道器仍在改連 PTU $mac，連上後畫面會自動更新；也可改選其他 PTU。';
  }

  @override
  String get controller_disconnecting => '正在斷開藍牙…';

  @override
  String get controller_doneBefore => '先前已完成';

  @override
  String get controller_doneBusy => '正在處理，完成後再按〔完成〕。';

  @override
  String get controller_doneNextLabel => '配置下一台';

  @override
  String get controller_endFlowConfirmTitle => '結束目前配置？';

  @override
  String controller_endFlowDeferHint(String label) {
    return '本樁 PTU 不在場時，請改按「$label」。';
  }

  @override
  String get controller_endFlowHeldUpload =>
      '注意：這台閘道器還沒加入運作（資料上傳暫停），結束後不會上傳任何資料。';

  @override
  String controller_endFlowKeepDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已完成的 $count 台會保留在閘道器。',
    );
    return '$_temp0';
  }

  @override
  String get controller_endFlowLabel => '結束並重新選擇閘道器';

  @override
  String get controller_endFlowNoneDone => '目前尚未完成任何 PTU。';

  @override
  String controller_endFlowRestoreDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '結束後會把閘道器的 PTU 綁定還原為改選前的狀態；已完成的 $count 台保留。',
    );
    return '$_temp0';
  }

  @override
  String get controller_endFlowRestoreNone =>
      '結束後會把閘道器的 PTU 綁定還原為改選前的狀態；目前尚未完成任何 PTU。';

  @override
  String controller_firmwareNote(String version) {
    return '韌體 $version';
  }

  @override
  String controller_firstConnectFailure(String failure) {
    return '第一次連線失敗：$failure';
  }

  @override
  String get controller_gatewayBusy => '閘道器忙碌中，等待…';

  @override
  String get controller_gatewayFallbackName => '閘道器';

  @override
  String get controller_gatewayFull => '本機已滿，請連另一台閘道器。';

  @override
  String get controller_gatewayStatusBusy => '配置進行中不可用';

  @override
  String get controller_gatewayStatusMenu => '查看上傳資料…';

  @override
  String controller_gatewayStatusMenuBusy(String reason) {
    return '查看上傳資料（$reason）';
  }

  @override
  String get controller_healthAbnormal => '資料有異常，請檢查 PTU 與網路。';

  @override
  String get controller_healthPending => '正在確認資料上傳…';

  @override
  String get controller_healthUnknown => '無法確認最新資料，請檢查網路';

  @override
  String controller_heartbeatNote(int n) {
    return '心跳 $n/2';
  }

  @override
  String get controller_identifyPeerLabel => '辨識閘道器（閃燈）';

  @override
  String get controller_identifyRun => '辨識閘道器';

  @override
  String controller_identityConflict(int site, int gw) {
    return 'ID 衝突：偵測到多台實體設備使用相同 Site $site / 閘道器 $gw。';
  }

  @override
  String get controller_keepStationResetWifi =>
      '保留目前站點與 PTU，只重設 Wi-Fi。請選 2.4 GHz 的 Wi-Fi。';

  @override
  String controller_lastDone(String site, String gateway) {
    return '上一台已完成：站 $site 閘道器 $gateway';
  }

  @override
  String controller_lastDoneDeferred(String site, String gateway) {
    return '上一台已完成：站 $site 閘道器 $gateway（本樁 PTU 尚未連線，上電後自動連上）';
  }

  @override
  String get controller_leaveListConfirmTitle => '結束這次配置並回首頁？';

  @override
  String get controller_leaveListLabel => '結束配置';

  @override
  String get controller_linkConfirming => '藍牙已連線，正在確認閘道器回應與設定…';

  @override
  String get controller_listNotWritten => '名單沒有寫入，指派照常進行';

  @override
  String get controller_loginRun => '登入後端';

  @override
  String get controller_monitorSkipped => '已略過監控確認，請在資料驗證確認各台是否上傳。';

  @override
  String get controller_monitorUnconfirmedCheck => '尚未確認閘道器已恢復監控，請重新連線核對設定。';

  @override
  String get controller_monitorUnconfirmedRecheck => '尚未確認閘道器已恢復監控，請重新連線核對。';

  @override
  String controller_monitorUnconfirmedResume(String label) {
    return '尚未確認閘道器已恢復監控，請按「$label」核對。';
  }

  @override
  String get controller_netCheckIntro => '網路體檢：確認閘道器的 Wi-Fi 與資料上傳。';

  @override
  String get controller_newStationPrompt => '請輸入新的站點 ID 與 Wi-Fi；儲存後才會變更閘道器。';

  @override
  String controller_nextGateway(int site) {
    return '請選擇下一台閘道器；新的閘道器會預設沿用站 $site。';
  }

  @override
  String get controller_nextSetWifi => '接著設定 Wi-Fi。';

  @override
  String get controller_noChange => '不需變更';

  @override
  String get controller_noGatewayFound => '未找到閘道器，請靠近並確認電源後重掃。';

  @override
  String get controller_noPtuConnected =>
      '未連上任何 PTU，請確認 PTU 電源與距離後重試；閘道器仍維持監控。';

  @override
  String get controller_noneValue => '（無）';

  @override
  String controller_notIdentifiedPick(String mac) {
    return '閘道器目前連的是 PTU $mac，請先按「辨識此樁」確認是眼前這台，再按「是這台，開始配置」。';
  }

  @override
  String get controller_notReported => '（未回報）';

  @override
  String get controller_offlineMode => '離線模式：最後仍需登入驗證資料';

  @override
  String get controller_onlineReady => '閘道器持續上線，可搜尋 PTU';

  @override
  String get controller_onlineRun => '確認閘道器持續上線';

  @override
  String controller_partialAssign(int ok, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '已先讓 $ok 台上線；$failed 台指派失敗，可按「重試這 $failed 台」。',
    );
    return '$_temp0';
  }

  @override
  String controller_pendingReadback(int id) {
    return '已送出 #$id，待回讀確認';
  }

  @override
  String get controller_prepareRun => '檢查藍牙與後端連線';

  @override
  String get controller_prepared => '準備完成';

  @override
  String get controller_ptuBackHint => '閘道器已連上綁定的 PTU，不需要更換。';

  @override
  String controller_ptuBackTitle(String mac) {
    return 'PTU 已連線（$mac）';
  }

  @override
  String get controller_ptuConnectFailed => 'PTU 連線失敗，請確認 PTU 電源與距離';

  @override
  String controller_ptuCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台',
    );
    return '$_temp0';
  }

  @override
  String get controller_ptuCountReading => '讀取中…';

  @override
  String get controller_ptuCountUnread => '尚未讀取 PTU 列表';

  @override
  String controller_ptuCounts(int connected, int nearby) {
    return '已連線 $connected 台／周邊未連線 $nearby 台';
  }

  @override
  String controller_ptuJoinedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台 PTU 已連上',
    );
    return '$_temp0';
  }

  @override
  String get controller_ptuJoinedDirect => 'PTU 已連上閘道器';

  @override
  String get controller_ptuListBusy => '閘道器忙碌，列表暫時無法更新';

  @override
  String controller_ptuListBusyWithCounts(String busy, String counts) {
    return '$busy（下面是上一次的列表：$counts）';
  }

  @override
  String controller_ptuListLoading(int target) {
    return '讀取中…（目標 $target 台）';
  }

  @override
  String get controller_ptuMissingHint =>
      '請確認原 PTU 已上電。一般情況可透過手機藍牙更換，原 PTU 不需在場。後台同步與資料驗證仍需閘道器上網，且手機可連到後台。若只是更換網路，可先重設 Wi-Fi，不需 PTU 在場。';

  @override
  String controller_ptuMissingTitle(String tail) {
    return '本樁 PTU 不在場（綁定 MAC 後 4 碼 $tail）';
  }

  @override
  String get controller_ptuNoResponse => 'PTU 沒有回應';

  @override
  String get controller_ptuNotFound => '閘道器找不到這台 PTU，請重新掃描';

  @override
  String controller_ptuOtherTitle(String bound, String other) {
    return '連到的不是綁定的 PTU（綁定 MAC 後 4 碼 $bound，目前連 $other）';
  }

  @override
  String controller_ptuSearchingHint(String tail, String label) {
    return '閘道器剛開機或狀態剛變化，正在連線綁定的 PTU（MAC 後 4 碼 $tail），通常 1 分鐘內會連上；請稍候再按〔$label〕。';
  }

  @override
  String get controller_ptuSearchingRecheckLabel => '重新檢查';

  @override
  String get controller_ptuSearchingTitle => '正在尋找本樁 PTU…';

  @override
  String get controller_ptuSetupIncomplete => 'PTU 設定未完成，請靠近後重試';

  @override
  String controller_ptuUnnumbered(String mac) {
    return 'PTU $mac：PTU 未取得裝置編號（device_number=0）';
  }

  @override
  String controller_ptusReturned(int count, int target) {
    return '閘道器已回傳 $count 台 PTU，請選擇要監控的裝置，最多 $target 台';
  }

  @override
  String controller_readbackMismatch(int actual, int wanted) {
    return '回讀編號為 #$actual，不是指派的 #$wanted，請重試';
  }

  @override
  String get controller_recheckPtuLabel => 'PTU 已上電，重新檢查';

  @override
  String get controller_recheckingPtu => '正在重新檢查 PTU';

  @override
  String controller_reconnectContinueRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '重新連線並繼續（剩 $count 台）',
    );
    return '$_temp0';
  }

  @override
  String controller_reconnectFailedAttempts(int attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '重新連線失敗（已嘗試 $attempts 次），請靠近閘道器後再按一次',
    );
    return '$_temp0';
  }

  @override
  String get controller_reconnectLinkRun => '重新連線閘道器';

  @override
  String get controller_reconnectedRescan => '已重新連線，由閘道器重新掃描 PTU。';

  @override
  String get controller_reconnecting => '正在重新連線閘道器';

  @override
  String get controller_rejoining => '正在重新加入後台';

  @override
  String get controller_relinkReconnect => '手機與閘道器重新連線中…';

  @override
  String get controller_relinkReload => '重新讀取 PTU 列表…';

  @override
  String get controller_relinkingLabel => '重新連線中…';

  @override
  String get controller_relistingLabel => '讀取列表中…';

  @override
  String get controller_repairRequested => '已要求重新連線，請重新確認上線與資料';

  @override
  String get controller_repairRun => '重新連接閘道器';

  @override
  String get controller_replaceBindChanged => '閘道器的 PTU 綁定已改變，請重新連線核對；尚未變更綁定。';

  @override
  String get controller_replaceBleOff => '閘道器的 PTU 藍牙尚未啟用，請先確認裝置狀態；尚未變更綁定。';

  @override
  String get controller_replaceChanged => '閘道器或綁定已改變，請重新確認要更換的 PTU。';

  @override
  String get controller_replaceIdentityMismatch =>
      '閘道器身分、站點或一對一設定無法核對，請重新連線確認；未變更綁定。';

  @override
  String get controller_replaceJournalNotCleared =>
      'PTU 綁定已讀回，恢復紀錄尚未清除，請重新連線核對。';

  @override
  String get controller_replaceJournalSaveFailed => '無法保存 PTU 更換恢復紀錄，未變更綁定。';

  @override
  String get controller_replaceJournalUnreadable => '更換 PTU 的恢復紀錄無法讀取，請聯絡維護人員。';

  @override
  String get controller_replaceMustRestore => '請先重新連線還原上次更換 PTU 的綁定，不能略過恢復紀錄。';

  @override
  String get controller_replaceNotReadBack => '新 PTU 綁定尚未讀回確認，已停止更換。';

  @override
  String controller_replaceNotRestored(String label) {
    return '上次更換 PTU 尚未還原，請使用「$label」先核對原綁定。';
  }

  @override
  String get controller_replaceOtherBinding => '閘道器已有另一筆 PTU 綁定，未覆寫；請重新連線核對。';

  @override
  String get controller_replacePending => '上次更換尚未還原，請先取消並還原原綁定。';

  @override
  String controller_replacePtuConfirm(String mac) {
    return '會解除閘道器對 PTU $mac 的綁定（站點與 Wi-Fi 不變），通過裝置安全檢查後，透過手機藍牙在本機搜尋新的 PTU，原 PTU 不需在場。新綁定確認前取消或失敗會還原原綁定；藍牙中斷時請重新連線完成還原。後台同步與資料驗證仍需網路，尚未驗證前不算開通完成。';
  }

  @override
  String get controller_replacePtuConfirmTitle => '更換 PTU：解除綁定並重新配對？';

  @override
  String get controller_replacePtuLabel => '更換 PTU';

  @override
  String controller_replaceRestoreFailed(String mac) {
    return '無法進入「選擇 PTU」，且閘道器的 PTU 綁定未能還原成 $mac：請重新連線這台閘道器確認綁定。';
  }

  @override
  String get controller_replaceSearching => '正在本機搜尋新 PTU；後台同步與資料驗證仍需網路。';

  @override
  String get controller_replaceSetupRestored => 'PTU 配置未完成，已還原原綁定；請重新開始更換。';

  @override
  String get controller_replaceUnbindUnconfirmed => '閘道器尚未確認解除綁定，已停止更換。';

  @override
  String get controller_replaceUnfinished => '上次更換 PTU 尚未完成，請重新連線核對並還原原綁定。';

  @override
  String get controller_replacingPtu => '正在解除 PTU 綁定';

  @override
  String controller_reread(String status) {
    return '已重新讀取。$status';
  }

  @override
  String get controller_rereadStatusRun => '重新讀取閘道器狀態';

  @override
  String get controller_rescanAfterLossLabel => '重新連線並繼續';

  @override
  String get controller_rescanLabel => '重新掃描';

  @override
  String get controller_resetFailed => '重置失敗（連線逾時），請靠近後重試';

  @override
  String get controller_resetNumberRun => '重置編號，準備重新掃描';

  @override
  String controller_resettingStale(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '發現 $count 台殘留編號的 PTU，自動重置中',
    );
    return '$_temp0';
  }

  @override
  String get controller_restoredBind => '已核對並還原原 PTU 綁定。網路尚需重新檢查。';

  @override
  String get controller_restoringBind => '正在核對並還原原 PTU 綁定';

  @override
  String controller_resume(
    String where,
    String done,
    String inflight,
    String pending,
  ) {
    return '上次中斷於$where，$done$inflight$pending。閘道器仍在運作，不需重新上電。';
  }

  @override
  String controller_resumeDone(int count, String list) {
    return '已完成 $count 台（$list）';
  }

  @override
  String controller_resumeInflight(String list) {
    return '，$list 指派中斷、重新連線後以閘道器核對為準';
  }

  @override
  String get controller_resumeMonitoring => '恢復監控';

  @override
  String get controller_resumeNoneDone => '尚未完成任何 PTU';

  @override
  String controller_resumePending(int count) {
    return '，尚有 $count 台未配置';
  }

  @override
  String get controller_resumeUnknown => '已保留先前進度，請重新連線以核對裝置現況。';

  @override
  String get controller_resumeWithoutLogin => '未登入時無法自動收編殘留編號，將以手動模式繼續';

  @override
  String get controller_retryAssignRun => '重試指派失敗的 PTU';

  @override
  String get controller_reuseBlocked =>
      '閘道器還沒連上 Wi-Fi 或還沒開始上傳資料，暫時不能使用此站點。請先按「改用其他 Wi-Fi」，或回到網路體檢確認。';

  @override
  String get controller_reuseStationPrompt => '使用此站點，由閘道器搜尋 PTU，請確認要監控的裝置。';

  @override
  String get controller_savedStepFind => '第 2 步（找到閘道器）';

  @override
  String get controller_savedStepMonitor => '第 8 步（開始監控）';

  @override
  String get controller_savedStepNetCheck => '第 3 步（閘道器網路體檢）';

  @override
  String get controller_savedStepSelect => '第 7 步（選擇 PTU）';

  @override
  String get controller_savedStepUpload => '第 5 步（確認資料上傳）';

  @override
  String get controller_savedStepVerify => '第 9 步（驗證資料）';

  @override
  String controller_scanIncomplete(String label) {
    return '閘道器掃描未完成，請查看錯誤後按「$label」。';
  }

  @override
  String controller_scanLinkLost(String label) {
    return '閘道器掃描未完成：藍牙連線已中斷。請靠近閘道器，再按「$label」。';
  }

  @override
  String get controller_scanRun => '搜尋附近的閘道器';

  @override
  String controller_scanTestMode(String label) {
    return '閘道器在測試模式，不會掃描 PTU。請按「$label」，切換後 APP 會自動重新掃描。';
  }

  @override
  String get controller_scanningLabel => '掃描中…';

  @override
  String get controller_scanningPtus => '閘道器正在掃描周邊 PTU，請稍候';

  @override
  String controller_selectedDoneRest(int selected, int done, int rest) {
    return '已選 $selected 台 · 已完成 $done 台 · 將配置 $rest 台';
  }

  @override
  String controller_selectedOfTarget(int selected, int target) {
    return '已選 $selected / $target 台';
  }

  @override
  String controller_starApply(int limit) {
    return '閘道器目前只連 $limit 台；按下「配置」後，閘道器會切換為星狀並連線全部 PTU。';
  }

  @override
  String get controller_starOwnerUnknown => '無法確認閘道器登記狀態，請手動重置';

  @override
  String get controller_startVerify => '開始驗證';

  @override
  String controller_step7Retry(int seconds, int retry, int total) {
    return '藍牙連線又中斷，$seconds 秒後自動重新連線（第 $retry/$total 次重試）';
  }

  @override
  String controller_stepWhere(int step, String label) {
    return '第 $step 步（$label）';
  }

  @override
  String controller_stoppedStep8(int count, String label) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已停止。已完成的 $count 台保留，可按「$label」接續。',
    );
    return '$_temp0';
  }

  @override
  String controller_summary(int scanned, int configured) {
    return '掃到 $scanned 台，本機配置 $configured 台';
  }

  @override
  String controller_summaryOtherGateways(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '，$count 台屬於其他閘道器',
    );
    return '$_temp0';
  }

  @override
  String controller_summaryResetFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '，$count 台重置失敗',
    );
    return '$_temp0';
  }

  @override
  String controller_switchingPick(String mac) {
    return '正在讓閘道器改連 PTU $mac';
  }

  @override
  String controller_switchingTarget(String target) {
    return '正在把閘道器切到$target（會重新開機，約 1 分鐘）';
  }

  @override
  String controller_targetSwitched(String target, String next) {
    return '已把閘道器切到$target，閘道器已重新開機並重新連上。$next';
  }

  @override
  String controller_targetUnchanged(String target, String status) {
    return '不用切換：閘道器本來就送到$target（沒有重新開機）。$status';
  }

  @override
  String controller_tempRestoreFailed(
    String temp,
    String restore,
    String failure,
  ) {
    return '暫時綁定 $temp 未能還原成 $restore：$failure';
  }

  @override
  String controller_tempUnbindFailed(String temp, String failure) {
    return '暫時綁定 $temp 未能解除：$failure';
  }

  @override
  String controller_thresholdReadback(String wanted, String readBack) {
    return '寫入 $wanted，回讀 $readBack';
  }

  @override
  String get controller_topologyDirect => '一對一';

  @override
  String controller_topologyRelistPending(String reason) {
    return '$reason，PTU 列表需重新讀取';
  }

  @override
  String controller_topologyRelistReading(String reason) {
    return '$reason，重新讀取 PTU 列表…';
  }

  @override
  String get controller_topologyStar => '星狀';

  @override
  String controller_topologySwitched(String mode) {
    return '已切換為$mode';
  }

  @override
  String get controller_unbindingRun => '正在解除閘道器的 PTU 綁定';

  @override
  String get controller_unreadable => '（無法讀取）';

  @override
  String get controller_updatingDirect => '正在更新直連設定';

  @override
  String get controller_uploadConnecting => '閘道器正在連線，APP 會自動確認（最多約 2 分鐘）。';

  @override
  String get controller_uploadElsewhere => '閘道器的資料送到別的後台';

  @override
  String get controller_uploadNotReady =>
      '要等閘道器連上 Wi-Fi 並開始上傳資料，才能繼續選擇 PTU。請等「確認資料上傳」出現 ✓，或再重設一次 Wi-Fi。';

  @override
  String get controller_uploadStarted => '閘道器已開始上傳資料。';

  @override
  String get controller_verified => '開通驗證通過，已恢復自動監控';

  @override
  String controller_verifyFailed(String detail) {
    return '資料驗證未通過：\n$detail';
  }

  @override
  String controller_verifyNoData(int id) {
    return 'PTU #$id 尚無資料';
  }

  @override
  String controller_verifyProgress(String line) {
    return '資料驗證 $line';
  }

  @override
  String get controller_verifyRun => '確認每台 PTU 的資料持續進入後端';

  @override
  String controller_verifySkipped(int id) {
    return 'PTU #$id 未驗證（已略過）';
  }

  @override
  String get controller_verifyStopped => '已停止驗證，可調整勾選後重新配置。';

  @override
  String get controller_waitingBluetooth => '等待藍牙就緒';

  @override
  String get controller_wifiConnectedNext => 'WiFi 已連線，下一步確認後端看得到閘道器';

  @override
  String get controller_wifiFirstCheck => 'Wi-Fi 已連上。網路體檢還有項目沒通過，請依下方提示處理。';

  @override
  String get controller_wifiFirstDone => '網路已正常，接著設定站號。';

  @override
  String get controller_wifiFirstPrompt =>
      '請先設定 Wi-Fi（閘道器只能用 2.4 GHz），網路正常後再設定站號。';

  @override
  String get controller_wifiFirstRunLabel => '設定 Wi-Fi';

  @override
  String controller_wifiKept(String ssid) {
    return '閘道器已連上 $ssid，沿用';
  }

  @override
  String controller_wifiKeptDone(String ssid) {
    return '沿用 Wi-Fi $ssid（未重新連線），下一步確認後端看得到閘道器';
  }

  @override
  String get controller_wifiOnlyPrompt => '保留目前站點與 PTU，僅更新 Wi-Fi。';

  @override
  String get controller_wifiUpdatedChooseStation =>
      'Wi-Fi 已更新，資料上傳正常。請確認站點：這台閘道器目前的站點若不是這裡，請選「改用其他站號」。';

  @override
  String get controller_wifiUpdatedKeepStation =>
      'Wi-Fi 已更新，站點與 PTU 設定保留。接著確認資料有上傳。';

  @override
  String controller_writingThreshold(String dbm) {
    return '正在寫入門檻 $dbm dBm';
  }

  @override
  String get controller_wrongDevice => '指派到錯誤裝置，請重試';

  @override
  String get coreProgressChecklist_connectBackend => '後台連線正常';

  @override
  String get coreProgressChecklist_connectBle => '藍牙連線';

  @override
  String get coreProgressChecklist_connectStatus => '讀取閘道器狀態';

  @override
  String get coreProgressChecklist_connectWifi => 'Wi-Fi 已連線';

  @override
  String coreProgressChecklist_dataEach(int count, int need) {
    return '每台 $count/$need 筆';
  }

  @override
  String coreProgressChecklist_dataReceived(int count, int need) {
    return '收到 $count/$need 筆';
  }

  @override
  String get coreProgressChecklist_finishAssign => '指派 PTU';

  @override
  String coreProgressChecklist_finishAssignTotal(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '指派 PTU（共 $total 台）',
    );
    return '$_temp0';
  }

  @override
  String get coreProgressChecklist_finishBind => '寫入 PTU 綁定';

  @override
  String get coreProgressChecklist_finishData => '驗證資料上傳';

  @override
  String get coreProgressChecklist_finishJoin => '加入監控';

  @override
  String get coreProgressChecklist_finishJoined => '核對已加入監控';

  @override
  String get coreProgressChecklist_finishList => '寫入 PTU 名單';

  @override
  String get coreProgressChecklist_finishSettings => '寫入 PTU 設定';

  @override
  String get coreProgressChecklist_notDone => '沒有完成';

  @override
  String get coreProgressChecklist_onlineBackend => '連上後台';

  @override
  String get coreProgressChecklist_onlineBeat1 => '收到第 1 次心跳';

  @override
  String get coreProgressChecklist_onlineBeat2 => '收到第 2 次心跳（持續上線）';

  @override
  String get coreProgressChecklist_onlineTarget => '上傳目標確認';

  @override
  String get coreProgressChecklist_targetCurrent => '送到目前的後台';

  @override
  String get coreProgressChecklist_targetLocal => '本地測試';

  @override
  String dashboardApi_backend(String origin) {
    return '後端 $origin';
  }

  @override
  String dashboardApi_backendLocal(String origin) {
    return '區域網路／本機後端 $origin';
  }

  @override
  String get dashboardApi_backendUnset => '（尚未設定後端網址）';

  @override
  String directCalibrationSheet_intro(int seconds) {
    return '本樁與鄰近樁請維持實際擺放與電源。取樣 $seconds 秒後建議門檻，確認後才寫入閘道器。';
  }

  @override
  String get directCalibrationSheet_legacyFirmware => '閘道器韌體較舊，未回報';

  @override
  String directCalibrationSheet_median(String value) {
    return '中位數 $value';
  }

  @override
  String directCalibrationSheet_medianSkipped(String value) {
    return '中位數 $value（未列入上限）';
  }

  @override
  String get directCalibrationSheet_neighborLegacy =>
      '鄰近訊號取自閘道器最近一次選台聽到的其他 PTU（峰值），連線後不再更新。';

  @override
  String directCalibrationSheet_neighborLive(int maxAge) {
    return '鄰近訊號為閘道器連線中持續聽到的其他 PTU（峰值；$maxAge 秒內都列入計算）。';
  }

  @override
  String get directCalibrationSheet_noNeighbor => '未聽到鄰近 PTU';

  @override
  String get directCalibrationSheet_notRead => '尚未讀到';

  @override
  String get directCalibrationSheet_notReported => '閘道器未回報';

  @override
  String get directCalibrationSheet_ownAdv => '本樁廣播訊號';

  @override
  String get directCalibrationSheet_ownLink => '本樁連線訊號';

  @override
  String directCalibrationSheet_ownLinkValue(
    String median,
    String weakest,
    int count,
  ) {
    return '中位數 $median · 最弱 $weakest（$count 筆）';
  }

  @override
  String directCalibrationSheet_ownPtu(String mac) {
    return '本樁 PTU：$mac';
  }

  @override
  String directCalibrationSheet_peak(String value) {
    return '峰值 $value';
  }

  @override
  String directCalibrationSheet_range(String lower, String upper) {
    return '可用範圍 $lower ～ $upper：本樁選得到、連上後不會被踢，本樁關機時也不會連到鄰近樁。';
  }

  @override
  String get directCalibrationSheet_resample => '重新取樣';

  @override
  String directCalibrationSheet_sampleDone(int reads) {
    String _temp0 = intl.Intl.pluralLogic(
      reads,
      locale: localeName,
      other: '取樣完成（讀取 $reads 次）',
    );
    return '$_temp0';
  }

  @override
  String directCalibrationSheet_sampling(int left, int reads) {
    return '取樣中… 剩 $left 秒（已讀取 $reads 次）';
  }

  @override
  String get directCalibrationSheet_saveFailed => '門檻未寫入閘道器，請重試。';

  @override
  String directCalibrationSheet_saved(String label, int value) {
    return '$label：$value dBm';
  }

  @override
  String get directCalibrationSheet_strongestNeighbor => '最強鄰近訊號';

  @override
  String directCalibrationSheet_suggestion(int threshold, int current) {
    return '建議門檻：$threshold dBm（目前 $current dBm）';
  }

  @override
  String directCalibrationSheet_tiesAll(int count, int db) {
    return '$count 台相差 $db dB 內，一併列出';
  }

  @override
  String directCalibrationSheet_tiesListed(int ties, int db, int listed) {
    return '$ties 台相差 $db dB 內，列出 $listed 台';
  }

  @override
  String directCalibrationSheet_tooClose(String reason, String advice) {
    return '$reason。$advice。';
  }

  @override
  String get directCalibrationSheet_write => '寫入閘道器';

  @override
  String directCalibrationSheet_writeValue(int threshold) {
    return '寫入閘道器（$threshold dBm）';
  }

  @override
  String get directCalibrationSheet_writing => '寫入中…';

  @override
  String directCalibration_ambiguous(int db) {
    return '本樁與鄰近樁的廣播訊號相差不到 $db dB：選台時可能判為不確定，綁定後就不受影響。';
  }

  @override
  String directCalibration_fewSamples(int count, int min, String rescan) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 台鄰近 PTU 讀數較少（不足 $min 筆），已計入下限但可能不穩定，請按「$rescan」再取樣一次。',
    );
    return '$_temp0';
  }

  @override
  String directCalibration_gapEqual(String neighbor) {
    return '鄰近樁 $neighbor 和本樁一樣強';
  }

  @override
  String directCalibration_gapSmall(String neighbor, int gap, int min) {
    return '鄰近樁 $neighbor 只比本樁弱 $gap dB，餘裕不足（至少要弱 $min dB）';
  }

  @override
  String directCalibration_gapStronger(String neighbor, int db) {
    return '鄰近樁 $neighbor 比本樁還強 $db dB';
  }

  @override
  String directCalibration_holdLabel(int hold) {
    return '維持目前門檻（$hold dBm），不需寫入';
  }

  @override
  String get directCalibration_needsOwn => '請先在第 7 步按「辨識此樁」確認本樁 PTU，再校正門檻。';

  @override
  String directCalibration_neighborsAndMore(String named, int total) {
    return '$named 等 $total 台';
  }

  @override
  String directCalibration_noNeighbor(int hold) {
    return '未偵測到鄰近 PTU（已連線的 PTU 不會廣播），無法確認放寬是否安全，建議維持 $hold dBm。';
  }

  @override
  String get directCalibration_noOwn =>
      '未取得本樁 PTU 的連線訊號（閘道器目前沒有連著已確認的 PTU），無法建議門檻。請確認本樁 PTU 已連上後重新取樣。';

  @override
  String get directCalibration_outOfRange =>
      '本樁讀數已超出閘道器可用範圍（-100～-20 dBm），請重新取樣';

  @override
  String directCalibration_ownBelowHold(int upper, int hold) {
    return '本樁 PTU 訊號偏弱（可用上限 $upper dBm，低於門檻 $hold dBm），但沒有鄰近資料不能放寬門檻：請確認已開啟「確認後綁定 PTU」（綁定後不受門檻影響），或調整 PTU 擺放後重新取樣。';
  }

  @override
  String get directCalibration_referenceLegacy => '參考值（閘道器韌體較舊）';

  @override
  String get directCalibration_referenceNoAdv => '參考值（閘道器未回報本樁廣播訊號）';

  @override
  String directCalibration_referenceStaleAdv(int minutes) {
    return '參考值（本樁廣播值超過 $minutes 分鐘，上限只用連線訊號）';
  }

  @override
  String get directCalibration_referenceUndatedAdv =>
      '參考值（本樁廣播值未附選台時間，上限只用連線訊號）';

  @override
  String get directCalibration_rescanLabel => '重新掃描鄰近';

  @override
  String get directCalibration_saved => '已寫入閘道器（重開機仍保留）';

  @override
  String directCalibration_selfAdvMinutes(int minutes) {
    return '本樁廣播值來自 $minutes 分鐘前選台';
  }

  @override
  String directCalibration_selfAdvSeconds(int seconds) {
    return '本樁廣播值來自 $seconds 秒前選台';
  }

  @override
  String get directCalibration_selfAdvUndated => '本樁廣播值未附選台時間';

  @override
  String directCalibration_stale(int age, int max, String rescan) {
    return '鄰近資料已 $age 秒未更新（超過 $max 秒，未列入計算），請按「$rescan」再取樣一次。';
  }

  @override
  String get directCalibration_title => '校正門檻';

  @override
  String get directCalibration_tooClose => '鄰近樁訊號太強，無法只靠門檻區分，請在確認後綁定此 PTU';

  @override
  String get directModePanel_askBackOffice => '請後台協助';

  @override
  String directModePanel_autoThreshold(int value, int defaultValue) {
    return '自動連線門檻：$value dBm（預設 $defaultValue）';
  }

  @override
  String get directModePanel_bindCurrent => '綁定目前 PTU';

  @override
  String get directModePanel_bindOnConfirm => '確認後綁定 PTU';

  @override
  String get directModePanel_bindOnConfirmOff =>
      '關閉後不會鎖定 MAC：本樁 PTU 關機或斷線時，閘道器可能改連鄰近樁的 PTU';

  @override
  String directModePanel_bindOnConfirmOn(String label) {
    return '按「$label」時把該 PTU 的 MAC 存進閘道器，之後只連這台';
  }

  @override
  String directModePanel_bound(String mac) {
    return '已綁定 $mac';
  }

  @override
  String directModePanel_boundOnly(String mac) {
    return '已綁定 $mac，只連這台';
  }

  @override
  String directModePanel_calibrateButton(String title, int seconds) {
    return '$title（現場取樣 $seconds 秒）';
  }

  @override
  String get directModePanel_cancelAction => '取消操作';

  @override
  String directModePanel_candidatesHint(int count) {
    return '附近候選（$count）：點選後閘道器會綁定並改連那一台，再按「辨識此樁」確認。';
  }

  @override
  String get directModePanel_cannotBind => '尚未連上 PTU，無法綁定';

  @override
  String directModePanel_causeBound(String mac) {
    return '已綁定 PTU $mac：閘道器只連這台。若本樁已更換 PTU，請按「解除綁定」後重新搜尋。';
  }

  @override
  String directModePanel_causeDefer(String label) {
    return 'PTU 暫時不在場（尚未安裝或斷電）：按「$label」，閘道器照常加入運作，PTU 上電後會自動連上。';
  }

  @override
  String get directModePanel_causeDenied =>
      '附近的 PTU 已綁定給其他充電樁（已自動略過）；本樁 PTU 可能尚未上電。';

  @override
  String get directModePanel_causeHelp => '仍找不到：按「請後台協助」，後台可看到閘道器狀態協助判斷。';

  @override
  String get directModePanel_causeHousing =>
      '擺放或機殼遮蔽：PTU 要和閘道器裝在同一個機殼內；金屬外殼、天線被擋住都會讓訊號變弱。';

  @override
  String directModePanel_causeNone(int min) {
    return '沒有聽到任何 PTU，請確認本樁 PTU 電源（門檻 $min dBm）。';
  }

  @override
  String get directModePanel_causePower => '本樁 PTU 沒有上電：確認 PTU 電源開啟、指示燈有亮。';

  @override
  String directModePanel_causeWeak(String rssi, int min, String mac) {
    return '附近 PTU 訊號太弱（$rssi dBm，門檻 $min）：PTU $mac 可能是鄰近樁的 PTU——請不要為了連上而放寬門檻。';
  }

  @override
  String get directModePanel_collecting => '閘道器正在重新收集附近的 PTU，約需 5–10 秒…';

  @override
  String get directModePanel_currentPick => '目前選中';

  @override
  String get directModePanel_gatewayBusy => '閘道器處理中，請稍候…';

  @override
  String get directModePanel_hintConfirm => '確認閃燈的是這台 PTU，再開始監控';

  @override
  String get directModePanel_hintIdentify => '點「辨識此樁」，確認現場燈號';

  @override
  String get directModePanel_identifyDetailTitle => '辨識訊息';

  @override
  String get directModePanel_identifyThis => '辨識此樁';

  @override
  String get directModePanel_keep => '保留';

  @override
  String directModePanel_linkedNow(String mac) {
    return '目前連線：$mac';
  }

  @override
  String get directModePanel_macLabel => '裝置編號（MAC）';

  @override
  String get directModePanel_moreActions => '更多操作';

  @override
  String get directModePanel_noCandidates => '閘道器目前沒有回報附近候選，請按「重新搜尋」或稍後再試。';

  @override
  String get directModePanel_noPick => '尚未取得閘道器的選台結果，請按「重新搜尋」。';

  @override
  String get directModePanel_noPtuTitle => '找不到本樁 PTU：可能原因與處理';

  @override
  String get directModePanel_notLinked => '閘道器尚未連上 PTU';

  @override
  String get directModePanel_notThis => '不是這台？';

  @override
  String get directModePanel_pickOther => '改選其他 PTU';

  @override
  String get directModePanel_pickedTitle => '閘道器選中的 PTU';

  @override
  String get directModePanel_readingPick => '正在讀取閘道器的選台結果…';

  @override
  String directModePanel_reason(String reason) {
    return '選台依據：$reason';
  }

  @override
  String get directModePanel_release => '解除';

  @override
  String get directModePanel_searchAgain => '重新搜尋';

  @override
  String get directModePanel_settingsTitle => '直連進階設定';

  @override
  String get directModePanel_signalLabel => '訊號';

  @override
  String get directModePanel_switchToThis => '改連這台';

  @override
  String directModePanel_threshold(int min) {
    return '門檻 $min dBm';
  }

  @override
  String get directModePanel_thresholdHelp =>
      '閘道器只自動連線訊號強於門檻的 PTU；數值越大（越接近 -20）要越靠近。';

  @override
  String get directModePanel_unbind => '解除綁定';

  @override
  String get directModePanel_unbound => '未綁定';

  @override
  String get directModePanel_watchLights => '按下後請看樁上 PTU 與閘道器的燈號';

  @override
  String directMode_ackPlain(String note, String gateway) {
    return '$note；$gateway。';
  }

  @override
  String directMode_ackWithNumber(String note, String number, String gateway) {
    return '$note（#$number）；$gateway。';
  }

  @override
  String directMode_advRssi(int rssi) {
    return '廣播 $rssi dBm（連線訊號讀取中）';
  }

  @override
  String directMode_advStale(int rssi) {
    return '$rssi dBm（廣播值）';
  }

  @override
  String get directMode_ambiguous => '附近有訊號相近的 PTU，請按「辨識此樁」確認是否為眼前這台';

  @override
  String get directMode_confirmLabel => '是這台，開始配置';

  @override
  String get directMode_hintBoundMissing =>
      '已綁定的 PTU 不在場，請確認其電源；若已更換 PTU，請解除綁定';

  @override
  String get directMode_hintNoCandidate => '請靠近／確認同樁 PTU 已上電';

  @override
  String get directMode_identifyConfirmTimeout =>
      '閘道器已送出；舊版閘道器未取得 PTU 確認，請看樁上燈號';

  @override
  String get directMode_identifyConfirmed => 'PTU 已確認亮燈';

  @override
  String get directMode_identifyFirstLabel => '請先按「辨識此樁」確認';

  @override
  String directMode_identifyFirstText(String confirm) {
    return '請先按「辨識此樁」確認是眼前這台，再按「$confirm」。';
  }

  @override
  String get directMode_identifyNoPtu => '閘道器雙閃 4 秒；閘道器尚未連上 PTU，PTU 不會閃燈。';

  @override
  String get directMode_identifyPending => '已送出，等待閘道器回應…';

  @override
  String get directMode_identifySent => '已送出，請看樁上燈號';

  @override
  String get directMode_identifySentLine => '已送出 · 請看樁上燈號';

  @override
  String get directMode_identifyUnsupportedPattern =>
      '閘道器已送出；PTU 不支援此燈效，請看樁上燈號';

  @override
  String get directMode_lineGatewayOnly => '已送出 · 只有閘道器閃燈，PTU 未收到';

  @override
  String get directMode_lineOffSent => '已送出關燈指令';

  @override
  String get directMode_lineStopPtuNotSent => '閘道器已停止辨識 · PTU 關燈未送出';

  @override
  String get directMode_lineTimeout => '已送出 · PTU 未回應確認 · 請看樁上燈號';

  @override
  String get directMode_lineUnsupportedPattern => '已送出 · PTU 不支援此燈效 · 請看樁上燈號';

  @override
  String directMode_noteGatewayOnly(String reason) {
    return '已送出：只有閘道器在閃燈，PTU 未收到（$reason）';
  }

  @override
  String directMode_noteOffSent(String gateway) {
    return '已送出關燈指令；$gateway。PTU 不回覆，請查看燈號。';
  }

  @override
  String directMode_noteStopPtuNotSent(String gateway, String reason) {
    return '$gateway；PTU 關燈未送出（$reason）';
  }

  @override
  String directMode_noteWithDetail(String head, String detail) {
    return '$head（$detail）';
  }

  @override
  String directMode_ptuFailedBlinking(int seconds, String reason) {
    return '閘道器正在閃燈（$seconds 秒）；PTU 指令未送出（$reason）。';
  }

  @override
  String directMode_ptuFailedStop(String reason) {
    return '閘道器已停止辨識；PTU 關燈未送出（$reason）。';
  }

  @override
  String get directMode_ptuWriteAmbiguousTarget => '閘道器連著多台 PTU，沒有指定哪一台';

  @override
  String get directMode_ptuWriteFailed => '閘道器寫入 PTU 失敗';

  @override
  String get directMode_ptuWriteNotConnected => '閘道器尚未連上 PTU';

  @override
  String get directMode_ptuWriteOther => 'PTU 沒有收到指令';

  @override
  String get directMode_reasonAmbiguous => '附近訊號相近，閘道器暫選最強的一台';

  @override
  String get directMode_reasonBound => '已綁定這台，閘道器只連它';

  @override
  String get directMode_reasonOk => '訊號最強且明確';

  @override
  String get directMode_reasonResume => '延續既有連線';

  @override
  String get directMode_remoteGateway => '後台讓閘道器閃燈（請看閘道器上的燈）';

  @override
  String get directMode_remoteHeadConfirmed => '後台已讓此樁閃燈 · PTU 已確認';

  @override
  String get directMode_remoteHeadGatewayOnly => '後台已讓閘道器閃燈 · PTU 未收到';

  @override
  String get directMode_remoteHeadOffSent => '後台已送出關燈指令';

  @override
  String get directMode_remoteHeadPtuSent => '後台已送出 PTU 辨識指令';

  @override
  String get directMode_remoteHeadSent => '後台已送出 · 請查看燈號';

  @override
  String get directMode_remoteHeadStopped => '後台已停止閘道器辨識';

  @override
  String get directMode_remoteHeadTimeout => '後台已送出 · 舊版未取得確認';

  @override
  String get directMode_remoteHeadUnsupportedPattern => '後台已送出 · PTU 不支援燈效';

  @override
  String directMode_remoteOffNotSent(String gateway) {
    return '後台：$gateway；PTU 關燈未送出';
  }

  @override
  String directMode_remoteOffSent(String gateway) {
    return '後台已送出 PTU 關燈指令；$gateway';
  }

  @override
  String directMode_remoteSentPtu(String label) {
    return '後台已送出 PTU $label 辨識指令（請看樁上燈號）';
  }

  @override
  String get directMode_remoteSentPtuUnnamed => '後台已送出 PTU 辨識指令（請看樁上燈號）';

  @override
  String directMode_resultGatewayOnly(String reason) {
    return '只有閘道器閃燈（$reason）';
  }

  @override
  String get directMode_resultIdentifySent => 'PTU 辨識指令已送出';

  @override
  String get directMode_resultOffSent => 'PTU 關燈指令已送出';

  @override
  String get directMode_resultTimeout => '舊版閘道器未取得 PTU 確認';

  @override
  String get directMode_resultUnsupportedPattern => 'PTU 不支援此燈效';

  @override
  String directMode_rssiPeak(int rssi) {
    return '峰值 $rssi dBm';
  }

  @override
  String get directMode_rssiReading => '訊號讀取中…';

  @override
  String get directMode_settlingLabel => '連線建立中…';

  @override
  String get directMode_stateBoundMissing => '已綁定的 PTU 不在場';

  @override
  String get directMode_stateConnected => '已連上 PTU';

  @override
  String get directMode_stateConnecting => '正在連線 PTU';

  @override
  String get directMode_stateNoCandidate => '找不到夠近的 PTU';

  @override
  String get directMode_stateScanning => '正在尋找最近的 PTU';

  @override
  String directMode_strayBind(String mac) {
    return '閘道器目前綁定 PTU $mac';
  }

  @override
  String get directMode_strayBindHint =>
      '這個綁定不是在本機確認過的：保留則閘道器只連這台；解除則恢復自動選最近的 PTU。';

  @override
  String directMode_switched(String mac) {
    return '閘道器已切換到另一顆 PTU（$mac），請重新辨識';
  }

  @override
  String directMode_unbindFailed(String mac) {
    return '已取消，但閘道器的暫時綁定（PTU $mac）未能解除；下次進入第 7 步會再詢問是否解除。';
  }

  @override
  String directMode_unbindRestoreFailed(String restore) {
    return '已取消，但閘道器的 PTU 綁定未能還原成原本的 $restore；請重新連線這台閘道器確認綁定。';
  }

  @override
  String directMode_unbindTempRestoreFailed(String mac, String restore) {
    return '已取消，但閘道器的暫時綁定（PTU $mac）未能還原成原本的綁定 $restore；下次進入第 7 步會再詢問。';
  }

  @override
  String get directMode_waitingLabel => '等待閘道器連上 PTU';

  @override
  String get directPickActivity_ambiguousIdentify => '訊號相近，請辨識此樁';

  @override
  String get directPickActivity_boundMissing => '已綁定的 PTU 不在場';

  @override
  String get directPickActivity_connected => '等待閘道器回報選中的 PTU';

  @override
  String get directPickActivity_connecting => '閘道器正在連線 PTU';

  @override
  String get directPickActivity_foundConfirm => '已找到 PTU，請確認是眼前此樁';

  @override
  String get directPickActivity_foundIdentify => '已找到 PTU，請辨識此樁';

  @override
  String get directPickActivity_gatewayEndpoint => '閘道器';

  @override
  String get directPickActivity_identifySent => '已送出辨識，請確認燈號';

  @override
  String get directPickActivity_noCandidate => '尚未找到 PTU，請確認電源';

  @override
  String get directPickActivity_noStatus => '尚未取得 PTU 狀態';

  @override
  String get directPickActivity_reading => '正在讀取 PTU 狀態';

  @override
  String get directPickActivity_scanning => '閘道器正在搜尋 PTU';

  @override
  String get directPickActivity_unavailable => '連線待確認，請依提示重試';

  @override
  String environmentSwitch_blocked(String task) {
    return '正在進行「$task」，完成或按「取消操作」後才能切換。';
  }

  @override
  String environmentSwitch_blockedPrep(String task) {
    return '正在進行「$task」，完成後才能切換。';
  }

  @override
  String get environmentSwitch_changeIp => '變更電腦 IP';

  @override
  String get environmentSwitch_customNotSet => '使用自訂的後端網址（尚未設定）';

  @override
  String environmentSwitch_customUrl(String url) {
    return '使用自訂的後端網址：$url';
  }

  @override
  String get environmentSwitch_editIp => '可修改測試主機的 IP：';

  @override
  String get environmentSwitch_localNoHost => '資料送到這台電腦上的測試主機（還沒設定電腦 IP）';

  @override
  String environmentSwitch_localWithHost(String host) {
    return '資料送到這台電腦上的測試主機（$host）';
  }

  @override
  String get environmentSwitch_noIp => '還沒有測試主機的 IP，請按「自動尋找」或直接輸入。';

  @override
  String get environmentSwitch_productionHint => '資料送到正式站。';

  @override
  String get environmentSwitch_productionSheetHint => '資料送到正式站';

  @override
  String get environmentSwitch_sheetSubtitle => '手機和已連上的閘道器會一起切換。';

  @override
  String get environmentSwitch_title => '切換連線環境';

  @override
  String get environmentSwitch_urlLabel => '後端網址';

  @override
  String get environmentSwitch_useLocal => '使用本地測試';

  @override
  String get environmentSwitch_useUrl => '使用這個網址';

  @override
  String get fieldHelpSheet_demo => '示範模式不會傳送，請直接唸下面的資訊。';

  @override
  String get fieldHelpSheet_label => '請後台協助';

  @override
  String get fieldHelpSheet_needsConnection => '已切換後台，請先連線到新的後台，再重新求助。';

  @override
  String get fieldHelpSheet_noPassword => '不會傳送 Wi-Fi 密碼。';

  @override
  String fieldHelpSheet_queued(String reason) {
    return '⚠ 目前送不出去（$reason），後台暫時看不到。請在電話中直接唸下面的資訊。';
  }

  @override
  String get fieldHelpSheet_queuedNoReason => '沒有網路／尚未登入後台';

  @override
  String get fieldHelpSheet_readOut => '請唸給後台：';

  @override
  String get fieldHelpSheet_resend => '重新傳送';

  @override
  String get fieldHelpSheet_sending => '正在通知後台…';

  @override
  String get fieldHelpSheet_sent => '✓ 求助已送達後台';

  @override
  String get fieldHelpSheet_unsupported => '後台版本還不支援線上通知，請直接唸下面的資訊。';

  @override
  String fieldReport_backendRefused(String status) {
    return '後台拒收（HTTP $status）';
  }

  @override
  String get fieldReport_backendSwitched => '已切換後台，報告沒有送出';

  @override
  String get fieldReport_backendUnsupported => '後台尚未支援（請更新後台）';

  @override
  String fieldReport_helpCode(String code) {
    return '狀況代碼：$code';
  }

  @override
  String fieldReport_helpCondition(String label) {
    return '狀況：$label';
  }

  @override
  String fieldReport_helpError(String error) {
    return '錯誤：$error';
  }

  @override
  String fieldReport_helpFirmwareDirect(String fw) {
    return '韌體 $fw · 直連';
  }

  @override
  String fieldReport_helpFirmwareStar(String fw, int count) {
    return '韌體 $fw · 星狀 $count 台';
  }

  @override
  String fieldReport_helpGatewayName(String name) {
    return '閘道器 $name';
  }

  @override
  String fieldReport_helpGatewayNameMac(String name, String tail) {
    return '閘道器 $name（MAC 後 4 碼 $tail）';
  }

  @override
  String get fieldReport_helpNoGateway => '還沒連上閘道器';

  @override
  String fieldReport_helpStationGateway(String site, String gateway) {
    return '站 $site / 閘道器 $gateway';
  }

  @override
  String fieldReport_helpStationGatewayMac(
    String site,
    String gateway,
    String tail,
  ) {
    return '站 $site / 閘道器 $gateway（MAC 後 4 碼 $tail）';
  }

  @override
  String fieldReport_helpStep(int step, String label) {
    return '目前第 $step 步：$label';
  }

  @override
  String get fieldReport_noNetwork => '沒有網路或後台沒有回應';

  @override
  String get fieldReport_notLoggedIn => '尚未登入後台';

  @override
  String get fieldReport_removedFromOutbox => '已從手機的待送清單移除';

  @override
  String get fieldSupportPanel_askAgain => '再次求助';

  @override
  String get fieldSupportPanel_checkFirst => '請先核對目前畫面與設備，再依指引操作。';

  @override
  String get fieldSupportPanel_confirmFailed => '尚未確認回覆結果，請重新整理；若指引更新，請看完後再回覆。';

  @override
  String get fieldSupportPanel_fetchFailed =>
      '暫時無法取得後台回覆；以下若有內容是上次收到的，請重新整理或電話聯絡。';

  @override
  String fieldSupportPanel_instructionHeader(String step) {
    return '後台指引 · 當時第 $step 步';
  }

  @override
  String fieldSupportPanel_instructionHeaderAt(String step, String time) {
    return '後台指引 · 當時第 $step 步 · $time';
  }

  @override
  String fieldSupportPanel_instructionTarget(
    String site,
    String gateway,
    String mac,
  ) {
    return '指引對象：站 $site / 閘道器 $gateway · MAC $mac';
  }

  @override
  String get fieldSupportPanel_notConnected => '請先連線到目前選擇的後台，再查看協助回覆。';

  @override
  String get fieldSupportPanel_otherGateway =>
      '這是其他閘道器的協助紀錄，請勿照做；請更新求助資訊，讓後台確認目前設備。';

  @override
  String get fieldSupportPanel_refresh => '重新整理回覆';

  @override
  String get fieldSupportPanel_reopenHint => '關閉後可點頂部「請後台協助」再次查看回覆。';

  @override
  String get fieldSupportPanel_replying => '回覆中…';

  @override
  String get fieldSupportPanel_resolved => '已解決';

  @override
  String get fieldSupportPanel_stateCallSupport => '請電話聯絡後台協助';

  @override
  String get fieldSupportPanel_stateHandling => '後台已接手，處理中';

  @override
  String get fieldSupportPanel_stateLoading => '正在取得協助狀態…';

  @override
  String get fieldSupportPanel_statePending => '等待後台接手';

  @override
  String get fieldSupportPanel_stateResolved => '你已確認解決';

  @override
  String get fieldSupportPanel_stateWaitingField => '後台已提供指引，請操作後回覆';

  @override
  String get fieldSupportPanel_stillHelp => '仍需協助';

  @override
  String get fieldSupportPanel_unavailable =>
      '目前無法在 APP 查看文字回覆，請將下方設備與步驟資訊告知後台。';

  @override
  String get fieldSupportPanel_updateRequest => '更新求助資訊';

  @override
  String get gatewayDiscovery_backendNoRecordNote =>
      '目前後台查無此設備紀錄。若尚未開通，請點選『開始開通』；若已開通，請確認連線狀態與所選站點。';

  @override
  String get gatewayDiscovery_backendOfflineNote =>
      '後台目前未收到此設備的連線訊號。請確認電源與 Wi-Fi；若已更換網路環境，請重新設定 Wi-Fi。';

  @override
  String get gatewayDiscovery_backendReferenceNote =>
      '沒有本機身分核對紀錄時，後端狀態只參考相同站號及閘道器編號；連線後再確認裝置身分。';

  @override
  String get gatewayDiscovery_backendRefreshNote =>
      '後端狀態每 15 秒更新，僅代表目前選擇的後端環境。';

  @override
  String get gatewayDiscovery_bluetoothConnect => '藍牙連線';

  @override
  String get gatewayDiscovery_busy => '正在連線並讀取設定…';

  @override
  String get gatewayDiscovery_cancelConnect => '取消連線';

  @override
  String get gatewayDiscovery_cleanupFailed => '藍牙清理未完成，請重試斷開。';

  @override
  String get gatewayDiscovery_cleanupIncomplete => '清理未完成';

  @override
  String gatewayDiscovery_connectLabel(String title) {
    return '開始開通：$title';
  }

  @override
  String get gatewayDiscovery_connecting => '連線中…';

  @override
  String get gatewayDiscovery_disconnect => '斷開';

  @override
  String get gatewayDiscovery_disconnecting => '斷開中…';

  @override
  String gatewayDiscovery_found(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到 $count 台',
    );
    return '$_temp0';
  }

  @override
  String gatewayDiscovery_foundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已找到 $count 台',
    );
    return '$_temp0';
  }

  @override
  String gatewayDiscovery_foundPick(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到 $count 台，請點選本樁的那台',
    );
    return '$_temp0';
  }

  @override
  String get gatewayDiscovery_gatewayOnlyBoundMissingNote =>
      '閘道器已閃燈；找不到已綁定的 PTU，請確認原 PTU 已開機並在附近';

  @override
  String get gatewayDiscovery_gatewayOnlyHint => '閘道器已閃・PTU 不會閃';

  @override
  String get gatewayDiscovery_gatewayOnlyNoPtuNote =>
      '閘道器已閃燈；閘道器附近沒聽到 PTU，請確認 PTU 已上電';

  @override
  String get gatewayDiscovery_gatewayOnlyNote => '閘道器已閃燈；它目前沒連到 PTU，PTU 不會閃';

  @override
  String get gatewayDiscovery_gatewayOnlyPickingNote =>
      '閘道器已閃燈；閘道器正在選擇 PTU，請 3 秒後再按';

  @override
  String gatewayDiscovery_gatewayOnlySnack(String title, String note) {
    return '$title：$note';
  }

  @override
  String get gatewayDiscovery_gatewayOnlySwitchedNote =>
      '閘道器已閃燈；已切換為一對一，閘道器正在重新尋找 PTU，請稍後再按';

  @override
  String gatewayDiscovery_gatewayOnlyWeakNote(int best, int min) {
    return '閘道器已閃燈；PTU 訊號太弱（最強 $best dBm，需 ≥ $min），請靠近或檢查天線';
  }

  @override
  String get gatewayDiscovery_held => '已連線';

  @override
  String get gatewayDiscovery_holdFailed => '連線失敗';

  @override
  String gatewayDiscovery_holdFailedText(String title) {
    return '無法連線 $title，請按「藍牙連線」重試';
  }

  @override
  String get gatewayDiscovery_holdLost => '已斷線';

  @override
  String gatewayDiscovery_holdLostText(String title) {
    return '$title 的藍牙連線已中斷，請按「藍牙連線」重新連線';
  }

  @override
  String get gatewayDiscovery_identifiedHint => '已送出';

  @override
  String gatewayDiscovery_identifiedSnack(String title) {
    return '$title 已送出';
  }

  @override
  String get gatewayDiscovery_identifyIncomplete => '辨識未完成，請重新連線後再試。';

  @override
  String get gatewayDiscovery_identifyLabel => '閃燈辨識';

  @override
  String gatewayDiscovery_nearbyGroup(int count) {
    return '附近裝置（$count）';
  }

  @override
  String get gatewayDiscovery_notConnected => '未連線';

  @override
  String get gatewayDiscovery_notFound => '未發現附近閘道器。請確認電源、靠近裝置，並確認沒有被其他手機連線。';

  @override
  String get gatewayDiscovery_pending => '待核對';

  @override
  String get gatewayDiscovery_pickCardHint => '先選擇要配置的閘道器卡片，再點「藍牙連線」';

  @override
  String get gatewayDiscovery_pickFirst => '請先選擇閘道器';

  @override
  String get gatewayDiscovery_recentGroup => '最近使用';

  @override
  String get gatewayDiscovery_retryDisconnect => '重試斷開';

  @override
  String get gatewayDiscovery_retrying => '沒找到，再搜尋一次…';

  @override
  String get gatewayDiscovery_rssiNote => 'RSSI 為手機收到的藍牙訊號，與後端在線狀態不同。';

  @override
  String get gatewayDiscovery_scanFailed => '搜尋失敗，請確認藍牙、定位與附近裝置權限後重試。';

  @override
  String get gatewayDiscovery_searchAgain => '重新搜尋';

  @override
  String get gatewayDiscovery_searchPaused => '已選取閘道器，搜尋已暫停';

  @override
  String get gatewayDiscovery_searching => '正在搜尋附近的閘道器…';

  @override
  String get gatewayDiscovery_selectNearby => '選擇附近的閘道器';

  @override
  String get gatewayDiscovery_selected => '已選取';

  @override
  String get gatewayDiscovery_signalLost => '訊號中斷';

  @override
  String get gatewayDiscovery_signalUnknown => '訊號未知';

  @override
  String get gatewayDiscovery_startCommissioning => '開始開通';

  @override
  String get gatewayDiscovery_stopSearch => '停止搜尋';

  @override
  String get gatewayDiscovery_stopped => '已停止搜尋，按〔重新搜尋〕再找一次';

  @override
  String get gatewayDiscovery_unconfigured => '未配置';

  @override
  String get gatewayIdentity_confirmOnlineLabel => '確認閘道器上線';

  @override
  String gatewayIdentity_directGatewayPick(String mac) {
    return '閘道器連到的是附近另一台閘道器（$mac），不是 PTU，APP 不會把它當成 PTU。請按「不是這台？」改選同樁的 PTU，或靠近同樁 PTU 後按「重新搜尋」。';
  }

  @override
  String gatewayIdentity_idText(int site, int gateway) {
    return '站 $site · 閘道器 $gateway';
  }

  @override
  String get gatewayIdentity_leaveTestModeLabel => '切回正常模式';

  @override
  String get gatewayIdentity_leavingTestMode => '正在把閘道器切回正常模式（會重新開機，約 1 分鐘）';

  @override
  String get gatewayIdentity_leftTestMode => '閘道器已切回正常模式並重新連上，可以繼續配置。';

  @override
  String gatewayIdentity_macTail(String tail) {
    return 'MAC 後 4 碼 $tail';
  }

  @override
  String gatewayIdentity_macTailWithBle(String tail, String ble) {
    return 'MAC 後 4 碼 $tail（藍牙 $ble）';
  }

  @override
  String get gatewayIdentity_resumeUploadLabel => '恢復上傳';

  @override
  String get gatewayIdentity_resumingUpload => '正在恢復資料上傳';

  @override
  String get gatewayIdentity_testMode =>
      '這台閘道器處於測試模式（只產生測試資料、不會連 PTU），配置前需切回正常模式。';

  @override
  String get gatewayIdentity_testModeActionHint =>
      '切回後閘道器會重新開機（約 1 分鐘），APP 會自動重新連線並繼續。';

  @override
  String gatewayIdentity_testModeStatusHint(String leave) {
    return '閘道器在測試模式（只產生測試資料），請按「$leave」。';
  }

  @override
  String get gatewayIdentity_testModeUpload => '閘道器在測試模式：只上傳測試資料，不會上傳 PTU 資料。';

  @override
  String get gatewayIdentity_unconfigured => '未配置閘道器';

  @override
  String get gatewayIdentity_uploadHeld =>
      '後台連線正常。PTU 資料會在完成配置後自動開始上傳（目前暫停是正常的），APP 會自動繼續';

  @override
  String get gatewayIdentity_uploadHeldStatus => '✓ 已連上（完成配置後才上傳）';

  @override
  String gatewayIdentity_uploadPaused(String resume) {
    return '閘道器已連上後台，但資料上傳已暫停：PTU 資料不會送出。請按「$resume」。';
  }

  @override
  String gatewayIdentity_uploadPausedStatusHint(String resume) {
    return '閘道器的資料上傳已暫停，PTU 資料不會送出；請按「$resume」。';
  }

  @override
  String get gatewayIdentity_uploadResumed => '已恢復資料上傳，閘道器開始送出 PTU 資料。';

  @override
  String get gatewayModeCard_resumeHint => '恢復後閘道器立刻開始送出 PTU 資料，不會重新開機。';

  @override
  String get gatewayNet_connecting => '閘道器正在連 Wi-Fi…';

  @override
  String gatewayNet_discDetail(String kind, int code) {
    return 'Wi-Fi 最後斷線原因：$kind（代碼 $code）';
  }

  @override
  String gatewayNet_discDetailAge(String kind, int code, int age) {
    return 'Wi-Fi 最後斷線原因：$kind（代碼 $code，$age 秒前）';
  }

  @override
  String get gatewayNet_discLeave => '閘道器自行中斷';

  @override
  String get gatewayNet_discNotFound => '找不到這個 Wi-Fi';

  @override
  String get gatewayNet_discPassword => '密碼可能錯誤';

  @override
  String get gatewayNet_discWeak => '訊號弱或其他';

  @override
  String gatewayNet_ok(String wifi) {
    return '閘道器已連上 $wifi';
  }

  @override
  String get gatewayNet_problemNotConfigured => '閘道器還沒有設定 Wi-Fi，所以沒辦法上傳資料。';

  @override
  String gatewayNet_problemNotFound(String wifi) {
    return '閘道器找不到 $wifi。請確認名稱正確、是 2.4 GHz（閘道器不支援 5 GHz），且基地台就在附近。';
  }

  @override
  String gatewayNet_problemPassword(String wifi) {
    return '閘道器連不上 $wifi：密碼可能錯誤，請確認密碼（含大小寫）後重新輸入。';
  }

  @override
  String gatewayNet_problemUnknown(String wifi) {
    return '閘道器連不上 $wifi。這個 Wi-Fi 可能不在附近、密碼不對，或是 5 GHz（閘道器只能用 2.4 GHz）。';
  }

  @override
  String gatewayNet_problemWeak(String wifi) {
    return '閘道器連不上 $wifi，可能是訊號太弱或基地台暫時拒絕連線。請把閘道器移近基地台、避開金屬遮蔽後再試。';
  }

  @override
  String get gatewayNet_setFailedNotFound =>
      '新 Wi-Fi 連線未成功：閘道器找不到這個 Wi-Fi。請確認名稱正確、是 2.4 GHz（不支援 5 GHz），且基地台就在附近。';

  @override
  String get gatewayNet_setFailedPassword =>
      '新 Wi-Fi 連線未成功：密碼可能錯誤，請確認密碼（含大小寫）後重試。';

  @override
  String get gatewayNet_setFailedUnknown => '新 Wi-Fi 連線未成功，請檢查密碼與訊號後重試。';

  @override
  String get gatewayNet_setFailedWeak =>
      '新 Wi-Fi 連線未成功：可能是訊號太弱或基地台暫時拒絕連線，請把閘道器移近基地台後重試。';

  @override
  String gatewayNet_ssidNamed(String ssid) {
    return 'Wi-Fi「$ssid」';
  }

  @override
  String get gatewayNet_stateConnecting => '連線中（connecting）';

  @override
  String get gatewayNet_stateDisconnected => '未連線（disconnected）';

  @override
  String get gatewayNet_stateGotIp => '已連線（got_ip）';

  @override
  String get gatewayNet_stateUnknown => '未知';

  @override
  String gatewayNet_stateUnknownRaw(String raw) {
    return '未知（$raw）';
  }

  @override
  String gatewayNet_weak(int rssi, int limit) {
    return '⚠ Wi-Fi 訊號偏弱（$rssi dBm，低於 $limit dBm），資料可能時斷時續。建議把閘道器移近基地台、避開金屬遮蔽，或在附近加裝 Wi-Fi 延伸器。';
  }

  @override
  String get gatewayProximity_closeHint => '兩台距離相近，請連線後按燈泡辨識確認';

  @override
  String get gatewayProximity_nearest => '最近';

  @override
  String get gatewayProximity_nearestHint =>
      '本樁的閘道器通常是訊號最強的那台；不確定就點選它，連線後按燈泡看哪台閃燈';

  @override
  String gatewayReboot_notice(String reason) {
    return '閘道器剛重新啟動（原因：$reason）。這不是 PTU 故障，閘道器上已完成的設定都會保留。APP 已重新連上，請從目前的步驟繼續，不用從頭開始，也不要拔電或重複按。';
  }

  @override
  String gatewayReboot_noticeMany(String reason, int times) {
    return '閘道器剛重新啟動（原因：$reason；期間共重新啟動 $times 次）。這不是 PTU 故障，閘道器上已完成的設定都會保留。APP 已重新連上，請從目前的步驟繼續，不用從頭開始，也不要拔電或重複按。若短時間內一再重新啟動，請拍下這個畫面回報。';
  }

  @override
  String get gatewayReboot_reasonBleStackStuck => '藍牙功能卡住，閘道器自動重新啟動修復';

  @override
  String get gatewayReboot_reasonBrownout => '供電電壓不足（電源不穩或變壓器太弱）';

  @override
  String get gatewayReboot_reasonCpuLockup => '閘道器處理器卡住，自動重新啟動';

  @override
  String get gatewayReboot_reasonDeepSleep => '從省電休眠中醒來';

  @override
  String get gatewayReboot_reasonPanic => '閘道器程式發生錯誤，自動重新啟動';

  @override
  String get gatewayReboot_reasonPowerGlitch => '電源瞬間不穩';

  @override
  String get gatewayReboot_reasonPowerOn => '曾經斷電後重新上電';

  @override
  String get gatewayReboot_reasonResetButton => '有人按了重置鍵';

  @override
  String get gatewayReboot_reasonSoftware => '收到重新啟動指令或設定變更';

  @override
  String get gatewayReboot_reasonUnknown => '原因不明';

  @override
  String get gatewayReboot_reasonUsb => '接上電腦時被重置';

  @override
  String get gatewayReboot_reasonWatchdog => '閘道器程式卡住，看門狗保護機制自動重新啟動';

  @override
  String get gatewayReboot_retry => '剛才的操作因閘道器重新啟動而中斷（不是 PTU 故障），請再按一次剛才的按鈕繼續。';

  @override
  String gatewaySignal_demoScan(String value) {
    return '模擬・掃描 $value';
  }

  @override
  String gatewaySignal_disconnectedLast(String value) {
    return '已斷線・上次 $value';
  }

  @override
  String gatewaySignal_disconnectedScan(String value) {
    return '已斷線・掃描 $value';
  }

  @override
  String gatewaySignal_last(String value) {
    return '上次 $value';
  }

  @override
  String gatewaySignal_line(String status) {
    return '手機 ↔ 閘道器：$status';
  }

  @override
  String get gatewaySignal_linkLost => '手機與閘道器的藍牙已斷線，請靠近閘道器；APP 會提示如何重新連線。';

  @override
  String get gatewaySignal_noReading => '尚無讀值';

  @override
  String gatewaySignal_scan(String value) {
    return '掃描 $value';
  }

  @override
  String gatewayStatus_dataAgo(String age) {
    return '$age前';
  }

  @override
  String gatewayStatus_doneAt(String time) {
    return '$time 完成';
  }

  @override
  String get gatewayStatus_fleetEmpty => '後台目前沒有任何閘道器。';

  @override
  String get gatewayStatus_fleetTitle => '後台在線閘道器';

  @override
  String gatewayStatus_gatewayCount(int count) {
    return '$count 台閘道器';
  }

  @override
  String gatewayStatus_heartbeatAgo(String age) {
    return '心跳 $age前';
  }

  @override
  String get gatewayStatus_hint => '展開站號，再點選閘道器查看最近資料。';

  @override
  String get gatewayStatus_homeCaption => '架設完後，看資料有沒有正常送到後台';

  @override
  String get gatewayStatus_label => '查看上傳資料';

  @override
  String get gatewayStatus_loading => '正在向後台查詢…';

  @override
  String gatewayStatus_name(int site, int gateway) {
    return '站 $site 閘道器 $gateway';
  }

  @override
  String get gatewayStatus_nearbyEmpty => '附近沒有掃到閘道器，請靠近後按〔重新掃描〕';

  @override
  String get gatewayStatus_nearbyScanFailed => '掃描失敗，請確認藍牙、定位與附近裝置權限後重試。';

  @override
  String get gatewayStatus_nearbyScanning => '正在掃描附近閘道器（約 8 秒）…';

  @override
  String get gatewayStatus_nearbyTitle => '附近閘道器（藍牙掃描）';

  @override
  String get gatewayStatus_nearbyUnconfigured => '尚未配置，無法查看資料';

  @override
  String get gatewayStatus_nearbyUnnamed => '尚未設定站號，無法查看資料';

  @override
  String get gatewayStatus_nearest => '最近';

  @override
  String get gatewayStatus_noData => '尚無資料';

  @override
  String get gatewayStatus_offline => '離線';

  @override
  String get gatewayStatus_online => '在線';

  @override
  String get gatewayStatus_openSettings => '開啟權限設定';

  @override
  String get gatewayStatus_ptuConnected => 'PTU 已連線';

  @override
  String get gatewayStatus_ptuDisconnected => 'PTU 未連線';

  @override
  String get gatewayStatus_recentEmpty => '這支手機尚未用此版本完成過配置';

  @override
  String get gatewayStatus_recentTitle => '最近配置（這支手機）';

  @override
  String get gatewayStatus_rescan => '重新掃描';

  @override
  String gatewayStatus_siteGroup(int site) {
    return '站 $site';
  }

  @override
  String get gatewayStatus_unconfiguredGroup => '未配置／站號未確認';

  @override
  String get gatewaySwapSheet_assignmentHint => '（取代舊機）';

  @override
  String gatewaySwapSheet_assignmentHintTail(String tail) {
    return '（取代舊機 $tail）';
  }

  @override
  String get gatewaySwapSheet_cancelLabel => '取消換機';

  @override
  String get gatewaySwapSheet_confirmOk => '確定換機';

  @override
  String gatewaySwapSheet_confirmText(int site, int gateway) {
    return '這台將接手 站 $site · 閘道器 $gateway。舊機必須已拆除或斷電。';
  }

  @override
  String gatewaySwapSheet_confirmTextTail(int site, int gateway, String tail) {
    return '這台將接手 站 $site · 閘道器 $gateway。舊機（$tail）必須已拆除或斷電。';
  }

  @override
  String get gatewaySwapSheet_confirmTitle => '確定換機？';

  @override
  String get gatewaySwapSheet_label => '這台是來換掉壞掉的舊機';

  @override
  String gatewaySwapSheet_lastSeen(String age) {
    return '最後上線 $age前';
  }

  @override
  String get gatewaySwapSheet_needsNetwork => '換機需要連上網路';

  @override
  String get gatewaySwapSheet_noRecord => '沒有上線紀錄';

  @override
  String get gatewaySwapSheet_none => '本站沒有離線的閘道器可以取代';

  @override
  String gatewaySwapSheet_online(int gateway) {
    return '閘道器 $gateway 目前在線上，請先把舊機斷電。';
  }

  @override
  String gatewaySwapSheet_rowTitle(int gateway) {
    return '閘道器 $gateway';
  }

  @override
  String get gatewaySwapSheet_sheetHint => '只列出本站目前離線的閘道器；舊機必須已拆除或斷電。';

  @override
  String gatewaySwapSheet_sheetTitle(int site) {
    return '選擇要取代的舊機（站 $site）';
  }

  @override
  String get gatewayTopology_directLabel => '直連模式（一對一）';

  @override
  String get gatewayTopology_directShort => '直連模式';

  @override
  String get gatewayTopology_starLabel => '星狀模式（一對多）';

  @override
  String get gatewayTopology_starShort => '星狀模式';

  @override
  String heartbeatActivity_announcement(int received, String message) {
    return '已收到 $received 次心跳。$message';
  }

  @override
  String get heartbeatActivity_backOffice => '後台';

  @override
  String get heartbeatActivity_confirmed => '已確認閘道器持續上線';

  @override
  String get heartbeatActivity_connectingBackend => '正在連上後台';

  @override
  String heartbeatActivity_count(int received) {
    return '心跳 $received/2';
  }

  @override
  String get heartbeatActivity_gotOne => '已收到 1 次，等待下一次心跳';

  @override
  String get heartbeatActivity_gotTwo => '已收到 2 次，正在確認上傳目標';

  @override
  String get heartbeatActivity_notDone => '尚未完成心跳確認';

  @override
  String get heartbeatActivity_paused => '確認暫停，請依提示重試';

  @override
  String get heartbeatActivity_waitingFirst => '等待第 1 次心跳';

  @override
  String get heartbeatActivity_waitingStart => '等待開始確認';

  @override
  String get homeEntry_backHome => '返回首頁';

  @override
  String get homeEntry_configure => '現場配置';

  @override
  String get homeEntry_configureAction => '進入配置';

  @override
  String get homeEntry_configureDescription => '安裝新設備、設定網路、綁定 PTU 並確認資料上傳';

  @override
  String get homeEntry_savedProgress => '有未完成的配置，可進入後繼續';

  @override
  String get homeEntry_title => '選擇要進行的操作';

  @override
  String get homeEntry_viewData => '查看數據';

  @override
  String get homeEntry_viewDataAction => '查看數據';

  @override
  String get homeEntry_viewDataDescription => '查看各站充電功率、效率、電池狀態與異常資訊';

  @override
  String get identifyDurationSetting_fieldLabel => '秒數（0 或 2–10）';

  @override
  String get identifyDurationSetting_help =>
      '預設 4 秒。閘道器與 PTU 使用相同秒數。可填 2–10 秒；0＝關燈，閘道器會停止辨識並恢復正常狀態燈。不提供 1 秒（PTU 的 1 秒封包會讓燈恆亮）。';

  @override
  String get identifyDurationSetting_save => '儲存秒數';

  @override
  String get identifyDurationSetting_saveFailed => '無法儲存，請重試';

  @override
  String identifyDurationSetting_saved(int seconds) {
    return '已儲存：$seconds 秒';
  }

  @override
  String get identifyDurationSetting_savedOff => '已儲存：0 秒（關閉辨識燈）';

  @override
  String get identifyDurationSetting_saving => '儲存中…';

  @override
  String get identifyDurationSetting_suffix => '秒';

  @override
  String get identifyDurationSetting_title => '辨識秒數';

  @override
  String identify_gatewayBlink(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '閘道器雙閃 $seconds 秒',
    );
    return '$_temp0';
  }

  @override
  String get identify_gatewayLedUnavailable => '閘道器燈效無法使用';

  @override
  String get identify_gatewayStopped => '閘道器已停止辨識，恢復正常燈號';

  @override
  String get identify_ptuOnly => '僅處理 PTU，閘道器燈號未變更';

  @override
  String get identify_secondsError =>
      '請輸入 0（關燈）或 2–10 的整數秒數（1 秒會讓 PTU 燈恆亮，不提供）';

  @override
  String get installReportPanel_resend => '重送';

  @override
  String get installReport_demo => '模擬模式：報告不送後台';

  @override
  String get installReport_failed => '報告沒有送到後台';

  @override
  String installReport_failedReason(String reason) {
    return '報告沒有送到後台：$reason';
  }

  @override
  String get installReport_queued => '排隊中，網路恢復後自動送';

  @override
  String installReport_queuedReason(String reason) {
    return '排隊中，網路恢復後自動送（$reason）';
  }

  @override
  String get installReport_sending => '正在把報告送到後台…';

  @override
  String get installReport_sent => '報告已送到後台';

  @override
  String installReport_sentAt(String time) {
    return '報告已送到後台 $time';
  }

  @override
  String get localBackendAddress_hostEmpty => '請輸入電腦的 IP 位址';

  @override
  String get localBackendAddress_hostFormat =>
      '格式應為 4 組 0–255 的數字，例如 192.168.1.187';

  @override
  String get localBackendAddress_hostLastOctet => '最後一組不可為 0 或 255';

  @override
  String get localBackendAddress_hostLoopback => '127.x 是手機本身，請輸入電腦在區域網路的 IP';

  @override
  String get localBackendAddress_hostNotPrivate =>
      '只接受區域網路位址（10.x、172.16–31.x、192.168.x）';

  @override
  String get localBackendAddress_portRange => '連接埠需為 1–65535';

  @override
  String localBackendField_advancedPort(String port) {
    return '進階：連接埠 $port';
  }

  @override
  String get localBackendField_autoFind => '自動尋找';

  @override
  String get localBackendField_dbNotReady => '資料庫尚未就緒';

  @override
  String localBackendField_filledNotReady(String host) {
    return '已填入 $host，但該後端的資料庫尚未就緒，請稍後按「測試連線」確認。';
  }

  @override
  String localBackendField_foundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到 $count 台本地後端',
    );
    return '$_temp0';
  }

  @override
  String localBackendField_foundFilled(String host) {
    return '✓ 找到本地後端 $host，已自動填入。';
  }

  @override
  String localBackendField_foundNotChosen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到 $count 台本地後端，尚未選擇。',
    );
    return '$_temp0';
  }

  @override
  String get localBackendField_gettingSubnet => '正在取得手機的 Wi-Fi 網段…';

  @override
  String get localBackendField_ipLabel => '電腦 IP 位址';

  @override
  String get localBackendField_noPhoneIp =>
      '找不到手機的 Wi-Fi IP。請先讓手機連上與電腦相同的 Wi-Fi 後再試。';

  @override
  String localBackendField_notFound(String subnet, String port) {
    return '在 $subnet 網段找不到本地後端（連接埠 $port）。';
  }

  @override
  String localBackendField_notFoundTimedOut(String subnet, String port) {
    return '在 $subnet 網段找不到本地後端（連接埠 $port）。（已達搜尋時間上限）';
  }

  @override
  String localBackendField_portDefault(String port) {
    return '預設 $port';
  }

  @override
  String get localBackendField_portDialogTitle => '本地後端連接埠';

  @override
  String get localBackendField_portLabel => '連接埠';

  @override
  String get localBackendField_restoreDefault => '還原預設';

  @override
  String get localBackendField_scanCancelled => '已取消搜尋。';

  @override
  String localBackendField_searching(String host, int done, int total) {
    return '正在搜尋 $host…（$done／$total）';
  }

  @override
  String get localBackendField_testConnection => '測試連線';

  @override
  String get localBackendField_testing => '測試中…';

  @override
  String localBackendField_version(String version) {
    return '版本 $version';
  }

  @override
  String localBackendField_willConnect(String url) {
    return '將連線：$url';
  }

  @override
  String get localBackendField_willConnectNone => '將連線：（請先輸入正確的 IP）';

  @override
  String get localBackendProbe_degraded =>
      '✗ 已連到本地後端，但資料庫尚未就緒（HTTP 503）。請等 Docker 本地後端完全啟動後重試。';

  @override
  String get localBackendProbe_healthy => '✓ 已連上本地後端';

  @override
  String localBackendProbe_healthyVersion(String version) {
    return '✓ 已連上本地後端（版本 $version）';
  }

  @override
  String get localBackendProbe_hint =>
      '請確認：手機與電腦在同一個 Wi-Fi、電腦已啟動 Docker 本地後端、電腦防火牆已執行 allow_local_api_lan.ps1。';

  @override
  String localBackendProbe_httpError(String status) {
    return '✗ 回應不是本地後端（HTTP $status）。請確認電腦 IP 與連接埠。';
  }

  @override
  String localBackendProbe_notBackend(String status) {
    return '✗ 回應不是本地後端（HTTP $status）。這個 IP／連接埠上是其他服務，請確認電腦 IP。';
  }

  @override
  String localBackendProbe_timeout(String message) {
    return '✗ 逾時：$message';
  }

  @override
  String localBackendProbe_unreachable(String message) {
    return '✗ 無法連線：$message';
  }

  @override
  String get mqttTarget_failBleOnly => '上傳目標只能在現場透過藍牙切換，不接受遠端指令。';

  @override
  String get mqttTarget_failBusy => '閘道器正在處理其他指令，請稍候重試。';

  @override
  String get mqttTarget_failInvalidHost =>
      '閘道器拒絕切換：本地後端位址必須是區網私有 IPv4（10.x、172.16–31.x、192.168.x），不可使用主機名稱或公網 IP。';

  @override
  String get mqttTarget_failInvalidParams => '閘道器拒絕切換：指令參數格式錯誤。請更新 APP 後重試。';

  @override
  String get mqttTarget_failInvalidPort => '閘道器拒絕切換：MQTT 連接埠必須是 1–65535 的整數。';

  @override
  String get mqttTarget_failInvalidReqId => 'APP 送出的指令編號無效，請重新連線後重試。';

  @override
  String get mqttTarget_failInvalidTarget => '閘道器拒絕切換：上傳目標名稱無效。請更新 APP 後重試。';

  @override
  String get mqttTarget_failNoReason => '閘道器拒絕切換上傳目標（未提供原因）。';

  @override
  String get mqttTarget_failNotReady => '閘道器仍在開機初始化，請稍候數秒後重試。';

  @override
  String get mqttTarget_failNvsWrite =>
      '閘道器儲存設定失敗，上傳目標未變更、也沒有重新開機。請重試；若持續失敗請回報。';

  @override
  String get mqttTarget_failOtaInProgress =>
      '閘道器正在更新韌體（OTA），更新完成前無法切換上傳目標，請稍後重試。';

  @override
  String get mqttTarget_failOther => '閘道器拒絕切換上傳目標。';

  @override
  String get mqttTarget_failOtpInvalid => '一次性密碼（OTP）錯誤，閘道器拒絕切換。';

  @override
  String get mqttTarget_failOtpLocked => 'OTP 錯誤次數過多，閘道器暫時鎖定，請稍後再試。';

  @override
  String get mqttTarget_failOtpRequired =>
      '此閘道器已啟用一次性密碼（OTP），切換上傳目標需要 OTP，請聯絡管理員。';

  @override
  String get mqttTarget_failOtpReused => '此一次性密碼已使用過，請等下一組 OTP 後重試。';

  @override
  String get mqttTarget_failTimeNotSynced =>
      '閘道器已啟用 OTP 但時間尚未同步（NTP），無法驗證。若目前 Wi-Fi 無法連到網際網路，請先改用可連外的網路。';

  @override
  String get mqttTarget_failUnknownOp => '閘道器韌體不支援切換上傳目標，需更新至 1.7.3 以上。';

  @override
  String mqttTarget_legacyFirmware(String version) {
    return '這台閘道器韌體太舊（版本 $version），只能送到正式站，請更新到 1.7.3 以上。';
  }

  @override
  String mqttTarget_localHost(String host) {
    return '本地 $host';
  }

  @override
  String mqttTarget_localHostNotPrivate(String host) {
    return '本地測試站網址的主機「$host」不是區網私有 IPv4 位址（10.x.x.x、172.16–31.x.x、192.168.x.x），閘道器無法上傳到此後端。請把網址改成電腦的區網 IP。';
  }

  @override
  String mqttTarget_localHostPort(String host, String port) {
    return '本地 $host:$port';
  }

  @override
  String get mqttTarget_localUrlEmpty => '尚未輸入本地測試站網址，無法決定閘道器的上傳目標。';

  @override
  String mqttTarget_localUrlUnparsable(String url) {
    return '本地測試站網址「$url」無法解析主機位址，請輸入如 http://192.168.1.10:18000 的網址。';
  }

  @override
  String mqttTarget_plainLocal(String host) {
    return '本地測試主機（$host）';
  }

  @override
  String get mqttTarget_plainProduction => '正式站';

  @override
  String get mqttTarget_production => '正式站';

  @override
  String mqttTarget_productionHostPort(String host, String port) {
    return '正式站 $host:$port';
  }

  @override
  String mqttTarget_reportLegacy(String version) {
    return '資料上傳目標：正式站（韌體 $version 固定）';
  }

  @override
  String mqttTarget_reportLine(String where) {
    return '資料上傳目標：$where';
  }

  @override
  String mqttTarget_reportNote(String warning) {
    return '注意：$warning';
  }

  @override
  String get mqttTarget_reportUnconfirmed => '資料上傳目標：未確認';

  @override
  String get mqttTarget_shipWarning => '此閘道器目前上傳到本地測試站，出貨前請切回正式站。';

  @override
  String get networkCheck_reuseNoWifi => '閘道器還沒連上 Wi-Fi';

  @override
  String get networkCheck_reuseNotUploading => '閘道器還沒開始上傳資料';

  @override
  String get networkCheck_reuseTargetMismatch => '閘道器的資料還沒送到手機連的地方';

  @override
  String get networkCheck_reuseTestMode => '閘道器在測試模式';

  @override
  String get networkCheck_reuseUploadPaused => '閘道器的資料上傳已暫停';

  @override
  String get networkCheck_stepAlignTarget => '對準上傳目標';

  @override
  String get networkCheck_stepChoosePtu => '選擇 PTU';

  @override
  String get networkCheck_stepChooseSite => '站點選擇';

  @override
  String get networkCheck_stepConfirmUpload => '確認資料上傳';

  @override
  String get networkCheck_stepFindGateway => '找到閘道器';

  @override
  String get networkCheck_stepNetworkCheck => '閘道器網路體檢';

  @override
  String get networkCheck_stepPrepare => '準備';

  @override
  String get networkCheck_stepStartMonitoring => '開始監控';

  @override
  String get networkCheck_stepVerifyData => '驗證資料';

  @override
  String networkCheck_targetInvalid(String error) {
    return '$error請點右上角的環境按鈕修正。';
  }

  @override
  String networkCheck_targetMatch(String current) {
    return '閘道器的資料送到$current，和手機一致';
  }

  @override
  String networkCheck_targetMismatch(String current, String phone) {
    return '閘道器把資料送到$current，但手機連的是$phone。';
  }

  @override
  String get networkCheck_targetProductionFixed => '閘道器的資料送到正式站';

  @override
  String networkCheck_targetUndecidable(String current) {
    return '閘道器的資料送到$current；APP 無法從這個網址判斷是否一致。';
  }

  @override
  String get networkCheck_targetUnknown => '還不確定閘道器把資料送到哪裡。';

  @override
  String networkCheck_targetUnknownSync(String place) {
    return '還不確定閘道器把資料送到哪裡，要讓它改送到$place。';
  }

  @override
  String get networkCheck_uploadAfterTarget => '對準上傳目標後再確認';

  @override
  String get networkCheck_uploadAfterWifi => '等閘道器連上 Wi-Fi 後再確認';

  @override
  String get networkCheck_uploadLinkLost => '手機和閘道器的藍牙斷了，無法確認。';

  @override
  String get networkCheck_uploadLinkLostHint => '請靠近閘道器，按「結束並重新選擇閘道器」重新連線。';

  @override
  String get networkCheck_uploadNotConfirmed => '還沒確認資料上傳，請按「重新檢查」。';

  @override
  String get networkCheck_uploadNotStarted => '閘道器還沒開始上傳資料。';

  @override
  String get networkCheck_uploadUnsupported => '無法確認，最後的資料驗證會再確認。';

  @override
  String get networkCheck_uploadWaiting => '等待閘道器開始上傳資料…（最多約 1 分鐘）';

  @override
  String get networkCheck_uploading => '資料上傳中';

  @override
  String get networkCheck_wifiNotRead => '還沒讀到閘道器的網路狀態，請按「重新檢查」。';

  @override
  String get networkCheck_wifiReading => '正在讀取閘道器的網路狀態…';

  @override
  String get networkCheck_wifiResetAction => '重設 Wi-Fi';

  @override
  String networkCheck_wifiUnsupported(String fw) {
    return 'APP 無法讀取這台閘道器的 Wi-Fi（韌體 $fw 較舊），最後的資料驗證會再確認。';
  }

  @override
  String get nextActionGuide_captionBegin => '連線完成，可以開始開通';

  @override
  String get nextActionGuide_captionConnect => '確認目標後，點下方連線';

  @override
  String get nextActionGuide_captionStart => '從這裡開始';

  @override
  String get protocol_ambiguousTarget =>
      '閘道器同時連著多台 PTU，無法判斷要辨識哪一台，請指定 PTU 後重試。';

  @override
  String get protocol_authentication => '後台登入失敗或已失效，請稍後重試；若仍失敗，請聯絡管理員更新 APP。';

  @override
  String get protocol_backendUnavailable =>
      '後端暫時無回應，已自動重試 60 秒仍未恢復。請確認後端後按「重試」，已累計的驗證進度會保留。';

  @override
  String protocol_badResponse(String backend) {
    return '後端回應格式無法解析（$backend）。';
  }

  @override
  String protocol_bleErrorCode(String code) {
    return '無法連上閘道器（藍牙錯誤 $code），請靠近閘道器後重試';
  }

  @override
  String get protocol_bleErrorNoCode => '無法連上閘道器（藍牙錯誤），請靠近閘道器後重試';

  @override
  String get protocol_bluetoothOff => '請開啟手機藍牙後重試。';

  @override
  String get protocol_cancelled => '操作已取消，可從最近完成的步驟重試。';

  @override
  String get protocol_conflict => '此站點或編號已被使用，請選擇其他編號。';

  @override
  String get protocol_currentBackend => '目前設定的後端';

  @override
  String get protocol_directDeferUnconfirmed =>
      '閘道器沒有回報已加入運作並恢復上傳，配置尚未完成。請再按一次「先完成配置」；若仍不行，請按「請後台協助」。';

  @override
  String get protocol_directNoPtu => '閘道器目前沒有連上 PTU，無法綁定。請等 PTU 連上後再試。';

  @override
  String get protocol_directPickMissing => '閘道器目前沒有連上 PTU，請確認 PTU 電源後按「重新搜尋」。';

  @override
  String get protocol_directSwitchFailed =>
      '閘道器在等待時限內還沒改連這台 PTU（已暫時綁定它）。連上後畫面會自動更新；也可確認這台 PTU 已上電並靠近，或改選其他 PTU。';

  @override
  String get protocol_directThresholdNotSaved => '門檻未寫入閘道器（回讀的值不同），請重試。';

  @override
  String get protocol_directUnsupported => '此韌體尚未支援直連門檻與綁定，請先更新韌體（1.7.20 起）。';

  @override
  String get protocol_disconnected => '與閘道器的連線已中斷，請靠近後重新連線。';

  @override
  String get protocol_expired => '指令已逾期（手機時間與閘道器差異過大或傳送延遲），請重試';

  @override
  String get protocol_fleetUnconfirmed =>
      '資料已上傳，但閘道器沒有回報「已加入監控」（APP 已自動補送一次），開通尚未完成。請靠近閘道器後按「開始資料驗證」重試；若仍不行，請按「請後台協助」。';

  @override
  String get protocol_gatewayBusy => '閘道器正在準備或處理其他操作，請稍後重試。';

  @override
  String get protocol_gatewayFailedNoReason => '閘道器回報失敗（未提供原因）。';

  @override
  String get protocol_gatewayFailedSeeDetails => '閘道器回報失敗，請查看詳細資訊。';

  @override
  String protocol_gatewayFailedWithCode(String code) {
    return '閘道器回報失敗：$code';
  }

  @override
  String get protocol_gatewayFull => '本機已滿，請連另一台閘道器。';

  @override
  String protocol_gatewayNotFound(String where, String backend) {
    return '後端找不到此閘道器$where。閘道器的資料可能上傳到其他後端環境（例如正式站），而 APP 目前連的是 $backend。';
  }

  @override
  String protocol_gatewayNotFoundCause(
    String where,
    String backend,
    String cause,
  ) {
    return '後端找不到此閘道器$where（APP 目前連的是 $backend）。$cause';
  }

  @override
  String get protocol_gatewayServiceNotReady => '閘道器藍牙服務尚未就緒，請稍後再試';

  @override
  String protocol_httpRejected(int status) {
    return '後端拒絕此請求（HTTP $status）。';
  }

  @override
  String protocol_httpServerError(int status) {
    return '後端內部錯誤（HTTP $status），請查看後端紀錄後重試。';
  }

  @override
  String get protocol_httpsRequired => '正式環境需要有效的 HTTPS 網址。';

  @override
  String get protocol_identifyDurationUnsupported =>
      '這台舊版閘道器不支援所選辨識秒數。支援 PTU 辨識的舊版僅可用 1–30 秒，更早版本固定 6 秒；其他秒數（含 0 秒關燈）請更新閘道器韌體。';

  @override
  String get protocol_identifyNoPtu =>
      '閘道器尚未連上 PTU，無法讓 PTU 閃燈。請確認同樁 PTU 已上電並靠近後重試。';

  @override
  String get protocol_identifyUnsupported =>
      '此韌體尚未支援辨識燈號，請先更新韌體。連線時的呼吸燈仍可協助辨識。';

  @override
  String get protocol_identityArchived =>
      '這台閘道器之前在後台被移除（封存），後台不會記錄它的心跳。請按下方「重新加入」，恢復記錄後會繼續確認上線。';

  @override
  String get protocol_incomplete => '仍有 PTU 未連線或資料未到達，請查看各台狀態後重試。';

  @override
  String get protocol_invalidIdentifySeconds =>
      '辨識秒數必須是 0（關燈）或 2–10 的整數；1 秒會讓 PTU 燈恆亮，因此不提供。';

  @override
  String get protocol_locationOff => '此版本 Android 搜尋藍牙需要定位服務，請開啟手機定位後重新搜尋。';

  @override
  String get protocol_monitorUnconfirmed =>
      '30 秒內未確認閘道器已恢復監控，可按「重新連線並繼續」重試，或「略過」直接驗證資料。';

  @override
  String protocol_networkUnreachable(String backend) {
    return '無法連到 $backend。請確認手機與後端電腦在同一個 Wi-Fi 網段、電腦防火牆允許該連接埠，以及後端網址是否正確。';
  }

  @override
  String get protocol_newSiteRequired => '請輸入與目前站點不同的新站點 ID。';

  @override
  String get protocol_noDevices => '未找到 PTU。請確認已上電並靠近閘道器後重掃。';

  @override
  String protocol_notFoundWhere(int site, int gateway) {
    return '（站 $site / 閘道器 $gateway）';
  }

  @override
  String get protocol_otherFailure => '操作未完成，請確認裝置狀態後重試。';

  @override
  String get protocol_otpInvalid => '一次性密碼錯誤';

  @override
  String get protocol_otpLocked => '一次性密碼已鎖定，請稍後再試';

  @override
  String get protocol_otpRequired => '此閘道器已啟用一次性密碼，請聯絡管理員。';

  @override
  String get protocol_otpReused => '一次性密碼已用過';

  @override
  String get protocol_permission => '需要藍牙權限，請至系統設定允許後重試。';

  @override
  String get protocol_phoneLinkLost => '手機與閘道器的藍牙連線中斷，請靠近閘道器後按「重新連線並繼續」';

  @override
  String get protocol_ptuConnectFailed => 'PTU 連線失敗，請確認 PTU 電源與距離';

  @override
  String get protocol_ptuIdentityMismatch =>
      '後台資料的 PTU 身分與本次選擇不符，或缺少 MAC，尚未完成驗證。請返回確認本樁 PTU；若仍不符，請後台協助。';

  @override
  String get protocol_ptuNoResponse => 'PTU 沒有回應';

  @override
  String get protocol_reconnectFailed => '重新連線失敗，請靠近閘道器後重試，或回到找閘道器。';

  @override
  String get protocol_replacePending => '後台已登記為新機，但寫入裝置失敗。請重新執行配置，系統會沿用取代設定。';

  @override
  String get protocol_replaceUnsupported => '後端版本不支援取代舊機，請改用下一個編號。裝置設定未變更。';

  @override
  String protocol_targetMismatch(String gatewayTarget, String appTarget) {
    return '閘道器目前把資料送到$gatewayTarget，但手機連的是$appTarget，資料到不了手機連的這個後端，所以直接停止驗證（不必空等）。\n請在「連線狀態」按「同步」，或點右上角的環境按鈕重新選一次，讓閘道器和手機連同一個地方後再驗證。';
  }

  @override
  String protocol_targetReadback(String actual, String wanted) {
    return '閘道器重新連上後回報的資料上傳目的地是$actual，不是要求的$wanted。設定可能沒有生效，請在「連線狀態」按重新讀取確認，或再同步一次。';
  }

  @override
  String get protocol_targetReconnect =>
      '閘道器已收到切換指令並重新開機，但 45 秒內未能重新連上藍牙。請靠近閘道器，按「結束並重新選擇閘道器」重新連線後看「連線狀態」。';

  @override
  String protocol_testModeStuck(String button) {
    return '閘道器重新開機後仍在測試模式，請再按一次「$button」；若仍不行，請按「請後台協助」。';
  }

  @override
  String get protocol_timeNotSynced => '閘道器時間尚未同步。若無可用網路，請先以 USB 更新韌體。';

  @override
  String get protocol_timeout => '等待超時，請確認裝置與網路後重試。';

  @override
  String protocol_unexpected(String detail) {
    return 'APP 發生未預期錯誤：$detail';
  }

  @override
  String protocol_uploadPaused(String button) {
    return '閘道器仍回報資料上傳暫停，請再按一次「$button」；若仍不行，請按「請後台協助」。';
  }

  @override
  String get protocol_wifiPasswordNeeded =>
      '閘道器目前沒有連上這個 Wi-Fi，無法沿用。請輸入 Wi-Fi 密碼後再按「儲存並繼續」。';

  @override
  String get protocol_writeFailed => '寫入 PTU 失敗（閘道器未能送出辨識指令），請確認 PTU 電源與距離後重試。';

  @override
  String ptuRssi_cached(String rssi) {
    return '快取 $rssi dBm';
  }

  @override
  String ptuRssi_last(String rssi) {
    return '上次 $rssi dBm';
  }

  @override
  String ptuRssi_scan(String rssi) {
    return '掃描 $rssi dBm';
  }

  @override
  String get ptuSelectionTile_blocked => '已屬於其他閘道器';

  @override
  String get ptuSelectionTile_connected => '已連線';

  @override
  String get ptuSelectionTile_connectedHere => '已連線至此閘道器';

  @override
  String get ptuSelectionTile_detailTitle => '詳細（最近一次失敗）';

  @override
  String ptuSelectionTile_infoTooltip(String title) {
    return '$title 裝置資訊';
  }

  @override
  String ptuSelectionTile_mac(String mac) {
    return 'MAC：$mac';
  }

  @override
  String ptuSelectionTile_name(String name) {
    return '名稱：$name';
  }

  @override
  String get ptuSelectionTile_noReading => '尚無讀值';

  @override
  String get ptuSelectionTile_notConnected => '未連線';

  @override
  String get ptuSelectionTile_peripheralNotConnected => '周邊未連線';

  @override
  String ptuSelectionTile_readingState(String text) {
    return '讀值狀態：$text';
  }

  @override
  String get ptuSelectionTile_reset => '重置並納入';

  @override
  String ptuSelectionTile_selectSemantic(String title, String mac) {
    return '選擇 $title，$mac';
  }

  @override
  String ptuSelectionTile_signal(String value) {
    return '訊號：$value';
  }

  @override
  String get ptuSelectionTile_snapshotNote => '此處為開啟時的讀值；動態數值請看清單。';

  @override
  String ptuSelectionTile_status(String text) {
    return '狀態：$text';
  }

  @override
  String get ptuSelectionTile_unassigned => '未指派 PTU';

  @override
  String get recentDataApi_authRefused => '後台拒絕此 APP 的登入憑證，請聯絡管理員更新 APP';

  @override
  String recentDataApi_errorText(String reason) {
    return '連不上後台（$reason）';
  }

  @override
  String recentDataApi_minutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes 分鐘',
    );
    return '$_temp0';
  }

  @override
  String recentDataApi_seconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds 秒',
    );
    return '$_temp0';
  }

  @override
  String recentDataApi_secondsAgo(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds 秒前',
    );
    return '$_temp0';
  }

  @override
  String recentDataApi_secondsDecimal(String seconds) {
    return '$seconds 秒';
  }

  @override
  String recentDataApi_summary(int count, String ago) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最近一筆 $ago・共 $count 筆',
    );
    return '$_temp0';
  }

  @override
  String get recentDataApi_timeUnknown => '時間不明';

  @override
  String recentDataPage_ageDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n 天');
    return '$_temp0';
  }

  @override
  String recentDataPage_ageHours(int n) {
    return '$n 小時';
  }

  @override
  String recentDataPage_ageMinutes(int n) {
    return '$n 分鐘';
  }

  @override
  String recentDataPage_ageSeconds(int n) {
    return '$n 秒';
  }

  @override
  String recentDataPage_ago(String age) {
    return '$age前';
  }

  @override
  String get recentDataPage_batteryVoltage => 'Battery Voltage';

  @override
  String get recentDataPage_chargingCurrent => 'Charging Current';

  @override
  String get recentDataPage_current => '電流';

  @override
  String get recentDataPage_dataTime => '資料時間';

  @override
  String recentDataPage_deviceError(int code) {
    return '裝置異常（錯誤碼 $code）';
  }

  @override
  String get recentDataPage_efficiency => '效率';

  @override
  String get recentDataPage_empty => '後台尚未收到這台閘道器的資料，請稍等一下再重新整理';

  @override
  String recentDataPage_emptyInterval(String interval) {
    return '後台尚未收到這台閘道器的資料；閘道器約每 $interval上傳一筆，請稍後再重新整理';
  }

  @override
  String get recentDataPage_errorChargeComplete => '充電完成';

  @override
  String get recentDataPage_errorClearComplete => '重新啟動充電';

  @override
  String get recentDataPage_errorCode => '錯誤碼';

  @override
  String get recentDataPage_errorNone => '無錯誤';

  @override
  String get recentDataPage_errorPruCharged => 'PRU 已充滿';

  @override
  String get recentDataPage_errorPruOc => 'PRU 過流';

  @override
  String get recentDataPage_errorPruOt => 'PRU 過溫';

  @override
  String get recentDataPage_errorPruOv => 'PRU 過壓';

  @override
  String get recentDataPage_errorPtuComm => 'PTU 通訊錯誤';

  @override
  String get recentDataPage_errorPtuLpStuck => 'PTU Low Power 卡住';

  @override
  String get recentDataPage_errorPtuOcBus => 'PTU IBUS 電流過流';

  @override
  String get recentDataPage_errorPtuOcI1 => 'PTU I1 電流過流';

  @override
  String get recentDataPage_errorPtuOcI3 => 'PTU I3 電流過流';

  @override
  String get recentDataPage_errorPtuOcIn => 'PTU Iin 電流過流';

  @override
  String get recentDataPage_errorPtuOtDcdc => 'PTU DCDC 過溫';

  @override
  String get recentDataPage_errorPtuOtIc => 'PTU IC 過溫';

  @override
  String get recentDataPage_errorPtuOtPa => 'PTU PA 過溫';

  @override
  String get recentDataPage_errorPtuPhase => 'PTU I1/I3 相位異常';

  @override
  String get recentDataPage_errorPtuPtStuck => 'PTU Power Transfer 卡住';

  @override
  String get recentDataPage_errorPtuTimeset => 'PTU Timeset 失敗';

  @override
  String get recentDataPage_errorUnknown => '未知錯誤';

  @override
  String get recentDataPage_fault => 'PTU 回報故障';

  @override
  String get recentDataPage_faultCode => 'Fault Code';

  @override
  String get recentDataPage_label => '查看最近資料';

  @override
  String recentDataPage_latestRest(String state, String clock, String ago) {
    return '$state・$clock（$ago）';
  }

  @override
  String get recentDataPage_latestUnknown => '最近一筆的時間不明';

  @override
  String recentDataPage_noNewData(String age) {
    return '最近 $age沒有新資料';
  }

  @override
  String get recentDataPage_ok => '上傳正常';

  @override
  String get recentDataPage_overallEfficiency => '整體效率';

  @override
  String get recentDataPage_pruCurrent => '電流';

  @override
  String get recentDataPage_pruOutputPower => 'PRU 輸出功率';

  @override
  String get recentDataPage_pruTemperature => '接收端溫度';

  @override
  String get recentDataPage_ptuInputPower => 'PTU 輸入功率';

  @override
  String get recentDataPage_ptuTemperature => '發射端溫度';

  @override
  String get recentDataPage_shortCharging => '充電';

  @override
  String get recentDataPage_shortConfiguration => '設定';

  @override
  String get recentDataPage_shortCooling => '冷卻';

  @override
  String get recentDataPage_shortExceeded => '超範圍';

  @override
  String get recentDataPage_shortFault => '故障';

  @override
  String get recentDataPage_shortIdle => '待機';

  @override
  String get recentDataPage_shortLowPower => '低功率';

  @override
  String get recentDataPage_shortPowerSave => '省電';

  @override
  String get recentDataPage_stateConfiguration => '設定中';

  @override
  String get recentDataPage_stateCooling => '冷卻中';

  @override
  String get recentDataPage_stateExceededRange => 'PRU 超出範圍';

  @override
  String get recentDataPage_stateLabel => '狀態';

  @override
  String get recentDataPage_stateLatchFault => '鎖定故障';

  @override
  String get recentDataPage_stateLocalFault => '本地故障';

  @override
  String get recentDataPage_stateLowPower => '低功率';

  @override
  String get recentDataPage_stateOta => 'OTA 更新中';

  @override
  String get recentDataPage_statePowerSave => '省電';

  @override
  String get recentDataPage_statePowerTransfer => '充電中';

  @override
  String get recentDataPage_systemCharging => 'Charging';

  @override
  String get recentDataPage_systemFault => 'Fault';

  @override
  String get recentDataPage_systemNormal => 'Normal';

  @override
  String get recentDataPage_systemStatus => 'System Status / Fault';

  @override
  String get recentDataPage_systemWarning => 'Warning';

  @override
  String recentDataPage_tableTitleCount(String title, int count) {
    return '$title（$count 筆）';
  }

  @override
  String get recentDataPage_temperature => '溫度';

  @override
  String get recentDataPage_time => '時間';

  @override
  String get recentDataPage_timeUnknown => '時間不明';

  @override
  String get recentDataPage_title => '最近資料';

  @override
  String recentDataPage_trend(int n, String span, String rate) {
    return '最近 $n 筆・跨 $span・平均每秒 $rate 筆';
  }

  @override
  String recentDataPage_trendCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '最近 $n 筆',
    );
    return '$_temp0';
  }

  @override
  String get recentDataPage_vehicleType => '車型';

  @override
  String get recentDataPage_voltage => '電壓';

  @override
  String get recentGateways_archivedLabel => '已封存（後台已移除）';

  @override
  String get recentGateways_configuredLabel => '已配置';

  @override
  String recentGateways_queryFailed(String detail) {
    return '後端狀態未知・查詢失敗（$detail）';
  }

  @override
  String get recentGateways_queryTimeout => '後端狀態未知・查詢逾時（8 秒）';

  @override
  String get recentGateways_reportedOffline => '後端回報離線';

  @override
  String get recentGateways_reportedOnline => '後端回報在線上';

  @override
  String get recentGateways_shortArchived => '後端已封存';

  @override
  String get recentGateways_shortNoRecord => '後端無紀錄';

  @override
  String get recentGateways_shortOffline => '後端離線';

  @override
  String get recentGateways_shortOnline => '後端在線';

  @override
  String get recentGateways_shortUnknown => '後端未知';

  @override
  String get recentGateways_unknown => '後端狀態未知';

  @override
  String get recentGateways_unknownConflict => '後端狀態未知・後台標示身分衝突';

  @override
  String recentGateways_unknownDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '後端狀態未知・後台有 $count 筆相同 MAC 的紀錄',
    );
    return '$_temp0';
  }

  @override
  String get recentGateways_unknownNoHeartbeat => '後端狀態未知・後台沒有這個 MAC 的心跳紀錄';

  @override
  String get recentGateways_unknownUnverified => '後端狀態未知・連線後確認身分';

  @override
  String get rescueCode_appUnexpected => 'APP 發生未預期錯誤';

  @override
  String get rescueCode_backendAuth => '後台登入失效';

  @override
  String get rescueCode_backendDown => 'APP 連不到後台';

  @override
  String get rescueCode_bleConnectFail => '手機連不上閘道器（藍牙錯誤）';

  @override
  String get rescueCode_bleLinkDrop => '手機和閘道器的藍牙斷了';

  @override
  String get rescueCode_bleReconnectFail => '重新連線失敗';

  @override
  String get rescueCode_cmdTimeout => '閘道器沒有回應';

  @override
  String get rescueCode_directPick => '直連選台失敗';

  @override
  String get rescueCode_fwTooOld => '韌體太舊，不支援這個功能';

  @override
  String get rescueCode_gwAuthRefused => '閘道器拒絕指令（一次性密碼或時間未同步）';

  @override
  String get rescueCode_gwBusy => '閘道器忙碌（已自動重試 20 秒）';

  @override
  String get rescueCode_gwFull => '這台閘道器已滿';

  @override
  String get rescueCode_gwLowMemory => '閘道器記憶體不足';

  @override
  String get rescueCode_gwNotFound => '手機找不到閘道器';

  @override
  String get rescueCode_gwNotInBackend => '後台沒有這台閘道器的資料';

  @override
  String get rescueCode_gwRebooted => '閘道器剛重新啟動';

  @override
  String get rescueCode_gwRejected => '閘道器回報失敗';

  @override
  String get rescueCode_helpOnly => '畫面沒有錯誤，現場主動求助';

  @override
  String get rescueCode_identityConflict => '站號已被別台使用';

  @override
  String get rescueCode_identityReplace => '取代舊機沒完成';

  @override
  String get rescueCode_monitorUnconfirmed => '還沒確認閘道器已恢復監控';

  @override
  String get rescueCode_phoneBtOff => '手機藍牙沒開';

  @override
  String get rescueCode_phonePermission => 'APP 沒有藍牙／定位權限';

  @override
  String get rescueCode_ptuConnectFail => '閘道器連不上 PTU';

  @override
  String get rescueCode_ptuNoResponse => 'PTU 沒回應';

  @override
  String get rescueCode_ptuNoneFound => '掃不到 PTU';

  @override
  String get rescueCode_ptuResidual => '有 PTU 帶舊編號，或屬於其他閘道器';

  @override
  String get rescueCode_ptuWrongDevice => '編號寫到別台，或回讀不符';

  @override
  String get rescueCode_stepStuck => '同一步停太久';

  @override
  String get rescueCode_uploadNotStarted => 'Wi-Fi 已連上，但資料還沒送到後台';

  @override
  String get rescueCode_uploadTarget => '閘道器資料送錯地方（跟手機連的後台不同）';

  @override
  String get rescueCode_verifyIncomplete => '有 PTU 資料沒進來';

  @override
  String get rescueCode_wifiNotFound => '閘道器找不到這個 Wi-Fi';

  @override
  String get rescueCode_wifiPassword => 'Wi-Fi 密碼可能錯';

  @override
  String get rescueCode_wifiUnknown => 'Wi-Fi 沒連上（原因不明）';

  @override
  String get rescueCode_wifiWeak => 'Wi-Fi 訊號弱或基地台拒絕';

  @override
  String get settings_appearance => '外觀';

  @override
  String get settings_language => '語言';

  @override
  String get settings_more => '更多';

  @override
  String get settings_themeDark => '深色';

  @override
  String get settings_themeLight => '淺色';

  @override
  String get settings_themeSystem => '跟隨系統';

  @override
  String get starAllowList_beforeFailed =>
      'PTU 綁定名單未寫入，繼續配置。若附近有編號相同的其他 PTU 佔住連線，部分 PTU 可能指派失敗；資料驗證完成後會再寫一次。';

  @override
  String get starAllowList_failed =>
      'PTU 綁定名單未寫入，請重試。未寫入前閘道器只看編號，附近帶相同編號的其他 PTU 仍可能被連走。';

  @override
  String starAllowList_foreignIgnored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '附近有 $count 台編號相同的其他 PTU，已被閘道器忽略（不會連線）。',
    );
    return '$_temp0';
  }

  @override
  String get starAllowList_reselectHint => '若其中有這台閘道器要接的 PTU，請勾選它後重新配置。';

  @override
  String get starAllowList_retryButton => '重試寫入綁定名單';

  @override
  String get starAllowList_sentenceSeparator => '';

  @override
  String get starAllowList_switchFailed => '切回星狀後 PTU 綁定名單未寫入，資料驗證完成後會再寫一次。';

  @override
  String starAllowList_unlistedDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 台已連線的 PTU 不在這台閘道器的綁定名單，閘道器會自動斷開。',
    );
    return '$_temp0';
  }

  @override
  String get starAllowList_writing => '正在寫入 PTU 綁定名單';

  @override
  String starAllowList_written(String ids) {
    return 'PTU 綁定名單已寫入：$ids（閘道器只連這幾台，附近編號相同的其他 PTU 不會被連走）';
  }

  @override
  String get stationChangeProgress_applying =>
      '套用站號後，閘道器會重新啟動。請保持靠近，APP 會自動重新連線。';

  @override
  String get stationChangeProgress_confirming =>
      '已重新連線，正在確認新站號與 Wi-Fi。確認完成後會自動繼續。';

  @override
  String get stationChangeProgress_restarting =>
      '這是套用站號時的正常重啟，藍牙會短暫中斷。請保持靠近，APP 會自動重新連線。';

  @override
  String stationChangeProgress_target(int site, int gateway) {
    return '站點 $site · 閘道器 $gateway';
  }

  @override
  String get stationChange_itemApply => '套用站點設定';

  @override
  String get stationChange_itemConfirm => '確認站號與 Wi-Fi';

  @override
  String get stationChange_itemRestart => '重新啟動並連線';

  @override
  String get stationChange_noteReconnecting => '正在自動重新連線';

  @override
  String get stationChange_noteWaitBoot => '等待閘道器啟動';

  @override
  String get stationChange_titleApplying => '正在套用站號，請稍候';

  @override
  String get stationChange_titleConfirming => '正在確認站號與 Wi-Fi';

  @override
  String get stationChange_titleReconnecting => '正在重新連線閘道器';

  @override
  String get stationChange_titleRestarting => '閘道器重新啟動中，請稍候';

  @override
  String uiProgressChecklist_doneAt(String time) {
    return '$time 完成';
  }

  @override
  String get uiProgressChecklist_running => '進行中…';

  @override
  String uiProgressChecklist_runningNote(String note) {
    return '進行中… $note';
  }

  @override
  String get verifyDiagnosis_causeOtherBackend => '閘道器可能上傳到其他後端環境（例如正式站）。';

  @override
  String get verifyDiagnosis_causeProductionUnknown =>
      '閘道器可能尚未連上正式站的 MQTT，或上傳到其他後端環境（例如本地測試站）。';

  @override
  String verifyDiagnosis_consecutive(int count) {
    return '連續通過 $count / 3 次。';
  }

  @override
  String get verifyDiagnosis_installNoDetail => '後端安裝驗證未通過（未回傳此 PTU 明細）';

  @override
  String verifyDiagnosis_localHint(String port, String host) {
    return '請確認：閘道器的 MQTT 已連線（按「重新讀取」查看）、電腦防火牆已開放 TCP $port、本地 MQTT broker 已啟動，且 broker 憑證包含電腦目前的 IP $host（電腦 IP 若因 DHCP 變更，需重新產生憑證並把閘道器切到新 IP）。';
  }

  @override
  String get verifyDiagnosis_mqttConnected =>
      '閘道器最近回報 MQTT 已連線，可能剛連上、心跳尚未送達，可稍候再驗證。';

  @override
  String get verifyDiagnosis_mqttDisconnected => '閘道器最近回報 MQTT 未連線。';

  @override
  String verifyDiagnosis_noData(
    String backend,
    int site,
    int gateway,
    String cause,
  ) {
    return '閘道器的資料沒有進入目前連線的$backend：fleet-status 沒有站 $site / 閘道器 $gateway 的心跳，/api/latest 也沒有任何資料。$cause';
  }

  @override
  String verifyDiagnosis_noFleet(int site, int gateway) {
    return 'fleet-status 沒有站 $site / 閘道器 $gateway 的心跳紀錄。';
  }

  @override
  String get verifyDiagnosis_none => '無';

  @override
  String verifyDiagnosis_offline(String last) {
    return '閘道器在後端顯示離線（最後心跳 $last）。';
  }

  @override
  String verifyDiagnosis_productionHint(String port) {
    return '請確認現場網路可連到正式站（TCP $port），並按「重新讀取」查看 MQTT 是否已連線。';
  }

  @override
  String verifyDiagnosis_ptuLine(int id, String reasons) {
    return 'PTU #$id：$reasons';
  }

  @override
  String verifyDiagnosis_reasonBackendLate(String seconds) {
    return '後端資料延遲 $seconds 秒';
  }

  @override
  String get verifyDiagnosis_reasonBadTime => '資料時間無法解析';

  @override
  String verifyDiagnosis_reasonLag(int seconds) {
    return '延遲 $seconds 秒';
  }

  @override
  String get verifyDiagnosis_reasonLagUnknown => '延遲未知';

  @override
  String get verifyDiagnosis_reasonNoBackendData => '後端無資料';

  @override
  String get verifyDiagnosis_reasonNotInLatest => '最新資料（/api/latest）無此 PTU';

  @override
  String verifyDiagnosis_reasonNotUpdated(String ts) {
    return '資料未更新（最後 $ts）';
  }

  @override
  String get verifyDiagnosis_reasonOffline => '離線';

  @override
  String get verifyDiagnosis_roundOk => '本輪正常';

  @override
  String verifyDiagnosis_sameTarget(String target, String state, String hint) {
    return '閘道器已確認上傳到$target（與 APP 所連後端一致），但後端尚未收到它的心跳，表示閘道器還沒連上該 MQTT broker。$state\n$hint';
  }

  @override
  String get verifyDiagnosis_uploadPaused => '閘道器資料上傳為暫停狀態（已嘗試恢復）。';

  @override
  String verifyLivePanel_announceEvery(String text) {
    return '每台$text';
  }

  @override
  String get verifyLivePanel_announceNew => '收到新資料';

  @override
  String verifyLivePanel_announceNotCounted(String reasons) {
    return '資料未計入：$reasons';
  }

  @override
  String verifyLivePanel_announceNth(int count) {
    return '收到第 $count 筆';
  }

  @override
  String verifyLivePanel_announcePtu(String who, String text) {
    return '$who $text';
  }

  @override
  String get verifyLivePanel_announceSeparator => '；';

  @override
  String get verifyLivePanel_countFull => '正常（已滿 3 筆）';

  @override
  String verifyLivePanel_countNotCounted(int count) {
    return '未計入（維持 $count/3）';
  }

  @override
  String verifyLivePanel_countNth(int count) {
    return '第 $count 筆';
  }

  @override
  String verifyLivePanel_countRestart(int count) {
    return '重新計數：第 $count/3 筆';
  }

  @override
  String get verifyLivePanel_flowBackOffice => '後台';

  @override
  String get verifyLivePanel_flowGateway => '閘道器';

  @override
  String verifyLivePanel_footer(String pace, int seconds) {
    return '$pace・剩餘 $seconds 秒';
  }

  @override
  String get verifyLivePanel_goal => '收到 3 筆正常資料就算完成';

  @override
  String verifyLivePanel_pace(int seconds) {
    return '每 $seconds 秒確認新資料，收到 3 筆正常資料即完成';
  }

  @override
  String verifyLivePanel_paceInterval(String interval, String total) {
    return '約每 $interval收一筆，通常 $total內完成';
  }

  @override
  String get verifyLivePanel_passed => '資料正常上傳';

  @override
  String verifyLivePanel_reason(String reasons) {
    return '原因：$reasons';
  }

  @override
  String get verifyLivePanel_reasonDefault => '未通過檢查';

  @override
  String get verifyLivePanel_rowBad => '異常';

  @override
  String get verifyLivePanel_rowOk => '正常';

  @override
  String verifyLivePanel_uncountedDetails(int count) {
    return '查看未計入資料（$count 筆）';
  }

  @override
  String get verifyLivePanel_waitingFirst => '等待第一筆資料…';

  @override
  String get verifyLivePanel_waitingNormal => '等待下一筆正常資料…';

  @override
  String get wifiCredentialsForm_forgetButton => '忘記已存密碼';

  @override
  String get wifiCredentialsForm_forgetFailed => '舊密碼尚未刪除，請重試；本次不會記住新密碼。';

  @override
  String get wifiCredentialsForm_forgotten => '已忘記這個 Wi-Fi 的已存密碼。';

  @override
  String get wifiCredentialsForm_gatewayWifiLabel => '閘道器要使用的 Wi-Fi';

  @override
  String get wifiCredentialsForm_hidePassword => '隱藏密碼';

  @override
  String get wifiCredentialsForm_intro => '帶入手機目前的 Wi-Fi 名稱後，輸入密碼或使用已記住的密碼。';

  @override
  String get wifiCredentialsForm_locationOff => '請開啟手機定位服務後重試，或手動輸入 Wi-Fi 名稱。';

  @override
  String get wifiCredentialsForm_manualButton => '手動輸入其他網路';

  @override
  String get wifiCredentialsForm_noneSelected => '尚未選擇 Wi-Fi';

  @override
  String get wifiCredentialsForm_notRemembered => '連線尚未完成，未記住本次密碼。';

  @override
  String get wifiCredentialsForm_openAppSettings => '開啟 App 權限設定';

  @override
  String get wifiCredentialsForm_passwordHint => '輸入 Wi-Fi 密碼；無密碼的網路可直接儲存';

  @override
  String get wifiCredentialsForm_passwordLabel => 'Wi-Fi 密碼';

  @override
  String get wifiCredentialsForm_permissionNeeded =>
      '讀取 Wi-Fi 名稱需要定位權限及精確位置。請在 App 設定允許後重試，也可手動輸入名稱。';

  @override
  String get wifiCredentialsForm_phoneWifiFilled =>
      '已帶入手機的 Wi-Fi 名稱，請確認此網路支援 2.4 GHz，並確認下方密碼。';

  @override
  String get wifiCredentialsForm_phoneWifiUnreadable =>
      '讀不到手機目前的 Wi-Fi。請先在手機的 Wi-Fi 設定連上現場網路，再回來重試，或手動輸入名稱。';

  @override
  String get wifiCredentialsForm_readSavedFailed => '暫時無法讀取已存密碼，請手動輸入。';

  @override
  String get wifiCredentialsForm_readSavedTimeout => '讀取已存密碼逾時，請手動輸入。';

  @override
  String get wifiCredentialsForm_readWifiFailed => '暫時無法讀取 Wi-Fi 名稱，請重試或手動輸入。';

  @override
  String get wifiCredentialsForm_readWifiTimeout => '讀取 Wi-Fi 逾時，請重試或手動輸入名稱。';

  @override
  String get wifiCredentialsForm_rememberFailed => 'Wi-Fi 已連線，但無法記住密碼；下次請重新輸入。';

  @override
  String get wifiCredentialsForm_rememberPassword => '記住密碼（僅限這支手機）';

  @override
  String wifiCredentialsForm_saveHint(String label) {
    return '確認 Wi-Fi 名稱與密碼後，點「$label」';
  }

  @override
  String get wifiCredentialsForm_savedFilled => '已帶入這支手機記住的密碼，可按眼睛查看或手動修改。';

  @override
  String get wifiCredentialsForm_showPassword => '顯示密碼';

  @override
  String get wifiCredentialsForm_ssidHint => '輸入 Wi-Fi 名稱';

  @override
  String get wifiCredentialsForm_ssidLabel => 'Wi-Fi 名稱（SSID）';

  @override
  String get wifiCredentialsForm_unsupported => '此平台無法讀取手機 Wi-Fi，請手動輸入名稱。';

  @override
  String get wifiCredentialsForm_usePhoneButton => '使用手機目前的 Wi-Fi';

  @override
  String get wifiCredentialsForm_usePhoneHint => '帶入手機目前的 Wi-Fi';

  @override
  String get wifiCredentialsForm_wifiOff =>
      '請先在手機的 Wi-Fi 設定連上現場網路，再回來重試，或手動輸入名稱。';
}
