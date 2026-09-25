import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';

const _debug = EnvSwitchPolicy(
  autoSyncDefault: true,
  confirmGatewaySwitch: false,
);
const _release = EnvSwitchPolicy(
  autoSyncDefault: false,
  confirmGatewaySwitch: true,
);

class _Prober implements LocalBackendProber {
  final probed = <String>[];
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async {
    probed.add('$base');
    return const ProbeResult(
      ProbeOutcome.healthy,
      status: 200,
      version: '1.1.0',
    );
  }
}

class SimGateway extends DemoSystem {
  final commands = <String>[];
  Completer<void>? connectGate, prepareGate;
  final logins = <(String, String)>[];

  /// An existing station with three numbered PTUs, ready for step 6.
  SimGateway.commissioned() {
    config['fleet_joined'] = true;
    for (final (i, device) in devices.indexed) {
      device
        ..['device_number'] = i + 1
        ..['connected'] = true
        ..['notify_enabled'] = true;
    }
  }
  SimGateway();

  @override
  Future<void> prepare() async {
    await prepareGate?.future;
  }

  /// Step 6's verification fails at once (keeps the page on step 6).
  bool failVerify = false;

  @override
  Future<void> login(String base, String password) async =>
      logins.add((base, password));

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    if (failVerify && path.contains('bot-monitor')) {
      throw const GatewayFailure('incomplete');
    }
    return super.request(method, path, body);
  }

  @override
  Future<void> connect(GatewayPeer peer) async {
    await connectGate?.future;
    await super.connect(peer);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    commands.add(op);
    return super.command(op, params);
  }
}

const _localPrefs = {
  'backend_environment': 'local',
  'backend_local_url': 'http://192.168.1.50:18000',
};
const _productionPrefs = {
  'backend_environment': 'production',
  'backend_local_url': 'http://192.168.1.50:18000',
};

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  SimGateway fake, {
  Map<String, Object> prefs = _productionPrefs,
  EnvSwitchPolicy policy = _debug,
  _Prober? prober,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        envSwitchPolicyProvider.overrideWithValue(policy),
        localBackendProberProvider.overrideWithValue(prober ?? _Prober()),
        phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
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

Finder get _chip => find.byKey(const Key('env-chip'));

String _chipText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _chip, matching: find.byType(Text)))
    .data!;

Future<void> _connectGateway(WidgetTester tester) async {
  await _tap(tester, find.text('檢查並開始'));
  await _tap(tester, find.text('GIOS-S1-GW01'));
}

/// The network check shown right after connecting has passed: go on to the
/// station choice.
Future<void> _passCheck(WidgetTester tester) =>
    _tap(tester, find.text('下一步：選擇站點'));

Future<void> _chooseInSheet(WidgetTester tester, BackendEnv env) async {
  await tester.tap(_chip);
  await tester.pumpAndSettle();
  await _tap(tester, find.byKey(Key('env-option-${env.name}')));
}

