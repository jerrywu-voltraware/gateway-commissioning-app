// Build38: moving an already configured gateway must not require its old
// Wi-Fi or PTU before replacing that PTU over the phone's local BLE link.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

const relocationOldPtu = 'AA:BB:CC:00:00:01';
const _newPtu = 'AA:BB:CC:00:00:02';

class RelocationGateway extends PickGateway {
  RelocationGateway() {
    config.addAll({
      'max_connections': 1,
      'direct_bind_mac': relocationOldPtu,
      'wifi_ssid': 'old-site-test-network',
    });
    wifiState = 'disconnected';
    mqttConnected = false;
    devices.removeWhere((row) => row['mac'] == relocationOldPtu);
  }

  bool apiUnavailable = true;
  bool bleUnavailable = false;
  bool failDiscovery = false;
  bool loseUnbindAck = false;
  bool ignoreUnbind = false;
  bool ignoreRestore = false;
  bool ignoreNewBind = false;
  bool changeIdentityOnNewBindReadback = false;
  int apiRequests = 0;
  bool unbound = false;

  @override
  Future<void> login(String base, String password) async {
    if (apiUnavailable) throw const GatewayFailure('network');
    return super.login(base, password);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    apiRequests++;
    if (apiUnavailable) throw const GatewayFailure('network');
    return super.request(method, path, body);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'get_config' &&
        changeIdentityOnNewBindReadback &&
        config['direct_bind_mac'] == _newPtu) {
      changeIdentityOnNewBindReadback = false;
      config['gateway_uid'] = 'AABBCCDDFE00';
      // Capture every operation after the device reveals a different identity.
      ops.clear();
    }
    if (bleUnavailable || (failDiscovery && unbound && op == 'get_status')) {
      ops.add((op, Map.of(params)));
      if (bleUnavailable) throw const GatewayFailure('disconnected');
      throw const GatewayFailure.gateway('test discovery rejected');
    }
    final bind = op == 'set_config' ? params['direct_bind_mac'] : null;
    if ((bind == '' && ignoreUnbind) ||
        (bind == relocationOldPtu && ignoreRestore) ||
        (bind == _newPtu && ignoreNewBind)) {
      ops.add((op, Map.of(params)));
      // Firmware may acknowledge a request whose individual field was rejected.
      return {'status': 'ok', 'message': 'direct_bind_mac rejected'};
    }
    final result = await super.command(op, params);
    if (bind == '') {
      unbound = true;
      if (loseUnbindAck) {
        loseUnbindAck = false;
        throw const GatewayFailure('timeout');
      }
    } else if (bind == relocationOldPtu) {
      unbound = false;
    }
    return result;
  }
}

ProviderContainer relocationContainer(RelocationGateway fake) =>
    ProviderContainer(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
      ],
    );

Future<(ProviderContainer, CommissioningController)> relocationConnected(
  RelocationGateway fake, {
  bool resetPreferences = true,
}) async {
  if (resetPreferences) SharedPreferences.setMockInitialValues({});
  final container = relocationContainer(fake);
  final topology = container.read(topologyProvider.notifier);
  await topology.ready;
  await topology.setTopology(GatewayTopology.direct);
  final controller = container.read(commissionProvider.notifier);
  await controller.prepare('https://example.invalid', '', offline: true);
  await controller.scan();
  await controller.connect(container.read(commissionProvider).peers.single);
  expect(container.read(commissionProvider).step, 2);
  expect(container.read(commissionProvider).ptuMissingMac, relocationOldPtu);
  return (container, controller);
}

Map<String, dynamic> _identityAndWifi(RelocationGateway fake) => {
  for (final key in ['site_id', 'gateway_id', 'gateway_uid', 'wifi_ssid'])
    key: fake.config[key],
};

void _noNetworkOrIdentityWrites(RelocationGateway fake, Map before) {
  expect(_identityAndWifi(fake), before);
  for (final op in ['set_wifi', 'set_site_identity', 'set_mqtt_target']) {
    expect(
      fake.sent(op),
      isEmpty,
      reason: '$op is not part of local replacement',
    );
  }
}

