/// 中英語系的入口（規範見 docs/i18n.md）。
///
/// - widget 層：`context.l10n.xxx`（等同 `AppLocalizations.of(context)`，
///   會訂閱語言變更）。
/// - 沒有 context 的層（application／core／data）：`L10n.current.xxx`，
///   由 [GatewayApp] 在啟動與切換語言時以 [L10n.load] 更新。
/// - 上傳後台、匯出的報告一律維持中文：用 [L10n.zh]，不要用 current。
library;

import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// APP 支援的語言代碼（存在 shared_preferences `app_locale` 的值）。
enum AppLanguage {
  /// 繁體中文（預設）。
  zh,

  /// English.
  en;

  /// 這個語言的 [Locale]。zh 用 zh_Hant_TW，讓 Material 內建字串（返回、
  /// 複製、日期選擇器…）也是繁體；APP 自己的字串只看 languageCode。
  Locale get locale => switch (this) {
    AppLanguage.zh => appZhLocale,
    AppLanguage.en => appEnLocale,
  };

  /// prefs 存的值（`zh`／`en`）轉回列舉；不認得的值（含 null）一律繁中。
  static AppLanguage fromCode(String? code) => switch (code) {
    'en' => AppLanguage.en,
    _ => AppLanguage.zh,
  };

  /// [locale] 對應的語言；非英文一律視為繁中。
  static AppLanguage of(Locale locale) =>
      locale.languageCode == 'en' ? AppLanguage.en : AppLanguage.zh;
}

/// 繁體中文（台灣）。
const appZhLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
  countryCode: 'TW',
);

/// English.
const appEnLocale = Locale('en');

/// [MaterialApp.supportedLocales]；第一個是預設語言。
const appSupportedLocales = [appZhLocale, appEnLocale];

/// [MaterialApp.localizationsDelegates]（APP 字串＋Material／Cupertino／
/// Widgets 內建字串）。測試自建 MaterialApp 時也用這組。
const appLocalizationsDelegates = AppLocalizations.localizationsDelegates;

/// 無 context 的存取器。
abstract final class L10n {
  static AppLanguage _language = AppLanguage.zh;
  static AppLocalizations _current = lookupAppLocalizations(appZhLocale);

  /// 固定的繁中字串：上傳後台、匯出（分享、複製）的報告用這個。
  static final AppLocalizations zh = lookupAppLocalizations(appZhLocale);

  /// 目前畫面語言的字串；尚未 [load] 時是繁中（測試不必先初始化）。
  static AppLocalizations get current => _current;

  /// 目前畫面語言。
  static AppLanguage get language => _language;

  /// 切換無 context 層使用的語言（[GatewayApp] 呼叫；測試可直接呼叫）。
  static void load(AppLanguage language) {
    _language = language;
    _current = lookupAppLocalizations(language.locale);
  }

  /// 測試用：回到預設繁中（在 tearDown 呼叫，避免影響同檔後面的測試）。
  @visibleForTesting
  static void reset() => load(AppLanguage.zh);
}

/// [text] 是否等於 [pick] 在任一 APP 語言產生的文字（docs/i18n.md §8.3）。
///
/// 給「同源比對」用：state 裡存的文字是產生當下的語言，語言切換後
/// `L10n.current` 算出的會是另一種語言；比對所有語言就不會因切換而失準。
/// 能用旗標或列舉時優先用旗標，這只是沒有結構化資料時的退路。
bool matchesAnyLanguage(
  String? text,
  String Function(AppLocalizations l10n) pick,
) {
  if (text == null) return false;
  for (final language in AppLanguage.values) {
    if (pick(lookupAppLocalizations(language.locale)) == text) return true;
  }
  return false;
}

/// widget 層的簡寫：`context.l10n.common_close`。
///
/// 樹上有 [AppLocalizations]（[GatewayApp]、`test/support/l10n.dart`）就用
/// 它並訂閱語言變更；沒有（既有測試自建的 MaterialApp）就退回
/// [L10n.current]，不丟例外。
extension L10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      L10n.current;
}
