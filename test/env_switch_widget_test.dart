import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
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
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200, version: '1.1.0');
}

class SimGateway extends DemoSystem {
  final commands = <String>[];
  Completer<void>? connectGate;
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
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        envSwitchPolicyProvider.overrideWithValue(policy),
        localBackendProberProvider.overrideWithValue(_Prober()),
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
  await _tap(tester, find.text('搜尋閘道器'));
  await _tap(tester, find.text('GIOS-S1-GW01'));
}

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
    expect(find.text('3 / 8   身份與 WiFi'), findsOneWidget);
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
    expect(state.message, '已連線，請設定身份與 WiFi');
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
    expect(find.text('尚未登入正式站：站號衝突檢查會先略過，第 3 步會請你輸入密碼。'), findsOneWidget);
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
    await _tap(tester, find.text('搜尋閘道器'));
    fake.connectGate = Completer<void>();
    await tester.ensureVisible(find.text('GIOS-S1-GW01'));
    await tester.tap(find.text('GIOS-S1-GW01'));
    await tester.pump();
    expect(container.read(commissionProvider).busy, isTrue);

    await tester.tap(_chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('env-sheet-busy')), findsOneWidget);
    expect(find.textContaining('正在進行「連線並讀取閘道器設定」'), findsOneWidget);
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
