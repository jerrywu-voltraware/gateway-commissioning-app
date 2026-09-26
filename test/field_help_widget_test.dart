// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §5.3, §6.3 APP 5): the
// 「打電話給後台前按這裡」 button in the red box and the AppBar 「找後台幫忙」
// open the help sheet with a NNN-NNN code; when nothing could be sent the
// 「請唸給後台」 lines are still there. On the field phone's 360x640 screen
// at font scale 1.1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';

const _code = r'^\d{3}-\d{3}$';

/// Demo gateway + backend recording the rescue uploads ([mode] `ok` /
/// `network`); [failOp] times out once.
class _Fake extends DemoSystem implements SessionInfo {
  String mode = 'ok';
  String? failOp;
  final uploads = <(String, Map<String, dynamic>)>[];

  List<Map<String, dynamic>> get diags => [
    for (final u in uploads)
      if (u.$1 == fieldDiagnosticsPath) u.$2,
  ];

  @override
  bool get hasSession => true;

  @override
  String? get origin => 'https://example.invalid';

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == failOp) {
      failOp = null;
      throw const GatewayFailure('timeout');
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!path.startsWith('/api/field/')) {
      return super.request(method, path, body);
    }
    uploads.add((path, Map<String, dynamic>.from(body ?? const {})));
    if (mode == 'network') {
      throw GatewayFailure.network(endpoint: '$method $path', detail: 'x');
    }
    return {'ok': true, 'duplicate': false};
  }
}

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Fake fake, {
  bool reporting = true,
}) async {
  _phoneView(tester);
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        fieldReporterConfigProvider.overrideWithValue(
          FieldReporterConfig(
            allowDemoLink: reporting,
            helpWait: const Duration(milliseconds: 300),
          ),
        ),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(GatewayApp)));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 檢查並開始 → the demo gateway (network check, 第 3–5 步).
Future<void> _connect(WidgetTester tester) async {
  await _tap(tester, find.text('檢查並開始'));
  await _tap(tester, find.text('GIOS-S1-GW01'));
}

/// A red box: re-reading the gateway times out. The page is scrolled back
/// to the box (it sits above the network check).
Future<void> _fail(
  WidgetTester tester,
  ProviderContainer container,
  _Fake fake,
) async {
  fake.failOp = 'get_net_status';
  await container.read(commissionProvider.notifier).refreshUploadTarget();
  await tester.pumpAndSettle();
  final banner = find.byKey(const Key('error-banner'), skipOffstage: false);
  if (banner.evaluate().isNotEmpty) {
    await tester.ensureVisible(banner);
    await tester.pumpAndSettle();
  }
}

/// Lets the upload and its timeout settle behind the open sheet.
Future<void> _wait(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

String _shownCode(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const Key('field-help-code')))
    .data!;

