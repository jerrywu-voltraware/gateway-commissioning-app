import 'package:flutter/material.dart';

ThemeData gatewayTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: dark ? const Color(0xFF00BFA5) : const Color(0xFF365D79),
    brightness: brightness,
  );
  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0D1117)
        : const Color(0xFFF4F5F6),
    appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
  );
  // 1.0.0+10 (phone, 360 dp at text scale 1.1: 「GIOS 現場…」): every
  // page's AppBar title is titleMedium w600 — one size on all pages, and
  // 「GIOS 現場開通」 whole beside the help icon and the environment chip.
  // (ThemeData.textTheme has no sizes until Theme.of localizes it: the
  // style is taken from the localized theme.)
  final sized = ThemeData.localize(theme, theme.typography.englishLike);
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: sized.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
    ),
  );
}
