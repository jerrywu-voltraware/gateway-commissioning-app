// Real fonts for layout tests (1.0.0+10).
//
// The test font gives every glyph 1 em — Latin about twice as wide as on
// the phone. The SDK's Roboto alone is no better for this APP: Roboto has
// no Chinese glyphs and the test engine has no system fallback, so every
// Chinese character is drawn as Roboto's narrow missing-glyph box (about
// 0.44 em instead of 1 em) and a line that is cut on the phone "fits".
//
// [loadRealFonts] loads Roboto (regular / medium / bold, from the Flutter
// SDK's material_fonts cache) under the family `Roboto` the Material text
// theme names, and a Chinese font as [realFontFallback]; [withRealFonts]
// adds that fallback to a theme's text styles. Together they measure text
// about as the phone does (Android: Roboto + Noto Sans CJK).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The family name the Chinese font is loaded under.
const realFontFallback = ['GiosTestCjk'];

/// Chinese fonts tried in order (the first one found is used).
/// `GIOS_TEST_CJK_FONT` may name another file.
List<String> _cjkCandidates() => [
  ?Platform.environment['GIOS_TEST_CJK_FONT'],
  'C:/Windows/Fonts/NotoSansTC-VF.ttf',
  'C:/Windows/Fonts/msjh.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
  '/System/Library/Fonts/PingFang.ttc',
];

Directory? _flutterRoot() {
  const fonts = 'bin/cache/artifacts/material_fonts';
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && Directory('$env/$fonts').existsSync()) {
    return Directory(env);
  }
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    if (Directory('${dir.path}/$fonts').existsSync()) return dir;
    dir = dir.parent;
  }
  return null;
}

Future<ByteData> _bytes(File file) async =>
    ByteData.sublistView(await file.readAsBytes());

bool? _loaded;

/// Loads Roboto and a Chinese font once per test file; whether both were
/// found (widths are only meaningful then).
Future<bool> loadRealFonts() async {
  if (_loaded != null) return _loaded!;
  final root = _flutterRoot();
  var roboto = false;
  if (root != null) {
    final loader = FontLoader('Roboto');
    for (final name in const [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]) {
      final file = File(
        '${root.path}/bin/cache/artifacts/material_fonts/$name',
      );
      if (!file.existsSync()) continue;
      loader.addFont(_bytes(file));
      roboto = true;
    }
    if (roboto) await loader.load();
  }
  var cjk = false;
  for (final path in _cjkCandidates()) {
    final file = File(path);
    if (!file.existsSync()) continue;
    await (FontLoader(realFontFallback.single)..addFont(_bytes(file))).load();
    cjk = true;
    break;
  }
  return _loaded = roboto && cjk;
}

/// [theme] with [realFontFallback] behind every text style (the AppBar's
/// title style included).
ThemeData withRealFonts(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamilyFallback: realFontFallback),
  primaryTextTheme: theme.primaryTextTheme.apply(
    fontFamilyFallback: realFontFallback,
  ),
  appBarTheme: theme.appBarTheme.copyWith(
    titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
      fontFamilyFallback: realFontFallback,
    ),
  ),
);
