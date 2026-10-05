// 2026-10-05 中英語系（docs/i18n.md）：
// 1. ARB：lib/l10n/app_*.arb 與 parts 合併結果一致；zh／en key 與
//    placeholders 相同；key 帶分區前綴、不跨分區重複。
// 2. L10n 存取器：未初始化就是繁中；load／reset。
// 3. 語言切換：預設繁中（不跟隨系統）；「更多」→「語言」立即生效並寫入
//    prefs `app_locale`；重建 GatewayApp 後讀回。
// 4. 範本檔：mqtt_target 的英文、安裝報告維持中文；兩個範本檔沒有中文
//    字串字面量。
// 5. 邏輯不再比對中文：assignResultKindOf（跨語言）、isNetworkTimeout。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart'
    show notAssignedLinkText;
import 'package:gateway_commissioning/core/assign_progress.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n.dart';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Iterable<String> _keys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

/// `{name}` placeholders used in [text] (top level; ICU plural/select
/// bodies are not parsed here).
Set<String> _used(String text) =>
    RegExp(r'\{(\w+)[,}]').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  group('ARB parts and merged files', () {
    final partFiles =
        Directory('lib/l10n/parts')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.arb'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('parts: <area>_<lang>.arb, keys prefixed, no duplicates', () {
      expect(partFiles, isNotEmpty);
      final seen = <String, Map<String, String>>{'zh': {}, 'en': {}};
      for (final f in partFiles) {
        final name = f.uri.pathSegments.last;
        final m = RegExp(r'^([a-z][A-Za-z0-9]*)_(zh|en)\.arb$').firstMatch(name);
        expect(m, isNotNull, reason: name);
        final area = m!.group(1)!, lang = m.group(2)!;
        for (final key in _keys(_readJson(f.path))) {
          expect(key, startsWith('${area}_'), reason: '$name: $key');
          expect(
            seen[lang]!.containsKey(key),
            isFalse,
            reason: '$key in ${seen[lang]![key]} and $name',
          );
          seen[lang]![key] = name;
        }
      }
    });

    for (final lang in ['zh', 'en']) {
      test('app_$lang.arb equals the merged parts (run tools/merge_l10n.py)', () {
        final merged = <String, dynamic>{};
        for (final f in partFiles.where((f) => f.path.endsWith('_$lang.arb'))) {
          final part = _readJson(f.path);
          for (final key in _keys(part)) {
            merged[key] = part[key];
          }
        }
        final app = _readJson('lib/l10n/app_$lang.arb');
        expect(app['@@locale'], lang);
        expect({for (final k in _keys(app)) k: app[k]}, merged);
      });
    }

    test('zh and en: same keys, same placeholders', () {
      final zh = _readJson('lib/l10n/app_zh.arb');
      final en = _readJson('lib/l10n/app_en.arb');
      expect(_keys(en).toSet(), _keys(zh).toSet());
      for (final key in _keys(zh)) {
        final declared =
            ((zh['@$key'] as Map?)?['placeholders'] as Map?)?.keys
                .cast<String>()
                .toSet() ??
            <String>{};
        expect(_used(zh[key] as String), declared, reason: 'zh $key');
        expect(_used(en[key] as String), declared, reason: 'en $key');
      }
    });
  });

  group('L10n accessor', () {
    test('Chinese before anything loads it; load / reset', () {
      expect(L10n.language, AppLanguage.zh);
      expect(L10n.current.common_close, '關閉');
      useLanguage(AppLanguage.en);
      expect(L10n.current.common_close, 'Close');
      expect(L10n.zh.common_close, '關閉', reason: 'zh stays Chinese');
      L10n.reset();
      expect(L10n.current.common_close, '關閉');
    });

    test('prefs codes', () {
      expect(AppLanguage.fromCode('en'), AppLanguage.en);
      expect(AppLanguage.fromCode('zh'), AppLanguage.zh);
      expect(AppLanguage.fromCode(null), AppLanguage.zh);
      expect(AppLanguage.fromCode('fr'), AppLanguage.zh);
      expect(AppLanguage.zh.locale, appZhLocale);
      expect(appSupportedLocales.first, appZhLocale);
    });
  });

  group('language switch (GatewayApp)', () {
    String? title(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('appbar-title'))).data;

    testWidgets('default is 繁體中文, not the system language', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester);
      expect(title(tester), 'GIOS 設備助手');
      expect(L10n.language, AppLanguage.zh);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, appZhLocale);
    });

    testWidgets('a stored en starts in English; an unknown value in 繁中', (
      tester,
    ) async {
      await pumpApp(tester, prefs: {appLocalePrefKey: 'en'});
      expect(title(tester), 'GIOS Device Assistant');
      expect(L10n.current.common_close, 'Close');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, prefs: {appLocalePrefKey: 'xx'});
      expect(title(tester), 'GIOS 設備助手');
    });

    testWidgets('更多 → 語言 → English: at once, stored, read back', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('topology-menu')));
      await pumpFrames(tester);
      expect(find.text('語言'), findsOneWidget);
      expect(find.text('繁體中文'), findsOneWidget, reason: 'current language');
      await tester.tap(find.byKey(const Key('language-settings-menu')));
      await pumpFrames(tester);
      expect(find.byKey(const Key('language-options')), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      await tester.tap(find.byKey(const Key('language-option-en')));
      await pumpFrames(tester);
      // No restart: the title, the menu and L10n.current follow.
      expect(title(tester), 'GIOS Device Assistant');
      expect(L10n.language, AppLanguage.en);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(appLocalePrefKey), 'en');
      await tester.tap(find.byKey(const Key('topology-menu')));
      await pumpFrames(tester);
      expect(find.text('Language'), findsOneWidget);
      // Close the menu, then build the APP anew: read back from prefs.
      await tester.tapAt(const Offset(5, 5));
      await pumpFrames(tester);
      await tester.pumpWidget(const SizedBox());
      L10n.reset();
      await pumpApp(tester, prefs: {appLocalePrefKey: 'en'});
      expect(title(tester), 'GIOS Device Assistant');
      // And back to 繁體中文.
      await tester.tap(find.byKey(const Key('topology-menu')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('language-settings-menu')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('language-option-zh')));
      await pumpFrames(tester);
      expect(title(tester), 'GIOS 設備助手');
      expect(
        (await SharedPreferences.getInstance()).getString(appLocalePrefKey),
        'zh',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('template: core/mqtt_target.dart', () {
    test('screen texts follow the language', () {
      const local = MqttTarget.local('192.168.0.12');
      expect(local.label, '本地 192.168.0.12:8883');
      useLanguage(AppLanguage.en);
      expect(local.label, 'Local 192.168.0.12:8883');
      expect(local.shortLabel, 'Local 192.168.0.12');
      expect(local.plainLabel, 'the local test server (192.168.0.12)');
      expect(const MqttTarget.production().label, 'Production');
      expect(
        uploadTargetFailureText('busy'),
        'The gateway is busy with another command. Wait and retry.\n'
        '[set_mqtt_target · busy]',
      );
      expect(legacyTargetText(null), contains('version unknown'));
      expect(
        desiredUploadTarget('local', 'http://example.com:18000').error,
        startsWith('The host "example.com"'),
      );
    });

    test('the install report stays Chinese in English', () {
      useLanguage(AppLanguage.en);
      final report = reportTargetText({
        'mqtt_target': 'local',
        'mqtt_host': '192.168.0.12',
        'mqtt_port': 8883,
      });
      expect(
        report,
        '資料上傳目標：本地 192.168.0.12:8883\n'
        '注意：此閘道器目前上傳到本地測試站，出貨前請切回正式站。',
      );
      expect(reportTargetText({'fw_version': '1.7.2'}), contains('韌體 1.7.2'));
    });
  });

  test('template files have no Chinese string literals', () {
    final cjk = RegExp(r'[㐀-鿿＀-￯　-〿]');
    for (final path in [
      'lib/presentation/gateway_status_page.dart',
      'lib/core/mqtt_target.dart',
    ]) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        expect(cjk.hasMatch(line), isFalse, reason: '$path:${i + 1}: $line');
      }
    }
  });

  group('logic no longer compares Chinese words', () {
    test('assignResultKindOf knows both languages', () {
      expect(
        assignResultKindOf(notAssignedLinkText),
        AssignResultKind.notAssigned,
      );
      expect(
        assignResultKindOf(L10n.current.assign_assigningResult(3)),
        AssignResultKind.assigning,
      );
      useLanguage(AppLanguage.en);
      expect(
        assignResultKindOf('Not assigned (phone lost the gateway)'),
        AssignResultKind.notAssigned,
      );
      expect(assignResultKindOf('Assigning #12'), AssignResultKind.assigning);
      // Written before a switch back to 繁中: still recognised.
      L10n.reset();
      expect(assignResultKindOf('Assigning #12'), AssignResultKind.assigning);
      expect(
        assignStatusText(
          const AssignStatus(AssignPhase.waiting),
          result: 'Not assigned (phone lost the gateway)',
        ),
        'Not assigned (phone lost the gateway)',
      );
      expect(
        assignStatusText(
          const AssignStatus(AssignPhase.done, id: 3),
          result: 'Assigning #3',
        ),
        '完成 · #3',
      );
      expect(assignResultKindOf('Assigning #x'), AssignResultKind.other);
      expect(assignResultKindOf('已連線 #3'), AssignResultKind.other);
      expect(assignResultKindOf(null), AssignResultKind.other);
    });

    test('a timed-out backend request is a code, shown in words', () {
      const timeout = GatewayFailure.network(
        endpoint: 'GET /x',
        detail: networkTimeoutDetail,
      );
      expect(timeout.isNetworkTimeout, isTrue);
      expect(timeout.message, contains('[GET /x · 逾時]'));
      useLanguage(AppLanguage.en);
      expect(timeout.message, contains('[GET /x · timed out]'));
      expect(
        const GatewayFailure.network(
          endpoint: 'GET /x',
          detail: 'Connection refused',
        ).isNetworkTimeout,
        isFalse,
      );
      expect(
        const GatewayFailure('timeout', detail: networkTimeoutDetail)
            .isNetworkTimeout,
        isFalse,
        reason: 'only the network code',
      );
    });
  });
}
