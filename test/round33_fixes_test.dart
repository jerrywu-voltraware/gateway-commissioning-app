// Round 33 (2026-09-28, r33_prod/r33_results.md) backlog:
//  1. a fresh install defaults to star; a one-to-one gateway went through
//     it silently as max_connections 5 — the gateway's mode is asked about;
//  2. 81 typed, 81/1 held by another device: the APP went on as 81/2
//     without a word — said, with 〔取代舊機〕 (force_replace);
//  3. the back office flagged this gateway's number in conflict, the APP
//     said nothing — its conflict text, with 〔取代舊機〕;
//  4. (env_switch_widget_test) the permission dialog is not timed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';
import 'network_check_test.dart' show WifiGateway;

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

const _other = 'AABBCC000099';

/// A gateway whose back office holds other devices' records.
class _Gateway extends WifiGateway {
  _Gateway() : super();
  _Gateway.station() : super.station();

  /// 'site/gw' → the MAC on record.
  final records = <String, String>{};

  /// 'site/gw' → the back office's conflict text (flag up).
  final conflicts = <String, String>{};
  final reserves = <String>[];

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final identity = RegExp(
      r'^/api/gateways/(\d+)/(\d+)/check-identity$',
    ).firstMatch(path);
    if (identity != null) {
      final mac = records['${identity[1]}/${identity[2]}'];
      return {'exists': mac != null, 'last_seen_mac': mac, 'archived': false};
    }
    if (path.contains('reserve-identity')) {
      reserves.add('$method $path');
      final m = RegExp(r'/api/gateways/(\d+)/(\d+)/').firstMatch(path)!;
      records['${m[1]}/${m[2]}'] = config['gateway_uid'].toString();
      return {'replaced': path.contains('force_replace=true')};
    }
    final fleet = RegExp(r'fleet-status\?site_id=(\d+)').firstMatch(path);
    if (fleet != null) {
      final site = int.parse(fleet[1]!);
      return {
        'gateways': [
          for (final e in records.entries)
            if (e.key.startsWith('$site/'))
              {
                'site_id': site,
                'gateway_id': int.parse(e.key.split('/')[1]),
                'last_seen_mac': e.value,
                'conflict_flag': conflicts.containsKey(e.key),
                'conflict_message': conflicts[e.key],
              },
        ],
      };
    }
    return super.request(method, path, body);
  }
}

/// The app on the gateway list, logged in.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  DemoSystem fake, {
  GatewayTopology topology = GatewayTopology.star,
}) async {
  tester.view.physicalSize = const Size(411, 891);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

Future<void> _connect(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('demo-gateway')));

Future<void> _typeSite(WidgetTester tester, String site) async {
  await tester.enterText(find.widgetWithText(TextField, siteFieldLabel), site);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await _tap(tester, find.byKey(const Key('station-use')));
}

