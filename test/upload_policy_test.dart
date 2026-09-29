// 1.0.0+19 (upload policy, docs/design/upload_policy_2026-09-29.md §G):
// 1. Build mode: the connect puts the gateway at one reading a second
//    (`set_config {ds_enabled:true, ds_min_ms:1000, ds_max_ms:1000}`) —
//    only a firmware reporting `ds_min_ms`, not when it is already
//    1000 / 1000, at most once per connect, no retry, no read-back; a
//    refused key, a provisioned OTP or a gateway error is only recorded,
//    the commissioning goes on. A new gateway, a station in service
//    (〔重設 Wi-Fi〕, 〔更換 PTU〕) and 〔配置下一台〕 all connect there.
// 2. The done page says 「資料上傳頻率由後台控制（目前每 N 秒）」 from `GET
//    /api/upload-policy` (the flow's APP-key session); any failure or no
//    login → 「資料上傳頻率由後台控制」, never waited for.
import 'dart:async';

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
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

const _policyPath = '/api/upload-policy';

/// The demo's first PTU (one-to-one: this pile's, bound).
const _ownPtu = 'AA:BB:CC:00:00:01';

/// A gateway whose get_config reports the ds_* keys (the real firmware
/// does; the demo does not), recording every command ([PickGateway]).
/// [fleetJoined] false: a new gateway. The build-mode set_config answers
/// [buildAck] or throws [buildError] when set.
class _DsGateway extends PickGateway {
  _DsGateway({
    int? min = 5000,
    int? max = 5000,
    Object? enabled = true,
    bool fleetJoined = false,
    super.rssi,
  }) {
    config['fleet_joined'] = fleetJoined;
    if (min != null) config['ds_min_ms'] = min;
    if (max != null) config['ds_max_ms'] = max;
    if (enabled != null) config['ds_enabled'] = enabled;
  }

  Map<String, dynamic>? buildAck;

  /// Thrown by the next build-mode set_configs, one each, in order.
  final buildErrors = <Object>[];

  /// Held until completed: the build-mode set_config waits for it.
  Completer<void>? buildGate;

  /// The next [dropNetReads] get_net_status fail as a dropped link.
  int dropNetReads = 0;

  /// The `/api/upload-policy` answer: throws [policyError] when set, else
  /// waits for [policyGate] when set.
  Object? policyError;
  Completer<void>? policyGate;
  int policyReads = 0;

  /// The build-mode set_configs sent (params as sent).
  List<Map<String, dynamic>> get buildSends => [
    for (final p in sent('set_config'))
      if (p.containsKey('ds_min_ms')) p,
  ];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'set_config' && params.containsKey('ds_min_ms')) {
      if (buildGate != null) await buildGate!.future;
      if (buildErrors.isNotEmpty) {
        ops.add((op, Map.of(params)));
        throw buildErrors.removeAt(0);
      }
      final ack = buildAck;
      if (ack != null) {
        ops.add((op, Map.of(params)));
        return ack;
      }
    }
    if (op == 'get_net_status' && dropNetReads > 0) {
      dropNetReads--;
      ops.add((op, Map.of(params)));
      throw const GatewayFailure('disconnected');
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == _policyPath) {
      policyReads++;
      final error = policyError;
      if (error != null) throw error;
      if (policyGate != null) await policyGate!.future;
    }
    return super.request(method, path, body);
  }

  /// 〔配置下一台〕: the next gateway on the bench, factory 1/1, at the
  /// firmware default interval.
  void nextFactoryGateway() => config.addAll({
    'site_id': 1,
    'gateway_id': 1,
    'fleet_joined': false,
    'gateway_uid': 'A0DD6CA370F0',
    'ds_enabled': true,
    'ds_min_ms': 1000,
    'ds_max_ms': 2000,
  });
}

/// One-to-one, in service, bound to [_ownPtu]; [present] false: that PTU
/// is gone (r34 PTU-missing card, 〔更換 PTU〕).
class _BoundDsGateway extends _DsGateway {
  _BoundDsGateway({bool present = true}) : super(fleetJoined: true) {
    config['max_connections'] = 1;
    config['direct_bind_mac'] = _ownPtu;
    if (!present) devices.removeWhere((d) => d['mac'] == _ownPtu);
  }
}

