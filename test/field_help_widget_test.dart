// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §5.3, §6.3 APP 5): the
// 「請後台協助」 button in the red box and in the AppBar open the help sheet:
// 「已通知後台」 and the 「請唸給後台」 lines (also when nothing could be
// sent). v1.1: no help code anywhere (user decision), `operator_name` in
// what goes out. On the field phone's 360x640 screen at font scale 1.1.
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
import 'package:gateway_commissioning/presentation/field_help_sheet.dart';

/// Demo gateway + backend recording the rescue uploads ([mode] `ok` /
/// `network`); [failOp] times out once. Logged in as [operatorName].
class _Fake extends DemoSystem implements SessionInfo, OperatorInfo {
  String mode = 'ok';
  String? failOp;
  final uploads = <(String, Map<String, dynamic>)>[];

  @override
  String? operatorName;

  List<Map<String, dynamic>> get diags => [
    for (final u in uploads)
      if (u.$1 == fieldDiagnosticsPath) u.$2,
  ];

  List<Map<String, dynamic>> get reports => [
    for (final u in uploads)
      if (u.$1 == fieldSessionsPath) u.$2,
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

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('field-help-status'))).data!;

/// No help code anywhere on screen, nor in anything sent.
void _noHelpCode(WidgetTester tester, _Fake fake) {
  expect(find.textContaining('求助碼'), findsNothing);
  expect(find.textContaining('電話中請唸'), findsNothing);
  expect(find.byKey(const Key('field-help-code')), findsNothing);
  expect(
    find.textContaining(RegExp(r'\b\d{3}-\d{3}\b')),
    findsNothing,
    reason: 'no NNN-NNN code',
  );
  for (final u in fake.uploads) {
    expect(u.$2.containsKey('short_code'), isFalse, reason: u.$1);
  }
}

void main() {
  testWidgets('red box: 請後台協助 → 已通知後台 + the lines, no help code, on '
      '360x640', (tester) async {
    final fake = _Fake()..operatorName = '王小明';
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
    expect(
      find.descendant(of: help, matching: find.text('請後台協助')),
      findsOneWidget,
    );
    expect(find.textContaining('打電話給後台前按這裡'), findsNothing);
    _noHelpCode(tester, fake);
    await _tap(tester, help);
    await _wait(tester);

    final sheet = find.byKey(const Key('field-help-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('請後台協助')),
      findsOneWidget,
      reason: 'title',
    );
    expect(_status(tester), '✓ 已通知後台');
    expect(find.text('請唸給後台：'), findsOneWidget);
    // The lines to read out stay: site / gateway, MAC, step, error, firmware.
    expect(find.textContaining('閘道器'), findsWidgets);
    expect(find.textContaining('韌體'), findsOneWidget);
    _noHelpCode(tester, fake);
    final step = fake.diags.last['step'];
    expect(find.textContaining('目前第 $step 步：'), findsOneWidget);
    // Round 24: the error line in words only; the code is in 詳細資訊.
    expect(find.text('・錯誤：等待超時，請確認裝置與網路後重試。'), findsOneWidget);
    expect(find.textContaining('CMD_TIMEOUT'), findsNothing);
    await _tap(tester, find.byKey(const Key('field-help-details')));
    expect(find.text('狀況代碼：CMD_TIMEOUT'), findsOneWidget);
    expect(find.text('不會傳送 Wi-Fi 密碼。'), findsOneWidget);
    // What the back office got: no code, the installer's name (package:
    // context.operator_name, report: top level).
    final diag = fake.diags.last;
    expect(diag['trigger'], 'help');
    expect(diag.containsKey('short_code'), isFalse);
    expect((diag['context'] as Map)['operator_name'], '王小明');
    expect((diag['error'] as Map)['code'], 'CMD_TIMEOUT');
    final report = fake.reports.lastWhere((r) => r['event'] == 'help');
    expect(report.containsKey('short_code'), isFalse);
    expect(report['operator_name'], '王小明');
    // The sheet fits the phone's screen (no overflow, inside 360 wide).
    for (final key in ['field-help-status', 'field-help-read']) {
      final rect = tester.getRect(find.byKey(Key(key)));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(640));
    }
    // Only the sheet opened: the commissioning did not move.
    final after = container.read(commissionProvider);
    expect(after.error, before.error);
    expect(after.step, before.step);
    expect(after.busy, isFalse);
    expect(tester.takeException(), isNull);

    await _tap(tester, find.byKey(const Key('field-help-close')));
    expect(find.byKey(const Key('field-help-sheet')), findsNothing);
  });

  testWidgets('AppBar 請後台協助 (no error) → HELP_ONLY, same session again', (
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
    expect(
      tester.widget<IconButton>(appbar).tooltip,
      fieldHelpLabel,
      reason: '請後台協助',
    );
    await _tap(tester, appbar);
    await _wait(tester);
    expect(_status(tester), '✓ 已通知後台');
    _noHelpCode(tester, fake);
    // Not logged in by name: null, still sent.
    expect(
      (fake.diags.last['context'] as Map).containsKey('operator_name'),
      isTrue,
    );
    expect((fake.diags.last['context'] as Map)['operator_name'], isNull);
    final session = fake.diags.last['session_id'];
    // Round 24 (field round 24: 「狀況代碼：HELP_ONLY」 on the sheet).
    expect(find.text('・狀況：畫面沒有錯誤，現場主動求助'), findsOneWidget);
    expect(find.textContaining('HELP_ONLY'), findsNothing);
    expect(fake.diags.last['trigger'], 'help');
    expect((fake.diags.last['error'] as Map)['code'], 'HELP_ONLY');
    expect(tester.takeException(), isNull);

    await _tap(tester, find.byKey(const Key('field-help-close')));
    await _tap(tester, appbar);
    await _wait(tester);
    expect(fake.diags.last['session_id'], session, reason: 'one session');
    _noHelpCode(tester, fake);
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

    _noHelpCode(tester, fake);
    final status = _status(tester);
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
    expect(_status(tester), '✓ 已通知後台');
    expect(fake.diags.last['trigger'], 'help');
    _noHelpCode(tester, fake);
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
