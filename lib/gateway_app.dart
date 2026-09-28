import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_theme.dart';
import 'presentation/commissioning_page.dart';

/// 1.0.0+9: the theme when `theme_mode` was never stored.
const defaultThemeMode = ThemeMode.light;

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
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => _mode =
            ThemeMode.values[(p.getInt('theme_mode') ?? defaultThemeMode.index)
                .clamp(0, 2)],
      );
    }
  }

  Future<void> _change(ThemeMode mode) async {
    setState(() => _mode = mode);
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme_mode', mode.index);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GIOS 現場開通',
    debugShowCheckedModeBanner: false,
    theme: widget.theme(Brightness.light),
    darkTheme: widget.theme(Brightness.dark),
    themeMode: _mode,
    home: CommissioningPage(themeMode: _mode, onThemeChanged: _change),
  );
}