List<Map<String, dynamic>> _bindWrites(RelocationGateway fake) => fake
    .sent('set_config')
    .where((params) => params.containsKey('direct_bind_mac'))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Duration savedPoll;
  late List<Duration> savedRetryGaps;
  setUp(() {
    savedPoll = directPollInterval;
    savedRetryGaps = step7RetryGaps;
    directPollInterval = const Duration(milliseconds: 1);
    step7RetryGaps = const [Duration(milliseconds: 1)];
  });
  tearDown(() {
    directPollInterval = savedPoll;
    step7RetryGaps = savedRetryGaps;
  });

  for (final wifiForm in [false, true]) {
    test(
      'local replacement from ${wifiForm ? 'wifi_only form' : 'network check'} '
      'works without old Wi-Fi, old PTU or phone API',
      () async {
        final fake = RelocationGateway();
        final (container, c) = await relocationConnected(fake);
        addTearDown(container.dispose);
        final protected = _identityAndWifi(fake);
        if (wifiForm) {
          await c.startWifiFix();
          expect(
            container.read(commissionProvider).config['wifi_only'],
            isTrue,
          );
        }
        expect(container.read(commissionProvider).networkReady, isFalse);
        final apiBefore = fake.apiRequests;
        fake.ops.clear();
        await c.replaceBoundPtu();
        final state = container.read(commissionProvider);
        expect(state.error, isNull);
        expect(state.step, 4);
        expect(state.networkReady, isFalse);
        expect(state.verified, isFalse);
        expect(state.monitoringOk, isFalse);
        expect(state.tempRestoreMac, relocationOldPtu);
        expect(state.tempBoundMac, replacedBindMarker);
        expect(fake.config['direct_bind_mac'], '');
        expect(_bindWrites(fake), [
          {'direct_bind_mac': ''},
        ]);
        expect(fake.apiRequests, apiBefore);
        expect(fake.sent('assign_device_id'), isEmpty);
        expect(fake.sent('join_fleet'), isEmpty);
        _noNetworkOrIdentityWrites(fake, protected);
        await c.cancel();
        expect(fake.config['direct_bind_mac'], relocationOldPtu);
        expect(container.read(commissionProvider).tempRestoreMac, isNull);
        expect(container.read(commissionProvider).verified, isFalse);
      },
    );
  }

  final preflightFailures = <String, void Function(RelocationGateway)>{
    'BLE unavailable': (fake) => fake.bleUnavailable = true,
    'binding changed since confirmation': (fake) =>
        fake.config['direct_bind_mac'] = _newPtu,
    'gateway UID changed': (fake) =>
        fake.config['gateway_uid'] = 'AABBCCDDFE00',
    'station changed since connection': (fake) => fake.config['site_id'] = 81,
    'not configured': (fake) => fake.config['fleet_joined'] = false,
    'invalid station identity': (fake) => fake.config['site_id'] = 0,
    'invalid gateway identity': (fake) => fake.config['gateway_id'] = 0,
    'test mode': (fake) => fake.config['mode'] = 'test',
    'upload paused': (fake) => fake.config['upload_paused'] = true,
    'OTP enabled': (fake) => fake.config['otp_enabled'] = true,
  };
  for (final entry in preflightFailures.entries) {
    test(
      'fresh preflight ${entry.key}: no configuration write precedes refusal',
      () async {
        final fake = RelocationGateway();
        final (container, c) = await relocationConnected(fake);
        addTearDown(container.dispose);
        entry.value(fake);
        final boundBefore = fake.config['direct_bind_mac'];
        fake.ops.clear();
        await c.replaceBoundPtu();
        expect(fake.ops.where((entry) => entry.$1.startsWith('set_')), isEmpty);
        expect(fake.sent('join_fleet'), isEmpty);
        expect(fake.config['direct_bind_mac'], boundBefore);
        final state = container.read(commissionProvider);
        expect(state.step, 2);
        expect(state.error, isNotNull);
        expect(state.verified, isFalse);
        expect(state.tempBoundMac, isNull);
      },
    );
  }

  for (final failure in ['discovery failure', 'lost unbind ACK']) {
    test('$failure restores the old binding without the old PTU', () async {
      final fake = RelocationGateway();
      final (container, c) = await relocationConnected(fake);
      addTearDown(container.dispose);
      final protected = _identityAndWifi(fake);
      fake.failDiscovery = failure == 'discovery failure';
      fake.loseUnbindAck = failure == 'lost unbind ACK';
      fake.ops.clear();
      await c.replaceBoundPtu();
      final state = container.read(commissionProvider);
      expect(fake.config['direct_bind_mac'], relocationOldPtu);
      expect(_bindWrites(fake), [
        {'direct_bind_mac': ''},
        {'direct_bind_mac': relocationOldPtu},
      ]);
      expect(state.error, isNotNull);
      expect(state.verified, isFalse);
      expect(state.tempRestoreMac, isNull);
      expect(
        fake.devices.any((row) => row['mac'] == relocationOldPtu),
        isFalse,
      );
      _noNetworkOrIdentityWrites(fake, protected);
    });
  }

  test('ACK with rejected unbind field cannot start replacement', () async {
    final fake = RelocationGateway();
    final (container, c) = await relocationConnected(fake);
    addTearDown(container.dispose);
    fake.ignoreUnbind = true;
    await c.replaceBoundPtu();
    final state = container.read(commissionProvider);
    expect(fake.config['direct_bind_mac'], relocationOldPtu);
    expect(state.step, isNot(4));
    expect(state.error, isNotNull);
    expect(state.verified, isFalse);
    expect(fake.sent('assign_device_id'), isEmpty);
  });

  test(
    'cancel does not clear rollback until the gateway reads back old bind',
    () async {
      final fake = RelocationGateway();
      final (container, c) = await relocationConnected(fake);
      addTearDown(container.dispose);
      await c.replaceBoundPtu();
      expect(container.read(commissionProvider).step, 4);
      fake.ignoreRestore = true;
      await c.cancel();
      var state = container.read(commissionProvider);
      expect(fake.config['direct_bind_mac'], '');
      expect(state.tempRestoreMac, relocationOldPtu);
      expect(state.error, isNotNull);
      expect(state.verified, isFalse);
      fake.ignoreRestore = false;
      await c.cancel();
      state = container.read(commissionProvider);
      expect(fake.config['direct_bind_mac'], relocationOldPtu);
      expect(state.tempRestoreMac, isNull);
    },
  );

  test(
    'a dropped BLE during cancellation keeps recovery available for retry',
    () async {
      final fake = RelocationGateway();
      final (container, c) = await relocationConnected(fake);
      addTearDown(container.dispose);
      await c.replaceBoundPtu();
      fake.bleUnavailable = true;
      await c.cancel();
      expect(
        container.read(commissionProvider).tempRestoreMac,
        relocationOldPtu,
      );
      expect(container.read(commissionProvider).verified, isFalse);
      fake.bleUnavailable = false;
      await c.cancel();
      expect(fake.config['direct_bind_mac'], relocationOldPtu);
      expect(container.read(commissionProvider).tempRestoreMac, isNull);
    },
  );

  test('kill and resume retains recovery for the same gateway', () async {
    final fake = RelocationGateway();
    final (first, c) = await relocationConnected(fake);
    await c.replaceBoundPtu();
    expect(fake.config['direct_bind_mac'], '');
    expect(first.read(commissionProvider).tempRestoreMac, relocationOldPtu);
    first.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final resumed = relocationContainer(fake);
    addTearDown(resumed.dispose);
    await resumed.read(topologyProvider.notifier).ready;
    final next = resumed.read(commissionProvider.notifier);
    await next.restore();
    expect(
      next.savedResumeNeedsLogin,
      isFalse,
      reason: 'Recovery is local BLE even when the phone API is unavailable.',
    );
    await next.resumeSaved();
    expect(fake.config['direct_bind_mac'], relocationOldPtu);
    expect(resumed.read(commissionProvider).verified, isFalse);
  });

  test(
    'journal resume on a different gateway identity performs reads only',
    () async {
      final fake = RelocationGateway();
      final (first, c) = await relocationConnected(fake);
      await c.replaceBoundPtu();
      first.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.config['gateway_uid'] = 'AABBCCDDFE00';
      fake.ops.clear();
      final resumed = relocationContainer(fake);
      addTearDown(resumed.dispose);
      await resumed.read(topologyProvider.notifier).ready;
      final next = resumed.read(commissionProvider.notifier);
      await next.restore();
      expect(next.savedResumeNeedsLogin, isFalse);
      await next.resumeSaved();
      expect(
        fake.ops.where((op) => op.$1.startsWith('set_')),
        isEmpty,
        reason:
            'Even build-mode or BLE writes must follow identity validation.',
      );
      expect(fake.sent('join_fleet'), isEmpty);
      expect(fake.sent('assign_device_id'), isEmpty);
      expect(fake.config['direct_bind_mac'], '');
      expect(resumed.read(commissionProvider).error, isNotNull);
      expect(resumed.read(commissionProvider).verified, isFalse);
    },
  );

  for (final accepted in [true, false]) {
    test(
      'confirming the new PTU ${accepted ? 'commits only after readback' : 'restores on rejected bind'}',
      () async {
        final fake = RelocationGateway();
        final (container, c) = await relocationConnected(fake);
        addTearDown(container.dispose);
        await c.replaceBoundPtu();
        expect(container.read(commissionProvider).direct?.pickedMac, _newPtu);
        await c.identify();
        expect(container.read(commissionProvider).identifiedMac, _newPtu);
        fake.ignoreNewBind = !accepted;
        fake.ops.clear();
        await c.confirmDirectPick();
        final state = container.read(commissionProvider);
        expect(
          state.verified,
          isFalse,
          reason: 'Local binding is not backend data verification.',
        );
        final bindIndex = fake.indexOf(
          'set_config',
          (params) => params['direct_bind_mac'] == _newPtu,
        );
        expect(bindIndex, greaterThanOrEqualTo(0));
        expect(
          fake.ops.skip(bindIndex + 1).any((op) => op.$1 == 'get_config'),
          isTrue,
          reason: 'A successful ACK alone cannot commit the binding.',
        );
        if (accepted) {
          expect(fake.config['direct_bind_mac'], _newPtu);
          expect(state.tempRestoreMac, isNull);
          await c.cancel();
          expect(fake.config['direct_bind_mac'], _newPtu);
        } else {
          expect(state.error, isNotNull);
          expect(fake.config['direct_bind_mac'], relocationOldPtu);
          expect(state.tempRestoreMac, isNull);
        }
        expect(fake.sent('set_wifi'), isEmpty);
        expect(fake.sent('set_site_identity'), isEmpty);
      },
    );
  }

  test(
    'identity mismatch at confirmation blocks rollback and safe-stop writes',
    () async {
      final fake = RelocationGateway();
      final (container, c) = await relocationConnected(fake);
      addTearDown(container.dispose);
      await c.replaceBoundPtu();
      await c.identify();
      fake.changeIdentityOnNewBindReadback = true;
      await c.confirmDirectPick();
      var state = container.read(commissionProvider);
      expect(state.error, isNotNull);
      expect(state.verified, isFalse);
      expect(state.tempRestoreMac, relocationOldPtu);
      expect(fake.ops.where((op) => op.$1.startsWith('set_')), isEmpty);
      expect(fake.sent('join_fleet'), isEmpty);
      expect(fake.sent('assign_device_id'), isEmpty);
      fake.ops.clear();
      await c.cancel();
      state = container.read(commissionProvider);
      expect(state.tempRestoreMac, relocationOldPtu);
      expect(state.verified, isFalse);
      expect(fake.ops.where((op) => op.$1.startsWith('set_')), isEmpty);
      expect(fake.sent('join_fleet'), isEmpty);
      expect(fake.sent('assign_device_id'), isEmpty);
      expect(fake.config['direct_bind_mac'], _newPtu);
    },
  );

  test('Wi-Fi repair remains independent of the missing old PTU', () async {
    final fake = RelocationGateway();
    final (container, c) = await relocationConnected(fake);
    addTearDown(container.dispose);
    final identity = (fake.config['site_id'], fake.config['gateway_id']);
    fake.ops.clear();
    await c.startWifiFix();
    expect(container.read(commissionProvider).config['wifi_only'], isTrue);
    expect(_bindWrites(fake), isEmpty);
    await c.configureWifi(
      identity.$1 as int,
      identity.$2 as int,
      'new-site-test-network',
      'test-only-password',
    );
    expect(fake.sent('set_wifi'), hasLength(1));
    expect(fake.config['direct_bind_mac'], relocationOldPtu);
    expect(fake.sent('set_site_identity'), isEmpty);
    expect(fake.sent('set_mqtt_target'), isEmpty);
    expect(fake.devices.any((row) => row['mac'] == relocationOldPtu), isFalse);
    expect(container.read(commissionProvider).verified, isFalse);
  });
}