final _buildParams = {'ds_enabled': true, 'ds_min_ms': 1000, 'ds_max_ms': 1000};

Future<(ProviderContainer, CommissioningController)> _connected(
  DemoSystem fake, {
  GatewayTopology topology = GatewayTopology.star,
  bool offline = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(topology);
  await topo.setDirectBindOnConfirm(false);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: offline);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

/// Star, logged in: a new gateway commissioned as 1/1 and verified.
Future<(ProviderContainer, CommissioningController)> _starDone(
  _DsGateway fake,
) async {
  final (container, c) = await _connected(fake, offline: false);
  await c.configureWifi(1, 1, 'test-network', 'password123');
  await c.online();
  await c.discover();
  await c.configurePtus();
  await c.verify('https://example.invalid', '');
  final s = container.read(commissionProvider);
  expect(s.error, isNull);
  expect(s.step, 7, reason: 'done page');
  expect(s.verified, isTrue);
  await _settle();
  return (container, c);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

void _phone(WidgetTester tester, double scale) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<ProviderContainer> _pumpApp(WidgetTester tester, DemoSystem fake) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        envSwitchPolicyProvider.overrideWithValue(
          const EnvSwitchPolicy(
            autoSyncDefault: false,
            confirmGatewaySwitch: true,
            localBuild: false,
          ),
        ),
        localBackendProberProvider.overrideWithValue(_Prober()),
        phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
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
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> _pumpStarDone(
  WidgetTester tester,
  _DsGateway fake,
) async {
  final container = await _pumpApp(tester, fake);
  await tester.runAsync(() async {
    final c = container.read(commissionProvider.notifier);
    await c.prepare(container.read(backendEnvProvider).base, 'pw');
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await c.configureWifi(80, 1, 'Office-2G', 'pw123456');
    await c.online();
    await c.discover();
    await c.configurePtus();
    await c.verify('https://example.invalid', '');
    await _settle();
  });
  await tester.pumpAndSettle();
  expect(container.read(commissionProvider).step, 7, reason: 'done page');
  return container;
}

/// One-to-one without the pile's PTU (every PTU under -55 dBm), offline:
/// 〔先完成配置〕 — the done page.
Future<ProviderContainer> _pumpDeferredDone(
  WidgetTester tester,
  _DsGateway fake,
) async {
  final container = await _pumpApp(tester, fake);
  await tester.runAsync(() async {
    final topo = container.read(topologyProvider.notifier);
    await topo.ready;
    await topo.setTopology(GatewayTopology.direct);
    await topo.setDirectBindOnConfirm(true);
    final c = container.read(commissionProvider.notifier);
    await c.prepare('https://example.invalid', '', offline: true);
    await c.scan();
    await c.connect(container.read(commissionProvider).peers.single);
    await c.passNetworkCheck(skip: true);
    await c.configureWifi(80, 2, 'Office-2G', 'password123');
    await c.online(skip: true);
    await c.finishWithoutPtu();
    await _settle();
  });
  await tester.pumpAndSettle();
  final s = container.read(commissionProvider);
  expect(s.step, 7, reason: 'done page');
  expect(s.ptuDeferred, isTrue);
  return container;
}

String? _rateLine(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('done-upload-rate'))).data;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepPoll, keepGap, keepBackendGap;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    keepPoll = directPollInterval;
    keepGap = connectRetryGap;
    keepBackendGap = backendRetryGap;
    directPollInterval = const Duration(milliseconds: 1);
    connectRetryGap = const Duration(milliseconds: 1);
    backendRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() {
    directPollInterval = keepPoll;
    connectRetryGap = keepGap;
    backendRetryGap = keepBackendGap;
  });

  group('build mode on connect', () {
    test('a gateway at 5 s is set to one reading a second, the connect '
        'goes on', () async {
      final fake = _DsGateway();
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 2);
      expect(fake.sent('set_config'), [_buildParams]);
      expect(buildModeParams, _buildParams);
      // Sent right after get_config, before the network check reads.
      expect(fake.indexOf('set_config'), fake.indexOf('get_config') + 1);
      expect(fake.config['ds_min_ms'], 1000);
      expect(fake.config['ds_max_ms'], 1000);
      expect(s.config['ds_min_ms'], 1000);
      expect(s.config['ds_max_ms'], 1000);
      expect(s.config['ds_enabled'], isTrue);
      expect(s.buildMode, BuildModeStatus.on);
      // No read-back: get_config once.
      expect(fake.sent('get_config'), hasLength(1));
      // Diagnostics: the interval and what the connect did.
      final diag = diagnosticSections(s, now: DateTime(2026, 9, 29));
      final gateway = diag['gateway'] as Map;
      expect(gateway['build_mode'], 'on');
      expect((gateway['config'] as Map)['ds_min_ms'], 1000);
      expect((gateway['config'] as Map)['ds_max_ms'], 1000);
      expect((gateway['config'] as Map)['ds_enabled'], isTrue);
    });

    test('ds_enabled off at 1000 / 1000 is sent too', () async {
      final fake = _DsGateway(min: 1000, max: 1000, enabled: false);
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      expect(fake.sent('set_config'), [_buildParams]);
      expect(container.read(commissionProvider).buildMode, BuildModeStatus.on);
    });

    for (final enabled in <Object>[true, 1]) {
      test('already 1000 / 1000 (ds_enabled $enabled): nothing sent', () async {
        final fake = _DsGateway(min: 1000, max: 1000, enabled: enabled);
        final (container, _) = await _connected(fake);
        addTearDown(container.dispose);
        final s = container.read(commissionProvider);
        expect(s.step, 2);
        expect(fake.sent('set_config'), isEmpty);
        expect(s.buildMode, BuildModeStatus.on);
      });
    }

    test('no ds_min_ms in get_config (older firmware, the demo): nothing '
        'sent', () async {
      final fake = _DsGateway(min: null, max: null, enabled: null);
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(fake.sent('set_config'), isEmpty);
      expect(s.buildMode, BuildModeStatus.off);
      expect(buildModeOn(DemoSystem().config), isNull);
    });

    test(
      'a refused key (`M rejected`): recorded, the connect goes on',
      () async {
        final fake = _DsGateway()
          ..buildAck = {
            'message': 'config updated: 0 params changed, 3 rejected (invalid)',
          };
        final (container, _) = await _connected(fake);
        addTearDown(container.dispose);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 2);
        expect(fake.buildSends, hasLength(1));
        expect(s.buildMode, BuildModeStatus.rejected);
        // What the gateway said it has, not what was asked.
        expect(s.config['ds_min_ms'], 5000);
        expect(fake.sent('get_config'), hasLength(1), reason: 'no read-back');
      },
    );

    test('OTP provisioned: not sent (the APP cannot sign it), recorded, '
        'the connect goes on', () async {
      final fake = _DsGateway()..config['otp_enabled'] = true;
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 2);
      expect(fake.sent('set_config'), isEmpty);
      expect(s.buildMode, BuildModeStatus.failed);
    });

    for (final (name, error) in [
      ('no answer (timeout)', const GatewayFailure('timeout')),
      (
        'a fail ack',
        const GatewayFailure(
          'otp_required',
          fromGateway: true,
          detail: 'otp_required',
        ),
      ),
      ('busy after the retries', const GatewayFailure('busy')),
    ]) {
      test('$name: recorded, not retried, the connect goes on', () async {
        final fake = _DsGateway()
          // busy: every try of [_commandBusy]'s own busy retries.
          ..buildErrors.addAll(
            List.filled(error.code == 'busy' ? 50 : 1, error),
          );
        final (container, _) = await _connected(fake);
        addTearDown(container.dispose);
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 2);
        expect(s.buildMode, BuildModeStatus.failed);
        expect(s.config['ds_min_ms'], 5000);
        // busy: [_commandBusy]'s own busy retries only, then given up.
        expect(
          fake.buildSends.length,
          error.code == 'busy' ? greaterThan(1) : 1,
        );
        final after = fake.buildSends.length;
        await _settle();
        expect(fake.buildSends, hasLength(after), reason: 'no retry later');
      });
    }

    test(
      'cancelled while it is sent: the connect stops (not swallowed)',
      () async {
        final fake = _DsGateway()..buildGate = Completer<void>();
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
          ],
        );
        addTearDown(container.dispose);
        final c = container.read(commissionProvider.notifier);
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        final connecting = c.connect(
          container.read(commissionProvider).peers.single,
        );
        for (
          var i = 0;
          i < 200 && !fake.ops.any((o) => o.$1 == 'get_config');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await c.cancel();
        fake.buildGate!.complete();
        await connecting;
        final s = container.read(commissionProvider);
        expect(s.step, isNot(2));
        expect(s.buildMode, isNot(BuildModeStatus.failed));
        // Nothing of the connect after the build-mode command.
        final at = fake.indexOf('set_config');
        expect(
          fake.ops.skip(at + 1).map((o) => o.$1),
          isNot(contains('get_net_status')),
        );
      },
    );

    test('a cancellation from the link is rethrown, never recorded as '
        'failed', () async {
      final fake = _DsGateway()
        ..buildErrors.add(const GatewayFailure('cancelled'));
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.step, isNot(2));
      expect(s.buildMode, isNot(BuildModeStatus.failed));
      expect(fake.sent('get_net_status'), isEmpty);
    });

    test('the phone link drops while it is sent: the connect reconnects and '
        'sends it again (the first never answered)', () async {
      final fake = _DsGateway()
        ..buildErrors.add(const GatewayFailure('disconnected'));
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 2);
      expect(fake.buildSends, hasLength(2));
      expect(s.buildMode, BuildModeStatus.on);
      expect(fake.config['ds_min_ms'], 1000);
    });

    test('once per connect: an answered attempt is not repeated when the '
        'link drops later in the same connect', () async {
      final fake = _DsGateway()
        ..buildAck = {'message': 'config updated: 0 params changed, 1 rejected'}
        ..dropNetReads = 1;
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 2);
      // Reconnected: get_config read again, still 5 s — not sent again.
      expect(fake.sent('get_config'), hasLength(2));
      expect(fake.buildSends, hasLength(1));
      expect(s.buildMode, BuildModeStatus.rejected);
    });

    test('once per connect: a new connect (the gateway back at 5 s) sends '
        'it again', () async {
      final fake = _DsGateway();
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      expect(fake.buildSends, hasLength(1));
      await c.cancel();
      // Same gateway, still 1000 / 1000: nothing to send.
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      expect(container.read(commissionProvider).step, 2);
      expect(fake.buildSends, hasLength(1));
      await c.cancel();
      // The back office has pushed its policy meanwhile.
      fake.config.addAll({'ds_min_ms': 5000, 'ds_max_ms': 5000});
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      expect(container.read(commissionProvider).step, 2);
      expect(fake.buildSends, hasLength(2));
    });

    test('a station in service (fleet_joined) gets it too', () async {
      final fake = _DsGateway(fleetJoined: true);
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.config['choose_station'], isTrue);
      expect(fake.sent('set_config'), [_buildParams]);
      expect(s.config['ds_min_ms'], 1000);
      expect(s.buildMode, BuildModeStatus.on);
    });
  });

  group('build mode on every re-commissioning path', () {
    test('〔重設 Wi-Fi〕 on a station: set before the Wi-Fi, once', () async {
      final fake = _DsGateway(fleetJoined: true)
        ..config['wifi_ssid'] = 'old-network';
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.chooseStation(newStation: false, wifiOnly: true);
      await c.configureWifi(80, 3, 'new-network', 'password123');
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.sent('set_wifi'), hasLength(1));
      expect(fake.buildSends, [_buildParams]);
      expect(
        fake.indexOf('set_config', (p) => p.containsKey('ds_min_ms')),
        lessThan(fake.indexOf('set_wifi')),
      );
    });

    test('〔更換 PTU〕 (r34, bound PTU gone): set on the connect, the binding '
        'cleared as before', () async {
      final fake = _BoundDsGateway(present: false);
      final (container, c) = await _connected(
        fake,
        topology: GatewayTopology.direct,
      );
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).ptuMissingMac, _ownPtu);
      await c.passNetworkCheck(skip: true);
      await c.replaceBoundPtu();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 4);
      expect(fake.sent('set_config').first, _buildParams);
      expect(fake.sent('set_config').last, {'direct_bind_mac': ''});
      expect(fake.buildSends, hasLength(1));
      expect(fake.sent('set_site_identity'), isEmpty);
    });

    test('〔配置下一台〕: the next gateway is set too', () async {
      final fake = _DsGateway();
      final (container, c) = await _starDone(fake);
      addTearDown(container.dispose);
      expect(fake.buildSends, hasLength(1));
      await c.finishDone(next: true);
      expect(container.read(commissionProvider).step, 1);
      fake.nextFactoryGateway();
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.config['suggested_site_id'], 1);
      expect(fake.buildSends, hasLength(2));
      expect(fake.buildSends.last, _buildParams);
      expect(s.buildMode, BuildModeStatus.on);
    });

    test('one-to-one step 7: build mode and max_connections 1 stay two '
        'separate set_configs', () async {
      final fake = _DsGateway(fleetJoined: true);
      final (container, c) = await _connected(
        fake,
        topology: GatewayTopology.direct,
      );
      addTearDown(container.dispose);
      await c.chooseStation(newStation: false);
      expect(container.read(commissionProvider).step, 4);
      expect(fake.sent('set_config').take(2).toList(), [
        _buildParams,
        {'max_connections': 1},
      ]);
      expect(fake.buildSends, hasLength(1));
    });

    test('the demo (no ds_*) never sends a build-mode set_config through a '
        'whole commissioning', () async {
      final fake = PickGateway()..config['fleet_joined'] = false;
      final (container, c) = await _connected(fake, offline: false);
      addTearDown(container.dispose);
      await c.configureWifi(1, 1, 'test-network', 'password123');
      await c.online();
      await c.discover();
      await c.configurePtus();
      await c.verify('https://example.invalid', '');
      expect(container.read(commissionProvider).step, 7);
      expect(
        fake
            .sent('set_config')
            .where((p) => p.keys.any((k) => k.startsWith('ds_'))),
        isEmpty,
      );
      expect(container.read(commissionProvider).buildMode, BuildModeStatus.off);
    });
  });

  group('done page: the upload interval line', () {
    test('uploadRateText: with and without the number', () {
      expect(uploadRateText(null), '資料上傳頻率由後台控制');
      expect(uploadRateText(5000), '資料上傳頻率由後台控制（目前每 5 秒）');
      expect(uploadRateText(1000), '資料上傳頻率由後台控制（目前每 1 秒）');
      expect(uploadRateText(20000), '資料上傳頻率由後台控制（目前每 20 秒）');
      expect(uploadRateText(1500), '資料上傳頻率由後台控制（目前每 1.5 秒）');
      for (final ms in [null, 5000, 1500]) {
        expect(uploadRateText(ms), isNot(contains('Gateway')));
        expect(uploadRateText(ms), isNot(contains('客戶')));
      }
      expect(uploadIntervalOf({'upload_interval_ms': 5000}), 5000);
      expect(uploadIntervalOf({'upload_interval_ms': 10000.0}), 10000);
      expect(uploadIntervalOf({'success': true}), isNull);
      expect(uploadIntervalOf({'upload_interval_ms': '5000'}), isNull);
      expect(uploadIntervalOf({'upload_interval_ms': 0}), isNull);
    });

    test('logged in: the back office policy is read once on the done page '
        '(not from the gateway)', () async {
      final fake = _DsGateway();
      final (container, _) = await _starDone(fake);
      addTearDown(container.dispose);
      expect(fake.policyReads, 1);
      final s = container.read(commissionProvider);
      expect(s.uploadIntervalMs, 5000);
      // The gateway is still in build mode; the line says the policy.
      expect(fake.config['ds_min_ms'], 1000);
    });

    for (final (name, error) in [
      (
        '404 (a back office without the route)',
        const GatewayFailure.http(
          status: 404,
          endpoint: _policyPath,
          detail: 'Not Found',
        ),
      ),
      ('unreachable', const GatewayFailure('network', detail: '逾時')),
    ]) {
      test('$name: no number, the done page as before', () async {
        final fake = _DsGateway()..policyError = error;
        final (container, _) = await _starDone(fake);
        addTearDown(container.dispose);
        final s = container.read(commissionProvider);
        expect(fake.policyReads, 1);
        expect(s.uploadIntervalMs, isNull);
        expect(s.error, isNull);
        expect(s.verified, isTrue);
      });
    }

    test(
      'never waited for: the done page is there before the answer',
      () async {
        final fake = _DsGateway()..policyGate = Completer<void>();
        final (container, _) = await _starDone(fake);
        addTearDown(container.dispose);
        var s = container.read(commissionProvider);
        expect(s.step, 7);
        expect(s.busy, isFalse);
        expect(s.uploadIntervalMs, isNull);
        fake.policyGate!.complete();
        await _settle();
        s = container.read(commissionProvider);
        expect(s.uploadIntervalMs, 5000);
      },
    );

    test('offline 〔先完成配置〕: not read; 〔登入並確認資料〕 reads it', () async {
      final fake = _DsGateway(rssi: const [-61, -72, -80]);
      final (container, c) = await _connected(
        fake,
        topology: GatewayTopology.direct,
      );
      addTearDown(container.dispose);
      await container
          .read(topologyProvider.notifier)
          .setDirectBindOnConfirm(true);
      await c.passNetworkCheck(skip: true);
      await c.configureWifi(80, 2, 'Office-2G', 'password123');
      await c.online(skip: true);
      await c.finishWithoutPtu();
      await _settle();
      var s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.ptuDeferred, isTrue);
      expect(fake.policyReads, 0);
      expect(s.uploadIntervalMs, isNull);
      await c.login('https://example.invalid');
      await _settle();
      s = container.read(commissionProvider);
      expect(s.loggedIn, isTrue);
      expect(fake.policyReads, 1);
      expect(s.uploadIntervalMs, 5000);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('star done page, font $scale: 「目前每 5 秒」 under the label '
          'card', (tester) async {
        _phone(tester, scale);
        await _pumpStarDone(tester, _DsGateway());
        expect(_rateLine(tester), '資料上傳頻率由後台控制（目前每 5 秒）');
        final label = tester.getRect(find.byKey(const Key('done-label')));
        final upload = tester.getRect(find.byKey(const Key('done-upload')));
        final rate = tester.getRect(find.byKey(const Key('done-upload-rate')));
        expect(rate.top, greaterThanOrEqualTo(label.bottom));
        expect(rate.top, greaterThanOrEqualTo(upload.bottom));
        // Inside the summary card.
        final summary = tester.getRect(find.byKey(const Key('done-summary')));
        expect(rate.bottom, lessThanOrEqualTo(summary.bottom));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('star done page, 404: 「資料上傳頻率由後台控制」 without a number', (
      tester,
    ) async {
      _phone(tester, 1.0);
      final fake = _DsGateway()
        ..policyError = const GatewayFailure.http(
          status: 404,
          endpoint: _policyPath,
          detail: 'Not Found',
        );
      await _pumpStarDone(tester, fake);
      expect(_rateLine(tester), '資料上傳頻率由後台控制');
      expect(_rateLine(tester), isNot(contains('秒')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('〔先完成配置〕 done page (offline, font 1.3): the line without '
        'a number', (tester) async {
      _phone(tester, 1.3);
      await _pumpDeferredDone(tester, _DsGateway(rssi: const [-61, -72, -80]));
      expect(_rateLine(tester), '資料上傳頻率由後台控制');
      expect(find.byKey(const Key('done-label')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