void main() {
  group('1. the gateway mode against the APP mode', () {
    test('gatewayTopologyMismatch', () {
      const star = GatewayTopology.star, direct = GatewayTopology.direct;
      // One-to-one gateway (bound or not, in service or not), APP star.
      expect(
        gatewayTopologyMismatch({
          'max_connections': 1,
          'direct_bind_mac': '90:5F:00:00:00:01',
        }, star),
        direct,
      );
      expect(gatewayTopologyMismatch({'max_connections': 1}, star), direct);
      expect(gatewayTopologyMismatch({'max_connections': 1}, direct), isNull);
      // Star gateway in service, APP direct.
      expect(
        gatewayTopologyMismatch({
          'max_connections': 5,
          'fleet_joined': true,
        }, direct),
        star,
      );
      expect(
        gatewayTopologyMismatch({
          'max_connections': 5,
          'fleet_joined': true,
        }, star),
        isNull,
      );
      // A factory gateway (5, not in service) is not asked about.
      expect(gatewayTopologyMismatch({'max_connections': 5}, direct), isNull);
      expect(gatewayTopologyMismatch(const {}, star), isNull);
      expect(gatewayBoundMac({'direct_bind_mac': ''}), isNull);
      expect(gatewayBoundMac({'direct_bind_mac': 'AA'}), 'AA');
    });

    testWidgets('APP star, gateway one-to-one and bound: asked, the default '
        '〔維持一對一〕 switches the APP; the gateway is not changed', (tester) async {
      final fake = _Gateway.station()
        ..config['max_connections'] = 1
        ..config['direct_bind_mac'] = '90:5F:00:00:00:01';
      final container = await _pump(tester, fake);
      await _connect(tester);
      expect(find.byKey(const Key('topology-ask')), findsOneWidget);
      expect(
        find.textContaining('目前是一對一模式（已綁定 PTU 90:5F:00:00:00:01），要改成星狀嗎？'),
        findsOneWidget,
      );
      expect(find.text('維持一對一'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('topology-ask-keep')));
      expect(find.byKey(const Key('topology-ask')), findsNothing);
      expect(container.read(topologyProvider).topology, GatewayTopology.direct);
      expect(fake.config['max_connections'], 1);
      expect(fake.config['direct_bind_mac'], '90:5F:00:00:00:01');
      expect(tester.takeException(), isNull);
    });

    testWidgets('APP direct, gateway star in service: 〔改成一對一〕 keeps '
        'the APP direct', (tester) async {
      final fake = _Gateway.station()..config['max_connections'] = 5;
      final container = await _pump(
        tester,
        fake,
        topology: GatewayTopology.direct,
      );
      await _connect(tester);
      expect(find.textContaining('目前是星狀模式（最多 5 台 PTU）'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('topology-ask-change')));
      expect(container.read(topologyProvider).topology, GatewayTopology.direct);
    });

    testWidgets('same mode: nothing asked', (tester) async {
      final fake = _Gateway.station()..config['max_connections'] = 5;
      await _pump(tester, fake);
      await _connect(tester);
      expect(find.byKey(const Key('topology-ask')), findsNothing);
    });
  });

  group('2. a number held by another device', () {
    testWidgets('81 typed, 81/1 taken: 「站 81 的閘道器 1 已被其他設備使用，'
        '改用閘道器 2」; 〔改用閘道器 2〕 goes on as 81/2', (tester) async {
      final fake = _Gateway()..config['wifi_ssid'] = 'Xiaomi_WU';
      fake.records['81/1'] = _other;
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _typeSite(tester, '81');
      expect(find.byKey(const Key('number-taken')), findsOneWidget);
      expect(find.textContaining(numberTakenText(81, 1, 2)), findsOneWidget);
      expect(find.textContaining(_other), findsOneWidget);
      await _tap(tester, find.byKey(const Key('number-taken-next')));
      final s = container.read(commissionProvider);
      expect(s.config['site_id'], 81);
      expect(s.config['gateway_id'], 2);
      expect(fake.reserves.where((r) => r.contains('force_replace')), isEmpty);
    });

    testWidgets('〔取代舊機（沿用閘道器 1）〕 saves 81/1 with force_replace, '
        'no second question', (tester) async {
      final fake = _Gateway()..config['wifi_ssid'] = 'Xiaomi_WU';
      fake.records['81/1'] = _other;
      fake.conflicts['81/1'] = 'ID 衝突：偵測到多台實體設備使用相同 Site 81 / Gateway 1。';
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _typeSite(tester, '81');
      // The back office's own conflict text is shown too.
      expect(find.textContaining('ID 衝突：偵測到多台實體設備'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('number-taken-replace')));
      expect(find.text('編號已被使用'), findsNothing);
      final s = container.read(commissionProvider);
      expect(s.config['site_id'], 81);
      expect(s.config['gateway_id'], 1);
      expect(
        fake.reserves.where((r) => r.contains('81/1/reserve-identity')).first,
        contains('force_replace=true'),
      );
    });

    testWidgets('取消 sends nothing', (tester) async {
      final fake = _Gateway()..config['wifi_ssid'] = 'Xiaomi_WU';
      fake.records['81/1'] = _other;
      await _pump(tester, fake);
      await _connect(tester);
      await _typeSite(tester, '81');
      await _tap(tester, find.byKey(const Key('number-taken-cancel')));
      expect(fake.count('set_site_identity'), 0);
    });
  });

  group('3. this gateway\'s own number flagged in conflict', () {
    const text =
        'ID 衝突：偵測到多台實體設備使用相同 Site 80 / Gateway 1。'
        '目前連線 MAC: AA:BB:CC:DD:EE:FF，被踢掉 MAC: AA:BB:CC:00:00:99';

    testWidgets('〔使用此站點〕: the back office text; 〔取代舊機〕 reserves '
        'it with force_replace and goes on', (tester) async {
      final fake = _Gateway.station();
      fake.records['80/1'] = fake.config['gateway_uid'].toString();
      fake.conflicts['80/1'] = text;
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _tap(tester, find.text(useStationLabel));
      expect(find.byKey(const Key('identity-conflict')), findsOneWidget);
      expect(find.textContaining(text), findsOneWidget);
      await _tap(tester, find.byKey(const Key('identity-conflict-replace')));
      expect(
        fake.reserves.single,
        allOf(
          contains('80/1/reserve-identity'),
          contains('force_replace=true'),
        ),
      );
      expect(container.read(commissionProvider).step, greaterThanOrEqualTo(4));
    });

    testWidgets('〔改用其他站號〕 opens the input, nothing sent', (tester) async {
      final fake = _Gateway.station();
      fake.records['80/1'] = fake.config['gateway_uid'].toString();
      fake.conflicts['80/1'] = text;
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _tap(tester, find.text(useStationLabel));
      await _tap(tester, find.byKey(const Key('identity-conflict-other-site')));
      expect(fake.reserves, isEmpty);
      expect(container.read(commissionProvider).step, 2);
      expect(find.widgetWithText(TextField, siteFieldLabel), findsOneWidget);
    });

    testWidgets('no conflict: 〔使用此站點〕 asks nothing', (tester) async {
      final fake = _Gateway.station();
      fake.records['80/1'] = fake.config['gateway_uid'].toString();
      final container = await _pump(tester, fake);
      await _connect(tester);
      await _tap(tester, find.text(useStationLabel));
      expect(find.byKey(const Key('identity-conflict')), findsNothing);
      expect(container.read(commissionProvider).step, greaterThanOrEqualTo(4));
    });
  });
}