void main() {
  testWidgets('red box: 打電話給後台前按這裡 → code NNN-NNN, sent, on 360x640', (
    tester,
  ) async {
    final fake = _Fake();
    final container = await _pump(tester, fake);
    await _connect(tester);
    await _fail(tester, container, fake);
    final before = container.read(commissionProvider);
    expect(before.error, '等待超時，請確認裝置與網路後重試。');
    expect(find.byKey(const Key('error-banner')), findsOneWidget);

    final help = find.byKey(const Key('field-help'));
    expect(help, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('error-banner')),
        matching: help,
      ),
      findsOneWidget,
    );
    expect(find.text('打電話給後台前按這裡'), findsOneWidget);
    await _tap(tester, help);
    await _wait(tester);

    expect(find.byKey(const Key('field-help-sheet')), findsOneWidget);
    final code = _shownCode(tester);
    expect(code, matches(_code));
    expect(find.textContaining('電話中請唸'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('field-help-status'))).data,
      '✓ 已把目前狀況送給後台，打電話時先唸求助碼。',
    );
    expect(find.text('請唸給後台：'), findsOneWidget);
    final step = fake.diags.last['step'];
    expect(find.textContaining('目前第 $step 步：'), findsOneWidget);
    // Round 24: the error line in words only; the code is in 詳細資訊.
    expect(
      find.text('・錯誤：等待超時，請確認裝置與網路後重試。'),
      findsOneWidget,
    );
    expect(find.textContaining('CMD_TIMEOUT'), findsNothing);
    await _tap(tester, find.byKey(const Key('field-help-details')));
    expect(find.text('狀況代碼：CMD_TIMEOUT'), findsOneWidget);
    expect(find.text('不會傳送 Wi-Fi 密碼。'), findsOneWidget);
    // The code on screen is the one the back office got.
    final diag = fake.diags.last;
    expect(diag['trigger'], 'help');
    expect(diag['short_code'], code.replaceAll('-', ''));
    expect((diag['error'] as Map)['code'], 'CMD_TIMEOUT');
    // The code fits on the phone's screen.
    final rect = tester.getRect(find.byKey(const Key('field-help-code')));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(rect.bottom, lessThanOrEqualTo(640));
    // Only the sheet opened: the commissioning did not move.
    final after = container.read(commissionProvider);
    expect(after.error, before.error);
    expect(after.step, before.step);
    expect(after.busy, isFalse);
    expect(tester.takeException(), isNull);

    await _tap(tester, find.byKey(const Key('field-help-close')));
    expect(find.byKey(const Key('field-help-sheet')), findsNothing);
  });

  testWidgets('AppBar 找後台幫忙 (no error) → HELP_ONLY, same code again', (
    tester,
  ) async {
    final fake = _Fake();
    await _pump(tester, fake);
    // Not before 準備.
    expect(find.byKey(const Key('field-help-appbar')), findsNothing);
    await _connect(tester);
    final appbar = find.byKey(const Key('field-help-appbar'));
    expect(appbar, findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: appbar),
      findsOneWidget,
    );
    await _tap(tester, appbar);
    await _wait(tester);
    final code = _shownCode(tester);
    expect(code, matches(_code));
    // Round 24 (field round 24: 「狀況代碼：HELP_ONLY」 on the sheet).
    expect(find.text('・狀況：畫面沒有錯誤，現場主動求助'), findsOneWidget);
    expect(find.textContaining('HELP_ONLY'), findsNothing);
    expect(fake.diags.last['trigger'], 'help');
    expect((fake.diags.last['error'] as Map)['code'], 'HELP_ONLY');
    expect(tester.takeException(), isNull);

    await _tap(tester, find.byKey(const Key('field-help-close')));
    await _tap(tester, appbar);
    await _wait(tester);
    expect(_shownCode(tester), code, reason: 'one session, one code');
  });

  testWidgets('not sent: 送不出去, the lines to read out, 重新傳送 works', (
    tester,
  ) async {
    final fake = _Fake()..mode = 'network';
    final container = await _pump(tester, fake);
    await _connect(tester);
    await _fail(tester, container, fake);
    await _tap(tester, find.byKey(const Key('field-help')));
    await _wait(tester);

    expect(_shownCode(tester), matches(_code));
    final status = tester
        .widget<Text>(find.byKey(const Key('field-help-status')))
        .data!;
    expect(status, startsWith('⚠ 目前送不出去（沒有網路或後台沒有回應）'));
    expect(status, contains('請在電話中直接唸下面的資訊'));
    expect(find.text('請唸給後台：'), findsOneWidget);
    expect(find.textContaining(RegExp(r'目前第 [3-5] 步：')), findsOneWidget);
    expect(find.textContaining('等待超時'), findsWidgets);
    expect(find.textContaining('韌體'), findsOneWidget);
    final resend = find.byKey(const Key('field-help-resend'));
    expect(resend, findsOneWidget);
    expect(tester.takeException(), isNull);
    // The flow is untouched by the failed upload.
    expect(container.read(commissionProvider).busy, isFalse);

    fake.mode = 'ok';
    await _tap(tester, resend);
    await _wait(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('field-help-status'))).data,
      '✓ 已把目前狀況送給後台，打電話時先唸求助碼。',
    );
    expect(fake.diags.last['trigger'], 'help');
  });

  testWidgets('demo gateway: no help buttons at all', (tester) async {
    final fake = _Fake();
    final container = await _pump(tester, fake, reporting: false);
    await _connect(tester);
    expect(find.byKey(const Key('field-help-appbar')), findsNothing);
    await _fail(tester, container, fake);
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.byKey(const Key('field-help')), findsNothing);
    expect(fake.uploads, isEmpty);
  });
}
