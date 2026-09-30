import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';

import 'network_check_test.dart' show WifiGateway;

class _ProvisionGateway extends WifiGateway implements SessionStore {
  final events = <String>[];
  final reservations = <String>[];
  GatewayFailure? reserveFailure;
  GatewayFailure? loginFailure;
  bool savedSession = false;
  bool accountReady = false;
  bool failReconnect = false;
  bool identityWritten = false;
  bool archived = false;

  @override
  Future<bool> restoreSession(String base) async {
    events.add('restore-session');
    return savedSession;
  }

  @override
  Future<void> login(String base, String password) async {
    events.add('login');
    if (loginFailure case final failure?) throw failure;
    return super.login(base, password);
  }

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    if (failReconnect && identityWritten) {
      throw const GatewayFailure('disconnected');
    }
    return super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (op == 'set_site_identity') {
      if (!accountReady) {
        throw StateError('Identity written before provisioning');
      }
      identityWritten = true;
    }
    events.add('BLE $op');
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path.contains('/reserve-identity')) {
      events.add('reserve');
      reservations.add(path);
      if (reserveFailure case final failure?) throw failure;
      accountReady = true;
      return {'ok': true};
    }
    if (path.endsWith('/check-identity')) {
      return {
        'exists': archived,
        'archived': archived,
        'last_seen_mac': archived ? config['gateway_uid'] : null,
      };
    }
    if (path.endsWith('/restore')) {
      events.add('restore-identity');
      archived = false;
      return {'success': true};
    }
    return super.request(method, path, body);
  }
}

