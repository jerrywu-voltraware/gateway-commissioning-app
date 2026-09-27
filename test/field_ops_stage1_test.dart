// FIELD_OPS plan stage 1, APP items: a gateway restart is named as such
// (boot_count / reset_reason), a failed Wi-Fi is split into three causes
// (firmware 1.7.32 wifi_last_disc_reason), and a weak gateway Wi-Fi is red.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/core/gateway_net.dart';
import 'package:gateway_commissioning/core/gateway_reboot.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';

const _production = BackendEnvState(loaded: true);

/// Demo gateway reporting boot_count [boot] (null: firmware before 1.7.6).
/// [dropAfterAssigns]: the phone link drops after that many assigns (the
/// gateway restarting for [restartReason] when set). [timeoutNextNet]: the
/// next get_net_status times out (the gateway restarting for
/// [restartOnTimeout] meanwhile when set). [netExtra] is added to every
/// get_net_status (e.g. the firmware 1.7.32 Wi-Fi reason).
class FieldGateway extends DemoSystem {
  FieldGateway({int? boot = 40}) {
    bootCount = boot;
  }

  int? dropAfterAssigns;
  String? restartReason;
  bool down = false;
  bool timeoutNextNet = false;
  String? restartOnTimeout;
  Map<String, dynamic> netExtra = {};
  final commands = <String>[];
  final assigns = <String>[];

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    down = false;
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (down) throw const GatewayFailure('not_connected');
    commands.add(op);
    if (op == 'get_net_status' && timeoutNextNet) {
      timeoutNextNet = false;
      if (restartOnTimeout != null) simulateRestart(restartOnTimeout!);
      throw const GatewayFailure('timeout');
    }
    if (op == 'assign_device_id') {
      if (dropAfterAssigns != null && assigns.length >= dropAfterAssigns!) {
        dropAfterAssigns = null;
        down = true;
        if (restartReason != null) simulateRestart(restartReason!);
        throw const GatewayFailure('not_connected');
      }
      assigns.add(params['mac'].toString());
    }
    final result = await super.command(op, params);
    return op == 'get_net_status' ? {...result, ...netExtra} : result;
  }

  int count(String op) => commands.where((c) => c == op).length;
}

ProviderContainer _container(DemoSystem fake) => ProviderContainer(
  overrides: [
    linkProvider.overrideWithValue(fake),
    apiProvider.overrideWithValue(fake),
  ],
);

