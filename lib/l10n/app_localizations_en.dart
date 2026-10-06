// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get androidAppUpdateDialog_cancelDownload => 'Cancel download';

  @override
  String get androidAppUpdateDialog_continueInstall => 'Continue install';

  @override
  String androidAppUpdateDialog_currentVersion(String name, String code) {
    return 'Current version: $name ($code)';
  }

  @override
  String get androidAppUpdateDialog_defaultNotes =>
      'Improves the app experience.';

  @override
  String get androidAppUpdateDialog_downloadFailed =>
      'Download didn\'t finish. Check the network and retry.';

  @override
  String androidAppUpdateDialog_downloading(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String get androidAppUpdateDialog_installFailed =>
      'Can\'t open the system installer. Return to the app and retry.';

  @override
  String get androidAppUpdateDialog_installerOpened =>
      'Confirm the install on the system screen. If you cancelled, tap [Continue install] again.';

  @override
  String get androidAppUpdateDialog_integrityFailed =>
      'Update file check failed. Download it again.';

  @override
  String androidAppUpdateDialog_latestVersion(String name, String code) {
    return 'Latest version: $name ($code)';
  }

  @override
  String get androidAppUpdateDialog_permissionRequired =>
      'Allow installing apps from this source, then come back and tap [Continue install].';

  @override
  String get androidAppUpdateDialog_prepareFailed =>
      'Can\'t prepare the update file. Check phone storage and retry.';

  @override
  String get androidAppUpdateDialog_redownload => 'Download again';

  @override
  String get androidAppUpdateDialog_startFailed =>
      'Can\'t start the update install. Contact an administrator.';

  @override
  String get androidAppUpdateDialog_title => 'New app version available';

  @override
  String get androidAppUpdateDialog_updateNow => 'Update now';

  @override
  String get androidAppUpdateDialog_verificationFailed =>
      'The update\'s version or signature check failed. Contact an administrator.';

  @override
  String get androidAppUpdateDialog_verifying => 'Verifying the update file…';

  @override
  String get appInfo_title => 'GIOS Device Assistant';

  @override
  String get assign_assigning => 'Assigning';

  @override
  String assign_assigningId(int id) {
    return 'Assigning #$id';
  }

  @override
  String assign_assigningResult(int id) {
    return 'Assigning #$id';
  }

  @override
  String get assign_autoHint =>
      'Handled automatically. Failures are retried; nothing to do.';

  @override
  String get assign_busy => 'Gateway busy, retrying shortly';

  @override
  String assign_doneId(int id) {
    return 'Done · #$id';
  }

  @override
  String assign_doneResult(String result) {
    return 'Done · $result';
  }

  @override
  String get assign_failed => 'Failed, needs action';

  @override
  String assign_failedHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Check PTU power and distance, then tap [Retry these $count] below.',
      one:
          'Check the PTU\'s power and distance, then tap [Retry this one] below.',
    );
    return '$_temp0';
  }

  @override
  String assign_failedReason(String reason) {
    return 'Failed, needs action: $reason';
  }

  @override
  String assign_linkRetry(int retry, int retries) {
    return 'Bluetooth link failed, retrying $retry/$retries';
  }

  @override
  String get assign_notAssignedLink => 'Not assigned (phone lost the gateway)';

  @override
  String assign_progressDone(int done, int total) {
    return '$done/$total done';
  }

  @override
  String assign_progressFailed(int count) {
    return '$count failed, needs action';
  }

  @override
  String assign_progressRetrying(int count) {
    return '$count retrying automatically';
  }

  @override
  String get assign_progressSeparator => ', ';

  @override
  String assign_retry(int retry, int retries) {
    return 'Not done, retrying $retry/$retries';
  }

  @override
  String assign_retryAttempt(int retry, int retries) {
    return ' ($retry/$retries)';
  }

  @override
  String assign_retryingMany(String names, int count) {
    return '$names and others: $count retrying automatically';
  }

  @override
  String assign_retryingOne(String name, String attempt) {
    return '$name retrying automatically$attempt';
  }

  @override
  String assign_retryingTwo(String names) {
    return '$names retrying automatically';
  }

  @override
  String get assign_waiting => 'Waiting';

  @override
  String get autoChecklist_linkLost => 'Bluetooth lost; can\'t confirm';

  @override
  String get autoChecklist_oldFirmwareLater =>
      'This firmware can\'t report; checked in the final data check';

  @override
  String get autoChecklist_targetElsewhere =>
      'Data goes to another back office; follow the hint below';

  @override
  String get autoChecklist_testMode =>
      'Gateway in test mode; switch back to normal mode first';

  @override
  String get autoChecklist_uploadHeld =>
      'Connected; data upload starts after setup';

  @override
  String get autoChecklist_uploadNotStarted =>
      'Data upload not started; follow the hint below';

  @override
  String get autoChecklist_uploadPaused =>
      'Data upload paused; tap [Resume upload] below';

  @override
  String get autoChecklist_uploading => 'Uploading data';

  @override
  String get autoChecklist_wifiConnected => 'Connected';

  @override
  String get autoChecklist_wifiFailed =>
      'Can\'t connect to Wi-Fi; tap [Reset Wi-Fi] below';

  @override
  String get autoChecklist_wifiNotSet =>
      'Wi-Fi not set up; tap [Set up Wi-Fi] below';

  @override
  String backendEnvironment_changeHint(String label) {
    return 'Backend: $label (kept from last time; switch at top right)';
  }

  @override
  String get backendEnvironment_invalidUrl => 'Invalid URL';

  @override
  String get backendEnvironment_labelCustom => 'Other URL';

  @override
  String get backendEnvironment_labelLocal => 'Local test';

  @override
  String get backendEnvironment_labelProduction => 'Production';

  @override
  String get backendEnvironment_localUnavailable =>
      'The release app can\'t use the local test site. Install the local test APK instead.';

  @override
  String get backendEnvironment_localUnavailableLabel =>
      'Local test (not in this build)';

  @override
  String get backendKey_missing =>
      'This build has no back office credential. Rebuild it';

  @override
  String get bleGatewayLink_stageClearing => 'Clearing the old connection';

  @override
  String get bleGatewayLink_stageConnecting => 'Connecting to the gateway';

  @override
  String get bleGatewayLink_stageRescanning => 'Gateway not found, rescanning';

  @override
  String bleGatewayLink_stageRetry(int attempt) {
    return 'Retry #$attempt';
  }

  @override
  String get commissioning_advancedCheck => 'Advanced checks';

  @override
  String get commissioning_appVersion => 'App version';

  @override
  String commissioning_archivedConfirmText(int site, int gateway) {
    return 'Site $site / gateway $gateway was removed (archived) in the back office. Its heartbeats are not recorded, so setup stops at \"Confirm the gateway is online\". Adding it back resumes recording; its history is kept.';
  }

  @override
  String get commissioning_archivedConfirmTitle =>
      'This gateway was removed (archived) in the back office. Add it back?';

  @override
  String get commissioning_archivedRejoinLabel => 'Rejoin and continue';

  @override
  String commissioning_assignFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs failed to assign:',
      one: '1 PTU failed to assign:',
    );
    return '$_temp0';
  }

  @override
  String commissioning_assignFailedRow(String id, String reason) {
    return 'PTU $id: $reason';
  }

  @override
  String commissioning_assignmentLine(
    String site,
    String gateway,
    String hint,
  ) {
    return 'Will be site $site / gateway $gateway$hint';
  }

  @override
  String get commissioning_backToGatewaySearch => 'Back to gateway search';

  @override
  String get commissioning_backToNetworkCheck => 'Back to network check';

  @override
  String get commissioning_backToPtuRescan =>
      'Back to PTU selection and rescan';

  @override
  String get commissioning_backToPtuSelect => 'Back to PTU selection';

  @override
  String commissioning_backToSite(int site) {
    return 'Back to site $site';
  }

  @override
  String get commissioning_backToStationChoice => 'Back to site choice';

  @override
  String get commissioning_backendUrl => 'Backend URL';

  @override
  String get commissioning_boundPtu => 'Bound PTU';

  @override
  String commissioning_busyWaitUpTo(int seconds) {
    return 'Working · up to $seconds s';
  }

  @override
  String get commissioning_cancelAction => 'Cancel';

  @override
  String get commissioning_checkAndStart => 'Check and start';

  @override
  String get commissioning_checkContinueLabel => 'Continue to site';

  @override
  String get commissioning_checkIntro =>
      'Check the gateway is online and sends data to the right place, then choose the site.';

  @override
  String get commissioning_checkPassedTaskTitle =>
      'Network check passed. Review, then tap below to continue';

  @override
  String get commissioning_checkTargetItem => 'Where data goes';

  @override
  String get commissioning_checkUpdate => 'Check for updates';

  @override
  String get commissioning_checkUploadItem => 'Data upload';

  @override
  String get commissioning_checkWifiItem => 'Gateway Wi-Fi';

  @override
  String get commissioning_checkingTaskTitle =>
      'Connecting and checking the network, please wait';

  @override
  String get commissioning_checkingUpdate => 'Checking for updates…';

  @override
  String get commissioning_confirmTargetHint =>
      'Confirm the upload destination';

  @override
  String get commissioning_confirmUploadTitle => 'Confirm data upload';

  @override
  String get commissioning_continueCommissioning => 'Continue setup';

  @override
  String get commissioning_copied => 'Copied; paste to share';

  @override
  String get commissioning_copyReport => 'Copy report';

  @override
  String commissioning_currentMode(String mode) {
    return 'Current mode: $mode';
  }

  @override
  String get commissioning_demoBanner =>
      'Demo mode · no real devices set up, no real data verified';

  @override
  String get commissioning_demoWifiConnected => 'Connected';

  @override
  String get commissioning_demoWifiConnecting => 'Just booted, connecting';

  @override
  String get commissioning_demoWifiDisconnected =>
      'Cannot connect (Wi-Fi out of range)';

  @override
  String get commissioning_demoWifiLabel => 'Simulated gateway Wi-Fi';

  @override
  String get commissioning_detailsTitle => 'Device and connection info';

  @override
  String get commissioning_directPickTaskTitle =>
      'Identify the charger in front of you, then start';

  @override
  String get commissioning_directSettings => 'One-to-one advanced settings';

  @override
  String get commissioning_doneLabelHead => 'Label the enclosure:';

  @override
  String get commissioning_doneLabelHint =>
      'The back office uses this label to find this gateway';

  @override
  String commissioning_doneLabelText(String label) {
    return 'Label the enclosure: $label';
  }

  @override
  String commissioning_doneMode(String mode) {
    return 'Mode: $mode';
  }

  @override
  String get commissioning_doneTitle => 'Setup complete';

  @override
  String get commissioning_doneTitleDemo => 'Demo setup complete';

  @override
  String get commissioning_end => 'End';

  @override
  String commissioning_envSwitched(String env) {
    return 'Switched to $env.';
  }

  @override
  String commissioning_envSwitchedAutoSync(String env) {
    return 'Switched to $env. A gateway connected later is switched too.';
  }

  @override
  String commissioning_envSwitchedManualSync(String env) {
    return 'Switched to $env. After connecting a gateway, tap [Sync] in \"Connection status\".';
  }

  @override
  String get commissioning_finishingTaskTitle =>
      'Finishing setup and confirming data upload';

  @override
  String commissioning_gatewayN(int gateway) {
    return 'Gateway $gateway';
  }

  @override
  String get commissioning_gatewayNumberComputing =>
      'Working out the gateway number…';

  @override
  String commissioning_gatewayReports(String line) {
    return 'Gateway reports: $line';
  }

  @override
  String commissioning_gatewaySwitching(String target) {
    return 'Switching the gateway to $target (about 1 min). Stay near the gateway.';
  }

  @override
  String commissioning_identifyGateway(int seconds) {
    return 'Identify this one · $seconds s';
  }

  @override
  String get commissioning_identifyPile =>
      'Identify this charger (PTU and gateway blink)';

  @override
  String get commissioning_identifyUnsupported =>
      'The blue light breathes while connected; update the firmware for double-blink identify.';

  @override
  String commissioning_identityConflictHint(int site, int gateway) {
    return 'If the old gateway was removed or replaced, tap [Replace old] so this one takes over site $site / gateway $gateway. Otherwise find the other gateway with this number, or use another site.';
  }

  @override
  String get commissioning_identityConflictTitle => 'Identity conflict';

  @override
  String commissioning_lastUploadConfirmed(String time) {
    return 'Last upload confirmed: $time';
  }

  @override
  String get commissioning_liveRssi => 'Live RSSI · every 5 s (order kept)';

  @override
  String get commissioning_localHint =>
      'Phone and PC must be on the same Wi-Fi. If the PC IP changes, edit it above or tap [Auto find].';

  @override
  String get commissioning_loginAndCheck => 'Log in and check data';

  @override
  String commissioning_messageRemaining(String message, int seconds) {
    return '$message ($seconds s left)';
  }

  @override
  String get commissioning_networkCheckTitle => 'Gateway network check';

  @override
  String commissioning_newSiteConfirmText(int site) {
    return 'The back office has no gateway for site $site yet. Check the site ID; continue only if it is a new site.';
  }

  @override
  String get commissioning_newSiteConfirmTitle => 'Is this a new site?';

  @override
  String commissioning_newSiteOk(int site) {
    return 'New site, use $site';
  }

  @override
  String get commissioning_noDataYet => 'No data yet';

  @override
  String get commissioning_noPtuFound =>
      'No PTU found. Make sure the PTU is powered, then rescan';

  @override
  String commissioning_notConnectedList(String list) {
    return 'Not connected: $list';
  }

  @override
  String commissioning_notLoggedIn(String env) {
    return 'Not logged in to $env: the site conflict check is skipped for now; login runs when needed.';
  }

  @override
  String get commissioning_notVerifiedSkipped => 'Not verified (skipped)';

  @override
  String commissioning_numberTakenMac(int taken, String mac) {
    return '(MAC registered for gateway $taken: $mac)';
  }

  @override
  String commissioning_numberTakenNextLabel(int gateway) {
    return 'Use gateway $gateway';
  }

  @override
  String commissioning_numberTakenOnlineText(int taken) {
    return 'Gateway $taken is online and cannot be replaced. If this one replaces it, power off the old one first.';
  }

  @override
  String commissioning_numberTakenOnlyText(int site, int taken) {
    return 'Gateway $taken of site $site is used by another device.';
  }

  @override
  String commissioning_numberTakenReplaceHint(int taken) {
    return 'If this one replaces that old gateway (removed or powered off), tap [Replace old] to keep gateway $taken.';
  }

  @override
  String commissioning_numberTakenReplaceLabel(int taken) {
    return 'Replace old (keep gateway $taken)';
  }

  @override
  String commissioning_numberTakenText(int site, int taken, int gateway) {
    return 'Gateway $taken of site $site is used by another device; using gateway $gateway instead.';
  }

  @override
  String get commissioning_numberTakenTitle => 'Gateway number already in use';

  @override
  String get commissioning_offlineFirst => 'Set up offline, check data later';

  @override
  String get commissioning_offlineNumber =>
      ' (numbered offline; checked again once online)';

  @override
  String get commissioning_offlineNumberNoList =>
      ' (site gateway list unavailable; using 1 for now, check once online)';

  @override
  String get commissioning_oneToMany => 'One-to-many';

  @override
  String get commissioning_oneToOne => 'One-to-one';

  @override
  String get commissioning_onlineAuto =>
      'Confirming online automatically, please wait.';

  @override
  String get commissioning_onlineFailed =>
      'Check not passed. Fix as advised, then tap the button below to check again.';

  @override
  String get commissioning_onlineIntro =>
      'Confirm the gateway is on Wi-Fi and the backend keeps receiving heartbeats.';

  @override
  String get commissioning_onlineOffline =>
      'Offline setup: confirm online now, or verify later.';

  @override
  String get commissioning_onlineRunning =>
      'Checking the back office receives heartbeats; PTUs are searched next. Please wait.';

  @override
  String get commissioning_onlineRunningTaskTitle =>
      'Confirming the gateway is online, please wait';

  @override
  String get commissioning_onlineTapStart =>
      'Tap the button below to start the check.';

  @override
  String get commissioning_onlineTaskTitle => 'Confirm the gateway is online';

  @override
  String get commissioning_otherSiteLabel => 'Use another site';

  @override
  String get commissioning_otherWifiLabel => 'Use another Wi-Fi';

  @override
  String get commissioning_pickGatewayTaskTitle => 'Choose a gateway';

  @override
  String get commissioning_powerOffOldFirst =>
      'Make sure the old gateway is powered off, or the back office flags a conflict again.';

  @override
  String commissioning_ptuCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs',
      one: '1 PTU',
    );
    return '$_temp0';
  }

  @override
  String get commissioning_ptuOtherGateway => 'Belongs to another gateway';

  @override
  String get commissioning_ptuOutOfRange =>
      'Number outside this gateway\'s range; owner unconfirmed';

  @override
  String get commissioning_ptusPerGateway => 'PTUs per gateway';

  @override
  String get commissioning_recheck => 'Check again';

  @override
  String get commissioning_recheckIntro =>
      'Wi-Fi updated. Once the gateway uploads, confirm the site (keep it or set a new one).';

  @override
  String get commissioning_reconfigureAll => 'Reconfigure all';

  @override
  String get commissioning_reconfigureAllText =>
      'PTUs already assigned are assigned again. Continue?';

  @override
  String get commissioning_reconfigureAllTitle => 'Reconfigure all?';

  @override
  String get commissioning_reconnect => 'Reconnect';

  @override
  String get commissioning_reconnectContinue => 'Reconnect and continue';

  @override
  String get commissioning_reconnectVerify => 'Reconnect and verify';

  @override
  String get commissioning_reenter => 'Re-enter';

  @override
  String get commissioning_refreshHealth => 'Refresh health';

  @override
  String get commissioning_rejoinHintText =>
      'This gateway was removed (archived) in the back office, so its heartbeats are not recorded. Tap [Rejoin] below to continue the online check.';

  @override
  String get commissioning_rejoinLabel => 'Rejoin';

  @override
  String get commissioning_replaceFailedText =>
      'Replacing the old gateway failed. Check the network and retry';

  @override
  String get commissioning_replaceOldKeepNumber =>
      'Replace old (keep this number)';

  @override
  String get commissioning_replaceOldLabel => 'Replace old';

  @override
  String commissioning_replacedText(int site, int gateway) {
    return 'This gateway took over site $site / gateway $gateway';
  }

  @override
  String get commissioning_reportSubtitle => 'Full text; share or copy it';

  @override
  String get commissioning_reportTitle => 'Install report';

  @override
  String get commissioning_reportTitleDemo => 'Demo install report';

  @override
  String get commissioning_rescanPtus => 'Rescan PTUs from the gateway';

  @override
  String get commissioning_resetInclude => 'Reset and add';

  @override
  String get commissioning_resetWifi => 'Reset Wi-Fi';

  @override
  String get commissioning_restart => 'Start over';

  @override
  String commissioning_resumeMissingKey(String missing, String resume) {
    return '$missing.\n$resume';
  }

  @override
  String commissioning_retryFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Retry these $count',
      one: 'Retry this one',
    );
    return '$_temp0';
  }

  @override
  String get commissioning_retryReconnect => 'Retry reconnect';

  @override
  String commissioning_reuseBlockedTapAbove(String button, String reason) {
    return 'To use this site, first tap [$button] above (now: $reason).';
  }

  @override
  String commissioning_reuseBlockedWifi(
    String reason,
    String otherWifi,
    String review,
  ) {
    return 'To use this site, the gateway must be on Wi-Fi and uploading (now: $reason). Tap [$otherWifi] or [$review].';
  }

  @override
  String commissioning_saveNumberTakenText(int site, int gateway, String mac) {
    return 'Site $site / gateway $gateway is registered to another device (MAC $mac).';
  }

  @override
  String get commissioning_saveNumberTakenTitle => 'Number already in use';

  @override
  String get commissioning_saveWifiLabel => 'Save and continue';

  @override
  String commissioning_savedGateway(String name) {
    return 'Last gateway: $name';
  }

  @override
  String get commissioning_scanHelpDirect =>
      'The gateway scans nearby PTUs and sends the list to the phone over Bluetooth. One-to-one mode: the strongest one is selected automatically. RSSI is the gateway-to-PTU signal; unconnected devices show the scan value. \"Last\" means paused or stale; \"Cached\" means the firmware gave no read time. Firmware 1.7.5+ measures during setup; RSSI — means no valid reading yet.';

  @override
  String get commissioning_scanHelpDirectFlow =>
      'The gateway scans nearby PTUs and sends the list to the phone over Bluetooth. One-to-one mode: the gateway picks the nearest PTU itself (strongest within the threshold, or the bound one); this list only shows its pick. Use [Identify this charger] to check it is the one in front of you; if not, tap [Not this one?] to pick again. RSSI is the gateway-to-PTU signal; unconnected devices show the scan value. \"Last\" means paused or stale; \"Cached\" means the firmware gave no read time. Firmware 1.7.5+ measures during setup; RSSI — means no valid reading yet.';

  @override
  String commissioning_scanHelpStar(int max) {
    return 'The gateway scans nearby PTUs and sends the list to the phone over Bluetooth. Select up to $max. RSSI is the gateway-to-PTU signal; unconnected devices show the scan value. \"Last\" means paused or stale; \"Cached\" means the firmware gave no read time. Firmware 1.7.5+ measures during setup; RSSI — means no valid reading yet.';
  }

  @override
  String get commissioning_scanHelpTitle => 'Scan help and full flow';

  @override
  String get commissioning_setWifi => 'Set up Wi-Fi';

  @override
  String get commissioning_shareFailed =>
      'Cannot open sharing; copy the report instead.';

  @override
  String get commissioning_shareReport => 'Share report';

  @override
  String get commissioning_siteFieldLabel => 'Site ID (1–65535)';

  @override
  String commissioning_siteN(int site) {
    return 'Site $site';
  }

  @override
  String commissioning_siteNumbersFull(int site, int max) {
    return 'Gateways 1–$max of site $site are all in use. Check the site ID.';
  }

  @override
  String get commissioning_skipChooseSite =>
      'Choose the site first (keeping it needs a working network)';

  @override
  String get commissioning_skipNewNote =>
      '⚠ The gateway network is not confirmed yet. Upload is checked again after the new site is set, and in the final \"Verify data\" step.';

  @override
  String get commissioning_skipNewSite =>
      'Set up a new site anyway (confirm upload later)';

  @override
  String get commissioning_skipOfflineNewSite =>
      'Set up a new site offline (confirm upload later)';

  @override
  String get commissioning_skipOnline => 'Skip for now, set up PTUs';

  @override
  String get commissioning_skipOnlineHint =>
      'If skipped, the final \"Verify data\" step still checks the upload.';

  @override
  String get commissioning_skipStationNote =>
      'The current site can\'t be kept until the network check passes. Reset Wi-Fi or set a new site.';

  @override
  String get commissioning_skipThisPtu => 'Skip this one';

  @override
  String get commissioning_sortBySignal => 'Sort by signal';

  @override
  String get commissioning_starAssignTaskTitle =>
      'Setting up PTUs and starting monitoring';

  @override
  String commissioning_starCountChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Star mode now uses $count PTUs per gateway',
      one: 'Star mode now uses 1 PTU per gateway',
    );
    return '$_temp0';
  }

  @override
  String get commissioning_starCountTitle => 'Star mode: PTUs per gateway';

  @override
  String get commissioning_starPickTaskTitle =>
      'Select the PTUs this gateway handles';

  @override
  String get commissioning_starVerifyTaskTitle => 'Confirming data upload';

  @override
  String get commissioning_startPowerHint =>
      'First make sure the site Wi-Fi router and devices are powered on.';

  @override
  String get commissioning_startTaskTitle =>
      'Log in to the back office to start';

  @override
  String get commissioning_startVerify => 'Start data check';

  @override
  String commissioning_stationFull(int max, String swap) {
    return 'This site is full (1–$max all in use). Check the site ID or use [$swap].';
  }

  @override
  String get commissioning_stationHintBlocked =>
      'Use another site, or fix the tip above to keep this one';

  @override
  String get commissioning_stationHintCanUse =>
      'Choose: use this site, or another site';

  @override
  String get commissioning_stationInputTitle =>
      'Enter the site ID for this gateway';

  @override
  String commissioning_stationKeep(String site, String gateway) {
    return 'Keep site $site / gateway $gateway; site data stays as is.';
  }

  @override
  String commissioning_stationQuestionTitle(int site) {
    return 'Current site ID is $site. Set up this gateway here?';
  }

  @override
  String get commissioning_stayOnList => 'Stay on list';

  @override
  String commissioning_syncFirstHint(String place) {
    return 'This first points the gateway to $place (one reboot), then sets up Wi-Fi.';
  }

  @override
  String commissioning_syncTo(String place) {
    return 'Send to $place (reboot ~1 min)';
  }

  @override
  String get commissioning_targetTaskTitle =>
      'Have the gateway send data to this back office';

  @override
  String get commissioning_testModeTaskTitle =>
      'Gateway is in test mode. Switch it back to normal first';

  @override
  String commissioning_topologyAskDirectBound(String mac) {
    return 'This gateway is in one-to-one mode (bound to PTU $mac). Change it to star?\n\n[Keep one-to-one]: the app switches to one-to-one mode; the gateway settings stay.';
  }

  @override
  String get commissioning_topologyAskDirectTitle =>
      'This gateway is in one-to-one mode';

  @override
  String get commissioning_topologyAskDirectUnbound =>
      'This gateway is in one-to-one mode (no PTU bound). Change it to star?\n\n[Keep one-to-one]: the app switches to one-to-one mode; the gateway settings stay.';

  @override
  String commissioning_topologyAskStarText(int max) {
    return 'This gateway is in star mode (up to $max PTUs). Change it to one-to-one?\n\n[Keep star]: the app switches to star mode; the gateway settings stay.';
  }

  @override
  String get commissioning_topologyAskStarTitle =>
      'This gateway is in star mode';

  @override
  String get commissioning_topologyBusy =>
      'An action is running; switch after it ends.';

  @override
  String get commissioning_topologyChangeToDirect => 'Change to one-to-one';

  @override
  String get commissioning_topologyChangeToStar => 'Change to star';

  @override
  String get commissioning_topologyKeepDirect => 'Keep one-to-one';

  @override
  String get commissioning_topologyKeepStar => 'Keep star';

  @override
  String commissioning_topologyKeptText(String mode) {
    return 'The app now uses $mode; the gateway keeps its mode';
  }

  @override
  String get commissioning_topologyMenuBusy =>
      'Available after the action ends';

  @override
  String get commissioning_topologyMenuDirect => 'One-to-one';

  @override
  String get commissioning_topologyMenuStar => 'Star · one-to-many';

  @override
  String get commissioning_topologyTitle => 'Connection mode';

  @override
  String get commissioning_updateAfterHome =>
      'Available on the home page when no setup is running';

  @override
  String get commissioning_updateCheckFailed =>
      'Cannot check for updates now. Check the network and retry';

  @override
  String get commissioning_updateLatest => 'You have the latest version';

  @override
  String get commissioning_uploadBadTaskTitle =>
      'Gateway is not uploading yet. Follow the tips below';

  @override
  String commissioning_uploadOngoing(String where) {
    return '✓ Data uploading ($where)';
  }

  @override
  String get commissioning_uploadPausedTaskTitle =>
      'Gateway upload is paused. Resume it';

  @override
  String get commissioning_uploadRateHead =>
      'Upload interval is set by the back office';

  @override
  String commissioning_uploadRateNow(String seconds) {
    return 'Upload interval is set by the back office (now every $seconds s)';
  }

  @override
  String commissioning_uploadStatusWhere(String status, String where) {
    return 'Data upload: $status ($where)';
  }

  @override
  String commissioning_uploadWhere(String where) {
    return 'Data upload: $where';
  }

  @override
  String get commissioning_useNextFreeNumber => 'Use the next free number';

  @override
  String get commissioning_useSiteEmptyLabel => 'Use site';

  @override
  String commissioning_useSiteLabel(int site) {
    return 'Use site $site';
  }

  @override
  String get commissioning_useStationLabel => 'Use this site';

  @override
  String commissioning_verifyBackend(String env) {
    return 'Verify against: $env';
  }

  @override
  String commissioning_verifyBackendLocal(String env) {
    return 'Verify against: $env (test host on this PC)';
  }

  @override
  String get commissioning_verifyLoginTaskTitle =>
      'Log in to the back office to confirm data upload';

  @override
  String commissioning_versionBuild(String version, String build) {
    return 'Version $version · Build $build';
  }

  @override
  String get commissioning_versionUnavailable => 'Cannot read the version now';

  @override
  String get commissioning_viewNetworkStatus => 'View network status';

  @override
  String get commissioning_viewUploadData => 'View uploaded data…';

  @override
  String commissioning_waitUpTo(int seconds) {
    return 'Up to $seconds s';
  }

  @override
  String get commissioning_wifi24Only =>
      'The gateway works with 2.4 GHz Wi-Fi only; 5 GHz networks do not connect.';

  @override
  String get commissioning_wifiBackKeep => 'Keep Wi-Fi, go back';

  @override
  String get commissioning_wifiBackSite => 'Back to edit site ID';

  @override
  String get commissioning_wifiFirstPageText =>
      'Connect the gateway to Wi-Fi first; set the site ID once the network works.';

  @override
  String commissioning_wifiOnlyKeep(String site, String gateway) {
    return 'Keep site $site / gateway $gateway; update Wi-Fi only.';
  }

  @override
  String get commissioning_wifiPasswordNotSaved =>
      'Wi-Fi connected, but the password could not be saved; enter it again next time.';

  @override
  String get commissioning_wifiProblemTaskTitle =>
      'Gateway is not on Wi-Fi. Set up Wi-Fi';

  @override
  String get commissioning_wifiResetConfirm => 'Yes, reset Wi-Fi';

  @override
  String get commissioning_wifiResetGoHint =>
      'Tap [Yes, reset Wi-Fi] to open the Wi-Fi setup.';

  @override
  String get commissioning_wifiResetLater => 'Not now';

  @override
  String get commissioning_wifiResetTitle => 'Reset Wi-Fi?';

  @override
  String get commissioning_wifiSavedWaiting =>
      'Wi-Fi saved. Waiting for the gateway to resume uploading; the next step shows once confirmed. Please wait.';

  @override
  String get commissioning_wifiTaskTitle => 'Set up the gateway Wi-Fi';

  @override
  String get commissioning_wifiUploadWaitTitle =>
      'Wi-Fi connected, confirming data upload';

  @override
  String get common_back => 'Back';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_close => 'Close';

  @override
  String get common_confirm => 'Confirm';

  @override
  String get common_continue => 'Continue';

  @override
  String get common_copy => 'Copy';

  @override
  String get common_details => 'Details';

  @override
  String get common_done => 'Done';

  @override
  String get common_dotSeparator => ' · ';

  @override
  String get common_gotIt => 'Got it';

  @override
  String get common_languageEnglish => 'English';

  @override
  String get common_languageZhHant => '繁體中文';

  @override
  String get common_later => 'Later';

  @override
  String get common_listSeparator => ', ';

  @override
  String get common_loading => 'Loading…';

  @override
  String get common_ok => 'OK';

  @override
  String get common_refresh => 'Refresh';

  @override
  String get common_retry => 'Retry';

  @override
  String get common_settings => 'Settings';

  @override
  String get common_skip => 'Skip';

  @override
  String get common_timeout => 'timed out';

  @override
  String get common_unknown => 'unknown';

  @override
  String get connectionStatusPanel_collapse => 'Collapse';

  @override
  String get connectionStatusPanel_details => 'Technical details';

  @override
  String get connectionStatusPanel_expand => 'Expand';

  @override
  String get connectionStatusPanel_gatewayRow => 'Gateway → data upload';

  @override
  String get connectionStatusPanel_notNow => 'Not now';

  @override
  String get connectionStatusPanel_phoneRow => 'Phone → backend';

  @override
  String get connectionStatusPanel_reload => 'Reload';

  @override
  String connectionStatusPanel_switchBody(String target) {
    return 'The gateway will send its data to $target and restart (about 1 min). Stay near the gateway.';
  }

  @override
  String get connectionStatusPanel_switchButton => 'Switch';

  @override
  String get connectionStatusPanel_switchTitle => 'Switch the gateway too?';

  @override
  String get connectionStatusPanel_sync => 'Sync';

  @override
  String get connectionStatusPanel_title => 'Connection status';

  @override
  String connectionStatus_detailBootCount(int count) {
    return 'Gateway boot count: $count';
  }

  @override
  String get connectionStatus_detailDemo => 'Demo';

  @override
  String connectionStatus_detailFirmware(String version) {
    return 'Firmware version: $version';
  }

  @override
  String connectionStatus_detailGatewayNet(String ssid) {
    return 'Gateway network: Wi-Fi \"$ssid\"';
  }

  @override
  String connectionStatus_detailHealth(String result) {
    return 'Backend health check (GET /healthz): $result';
  }

  @override
  String connectionStatus_detailLastReset(String reason) {
    return ' (last reset: $reason)';
  }

  @override
  String connectionStatus_detailLocalMqttCheck(String port, String host) {
    return 'If local MQTT can\'t connect, check: the PC firewall allows TCP $port, the local MQTT broker is running, and the broker certificate includes $host.';
  }

  @override
  String get connectionStatus_detailModeNormal => 'Gateway mode: normal';

  @override
  String get connectionStatus_detailModeTest =>
      'Gateway mode: test mode (test data only)';

  @override
  String connectionStatus_detailMqtt(String state) {
    return 'MQTT connection: $state';
  }

  @override
  String connectionStatus_detailMqttLastRead(String state) {
    return 'MQTT connection (last read before the drop): $state';
  }

  @override
  String get connectionStatus_detailNotSet => '(not set)';

  @override
  String connectionStatus_detailPauseReason(String reason) {
    return ' ($reason)';
  }

  @override
  String connectionStatus_detailPhoneBackend(String base) {
    return 'Phone backend: $base';
  }

  @override
  String connectionStatus_detailSignal(String rssi) {
    return ' · signal $rssi dBm';
  }

  @override
  String get connectionStatus_detailSignalWeak => ' (weak)';

  @override
  String connectionStatus_detailTargetLegacy(String version) {
    return 'Gateway upload target: Production (firmware $version can\'t switch)';
  }

  @override
  String connectionStatus_detailTargetLocal(String hostPort) {
    return 'Gateway upload target: MQTT local $hostPort (TLS)';
  }

  @override
  String connectionStatus_detailTargetProduction(String hostPort) {
    return 'Gateway upload target: MQTT production $hostPort (TLS)';
  }

  @override
  String get connectionStatus_detailTargetUnconfirmed =>
      'Gateway upload target: unconfirmed (switch result not read back yet)';

  @override
  String connectionStatus_detailTargetUnknown(String value) {
    return 'Gateway upload target: unrecognized ($value)';
  }

  @override
  String get connectionStatus_detailUploadOn => 'Data upload: on';

  @override
  String get connectionStatus_detailUploadPaused => 'Data upload: paused';

  @override
  String get connectionStatus_hintCustomUnknown =>
      'The app can\'t tell from this URL where the gateway should send data. Showing the gateway\'s current setting only; no automatic switch.';

  @override
  String get connectionStatus_hintLinkLostReconnect =>
      'Bluetooth to the gateway dropped. Move closer and tap [End and choose another gateway] to reconnect.';

  @override
  String connectionStatus_hintPhoneNoBackend(String label) {
    return 'The phone can\'t reach $label. Check that the phone has internet access.';
  }

  @override
  String get connectionStatus_hintPhoneNoLocal =>
      'The phone can\'t reach the test host: check that it is running on the computer and that the phone and computer use the same Wi-Fi.';

  @override
  String connectionStatus_hintPortMismatch(String place) {
    return 'The gateway\'s upload settings differ from the phone\'s (see Technical details). Tap [Sync] to send it to $place.';
  }

  @override
  String connectionStatus_hintTargetMismatch(
    String current,
    String wanted,
    String place,
  ) {
    return 'The gateway sends data to $current, but the phone uses $wanted. Tap [Sync] to send it to $place.';
  }

  @override
  String get connectionStatus_hintUnknownReread =>
      'Not sure yet where the gateway sends data. Tap the reload icon (↻) at the right end of the Connection status row.';

  @override
  String connectionStatus_hintUnknownSync(String place) {
    return 'Not sure yet where the gateway sends data. Tap [Sync] to send it to $place.';
  }

  @override
  String connectionStatus_hintWifiConnecting(String action) {
    return 'The gateway is not on Wi-Fi yet; please wait. If it never connects, check the Wi-Fi name and password (tap [$action]).';
  }

  @override
  String connectionStatus_linkBack(String reload) {
    return 'Phone reconnected to the gateway. $reload';
  }

  @override
  String connectionStatus_linkLostCannotRead(String action) {
    return 'Bluetooth to the gateway dropped; can\'t read its current status. $action';
  }

  @override
  String connectionStatus_linkLostRelinking(String relinking) {
    return 'Bluetooth to the gateway dropped. $relinking';
  }

  @override
  String get connectionStatus_mqttConnected => 'connected';

  @override
  String get connectionStatus_mqttDisconnected => 'not connected';

  @override
  String get connectionStatus_placeLocal => 'Local test host';

  @override
  String get connectionStatus_probeChecking => 'Checking';

  @override
  String get connectionStatus_probeDegraded => 'Database not ready (HTTP 503)';

  @override
  String get connectionStatus_probeHealthy => 'OK';

  @override
  String connectionStatus_probeHealthyVersion(String version) {
    return 'OK (version $version)';
  }

  @override
  String connectionStatus_probeNotBackend(String status) {
    return 'Not this system\'s backend (HTTP $status)';
  }

  @override
  String get connectionStatus_probeUnreachable => 'Unreachable';

  @override
  String connectionStatus_probeUnreachableDetail(String detail) {
    return 'Unreachable ($detail)';
  }

  @override
  String get connectionStatus_reconnectThenCheck =>
      'Reconnect the gateway, then check again.';

  @override
  String get connectionStatus_statusChecking => '⏳ Checking…';

  @override
  String get connectionStatus_statusConfirming => '⏳ Confirming…';

  @override
  String get connectionStatus_statusConnected => '✓ Connected';

  @override
  String get connectionStatus_statusConnectedDemo => '✓ Connected (demo)';

  @override
  String get connectionStatus_statusConnecting => '⏳ Connecting…';

  @override
  String get connectionStatus_statusDbNotReady =>
      '⚠ Connected, but the database is not ready';

  @override
  String get connectionStatus_statusElsewhere => '⚠ Sending elsewhere';

  @override
  String get connectionStatus_statusLinkLostUploadUnknown =>
      '? Bluetooth lost, upload status unconfirmed';

  @override
  String get connectionStatus_statusTestMode => '⚠ Test mode';

  @override
  String get connectionStatus_statusUnconfirmed => '? Unconfirmed';

  @override
  String get connectionStatus_statusUnreachable => '✗ Can\'t connect';

  @override
  String get connectionStatus_statusUploadPaused => '⚠ Upload paused';

  @override
  String get connectionStatus_statusUploadUnknown =>
      '? Upload status unconfirmed';

  @override
  String get connectionStatus_statusUploading => '✓ Uploading data';

  @override
  String get connectionStatus_statusWifiDown => '✗ Wi-Fi not connected';

  @override
  String connectionStatus_subnetHint(
    String subnet,
    String host,
    String action,
  ) {
    return 'The gateway is on the $subnet.x subnet and may not reach the test host $host. Make sure the gateway and this computer use the same Wi-Fi (tap [$action]).';
  }

  @override
  String connectionStatus_summary(String label) {
    return '✓ $label: phone and gateway both connected';
  }

  @override
  String connectionStatus_tapButton(String button) {
    return 'Tap [$button].';
  }

  @override
  String get connectionStatus_uploadCheckLocal =>
      'Check that the test host on the computer is running and the gateway is on the same Wi-Fi as this computer.';

  @override
  String get connectionStatus_uploadCheckProduction =>
      'Check that the gateway\'s Wi-Fi has internet access.';

  @override
  String get connectionStatus_whereChecking => 'Checking';

  @override
  String get connectionStatus_whereUnconfirmed => 'Unconfirmed';

  @override
  String get connectionStatus_whereUnknown => 'Unrecognized';

  @override
  String get connectionStatus_wifiActionOther => 'Use another Wi-Fi';

  @override
  String get connectionStatus_wifiActionReset => 'Reset Wi-Fi';

  @override
  String get connectionStatus_wifiActionSet => 'Set up Wi-Fi';

  @override
  String connectionStatus_wifiFixHere(String action) {
    return 'Tap [$action] and switch to the site\'s 2.4 GHz Wi-Fi.';
  }

  @override
  String connectionStatus_wifiFixReconnect(String action) {
    return 'Tap [End and choose another gateway] to reconnect, then tap [$action] in the network check.';
  }

  @override
  String connectionStatus_wifiLinkLostReconnect(String action) {
    return 'Bluetooth to the gateway also dropped: move closer, tap [End and choose another gateway] to reconnect, then tap [$action].';
  }

  @override
  String connectionStatus_wifiLinkLostRelinking(String relinking) {
    return 'Bluetooth to the gateway also dropped. $relinking';
  }

  @override
  String controller_absentSelection(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs did not appear in this scan and were unchecked',
      one: '1 PTU did not appear in this scan and was unchecked',
    );
    return '$_temp0';
  }

  @override
  String controller_ackNumberMismatch(String reported, int wanted) {
    return 'Device reports #$reported, not the assigned #$wanted. Retry';
  }

  @override
  String controller_adjustedTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Adjusted to $count PTUs. Choose the connected devices again or fix the missing PTUs.',
      one:
          'Adjusted to 1 PTU. Choose the connected devices again or fix the missing PTUs.',
    );
    return '$_temp0';
  }

  @override
  String controller_allAssignFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'All $count PTUs failed to assign; gateway settings unchanged. Check the PTUs, then tap [Retry these $count].',
      one:
          'The PTU failed to assign; gateway settings unchanged. Check the PTU, then tap [Retry this one].',
    );
    return '$_temp0';
  }

  @override
  String get controller_alreadyMonitoring => 'Already monitoring';

  @override
  String controller_assignCount(int done, int total) {
    return '$done/$total';
  }

  @override
  String controller_assignFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs failed to assign',
      one: '1 PTU failed to assign',
    );
    return '$_temp0';
  }

  @override
  String controller_assignFailedReason(String reason) {
    return 'Assign failed: $reason';
  }

  @override
  String controller_assignedNumber(String id) {
    return 'Assigned #$id';
  }

  @override
  String controller_assignedPtu(int id) {
    return 'Assigned PTU #$id';
  }

  @override
  String controller_assignedWaiting(int id) {
    return 'Assigned #$id, waiting to connect';
  }

  @override
  String controller_assigningDirect(int id) {
    return 'Assigning #$id and starting monitoring';
  }

  @override
  String controller_assigningLabel(int done, int total) {
    return 'Setting up… $done/$total';
  }

  @override
  String get controller_autoRelinking => 'Reconnecting automatically…';

  @override
  String controller_backendRetry(int attempt) {
    return 'Backend not responding; retrying automatically ($attempt)';
  }

  @override
  String get controller_backendSwitchedDone =>
      'Environment switched. The data must be confirmed again on the new one.';

  @override
  String get controller_backendSwitchedVerify =>
      'Environment switched. Tap [Start data check] to confirm again.';

  @override
  String get controller_backendUnconfirmed =>
      'Backend not confirmed yet; verification is still needed after setup';

  @override
  String get controller_bindLaterBlocked =>
      'Cannot open \"Choose PTUs\" now. Finish the network check, then tap again.';

  @override
  String get controller_bindLaterHint =>
      'Tap [Identify and bind]: on the PTU list tap [Identify this charger] to confirm it is the one in front of you, then [This one, start setup] binds it and numbers it #1.';

  @override
  String get controller_bindLaterLabel => 'Identify and bind';

  @override
  String get controller_bindLaterNoStation =>
      'This gateway cannot keep its site now. Set up the site and Wi-Fi first.';

  @override
  String controller_bindLaterTitle(String mac) {
    return 'This gateway is connected to PTU $mac but not bound';
  }

  @override
  String get controller_bindLaterWaitingHint =>
      'Make sure this charger\'s PTU is powered and in the same enclosure as the gateway. Once connected, tap [Identify and bind].';

  @override
  String get controller_bindLaterWaitingTitle =>
      'This charger\'s PTU was not connected at the last setup, and the gateway is still not connected to a PTU';

  @override
  String controller_bleCleanupDone(String done, String next) {
    return 'Bluetooth cleanup not finished. Tap [$done] or [$next] to retry disconnecting.';
  }

  @override
  String get controller_bleCleanupIncomplete =>
      'Bluetooth cleanup not finished. Retry disconnecting.';

  @override
  String get controller_bleConnectIncomplete =>
      'Bluetooth connection not finished. Retry.';

  @override
  String controller_boundPtu(int id) {
    return 'Bound PTU #$id';
  }

  @override
  String get controller_busyTryAgain =>
      'Another action is still running. Wait for it to finish, then tap again.';

  @override
  String controller_cancelRestoreRetry(String failure) {
    return '$failure Stay close and cancel again to retry restoring, or restart the app and reconnect.';
  }

  @override
  String get controller_cancelled =>
      'Cancelled. Reconnect to check progress; any unrestored monitoring session resumes by its expiry.';

  @override
  String get controller_checkFailedNew =>
      'Network check failed. You can still set up a new site; the upload is confirmed later.';

  @override
  String get controller_checkFailedStation =>
      'Network check failed. You can reset the Wi-Fi or set a new site; keeping the site needs a working network.';

  @override
  String get controller_checkPassedNew =>
      'Network check passed. Set the identity and Wi-Fi.';

  @override
  String get controller_checkPassedStation =>
      'Network check passed. Choose the site.';

  @override
  String get controller_checkingMonitor =>
      'Checking the gateway\'s monitoring state';

  @override
  String get controller_chooseGateway => 'Choose the gateway to set up';

  @override
  String get controller_chooseStationWaitUpload =>
      'Choose the site. To keep it, wait for the gateway to start uploading.';

  @override
  String controller_configureCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Set up $count PTUs and start monitoring',
      one: 'Set up 1 PTU and start monitoring',
    );
    return '$_temp0';
  }

  @override
  String controller_configureRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Set up the remaining $count and start monitoring',
      one: 'Set up the last one and start monitoring',
    );
    return '$_temp0';
  }

  @override
  String get controller_configureRun =>
      'Numbering each PTU and starting monitoring';

  @override
  String get controller_configureWifiRun => 'Setting identity and Wi-Fi';

  @override
  String get controller_configuredVerify =>
      'Setup done. Verify the backend data';

  @override
  String controller_connectLogDetail(String log) {
    return 'Connect failures: $log';
  }

  @override
  String controller_connectLogLine(int attempt, String type) {
    return 'Attempt $attempt: $type';
  }

  @override
  String get controller_connectedHasStation =>
      'Connected. This gateway already has a site. Run the network check first, then keep the site or set a new one.';

  @override
  String get controller_connectedNew =>
      'Connected. Run the network check first, then set the identity and Wi-Fi.';

  @override
  String controller_connectedNumber(String id) {
    return 'Connected #$id';
  }

  @override
  String controller_connectingAttempt(int attempt) {
    return 'Connecting (attempt $attempt)';
  }

  @override
  String controller_connectingPeer(String name) {
    return 'Connecting to $name. Stay close';
  }

  @override
  String controller_connectingStage(String attempt, String stage) {
    return '$attempt: $stage';
  }

  @override
  String controller_continueAssign(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Continuing to assign $count PTUs',
      one: 'Continuing to assign 1 PTU',
    );
    return '$_temp0';
  }

  @override
  String get controller_dataStale => 'No new data for now';

  @override
  String get controller_dataStreaming => 'Data keeps updating';

  @override
  String controller_deferConfirm(int threshold) {
    return 'The gateway finishes setup as usual: it joins service, resumes uploading and keeps one-to-one mode with the current threshold ($threshold dBm), but binds no PTU.\nOnce this charger\'s PTU is powered, the gateway connects to it; confirm the binding later on site with [Identify and bind].';
  }

  @override
  String get controller_deferConfirmTitle =>
      'Finish setup now and let the PTU connect once powered?';

  @override
  String get controller_deferFinishLabel => 'Finish setup now';

  @override
  String get controller_deferredBindNowLabel =>
      'PTU powered: identify and bind';

  @override
  String controller_deferredDetail(int threshold) {
    return 'The gateway is in service and uploading, in one-to-one mode (threshold $threshold dBm), with no PTU bound yet.';
  }

  @override
  String get controller_deferredDone =>
      'This charger\'s PTU is not connected yet. It connects once powered; confirm the binding later on site with [Identify and bind].';

  @override
  String get controller_deferredDoneTitle => 'Gateway setup done';

  @override
  String get controller_deferredLater =>
      'To bind later: once the PTU is powered, reconnect to this gateway with the app and [Identify and bind] appears. If you are still on site and the PTU is powered, tap the button below.';

  @override
  String get controller_deferredSummary =>
      'This charger\'s PTU is not connected yet (connects once powered)';

  @override
  String get controller_deferredUploadStatus =>
      '✓ Uploading again (waiting for this charger\'s PTU)';

  @override
  String get controller_deferring =>
      'Finishing gateway setup (this charger\'s PTU not connected yet)';

  @override
  String get controller_devShipNote =>
      'Developer note (local test builds only; field staff can ignore it): this gateway uploads to a local test server. Before shipping, a developer must switch the phone and the gateway back to production.';

  @override
  String get controller_devShipSwitchLabel => 'Switch to production';

  @override
  String get controller_directBoundMissing =>
      'The PTU bound to the gateway is not here. Make sure it is powered, or unbind it and tap [Search again].';

  @override
  String controller_directBoundNote(String mac) {
    return 'Bound PTU MAC: $mac (the gateway connects to this one only)';
  }

  @override
  String get controller_directFreshWindow =>
      'The gateway is collecting nearby PTUs again. Please wait';

  @override
  String get controller_directNoCandidate =>
      'The gateway found no PTU close enough. Make sure this charger\'s PTU is powered and close, then tap [Search again].';

  @override
  String get controller_directNoData =>
      'The gateway has no data from this PTU yet. Check the PTU\'s power, then tap [This one, start setup] to retry; the gateway keeps monitoring.';

  @override
  String get controller_directNoReport =>
      'The gateway has not reported a pick yet. Tap [Search again].';

  @override
  String get controller_directPickIncomplete =>
      'The gateway did not finish picking. Check the error, then tap [Search again].';

  @override
  String controller_directPicked(String mac) {
    return 'The gateway picked PTU $mac. Tap [Identify this charger] to confirm it is the one in front of you';
  }

  @override
  String controller_directPickedAmbiguous(String mac) {
    return 'The gateway picked PTU $mac, but a nearby PTU has a similar signal. Tap [Identify this charger] to confirm';
  }

  @override
  String get controller_directPicking =>
      'The gateway is picking the nearest PTU. Please wait';

  @override
  String get controller_directStillSearching =>
      'The gateway is still looking for a PTU. Wait, then tap [Search again].';

  @override
  String controller_directSwitchDone(String mac) {
    return 'The gateway switched to PTU $mac (bound). Tap [Identify this charger] to confirm it is the one in front of you.';
  }

  @override
  String controller_directSwitchPending(String mac) {
    return 'The gateway is still switching to PTU $mac. The screen updates once it connects; you can also pick another PTU.';
  }

  @override
  String get controller_disconnecting => 'Disconnecting Bluetooth…';

  @override
  String get controller_doneBefore => 'Done earlier';

  @override
  String get controller_doneBusy =>
      'Working on it. Tap [Done] when it finishes.';

  @override
  String get controller_doneNextLabel => 'Set up next';

  @override
  String get controller_endFlowConfirmTitle => 'End the current setup?';

  @override
  String controller_endFlowDeferHint(String label) {
    return 'If this charger\'s PTU is not here, tap [$label] instead.';
  }

  @override
  String get controller_endFlowHeldUpload =>
      'Note: this gateway is not in service yet (upload paused). Nothing will be uploaded after you end.';

  @override
  String controller_endFlowKeepDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The $count PTUs already done stay on the gateway.',
      one: 'The 1 PTU already done stays on the gateway.',
    );
    return '$_temp0';
  }

  @override
  String get controller_endFlowLabel => 'End and choose another gateway';

  @override
  String get controller_endFlowNoneDone => 'No PTU is done yet.';

  @override
  String controller_endFlowRestoreDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Ending restores the gateway\'s PTU binding from before the change. The $count PTUs already done are kept.',
      one:
          'Ending restores the gateway\'s PTU binding from before the change. The 1 PTU already done is kept.',
    );
    return '$_temp0';
  }

  @override
  String get controller_endFlowRestoreNone =>
      'Ending restores the gateway\'s PTU binding from before the change. No PTU is done yet.';

  @override
  String controller_firmwareNote(String version) {
    return 'Firmware $version';
  }

  @override
  String controller_firstConnectFailure(String failure) {
    return 'First connection failed: $failure';
  }

  @override
  String get controller_gatewayBusy => 'Gateway busy, waiting…';

  @override
  String get controller_gatewayFallbackName => 'Gateway';

  @override
  String get controller_gatewayFull =>
      'This gateway is full. Connect another gateway.';

  @override
  String get controller_gatewayStatusBusy => 'Not available during setup';

  @override
  String get controller_gatewayStatusMenu => 'View uploaded data…';

  @override
  String controller_gatewayStatusMenuBusy(String reason) {
    return 'View uploaded data ($reason)';
  }

  @override
  String get controller_healthAbnormal =>
      'Data looks abnormal. Check the PTUs and the network.';

  @override
  String get controller_healthPending => 'Checking the upload…';

  @override
  String get controller_healthUnknown =>
      'Cannot confirm the latest data. Check the network';

  @override
  String controller_heartbeatNote(int n) {
    return 'Heartbeat $n/2';
  }

  @override
  String get controller_identifyPeerLabel => 'Identify gateway (blink)';

  @override
  String get controller_identifyRun => 'Identifying the gateway';

  @override
  String controller_identityConflict(int site, int gw) {
    return 'ID conflict: several devices use the same site $site / gateway $gw.';
  }

  @override
  String get controller_keepStationResetWifi =>
      'Keeping the current site and PTUs; only the Wi-Fi is reset. Choose a 2.4 GHz Wi-Fi.';

  @override
  String controller_lastDone(String site, String gateway) {
    return 'Last one done: site $site, gateway $gateway';
  }

  @override
  String controller_lastDoneDeferred(String site, String gateway) {
    return 'Last one done: site $site, gateway $gateway (its PTU connects once powered)';
  }

  @override
  String get controller_leaveListConfirmTitle =>
      'End this setup and go to the home page?';

  @override
  String get controller_leaveListLabel => 'End setup';

  @override
  String get controller_linkConfirming =>
      'Bluetooth connected. Checking the gateway\'s replies and settings…';

  @override
  String get controller_listNotWritten =>
      'List not written; assignment continues';

  @override
  String get controller_loginRun => 'Logging in to the backend';

  @override
  String get controller_monitorSkipped =>
      'Monitoring check skipped. Confirm each PTU uploads during the data check.';

  @override
  String get controller_monitorUnconfirmedCheck =>
      'Not confirmed that the gateway resumed monitoring. Reconnect to check its settings.';

  @override
  String get controller_monitorUnconfirmedRecheck =>
      'Not confirmed that the gateway resumed monitoring. Reconnect to check.';

  @override
  String controller_monitorUnconfirmedResume(String label) {
    return 'Not confirmed that the gateway resumed monitoring. Tap [$label] to check.';
  }

  @override
  String get controller_netCheckIntro =>
      'Network check: confirm the gateway\'s Wi-Fi and upload.';

  @override
  String get controller_newStationPrompt =>
      'Enter the new site ID and Wi-Fi. The gateway changes only after you save.';

  @override
  String controller_nextGateway(int site) {
    return 'Choose the next gateway. It will use site $site by default.';
  }

  @override
  String get controller_nextSetWifi => 'Next, set the Wi-Fi.';

  @override
  String get controller_noChange => 'No change needed';

  @override
  String get controller_noGatewayFound =>
      'No gateway found. Move closer, check its power and scan again.';

  @override
  String get controller_noPtuConnected =>
      'No PTU connected. Check the PTUs\' power and distance, then retry; the gateway keeps monitoring.';

  @override
  String get controller_noneValue => '(none)';

  @override
  String controller_notIdentifiedPick(String mac) {
    return 'The gateway is connected to PTU $mac. Tap [Identify this charger] to confirm it is the one in front of you, then [This one, start setup].';
  }

  @override
  String get controller_notReported => '(not reported)';

  @override
  String get controller_offlineMode =>
      'Offline mode: log in at the end for the data check';

  @override
  String get controller_onlineReady =>
      'The gateway stays online. You can search for PTUs';

  @override
  String get controller_onlineRun => 'Confirming the gateway stays online';

  @override
  String controller_partialAssign(int ok, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other:
          '$ok now online; $failed failed to assign. Tap [Retry these $failed].',
      one: '$ok now online; 1 failed to assign. Tap [Retry this one].',
    );
    return '$_temp0';
  }

  @override
  String controller_pendingReadback(int id) {
    return 'Sent #$id, waiting for read-back';
  }

  @override
  String get controller_prepareRun =>
      'Checking Bluetooth and the backend connection';

  @override
  String get controller_prepared => 'Ready';

  @override
  String get controller_ptuBackHint =>
      'The gateway is connected to the bound PTU. No replacement needed.';

  @override
  String controller_ptuBackTitle(String mac) {
    return 'PTU connected ($mac)';
  }

  @override
  String get controller_ptuConnectFailed =>
      'PTU connection failed. Check the PTU\'s power and distance';

  @override
  String controller_ptuCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs',
      one: '1 PTU',
    );
    return '$_temp0';
  }

  @override
  String get controller_ptuCountReading => 'Reading…';

  @override
  String get controller_ptuCountUnread => 'PTU list not read yet';

  @override
  String controller_ptuCounts(int connected, int nearby) {
    return '$connected connected / $nearby nearby not connected';
  }

  @override
  String controller_ptuJoinedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs connected',
      one: '1 PTU connected',
    );
    return '$_temp0';
  }

  @override
  String get controller_ptuJoinedDirect => 'PTU connected to the gateway';

  @override
  String get controller_ptuListBusy =>
      'Gateway busy; the list cannot be updated for now';

  @override
  String controller_ptuListBusyWithCounts(String busy, String counts) {
    return '$busy (the list below is the last one: $counts)';
  }

  @override
  String controller_ptuListLoading(int target) {
    return 'Reading… (target $target)';
  }

  @override
  String get controller_ptuMissingHint =>
      'Make sure the original PTU is powered. Normally it can be replaced over the phone\'s Bluetooth without the original PTU. Back office sync and the data check still need the gateway online and the phone able to reach the back office. To change only the network, reset the Wi-Fi first; no PTU is needed.';

  @override
  String controller_ptuMissingTitle(String tail) {
    return 'This charger\'s PTU is missing (bound MAC ends $tail)';
  }

  @override
  String get controller_ptuNoResponse => 'PTU not responding';

  @override
  String get controller_ptuNotFound =>
      'The gateway cannot find this PTU. Scan again';

  @override
  String controller_ptuOtherTitle(String bound, String other) {
    return 'Connected to a PTU other than the bound one (bound MAC ends $bound, now $other)';
  }

  @override
  String controller_ptuSearchingHint(String tail, String label) {
    return 'The gateway just started or changed state and is connecting to the bound PTU (MAC ends $tail). It usually connects within 1 minute; wait, then tap [$label].';
  }

  @override
  String get controller_ptuSearchingRecheckLabel => 'Check again';

  @override
  String get controller_ptuSearchingTitle => 'Looking for this charger\'s PTU…';

  @override
  String get controller_ptuSetupIncomplete =>
      'PTU setup not finished. Move closer and retry';

  @override
  String controller_ptuUnnumbered(String mac) {
    return 'PTU $mac: no device number (device_number=0)';
  }

  @override
  String controller_ptusReturned(int count, int target) {
    return 'PTUs from the gateway: $count. Choose the devices to monitor (up to $target)';
  }

  @override
  String controller_readbackMismatch(int actual, int wanted) {
    return 'Read back #$actual, not the assigned #$wanted. Retry';
  }

  @override
  String get controller_recheckPtuLabel => 'PTU powered, check again';

  @override
  String get controller_recheckingPtu => 'Checking the PTU again';

  @override
  String controller_reconnectContinueRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reconnect and continue ($count left)',
    );
    return '$_temp0';
  }

  @override
  String controller_reconnectFailedAttempts(int attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other:
          'Reconnect failed ($attempts attempts). Move closer to the gateway and tap again',
      one:
          'Reconnect failed (1 attempt). Move closer to the gateway and tap again',
    );
    return '$_temp0';
  }

  @override
  String get controller_reconnectLinkRun => 'Reconnecting to the gateway';

  @override
  String get controller_reconnectedRescan =>
      'Reconnected. The gateway is scanning for PTUs again.';

  @override
  String get controller_reconnecting => 'Reconnecting to the gateway';

  @override
  String get controller_rejoining => 'Rejoining the back office';

  @override
  String get controller_relinkReconnect => 'Phone reconnecting to the gateway…';

  @override
  String get controller_relinkReload => 'Reading the PTU list again…';

  @override
  String get controller_relinkingLabel => 'Reconnecting…';

  @override
  String get controller_relistingLabel => 'Reading list…';

  @override
  String get controller_repairRequested =>
      'Reconnect requested. Confirm online status and data again';

  @override
  String get controller_repairRun => 'Reconnecting the gateway';

  @override
  String get controller_replaceBindChanged =>
      'The gateway\'s PTU binding changed. Reconnect to check; the binding was not changed.';

  @override
  String get controller_replaceBleOff =>
      'The gateway\'s PTU Bluetooth is off. Check the device first; the binding was not changed.';

  @override
  String get controller_replaceChanged =>
      'The gateway or its binding changed. Check again which PTU to replace.';

  @override
  String get controller_replaceIdentityMismatch =>
      'Cannot match the gateway\'s identity, site or one-to-one settings. Reconnect to check; the binding was not changed.';

  @override
  String get controller_replaceJournalNotCleared =>
      'The PTU binding was read back, but the recovery record was not cleared. Reconnect to check.';

  @override
  String get controller_replaceJournalSaveFailed =>
      'Cannot save the PTU replacement recovery record; the binding was not changed.';

  @override
  String get controller_replaceJournalUnreadable =>
      'Cannot read the PTU replacement recovery record. Contact maintenance.';

  @override
  String get controller_replaceMustRestore =>
      'Reconnect first to restore the binding from the last PTU replacement; the recovery record cannot be skipped.';

  @override
  String get controller_replaceNotReadBack =>
      'The new PTU binding was not read back; replacement stopped.';

  @override
  String controller_replaceNotRestored(String label) {
    return 'The last PTU replacement is not restored yet. Use [$label] to check the original binding first.';
  }

  @override
  String get controller_replaceOtherBinding =>
      'The gateway already has another PTU binding; not overwritten. Reconnect to check.';

  @override
  String get controller_replacePending =>
      'The last replacement is not restored yet. Cancel and restore the original binding first.';

  @override
  String controller_replacePtuConfirm(String mac) {
    return 'The gateway\'s binding to PTU $mac is removed (site and Wi-Fi unchanged). After the device safety check, a new PTU is searched for over the phone\'s Bluetooth; the original PTU need not be here. Cancelling or failing before the new binding is confirmed restores the old one; if Bluetooth drops, reconnect to finish restoring. Back office sync and the data check still need the network; setup is not complete until verified.';
  }

  @override
  String get controller_replacePtuConfirmTitle =>
      'Replace PTU: unbind and pair again?';

  @override
  String get controller_replacePtuLabel => 'Replace PTU';

  @override
  String controller_replaceRestoreFailed(String mac) {
    return 'Cannot open \"Choose PTUs\", and the gateway\'s PTU binding could not be restored to $mac. Reconnect to this gateway to check the binding.';
  }

  @override
  String get controller_replaceSearching =>
      'Searching for a new PTU here; back office sync and the data check still need the network.';

  @override
  String get controller_replaceSetupRestored =>
      'PTU setup not finished; the original binding was restored. Start the replacement again.';

  @override
  String get controller_replaceUnbindUnconfirmed =>
      'The gateway did not confirm the unbinding; replacement stopped.';

  @override
  String get controller_replaceUnfinished =>
      'The last PTU replacement did not finish. Reconnect to check and restore the original binding.';

  @override
  String get controller_replacingPtu => 'Removing the PTU binding';

  @override
  String controller_reread(String status) {
    return 'Read again. $status';
  }

  @override
  String get controller_rereadStatusRun => 'Reading the gateway status again';

  @override
  String get controller_rescanAfterLossLabel => 'Reconnect and continue';

  @override
  String get controller_rescanLabel => 'Rescan';

  @override
  String get controller_resetFailed =>
      'Reset failed (timed out). Move closer and retry';

  @override
  String get controller_resetNumberRun =>
      'Resetting the number before rescanning';

  @override
  String controller_resettingStale(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count PTUs with leftover numbers; resetting them',
      one: 'Found 1 PTU with a leftover number; resetting it',
    );
    return '$_temp0';
  }

  @override
  String get controller_restoredBind =>
      'Original PTU binding checked and restored. The network must be checked again.';

  @override
  String get controller_restoringBind =>
      'Checking and restoring the original PTU binding';

  @override
  String controller_resume(
    String where,
    String done,
    String inflight,
    String pending,
  ) {
    return 'Stopped last time at $where: $done$inflight$pending. The gateway is still running; no need to power-cycle it.';
  }

  @override
  String controller_resumeDone(int count, String list) {
    return '$count done ($list)';
  }

  @override
  String controller_resumeInflight(String list) {
    return '; $list interrupted while assigning (the gateway decides after reconnecting)';
  }

  @override
  String get controller_resumeMonitoring => 'Resume monitoring';

  @override
  String get controller_resumeNoneDone => 'no PTU done yet';

  @override
  String controller_resumePending(int count) {
    return ', $count not set up yet';
  }

  @override
  String get controller_resumeUnknown =>
      'Earlier progress kept. Reconnect to check the devices\' current state.';

  @override
  String get controller_resumeWithoutLogin =>
      'Not logged in, so leftover numbers cannot be reclaimed automatically. Continuing in manual mode';

  @override
  String get controller_retryAssignRun =>
      'Retrying the PTUs that failed to assign';

  @override
  String get controller_reuseBlocked =>
      'The gateway is not on Wi-Fi or not uploading yet, so this site cannot be used for now. Tap [Use another Wi-Fi] first, or go back to the network check.';

  @override
  String get controller_reuseStationPrompt =>
      'Using this site. The gateway searches for PTUs; confirm the devices to monitor.';

  @override
  String get controller_savedStepFind => 'step 2 (find gateway)';

  @override
  String get controller_savedStepMonitor => 'step 8 (start monitoring)';

  @override
  String get controller_savedStepNetCheck => 'step 3 (gateway network check)';

  @override
  String get controller_savedStepSelect => 'step 7 (choose PTUs)';

  @override
  String get controller_savedStepUpload => 'step 5 (confirm upload)';

  @override
  String get controller_savedStepVerify => 'step 9 (data check)';

  @override
  String controller_scanIncomplete(String label) {
    return 'Gateway scan not finished. Check the error, then tap [$label].';
  }

  @override
  String controller_scanLinkLost(String label) {
    return 'Gateway scan not finished: the Bluetooth link dropped. Move closer to the gateway, then tap [$label].';
  }

  @override
  String get controller_scanRun => 'Searching for nearby gateways';

  @override
  String controller_scanTestMode(String label) {
    return 'The gateway is in test mode and does not scan PTUs. Tap [$label]; the app rescans after the switch.';
  }

  @override
  String get controller_scanningLabel => 'Scanning…';

  @override
  String get controller_scanningPtus =>
      'The gateway is scanning nearby PTUs. Please wait';

  @override
  String controller_selectedDoneRest(int selected, int done, int rest) {
    return 'Selected $selected · done $done · to set up $rest';
  }

  @override
  String controller_selectedOfTarget(int selected, int target) {
    return 'Selected $selected / $target';
  }

  @override
  String controller_starApply(int limit) {
    return 'The gateway connects to only $limit now. Once you start the setup, it switches to star and connects all PTUs.';
  }

  @override
  String get controller_starOwnerUnknown =>
      'Cannot confirm the gateway\'s registration. Reset manually';

  @override
  String get controller_startVerify => 'Start verification';

  @override
  String controller_step7Retry(int seconds, int retry, int total) {
    return 'Bluetooth dropped again. Reconnecting in $seconds s (retry $retry/$total)';
  }

  @override
  String controller_stepWhere(int step, String label) {
    return 'step $step ($label)';
  }

  @override
  String controller_stoppedStep8(int count, String label) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Stopped. The $count PTUs done are kept; tap [$label] to go on.',
      one: 'Stopped. The 1 PTU done is kept; tap [$label] to go on.',
    );
    return '$_temp0';
  }

  @override
  String controller_summary(int scanned, int configured) {
    return 'Found $scanned, $configured set up on this gateway';
  }

  @override
  String controller_summaryOtherGateways(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ', $count belong to other gateways',
      one: ', 1 belongs to another gateway',
    );
    return '$_temp0';
  }

  @override
  String controller_summaryResetFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ', $count failed to reset',
    );
    return '$_temp0';
  }

  @override
  String controller_switchingPick(String mac) {
    return 'Switching the gateway to PTU $mac';
  }

  @override
  String controller_switchingTarget(String target) {
    return 'Switching the gateway to $target (it restarts, about 1 minute)';
  }

  @override
  String controller_targetSwitched(String target, String next) {
    return 'Switched the gateway to $target; it restarted and reconnected. $next';
  }

  @override
  String controller_targetUnchanged(String target, String status) {
    return 'No switch needed: the gateway already sends to $target (no restart). $status';
  }

  @override
  String controller_tempRestoreFailed(
    String temp,
    String restore,
    String failure,
  ) {
    return 'Temporary binding $temp could not be restored to $restore: $failure';
  }

  @override
  String controller_tempUnbindFailed(String temp, String failure) {
    return 'Temporary binding $temp could not be removed: $failure';
  }

  @override
  String controller_thresholdReadback(String wanted, String readBack) {
    return 'Wrote $wanted, read back $readBack';
  }

  @override
  String get controller_topologyDirect => 'One-to-one';

  @override
  String controller_topologyRelistPending(String reason) {
    return '$reason. The PTU list must be read again';
  }

  @override
  String controller_topologyRelistReading(String reason) {
    return '$reason. Reading the PTU list again…';
  }

  @override
  String get controller_topologyStar => 'Star';

  @override
  String controller_topologySwitched(String mode) {
    return 'Switched to $mode';
  }

  @override
  String get controller_unbindingRun => 'Removing the gateway\'s PTU binding';

  @override
  String get controller_unreadable => '(unreadable)';

  @override
  String get controller_updatingDirect => 'Updating one-to-one settings';

  @override
  String get controller_uploadConnecting =>
      'The gateway is connecting; the app confirms automatically (up to about 2 minutes).';

  @override
  String get controller_uploadElsewhere =>
      'The gateway sends its data to another back office';

  @override
  String get controller_uploadNotReady =>
      'PTUs can be chosen only after the gateway joins Wi-Fi and starts uploading. Wait for ✓ on \"Confirm upload\", or reset the Wi-Fi again.';

  @override
  String get controller_uploadStarted => 'The gateway has started uploading.';

  @override
  String get controller_verified =>
      'Verification passed; automatic monitoring resumed';

  @override
  String controller_verifyFailed(String detail) {
    return 'Data check failed:\n$detail';
  }

  @override
  String controller_verifyNoData(int id) {
    return 'PTU #$id: no data yet';
  }

  @override
  String controller_verifyProgress(String line) {
    return 'Data check $line';
  }

  @override
  String get controller_verifyRun =>
      'Confirming each PTU\'s data keeps reaching the backend';

  @override
  String controller_verifySkipped(int id) {
    return 'PTU #$id not verified (skipped)';
  }

  @override
  String get controller_verifyStopped =>
      'Data check stopped. Adjust the selection and set up again.';

  @override
  String get controller_waitingBluetooth => 'Waiting for Bluetooth';

  @override
  String get controller_wifiConnectedNext =>
      'Wi-Fi connected. Next, confirm the backend sees the gateway';

  @override
  String get controller_wifiFirstCheck =>
      'Wi-Fi connected. Some network check items still fail; follow the hints below.';

  @override
  String get controller_wifiFirstDone => 'Network OK. Next, set the site ID.';

  @override
  String get controller_wifiFirstPrompt =>
      'Set the Wi-Fi first (the gateway supports 2.4 GHz only), then the site ID once the network works.';

  @override
  String get controller_wifiFirstRunLabel => 'Setting up Wi-Fi';

  @override
  String controller_wifiKept(String ssid) {
    return 'Gateway is on $ssid; keep it';
  }

  @override
  String controller_wifiKeptDone(String ssid) {
    return 'Kept Wi-Fi $ssid (not reconnected). Next, confirm the backend sees the gateway';
  }

  @override
  String get controller_wifiOnlyPrompt =>
      'Keeping the current site and PTUs; only the Wi-Fi is updated.';

  @override
  String get controller_wifiUpdatedChooseStation =>
      'Wi-Fi updated and uploading. Check the site: if this gateway\'s current site is not this one, choose [Use another site].';

  @override
  String get controller_wifiUpdatedKeepStation =>
      'Wi-Fi updated; site and PTU settings kept. Next, confirm the upload.';

  @override
  String controller_writingThreshold(String dbm) {
    return 'Writing threshold $dbm dBm';
  }

  @override
  String get controller_wrongDevice => 'Assigned to the wrong device. Retry';

  @override
  String get coreProgressChecklist_connectBackend => 'Back office reachable';

  @override
  String get coreProgressChecklist_connectBle => 'Bluetooth connection';

  @override
  String get coreProgressChecklist_connectStatus => 'Read gateway status';

  @override
  String get coreProgressChecklist_connectWifi => 'Wi-Fi connected';

  @override
  String coreProgressChecklist_dataEach(int count, int need) {
    return '$count/$need rows each';
  }

  @override
  String coreProgressChecklist_dataReceived(int count, int need) {
    return '$count/$need rows received';
  }

  @override
  String get coreProgressChecklist_finishAssign => 'Assign PTU';

  @override
  String coreProgressChecklist_finishAssignTotal(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'Assign PTUs ($total in total)',
      one: 'Assign PTU',
    );
    return '$_temp0';
  }

  @override
  String get coreProgressChecklist_finishBind => 'Write PTU binding';

  @override
  String get coreProgressChecklist_finishData => 'Verify data upload';

  @override
  String get coreProgressChecklist_finishJoin => 'Join monitoring';

  @override
  String get coreProgressChecklist_finishJoined => 'Check it joined monitoring';

  @override
  String get coreProgressChecklist_finishList => 'Write PTU list';

  @override
  String get coreProgressChecklist_finishSettings => 'Write PTU settings';

  @override
  String get coreProgressChecklist_notDone => 'Not completed';

  @override
  String get coreProgressChecklist_onlineBackend => 'Reach the back office';

  @override
  String get coreProgressChecklist_onlineBeat1 => '1st heartbeat received';

  @override
  String get coreProgressChecklist_onlineBeat2 =>
      '2nd heartbeat received (stays online)';

  @override
  String get coreProgressChecklist_onlineTarget => 'Upload target confirmed';

  @override
  String get coreProgressChecklist_targetCurrent =>
      'To the current back office';

  @override
  String get coreProgressChecklist_targetLocal => 'Local test';

  @override
  String dashboardApi_backend(String origin) {
    return 'Backend $origin';
  }

  @override
  String dashboardApi_backendLocal(String origin) {
    return 'LAN / local backend $origin';
  }

  @override
  String get dashboardApi_backendUnset => '(no backend URL set)';

  @override
  String directCalibrationSheet_intro(int seconds) {
    return 'Keep this and nearby chargers placed and powered as in use. After $seconds s of sampling a threshold is suggested; it is written to the gateway only after you confirm.';
  }

  @override
  String get directCalibrationSheet_legacyFirmware =>
      'Older gateway firmware, not reported';

  @override
  String directCalibrationSheet_median(String value) {
    return 'Median $value';
  }

  @override
  String directCalibrationSheet_medianSkipped(String value) {
    return 'Median $value (not used for the upper bound)';
  }

  @override
  String get directCalibrationSheet_neighborLegacy =>
      'Neighbour signals are other PTUs (peak) the gateway heard at its last pick; not updated after it connects.';

  @override
  String directCalibrationSheet_neighborLive(int maxAge) {
    return 'Neighbour signals are other PTUs (peak) the gateway keeps hearing while connected (counted for $maxAge s).';
  }

  @override
  String get directCalibrationSheet_noNeighbor => 'No neighbouring PTU heard';

  @override
  String get directCalibrationSheet_notRead => 'Not read yet';

  @override
  String get directCalibrationSheet_notReported =>
      'Not reported by the gateway';

  @override
  String get directCalibrationSheet_ownAdv => 'This charger\'s advertising';

  @override
  String get directCalibrationSheet_ownLink => 'This charger\'s link signal';

  @override
  String directCalibrationSheet_ownLinkValue(
    String median,
    String weakest,
    int count,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows',
      one: '1 row',
    );
    return 'Median $median · weakest $weakest ($_temp0)';
  }

  @override
  String directCalibrationSheet_ownPtu(String mac) {
    return 'This charger\'s PTU: $mac';
  }

  @override
  String directCalibrationSheet_peak(String value) {
    return 'Peak $value';
  }

  @override
  String directCalibrationSheet_range(String lower, String upper) {
    return 'Usable range $lower to $upper: this charger gets picked and stays connected, and no neighbour connects when this charger is off.';
  }

  @override
  String get directCalibrationSheet_resample => 'Sample again';

  @override
  String directCalibrationSheet_sampleDone(int reads) {
    String _temp0 = intl.Intl.pluralLogic(
      reads,
      locale: localeName,
      other: 'Sampling done ($reads reads)',
      one: 'Sampling done (1 read)',
    );
    return '$_temp0';
  }

  @override
  String directCalibrationSheet_sampling(int left, int reads) {
    String _temp0 = intl.Intl.pluralLogic(
      reads,
      locale: localeName,
      other: '$reads reads so far',
      one: '1 read so far',
    );
    return 'Sampling… $left s left ($_temp0)';
  }

  @override
  String get directCalibrationSheet_saveFailed =>
      'Threshold not written to the gateway. Try again.';

  @override
  String directCalibrationSheet_saved(String label, int value) {
    return '$label: $value dBm';
  }

  @override
  String get directCalibrationSheet_strongestNeighbor => 'Strongest neighbour';

  @override
  String directCalibrationSheet_suggestion(int threshold, int current) {
    return 'Suggested threshold: $threshold dBm (now $current dBm)';
  }

  @override
  String directCalibrationSheet_tiesAll(int count, int db) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs within $db dB, all listed',
      one: '1 PTU within $db dB, listed',
    );
    return '$_temp0';
  }

  @override
  String directCalibrationSheet_tiesListed(int ties, int db, int listed) {
    return '$ties PTUs within $db dB, $listed listed';
  }

  @override
  String directCalibrationSheet_tooClose(String reason, String advice) {
    return '$reason. $advice.';
  }

  @override
  String get directCalibrationSheet_write => 'Write to gateway';

  @override
  String directCalibrationSheet_writeValue(int threshold) {
    return 'Write to gateway ($threshold dBm)';
  }

  @override
  String get directCalibrationSheet_writing => 'Writing…';

  @override
  String directCalibration_ambiguous(int db) {
    return 'This charger and a neighbour advertise less than $db dB apart: the pick may be ambiguous. Once the PTU is bound, this no longer matters.';
  }

  @override
  String directCalibration_fewSamples(int count, int min, String rescan) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count neighbour PTUs have few readings (under $min); they are counted in the lower bound but may be unstable. Tap [$rescan] to sample again.',
      one:
          '1 neighbour PTU has few readings (under $min); it is counted in the lower bound but may be unstable. Tap [$rescan] to sample again.',
    );
    return '$_temp0';
  }

  @override
  String directCalibration_gapEqual(String neighbor) {
    return 'Neighbour $neighbor is as strong as this charger';
  }

  @override
  String directCalibration_gapSmall(String neighbor, int gap, int min) {
    return 'Neighbour $neighbor is only $gap dB weaker than this charger; not enough margin (needs at least $min dB)';
  }

  @override
  String directCalibration_gapStronger(String neighbor, int db) {
    return 'Neighbour $neighbor is $db dB stronger than this charger';
  }

  @override
  String directCalibration_holdLabel(int hold) {
    return 'Keep current threshold ($hold dBm), no write needed';
  }

  @override
  String get directCalibration_needsOwn =>
      'First tap [Identify this charger] in step 7 to confirm this charger\'s PTU, then calibrate.';

  @override
  String directCalibration_neighborsAndMore(String named, int total) {
    return '$named and others ($total in all)';
  }

  @override
  String directCalibration_noNeighbor(int hold) {
    return 'No neighbour PTU heard (connected PTUs do not advertise), so a looser threshold cannot be proven safe. Keep $hold dBm.';
  }

  @override
  String get directCalibration_noOwn =>
      'No link signal from this charger\'s PTU (the gateway is not linked to the confirmed PTU), so no threshold can be suggested. Check this charger\'s PTU is connected, then sample again.';

  @override
  String get directCalibration_outOfRange =>
      'This charger\'s readings are outside the gateway\'s range (-100 to -20 dBm). Sample again';

  @override
  String directCalibration_ownBelowHold(int upper, int hold) {
    return 'This charger\'s PTU signal is weak (usable up to $upper dBm, below the $hold dBm threshold), but without neighbour data the threshold cannot be loosened. Turn on [Bind PTU on confirm] (a bound PTU ignores the threshold), or move the PTU and sample again.';
  }

  @override
  String get directCalibration_referenceLegacy =>
      'Reference only (older gateway firmware)';

  @override
  String get directCalibration_referenceNoAdv =>
      'Reference only (gateway did not report this charger\'s advertising)';

  @override
  String directCalibration_referenceStaleAdv(int minutes) {
    return 'Reference only (this charger\'s advertising value is over $minutes min old; upper bound from link signal only)';
  }

  @override
  String get directCalibration_referenceUndatedAdv =>
      'Reference only (this charger\'s advertising value has no pick time; upper bound from link signal only)';

  @override
  String get directCalibration_rescanLabel => 'Rescan neighbours';

  @override
  String get directCalibration_saved =>
      'Written to the gateway (kept after reboot)';

  @override
  String directCalibration_selfAdvMinutes(int minutes) {
    return 'This charger\'s advertising value is from a pick $minutes min ago';
  }

  @override
  String directCalibration_selfAdvSeconds(int seconds) {
    return 'This charger\'s advertising value is from a pick $seconds s ago';
  }

  @override
  String get directCalibration_selfAdvUndated =>
      'This charger\'s advertising value has no pick time';

  @override
  String directCalibration_stale(int age, int max, String rescan) {
    return 'Neighbour data is $age s old (over $max s, not counted). Tap [$rescan] to sample again.';
  }

  @override
  String get directCalibration_title => 'Calibrate threshold';

  @override
  String get directCalibration_tooClose =>
      'A neighbour charger is too strong to tell apart by threshold. Bind this PTU after confirming it';

  @override
  String get directModePanel_askBackOffice => 'Ask back office';

  @override
  String directModePanel_autoThreshold(int value, int defaultValue) {
    return 'Auto-connect threshold: $value dBm (default $defaultValue)';
  }

  @override
  String get directModePanel_bindCurrent => 'Bind current PTU';

  @override
  String get directModePanel_bindOnConfirm => 'Bind PTU on confirm';

  @override
  String get directModePanel_bindOnConfirmOff =>
      'Off: no MAC lock. If this charger\'s PTU is off or drops, the gateway may connect to a neighbouring charger\'s PTU';

  @override
  String directModePanel_bindOnConfirmOn(String label) {
    return 'Tapping [$label] saves that PTU\'s MAC to the gateway; it then connects only to it';
  }

  @override
  String directModePanel_bound(String mac) {
    return 'Bound $mac';
  }

  @override
  String directModePanel_boundOnly(String mac) {
    return 'Bound $mac; connects only to it';
  }

  @override
  String directModePanel_calibrateButton(String title, int seconds) {
    return '$title ($seconds s on-site sampling)';
  }

  @override
  String get directModePanel_cancelAction => 'Cancel operation';

  @override
  String directModePanel_candidatesHint(int count) {
    return 'Nearby candidates ($count): tap one to bind the gateway to it, then tap [Identify this charger] to check.';
  }

  @override
  String get directModePanel_cannotBind => 'No PTU connected yet; can\'t bind';

  @override
  String directModePanel_causeBound(String mac) {
    return 'Bound to PTU $mac: the gateway connects only to it. If this charger\'s PTU was replaced, tap [Unbind], then search again.';
  }

  @override
  String directModePanel_causeDefer(String label) {
    return 'PTU not here yet (not installed or no power): tap [$label]. The gateway runs as usual and connects once the PTU powers up.';
  }

  @override
  String get directModePanel_causeDenied =>
      'Nearby PTUs are bound to other chargers (skipped). This charger\'s PTU may not be powered yet.';

  @override
  String get directModePanel_causeHelp =>
      'Still not found: tap [Ask back office]; the back office can see the gateway status and help.';

  @override
  String get directModePanel_causeHousing =>
      'Placement or housing: the PTU must be in the same housing as the gateway; a metal case or a blocked antenna weakens the signal.';

  @override
  String directModePanel_causeNone(int min) {
    return 'No PTU heard. Check this charger\'s PTU power (threshold $min dBm).';
  }

  @override
  String get directModePanel_causePower =>
      'This charger\'s PTU not powered: check its power is on and its light is lit.';

  @override
  String directModePanel_causeWeak(String rssi, int min, String mac) {
    return 'Nearby PTU too weak ($rssi dBm, threshold $min): PTU $mac may belong to a neighbouring charger. Do not loosen the threshold just to connect.';
  }

  @override
  String get directModePanel_collecting =>
      'The gateway is collecting nearby PTUs again, about 5–10 s…';

  @override
  String get directModePanel_currentPick => 'Current pick';

  @override
  String get directModePanel_gatewayBusy => 'Gateway working, please wait…';

  @override
  String get directModePanel_hintConfirm =>
      'Check this PTU is the one blinking, then start monitoring';

  @override
  String get directModePanel_hintIdentify =>
      'Tap [Identify this charger] and check the lights';

  @override
  String get directModePanel_identifyDetailTitle => 'Identify details';

  @override
  String get directModePanel_identifyThis => 'Identify this charger';

  @override
  String get directModePanel_keep => 'Keep';

  @override
  String directModePanel_linkedNow(String mac) {
    return 'Connected now: $mac';
  }

  @override
  String get directModePanel_macLabel => 'Device ID (MAC)';

  @override
  String get directModePanel_moreActions => 'More actions';

  @override
  String get directModePanel_noCandidates =>
      'The gateway reports no nearby candidates. Tap [Search again] or try later.';

  @override
  String get directModePanel_noPick =>
      'No PTU pick from the gateway yet. Tap [Search again].';

  @override
  String get directModePanel_noPtuTitle =>
      'This charger\'s PTU not found: causes and fixes';

  @override
  String get directModePanel_notLinked => 'Gateway not connected to a PTU yet';

  @override
  String get directModePanel_notThis => 'Not this one?';

  @override
  String get directModePanel_pickOther => 'Pick another PTU';

  @override
  String get directModePanel_pickedTitle => 'PTU picked by the gateway';

  @override
  String get directModePanel_readingPick => 'Reading the gateway\'s PTU pick…';

  @override
  String directModePanel_reason(String reason) {
    return 'Pick reason: $reason';
  }

  @override
  String get directModePanel_release => 'Release';

  @override
  String get directModePanel_searchAgain => 'Search again';

  @override
  String get directModePanel_settingsTitle => 'One-to-one advanced settings';

  @override
  String get directModePanel_signalLabel => 'Signal';

  @override
  String get directModePanel_switchToThis => 'Switch to this one';

  @override
  String directModePanel_threshold(int min) {
    return 'Threshold $min dBm';
  }

  @override
  String get directModePanel_thresholdHelp =>
      'The gateway auto-connects only to PTUs stronger than the threshold; a higher value (closer to -20) needs the PTU closer.';

  @override
  String get directModePanel_unbind => 'Unbind';

  @override
  String get directModePanel_unbound => 'Not bound';

  @override
  String get directModePanel_watchLights => 'Tap, then watch the lights';

  @override
  String directMode_ackPlain(String note, String gateway) {
    return '$note; $gateway.';
  }

  @override
  String directMode_ackWithNumber(String note, String number, String gateway) {
    return '$note (#$number); $gateway.';
  }

  @override
  String directMode_advRssi(int rssi) {
    return 'Advertising $rssi dBm (reading link signal…)';
  }

  @override
  String directMode_advStale(int rssi) {
    return '$rssi dBm (advertising)';
  }

  @override
  String get directMode_ambiguous =>
      'PTUs with similar signals nearby. Tap [Identify this charger] to check it is the one in front of you';

  @override
  String get directMode_confirmLabel => 'This one, start setup';

  @override
  String get directMode_hintBoundMissing =>
      'Bound PTU not found. Check its power; if the PTU was replaced, unbind it';

  @override
  String get directMode_hintNoCandidate =>
      'Move closer / check this charger\'s PTU is powered';

  @override
  String get directMode_identifyConfirmTimeout =>
      'Sent. This older gateway can\'t confirm the PTU; watch the charger lights';

  @override
  String get directMode_identifyConfirmed => 'PTU confirmed its light is on';

  @override
  String get directMode_identifyFirstLabel =>
      'Tap [Identify this charger] first';

  @override
  String directMode_identifyFirstText(String confirm) {
    return 'Tap [Identify this charger] to check it is the one in front of you, then tap [$confirm].';
  }

  @override
  String get directMode_identifyNoPtu =>
      'Gateway double-blinks for 4 s; it has no PTU yet, so no PTU will blink.';

  @override
  String get directMode_identifyPending => 'Sent, waiting for the gateway…';

  @override
  String get directMode_identifySent => 'Sent. Watch the lights on the charger';

  @override
  String get directMode_identifySentLine => 'Sent · check lights';

  @override
  String get directMode_identifyUnsupportedPattern =>
      'Gateway sent it; the PTU does not support this light pattern. Watch the charger lights';

  @override
  String get directMode_lineGatewayOnly =>
      'Sent · only the gateway blinks, PTU did not get it';

  @override
  String get directMode_lineOffSent => 'Lights-off command sent';

  @override
  String get directMode_lineStopPtuNotSent =>
      'Gateway stopped identify · PTU lights-off not sent';

  @override
  String get directMode_lineTimeout => 'Sent · PTU unconfirmed';

  @override
  String get directMode_lineUnsupportedPattern => 'Sent · PTU lacks pattern';

  @override
  String directMode_noteGatewayOnly(String reason) {
    return 'Sent: only the gateway is blinking, the PTU did not get it ($reason)';
  }

  @override
  String directMode_noteOffSent(String gateway) {
    return 'Lights-off command sent; $gateway. The PTU does not reply, so check its lights.';
  }

  @override
  String directMode_noteStopPtuNotSent(String gateway, String reason) {
    return '$gateway; PTU lights-off not sent ($reason)';
  }

  @override
  String directMode_noteWithDetail(String head, String detail) {
    return '$head ($detail)';
  }

  @override
  String directMode_ptuFailedBlinking(int seconds, String reason) {
    return 'Gateway is blinking ($seconds s); PTU command not sent ($reason).';
  }

  @override
  String directMode_ptuFailedStop(String reason) {
    return 'Gateway stopped identify; PTU lights-off not sent ($reason).';
  }

  @override
  String get directMode_ptuWriteAmbiguousTarget =>
      'Gateway is linked to several PTUs and none was specified';

  @override
  String get directMode_ptuWriteFailed => 'Gateway failed to write to the PTU';

  @override
  String get directMode_ptuWriteNotConnected =>
      'Gateway is not connected to a PTU yet';

  @override
  String get directMode_ptuWriteOther => 'PTU did not get the command';

  @override
  String get directMode_reasonAmbiguous =>
      'Similar signals nearby; the gateway took the strongest for now';

  @override
  String get directMode_reasonBound =>
      'Bound to this one; the gateway connects only to it';

  @override
  String get directMode_reasonOk => 'Clearly the strongest signal';

  @override
  String get directMode_reasonResume => 'Kept the existing link';

  @override
  String get directMode_remoteGateway =>
      'Back office made the gateway blink (watch the gateway light)';

  @override
  String get directMode_remoteHeadConfirmed =>
      'Back office blinked it · PTU confirmed';

  @override
  String get directMode_remoteHeadGatewayOnly =>
      'Back office blinked gateway · PTU missed it';

  @override
  String get directMode_remoteHeadOffSent => 'Back office sent lights-off';

  @override
  String get directMode_remoteHeadPtuSent => 'Back office sent PTU identify';

  @override
  String get directMode_remoteHeadSent => 'Back office sent · check the lights';

  @override
  String get directMode_remoteHeadStopped => 'Back office stopped identify';

  @override
  String get directMode_remoteHeadTimeout =>
      'Back office sent · no confirmation';

  @override
  String get directMode_remoteHeadUnsupportedPattern =>
      'Back office sent · PTU lacks pattern';

  @override
  String directMode_remoteOffNotSent(String gateway) {
    return 'Back office: $gateway; PTU lights-off not sent';
  }

  @override
  String directMode_remoteOffSent(String gateway) {
    return 'Back office sent PTU lights-off; $gateway';
  }

  @override
  String directMode_remoteSentPtu(String label) {
    return 'Back office sent identify to PTU $label (watch the charger lights)';
  }

  @override
  String get directMode_remoteSentPtuUnnamed =>
      'Back office sent identify to the PTU (watch the charger lights)';

  @override
  String directMode_resultGatewayOnly(String reason) {
    return 'Only the gateway blinks ($reason)';
  }

  @override
  String get directMode_resultIdentifySent => 'PTU identify command sent';

  @override
  String get directMode_resultOffSent => 'PTU lights-off command sent';

  @override
  String get directMode_resultTimeout =>
      'Older gateway got no PTU confirmation';

  @override
  String get directMode_resultUnsupportedPattern =>
      'PTU does not support this light pattern';

  @override
  String directMode_rssiPeak(int rssi) {
    return 'Peak $rssi dBm';
  }

  @override
  String get directMode_rssiReading => 'Reading signal…';

  @override
  String get directMode_settlingLabel => 'Setting up link…';

  @override
  String get directMode_stateBoundMissing => 'Bound PTU not found';

  @override
  String get directMode_stateConnected => 'PTU connected';

  @override
  String get directMode_stateConnecting => 'Connecting to PTU';

  @override
  String get directMode_stateNoCandidate => 'No PTU close enough';

  @override
  String get directMode_stateScanning => 'Looking for the nearest PTU';

  @override
  String directMode_strayBind(String mac) {
    return 'Gateway is bound to PTU $mac';
  }

  @override
  String get directMode_strayBindHint =>
      'This binding was not confirmed on this phone. [Keep]: the gateway connects only to this PTU. [Release]: it picks the nearest PTU again.';

  @override
  String directMode_switched(String mac) {
    return 'Gateway switched to another PTU ($mac). Identify again';
  }

  @override
  String directMode_unbindFailed(String mac) {
    return 'Cancelled, but the gateway\'s temporary binding (PTU $mac) was not removed. You will be asked again next time you enter step 7.';
  }

  @override
  String directMode_unbindRestoreFailed(String restore) {
    return 'Cancelled, but the gateway\'s PTU binding was not restored to $restore. Reconnect this gateway to check the binding.';
  }

  @override
  String directMode_unbindTempRestoreFailed(String mac, String restore) {
    return 'Cancelled, but the gateway\'s temporary binding (PTU $mac) was not restored to the original binding $restore. You will be asked again next time you enter step 7.';
  }

  @override
  String get directMode_waitingLabel =>
      'Waiting for the gateway to connect to a PTU';

  @override
  String get directPickActivity_ambiguousIdentify =>
      'Signals are close. Identify this charger.';

  @override
  String get directPickActivity_boundMissing => 'The bound PTU is not here';

  @override
  String get directPickActivity_connected =>
      'Waiting for the gateway to report its PTU';

  @override
  String get directPickActivity_connecting =>
      'Gateway is connecting to the PTU';

  @override
  String get directPickActivity_foundConfirm =>
      'PTU found. Make sure it is this charger.';

  @override
  String get directPickActivity_foundIdentify =>
      'PTU found. Identify this charger.';

  @override
  String get directPickActivity_gatewayEndpoint => 'Gateway';

  @override
  String get directPickActivity_identifySent =>
      'Identify sent. Check the light.';

  @override
  String get directPickActivity_noCandidate =>
      'No PTU found yet. Check its power.';

  @override
  String get directPickActivity_noStatus => 'No PTU status yet';

  @override
  String get directPickActivity_reading => 'Reading PTU status';

  @override
  String get directPickActivity_scanning => 'Gateway is searching for PTUs';

  @override
  String get directPickActivity_unavailable =>
      'Link not confirmed. Follow the hint to retry.';

  @override
  String environmentSwitch_blocked(String task) {
    return '\"$task\" is running. Switch after it finishes or after tapping [Cancel operation].';
  }

  @override
  String environmentSwitch_blockedPrep(String task) {
    return '\"$task\" is running. Switch after it finishes.';
  }

  @override
  String get environmentSwitch_changeIp => 'Change PC IP';

  @override
  String get environmentSwitch_customNotSet =>
      'Use a custom backend URL (not set)';

  @override
  String environmentSwitch_customUrl(String url) {
    return 'Use a custom backend URL: $url';
  }

  @override
  String get environmentSwitch_editIp => 'You can change the test host IP:';

  @override
  String get environmentSwitch_localNoHost =>
      'Data goes to the test host on this PC (PC IP not set)';

  @override
  String environmentSwitch_localWithHost(String host) {
    return 'Data goes to the test host on this PC ($host)';
  }

  @override
  String get environmentSwitch_noIp =>
      'No test host IP yet. Tap [Auto find] or enter it.';

  @override
  String get environmentSwitch_productionHint => 'Data goes to production.';

  @override
  String get environmentSwitch_productionSheetHint => 'Data goes to production';

  @override
  String get environmentSwitch_sheetSubtitle =>
      'The phone and the connected gateway switch together.';

  @override
  String get environmentSwitch_title => 'Switch environment';

  @override
  String get environmentSwitch_urlLabel => 'Backend URL';

  @override
  String get environmentSwitch_useLocal => 'Use local test';

  @override
  String get environmentSwitch_useUrl => 'Use this URL';

  @override
  String get fieldHelpSheet_demo =>
      'Demo mode sends nothing. Read the info below aloud.';

  @override
  String get fieldHelpSheet_label => 'Ask back office';

  @override
  String get fieldHelpSheet_needsConnection =>
      'You switched back office. Connect to the new one first, then ask again.';

  @override
  String get fieldHelpSheet_noPassword => 'The Wi-Fi password is never sent.';

  @override
  String fieldHelpSheet_queued(String reason) {
    return '⚠ Cannot send now ($reason); the back office cannot see it yet. Read the info below over the phone.';
  }

  @override
  String get fieldHelpSheet_queuedNoReason =>
      'no network / not logged in to the back office';

  @override
  String get fieldHelpSheet_readOut => 'Read to the back office:';

  @override
  String get fieldHelpSheet_resend => 'Resend';

  @override
  String get fieldHelpSheet_sending => 'Notifying the back office…';

  @override
  String get fieldHelpSheet_sent => '✓ Help request reached the back office';

  @override
  String get fieldHelpSheet_unsupported =>
      'The back office can\'t receive online requests yet. Read the info below to the back office by phone.';

  @override
  String fieldReport_backendRefused(String status) {
    return 'Back office refused it (HTTP $status)';
  }

  @override
  String get fieldReport_backendSwitched =>
      'Back office switched; the report was not sent';

  @override
  String get fieldReport_backendUnsupported =>
      'Back office does not support it yet (update the back office)';

  @override
  String fieldReport_helpCode(String code) {
    return 'Situation code: $code';
  }

  @override
  String fieldReport_helpCondition(String label) {
    return 'Situation: $label';
  }

  @override
  String fieldReport_helpError(String error) {
    return 'Error: $error';
  }

  @override
  String fieldReport_helpFirmwareDirect(String fw) {
    return 'Firmware $fw · one-to-one';
  }

  @override
  String fieldReport_helpFirmwareStar(String fw, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PTUs',
      one: '1 PTU',
    );
    return 'Firmware $fw · star, $_temp0';
  }

  @override
  String fieldReport_helpGatewayName(String name) {
    return 'Gateway $name';
  }

  @override
  String fieldReport_helpGatewayNameMac(String name, String tail) {
    return 'Gateway $name (MAC ends $tail)';
  }

  @override
  String get fieldReport_helpNoGateway => 'Not connected to a gateway yet';

  @override
  String fieldReport_helpStationGateway(String site, String gateway) {
    return 'Site $site / gateway $gateway';
  }

  @override
  String fieldReport_helpStationGatewayMac(
    String site,
    String gateway,
    String tail,
  ) {
    return 'Site $site / gateway $gateway (MAC ends $tail)';
  }

  @override
  String fieldReport_helpStep(int step, String label) {
    return 'Now at step $step: $label';
  }

  @override
  String get fieldReport_noNetwork =>
      'No network, or the back office did not answer';

  @override
  String get fieldReport_notLoggedIn => 'Not logged in to the back office';

  @override
  String get fieldReport_removedFromOutbox =>
      'Removed from the phone\'s outbox';

  @override
  String get fieldSupportPanel_askAgain => 'Ask for help again';

  @override
  String get fieldSupportPanel_checkFirst =>
      'Check the current screen and device first, then follow the instructions.';

  @override
  String get fieldSupportPanel_confirmFailed =>
      'Reply not confirmed. Refresh; if the instructions changed, read them before replying.';

  @override
  String get fieldSupportPanel_fetchFailed =>
      'Can\'t get the back office\'s reply right now. Anything below is from last time; refresh or call.';

  @override
  String fieldSupportPanel_instructionHeader(String step) {
    return 'Back office instructions · at step $step';
  }

  @override
  String fieldSupportPanel_instructionHeaderAt(String step, String time) {
    return 'Back office instructions · at step $step · $time';
  }

  @override
  String fieldSupportPanel_instructionTarget(
    String site,
    String gateway,
    String mac,
  ) {
    return 'For: Site $site / gateway $gateway · MAC $mac';
  }

  @override
  String get fieldSupportPanel_notConnected =>
      'Connect to the selected back office first, then check for replies.';

  @override
  String get fieldSupportPanel_otherGateway =>
      'This help record is for another gateway; don\'t follow it. Update the help request so the back office can confirm the current device.';

  @override
  String get fieldSupportPanel_refresh => 'Refresh replies';

  @override
  String get fieldSupportPanel_reopenHint =>
      'After closing, tap [Ask back office] at the top to see replies again.';

  @override
  String get fieldSupportPanel_replying => 'Replying…';

  @override
  String get fieldSupportPanel_resolved => 'Resolved';

  @override
  String get fieldSupportPanel_stateCallSupport =>
      'Call the back office for help';

  @override
  String get fieldSupportPanel_stateHandling => 'Back office is on it';

  @override
  String get fieldSupportPanel_stateLoading => 'Getting help status…';

  @override
  String get fieldSupportPanel_statePending => 'Waiting for the back office';

  @override
  String get fieldSupportPanel_stateResolved => 'You confirmed it\'s solved';

  @override
  String get fieldSupportPanel_stateWaitingField =>
      'Back office sent instructions; follow them, then reply';

  @override
  String get fieldSupportPanel_stillHelp => 'Still need help';

  @override
  String get fieldSupportPanel_unavailable =>
      'Text replies can\'t be shown in the app now. Tell the back office the device and step info below.';

  @override
  String get fieldSupportPanel_updateRequest => 'Update help request';

  @override
  String get gatewayDiscovery_backendNoRecordNote =>
      'The back office has no record of this device. If it is not set up yet, tap [Start setup]; if it is, check the connection and the selected site.';

  @override
  String get gatewayDiscovery_backendOfflineNote =>
      'The back office is not receiving this device. Check power and Wi-Fi; if the network has changed, set up Wi-Fi again.';

  @override
  String get gatewayDiscovery_backendReferenceNote =>
      'Without an identity check on this phone, backend status only matches the same site ID and gateway number. Connect to confirm the device.';

  @override
  String get gatewayDiscovery_backendRefreshNote =>
      'Backend status refreshes every 15 s and covers only the selected backend.';

  @override
  String get gatewayDiscovery_bluetoothConnect => 'Connect';

  @override
  String get gatewayDiscovery_busy => 'Connecting and reading settings…';

  @override
  String get gatewayDiscovery_cancelConnect => 'Cancel';

  @override
  String get gatewayDiscovery_cleanupFailed =>
      'Bluetooth cleanup incomplete. Tap [Retry disconnect].';

  @override
  String get gatewayDiscovery_cleanupIncomplete => 'Cleanup incomplete';

  @override
  String gatewayDiscovery_connectLabel(String title) {
    return 'Start setup: $title';
  }

  @override
  String get gatewayDiscovery_connecting => 'Connecting…';

  @override
  String get gatewayDiscovery_disconnect => 'Disconnect';

  @override
  String get gatewayDiscovery_disconnecting => 'Disconnecting…';

  @override
  String gatewayDiscovery_found(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count gateways',
      one: 'Found 1 gateway',
    );
    return '$_temp0';
  }

  @override
  String gatewayDiscovery_foundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count found',
      one: '1 found',
    );
    return '$_temp0';
  }

  @override
  String gatewayDiscovery_foundPick(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count gateways. Tap the one for this charger',
      one: 'Found 1 gateway. Tap the one for this charger',
    );
    return '$_temp0';
  }

  @override
  String get gatewayDiscovery_gatewayOnlyBoundMissingNote =>
      'Gateway blinked; its bound PTU is not found. Check that PTU is on and nearby';

  @override
  String get gatewayDiscovery_gatewayOnlyHint => 'Gateway blinked · PTU won\'t';

  @override
  String get gatewayDiscovery_gatewayOnlyNoPtuNote =>
      'Gateway blinked; it hears no PTU nearby. Check that the PTU is powered';

  @override
  String get gatewayDiscovery_gatewayOnlyNote =>
      'Gateway blinked; it has no PTU connected, so no PTU blinks';

  @override
  String get gatewayDiscovery_gatewayOnlyPickingNote =>
      'Gateway blinked; it is choosing a PTU. Try again in 3 s';

  @override
  String gatewayDiscovery_gatewayOnlySnack(String title, String note) {
    return '$title: $note';
  }

  @override
  String get gatewayDiscovery_gatewayOnlySwitchedNote =>
      'Gateway blinked; switched to one-to-one and it is looking for its PTU again. Try again shortly';

  @override
  String gatewayDiscovery_gatewayOnlyWeakNote(int best, int min) {
    return 'Gateway blinked; PTU signal too weak (best $best dBm, needs ≥ $min). Move closer or check the antenna';
  }

  @override
  String get gatewayDiscovery_held => 'Connected';

  @override
  String get gatewayDiscovery_holdFailed => 'Connect failed';

  @override
  String gatewayDiscovery_holdFailedText(String title) {
    return 'Can\'t connect to $title. Tap [Connect] to retry';
  }

  @override
  String get gatewayDiscovery_holdLost => 'Disconnected';

  @override
  String gatewayDiscovery_holdLostText(String title) {
    return '$title: Bluetooth link lost. Tap [Connect] to reconnect';
  }

  @override
  String get gatewayDiscovery_identifiedHint => 'Sent';

  @override
  String gatewayDiscovery_identifiedSnack(String title) {
    return '$title: sent';
  }

  @override
  String get gatewayDiscovery_identifyIncomplete =>
      'Identify not finished. Reconnect and try again.';

  @override
  String get gatewayDiscovery_identifyLabel => 'Blink to identify';

  @override
  String gatewayDiscovery_nearbyGroup(int count) {
    return 'Nearby devices ($count)';
  }

  @override
  String get gatewayDiscovery_notConnected => 'Not connected';

  @override
  String get gatewayDiscovery_notFound =>
      'No gateway found nearby. Check power, move closer, and make sure no other phone is connected to it.';

  @override
  String get gatewayDiscovery_pending => 'To verify';

  @override
  String get gatewayDiscovery_pickCardHint =>
      'Select the gateway card to set up, then tap [Connect]';

  @override
  String get gatewayDiscovery_pickFirst => 'Select a gateway first';

  @override
  String get gatewayDiscovery_recentGroup => 'Recently used';

  @override
  String get gatewayDiscovery_retryDisconnect => 'Retry disconnect';

  @override
  String get gatewayDiscovery_retrying => 'None found, searching again…';

  @override
  String get gatewayDiscovery_rssiNote =>
      'RSSI is the Bluetooth signal the phone receives, not the backend online status.';

  @override
  String get gatewayDiscovery_scanFailed =>
      'Search failed. Check Bluetooth, Location and Nearby devices permissions, then retry.';

  @override
  String get gatewayDiscovery_searchAgain => 'Search again';

  @override
  String get gatewayDiscovery_searchPaused => 'Gateway selected, search paused';

  @override
  String get gatewayDiscovery_searching => 'Searching for nearby gateways…';

  @override
  String get gatewayDiscovery_selectNearby => 'Select a nearby gateway';

  @override
  String get gatewayDiscovery_selected => 'Selected';

  @override
  String get gatewayDiscovery_signalLost => 'Signal lost';

  @override
  String get gatewayDiscovery_signalUnknown => 'Signal unknown';

  @override
  String get gatewayDiscovery_startCommissioning => 'Start setup';

  @override
  String get gatewayDiscovery_stopSearch => 'Stop search';

  @override
  String get gatewayDiscovery_stopped =>
      'Search stopped. Tap [Search again] to retry';

  @override
  String get gatewayDiscovery_unconfigured => 'Not set up';

  @override
  String get gatewayIdentity_confirmOnlineLabel => 'Confirm gateway online';

  @override
  String gatewayIdentity_directGatewayPick(String mac) {
    return 'The gateway connected to another gateway nearby ($mac), not a PTU; the app will not treat it as a PTU. Tap [Not this one?] to pick this charger\'s PTU, or move closer to it and tap [Search again].';
  }

  @override
  String gatewayIdentity_idText(int site, int gateway) {
    return 'Site $site · Gateway $gateway';
  }

  @override
  String get gatewayIdentity_leaveTestModeLabel => 'Back to normal mode';

  @override
  String get gatewayIdentity_leavingTestMode =>
      'Switching the gateway back to normal mode (it reboots, about 1 min)';

  @override
  String get gatewayIdentity_leftTestMode =>
      'Gateway is back in normal mode and reconnected. Continue setup.';

  @override
  String gatewayIdentity_macTail(String tail) {
    return 'MAC last 4: $tail';
  }

  @override
  String gatewayIdentity_macTailWithBle(String tail, String ble) {
    return 'MAC last 4: $tail (Bluetooth $ble)';
  }

  @override
  String get gatewayIdentity_resumeUploadLabel => 'Resume upload';

  @override
  String get gatewayIdentity_resumingUpload => 'Resuming data upload';

  @override
  String get gatewayIdentity_testMode =>
      'This gateway is in test mode (test data only, no PTU links). Switch it back to normal mode before setup.';

  @override
  String get gatewayIdentity_testModeActionHint =>
      'The gateway reboots after the switch (about 1 min); the app reconnects and continues by itself.';

  @override
  String gatewayIdentity_testModeStatusHint(String leave) {
    return 'Gateway in test mode (test data only). Tap [$leave].';
  }

  @override
  String get gatewayIdentity_testModeUpload =>
      'Gateway in test mode: it uploads test data only, no PTU data.';

  @override
  String get gatewayIdentity_unconfigured => 'Unconfigured gateway';

  @override
  String get gatewayIdentity_uploadHeld =>
      'Back office link OK. PTU data starts uploading once setup is done (paused for now, which is normal); the app continues by itself';

  @override
  String get gatewayIdentity_uploadHeldStatus =>
      '✓ Connected (uploads after setup)';

  @override
  String gatewayIdentity_uploadPaused(String resume) {
    return 'Gateway is online but data upload is paused: no PTU data is sent. Tap [$resume].';
  }

  @override
  String gatewayIdentity_uploadPausedStatusHint(String resume) {
    return 'Gateway data upload is paused; no PTU data is sent. Tap [$resume].';
  }

  @override
  String get gatewayIdentity_uploadResumed =>
      'Data upload resumed; the gateway is sending PTU data.';

  @override
  String get gatewayModeCard_resumeHint =>
      'After resuming, the gateway sends PTU data at once, without a restart.';

  @override
  String get gatewayNet_connecting => 'Gateway is joining Wi-Fi…';

  @override
  String gatewayNet_discDetail(String kind, int code) {
    return 'Last Wi-Fi drop: $kind (code $code)';
  }

  @override
  String gatewayNet_discDetailAge(String kind, int code, int age) {
    return 'Last Wi-Fi drop: $kind (code $code, $age s ago)';
  }

  @override
  String get gatewayNet_discLeave => 'Gateway left on its own';

  @override
  String get gatewayNet_discNotFound => 'Network not found';

  @override
  String get gatewayNet_discPassword => 'Password may be wrong';

  @override
  String get gatewayNet_discWeak => 'Weak signal or other';

  @override
  String gatewayNet_ok(String wifi) {
    return 'Gateway joined $wifi';
  }

  @override
  String get gatewayNet_problemNotConfigured =>
      'The gateway has no Wi-Fi set up, so it cannot upload data.';

  @override
  String gatewayNet_problemNotFound(String wifi) {
    return 'Gateway cannot find $wifi. Check the name, that it is 2.4 GHz (the gateway does not support 5 GHz), and that the router is nearby.';
  }

  @override
  String gatewayNet_problemPassword(String wifi) {
    return 'Gateway cannot join $wifi: the password may be wrong. Check it (case-sensitive) and enter it again.';
  }

  @override
  String gatewayNet_problemUnknown(String wifi) {
    return 'Gateway cannot join $wifi. The network may be out of range, the password wrong, or it is 5 GHz (the gateway needs 2.4 GHz).';
  }

  @override
  String gatewayNet_problemWeak(String wifi) {
    return 'Gateway cannot join $wifi: the signal may be too weak or the router refused for now. Move the gateway closer to the router, away from metal, and try again.';
  }

  @override
  String get gatewayNet_setFailedNotFound =>
      'New Wi-Fi not joined: the gateway cannot find it. Check the name, that it is 2.4 GHz (no 5 GHz support), and that the router is nearby.';

  @override
  String get gatewayNet_setFailedPassword =>
      'New Wi-Fi not joined: the password may be wrong. Check it (case-sensitive) and retry.';

  @override
  String get gatewayNet_setFailedUnknown =>
      'New Wi-Fi not joined. Check the password and signal, then retry.';

  @override
  String get gatewayNet_setFailedWeak =>
      'New Wi-Fi not joined: the signal may be too weak or the router refused for now. Move the gateway closer to the router and retry.';

  @override
  String gatewayNet_ssidNamed(String ssid) {
    return 'Wi-Fi \"$ssid\"';
  }

  @override
  String get gatewayNet_stateConnecting => 'Connecting (connecting)';

  @override
  String get gatewayNet_stateDisconnected => 'Not connected (disconnected)';

  @override
  String get gatewayNet_stateGotIp => 'Connected (got_ip)';

  @override
  String get gatewayNet_stateUnknown => 'Unknown';

  @override
  String gatewayNet_stateUnknownRaw(String raw) {
    return 'Unknown ($raw)';
  }

  @override
  String gatewayNet_weak(int rssi, int limit) {
    return '⚠ Weak Wi-Fi ($rssi dBm, below $limit dBm); data may drop in and out. Move the gateway closer to the router, away from metal, or add a Wi-Fi extender nearby.';
  }

  @override
  String get gatewayProximity_closeHint =>
      'Two gateways are about equally close. Connect and tap the bulb to confirm';

  @override
  String get gatewayProximity_nearest => 'Nearest';

  @override
  String get gatewayProximity_nearestHint =>
      'This charger\'s gateway usually has the strongest signal. If unsure, tap it, connect, then tap the bulb to see which one blinks';

  @override
  String gatewayReboot_notice(String reason) {
    return 'The gateway just restarted (reason: $reason). This is not a PTU fault; settings already done on the gateway are kept. The app has reconnected: continue from the current step. No need to start over; do not unplug it or tap repeatedly.';
  }

  @override
  String gatewayReboot_noticeMany(String reason, int times) {
    return 'The gateway just restarted (reason: $reason; $times restarts in total). This is not a PTU fault; settings already done on the gateway are kept. The app has reconnected: continue from the current step. No need to start over; do not unplug it or tap repeatedly. If it keeps restarting, take a screenshot and report it.';
  }

  @override
  String get gatewayReboot_reasonBleStackStuck =>
      'Bluetooth got stuck; the gateway restarted itself to recover';

  @override
  String get gatewayReboot_reasonBrownout =>
      'Supply voltage too low (unstable power or weak adapter)';

  @override
  String get gatewayReboot_reasonCpuLockup =>
      'Gateway processor hung; it restarted itself';

  @override
  String get gatewayReboot_reasonDeepSleep => 'Woke from power-saving sleep';

  @override
  String get gatewayReboot_reasonPanic =>
      'Gateway software error; it restarted itself';

  @override
  String get gatewayReboot_reasonPowerGlitch => 'Brief power glitch';

  @override
  String get gatewayReboot_reasonPowerOn => 'Power was cut and restored';

  @override
  String get gatewayReboot_reasonResetButton =>
      'Someone pressed the reset button';

  @override
  String get gatewayReboot_reasonSoftware =>
      'Restart command or settings change';

  @override
  String get gatewayReboot_reasonUnknown => 'Unknown reason';

  @override
  String get gatewayReboot_reasonUsb => 'Reset while connected to a computer';

  @override
  String get gatewayReboot_reasonWatchdog =>
      'Gateway software hung; the watchdog restarted it';

  @override
  String get gatewayReboot_retry =>
      'The last action was interrupted by a gateway restart (not a PTU fault). Tap the same button again to continue.';

  @override
  String gatewaySignal_demoScan(String value) {
    return 'Demo · scan $value';
  }

  @override
  String gatewaySignal_disconnectedLast(String value) {
    return 'Disconnected · last $value';
  }

  @override
  String gatewaySignal_disconnectedScan(String value) {
    return 'Disconnected · scan $value';
  }

  @override
  String gatewaySignal_last(String value) {
    return 'Last $value';
  }

  @override
  String gatewaySignal_line(String status) {
    return 'Phone ↔ gateway: $status';
  }

  @override
  String get gatewaySignal_linkLost =>
      'The phone lost its Bluetooth link to the gateway. Move closer; the app will show how to reconnect.';

  @override
  String get gatewaySignal_noReading => 'no reading';

  @override
  String gatewaySignal_scan(String value) {
    return 'Scan $value';
  }

  @override
  String gatewayStatus_dataAgo(String age) {
    return '$age ago';
  }

  @override
  String gatewayStatus_doneAt(String time) {
    return 'Done $time';
  }

  @override
  String get gatewayStatus_fleetEmpty => 'The back office has no gateways yet.';

  @override
  String get gatewayStatus_fleetTitle => 'Gateways in the back office';

  @override
  String gatewayStatus_gatewayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gateways',
      one: '1 gateway',
    );
    return '$_temp0';
  }

  @override
  String gatewayStatus_heartbeatAgo(String age) {
    return 'Heartbeat $age ago';
  }

  @override
  String get gatewayStatus_hint =>
      'Expand a site, then tap a gateway to view recent data.';

  @override
  String get gatewayStatus_homeCaption =>
      'After setup, check that data reaches the back office';

  @override
  String get gatewayStatus_label => 'View uploaded data';

  @override
  String get gatewayStatus_loading => 'Checking the back office…';

  @override
  String gatewayStatus_name(int site, int gateway) {
    return 'Site $site Gateway $gateway';
  }

  @override
  String get gatewayStatus_nearbyEmpty =>
      'No gateway found nearby. Move closer and tap [Rescan].';

  @override
  String get gatewayStatus_nearbyScanFailed =>
      'Scan failed. Check Bluetooth, Location and Nearby devices permissions, then retry.';

  @override
  String get gatewayStatus_nearbyScanning =>
      'Scanning for nearby gateways (about 8 s)…';

  @override
  String get gatewayStatus_nearbyTitle => 'Nearby gateways (Bluetooth scan)';

  @override
  String get gatewayStatus_nearbyUnconfigured =>
      'Not set up yet, no data to view';

  @override
  String get gatewayStatus_nearbyUnnamed => 'No site ID yet, no data to view';

  @override
  String get gatewayStatus_nearest => 'Nearest';

  @override
  String get gatewayStatus_noData => 'No data yet';

  @override
  String get gatewayStatus_offline => 'Offline';

  @override
  String get gatewayStatus_online => 'Online';

  @override
  String get gatewayStatus_openSettings => 'Open permission settings';

  @override
  String get gatewayStatus_ptuConnected => 'PTU connected';

  @override
  String get gatewayStatus_ptuDisconnected => 'PTU not connected';

  @override
  String get gatewayStatus_recentEmpty =>
      'No setup finished on this phone with this version yet';

  @override
  String get gatewayStatus_recentTitle => 'Recent setups (this phone)';

  @override
  String get gatewayStatus_rescan => 'Rescan';

  @override
  String gatewayStatus_siteGroup(int site) {
    return 'Site $site';
  }

  @override
  String get gatewayStatus_unconfiguredGroup => 'Not set up / site unconfirmed';

  @override
  String get gatewaySwapSheet_assignmentHint => '(replacing old gateway)';

  @override
  String gatewaySwapSheet_assignmentHintTail(String tail) {
    return '(replacing old gateway $tail)';
  }

  @override
  String get gatewaySwapSheet_cancelLabel => 'Cancel replacement';

  @override
  String get gatewaySwapSheet_confirmOk => 'Replace';

  @override
  String gatewaySwapSheet_confirmText(int site, int gateway) {
    return 'This gateway takes over site $site · gateway $gateway. The old gateway must be removed or powered off.';
  }

  @override
  String gatewaySwapSheet_confirmTextTail(int site, int gateway, String tail) {
    return 'This gateway takes over site $site · gateway $gateway. The old gateway ($tail) must be removed or powered off.';
  }

  @override
  String get gatewaySwapSheet_confirmTitle => 'Replace the gateway?';

  @override
  String get gatewaySwapSheet_label => 'This replaces a broken gateway';

  @override
  String gatewaySwapSheet_lastSeen(String age) {
    return 'Last online $age ago';
  }

  @override
  String get gatewaySwapSheet_needsNetwork =>
      'Replacement needs a network connection';

  @override
  String get gatewaySwapSheet_noRecord => 'Never online';

  @override
  String get gatewaySwapSheet_none =>
      'No offline gateway on this site to replace';

  @override
  String gatewaySwapSheet_online(int gateway) {
    return 'Gateway $gateway is online. Power off the old gateway first.';
  }

  @override
  String gatewaySwapSheet_rowTitle(int gateway) {
    return 'Gateway $gateway';
  }

  @override
  String get gatewaySwapSheet_sheetHint =>
      'Only this site\'s offline gateways are listed. The old gateway must be removed or powered off.';

  @override
  String gatewaySwapSheet_sheetTitle(int site) {
    return 'Pick the gateway to replace (Site $site)';
  }

  @override
  String get gatewayTopology_directLabel =>
      'One-to-one mode (1 gateway : 1 PTU)';

  @override
  String get gatewayTopology_directShort => 'One-to-one mode';

  @override
  String get gatewayTopology_starLabel =>
      'Star mode (1 gateway : several PTUs)';

  @override
  String get gatewayTopology_starShort => 'Star mode';

  @override
  String heartbeatActivity_announcement(int received, String message) {
    String _temp0 = intl.Intl.pluralLogic(
      received,
      locale: localeName,
      other: 'Received $received heartbeats.',
      one: 'Received 1 heartbeat.',
    );
    return '$_temp0 $message';
  }

  @override
  String get heartbeatActivity_backOffice => 'Back office';

  @override
  String get heartbeatActivity_confirmed => 'Gateway confirmed online';

  @override
  String get heartbeatActivity_connectingBackend =>
      'Connecting to the back office';

  @override
  String heartbeatActivity_count(int received) {
    return 'Heartbeat $received/2';
  }

  @override
  String get heartbeatActivity_gotOne =>
      'Got 1, waiting for the next heartbeat';

  @override
  String get heartbeatActivity_gotTwo => 'Got 2, checking the upload target';

  @override
  String get heartbeatActivity_notDone => 'Heartbeat check not finished';

  @override
  String get heartbeatActivity_paused =>
      'Check paused. Follow the hint to retry.';

  @override
  String get heartbeatActivity_waitingFirst => 'Waiting for heartbeat 1';

  @override
  String get heartbeatActivity_waitingStart => 'Waiting to start the check';

  @override
  String get homeEntry_backHome => 'Back to home';

  @override
  String get homeEntry_configure => 'Field Setup';

  @override
  String get homeEntry_configureAction => 'Open setup';

  @override
  String get homeEntry_configureDescription =>
      'Install devices, set up Wi-Fi, pair PTUs and confirm data uploads';

  @override
  String get homeEntry_savedProgress =>
      'An unfinished setup is available to continue';

  @override
  String get homeEntry_title => 'Choose an action';

  @override
  String get homeEntry_viewData => 'View Data';

  @override
  String get homeEntry_viewDataAction => 'View data';

  @override
  String get homeEntry_viewDataDescription =>
      'View charging power, efficiency, battery status and faults by site';

  @override
  String get identifyDurationSetting_fieldLabel => 'Seconds (0 or 2–10)';

  @override
  String get identifyDurationSetting_help =>
      'Default 4 s. The gateway and PTU use the same duration. Enter 2–10 s; 0 = light off: the gateway stops identifying and goes back to its normal status light. 1 s is not offered (the PTU\'s 1 s packet keeps the light on).';

  @override
  String get identifyDurationSetting_save => 'Save duration';

  @override
  String get identifyDurationSetting_saveFailed => 'Could not save. Try again.';

  @override
  String identifyDurationSetting_saved(int seconds) {
    return 'Saved: $seconds s';
  }

  @override
  String get identifyDurationSetting_savedOff =>
      'Saved: 0 s (identify light off)';

  @override
  String get identifyDurationSetting_saving => 'Saving…';

  @override
  String get identifyDurationSetting_suffix => 's';

  @override
  String get identifyDurationSetting_title => 'Identify duration';

  @override
  String identify_gatewayBlink(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Gateway double-blinks for $seconds seconds',
      one: 'Gateway double-blinks for 1 second',
    );
    return '$_temp0';
  }

  @override
  String get identify_gatewayLedUnavailable =>
      'Gateway light effect unavailable';

  @override
  String get identify_gatewayStopped =>
      'Gateway stopped identifying; normal light restored';

  @override
  String get identify_ptuOnly => 'PTU only; gateway light unchanged';

  @override
  String get identify_secondsError =>
      'Enter 0 (light off) or a whole number 2–10 (1 keeps the PTU light on, not offered)';

  @override
  String get installReportPanel_resend => 'Resend';

  @override
  String get installReport_demo =>
      'Demo mode: report not sent to the back office';

  @override
  String get installReport_failed => 'Report not sent to the back office';

  @override
  String installReport_failedReason(String reason) {
    return 'Report not sent to the back office: $reason';
  }

  @override
  String get installReport_queued =>
      'Queued; sent automatically when the network is back';

  @override
  String installReport_queuedReason(String reason) {
    return 'Queued; sent automatically when the network is back ($reason)';
  }

  @override
  String get installReport_sending => 'Sending the report to the back office…';

  @override
  String get installReport_sent => 'Report sent to the back office';

  @override
  String installReport_sentAt(String time) {
    return 'Report sent to the back office $time';
  }

  @override
  String get localBackendAddress_hostEmpty => 'Enter the PC\'s IP address';

  @override
  String get localBackendAddress_hostFormat =>
      'Use 4 numbers 0–255, e.g. 192.168.1.187';

  @override
  String get localBackendAddress_hostLastOctet =>
      'The last number cannot be 0 or 255';

  @override
  String get localBackendAddress_hostLoopback =>
      '127.x is the phone itself. Enter the PC\'s LAN IP';

  @override
  String get localBackendAddress_hostNotPrivate =>
      'LAN addresses only (10.x, 172.16–31.x, 192.168.x)';

  @override
  String get localBackendAddress_portRange => 'Port must be 1–65535';

  @override
  String localBackendField_advancedPort(String port) {
    return 'Advanced: port $port';
  }

  @override
  String get localBackendField_autoFind => 'Auto find';

  @override
  String get localBackendField_dbNotReady => 'Database not ready';

  @override
  String localBackendField_filledNotReady(String host) {
    return 'Filled in $host, but its database isn\'t ready. Tap [Test connection] later to check.';
  }

  @override
  String localBackendField_foundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count local backends',
      one: 'Found 1 local backend',
    );
    return '$_temp0';
  }

  @override
  String localBackendField_foundFilled(String host) {
    return '✓ Found local backend $host and filled it in.';
  }

  @override
  String localBackendField_foundNotChosen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count local backends; none chosen.',
      one: 'Found 1 local backend; none chosen.',
    );
    return '$_temp0';
  }

  @override
  String get localBackendField_gettingSubnet =>
      'Getting the phone\'s Wi-Fi subnet…';

  @override
  String get localBackendField_ipLabel => 'PC IP address';

  @override
  String get localBackendField_noPhoneIp =>
      'Can\'t find the phone\'s Wi-Fi IP. Connect the phone to the same Wi-Fi as the PC, then try again.';

  @override
  String localBackendField_notFound(String subnet, String port) {
    return 'No local backend found on $subnet (port $port).';
  }

  @override
  String localBackendField_notFoundTimedOut(String subnet, String port) {
    return 'No local backend found on $subnet (port $port). (Search time limit reached)';
  }

  @override
  String localBackendField_portDefault(String port) {
    return 'Default $port';
  }

  @override
  String get localBackendField_portDialogTitle => 'Local backend port';

  @override
  String get localBackendField_portLabel => 'Port';

  @override
  String get localBackendField_restoreDefault => 'Restore default';

  @override
  String get localBackendField_scanCancelled => 'Search cancelled.';

  @override
  String localBackendField_searching(String host, int done, int total) {
    return 'Searching $host… ($done/$total)';
  }

  @override
  String get localBackendField_testConnection => 'Test connection';

  @override
  String get localBackendField_testing => 'Testing…';

  @override
  String localBackendField_version(String version) {
    return 'Version $version';
  }

  @override
  String localBackendField_willConnect(String url) {
    return 'Will connect to: $url';
  }

  @override
  String get localBackendField_willConnectNone =>
      'Will connect to: (enter a valid IP first)';

  @override
  String get localBackendProbe_degraded =>
      '✗ Reached the local backend, but its database is not ready (HTTP 503). Wait until the Docker local backend has fully started, then retry.';

  @override
  String get localBackendProbe_healthy => '✓ Connected to the local backend';

  @override
  String localBackendProbe_healthyVersion(String version) {
    return '✓ Connected to the local backend (version $version)';
  }

  @override
  String get localBackendProbe_hint =>
      'Check: the phone and PC are on the same Wi-Fi, the Docker local backend is running on the PC, and allow_local_api_lan.ps1 has been run for the PC firewall.';

  @override
  String localBackendProbe_httpError(String status) {
    return '✗ Not the local backend (HTTP $status). Check the PC\'s IP and port.';
  }

  @override
  String localBackendProbe_notBackend(String status) {
    return '✗ Not the local backend (HTTP $status). Another service is on this IP / port; check the PC\'s IP.';
  }

  @override
  String localBackendProbe_timeout(String message) {
    return '✗ Timed out: $message';
  }

  @override
  String localBackendProbe_unreachable(String message) {
    return '✗ Cannot connect: $message';
  }

  @override
  String get mqttTarget_failBleOnly =>
      'The upload target can only be switched on site over Bluetooth, not by remote command.';

  @override
  String get mqttTarget_failBusy =>
      'The gateway is busy with another command. Wait and retry.';

  @override
  String get mqttTarget_failInvalidHost =>
      'Gateway refused the switch: the local backend address must be a private LAN IPv4 (10.x, 172.16–31.x, 192.168.x), not a host name or public IP.';

  @override
  String get mqttTarget_failInvalidParams =>
      'Gateway refused the switch: bad command parameters. Update the app and retry.';

  @override
  String get mqttTarget_failInvalidPort =>
      'Gateway refused the switch: the MQTT port must be a whole number from 1 to 65535.';

  @override
  String get mqttTarget_failInvalidReqId =>
      'The app sent an invalid command number. Reconnect and retry.';

  @override
  String get mqttTarget_failInvalidTarget =>
      'Gateway refused the switch: invalid upload target name. Update the app and retry.';

  @override
  String get mqttTarget_failNoReason =>
      'The gateway refused to switch the upload target (no reason given).';

  @override
  String get mqttTarget_failNotReady =>
      'The gateway is still starting up. Wait a few seconds and retry.';

  @override
  String get mqttTarget_failNvsWrite =>
      'The gateway could not save the setting. The upload target did not change and it did not restart. Retry; report it if this keeps failing.';

  @override
  String get mqttTarget_failOtaInProgress =>
      'The gateway is updating its firmware (OTA). The upload target cannot change until it finishes. Retry later.';

  @override
  String get mqttTarget_failOther =>
      'The gateway refused to switch the upload target.';

  @override
  String get mqttTarget_failOtpInvalid =>
      'Wrong one-time password (OTP); the gateway refused the switch.';

  @override
  String get mqttTarget_failOtpLocked =>
      'Too many wrong OTPs; the gateway is locked for a while. Try again later.';

  @override
  String get mqttTarget_failOtpRequired =>
      'This gateway has one-time passwords (OTP) on. Switching the upload target needs an OTP; contact your admin.';

  @override
  String get mqttTarget_failOtpReused =>
      'This one-time password was already used. Wait for the next OTP and retry.';

  @override
  String get mqttTarget_failTimeNotSynced =>
      'The gateway has OTP on but its clock is not synced (NTP), so it cannot check the OTP. If this Wi-Fi has no internet, switch to a network that does.';

  @override
  String get mqttTarget_failUnknownOp =>
      'This gateway firmware cannot switch the upload target. Update it to 1.7.3 or later.';

  @override
  String mqttTarget_legacyFirmware(String version) {
    return 'This gateway\'s firmware is too old (version $version) and can only send to production. Update it to 1.7.3 or later.';
  }

  @override
  String mqttTarget_localHost(String host) {
    return 'Local $host';
  }

  @override
  String mqttTarget_localHostNotPrivate(String host) {
    return 'The host \"$host\" in the local test host URL is not a private LAN IPv4 address (10.x.x.x, 172.16–31.x.x, 192.168.x.x), so the gateway cannot upload to it. Use the computer\'s LAN IP in the URL.';
  }

  @override
  String mqttTarget_localHostPort(String host, String port) {
    return 'Local $host:$port';
  }

  @override
  String get mqttTarget_localUrlEmpty =>
      'No local test server URL entered, so the gateway\'s upload target cannot be decided.';

  @override
  String mqttTarget_localUrlUnparsable(String url) {
    return 'Cannot read a host from the local test server URL \"$url\". Enter a URL like http://192.168.1.10:18000.';
  }

  @override
  String mqttTarget_plainLocal(String host) {
    return 'the local test host ($host)';
  }

  @override
  String get mqttTarget_plainProduction => 'the production server';

  @override
  String get mqttTarget_production => 'Production';

  @override
  String mqttTarget_productionHostPort(String host, String port) {
    return 'Production $host:$port';
  }

  @override
  String mqttTarget_reportLegacy(String version) {
    return 'Upload target: production (fixed by firmware $version)';
  }

  @override
  String mqttTarget_reportLine(String where) {
    return 'Upload target: $where';
  }

  @override
  String mqttTarget_reportNote(String warning) {
    return 'Note: $warning';
  }

  @override
  String get mqttTarget_reportUnconfirmed => 'Upload target: not confirmed';

  @override
  String get mqttTarget_shipWarning =>
      'This gateway uploads to a local test server. Switch it back to production before shipping.';

  @override
  String get networkCheck_reuseNoWifi => 'The gateway is not on Wi-Fi yet';

  @override
  String get networkCheck_reuseNotUploading =>
      'The gateway has not started uploading data';

  @override
  String get networkCheck_reuseTargetMismatch =>
      'The gateway\'s data does not reach the phone\'s backend yet';

  @override
  String get networkCheck_reuseTestMode => 'The gateway is in test mode';

  @override
  String get networkCheck_reuseUploadPaused =>
      'The gateway\'s data upload is paused';

  @override
  String get networkCheck_stepAlignTarget => 'Match upload target';

  @override
  String get networkCheck_stepChoosePtu => 'Choose PTUs';

  @override
  String get networkCheck_stepChooseSite => 'Choose site';

  @override
  String get networkCheck_stepConfirmUpload => 'Confirm data upload';

  @override
  String get networkCheck_stepFindGateway => 'Find gateway';

  @override
  String get networkCheck_stepNetworkCheck => 'Gateway network check';

  @override
  String get networkCheck_stepPrepare => 'Prepare';

  @override
  String get networkCheck_stepStartMonitoring => 'Start monitoring';

  @override
  String get networkCheck_stepVerifyData => 'Verify data';

  @override
  String networkCheck_targetInvalid(String error) {
    return '$error Tap the environment button at the top right to fix it.';
  }

  @override
  String networkCheck_targetMatch(String current) {
    return 'The gateway sends data to $current, same as the phone';
  }

  @override
  String networkCheck_targetMismatch(String current, String phone) {
    return 'The gateway sends data to $current, but the phone uses $phone.';
  }

  @override
  String get networkCheck_targetProductionFixed =>
      'The gateway sends data to production';

  @override
  String networkCheck_targetUndecidable(String current) {
    return 'The gateway sends data to $current; the app cannot tell from this URL whether it matches.';
  }

  @override
  String get networkCheck_targetUnknown =>
      'Not sure yet where the gateway sends data.';

  @override
  String networkCheck_targetUnknownSync(String place) {
    return 'Not sure yet where the gateway sends data; switch it to $place.';
  }

  @override
  String get networkCheck_uploadAfterTarget =>
      'Checked once the upload target matches';

  @override
  String get networkCheck_uploadAfterWifi =>
      'Checked once the gateway is on Wi-Fi';

  @override
  String get networkCheck_uploadLinkLost =>
      'The phone lost its Bluetooth link to the gateway; cannot confirm.';

  @override
  String get networkCheck_uploadLinkLostHint =>
      'Move closer to the gateway and tap [End and choose another gateway] to reconnect.';

  @override
  String get networkCheck_uploadNotConfirmed =>
      'Data upload not confirmed yet. Tap [Check again].';

  @override
  String get networkCheck_uploadNotStarted =>
      'The gateway has not started uploading data.';

  @override
  String get networkCheck_uploadUnsupported =>
      'Cannot confirm; the final data check checks it again.';

  @override
  String get networkCheck_uploadWaiting =>
      'Waiting for the gateway to start uploading… (up to about 1 minute)';

  @override
  String get networkCheck_uploading => 'Uploading data';

  @override
  String get networkCheck_wifiNotRead =>
      'Gateway network status not read yet. Tap [Check again].';

  @override
  String get networkCheck_wifiReading =>
      'Reading the gateway\'s network status…';

  @override
  String get networkCheck_wifiResetAction => 'Reset Wi-Fi';

  @override
  String networkCheck_wifiUnsupported(String fw) {
    return 'The app cannot read this gateway\'s Wi-Fi (firmware $fw is too old); the final data check checks it again.';
  }

  @override
  String get nextActionGuide_captionBegin => 'Connected. You can start setup.';

  @override
  String get nextActionGuide_captionConnect =>
      'Check the target, then tap connect below';

  @override
  String get nextActionGuide_captionStart => 'Start here';

  @override
  String get protocol_ambiguousTarget =>
      'The gateway is connected to several PTUs and cannot tell which one to identify. Choose a PTU, then retry.';

  @override
  String get protocol_authentication =>
      'Back office login failed or expired. Retry later; if it still fails, contact the administrator to update the app.';

  @override
  String get protocol_backendUnavailable =>
      'The backend is not responding; 60 seconds of automatic retries did not help. Check the backend, then tap [Retry]; the verification progress so far is kept.';

  @override
  String protocol_badResponse(String backend) {
    return 'Cannot read the backend\'s response ($backend).';
  }

  @override
  String protocol_bleErrorCode(String code) {
    return 'Cannot connect to the gateway (Bluetooth error $code). Move closer and retry';
  }

  @override
  String get protocol_bleErrorNoCode =>
      'Cannot connect to the gateway (Bluetooth error). Move closer and retry';

  @override
  String get protocol_bluetoothOff =>
      'Turn on the phone\'s Bluetooth, then retry.';

  @override
  String get protocol_cancelled =>
      'Cancelled. You can retry from the last completed step.';

  @override
  String get protocol_conflict =>
      'This site or number is already in use. Choose another number.';

  @override
  String get protocol_currentBackend => 'the configured backend';

  @override
  String get protocol_directDeferUnconfirmed =>
      'The gateway did not report being in service with uploads resumed, so setup is not finished. Tap [Finish setup now] again; if that still fails, tap [Ask back office].';

  @override
  String get protocol_directNoPtu =>
      'The gateway is not connected to a PTU, so it cannot bind. Wait for the PTU to connect, then try again.';

  @override
  String get protocol_directPickMissing =>
      'The gateway is not connected to a PTU. Check the PTU\'s power, then tap [Search again].';

  @override
  String get protocol_directSwitchFailed =>
      'The gateway has not switched to this PTU in time (it is bound for now). The screen updates once it connects; you can also check the PTU is powered and close, or pick another PTU.';

  @override
  String get protocol_directThresholdNotSaved =>
      'Threshold not saved on the gateway (read-back differs). Retry.';

  @override
  String get protocol_directUnsupported =>
      'This firmware does not support the one-to-one threshold and binding. Update the firmware first (1.7.20 or later).';

  @override
  String get protocol_disconnected =>
      'Connection to the gateway lost. Move closer and reconnect.';

  @override
  String get protocol_expired =>
      'Command expired (phone and gateway clocks differ too much, or it was delayed). Retry';

  @override
  String get protocol_fleetUnconfirmed =>
      'Data uploaded, but the gateway did not report being in monitoring (the app resent the command once), so setup is not finished. Move closer to the gateway and tap [Start data check] to retry; if that still fails, tap [Ask back office].';

  @override
  String get protocol_gatewayBusy =>
      'The gateway is preparing or busy with another operation. Retry shortly.';

  @override
  String get protocol_gatewayFailedNoReason =>
      'The gateway reported a failure (no reason given).';

  @override
  String get protocol_gatewayFailedSeeDetails =>
      'The gateway reported a failure. See the details.';

  @override
  String protocol_gatewayFailedWithCode(String code) {
    return 'The gateway reported a failure: $code';
  }

  @override
  String get protocol_gatewayFull =>
      'This gateway is full. Connect to another gateway.';

  @override
  String protocol_gatewayNotFound(String where, String backend) {
    return 'The backend has no record of this gateway$where. The gateway may upload to another backend (e.g. production), while the app is connected to $backend.';
  }

  @override
  String protocol_gatewayNotFoundCause(
    String where,
    String backend,
    String cause,
  ) {
    return 'The backend has no record of this gateway$where (the app is connected to $backend). $cause';
  }

  @override
  String get protocol_gatewayServiceNotReady =>
      'Gateway Bluetooth service not ready. Try again shortly';

  @override
  String protocol_httpRejected(int status) {
    return 'The backend refused this request (HTTP $status).';
  }

  @override
  String protocol_httpServerError(int status) {
    return 'Backend internal error (HTTP $status). Check the backend logs, then retry.';
  }

  @override
  String get protocol_httpsRequired => 'Production needs a valid HTTPS URL.';

  @override
  String get protocol_identifyDurationUnsupported =>
      'This older gateway does not support the chosen identify seconds. Older versions with PTU identify allow only 1–30 seconds, earlier ones a fixed 6 seconds; for other values (including 0, light off) update the gateway firmware.';

  @override
  String get protocol_identifyNoPtu =>
      'The gateway is not connected to a PTU, so no PTU can blink. Make sure this charger\'s PTU is powered and close, then retry.';

  @override
  String get protocol_identifyUnsupported =>
      'This firmware does not support the identify light. Update the firmware first. The breathing light while connected can still help.';

  @override
  String get protocol_identityArchived =>
      'This gateway was removed (archived) in the back office, so its heartbeats are not recorded. Tap [Rejoin] below; once recording resumes, the online check continues.';

  @override
  String get protocol_incomplete =>
      'Some PTUs are not connected or their data has not arrived. Check each one\'s status, then retry.';

  @override
  String get protocol_invalidIdentifySeconds =>
      'Identify seconds must be 0 (light off) or a whole number 2–10; 1 keeps the PTU light on, so it is not offered.';

  @override
  String get protocol_locationOff =>
      'This Android version needs Location to scan for Bluetooth. Turn on Location, then scan again.';

  @override
  String get protocol_monitorUnconfirmed =>
      'Could not confirm within 30 seconds that the gateway resumed monitoring. Tap [Reconnect and continue] to retry, or [Skip] to verify the data directly.';

  @override
  String protocol_networkUnreachable(String backend) {
    return 'Cannot reach $backend. Check that the phone and the backend PC are on the same Wi-Fi subnet, the PC firewall allows the port, and the backend URL is correct.';
  }

  @override
  String get protocol_newSiteRequired =>
      'Enter a new site ID different from the current site.';

  @override
  String get protocol_noDevices =>
      'No PTU found. Make sure it is powered and close to the gateway, then rescan.';

  @override
  String protocol_notFoundWhere(int site, int gateway) {
    return ' (site $site / gateway $gateway)';
  }

  @override
  String get protocol_otherFailure =>
      'Not completed. Check the device status, then retry.';

  @override
  String get protocol_otpInvalid => 'Wrong one-time password';

  @override
  String get protocol_otpLocked => 'One-time password locked. Try again later';

  @override
  String get protocol_otpRequired =>
      'This gateway requires a one-time password. Contact the administrator.';

  @override
  String get protocol_otpReused => 'One-time password already used';

  @override
  String get protocol_permission =>
      'Bluetooth permission needed. Allow it in system settings, then retry.';

  @override
  String get protocol_phoneLinkLost =>
      'The phone lost its Bluetooth link to the gateway. Move closer and tap [Reconnect and continue]';

  @override
  String get protocol_ptuConnectFailed =>
      'PTU connection failed. Check the PTU\'s power and distance';

  @override
  String get protocol_ptuIdentityMismatch =>
      'The back office\'s PTU identity does not match this selection, or the MAC is missing; verification is not complete. Go back and check this charger\'s PTU; if it still differs, ask the back office for help.';

  @override
  String get protocol_ptuNoResponse => 'PTU not responding';

  @override
  String get protocol_reconnectFailed =>
      'Reconnect failed. Move closer to the gateway and retry, or go back to finding gateways.';

  @override
  String get protocol_replacePending =>
      'The back office registered the new unit, but writing to the device failed. Run setup again; the replacement setting is kept.';

  @override
  String get protocol_replaceUnsupported =>
      'This backend version cannot replace an old unit. Use the next number instead. Device settings unchanged.';

  @override
  String protocol_targetMismatch(String gatewayTarget, String appTarget) {
    return 'The gateway sends its data to $gatewayTarget, but the phone is connected to $appTarget, so the data can never arrive. Verification stopped (no need to wait).\nIn [Connection status] tap [Sync], or tap the environment button at the top right and choose again, so the gateway and the phone use the same place, then verify.';
  }

  @override
  String protocol_targetReadback(String actual, String wanted) {
    return 'After reconnecting, the gateway reports it uploads to $actual, not the requested $wanted. The setting may not have taken effect. In [Connection status] tap reload to check, or sync again.';
  }

  @override
  String get protocol_targetReconnect =>
      'The gateway got the switch command and restarted, but Bluetooth did not reconnect within 45 seconds. Move closer to the gateway, tap [End and choose another gateway], reconnect, then check [Connection status].';

  @override
  String protocol_testModeStuck(String button) {
    return 'The gateway is still in test mode after restarting. Tap [$button] again; if that still fails, tap [Ask back office].';
  }

  @override
  String get protocol_timeNotSynced =>
      'Gateway clock not synced. Without a network, update the firmware over USB first.';

  @override
  String get protocol_timeout =>
      'Timed out. Check the device and network, then retry.';

  @override
  String protocol_unexpected(String detail) {
    return 'Unexpected app error: $detail';
  }

  @override
  String protocol_uploadPaused(String button) {
    return 'The gateway still reports uploads paused. Tap [$button] again; if that still fails, tap [Ask back office].';
  }

  @override
  String get protocol_wifiPasswordNeeded =>
      'The gateway is not on this Wi-Fi, so it cannot be kept. Enter the Wi-Fi password, then tap [Save and continue].';

  @override
  String get protocol_writeFailed =>
      'Writing to the PTU failed (the gateway could not send the identify command). Check the PTU\'s power and distance, then retry.';

  @override
  String ptuRssi_cached(String rssi) {
    return 'Cached $rssi dBm';
  }

  @override
  String ptuRssi_last(String rssi) {
    return 'Last $rssi dBm';
  }

  @override
  String ptuRssi_scan(String rssi) {
    return 'Scan $rssi dBm';
  }

  @override
  String get ptuSelectionTile_blocked => 'Belongs to another gateway';

  @override
  String get ptuSelectionTile_connected => 'Connected';

  @override
  String get ptuSelectionTile_connectedHere => 'Connected to this gateway';

  @override
  String get ptuSelectionTile_detailTitle => 'Details (last failure)';

  @override
  String ptuSelectionTile_infoTooltip(String title) {
    return '$title device info';
  }

  @override
  String ptuSelectionTile_mac(String mac) {
    return 'MAC: $mac';
  }

  @override
  String ptuSelectionTile_name(String name) {
    return 'Name: $name';
  }

  @override
  String get ptuSelectionTile_noReading => 'No reading yet';

  @override
  String get ptuSelectionTile_notConnected => 'Not connected';

  @override
  String get ptuSelectionTile_peripheralNotConnected => 'Not connected';

  @override
  String ptuSelectionTile_readingState(String text) {
    return 'Reading status: $text';
  }

  @override
  String get ptuSelectionTile_reset => 'Reset and add';

  @override
  String ptuSelectionTile_selectSemantic(String title, String mac) {
    return 'Select $title, $mac';
  }

  @override
  String ptuSelectionTile_signal(String value) {
    return 'Signal: $value';
  }

  @override
  String get ptuSelectionTile_snapshotNote =>
      'Values as of opening; see the list for live values.';

  @override
  String ptuSelectionTile_status(String text) {
    return 'Status: $text';
  }

  @override
  String get ptuSelectionTile_unassigned => 'Unassigned PTU';

  @override
  String get recentDataApi_authRefused =>
      'The back office refused this app\'s credential. Contact the administrator to update the app';

  @override
  String recentDataApi_errorText(String reason) {
    return 'Cannot reach the back office ($reason)';
  }

  @override
  String recentDataApi_minutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String recentDataApi_seconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String recentDataApi_secondsAgo(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds ago',
      one: '1 second ago',
    );
    return '$_temp0';
  }

  @override
  String recentDataApi_secondsDecimal(String seconds) {
    return '$seconds seconds';
  }

  @override
  String recentDataApi_summary(int count, String ago) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Latest $ago · $count records',
      one: 'Latest $ago · 1 record',
    );
    return '$_temp0';
  }

  @override
  String get recentDataApi_timeUnknown => 'time unknown';

  @override
  String recentDataPage_ageDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String recentDataPage_ageHours(int n) {
    return '$n h';
  }

  @override
  String recentDataPage_ageMinutes(int n) {
    return '$n min';
  }

  @override
  String recentDataPage_ageSeconds(int n) {
    return '$n s';
  }

  @override
  String recentDataPage_ago(String age) {
    return '$age ago';
  }

  @override
  String get recentDataPage_batteryVoltage => 'Battery Voltage';

  @override
  String get recentDataPage_chargingCurrent => 'Charging Current';

  @override
  String get recentDataPage_current => 'Current';

  @override
  String get recentDataPage_dataTime => 'Data time';

  @override
  String recentDataPage_deviceError(int code) {
    return 'Device error (code $code)';
  }

  @override
  String get recentDataPage_efficiency => 'Efficiency';

  @override
  String get recentDataPage_empty =>
      'The back office has no data from this gateway yet. Wait a moment, then refresh';

  @override
  String recentDataPage_emptyInterval(String interval) {
    return 'The back office has no data from this gateway yet; it uploads about every $interval. Refresh later';
  }

  @override
  String get recentDataPage_errorChargeComplete => 'Charging complete';

  @override
  String get recentDataPage_errorClearComplete => 'Restarting charging';

  @override
  String get recentDataPage_errorCode => 'Error code';

  @override
  String get recentDataPage_errorNone => 'No error';

  @override
  String get recentDataPage_errorPruCharged => 'PRU fully charged';

  @override
  String get recentDataPage_errorPruOc => 'PRU overcurrent';

  @override
  String get recentDataPage_errorPruOt => 'PRU overtemperature';

  @override
  String get recentDataPage_errorPruOv => 'PRU overvoltage';

  @override
  String get recentDataPage_errorPtuComm => 'PTU communication error';

  @override
  String get recentDataPage_errorPtuLpStuck => 'PTU stuck in Low Power';

  @override
  String get recentDataPage_errorPtuOcBus => 'PTU IBUS overcurrent';

  @override
  String get recentDataPage_errorPtuOcI1 => 'PTU I1 overcurrent';

  @override
  String get recentDataPage_errorPtuOcI3 => 'PTU I3 overcurrent';

  @override
  String get recentDataPage_errorPtuOcIn => 'PTU Iin overcurrent';

  @override
  String get recentDataPage_errorPtuOtDcdc => 'PTU DCDC overtemperature';

  @override
  String get recentDataPage_errorPtuOtIc => 'PTU IC overtemperature';

  @override
  String get recentDataPage_errorPtuOtPa => 'PTU PA overtemperature';

  @override
  String get recentDataPage_errorPtuPhase => 'PTU I1/I3 phase fault';

  @override
  String get recentDataPage_errorPtuPtStuck => 'PTU stuck in Power Transfer';

  @override
  String get recentDataPage_errorPtuTimeset => 'PTU Timeset failed';

  @override
  String get recentDataPage_errorUnknown => 'Unknown error';

  @override
  String get recentDataPage_fault => 'PTU reports a fault';

  @override
  String get recentDataPage_faultCode => 'Fault Code';

  @override
  String get recentDataPage_label => 'View recent data';

  @override
  String recentDataPage_latestRest(String state, String clock, String ago) {
    return '$state · $clock ($ago)';
  }

  @override
  String get recentDataPage_latestUnknown => 'Time of the latest row unknown';

  @override
  String recentDataPage_noNewData(String age) {
    return 'No new data for $age';
  }

  @override
  String get recentDataPage_ok => 'Uploading OK';

  @override
  String get recentDataPage_overallEfficiency => 'Overall Efficiency';

  @override
  String get recentDataPage_pruCurrent => 'Current';

  @override
  String get recentDataPage_pruOutputPower => 'PRU Output Power';

  @override
  String get recentDataPage_pruTemperature => 'Receiver temp';

  @override
  String get recentDataPage_ptuInputPower => 'PTU Input Power';

  @override
  String get recentDataPage_ptuTemperature => 'Transmitter temp';

  @override
  String get recentDataPage_shortCharging => 'Charging';

  @override
  String get recentDataPage_shortConfiguration => 'Config';

  @override
  String get recentDataPage_shortCooling => 'Cooling';

  @override
  String get recentDataPage_shortExceeded => 'Out rng';

  @override
  String get recentDataPage_shortFault => 'Fault';

  @override
  String get recentDataPage_shortIdle => 'Idle';

  @override
  String get recentDataPage_shortLowPower => 'Low pwr';

  @override
  String get recentDataPage_shortPowerSave => 'PwrSave';

  @override
  String get recentDataPage_stateConfiguration => 'Configuring';

  @override
  String get recentDataPage_stateCooling => 'Cooling';

  @override
  String get recentDataPage_stateExceededRange => 'PRU out of range';

  @override
  String get recentDataPage_stateLabel => 'State';

  @override
  String get recentDataPage_stateLatchFault => 'Latch fault';

  @override
  String get recentDataPage_stateLocalFault => 'Local fault';

  @override
  String get recentDataPage_stateLowPower => 'Low power';

  @override
  String get recentDataPage_stateOta => 'OTA updating';

  @override
  String get recentDataPage_statePowerSave => 'Power save';

  @override
  String get recentDataPage_statePowerTransfer => 'Charging';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows',
      one: '1 row',
    );
    return '$title ($_temp0)';
  }

  @override
  String get recentDataPage_temperature => 'Temp';

  @override
  String get recentDataPage_time => 'Time';

  @override
  String get recentDataPage_timeUnknown => 'Time unknown';

  @override
  String get recentDataPage_title => 'Recent data';

  @override
  String recentDataPage_trend(int n, String span, String rate) {
    return 'Last $n rows · over $span · $rate rows/s avg';
  }

  @override
  String recentDataPage_trendCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Last $n rows',
      one: 'Last 1 row',
    );
    return '$_temp0';
  }

  @override
  String get recentDataPage_vehicleType => 'Vehicle Type';

  @override
  String get recentDataPage_voltage => 'Voltage';

  @override
  String get recentGateways_archivedLabel =>
      'Archived (removed in back office)';

  @override
  String get recentGateways_configuredLabel => 'Configured';

  @override
  String recentGateways_queryFailed(String detail) {
    return 'Backend status unknown · query failed ($detail)';
  }

  @override
  String get recentGateways_queryTimeout =>
      'Backend status unknown · query timed out (8 s)';

  @override
  String get recentGateways_reportedOffline => 'Backend reports offline';

  @override
  String get recentGateways_reportedOnline => 'Backend reports online';

  @override
  String get recentGateways_shortArchived => 'Backend archived';

  @override
  String get recentGateways_shortNoRecord => 'No backend record';

  @override
  String get recentGateways_shortOffline => 'Backend offline';

  @override
  String get recentGateways_shortOnline => 'Backend online';

  @override
  String get recentGateways_shortUnknown => 'Backend unknown';

  @override
  String get recentGateways_unknown => 'Backend status unknown';

  @override
  String get recentGateways_unknownConflict =>
      'Backend status unknown · back office flags an identity conflict';

  @override
  String recentGateways_unknownDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Backend status unknown · back office has $count records with the same MAC',
      one:
          'Backend status unknown · back office has 1 record with the same MAC',
    );
    return '$_temp0';
  }

  @override
  String get recentGateways_unknownNoHeartbeat =>
      'Backend status unknown · back office has no heartbeat from this MAC';

  @override
  String get recentGateways_unknownUnverified =>
      'Backend status unknown · identity checked after connecting';

  @override
  String get rescueCode_appUnexpected => 'Unexpected app error';

  @override
  String get rescueCode_backendAuth => 'Back office login expired';

  @override
  String get rescueCode_backendDown => 'The app cannot reach the back office';

  @override
  String get rescueCode_bleConnectFail =>
      'Phone cannot connect to the gateway (Bluetooth error)';

  @override
  String get rescueCode_bleLinkDrop =>
      'Phone lost its Bluetooth link to the gateway';

  @override
  String get rescueCode_bleReconnectFail => 'Reconnect failed';

  @override
  String get rescueCode_cmdTimeout => 'Gateway not responding';

  @override
  String get rescueCode_directPick => 'One-to-one PTU pick failed';

  @override
  String get rescueCode_fwTooOld => 'Firmware too old for this feature';

  @override
  String get rescueCode_gwAuthRefused =>
      'Gateway refused the command (one-time password or clock not synced)';

  @override
  String get rescueCode_gwBusy => 'Gateway busy (auto-retried for 20 seconds)';

  @override
  String get rescueCode_gwFull => 'This gateway is full';

  @override
  String get rescueCode_gwLowMemory => 'Gateway low on memory';

  @override
  String get rescueCode_gwNotFound => 'Phone cannot find the gateway';

  @override
  String get rescueCode_gwNotInBackend =>
      'Back office has no data for this gateway';

  @override
  String get rescueCode_gwRebooted => 'Gateway just restarted';

  @override
  String get rescueCode_gwRejected => 'Gateway reported a failure';

  @override
  String get rescueCode_helpOnly => 'No error on screen; asking for help';

  @override
  String get rescueCode_identityConflict =>
      'Site ID already used by another gateway';

  @override
  String get rescueCode_identityReplace =>
      'Replacing the old unit did not finish';

  @override
  String get rescueCode_monitorUnconfirmed =>
      'Gateway monitoring not yet confirmed back on';

  @override
  String get rescueCode_phoneBtOff => 'Phone Bluetooth is off';

  @override
  String get rescueCode_phonePermission =>
      'The app lacks Bluetooth / Location permission';

  @override
  String get rescueCode_ptuConnectFail => 'Gateway cannot connect to the PTU';

  @override
  String get rescueCode_ptuNoResponse => 'PTU not responding';

  @override
  String get rescueCode_ptuNoneFound => 'No PTU found in the scan';

  @override
  String get rescueCode_ptuResidual =>
      'A PTU has an old number or belongs to another gateway';

  @override
  String get rescueCode_ptuWrongDevice =>
      'Number written to another device, or read-back mismatch';

  @override
  String get rescueCode_stepStuck => 'Stuck on one step too long';

  @override
  String get rescueCode_uploadNotStarted =>
      'Wi-Fi connected, but no data has reached the back office yet';

  @override
  String get rescueCode_uploadTarget =>
      'Gateway sends data to the wrong place (not the phone\'s back office)';

  @override
  String get rescueCode_verifyIncomplete => 'Some PTU data has not arrived';

  @override
  String get rescueCode_wifiNotFound => 'Gateway cannot find this Wi-Fi';

  @override
  String get rescueCode_wifiPassword => 'Wi-Fi password may be wrong';

  @override
  String get rescueCode_wifiUnknown => 'Wi-Fi not connected (reason unknown)';

  @override
  String get rescueCode_wifiWeak => 'Weak Wi-Fi signal or access point refused';

  @override
  String get settings_appearance => 'Appearance';

  @override
  String get settings_language => 'Language';

  @override
  String get settings_more => 'More';

  @override
  String get settings_themeDark => 'Dark';

  @override
  String get settings_themeLight => 'Light';

  @override
  String get settings_themeSystem => 'System default';

  @override
  String get starAllowList_beforeFailed =>
      'PTU binding list not written; continuing. If another PTU nearby with the same number holds the connection, some PTUs may fail to be assigned. The list is written again after the data check.';

  @override
  String get starAllowList_failed =>
      'PTU binding list not written. Retry. Until it is written the gateway only checks numbers, so the gateway may still connect to another PTU nearby with the same number.';

  @override
  String starAllowList_foreignIgnored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count other PTUs nearby have the same numbers and are ignored by the gateway (no connection).',
      one:
          '1 other PTU nearby has the same number and is ignored by the gateway (no connection).',
    );
    return '$_temp0';
  }

  @override
  String get starAllowList_reselectHint =>
      'If one of them belongs to this gateway, select it and set up again.';

  @override
  String get starAllowList_retryButton => 'Retry writing the binding list';

  @override
  String get starAllowList_sentenceSeparator => ' ';

  @override
  String get starAllowList_switchFailed =>
      'PTU binding list not written after switching back to star; it is written again after the data check.';

  @override
  String starAllowList_unlistedDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count connected PTUs are not on this gateway\'s binding list; the gateway drops them.',
      one:
          '1 connected PTU is not on this gateway\'s binding list; the gateway drops it.',
    );
    return '$_temp0';
  }

  @override
  String get starAllowList_writing => 'Writing the PTU binding list';

  @override
  String starAllowList_written(String ids) {
    return 'PTU binding list written: $ids (the gateway connects only these; other PTUs nearby with the same numbers are ignored)';
  }

  @override
  String get stationChangeProgress_applying =>
      'After the site ID is applied, the gateway restarts. Stay close; the app reconnects by itself.';

  @override
  String get stationChangeProgress_confirming =>
      'Reconnected. Checking the new site ID and Wi-Fi; it continues by itself when done.';

  @override
  String get stationChangeProgress_restarting =>
      'This is the normal restart after applying the site ID; Bluetooth drops briefly. Stay close; the app reconnects by itself.';

  @override
  String stationChangeProgress_target(int site, int gateway) {
    return 'Site $site · Gateway $gateway';
  }

  @override
  String get stationChange_itemApply => 'Apply site settings';

  @override
  String get stationChange_itemConfirm => 'Check the site ID and Wi-Fi';

  @override
  String get stationChange_itemRestart => 'Restart and reconnect';

  @override
  String get stationChange_noteReconnecting => 'Reconnecting automatically';

  @override
  String get stationChange_noteWaitBoot => 'Waiting for the gateway to start';

  @override
  String get stationChange_titleApplying => 'Applying the site ID, please wait';

  @override
  String get stationChange_titleConfirming => 'Checking the site ID and Wi-Fi';

  @override
  String get stationChange_titleReconnecting => 'Reconnecting to the gateway';

  @override
  String get stationChange_titleRestarting => 'Gateway restarting, please wait';

  @override
  String uiProgressChecklist_doneAt(String time) {
    return 'Done $time';
  }

  @override
  String get uiProgressChecklist_running => 'In progress…';

  @override
  String uiProgressChecklist_runningNote(String note) {
    return 'In progress… $note';
  }

  @override
  String get verifyDiagnosis_causeOtherBackend =>
      'The gateway may upload to another backend (e.g. production).';

  @override
  String get verifyDiagnosis_causeProductionUnknown =>
      'The gateway may not be connected to production MQTT yet, or uploads to another backend (e.g. a local test site).';

  @override
  String verifyDiagnosis_consecutive(int count) {
    return 'Passed $count / 3 in a row.';
  }

  @override
  String get verifyDiagnosis_installNoDetail =>
      'Backend install check failed (no details for this PTU)';

  @override
  String verifyDiagnosis_localHint(String port, String host) {
    return 'Check: the gateway\'s MQTT is connected (tap [Reload] to see), the PC firewall allows TCP $port, the local MQTT broker is running, and the broker certificate includes the PC\'s current IP $host (if DHCP changed the PC\'s IP, regenerate the certificate and switch the gateway to the new IP).';
  }

  @override
  String get verifyDiagnosis_mqttConnected =>
      ' The gateway last reported MQTT connected; it may have just connected and its heartbeat has not arrived yet. Wait a moment and verify again.';

  @override
  String get verifyDiagnosis_mqttDisconnected =>
      ' The gateway last reported MQTT not connected.';

  @override
  String verifyDiagnosis_noData(
    String backend,
    int site,
    int gateway,
    String cause,
  ) {
    return 'The gateway\'s data is not reaching the connected $backend: fleet-status has no heartbeat for site $site / gateway $gateway, and /api/latest has no data. $cause';
  }

  @override
  String verifyDiagnosis_noFleet(int site, int gateway) {
    return 'fleet-status has no heartbeat record for site $site / gateway $gateway.';
  }

  @override
  String get verifyDiagnosis_none => 'none';

  @override
  String verifyDiagnosis_offline(String last) {
    return 'The backend shows the gateway offline (last heartbeat $last).';
  }

  @override
  String verifyDiagnosis_productionHint(String port) {
    return 'Check that the site network can reach production (TCP $port), and tap [Reload] to see if MQTT is connected.';
  }

  @override
  String verifyDiagnosis_ptuLine(int id, String reasons) {
    return 'PTU #$id: $reasons';
  }

  @override
  String verifyDiagnosis_reasonBackendLate(String seconds) {
    return 'Backend data $seconds s late';
  }

  @override
  String get verifyDiagnosis_reasonBadTime => 'Data time unreadable';

  @override
  String verifyDiagnosis_reasonLag(int seconds) {
    return 'Lag $seconds s';
  }

  @override
  String get verifyDiagnosis_reasonLagUnknown => 'Lag unknown';

  @override
  String get verifyDiagnosis_reasonNoBackendData => 'No backend data';

  @override
  String get verifyDiagnosis_reasonNotInLatest =>
      'PTU missing from latest data (/api/latest)';

  @override
  String verifyDiagnosis_reasonNotUpdated(String ts) {
    return 'Data not updated (last $ts)';
  }

  @override
  String get verifyDiagnosis_reasonOffline => 'Offline';

  @override
  String get verifyDiagnosis_roundOk => 'OK this round';

  @override
  String verifyDiagnosis_sameTarget(String target, String state, String hint) {
    return 'The gateway uploads to $target (same backend as the app), but the backend has no heartbeat from it yet, so the gateway is not connected to that MQTT broker yet.$state\n$hint';
  }

  @override
  String get verifyDiagnosis_uploadPaused =>
      'Gateway data upload is paused (tried to resume).';

  @override
  String verifyLivePanel_announceEvery(String text) {
    return 'Every PTU: $text';
  }

  @override
  String get verifyLivePanel_announceNew => 'New data received';

  @override
  String verifyLivePanel_announceNotCounted(String reasons) {
    return 'Data not counted: $reasons';
  }

  @override
  String verifyLivePanel_announceNth(int count) {
    return 'Row $count received';
  }

  @override
  String verifyLivePanel_announcePtu(String who, String text) {
    return '$who: $text';
  }

  @override
  String get verifyLivePanel_announceSeparator => '; ';

  @override
  String get verifyLivePanel_countFull => 'Normal (3 rows reached)';

  @override
  String verifyLivePanel_countNotCounted(int count) {
    return 'Not counted (still $count/3)';
  }

  @override
  String verifyLivePanel_countNth(int count) {
    return 'Row $count';
  }

  @override
  String verifyLivePanel_countRestart(int count) {
    return 'Recounting: $count/3';
  }

  @override
  String get verifyLivePanel_flowBackOffice => 'Back office';

  @override
  String get verifyLivePanel_flowGateway => 'Gateway';

  @override
  String verifyLivePanel_footer(String pace, int seconds) {
    return '$pace · $seconds s left';
  }

  @override
  String get verifyLivePanel_goal => 'Done after 3 normal rows';

  @override
  String verifyLivePanel_pace(int seconds) {
    return 'Checks for new data every $seconds s; done after 3 normal rows';
  }

  @override
  String verifyLivePanel_paceInterval(String interval, String total) {
    return 'About one row every $interval; usually done within $total';
  }

  @override
  String get verifyLivePanel_passed => 'Data uploading normally';

  @override
  String verifyLivePanel_reason(String reasons) {
    return 'Reason: $reasons';
  }

  @override
  String get verifyLivePanel_reasonDefault => 'Failed checks';

  @override
  String get verifyLivePanel_rowBad => 'Abnormal';

  @override
  String get verifyLivePanel_rowOk => 'Normal';

  @override
  String verifyLivePanel_uncountedDetails(int count) {
    return 'Show uncounted rows ($count)';
  }

  @override
  String get verifyLivePanel_waitingFirst => 'Waiting for the first row…';

  @override
  String get verifyLivePanel_waitingNormal =>
      'Waiting for the next normal row…';

  @override
  String get wifiCredentialsForm_forgetButton => 'Forget saved password';

  @override
  String get wifiCredentialsForm_forgetFailed =>
      'The old password was not deleted. Try again; the new password won\'t be saved this time.';

  @override
  String get wifiCredentialsForm_forgotten =>
      'Forgot the saved password for this Wi-Fi.';

  @override
  String get wifiCredentialsForm_gatewayWifiLabel => 'Wi-Fi for the gateway';

  @override
  String get wifiCredentialsForm_hidePassword => 'Hide password';

  @override
  String get wifiCredentialsForm_intro =>
      'Fill in the phone\'s current Wi-Fi name, then enter the password or use a saved one.';

  @override
  String get wifiCredentialsForm_locationOff =>
      'Turn on location services and retry, or enter the Wi-Fi name manually.';

  @override
  String get wifiCredentialsForm_manualButton => 'Enter another network';

  @override
  String get wifiCredentialsForm_noneSelected => 'No Wi-Fi selected';

  @override
  String get wifiCredentialsForm_notRemembered =>
      'Not connected yet; this password was not saved.';

  @override
  String get wifiCredentialsForm_openAppSettings =>
      'Open app permission settings';

  @override
  String get wifiCredentialsForm_passwordHint =>
      'Enter the Wi-Fi password; an open network can be saved without one';

  @override
  String get wifiCredentialsForm_passwordLabel => 'Wi-Fi password';

  @override
  String get wifiCredentialsForm_permissionNeeded =>
      'Reading the Wi-Fi name needs location permission with precise location. Allow it in app settings and retry, or enter the name manually.';

  @override
  String get wifiCredentialsForm_phoneWifiFilled =>
      'Filled in the phone\'s Wi-Fi name. Make sure this network supports 2.4 GHz, and check the password below.';

  @override
  String get wifiCredentialsForm_phoneWifiUnreadable =>
      'Can\'t read the phone\'s current Wi-Fi. Connect the phone to the site network in Wi-Fi settings, then come back and retry, or enter the name manually.';

  @override
  String get wifiCredentialsForm_readSavedFailed =>
      'Can\'t read the saved password right now. Enter it manually.';

  @override
  String get wifiCredentialsForm_readSavedTimeout =>
      'Reading the saved password timed out. Enter it manually.';

  @override
  String get wifiCredentialsForm_readWifiFailed =>
      'Can\'t read the Wi-Fi name right now. Retry or enter it manually.';

  @override
  String get wifiCredentialsForm_readWifiTimeout =>
      'Reading Wi-Fi timed out. Retry or enter the name manually.';

  @override
  String get wifiCredentialsForm_rememberFailed =>
      'Wi-Fi connected, but the password couldn\'t be saved. Enter it again next time.';

  @override
  String get wifiCredentialsForm_rememberPassword =>
      'Remember password (this phone only)';

  @override
  String wifiCredentialsForm_saveHint(String label) {
    return 'Check the Wi-Fi name and password, then tap [$label]';
  }

  @override
  String get wifiCredentialsForm_savedFilled =>
      'Filled in the password saved on this phone. Tap the eye to view it, or edit it.';

  @override
  String get wifiCredentialsForm_showPassword => 'Show password';

  @override
  String get wifiCredentialsForm_ssidHint => 'Enter the Wi-Fi name';

  @override
  String get wifiCredentialsForm_ssidLabel => 'Wi-Fi name (SSID)';

  @override
  String get wifiCredentialsForm_unsupported =>
      'This platform can\'t read the phone\'s Wi-Fi. Enter the name manually.';

  @override
  String get wifiCredentialsForm_usePhoneButton => 'Use phone\'s current Wi-Fi';

  @override
  String get wifiCredentialsForm_usePhoneHint =>
      'Fill in the phone\'s current Wi-Fi';

  @override
  String get wifiCredentialsForm_wifiOff =>
      'Connect the phone to the site network in Wi-Fi settings, then come back and retry, or enter the name manually.';
}
