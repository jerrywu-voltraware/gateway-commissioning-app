import 'dart:async';
import 'support/direct_pick_actions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/presentation/direct_mode_panel.dart';
import 'package:gateway_commissioning/presentation/gateway_discovery.dart';

const _newKeys = [
  'direct_autoconnect_supported',
  'identify_ptu_supported',
  'auto_connect_min_rssi',
  'direct_bind_mac',
];

class _LiveLink extends DemoSystem implements GatewayScanner {
  // 1.0.0+10: broadcast — the list listens again when its scan resumes
  // (after 〔辨識〕, or back from 「閘道器狀態」).
  final events = StreamController<List<GatewayPeer>>.broadcast();
  bool stopped = false;
  @override
  Stream<List<GatewayPeer>> scanLive() => events.stream;
  @override
  Future<void> stopScan() async {
    stopped = true;
  }
}

/// Gateway 3 of site 80 (range #11–#15) recording every command.
class DirectGateway extends DemoSystem {
  DirectGateway({bool newFirmware = true}) {
    config.addAll({'fleet_joined': true, 'site_id': 80, 'gateway_id': 3});
    if (!newFirmware) {
      for (final key in _newKeys) {
        config.remove(key);
      }
    }
  }
  final commands = <(String, Map<String, dynamic>)>[];

  List<Map<String, dynamic>> sent(String op) => [
    for (final (o, p) in commands)
      if (o == op) p,
  ];

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    commands.add((op, Map.of(params)));
    return super.command(op, params);
  }
}

