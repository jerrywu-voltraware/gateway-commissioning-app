// 1.0.0+15 (09-29 field: a gateway not in service showed 「✗ Gateway 找不到
// Wi-Fi『Xiaomi_WU』」 on the network check; 〔重設 Wi-Fi〕 opened 「請輸入這台
// 要配置的站號」 (6 / 10 站點選擇) and read as the wrong page). The network
// is fixed first: 〔重設 Wi-Fi〕／〔設定 Wi-Fi〕 of a gateway not in service
// opens the Wi-Fi form of 「保留站點」 (set_wifi only, no identity, no
// restart; the upload target first when it must change), the check is read
// again once it joined, and the station follows with that Wi-Fi kept (the
// identity only). A failed Wi-Fi stays on the form with its reason.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/core/gateway_net.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';

import 'network_check_test.dart' show WifiGateway;
import 'support/pick_gateway.dart';

const _lan = MqttTarget.local('192.168.1.50');

const _fast = UploadWatchTiming(
  interval: Duration(milliseconds: 20),
  cap: Duration(seconds: 2),
  slowAfter: Duration(milliseconds: 100),
  confirmAfter: Duration(milliseconds: 200),
  wifiGrace: Duration(milliseconds: 100),
);

const _localPrefs = {
  'backend_environment': 'local',
  'backend_local_url': 'http://192.168.1.50:18000',
};

/// Not in service (factory 1/1), set up for 「Xiaomi_WU」 that it cannot
/// find. [discReason]: `wifi_last_disc_reason` reported with a set_wifi
/// that did not join (firmware 1.7.32).
class _NewGateway extends WifiGateway {
  _NewGateway({this.discReason}) {
    config['wifi_ssid'] = 'Xiaomi_WU';
    simulateWifi('disconnected');
  }

  int? discReason;
  final wifiParams = <Map<String, dynamic>>[];
  final identityParams = <Map<String, dynamic>>[];
  final paths = <String>[];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'set_wifi') wifiParams.add(Map.of(params));
    if (op == 'set_site_identity') identityParams.add(Map.of(params));
    final result = await super.command(op, params);
    if (op == 'get_net_status' &&
        discReason != null &&
        lastWifiError.isNotEmpty) {
      return {
        ...result,
        'wifi_last_disc_reason': discReason,
        'wifi_last_disc_age_s': 1,
      };
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    paths.add(path);
    return super.request(method, path, body);
  }

  /// The ops sent after the first [op].
  List<String> after(String op) => commands.sublist(commands.indexOf(op));
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

class _SignalGateway extends _NewGateway implements GatewaySignalSource {
  @override
  bool signalConnected = true;
  @override
  Stream<bool> get signalConnections => const Stream.empty();
  @override
  Future<int> readSignal() async => -45;
}

Future<(ProviderContainer, CommissioningController)> _connected(
  DemoSystem fake, {
  bool offline = true,
  bool local = false,
}) async {
  SharedPreferences.setMockInitialValues(
    local ? _localPrefs : const {'backend_environment': 'production'},
  );
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      uploadWatchTimingProvider.overrideWithValue(_fast),
      envSwitchPolicyProvider.overrideWithValue(
        const EnvSwitchPolicy(confirmGatewaySwitch: false),
      ),
    ],
  );
  await container.read(backendEnvProvider.notifier).ready;
  final c = container.read(commissionProvider.notifier);
  await c.prepare(
    container.read(backendEnvProvider).base,
    'pw',
    offline: offline,
  );
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

NetworkCheck _check(ProviderContainer container) => networkCheck(
  state: container.read(commissionProvider),
  env: container.read(backendEnvProvider),
);

