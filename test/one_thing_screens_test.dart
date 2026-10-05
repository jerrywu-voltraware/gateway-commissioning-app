// One-thing screens (09-28, user request after the second rehearsal): each
// page says one thing at the top and has one main button named after its
// action.
// 3. The Wi-Fi page only when needed (the gateway is on no Wi-Fi, or
//    〔改用其他 Wi-Fi〕); its main button 〔儲存並繼續〕.
// 4. The station page is one question: 「目前站號是 N，這台要配置在本站
//    嗎？」 〔使用此站點〕, 〔改用其他站號〕 opens the input (〔使用站點 M〕,
//    「確定是新站？」 when the back office has no gateway there — backlog K);
//    a gateway without a station shows the input at once.
// 5. The direct pick: 〔是這台，開始配置〕 and 〔不是這台？〕.
// Technical lines are in 「設備與連線資訊」 (collapsed); errors, the
// Bluetooth alert, 請後台協助 and 結束 never are. The star flow's PTU list
// is unchanged.
import 'support/direct_pick_actions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/written_identities.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';
import 'package:gateway_commissioning/presentation/gateway_signal.dart';

import 'gateway_signal_test.dart' show SignalLink;
import 'network_check_test.dart' show WifiGateway;
import 'round15_direct_flow_test.dart' show PickGateway;
import 'support/pick_gateway.dart';
import 'support/finders.dart';

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

const _phone = Size(360, 640);

void _phoneView(WidgetTester tester, {double scale = 1.0}) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// The app on the gateway list, logged in (the back office answers the
/// 「確定是新站？」 lookup).
Future<ProviderContainer> _pump(
  WidgetTester tester,
  DemoSystem fake, {
  GatewayTopology topology = GatewayTopology.star,
}) async {
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        localBackendProberProvider.overrideWithValue(_Prober()),
        fieldReporterConfigProvider.overrideWithValue(
          const FieldReporterConfig(
            allowDemoLink: true,
            helpWait: Duration(milliseconds: 300),
          ),
        ),
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
  await tester.runAsync(() async {
    final topo = container.read(topologyProvider.notifier);
    await topo.ready;
    await topo.setTopology(topology);
  });
  await tester.runAsync(
    () => container
        .read(commissionProvider.notifier)
        .prepare(container.read(backendEnvProvider).base, 'pw'),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _connect(WidgetTester tester) => pickGateway(
  (f) => _tap(tester, f),
  find.byKey(const ValueKey('demo-gateway')),
);

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('task-title'))).data!;

String _label(WidgetTester tester, String key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
  return ((button.child! as Text).data)!;
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

/// Fully on the 360x640 screen, nothing drawn over its centre.
void _onScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(_phone.height));
  expect(rect.right, lessThanOrEqualTo(_phone.width));
  expect(finder.hitTestable(), findsOneWidget);
}

Finder get _details => find.byKey(const Key('commission-details'));

