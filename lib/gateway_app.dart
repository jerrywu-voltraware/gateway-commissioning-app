import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_theme.dart';
import 'l10n/l10n.dart';
import 'presentation/commissioning_page.dart';

/// 1.0.0+9: the theme when `theme_mode` was never stored.
const defaultThemeMode = ThemeMode.light;

/// shared_preferences key of the chosen APP language (`zh` / `en`).
const appLocalePrefKey = 'app_locale';

/// 2026-10-05: the language when `app_locale` was never stored — 繁體中文,
/// never the phone's system language.
const defaultAppLanguage = AppLanguage.zh;

class GatewayApp extends StatefulWidget {
  const GatewayApp({super.key, this.theme = gatewayTheme});

  /// The theme for a brightness ([gatewayTheme]; layout tests add fonts).
  final ThemeData Function(Brightness brightness) theme;
  @override
  State<GatewayApp> createState() => _GatewayAppState();
}

class _GatewayAppState extends State<GatewayApp> {
  /// 1.0.0+9: light unless the phone chose otherwise (was 跟隨系統).
  ThemeMode _mode = defaultThemeMode;

  /// 畫面語言；預設繁中，不跟隨系統。
  AppLanguage _language = defaultAppLanguage;

  @override
  void initState() {
    super.initState();
    // 無 context 層（L10n.current）先回到預設，prefs 讀到後再換。
    L10n.load(_language);
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final language = AppLanguage.fromCode(p.getString(appLocalePrefKey));
    if (language != _language) _applyLanguage(language);
    setState(
      () => _mode =
          ThemeMode.values[(p.getInt('theme_mode') ?? defaultThemeMode.index)
              .clamp(0, 2)],
    );
  }

  Future<void> _change(ThemeMode mode) async {
    setState(() => _mode = mode);
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme_mode', mode.index);
  }

  Future<void> _changeLanguage(AppLanguage language) async {
    if (language != _language) _applyLanguage(language);
    final p = await SharedPreferences.getInstance();
    await p.setString(appLocalePrefKey, language.name);
  }

  /// 立即生效、不必重開：先換 [L10n.current]，再讓整棵樹重建一次——
  /// 用 `context.l10n` 的 widget 會因 Localizations 變更自動重建，但讀
  /// [L10n.current]（top-level getter、controller 產生的文字）的 widget
  /// 不會，所以全部標記 dirty（State 不會重建，畫面進度不受影響）。
  void _applyLanguage(AppLanguage language) {
    L10n.load(language);
    setState(() => _language = language);
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => context.l10n.appInfo_title,
    debugShowCheckedModeBanner: false,
    theme: widget.theme(Brightness.light),
    darkTheme: widget.theme(Brightness.dark),
    themeMode: _mode,
    locale: _language.locale,
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    home: CommissioningPage(
      themeMode: _mode,
      onThemeChanged: _change,
      language: _language,
      onLanguageChanged: _changeLanguage,
    ),
  );
}