void main() {
  testWidgets('AppBar sheet and prep dropdown share one environment', (
    tester,
  ) async {
    final container = await _pumpApp(tester, SimGateway());
    expect(_chipText(tester), '正式站');

    await _chooseInSheet(tester, BackendEnv.local);
    expect(_chipText(tester), '本地測試');
    final dropdown = tester.widget<DropdownButtonFormField<BackendEnv>>(
      find.byType(DropdownButtonFormField<BackendEnv>),
    );
    expect(dropdown.initialValue, BackendEnv.local);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('local-backend-host')))
          .controller!
          .text,
      '192.168.1.50',
    );
    expect(find.text('已切換到本地測試。連上 Gateway 後會自動讓它一起切換。'), findsOneWidget);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_environment'), 'local');
    expect(
      container.read(backendEnvProvider).base,
      'http://192.168.1.50:18000',
    );

    // The other way round: the prep dropdown moves the AppBar chip.
    await _tap(tester, find.byType(DropdownButtonFormField<BackendEnv>));
    await tester.tap(find.text('正式站').last);
    await tester.pumpAndSettle();
    expect(_chipText(tester), '正式站');
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_environment'), 'production');

    // Typing a new PC address on the prep page is what the sheet shows.
    await _tap(tester, find.byType(DropdownButtonFormField<BackendEnv>));
    await tester.tap(find.text('本地測試').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-backend-host')),
      '192.168.1.77',
    );
    await tester.pumpAndSettle();
    await tester.tap(_chip);
    await tester.pumpAndSettle();
    expect(find.text('資料送到這台電腦上的測試主機（192.168.1.77）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet without a valid local IP asks for one first', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      SimGateway(),
      prefs: {'backend_environment': 'production', 'backend_local_url': 'bad'},
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GatewayApp)),
    );
    container.read(backendEnvProvider.notifier).setLocalHost('');
    await tester.pumpAndSettle();
    await tester.tap(_chip);
    await tester.pumpAndSettle();
    expect(find.text('資料送到這台電腦上的測試主機（還沒設定電腦 IP）'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('env-option-local')));
    expect(find.text('還沒有測試主機的 IP，請按「自動尋找」或直接輸入。'), findsOneWidget);
    expect(_chipText(tester), '正式站', reason: 'not switched yet');
    await tester.enterText(
      find.byKey(const Key('local-backend-host')).last,
      '192.168.1.88',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('使用本地測試'));
    expect(_chipText(tester), '本地測試');
    expect(
      container.read(backendEnvProvider).base,
      'http://192.168.1.88:18000',
    );
  });

  testWidgets('one tap in the sheet also switches the connected gateway', (
    tester,
  ) async {
    final fake = SimGateway();
    final container = await _pumpApp(tester, fake);
    await _connectGateway(tester);
    // Right after connecting: the network check, all passed.
    expect(find.text('5 / 10   確認資料上傳'), findsOneWidget);
    expect(find.text('下一步：設定身份與 Wi-Fi'), findsOneWidget);
    expect(fake.targetRequests, isEmpty, reason: 'already on 正式站');
    expect(find.text('✓ 正式站：手機與 Gateway 都已連上'), findsOneWidget);
    expect(container.read(commissionProvider).loggedIn, isTrue);

    await _chooseInSheet(tester, BackendEnv.local);

    expect(fake.targetRequests.single, {
      'target': 'local',
      'host': '192.168.1.50',
      'port': 8883,
    });
    expect(fake.connects, 2, reason: 'reconnected after the reboot');
    expect(
      fake.commands.sublist(fake.commands.indexOf('set_mqtt_target')),
      containsAllInOrder(['set_mqtt_target', 'ping', 'get_net_status']),
    );
    expect(find.text('✓ 本地測試：手機與 Gateway 都已連上'), findsOneWidget);
    final state = container.read(commissionProvider);
    expect(parseMqttTarget(state.config)!.host, '192.168.1.50');
    expect(state.step, 2);
    expect(state.message, '已連線。先做網路體檢，再設定身份與 Wi-Fi。');
    expect(state.error, isNull);
    expect(state.busy, isFalse);
    expect(
      state.loggedIn,
      isTrue,
      reason: 'logged in again to the local test host (known password)',
    );
    expect(
      find.text('同時切換 Gateway？'),
      findsNothing,
      reason: 'debug: no dialog',
    );

    // And back: 正式站 needs its password, so the old login is dropped.
    await _chooseInSheet(tester, BackendEnv.production);
    expect(fake.targetRequests.last, {'target': 'production'});
    final back = container.read(commissionProvider);
    expect(parseMqttTarget(back.config)!.isLocal, isFalse);
    expect(back.loggedIn, isFalse);
    expect(back.step, 2);
    expect(find.text('尚未登入正式站：站號衝突檢查會先略過，之後需要時會請你輸入密碼。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('debug build: remembered environment syncs on connect', (
    tester,
  ) async {
    final fake = SimGateway();
    await _pumpApp(tester, fake, prefs: _localPrefs, policy: _debug);
    await _connectGateway(tester);
    expect(fake.targetRequests.single['host'], '192.168.1.50');
    expect(find.text('✓ 本地測試：手機與 Gateway 都已連上'), findsOneWidget);
    expect(find.text('同時切換 Gateway？'), findsNothing);
  });

  testWidgets('release build: no auto sync, one-tap 同步 with a confirm', (
    tester,
  ) async {
    final fake = SimGateway();
    await _pumpApp(tester, fake, prefs: _localPrefs, policy: _release);
    await _connectGateway(tester);
    expect(fake.targetRequests, isEmpty);
    expect(find.text('⚠ 送到別處'), findsOneWidget);
    await _tap(tester, find.text('同步'));
    expect(find.text('同時切換 Gateway？'), findsOneWidget);
    await _tap(tester, find.text('先不要'));
    expect(fake.targetRequests, isEmpty);
    await _tap(tester, find.text('同步'));
    await _tap(tester, find.text('切換'));
    expect(fake.targetRequests.single['host'], '192.168.1.50');
    expect(find.text('⚠ 送到別處'), findsNothing);

    // Turning the setting on makes the next connect sync by itself.
    await tester.tap(_chip);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('auto-sync-switch')));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_sync_upload_target'), isTrue);
  });

  testWidgets('legacy firmware gets the plain 韌體太舊 message', (tester) async {
    final fake = SimGateway();
    fake.config
      ..['fw_version'] = '1.7.2'
      ..remove('mqtt_target')
      ..remove('mqtt_host')
      ..remove('mqtt_port');
    await _pumpApp(tester, fake);
    await _connectGateway(tester);
    await _chooseInSheet(tester, BackendEnv.local);
    expect(fake.targetRequests, isEmpty);
    expect(
      find.text('這台 Gateway 韌體太舊（版本 1.7.2），只能送到正式站，請更新到 1.7.3 以上。'),
      findsWidgets,
    );
  });

  testWidgets('switch is refused while a step is running', (tester) async {
    final fake = SimGateway();
    final container = await _pumpApp(tester, fake);
    await _tap(tester, find.text('檢查並開始'));
    fake.connectGate = Completer<void>();
    await tester.ensureVisible(find.text('GIOS-S1-GW01'));
    await tester.tap(find.text('GIOS-S1-GW01'));
    await tester.pump();
    expect(container.read(commissionProvider).busy, isTrue);

    await tester.tap(_chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('env-sheet-busy')), findsOneWidget);
    expect(find.text('正在進行「正在連線 GIOS-S1-GW01，請保持靠近」，完成或按「取消操作」後才能切換。'), findsOneWidget);
    expect(find.text('取消操作'), findsOneWidget, reason: 'the page has it');
    await tester.tap(find.byKey(const Key('env-option-local')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      container.read(backendEnvProvider).environment,
      BackendEnv.production,
    );
    expect(find.byKey(const Key('env-sheet-busy')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('env-sheet-busy')))).pop();
    await tester.pump(const Duration(milliseconds: 500));

    fake.connectGate!.complete();
    await tester.pumpAndSettle();
    final state = container.read(commissionProvider);
    expect(state.step, 2);
    expect(state.error, isNull);
    expect(fake.targetRequests, isEmpty);
    expect(_chipText(tester), '正式站');
  });

  testWidgets('switch refused on step 0 names no missing button', (
    tester,
  ) async {
    final fake = SimGateway()..prepareGate = Completer<void>();
    final container = await _pumpApp(tester, fake);
    await tester.ensureVisible(find.text('檢查並開始'));
    await tester.pump();
    await tester.tap(find.text('檢查並開始'));
    await tester.pump();
    final state = container.read(commissionProvider);
    expect(state.busy, isTrue);
    expect(state.step, 0);
    expect(find.text('取消操作'), findsNothing, reason: 'no cancel on step 0');

    await tester.tap(_chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('正在進行「檢查藍牙與後端連線」，完成後才能切換。'), findsOneWidget);
    expect(find.textContaining('取消操作'), findsNothing);
    Navigator.of(tester.element(find.byKey(const Key('env-sheet-busy')))).pop();
    await tester.pump(const Duration(milliseconds: 500));

    fake.prepareGate!.complete();
    await tester.pumpAndSettle();
    expect(container.read(commissionProvider).step, 1);
  });

  testWidgets('step 7: 切回正式站 then log in and re-verify right there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = SimGateway.commissioned();
    final container = await _pumpApp(tester, fake, prefs: _localPrefs);
    await _connectGateway(tester);
    expect(fake.targetRequests.single['host'], '192.168.1.50');
    await _passCheck(tester);
    await _tap(tester, find.text('沿用目前站點'));
    await _tap(tester, find.text('配置 3 台並開始監控'));
    // Step 6 starts the data verification by itself (no 開始資料驗證 tap).
    var state = container.read(commissionProvider);
    expect(state.error, isNull);
    expect(state.step, 7);
    expect(find.text('開通驗證通過，已恢復自動監控'), findsOneWidget);
    expect(find.text(localTargetShipWarning), findsOneWidget);

    await _tap(tester, find.text('手機和 Gateway 都切回正式站'));
    expect(fake.targetRequests.last, {'target': 'production'});
    state = container.read(commissionProvider);
    expect(state.error, isNull);
    expect(state.loggedIn, isFalse);
    expect(find.text(localTargetShipWarning), findsNothing);
    // Before the fix the old 「開通驗證通過」 stayed and there was no way to
    // log in on this page.
    expect(find.text('開通驗證通過，已恢復自動監控'), findsNothing);
    expect(find.text(backendSwitchedDoneText), findsOneWidget);
    final password = find.widgetWithText(TextField, '正式站的登入密碼');
    expect(password, findsOneWidget);
    expect(find.text('更新健康狀態'), findsNothing);

    // No password yet: say so instead of 「登入失敗」.
    await _tap(tester, find.text('重新連線並驗證'));
    expect(find.text('請先輸入正式站的登入密碼。'), findsOneWidget);
    expect(container.read(commissionProvider).error, isNull);
    expect(container.read(commissionProvider).step, 7);

    await tester.enterText(password, 'vps-secret');
    await _tap(tester, find.text('登入並確認資料'));
    state = container.read(commissionProvider);
    expect(fake.logins.last, (productionApiBase, 'vps-secret'));
    expect(state.loggedIn, isTrue);
    expect(state.error, isNull);
    expect(state.message, '資料持續更新');
    expect(find.widgetWithText(TextField, '正式站的登入密碼'), findsNothing);
    expect(find.text('更新健康狀態'), findsOneWidget);

    await _tap(tester, find.text('重新連線並驗證'));
    state = container.read(commissionProvider);
    expect(state.error, isNull);
    expect(state.step, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('step 7: the password can go straight to 重新連線並驗證', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = SimGateway.commissioned();
    final container = await _pumpApp(tester, fake, prefs: _localPrefs);
    await _connectGateway(tester);
    await _passCheck(tester);
    await _tap(tester, find.text('沿用目前站點'));
    await _tap(tester, find.text('配置 3 台並開始監控'));
    await _tap(tester, find.text('手機和 Gateway 都切回正式站'));
    await tester.enterText(
      find.widgetWithText(TextField, '正式站的登入密碼'),
      'vps-secret',
    );
    await _tap(tester, find.text('重新連線並驗證'));
    final state = container.read(commissionProvider);
    expect(fake.logins.last, (productionApiBase, 'vps-secret'));
    expect(state.error, isNull);
    expect(state.loggedIn, isTrue);
    expect(state.step, 3);
  });

  testWidgets('其他網址 on step 6 is applied after typing pauses', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = SimGateway.commissioned()..failVerify = true;
    final prober = _Prober();
    final container = await _pumpApp(
      tester,
      fake,
      prefs: {
        'backend_environment': 'custom',
        'backend_custom_url': 'https://example.invalid',
      },
      prober: prober,
    );
    await _connectGateway(tester);
    await _passCheck(tester);
    await _tap(tester, find.text('沿用目前站點'));
    await _tap(tester, find.text('配置 3 台並開始監控'));
    expect(container.read(commissionProvider).step, 6);
    expect(container.read(commissionProvider).loggedIn, isTrue);
    // The automatic verification ran once (and failed here), staying on 6.
    expect(container.read(commissionProvider).error, isNotNull);
    final url = find.widgetWithText(TextField, '後端網址');
    prober.probed.clear();

    for (final text in ['https://a.example', 'https://ab.example']) {
      await tester.enterText(url, text);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.enterText(url, 'https://abc.example');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      container.read(commissionProvider).loggedIn,
      isTrue,
      reason: 'login kept while still typing',
    );
    expect(prober.probed, isEmpty, reason: 'no backend check per keystroke');

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(container.read(backendEnvProvider).base, 'https://abc.example');
    expect(container.read(commissionProvider).loggedIn, isFalse);
    expect(prober.probed, ['https://abc.example']);
    expect(
      tester.widget<TextField>(url).controller!.selection.baseOffset,
      'https://abc.example'.length,
      reason: 'the field is not rewritten under the cursor',
    );

    // Typed and started at once: the new URL is used, not the old one.
    await tester.enterText(url, 'https://final.example');
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, '若尚未登入，請輸入登入密碼'),
      'pw',
    );
    await tester.tap(find.text('開始資料驗證'));
    await tester.pumpAndSettle();
    expect(fake.logins.last, ('https://final.example', 'pw'));
    expect(prober.probed, isNot(contains('https://a.example')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow 360dp: chip, sheet and status panel fit', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = SimGateway()..mqttConnected = false;
    await _pumpApp(tester, fake, prefs: _localPrefs, policy: _release);
    expect(_chipText(tester), '本地測試');
    await _connectGateway(tester);
    expect(find.text('⚠ 送到別處'), findsOneWidget);
    await _tap(tester, find.text('技術細節'));
    expect(find.textContaining('46.250.255.172:8883'), findsOneWidget);
    await tester.tap(_chip);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('變更電腦 IP'));
    expect(find.text('自動尋找'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