/// Connected, at the network check (step 2).
Future<(ProviderContainer, CommissioningController)> _connected(
  DemoSystem fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = _container(fake);
  final c = container.read(commissionProvider.notifier);
  await c.prepare(productionApiBase, 'pw', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

/// At step 7 with the PTU list read (as link_loss_test.dart).
Future<(ProviderContainer, CommissioningController)> _atPtus(
  FieldGateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = _container(fake);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'test', 'test-password');
  await c.online();
  await c.discover();
  return (container, c);
}

/// Step 8 tests drive 「重新連線並繼續」 themselves.
void _manualRelink() {
  final keep = autoRelinkRounds;
  autoRelinkRounds = 0;
  addTearDown(() => autoRelinkRounds = keep);
}

CommissionState _state({
  int step = 2,
  bool checkPassed = false,
  required Map<String, dynamic> net,
}) => CommissionState(
  step: step,
  checkPassed: checkPassed,
  peer: const GatewayPeer('id', 'GIOS-S1-GW01', -40),
  config: {
    'fw_version': '1.7.32',
    'mqtt_target': 'production',
    'mqtt_connected': net['wifi_state'] == 'got_ip',
    'wifi_ssid': 'Site-2G',
  },
  net: net,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('restart wording', () {
    test('every reset_reason becomes plain words, never the raw code', () {
      const codes = [
        'ble_stack_stuck',
        'panic',
        'task_wdt',
        'int_wdt',
        'wdt',
        'cpu_lockup',
        'brownout',
        'pwr_glitch',
        'poweron',
        'ext',
        'sw',
        'deepsleep',
        'usb',
        'jtag',
        'sdio',
        'efuse',
        'unknown',
      ];
      for (final code in codes) {
        final text = resetReasonText(code);
        expect(text, isNot(contains(code)), reason: code);
        expect(text, isNot(matches(RegExp('[a-z_]{3,}'))), reason: code);
      }
      expect(resetReasonText('ble_stack_stuck'), contains('藍牙功能卡住'));
      expect(resetReasonText('task_wdt'), contains('看門狗'));
      expect(resetReasonText('brownout'), contains('電壓不足'));
      expect(resetReasonText('poweron'), contains('斷電'));
      for (final unknown in [null, '', 'unknown', 'sdio', 'new_reason']) {
        expect(resetReasonText(unknown), '原因不明');
      }
    });

    test('the notice: why, not a PTU fault, carry on', () {
      const once = GatewayReboot(from: 40, to: 41, reason: 'ble_stack_stuck');
      final text = gatewayRebootText(once);
      expect(text, startsWith('閘道器剛重新啟動（原因：藍牙功能卡住，閘道器自動重新啟動修復）。'));
      expect(text, contains('不是 PTU 故障'));
      expect(text, contains('請從目前的步驟繼續'));
      expect(text, isNot(contains('ble_stack_stuck')));
      expect(text, isNot(contains('次）')));

      final twice = gatewayRebootText(const GatewayReboot(from: 3, to: 5));
      expect(twice, startsWith('閘道器剛重新啟動（原因：原因不明；期間共重新啟動 2 次）'));
      expect(twice, contains('請拍下這個畫面回報'));
    });

    test('boot_count only when the firmware reports a number', () {
      expect(bootCountOf({'boot_count': 12}), 12);
      expect(bootCountOf({}), isNull);
      expect(bootCountOf({'boot_count': '12'}), isNull);
      expect(bootCountOf({'boot_count': null}), isNull);
    });
  });

  group('restart detection', () {
    test(
      'step 8: a restart cut the link — named on resume, not a PTU fault',
      () async {
        _manualRelink();
        final fake = FieldGateway()
          ..restartReason = 'ble_stack_stuck'
          ..dropAfterAssigns = 1;
        final (container, c) = await _atPtus(fake);
        addTearDown(container.dispose);
        final macs = fake.devices.map((d) => d['mac'].toString()).toList();
        await c.configurePtus();
        var s = container.read(commissionProvider);
        expect(s.error, phoneLinkLostText);
        expect(s.gatewayReboot, isNull, reason: 'not known before reconnect');

        await c.resumeAssign();
        s = container.read(commissionProvider);
        final reboot = s.gatewayReboot!;
        expect(
          (reboot.from, reboot.to, reboot.reason),
          (40, 41, 'ble_stack_stuck'),
        );
        expect(gatewayRebootText(reboot), contains('藍牙功能卡住'));
        expect(s.error, isNull);
        expect(fake.assigns, [macs[0], macs[1], macs[2]]);
        for (final r in s.results.values) {
          expect(r, isNot(contains('PTU 連線失敗')));
          expect(r, isNot(contains('PTU 沒有回應')));
        }

        c.dismissGatewayReboot();
        expect(container.read(commissionProvider).gatewayReboot, isNull);
      },
    );

    test('a link drop without a restart says nothing about restarts', () async {
      _manualRelink();
      final fake = FieldGateway()..dropAfterAssigns = 1;
      final (container, c) = await _atPtus(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.resumeAssign();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.gatewayReboot, isNull);
    });

    test('a command timeout during a restart is explained, not 等待超時', () async {
      final fake = FieldGateway();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      fake
        ..timeoutNextNet = true
        ..restartOnTimeout = 'task_wdt';
      await c.refreshUploadTarget();
      final s = container.read(commissionProvider);
      expect(s.error, gatewayRebootRetryText);
      expect(s.error, isNot(const GatewayFailure('timeout').message));
      expect(s.gatewayReboot?.reason, 'task_wdt');
      expect(gatewayRebootText(s.gatewayReboot!), contains('看門狗'));
    });

    test(
      'old firmware (no boot_count): a timeout keeps its text, no extra read',
      () async {
        final fake = FieldGateway(boot: null);
        final (container, c) = await _connected(fake);
        addTearDown(container.dispose);
        expect(
          container.read(commissionProvider).net,
          isNot(contains('boot_count')),
        );
        final before = fake.count('get_net_status');
        fake.timeoutNextNet = true;
        await c.refreshUploadTarget();
        final s = container.read(commissionProvider);
        expect(s.error, const GatewayFailure('timeout').message);
        expect(s.gatewayReboot, isNull);
        expect(fake.count('get_net_status'), before + 1);
      },
    );

    test(
      'a restart the APP asked for is not reported; a later one is',
      () async {
        final fake = FieldGateway();
        final (container, c) = await _connected(fake);
        addTearDown(container.dispose);
        await c.switchUploadTarget(const MqttTarget.local('192.168.1.50'));
        var s = container.read(commissionProvider);
        expect(fake.bootCount, 41, reason: 'the switch restarted it');
        expect(s.error, isNull);
        expect(s.gatewayReboot, isNull);

        fake.simulateRestart('panic');
        await c.reconnectLink();
        s = container.read(commissionProvider);
        expect((s.gatewayReboot?.from, s.gatewayReboot?.to), (41, 42));
        expect(gatewayRebootText(s.gatewayReboot!), contains('程式發生錯誤'));
      },
    );

    test(
      'restarted while the APP was closed: the saved count shows it',
      () async {
        _manualRelink();
        final fake = FieldGateway()..dropAfterAssigns = 1;
        final (container, c) = await _atPtus(fake);
        addTearDown(container.dispose);
        await c.configurePtus();
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(prefs.getString('demo_progress')!) as Map;
        expect(saved['boot_count'], 40);

        fake.simulateRestart('brownout');
        final second = _container(fake);
        addTearDown(second.dispose);
        final c2 = second.read(commissionProvider.notifier);
        await c2.restore();
        await c2.resumeSaved();
        final s = second.read(commissionProvider);
        expect(s.error, isNull);
        // get_config told of it, get_net_status right after why.
        expect(s.gatewayReboot?.to, 41);
        expect(s.gatewayReboot?.reason, 'brownout');
        expect(gatewayRebootText(s.gatewayReboot!), contains('電壓不足'));
      },
    );
  });

  group('Wi-Fi failure in three causes', () {
    test('IDF 5.4.1 wifi_err_reason_t values sort into the three causes', () {
      for (final r in [14, 15, 23, 202, 204]) {
        expect(wifiFailKindOf(r), WifiFailKind.password, reason: '$r');
      }
      for (final r in [201, 210, 211]) {
        expect(wifiFailKindOf(r), WifiFailKind.notFound, reason: '$r');
      }
      // AUTH_EXPIRE 2 is not a wrong password (firmware review).
      for (final r in [1, 2, 39, 200, 203, 205, 212]) {
        expect(wifiFailKindOf(r), WifiFailKind.weakOrOther, reason: '$r');
      }
      expect(wifiFailKindOf(null), isNull);
    });

    test('reason field: missing (old firmware), none, own leave, stale', () {
      expect(wifiDiscReasonOf({}), isNull);
      expect(wifiDiscReasonOf({'wifi_last_disc_reason': 0}), isNull);
      expect(wifiDiscReasonOf({'wifi_last_disc_reason': 8}), isNull);
      expect(wifiDiscReasonOf({'wifi_last_disc_reason': 15}), 15);
      const recent = Duration(seconds: 10);
      expect(
        wifiDiscReasonOf({
          'wifi_last_disc_reason': 15,
          'wifi_last_disc_age_s': 30,
        }, notOlderThan: recent),
        isNull,
      );
      expect(
        wifiDiscReasonOf({
          'wifi_last_disc_reason': 15,
          'wifi_last_disc_age_s': 5,
        }, notOlderThan: recent),
        15,
      );
      expect(
        wifiDiscReasonOf({
          'wifi_last_disc_reason': 15,
          'wifi_last_disc_age_s': null,
        }, notOlderThan: recent),
        15,
      );
    });

    test('network check wording per cause; old firmware unchanged', () {
      const legacy =
          'Gateway 連不上 Wi-Fi「Site-2G」。這個 Wi-Fi 可能不在附近、密碼不對，'
          '或是 5 GHz（Gateway 只能用 2.4 GHz）。';
      expect(wifiProblemText('Site-2G'), legacy);
      expect(wifiProblemText('Site-2G', reason: 15), contains('密碼可能錯誤'));
      expect(
        wifiProblemText('Site-2G', reason: 201),
        allOf(contains('找不到 Wi-Fi「Site-2G」'), contains('2.4 GHz')),
      );
      expect(
        wifiProblemText('Site-2G', reason: 200),
        allOf(contains('訊號太弱'), contains('移近基地台')),
      );
      expect(wifiProblemText('', reason: 15), contains('還沒有設定 Wi-Fi'));

      Map<String, dynamic> down(Map<String, dynamic> extra) => {
        'wifi_state': 'disconnected',
        'ssid': 'Site-2G',
        'ip': '',
        'rssi': 0,
        'uptime_sec': 600,
        ...extra,
      };
      final old = networkCheck(
        state: _state(net: down({})),
        env: _production,
      );
      expect(old.wifi.line, '✗ $legacy');
      final wrongKey = _state(
        net: down({'wifi_last_disc_reason': 202, 'wifi_last_disc_age_s': 4}),
      );
      expect(
        networkCheck(state: wrongKey, env: _production).wifi.text,
        wifiProblemText('Site-2G', reason: 202),
      );
      expect(
        connectionStatus(env: _production, state: wrongKey).hint,
        contains('密碼可能錯誤'),
      );
      expect(
        connectionStatus(env: _production, state: wrongKey).details,
        contains('Wi-Fi 最後斷線原因：密碼可能錯誤（代碼 202，4 秒前）'),
      );
    });

    test('set_wifi failure text per cause, trusted only for this attempt', () {
      expect(
        const GatewayFailure('wifi_failed').message,
        '新 WiFi 連線未成功，請檢查密碼與訊號後重試。',
      );
      String message(Map<String, dynamic> net) => wifiFailedFrom(
        net,
        ssid: 'Site-2G',
        sinceSent: const Duration(seconds: 20),
      ).message;
      // Back on the old Wi-Fi and joined: the reason is this attempt's.
      const back = {'ssid': 'Office', 'wifi_state': 'got_ip'};
      expect(
        message({...back, 'wifi_last_disc_reason': 15}),
        allOf(contains('密碼可能錯誤'), isNot(contains('請檢查密碼與訊號'))),
      );
      expect(
        message({...back, 'wifi_last_disc_reason': 201}),
        contains('找不到這個 Wi-Fi'),
      );
      expect(
        message({...back, 'wifi_last_disc_reason': 200}),
        contains('訊號太弱'),
      );
      // Still trying the new one.
      expect(
        message({
          'ssid': 'Site-2G',
          'wifi_state': 'connecting',
          'wifi_last_disc_reason': 204,
        }),
        contains('密碼可能錯誤'),
      );
      const generic = '新 WiFi 連線未成功，請檢查密碼與訊號後重試。';
      // Back on an old Wi-Fi that is gone too: the reason may be about it.
      expect(
        message({
          'ssid': 'Office',
          'wifi_state': 'disconnected',
          'wifi_last_disc_reason': 201,
        }),
        generic,
      );
      // From before set_wifi.
      expect(
        message({
          ...back,
          'wifi_last_disc_reason': 15,
          'wifi_last_disc_age_s': 3600,
        }),
        generic,
      );
      // Firmware before 1.7.32.
      expect(message(back), generic);
    });

    test(
      'set_wifi flow: wrong password named, old firmware unchanged',
      () async {
        Future<String?> run(
          Map<String, dynamic> extra, {
          bool oldGone = false,
        }) async {
          final fake = FieldGateway()
            ..unreachableSsids.add('Site-2G')
            ..netExtra = extra;
          if (oldGone) fake.simulateWifi('disconnected');
          final (container, c) = await _connected(fake);
          addTearDown(container.dispose);
          await c.configureWifi(1, 1, 'Site-2G', 'password123');
          expect(fake.commands, contains('set_wifi'));
          return container.read(commissionProvider).error;
        }

        expect(
          await run({'wifi_last_disc_reason': 15, 'wifi_last_disc_age_s': 2}),
          wifiSetFailedText(15),
        );
        expect(
          await run({'wifi_last_disc_reason': 201}, oldGone: true),
          '新 WiFi 連線未成功，請檢查密碼與訊號後重試。',
        );
        expect(await run({}), '新 WiFi 連線未成功，請檢查密碼與訊號後重試。');
      },
    );
  });

  group('weak gateway Wi-Fi', () {
    test('threshold -75 dBm; 0 (not joined) is no reading', () {
      expect(weakWifiRssiDbm, -75);
      expect(isWeakWifiRssi(-76), isTrue);
      expect(isWeakWifiRssi(-75), isFalse);
      expect(isWeakWifiRssi(-60), isFalse);
      expect(isWeakWifiRssi(0), isFalse);
      expect(isWeakWifiRssi(null), isFalse);
    });

    Map<String, dynamic> up(int rssi) => {
      'wifi_state': 'got_ip',
      'ssid': 'Site-2G',
      'ip': '192.168.0.57',
      'rssi': rssi,
      'uptime_sec': 600,
    };

    test('network check: red advice, not a blocker', () {
      final weak = networkCheck(
        state: _state(net: up(-82)),
        env: _production,
      );
      expect(weak.wifiOk, isTrue);
      expect(
        weak.wifiWeak,
        allOf(contains('-82 dBm'), contains('低於 -75 dBm'), contains('移近基地台')),
      );
      expect(
        networkCheck(
          state: _state(net: up(-60)),
          env: _production,
        ).wifiWeak,
        isNull,
      );
      final noReading = {...up(-60)}..remove('rssi');
      expect(
        networkCheck(
          state: _state(net: noReading),
          env: _production,
        ).wifiWeak,
        isNull,
      );
    });

    test('status panel: red after the check, once only at the check', () {
      final later = connectionStatus(
        env: _production,
        state: _state(step: 4, checkPassed: true, net: up(-82)),
      );
      expect(later.wifiWeak, contains('-82 dBm'));
      expect(later.summary, isNull, reason: 'panel stays open');
      expect(later.details, contains(contains('訊號 -82 dBm（偏弱）')));
      final atCheck = connectionStatus(
        env: _production,
        state: _state(net: up(-82)),
      );
      expect(atCheck.wifiWeak, isNull, reason: 'the check shows it');
      expect(
        connectionStatus(
          env: _production,
          state: _state(step: 4, checkPassed: true, net: up(-60)),
        ).wifiWeak,
        isNull,
      );
    });

    test('details: boot count with the plain reason', () {
      final status = connectionStatus(
        env: _production,
        state: _state(
          step: 4,
          checkPassed: true,
          net: {...up(-60), 'boot_count': 41, 'reset_reason': 'brownout'},
        ),
      );
      expect(
        status.details,
        contains('Gateway 開機次數：41（上次開機原因：供電電壓不足（電源不穩或變壓器太弱））'),
      );
      expect(status.details.join('\n'), isNot(contains('brownout')));
    });
  });

  group('page', () {
    Future<ProviderContainer> pumpApp(
      WidgetTester tester,
      DemoSystem fake,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'production',
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(GatewayApp)));
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> connect(WidgetTester tester) async {
      await tap(tester, find.text('檢查並開始'));
      await tap(tester, find.text('GIOS-S1-GW01'));
    }

    testWidgets('restart notice: plain reason, 知道了 hides it', (tester) async {
      final fake = FieldGateway();
      final container = await pumpApp(tester, fake);
      await connect(tester);
      expect(find.byKey(const Key('gateway-reboot')), findsNothing);

      fake.simulateRestart('ble_stack_stuck');
      unawaited(container.read(commissionProvider.notifier).reconnectLink());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gateway-reboot')), findsOneWidget);
      expect(find.textContaining('閘道器剛重新啟動（原因：藍牙功能卡住'), findsOneWidget);
      expect(find.textContaining('不是 PTU 故障'), findsOneWidget);
      expect(find.textContaining('ble_stack_stuck'), findsNothing);

      await tap(tester, find.byKey(const Key('gateway-reboot-ok')));
      expect(find.byKey(const Key('gateway-reboot')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('weak gateway Wi-Fi is red at the check, then in the panel', (
      tester,
    ) async {
      final fake = FieldGateway()..netExtra = {'rssi': -82};
      final container = await pumpApp(tester, fake);
      await connect(tester);
      expect(container.read(commissionProvider).checkPassed, isTrue);
      final weak = find.byKey(const Key('status-wifi-weak'));
      expect(weak, findsOneWidget);
      final red = Theme.of(tester.element(weak)).colorScheme.error;
      final text = tester.widget<Text>(weak);
      expect(text.data, contains('Wi-Fi 訊號偏弱（-82 dBm'));
      expect(text.style?.color, red);
      final panel = find.byKey(const Key('status-wifi-weak'));
      expect(panel, findsOneWidget);
      expect(tester.widget<Text>(panel).style?.color, red);
      expect(tester.takeException(), isNull);
    });
  });
}