String _shown(ProviderContainer container) =>
    stepLabels[displayStep(
      container.read(commissionProvider),
      container.read(backendEnvProvider),
    )];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('controller', () {
    test('Wi-Fi failed, 〔重設 Wi-Fi〕: the Wi-Fi form (not the station), '
        'set_wifi only; joined → the check again → the station, whose '
        'identity is written with that Wi-Fi kept', () async {
      final fake = _NewGateway();
      final (container, c) = await _connected(fake, offline: false);
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.checkPassed, isFalse);
      expect(_check(container).wifiProblem, isTrue);

      await c.startWifiFix();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.checkPassed, isTrue);
      expect(s.config[wifiFirstKey], isTrue);
      expect(s.config['wifi_only'], isFalse);
      expect(s.config['choose_station'], isFalse);
      expect(wifiFormOfCheck(s), isTrue);
      expect(_shown(container), '閘道器網路體檢', reason: 'not 站點選擇');
      expect(keptWifiSsid(s), isNull, reason: 'the form asks the password');
      expect(fake.commands, isNot(contains('set_wifi')));

      fake.paths.clear();
      await c.configureWifiFirst('Office-2G', 'password123');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.wifiParams, [
        {'ssid': 'Office-2G', 'password': 'password123'},
      ]);
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('set_mqtt_target'), 0);
      expect(
        fake.paths.where((p) => p.contains('identity')),
        isEmpty,
        reason: 'no check-identity / reserve-identity for the Wi-Fi alone',
      );
      // Joined (the wait), then the check read again.
      expect(
        fake.after('set_wifi').where((op) => op == 'get_net_status').length,
        greaterThanOrEqualTo(2),
      );
      expect(s.step, 2);
      expect(s.checkPassed, isTrue);
      expect(s.config[wifiFirstKey], isFalse);
      expect(s.config['choose_station'], isFalse);
      expect(s.config['new_station'], isFalse);
      expect(s.message, wifiFirstDoneText);
      expect(_shown(container), '站點選擇');
      expect(_check(container).wifiOk, isTrue);
      expect(keptWifiSsid(s), 'Office-2G');
      expect(wifiFirstJoined(s), isTrue);

      // The station: identity only, no Wi-Fi asked for or sent again.
      await c.configureWifi(82, 1, 'Office-2G', '');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 3);
      expect(fake.identityParams, [
        {'site_id': 82, 'gateway_id': 1},
      ]);
      expect(fake.count('set_wifi'), 1);
      expect(fake.paths.any((p) => p.contains('reserve-identity')), isTrue);
      expect(fake.config['wifi_ssid'], 'Office-2G');
    });

    test('MQTT still connecting after the Wi-Fi joined: the upload item does '
        'not hold up the station, and the Wi-Fi is kept', () async {
      final fake = _NewGateway()..mqttConnected = false;
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.startWifiFix();
      await c.configureWifiFirst('Xiaomi_WU', 'password123');
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(_check(container).wifiOk, isTrue);
      expect(_check(container).uploadOk, isFalse);
      expect(s.checkPassed, isTrue);
      expect(s.config[wifiFirstKey], isFalse);
      expect(s.message, wifiFirstDoneText);
      expect(keptWifiSsid(s), 'Xiaomi_WU', reason: 'set here a moment ago');
      await c.configureWifi(3, 1, 'Xiaomi_WU', '');
      s = container.read(commissionProvider);
      expect(s.error, isNull, reason: 'no 「請輸入 Wi-Fi 密碼」');
      expect(s.step, 3);
      expect(fake.count('set_wifi'), 1);
      expect(fake.count('set_site_identity'), 1);
    });

    test('the Wi-Fi does not join: its reason, the Wi-Fi form stays and the '
        'station never opens; a retry that joins goes on', () async {
      // The same SSID, a wrong password: the firmware tells why (15).
      final fake = _NewGateway(discReason: 15)
        ..unreachableSsids.add('Xiaomi_WU');
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.startWifiFix();
      await c.configureWifiFirst('Xiaomi_WU', 'wrong-pass-1');
      var s = container.read(commissionProvider);
      expect(s.error, wifiSetFailedText(15));
      expect(s.error, contains('密碼可能錯誤'));
      expect(s.step, 2);
      expect(s.checkPassed, isTrue);
      expect(s.config[wifiFirstKey], isTrue, reason: 'still the Wi-Fi form');
      expect(s.config['choose_station'], isFalse);
      expect(_shown(container), '閘道器網路體檢');
      expect(keptWifiSsid(s), isNull);
      expect(wifiFirstJoined(s), isFalse);
      expect(fake.count('set_site_identity'), 0);

      // Another network it cannot find: back on the old one, plain words.
      fake.unreachableSsids.add('Missing-2G');
      await c.configureWifiFirst('Missing-2G', 'password123');
      s = container.read(commissionProvider);
      expect(s.error, wifiSetFailedText(null));
      expect(s.config[wifiFirstKey], isTrue);

      fake.unreachableSsids.clear();
      await c.configureWifiFirst('Xiaomi_WU', 'password123');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.config[wifiFirstKey], isFalse);
      expect(s.message, wifiFirstDoneText);
      expect(fake.count('set_wifi'), 3);
      expect(fake.count('set_site_identity'), 0);
    });

    test('the upload target must change too: set_mqtt_target first, then '
        'set_wifi (one reboot), then the station', () async {
      final fake = _NewGateway();
      final (container, c) = await _connected(fake, local: true);
      addTearDown(container.dispose);
      final check = _check(container);
      expect(check.need, SyncNeed.sync);
      expect(check.wifiProblem, isTrue);
      await c.startWifiFix(target: check.syncTarget);
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.config[wifiFirstKey], isTrue);
      expect(parseMqttTarget(s.config)!.sameAs(_lan), isTrue);
      expect(fake.count('set_wifi'), 0);

      await c.configureWifiFirst('Office-2G', 'password123');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.commands.where((op) => op.startsWith('set_')).toList(), [
        'set_mqtt_target',
        'set_wifi',
      ]);
      expect(fake.targetRequests.single, _lan.params);
      expect(fake.connects, 2, reason: 'one reboot, for the target');
      expect(_check(container).targetOk, isTrue);
      expect(s.checkPassed, isTrue);
      expect(s.config[wifiFirstKey], isFalse);
      expect(s.message, wifiFirstDoneText);
    });

    test('the upload target left as it was: after the Wi-Fi the check shows '
        'what is left (no station yet)', () async {
      final fake = _NewGateway();
      final (container, c) = await _connected(fake, local: true);
      addTearDown(container.dispose);
      await c.startWifiFix();
      await c.configureWifiFirst('Office-2G', 'password123');
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.checkPassed, isFalse);
      expect(s.config[wifiFirstKey], isFalse);
      expect(s.message, wifiFirstCheckText);
      final check = _check(container);
      expect(check.wifiOk, isTrue);
      expect(check.targetOk, isFalse);
      expect(fake.count('set_site_identity'), 0);
      // The station after it keeps that Wi-Fi all the same.
      expect(keptWifiSsid(s), 'Office-2G');
    });

    test('a station in service: 〔重設 Wi-Fi〕 is still 「保留站點」', () async {
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.startWifiFix();
      var s = container.read(commissionProvider);
      expect(s.config['wifi_only'], isTrue);
      expect(s.config[wifiFirstKey], isFalse);
      expect(_shown(container), '閘道器網路體檢');
      fake.mqttConnected = false;
      await c.configureWifi(80, 1, 'Office-2G', 'password123');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.checkPassed, isFalse, reason: 'the upload check next');
      expect(s.message, 'Wi-Fi 已更新，站點與 PTU 設定保留。接著確認資料有上傳。');
      expect(s.config[wifiFirstSsidKey], 'Office-2G');
      expect(fake.count('set_site_identity'), 0);
    });

    test('keptWifiSsid: the Wi-Fi-first SSID counts without MQTT, only for '
        'that SSID and not on the form itself', () {
      CommissionState state({
        Object? first,
        bool form = false,
        String ssid = 'Office-2G',
      }) => CommissionState(
        step: 2,
        checkPassed: true,
        config: {
          'fw_version': '1.7.41',
          'wifi_ssid': ssid,
          'mqtt_connected': false,
          wifiFirstKey: form,
          wifiFirstSsidKey: ?first,
        },
        net: {'wifi_state': 'got_ip', 'ssid': ssid, 'ip': '192.168.31.20'},
      );
      expect(keptWifiSsid(state()), isNull);
      expect(keptWifiSsid(state(first: 'Office-2G')), 'Office-2G');
      expect(keptWifiSsid(state(first: 'Xiaomi_WU')), isNull);
      expect(keptWifiSsid(state(first: 'Office-2G', form: true)), isNull);
      expect(wifiFirstJoined(state(first: 'Office-2G')), isTrue);
      expect(wifiFirstJoined(state()), isFalse);
    });
  });

  group('page', () {
    Future<ProviderContainer> pump(WidgetTester tester, DemoSystem fake) async {
      tester.view.physicalSize = const Size(360, 640);
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
            localBackendProberProvider.overrideWithValue(_Prober()),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      await tester.runAsync(
        () => container.read(backendEnvProvider.notifier).ready,
      );
      await tester.runAsync(
        () => container
            .read(commissionProvider.notifier)
            .prepare(container.read(backendEnvProvider).base, 'pw'),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data!;

    Future<void> save(WidgetTester tester, String password) async {
      await tester.enterText(
        find.widgetWithText(TextField, 'Wi-Fi 密碼'),
        password,
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('wifi-save')));
    }

    testWidgets(
      'manual Wi-Fi entry saves through the existing gateway command on both platforms',
      (tester) async {
        final fake = _NewGateway();
        final container = await pump(tester, fake);
        await pickGateway(
          (f) => tap(tester, f),
          find.byKey(const ValueKey('demo-gateway')),
        );
        await tap(tester, find.byKey(const Key('wifi-reset-confirm')));

        expect(find.byKey(const Key('wifi-use-phone')), findsOneWidget);
        await tap(tester, find.byKey(const Key('wifi-manual')));
        final ssid = find.widgetWithText(TextField, 'Wi-Fi 名稱（SSID）');
        expect(tester.widget<TextField>(ssid).controller!.text, 'Xiaomi_WU');
        final password = find.widgetWithText(TextField, 'Wi-Fi 密碼');
        await tester.enterText(password, 'previous-password');
        await tester.enterText(ssid, 'Office-2G');
        expect(tester.widget<TextField>(password).controller!.text, isEmpty);
        await save(tester, 'password123');

        expect(fake.wifiParams.single, {
          'ssid': 'Office-2G',
          'password': 'password123',
        });
        expect(container.read(commissionProvider).error, isNull);
        expect(find.byKey(const Key('wifi-first-done')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

    testWidgets(
      'phone Wi-Fi selection uses the existing set_wifi flow on both platforms',
      (tester) async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const permissions = MethodChannel(
          'flutter.baseflow.com/permissions/methods',
        );
        const wifi = MethodChannel('voltraware/wifi');
        messenger.setMockMethodCallHandler(
          permissions,
          (call) async => call.method == 'checkServiceStatus' ? 1 : {5: 1},
        );
        messenger.setMockMethodCallHandler(wifi, (call) async {
          if (call.method == 'requestLocation') return null;
          expect(call.method, 'current');
          return 'Phone-2G';
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(permissions, null);
          messenger.setMockMethodCallHandler(wifi, null);
        });
        final fake = _NewGateway();
        final container = await pump(tester, fake);
        await pickGateway(
          (f) => tap(tester, f),
          find.byKey(const ValueKey('demo-gateway')),
        );
        await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
        await tap(tester, find.byKey(const Key('wifi-use-phone')));
        expect(text(tester, 'wifi-selected'), 'Phone-2G');
        await save(tester, 'password123');
        expect(fake.wifiParams.single, {
          'ssid': 'Phone-2G',
          'password': 'password123',
        });
        expect(fake.count('set_site_identity'), 0);
        expect(container.read(commissionProvider).error, isNull);
        expect(find.byKey(const Key('wifi-first-done')), findsOneWidget);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );

    testWidgets('〔重設 Wi-Fi〕 → 「設定閘道器的 Wi-Fi」 (3 / 10 閘道器網路體檢, '
        'no station field); a failure keeps it with its reason; joined → '
        '「請輸入這台要配置的站號」 with 「網路已正常」, identity only', (tester) async {
      final fake = _NewGateway(discReason: 15)
        ..unreachableSsids.add('Xiaomi_WU');
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      expect(text(tester, 'task-title'), wifiProblemTaskTitle);
      expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
      await tap(tester, find.byKey(const Key('wifi-reset-confirm')));

      expect(text(tester, 'task-title'), wifiTaskTitle);
      expect(text(tester, 'step-title'), '3 / 10   閘道器網路體檢');
      expect(find.byKey(const Key('wifi-first-intro')), findsOneWidget);
      expect(find.widgetWithText(TextField, siteFieldLabel), findsNothing);
      expect(find.textContaining('站點'), findsNothing);
      expect(find.byKey(const Key('details-review-check')), findsNothing);
      expect(text(tester, 'wifi-selected'), 'Xiaomi_WU');

      // Wrong password: the reason, the same form, nothing else sent.
      await save(tester, 'wrong-pass-1');
      expect(
        find.descendant(
          of: find.byKey(const Key('error-banner')),
          matching: find.text(wifiSetFailedText(15)),
        ),
        findsOneWidget,
      );
      expect(text(tester, 'task-title'), wifiTaskTitle);
      expect(text(tester, 'step-title'), '3 / 10   閘道器網路體檢');
      expect(find.widgetWithText(TextField, siteFieldLabel), findsNothing);
      expect(fake.count('set_site_identity'), 0);

      // Retried with the right one: joined → the station.
      fake.unreachableSsids.clear();
      await save(tester, 'password123');
      expect(container.read(commissionProvider).error, isNull);
      expect(text(tester, 'task-title'), stationInputTitle);
      expect(text(tester, 'step-title'), '6 / 10   站點選擇');
      expect(find.byKey(const Key('wifi-first-done')), findsOneWidget);
      expect(find.text('✓ $wifiFirstDoneText'), findsOneWidget);
      expect(find.byKey(const Key('wifi-keep')), findsOneWidget);
      expect(fake.count('set_wifi'), 2);
      expect(fake.count('set_site_identity'), 0);

      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '82',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('station-use')));
      await tap(tester, find.byKey(const Key('new-site-ok')));
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, greaterThanOrEqualTo(3));
      expect(fake.identityParams.single['site_id'], 82);
      expect(fake.count('set_wifi'), 2, reason: 'no Wi-Fi page after it');
      expect(find.text(wifiTaskTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('〔不改 Wi-Fi，返回〕 goes back to the check, nothing sent', (
      tester,
    ) async {
      final fake = _NewGateway();
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
      expect(text(tester, 'task-title'), wifiTaskTitle);
      await tap(tester, find.text('不改 Wi-Fi，返回'));
      final s = container.read(commissionProvider);
      expect(s.checkPassed, isFalse);
      expect(s.config[wifiFirstKey], isFalse);
      expect(text(tester, 'task-title'), wifiProblemTaskTitle);
      expect(fake.count('set_wifi'), 0);
      expect(fake.count('set_site_identity'), 0);
      await tester.runAsync(
        container.read(commissionProvider.notifier).refreshUploadTarget,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wifi-reset-prompt')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'declining survives refresh and keeps the manual Wi-Fi action',
      (tester) async {
        final fake = _NewGateway();
        final container = await pump(tester, fake);
        await pickGateway(
          (f) => tap(tester, f),
          find.byKey(const ValueKey('demo-gateway')),
        );
        await tap(tester, find.byKey(const Key('wifi-reset-later')));
        for (var i = 0; i < 2; i++) {
          await tester.runAsync(
            container.read(commissionProvider.notifier).refreshUploadTarget,
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('wifi-reset-prompt')), findsNothing);
        }
        expect(container.read(commissionProvider).checkPassed, isFalse);
        expect(fake.count('set_wifi'), 0);
        expect(fake.count('set_site_identity'), 0);
        await tester.scrollUntilVisible(
          find.text('重設 Wi-Fi'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, find.text('重設 Wi-Fi'));
        expect(text(tester, 'task-title'), wifiTaskTitle);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('confirmation preserves the existing station and PTUs', (
      tester,
    ) async {
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      final before = container.read(commissionProvider);
      await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
      final after = container.read(commissionProvider);
      expect(after.config['wifi_only'], isTrue);
      expect(after.config['site_id'], before.config['site_id']);
      expect(after.config['gateway_id'], before.config['gateway_id']);
      expect(after.ptus, before.ptus);
      expect(after.selected, before.selected);
      expect(find.byKey(const Key('wifi-save')).hitTestable(), findsOneWidget);
      expect(fake.count('set_wifi'), 0);
      expect(fake.count('set_site_identity'), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wi-Fi reset returns to the station question even while '
        'the upload is still reconnecting', (tester) async {
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
      fake.mqttConnected = false;
      await save(tester, 'password123');
      final state = container.read(commissionProvider);
      expect(state.error, isNull);
      expect(state.wifi, WifiVerdict.ok);
      expect(text(tester, 'task-title'), '目前站號是 80，這台要配置在本站嗎？');
      expect(
        find.byKey(const Key('station-change')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('station-use')))
            .onPressed,
        isNull,
      );
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('scan_ble_discover'), 0);
      await tap(tester, find.byKey(const Key('station-change')));
      expect(find.widgetWithText(TextField, siteFieldLabel), findsOneWidget);
      expect(find.byKey(const Key('wifi-keep')), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '82',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('station-use')));
      await tap(tester, find.byKey(const Key('new-site-ok')));
      expect(fake.config['site_id'], 82);
      expect(fake.count('set_wifi'), 1, reason: 'the verified Wi-Fi is kept');
      expect(fake.count('set_site_identity'), 1);
      expect(find.byKey(const Key('wifi-save')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('successful reset waits for an explicit station choice before '
        'scanning PTUs', (tester) async {
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
      await save(tester, 'password123');
      await tester.runAsync(
        container.read(commissionProvider.notifier).refreshUploadTarget,
      );
      await tester.pumpAndSettle();
      expect(text(tester, 'task-title'), '目前站號是 80，這台要配置在本站嗎？');
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('scan_ble_discover'), 0);
      await tap(tester, find.byKey(const Key('station-use')));
      expect(container.read(commissionProvider).step, 4);
      expect(fake.count('scan_ble_discover'), greaterThan(0));
      expect(fake.config['site_id'], 80);
      expect(fake.count('set_wifi'), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reset after reviewing the network check still asks for the '
        'station when saved', (tester) async {
      final fake = WifiGateway.station();
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      fake.simulateWifi('disconnected');
      await tester.runAsync(
        container.read(commissionProvider.notifier).refreshUploadTarget,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('station-review-check')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.byKey(const Key('station-review-check')));
      await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
      await save(tester, 'password123');
      expect(text(tester, 'task-title'), '目前站號是 80，這台要配置在本站嗎？');
      expect(
        find.byKey(const Key('station-change')).hitTestable(),
        findsOneWidget,
      );
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('scan_ble_discover'), 0);
      expect(tester.takeException(), isNull);
    });

    for (final gate in ['test-mode', 'upload-paused', 'target-mismatch']) {
      testWidgets('station reuse after Wi-Fi reset still respects $gate', (
        tester,
      ) async {
        final fake = WifiGateway.station()..simulateWifi('disconnected');
        if (gate == 'test-mode') fake.config['mode'] = 'test';
        if (gate == 'upload-paused') fake.config['upload_paused'] = true;
        final container = await pump(tester, fake);
        await pickGateway(
          (f) => tap(tester, f),
          find.byKey(const ValueKey('demo-gateway')),
        );
        await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
        if (gate == 'target-mismatch') {
          fake.config.addAll({
            'mqtt_target': 'local',
            'mqtt_host': '192.168.1.50',
            'mqtt_port': 1883,
          });
        }
        await save(tester, 'password123');
        await tester.runAsync(
          container.read(commissionProvider.notifier).refreshUploadTarget,
        );
        await tester.pumpAndSettle();
        expect(text(tester, 'task-title'), '目前站號是 80，這台要配置在本站嗎？');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('station-use')))
              .onPressed,
          isNull,
        );
        expect(find.byKey(const Key('station-change')), findsOneWidget);
        expect(fake.count('set_site_identity'), 0);
        expect(fake.count('scan_ble_discover'), 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a failed reset stays on the Wi-Fi form until retry succeeds', (
      tester,
    ) async {
      final fake = WifiGateway.station()
        ..simulateWifi('disconnected')
        ..unreachableSsids.add('Xiaomi_WU');
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
      await save(tester, 'wrong-pass-1');
      expect(container.read(commissionProvider).error, isNotNull);
      expect(text(tester, 'task-title'), wifiTaskTitle);
      expect(find.byKey(const Key('station-change')), findsNothing);
      fake.unreachableSsids.clear();
      await save(tester, 'password123');
      expect(container.read(commissionProvider).error, isNull);
      expect(text(tester, 'task-title'), '目前站號是 80，這台要配置在本站嗎？');
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('scan_ble_discover'), 0);
      expect(tester.takeException(), isNull);
    });

    for (final scenario in [
      'connecting',
      'upload-only',
      'unsupported',
      'unknown',
      'link-lost',
    ]) {
      testWidgets('$scenario does not prompt for Wi-Fi reset', (tester) async {
        final fake = _SignalGateway();
        switch (scenario) {
          case 'connecting':
            fake.simulateWifi('connecting');
            fake.connectingReads = 100;
          case 'upload-only':
            fake.simulateWifi('got_ip');
            fake.mqttConnected = false;
          case 'unsupported':
            fake.config['fw_version'] = '1.0.0';
          case 'unknown':
            fake.netNotReadyAfterReboot = true;
            fake.connects = 2;
          case 'link-lost':
            fake.signalConnected = false;
        }
        await pump(tester, fake);
        await pickGateway(
          (f) => tap(tester, f),
          find.byKey(const ValueKey('demo-gateway')),
        );
        expect(find.byKey(const Key('wifi-reset-prompt')), findsNothing);
        expect(fake.count('set_wifi'), 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'a gateway without Wi-Fi configured is offered the Wi-Fi form',
      (tester) async {
        final fake = _NewGateway()..config['wifi_ssid'] = '';
        await pump(tester, fake);
        await pickGateway(
          (f) => tap(tester, f),
          find.byKey(const ValueKey('demo-gateway')),
        );
        expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
        await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
        expect(text(tester, 'task-title'), wifiTaskTitle);
        expect(fake.count('set_wifi'), 0);
      },
    );

    for (final change in ['recovered', 'link-lost']) {
      testWidgets('confirmation after $change does not open the Wi-Fi form', (
        tester,
      ) async {
        final fake = _SignalGateway();
        final container = await pump(tester, fake);
        await pickGateway(
          (f) => tap(tester, f),
          find.byKey(const ValueKey('demo-gateway')),
        );
        expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
        if (change == 'recovered') {
          fake.simulateWifi('got_ip');
          await tester.runAsync(
            container.read(commissionProvider.notifier).refreshUploadTarget,
          );
          await tester.pumpAndSettle();
        } else {
          fake.signalConnected = false;
        }
        await tap(tester, find.byKey(const Key('wifi-reset-confirm')));
        expect(find.byKey(const Key('wifi-save')), findsNothing);
        expect(fake.count('set_wifi'), 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Wi-Fi prompt waits until the app returns to the foreground', (
      tester,
    ) async {
      final fake = _NewGateway();
      await pump(tester, fake);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      expect(find.byKey(const Key('wifi-reset-prompt')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
      await tap(tester, find.byKey(const Key('wifi-reset-later')));
    });

    testWidgets('another dialog blocks the Wi-Fi prompt until dismissed', (
      tester,
    ) async {
      final fake = _NewGateway();
      final container = await pump(tester, fake);
      await tester.runAsync(container.read(commissionProvider.notifier).scan);
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.byKey(const Key('step-title'))),
          builder: (context) => AlertDialog(
            title: const Text('Review'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        container
            .read(commissionProvider.notifier)
            .connect(container.read(commissionProvider).peers.single),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wifi-reset-prompt')), findsNothing);
      await tap(tester, find.text('Close'));
      expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
      await tap(tester, find.byKey(const Key('wifi-reset-later')));
    });

    testWidgets('the check passing at once: the station as before, no '
        '「網路已正常」 line', (tester) async {
      final fake = WifiGateway();
      final container = await pump(tester, fake);
      await pickGateway(
        (f) => tap(tester, f),
        find.byKey(const ValueKey('demo-gateway')),
      );
      expect(container.read(commissionProvider).checkPassed, isTrue);
      expect(text(tester, 'task-title'), stationInputTitle);
      expect(find.byKey(const Key('wifi-first-done')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
