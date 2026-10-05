// 測試用的語系輔助（docs/i18n.md「測試」）。
//
// - [wrapWithL10n]：自建 MaterialApp 的測試改用它，就有 APP 與 Material
//   的 delegates（`context.l10n`、`AppLocalizations.of` 都拿得到）。
// - [useLanguage]：切換無 context 層（L10n.current）的語言，測試結束自動
//   回到繁中，不影響同檔後面的測試。
// - [pumpApp]：以指定的 prefs（含 `app_locale`）啟動整個 GatewayApp。
//
// 注意：首頁的 NextActionGuide 呼吸動畫會一直排 frame，整個 APP 的測試
// 不要用 pumpAndSettle，改用 [pumpFrames]。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [home] 包在帶 APP 語系設定的 MaterialApp 裡（預設繁中）。
Widget wrapWithL10n(
  Widget home, {
  AppLanguage language = AppLanguage.zh,
  ThemeData? theme,
}) => MaterialApp(
  locale: language.locale,
  supportedLocales: appSupportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  theme: theme,
  home: home,
);

/// 無 context 層改用 [language]；tearDown 時回到繁中。
void useLanguage(AppLanguage language) {
  L10n.load(language);
  addTearDown(L10n.reset);
}

/// 以 [prefs] 啟動 GatewayApp（[overrides] 給 ProviderScope）並跑幾個 frame。
Future<void> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  addTearDown(L10n.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const GatewayApp()),
  );
  await pumpFrames(tester);
}

/// 不等動畫全停（pumpAndSettle 會被呼吸動畫卡住），只往前推 [total]。
Future<void> pumpFrames(
  WidgetTester tester, [
  Duration total = const Duration(seconds: 1),
]) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}