Future<(ProviderContainer, CommissioningController)> _connect(
  _ProvisionGateway fake, {
  bool offline = false,
}) async {
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      backendKeyProvider.overrideWithValue('unit-test-login'),
    ],
  );
  await container.read(backendEnvProvider.notifier).ready;
  final c = container.read(commissionProvider.notifier);
  await c.prepare(
    container.read(backendEnvProvider).base,
    '',
    offline: offline,
  );
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  expect(container.read(commissionProvider).error, isNull);
  fake.events.clear();
  return (container, c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final site in [199, 65535]) {
    test(
      'site $site reserves its exact account before changing identity',
      () async {
        final fake = _ProvisionGateway();
        final (container, c) = await _connect(fake);
        addTearDown(container.dispose);

        await c.configureWifi(site, 1, 'Commissioning-2G', 'unit-test-wifi');

        expect(container.read(commissionProvider).error, isNull);
        expect(container.read(commissionProvider).step, 3);
        expect(fake.config['site_id'], site);
        expect(fake.reservations, hasLength(1));
        expect(fake.reservations.single, startsWith('/api/gateways/$site/1/'));
        expect(
          fake.events.indexOf('reserve'),
          lessThan(fake.events.indexOf('BLE set_site_identity')),
        );
        expect(
          fake.events.indexOf('reserve'),
          lessThan(fake.events.indexOf('BLE set_wifi')),
        );
        expect(fake.events, isNot(contains('login')));
      },
    );
  }

  for (final failure in [
    const GatewayFailure.http(
      status: 503,
      endpoint: 'POST /api/gateways/199/1/reserve-identity',
      detail: 'mqtt_account_unavailable',
    ),
    const GatewayFailure.network(
      endpoint: 'POST /api/gateways/199/1/reserve-identity',
      detail: '逾時',
    ),
  ]) {
    test(
      'reservation ${failure.code} ${failure.status} leaves gateway unchanged and retries',
      () async {
        final fake = _ProvisionGateway()..reserveFailure = failure;
        final (container, c) = await _connect(fake);
        addTearDown(container.dispose);
        final originalSite = fake.config['site_id'];

        await c.configureWifi(199, 1, 'Commissioning-2G', 'unit-test-wifi');

        expect(container.read(commissionProvider).error, isNotNull);
        expect(container.read(commissionProvider).step, 2);
        expect(fake.config['site_id'], originalSite);
        expect(fake.count('set_site_identity'), 0);
        expect(fake.count('set_wifi'), 0);
        expect(c.pendingReplace, isFalse);

        fake.reserveFailure = null;
        await c.configureWifi(199, 1, 'Commissioning-2G', 'unit-test-wifi');

        expect(container.read(commissionProvider).error, isNull);
        expect(fake.reservations, hasLength(2));
        expect(fake.count('set_site_identity'), 1);
        expect(fake.config['site_id'], 199);
      },
    );
  }

  for (final restore in [false, true]) {
    test(
      'offline setup ${restore ? 'restores session' : 'logs in automatically'} before reservation',
      () async {
        final fake = _ProvisionGateway()..savedSession = restore;
        final (container, c) = await _connect(fake, offline: true);
        addTearDown(container.dispose);

        await c.configureWifi(199, 1, 'Commissioning-2G', 'unit-test-wifi');

        expect(container.read(commissionProvider).error, isNull);
        expect(container.read(commissionProvider).loggedIn, isTrue);
        expect(
          fake.events.indexOf('restore-session'),
          lessThan(fake.events.indexOf('reserve')),
        );
        expect(fake.events.where((e) => e == 'login').length, restore ? 0 : 1);
        if (!restore) {
          expect(
            fake.events.indexOf('login'),
            lessThan(fake.events.indexOf('reserve')),
          );
        }
      },
    );
  }

  test(
    'automatic login failure makes no reservation or device changes; retry works',
    () async {
      final fake = _ProvisionGateway()
        ..loginFailure = const GatewayFailure('authentication');
      final (container, c) = await _connect(fake, offline: true);
      addTearDown(container.dispose);

      await c.configureWifi(199, 1, 'Commissioning-2G', 'unit-test-wifi');

      expect(container.read(commissionProvider).error, contains('登入失敗'));
      expect(fake.reservations, isEmpty);
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('set_wifi'), 0);

      fake.loginFailure = null;
      await c.configureWifi(199, 1, 'Commissioning-2G', 'unit-test-wifi');
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.config['site_id'], 199);
    },
  );

  test(
    'replacement provisioning failure is retryable and does not claim the identity changed',
    () async {
      final fake = _ProvisionGateway()
        ..reserveFailure = const GatewayFailure.http(
          status: 503,
          endpoint: 'POST /api/gateways/199/1/reserve-identity',
        );
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);

      await c.configureWifi(
        199,
        1,
        'Commissioning-2G',
        'unit-test-wifi',
        replaceExisting: true,
      );
      expect(fake.reservations.single, contains('force_replace=true'));
      expect(container.read(commissionProvider).error, contains('503'));
      expect(c.pendingReplace, isFalse);
      expect(fake.count('set_site_identity'), 0);
      expect(fake.count('set_wifi'), 0);

      fake.reserveFailure = null;
      await c.configureWifi(
        199,
        1,
        'Commissioning-2G',
        'unit-test-wifi',
        replaceExisting: true,
      );
      expect(container.read(commissionProvider).error, isNull);
      expect(
        fake.events.indexOf('reserve'),
        lessThan(fake.events.indexOf('BLE set_site_identity')),
      );
    },
  );

  test(
    'reconnect failure after provisioning can resume on the same identity',
    () async {
      final fake = _ProvisionGateway()..failReconnect = true;
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);

      await c.configureWifi(199, 1, 'Commissioning-2G', 'unit-test-wifi');
      expect(container.read(commissionProvider).error, isNotNull);
      expect(fake.accountReady, isTrue);
      expect(fake.config['site_id'], 199);
      expect(fake.count('set_site_identity'), 1);

      fake.failReconnect = false;
      await c.connect(container.read(commissionProvider).peer!);
      await c.configureWifi(199, 1, 'Commissioning-2G', 'unit-test-wifi');
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.count('set_site_identity'), 1);
      expect(fake.reservations, hasLength(2));
    },
  );

  for (final joined in [false, true]) {
    test(
      '${joined ? 'station Wi-Fi-only' : 'Wi-Fi-first'} never requires account login',
      () async {
        final fake = _ProvisionGateway()
          ..config['fleet_joined'] = joined
          ..loginFailure = const GatewayFailure('authentication');
        final (container, c) = await _connect(fake, offline: true);
        addTearDown(container.dispose);
        await c.startWifiFix();
        if (joined) {
          await c.configureWifi(
            c.site,
            c.gateway,
            'Commissioning-2G',
            'unit-test-wifi',
          );
        } else {
          await c.configureWifiFirst('Commissioning-2G', 'unit-test-wifi');
        }

        expect(container.read(commissionProvider).error, isNull);
        expect(fake.events, isNot(contains('login')));
        expect(fake.reservations, isEmpty);
        expect(fake.count('set_site_identity'), 0);
        expect(fake.count('set_wifi'), 1);
      },
    );
  }

  test(
    'online check provisions an older offline identity, retaining retry after login succeeds',
    () async {
      final fake = _ProvisionGateway()
        ..config['site_id'] = 199
        ..reserveFailure = const GatewayFailure.http(
          status: 503,
          endpoint: 'POST /api/gateways/199/1/reserve-identity',
        );
      final (container, c) = await _connect(fake, offline: true);
      addTearDown(container.dispose);

      await c.online(base: container.read(backendEnvProvider).base);
      expect(container.read(commissionProvider).error, contains('503'));
      expect(fake.reservations, hasLength(1));
      expect(fake.count('heartbeat_boost'), 0);
      expect(fake.count('set_site_identity'), 0);

      fake.reserveFailure = null;
      await c.online(base: container.read(backendEnvProvider).base);
      expect(container.read(commissionProvider).error, isNull);
      expect(fake.reservations, hasLength(2));
      expect(fake.accountReady, isTrue);
      expect(fake.count('set_site_identity'), 0);
    },
  );

  test(
    'online account recovery does not reserve an archived identity automatically',
    () async {
      final fake = _ProvisionGateway()..archived = true;
      final (container, c) = await _connect(fake, offline: true);
      addTearDown(container.dispose);

      await c.online(base: container.read(backendEnvProvider).base);

      expect(fake.reservations, isEmpty);
      expect(fake.count('set_site_identity'), 0);
    },
  );

  test(
    'archived rejoin provisions first and a failure leaves it archived',
    () async {
      final fake = _ProvisionGateway()
        ..archived = true
        ..reserveFailure = const GatewayFailure.http(
          status: 503,
          endpoint: 'POST /api/gateways/199/1/reserve-identity',
        );
      final (container, c) = await _connect(fake);
      addTearDown(container.dispose);

      expect(await c.rejoinIdentity(199, 1), isFalse);
      expect(fake.archived, isTrue);
      expect(fake.events, isNot(contains('restore-identity')));
      expect(fake.count('set_site_identity'), 0);

      fake.reserveFailure = null;
      fake.events.clear();
      expect(await c.rejoinIdentity(199, 1), isTrue);
      expect(fake.archived, isFalse);
      expect(
        fake.events.indexOf('reserve'),
        lessThan(fake.events.indexOf('restore-identity')),
      );
    },
  );
}