Future<(ProviderContainer, CommissioningController)> _connect(
  DirectGateway fake, {
  bool toStep7 = true,
  GatewayTopology topology = GatewayTopology.direct,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  await container.read(topologyProvider.notifier).setTopology(topology);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  if (toStep7) await c.chooseStation(newStation: false);
  return (container, c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('direct mode assign', () {
    test('firmware 1.7.20 direct mode assigns #1 on gateway 3', () async {
      final fake = DirectGateway();
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      expect(container.read(commissionProvider).selected, hasLength(1));
      await c.configurePtus();
      expect(fake.sent('assign_device_id').map((p) => p['new_id']), [1]);
      expect(
        fake.sent('set_config').where((p) => p.containsKey('max_connections')),
        everyElement(containsPair('max_connections', 1)),
      );
    });

    test('older firmware keeps the gateway range (#11 on gateway 3)', () async {
      final fake = DirectGateway(newFirmware: false);
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      expect(fake.sent('assign_device_id').map((p) => p['new_id']), [11]);
      expect(container.read(commissionProvider).direct, isNull);
      expect(fake.sent('get_status'), isEmpty);
    });

    test('star mode is unchanged (range numbering)', () async {
      final fake = DirectGateway();
      final (container, c) = await _connect(
        fake,
        topology: GatewayTopology.star,
      );
      addTearDown(container.dispose);
      await c.configurePtus();
      expect(
        fake.sent('assign_device_id').map((p) => p['new_id']),
        everyElement(inInclusiveRange(11, 15)),
      );
      expect(container.read(commissionProvider).direct, isNull);
    });
  });

  group('direct status', () {
    test('parses state, threshold, binding and at most 5 candidates', () {
      final status = DirectStatus.from({
        'state': 'no_candidate',
        'min_rssi': -60,
        'bound_mac': '',
        'candidates': [
          for (int i = 0; i < 7; i++)
            {'mac': 'AA:$i', 'rssi_peak': -70 - i, 'device_number': 0},
        ],
      })!;
      expect(status.state, DirectState.noCandidate);
      expect(status.minRssi, -60);
      expect(status.boundMac, isNull);
      expect(status.candidates, hasLength(5));
      expect(DirectStatus.from(null), isNull);
      expect(DirectStatus.from({'state': 'unknown'}), isNull);
    });

    test('three hints: no_candidate / bound_missing / connected', () async {
      final fake = DirectGateway();
      for (final d in fake.devices) {
        d['rssi'] = -80;
      }
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      var direct = container.read(commissionProvider).direct!;
      expect(direct.state, DirectState.noCandidate);
      expect(direct.state.hint, contains('請靠近／確認同樁 PTU 已上電'));
      expect(direct.candidates, hasLength(3));

      fake.config['direct_bind_mac'] = 'FF:FF:FF:FF:FF:FF';
      await c.rescanPtus();
      direct = container.read(commissionProvider).direct!;
      expect(direct.state, DirectState.boundMissing);
      expect(direct.state.hint, contains('已綁定的 PTU 不在場'));

      fake.config['direct_bind_mac'] = '';
      // Round 15: the gateway connects by itself once a PTU is near enough.
      fake.devices.first['rssi'] = -40;
      await c.rescanPtus();
      direct = container.read(commissionProvider).direct!;
      expect(direct.state, DirectState.connected);
      expect(direct.state.hint, isNull);
    });

    testWidgets('panel shows state, hint, unbind and candidates', (
      tester,
    ) async {
      final fake = DirectGateway();
      fake.config['direct_bind_mac'] = 'FF:FF:FF:FF:FF:FF';
      late ProviderContainer container;
      late CommissioningController c;
      await tester.runAsync(() async {
        (container, c) = await _connect(fake);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DirectStatusPanel()),
            ),
          ),
        ),
      );
      expect(find.textContaining('已綁定的 PTU 不在場'), findsWidgets);
      expect(find.byKey(const Key('direct-unbind')), findsOneWidget);
      // Round 15: candidates only under 「改選其他 PTU」 / 「不是這台？」.
      await tapDirectAction(tester, 'direct-not-this');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('direct-candidate-AA:BB:CC:00:00:01')),
        findsOneWidget,
      );
      expect(find.textContaining('峰值 -40 dBm'), findsOneWidget);
      await tester.tap(find.byKey(const Key('direct-unbind')));
      await tester.runAsync(() async {
        for (
          int i = 0;
          i < 50 && container.read(commissionProvider).busy;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(fake.sent('set_config').last, {'direct_bind_mac': ''});
      // Round 15: unbound, the gateway connects the nearest PTU by itself.
      expect(c.directConnectedMac, 'AA:BB:CC:00:00:01');
    });
  });

  group('direct settings', () {
    test('threshold and binding are sent with set_config', () async {
      final fake = DirectGateway();
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      expect(directMinRssiOf(container.read(commissionProvider).config), -55);
      await c.setDirectMinRssi(-70);
      expect(fake.sent('set_config').last, {'auto_connect_min_rssi': -70});
      expect(directMinRssiOf(container.read(commissionProvider).config), -70);
      await c.setDirectMinRssi(-5);
      expect(fake.sent('set_config').last, {'auto_connect_min_rssi': -20});

      // Nothing connected yet: binding is refused without a command.
      final before = fake.sent('set_config').length;
      await c.setDirectBind(true);
      expect(fake.sent('set_config'), hasLength(before));
      expect(container.read(commissionProvider).error, contains('無法綁定'));

      // Round 15: back to a threshold the demo PTU passes; the gateway
      // connects it by itself.
      await c.setDirectMinRssi(-55);
      await c.rescanPtus();
      final mac = c.directConnectedMac;
      expect(mac, isNotNull);
      await c.setDirectBind(true);
      expect(fake.sent('set_config').last, {'direct_bind_mac': mac});
      expect(directBoundMacOf(container.read(commissionProvider).config), mac);
      await c.setDirectBind(false);
      expect(fake.sent('set_config').last, {'direct_bind_mac': ''});
    });

    test('older firmware: no set_config, clear error', () async {
      final fake = DirectGateway(newFirmware: false);
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      await c.setDirectMinRssi(-70);
      expect(fake.sent('set_config'), isEmpty);
      expect(container.read(commissionProvider).error, contains('1.7.20'));
    });
  });

  group('identify', () {
    test('sends target both and shows the acked PTU', () async {
      final fake = DirectGateway();
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.identify();
      expect(fake.sent('identify').last, {'target': 'both', 'duration_ms': 4000});
      final message = container.read(commissionProvider).message;
      expect(message, contains('AA:BB:CC:00:00:01'));
      expect(message, contains('-40 dBm'));
      expect(message, contains('已送出'));
      await c.identify(target: 'ptu');
      expect(fake.sent('identify').last, {'target': 'ptu', 'duration_ms': 4000});
    });

    test(
      'target=both, no PTU connected: gateway LED still blinks, ack ok '
      'with ptu_write text (firmware 1.7.20 does not fail the whole ack)',
      () async {
        final fake = DirectGateway();
        final (container, c) = await _connect(fake, toStep7: false);
        addTearDown(container.dispose);
        await c.identify();
        // Single ack, no fallback resend: target=both never failed.
        expect(fake.sent('identify'), [
          {'target': 'both', 'duration_ms': 4000},
        ]);
        final state = container.read(commissionProvider);
        expect(state.error, isNull);
        expect(state.message, identifyPtuFailedText('not_connected'));
        expect(state.message, contains('閘道器正在閃燈'));
        expect(state.peer, isNotNull);
      },
    );

    test('target=ptu, no PTU connected: fails outright (no LED fallback)', () async {
      final fake = DirectGateway();
      final (container, c) = await _connect(fake, toStep7: false);
      addTearDown(container.dispose);
      await c.identify(target: 'ptu');
      // A single failed ack; target=ptu does not fall back to blinking the
      // gateway only (that fallback is target=both-specific).
      expect(fake.sent('identify'), [
        {'target': 'ptu', 'duration_ms': 4000},
      ]);
      final state = container.read(commissionProvider);
      expect(state.error, contains('尚未連上 PTU'));
      // Never mistaken for a phone link loss.
      expect(state.uploadWatch, isNot(UploadWatch.linkLost));
    });

    test('target=both with a connected PTU: ack ok, ptu_write ok text', () async {
      final fake = DirectGateway();
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.identify();
      expect(fake.sent('identify').last, {'target': 'both', 'duration_ms': 4000});
      final message = container.read(commissionProvider).message;
      expect(message, contains('已送出'));
      expect(message, contains('AA:BB:CC:00:00:01'));
      expect(message, contains('-40 dBm'));
    });

    test(
      'direct comes from get_status only; get_ble_devices never carries it',
      () async {
        final fake = DirectGateway();
        final (container, c) = await _connect(fake);
        addTearDown(container.dispose);
        // get_ble_devices itself must not report `direct` (only get_status
        // does per cmd_contract.md's identify section).
        final devicesAck = await fake.command('get_ble_devices');
        expect(devicesAck.containsKey('direct'), isFalse);
        // _absorbDirect still populates it, by reading get_status instead.
        expect(container.read(commissionProvider).direct, isNotNull);
        expect(fake.sent('get_status'), isNotEmpty);
      },
    );

    test('older firmware: bare identify, old text', () async {
      final fake = DirectGateway(newFirmware: false);
      final (container, c) = await _connect(fake, toStep7: false);
      addTearDown(container.dispose);
      // Pre-PTU firmware takes only its fixed six seconds (the APP default
      // 4 is refused; see identify_seconds_test), so pick 6 here.
      await container.read(topologyProvider.notifier).setIdentifySeconds(6);
      await c.identify();
      expect(fake.sent('identify'), [<String, dynamic>{}]);
      expect(container.read(commissionProvider).message, contains('雙閃'));
    });

    test('ambiguous_target / write_failed have their own text', () {
      expect(
        const GatewayFailure.gateway('ambiguous_target').message,
        contains('多台 PTU'),
      );
      expect(
        const GatewayFailure.gateway('write_failed').message,
        contains('寫入 PTU 失敗'),
      );
    });

    test('ack text', () {
      expect(
        identifyAckText({
          'mac': 'AA:01',
          'rssi': -33,
          'device_number': 1,
          'duration_ms': 6000,
          'ptu_confirmed': false,
        }),
        allOf(
          contains('AA:01'),
          contains('-33 dBm'),
          contains('#1'),
          contains('已送出'),
        ),
      );
    });

    test('ptu_write failed text names the reason, without resending', () {
      // Round 24: the reason in words, never the raw code.
      expect(
        identifyPtuFailedText('not_connected'),
        allOf(
          contains('閘道器正在閃燈'),
          contains('尚未連上 PTU'),
          isNot(contains('not_connected')),
        ),
      );
    });
  });

  testWidgets('gateway list row 「辨識」: selection keeps scanning; explicit '
      'connect holds the link before its bulb calls onIdentify', (
    tester,
  ) async {
    final link = _LiveLink();
    addTearDown(link.events.close);
    GatewayPeer? identified;
    var connected = false;
    var holdCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [linkProvider.overrideWithValue(link)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GatewayDiscovery(
                enabled: true,
                onConnect: (peer) async => connected = true,
                onIdentify: (peer) async {
                  identified = peer;
                  return true;
                },
                onHold: (_) async {
                  holdCalls++;
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
    }

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    link.events.add([const GatewayPeer('AA:BB', 'GIOS-S1-GW01', -42)]);
    await tester.pump();
    // 1.0.0+22: the bulb is on the selected card once its link is up.
    expect(find.byKey(const ValueKey('identify-AA:BB')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('AA:BB')));
    await settle();
    expect(link.stopped, isFalse);
    expect(holdCalls, 0);
    expect(identified, isNull);
    expect(connected, isFalse);
    expect(find.byKey(const ValueKey('identify-AA:BB')), findsNothing);
    await tester.tap(find.byKey(const Key('gateway-link-identify')));
    await settle();
    expect(link.stopped, isTrue);
    expect(holdCalls, 1);
    expect(identified, isNull);
    await tester.tap(find.byKey(const ValueKey('identify-AA:BB')));
    await settle();
    expect(identified?.id, 'AA:BB');
    expect(connected, isFalse);
  });
}
