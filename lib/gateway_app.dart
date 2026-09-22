import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_theme.dart';
import 'presentation/commissioning_page.dart';

class GatewayApp extends StatefulWidget {
  const GatewayApp({super.key});
  @override
  State<GatewayApp> createState() => _GatewayAppState();
}

class _GatewayAppState extends State<GatewayApp> {
  ThemeMode _mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () =>
            _mode = ThemeMode.values[(p.getInt('theme_mode') ?? 0).clamp(0, 2)],
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
    theme: gatewayTheme(Brightness.light),
    darkTheme: gatewayTheme(Brightness.dark),
    themeMode: _mode,
    home: CommissioningPage(themeMode: _mode, onThemeChanged: _change),
  );
}
