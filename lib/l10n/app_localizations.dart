import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @androidAppUpdateDialog_cancelDownload.
  ///
  /// In zh, this message translates to:
  /// **'取消下載'**
  String get androidAppUpdateDialog_cancelDownload;

  /// No description provided for @androidAppUpdateDialog_continueInstall.
  ///
  /// In zh, this message translates to:
  /// **'繼續安裝'**
  String get androidAppUpdateDialog_continueInstall;

  /// No description provided for @androidAppUpdateDialog_currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'目前版本：{name}（{code}）'**
  String androidAppUpdateDialog_currentVersion(String name, String code);

  /// Shown when the release has no notes (release notes from the server are shown as is).
  ///
  /// In zh, this message translates to:
  /// **'改善 APP 使用體驗。'**
  String get androidAppUpdateDialog_defaultNotes;

  /// No description provided for @androidAppUpdateDialog_downloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新下載未完成，請確認網路後重試。'**
  String get androidAppUpdateDialog_downloadFailed;

  /// No description provided for @androidAppUpdateDialog_downloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下載 {percent}%'**
  String androidAppUpdateDialog_downloading(int percent);

  /// No description provided for @androidAppUpdateDialog_installFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法開啟系統安裝畫面，請返回 APP 後重試。'**
  String get androidAppUpdateDialog_installFailed;

  /// No description provided for @androidAppUpdateDialog_installerOpened.
  ///
  /// In zh, this message translates to:
  /// **'請在系統畫面確認安裝。若已取消，可再按「繼續安裝」。'**
  String get androidAppUpdateDialog_installerOpened;

  /// No description provided for @androidAppUpdateDialog_integrityFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新檔驗證失敗，請重新下載。'**
  String get androidAppUpdateDialog_integrityFailed;

  /// No description provided for @androidAppUpdateDialog_latestVersion.
  ///
  /// In zh, this message translates to:
  /// **'最新版本：{name}（{code}）'**
  String androidAppUpdateDialog_latestVersion(String name, String code);

  /// No description provided for @androidAppUpdateDialog_permissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'請允許安裝此來源的應用程式，返回後按「繼續安裝」。'**
  String get androidAppUpdateDialog_permissionRequired;

  /// No description provided for @androidAppUpdateDialog_prepareFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法準備更新檔，請確認手機儲存空間後重試。'**
  String get androidAppUpdateDialog_prepareFailed;

  /// No description provided for @androidAppUpdateDialog_redownload.
  ///
  /// In zh, this message translates to:
  /// **'重新下載'**
  String get androidAppUpdateDialog_redownload;

  /// No description provided for @androidAppUpdateDialog_startFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法啟動更新安裝，請聯絡管理人員。'**
  String get androidAppUpdateDialog_startFailed;

  /// No description provided for @androidAppUpdateDialog_title.
  ///
  /// In zh, this message translates to:
  /// **'有新版 APP'**
  String get androidAppUpdateDialog_title;

  /// No description provided for @androidAppUpdateDialog_updateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get androidAppUpdateDialog_updateNow;

  /// No description provided for @androidAppUpdateDialog_verificationFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新檔的版本或簽章驗證失敗，請聯絡管理人員。'**
  String get androidAppUpdateDialog_verificationFailed;

  /// No description provided for @androidAppUpdateDialog_verifying.
  ///
  /// In zh, this message translates to:
  /// **'正在驗證更新檔…'**
  String get androidAppUpdateDialog_verifying;

  /// APP name; keep equal to android res/values*/strings.xml app_name and iOS InfoPlist.strings CFBundleDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'GIOS 設備助手'**
  String get appInfo_title;

  /// No description provided for @assign_assigning.
  ///
  /// In zh, this message translates to:
  /// **'指派中'**
  String get assign_assigning;

  /// No description provided for @assign_assigningId.
  ///
  /// In zh, this message translates to:
  /// **'指派中 #{id}'**
  String assign_assigningId(int id);

  /// Step 8 PTU row result while its number is being written; recognised by assignResultKindOf in every locale.
  ///
  /// In zh, this message translates to:
  /// **'正在指派 #{id}'**
  String assign_assigningResult(int id);

  /// No description provided for @assign_autoHint.
  ///
  /// In zh, this message translates to:
  /// **'系統自動處理中，失敗會自動重試，不用動手'**
  String get assign_autoHint;

  /// No description provided for @assign_busy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器忙碌，稍後重試'**
  String get assign_busy;

  /// No description provided for @assign_doneId.
  ///
  /// In zh, this message translates to:
  /// **'完成 · #{id}'**
  String assign_doneId(int id);

  /// Done, followed by the row's own result text (e.g. 'Connected #3').
  ///
  /// In zh, this message translates to:
  /// **'完成 · {result}'**
  String assign_doneResult(String result);

  /// No description provided for @assign_failed.
  ///
  /// In zh, this message translates to:
  /// **'失敗需處理'**
  String get assign_failed;

  /// Names the retry button below (controller_retryCount).
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{請確認 PTU 電源與距離，再按下方「重試這 {count} 台」}}'**
  String assign_failedHint(int count);

  /// No description provided for @assign_failedReason.
  ///
  /// In zh, this message translates to:
  /// **'失敗需處理：{reason}'**
  String assign_failedReason(String reason);

  /// No description provided for @assign_linkRetry.
  ///
  /// In zh, this message translates to:
  /// **'藍牙連線失敗，自動重試 {retry}/{retries}'**
  String assign_linkRetry(int retry, int retries);

  /// Step 8 PTU row result after the phone lost the gateway; recognised by assignResultKindOf in every locale.
  ///
  /// In zh, this message translates to:
  /// **'尚未指派（手機與閘道器斷線）'**
  String get assign_notAssignedLink;

  /// First part of the one-line run summary.
  ///
  /// In zh, this message translates to:
  /// **'{done}/{total} 完成'**
  String assign_progressDone(int done, int total);

  /// No description provided for @assign_progressFailed.
  ///
  /// In zh, this message translates to:
  /// **'{count} 台失敗需處理'**
  String assign_progressFailed(int count);

  /// No description provided for @assign_progressRetrying.
  ///
  /// In zh, this message translates to:
  /// **'{count} 台自動重試中'**
  String assign_progressRetrying(int count);

  /// Joins the parts of the run summary ('3/5 done, 1 retrying').
  ///
  /// In zh, this message translates to:
  /// **'，'**
  String get assign_progressSeparator;

  /// No description provided for @assign_retry.
  ///
  /// In zh, this message translates to:
  /// **'未完成，自動重試 {retry}/{retries}'**
  String assign_retry(int retry, int retries);

  /// Appended to a named retrying PTU; keep the leading space in English.
  ///
  /// In zh, this message translates to:
  /// **'（{retry}/{retries}）'**
  String assign_retryAttempt(int retry, int retries);

  /// Two PTU names shown, count is the total retrying (3 or more).
  ///
  /// In zh, this message translates to:
  /// **'{names} 等 {count} 台自動重試中'**
  String assign_retryingMany(String names, int count);

  /// No description provided for @assign_retryingOne.
  ///
  /// In zh, this message translates to:
  /// **'{name} 自動重試中{attempt}'**
  String assign_retryingOne(String name, String attempt);

  /// No description provided for @assign_retryingTwo.
  ///
  /// In zh, this message translates to:
  /// **'{names} 自動重試中'**
  String assign_retryingTwo(String names);

  /// Step 8 PTU row status: queued, not started yet.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get assign_waiting;

  /// No description provided for @autoChecklist_linkLost.
  ///
  /// In zh, this message translates to:
  /// **'藍牙斷線，無法確認'**
  String get autoChecklist_linkLost;

  /// Checklist item note (Wi-Fi / back office) for firmware that cannot report its network state.
  ///
  /// In zh, this message translates to:
  /// **'這台韌體無法回報，最後驗證資料時會確認'**
  String get autoChecklist_oldFirmwareLater;

  /// No description provided for @autoChecklist_targetElsewhere.
  ///
  /// In zh, this message translates to:
  /// **'資料送到別的後台，請依下方提示處理'**
  String get autoChecklist_targetElsewhere;

  /// No description provided for @autoChecklist_testMode.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在測試模式，請先切回正常模式'**
  String get autoChecklist_testMode;

  /// No description provided for @autoChecklist_uploadHeld.
  ///
  /// In zh, this message translates to:
  /// **'已連上，完成配置後開始上傳資料'**
  String get autoChecklist_uploadHeld;

  /// No description provided for @autoChecklist_uploadNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'還沒開始上傳資料，請依下方提示處理'**
  String get autoChecklist_uploadNotStarted;

  /// No description provided for @autoChecklist_uploadPaused.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳已暫停，請按下方恢復上傳'**
  String get autoChecklist_uploadPaused;

  /// No description provided for @autoChecklist_uploading.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳中'**
  String get autoChecklist_uploading;

  /// Wi-Fi item note when the SSID is unknown.
  ///
  /// In zh, this message translates to:
  /// **'已連上'**
  String get autoChecklist_wifiConnected;

  /// No description provided for @autoChecklist_wifiFailed.
  ///
  /// In zh, this message translates to:
  /// **'連不上 Wi-Fi，請按下方重設 Wi-Fi'**
  String get autoChecklist_wifiFailed;

  /// No description provided for @autoChecklist_wifiNotSet.
  ///
  /// In zh, this message translates to:
  /// **'還沒設定 Wi-Fi，請按下方設定 Wi-Fi'**
  String get autoChecklist_wifiNotSet;

  /// No description provided for @backendEnvironment_changeHint.
  ///
  /// In zh, this message translates to:
  /// **'連線環境：{label}（沿用上次的設定，可在右上角切換）'**
  String backendEnvironment_changeHint(String label);

  /// Health check detail: the backend URL cannot be parsed.
  ///
  /// In zh, this message translates to:
  /// **'網址無效'**
  String get backendEnvironment_invalidUrl;

  /// Environment name: a custom backend URL.
  ///
  /// In zh, this message translates to:
  /// **'其他網址'**
  String get backendEnvironment_labelCustom;

  /// Environment name: the local test backend on a PC.
  ///
  /// In zh, this message translates to:
  /// **'本地測試'**
  String get backendEnvironment_labelLocal;

  /// The production back office (environment name / where data goes).
  ///
  /// In zh, this message translates to:
  /// **'正式站'**
  String get backendEnvironment_labelProduction;

  /// Why the local test backend cannot be used in a prod / prodtest build.
  ///
  /// In zh, this message translates to:
  /// **'正式版 APP 不能連本地測試站，請改用本地測試版 APK。'**
  String get backendEnvironment_localUnavailable;

  /// No description provided for @backendEnvironment_localUnavailableLabel.
  ///
  /// In zh, this message translates to:
  /// **'本地測試（此版本不可用）'**
  String get backendEnvironment_localUnavailableLabel;

  /// No trailing period: one caller appends a sentence end.
  ///
  /// In zh, this message translates to:
  /// **'此建置缺少後台憑證，請重新建置'**
  String get backendKey_missing;

  /// Connect progress stage.
  ///
  /// In zh, this message translates to:
  /// **'清除舊連線'**
  String get bleGatewayLink_stageClearing;

  /// No description provided for @bleGatewayLink_stageConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在連線閘道器'**
  String get bleGatewayLink_stageConnecting;

  /// No description provided for @bleGatewayLink_stageRescanning.
  ///
  /// In zh, this message translates to:
  /// **'找不到閘道器，重新掃描中'**
  String get bleGatewayLink_stageRescanning;

  /// No description provided for @bleGatewayLink_stageRetry.
  ///
  /// In zh, this message translates to:
  /// **'第 {attempt} 次重試'**
  String bleGatewayLink_stageRetry(int attempt);

  /// No description provided for @commissioning_advancedCheck.
  ///
  /// In zh, this message translates to:
  /// **'進階檢查'**
  String get commissioning_advancedCheck;

  /// No description provided for @commissioning_appVersion.
  ///
  /// In zh, this message translates to:
  /// **'App 版本'**
  String get commissioning_appVersion;

  /// No description provided for @commissioning_archivedConfirmText.
  ///
  /// In zh, this message translates to:
  /// **'站點 {site}／閘道器 {gateway} 在後台已被移除（封存）。封存的閘道器，後台不會記錄它的心跳，配置會停在「確認閘道器上線」。重新加入後會恢復記錄，原本的歷史資料不變。'**
  String commissioning_archivedConfirmText(int site, int gateway);

  /// No description provided for @commissioning_archivedConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器之前在後台被移除（封存），要重新加入嗎？'**
  String get commissioning_archivedConfirmTitle;

  /// No description provided for @commissioning_archivedRejoinLabel.
  ///
  /// In zh, this message translates to:
  /// **'重新加入並繼續'**
  String get commissioning_archivedRejoinLabel;

  /// No description provided for @commissioning_assignFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 台指派失敗：}}'**
  String commissioning_assignFailedCount(int count);

  /// No description provided for @commissioning_assignFailedRow.
  ///
  /// In zh, this message translates to:
  /// **'PTU {id}：{reason}'**
  String commissioning_assignFailedRow(String id, String reason);

  /// hint: an optional note in parentheses, or empty.
  ///
  /// In zh, this message translates to:
  /// **'將配置為 站點 {site} / 閘道器 {gateway}{hint}'**
  String commissioning_assignmentLine(String site, String gateway, String hint);

  /// No description provided for @commissioning_backToGatewaySearch.
  ///
  /// In zh, this message translates to:
  /// **'回到找閘道器'**
  String get commissioning_backToGatewaySearch;

  /// No description provided for @commissioning_backToNetworkCheck.
  ///
  /// In zh, this message translates to:
  /// **'回到網路體檢'**
  String get commissioning_backToNetworkCheck;

  /// No description provided for @commissioning_backToPtuRescan.
  ///
  /// In zh, this message translates to:
  /// **'返回選擇 PTU，由閘道器重新掃描'**
  String get commissioning_backToPtuRescan;

  /// No description provided for @commissioning_backToPtuSelect.
  ///
  /// In zh, this message translates to:
  /// **'返回選擇 PTU'**
  String get commissioning_backToPtuSelect;

  /// No description provided for @commissioning_backToSite.
  ///
  /// In zh, this message translates to:
  /// **'改回站號 {site}'**
  String commissioning_backToSite(int site);

  /// No description provided for @commissioning_backToStationChoice.
  ///
  /// In zh, this message translates to:
  /// **'回到站點選擇'**
  String get commissioning_backToStationChoice;

  /// No description provided for @commissioning_backendUrl.
  ///
  /// In zh, this message translates to:
  /// **'後端網址'**
  String get commissioning_backendUrl;

  /// No description provided for @commissioning_boundPtu.
  ///
  /// In zh, this message translates to:
  /// **'已綁定 PTU'**
  String get commissioning_boundPtu;

  /// No description provided for @commissioning_busyWaitUpTo.
  ///
  /// In zh, this message translates to:
  /// **'處理中 · 最多等待 {seconds} 秒'**
  String commissioning_busyWaitUpTo(int seconds);

  /// No description provided for @commissioning_cancelAction.
  ///
  /// In zh, this message translates to:
  /// **'取消操作'**
  String get commissioning_cancelAction;

  /// Start page main button.
  ///
  /// In zh, this message translates to:
  /// **'檢查並開始'**
  String get commissioning_checkAndStart;

  /// No description provided for @commissioning_checkContinueLabel.
  ///
  /// In zh, this message translates to:
  /// **'繼續設定站點'**
  String get commissioning_checkContinueLabel;

  /// No description provided for @commissioning_checkIntro.
  ///
  /// In zh, this message translates to:
  /// **'先確認閘道器能上網、資料送對地方，再選擇站點。'**
  String get commissioning_checkIntro;

  /// No description provided for @commissioning_checkPassedTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'網路檢查通過，看完請按下方繼續'**
  String get commissioning_checkPassedTaskTitle;

  /// No description provided for @commissioning_checkTargetItem.
  ///
  /// In zh, this message translates to:
  /// **'資料送到哪裡'**
  String get commissioning_checkTargetItem;

  /// More menu item.
  ///
  /// In zh, this message translates to:
  /// **'檢查更新'**
  String get commissioning_checkUpdate;

  /// No description provided for @commissioning_checkUploadItem.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳'**
  String get commissioning_checkUploadItem;

  /// No description provided for @commissioning_checkWifiItem.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的 Wi-Fi'**
  String get commissioning_checkWifiItem;

  /// No description provided for @commissioning_checkingTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在連線並檢查網路，請稍候'**
  String get commissioning_checkingTaskTitle;

  /// More menu item while checking.
  ///
  /// In zh, this message translates to:
  /// **'正在檢查更新…'**
  String get commissioning_checkingUpdate;

  /// No description provided for @commissioning_confirmTargetHint.
  ///
  /// In zh, this message translates to:
  /// **'確認資料上傳目的地'**
  String get commissioning_confirmTargetHint;

  /// No description provided for @commissioning_confirmUploadTitle.
  ///
  /// In zh, this message translates to:
  /// **'確認資料上傳'**
  String get commissioning_confirmUploadTitle;

  /// No description provided for @commissioning_continueCommissioning.
  ///
  /// In zh, this message translates to:
  /// **'繼續配置'**
  String get commissioning_continueCommissioning;

  /// No description provided for @commissioning_copied.
  ///
  /// In zh, this message translates to:
  /// **'已複製，可貼上分享'**
  String get commissioning_copied;

  /// No description provided for @commissioning_copyReport.
  ///
  /// In zh, this message translates to:
  /// **'複製安裝報告'**
  String get commissioning_copyReport;

  /// No description provided for @commissioning_currentMode.
  ///
  /// In zh, this message translates to:
  /// **'目前模式：{mode}'**
  String commissioning_currentMode(String mode);

  /// No description provided for @commissioning_demoBanner.
  ///
  /// In zh, this message translates to:
  /// **'模擬模式 · 不會設定真實設備或驗證正式資料'**
  String get commissioning_demoBanner;

  /// No description provided for @commissioning_demoWifiConnected.
  ///
  /// In zh, this message translates to:
  /// **'已連上'**
  String get commissioning_demoWifiConnected;

  /// No description provided for @commissioning_demoWifiConnecting.
  ///
  /// In zh, this message translates to:
  /// **'剛開機，正在連'**
  String get commissioning_demoWifiConnecting;

  /// No description provided for @commissioning_demoWifiDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'連不上（Wi-Fi 不在附近）'**
  String get commissioning_demoWifiDisconnected;

  /// No description provided for @commissioning_demoWifiLabel.
  ///
  /// In zh, this message translates to:
  /// **'模擬閘道器的 Wi-Fi'**
  String get commissioning_demoWifiLabel;

  /// No description provided for @commissioning_detailsTitle.
  ///
  /// In zh, this message translates to:
  /// **'設備與連線資訊'**
  String get commissioning_detailsTitle;

  /// No description provided for @commissioning_directPickTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'請辨識眼前的充電樁，確認後開始配置'**
  String get commissioning_directPickTaskTitle;

  /// No description provided for @commissioning_directSettings.
  ///
  /// In zh, this message translates to:
  /// **'直連進階設定'**
  String get commissioning_directSettings;

  /// No description provided for @commissioning_doneLabelHead.
  ///
  /// In zh, this message translates to:
  /// **'請在機殼上標示：'**
  String get commissioning_doneLabelHead;

  /// No description provided for @commissioning_doneLabelHint.
  ///
  /// In zh, this message translates to:
  /// **'後台人員靠這個標示找到這台'**
  String get commissioning_doneLabelHint;

  /// label: e.g. 站 80 · 閘道器 2.
  ///
  /// In zh, this message translates to:
  /// **'請在機殼上標示：{label}'**
  String commissioning_doneLabelText(String label);

  /// No description provided for @commissioning_doneMode.
  ///
  /// In zh, this message translates to:
  /// **'模式：{mode}'**
  String commissioning_doneMode(String mode);

  /// No description provided for @commissioning_doneTitle.
  ///
  /// In zh, this message translates to:
  /// **'開通完成'**
  String get commissioning_doneTitle;

  /// No description provided for @commissioning_doneTitleDemo.
  ///
  /// In zh, this message translates to:
  /// **'模擬開通完成'**
  String get commissioning_doneTitleDemo;

  /// No description provided for @commissioning_end.
  ///
  /// In zh, this message translates to:
  /// **'結束'**
  String get commissioning_end;

  /// env: environment label.
  ///
  /// In zh, this message translates to:
  /// **'已切換到{env}。'**
  String commissioning_envSwitched(String env);

  /// No description provided for @commissioning_envSwitchedAutoSync.
  ///
  /// In zh, this message translates to:
  /// **'已切換到{env}。連上閘道器後會自動讓它一起切換。'**
  String commissioning_envSwitchedAutoSync(String env);

  /// No description provided for @commissioning_envSwitchedManualSync.
  ///
  /// In zh, this message translates to:
  /// **'已切換到{env}。連上閘道器後可在「連線狀態」按「同步」。'**
  String commissioning_envSwitchedManualSync(String env);

  /// No description provided for @commissioning_finishingTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在完成設定並確認資料上傳'**
  String get commissioning_finishingTaskTitle;

  /// No description provided for @commissioning_gatewayN.
  ///
  /// In zh, this message translates to:
  /// **'閘道器 {gateway}'**
  String commissioning_gatewayN(int gateway);

  /// No description provided for @commissioning_gatewayNumberComputing.
  ///
  /// In zh, this message translates to:
  /// **'正在計算閘道器編號…'**
  String get commissioning_gatewayNumberComputing;

  /// No description provided for @commissioning_gatewayReports.
  ///
  /// In zh, this message translates to:
  /// **'閘道器自己回報：{line}'**
  String commissioning_gatewayReports(String line);

  /// No description provided for @commissioning_gatewaySwitching.
  ///
  /// In zh, this message translates to:
  /// **'正在把閘道器切到{target}，約 1 分鐘，請留在閘道器旁。'**
  String commissioning_gatewaySwitching(String target);

  /// No description provided for @commissioning_identifyGateway.
  ///
  /// In zh, this message translates to:
  /// **'辨識這台・{seconds} 秒'**
  String commissioning_identifyGateway(int seconds);

  /// No description provided for @commissioning_identifyPile.
  ///
  /// In zh, this message translates to:
  /// **'辨識此樁（PTU 與閘道器閃燈）'**
  String get commissioning_identifyPile;

  /// No description provided for @commissioning_identifyUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'連線時藍燈呼吸；更新韌體後可使用雙閃辨識。'**
  String get commissioning_identifyUnsupported;

  /// No description provided for @commissioning_identityConflictHint.
  ///
  /// In zh, this message translates to:
  /// **'若舊機已拆除或換掉，按〔取代舊機〕由這台接手站 {site}／閘道器 {gateway}；否則請先找出另一台同編號的閘道器，或改用其他站號。'**
  String commissioning_identityConflictHint(int site, int gateway);

  /// No description provided for @commissioning_identityConflictTitle.
  ///
  /// In zh, this message translates to:
  /// **'身分衝突'**
  String get commissioning_identityConflictTitle;

  /// time: formatted in Dart (HH:mm or y/M/d HH:mm).
  ///
  /// In zh, this message translates to:
  /// **'最近確認上傳：{time}'**
  String commissioning_lastUploadConfirmed(String time);

  /// No description provided for @commissioning_liveRssi.
  ///
  /// In zh, this message translates to:
  /// **'動態 RSSI · 每 5 秒更新（順序不變）'**
  String get commissioning_liveRssi;

  /// No description provided for @commissioning_localHint.
  ///
  /// In zh, this message translates to:
  /// **'手機與電腦需連同一個 Wi-Fi；電腦 IP 若變更，可在上方修改或按「自動尋找」。'**
  String get commissioning_localHint;

  /// No description provided for @commissioning_loginAndCheck.
  ///
  /// In zh, this message translates to:
  /// **'登入並確認資料'**
  String get commissioning_loginAndCheck;

  /// No description provided for @commissioning_messageRemaining.
  ///
  /// In zh, this message translates to:
  /// **'{message}（剩餘 {seconds} 秒）'**
  String commissioning_messageRemaining(String message, int seconds);

  /// No description provided for @commissioning_networkCheckTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器網路體檢'**
  String get commissioning_networkCheckTitle;

  /// No description provided for @commissioning_newSiteConfirmText.
  ///
  /// In zh, this message translates to:
  /// **'後台還沒有站號 {site} 的任何閘道器。請確認站號沒有打錯；確定是新站再繼續。'**
  String commissioning_newSiteConfirmText(int site);

  /// No description provided for @commissioning_newSiteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'確定是新站？'**
  String get commissioning_newSiteConfirmTitle;

  /// No description provided for @commissioning_newSiteOk.
  ///
  /// In zh, this message translates to:
  /// **'是新站，使用站號 {site}'**
  String commissioning_newSiteOk(int site);

  /// No description provided for @commissioning_noDataYet.
  ///
  /// In zh, this message translates to:
  /// **'尚無資料'**
  String get commissioning_noDataYet;

  /// No description provided for @commissioning_noPtuFound.
  ///
  /// In zh, this message translates to:
  /// **'未掃到 PTU，請確認 PTU 已上電後重新掃描'**
  String get commissioning_noPtuFound;

  /// No description provided for @commissioning_notConnectedList.
  ///
  /// In zh, this message translates to:
  /// **'尚未連線：{list}'**
  String commissioning_notConnectedList(String list);

  /// No description provided for @commissioning_notLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'尚未登入{env}：站號衝突檢查會先略過，之後需要時會自動登入。'**
  String commissioning_notLoggedIn(String env);

  /// No description provided for @commissioning_notVerifiedSkipped.
  ///
  /// In zh, this message translates to:
  /// **'未驗證（已略過）'**
  String get commissioning_notVerifiedSkipped;

  /// No description provided for @commissioning_numberTakenMac.
  ///
  /// In zh, this message translates to:
  /// **'（閘道器 {taken} 目前登記的 MAC：{mac}）'**
  String commissioning_numberTakenMac(int taken, String mac);

  /// No description provided for @commissioning_numberTakenNextLabel.
  ///
  /// In zh, this message translates to:
  /// **'改用閘道器 {gateway}'**
  String commissioning_numberTakenNextLabel(int gateway);

  /// No description provided for @commissioning_numberTakenOnlineText.
  ///
  /// In zh, this message translates to:
  /// **'閘道器 {taken} 目前在線上，不能取代；如果這台是來換掉它，請先把舊機斷電。'**
  String commissioning_numberTakenOnlineText(int taken);

  /// No description provided for @commissioning_numberTakenOnlyText.
  ///
  /// In zh, this message translates to:
  /// **'站 {site} 的閘道器 {taken} 已被其他設備使用。'**
  String commissioning_numberTakenOnlyText(int site, int taken);

  /// No description provided for @commissioning_numberTakenReplaceHint.
  ///
  /// In zh, this message translates to:
  /// **'若這台是來取代那台舊機（舊機已拆除或斷電），按〔取代舊機〕沿用閘道器 {taken}。'**
  String commissioning_numberTakenReplaceHint(int taken);

  /// No description provided for @commissioning_numberTakenReplaceLabel.
  ///
  /// In zh, this message translates to:
  /// **'取代舊機（沿用閘道器 {taken}）'**
  String commissioning_numberTakenReplaceLabel(int taken);

  /// No description provided for @commissioning_numberTakenText.
  ///
  /// In zh, this message translates to:
  /// **'站 {site} 的閘道器 {taken} 已被其他設備使用，改用閘道器 {gateway}。'**
  String commissioning_numberTakenText(int site, int taken, int gateway);

  /// No description provided for @commissioning_numberTakenTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器編號已被使用'**
  String get commissioning_numberTakenTitle;

  /// No description provided for @commissioning_offlineFirst.
  ///
  /// In zh, this message translates to:
  /// **'先離線配置，稍後驗證資料'**
  String get commissioning_offlineFirst;

  /// Appended to assignmentLine.
  ///
  /// In zh, this message translates to:
  /// **'（離線配號，上線後會再核對）'**
  String get commissioning_offlineNumber;

  /// Appended to assignmentLine.
  ///
  /// In zh, this message translates to:
  /// **'（無法取得同站閘道器清單，暫配 1 號，請上線核對）'**
  String get commissioning_offlineNumberNoList;

  /// No description provided for @commissioning_oneToMany.
  ///
  /// In zh, this message translates to:
  /// **'一對多'**
  String get commissioning_oneToMany;

  /// No description provided for @commissioning_oneToOne.
  ///
  /// In zh, this message translates to:
  /// **'一對一'**
  String get commissioning_oneToOne;

  /// No description provided for @commissioning_onlineAuto.
  ///
  /// In zh, this message translates to:
  /// **'即將自動確認上線，請稍候。'**
  String get commissioning_onlineAuto;

  /// No description provided for @commissioning_onlineFailed.
  ///
  /// In zh, this message translates to:
  /// **'檢查尚未通過。請依提示修正後，按下方按鈕重新檢查。'**
  String get commissioning_onlineFailed;

  /// No description provided for @commissioning_onlineIntro.
  ///
  /// In zh, this message translates to:
  /// **'確認閘道器不只連上 WiFi，後端也持續收到心跳。'**
  String get commissioning_onlineIntro;

  /// No description provided for @commissioning_onlineOffline.
  ///
  /// In zh, this message translates to:
  /// **'目前為離線配置，請選擇確認上線或稍後驗證。'**
  String get commissioning_onlineOffline;

  /// No description provided for @commissioning_onlineRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在確認後台收到心跳，成功後會自動尋找 PTU，請稍候。'**
  String get commissioning_onlineRunning;

  /// No description provided for @commissioning_onlineRunningTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在確認閘道器上線，請稍候'**
  String get commissioning_onlineRunningTaskTitle;

  /// No description provided for @commissioning_onlineTapStart.
  ///
  /// In zh, this message translates to:
  /// **'請按下方按鈕開始檢查。'**
  String get commissioning_onlineTapStart;

  /// No description provided for @commissioning_onlineTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'確認閘道器上線'**
  String get commissioning_onlineTaskTitle;

  /// No description provided for @commissioning_otherSiteLabel.
  ///
  /// In zh, this message translates to:
  /// **'改用其他站號'**
  String get commissioning_otherSiteLabel;

  /// No description provided for @commissioning_otherWifiLabel.
  ///
  /// In zh, this message translates to:
  /// **'改用其他 Wi-Fi'**
  String get commissioning_otherWifiLabel;

  /// No description provided for @commissioning_pickGatewayTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'選擇閘道器'**
  String get commissioning_pickGatewayTaskTitle;

  /// No description provided for @commissioning_powerOffOldFirst.
  ///
  /// In zh, this message translates to:
  /// **'請先確認舊機已斷電，否則後台會再次標記衝突。'**
  String get commissioning_powerOffOldFirst;

  /// No description provided for @commissioning_ptuCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 台}}'**
  String commissioning_ptuCount(int count);

  /// No description provided for @commissioning_ptuOtherGateway.
  ///
  /// In zh, this message translates to:
  /// **'已屬於其他閘道器'**
  String get commissioning_ptuOtherGateway;

  /// No description provided for @commissioning_ptuOutOfRange.
  ///
  /// In zh, this message translates to:
  /// **'編號不在本機範圍，所屬閘道器未確認'**
  String get commissioning_ptuOutOfRange;

  /// No description provided for @commissioning_ptusPerGateway.
  ///
  /// In zh, this message translates to:
  /// **'每台 PTU 數'**
  String get commissioning_ptusPerGateway;

  /// No description provided for @commissioning_recheck.
  ///
  /// In zh, this message translates to:
  /// **'重新檢查'**
  String get commissioning_recheck;

  /// No description provided for @commissioning_recheckIntro.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已更新。等閘道器開始上傳資料，再確認站點（沿用或設定新站點）。'**
  String get commissioning_recheckIntro;

  /// No description provided for @commissioning_reconfigureAll.
  ///
  /// In zh, this message translates to:
  /// **'全部重新配置'**
  String get commissioning_reconfigureAll;

  /// No description provided for @commissioning_reconfigureAllText.
  ///
  /// In zh, this message translates to:
  /// **'已成功指派的台也會重新指派一次，確定要繼續嗎？'**
  String get commissioning_reconfigureAllText;

  /// No description provided for @commissioning_reconfigureAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'全部重新配置？'**
  String get commissioning_reconfigureAllTitle;

  /// No description provided for @commissioning_reconnect.
  ///
  /// In zh, this message translates to:
  /// **'重新連線'**
  String get commissioning_reconnect;

  /// No description provided for @commissioning_reconnectContinue.
  ///
  /// In zh, this message translates to:
  /// **'重新連線並繼續'**
  String get commissioning_reconnectContinue;

  /// No description provided for @commissioning_reconnectVerify.
  ///
  /// In zh, this message translates to:
  /// **'重新連線並驗證'**
  String get commissioning_reconnectVerify;

  /// No description provided for @commissioning_reenter.
  ///
  /// In zh, this message translates to:
  /// **'重新輸入'**
  String get commissioning_reenter;

  /// No description provided for @commissioning_refreshHealth.
  ///
  /// In zh, this message translates to:
  /// **'更新健康狀態'**
  String get commissioning_refreshHealth;

  /// No description provided for @commissioning_rejoinHintText.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器在後台被移除（封存），心跳不會被記錄。按下方「重新加入」後會繼續確認上線。'**
  String get commissioning_rejoinHintText;

  /// No description provided for @commissioning_rejoinLabel.
  ///
  /// In zh, this message translates to:
  /// **'重新加入'**
  String get commissioning_rejoinLabel;

  /// No description provided for @commissioning_replaceFailedText.
  ///
  /// In zh, this message translates to:
  /// **'取代舊機沒有成功，請確認網路後重試'**
  String get commissioning_replaceFailedText;

  /// No description provided for @commissioning_replaceOldKeepNumber.
  ///
  /// In zh, this message translates to:
  /// **'取代舊機（沿用此編號）'**
  String get commissioning_replaceOldKeepNumber;

  /// No description provided for @commissioning_replaceOldLabel.
  ///
  /// In zh, this message translates to:
  /// **'取代舊機'**
  String get commissioning_replaceOldLabel;

  /// No description provided for @commissioning_replacedText.
  ///
  /// In zh, this message translates to:
  /// **'已由這台接手站 {site}／閘道器 {gateway}'**
  String commissioning_replacedText(int site, int gateway);

  /// No description provided for @commissioning_reportSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'全文；也可分享或複製'**
  String get commissioning_reportSubtitle;

  /// No description provided for @commissioning_reportTitle.
  ///
  /// In zh, this message translates to:
  /// **'安裝報告'**
  String get commissioning_reportTitle;

  /// No description provided for @commissioning_reportTitleDemo.
  ///
  /// In zh, this message translates to:
  /// **'模擬安裝報告'**
  String get commissioning_reportTitleDemo;

  /// No description provided for @commissioning_rescanPtus.
  ///
  /// In zh, this message translates to:
  /// **'由閘道器重新掃描 PTU'**
  String get commissioning_rescanPtus;

  /// No description provided for @commissioning_resetInclude.
  ///
  /// In zh, this message translates to:
  /// **'重置並納入'**
  String get commissioning_resetInclude;

  /// No description provided for @commissioning_resetWifi.
  ///
  /// In zh, this message translates to:
  /// **'重設 Wi-Fi'**
  String get commissioning_resetWifi;

  /// No description provided for @commissioning_restart.
  ///
  /// In zh, this message translates to:
  /// **'重新開始'**
  String get commissioning_restart;

  /// Two sentences from other areas joined.
  ///
  /// In zh, this message translates to:
  /// **'{missing}。\n{resume}'**
  String commissioning_resumeMissingKey(String missing, String resume);

  /// No description provided for @commissioning_retryFailed.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{重試這 {count} 台}}'**
  String commissioning_retryFailed(int count);

  /// No description provided for @commissioning_retryReconnect.
  ///
  /// In zh, this message translates to:
  /// **'重試重新連線'**
  String get commissioning_retryReconnect;

  /// No description provided for @commissioning_reuseBlockedTapAbove.
  ///
  /// In zh, this message translates to:
  /// **'要使用此站點，請先按上方「{button}」（目前：{reason}）。'**
  String commissioning_reuseBlockedTapAbove(String button, String reason);

  /// No description provided for @commissioning_reuseBlockedWifi.
  ///
  /// In zh, this message translates to:
  /// **'要使用此站點，閘道器必須先連上 Wi-Fi 並開始上傳資料（目前：{reason}）。請按「{otherWifi}」，或按「{review}」。'**
  String commissioning_reuseBlockedWifi(
    String reason,
    String otherWifi,
    String review,
  );

  /// No description provided for @commissioning_saveNumberTakenText.
  ///
  /// In zh, this message translates to:
  /// **'站點 {site} / 閘道器 {gateway} 目前登記給另一台裝置（MAC {mac}）。'**
  String commissioning_saveNumberTakenText(int site, int gateway, String mac);

  /// No description provided for @commissioning_saveNumberTakenTitle.
  ///
  /// In zh, this message translates to:
  /// **'編號已被使用'**
  String get commissioning_saveNumberTakenTitle;

  /// No description provided for @commissioning_saveWifiLabel.
  ///
  /// In zh, this message translates to:
  /// **'儲存並繼續'**
  String get commissioning_saveWifiLabel;

  /// No description provided for @commissioning_savedGateway.
  ///
  /// In zh, this message translates to:
  /// **'上次配置的閘道器：{name}'**
  String commissioning_savedGateway(String name);

  /// No description provided for @commissioning_scanHelpDirect.
  ///
  /// In zh, this message translates to:
  /// **'由閘道器掃描附近的 PTU，再透過藍牙把清單傳回手機。直連模式：已自動選定訊號最強的一台。RSSI 是閘道器與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。'**
  String get commissioning_scanHelpDirect;

  /// No description provided for @commissioning_scanHelpDirectFlow.
  ///
  /// In zh, this message translates to:
  /// **'由閘道器掃描附近的 PTU，再透過藍牙把清單傳回手機。直連模式：由閘道器自己選最近的 PTU（門檻內最強，或已綁定的那台），這裡只顯示它的選擇；請用「辨識此樁」確認是眼前這台，不是的話按「不是這台？」改選。RSSI 是閘道器與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。'**
  String get commissioning_scanHelpDirectFlow;

  /// No description provided for @commissioning_scanHelpStar.
  ///
  /// In zh, this message translates to:
  /// **'由閘道器掃描附近的 PTU，再透過藍牙把清單傳回手機。最多可選 {max} 台。RSSI 是閘道器與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。'**
  String commissioning_scanHelpStar(int max);

  /// No description provided for @commissioning_scanHelpTitle.
  ///
  /// In zh, this message translates to:
  /// **'掃描說明與完整流程'**
  String get commissioning_scanHelpTitle;

  /// No description provided for @commissioning_setWifi.
  ///
  /// In zh, this message translates to:
  /// **'設定 Wi-Fi'**
  String get commissioning_setWifi;

  /// No description provided for @commissioning_shareFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法開啟分享，可改用複製報告。'**
  String get commissioning_shareFailed;

  /// No description provided for @commissioning_shareReport.
  ///
  /// In zh, this message translates to:
  /// **'分享安裝報告'**
  String get commissioning_shareReport;

  /// No description provided for @commissioning_siteFieldLabel.
  ///
  /// In zh, this message translates to:
  /// **'站號（1–65535）'**
  String get commissioning_siteFieldLabel;

  /// No description provided for @commissioning_siteN.
  ///
  /// In zh, this message translates to:
  /// **'站點 {site}'**
  String commissioning_siteN(int site);

  /// No description provided for @commissioning_siteNumbersFull.
  ///
  /// In zh, this message translates to:
  /// **'站點 {site} 的 1–{max} 號閘道器都已被使用，請確認站點 ID 是否正確。'**
  String commissioning_siteNumbersFull(int site, int max);

  /// No description provided for @commissioning_skipChooseSite.
  ///
  /// In zh, this message translates to:
  /// **'先選擇站點（沿用要等網路正常）'**
  String get commissioning_skipChooseSite;

  /// No description provided for @commissioning_skipNewNote.
  ///
  /// In zh, this message translates to:
  /// **'⚠ 閘道器的網路還沒確認好。設定完新站點後會再確認資料上傳，最後的「驗證資料」也會檢查。'**
  String get commissioning_skipNewNote;

  /// No description provided for @commissioning_skipNewSite.
  ///
  /// In zh, this message translates to:
  /// **'仍要繼續設定新站點（稍後再確認上傳）'**
  String get commissioning_skipNewSite;

  /// No description provided for @commissioning_skipOfflineNewSite.
  ///
  /// In zh, this message translates to:
  /// **'先離線配置新站點（稍後再確認上傳）'**
  String get commissioning_skipOfflineNewSite;

  /// No description provided for @commissioning_skipOnline.
  ///
  /// In zh, this message translates to:
  /// **'暫未確認，先配置 PTU'**
  String get commissioning_skipOnline;

  /// No description provided for @commissioning_skipOnlineHint.
  ///
  /// In zh, this message translates to:
  /// **'略過的話，最後「驗證資料」仍會確認資料有沒有上傳。'**
  String get commissioning_skipOnlineHint;

  /// No description provided for @commissioning_skipStationNote.
  ///
  /// In zh, this message translates to:
  /// **'沒有通過網路體檢時不能沿用目前站點；可以重設 Wi-Fi 或設定新站點。'**
  String get commissioning_skipStationNote;

  /// No description provided for @commissioning_skipThisPtu.
  ///
  /// In zh, this message translates to:
  /// **'略過此台'**
  String get commissioning_skipThisPtu;

  /// No description provided for @commissioning_sortBySignal.
  ///
  /// In zh, this message translates to:
  /// **'依訊號重新排序'**
  String get commissioning_sortBySignal;

  /// No description provided for @commissioning_starAssignTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在配置 PTU 並開始監控'**
  String get commissioning_starAssignTaskTitle;

  /// No description provided for @commissioning_starCountChanged.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{星狀模式每台 PTU 數已改為 {count} 台}}'**
  String commissioning_starCountChanged(int count);

  /// No description provided for @commissioning_starCountTitle.
  ///
  /// In zh, this message translates to:
  /// **'星狀模式：每台 PTU 數'**
  String get commissioning_starCountTitle;

  /// No description provided for @commissioning_starPickTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'請選擇本閘道器負責的 PTU'**
  String get commissioning_starPickTaskTitle;

  /// No description provided for @commissioning_starVerifyTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在確認資料上傳'**
  String get commissioning_starVerifyTaskTitle;

  /// No description provided for @commissioning_startPowerHint.
  ///
  /// In zh, this message translates to:
  /// **'先確認現場 WiFi 路由器與裝置電源已開啟。'**
  String get commissioning_startPowerHint;

  /// No description provided for @commissioning_startTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'登入後台，開始配置'**
  String get commissioning_startTaskTitle;

  /// No description provided for @commissioning_startVerify.
  ///
  /// In zh, this message translates to:
  /// **'開始資料驗證'**
  String get commissioning_startVerify;

  /// No description provided for @commissioning_stationFull.
  ///
  /// In zh, this message translates to:
  /// **'本站閘道器已滿（1–{max} 皆已使用），請確認站點 ID 或改用「{swap}」。'**
  String commissioning_stationFull(int max, String swap);

  /// No description provided for @commissioning_stationHintBlocked.
  ///
  /// In zh, this message translates to:
  /// **'改用其他站號，或先處理上方提示再沿用此站'**
  String get commissioning_stationHintBlocked;

  /// No description provided for @commissioning_stationHintCanUse.
  ///
  /// In zh, this message translates to:
  /// **'請選擇：使用此站點，或改用其他站號'**
  String get commissioning_stationHintCanUse;

  /// No description provided for @commissioning_stationInputTitle.
  ///
  /// In zh, this message translates to:
  /// **'請輸入這台要配置的站號'**
  String get commissioning_stationInputTitle;

  /// No description provided for @commissioning_stationKeep.
  ///
  /// In zh, this message translates to:
  /// **'沿用站點 {site}／閘道器 {gateway}，原站資料不變。'**
  String commissioning_stationKeep(String site, String gateway);

  /// No description provided for @commissioning_stationQuestionTitle.
  ///
  /// In zh, this message translates to:
  /// **'目前站號是 {site}，這台要配置在本站嗎？'**
  String commissioning_stationQuestionTitle(int site);

  /// No description provided for @commissioning_stayOnList.
  ///
  /// In zh, this message translates to:
  /// **'留在清單'**
  String get commissioning_stayOnList;

  /// No description provided for @commissioning_syncFirstHint.
  ///
  /// In zh, this message translates to:
  /// **'按下後會先讓閘道器改送到{place}（重新開機一次），再設定 Wi-Fi。'**
  String commissioning_syncFirstHint(String place);

  /// No description provided for @commissioning_syncTo.
  ///
  /// In zh, this message translates to:
  /// **'讓閘道器改送到{place}（重新開機約 1 分鐘）'**
  String commissioning_syncTo(String place);

  /// No description provided for @commissioning_targetTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'請讓閘道器把資料送到目前的後台'**
  String get commissioning_targetTaskTitle;

  /// No description provided for @commissioning_testModeTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在測試模式，請先切回正常模式'**
  String get commissioning_testModeTaskTitle;

  /// No description provided for @commissioning_topologyAskDirectBound.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器目前是一對一模式（已綁定 PTU {mac}），要改成星狀嗎？\n\n選〔維持一對一〕：APP 改用直連模式，閘道器的設定不變。'**
  String commissioning_topologyAskDirectBound(String mac);

  /// No description provided for @commissioning_topologyAskDirectTitle.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器是一對一模式'**
  String get commissioning_topologyAskDirectTitle;

  /// No description provided for @commissioning_topologyAskDirectUnbound.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器目前是一對一模式（尚未綁定 PTU），要改成星狀嗎？\n\n選〔維持一對一〕：APP 改用直連模式，閘道器的設定不變。'**
  String get commissioning_topologyAskDirectUnbound;

  /// No description provided for @commissioning_topologyAskStarText.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器目前是星狀模式（最多 {max} 台 PTU），要改成一對一嗎？\n\n選〔維持星狀〕：APP 改用星狀模式，閘道器的設定不變。'**
  String commissioning_topologyAskStarText(int max);

  /// No description provided for @commissioning_topologyAskStarTitle.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器是星狀模式'**
  String get commissioning_topologyAskStarTitle;

  /// No description provided for @commissioning_topologyBusy.
  ///
  /// In zh, this message translates to:
  /// **'操作進行中，完成後才能切換。'**
  String get commissioning_topologyBusy;

  /// No description provided for @commissioning_topologyChangeToDirect.
  ///
  /// In zh, this message translates to:
  /// **'改成一對一'**
  String get commissioning_topologyChangeToDirect;

  /// No description provided for @commissioning_topologyChangeToStar.
  ///
  /// In zh, this message translates to:
  /// **'改成星狀'**
  String get commissioning_topologyChangeToStar;

  /// No description provided for @commissioning_topologyKeepDirect.
  ///
  /// In zh, this message translates to:
  /// **'維持一對一'**
  String get commissioning_topologyKeepDirect;

  /// No description provided for @commissioning_topologyKeepStar.
  ///
  /// In zh, this message translates to:
  /// **'維持星狀'**
  String get commissioning_topologyKeepStar;

  /// No description provided for @commissioning_topologyKeptText.
  ///
  /// In zh, this message translates to:
  /// **'APP 已改用{mode}，這台閘道器維持原模式'**
  String commissioning_topologyKeptText(String mode);

  /// No description provided for @commissioning_topologyMenuBusy.
  ///
  /// In zh, this message translates to:
  /// **'操作完成後可切換'**
  String get commissioning_topologyMenuBusy;

  /// No description provided for @commissioning_topologyMenuDirect.
  ///
  /// In zh, this message translates to:
  /// **'直連 · 一對一'**
  String get commissioning_topologyMenuDirect;

  /// No description provided for @commissioning_topologyMenuStar.
  ///
  /// In zh, this message translates to:
  /// **'星狀 · 一對多'**
  String get commissioning_topologyMenuStar;

  /// No description provided for @commissioning_topologyTitle.
  ///
  /// In zh, this message translates to:
  /// **'連接模式'**
  String get commissioning_topologyTitle;

  /// No description provided for @commissioning_updateAfterHome.
  ///
  /// In zh, this message translates to:
  /// **'返回首頁且結束配置後可用'**
  String get commissioning_updateAfterHome;

  /// No description provided for @commissioning_updateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'暫時無法檢查更新，請確認網路後重試'**
  String get commissioning_updateCheckFailed;

  /// No description provided for @commissioning_updateLatest.
  ///
  /// In zh, this message translates to:
  /// **'目前已是最新版本'**
  String get commissioning_updateLatest;

  /// No description provided for @commissioning_uploadBadTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒開始上傳資料，請依下方提示處理'**
  String get commissioning_uploadBadTaskTitle;

  /// No description provided for @commissioning_uploadOngoing.
  ///
  /// In zh, this message translates to:
  /// **'✓ 資料持續上傳（{where}）'**
  String commissioning_uploadOngoing(String where);

  /// No description provided for @commissioning_uploadPausedTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料上傳已暫停，請恢復上傳'**
  String get commissioning_uploadPausedTaskTitle;

  /// No description provided for @commissioning_uploadRateHead.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳頻率由後台控制'**
  String get commissioning_uploadRateHead;

  /// seconds: formatted in Dart, e.g. 30 or 2.5.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳頻率由後台控制（目前每 {seconds} 秒）'**
  String commissioning_uploadRateNow(String seconds);

  /// No description provided for @commissioning_uploadStatusWhere.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳：{status}（{where}）'**
  String commissioning_uploadStatusWhere(String status, String where);

  /// No description provided for @commissioning_uploadWhere.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳：{where}'**
  String commissioning_uploadWhere(String where);

  /// No description provided for @commissioning_useNextFreeNumber.
  ///
  /// In zh, this message translates to:
  /// **'改用下一個可用編號'**
  String get commissioning_useNextFreeNumber;

  /// No description provided for @commissioning_useSiteEmptyLabel.
  ///
  /// In zh, this message translates to:
  /// **'使用站點'**
  String get commissioning_useSiteEmptyLabel;

  /// No description provided for @commissioning_useSiteLabel.
  ///
  /// In zh, this message translates to:
  /// **'使用站點 {site}'**
  String commissioning_useSiteLabel(int site);

  /// No description provided for @commissioning_useStationLabel.
  ///
  /// In zh, this message translates to:
  /// **'使用此站點'**
  String get commissioning_useStationLabel;

  /// No description provided for @commissioning_verifyBackend.
  ///
  /// In zh, this message translates to:
  /// **'驗證後端：{env}'**
  String commissioning_verifyBackend(String env);

  /// No description provided for @commissioning_verifyBackendLocal.
  ///
  /// In zh, this message translates to:
  /// **'驗證後端：{env}（這台電腦上的測試主機）'**
  String commissioning_verifyBackendLocal(String env);

  /// No description provided for @commissioning_verifyLoginTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'請登入後台，確認資料上傳'**
  String get commissioning_verifyLoginTaskTitle;

  /// No description provided for @commissioning_versionBuild.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version} · Build {build}'**
  String commissioning_versionBuild(String version, String build);

  /// No description provided for @commissioning_versionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暫時無法讀取版本'**
  String get commissioning_versionUnavailable;

  /// No description provided for @commissioning_viewNetworkStatus.
  ///
  /// In zh, this message translates to:
  /// **'查看網路狀態'**
  String get commissioning_viewNetworkStatus;

  /// More menu item.
  ///
  /// In zh, this message translates to:
  /// **'查看上傳資料…'**
  String get commissioning_viewUploadData;

  /// No description provided for @commissioning_waitUpTo.
  ///
  /// In zh, this message translates to:
  /// **'最多等待 {seconds} 秒'**
  String commissioning_waitUpTo(int seconds);

  /// No description provided for @commissioning_wifi24Only.
  ///
  /// In zh, this message translates to:
  /// **'閘道器只能用 2.4 GHz 的 Wi-Fi，5 GHz 的網路連不上。'**
  String get commissioning_wifi24Only;

  /// No description provided for @commissioning_wifiBackKeep.
  ///
  /// In zh, this message translates to:
  /// **'不改 Wi-Fi，返回'**
  String get commissioning_wifiBackKeep;

  /// No description provided for @commissioning_wifiBackSite.
  ///
  /// In zh, this message translates to:
  /// **'返回修改站號'**
  String get commissioning_wifiBackSite;

  /// No description provided for @commissioning_wifiFirstPageText.
  ///
  /// In zh, this message translates to:
  /// **'先讓閘道器連上 Wi-Fi，網路正常後再設定站號。'**
  String get commissioning_wifiFirstPageText;

  /// No description provided for @commissioning_wifiOnlyKeep.
  ///
  /// In zh, this message translates to:
  /// **'保留站點 {site}／閘道器 {gateway}，只更新 Wi-Fi。'**
  String commissioning_wifiOnlyKeep(String site, String gateway);

  /// No description provided for @commissioning_wifiPasswordNotSaved.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已連線，但無法記住密碼；下次請重新輸入。'**
  String get commissioning_wifiPasswordNotSaved;

  /// No description provided for @commissioning_wifiProblemTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器沒有連上 Wi-Fi，請設定 Wi-Fi'**
  String get commissioning_wifiProblemTaskTitle;

  /// No description provided for @commissioning_wifiResetConfirm.
  ///
  /// In zh, this message translates to:
  /// **'是，重設 Wi-Fi'**
  String get commissioning_wifiResetConfirm;

  /// No description provided for @commissioning_wifiResetGoHint.
  ///
  /// In zh, this message translates to:
  /// **'按「是，重設 Wi-Fi」將前往 Wi-Fi 設定。'**
  String get commissioning_wifiResetGoHint;

  /// No description provided for @commissioning_wifiResetLater.
  ///
  /// In zh, this message translates to:
  /// **'暫不重設'**
  String get commissioning_wifiResetLater;

  /// No description provided for @commissioning_wifiResetTitle.
  ///
  /// In zh, this message translates to:
  /// **'是否重設 Wi-Fi？'**
  String get commissioning_wifiResetTitle;

  /// No description provided for @commissioning_wifiSavedWaiting.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已儲存，正在等待閘道器恢復資料上傳。確認完成後會自動顯示下一步，請稍候。'**
  String get commissioning_wifiSavedWaiting;

  /// No description provided for @commissioning_wifiTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'設定閘道器的 Wi-Fi'**
  String get commissioning_wifiTaskTitle;

  /// Task title.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已連線，正在確認資料上傳'**
  String get commissioning_wifiUploadWaitTitle;

  /// No description provided for @common_back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get common_back;

  /// No description provided for @common_cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get common_cancel;

  /// No description provided for @common_close.
  ///
  /// In zh, this message translates to:
  /// **'關閉'**
  String get common_close;

  /// No description provided for @common_confirm.
  ///
  /// In zh, this message translates to:
  /// **'確認'**
  String get common_confirm;

  /// No description provided for @common_continue.
  ///
  /// In zh, this message translates to:
  /// **'繼續'**
  String get common_continue;

  /// No description provided for @common_copy.
  ///
  /// In zh, this message translates to:
  /// **'複製'**
  String get common_copy;

  /// Opens or titles the technical details.
  ///
  /// In zh, this message translates to:
  /// **'詳細資訊'**
  String get common_details;

  /// No description provided for @common_done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get common_done;

  /// Joins short status parts on one line (e.g. Online・PTU connected).
  ///
  /// In zh, this message translates to:
  /// **'・'**
  String get common_dotSeparator;

  /// Dismisses a notice.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get common_gotIt;

  /// Language name, always written in that language (same text in every locale).
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get common_languageEnglish;

  /// Language name, always written in that language (same text in every locale).
  ///
  /// In zh, this message translates to:
  /// **'繁體中文'**
  String get common_languageZhHant;

  /// No description provided for @common_later.
  ///
  /// In zh, this message translates to:
  /// **'稍後'**
  String get common_later;

  /// Joins items of a list in a sentence (#1、#2 / #1, #2).
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get common_listSeparator;

  /// No description provided for @common_loading.
  ///
  /// In zh, this message translates to:
  /// **'讀取中…'**
  String get common_loading;

  /// No description provided for @common_ok.
  ///
  /// In zh, this message translates to:
  /// **'確定'**
  String get common_ok;

  /// No description provided for @common_refresh.
  ///
  /// In zh, this message translates to:
  /// **'重新整理'**
  String get common_refresh;

  /// No description provided for @common_retry.
  ///
  /// In zh, this message translates to:
  /// **'重試'**
  String get common_retry;

  /// No description provided for @common_settings.
  ///
  /// In zh, this message translates to:
  /// **'設定'**
  String get common_settings;

  /// No description provided for @common_skip.
  ///
  /// In zh, this message translates to:
  /// **'略過'**
  String get common_skip;

  /// Network request timed out; also shown inside [endpoint · detail] brackets.
  ///
  /// In zh, this message translates to:
  /// **'逾時'**
  String get common_timeout;

  /// No description provided for @common_unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get common_unknown;

  /// No description provided for @connectionStatusPanel_collapse.
  ///
  /// In zh, this message translates to:
  /// **'收合'**
  String get connectionStatusPanel_collapse;

  /// No description provided for @connectionStatusPanel_details.
  ///
  /// In zh, this message translates to:
  /// **'技術細節'**
  String get connectionStatusPanel_details;

  /// No description provided for @connectionStatusPanel_expand.
  ///
  /// In zh, this message translates to:
  /// **'展開'**
  String get connectionStatusPanel_expand;

  /// No description provided for @connectionStatusPanel_gatewayRow.
  ///
  /// In zh, this message translates to:
  /// **'閘道器 → 資料上傳'**
  String get connectionStatusPanel_gatewayRow;

  /// No description provided for @connectionStatusPanel_notNow.
  ///
  /// In zh, this message translates to:
  /// **'先不要'**
  String get connectionStatusPanel_notNow;

  /// No description provided for @connectionStatusPanel_phoneRow.
  ///
  /// In zh, this message translates to:
  /// **'手機 → 後端'**
  String get connectionStatusPanel_phoneRow;

  /// No description provided for @connectionStatusPanel_reload.
  ///
  /// In zh, this message translates to:
  /// **'重新讀取'**
  String get connectionStatusPanel_reload;

  /// No description provided for @connectionStatusPanel_switchBody.
  ///
  /// In zh, this message translates to:
  /// **'閘道器會改把資料送到{target}，並重新開機約 1 分鐘，期間請留在閘道器旁。'**
  String connectionStatusPanel_switchBody(String target);

  /// No description provided for @connectionStatusPanel_switchButton.
  ///
  /// In zh, this message translates to:
  /// **'切換'**
  String get connectionStatusPanel_switchButton;

  /// No description provided for @connectionStatusPanel_switchTitle.
  ///
  /// In zh, this message translates to:
  /// **'同時切換閘道器？'**
  String get connectionStatusPanel_switchTitle;

  /// No description provided for @connectionStatusPanel_sync.
  ///
  /// In zh, this message translates to:
  /// **'同步'**
  String get connectionStatusPanel_sync;

  /// No description provided for @connectionStatusPanel_title.
  ///
  /// In zh, this message translates to:
  /// **'連線狀態'**
  String get connectionStatusPanel_title;

  /// No description provided for @connectionStatus_detailBootCount.
  ///
  /// In zh, this message translates to:
  /// **'閘道器開機次數：{count}'**
  String connectionStatus_detailBootCount(int count);

  /// No description provided for @connectionStatus_detailDemo.
  ///
  /// In zh, this message translates to:
  /// **'模擬'**
  String get connectionStatus_detailDemo;

  /// No description provided for @connectionStatus_detailFirmware.
  ///
  /// In zh, this message translates to:
  /// **'韌體版本：{version}'**
  String connectionStatus_detailFirmware(String version);

  /// Start of the gateway network line; technical tails (· IP …, · signal …) follow.
  ///
  /// In zh, this message translates to:
  /// **'閘道器網路：Wi-Fi「{ssid}」'**
  String connectionStatus_detailGatewayNet(String ssid);

  /// No description provided for @connectionStatus_detailHealth.
  ///
  /// In zh, this message translates to:
  /// **'後端健康檢查（GET /healthz）：{result}'**
  String connectionStatus_detailHealth(String result);

  /// Appended right after the boot count.
  ///
  /// In zh, this message translates to:
  /// **'（上次開機原因：{reason}）'**
  String connectionStatus_detailLastReset(String reason);

  /// No description provided for @connectionStatus_detailLocalMqttCheck.
  ///
  /// In zh, this message translates to:
  /// **'本地 MQTT 連不上時請確認：電腦防火牆已開放 TCP {port}、本地 MQTT broker 已啟動，且 broker 憑證包含 {host}。'**
  String connectionStatus_detailLocalMqttCheck(String port, String host);

  /// No description provided for @connectionStatus_detailModeNormal.
  ///
  /// In zh, this message translates to:
  /// **'閘道器模式：正常'**
  String get connectionStatus_detailModeNormal;

  /// No description provided for @connectionStatus_detailModeTest.
  ///
  /// In zh, this message translates to:
  /// **'閘道器模式：測試模式（只產生測試資料）'**
  String get connectionStatus_detailModeTest;

  /// No description provided for @connectionStatus_detailMqtt.
  ///
  /// In zh, this message translates to:
  /// **'MQTT 連線：{state}'**
  String connectionStatus_detailMqtt(String state);

  /// No description provided for @connectionStatus_detailMqttLastRead.
  ///
  /// In zh, this message translates to:
  /// **'中斷前最後讀到的 MQTT 連線：{state}'**
  String connectionStatus_detailMqttLastRead(String state);

  /// No description provided for @connectionStatus_detailNotSet.
  ///
  /// In zh, this message translates to:
  /// **'（未設定）'**
  String get connectionStatus_detailNotSet;

  /// Gateway-reported pause reason appended to the data upload line.
  ///
  /// In zh, this message translates to:
  /// **'（{reason}）'**
  String connectionStatus_detailPauseReason(String reason);

  /// No description provided for @connectionStatus_detailPhoneBackend.
  ///
  /// In zh, this message translates to:
  /// **'手機連線的後端：{base}'**
  String connectionStatus_detailPhoneBackend(String base);

  /// Technical tail of the gateway network line (keep the leading ' · ').
  ///
  /// In zh, this message translates to:
  /// **' · 訊號 {rssi} dBm'**
  String connectionStatus_detailSignal(String rssi);

  /// Appended right after the dBm value when the signal is weak.
  ///
  /// In zh, this message translates to:
  /// **'（偏弱）'**
  String get connectionStatus_detailSignalWeak;

  /// No description provided for @connectionStatus_detailTargetLegacy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器上傳目標：正式站（韌體 {version} 不支援切換）'**
  String connectionStatus_detailTargetLegacy(String version);

  /// No description provided for @connectionStatus_detailTargetLocal.
  ///
  /// In zh, this message translates to:
  /// **'閘道器上傳目標：MQTT 本地 {hostPort}（TLS）'**
  String connectionStatus_detailTargetLocal(String hostPort);

  /// No description provided for @connectionStatus_detailTargetProduction.
  ///
  /// In zh, this message translates to:
  /// **'閘道器上傳目標：MQTT 正式站 {hostPort}（TLS）'**
  String connectionStatus_detailTargetProduction(String hostPort);

  /// No description provided for @connectionStatus_detailTargetUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'閘道器上傳目標：未確認（切換結果尚未讀回）'**
  String get connectionStatus_detailTargetUnconfirmed;

  /// No description provided for @connectionStatus_detailTargetUnknown.
  ///
  /// In zh, this message translates to:
  /// **'閘道器上傳目標：無法辨識（{value}）'**
  String connectionStatus_detailTargetUnknown(String value);

  /// No description provided for @connectionStatus_detailUploadOn.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳：開啟'**
  String get connectionStatus_detailUploadOn;

  /// No description provided for @connectionStatus_detailUploadPaused.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳：已暫停'**
  String get connectionStatus_detailUploadPaused;

  /// No description provided for @connectionStatus_hintCustomUnknown.
  ///
  /// In zh, this message translates to:
  /// **'APP 無法從這個網址判斷閘道器該送到哪裡，這裡只顯示閘道器目前的設定，不會自動切換。'**
  String get connectionStatus_hintCustomUnknown;

  /// No description provided for @connectionStatus_hintLinkLostReconnect.
  ///
  /// In zh, this message translates to:
  /// **'手機和閘道器的藍牙斷了，請靠近閘道器後按「結束並重新選擇閘道器」重新連線。'**
  String get connectionStatus_hintLinkLostReconnect;

  /// No description provided for @connectionStatus_hintPhoneNoBackend.
  ///
  /// In zh, this message translates to:
  /// **'手機連不到{label}，請確認手機可以上網。'**
  String connectionStatus_hintPhoneNoBackend(String label);

  /// No description provided for @connectionStatus_hintPhoneNoLocal.
  ///
  /// In zh, this message translates to:
  /// **'手機連不到測試主機：請確認電腦上的測試主機是否開著，且手機和電腦連同一個 Wi-Fi。'**
  String get connectionStatus_hintPhoneNoLocal;

  /// No description provided for @connectionStatus_hintPortMismatch.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的上傳設定和手機不一致（見技術細節）。按「同步」讓閘道器改送到{place}。'**
  String connectionStatus_hintPortMismatch(String place);

  /// No description provided for @connectionStatus_hintTargetMismatch.
  ///
  /// In zh, this message translates to:
  /// **'閘道器把資料送到{current}，但手機連的是{wanted}。按「同步」讓閘道器改送到{place}。'**
  String connectionStatus_hintTargetMismatch(
    String current,
    String wanted,
    String place,
  );

  /// No description provided for @connectionStatus_hintUnknownReread.
  ///
  /// In zh, this message translates to:
  /// **'還不確定閘道器把資料送到哪裡，請按「連線狀態」這一列最右邊的重新讀取圖示（↻）。'**
  String get connectionStatus_hintUnknownReread;

  /// No description provided for @connectionStatus_hintUnknownSync.
  ///
  /// In zh, this message translates to:
  /// **'還不確定閘道器把資料送到哪裡。按「同步」讓閘道器改送到{place}。'**
  String connectionStatus_hintUnknownSync(String place);

  /// No description provided for @connectionStatus_hintWifiConnecting.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒連上 Wi-Fi，請稍候；若一直連不上，請確認 Wi-Fi 名稱和密碼（可用「{action}」）。'**
  String connectionStatus_hintWifiConnecting(String action);

  /// No description provided for @connectionStatus_linkBack.
  ///
  /// In zh, this message translates to:
  /// **'手機已重新連上閘道器，{reload}'**
  String connectionStatus_linkBack(String reload);

  /// No description provided for @connectionStatus_linkLostCannotRead.
  ///
  /// In zh, this message translates to:
  /// **'手機和閘道器的藍牙已中斷，無法讀取目前狀態。{action}'**
  String connectionStatus_linkLostCannotRead(String action);

  /// No description provided for @connectionStatus_linkLostRelinking.
  ///
  /// In zh, this message translates to:
  /// **'手機和閘道器的藍牙已中斷，{relinking}'**
  String connectionStatus_linkLostRelinking(String relinking);

  /// No description provided for @connectionStatus_mqttConnected.
  ///
  /// In zh, this message translates to:
  /// **'已連線'**
  String get connectionStatus_mqttConnected;

  /// No description provided for @connectionStatus_mqttDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未連線'**
  String get connectionStatus_mqttDisconnected;

  /// Where data goes / the phone connects: the local test backend on a PC (status row name).
  ///
  /// In zh, this message translates to:
  /// **'本地測試主機'**
  String get connectionStatus_placeLocal;

  /// No description provided for @connectionStatus_probeChecking.
  ///
  /// In zh, this message translates to:
  /// **'檢查中'**
  String get connectionStatus_probeChecking;

  /// No description provided for @connectionStatus_probeDegraded.
  ///
  /// In zh, this message translates to:
  /// **'資料庫未就緒（HTTP 503）'**
  String get connectionStatus_probeDegraded;

  /// No description provided for @connectionStatus_probeHealthy.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get connectionStatus_probeHealthy;

  /// No description provided for @connectionStatus_probeHealthyVersion.
  ///
  /// In zh, this message translates to:
  /// **'正常（版本 {version}）'**
  String connectionStatus_probeHealthyVersion(String version);

  /// No description provided for @connectionStatus_probeNotBackend.
  ///
  /// In zh, this message translates to:
  /// **'不是本系統後端（HTTP {status}）'**
  String connectionStatus_probeNotBackend(String status);

  /// No description provided for @connectionStatus_probeUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'無法連線'**
  String get connectionStatus_probeUnreachable;

  /// No description provided for @connectionStatus_probeUnreachableDetail.
  ///
  /// In zh, this message translates to:
  /// **'無法連線（{detail}）'**
  String connectionStatus_probeUnreachableDetail(String detail);

  /// No description provided for @connectionStatus_reconnectThenCheck.
  ///
  /// In zh, this message translates to:
  /// **'請重新連線閘道器後再確認。'**
  String get connectionStatus_reconnectThenCheck;

  /// No description provided for @connectionStatus_statusChecking.
  ///
  /// In zh, this message translates to:
  /// **'⏳ 檢查中…'**
  String get connectionStatus_statusChecking;

  /// No description provided for @connectionStatus_statusConfirming.
  ///
  /// In zh, this message translates to:
  /// **'⏳ 確認中…'**
  String get connectionStatus_statusConfirming;

  /// No description provided for @connectionStatus_statusConnected.
  ///
  /// In zh, this message translates to:
  /// **'✓ 已連線'**
  String get connectionStatus_statusConnected;

  /// No description provided for @connectionStatus_statusConnectedDemo.
  ///
  /// In zh, this message translates to:
  /// **'✓ 已連線（模擬）'**
  String get connectionStatus_statusConnectedDemo;

  /// No description provided for @connectionStatus_statusConnecting.
  ///
  /// In zh, this message translates to:
  /// **'⏳ 連線中…'**
  String get connectionStatus_statusConnecting;

  /// No description provided for @connectionStatus_statusDbNotReady.
  ///
  /// In zh, this message translates to:
  /// **'⚠ 連上了，但資料庫還沒準備好'**
  String get connectionStatus_statusDbNotReady;

  /// The gateway uploads to another backend than the phone uses.
  ///
  /// In zh, this message translates to:
  /// **'⚠ 送到別處'**
  String get connectionStatus_statusElsewhere;

  /// No description provided for @connectionStatus_statusLinkLostUploadUnknown.
  ///
  /// In zh, this message translates to:
  /// **'？ 藍牙已中斷，上傳狀態待確認'**
  String get connectionStatus_statusLinkLostUploadUnknown;

  /// No description provided for @connectionStatus_statusTestMode.
  ///
  /// In zh, this message translates to:
  /// **'⚠ 測試模式'**
  String get connectionStatus_statusTestMode;

  /// No description provided for @connectionStatus_statusUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'？ 未確認'**
  String get connectionStatus_statusUnconfirmed;

  /// No description provided for @connectionStatus_statusUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'✗ 連不上'**
  String get connectionStatus_statusUnreachable;

  /// No description provided for @connectionStatus_statusUploadPaused.
  ///
  /// In zh, this message translates to:
  /// **'⚠ 上傳已暫停'**
  String get connectionStatus_statusUploadPaused;

  /// No description provided for @connectionStatus_statusUploadUnknown.
  ///
  /// In zh, this message translates to:
  /// **'？ 上傳狀態待確認'**
  String get connectionStatus_statusUploadUnknown;

  /// No description provided for @connectionStatus_statusUploading.
  ///
  /// In zh, this message translates to:
  /// **'✓ 資料上傳中'**
  String get connectionStatus_statusUploading;

  /// No description provided for @connectionStatus_statusWifiDown.
  ///
  /// In zh, this message translates to:
  /// **'✗ Wi-Fi 沒連上'**
  String get connectionStatus_statusWifiDown;

  /// No description provided for @connectionStatus_subnetHint.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前在 {subnet}.x 網段，可能連不到測試主機 {host}。請確認閘道器和這台電腦連同一個 Wi-Fi（可用「{action}」）。'**
  String connectionStatus_subnetHint(String subnet, String host, String action);

  /// No description provided for @connectionStatus_summary.
  ///
  /// In zh, this message translates to:
  /// **'✓ {label}：手機與閘道器都已連上'**
  String connectionStatus_summary(String label);

  /// No description provided for @connectionStatus_tapButton.
  ///
  /// In zh, this message translates to:
  /// **'請按「{button}」。'**
  String connectionStatus_tapButton(String button);

  /// No description provided for @connectionStatus_uploadCheckLocal.
  ///
  /// In zh, this message translates to:
  /// **'請確認電腦上的測試主機是否開著，以及閘道器是否連上和這台電腦同一個 Wi-Fi。'**
  String get connectionStatus_uploadCheckLocal;

  /// No description provided for @connectionStatus_uploadCheckProduction.
  ///
  /// In zh, this message translates to:
  /// **'請確認閘道器所在的 Wi-Fi 可以上網。'**
  String get connectionStatus_uploadCheckProduction;

  /// Gateway row name while its upload target is being read.
  ///
  /// In zh, this message translates to:
  /// **'確認中'**
  String get connectionStatus_whereChecking;

  /// Gateway row name: a target switch was sent but not read back.
  ///
  /// In zh, this message translates to:
  /// **'未確認'**
  String get connectionStatus_whereUnconfirmed;

  /// Gateway row name: the firmware reported an unknown target.
  ///
  /// In zh, this message translates to:
  /// **'無法辨識'**
  String get connectionStatus_whereUnknown;

  /// Button name quoted inside hints (choose another Wi-Fi network).
  ///
  /// In zh, this message translates to:
  /// **'改用其他 Wi-Fi'**
  String get connectionStatus_wifiActionOther;

  /// Button name quoted inside hints (change the gateway's Wi-Fi).
  ///
  /// In zh, this message translates to:
  /// **'重設 Wi-Fi'**
  String get connectionStatus_wifiActionReset;

  /// Button name quoted inside hints (gateway has no Wi-Fi yet).
  ///
  /// In zh, this message translates to:
  /// **'設定 Wi-Fi'**
  String get connectionStatus_wifiActionSet;

  /// No description provided for @connectionStatus_wifiFixHere.
  ///
  /// In zh, this message translates to:
  /// **'請按「{action}」，改成現場的 2.4 GHz Wi-Fi。'**
  String connectionStatus_wifiFixHere(String action);

  /// No description provided for @connectionStatus_wifiFixReconnect.
  ///
  /// In zh, this message translates to:
  /// **'請按「結束並重新選擇閘道器」重新連線，在網路體檢按「{action}」。'**
  String connectionStatus_wifiFixReconnect(String action);

  /// No description provided for @connectionStatus_wifiLinkLostReconnect.
  ///
  /// In zh, this message translates to:
  /// **'手機和閘道器的藍牙也斷了：請靠近閘道器，按「結束並重新選擇閘道器」重新連線，再按「{action}」。'**
  String connectionStatus_wifiLinkLostReconnect(String action);

  /// Second line under a Wi-Fi problem while the automatic reconnect runs.
  ///
  /// In zh, this message translates to:
  /// **'手機和閘道器的藍牙也斷了，{relinking}'**
  String connectionStatus_wifiLinkLostRelinking(String relinking);

  /// No description provided for @controller_absentSelection.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 台在本次掃描未出現，已取消勾選}}'**
  String controller_absentSelection(int count);

  /// No description provided for @controller_ackNumberMismatch.
  ///
  /// In zh, this message translates to:
  /// **'裝置回報編號 #{reported} 與指派 #{wanted} 不符，請重試'**
  String controller_ackNumberMismatch(String reported, int wanted);

  /// No description provided for @controller_adjustedTo.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{已調整為 {count} 台；請重新選擇已連線裝置或修復缺少的 PTU。}}'**
  String controller_adjustedTo(int count);

  /// No description provided for @controller_allAssignFailed.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 台都指派失敗，閘道器設定未變更；請確認 PTU 後按「重試這 {count} 台」。}}'**
  String controller_allAssignFailed(int count);

  /// No description provided for @controller_alreadyMonitoring.
  ///
  /// In zh, this message translates to:
  /// **'已在監控'**
  String get controller_alreadyMonitoring;

  /// No description provided for @controller_assignCount.
  ///
  /// In zh, this message translates to:
  /// **'{done}/{total} 台'**
  String controller_assignCount(int done, int total);

  /// No description provided for @controller_assignFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 台指派失敗}}'**
  String controller_assignFailedCount(int count);

  /// No description provided for @controller_assignFailedReason.
  ///
  /// In zh, this message translates to:
  /// **'指派失敗：{reason}'**
  String controller_assignFailedReason(String reason);

  /// No description provided for @controller_assignedNumber.
  ///
  /// In zh, this message translates to:
  /// **'已指派 #{id}'**
  String controller_assignedNumber(String id);

  /// No description provided for @controller_assignedPtu.
  ///
  /// In zh, this message translates to:
  /// **'已指派 PTU #{id}'**
  String controller_assignedPtu(int id);

  /// No description provided for @controller_assignedWaiting.
  ///
  /// In zh, this message translates to:
  /// **'已指派 #{id}，等待連線'**
  String controller_assignedWaiting(int id);

  /// No description provided for @controller_assigningDirect.
  ///
  /// In zh, this message translates to:
  /// **'正在指派 #{id} 並開始監控'**
  String controller_assigningDirect(int id);

  /// No description provided for @controller_assigningLabel.
  ///
  /// In zh, this message translates to:
  /// **'配置中… {done}/{total}'**
  String controller_assigningLabel(int done, int total);

  /// No description provided for @controller_autoRelinking.
  ///
  /// In zh, this message translates to:
  /// **'正在自動重新連線…'**
  String get controller_autoRelinking;

  /// No description provided for @controller_backendRetry.
  ///
  /// In zh, this message translates to:
  /// **'後端暫時無回應，自動重試中（{attempt}）'**
  String controller_backendRetry(int attempt);

  /// No description provided for @controller_backendSwitchedDone.
  ///
  /// In zh, this message translates to:
  /// **'已切換連線環境，資料要在新的環境重新確認。'**
  String get controller_backendSwitchedDone;

  /// No description provided for @controller_backendSwitchedVerify.
  ///
  /// In zh, this message translates to:
  /// **'已切換連線環境，請按「開始資料驗證」重新確認。'**
  String get controller_backendSwitchedVerify;

  /// No description provided for @controller_backendUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'後端尚未確認；完成配置後仍需驗證'**
  String get controller_backendUnconfirmed;

  /// No description provided for @controller_bindLaterBlocked.
  ///
  /// In zh, this message translates to:
  /// **'目前無法進入「選擇 PTU」，請先完成網路體檢後再按一次。'**
  String get controller_bindLaterBlocked;

  /// No description provided for @controller_bindLaterHint.
  ///
  /// In zh, this message translates to:
  /// **'請按〔辨識並綁定〕：到選擇 PTU 時按「辨識此樁」確認是眼前這台，再按「是這台，開始配置」即會綁定並把它編為 #1。'**
  String get controller_bindLaterHint;

  /// No description provided for @controller_bindLaterLabel.
  ///
  /// In zh, this message translates to:
  /// **'辨識並綁定'**
  String get controller_bindLaterLabel;

  /// No description provided for @controller_bindLaterNoStation.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器目前不能沿用站點，請先完成站點與 Wi-Fi 設定。'**
  String get controller_bindLaterNoStation;

  /// No description provided for @controller_bindLaterTitle.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器已連上 PTU {mac}，但尚未綁定'**
  String controller_bindLaterTitle(String mac);

  /// No description provided for @controller_bindLaterWaitingHint.
  ///
  /// In zh, this message translates to:
  /// **'請確認本樁 PTU 已上電、與閘道器放在同一個機殼內；連上後按〔辨識並綁定〕。'**
  String get controller_bindLaterWaitingHint;

  /// No description provided for @controller_bindLaterWaitingTitle.
  ///
  /// In zh, this message translates to:
  /// **'上次配置時本樁 PTU 尚未連線，閘道器目前仍未連上 PTU'**
  String get controller_bindLaterWaitingTitle;

  /// No description provided for @controller_bleCleanupDone.
  ///
  /// In zh, this message translates to:
  /// **'藍牙清理未完成，請按「{done}」或「{next}」重試斷開。'**
  String controller_bleCleanupDone(String done, String next);

  /// No description provided for @controller_bleCleanupIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'藍牙清理未完成，請重試斷開。'**
  String get controller_bleCleanupIncomplete;

  /// No description provided for @controller_bleConnectIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'藍牙連線未完成，請重試。'**
  String get controller_bleConnectIncomplete;

  /// No description provided for @controller_boundPtu.
  ///
  /// In zh, this message translates to:
  /// **'已綁定 PTU #{id}'**
  String controller_boundPtu(int id);

  /// No description provided for @controller_busyTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'另一個動作還在進行，請等它結束後再按一次。'**
  String get controller_busyTryAgain;

  /// No description provided for @controller_cancelRestoreRetry.
  ///
  /// In zh, this message translates to:
  /// **'{failure} 請保持靠近並再次取消以重試還原，或重開 APP 後重新連線。'**
  String controller_cancelRestoreRetry(String failure);

  /// No description provided for @controller_cancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消。請重新連線核對進度；未成功恢復的監控會話最晚於到期時恢復。'**
  String get controller_cancelled;

  /// No description provided for @controller_checkFailedNew.
  ///
  /// In zh, this message translates to:
  /// **'網路體檢未通過，仍可設定新站點；之後會再確認資料上傳。'**
  String get controller_checkFailedNew;

  /// No description provided for @controller_checkFailedStation.
  ///
  /// In zh, this message translates to:
  /// **'網路體檢未通過：可重設 Wi-Fi 或設定新站點；沿用要等網路正常。'**
  String get controller_checkFailedStation;

  /// No description provided for @controller_checkPassedNew.
  ///
  /// In zh, this message translates to:
  /// **'網路體檢通過，請設定身份與 Wi-Fi。'**
  String get controller_checkPassedNew;

  /// No description provided for @controller_checkPassedStation.
  ///
  /// In zh, this message translates to:
  /// **'網路體檢通過，請選擇站點。'**
  String get controller_checkPassedStation;

  /// No description provided for @controller_checkingMonitor.
  ///
  /// In zh, this message translates to:
  /// **'正在確認閘道器監控狀態'**
  String get controller_checkingMonitor;

  /// No description provided for @controller_chooseGateway.
  ///
  /// In zh, this message translates to:
  /// **'請選擇要開通的閘道器'**
  String get controller_chooseGateway;

  /// No description provided for @controller_chooseStationWaitUpload.
  ///
  /// In zh, this message translates to:
  /// **'請選擇站點。沿用要等閘道器開始上傳資料。'**
  String get controller_chooseStationWaitUpload;

  /// No description provided for @controller_configureCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{配置 {count} 台並開始監控}}'**
  String controller_configureCount(int count);

  /// No description provided for @controller_configureRest.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{配置剩餘 {count} 台並開始監控}}'**
  String controller_configureRest(int count);

  /// No description provided for @controller_configureRun.
  ///
  /// In zh, this message translates to:
  /// **'逐台編號並開始監控'**
  String get controller_configureRun;

  /// No description provided for @controller_configureWifiRun.
  ///
  /// In zh, this message translates to:
  /// **'設定身份與 WiFi'**
  String get controller_configureWifiRun;

  /// No description provided for @controller_configuredVerify.
  ///
  /// In zh, this message translates to:
  /// **'配置完成，請驗證後端資料'**
  String get controller_configuredVerify;

  /// No description provided for @controller_connectLogDetail.
  ///
  /// In zh, this message translates to:
  /// **'連線失敗紀錄：{log}'**
  String controller_connectLogDetail(String log);

  /// One connect-failure entry (attempt number and technical error type). The Chinese text is also uploaded as field diagnostics connect_log.
  ///
  /// In zh, this message translates to:
  /// **'第 {attempt} 次：{type}'**
  String controller_connectLogLine(int attempt, String type);

  /// No description provided for @controller_connectedHasStation.
  ///
  /// In zh, this message translates to:
  /// **'已連線，此閘道器已有站點設定。先做網路體檢，再選擇沿用或設定新站。'**
  String get controller_connectedHasStation;

  /// No description provided for @controller_connectedNew.
  ///
  /// In zh, this message translates to:
  /// **'已連線。先做網路體檢，再設定身份與 Wi-Fi。'**
  String get controller_connectedNew;

  /// No description provided for @controller_connectedNumber.
  ///
  /// In zh, this message translates to:
  /// **'已連線 #{id}'**
  String controller_connectedNumber(String id);

  /// No description provided for @controller_connectingAttempt.
  ///
  /// In zh, this message translates to:
  /// **'連線中（第 {attempt} 次）'**
  String controller_connectingAttempt(int attempt);

  /// No description provided for @controller_connectingPeer.
  ///
  /// In zh, this message translates to:
  /// **'正在連線 {name}，請保持靠近'**
  String controller_connectingPeer(String name);

  /// No description provided for @controller_connectingStage.
  ///
  /// In zh, this message translates to:
  /// **'{attempt}：{stage}'**
  String controller_connectingStage(String attempt, String stage);

  /// No description provided for @controller_continueAssign.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{繼續指派 {count} 台}}'**
  String controller_continueAssign(int count);

  /// No description provided for @controller_dataStale.
  ///
  /// In zh, this message translates to:
  /// **'資料暫未更新'**
  String get controller_dataStale;

  /// Done page health result; use CommissionState.dataStreaming instead of matching this text.
  ///
  /// In zh, this message translates to:
  /// **'資料持續更新'**
  String get controller_dataStreaming;

  /// No description provided for @controller_deferConfirm.
  ///
  /// In zh, this message translates to:
  /// **'閘道器會照常完成配置：加入運作、恢復上傳，維持一對一模式與目前門檻（{threshold} dBm），但不綁定 PTU。\n本樁 PTU 上電後，閘道器會自動連上它；綁定需之後到現場按〔辨識並綁定〕確認。'**
  String controller_deferConfirm(int threshold);

  /// No description provided for @controller_deferConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'先完成配置，稍後 PTU 上電自動連線？'**
  String get controller_deferConfirmTitle;

  /// No description provided for @controller_deferFinishLabel.
  ///
  /// In zh, this message translates to:
  /// **'先完成配置'**
  String get controller_deferFinishLabel;

  /// No description provided for @controller_deferredBindNowLabel.
  ///
  /// In zh, this message translates to:
  /// **'PTU 已上電：辨識並綁定'**
  String get controller_deferredBindNowLabel;

  /// Done page line; the install report always uses the zh text.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已加入運作並恢復上傳，維持一對一模式（門檻 {threshold} dBm），尚未綁定 PTU。'**
  String controller_deferredDetail(int threshold);

  /// No description provided for @controller_deferredDone.
  ///
  /// In zh, this message translates to:
  /// **'本樁 PTU 尚未連線。PTU 上電後會自動連線，之後到現場按〔辨識並綁定〕確認綁定。'**
  String get controller_deferredDone;

  /// No description provided for @controller_deferredDoneTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器配置完成'**
  String get controller_deferredDoneTitle;

  /// No description provided for @controller_deferredLater.
  ///
  /// In zh, this message translates to:
  /// **'之後補做綁定：PTU 上電後，用 APP 重新連上這台閘道器，會出現〔辨識並綁定〕。人還在現場且 PTU 已上電，可直接按下方按鈕。'**
  String get controller_deferredLater;

  /// No description provided for @controller_deferredSummary.
  ///
  /// In zh, this message translates to:
  /// **'本樁 PTU 尚未連線（上電後自動連上）'**
  String get controller_deferredSummary;

  /// No description provided for @controller_deferredUploadStatus.
  ///
  /// In zh, this message translates to:
  /// **'✓ 已恢復上傳（等本樁 PTU 連上）'**
  String get controller_deferredUploadStatus;

  /// No description provided for @controller_deferring.
  ///
  /// In zh, this message translates to:
  /// **'正在完成閘道器配置（本樁 PTU 尚未連線）'**
  String get controller_deferring;

  /// No description provided for @controller_devShipNote.
  ///
  /// In zh, this message translates to:
  /// **'開發環境提示（本地測試版才會出現，現場人員不用處理）：這台閘道器目前上傳到本地測試站，出貨前需由開發人員把手機和閘道器一起切回正式站。'**
  String get controller_devShipNote;

  /// No description provided for @controller_devShipSwitchLabel.
  ///
  /// In zh, this message translates to:
  /// **'切回正式站'**
  String get controller_devShipSwitchLabel;

  /// No description provided for @controller_directBoundMissing.
  ///
  /// In zh, this message translates to:
  /// **'閘道器綁定的 PTU 不在場：請確認它已上電，或解除綁定後按「重新搜尋」。'**
  String get controller_directBoundMissing;

  /// Done page line; the install report always uses the zh text.
  ///
  /// In zh, this message translates to:
  /// **'已綁定 PTU MAC：{mac}（閘道器只連這台）'**
  String controller_directBoundNote(String mac);

  /// No description provided for @controller_directFreshWindow.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在重新收集附近的 PTU，請稍候'**
  String get controller_directFreshWindow;

  /// No description provided for @controller_directNoCandidate.
  ///
  /// In zh, this message translates to:
  /// **'閘道器找不到夠近的 PTU：請確認同樁 PTU 已上電並靠近，再按「重新搜尋」。'**
  String get controller_directNoCandidate;

  /// No description provided for @controller_directNoData.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒收到這台 PTU 的資料，請確認 PTU 電源後再按「是這台，開始配置」重試；閘道器仍維持監控。'**
  String get controller_directNoData;

  /// No description provided for @controller_directNoReport.
  ///
  /// In zh, this message translates to:
  /// **'閘道器尚未回報選台結果，請按「重新搜尋」。'**
  String get controller_directNoReport;

  /// No description provided for @controller_directPickIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'閘道器選台未完成，請查看錯誤後按「重新搜尋」。'**
  String get controller_directPickIncomplete;

  /// No description provided for @controller_directPicked.
  ///
  /// In zh, this message translates to:
  /// **'閘道器選中 PTU {mac}，請按「辨識此樁」確認是眼前這台'**
  String controller_directPicked(String mac);

  /// No description provided for @controller_directPickedAmbiguous.
  ///
  /// In zh, this message translates to:
  /// **'閘道器選中 PTU {mac}，但附近有訊號相近的 PTU，請按「辨識此樁」確認'**
  String controller_directPickedAmbiguous(String mac);

  /// No description provided for @controller_directPicking.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在選擇最近的 PTU，請稍候'**
  String get controller_directPicking;

  /// No description provided for @controller_directStillSearching.
  ///
  /// In zh, this message translates to:
  /// **'閘道器仍在尋找 PTU，請稍候再按「重新搜尋」。'**
  String get controller_directStillSearching;

  /// No description provided for @controller_directSwitchDone.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已改連 PTU {mac}（已綁定），請按「辨識此樁」確認是眼前這台。'**
  String controller_directSwitchDone(String mac);

  /// No description provided for @controller_directSwitchPending.
  ///
  /// In zh, this message translates to:
  /// **'閘道器仍在改連 PTU {mac}，連上後畫面會自動更新；也可改選其他 PTU。'**
  String controller_directSwitchPending(String mac);

  /// No description provided for @controller_disconnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在斷開藍牙…'**
  String get controller_disconnecting;

  /// No description provided for @controller_doneBefore.
  ///
  /// In zh, this message translates to:
  /// **'先前已完成'**
  String get controller_doneBefore;

  /// No description provided for @controller_doneBusy.
  ///
  /// In zh, this message translates to:
  /// **'正在處理，完成後再按〔完成〕。'**
  String get controller_doneBusy;

  /// No description provided for @controller_doneNextLabel.
  ///
  /// In zh, this message translates to:
  /// **'配置下一台'**
  String get controller_doneNextLabel;

  /// No description provided for @controller_endFlowConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'結束目前配置？'**
  String get controller_endFlowConfirmTitle;

  /// No description provided for @controller_endFlowDeferHint.
  ///
  /// In zh, this message translates to:
  /// **'本樁 PTU 不在場時，請改按「{label}」。'**
  String controller_endFlowDeferHint(String label);

  /// No description provided for @controller_endFlowHeldUpload.
  ///
  /// In zh, this message translates to:
  /// **'注意：這台閘道器還沒加入運作（資料上傳暫停），結束後不會上傳任何資料。'**
  String get controller_endFlowHeldUpload;

  /// No description provided for @controller_endFlowKeepDone.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{已完成的 {count} 台會保留在閘道器。}}'**
  String controller_endFlowKeepDone(int count);

  /// No description provided for @controller_endFlowLabel.
  ///
  /// In zh, this message translates to:
  /// **'結束並重新選擇閘道器'**
  String get controller_endFlowLabel;

  /// No description provided for @controller_endFlowNoneDone.
  ///
  /// In zh, this message translates to:
  /// **'目前尚未完成任何 PTU。'**
  String get controller_endFlowNoneDone;

  /// No description provided for @controller_endFlowRestoreDone.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{結束後會把閘道器的 PTU 綁定還原為改選前的狀態；已完成的 {count} 台保留。}}'**
  String controller_endFlowRestoreDone(int count);

  /// No description provided for @controller_endFlowRestoreNone.
  ///
  /// In zh, this message translates to:
  /// **'結束後會把閘道器的 PTU 綁定還原為改選前的狀態；目前尚未完成任何 PTU。'**
  String get controller_endFlowRestoreNone;

  /// No description provided for @controller_firmwareNote.
  ///
  /// In zh, this message translates to:
  /// **'韌體 {version}'**
  String controller_firmwareNote(String version);

  /// No description provided for @controller_firstConnectFailure.
  ///
  /// In zh, this message translates to:
  /// **'第一次連線失敗：{failure}'**
  String controller_firstConnectFailure(String failure);

  /// No description provided for @controller_gatewayBusy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器忙碌中，等待…'**
  String get controller_gatewayBusy;

  /// No description provided for @controller_gatewayFallbackName.
  ///
  /// In zh, this message translates to:
  /// **'閘道器'**
  String get controller_gatewayFallbackName;

  /// No description provided for @controller_gatewayFull.
  ///
  /// In zh, this message translates to:
  /// **'本機已滿，請連另一台閘道器。'**
  String get controller_gatewayFull;

  /// No description provided for @controller_gatewayStatusBusy.
  ///
  /// In zh, this message translates to:
  /// **'配置進行中不可用'**
  String get controller_gatewayStatusBusy;

  /// No description provided for @controller_gatewayStatusMenu.
  ///
  /// In zh, this message translates to:
  /// **'查看上傳資料…'**
  String get controller_gatewayStatusMenu;

  /// No description provided for @controller_gatewayStatusMenuBusy.
  ///
  /// In zh, this message translates to:
  /// **'查看上傳資料（{reason}）'**
  String controller_gatewayStatusMenuBusy(String reason);

  /// No description provided for @controller_healthAbnormal.
  ///
  /// In zh, this message translates to:
  /// **'資料有異常，請檢查 PTU 與網路。'**
  String get controller_healthAbnormal;

  /// No description provided for @controller_healthPending.
  ///
  /// In zh, this message translates to:
  /// **'正在確認資料上傳…'**
  String get controller_healthPending;

  /// No description provided for @controller_healthUnknown.
  ///
  /// In zh, this message translates to:
  /// **'無法確認最新資料，請檢查網路'**
  String get controller_healthUnknown;

  /// No description provided for @controller_heartbeatNote.
  ///
  /// In zh, this message translates to:
  /// **'心跳 {n}/2'**
  String controller_heartbeatNote(int n);

  /// No description provided for @controller_identifyPeerLabel.
  ///
  /// In zh, this message translates to:
  /// **'辨識閘道器（閃燈）'**
  String get controller_identifyPeerLabel;

  /// No description provided for @controller_identifyRun.
  ///
  /// In zh, this message translates to:
  /// **'辨識閘道器'**
  String get controller_identifyRun;

  /// No description provided for @controller_identityConflict.
  ///
  /// In zh, this message translates to:
  /// **'ID 衝突：偵測到多台實體設備使用相同 Site {site} / 閘道器 {gw}。'**
  String controller_identityConflict(int site, int gw);

  /// No description provided for @controller_keepStationResetWifi.
  ///
  /// In zh, this message translates to:
  /// **'保留目前站點與 PTU，只重設 Wi-Fi。請選 2.4 GHz 的 Wi-Fi。'**
  String get controller_keepStationResetWifi;

  /// No description provided for @controller_lastDone.
  ///
  /// In zh, this message translates to:
  /// **'上一台已完成：站 {site} 閘道器 {gateway}'**
  String controller_lastDone(String site, String gateway);

  /// No description provided for @controller_lastDoneDeferred.
  ///
  /// In zh, this message translates to:
  /// **'上一台已完成：站 {site} 閘道器 {gateway}（本樁 PTU 尚未連線，上電後自動連上）'**
  String controller_lastDoneDeferred(String site, String gateway);

  /// No description provided for @controller_leaveListConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'結束這次配置並回首頁？'**
  String get controller_leaveListConfirmTitle;

  /// No description provided for @controller_leaveListLabel.
  ///
  /// In zh, this message translates to:
  /// **'結束配置'**
  String get controller_leaveListLabel;

  /// No description provided for @controller_linkConfirming.
  ///
  /// In zh, this message translates to:
  /// **'藍牙已連線，正在確認閘道器回應與設定…'**
  String get controller_linkConfirming;

  /// No description provided for @controller_listNotWritten.
  ///
  /// In zh, this message translates to:
  /// **'名單沒有寫入，指派照常進行'**
  String get controller_listNotWritten;

  /// No description provided for @controller_loginRun.
  ///
  /// In zh, this message translates to:
  /// **'登入後端'**
  String get controller_loginRun;

  /// No description provided for @controller_monitorSkipped.
  ///
  /// In zh, this message translates to:
  /// **'已略過監控確認，請在資料驗證確認各台是否上傳。'**
  String get controller_monitorSkipped;

  /// No description provided for @controller_monitorUnconfirmedCheck.
  ///
  /// In zh, this message translates to:
  /// **'尚未確認閘道器已恢復監控，請重新連線核對設定。'**
  String get controller_monitorUnconfirmedCheck;

  /// No description provided for @controller_monitorUnconfirmedRecheck.
  ///
  /// In zh, this message translates to:
  /// **'尚未確認閘道器已恢復監控，請重新連線核對。'**
  String get controller_monitorUnconfirmedRecheck;

  /// No description provided for @controller_monitorUnconfirmedResume.
  ///
  /// In zh, this message translates to:
  /// **'尚未確認閘道器已恢復監控，請按「{label}」核對。'**
  String controller_monitorUnconfirmedResume(String label);

  /// No description provided for @controller_netCheckIntro.
  ///
  /// In zh, this message translates to:
  /// **'網路體檢：確認閘道器的 Wi-Fi 與資料上傳。'**
  String get controller_netCheckIntro;

  /// No description provided for @controller_newStationPrompt.
  ///
  /// In zh, this message translates to:
  /// **'請輸入新的站點 ID 與 Wi-Fi；儲存後才會變更閘道器。'**
  String get controller_newStationPrompt;

  /// No description provided for @controller_nextGateway.
  ///
  /// In zh, this message translates to:
  /// **'請選擇下一台閘道器；新的閘道器會預設沿用站 {site}。'**
  String controller_nextGateway(int site);

  /// No description provided for @controller_nextSetWifi.
  ///
  /// In zh, this message translates to:
  /// **'接著設定 Wi-Fi。'**
  String get controller_nextSetWifi;

  /// No description provided for @controller_noChange.
  ///
  /// In zh, this message translates to:
  /// **'不需變更'**
  String get controller_noChange;

  /// Use CommissionState.noGatewayFound instead of matching this text.
  ///
  /// In zh, this message translates to:
  /// **'未找到閘道器，請靠近並確認電源後重掃。'**
  String get controller_noGatewayFound;

  /// No description provided for @controller_noPtuConnected.
  ///
  /// In zh, this message translates to:
  /// **'未連上任何 PTU，請確認 PTU 電源與距離後重試；閘道器仍維持監控。'**
  String get controller_noPtuConnected;

  /// No description provided for @controller_noneValue.
  ///
  /// In zh, this message translates to:
  /// **'（無）'**
  String get controller_noneValue;

  /// No description provided for @controller_notIdentifiedPick.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前連的是 PTU {mac}，請先按「辨識此樁」確認是眼前這台，再按「是這台，開始配置」。'**
  String controller_notIdentifiedPick(String mac);

  /// No description provided for @controller_notReported.
  ///
  /// In zh, this message translates to:
  /// **'（未回報）'**
  String get controller_notReported;

  /// No description provided for @controller_offlineMode.
  ///
  /// In zh, this message translates to:
  /// **'離線模式：最後仍需登入驗證資料'**
  String get controller_offlineMode;

  /// No description provided for @controller_onlineReady.
  ///
  /// In zh, this message translates to:
  /// **'閘道器持續上線，可搜尋 PTU'**
  String get controller_onlineReady;

  /// No description provided for @controller_onlineRun.
  ///
  /// In zh, this message translates to:
  /// **'確認閘道器持續上線'**
  String get controller_onlineRun;

  /// No description provided for @controller_partialAssign.
  ///
  /// In zh, this message translates to:
  /// **'{failed, plural, other{已先讓 {ok} 台上線；{failed} 台指派失敗，可按「重試這 {failed} 台」。}}'**
  String controller_partialAssign(int ok, int failed);

  /// Step 8 PTU row result; use CommissionState.pendingReadback instead of matching this text.
  ///
  /// In zh, this message translates to:
  /// **'已送出 #{id}，待回讀確認'**
  String controller_pendingReadback(int id);

  /// No description provided for @controller_prepareRun.
  ///
  /// In zh, this message translates to:
  /// **'檢查藍牙與後端連線'**
  String get controller_prepareRun;

  /// No description provided for @controller_prepared.
  ///
  /// In zh, this message translates to:
  /// **'準備完成'**
  String get controller_prepared;

  /// No description provided for @controller_ptuBackHint.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已連上綁定的 PTU，不需要更換。'**
  String get controller_ptuBackHint;

  /// No description provided for @controller_ptuBackTitle.
  ///
  /// In zh, this message translates to:
  /// **'PTU 已連線（{mac}）'**
  String controller_ptuBackTitle(String mac);

  /// No description provided for @controller_ptuConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'PTU 連線失敗，請確認 PTU 電源與距離'**
  String get controller_ptuConnectFailed;

  /// No description provided for @controller_ptuCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 台}}'**
  String controller_ptuCount(int count);

  /// No description provided for @controller_ptuCountReading.
  ///
  /// In zh, this message translates to:
  /// **'讀取中…'**
  String get controller_ptuCountReading;

  /// No description provided for @controller_ptuCountUnread.
  ///
  /// In zh, this message translates to:
  /// **'尚未讀取 PTU 列表'**
  String get controller_ptuCountUnread;

  /// No description provided for @controller_ptuCounts.
  ///
  /// In zh, this message translates to:
  /// **'已連線 {connected} 台／周邊未連線 {nearby} 台'**
  String controller_ptuCounts(int connected, int nearby);

  /// No description provided for @controller_ptuJoinedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 台 PTU 已連上}}'**
  String controller_ptuJoinedCount(int count);

  /// No description provided for @controller_ptuJoinedDirect.
  ///
  /// In zh, this message translates to:
  /// **'PTU 已連上閘道器'**
  String get controller_ptuJoinedDirect;

  /// No description provided for @controller_ptuListBusy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器忙碌，列表暫時無法更新'**
  String get controller_ptuListBusy;

  /// No description provided for @controller_ptuListBusyWithCounts.
  ///
  /// In zh, this message translates to:
  /// **'{busy}（下面是上一次的列表：{counts}）'**
  String controller_ptuListBusyWithCounts(String busy, String counts);

  /// No description provided for @controller_ptuListLoading.
  ///
  /// In zh, this message translates to:
  /// **'讀取中…（目標 {target} 台）'**
  String controller_ptuListLoading(int target);

  /// No description provided for @controller_ptuMissingHint.
  ///
  /// In zh, this message translates to:
  /// **'請確認原 PTU 已上電。一般情況可透過手機藍牙更換，原 PTU 不需在場。後台同步與資料驗證仍需閘道器上網，且手機可連到後台。若只是更換網路，可先重設 Wi-Fi，不需 PTU 在場。'**
  String get controller_ptuMissingHint;

  /// No description provided for @controller_ptuMissingTitle.
  ///
  /// In zh, this message translates to:
  /// **'本樁 PTU 不在場（綁定 MAC 後 4 碼 {tail}）'**
  String controller_ptuMissingTitle(String tail);

  /// No description provided for @controller_ptuNoResponse.
  ///
  /// In zh, this message translates to:
  /// **'PTU 沒有回應'**
  String get controller_ptuNoResponse;

  /// No description provided for @controller_ptuNotFound.
  ///
  /// In zh, this message translates to:
  /// **'閘道器找不到這台 PTU，請重新掃描'**
  String get controller_ptuNotFound;

  /// No description provided for @controller_ptuOtherTitle.
  ///
  /// In zh, this message translates to:
  /// **'連到的不是綁定的 PTU（綁定 MAC 後 4 碼 {bound}，目前連 {other}）'**
  String controller_ptuOtherTitle(String bound, String other);

  /// No description provided for @controller_ptuSearchingHint.
  ///
  /// In zh, this message translates to:
  /// **'閘道器剛開機或狀態剛變化，正在連線綁定的 PTU（MAC 後 4 碼 {tail}），通常 1 分鐘內會連上；請稍候再按〔{label}〕。'**
  String controller_ptuSearchingHint(String tail, String label);

  /// No description provided for @controller_ptuSearchingRecheckLabel.
  ///
  /// In zh, this message translates to:
  /// **'重新檢查'**
  String get controller_ptuSearchingRecheckLabel;

  /// No description provided for @controller_ptuSearchingTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在尋找本樁 PTU…'**
  String get controller_ptuSearchingTitle;

  /// No description provided for @controller_ptuSetupIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'PTU 設定未完成，請靠近後重試'**
  String get controller_ptuSetupIncomplete;

  /// No description provided for @controller_ptuUnnumbered.
  ///
  /// In zh, this message translates to:
  /// **'PTU {mac}：PTU 未取得裝置編號（device_number=0）'**
  String controller_ptuUnnumbered(String mac);

  /// No description provided for @controller_ptusReturned.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已回傳 {count} 台 PTU，請選擇要監控的裝置，最多 {target} 台'**
  String controller_ptusReturned(int count, int target);

  /// No description provided for @controller_readbackMismatch.
  ///
  /// In zh, this message translates to:
  /// **'回讀編號為 #{actual}，不是指派的 #{wanted}，請重試'**
  String controller_readbackMismatch(int actual, int wanted);

  /// No description provided for @controller_recheckPtuLabel.
  ///
  /// In zh, this message translates to:
  /// **'PTU 已上電，重新檢查'**
  String get controller_recheckPtuLabel;

  /// No description provided for @controller_recheckingPtu.
  ///
  /// In zh, this message translates to:
  /// **'正在重新檢查 PTU'**
  String get controller_recheckingPtu;

  /// No description provided for @controller_reconnectContinueRest.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{重新連線並繼續（剩 {count} 台）}}'**
  String controller_reconnectContinueRest(int count);

  /// No description provided for @controller_reconnectFailedAttempts.
  ///
  /// In zh, this message translates to:
  /// **'{attempts, plural, other{重新連線失敗（已嘗試 {attempts} 次），請靠近閘道器後再按一次}}'**
  String controller_reconnectFailedAttempts(int attempts);

  /// No description provided for @controller_reconnectLinkRun.
  ///
  /// In zh, this message translates to:
  /// **'重新連線閘道器'**
  String get controller_reconnectLinkRun;

  /// No description provided for @controller_reconnectedRescan.
  ///
  /// In zh, this message translates to:
  /// **'已重新連線，由閘道器重新掃描 PTU。'**
  String get controller_reconnectedRescan;

  /// No description provided for @controller_reconnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在重新連線閘道器'**
  String get controller_reconnecting;

  /// No description provided for @controller_rejoining.
  ///
  /// In zh, this message translates to:
  /// **'正在重新加入後台'**
  String get controller_rejoining;

  /// No description provided for @controller_relinkReconnect.
  ///
  /// In zh, this message translates to:
  /// **'手機與閘道器重新連線中…'**
  String get controller_relinkReconnect;

  /// No description provided for @controller_relinkReload.
  ///
  /// In zh, this message translates to:
  /// **'重新讀取 PTU 列表…'**
  String get controller_relinkReload;

  /// No description provided for @controller_relinkingLabel.
  ///
  /// In zh, this message translates to:
  /// **'重新連線中…'**
  String get controller_relinkingLabel;

  /// No description provided for @controller_relistingLabel.
  ///
  /// In zh, this message translates to:
  /// **'讀取列表中…'**
  String get controller_relistingLabel;

  /// No description provided for @controller_repairRequested.
  ///
  /// In zh, this message translates to:
  /// **'已要求重新連線，請重新確認上線與資料'**
  String get controller_repairRequested;

  /// No description provided for @controller_repairRun.
  ///
  /// In zh, this message translates to:
  /// **'重新連接閘道器'**
  String get controller_repairRun;

  /// No description provided for @controller_replaceBindChanged.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的 PTU 綁定已改變，請重新連線核對；尚未變更綁定。'**
  String get controller_replaceBindChanged;

  /// No description provided for @controller_replaceBleOff.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的 PTU 藍牙尚未啟用，請先確認裝置狀態；尚未變更綁定。'**
  String get controller_replaceBleOff;

  /// No description provided for @controller_replaceChanged.
  ///
  /// In zh, this message translates to:
  /// **'閘道器或綁定已改變，請重新確認要更換的 PTU。'**
  String get controller_replaceChanged;

  /// No description provided for @controller_replaceIdentityMismatch.
  ///
  /// In zh, this message translates to:
  /// **'閘道器身分、站點或一對一設定無法核對，請重新連線確認；未變更綁定。'**
  String get controller_replaceIdentityMismatch;

  /// No description provided for @controller_replaceJournalNotCleared.
  ///
  /// In zh, this message translates to:
  /// **'PTU 綁定已讀回，恢復紀錄尚未清除，請重新連線核對。'**
  String get controller_replaceJournalNotCleared;

  /// No description provided for @controller_replaceJournalSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法保存 PTU 更換恢復紀錄，未變更綁定。'**
  String get controller_replaceJournalSaveFailed;

  /// No description provided for @controller_replaceJournalUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'更換 PTU 的恢復紀錄無法讀取，請聯絡維護人員。'**
  String get controller_replaceJournalUnreadable;

  /// No description provided for @controller_replaceMustRestore.
  ///
  /// In zh, this message translates to:
  /// **'請先重新連線還原上次更換 PTU 的綁定，不能略過恢復紀錄。'**
  String get controller_replaceMustRestore;

  /// No description provided for @controller_replaceNotReadBack.
  ///
  /// In zh, this message translates to:
  /// **'新 PTU 綁定尚未讀回確認，已停止更換。'**
  String get controller_replaceNotReadBack;

  /// No description provided for @controller_replaceNotRestored.
  ///
  /// In zh, this message translates to:
  /// **'上次更換 PTU 尚未還原，請使用「{label}」先核對原綁定。'**
  String controller_replaceNotRestored(String label);

  /// No description provided for @controller_replaceOtherBinding.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已有另一筆 PTU 綁定，未覆寫；請重新連線核對。'**
  String get controller_replaceOtherBinding;

  /// No description provided for @controller_replacePending.
  ///
  /// In zh, this message translates to:
  /// **'上次更換尚未還原，請先取消並還原原綁定。'**
  String get controller_replacePending;

  /// No description provided for @controller_replacePtuConfirm.
  ///
  /// In zh, this message translates to:
  /// **'會解除閘道器對 PTU {mac} 的綁定（站點與 Wi-Fi 不變），通過裝置安全檢查後，透過手機藍牙在本機搜尋新的 PTU，原 PTU 不需在場。新綁定確認前取消或失敗會還原原綁定；藍牙中斷時請重新連線完成還原。後台同步與資料驗證仍需網路，尚未驗證前不算開通完成。'**
  String controller_replacePtuConfirm(String mac);

  /// No description provided for @controller_replacePtuConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'更換 PTU：解除綁定並重新配對？'**
  String get controller_replacePtuConfirmTitle;

  /// No description provided for @controller_replacePtuLabel.
  ///
  /// In zh, this message translates to:
  /// **'更換 PTU'**
  String get controller_replacePtuLabel;

  /// No description provided for @controller_replaceRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法進入「選擇 PTU」，且閘道器的 PTU 綁定未能還原成 {mac}：請重新連線這台閘道器確認綁定。'**
  String controller_replaceRestoreFailed(String mac);

  /// No description provided for @controller_replaceSearching.
  ///
  /// In zh, this message translates to:
  /// **'正在本機搜尋新 PTU；後台同步與資料驗證仍需網路。'**
  String get controller_replaceSearching;

  /// No description provided for @controller_replaceSetupRestored.
  ///
  /// In zh, this message translates to:
  /// **'PTU 配置未完成，已還原原綁定；請重新開始更換。'**
  String get controller_replaceSetupRestored;

  /// No description provided for @controller_replaceUnbindUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'閘道器尚未確認解除綁定，已停止更換。'**
  String get controller_replaceUnbindUnconfirmed;

  /// No description provided for @controller_replaceUnfinished.
  ///
  /// In zh, this message translates to:
  /// **'上次更換 PTU 尚未完成，請重新連線核對並還原原綁定。'**
  String get controller_replaceUnfinished;

  /// No description provided for @controller_replacingPtu.
  ///
  /// In zh, this message translates to:
  /// **'正在解除 PTU 綁定'**
  String get controller_replacingPtu;

  /// No description provided for @controller_reread.
  ///
  /// In zh, this message translates to:
  /// **'已重新讀取。{status}'**
  String controller_reread(String status);

  /// No description provided for @controller_rereadStatusRun.
  ///
  /// In zh, this message translates to:
  /// **'重新讀取閘道器狀態'**
  String get controller_rereadStatusRun;

  /// No description provided for @controller_rescanAfterLossLabel.
  ///
  /// In zh, this message translates to:
  /// **'重新連線並繼續'**
  String get controller_rescanAfterLossLabel;

  /// No description provided for @controller_rescanLabel.
  ///
  /// In zh, this message translates to:
  /// **'重新掃描'**
  String get controller_rescanLabel;

  /// No description provided for @controller_resetFailed.
  ///
  /// In zh, this message translates to:
  /// **'重置失敗（連線逾時），請靠近後重試'**
  String get controller_resetFailed;

  /// No description provided for @controller_resetNumberRun.
  ///
  /// In zh, this message translates to:
  /// **'重置編號，準備重新掃描'**
  String get controller_resetNumberRun;

  /// No description provided for @controller_resettingStale.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{發現 {count} 台殘留編號的 PTU，自動重置中}}'**
  String controller_resettingStale(int count);

  /// No description provided for @controller_restoredBind.
  ///
  /// In zh, this message translates to:
  /// **'已核對並還原原 PTU 綁定。網路尚需重新檢查。'**
  String get controller_restoredBind;

  /// No description provided for @controller_restoringBind.
  ///
  /// In zh, this message translates to:
  /// **'正在核對並還原原 PTU 綁定'**
  String get controller_restoringBind;

  /// No description provided for @controller_resume.
  ///
  /// In zh, this message translates to:
  /// **'上次中斷於{where}，{done}{inflight}{pending}。閘道器仍在運作，不需重新上電。'**
  String controller_resume(
    String where,
    String done,
    String inflight,
    String pending,
  );

  /// No description provided for @controller_resumeDone.
  ///
  /// In zh, this message translates to:
  /// **'已完成 {count} 台（{list}）'**
  String controller_resumeDone(int count, String list);

  /// No description provided for @controller_resumeInflight.
  ///
  /// In zh, this message translates to:
  /// **'，{list} 指派中斷、重新連線後以閘道器核對為準'**
  String controller_resumeInflight(String list);

  /// No description provided for @controller_resumeMonitoring.
  ///
  /// In zh, this message translates to:
  /// **'恢復監控'**
  String get controller_resumeMonitoring;

  /// No description provided for @controller_resumeNoneDone.
  ///
  /// In zh, this message translates to:
  /// **'尚未完成任何 PTU'**
  String get controller_resumeNoneDone;

  /// No description provided for @controller_resumePending.
  ///
  /// In zh, this message translates to:
  /// **'，尚有 {count} 台未配置'**
  String controller_resumePending(int count);

  /// No description provided for @controller_resumeUnknown.
  ///
  /// In zh, this message translates to:
  /// **'已保留先前進度，請重新連線以核對裝置現況。'**
  String get controller_resumeUnknown;

  /// No description provided for @controller_resumeWithoutLogin.
  ///
  /// In zh, this message translates to:
  /// **'未登入時無法自動收編殘留編號，將以手動模式繼續'**
  String get controller_resumeWithoutLogin;

  /// No description provided for @controller_retryAssignRun.
  ///
  /// In zh, this message translates to:
  /// **'重試指派失敗的 PTU'**
  String get controller_retryAssignRun;

  /// No description provided for @controller_reuseBlocked.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒連上 Wi-Fi 或還沒開始上傳資料，暫時不能使用此站點。請先按「改用其他 Wi-Fi」，或回到網路體檢確認。'**
  String get controller_reuseBlocked;

  /// No description provided for @controller_reuseStationPrompt.
  ///
  /// In zh, this message translates to:
  /// **'使用此站點，由閘道器搜尋 PTU，請確認要監控的裝置。'**
  String get controller_reuseStationPrompt;

  /// No description provided for @controller_savedStepFind.
  ///
  /// In zh, this message translates to:
  /// **'第 2 步（找到閘道器）'**
  String get controller_savedStepFind;

  /// No description provided for @controller_savedStepMonitor.
  ///
  /// In zh, this message translates to:
  /// **'第 8 步（開始監控）'**
  String get controller_savedStepMonitor;

  /// No description provided for @controller_savedStepNetCheck.
  ///
  /// In zh, this message translates to:
  /// **'第 3 步（閘道器網路體檢）'**
  String get controller_savedStepNetCheck;

  /// No description provided for @controller_savedStepSelect.
  ///
  /// In zh, this message translates to:
  /// **'第 7 步（選擇 PTU）'**
  String get controller_savedStepSelect;

  /// No description provided for @controller_savedStepUpload.
  ///
  /// In zh, this message translates to:
  /// **'第 5 步（確認資料上傳）'**
  String get controller_savedStepUpload;

  /// No description provided for @controller_savedStepVerify.
  ///
  /// In zh, this message translates to:
  /// **'第 9 步（驗證資料）'**
  String get controller_savedStepVerify;

  /// No description provided for @controller_scanIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'閘道器掃描未完成，請查看錯誤後按「{label}」。'**
  String controller_scanIncomplete(String label);

  /// No description provided for @controller_scanLinkLost.
  ///
  /// In zh, this message translates to:
  /// **'閘道器掃描未完成：藍牙連線已中斷。請靠近閘道器，再按「{label}」。'**
  String controller_scanLinkLost(String label);

  /// No description provided for @controller_scanRun.
  ///
  /// In zh, this message translates to:
  /// **'搜尋附近的閘道器'**
  String get controller_scanRun;

  /// No description provided for @controller_scanTestMode.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在測試模式，不會掃描 PTU。請按「{label}」，切換後 APP 會自動重新掃描。'**
  String controller_scanTestMode(String label);

  /// No description provided for @controller_scanningLabel.
  ///
  /// In zh, this message translates to:
  /// **'掃描中…'**
  String get controller_scanningLabel;

  /// No description provided for @controller_scanningPtus.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在掃描周邊 PTU，請稍候'**
  String get controller_scanningPtus;

  /// No description provided for @controller_selectedDoneRest.
  ///
  /// In zh, this message translates to:
  /// **'已選 {selected} 台 · 已完成 {done} 台 · 將配置 {rest} 台'**
  String controller_selectedDoneRest(int selected, int done, int rest);

  /// No description provided for @controller_selectedOfTarget.
  ///
  /// In zh, this message translates to:
  /// **'已選 {selected} / {target} 台'**
  String controller_selectedOfTarget(int selected, int target);

  /// No description provided for @controller_starApply.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前只連 {limit} 台；按下「配置」後，閘道器會切換為星狀並連線全部 PTU。'**
  String controller_starApply(int limit);

  /// No description provided for @controller_starOwnerUnknown.
  ///
  /// In zh, this message translates to:
  /// **'無法確認閘道器登記狀態，請手動重置'**
  String get controller_starOwnerUnknown;

  /// No description provided for @controller_startVerify.
  ///
  /// In zh, this message translates to:
  /// **'開始驗證'**
  String get controller_startVerify;

  /// No description provided for @controller_step7Retry.
  ///
  /// In zh, this message translates to:
  /// **'藍牙連線又中斷，{seconds} 秒後自動重新連線（第 {retry}/{total} 次重試）'**
  String controller_step7Retry(int seconds, int retry, int total);

  /// No description provided for @controller_stepWhere.
  ///
  /// In zh, this message translates to:
  /// **'第 {step} 步（{label}）'**
  String controller_stepWhere(int step, String label);

  /// No description provided for @controller_stoppedStep8.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{已停止。已完成的 {count} 台保留，可按「{label}」接續。}}'**
  String controller_stoppedStep8(int count, String label);

  /// Done page summary; the two optional clauses below are appended.
  ///
  /// In zh, this message translates to:
  /// **'掃到 {scanned} 台，本機配置 {configured} 台'**
  String controller_summary(int scanned, int configured);

  /// No description provided for @controller_summaryOtherGateways.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{，{count} 台屬於其他閘道器}}'**
  String controller_summaryOtherGateways(int count);

  /// No description provided for @controller_summaryResetFailed.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{，{count} 台重置失敗}}'**
  String controller_summaryResetFailed(int count);

  /// No description provided for @controller_switchingPick.
  ///
  /// In zh, this message translates to:
  /// **'正在讓閘道器改連 PTU {mac}'**
  String controller_switchingPick(String mac);

  /// No description provided for @controller_switchingTarget.
  ///
  /// In zh, this message translates to:
  /// **'正在把閘道器切到{target}（會重新開機，約 1 分鐘）'**
  String controller_switchingTarget(String target);

  /// No description provided for @controller_targetSwitched.
  ///
  /// In zh, this message translates to:
  /// **'已把閘道器切到{target}，閘道器已重新開機並重新連上。{next}'**
  String controller_targetSwitched(String target, String next);

  /// No description provided for @controller_targetUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'不用切換：閘道器本來就送到{target}（沒有重新開機）。{status}'**
  String controller_targetUnchanged(String target, String status);

  /// No description provided for @controller_tempRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'暫時綁定 {temp} 未能還原成 {restore}：{failure}'**
  String controller_tempRestoreFailed(
    String temp,
    String restore,
    String failure,
  );

  /// No description provided for @controller_tempUnbindFailed.
  ///
  /// In zh, this message translates to:
  /// **'暫時綁定 {temp} 未能解除：{failure}'**
  String controller_tempUnbindFailed(String temp, String failure);

  /// No description provided for @controller_thresholdReadback.
  ///
  /// In zh, this message translates to:
  /// **'寫入 {wanted}，回讀 {readBack}'**
  String controller_thresholdReadback(String wanted, String readBack);

  /// No description provided for @controller_topologyDirect.
  ///
  /// In zh, this message translates to:
  /// **'一對一'**
  String get controller_topologyDirect;

  /// No description provided for @controller_topologyRelistPending.
  ///
  /// In zh, this message translates to:
  /// **'{reason}，PTU 列表需重新讀取'**
  String controller_topologyRelistPending(String reason);

  /// No description provided for @controller_topologyRelistReading.
  ///
  /// In zh, this message translates to:
  /// **'{reason}，重新讀取 PTU 列表…'**
  String controller_topologyRelistReading(String reason);

  /// No description provided for @controller_topologyStar.
  ///
  /// In zh, this message translates to:
  /// **'星狀'**
  String get controller_topologyStar;

  /// No description provided for @controller_topologySwitched.
  ///
  /// In zh, this message translates to:
  /// **'已切換為{mode}'**
  String controller_topologySwitched(String mode);

  /// No description provided for @controller_unbindingRun.
  ///
  /// In zh, this message translates to:
  /// **'正在解除閘道器的 PTU 綁定'**
  String get controller_unbindingRun;

  /// No description provided for @controller_unreadable.
  ///
  /// In zh, this message translates to:
  /// **'（無法讀取）'**
  String get controller_unreadable;

  /// No description provided for @controller_updatingDirect.
  ///
  /// In zh, this message translates to:
  /// **'正在更新直連設定'**
  String get controller_updatingDirect;

  /// No description provided for @controller_uploadConnecting.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在連線，APP 會自動確認（最多約 2 分鐘）。'**
  String get controller_uploadConnecting;

  /// No description provided for @controller_uploadElsewhere.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料送到別的後台'**
  String get controller_uploadElsewhere;

  /// No description provided for @controller_uploadNotReady.
  ///
  /// In zh, this message translates to:
  /// **'要等閘道器連上 Wi-Fi 並開始上傳資料，才能繼續選擇 PTU。請等「確認資料上傳」出現 ✓，或再重設一次 Wi-Fi。'**
  String get controller_uploadNotReady;

  /// No description provided for @controller_uploadStarted.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已開始上傳資料。'**
  String get controller_uploadStarted;

  /// No description provided for @controller_verified.
  ///
  /// In zh, this message translates to:
  /// **'開通驗證通過，已恢復自動監控'**
  String get controller_verified;

  /// No description provided for @controller_verifyFailed.
  ///
  /// In zh, this message translates to:
  /// **'資料驗證未通過：\n{detail}'**
  String controller_verifyFailed(String detail);

  /// No description provided for @controller_verifyNoData.
  ///
  /// In zh, this message translates to:
  /// **'PTU #{id} 尚無資料'**
  String controller_verifyNoData(int id);

  /// No description provided for @controller_verifyProgress.
  ///
  /// In zh, this message translates to:
  /// **'資料驗證 {line}'**
  String controller_verifyProgress(String line);

  /// No description provided for @controller_verifyRun.
  ///
  /// In zh, this message translates to:
  /// **'確認每台 PTU 的資料持續進入後端'**
  String get controller_verifyRun;

  /// No description provided for @controller_verifySkipped.
  ///
  /// In zh, this message translates to:
  /// **'PTU #{id} 未驗證（已略過）'**
  String controller_verifySkipped(int id);

  /// No description provided for @controller_verifyStopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止驗證，可調整勾選後重新配置。'**
  String get controller_verifyStopped;

  /// No description provided for @controller_waitingBluetooth.
  ///
  /// In zh, this message translates to:
  /// **'等待藍牙就緒'**
  String get controller_waitingBluetooth;

  /// No description provided for @controller_wifiConnectedNext.
  ///
  /// In zh, this message translates to:
  /// **'WiFi 已連線，下一步確認後端看得到閘道器'**
  String get controller_wifiConnectedNext;

  /// No description provided for @controller_wifiFirstCheck.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已連上。網路體檢還有項目沒通過，請依下方提示處理。'**
  String get controller_wifiFirstCheck;

  /// No description provided for @controller_wifiFirstDone.
  ///
  /// In zh, this message translates to:
  /// **'網路已正常，接著設定站號。'**
  String get controller_wifiFirstDone;

  /// No description provided for @controller_wifiFirstPrompt.
  ///
  /// In zh, this message translates to:
  /// **'請先設定 Wi-Fi（閘道器只能用 2.4 GHz），網路正常後再設定站號。'**
  String get controller_wifiFirstPrompt;

  /// No description provided for @controller_wifiFirstRunLabel.
  ///
  /// In zh, this message translates to:
  /// **'設定 Wi-Fi'**
  String get controller_wifiFirstRunLabel;

  /// No description provided for @controller_wifiKept.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已連上 {ssid}，沿用'**
  String controller_wifiKept(String ssid);

  /// No description provided for @controller_wifiKeptDone.
  ///
  /// In zh, this message translates to:
  /// **'沿用 Wi-Fi {ssid}（未重新連線），下一步確認後端看得到閘道器'**
  String controller_wifiKeptDone(String ssid);

  /// No description provided for @controller_wifiOnlyPrompt.
  ///
  /// In zh, this message translates to:
  /// **'保留目前站點與 PTU，僅更新 Wi-Fi。'**
  String get controller_wifiOnlyPrompt;

  /// No description provided for @controller_wifiUpdatedChooseStation.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已更新，資料上傳正常。請確認站點：這台閘道器目前的站點若不是這裡，請選「改用其他站號」。'**
  String get controller_wifiUpdatedChooseStation;

  /// No description provided for @controller_wifiUpdatedKeepStation.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已更新，站點與 PTU 設定保留。接著確認資料有上傳。'**
  String get controller_wifiUpdatedKeepStation;

  /// No description provided for @controller_writingThreshold.
  ///
  /// In zh, this message translates to:
  /// **'正在寫入門檻 {dbm} dBm'**
  String controller_writingThreshold(String dbm);

  /// No description provided for @controller_wrongDevice.
  ///
  /// In zh, this message translates to:
  /// **'指派到錯誤裝置，請重試'**
  String get controller_wrongDevice;

  /// No description provided for @coreProgressChecklist_connectBackend.
  ///
  /// In zh, this message translates to:
  /// **'後台連線正常'**
  String get coreProgressChecklist_connectBackend;

  /// Checklist items of the automatic pages (plain words).
  ///
  /// In zh, this message translates to:
  /// **'藍牙連線'**
  String get coreProgressChecklist_connectBle;

  /// No description provided for @coreProgressChecklist_connectStatus.
  ///
  /// In zh, this message translates to:
  /// **'讀取閘道器狀態'**
  String get coreProgressChecklist_connectStatus;

  /// No description provided for @coreProgressChecklist_connectWifi.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已連線'**
  String get coreProgressChecklist_connectWifi;

  /// Data verification progress, several PTUs.
  ///
  /// In zh, this message translates to:
  /// **'每台 {count}/{need} 筆'**
  String coreProgressChecklist_dataEach(int count, int need);

  /// Data verification progress, one PTU.
  ///
  /// In zh, this message translates to:
  /// **'收到 {count}/{need} 筆'**
  String coreProgressChecklist_dataReceived(int count, int need);

  /// No description provided for @coreProgressChecklist_finishAssign.
  ///
  /// In zh, this message translates to:
  /// **'指派 PTU'**
  String get coreProgressChecklist_finishAssign;

  /// No description provided for @coreProgressChecklist_finishAssignTotal.
  ///
  /// In zh, this message translates to:
  /// **'{total, plural, other{指派 PTU（共 {total} 台）}}'**
  String coreProgressChecklist_finishAssignTotal(int total);

  /// No description provided for @coreProgressChecklist_finishBind.
  ///
  /// In zh, this message translates to:
  /// **'寫入 PTU 綁定'**
  String get coreProgressChecklist_finishBind;

  /// No description provided for @coreProgressChecklist_finishData.
  ///
  /// In zh, this message translates to:
  /// **'驗證資料上傳'**
  String get coreProgressChecklist_finishData;

  /// No description provided for @coreProgressChecklist_finishJoin.
  ///
  /// In zh, this message translates to:
  /// **'加入監控'**
  String get coreProgressChecklist_finishJoin;

  /// No description provided for @coreProgressChecklist_finishJoined.
  ///
  /// In zh, this message translates to:
  /// **'核對已加入監控'**
  String get coreProgressChecklist_finishJoined;

  /// No description provided for @coreProgressChecklist_finishList.
  ///
  /// In zh, this message translates to:
  /// **'寫入 PTU 名單'**
  String get coreProgressChecklist_finishList;

  /// No description provided for @coreProgressChecklist_finishSettings.
  ///
  /// In zh, this message translates to:
  /// **'寫入 PTU 設定'**
  String get coreProgressChecklist_finishSettings;

  /// Failed checklist item without a usable reason.
  ///
  /// In zh, this message translates to:
  /// **'沒有完成'**
  String get coreProgressChecklist_notDone;

  /// No description provided for @coreProgressChecklist_onlineBackend.
  ///
  /// In zh, this message translates to:
  /// **'連上後台'**
  String get coreProgressChecklist_onlineBackend;

  /// No description provided for @coreProgressChecklist_onlineBeat1.
  ///
  /// In zh, this message translates to:
  /// **'收到第 1 次心跳'**
  String get coreProgressChecklist_onlineBeat1;

  /// No description provided for @coreProgressChecklist_onlineBeat2.
  ///
  /// In zh, this message translates to:
  /// **'收到第 2 次心跳（持續上線）'**
  String get coreProgressChecklist_onlineBeat2;

  /// No description provided for @coreProgressChecklist_onlineTarget.
  ///
  /// In zh, this message translates to:
  /// **'上傳目標確認'**
  String get coreProgressChecklist_onlineTarget;

  /// No description provided for @coreProgressChecklist_targetCurrent.
  ///
  /// In zh, this message translates to:
  /// **'送到目前的後台'**
  String get coreProgressChecklist_targetCurrent;

  /// No description provided for @coreProgressChecklist_targetLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地測試'**
  String get coreProgressChecklist_targetLocal;

  /// No description provided for @dashboardApi_backend.
  ///
  /// In zh, this message translates to:
  /// **'後端 {origin}'**
  String dashboardApi_backend(String origin);

  /// No description provided for @dashboardApi_backendLocal.
  ///
  /// In zh, this message translates to:
  /// **'區域網路／本機後端 {origin}'**
  String dashboardApi_backendLocal(String origin);

  /// describeBackend without a URL. Also written (in Chinese) into the install report.
  ///
  /// In zh, this message translates to:
  /// **'（尚未設定後端網址）'**
  String get dashboardApi_backendUnset;

  /// No description provided for @directCalibrationSheet_intro.
  ///
  /// In zh, this message translates to:
  /// **'本樁與鄰近樁請維持實際擺放與電源。取樣 {seconds} 秒後建議門檻，確認後才寫入閘道器。'**
  String directCalibrationSheet_intro(int seconds);

  /// No description provided for @directCalibrationSheet_legacyFirmware.
  ///
  /// In zh, this message translates to:
  /// **'閘道器韌體較舊，未回報'**
  String get directCalibrationSheet_legacyFirmware;

  /// No description provided for @directCalibrationSheet_median.
  ///
  /// In zh, this message translates to:
  /// **'中位數 {value}'**
  String directCalibrationSheet_median(String value);

  /// No description provided for @directCalibrationSheet_medianSkipped.
  ///
  /// In zh, this message translates to:
  /// **'中位數 {value}（未列入上限）'**
  String directCalibrationSheet_medianSkipped(String value);

  /// No description provided for @directCalibrationSheet_neighborLegacy.
  ///
  /// In zh, this message translates to:
  /// **'鄰近訊號取自閘道器最近一次選台聽到的其他 PTU（峰值），連線後不再更新。'**
  String get directCalibrationSheet_neighborLegacy;

  /// No description provided for @directCalibrationSheet_neighborLive.
  ///
  /// In zh, this message translates to:
  /// **'鄰近訊號為閘道器連線中持續聽到的其他 PTU（峰值；{maxAge} 秒內都列入計算）。'**
  String directCalibrationSheet_neighborLive(int maxAge);

  /// No description provided for @directCalibrationSheet_noNeighbor.
  ///
  /// In zh, this message translates to:
  /// **'未聽到鄰近 PTU'**
  String get directCalibrationSheet_noNeighbor;

  /// No description provided for @directCalibrationSheet_notRead.
  ///
  /// In zh, this message translates to:
  /// **'尚未讀到'**
  String get directCalibrationSheet_notRead;

  /// No description provided for @directCalibrationSheet_notReported.
  ///
  /// In zh, this message translates to:
  /// **'閘道器未回報'**
  String get directCalibrationSheet_notReported;

  /// No description provided for @directCalibrationSheet_ownAdv.
  ///
  /// In zh, this message translates to:
  /// **'本樁廣播訊號'**
  String get directCalibrationSheet_ownAdv;

  /// No description provided for @directCalibrationSheet_ownLink.
  ///
  /// In zh, this message translates to:
  /// **'本樁連線訊號'**
  String get directCalibrationSheet_ownLink;

  /// median and weakest are already formatted with dBm.
  ///
  /// In zh, this message translates to:
  /// **'中位數 {median} · 最弱 {weakest}（{count} 筆）'**
  String directCalibrationSheet_ownLinkValue(
    String median,
    String weakest,
    int count,
  );

  /// No description provided for @directCalibrationSheet_ownPtu.
  ///
  /// In zh, this message translates to:
  /// **'本樁 PTU：{mac}'**
  String directCalibrationSheet_ownPtu(String mac);

  /// No description provided for @directCalibrationSheet_peak.
  ///
  /// In zh, this message translates to:
  /// **'峰值 {value}'**
  String directCalibrationSheet_peak(String value);

  /// No description provided for @directCalibrationSheet_range.
  ///
  /// In zh, this message translates to:
  /// **'可用範圍 {lower} ～ {upper}：本樁選得到、連上後不會被踢，本樁關機時也不會連到鄰近樁。'**
  String directCalibrationSheet_range(String lower, String upper);

  /// No description provided for @directCalibrationSheet_resample.
  ///
  /// In zh, this message translates to:
  /// **'重新取樣'**
  String get directCalibrationSheet_resample;

  /// No description provided for @directCalibrationSheet_sampleDone.
  ///
  /// In zh, this message translates to:
  /// **'{reads, plural, other{取樣完成（讀取 {reads} 次）}}'**
  String directCalibrationSheet_sampleDone(int reads);

  /// No description provided for @directCalibrationSheet_sampling.
  ///
  /// In zh, this message translates to:
  /// **'取樣中… 剩 {left} 秒（已讀取 {reads} 次）'**
  String directCalibrationSheet_sampling(int left, int reads);

  /// No description provided for @directCalibrationSheet_saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'門檻未寫入閘道器，請重試。'**
  String get directCalibrationSheet_saveFailed;

  /// No description provided for @directCalibrationSheet_saved.
  ///
  /// In zh, this message translates to:
  /// **'{label}：{value} dBm'**
  String directCalibrationSheet_saved(String label, int value);

  /// No description provided for @directCalibrationSheet_strongestNeighbor.
  ///
  /// In zh, this message translates to:
  /// **'最強鄰近訊號'**
  String get directCalibrationSheet_strongestNeighbor;

  /// No description provided for @directCalibrationSheet_suggestion.
  ///
  /// In zh, this message translates to:
  /// **'建議門檻：{threshold} dBm（目前 {current} dBm）'**
  String directCalibrationSheet_suggestion(int threshold, int current);

  /// No description provided for @directCalibrationSheet_tiesAll.
  ///
  /// In zh, this message translates to:
  /// **'{count} 台相差 {db} dB 內，一併列出'**
  String directCalibrationSheet_tiesAll(int count, int db);

  /// No description provided for @directCalibrationSheet_tiesListed.
  ///
  /// In zh, this message translates to:
  /// **'{ties} 台相差 {db} dB 內，列出 {listed} 台'**
  String directCalibrationSheet_tiesListed(int ties, int db, int listed);

  /// Two sentences joined: why the signals are too close, and what to do.
  ///
  /// In zh, this message translates to:
  /// **'{reason}。{advice}。'**
  String directCalibrationSheet_tooClose(String reason, String advice);

  /// No description provided for @directCalibrationSheet_write.
  ///
  /// In zh, this message translates to:
  /// **'寫入閘道器'**
  String get directCalibrationSheet_write;

  /// No description provided for @directCalibrationSheet_writeValue.
  ///
  /// In zh, this message translates to:
  /// **'寫入閘道器（{threshold} dBm）'**
  String directCalibrationSheet_writeValue(int threshold);

  /// No description provided for @directCalibrationSheet_writing.
  ///
  /// In zh, this message translates to:
  /// **'寫入中…'**
  String get directCalibrationSheet_writing;

  /// No description provided for @directCalibration_ambiguous.
  ///
  /// In zh, this message translates to:
  /// **'本樁與鄰近樁的廣播訊號相差不到 {db} dB：選台時可能判為不確定，綁定後就不受影響。'**
  String directCalibration_ambiguous(int db);

  /// No description provided for @directCalibration_fewSamples.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{有 {count} 台鄰近 PTU 讀數較少（不足 {min} 筆），已計入下限但可能不穩定，請按「{rescan}」再取樣一次。}}'**
  String directCalibration_fewSamples(int count, int min, String rescan);

  /// No description provided for @directCalibration_gapEqual.
  ///
  /// In zh, this message translates to:
  /// **'鄰近樁 {neighbor} 和本樁一樣強'**
  String directCalibration_gapEqual(String neighbor);

  /// No description provided for @directCalibration_gapSmall.
  ///
  /// In zh, this message translates to:
  /// **'鄰近樁 {neighbor} 只比本樁弱 {gap} dB，餘裕不足（至少要弱 {min} dB）'**
  String directCalibration_gapSmall(String neighbor, int gap, int min);

  /// No description provided for @directCalibration_gapStronger.
  ///
  /// In zh, this message translates to:
  /// **'鄰近樁 {neighbor} 比本樁還強 {db} dB'**
  String directCalibration_gapStronger(String neighbor, int db);

  /// No description provided for @directCalibration_holdLabel.
  ///
  /// In zh, this message translates to:
  /// **'維持目前門檻（{hold} dBm），不需寫入'**
  String directCalibration_holdLabel(int hold);

  /// No description provided for @directCalibration_needsOwn.
  ///
  /// In zh, this message translates to:
  /// **'請先在第 7 步按「辨識此樁」確認本樁 PTU，再校正門檻。'**
  String get directCalibration_needsOwn;

  /// No description provided for @directCalibration_neighborsAndMore.
  ///
  /// In zh, this message translates to:
  /// **'{named} 等 {total} 台'**
  String directCalibration_neighborsAndMore(String named, int total);

  /// No description provided for @directCalibration_noNeighbor.
  ///
  /// In zh, this message translates to:
  /// **'未偵測到鄰近 PTU（已連線的 PTU 不會廣播），無法確認放寬是否安全，建議維持 {hold} dBm。'**
  String directCalibration_noNeighbor(int hold);

  /// No description provided for @directCalibration_noOwn.
  ///
  /// In zh, this message translates to:
  /// **'未取得本樁 PTU 的連線訊號（閘道器目前沒有連著已確認的 PTU），無法建議門檻。請確認本樁 PTU 已連上後重新取樣。'**
  String get directCalibration_noOwn;

  /// No description provided for @directCalibration_outOfRange.
  ///
  /// In zh, this message translates to:
  /// **'本樁讀數已超出閘道器可用範圍（-100～-20 dBm），請重新取樣'**
  String get directCalibration_outOfRange;

  /// No description provided for @directCalibration_ownBelowHold.
  ///
  /// In zh, this message translates to:
  /// **'本樁 PTU 訊號偏弱（可用上限 {upper} dBm，低於門檻 {hold} dBm），但沒有鄰近資料不能放寬門檻：請確認已開啟「確認後綁定 PTU」（綁定後不受門檻影響），或調整 PTU 擺放後重新取樣。'**
  String directCalibration_ownBelowHold(int upper, int hold);

  /// No description provided for @directCalibration_referenceLegacy.
  ///
  /// In zh, this message translates to:
  /// **'參考值（閘道器韌體較舊）'**
  String get directCalibration_referenceLegacy;

  /// No description provided for @directCalibration_referenceNoAdv.
  ///
  /// In zh, this message translates to:
  /// **'參考值（閘道器未回報本樁廣播訊號）'**
  String get directCalibration_referenceNoAdv;

  /// No description provided for @directCalibration_referenceStaleAdv.
  ///
  /// In zh, this message translates to:
  /// **'參考值（本樁廣播值超過 {minutes} 分鐘，上限只用連線訊號）'**
  String directCalibration_referenceStaleAdv(int minutes);

  /// No description provided for @directCalibration_referenceUndatedAdv.
  ///
  /// In zh, this message translates to:
  /// **'參考值（本樁廣播值未附選台時間，上限只用連線訊號）'**
  String get directCalibration_referenceUndatedAdv;

  /// No description provided for @directCalibration_rescanLabel.
  ///
  /// In zh, this message translates to:
  /// **'重新掃描鄰近'**
  String get directCalibration_rescanLabel;

  /// No description provided for @directCalibration_saved.
  ///
  /// In zh, this message translates to:
  /// **'已寫入閘道器（重開機仍保留）'**
  String get directCalibration_saved;

  /// No description provided for @directCalibration_selfAdvMinutes.
  ///
  /// In zh, this message translates to:
  /// **'本樁廣播值來自 {minutes} 分鐘前選台'**
  String directCalibration_selfAdvMinutes(int minutes);

  /// No description provided for @directCalibration_selfAdvSeconds.
  ///
  /// In zh, this message translates to:
  /// **'本樁廣播值來自 {seconds} 秒前選台'**
  String directCalibration_selfAdvSeconds(int seconds);

  /// No description provided for @directCalibration_selfAdvUndated.
  ///
  /// In zh, this message translates to:
  /// **'本樁廣播值未附選台時間'**
  String get directCalibration_selfAdvUndated;

  /// No description provided for @directCalibration_stale.
  ///
  /// In zh, this message translates to:
  /// **'鄰近資料已 {age} 秒未更新（超過 {max} 秒，未列入計算），請按「{rescan}」再取樣一次。'**
  String directCalibration_stale(int age, int max, String rescan);

  /// Title / button of the direct-mode RSSI threshold calibration.
  ///
  /// In zh, this message translates to:
  /// **'校正門檻'**
  String get directCalibration_title;

  /// No description provided for @directCalibration_tooClose.
  ///
  /// In zh, this message translates to:
  /// **'鄰近樁訊號太強，無法只靠門檻區分，請在確認後綁定此 PTU'**
  String get directCalibration_tooClose;

  /// No description provided for @directModePanel_askBackOffice.
  ///
  /// In zh, this message translates to:
  /// **'請後台協助'**
  String get directModePanel_askBackOffice;

  /// No description provided for @directModePanel_autoThreshold.
  ///
  /// In zh, this message translates to:
  /// **'自動連線門檻：{value} dBm（預設 {defaultValue}）'**
  String directModePanel_autoThreshold(int value, int defaultValue);

  /// No description provided for @directModePanel_bindCurrent.
  ///
  /// In zh, this message translates to:
  /// **'綁定目前 PTU'**
  String get directModePanel_bindCurrent;

  /// No description provided for @directModePanel_bindOnConfirm.
  ///
  /// In zh, this message translates to:
  /// **'確認後綁定 PTU'**
  String get directModePanel_bindOnConfirm;

  /// No description provided for @directModePanel_bindOnConfirmOff.
  ///
  /// In zh, this message translates to:
  /// **'關閉後不會鎖定 MAC：本樁 PTU 關機或斷線時，閘道器可能改連鄰近樁的 PTU'**
  String get directModePanel_bindOnConfirmOff;

  /// No description provided for @directModePanel_bindOnConfirmOn.
  ///
  /// In zh, this message translates to:
  /// **'按「{label}」時把該 PTU 的 MAC 存進閘道器，之後只連這台'**
  String directModePanel_bindOnConfirmOn(String label);

  /// No description provided for @directModePanel_bound.
  ///
  /// In zh, this message translates to:
  /// **'已綁定 {mac}'**
  String directModePanel_bound(String mac);

  /// No description provided for @directModePanel_boundOnly.
  ///
  /// In zh, this message translates to:
  /// **'已綁定 {mac}，只連這台'**
  String directModePanel_boundOnly(String mac);

  /// No description provided for @directModePanel_calibrateButton.
  ///
  /// In zh, this message translates to:
  /// **'{title}（現場取樣 {seconds} 秒）'**
  String directModePanel_calibrateButton(String title, int seconds);

  /// No description provided for @directModePanel_cancelAction.
  ///
  /// In zh, this message translates to:
  /// **'取消操作'**
  String get directModePanel_cancelAction;

  /// No description provided for @directModePanel_candidatesHint.
  ///
  /// In zh, this message translates to:
  /// **'附近候選（{count}）：點選後閘道器會綁定並改連那一台，再按「辨識此樁」確認。'**
  String directModePanel_candidatesHint(int count);

  /// No description provided for @directModePanel_cannotBind.
  ///
  /// In zh, this message translates to:
  /// **'尚未連上 PTU，無法綁定'**
  String get directModePanel_cannotBind;

  /// No description provided for @directModePanel_causeBound.
  ///
  /// In zh, this message translates to:
  /// **'已綁定 PTU {mac}：閘道器只連這台。若本樁已更換 PTU，請按「解除綁定」後重新搜尋。'**
  String directModePanel_causeBound(String mac);

  /// label is the finish-without-PTU button name.
  ///
  /// In zh, this message translates to:
  /// **'PTU 暫時不在場（尚未安裝或斷電）：按「{label}」，閘道器照常加入運作，PTU 上電後會自動連上。'**
  String directModePanel_causeDefer(String label);

  /// No description provided for @directModePanel_causeDenied.
  ///
  /// In zh, this message translates to:
  /// **'附近的 PTU 已綁定給其他充電樁（已自動略過）；本樁 PTU 可能尚未上電。'**
  String get directModePanel_causeDenied;

  /// No description provided for @directModePanel_causeHelp.
  ///
  /// In zh, this message translates to:
  /// **'仍找不到：按「請後台協助」，後台可看到閘道器狀態協助判斷。'**
  String get directModePanel_causeHelp;

  /// No description provided for @directModePanel_causeHousing.
  ///
  /// In zh, this message translates to:
  /// **'擺放或機殼遮蔽：PTU 要和閘道器裝在同一個機殼內；金屬外殼、天線被擋住都會讓訊號變弱。'**
  String get directModePanel_causeHousing;

  /// No description provided for @directModePanel_causeNone.
  ///
  /// In zh, this message translates to:
  /// **'沒有聽到任何 PTU，請確認本樁 PTU 電源（門檻 {min} dBm）。'**
  String directModePanel_causeNone(int min);

  /// No description provided for @directModePanel_causePower.
  ///
  /// In zh, this message translates to:
  /// **'本樁 PTU 沒有上電：確認 PTU 電源開啟、指示燈有亮。'**
  String get directModePanel_causePower;

  /// No description provided for @directModePanel_causeWeak.
  ///
  /// In zh, this message translates to:
  /// **'附近 PTU 訊號太弱（{rssi} dBm，門檻 {min}）：PTU {mac} 可能是鄰近樁的 PTU——請不要為了連上而放寬門檻。'**
  String directModePanel_causeWeak(String rssi, int min, String mac);

  /// No description provided for @directModePanel_collecting.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在重新收集附近的 PTU，約需 5–10 秒…'**
  String get directModePanel_collecting;

  /// No description provided for @directModePanel_currentPick.
  ///
  /// In zh, this message translates to:
  /// **'目前選中'**
  String get directModePanel_currentPick;

  /// No description provided for @directModePanel_gatewayBusy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器處理中，請稍候…'**
  String get directModePanel_gatewayBusy;

  /// No description provided for @directModePanel_hintConfirm.
  ///
  /// In zh, this message translates to:
  /// **'確認閃燈的是這台 PTU，再開始監控'**
  String get directModePanel_hintConfirm;

  /// No description provided for @directModePanel_hintIdentify.
  ///
  /// In zh, this message translates to:
  /// **'點「辨識此樁」，確認現場燈號'**
  String get directModePanel_hintIdentify;

  /// No description provided for @directModePanel_identifyDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'辨識訊息'**
  String get directModePanel_identifyDetailTitle;

  /// Button: blink this charger's PTU and gateway.
  ///
  /// In zh, this message translates to:
  /// **'辨識此樁'**
  String get directModePanel_identifyThis;

  /// No description provided for @directModePanel_keep.
  ///
  /// In zh, this message translates to:
  /// **'保留'**
  String get directModePanel_keep;

  /// No description provided for @directModePanel_linkedNow.
  ///
  /// In zh, this message translates to:
  /// **'目前連線：{mac}'**
  String directModePanel_linkedNow(String mac);

  /// No description provided for @directModePanel_macLabel.
  ///
  /// In zh, this message translates to:
  /// **'裝置編號（MAC）'**
  String get directModePanel_macLabel;

  /// No description provided for @directModePanel_moreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get directModePanel_moreActions;

  /// No description provided for @directModePanel_noCandidates.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前沒有回報附近候選，請按「重新搜尋」或稍後再試。'**
  String get directModePanel_noCandidates;

  /// No description provided for @directModePanel_noPick.
  ///
  /// In zh, this message translates to:
  /// **'尚未取得閘道器的選台結果，請按「重新搜尋」。'**
  String get directModePanel_noPick;

  /// No description provided for @directModePanel_noPtuTitle.
  ///
  /// In zh, this message translates to:
  /// **'找不到本樁 PTU：可能原因與處理'**
  String get directModePanel_noPtuTitle;

  /// No description provided for @directModePanel_notLinked.
  ///
  /// In zh, this message translates to:
  /// **'閘道器尚未連上 PTU'**
  String get directModePanel_notLinked;

  /// No description provided for @directModePanel_notThis.
  ///
  /// In zh, this message translates to:
  /// **'不是這台？'**
  String get directModePanel_notThis;

  /// No description provided for @directModePanel_pickOther.
  ///
  /// In zh, this message translates to:
  /// **'改選其他 PTU'**
  String get directModePanel_pickOther;

  /// No description provided for @directModePanel_pickedTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器選中的 PTU'**
  String get directModePanel_pickedTitle;

  /// No description provided for @directModePanel_readingPick.
  ///
  /// In zh, this message translates to:
  /// **'正在讀取閘道器的選台結果…'**
  String get directModePanel_readingPick;

  /// Why the gateway picked this PTU; reason comes from the gateway's select_reason text.
  ///
  /// In zh, this message translates to:
  /// **'選台依據：{reason}'**
  String directModePanel_reason(String reason);

  /// No description provided for @directModePanel_release.
  ///
  /// In zh, this message translates to:
  /// **'解除'**
  String get directModePanel_release;

  /// No description provided for @directModePanel_searchAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新搜尋'**
  String get directModePanel_searchAgain;

  /// No description provided for @directModePanel_settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'直連進階設定'**
  String get directModePanel_settingsTitle;

  /// No description provided for @directModePanel_signalLabel.
  ///
  /// In zh, this message translates to:
  /// **'訊號'**
  String get directModePanel_signalLabel;

  /// No description provided for @directModePanel_switchToThis.
  ///
  /// In zh, this message translates to:
  /// **'改連這台'**
  String get directModePanel_switchToThis;

  /// No description provided for @directModePanel_threshold.
  ///
  /// In zh, this message translates to:
  /// **'門檻 {min} dBm'**
  String directModePanel_threshold(int min);

  /// No description provided for @directModePanel_thresholdHelp.
  ///
  /// In zh, this message translates to:
  /// **'閘道器只自動連線訊號強於門檻的 PTU；數值越大（越接近 -20）要越靠近。'**
  String get directModePanel_thresholdHelp;

  /// No description provided for @directModePanel_unbind.
  ///
  /// In zh, this message translates to:
  /// **'解除綁定'**
  String get directModePanel_unbind;

  /// No description provided for @directModePanel_unbound.
  ///
  /// In zh, this message translates to:
  /// **'未綁定'**
  String get directModePanel_unbound;

  /// No description provided for @directModePanel_watchLights.
  ///
  /// In zh, this message translates to:
  /// **'按下後請看樁上 PTU 與閘道器的燈號'**
  String get directModePanel_watchLights;

  /// No description provided for @directMode_ackPlain.
  ///
  /// In zh, this message translates to:
  /// **'{note}；{gateway}。'**
  String directMode_ackPlain(String note, String gateway);

  /// No description provided for @directMode_ackWithNumber.
  ///
  /// In zh, this message translates to:
  /// **'{note}（#{number}）；{gateway}。'**
  String directMode_ackWithNumber(String note, String number, String gateway);

  /// No description provided for @directMode_advRssi.
  ///
  /// In zh, this message translates to:
  /// **'廣播 {rssi} dBm（連線訊號讀取中）'**
  String directMode_advRssi(int rssi);

  /// Link RSSI still unread: the last advertising RSSI, marked as such.
  ///
  /// In zh, this message translates to:
  /// **'{rssi} dBm（廣播值）'**
  String directMode_advStale(int rssi);

  /// No description provided for @directMode_ambiguous.
  ///
  /// In zh, this message translates to:
  /// **'附近有訊號相近的 PTU，請按「辨識此樁」確認是否為眼前這台'**
  String get directMode_ambiguous;

  /// Main button of the direct pick: this PTU is the one, start the setup.
  ///
  /// In zh, this message translates to:
  /// **'是這台，開始配置'**
  String get directMode_confirmLabel;

  /// No description provided for @directMode_hintBoundMissing.
  ///
  /// In zh, this message translates to:
  /// **'已綁定的 PTU 不在場，請確認其電源；若已更換 PTU，請解除綁定'**
  String get directMode_hintBoundMissing;

  /// No description provided for @directMode_hintNoCandidate.
  ///
  /// In zh, this message translates to:
  /// **'請靠近／確認同樁 PTU 已上電'**
  String get directMode_hintNoCandidate;

  /// No description provided for @directMode_identifyConfirmTimeout.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已送出；舊版閘道器未取得 PTU 確認，請看樁上燈號'**
  String get directMode_identifyConfirmTimeout;

  /// No description provided for @directMode_identifyConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'PTU 已確認亮燈'**
  String get directMode_identifyConfirmed;

  /// Main button label until the shown PTU is identified. 「辨識此樁」 is the identify button.
  ///
  /// In zh, this message translates to:
  /// **'請先按「辨識此樁」確認'**
  String get directMode_identifyFirstLabel;

  /// No description provided for @directMode_identifyFirstText.
  ///
  /// In zh, this message translates to:
  /// **'請先按「辨識此樁」確認是眼前這台，再按「{confirm}」。'**
  String directMode_identifyFirstText(String confirm);

  /// No description provided for @directMode_identifyNoPtu.
  ///
  /// In zh, this message translates to:
  /// **'閘道器雙閃 4 秒；閘道器尚未連上 PTU，PTU 不會閃燈。'**
  String get directMode_identifyNoPtu;

  /// No description provided for @directMode_identifyPending.
  ///
  /// In zh, this message translates to:
  /// **'已送出，等待閘道器回應…'**
  String get directMode_identifyPending;

  /// No description provided for @directMode_identifySent.
  ///
  /// In zh, this message translates to:
  /// **'已送出，請看樁上燈號'**
  String get directMode_identifySent;

  /// One-line bottom bar form of directMode_identifySent.
  ///
  /// In zh, this message translates to:
  /// **'已送出 · 請看樁上燈號'**
  String get directMode_identifySentLine;

  /// No description provided for @directMode_identifyUnsupportedPattern.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已送出；PTU 不支援此燈效，請看樁上燈號'**
  String get directMode_identifyUnsupportedPattern;

  /// No description provided for @directMode_lineGatewayOnly.
  ///
  /// In zh, this message translates to:
  /// **'已送出 · 只有閘道器閃燈，PTU 未收到'**
  String get directMode_lineGatewayOnly;

  /// No description provided for @directMode_lineOffSent.
  ///
  /// In zh, this message translates to:
  /// **'已送出關燈指令'**
  String get directMode_lineOffSent;

  /// No description provided for @directMode_lineStopPtuNotSent.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已停止辨識 · PTU 關燈未送出'**
  String get directMode_lineStopPtuNotSent;

  /// No description provided for @directMode_lineTimeout.
  ///
  /// In zh, this message translates to:
  /// **'已送出 · PTU 未回應確認 · 請看樁上燈號'**
  String get directMode_lineTimeout;

  /// No description provided for @directMode_lineUnsupportedPattern.
  ///
  /// In zh, this message translates to:
  /// **'已送出 · PTU 不支援此燈效 · 請看樁上燈號'**
  String get directMode_lineUnsupportedPattern;

  /// No description provided for @directMode_noteGatewayOnly.
  ///
  /// In zh, this message translates to:
  /// **'已送出：只有閘道器在閃燈，PTU 未收到（{reason}）'**
  String directMode_noteGatewayOnly(String reason);

  /// No description provided for @directMode_noteOffSent.
  ///
  /// In zh, this message translates to:
  /// **'已送出關燈指令；{gateway}。PTU 不回覆，請查看燈號。'**
  String directMode_noteOffSent(String gateway);

  /// No description provided for @directMode_noteStopPtuNotSent.
  ///
  /// In zh, this message translates to:
  /// **'{gateway}；PTU 關燈未送出（{reason}）'**
  String directMode_noteStopPtuNotSent(String gateway, String reason);

  /// An identify note followed by its detail in brackets.
  ///
  /// In zh, this message translates to:
  /// **'{head}（{detail}）'**
  String directMode_noteWithDetail(String head, String detail);

  /// No description provided for @directMode_ptuFailedBlinking.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在閃燈（{seconds} 秒）；PTU 指令未送出（{reason}）。'**
  String directMode_ptuFailedBlinking(int seconds, String reason);

  /// No description provided for @directMode_ptuFailedStop.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已停止辨識；PTU 關燈未送出（{reason}）。'**
  String directMode_ptuFailedStop(String reason);

  /// No description provided for @directMode_ptuWriteAmbiguousTarget.
  ///
  /// In zh, this message translates to:
  /// **'閘道器連著多台 PTU，沒有指定哪一台'**
  String get directMode_ptuWriteAmbiguousTarget;

  /// No description provided for @directMode_ptuWriteFailed.
  ///
  /// In zh, this message translates to:
  /// **'閘道器寫入 PTU 失敗'**
  String get directMode_ptuWriteFailed;

  /// No description provided for @directMode_ptuWriteNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'閘道器尚未連上 PTU'**
  String get directMode_ptuWriteNotConnected;

  /// No description provided for @directMode_ptuWriteOther.
  ///
  /// In zh, this message translates to:
  /// **'PTU 沒有收到指令'**
  String get directMode_ptuWriteOther;

  /// No description provided for @directMode_reasonAmbiguous.
  ///
  /// In zh, this message translates to:
  /// **'附近訊號相近，閘道器暫選最強的一台'**
  String get directMode_reasonAmbiguous;

  /// No description provided for @directMode_reasonBound.
  ///
  /// In zh, this message translates to:
  /// **'已綁定這台，閘道器只連它'**
  String get directMode_reasonBound;

  /// Why the gateway picked this PTU (select_reason ok).
  ///
  /// In zh, this message translates to:
  /// **'訊號最強且明確'**
  String get directMode_reasonOk;

  /// No description provided for @directMode_reasonResume.
  ///
  /// In zh, this message translates to:
  /// **'延續既有連線'**
  String get directMode_reasonResume;

  /// No description provided for @directMode_remoteGateway.
  ///
  /// In zh, this message translates to:
  /// **'後台讓閘道器閃燈（請看閘道器上的燈）'**
  String get directMode_remoteGateway;

  /// Short first line of the back office identify notice; keep all remoteHead texts short (one line of a 360 dp bar).
  ///
  /// In zh, this message translates to:
  /// **'後台已讓此樁閃燈 · PTU 已確認'**
  String get directMode_remoteHeadConfirmed;

  /// No description provided for @directMode_remoteHeadGatewayOnly.
  ///
  /// In zh, this message translates to:
  /// **'後台已讓閘道器閃燈 · PTU 未收到'**
  String get directMode_remoteHeadGatewayOnly;

  /// No description provided for @directMode_remoteHeadOffSent.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出關燈指令'**
  String get directMode_remoteHeadOffSent;

  /// No description provided for @directMode_remoteHeadPtuSent.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出 PTU 辨識指令'**
  String get directMode_remoteHeadPtuSent;

  /// No description provided for @directMode_remoteHeadSent.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出 · 請查看燈號'**
  String get directMode_remoteHeadSent;

  /// No description provided for @directMode_remoteHeadStopped.
  ///
  /// In zh, this message translates to:
  /// **'後台已停止閘道器辨識'**
  String get directMode_remoteHeadStopped;

  /// No description provided for @directMode_remoteHeadTimeout.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出 · 舊版未取得確認'**
  String get directMode_remoteHeadTimeout;

  /// No description provided for @directMode_remoteHeadUnsupportedPattern.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出 · PTU 不支援燈效'**
  String get directMode_remoteHeadUnsupportedPattern;

  /// No description provided for @directMode_remoteOffNotSent.
  ///
  /// In zh, this message translates to:
  /// **'後台：{gateway}；PTU 關燈未送出'**
  String directMode_remoteOffNotSent(String gateway);

  /// No description provided for @directMode_remoteOffSent.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出 PTU 關燈指令；{gateway}'**
  String directMode_remoteOffSent(String gateway);

  /// No description provided for @directMode_remoteSentPtu.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出 PTU {label} 辨識指令（請看樁上燈號）'**
  String directMode_remoteSentPtu(String label);

  /// No description provided for @directMode_remoteSentPtuUnnamed.
  ///
  /// In zh, this message translates to:
  /// **'後台已送出 PTU 辨識指令（請看樁上燈號）'**
  String get directMode_remoteSentPtuUnnamed;

  /// No description provided for @directMode_resultGatewayOnly.
  ///
  /// In zh, this message translates to:
  /// **'只有閘道器閃燈（{reason}）'**
  String directMode_resultGatewayOnly(String reason);

  /// No description provided for @directMode_resultIdentifySent.
  ///
  /// In zh, this message translates to:
  /// **'PTU 辨識指令已送出'**
  String get directMode_resultIdentifySent;

  /// No description provided for @directMode_resultOffSent.
  ///
  /// In zh, this message translates to:
  /// **'PTU 關燈指令已送出'**
  String get directMode_resultOffSent;

  /// No description provided for @directMode_resultTimeout.
  ///
  /// In zh, this message translates to:
  /// **'舊版閘道器未取得 PTU 確認'**
  String get directMode_resultTimeout;

  /// No description provided for @directMode_resultUnsupportedPattern.
  ///
  /// In zh, this message translates to:
  /// **'PTU 不支援此燈效'**
  String get directMode_resultUnsupportedPattern;

  /// A direct-mode candidate's advertising peak.
  ///
  /// In zh, this message translates to:
  /// **'峰值 {rssi} dBm'**
  String directMode_rssiPeak(int rssi);

  /// The gateway's pick has no link RSSI reading yet.
  ///
  /// In zh, this message translates to:
  /// **'訊號讀取中…'**
  String get directMode_rssiReading;

  /// No description provided for @directMode_settlingLabel.
  ///
  /// In zh, this message translates to:
  /// **'連線建立中…'**
  String get directMode_settlingLabel;

  /// No description provided for @directMode_stateBoundMissing.
  ///
  /// In zh, this message translates to:
  /// **'已綁定的 PTU 不在場'**
  String get directMode_stateBoundMissing;

  /// No description provided for @directMode_stateConnected.
  ///
  /// In zh, this message translates to:
  /// **'已連上 PTU'**
  String get directMode_stateConnected;

  /// No description provided for @directMode_stateConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在連線 PTU'**
  String get directMode_stateConnecting;

  /// No description provided for @directMode_stateNoCandidate.
  ///
  /// In zh, this message translates to:
  /// **'找不到夠近的 PTU'**
  String get directMode_stateNoCandidate;

  /// No description provided for @directMode_stateScanning.
  ///
  /// In zh, this message translates to:
  /// **'正在尋找最近的 PTU'**
  String get directMode_stateScanning;

  /// No description provided for @directMode_strayBind.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前綁定 PTU {mac}'**
  String directMode_strayBind(String mac);

  /// No description provided for @directMode_strayBindHint.
  ///
  /// In zh, this message translates to:
  /// **'這個綁定不是在本機確認過的：保留則閘道器只連這台；解除則恢復自動選最近的 PTU。'**
  String get directMode_strayBindHint;

  /// No description provided for @directMode_switched.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已切換到另一顆 PTU（{mac}），請重新辨識'**
  String directMode_switched(String mac);

  /// No description provided for @directMode_unbindFailed.
  ///
  /// In zh, this message translates to:
  /// **'已取消，但閘道器的暫時綁定（PTU {mac}）未能解除；下次進入第 7 步會再詢問是否解除。'**
  String directMode_unbindFailed(String mac);

  /// No description provided for @directMode_unbindRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'已取消，但閘道器的 PTU 綁定未能還原成原本的 {restore}；請重新連線這台閘道器確認綁定。'**
  String directMode_unbindRestoreFailed(String restore);

  /// No description provided for @directMode_unbindTempRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'已取消，但閘道器的暫時綁定（PTU {mac}）未能還原成原本的綁定 {restore}；下次進入第 7 步會再詢問。'**
  String directMode_unbindTempRestoreFailed(String mac, String restore);

  /// No description provided for @directMode_waitingLabel.
  ///
  /// In zh, this message translates to:
  /// **'等待閘道器連上 PTU'**
  String get directMode_waitingLabel;

  /// No description provided for @directPickActivity_ambiguousIdentify.
  ///
  /// In zh, this message translates to:
  /// **'訊號相近，請辨識此樁'**
  String get directPickActivity_ambiguousIdentify;

  /// No description provided for @directPickActivity_boundMissing.
  ///
  /// In zh, this message translates to:
  /// **'已綁定的 PTU 不在場'**
  String get directPickActivity_boundMissing;

  /// No description provided for @directPickActivity_connected.
  ///
  /// In zh, this message translates to:
  /// **'等待閘道器回報選中的 PTU'**
  String get directPickActivity_connected;

  /// No description provided for @directPickActivity_connecting.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在連線 PTU'**
  String get directPickActivity_connecting;

  /// No description provided for @directPickActivity_foundConfirm.
  ///
  /// In zh, this message translates to:
  /// **'已找到 PTU，請確認是眼前此樁'**
  String get directPickActivity_foundConfirm;

  /// No description provided for @directPickActivity_foundIdentify.
  ///
  /// In zh, this message translates to:
  /// **'已找到 PTU，請辨識此樁'**
  String get directPickActivity_foundIdentify;

  /// No description provided for @directPickActivity_gatewayEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'閘道器'**
  String get directPickActivity_gatewayEndpoint;

  /// No description provided for @directPickActivity_identifySent.
  ///
  /// In zh, this message translates to:
  /// **'已送出辨識，請確認燈號'**
  String get directPickActivity_identifySent;

  /// No description provided for @directPickActivity_noCandidate.
  ///
  /// In zh, this message translates to:
  /// **'尚未找到 PTU，請確認電源'**
  String get directPickActivity_noCandidate;

  /// No description provided for @directPickActivity_noStatus.
  ///
  /// In zh, this message translates to:
  /// **'尚未取得 PTU 狀態'**
  String get directPickActivity_noStatus;

  /// No description provided for @directPickActivity_reading.
  ///
  /// In zh, this message translates to:
  /// **'正在讀取 PTU 狀態'**
  String get directPickActivity_reading;

  /// No description provided for @directPickActivity_scanning.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在搜尋 PTU'**
  String get directPickActivity_scanning;

  /// No description provided for @directPickActivity_unavailable.
  ///
  /// In zh, this message translates to:
  /// **'連線待確認，請依提示重試'**
  String get directPickActivity_unavailable;

  /// task is the running operation's label; 「取消操作」 is the page's cancel-operation button.
  ///
  /// In zh, this message translates to:
  /// **'正在進行「{task}」，完成或按「取消操作」後才能切換。'**
  String environmentSwitch_blocked(String task);

  /// No description provided for @environmentSwitch_blockedPrep.
  ///
  /// In zh, this message translates to:
  /// **'正在進行「{task}」，完成後才能切換。'**
  String environmentSwitch_blockedPrep(String task);

  /// No description provided for @environmentSwitch_changeIp.
  ///
  /// In zh, this message translates to:
  /// **'變更電腦 IP'**
  String get environmentSwitch_changeIp;

  /// No description provided for @environmentSwitch_customNotSet.
  ///
  /// In zh, this message translates to:
  /// **'使用自訂的後端網址（尚未設定）'**
  String get environmentSwitch_customNotSet;

  /// No description provided for @environmentSwitch_customUrl.
  ///
  /// In zh, this message translates to:
  /// **'使用自訂的後端網址：{url}'**
  String environmentSwitch_customUrl(String url);

  /// No description provided for @environmentSwitch_editIp.
  ///
  /// In zh, this message translates to:
  /// **'可修改測試主機的 IP：'**
  String get environmentSwitch_editIp;

  /// No description provided for @environmentSwitch_localNoHost.
  ///
  /// In zh, this message translates to:
  /// **'資料送到這台電腦上的測試主機（還沒設定電腦 IP）'**
  String get environmentSwitch_localNoHost;

  /// No description provided for @environmentSwitch_localWithHost.
  ///
  /// In zh, this message translates to:
  /// **'資料送到這台電腦上的測試主機（{host}）'**
  String environmentSwitch_localWithHost(String host);

  /// No description provided for @environmentSwitch_noIp.
  ///
  /// In zh, this message translates to:
  /// **'還沒有測試主機的 IP，請按「自動尋找」或直接輸入。'**
  String get environmentSwitch_noIp;

  /// No description provided for @environmentSwitch_productionHint.
  ///
  /// In zh, this message translates to:
  /// **'資料送到正式站。'**
  String get environmentSwitch_productionHint;

  /// No description provided for @environmentSwitch_productionSheetHint.
  ///
  /// In zh, this message translates to:
  /// **'資料送到正式站'**
  String get environmentSwitch_productionSheetHint;

  /// No description provided for @environmentSwitch_sheetSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'手機和已連上的閘道器會一起切換。'**
  String get environmentSwitch_sheetSubtitle;

  /// Tooltip of the AppBar environment chip and title of the environment sheet.
  ///
  /// In zh, this message translates to:
  /// **'切換連線環境'**
  String get environmentSwitch_title;

  /// No description provided for @environmentSwitch_urlLabel.
  ///
  /// In zh, this message translates to:
  /// **'後端網址'**
  String get environmentSwitch_urlLabel;

  /// No description provided for @environmentSwitch_useLocal.
  ///
  /// In zh, this message translates to:
  /// **'使用本地測試'**
  String get environmentSwitch_useLocal;

  /// No description provided for @environmentSwitch_useUrl.
  ///
  /// In zh, this message translates to:
  /// **'使用這個網址'**
  String get environmentSwitch_useUrl;

  /// No description provided for @fieldHelpSheet_demo.
  ///
  /// In zh, this message translates to:
  /// **'示範模式不會傳送，請直接唸下面的資訊。'**
  String get fieldHelpSheet_demo;

  /// No description provided for @fieldHelpSheet_label.
  ///
  /// In zh, this message translates to:
  /// **'請後台協助'**
  String get fieldHelpSheet_label;

  /// No description provided for @fieldHelpSheet_needsConnection.
  ///
  /// In zh, this message translates to:
  /// **'已切換後台，請先連線到新的後台，再重新求助。'**
  String get fieldHelpSheet_needsConnection;

  /// No description provided for @fieldHelpSheet_noPassword.
  ///
  /// In zh, this message translates to:
  /// **'不會傳送 Wi-Fi 密碼。'**
  String get fieldHelpSheet_noPassword;

  /// No description provided for @fieldHelpSheet_queued.
  ///
  /// In zh, this message translates to:
  /// **'⚠ 目前送不出去（{reason}），後台暫時看不到。請在電話中直接唸下面的資訊。'**
  String fieldHelpSheet_queued(String reason);

  /// No description provided for @fieldHelpSheet_queuedNoReason.
  ///
  /// In zh, this message translates to:
  /// **'沒有網路／尚未登入後台'**
  String get fieldHelpSheet_queuedNoReason;

  /// No description provided for @fieldHelpSheet_readOut.
  ///
  /// In zh, this message translates to:
  /// **'請唸給後台：'**
  String get fieldHelpSheet_readOut;

  /// No description provided for @fieldHelpSheet_resend.
  ///
  /// In zh, this message translates to:
  /// **'重新傳送'**
  String get fieldHelpSheet_resend;

  /// No description provided for @fieldHelpSheet_sending.
  ///
  /// In zh, this message translates to:
  /// **'正在通知後台…'**
  String get fieldHelpSheet_sending;

  /// No description provided for @fieldHelpSheet_sent.
  ///
  /// In zh, this message translates to:
  /// **'✓ 求助已送達後台'**
  String get fieldHelpSheet_sent;

  /// No description provided for @fieldHelpSheet_unsupported.
  ///
  /// In zh, this message translates to:
  /// **'後台版本還不支援線上通知，請直接唸下面的資訊。'**
  String get fieldHelpSheet_unsupported;

  /// No description provided for @fieldReport_backendRefused.
  ///
  /// In zh, this message translates to:
  /// **'後台拒收（HTTP {status}）'**
  String fieldReport_backendRefused(String status);

  /// Why the install report failed (screen only).
  ///
  /// In zh, this message translates to:
  /// **'已切換後台，報告沒有送出'**
  String get fieldReport_backendSwitched;

  /// No description provided for @fieldReport_backendUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'後台尚未支援（請更新後台）'**
  String get fieldReport_backendUnsupported;

  /// No description provided for @fieldReport_helpCode.
  ///
  /// In zh, this message translates to:
  /// **'狀況代碼：{code}'**
  String fieldReport_helpCode(String code);

  /// No description provided for @fieldReport_helpCondition.
  ///
  /// In zh, this message translates to:
  /// **'狀況：{label}'**
  String fieldReport_helpCondition(String label);

  /// No description provided for @fieldReport_helpError.
  ///
  /// In zh, this message translates to:
  /// **'錯誤：{error}'**
  String fieldReport_helpError(String error);

  /// No description provided for @fieldReport_helpFirmwareDirect.
  ///
  /// In zh, this message translates to:
  /// **'韌體 {fw} · 直連'**
  String fieldReport_helpFirmwareDirect(String fw);

  /// No description provided for @fieldReport_helpFirmwareStar.
  ///
  /// In zh, this message translates to:
  /// **'韌體 {fw} · 星狀 {count} 台'**
  String fieldReport_helpFirmwareStar(String fw, int count);

  /// No description provided for @fieldReport_helpGatewayName.
  ///
  /// In zh, this message translates to:
  /// **'閘道器 {name}'**
  String fieldReport_helpGatewayName(String name);

  /// No description provided for @fieldReport_helpGatewayNameMac.
  ///
  /// In zh, this message translates to:
  /// **'閘道器 {name}（MAC 後 4 碼 {tail}）'**
  String fieldReport_helpGatewayNameMac(String name, String tail);

  /// No description provided for @fieldReport_helpNoGateway.
  ///
  /// In zh, this message translates to:
  /// **'還沒連上閘道器'**
  String get fieldReport_helpNoGateway;

  /// Help sheet line the installer reads to the back office.
  ///
  /// In zh, this message translates to:
  /// **'站 {site} / 閘道器 {gateway}'**
  String fieldReport_helpStationGateway(String site, String gateway);

  /// No description provided for @fieldReport_helpStationGatewayMac.
  ///
  /// In zh, this message translates to:
  /// **'站 {site} / 閘道器 {gateway}（MAC 後 4 碼 {tail}）'**
  String fieldReport_helpStationGatewayMac(
    String site,
    String gateway,
    String tail,
  );

  /// No description provided for @fieldReport_helpStep.
  ///
  /// In zh, this message translates to:
  /// **'目前第 {step} 步：{label}'**
  String fieldReport_helpStep(int step, String label);

  /// No description provided for @fieldReport_noNetwork.
  ///
  /// In zh, this message translates to:
  /// **'沒有網路或後台沒有回應'**
  String get fieldReport_noNetwork;

  /// No description provided for @fieldReport_notLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'尚未登入後台'**
  String get fieldReport_notLoggedIn;

  /// No description provided for @fieldReport_removedFromOutbox.
  ///
  /// In zh, this message translates to:
  /// **'已從手機的待送清單移除'**
  String get fieldReport_removedFromOutbox;

  /// No description provided for @fieldSupportPanel_askAgain.
  ///
  /// In zh, this message translates to:
  /// **'再次求助'**
  String get fieldSupportPanel_askAgain;

  /// No description provided for @fieldSupportPanel_checkFirst.
  ///
  /// In zh, this message translates to:
  /// **'請先核對目前畫面與設備，再依指引操作。'**
  String get fieldSupportPanel_checkFirst;

  /// No description provided for @fieldSupportPanel_confirmFailed.
  ///
  /// In zh, this message translates to:
  /// **'尚未確認回覆結果，請重新整理；若指引更新，請看完後再回覆。'**
  String get fieldSupportPanel_confirmFailed;

  /// No description provided for @fieldSupportPanel_fetchFailed.
  ///
  /// In zh, this message translates to:
  /// **'暫時無法取得後台回覆；以下若有內容是上次收到的，請重新整理或電話聯絡。'**
  String get fieldSupportPanel_fetchFailed;

  /// step is the commissioning step the installer was on when the back office replied.
  ///
  /// In zh, this message translates to:
  /// **'後台指引 · 當時第 {step} 步'**
  String fieldSupportPanel_instructionHeader(String step);

  /// time is already formatted as HH:mm.
  ///
  /// In zh, this message translates to:
  /// **'後台指引 · 當時第 {step} 步 · {time}'**
  String fieldSupportPanel_instructionHeaderAt(String step, String time);

  /// No description provided for @fieldSupportPanel_instructionTarget.
  ///
  /// In zh, this message translates to:
  /// **'指引對象：站 {site} / 閘道器 {gateway} · MAC {mac}'**
  String fieldSupportPanel_instructionTarget(
    String site,
    String gateway,
    String mac,
  );

  /// No description provided for @fieldSupportPanel_notConnected.
  ///
  /// In zh, this message translates to:
  /// **'請先連線到目前選擇的後台，再查看協助回覆。'**
  String get fieldSupportPanel_notConnected;

  /// No description provided for @fieldSupportPanel_otherGateway.
  ///
  /// In zh, this message translates to:
  /// **'這是其他閘道器的協助紀錄，請勿照做；請更新求助資訊，讓後台確認目前設備。'**
  String get fieldSupportPanel_otherGateway;

  /// No description provided for @fieldSupportPanel_refresh.
  ///
  /// In zh, this message translates to:
  /// **'重新整理回覆'**
  String get fieldSupportPanel_refresh;

  /// No description provided for @fieldSupportPanel_reopenHint.
  ///
  /// In zh, this message translates to:
  /// **'關閉後可點頂部「請後台協助」再次查看回覆。'**
  String get fieldSupportPanel_reopenHint;

  /// No description provided for @fieldSupportPanel_replying.
  ///
  /// In zh, this message translates to:
  /// **'回覆中…'**
  String get fieldSupportPanel_replying;

  /// No description provided for @fieldSupportPanel_resolved.
  ///
  /// In zh, this message translates to:
  /// **'已解決'**
  String get fieldSupportPanel_resolved;

  /// No description provided for @fieldSupportPanel_stateCallSupport.
  ///
  /// In zh, this message translates to:
  /// **'請電話聯絡後台協助'**
  String get fieldSupportPanel_stateCallSupport;

  /// No description provided for @fieldSupportPanel_stateHandling.
  ///
  /// In zh, this message translates to:
  /// **'後台已接手，處理中'**
  String get fieldSupportPanel_stateHandling;

  /// No description provided for @fieldSupportPanel_stateLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在取得協助狀態…'**
  String get fieldSupportPanel_stateLoading;

  /// No description provided for @fieldSupportPanel_statePending.
  ///
  /// In zh, this message translates to:
  /// **'等待後台接手'**
  String get fieldSupportPanel_statePending;

  /// No description provided for @fieldSupportPanel_stateResolved.
  ///
  /// In zh, this message translates to:
  /// **'你已確認解決'**
  String get fieldSupportPanel_stateResolved;

  /// No description provided for @fieldSupportPanel_stateWaitingField.
  ///
  /// In zh, this message translates to:
  /// **'後台已提供指引，請操作後回覆'**
  String get fieldSupportPanel_stateWaitingField;

  /// No description provided for @fieldSupportPanel_stillHelp.
  ///
  /// In zh, this message translates to:
  /// **'仍需協助'**
  String get fieldSupportPanel_stillHelp;

  /// No description provided for @fieldSupportPanel_unavailable.
  ///
  /// In zh, this message translates to:
  /// **'目前無法在 APP 查看文字回覆，請將下方設備與步驟資訊告知後台。'**
  String get fieldSupportPanel_unavailable;

  /// No description provided for @fieldSupportPanel_updateRequest.
  ///
  /// In zh, this message translates to:
  /// **'更新求助資訊'**
  String get fieldSupportPanel_updateRequest;

  /// No description provided for @gatewayDiscovery_backendNoRecordNote.
  ///
  /// In zh, this message translates to:
  /// **'目前後台查無此設備紀錄。若尚未開通，請點選『開始開通』；若已開通，請確認連線狀態與所選站點。'**
  String get gatewayDiscovery_backendNoRecordNote;

  /// No description provided for @gatewayDiscovery_backendOfflineNote.
  ///
  /// In zh, this message translates to:
  /// **'後台目前未收到此設備的連線訊號。請確認電源與 Wi-Fi；若已更換網路環境，請重新設定 Wi-Fi。'**
  String get gatewayDiscovery_backendOfflineNote;

  /// No description provided for @gatewayDiscovery_backendReferenceNote.
  ///
  /// In zh, this message translates to:
  /// **'沒有本機身分核對紀錄時，後端狀態只參考相同站號及閘道器編號；連線後再確認裝置身分。'**
  String get gatewayDiscovery_backendReferenceNote;

  /// No description provided for @gatewayDiscovery_backendRefreshNote.
  ///
  /// In zh, this message translates to:
  /// **'後端狀態每 15 秒更新，僅代表目前選擇的後端環境。'**
  String get gatewayDiscovery_backendRefreshNote;

  /// Card button: open the Bluetooth link to the selected gateway.
  ///
  /// In zh, this message translates to:
  /// **'藍牙連線'**
  String get gatewayDiscovery_bluetoothConnect;

  /// No description provided for @gatewayDiscovery_busy.
  ///
  /// In zh, this message translates to:
  /// **'正在連線並讀取設定…'**
  String get gatewayDiscovery_busy;

  /// No description provided for @gatewayDiscovery_cancelConnect.
  ///
  /// In zh, this message translates to:
  /// **'取消連線'**
  String get gatewayDiscovery_cancelConnect;

  /// No description provided for @gatewayDiscovery_cleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'藍牙清理未完成，請重試斷開。'**
  String get gatewayDiscovery_cleanupFailed;

  /// No description provided for @gatewayDiscovery_cleanupIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'清理未完成'**
  String get gatewayDiscovery_cleanupIncomplete;

  /// Bottom button for the selected gateway.
  ///
  /// In zh, this message translates to:
  /// **'開始開通：{title}'**
  String gatewayDiscovery_connectLabel(String title);

  /// No description provided for @gatewayDiscovery_connecting.
  ///
  /// In zh, this message translates to:
  /// **'連線中…'**
  String get gatewayDiscovery_connecting;

  /// No description provided for @gatewayDiscovery_disconnect.
  ///
  /// In zh, this message translates to:
  /// **'斷開'**
  String get gatewayDiscovery_disconnect;

  /// No description provided for @gatewayDiscovery_disconnecting.
  ///
  /// In zh, this message translates to:
  /// **'斷開中…'**
  String get gatewayDiscovery_disconnecting;

  /// Line after the search when the nearest hint is shown below it.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{找到 {count} 台}}'**
  String gatewayDiscovery_found(int count);

  /// Live count under the search progress bar.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{已找到 {count} 台}}'**
  String gatewayDiscovery_foundCount(int count);

  /// Line after the search; asks to tap the gateway of this charger.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{找到 {count} 台，請點選本樁的那台}}'**
  String gatewayDiscovery_foundPick(int count);

  /// No description provided for @gatewayDiscovery_gatewayOnlyBoundMissingNote.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已閃燈；找不到已綁定的 PTU，請確認原 PTU 已開機並在附近'**
  String get gatewayDiscovery_gatewayOnlyBoundMissingNote;

  /// No description provided for @gatewayDiscovery_gatewayOnlyHint.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已閃・PTU 不會閃'**
  String get gatewayDiscovery_gatewayOnlyHint;

  /// No description provided for @gatewayDiscovery_gatewayOnlyNoPtuNote.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已閃燈；閘道器附近沒聽到 PTU，請確認 PTU 已上電'**
  String get gatewayDiscovery_gatewayOnlyNoPtuNote;

  /// No description provided for @gatewayDiscovery_gatewayOnlyNote.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已閃燈；它目前沒連到 PTU，PTU 不會閃'**
  String get gatewayDiscovery_gatewayOnlyNote;

  /// No description provided for @gatewayDiscovery_gatewayOnlyPickingNote.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已閃燈；閘道器正在選擇 PTU，請 3 秒後再按'**
  String get gatewayDiscovery_gatewayOnlyPickingNote;

  /// No description provided for @gatewayDiscovery_gatewayOnlySnack.
  ///
  /// In zh, this message translates to:
  /// **'{title}：{note}'**
  String gatewayDiscovery_gatewayOnlySnack(String title, String note);

  /// No description provided for @gatewayDiscovery_gatewayOnlySwitchedNote.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已閃燈；已切換為一對一，閘道器正在重新尋找 PTU，請稍後再按'**
  String get gatewayDiscovery_gatewayOnlySwitchedNote;

  /// No description provided for @gatewayDiscovery_gatewayOnlyWeakNote.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已閃燈；PTU 訊號太弱（最強 {best} dBm，需 ≥ {min}），請靠近或檢查天線'**
  String gatewayDiscovery_gatewayOnlyWeakNote(int best, int min);

  /// No description provided for @gatewayDiscovery_held.
  ///
  /// In zh, this message translates to:
  /// **'已連線'**
  String get gatewayDiscovery_held;

  /// No description provided for @gatewayDiscovery_holdFailed.
  ///
  /// In zh, this message translates to:
  /// **'連線失敗'**
  String get gatewayDiscovery_holdFailed;

  /// No description provided for @gatewayDiscovery_holdFailedText.
  ///
  /// In zh, this message translates to:
  /// **'無法連線 {title}，請按「藍牙連線」重試'**
  String gatewayDiscovery_holdFailedText(String title);

  /// No description provided for @gatewayDiscovery_holdLost.
  ///
  /// In zh, this message translates to:
  /// **'已斷線'**
  String get gatewayDiscovery_holdLost;

  /// No description provided for @gatewayDiscovery_holdLostText.
  ///
  /// In zh, this message translates to:
  /// **'{title} 的藍牙連線已中斷，請按「藍牙連線」重新連線'**
  String gatewayDiscovery_holdLostText(String title);

  /// No description provided for @gatewayDiscovery_identifiedHint.
  ///
  /// In zh, this message translates to:
  /// **'已送出'**
  String get gatewayDiscovery_identifiedHint;

  /// SnackBar after the identify blink was sent; title is the gateway title.
  ///
  /// In zh, this message translates to:
  /// **'{title} 已送出'**
  String gatewayDiscovery_identifiedSnack(String title);

  /// No description provided for @gatewayDiscovery_identifyIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'辨識未完成，請重新連線後再試。'**
  String get gatewayDiscovery_identifyIncomplete;

  /// Tooltip of the bulb icon that blinks the gateway.
  ///
  /// In zh, this message translates to:
  /// **'閃燈辨識'**
  String get gatewayDiscovery_identifyLabel;

  /// No description provided for @gatewayDiscovery_nearbyGroup.
  ///
  /// In zh, this message translates to:
  /// **'附近裝置（{count}）'**
  String gatewayDiscovery_nearbyGroup(int count);

  /// No description provided for @gatewayDiscovery_notConnected.
  ///
  /// In zh, this message translates to:
  /// **'未連線'**
  String get gatewayDiscovery_notConnected;

  /// No description provided for @gatewayDiscovery_notFound.
  ///
  /// In zh, this message translates to:
  /// **'未發現附近閘道器。請確認電源、靠近裝置，並確認沒有被其他手機連線。'**
  String get gatewayDiscovery_notFound;

  /// Small badge on a gateway card: identity not verified yet.
  ///
  /// In zh, this message translates to:
  /// **'待核對'**
  String get gatewayDiscovery_pending;

  /// No description provided for @gatewayDiscovery_pickCardHint.
  ///
  /// In zh, this message translates to:
  /// **'先選擇要配置的閘道器卡片，再點「藍牙連線」'**
  String get gatewayDiscovery_pickCardHint;

  /// No description provided for @gatewayDiscovery_pickFirst.
  ///
  /// In zh, this message translates to:
  /// **'請先選擇閘道器'**
  String get gatewayDiscovery_pickFirst;

  /// No description provided for @gatewayDiscovery_recentGroup.
  ///
  /// In zh, this message translates to:
  /// **'最近使用'**
  String get gatewayDiscovery_recentGroup;

  /// No description provided for @gatewayDiscovery_retryDisconnect.
  ///
  /// In zh, this message translates to:
  /// **'重試斷開'**
  String get gatewayDiscovery_retryDisconnect;

  /// No description provided for @gatewayDiscovery_retrying.
  ///
  /// In zh, this message translates to:
  /// **'沒找到，再搜尋一次…'**
  String get gatewayDiscovery_retrying;

  /// No description provided for @gatewayDiscovery_rssiNote.
  ///
  /// In zh, this message translates to:
  /// **'RSSI 為手機收到的藍牙訊號，與後端在線狀態不同。'**
  String get gatewayDiscovery_rssiNote;

  /// No description provided for @gatewayDiscovery_scanFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜尋失敗，請確認藍牙、定位與附近裝置權限後重試。'**
  String get gatewayDiscovery_scanFailed;

  /// No description provided for @gatewayDiscovery_searchAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新搜尋'**
  String get gatewayDiscovery_searchAgain;

  /// No description provided for @gatewayDiscovery_searchPaused.
  ///
  /// In zh, this message translates to:
  /// **'已選取閘道器，搜尋已暫停'**
  String get gatewayDiscovery_searchPaused;

  /// No description provided for @gatewayDiscovery_searching.
  ///
  /// In zh, this message translates to:
  /// **'正在搜尋附近的閘道器…'**
  String get gatewayDiscovery_searching;

  /// No description provided for @gatewayDiscovery_selectNearby.
  ///
  /// In zh, this message translates to:
  /// **'選擇附近的閘道器'**
  String get gatewayDiscovery_selectNearby;

  /// No description provided for @gatewayDiscovery_selected.
  ///
  /// In zh, this message translates to:
  /// **'已選取'**
  String get gatewayDiscovery_selected;

  /// No description provided for @gatewayDiscovery_signalLost.
  ///
  /// In zh, this message translates to:
  /// **'訊號中斷'**
  String get gatewayDiscovery_signalLost;

  /// No description provided for @gatewayDiscovery_signalUnknown.
  ///
  /// In zh, this message translates to:
  /// **'訊號未知'**
  String get gatewayDiscovery_signalUnknown;

  /// No description provided for @gatewayDiscovery_startCommissioning.
  ///
  /// In zh, this message translates to:
  /// **'開始開通'**
  String get gatewayDiscovery_startCommissioning;

  /// No description provided for @gatewayDiscovery_stopSearch.
  ///
  /// In zh, this message translates to:
  /// **'停止搜尋'**
  String get gatewayDiscovery_stopSearch;

  /// No description provided for @gatewayDiscovery_stopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止搜尋，按〔重新搜尋〕再找一次'**
  String get gatewayDiscovery_stopped;

  /// Small badge on a gateway card: not configured yet.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get gatewayDiscovery_unconfigured;

  /// No description provided for @gatewayIdentity_confirmOnlineLabel.
  ///
  /// In zh, this message translates to:
  /// **'確認閘道器上線'**
  String get gatewayIdentity_confirmOnlineLabel;

  /// Yellow direct-mode notice. Logic recognises it by the text before {mac}, in every language.
  ///
  /// In zh, this message translates to:
  /// **'閘道器連到的是附近另一台閘道器（{mac}），不是 PTU，APP 不會把它當成 PTU。請按「不是這台？」改選同樁的 PTU，或靠近同樁 PTU 後按「重新搜尋」。'**
  String gatewayIdentity_directGatewayPick(String mac);

  /// A gateway's identity: site number and gateway number.
  ///
  /// In zh, this message translates to:
  /// **'站 {site} · 閘道器 {gateway}'**
  String gatewayIdentity_idText(int site, int gateway);

  /// No description provided for @gatewayIdentity_leaveTestModeLabel.
  ///
  /// In zh, this message translates to:
  /// **'切回正常模式'**
  String get gatewayIdentity_leaveTestModeLabel;

  /// No description provided for @gatewayIdentity_leavingTestMode.
  ///
  /// In zh, this message translates to:
  /// **'正在把閘道器切回正常模式（會重新開機，約 1 分鐘）'**
  String get gatewayIdentity_leavingTestMode;

  /// No description provided for @gatewayIdentity_leftTestMode.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已切回正常模式並重新連上，可以繼續配置。'**
  String get gatewayIdentity_leftTestMode;

  /// No description provided for @gatewayIdentity_macTail.
  ///
  /// In zh, this message translates to:
  /// **'MAC 後 4 碼 {tail}'**
  String gatewayIdentity_macTail(String tail);

  /// Wi-Fi MAC tail, with the Bluetooth MAC tail the phone sees in brackets.
  ///
  /// In zh, this message translates to:
  /// **'MAC 後 4 碼 {tail}（藍牙 {ble}）'**
  String gatewayIdentity_macTailWithBle(String tail, String ble);

  /// No description provided for @gatewayIdentity_resumeUploadLabel.
  ///
  /// In zh, this message translates to:
  /// **'恢復上傳'**
  String get gatewayIdentity_resumeUploadLabel;

  /// No description provided for @gatewayIdentity_resumingUpload.
  ///
  /// In zh, this message translates to:
  /// **'正在恢復資料上傳'**
  String get gatewayIdentity_resumingUpload;

  /// No description provided for @gatewayIdentity_testMode.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器處於測試模式（只產生測試資料、不會連 PTU），配置前需切回正常模式。'**
  String get gatewayIdentity_testMode;

  /// No description provided for @gatewayIdentity_testModeActionHint.
  ///
  /// In zh, this message translates to:
  /// **'切回後閘道器會重新開機（約 1 分鐘），APP 會自動重新連線並繼續。'**
  String get gatewayIdentity_testModeActionHint;

  /// No description provided for @gatewayIdentity_testModeStatusHint.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在測試模式（只產生測試資料），請按「{leave}」。'**
  String gatewayIdentity_testModeStatusHint(String leave);

  /// No description provided for @gatewayIdentity_testModeUpload.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在測試模式：只上傳測試資料，不會上傳 PTU 資料。'**
  String get gatewayIdentity_testModeUpload;

  /// Title of a gateway known not to be configured (a MAC tail may follow).
  ///
  /// In zh, this message translates to:
  /// **'未配置閘道器'**
  String get gatewayIdentity_unconfigured;

  /// No description provided for @gatewayIdentity_uploadHeld.
  ///
  /// In zh, this message translates to:
  /// **'後台連線正常。PTU 資料會在完成配置後自動開始上傳（目前暫停是正常的），APP 會自動繼續'**
  String get gatewayIdentity_uploadHeld;

  /// No description provided for @gatewayIdentity_uploadHeldStatus.
  ///
  /// In zh, this message translates to:
  /// **'✓ 已連上（完成配置後才上傳）'**
  String get gatewayIdentity_uploadHeldStatus;

  /// No description provided for @gatewayIdentity_uploadPaused.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已連上後台，但資料上傳已暫停：PTU 資料不會送出。請按「{resume}」。'**
  String gatewayIdentity_uploadPaused(String resume);

  /// No description provided for @gatewayIdentity_uploadPausedStatusHint.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料上傳已暫停，PTU 資料不會送出；請按「{resume}」。'**
  String gatewayIdentity_uploadPausedStatusHint(String resume);

  /// No description provided for @gatewayIdentity_uploadResumed.
  ///
  /// In zh, this message translates to:
  /// **'已恢復資料上傳，閘道器開始送出 PTU 資料。'**
  String get gatewayIdentity_uploadResumed;

  /// No description provided for @gatewayModeCard_resumeHint.
  ///
  /// In zh, this message translates to:
  /// **'恢復後閘道器立刻開始送出 PTU 資料，不會重新開機。'**
  String get gatewayModeCard_resumeHint;

  /// No description provided for @gatewayNet_connecting.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在連 Wi-Fi…'**
  String get gatewayNet_connecting;

  /// No description provided for @gatewayNet_discDetail.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 最後斷線原因：{kind}（代碼 {code}）'**
  String gatewayNet_discDetail(String kind, int code);

  /// No description provided for @gatewayNet_discDetailAge.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 最後斷線原因：{kind}（代碼 {code}，{age} 秒前）'**
  String gatewayNet_discDetailAge(String kind, int code, int age);

  /// No description provided for @gatewayNet_discLeave.
  ///
  /// In zh, this message translates to:
  /// **'閘道器自行中斷'**
  String get gatewayNet_discLeave;

  /// No description provided for @gatewayNet_discNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到這個 Wi-Fi'**
  String get gatewayNet_discNotFound;

  /// No description provided for @gatewayNet_discPassword.
  ///
  /// In zh, this message translates to:
  /// **'密碼可能錯誤'**
  String get gatewayNet_discPassword;

  /// No description provided for @gatewayNet_discWeak.
  ///
  /// In zh, this message translates to:
  /// **'訊號弱或其他'**
  String get gatewayNet_discWeak;

  /// No description provided for @gatewayNet_ok.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已連上 {wifi}'**
  String gatewayNet_ok(String wifi);

  /// No description provided for @gatewayNet_problemNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒有設定 Wi-Fi，所以沒辦法上傳資料。'**
  String get gatewayNet_problemNotConfigured;

  /// No description provided for @gatewayNet_problemNotFound.
  ///
  /// In zh, this message translates to:
  /// **'閘道器找不到 {wifi}。請確認名稱正確、是 2.4 GHz（閘道器不支援 5 GHz），且基地台就在附近。'**
  String gatewayNet_problemNotFound(String wifi);

  /// No description provided for @gatewayNet_problemPassword.
  ///
  /// In zh, this message translates to:
  /// **'閘道器連不上 {wifi}：密碼可能錯誤，請確認密碼（含大小寫）後重新輸入。'**
  String gatewayNet_problemPassword(String wifi);

  /// No description provided for @gatewayNet_problemUnknown.
  ///
  /// In zh, this message translates to:
  /// **'閘道器連不上 {wifi}。這個 Wi-Fi 可能不在附近、密碼不對，或是 5 GHz（閘道器只能用 2.4 GHz）。'**
  String gatewayNet_problemUnknown(String wifi);

  /// No description provided for @gatewayNet_problemWeak.
  ///
  /// In zh, this message translates to:
  /// **'閘道器連不上 {wifi}，可能是訊號太弱或基地台暫時拒絕連線。請把閘道器移近基地台、避開金屬遮蔽後再試。'**
  String gatewayNet_problemWeak(String wifi);

  /// No description provided for @gatewayNet_setFailedNotFound.
  ///
  /// In zh, this message translates to:
  /// **'新 Wi-Fi 連線未成功：閘道器找不到這個 Wi-Fi。請確認名稱正確、是 2.4 GHz（不支援 5 GHz），且基地台就在附近。'**
  String get gatewayNet_setFailedNotFound;

  /// No description provided for @gatewayNet_setFailedPassword.
  ///
  /// In zh, this message translates to:
  /// **'新 Wi-Fi 連線未成功：密碼可能錯誤，請確認密碼（含大小寫）後重試。'**
  String get gatewayNet_setFailedPassword;

  /// No description provided for @gatewayNet_setFailedUnknown.
  ///
  /// In zh, this message translates to:
  /// **'新 Wi-Fi 連線未成功，請檢查密碼與訊號後重試。'**
  String get gatewayNet_setFailedUnknown;

  /// No description provided for @gatewayNet_setFailedWeak.
  ///
  /// In zh, this message translates to:
  /// **'新 Wi-Fi 連線未成功：可能是訊號太弱或基地台暫時拒絕連線，請把閘道器移近基地台後重試。'**
  String get gatewayNet_setFailedWeak;

  /// A named Wi-Fi network inside a sentence.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi「{ssid}」'**
  String gatewayNet_ssidNamed(String ssid);

  /// No description provided for @gatewayNet_stateConnecting.
  ///
  /// In zh, this message translates to:
  /// **'連線中（connecting）'**
  String get gatewayNet_stateConnecting;

  /// No description provided for @gatewayNet_stateDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未連線（disconnected）'**
  String get gatewayNet_stateDisconnected;

  /// Technical detail: Wi-Fi state with the raw firmware value (keep got_ip).
  ///
  /// In zh, this message translates to:
  /// **'已連線（got_ip）'**
  String get gatewayNet_stateGotIp;

  /// No description provided for @gatewayNet_stateUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get gatewayNet_stateUnknown;

  /// No description provided for @gatewayNet_stateUnknownRaw.
  ///
  /// In zh, this message translates to:
  /// **'未知（{raw}）'**
  String gatewayNet_stateUnknownRaw(String raw);

  /// No description provided for @gatewayNet_weak.
  ///
  /// In zh, this message translates to:
  /// **'⚠ Wi-Fi 訊號偏弱（{rssi} dBm，低於 {limit} dBm），資料可能時斷時續。建議把閘道器移近基地台、避開金屬遮蔽，或在附近加裝 Wi-Fi 延伸器。'**
  String gatewayNet_weak(int rssi, int limit);

  /// No description provided for @gatewayProximity_closeHint.
  ///
  /// In zh, this message translates to:
  /// **'兩台距離相近，請連線後按燈泡辨識確認'**
  String get gatewayProximity_closeHint;

  /// Chip on the strongest gateway row of the list.
  ///
  /// In zh, this message translates to:
  /// **'最近'**
  String get gatewayProximity_nearest;

  /// No description provided for @gatewayProximity_nearestHint.
  ///
  /// In zh, this message translates to:
  /// **'本樁的閘道器通常是訊號最強的那台；不確定就點選它，連線後按燈泡看哪台閃燈'**
  String get gatewayProximity_nearestHint;

  /// Shown after an unrequested gateway restart; also uploaded (in Chinese) as the field report error_message.
  ///
  /// In zh, this message translates to:
  /// **'閘道器剛重新啟動（原因：{reason}）。這不是 PTU 故障，閘道器上已完成的設定都會保留。APP 已重新連上，請從目前的步驟繼續，不用從頭開始，也不要拔電或重複按。'**
  String gatewayReboot_notice(String reason);

  /// Same as gatewayReboot_notice when the gateway restarted more than once.
  ///
  /// In zh, this message translates to:
  /// **'閘道器剛重新啟動（原因：{reason}；期間共重新啟動 {times} 次）。這不是 PTU 故障，閘道器上已完成的設定都會保留。APP 已重新連上，請從目前的步驟繼續，不用從頭開始，也不要拔電或重複按。若短時間內一再重新啟動，請拍下這個畫面回報。'**
  String gatewayReboot_noticeMany(String reason, int times);

  /// No description provided for @gatewayReboot_reasonBleStackStuck.
  ///
  /// In zh, this message translates to:
  /// **'藍牙功能卡住，閘道器自動重新啟動修復'**
  String get gatewayReboot_reasonBleStackStuck;

  /// No description provided for @gatewayReboot_reasonBrownout.
  ///
  /// In zh, this message translates to:
  /// **'供電電壓不足（電源不穩或變壓器太弱）'**
  String get gatewayReboot_reasonBrownout;

  /// No description provided for @gatewayReboot_reasonCpuLockup.
  ///
  /// In zh, this message translates to:
  /// **'閘道器處理器卡住，自動重新啟動'**
  String get gatewayReboot_reasonCpuLockup;

  /// No description provided for @gatewayReboot_reasonDeepSleep.
  ///
  /// In zh, this message translates to:
  /// **'從省電休眠中醒來'**
  String get gatewayReboot_reasonDeepSleep;

  /// No description provided for @gatewayReboot_reasonPanic.
  ///
  /// In zh, this message translates to:
  /// **'閘道器程式發生錯誤，自動重新啟動'**
  String get gatewayReboot_reasonPanic;

  /// No description provided for @gatewayReboot_reasonPowerGlitch.
  ///
  /// In zh, this message translates to:
  /// **'電源瞬間不穩'**
  String get gatewayReboot_reasonPowerGlitch;

  /// No description provided for @gatewayReboot_reasonPowerOn.
  ///
  /// In zh, this message translates to:
  /// **'曾經斷電後重新上電'**
  String get gatewayReboot_reasonPowerOn;

  /// No description provided for @gatewayReboot_reasonResetButton.
  ///
  /// In zh, this message translates to:
  /// **'有人按了重置鍵'**
  String get gatewayReboot_reasonResetButton;

  /// No description provided for @gatewayReboot_reasonSoftware.
  ///
  /// In zh, this message translates to:
  /// **'收到重新啟動指令或設定變更'**
  String get gatewayReboot_reasonSoftware;

  /// No description provided for @gatewayReboot_reasonUnknown.
  ///
  /// In zh, this message translates to:
  /// **'原因不明'**
  String get gatewayReboot_reasonUnknown;

  /// No description provided for @gatewayReboot_reasonUsb.
  ///
  /// In zh, this message translates to:
  /// **'接上電腦時被重置'**
  String get gatewayReboot_reasonUsb;

  /// No description provided for @gatewayReboot_reasonWatchdog.
  ///
  /// In zh, this message translates to:
  /// **'閘道器程式卡住，看門狗保護機制自動重新啟動'**
  String get gatewayReboot_reasonWatchdog;

  /// No description provided for @gatewayReboot_retry.
  ///
  /// In zh, this message translates to:
  /// **'剛才的操作因閘道器重新啟動而中斷（不是 PTU 故障），請再按一次剛才的按鈕繼續。'**
  String get gatewayReboot_retry;

  /// No description provided for @gatewaySignal_demoScan.
  ///
  /// In zh, this message translates to:
  /// **'模擬・掃描 {value}'**
  String gatewaySignal_demoScan(String value);

  /// No description provided for @gatewaySignal_disconnectedLast.
  ///
  /// In zh, this message translates to:
  /// **'已斷線・上次 {value}'**
  String gatewaySignal_disconnectedLast(String value);

  /// No description provided for @gatewaySignal_disconnectedScan.
  ///
  /// In zh, this message translates to:
  /// **'已斷線・掃描 {value}'**
  String gatewaySignal_disconnectedScan(String value);

  /// No description provided for @gatewaySignal_last.
  ///
  /// In zh, this message translates to:
  /// **'上次 {value}'**
  String gatewaySignal_last(String value);

  /// No description provided for @gatewaySignal_line.
  ///
  /// In zh, this message translates to:
  /// **'手機 ↔ 閘道器：{status}'**
  String gatewaySignal_line(String status);

  /// No description provided for @gatewaySignal_linkLost.
  ///
  /// In zh, this message translates to:
  /// **'手機與閘道器的藍牙已斷線，請靠近閘道器；APP 會提示如何重新連線。'**
  String get gatewaySignal_linkLost;

  /// No description provided for @gatewaySignal_noReading.
  ///
  /// In zh, this message translates to:
  /// **'尚無讀值'**
  String get gatewaySignal_noReading;

  /// No description provided for @gatewaySignal_scan.
  ///
  /// In zh, this message translates to:
  /// **'掃描 {value}'**
  String gatewaySignal_scan(String value);

  /// Age of the newest data; age comes from recentAgeText (e.g. 7 秒 / 7 s).
  ///
  /// In zh, this message translates to:
  /// **'{age}前'**
  String gatewayStatus_dataAgo(String age);

  /// A recent setup row; time is already formatted as MM-dd HH:mm.
  ///
  /// In zh, this message translates to:
  /// **'{time} 完成'**
  String gatewayStatus_doneAt(String time);

  /// No description provided for @gatewayStatus_fleetEmpty.
  ///
  /// In zh, this message translates to:
  /// **'後台目前沒有任何閘道器。'**
  String get gatewayStatus_fleetEmpty;

  /// No description provided for @gatewayStatus_fleetTitle.
  ///
  /// In zh, this message translates to:
  /// **'後台在線閘道器'**
  String get gatewayStatus_fleetTitle;

  /// No description provided for @gatewayStatus_gatewayCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 台閘道器'**
  String gatewayStatus_gatewayCount(int count);

  /// No description provided for @gatewayStatus_heartbeatAgo.
  ///
  /// In zh, this message translates to:
  /// **'心跳 {age}前'**
  String gatewayStatus_heartbeatAgo(String age);

  /// No description provided for @gatewayStatus_hint.
  ///
  /// In zh, this message translates to:
  /// **'展開站號，再點選閘道器查看最近資料。'**
  String get gatewayStatus_hint;

  /// No description provided for @gatewayStatus_homeCaption.
  ///
  /// In zh, this message translates to:
  /// **'架設完後，看資料有沒有正常送到後台'**
  String get gatewayStatus_homeCaption;

  /// No description provided for @gatewayStatus_label.
  ///
  /// In zh, this message translates to:
  /// **'查看上傳資料'**
  String get gatewayStatus_label;

  /// No description provided for @gatewayStatus_loading.
  ///
  /// In zh, this message translates to:
  /// **'正在向後台查詢…'**
  String get gatewayStatus_loading;

  /// No description provided for @gatewayStatus_name.
  ///
  /// In zh, this message translates to:
  /// **'站 {site} 閘道器 {gateway}'**
  String gatewayStatus_name(int site, int gateway);

  /// No description provided for @gatewayStatus_nearbyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'附近沒有掃到閘道器，請靠近後按〔重新掃描〕'**
  String get gatewayStatus_nearbyEmpty;

  /// No description provided for @gatewayStatus_nearbyScanFailed.
  ///
  /// In zh, this message translates to:
  /// **'掃描失敗，請確認藍牙、定位與附近裝置權限後重試。'**
  String get gatewayStatus_nearbyScanFailed;

  /// No description provided for @gatewayStatus_nearbyScanning.
  ///
  /// In zh, this message translates to:
  /// **'正在掃描附近閘道器（約 8 秒）…'**
  String get gatewayStatus_nearbyScanning;

  /// No description provided for @gatewayStatus_nearbyTitle.
  ///
  /// In zh, this message translates to:
  /// **'附近閘道器（藍牙掃描）'**
  String get gatewayStatus_nearbyTitle;

  /// No description provided for @gatewayStatus_nearbyUnconfigured.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置，無法查看資料'**
  String get gatewayStatus_nearbyUnconfigured;

  /// No description provided for @gatewayStatus_nearbyUnnamed.
  ///
  /// In zh, this message translates to:
  /// **'尚未設定站號，無法查看資料'**
  String get gatewayStatus_nearbyUnnamed;

  /// Mark on the strongest (closest) nearby gateway.
  ///
  /// In zh, this message translates to:
  /// **'最近'**
  String get gatewayStatus_nearest;

  /// No description provided for @gatewayStatus_noData.
  ///
  /// In zh, this message translates to:
  /// **'尚無資料'**
  String get gatewayStatus_noData;

  /// No description provided for @gatewayStatus_offline.
  ///
  /// In zh, this message translates to:
  /// **'離線'**
  String get gatewayStatus_offline;

  /// No description provided for @gatewayStatus_online.
  ///
  /// In zh, this message translates to:
  /// **'在線'**
  String get gatewayStatus_online;

  /// No description provided for @gatewayStatus_openSettings.
  ///
  /// In zh, this message translates to:
  /// **'開啟權限設定'**
  String get gatewayStatus_openSettings;

  /// No description provided for @gatewayStatus_ptuConnected.
  ///
  /// In zh, this message translates to:
  /// **'PTU 已連線'**
  String get gatewayStatus_ptuConnected;

  /// No description provided for @gatewayStatus_ptuDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'PTU 未連線'**
  String get gatewayStatus_ptuDisconnected;

  /// No description provided for @gatewayStatus_recentEmpty.
  ///
  /// In zh, this message translates to:
  /// **'這支手機尚未用此版本完成過配置'**
  String get gatewayStatus_recentEmpty;

  /// No description provided for @gatewayStatus_recentTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近配置（這支手機）'**
  String get gatewayStatus_recentTitle;

  /// No description provided for @gatewayStatus_rescan.
  ///
  /// In zh, this message translates to:
  /// **'重新掃描'**
  String get gatewayStatus_rescan;

  /// No description provided for @gatewayStatus_siteGroup.
  ///
  /// In zh, this message translates to:
  /// **'站 {site}'**
  String gatewayStatus_siteGroup(int site);

  /// No description provided for @gatewayStatus_unconfiguredGroup.
  ///
  /// In zh, this message translates to:
  /// **'未配置／站號未確認'**
  String get gatewayStatus_unconfiguredGroup;

  /// No description provided for @gatewaySwapSheet_assignmentHint.
  ///
  /// In zh, this message translates to:
  /// **'（取代舊機）'**
  String get gatewaySwapSheet_assignmentHint;

  /// No description provided for @gatewaySwapSheet_assignmentHintTail.
  ///
  /// In zh, this message translates to:
  /// **'（取代舊機 {tail}）'**
  String gatewaySwapSheet_assignmentHintTail(String tail);

  /// No description provided for @gatewaySwapSheet_cancelLabel.
  ///
  /// In zh, this message translates to:
  /// **'取消換機'**
  String get gatewaySwapSheet_cancelLabel;

  /// No description provided for @gatewaySwapSheet_confirmOk.
  ///
  /// In zh, this message translates to:
  /// **'確定換機'**
  String get gatewaySwapSheet_confirmOk;

  /// No description provided for @gatewaySwapSheet_confirmText.
  ///
  /// In zh, this message translates to:
  /// **'這台將接手 站 {site} · 閘道器 {gateway}。舊機必須已拆除或斷電。'**
  String gatewaySwapSheet_confirmText(int site, int gateway);

  /// No description provided for @gatewaySwapSheet_confirmTextTail.
  ///
  /// In zh, this message translates to:
  /// **'這台將接手 站 {site} · 閘道器 {gateway}。舊機（{tail}）必須已拆除或斷電。'**
  String gatewaySwapSheet_confirmTextTail(int site, int gateway, String tail);

  /// No description provided for @gatewaySwapSheet_confirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'確定換機？'**
  String get gatewaySwapSheet_confirmTitle;

  /// Button: this new gateway replaces a broken one (takes over its site and number).
  ///
  /// In zh, this message translates to:
  /// **'這台是來換掉壞掉的舊機'**
  String get gatewaySwapSheet_label;

  /// age is an already formatted duration (e.g. 3 小時 / 3 h).
  ///
  /// In zh, this message translates to:
  /// **'最後上線 {age}前'**
  String gatewaySwapSheet_lastSeen(String age);

  /// No description provided for @gatewaySwapSheet_needsNetwork.
  ///
  /// In zh, this message translates to:
  /// **'換機需要連上網路'**
  String get gatewaySwapSheet_needsNetwork;

  /// No description provided for @gatewaySwapSheet_noRecord.
  ///
  /// In zh, this message translates to:
  /// **'沒有上線紀錄'**
  String get gatewaySwapSheet_noRecord;

  /// No description provided for @gatewaySwapSheet_none.
  ///
  /// In zh, this message translates to:
  /// **'本站沒有離線的閘道器可以取代'**
  String get gatewaySwapSheet_none;

  /// No description provided for @gatewaySwapSheet_online.
  ///
  /// In zh, this message translates to:
  /// **'閘道器 {gateway} 目前在線上，請先把舊機斷電。'**
  String gatewaySwapSheet_online(int gateway);

  /// No description provided for @gatewaySwapSheet_rowTitle.
  ///
  /// In zh, this message translates to:
  /// **'閘道器 {gateway}'**
  String gatewaySwapSheet_rowTitle(int gateway);

  /// No description provided for @gatewaySwapSheet_sheetHint.
  ///
  /// In zh, this message translates to:
  /// **'只列出本站目前離線的閘道器；舊機必須已拆除或斷電。'**
  String get gatewaySwapSheet_sheetHint;

  /// No description provided for @gatewaySwapSheet_sheetTitle.
  ///
  /// In zh, this message translates to:
  /// **'選擇要取代的舊機（站 {site}）'**
  String gatewaySwapSheet_sheetTitle(int site);

  /// No description provided for @gatewayTopology_directLabel.
  ///
  /// In zh, this message translates to:
  /// **'直連模式（一對一）'**
  String get gatewayTopology_directLabel;

  /// No description provided for @gatewayTopology_directShort.
  ///
  /// In zh, this message translates to:
  /// **'直連模式'**
  String get gatewayTopology_directShort;

  /// No description provided for @gatewayTopology_starLabel.
  ///
  /// In zh, this message translates to:
  /// **'星狀模式（一對多）'**
  String get gatewayTopology_starLabel;

  /// No description provided for @gatewayTopology_starShort.
  ///
  /// In zh, this message translates to:
  /// **'星狀模式'**
  String get gatewayTopology_starShort;

  /// No description provided for @heartbeatActivity_announcement.
  ///
  /// In zh, this message translates to:
  /// **'已收到 {received} 次心跳。{message}'**
  String heartbeatActivity_announcement(int received, String message);

  /// No description provided for @heartbeatActivity_backOffice.
  ///
  /// In zh, this message translates to:
  /// **'後台'**
  String get heartbeatActivity_backOffice;

  /// No description provided for @heartbeatActivity_confirmed.
  ///
  /// In zh, this message translates to:
  /// **'已確認閘道器持續上線'**
  String get heartbeatActivity_confirmed;

  /// No description provided for @heartbeatActivity_connectingBackend.
  ///
  /// In zh, this message translates to:
  /// **'正在連上後台'**
  String get heartbeatActivity_connectingBackend;

  /// No description provided for @heartbeatActivity_count.
  ///
  /// In zh, this message translates to:
  /// **'心跳 {received}/2'**
  String heartbeatActivity_count(int received);

  /// No description provided for @heartbeatActivity_gotOne.
  ///
  /// In zh, this message translates to:
  /// **'已收到 1 次，等待下一次心跳'**
  String get heartbeatActivity_gotOne;

  /// No description provided for @heartbeatActivity_gotTwo.
  ///
  /// In zh, this message translates to:
  /// **'已收到 2 次，正在確認上傳目標'**
  String get heartbeatActivity_gotTwo;

  /// No description provided for @heartbeatActivity_notDone.
  ///
  /// In zh, this message translates to:
  /// **'尚未完成心跳確認'**
  String get heartbeatActivity_notDone;

  /// No description provided for @heartbeatActivity_paused.
  ///
  /// In zh, this message translates to:
  /// **'確認暫停，請依提示重試'**
  String get heartbeatActivity_paused;

  /// No description provided for @heartbeatActivity_waitingFirst.
  ///
  /// In zh, this message translates to:
  /// **'等待第 1 次心跳'**
  String get heartbeatActivity_waitingFirst;

  /// No description provided for @heartbeatActivity_waitingStart.
  ///
  /// In zh, this message translates to:
  /// **'等待開始確認'**
  String get heartbeatActivity_waitingStart;

  /// No description provided for @homeEntry_backHome.
  ///
  /// In zh, this message translates to:
  /// **'返回首頁'**
  String get homeEntry_backHome;

  /// No description provided for @homeEntry_configure.
  ///
  /// In zh, this message translates to:
  /// **'現場配置'**
  String get homeEntry_configure;

  /// No description provided for @homeEntry_configureAction.
  ///
  /// In zh, this message translates to:
  /// **'進入配置'**
  String get homeEntry_configureAction;

  /// No description provided for @homeEntry_configureDescription.
  ///
  /// In zh, this message translates to:
  /// **'安裝新設備、設定網路、綁定 PTU 並確認資料上傳'**
  String get homeEntry_configureDescription;

  /// No description provided for @homeEntry_savedProgress.
  ///
  /// In zh, this message translates to:
  /// **'有未完成的配置，可進入後繼續'**
  String get homeEntry_savedProgress;

  /// No description provided for @homeEntry_title.
  ///
  /// In zh, this message translates to:
  /// **'選擇要進行的操作'**
  String get homeEntry_title;

  /// No description provided for @homeEntry_viewData.
  ///
  /// In zh, this message translates to:
  /// **'查看數據'**
  String get homeEntry_viewData;

  /// No description provided for @homeEntry_viewDataAction.
  ///
  /// In zh, this message translates to:
  /// **'查看數據'**
  String get homeEntry_viewDataAction;

  /// No description provided for @homeEntry_viewDataDescription.
  ///
  /// In zh, this message translates to:
  /// **'查看各站充電功率、效率、電池狀態與異常資訊'**
  String get homeEntry_viewDataDescription;

  /// No description provided for @identifyDurationSetting_fieldLabel.
  ///
  /// In zh, this message translates to:
  /// **'秒數（0 或 2–10）'**
  String get identifyDurationSetting_fieldLabel;

  /// No description provided for @identifyDurationSetting_help.
  ///
  /// In zh, this message translates to:
  /// **'預設 4 秒。閘道器與 PTU 使用相同秒數。可填 2–10 秒；0＝關燈，閘道器會停止辨識並恢復正常狀態燈。不提供 1 秒（PTU 的 1 秒封包會讓燈恆亮）。'**
  String get identifyDurationSetting_help;

  /// No description provided for @identifyDurationSetting_save.
  ///
  /// In zh, this message translates to:
  /// **'儲存秒數'**
  String get identifyDurationSetting_save;

  /// No description provided for @identifyDurationSetting_saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法儲存，請重試'**
  String get identifyDurationSetting_saveFailed;

  /// No description provided for @identifyDurationSetting_saved.
  ///
  /// In zh, this message translates to:
  /// **'已儲存：{seconds} 秒'**
  String identifyDurationSetting_saved(int seconds);

  /// No description provided for @identifyDurationSetting_savedOff.
  ///
  /// In zh, this message translates to:
  /// **'已儲存：0 秒（關閉辨識燈）'**
  String get identifyDurationSetting_savedOff;

  /// No description provided for @identifyDurationSetting_saving.
  ///
  /// In zh, this message translates to:
  /// **'儲存中…'**
  String get identifyDurationSetting_saving;

  /// No description provided for @identifyDurationSetting_suffix.
  ///
  /// In zh, this message translates to:
  /// **'秒'**
  String get identifyDurationSetting_suffix;

  /// No description provided for @identifyDurationSetting_title.
  ///
  /// In zh, this message translates to:
  /// **'辨識秒數'**
  String get identifyDurationSetting_title;

  /// No description provided for @identify_gatewayBlink.
  ///
  /// In zh, this message translates to:
  /// **'{seconds, plural, other{閘道器雙閃 {seconds} 秒}}'**
  String identify_gatewayBlink(int seconds);

  /// No description provided for @identify_gatewayLedUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'閘道器燈效無法使用'**
  String get identify_gatewayLedUnavailable;

  /// No description provided for @identify_gatewayStopped.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已停止辨識，恢復正常燈號'**
  String get identify_gatewayStopped;

  /// No description provided for @identify_ptuOnly.
  ///
  /// In zh, this message translates to:
  /// **'僅處理 PTU，閘道器燈號未變更'**
  String get identify_ptuOnly;

  /// No description provided for @identify_secondsError.
  ///
  /// In zh, this message translates to:
  /// **'請輸入 0（關燈）或 2–10 的整數秒數（1 秒會讓 PTU 燈恆亮，不提供）'**
  String get identify_secondsError;

  /// No description provided for @installReportPanel_resend.
  ///
  /// In zh, this message translates to:
  /// **'重送'**
  String get installReportPanel_resend;

  /// No description provided for @installReport_demo.
  ///
  /// In zh, this message translates to:
  /// **'模擬模式：報告不送後台'**
  String get installReport_demo;

  /// No description provided for @installReport_failed.
  ///
  /// In zh, this message translates to:
  /// **'報告沒有送到後台'**
  String get installReport_failed;

  /// No description provided for @installReport_failedReason.
  ///
  /// In zh, this message translates to:
  /// **'報告沒有送到後台：{reason}'**
  String installReport_failedReason(String reason);

  /// No description provided for @installReport_queued.
  ///
  /// In zh, this message translates to:
  /// **'排隊中，網路恢復後自動送'**
  String get installReport_queued;

  /// No description provided for @installReport_queuedReason.
  ///
  /// In zh, this message translates to:
  /// **'排隊中，網路恢復後自動送（{reason}）'**
  String installReport_queuedReason(String reason);

  /// Done page: the install report is being uploaded.
  ///
  /// In zh, this message translates to:
  /// **'正在把報告送到後台…'**
  String get installReport_sending;

  /// No description provided for @installReport_sent.
  ///
  /// In zh, this message translates to:
  /// **'報告已送到後台'**
  String get installReport_sent;

  /// No description provided for @installReport_sentAt.
  ///
  /// In zh, this message translates to:
  /// **'報告已送到後台 {time}'**
  String installReport_sentAt(String time);

  /// No description provided for @localBackendAddress_hostEmpty.
  ///
  /// In zh, this message translates to:
  /// **'請輸入電腦的 IP 位址'**
  String get localBackendAddress_hostEmpty;

  /// No description provided for @localBackendAddress_hostFormat.
  ///
  /// In zh, this message translates to:
  /// **'格式應為 4 組 0–255 的數字，例如 192.168.1.187'**
  String get localBackendAddress_hostFormat;

  /// No description provided for @localBackendAddress_hostLastOctet.
  ///
  /// In zh, this message translates to:
  /// **'最後一組不可為 0 或 255'**
  String get localBackendAddress_hostLastOctet;

  /// No description provided for @localBackendAddress_hostLoopback.
  ///
  /// In zh, this message translates to:
  /// **'127.x 是手機本身，請輸入電腦在區域網路的 IP'**
  String get localBackendAddress_hostLoopback;

  /// No description provided for @localBackendAddress_hostNotPrivate.
  ///
  /// In zh, this message translates to:
  /// **'只接受區域網路位址（10.x、172.16–31.x、192.168.x）'**
  String get localBackendAddress_hostNotPrivate;

  /// No description provided for @localBackendAddress_portRange.
  ///
  /// In zh, this message translates to:
  /// **'連接埠需為 1–65535'**
  String get localBackendAddress_portRange;

  /// No description provided for @localBackendField_advancedPort.
  ///
  /// In zh, this message translates to:
  /// **'進階：連接埠 {port}'**
  String localBackendField_advancedPort(String port);

  /// No description provided for @localBackendField_autoFind.
  ///
  /// In zh, this message translates to:
  /// **'自動尋找'**
  String get localBackendField_autoFind;

  /// No description provided for @localBackendField_dbNotReady.
  ///
  /// In zh, this message translates to:
  /// **'資料庫尚未就緒'**
  String get localBackendField_dbNotReady;

  /// No description provided for @localBackendField_filledNotReady.
  ///
  /// In zh, this message translates to:
  /// **'已填入 {host}，但該後端的資料庫尚未就緒，請稍後按「測試連線」確認。'**
  String localBackendField_filledNotReady(String host);

  /// Title of the pick dialog when several local back offices answered.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{找到 {count} 台本地後端}}'**
  String localBackendField_foundCount(int count);

  /// No description provided for @localBackendField_foundFilled.
  ///
  /// In zh, this message translates to:
  /// **'✓ 找到本地後端 {host}，已自動填入。'**
  String localBackendField_foundFilled(String host);

  /// No description provided for @localBackendField_foundNotChosen.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{找到 {count} 台本地後端，尚未選擇。}}'**
  String localBackendField_foundNotChosen(int count);

  /// No description provided for @localBackendField_gettingSubnet.
  ///
  /// In zh, this message translates to:
  /// **'正在取得手機的 Wi-Fi 網段…'**
  String get localBackendField_gettingSubnet;

  /// No description provided for @localBackendField_ipLabel.
  ///
  /// In zh, this message translates to:
  /// **'電腦 IP 位址'**
  String get localBackendField_ipLabel;

  /// No description provided for @localBackendField_noPhoneIp.
  ///
  /// In zh, this message translates to:
  /// **'找不到手機的 Wi-Fi IP。請先讓手機連上與電腦相同的 Wi-Fi 後再試。'**
  String get localBackendField_noPhoneIp;

  /// No description provided for @localBackendField_notFound.
  ///
  /// In zh, this message translates to:
  /// **'在 {subnet} 網段找不到本地後端（連接埠 {port}）。'**
  String localBackendField_notFound(String subnet, String port);

  /// No description provided for @localBackendField_notFoundTimedOut.
  ///
  /// In zh, this message translates to:
  /// **'在 {subnet} 網段找不到本地後端（連接埠 {port}）。（已達搜尋時間上限）'**
  String localBackendField_notFoundTimedOut(String subnet, String port);

  /// No description provided for @localBackendField_portDefault.
  ///
  /// In zh, this message translates to:
  /// **'預設 {port}'**
  String localBackendField_portDefault(String port);

  /// No description provided for @localBackendField_portDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地後端連接埠'**
  String get localBackendField_portDialogTitle;

  /// No description provided for @localBackendField_portLabel.
  ///
  /// In zh, this message translates to:
  /// **'連接埠'**
  String get localBackendField_portLabel;

  /// No description provided for @localBackendField_restoreDefault.
  ///
  /// In zh, this message translates to:
  /// **'還原預設'**
  String get localBackendField_restoreDefault;

  /// No description provided for @localBackendField_scanCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消搜尋。'**
  String get localBackendField_scanCancelled;

  /// No description provided for @localBackendField_searching.
  ///
  /// In zh, this message translates to:
  /// **'正在搜尋 {host}…（{done}／{total}）'**
  String localBackendField_searching(String host, int done, int total);

  /// No description provided for @localBackendField_testConnection.
  ///
  /// In zh, this message translates to:
  /// **'測試連線'**
  String get localBackendField_testConnection;

  /// No description provided for @localBackendField_testing.
  ///
  /// In zh, this message translates to:
  /// **'測試中…'**
  String get localBackendField_testing;

  /// No description provided for @localBackendField_version.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}'**
  String localBackendField_version(String version);

  /// No description provided for @localBackendField_willConnect.
  ///
  /// In zh, this message translates to:
  /// **'將連線：{url}'**
  String localBackendField_willConnect(String url);

  /// No description provided for @localBackendField_willConnectNone.
  ///
  /// In zh, this message translates to:
  /// **'將連線：（請先輸入正確的 IP）'**
  String get localBackendField_willConnectNone;

  /// No description provided for @localBackendProbe_degraded.
  ///
  /// In zh, this message translates to:
  /// **'✗ 已連到本地後端，但資料庫尚未就緒（HTTP 503）。請等 Docker 本地後端完全啟動後重試。'**
  String get localBackendProbe_degraded;

  /// No description provided for @localBackendProbe_healthy.
  ///
  /// In zh, this message translates to:
  /// **'✓ 已連上本地後端'**
  String get localBackendProbe_healthy;

  /// No description provided for @localBackendProbe_healthyVersion.
  ///
  /// In zh, this message translates to:
  /// **'✓ 已連上本地後端（版本 {version}）'**
  String localBackendProbe_healthyVersion(String version);

  /// No description provided for @localBackendProbe_hint.
  ///
  /// In zh, this message translates to:
  /// **'請確認：手機與電腦在同一個 Wi-Fi、電腦已啟動 Docker 本地後端、電腦防火牆已執行 allow_local_api_lan.ps1。'**
  String get localBackendProbe_hint;

  /// No description provided for @localBackendProbe_httpError.
  ///
  /// In zh, this message translates to:
  /// **'✗ 回應不是本地後端（HTTP {status}）。請確認電腦 IP 與連接埠。'**
  String localBackendProbe_httpError(String status);

  /// No description provided for @localBackendProbe_notBackend.
  ///
  /// In zh, this message translates to:
  /// **'✗ 回應不是本地後端（HTTP {status}）。這個 IP／連接埠上是其他服務，請確認電腦 IP。'**
  String localBackendProbe_notBackend(String status);

  /// No description provided for @localBackendProbe_timeout.
  ///
  /// In zh, this message translates to:
  /// **'✗ 逾時：{message}'**
  String localBackendProbe_timeout(String message);

  /// No description provided for @localBackendProbe_unreachable.
  ///
  /// In zh, this message translates to:
  /// **'✗ 無法連線：{message}'**
  String localBackendProbe_unreachable(String message);

  /// No description provided for @mqttTarget_failBleOnly.
  ///
  /// In zh, this message translates to:
  /// **'上傳目標只能在現場透過藍牙切換，不接受遠端指令。'**
  String get mqttTarget_failBleOnly;

  /// No description provided for @mqttTarget_failBusy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在處理其他指令，請稍候重試。'**
  String get mqttTarget_failBusy;

  /// No description provided for @mqttTarget_failInvalidHost.
  ///
  /// In zh, this message translates to:
  /// **'閘道器拒絕切換：本地後端位址必須是區網私有 IPv4（10.x、172.16–31.x、192.168.x），不可使用主機名稱或公網 IP。'**
  String get mqttTarget_failInvalidHost;

  /// No description provided for @mqttTarget_failInvalidParams.
  ///
  /// In zh, this message translates to:
  /// **'閘道器拒絕切換：指令參數格式錯誤。請更新 APP 後重試。'**
  String get mqttTarget_failInvalidParams;

  /// No description provided for @mqttTarget_failInvalidPort.
  ///
  /// In zh, this message translates to:
  /// **'閘道器拒絕切換：MQTT 連接埠必須是 1–65535 的整數。'**
  String get mqttTarget_failInvalidPort;

  /// No description provided for @mqttTarget_failInvalidReqId.
  ///
  /// In zh, this message translates to:
  /// **'APP 送出的指令編號無效，請重新連線後重試。'**
  String get mqttTarget_failInvalidReqId;

  /// No description provided for @mqttTarget_failInvalidTarget.
  ///
  /// In zh, this message translates to:
  /// **'閘道器拒絕切換：上傳目標名稱無效。請更新 APP 後重試。'**
  String get mqttTarget_failInvalidTarget;

  /// No description provided for @mqttTarget_failNoReason.
  ///
  /// In zh, this message translates to:
  /// **'閘道器拒絕切換上傳目標（未提供原因）。'**
  String get mqttTarget_failNoReason;

  /// No description provided for @mqttTarget_failNotReady.
  ///
  /// In zh, this message translates to:
  /// **'閘道器仍在開機初始化，請稍候數秒後重試。'**
  String get mqttTarget_failNotReady;

  /// No description provided for @mqttTarget_failNvsWrite.
  ///
  /// In zh, this message translates to:
  /// **'閘道器儲存設定失敗，上傳目標未變更、也沒有重新開機。請重試；若持續失敗請回報。'**
  String get mqttTarget_failNvsWrite;

  /// No description provided for @mqttTarget_failOtaInProgress.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在更新韌體（OTA），更新完成前無法切換上傳目標，請稍後重試。'**
  String get mqttTarget_failOtaInProgress;

  /// No description provided for @mqttTarget_failOther.
  ///
  /// In zh, this message translates to:
  /// **'閘道器拒絕切換上傳目標。'**
  String get mqttTarget_failOther;

  /// No description provided for @mqttTarget_failOtpInvalid.
  ///
  /// In zh, this message translates to:
  /// **'一次性密碼（OTP）錯誤，閘道器拒絕切換。'**
  String get mqttTarget_failOtpInvalid;

  /// No description provided for @mqttTarget_failOtpLocked.
  ///
  /// In zh, this message translates to:
  /// **'OTP 錯誤次數過多，閘道器暫時鎖定，請稍後再試。'**
  String get mqttTarget_failOtpLocked;

  /// No description provided for @mqttTarget_failOtpRequired.
  ///
  /// In zh, this message translates to:
  /// **'此閘道器已啟用一次性密碼（OTP），切換上傳目標需要 OTP，請聯絡管理員。'**
  String get mqttTarget_failOtpRequired;

  /// No description provided for @mqttTarget_failOtpReused.
  ///
  /// In zh, this message translates to:
  /// **'此一次性密碼已使用過，請等下一組 OTP 後重試。'**
  String get mqttTarget_failOtpReused;

  /// No description provided for @mqttTarget_failTimeNotSynced.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已啟用 OTP 但時間尚未同步（NTP），無法驗證。若目前 Wi-Fi 無法連到網際網路，請先改用可連外的網路。'**
  String get mqttTarget_failTimeNotSynced;

  /// No description provided for @mqttTarget_failUnknownOp.
  ///
  /// In zh, this message translates to:
  /// **'閘道器韌體不支援切換上傳目標，需更新至 1.7.3 以上。'**
  String get mqttTarget_failUnknownOp;

  /// No description provided for @mqttTarget_legacyFirmware.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器韌體太舊（版本 {version}），只能送到正式站，請更新到 1.7.3 以上。'**
  String mqttTarget_legacyFirmware(String version);

  /// No description provided for @mqttTarget_localHost.
  ///
  /// In zh, this message translates to:
  /// **'本地 {host}'**
  String mqttTarget_localHost(String host);

  /// No description provided for @mqttTarget_localHostNotPrivate.
  ///
  /// In zh, this message translates to:
  /// **'本地測試站網址的主機「{host}」不是區網私有 IPv4 位址（10.x.x.x、172.16–31.x.x、192.168.x.x），閘道器無法上傳到此後端。請把網址改成電腦的區網 IP。'**
  String mqttTarget_localHostNotPrivate(String host);

  /// No description provided for @mqttTarget_localHostPort.
  ///
  /// In zh, this message translates to:
  /// **'本地 {host}:{port}'**
  String mqttTarget_localHostPort(String host, String port);

  /// No description provided for @mqttTarget_localUrlEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未輸入本地測試站網址，無法決定閘道器的上傳目標。'**
  String get mqttTarget_localUrlEmpty;

  /// No description provided for @mqttTarget_localUrlUnparsable.
  ///
  /// In zh, this message translates to:
  /// **'本地測試站網址「{url}」無法解析主機位址，請輸入如 http://192.168.1.10:18000 的網址。'**
  String mqttTarget_localUrlUnparsable(String url);

  /// Local test backend inside a sentence; no port.
  ///
  /// In zh, this message translates to:
  /// **'本地測試主機（{host}）'**
  String mqttTarget_plainLocal(String host);

  /// Production target inside a sentence for non-developers (e.g. 'sends data to …').
  ///
  /// In zh, this message translates to:
  /// **'正式站'**
  String get mqttTarget_plainProduction;

  /// The production back office as an upload target (button / label).
  ///
  /// In zh, this message translates to:
  /// **'正式站'**
  String get mqttTarget_production;

  /// No description provided for @mqttTarget_productionHostPort.
  ///
  /// In zh, this message translates to:
  /// **'正式站 {host}:{port}'**
  String mqttTarget_productionHostPort(String host, String port);

  /// No description provided for @mqttTarget_reportLegacy.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳目標：正式站（韌體 {version} 固定）'**
  String mqttTarget_reportLegacy(String version);

  /// No description provided for @mqttTarget_reportLine.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳目標：{where}'**
  String mqttTarget_reportLine(String where);

  /// No description provided for @mqttTarget_reportNote.
  ///
  /// In zh, this message translates to:
  /// **'注意：{warning}'**
  String mqttTarget_reportNote(String warning);

  /// No description provided for @mqttTarget_reportUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳目標：未確認'**
  String get mqttTarget_reportUnconfirmed;

  /// No description provided for @mqttTarget_shipWarning.
  ///
  /// In zh, this message translates to:
  /// **'此閘道器目前上傳到本地測試站，出貨前請切回正式站。'**
  String get mqttTarget_shipWarning;

  /// No description provided for @networkCheck_reuseNoWifi.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒連上 Wi-Fi'**
  String get networkCheck_reuseNoWifi;

  /// No description provided for @networkCheck_reuseNotUploading.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒開始上傳資料'**
  String get networkCheck_reuseNotUploading;

  /// No description provided for @networkCheck_reuseTargetMismatch.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料還沒送到手機連的地方'**
  String get networkCheck_reuseTargetMismatch;

  /// Why 'keep the current station' cannot be used now.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在測試模式'**
  String get networkCheck_reuseTestMode;

  /// No description provided for @networkCheck_reuseUploadPaused.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料上傳已暫停'**
  String get networkCheck_reuseUploadPaused;

  /// No description provided for @networkCheck_stepAlignTarget.
  ///
  /// In zh, this message translates to:
  /// **'對準上傳目標'**
  String get networkCheck_stepAlignTarget;

  /// No description provided for @networkCheck_stepChoosePtu.
  ///
  /// In zh, this message translates to:
  /// **'選擇 PTU'**
  String get networkCheck_stepChoosePtu;

  /// No description provided for @networkCheck_stepChooseSite.
  ///
  /// In zh, this message translates to:
  /// **'站點選擇'**
  String get networkCheck_stepChooseSite;

  /// No description provided for @networkCheck_stepConfirmUpload.
  ///
  /// In zh, this message translates to:
  /// **'確認資料上傳'**
  String get networkCheck_stepConfirmUpload;

  /// No description provided for @networkCheck_stepFindGateway.
  ///
  /// In zh, this message translates to:
  /// **'找到閘道器'**
  String get networkCheck_stepFindGateway;

  /// No description provided for @networkCheck_stepNetworkCheck.
  ///
  /// In zh, this message translates to:
  /// **'閘道器網路體檢'**
  String get networkCheck_stepNetworkCheck;

  /// Step names (stepLabels), in order; shown on screen and uploaded (in Chinese) as field step_label.
  ///
  /// In zh, this message translates to:
  /// **'準備'**
  String get networkCheck_stepPrepare;

  /// No description provided for @networkCheck_stepStartMonitoring.
  ///
  /// In zh, this message translates to:
  /// **'開始監控'**
  String get networkCheck_stepStartMonitoring;

  /// No description provided for @networkCheck_stepVerifyData.
  ///
  /// In zh, this message translates to:
  /// **'驗證資料'**
  String get networkCheck_stepVerifyData;

  /// error is a full sentence about the local backend URL.
  ///
  /// In zh, this message translates to:
  /// **'{error}請點右上角的環境按鈕修正。'**
  String networkCheck_targetInvalid(String error);

  /// No description provided for @networkCheck_targetMatch.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料送到{current}，和手機一致'**
  String networkCheck_targetMatch(String current);

  /// No description provided for @networkCheck_targetMismatch.
  ///
  /// In zh, this message translates to:
  /// **'閘道器把資料送到{current}，但手機連的是{phone}。'**
  String networkCheck_targetMismatch(String current, String phone);

  /// No description provided for @networkCheck_targetProductionFixed.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料送到正式站'**
  String get networkCheck_targetProductionFixed;

  /// No description provided for @networkCheck_targetUndecidable.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料送到{current}；APP 無法從這個網址判斷是否一致。'**
  String networkCheck_targetUndecidable(String current);

  /// No description provided for @networkCheck_targetUnknown.
  ///
  /// In zh, this message translates to:
  /// **'還不確定閘道器把資料送到哪裡。'**
  String get networkCheck_targetUnknown;

  /// No description provided for @networkCheck_targetUnknownSync.
  ///
  /// In zh, this message translates to:
  /// **'還不確定閘道器把資料送到哪裡，要讓它改送到{place}。'**
  String networkCheck_targetUnknownSync(String place);

  /// No description provided for @networkCheck_uploadAfterTarget.
  ///
  /// In zh, this message translates to:
  /// **'對準上傳目標後再確認'**
  String get networkCheck_uploadAfterTarget;

  /// No description provided for @networkCheck_uploadAfterWifi.
  ///
  /// In zh, this message translates to:
  /// **'等閘道器連上 Wi-Fi 後再確認'**
  String get networkCheck_uploadAfterWifi;

  /// No description provided for @networkCheck_uploadLinkLost.
  ///
  /// In zh, this message translates to:
  /// **'手機和閘道器的藍牙斷了，無法確認。'**
  String get networkCheck_uploadLinkLost;

  /// No description provided for @networkCheck_uploadLinkLostHint.
  ///
  /// In zh, this message translates to:
  /// **'請靠近閘道器，按「結束並重新選擇閘道器」重新連線。'**
  String get networkCheck_uploadLinkLostHint;

  /// No description provided for @networkCheck_uploadNotConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'還沒確認資料上傳，請按「重新檢查」。'**
  String get networkCheck_uploadNotConfirmed;

  /// No description provided for @networkCheck_uploadNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'閘道器還沒開始上傳資料。'**
  String get networkCheck_uploadNotStarted;

  /// No description provided for @networkCheck_uploadUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'無法確認，最後的資料驗證會再確認。'**
  String get networkCheck_uploadUnsupported;

  /// No description provided for @networkCheck_uploadWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待閘道器開始上傳資料…（最多約 1 分鐘）'**
  String get networkCheck_uploadWaiting;

  /// No description provided for @networkCheck_uploading.
  ///
  /// In zh, this message translates to:
  /// **'資料上傳中'**
  String get networkCheck_uploading;

  /// No description provided for @networkCheck_wifiNotRead.
  ///
  /// In zh, this message translates to:
  /// **'還沒讀到閘道器的網路狀態，請按「重新檢查」。'**
  String get networkCheck_wifiNotRead;

  /// No description provided for @networkCheck_wifiReading.
  ///
  /// In zh, this message translates to:
  /// **'正在讀取閘道器的網路狀態…'**
  String get networkCheck_wifiReading;

  /// Name of the Reset Wi-Fi button, inserted into the subnet hint.
  ///
  /// In zh, this message translates to:
  /// **'重設 Wi-Fi'**
  String get networkCheck_wifiResetAction;

  /// No description provided for @networkCheck_wifiUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'APP 無法讀取這台閘道器的 Wi-Fi（韌體 {fw} 較舊），最後的資料驗證會再確認。'**
  String networkCheck_wifiUnsupported(String fw);

  /// No description provided for @nextActionGuide_captionBegin.
  ///
  /// In zh, this message translates to:
  /// **'連線完成，可以開始開通'**
  String get nextActionGuide_captionBegin;

  /// No description provided for @nextActionGuide_captionConnect.
  ///
  /// In zh, this message translates to:
  /// **'確認目標後，點下方連線'**
  String get nextActionGuide_captionConnect;

  /// No description provided for @nextActionGuide_captionStart.
  ///
  /// In zh, this message translates to:
  /// **'從這裡開始'**
  String get nextActionGuide_captionStart;

  /// No description provided for @protocol_ambiguousTarget.
  ///
  /// In zh, this message translates to:
  /// **'閘道器同時連著多台 PTU，無法判斷要辨識哪一台，請指定 PTU 後重試。'**
  String get protocol_ambiguousTarget;

  /// No description provided for @protocol_authentication.
  ///
  /// In zh, this message translates to:
  /// **'後台登入失敗或已失效，請稍後重試；若仍失敗，請聯絡管理員更新 APP。'**
  String get protocol_authentication;

  /// No description provided for @protocol_backendUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'後端暫時無回應，已自動重試 60 秒仍未恢復。請確認後端後按「重試」，已累計的驗證進度會保留。'**
  String get protocol_backendUnavailable;

  /// No description provided for @protocol_badResponse.
  ///
  /// In zh, this message translates to:
  /// **'後端回應格式無法解析（{backend}）。'**
  String protocol_badResponse(String backend);

  /// {code} is the numeric GATT status (e.g. 133).
  ///
  /// In zh, this message translates to:
  /// **'無法連上閘道器（藍牙錯誤 {code}），請靠近閘道器後重試'**
  String protocol_bleErrorCode(String code);

  /// No description provided for @protocol_bleErrorNoCode.
  ///
  /// In zh, this message translates to:
  /// **'無法連上閘道器（藍牙錯誤），請靠近閘道器後重試'**
  String get protocol_bleErrorNoCode;

  /// No description provided for @protocol_bluetoothOff.
  ///
  /// In zh, this message translates to:
  /// **'請開啟手機藍牙後重試。'**
  String get protocol_bluetoothOff;

  /// No description provided for @protocol_cancelled.
  ///
  /// In zh, this message translates to:
  /// **'操作已取消，可從最近完成的步驟重試。'**
  String get protocol_cancelled;

  /// No description provided for @protocol_conflict.
  ///
  /// In zh, this message translates to:
  /// **'此站點或編號已被使用，請選擇其他編號。'**
  String get protocol_conflict;

  /// Fallback name of the backend inside error sentences.
  ///
  /// In zh, this message translates to:
  /// **'目前設定的後端'**
  String get protocol_currentBackend;

  /// No description provided for @protocol_directDeferUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'閘道器沒有回報已加入運作並恢復上傳，配置尚未完成。請再按一次「先完成配置」；若仍不行，請按「請後台協助」。'**
  String get protocol_directDeferUnconfirmed;

  /// No description provided for @protocol_directNoPtu.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前沒有連上 PTU，無法綁定。請等 PTU 連上後再試。'**
  String get protocol_directNoPtu;

  /// No description provided for @protocol_directPickMissing.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前沒有連上 PTU，請確認 PTU 電源後按「重新搜尋」。'**
  String get protocol_directPickMissing;

  /// No description provided for @protocol_directSwitchFailed.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在等待時限內還沒改連這台 PTU（已暫時綁定它）。連上後畫面會自動更新；也可確認這台 PTU 已上電並靠近，或改選其他 PTU。'**
  String get protocol_directSwitchFailed;

  /// No description provided for @protocol_directThresholdNotSaved.
  ///
  /// In zh, this message translates to:
  /// **'門檻未寫入閘道器（回讀的值不同），請重試。'**
  String get protocol_directThresholdNotSaved;

  /// No description provided for @protocol_directUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'此韌體尚未支援直連門檻與綁定，請先更新韌體（1.7.20 起）。'**
  String get protocol_directUnsupported;

  /// No description provided for @protocol_disconnected.
  ///
  /// In zh, this message translates to:
  /// **'與閘道器的連線已中斷，請靠近後重新連線。'**
  String get protocol_disconnected;

  /// No description provided for @protocol_expired.
  ///
  /// In zh, this message translates to:
  /// **'指令已逾期（手機時間與閘道器差異過大或傳送延遲），請重試'**
  String get protocol_expired;

  /// No description provided for @protocol_fleetUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'資料已上傳，但閘道器沒有回報「已加入監控」（APP 已自動補送一次），開通尚未完成。請靠近閘道器後按「開始資料驗證」重試；若仍不行，請按「請後台協助」。'**
  String get protocol_fleetUnconfirmed;

  /// No description provided for @protocol_gatewayBusy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器正在準備或處理其他操作，請稍後重試。'**
  String get protocol_gatewayBusy;

  /// No description provided for @protocol_gatewayFailedNoReason.
  ///
  /// In zh, this message translates to:
  /// **'閘道器回報失敗（未提供原因）。'**
  String get protocol_gatewayFailedNoReason;

  /// No description provided for @protocol_gatewayFailedSeeDetails.
  ///
  /// In zh, this message translates to:
  /// **'閘道器回報失敗，請查看詳細資訊。'**
  String get protocol_gatewayFailedSeeDetails;

  /// {code} is the raw firmware failure text (not translated).
  ///
  /// In zh, this message translates to:
  /// **'閘道器回報失敗：{code}'**
  String protocol_gatewayFailedWithCode(String code);

  /// No description provided for @protocol_gatewayFull.
  ///
  /// In zh, this message translates to:
  /// **'本機已滿，請連另一台閘道器。'**
  String get protocol_gatewayFull;

  /// No description provided for @protocol_gatewayNotFound.
  ///
  /// In zh, this message translates to:
  /// **'後端找不到此閘道器{where}。閘道器的資料可能上傳到其他後端環境（例如正式站），而 APP 目前連的是 {backend}。'**
  String protocol_gatewayNotFound(String where, String backend);

  /// HTTP 404 gateway_not_found with a known cause sentence.
  ///
  /// In zh, this message translates to:
  /// **'後端找不到此閘道器{where}（APP 目前連的是 {backend}）。{cause}'**
  String protocol_gatewayNotFoundCause(
    String where,
    String backend,
    String cause,
  );

  /// No description provided for @protocol_gatewayServiceNotReady.
  ///
  /// In zh, this message translates to:
  /// **'閘道器藍牙服務尚未就緒，請稍後再試'**
  String get protocol_gatewayServiceNotReady;

  /// No description provided for @protocol_httpRejected.
  ///
  /// In zh, this message translates to:
  /// **'後端拒絕此請求（HTTP {status}）。'**
  String protocol_httpRejected(int status);

  /// No description provided for @protocol_httpServerError.
  ///
  /// In zh, this message translates to:
  /// **'後端內部錯誤（HTTP {status}），請查看後端紀錄後重試。'**
  String protocol_httpServerError(int status);

  /// No description provided for @protocol_httpsRequired.
  ///
  /// In zh, this message translates to:
  /// **'正式環境需要有效的 HTTPS 網址。'**
  String get protocol_httpsRequired;

  /// No description provided for @protocol_identifyDurationUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'這台舊版閘道器不支援所選辨識秒數。支援 PTU 辨識的舊版僅可用 1–30 秒，更早版本固定 6 秒；其他秒數（含 0 秒關燈）請更新閘道器韌體。'**
  String get protocol_identifyDurationUnsupported;

  /// No description provided for @protocol_identifyNoPtu.
  ///
  /// In zh, this message translates to:
  /// **'閘道器尚未連上 PTU，無法讓 PTU 閃燈。請確認同樁 PTU 已上電並靠近後重試。'**
  String get protocol_identifyNoPtu;

  /// No description provided for @protocol_identifyUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'此韌體尚未支援辨識燈號，請先更新韌體。連線時的呼吸燈仍可協助辨識。'**
  String get protocol_identifyUnsupported;

  /// The first sentence is used alone as a checklist reason.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器之前在後台被移除（封存），後台不會記錄它的心跳。請按下方「重新加入」，恢復記錄後會繼續確認上線。'**
  String get protocol_identityArchived;

  /// No description provided for @protocol_incomplete.
  ///
  /// In zh, this message translates to:
  /// **'仍有 PTU 未連線或資料未到達，請查看各台狀態後重試。'**
  String get protocol_incomplete;

  /// No description provided for @protocol_invalidIdentifySeconds.
  ///
  /// In zh, this message translates to:
  /// **'辨識秒數必須是 0（關燈）或 2–10 的整數；1 秒會讓 PTU 燈恆亮，因此不提供。'**
  String get protocol_invalidIdentifySeconds;

  /// No description provided for @protocol_locationOff.
  ///
  /// In zh, this message translates to:
  /// **'此版本 Android 搜尋藍牙需要定位服務，請開啟手機定位後重新搜尋。'**
  String get protocol_locationOff;

  /// No description provided for @protocol_monitorUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'30 秒內未確認閘道器已恢復監控，可按「重新連線並繼續」重試，或「略過」直接驗證資料。'**
  String get protocol_monitorUnconfirmed;

  /// No description provided for @protocol_networkUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'無法連到 {backend}。請確認手機與後端電腦在同一個 Wi-Fi 網段、電腦防火牆允許該連接埠，以及後端網址是否正確。'**
  String protocol_networkUnreachable(String backend);

  /// No description provided for @protocol_newSiteRequired.
  ///
  /// In zh, this message translates to:
  /// **'請輸入與目前站點不同的新站點 ID。'**
  String get protocol_newSiteRequired;

  /// No description provided for @protocol_noDevices.
  ///
  /// In zh, this message translates to:
  /// **'未找到 PTU。請確認已上電並靠近閘道器後重掃。'**
  String get protocol_noDevices;

  /// Parenthetical inserted as {where} into the gateway-not-found sentences.
  ///
  /// In zh, this message translates to:
  /// **'（站 {site} / 閘道器 {gateway}）'**
  String protocol_notFoundWhere(int site, int gateway);

  /// No description provided for @protocol_otherFailure.
  ///
  /// In zh, this message translates to:
  /// **'操作未完成，請確認裝置狀態後重試。'**
  String get protocol_otherFailure;

  /// No description provided for @protocol_otpInvalid.
  ///
  /// In zh, this message translates to:
  /// **'一次性密碼錯誤'**
  String get protocol_otpInvalid;

  /// No description provided for @protocol_otpLocked.
  ///
  /// In zh, this message translates to:
  /// **'一次性密碼已鎖定，請稍後再試'**
  String get protocol_otpLocked;

  /// No description provided for @protocol_otpRequired.
  ///
  /// In zh, this message translates to:
  /// **'此閘道器已啟用一次性密碼，請聯絡管理員。'**
  String get protocol_otpRequired;

  /// No description provided for @protocol_otpReused.
  ///
  /// In zh, this message translates to:
  /// **'一次性密碼已用過'**
  String get protocol_otpReused;

  /// No description provided for @protocol_permission.
  ///
  /// In zh, this message translates to:
  /// **'需要藍牙權限，請至系統設定允許後重試。'**
  String get protocol_permission;

  /// No description provided for @protocol_phoneLinkLost.
  ///
  /// In zh, this message translates to:
  /// **'手機與閘道器的藍牙連線中斷，請靠近閘道器後按「重新連線並繼續」'**
  String get protocol_phoneLinkLost;

  /// No description provided for @protocol_ptuConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'PTU 連線失敗，請確認 PTU 電源與距離'**
  String get protocol_ptuConnectFailed;

  /// No description provided for @protocol_ptuIdentityMismatch.
  ///
  /// In zh, this message translates to:
  /// **'後台資料的 PTU 身分與本次選擇不符，或缺少 MAC，尚未完成驗證。請返回確認本樁 PTU；若仍不符，請後台協助。'**
  String get protocol_ptuIdentityMismatch;

  /// No description provided for @protocol_ptuNoResponse.
  ///
  /// In zh, this message translates to:
  /// **'PTU 沒有回應'**
  String get protocol_ptuNoResponse;

  /// No description provided for @protocol_reconnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'重新連線失敗，請靠近閘道器後重試，或回到找閘道器。'**
  String get protocol_reconnectFailed;

  /// No description provided for @protocol_replacePending.
  ///
  /// In zh, this message translates to:
  /// **'後台已登記為新機，但寫入裝置失敗。請重新執行配置，系統會沿用取代設定。'**
  String get protocol_replacePending;

  /// No description provided for @protocol_replaceUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'後端版本不支援取代舊機，請改用下一個編號。裝置設定未變更。'**
  String get protocol_replaceUnsupported;

  /// Targets are upload-target labels (e.g. production / local test host).
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前把資料送到{gatewayTarget}，但手機連的是{appTarget}，資料到不了手機連的這個後端，所以直接停止驗證（不必空等）。\n請在「連線狀態」按「同步」，或點右上角的環境按鈕重新選一次，讓閘道器和手機連同一個地方後再驗證。'**
  String protocol_targetMismatch(String gatewayTarget, String appTarget);

  /// No description provided for @protocol_targetReadback.
  ///
  /// In zh, this message translates to:
  /// **'閘道器重新連上後回報的資料上傳目的地是{actual}，不是要求的{wanted}。設定可能沒有生效，請在「連線狀態」按重新讀取確認，或再同步一次。'**
  String protocol_targetReadback(String actual, String wanted);

  /// No description provided for @protocol_targetReconnect.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已收到切換指令並重新開機，但 45 秒內未能重新連上藍牙。請靠近閘道器，按「結束並重新選擇閘道器」重新連線後看「連線狀態」。'**
  String get protocol_targetReconnect;

  /// {button} is the leave-test-mode button name.
  ///
  /// In zh, this message translates to:
  /// **'閘道器重新開機後仍在測試模式，請再按一次「{button}」；若仍不行，請按「請後台協助」。'**
  String protocol_testModeStuck(String button);

  /// No description provided for @protocol_timeNotSynced.
  ///
  /// In zh, this message translates to:
  /// **'閘道器時間尚未同步。若無可用網路，請先以 USB 更新韌體。'**
  String get protocol_timeNotSynced;

  /// No description provided for @protocol_timeout.
  ///
  /// In zh, this message translates to:
  /// **'等待超時，請確認裝置與網路後重試。'**
  String get protocol_timeout;

  /// No description provided for @protocol_unexpected.
  ///
  /// In zh, this message translates to:
  /// **'APP 發生未預期錯誤：{detail}'**
  String protocol_unexpected(String detail);

  /// {button} is the resume-upload button name.
  ///
  /// In zh, this message translates to:
  /// **'閘道器仍回報資料上傳暫停，請再按一次「{button}」；若仍不行，請按「請後台協助」。'**
  String protocol_uploadPaused(String button);

  /// No description provided for @protocol_wifiPasswordNeeded.
  ///
  /// In zh, this message translates to:
  /// **'閘道器目前沒有連上這個 Wi-Fi，無法沿用。請輸入 Wi-Fi 密碼後再按「儲存並繼續」。'**
  String get protocol_wifiPasswordNeeded;

  /// No description provided for @protocol_writeFailed.
  ///
  /// In zh, this message translates to:
  /// **'寫入 PTU 失敗（閘道器未能送出辨識指令），請確認 PTU 電源與距離後重試。'**
  String get protocol_writeFailed;

  /// RSSI of a connected PTU without a reading age.
  ///
  /// In zh, this message translates to:
  /// **'快取 {rssi} dBm'**
  String ptuRssi_cached(String rssi);

  /// Gateway-to-PTU RSSI from an earlier reading.
  ///
  /// In zh, this message translates to:
  /// **'上次 {rssi} dBm'**
  String ptuRssi_last(String rssi);

  /// RSSI from the discovery scan (PTU not connected).
  ///
  /// In zh, this message translates to:
  /// **'掃描 {rssi} dBm'**
  String ptuRssi_scan(String rssi);

  /// No description provided for @ptuSelectionTile_blocked.
  ///
  /// In zh, this message translates to:
  /// **'已屬於其他閘道器'**
  String get ptuSelectionTile_blocked;

  /// No description provided for @ptuSelectionTile_connected.
  ///
  /// In zh, this message translates to:
  /// **'已連線'**
  String get ptuSelectionTile_connected;

  /// No description provided for @ptuSelectionTile_connectedHere.
  ///
  /// In zh, this message translates to:
  /// **'已連線至此閘道器'**
  String get ptuSelectionTile_connectedHere;

  /// No description provided for @ptuSelectionTile_detailTitle.
  ///
  /// In zh, this message translates to:
  /// **'詳細（最近一次失敗）'**
  String get ptuSelectionTile_detailTitle;

  /// No description provided for @ptuSelectionTile_infoTooltip.
  ///
  /// In zh, this message translates to:
  /// **'{title} 裝置資訊'**
  String ptuSelectionTile_infoTooltip(String title);

  /// No description provided for @ptuSelectionTile_mac.
  ///
  /// In zh, this message translates to:
  /// **'MAC：{mac}'**
  String ptuSelectionTile_mac(String mac);

  /// No description provided for @ptuSelectionTile_name.
  ///
  /// In zh, this message translates to:
  /// **'名稱：{name}'**
  String ptuSelectionTile_name(String name);

  /// No description provided for @ptuSelectionTile_noReading.
  ///
  /// In zh, this message translates to:
  /// **'尚無讀值'**
  String get ptuSelectionTile_noReading;

  /// No description provided for @ptuSelectionTile_notConnected.
  ///
  /// In zh, this message translates to:
  /// **'未連線'**
  String get ptuSelectionTile_notConnected;

  /// No description provided for @ptuSelectionTile_peripheralNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'周邊未連線'**
  String get ptuSelectionTile_peripheralNotConnected;

  /// No description provided for @ptuSelectionTile_readingState.
  ///
  /// In zh, this message translates to:
  /// **'讀值狀態：{text}'**
  String ptuSelectionTile_readingState(String text);

  /// Button: clear this PTU's number and rescan so it can be selected.
  ///
  /// In zh, this message translates to:
  /// **'重置並納入'**
  String get ptuSelectionTile_reset;

  /// No description provided for @ptuSelectionTile_selectSemantic.
  ///
  /// In zh, this message translates to:
  /// **'選擇 {title}，{mac}'**
  String ptuSelectionTile_selectSemantic(String title, String mac);

  /// No description provided for @ptuSelectionTile_signal.
  ///
  /// In zh, this message translates to:
  /// **'訊號：{value}'**
  String ptuSelectionTile_signal(String value);

  /// No description provided for @ptuSelectionTile_snapshotNote.
  ///
  /// In zh, this message translates to:
  /// **'此處為開啟時的讀值；動態數值請看清單。'**
  String get ptuSelectionTile_snapshotNote;

  /// No description provided for @ptuSelectionTile_status.
  ///
  /// In zh, this message translates to:
  /// **'狀態：{text}'**
  String ptuSelectionTile_status(String text);

  /// No description provided for @ptuSelectionTile_unassigned.
  ///
  /// In zh, this message translates to:
  /// **'未指派 PTU'**
  String get ptuSelectionTile_unassigned;

  /// No description provided for @recentDataApi_authRefused.
  ///
  /// In zh, this message translates to:
  /// **'後台拒絕此 APP 的登入憑證，請聯絡管理員更新 APP'**
  String get recentDataApi_authRefused;

  /// No description provided for @recentDataApi_errorText.
  ///
  /// In zh, this message translates to:
  /// **'連不上後台（{reason}）'**
  String recentDataApi_errorText(String reason);

  /// Upload interval in whole minutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes, plural, other{{minutes} 分鐘}}'**
  String recentDataApi_minutes(int minutes);

  /// Upload interval in whole seconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds, plural, other{{seconds} 秒}}'**
  String recentDataApi_seconds(int seconds);

  /// Used as {ago} in recentDataApi_summary.
  ///
  /// In zh, this message translates to:
  /// **'{seconds, plural, other{{seconds} 秒前}}'**
  String recentDataApi_secondsAgo(int seconds);

  /// Upload interval with one decimal (e.g. 1.5).
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String recentDataApi_secondsDecimal(String seconds);

  /// No description provided for @recentDataApi_summary.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{最近一筆 {ago}・共 {count} 筆}}'**
  String recentDataApi_summary(int count, String ago);

  /// Used as {ago} in recentDataApi_summary.
  ///
  /// In zh, this message translates to:
  /// **'時間不明'**
  String get recentDataApi_timeUnknown;

  /// No description provided for @recentDataPage_ageDays.
  ///
  /// In zh, this message translates to:
  /// **'{n, plural, other{{n} 天}}'**
  String recentDataPage_ageDays(int n);

  /// No description provided for @recentDataPage_ageHours.
  ///
  /// In zh, this message translates to:
  /// **'{n} 小時'**
  String recentDataPage_ageHours(int n);

  /// No description provided for @recentDataPage_ageMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{n} 分鐘'**
  String recentDataPage_ageMinutes(int n);

  /// No description provided for @recentDataPage_ageSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{n} 秒'**
  String recentDataPage_ageSeconds(int n);

  /// No description provided for @recentDataPage_ago.
  ///
  /// In zh, this message translates to:
  /// **'{age}前'**
  String recentDataPage_ago(String age);

  /// No description provided for @recentDataPage_batteryVoltage.
  ///
  /// In zh, this message translates to:
  /// **'Battery Voltage'**
  String get recentDataPage_batteryVoltage;

  /// No description provided for @recentDataPage_chargingCurrent.
  ///
  /// In zh, this message translates to:
  /// **'Charging Current'**
  String get recentDataPage_chargingCurrent;

  /// No description provided for @recentDataPage_current.
  ///
  /// In zh, this message translates to:
  /// **'電流'**
  String get recentDataPage_current;

  /// No description provided for @recentDataPage_dataTime.
  ///
  /// In zh, this message translates to:
  /// **'資料時間'**
  String get recentDataPage_dataTime;

  /// No description provided for @recentDataPage_deviceError.
  ///
  /// In zh, this message translates to:
  /// **'裝置異常（錯誤碼 {code}）'**
  String recentDataPage_deviceError(int code);

  /// No description provided for @recentDataPage_efficiency.
  ///
  /// In zh, this message translates to:
  /// **'效率'**
  String get recentDataPage_efficiency;

  /// No description provided for @recentDataPage_empty.
  ///
  /// In zh, this message translates to:
  /// **'後台尚未收到這台閘道器的資料，請稍等一下再重新整理'**
  String get recentDataPage_empty;

  /// No description provided for @recentDataPage_emptyInterval.
  ///
  /// In zh, this message translates to:
  /// **'後台尚未收到這台閘道器的資料；閘道器約每 {interval}上傳一筆，請稍後再重新整理'**
  String recentDataPage_emptyInterval(String interval);

  /// No description provided for @recentDataPage_errorChargeComplete.
  ///
  /// In zh, this message translates to:
  /// **'充電完成'**
  String get recentDataPage_errorChargeComplete;

  /// No description provided for @recentDataPage_errorClearComplete.
  ///
  /// In zh, this message translates to:
  /// **'重新啟動充電'**
  String get recentDataPage_errorClearComplete;

  /// No description provided for @recentDataPage_errorCode.
  ///
  /// In zh, this message translates to:
  /// **'錯誤碼'**
  String get recentDataPage_errorCode;

  /// No description provided for @recentDataPage_errorNone.
  ///
  /// In zh, this message translates to:
  /// **'無錯誤'**
  String get recentDataPage_errorNone;

  /// No description provided for @recentDataPage_errorPruCharged.
  ///
  /// In zh, this message translates to:
  /// **'PRU 已充滿'**
  String get recentDataPage_errorPruCharged;

  /// No description provided for @recentDataPage_errorPruOc.
  ///
  /// In zh, this message translates to:
  /// **'PRU 過流'**
  String get recentDataPage_errorPruOc;

  /// No description provided for @recentDataPage_errorPruOt.
  ///
  /// In zh, this message translates to:
  /// **'PRU 過溫'**
  String get recentDataPage_errorPruOt;

  /// No description provided for @recentDataPage_errorPruOv.
  ///
  /// In zh, this message translates to:
  /// **'PRU 過壓'**
  String get recentDataPage_errorPruOv;

  /// No description provided for @recentDataPage_errorPtuComm.
  ///
  /// In zh, this message translates to:
  /// **'PTU 通訊錯誤'**
  String get recentDataPage_errorPtuComm;

  /// No description provided for @recentDataPage_errorPtuLpStuck.
  ///
  /// In zh, this message translates to:
  /// **'PTU Low Power 卡住'**
  String get recentDataPage_errorPtuLpStuck;

  /// No description provided for @recentDataPage_errorPtuOcBus.
  ///
  /// In zh, this message translates to:
  /// **'PTU IBUS 電流過流'**
  String get recentDataPage_errorPtuOcBus;

  /// No description provided for @recentDataPage_errorPtuOcI1.
  ///
  /// In zh, this message translates to:
  /// **'PTU I1 電流過流'**
  String get recentDataPage_errorPtuOcI1;

  /// No description provided for @recentDataPage_errorPtuOcI3.
  ///
  /// In zh, this message translates to:
  /// **'PTU I3 電流過流'**
  String get recentDataPage_errorPtuOcI3;

  /// No description provided for @recentDataPage_errorPtuOcIn.
  ///
  /// In zh, this message translates to:
  /// **'PTU Iin 電流過流'**
  String get recentDataPage_errorPtuOcIn;

  /// No description provided for @recentDataPage_errorPtuOtDcdc.
  ///
  /// In zh, this message translates to:
  /// **'PTU DCDC 過溫'**
  String get recentDataPage_errorPtuOtDcdc;

  /// No description provided for @recentDataPage_errorPtuOtIc.
  ///
  /// In zh, this message translates to:
  /// **'PTU IC 過溫'**
  String get recentDataPage_errorPtuOtIc;

  /// No description provided for @recentDataPage_errorPtuOtPa.
  ///
  /// In zh, this message translates to:
  /// **'PTU PA 過溫'**
  String get recentDataPage_errorPtuOtPa;

  /// No description provided for @recentDataPage_errorPtuPhase.
  ///
  /// In zh, this message translates to:
  /// **'PTU I1/I3 相位異常'**
  String get recentDataPage_errorPtuPhase;

  /// No description provided for @recentDataPage_errorPtuPtStuck.
  ///
  /// In zh, this message translates to:
  /// **'PTU Power Transfer 卡住'**
  String get recentDataPage_errorPtuPtStuck;

  /// No description provided for @recentDataPage_errorPtuTimeset.
  ///
  /// In zh, this message translates to:
  /// **'PTU Timeset 失敗'**
  String get recentDataPage_errorPtuTimeset;

  /// No description provided for @recentDataPage_errorUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知錯誤'**
  String get recentDataPage_errorUnknown;

  /// No description provided for @recentDataPage_fault.
  ///
  /// In zh, this message translates to:
  /// **'PTU 回報故障'**
  String get recentDataPage_fault;

  /// No description provided for @recentDataPage_faultCode.
  ///
  /// In zh, this message translates to:
  /// **'Fault Code'**
  String get recentDataPage_faultCode;

  /// Button on the done page that opens the recent-data page.
  ///
  /// In zh, this message translates to:
  /// **'查看最近資料'**
  String get recentDataPage_label;

  /// No description provided for @recentDataPage_latestRest.
  ///
  /// In zh, this message translates to:
  /// **'{state}・{clock}（{ago}）'**
  String recentDataPage_latestRest(String state, String clock, String ago);

  /// No description provided for @recentDataPage_latestUnknown.
  ///
  /// In zh, this message translates to:
  /// **'最近一筆的時間不明'**
  String get recentDataPage_latestUnknown;

  /// No description provided for @recentDataPage_noNewData.
  ///
  /// In zh, this message translates to:
  /// **'最近 {age}沒有新資料'**
  String recentDataPage_noNewData(String age);

  /// No description provided for @recentDataPage_ok.
  ///
  /// In zh, this message translates to:
  /// **'上傳正常'**
  String get recentDataPage_ok;

  /// No description provided for @recentDataPage_overallEfficiency.
  ///
  /// In zh, this message translates to:
  /// **'整體效率'**
  String get recentDataPage_overallEfficiency;

  /// No description provided for @recentDataPage_pruCurrent.
  ///
  /// In zh, this message translates to:
  /// **'電流'**
  String get recentDataPage_pruCurrent;

  /// No description provided for @recentDataPage_pruOutputPower.
  ///
  /// In zh, this message translates to:
  /// **'PRU 輸出功率'**
  String get recentDataPage_pruOutputPower;

  /// No description provided for @recentDataPage_pruTemperature.
  ///
  /// In zh, this message translates to:
  /// **'接收端溫度'**
  String get recentDataPage_pruTemperature;

  /// No description provided for @recentDataPage_ptuInputPower.
  ///
  /// In zh, this message translates to:
  /// **'PTU 輸入功率'**
  String get recentDataPage_ptuInputPower;

  /// No description provided for @recentDataPage_ptuTemperature.
  ///
  /// In zh, this message translates to:
  /// **'發射端溫度'**
  String get recentDataPage_ptuTemperature;

  /// No description provided for @recentDataPage_shortCharging.
  ///
  /// In zh, this message translates to:
  /// **'充電'**
  String get recentDataPage_shortCharging;

  /// Short PTU state for a narrow table column (about 4 CJK characters / 8 Latin characters wide).
  ///
  /// In zh, this message translates to:
  /// **'設定'**
  String get recentDataPage_shortConfiguration;

  /// No description provided for @recentDataPage_shortCooling.
  ///
  /// In zh, this message translates to:
  /// **'冷卻'**
  String get recentDataPage_shortCooling;

  /// No description provided for @recentDataPage_shortExceeded.
  ///
  /// In zh, this message translates to:
  /// **'超範圍'**
  String get recentDataPage_shortExceeded;

  /// No description provided for @recentDataPage_shortFault.
  ///
  /// In zh, this message translates to:
  /// **'故障'**
  String get recentDataPage_shortFault;

  /// No description provided for @recentDataPage_shortIdle.
  ///
  /// In zh, this message translates to:
  /// **'待機'**
  String get recentDataPage_shortIdle;

  /// No description provided for @recentDataPage_shortLowPower.
  ///
  /// In zh, this message translates to:
  /// **'低功率'**
  String get recentDataPage_shortLowPower;

  /// No description provided for @recentDataPage_shortPowerSave.
  ///
  /// In zh, this message translates to:
  /// **'省電'**
  String get recentDataPage_shortPowerSave;

  /// PTU state CONFIGURATION (firmware ptu_state).
  ///
  /// In zh, this message translates to:
  /// **'設定中'**
  String get recentDataPage_stateConfiguration;

  /// No description provided for @recentDataPage_stateCooling.
  ///
  /// In zh, this message translates to:
  /// **'冷卻中'**
  String get recentDataPage_stateCooling;

  /// No description provided for @recentDataPage_stateExceededRange.
  ///
  /// In zh, this message translates to:
  /// **'PRU 超出範圍'**
  String get recentDataPage_stateExceededRange;

  /// No description provided for @recentDataPage_stateLabel.
  ///
  /// In zh, this message translates to:
  /// **'狀態'**
  String get recentDataPage_stateLabel;

  /// No description provided for @recentDataPage_stateLatchFault.
  ///
  /// In zh, this message translates to:
  /// **'鎖定故障'**
  String get recentDataPage_stateLatchFault;

  /// No description provided for @recentDataPage_stateLocalFault.
  ///
  /// In zh, this message translates to:
  /// **'本地故障'**
  String get recentDataPage_stateLocalFault;

  /// No description provided for @recentDataPage_stateLowPower.
  ///
  /// In zh, this message translates to:
  /// **'低功率'**
  String get recentDataPage_stateLowPower;

  /// No description provided for @recentDataPage_stateOta.
  ///
  /// In zh, this message translates to:
  /// **'OTA 更新中'**
  String get recentDataPage_stateOta;

  /// No description provided for @recentDataPage_statePowerSave.
  ///
  /// In zh, this message translates to:
  /// **'省電'**
  String get recentDataPage_statePowerSave;

  /// No description provided for @recentDataPage_statePowerTransfer.
  ///
  /// In zh, this message translates to:
  /// **'充電中'**
  String get recentDataPage_statePowerTransfer;

  /// No description provided for @recentDataPage_systemCharging.
  ///
  /// In zh, this message translates to:
  /// **'Charging'**
  String get recentDataPage_systemCharging;

  /// No description provided for @recentDataPage_systemFault.
  ///
  /// In zh, this message translates to:
  /// **'Fault'**
  String get recentDataPage_systemFault;

  /// No description provided for @recentDataPage_systemNormal.
  ///
  /// In zh, this message translates to:
  /// **'Normal'**
  String get recentDataPage_systemNormal;

  /// No description provided for @recentDataPage_systemStatus.
  ///
  /// In zh, this message translates to:
  /// **'System Status / Fault'**
  String get recentDataPage_systemStatus;

  /// No description provided for @recentDataPage_systemWarning.
  ///
  /// In zh, this message translates to:
  /// **'Warning'**
  String get recentDataPage_systemWarning;

  /// No description provided for @recentDataPage_tableTitleCount.
  ///
  /// In zh, this message translates to:
  /// **'{title}（{count} 筆）'**
  String recentDataPage_tableTitleCount(String title, int count);

  /// No description provided for @recentDataPage_temperature.
  ///
  /// In zh, this message translates to:
  /// **'溫度'**
  String get recentDataPage_temperature;

  /// No description provided for @recentDataPage_time.
  ///
  /// In zh, this message translates to:
  /// **'時間'**
  String get recentDataPage_time;

  /// No description provided for @recentDataPage_timeUnknown.
  ///
  /// In zh, this message translates to:
  /// **'時間不明'**
  String get recentDataPage_timeUnknown;

  /// AppBar title of the recent-data page and its table section.
  ///
  /// In zh, this message translates to:
  /// **'最近資料'**
  String get recentDataPage_title;

  /// No description provided for @recentDataPage_trend.
  ///
  /// In zh, this message translates to:
  /// **'最近 {n} 筆・跨 {span}・平均每秒 {rate} 筆'**
  String recentDataPage_trend(int n, String span, String rate);

  /// No description provided for @recentDataPage_trendCount.
  ///
  /// In zh, this message translates to:
  /// **'{n, plural, other{最近 {n} 筆}}'**
  String recentDataPage_trendCount(int n);

  /// No description provided for @recentDataPage_vehicleType.
  ///
  /// In zh, this message translates to:
  /// **'車型'**
  String get recentDataPage_vehicleType;

  /// No description provided for @recentDataPage_voltage.
  ///
  /// In zh, this message translates to:
  /// **'電壓'**
  String get recentDataPage_voltage;

  /// No description provided for @recentGateways_archivedLabel.
  ///
  /// In zh, this message translates to:
  /// **'已封存（後台已移除）'**
  String get recentGateways_archivedLabel;

  /// No description provided for @recentGateways_configuredLabel.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get recentGateways_configuredLabel;

  /// No description provided for @recentGateways_queryFailed.
  ///
  /// In zh, this message translates to:
  /// **'後端狀態未知・查詢失敗（{detail}）'**
  String recentGateways_queryFailed(String detail);

  /// No description provided for @recentGateways_queryTimeout.
  ///
  /// In zh, this message translates to:
  /// **'後端狀態未知・查詢逾時（8 秒）'**
  String get recentGateways_queryTimeout;

  /// No description provided for @recentGateways_reportedOffline.
  ///
  /// In zh, this message translates to:
  /// **'後端回報離線'**
  String get recentGateways_reportedOffline;

  /// No description provided for @recentGateways_reportedOnline.
  ///
  /// In zh, this message translates to:
  /// **'後端回報在線上'**
  String get recentGateways_reportedOnline;

  /// No description provided for @recentGateways_shortArchived.
  ///
  /// In zh, this message translates to:
  /// **'後端已封存'**
  String get recentGateways_shortArchived;

  /// No description provided for @recentGateways_shortNoRecord.
  ///
  /// In zh, this message translates to:
  /// **'後端無紀錄'**
  String get recentGateways_shortNoRecord;

  /// No description provided for @recentGateways_shortOffline.
  ///
  /// In zh, this message translates to:
  /// **'後端離線'**
  String get recentGateways_shortOffline;

  /// Short badge on the gateway list (BackendPresence.online).
  ///
  /// In zh, this message translates to:
  /// **'後端在線'**
  String get recentGateways_shortOnline;

  /// No description provided for @recentGateways_shortUnknown.
  ///
  /// In zh, this message translates to:
  /// **'後端未知'**
  String get recentGateways_shortUnknown;

  /// No description provided for @recentGateways_unknown.
  ///
  /// In zh, this message translates to:
  /// **'後端狀態未知'**
  String get recentGateways_unknown;

  /// No description provided for @recentGateways_unknownConflict.
  ///
  /// In zh, this message translates to:
  /// **'後端狀態未知・後台標示身分衝突'**
  String get recentGateways_unknownConflict;

  /// No description provided for @recentGateways_unknownDuplicates.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{後端狀態未知・後台有 {count} 筆相同 MAC 的紀錄}}'**
  String recentGateways_unknownDuplicates(int count);

  /// No description provided for @recentGateways_unknownNoHeartbeat.
  ///
  /// In zh, this message translates to:
  /// **'後端狀態未知・後台沒有這個 MAC 的心跳紀錄'**
  String get recentGateways_unknownNoHeartbeat;

  /// Gateway list: back-office status of a gateway; the part after the dot says why it is unknown.
  ///
  /// In zh, this message translates to:
  /// **'後端狀態未知・連線後確認身分'**
  String get recentGateways_unknownUnverified;

  /// No description provided for @rescueCode_appUnexpected.
  ///
  /// In zh, this message translates to:
  /// **'APP 發生未預期錯誤'**
  String get rescueCode_appUnexpected;

  /// No description provided for @rescueCode_backendAuth.
  ///
  /// In zh, this message translates to:
  /// **'後台登入失效'**
  String get rescueCode_backendAuth;

  /// No description provided for @rescueCode_backendDown.
  ///
  /// In zh, this message translates to:
  /// **'APP 連不到後台'**
  String get rescueCode_backendDown;

  /// No description provided for @rescueCode_bleConnectFail.
  ///
  /// In zh, this message translates to:
  /// **'手機連不上閘道器（藍牙錯誤）'**
  String get rescueCode_bleConnectFail;

  /// No description provided for @rescueCode_bleLinkDrop.
  ///
  /// In zh, this message translates to:
  /// **'手機和閘道器的藍牙斷了'**
  String get rescueCode_bleLinkDrop;

  /// No description provided for @rescueCode_bleReconnectFail.
  ///
  /// In zh, this message translates to:
  /// **'重新連線失敗'**
  String get rescueCode_bleReconnectFail;

  /// No description provided for @rescueCode_cmdTimeout.
  ///
  /// In zh, this message translates to:
  /// **'閘道器沒有回應'**
  String get rescueCode_cmdTimeout;

  /// No description provided for @rescueCode_directPick.
  ///
  /// In zh, this message translates to:
  /// **'直連選台失敗'**
  String get rescueCode_directPick;

  /// No description provided for @rescueCode_fwTooOld.
  ///
  /// In zh, this message translates to:
  /// **'韌體太舊，不支援這個功能'**
  String get rescueCode_fwTooOld;

  /// No description provided for @rescueCode_gwAuthRefused.
  ///
  /// In zh, this message translates to:
  /// **'閘道器拒絕指令（一次性密碼或時間未同步）'**
  String get rescueCode_gwAuthRefused;

  /// No description provided for @rescueCode_gwBusy.
  ///
  /// In zh, this message translates to:
  /// **'閘道器忙碌（已自動重試 20 秒）'**
  String get rescueCode_gwBusy;

  /// No description provided for @rescueCode_gwFull.
  ///
  /// In zh, this message translates to:
  /// **'這台閘道器已滿'**
  String get rescueCode_gwFull;

  /// No description provided for @rescueCode_gwLowMemory.
  ///
  /// In zh, this message translates to:
  /// **'閘道器記憶體不足'**
  String get rescueCode_gwLowMemory;

  /// No description provided for @rescueCode_gwNotFound.
  ///
  /// In zh, this message translates to:
  /// **'手機找不到閘道器'**
  String get rescueCode_gwNotFound;

  /// No description provided for @rescueCode_gwNotInBackend.
  ///
  /// In zh, this message translates to:
  /// **'後台沒有這台閘道器的資料'**
  String get rescueCode_gwNotInBackend;

  /// No description provided for @rescueCode_gwRebooted.
  ///
  /// In zh, this message translates to:
  /// **'閘道器剛重新啟動'**
  String get rescueCode_gwRebooted;

  /// No description provided for @rescueCode_gwRejected.
  ///
  /// In zh, this message translates to:
  /// **'閘道器回報失敗'**
  String get rescueCode_gwRejected;

  /// No description provided for @rescueCode_helpOnly.
  ///
  /// In zh, this message translates to:
  /// **'畫面沒有錯誤，現場主動求助'**
  String get rescueCode_helpOnly;

  /// No description provided for @rescueCode_identityConflict.
  ///
  /// In zh, this message translates to:
  /// **'站號已被別台使用'**
  String get rescueCode_identityConflict;

  /// No description provided for @rescueCode_identityReplace.
  ///
  /// In zh, this message translates to:
  /// **'取代舊機沒完成'**
  String get rescueCode_identityReplace;

  /// No description provided for @rescueCode_monitorUnconfirmed.
  ///
  /// In zh, this message translates to:
  /// **'還沒確認閘道器已恢復監控'**
  String get rescueCode_monitorUnconfirmed;

  /// Rescue code in words for the installer (help sheet). Never sent to the back office.
  ///
  /// In zh, this message translates to:
  /// **'手機藍牙沒開'**
  String get rescueCode_phoneBtOff;

  /// No description provided for @rescueCode_phonePermission.
  ///
  /// In zh, this message translates to:
  /// **'APP 沒有藍牙／定位權限'**
  String get rescueCode_phonePermission;

  /// No description provided for @rescueCode_ptuConnectFail.
  ///
  /// In zh, this message translates to:
  /// **'閘道器連不上 PTU'**
  String get rescueCode_ptuConnectFail;

  /// No description provided for @rescueCode_ptuNoResponse.
  ///
  /// In zh, this message translates to:
  /// **'PTU 沒回應'**
  String get rescueCode_ptuNoResponse;

  /// No description provided for @rescueCode_ptuNoneFound.
  ///
  /// In zh, this message translates to:
  /// **'掃不到 PTU'**
  String get rescueCode_ptuNoneFound;

  /// No description provided for @rescueCode_ptuResidual.
  ///
  /// In zh, this message translates to:
  /// **'有 PTU 帶舊編號，或屬於其他閘道器'**
  String get rescueCode_ptuResidual;

  /// No description provided for @rescueCode_ptuWrongDevice.
  ///
  /// In zh, this message translates to:
  /// **'編號寫到別台，或回讀不符'**
  String get rescueCode_ptuWrongDevice;

  /// No description provided for @rescueCode_stepStuck.
  ///
  /// In zh, this message translates to:
  /// **'同一步停太久'**
  String get rescueCode_stepStuck;

  /// No description provided for @rescueCode_uploadNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已連上，但資料還沒送到後台'**
  String get rescueCode_uploadNotStarted;

  /// No description provided for @rescueCode_uploadTarget.
  ///
  /// In zh, this message translates to:
  /// **'閘道器資料送錯地方（跟手機連的後台不同）'**
  String get rescueCode_uploadTarget;

  /// No description provided for @rescueCode_verifyIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'有 PTU 資料沒進來'**
  String get rescueCode_verifyIncomplete;

  /// No description provided for @rescueCode_wifiNotFound.
  ///
  /// In zh, this message translates to:
  /// **'閘道器找不到這個 Wi-Fi'**
  String get rescueCode_wifiNotFound;

  /// No description provided for @rescueCode_wifiPassword.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 密碼可能錯'**
  String get rescueCode_wifiPassword;

  /// No description provided for @rescueCode_wifiUnknown.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 沒連上（原因不明）'**
  String get rescueCode_wifiUnknown;

  /// No description provided for @rescueCode_wifiWeak.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 訊號弱或基地台拒絕'**
  String get rescueCode_wifiWeak;

  /// More menu item and dialog title for the theme.
  ///
  /// In zh, this message translates to:
  /// **'外觀'**
  String get settings_appearance;

  /// More menu item and dialog title for choosing the APP language.
  ///
  /// In zh, this message translates to:
  /// **'語言'**
  String get settings_language;

  /// AppBar overflow menu tooltip.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get settings_more;

  /// No description provided for @settings_themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settings_themeDark;

  /// No description provided for @settings_themeLight.
  ///
  /// In zh, this message translates to:
  /// **'淺色'**
  String get settings_themeLight;

  /// No description provided for @settings_themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟隨系統'**
  String get settings_themeSystem;

  /// No description provided for @starAllowList_beforeFailed.
  ///
  /// In zh, this message translates to:
  /// **'PTU 綁定名單未寫入，繼續配置。若附近有編號相同的其他 PTU 佔住連線，部分 PTU 可能指派失敗；資料驗證完成後會再寫一次。'**
  String get starAllowList_beforeFailed;

  /// Completion page: the star allow list (PTU binding list) could not be written.
  ///
  /// In zh, this message translates to:
  /// **'PTU 綁定名單未寫入，請重試。未寫入前閘道器只看編號，附近帶相同編號的其他 PTU 仍可能被連走。'**
  String get starAllowList_failed;

  /// No description provided for @starAllowList_foreignIgnored.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{附近有 {count} 台編號相同的其他 PTU，已被閘道器忽略（不會連線）。}}'**
  String starAllowList_foreignIgnored(int count);

  /// No description provided for @starAllowList_reselectHint.
  ///
  /// In zh, this message translates to:
  /// **'若其中有這台閘道器要接的 PTU，請勾選它後重新配置。'**
  String get starAllowList_reselectHint;

  /// No description provided for @starAllowList_retryButton.
  ///
  /// In zh, this message translates to:
  /// **'重試寫入綁定名單'**
  String get starAllowList_retryButton;

  /// Joins the sentences of the foreign-PTU note: empty in Chinese, a space in English.
  ///
  /// In zh, this message translates to:
  /// **''**
  String get starAllowList_sentenceSeparator;

  /// No description provided for @starAllowList_switchFailed.
  ///
  /// In zh, this message translates to:
  /// **'切回星狀後 PTU 綁定名單未寫入，資料驗證完成後會再寫一次。'**
  String get starAllowList_switchFailed;

  /// No description provided for @starAllowList_unlistedDropped.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{有 {count} 台已連線的 PTU 不在這台閘道器的綁定名單，閘道器會自動斷開。}}'**
  String starAllowList_unlistedDropped(int count);

  /// No description provided for @starAllowList_writing.
  ///
  /// In zh, this message translates to:
  /// **'正在寫入 PTU 綁定名單'**
  String get starAllowList_writing;

  /// No description provided for @starAllowList_written.
  ///
  /// In zh, this message translates to:
  /// **'PTU 綁定名單已寫入：{ids}（閘道器只連這幾台，附近編號相同的其他 PTU 不會被連走）'**
  String starAllowList_written(String ids);

  /// No description provided for @stationChangeProgress_applying.
  ///
  /// In zh, this message translates to:
  /// **'套用站號後，閘道器會重新啟動。請保持靠近，APP 會自動重新連線。'**
  String get stationChangeProgress_applying;

  /// No description provided for @stationChangeProgress_confirming.
  ///
  /// In zh, this message translates to:
  /// **'已重新連線，正在確認新站號與 Wi-Fi。確認完成後會自動繼續。'**
  String get stationChangeProgress_confirming;

  /// No description provided for @stationChangeProgress_restarting.
  ///
  /// In zh, this message translates to:
  /// **'這是套用站號時的正常重啟，藍牙會短暫中斷。請保持靠近，APP 會自動重新連線。'**
  String get stationChangeProgress_restarting;

  /// No description provided for @stationChangeProgress_target.
  ///
  /// In zh, this message translates to:
  /// **'站點 {site} · 閘道器 {gateway}'**
  String stationChangeProgress_target(int site, int gateway);

  /// No description provided for @stationChange_itemApply.
  ///
  /// In zh, this message translates to:
  /// **'套用站點設定'**
  String get stationChange_itemApply;

  /// No description provided for @stationChange_itemConfirm.
  ///
  /// In zh, this message translates to:
  /// **'確認站號與 Wi-Fi'**
  String get stationChange_itemConfirm;

  /// No description provided for @stationChange_itemRestart.
  ///
  /// In zh, this message translates to:
  /// **'重新啟動並連線'**
  String get stationChange_itemRestart;

  /// No description provided for @stationChange_noteReconnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在自動重新連線'**
  String get stationChange_noteReconnecting;

  /// No description provided for @stationChange_noteWaitBoot.
  ///
  /// In zh, this message translates to:
  /// **'等待閘道器啟動'**
  String get stationChange_noteWaitBoot;

  /// No description provided for @stationChange_titleApplying.
  ///
  /// In zh, this message translates to:
  /// **'正在套用站號，請稍候'**
  String get stationChange_titleApplying;

  /// No description provided for @stationChange_titleConfirming.
  ///
  /// In zh, this message translates to:
  /// **'正在確認站號與 Wi-Fi'**
  String get stationChange_titleConfirming;

  /// No description provided for @stationChange_titleReconnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在重新連線閘道器'**
  String get stationChange_titleReconnecting;

  /// No description provided for @stationChange_titleRestarting.
  ///
  /// In zh, this message translates to:
  /// **'閘道器重新啟動中，請稍候'**
  String get stationChange_titleRestarting;

  /// No description provided for @uiProgressChecklist_doneAt.
  ///
  /// In zh, this message translates to:
  /// **'{time} 完成'**
  String uiProgressChecklist_doneAt(String time);

  /// No description provided for @uiProgressChecklist_running.
  ///
  /// In zh, this message translates to:
  /// **'進行中…'**
  String get uiProgressChecklist_running;

  /// No description provided for @uiProgressChecklist_runningNote.
  ///
  /// In zh, this message translates to:
  /// **'進行中… {note}'**
  String uiProgressChecklist_runningNote(String note);

  /// No description provided for @verifyDiagnosis_causeOtherBackend.
  ///
  /// In zh, this message translates to:
  /// **'閘道器可能上傳到其他後端環境（例如正式站）。'**
  String get verifyDiagnosis_causeOtherBackend;

  /// No description provided for @verifyDiagnosis_causeProductionUnknown.
  ///
  /// In zh, this message translates to:
  /// **'閘道器可能尚未連上正式站的 MQTT，或上傳到其他後端環境（例如本地測試站）。'**
  String get verifyDiagnosis_causeProductionUnknown;

  /// No description provided for @verifyDiagnosis_consecutive.
  ///
  /// In zh, this message translates to:
  /// **'連續通過 {count} / 3 次。'**
  String verifyDiagnosis_consecutive(int count);

  /// No description provided for @verifyDiagnosis_installNoDetail.
  ///
  /// In zh, this message translates to:
  /// **'後端安裝驗證未通過（未回傳此 PTU 明細）'**
  String get verifyDiagnosis_installNoDetail;

  /// No description provided for @verifyDiagnosis_localHint.
  ///
  /// In zh, this message translates to:
  /// **'請確認：閘道器的 MQTT 已連線（按「重新讀取」查看）、電腦防火牆已開放 TCP {port}、本地 MQTT broker 已啟動，且 broker 憑證包含電腦目前的 IP {host}（電腦 IP 若因 DHCP 變更，需重新產生憑證並把閘道器切到新 IP）。'**
  String verifyDiagnosis_localHint(String port, String host);

  /// Sentence appended right after verifyDiagnosis_sameTarget's first sentence; the en value starts with a space.
  ///
  /// In zh, this message translates to:
  /// **'閘道器最近回報 MQTT 已連線，可能剛連上、心跳尚未送達，可稍候再驗證。'**
  String get verifyDiagnosis_mqttConnected;

  /// Sentence appended right after verifyDiagnosis_sameTarget's first sentence; the en value starts with a space.
  ///
  /// In zh, this message translates to:
  /// **'閘道器最近回報 MQTT 未連線。'**
  String get verifyDiagnosis_mqttDisconnected;

  /// No description provided for @verifyDiagnosis_noData.
  ///
  /// In zh, this message translates to:
  /// **'閘道器的資料沒有進入目前連線的{backend}：fleet-status 沒有站 {site} / 閘道器 {gateway} 的心跳，/api/latest 也沒有任何資料。{cause}'**
  String verifyDiagnosis_noData(
    String backend,
    int site,
    int gateway,
    String cause,
  );

  /// No description provided for @verifyDiagnosis_noFleet.
  ///
  /// In zh, this message translates to:
  /// **'fleet-status 沒有站 {site} / 閘道器 {gateway} 的心跳紀錄。'**
  String verifyDiagnosis_noFleet(int site, int gateway);

  /// No last heartbeat known.
  ///
  /// In zh, this message translates to:
  /// **'無'**
  String get verifyDiagnosis_none;

  /// No description provided for @verifyDiagnosis_offline.
  ///
  /// In zh, this message translates to:
  /// **'閘道器在後端顯示離線（最後心跳 {last}）。'**
  String verifyDiagnosis_offline(String last);

  /// No description provided for @verifyDiagnosis_productionHint.
  ///
  /// In zh, this message translates to:
  /// **'請確認現場網路可連到正式站（TCP {port}），並按「重新讀取」查看 MQTT 是否已連線。'**
  String verifyDiagnosis_productionHint(String port);

  /// No description provided for @verifyDiagnosis_ptuLine.
  ///
  /// In zh, this message translates to:
  /// **'PTU #{id}：{reasons}'**
  String verifyDiagnosis_ptuLine(int id, String reasons);

  /// No description provided for @verifyDiagnosis_reasonBackendLate.
  ///
  /// In zh, this message translates to:
  /// **'後端資料延遲 {seconds} 秒'**
  String verifyDiagnosis_reasonBackendLate(String seconds);

  /// No description provided for @verifyDiagnosis_reasonBadTime.
  ///
  /// In zh, this message translates to:
  /// **'資料時間無法解析'**
  String get verifyDiagnosis_reasonBadTime;

  /// No description provided for @verifyDiagnosis_reasonLag.
  ///
  /// In zh, this message translates to:
  /// **'延遲 {seconds} 秒'**
  String verifyDiagnosis_reasonLag(int seconds);

  /// No description provided for @verifyDiagnosis_reasonLagUnknown.
  ///
  /// In zh, this message translates to:
  /// **'延遲未知'**
  String get verifyDiagnosis_reasonLagUnknown;

  /// No description provided for @verifyDiagnosis_reasonNoBackendData.
  ///
  /// In zh, this message translates to:
  /// **'後端無資料'**
  String get verifyDiagnosis_reasonNoBackendData;

  /// No description provided for @verifyDiagnosis_reasonNotInLatest.
  ///
  /// In zh, this message translates to:
  /// **'最新資料（/api/latest）無此 PTU'**
  String get verifyDiagnosis_reasonNotInLatest;

  /// No description provided for @verifyDiagnosis_reasonNotUpdated.
  ///
  /// In zh, this message translates to:
  /// **'資料未更新（最後 {ts}）'**
  String verifyDiagnosis_reasonNotUpdated(String ts);

  /// No description provided for @verifyDiagnosis_reasonOffline.
  ///
  /// In zh, this message translates to:
  /// **'離線'**
  String get verifyDiagnosis_reasonOffline;

  /// No description provided for @verifyDiagnosis_roundOk.
  ///
  /// In zh, this message translates to:
  /// **'本輪正常'**
  String get verifyDiagnosis_roundOk;

  /// state: verifyDiagnosis_mqttConnected / _mqttDisconnected or empty; hint: what to check.
  ///
  /// In zh, this message translates to:
  /// **'閘道器已確認上傳到{target}（與 APP 所連後端一致），但後端尚未收到它的心跳，表示閘道器還沒連上該 MQTT broker。{state}\n{hint}'**
  String verifyDiagnosis_sameTarget(String target, String state, String hint);

  /// No description provided for @verifyDiagnosis_uploadPaused.
  ///
  /// In zh, this message translates to:
  /// **'閘道器資料上傳為暫停狀態（已嘗試恢復）。'**
  String get verifyDiagnosis_uploadPaused;

  /// Every PTU said the same announcement text.
  ///
  /// In zh, this message translates to:
  /// **'每台{text}'**
  String verifyLivePanel_announceEvery(String text);

  /// No description provided for @verifyLivePanel_announceNew.
  ///
  /// In zh, this message translates to:
  /// **'收到新資料'**
  String get verifyLivePanel_announceNew;

  /// No description provided for @verifyLivePanel_announceNotCounted.
  ///
  /// In zh, this message translates to:
  /// **'資料未計入：{reasons}'**
  String verifyLivePanel_announceNotCounted(String reasons);

  /// No description provided for @verifyLivePanel_announceNth.
  ///
  /// In zh, this message translates to:
  /// **'收到第 {count} 筆'**
  String verifyLivePanel_announceNth(int count);

  /// who is one or more PTU names (PTU #1, PTU #2); text is an announcement.
  ///
  /// In zh, this message translates to:
  /// **'{who} {text}'**
  String verifyLivePanel_announcePtu(String who, String text);

  /// Joins announcements of several PTUs (en: semicolon and space).
  ///
  /// In zh, this message translates to:
  /// **'；'**
  String get verifyLivePanel_announceSeparator;

  /// No description provided for @verifyLivePanel_countFull.
  ///
  /// In zh, this message translates to:
  /// **'正常（已滿 3 筆）'**
  String get verifyLivePanel_countFull;

  /// No description provided for @verifyLivePanel_countNotCounted.
  ///
  /// In zh, this message translates to:
  /// **'未計入（維持 {count}/3）'**
  String verifyLivePanel_countNotCounted(int count);

  /// No description provided for @verifyLivePanel_countNth.
  ///
  /// In zh, this message translates to:
  /// **'第 {count} 筆'**
  String verifyLivePanel_countNth(int count);

  /// No description provided for @verifyLivePanel_countRestart.
  ///
  /// In zh, this message translates to:
  /// **'重新計數：第 {count}/3 筆'**
  String verifyLivePanel_countRestart(int count);

  /// Last stop of the flow PTU → gateway → back office (short).
  ///
  /// In zh, this message translates to:
  /// **'後台'**
  String get verifyLivePanel_flowBackOffice;

  /// Middle stop of the flow PTU → gateway → back office (short).
  ///
  /// In zh, this message translates to:
  /// **'閘道器'**
  String get verifyLivePanel_flowGateway;

  /// No description provided for @verifyLivePanel_footer.
  ///
  /// In zh, this message translates to:
  /// **'{pace}・剩餘 {seconds} 秒'**
  String verifyLivePanel_footer(String pace, int seconds);

  /// Step 9 (data check) sentence; a row is one data sample uploaded by a PTU.
  ///
  /// In zh, this message translates to:
  /// **'收到 3 筆正常資料就算完成'**
  String get verifyLivePanel_goal;

  /// No description provided for @verifyLivePanel_pace.
  ///
  /// In zh, this message translates to:
  /// **'每 {seconds} 秒確認新資料，收到 3 筆正常資料即完成'**
  String verifyLivePanel_pace(int seconds);

  /// interval and total are already formatted durations (e.g. 30 秒 / 30 s).
  ///
  /// In zh, this message translates to:
  /// **'約每 {interval}收一筆，通常 {total}內完成'**
  String verifyLivePanel_paceInterval(String interval, String total);

  /// No description provided for @verifyLivePanel_passed.
  ///
  /// In zh, this message translates to:
  /// **'資料正常上傳'**
  String get verifyLivePanel_passed;

  /// No description provided for @verifyLivePanel_reason.
  ///
  /// In zh, this message translates to:
  /// **'原因：{reasons}'**
  String verifyLivePanel_reason(String reasons);

  /// No description provided for @verifyLivePanel_reasonDefault.
  ///
  /// In zh, this message translates to:
  /// **'未通過檢查'**
  String get verifyLivePanel_reasonDefault;

  /// No description provided for @verifyLivePanel_rowBad.
  ///
  /// In zh, this message translates to:
  /// **'異常'**
  String get verifyLivePanel_rowBad;

  /// No description provided for @verifyLivePanel_rowOk.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get verifyLivePanel_rowOk;

  /// No description provided for @verifyLivePanel_uncountedDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看未計入資料（{count} 筆）'**
  String verifyLivePanel_uncountedDetails(int count);

  /// No description provided for @verifyLivePanel_waitingFirst.
  ///
  /// In zh, this message translates to:
  /// **'等待第一筆資料…'**
  String get verifyLivePanel_waitingFirst;

  /// No description provided for @verifyLivePanel_waitingNormal.
  ///
  /// In zh, this message translates to:
  /// **'等待下一筆正常資料…'**
  String get verifyLivePanel_waitingNormal;

  /// No description provided for @wifiCredentialsForm_forgetButton.
  ///
  /// In zh, this message translates to:
  /// **'忘記已存密碼'**
  String get wifiCredentialsForm_forgetButton;

  /// No description provided for @wifiCredentialsForm_forgetFailed.
  ///
  /// In zh, this message translates to:
  /// **'舊密碼尚未刪除，請重試；本次不會記住新密碼。'**
  String get wifiCredentialsForm_forgetFailed;

  /// No description provided for @wifiCredentialsForm_forgotten.
  ///
  /// In zh, this message translates to:
  /// **'已忘記這個 Wi-Fi 的已存密碼。'**
  String get wifiCredentialsForm_forgotten;

  /// No description provided for @wifiCredentialsForm_gatewayWifiLabel.
  ///
  /// In zh, this message translates to:
  /// **'閘道器要使用的 Wi-Fi'**
  String get wifiCredentialsForm_gatewayWifiLabel;

  /// No description provided for @wifiCredentialsForm_hidePassword.
  ///
  /// In zh, this message translates to:
  /// **'隱藏密碼'**
  String get wifiCredentialsForm_hidePassword;

  /// No description provided for @wifiCredentialsForm_intro.
  ///
  /// In zh, this message translates to:
  /// **'帶入手機目前的 Wi-Fi 名稱後，輸入密碼或使用已記住的密碼。'**
  String get wifiCredentialsForm_intro;

  /// No description provided for @wifiCredentialsForm_locationOff.
  ///
  /// In zh, this message translates to:
  /// **'請開啟手機定位服務後重試，或手動輸入 Wi-Fi 名稱。'**
  String get wifiCredentialsForm_locationOff;

  /// No description provided for @wifiCredentialsForm_manualButton.
  ///
  /// In zh, this message translates to:
  /// **'手動輸入其他網路'**
  String get wifiCredentialsForm_manualButton;

  /// No description provided for @wifiCredentialsForm_noneSelected.
  ///
  /// In zh, this message translates to:
  /// **'尚未選擇 Wi-Fi'**
  String get wifiCredentialsForm_noneSelected;

  /// No description provided for @wifiCredentialsForm_notRemembered.
  ///
  /// In zh, this message translates to:
  /// **'連線尚未完成，未記住本次密碼。'**
  String get wifiCredentialsForm_notRemembered;

  /// No description provided for @wifiCredentialsForm_openAppSettings.
  ///
  /// In zh, this message translates to:
  /// **'開啟 App 權限設定'**
  String get wifiCredentialsForm_openAppSettings;

  /// No description provided for @wifiCredentialsForm_passwordHint.
  ///
  /// In zh, this message translates to:
  /// **'輸入 Wi-Fi 密碼；無密碼的網路可直接儲存'**
  String get wifiCredentialsForm_passwordHint;

  /// No description provided for @wifiCredentialsForm_passwordLabel.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 密碼'**
  String get wifiCredentialsForm_passwordLabel;

  /// No description provided for @wifiCredentialsForm_permissionNeeded.
  ///
  /// In zh, this message translates to:
  /// **'讀取 Wi-Fi 名稱需要定位權限及精確位置。請在 App 設定允許後重試，也可手動輸入名稱。'**
  String get wifiCredentialsForm_permissionNeeded;

  /// No description provided for @wifiCredentialsForm_phoneWifiFilled.
  ///
  /// In zh, this message translates to:
  /// **'已帶入手機的 Wi-Fi 名稱，請確認此網路支援 2.4 GHz，並確認下方密碼。'**
  String get wifiCredentialsForm_phoneWifiFilled;

  /// No description provided for @wifiCredentialsForm_phoneWifiUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'讀不到手機目前的 Wi-Fi。請先在手機的 Wi-Fi 設定連上現場網路，再回來重試，或手動輸入名稱。'**
  String get wifiCredentialsForm_phoneWifiUnreadable;

  /// No description provided for @wifiCredentialsForm_readSavedFailed.
  ///
  /// In zh, this message translates to:
  /// **'暫時無法讀取已存密碼，請手動輸入。'**
  String get wifiCredentialsForm_readSavedFailed;

  /// No description provided for @wifiCredentialsForm_readSavedTimeout.
  ///
  /// In zh, this message translates to:
  /// **'讀取已存密碼逾時，請手動輸入。'**
  String get wifiCredentialsForm_readSavedTimeout;

  /// No description provided for @wifiCredentialsForm_readWifiFailed.
  ///
  /// In zh, this message translates to:
  /// **'暫時無法讀取 Wi-Fi 名稱，請重試或手動輸入。'**
  String get wifiCredentialsForm_readWifiFailed;

  /// No description provided for @wifiCredentialsForm_readWifiTimeout.
  ///
  /// In zh, this message translates to:
  /// **'讀取 Wi-Fi 逾時，請重試或手動輸入名稱。'**
  String get wifiCredentialsForm_readWifiTimeout;

  /// No description provided for @wifiCredentialsForm_rememberFailed.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 已連線，但無法記住密碼；下次請重新輸入。'**
  String get wifiCredentialsForm_rememberFailed;

  /// No description provided for @wifiCredentialsForm_rememberPassword.
  ///
  /// In zh, this message translates to:
  /// **'記住密碼（僅限這支手機）'**
  String get wifiCredentialsForm_rememberPassword;

  /// label is the save button's text (already localized).
  ///
  /// In zh, this message translates to:
  /// **'確認 Wi-Fi 名稱與密碼後，點「{label}」'**
  String wifiCredentialsForm_saveHint(String label);

  /// The eye is the show/hide password icon button.
  ///
  /// In zh, this message translates to:
  /// **'已帶入這支手機記住的密碼，可按眼睛查看或手動修改。'**
  String get wifiCredentialsForm_savedFilled;

  /// No description provided for @wifiCredentialsForm_showPassword.
  ///
  /// In zh, this message translates to:
  /// **'顯示密碼'**
  String get wifiCredentialsForm_showPassword;

  /// No description provided for @wifiCredentialsForm_ssidHint.
  ///
  /// In zh, this message translates to:
  /// **'輸入 Wi-Fi 名稱'**
  String get wifiCredentialsForm_ssidHint;

  /// No description provided for @wifiCredentialsForm_ssidLabel.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 名稱（SSID）'**
  String get wifiCredentialsForm_ssidLabel;

  /// No description provided for @wifiCredentialsForm_unsupported.
  ///
  /// In zh, this message translates to:
  /// **'此平台無法讀取手機 Wi-Fi，請手動輸入名稱。'**
  String get wifiCredentialsForm_unsupported;

  /// No description provided for @wifiCredentialsForm_usePhoneButton.
  ///
  /// In zh, this message translates to:
  /// **'使用手機目前的 Wi-Fi'**
  String get wifiCredentialsForm_usePhoneButton;

  /// No description provided for @wifiCredentialsForm_usePhoneHint.
  ///
  /// In zh, this message translates to:
  /// **'帶入手機目前的 Wi-Fi'**
  String get wifiCredentialsForm_usePhoneHint;

  /// No description provided for @wifiCredentialsForm_wifiOff.
  ///
  /// In zh, this message translates to:
  /// **'請先在手機的 Wi-Fi 設定連上現場網路，再回來重試，或手動輸入名稱。'**
  String get wifiCredentialsForm_wifiOff;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
