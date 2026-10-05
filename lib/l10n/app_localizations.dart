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

  /// APP name; keep equal to android res/values*/strings.xml app_name and iOS InfoPlist.strings CFBundleDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'GIOS 設備助手'**
  String get appInfo_title;

  /// Step 8 PTU row result while its number is being written; recognised by assignResultKindOf in every locale.
  ///
  /// In zh, this message translates to:
  /// **'正在指派 #{id}'**
  String assign_assigningResult(int id);

  /// Step 8 PTU row result after the phone lost the gateway; recognised by assignResultKindOf in every locale.
  ///
  /// In zh, this message translates to:
  /// **'尚未指派（手機與閘道器斷線）'**
  String get assign_notAssignedLink;

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

  /// No description provided for @gatewayStatus_heartbeatAgo.
  ///
  /// In zh, this message translates to:
  /// **'心跳 {age}前'**
  String gatewayStatus_heartbeatAgo(String age);

  /// No description provided for @gatewayStatus_hint.
  ///
  /// In zh, this message translates to:
  /// **'點一列即可查看該閘道器的最近資料。'**
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

  /// More menu item and dialog title for choosing the APP language.
  ///
  /// In zh, this message translates to:
  /// **'語言'**
  String get settings_language;
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