Future<void> _openDetails(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text(detailsTitle),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await _tap(tester, find.text(detailsTitle));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('4. the station page asks one question', () {
    testWidgets('360x640: 「目前站號是 80，這台要配置在本站嗎？」 with 〔使用此站點〕 '
        'on screen; 〔改用其他站號〕 → 〔使用站點 81〕 → 「確定是新站？」 → '
        'saved with the kept Wi-Fi (no Wi-Fi page)', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway.station();
      final container = await _pump(tester, fake);
      await _connect(tester);
      var s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.checkPassed, isTrue);

      expect(_title(tester), '目前站號是 80，這台要配置在本站嗎？');
      expect(_label(tester, 'station-use'), '使用此站點');
      expect(_enabled(tester, 'station-use'), isTrue);
      _onScreen(tester, find.byKey(const Key('station-use')));
      expect(find.text('改用其他站號'), findsOneWidget);
      // One question: no input, no Wi-Fi form, no 「下一步：…」.
      expect(find.widgetWithText(TextField, siteFieldLabel), findsNothing);
      expect(find.widgetWithText(TextField, 'Wi-Fi 密碼'), findsNothing);
      expect(find.textContaining('下一步：'), findsNothing);
      expect(find.byKey(const Key('check-next')), findsNothing);
      expect(find.byKey(const Key('wifi-keep')), findsOneWidget);

      await _tap(tester, find.text('改用其他站號'));
      expect(_title(tester), stationInputTitle);
      expect(find.widgetWithText(TextField, siteFieldLabel), findsOneWidget);
      expect(_label(tester, 'station-use'), '使用站點');
      expect(_enabled(tester, 'station-use'), isFalse);
      expect(find.text('改回站號 80'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '81',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_label(tester, 'station-use'), '使用站點 81');
      expect(find.textContaining('將配置為 站點 81'), findsOneWidget);
      _onScreen(tester, find.byKey(const Key('station-use')));

      // Backlog K: the back office has no gateway on 81.
      await _tap(tester, find.byKey(const Key('station-use')));
      expect(find.text(newSiteConfirmTitle), findsOneWidget);
      expect(find.text(newSiteConfirmText(81)), findsOneWidget);
      // 「重新輸入」: nothing sent, the input stays.
      await _tap(tester, find.byKey(const Key('new-site-cancel')));
      expect(fake.count('set_site_identity'), 0);
      expect(find.widgetWithText(TextField, siteFieldLabel), findsOneWidget);

      await _tap(tester, find.byKey(const Key('station-use')));
      await _tap(tester, find.byKey(const Key('new-site-ok')));
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.count('set_site_identity'), 1);
      expect(fake.count('set_wifi'), 0, reason: 'the Wi-Fi it is on is kept');
      expect(s.config['site_id'], 81);
      expect(s.step, greaterThanOrEqualTo(3));
      expect(find.text(wifiTaskTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a station the back office knows is not asked about; '
        '〔改回站號 80〕 returns to the question', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway.station();
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _tap(tester, find.text('改用其他站號'));
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '80',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      // The same number: 使用站點 80 keeps the station (PTU search next).
      expect(_label(tester, 'station-use'), '使用站點 80');
      await _tap(tester, find.text('改回站號 80'));
      expect(_title(tester), '目前站號是 80，這台要配置在本站嗎？');
      expect(find.widgetWithText(TextField, siteFieldLabel), findsNothing);
      final c = container.read(commissionProvider.notifier);
      expect(await tester.runAsync(() => c.siteHasGateways(80)), isTrue);
      expect(await tester.runAsync(() => c.siteHasGateways(81)), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new number with 〔改用其他 Wi-Fi〕 opens the Wi-Fi page; '
        'back, its own number again keeps the station (PTU search)', (
      tester,
    ) async {
      _phoneView(tester);
      final fake = WifiGateway.station();
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _tap(tester, find.text('改用其他站號'));
      final field = find.widgetWithText(TextField, siteFieldLabel);
      await tester.enterText(field, '81');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await _tap(tester, find.text(otherWifiLabel));
      await _tap(tester, find.byKey(const Key('new-site-ok')));
      expect(container.read(commissionProvider).config['new_station'], isTrue);
      expect(_title(tester), wifiTaskTitle);
      expect(find.textContaining('將配置為 站點 81'), findsOneWidget);
      await _tap(tester, find.text('返回修改站號'));
      expect(_title(tester), stationInputTitle);
      await tester.enterText(field, '80');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_label(tester, 'station-use'), '使用站點 80');
      await _tap(tester, find.byKey(const Key('station-use')));
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 4);
      expect(s.config['site_id'], 80);
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('set_wifi'), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a gateway without a station shows the input at once '
        '(nothing prefilled)', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway(); // factory 1/1, not in service
      final container = await _pump(tester, fake);
      await _connect(tester);
      final s = container.read(commissionProvider);
      expect(s.checkPassed, isTrue);
      expect(s.config['suggested_site_known'], isFalse);
      expect(_title(tester), stationInputTitle);
      final field = find.widgetWithText(TextField, siteFieldLabel);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(_enabled(tester, 'station-use'), isFalse);
      expect(find.text('改用其他站號'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('3. the Wi-Fi page only when needed', () {
    // 1.0.0+15 (09-29 field): the Wi-Fi first, then the station (was: the
    // station first, then its Wi-Fi page, both sent together).
    testWidgets('360x640: a gateway on no Wi-Fi — 「設定閘道器的 Wi-Fi」 '
        'with 〔儲存並繼續〕 first (Wi-Fi only), then the station with that '
        'Wi-Fi kept (identity only)', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway()
        ..config['wifi_ssid'] = 'Xiaomi_WU'
        ..simulateWifi('disconnected');
      final container = await _pump(tester, fake);
      await _connect(tester);
      expect(container.read(commissionProvider).checkPassed, isFalse);
      expect(_title(tester), wifiProblemTaskTitle);
      expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('wifi-reset-confirm')));

      expect(_title(tester), wifiTaskTitle);
      expect(find.text(wifiFirstPageText), findsOneWidget);
      expect(find.widgetWithText(TextField, siteFieldLabel), findsNothing);
      expect(_label(tester, 'wifi-save'), saveWifiLabel);
      expect(find.text('不改 Wi-Fi，返回'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Wi-Fi 密碼'),
        'password123',
      );
      await tester.pumpAndSettle();
      _onScreen(tester, find.byKey(const Key('wifi-save')));
      await _tap(tester, find.byKey(const Key('wifi-save')));
      expect(fake.count('set_wifi'), 1);
      expect(fake.count('set_site_identity'), 0, reason: 'nothing else sent');

      expect(_title(tester), stationInputTitle);
      expect(find.byKey(const Key('wifi-first-done')), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Wi-Fi 密碼'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, siteFieldLabel),
        '82',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('station-use')));
      await _tap(tester, find.byKey(const Key('new-site-ok')));
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.count('set_site_identity'), 1);
      expect(fake.count('set_wifi'), 1, reason: 'the Wi-Fi is not sent again');
      expect(s.config['site_id'], 82);
      expect(s.step, greaterThanOrEqualTo(3));
      expect(find.text(wifiTaskTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new gateway on Wi-Fi: no Wi-Fi page; 〔改用其他 Wi-Fi〕 '
        'opens it and 〔返回修改站號〕 comes back', (tester) async {
      _phoneView(tester);
      // Not in service, its own station 80/3 (set a moment ago).
      final fake = WifiGateway()
        ..config.addAll({'site_id': 80, 'gateway_id': 3});
      final container = await _pump(tester, fake);
      // 1.0.0+12: set a moment ago by this phone — only then is it the
      // proposal (any other identity it carries is typed again).
      await tester.runAsync(
        () => WrittenIdentities.remember(
          true,
          WrittenIdentity(
            uid: 'AABBCCDDEEFF',
            peerId: 'demo-gateway',
            site: 80,
            gateway: 3,
            at: DateTime.now(),
          ),
        ),
      );
      await _connect(tester);
      expect(container.read(commissionProvider).checkPassed, isTrue);
      expect(_title(tester), '目前站號是 80，這台要配置在本站嗎？');
      expect(find.byKey(const Key('wifi-keep')), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Wi-Fi 密碼'), findsNothing);

      await _tap(tester, find.text(otherWifiLabel));
      expect(_title(tester), wifiTaskTitle);
      expect(find.widgetWithText(TextField, 'Wi-Fi 密碼'), findsOneWidget);
      expect(_label(tester, 'wifi-save'), saveWifiLabel);
      await _tap(tester, find.text('返回修改站號'));
      expect(_title(tester), '目前站號是 80，這台要配置在本站嗎？');
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('set_wifi'), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a station in service: 〔改用其他 Wi-Fi〕 keeps the station '
        '(Wi-Fi only, 〔儲存並繼續〕)', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway.station();
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _tap(tester, find.text(otherWifiLabel));
      expect(container.read(commissionProvider).config['wifi_only'], isTrue);
      expect(_title(tester), wifiTaskTitle);
      expect(find.text('保留站點 80／閘道器 1，只更新 Wi-Fi。'), findsOneWidget);
      expect(_label(tester, 'wifi-save'), saveWifiLabel);
      expect(find.widgetWithText(TextField, siteFieldLabel), findsNothing);
      // 不改 Wi-Fi: back to the question (through the automatic check).
      await _tap(tester, find.text('不改 Wi-Fi，返回'));
      await tester.pumpAndSettle();
      expect(_title(tester), '目前站號是 80，這台要配置在本站嗎？');
      expect(tester.takeException(), isNull);
    });
  });

  group('5. the direct pick', () {
    testWidgets('360x640 at text scale 1.3: 「請辨識眼前的充電樁…」, '
        '〔是這台，開始配置〕 after 〔辨識此樁〕, 〔不是這台？〕 in more actions', (tester) async {
      _phoneView(tester, scale: 1.3);
      final fake = PickGateway();
      final container = await _pump(
        tester,
        fake,
        topology: GatewayTopology.direct,
      );
      await _connect(tester);
      // r33: the gateway is a star one in service — asked about; this
      // test converts it (〔改成一對一〕 keeps the APP's direct mode).
      expect(find.byKey(const Key('topology-ask')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('topology-ask-change')));
      expect(container.read(topologyProvider).topology.isDirect, isTrue);
      await _tap(tester, find.text(useStationLabel));
      var s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(_title(tester), directPickTaskTitle);
      _onScreen(tester, find.byKey(const Key('direct-more')));
      await openDirectActions(tester);
      expect(find.text('不是這台？'), findsOneWidget);
      _onScreen(tester, find.byKey(const Key('direct-not-this')));
      await dismissDirectActions(tester);
      await _tap(tester, find.text('辨識此樁'));
      expect(_label(tester, 'direct-confirm'), directConfirmLabel);
      expect(directConfirmLabel, '是這台，開始配置');
      _onScreen(tester, find.byKey(const Key('direct-confirm')));
      // The rest runs by itself: bind, join, the data check, done.
      await _tap(tester, find.text(directConfirmLabel));
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('details never hide what needs the installer', () {
    testWidgets('360x640: the error banner with 請後台協助 and 結束 stay on '
        'the page; the gateway lines are in 「設備與連線資訊」', (tester) async {
      _phoneView(tester);
      final fake = WifiGateway.station()..simulateWifi('disconnected');
      final container = await _pump(tester, fake);
      await _connect(tester);
      final c = container.read(commissionProvider.notifier);
      expect(find.byKey(const Key('wifi-reset-prompt')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('wifi-reset-later')));
      await _tap(tester, find.byKey(const Key('check-skip')));
      expect(find.byKey(const Key('reuse-blocked')), findsOneWidget);
      // A refused 使用此站點 (as a late tap would be).
      await tester.runAsync(() => c.chooseStation(newStation: false));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).error, reuseBlockedText);

      final banner = find.byKey(const Key('error-banner'));
      await tester.scrollUntilVisible(
        banner,
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.text('請後台協助')),
        findsOneWidget,
      );
      expect(find.descendant(of: _details, matching: banner), findsNothing);
      // Collapsed: the gateway's name / MAC line is not shown.
      expect(find.byKey(const Key('gateway-header')), findsNothing);

      await _openDetails(tester);
      expect(
        find.descendant(
          of: _details,
          matching: find.byKey(const Key('gateway-header')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _details,
          matching: find.byKey(const Key('topology-banner')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _details,
          matching: find.byKey(const Key('step-list')),
        ),
        findsOneWidget,
      );
      // Opened, the banner is still outside it.
      expect(find.descendant(of: _details, matching: banner), findsNothing);
      final end = find.byKey(const Key('page-cancel'));
      await tester.scrollUntilVisible(
        end,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(end, findsOneWidget);
      expect(find.descendant(of: _details, matching: end), findsNothing);
      expect(find.text('結束並重新選擇閘道器'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lost Bluetooth link is said on the page, outside the '
        'details, and cleared when it is back', (tester) async {
      _phoneView(tester);
      final link = SignalLink();
      addTearDown(link.changes.close);
      await _pump(tester, link);
      await _connect(tester);
      expect(find.byKey(const Key('gateway-link-lost')), findsNothing);
      link.signalConnected = false;
      link.changes.add(false);
      await tester.pumpAndSettle();
      final alert = find.byKey(const Key('gateway-link-lost'));
      expect(alert, findsOneWidget);
      expect(find.text(gatewayLinkLostText), findsOneWidget);
      expect(find.descendant(of: _details, matching: alert), findsNothing);
      _onScreen(tester, alert);
      link.signalConnected = true;
      link.changes.add(true);
      await tester.pumpAndSettle();
      expect(alert, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('star flow regression', () {
    testWidgets('〔使用此站點〕 → the PTU list with its boxes and 〔配置 3 台並'
        '開始監控〕, the gateway identify on the page → done', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = WifiGateway.station();
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _tap(tester, find.text(useStationLabel));
      var s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(_title(tester), starPickTaskTitle);
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.byKey(const Key('ptu-configure')), findsOneWidget);
      expect(buttonText('配置 3 台並開始監控'), findsOneWidget);
      expect(find.byKey(const Key('identify-label')), findsOneWidget);
      expect(
        find.descendant(
          of: _details,
          matching: find.byKey(const Key('identify-label')),
        ),
        findsNothing,
      );
      await _tap(tester, buttonText('配置 3 台並開始監控'));
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
