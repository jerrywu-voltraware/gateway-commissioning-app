// 09-28: field staff never type a backend password. The build carries the
// backend credential (`APP_BACKEND_KEY`, injected by tools/build_apk.ps1
// from the git-ignored .secrets/<env>.env); the APP exchanges it for a
// session token at POST /api/auth/app-login and caches the token as before.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/backend_key.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/dashboard_api.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';

const _key = 'build-key-0928';

/// A backend that records each login and can refuse the next [refuse]
/// requests (401), with a restorable saved session.
class _KeyBackend extends DemoSystem implements SessionStore {
  final logins = <(String, String)>[];
  int refuse = 0;

  @override
  Future<bool> restoreSession(String base) async => true;

  @override
  Future<void> login(String base, String password) async {
    logins.add((base, password));
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (refuse > 0) {
      refuse--;
      throw const GatewayFailure('authentication');
    }
    return super.request(method, path, body);
  }
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

ProviderContainer _container(_KeyBackend fake, String key) {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      backendKeyProvider.overrideWithValue(key),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardApi', () {
    late HttpOverrides? saved;
    setUp(() {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() => HttpOverrides.global = saved);

    test('exchanges the build credential at /api/auth/app-login and caches '
        'the token, never the credential', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final seen = <String>[];
      Map<String, dynamic>? loginBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seen.add('${req.method} ${req.uri.path}');
        if (req.uri.path == '/api/auth/app-login') {
          loginBody =
              jsonDecode(await utf8.decoder.bind(req).join())
                  as Map<String, dynamic>;
          req.response.write(jsonEncode({'api_key': 'token-1'}));
        } else if (req.headers.value('X-API-Key') == 'token-1') {
          req.response.write(jsonEncode({'ok': true}));
        } else {
          req.response.statusCode = 401;
        }
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';

      await DashboardApi().login(base, _key);
      expect(seen, ['POST /api/auth/app-login']);
      expect(loginBody, {'app_key': _key});
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.values.join(), isNot(contains(_key)));
      expect(stored.values.join(), contains('token-1'));

      final next = DashboardApi();
      expect(await next.restoreSession(base), isTrue);
      expect(await next.request('GET', '/api/latest'), {'ok': true});
    });

    test('a build without a credential says so and sends nothing', () async {
      FlutterSecureStorage.setMockInitialValues({});
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        requests++;
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      await expectLater(
        DashboardApi().login('http://127.0.0.1:${server.port}', ''),
        throwsA(
          isA<GatewayFailure>().having(
            (e) => e.code,
            'code',
            'missing_backend_key',
          ),
        ),
      );
      expect(requests, 0);
    });
  });

  test('the missing credential reads as such and maps to BACKEND_AUTH', () {
    const failure = GatewayFailure('missing_backend_key');
    expect(failure.message, missingBackendKeyText);
    expect(missingBackendKeyText, '此建置缺少後台憑證，請重新建置');
    expect(
      rescueCodeOf(failure, rebooted: false, safe: null, ctlStep: 0),
      RescueCode.backendAuth,
    );
    expect(
      const GatewayFailure('authentication').message,
      isNot(contains('輸入')),
      reason: 'there is nothing to type any more',
    );
  });

  group('controller', () {
    test('檢查並開始 logs in with the build credential', () async {
      final fake = _KeyBackend();
      final container = _container(fake, _key);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('http://192.168.0.12:18000', '');
      expect(container.read(commissionProvider).loggedIn, isTrue);
      expect(fake.logins, [('http://192.168.0.12:18000', _key)]);
    });

    test(
      'a refused restored token is renewed with the build credential',
      () async {
        final fake = _KeyBackend()..refuse = 1;
        final container = _container(fake, _key);
        final c = container.read(commissionProvider.notifier);
        const base = 'https://example.invalid';
        expect(await c.restoreSession(base), isTrue);
        await c.refreshHealth();
        expect(fake.logins, [(base, _key)]);
        expect(fake.refuse, 0);
        expect(container.read(commissionProvider).loggedIn, isTrue);
      },
    );

    test('without a credential a refused token is not retried', () async {
      final fake = _KeyBackend()..refuse = 1;
      final container = _container(fake, '');
      final c = container.read(commissionProvider.notifier);
      expect(await c.restoreSession('https://example.invalid'), isTrue);
      await c.refreshHealth();
      expect(fake.logins, isEmpty);
    });
  });

  testWidgets('start page: no password field, no test password, no warning '
      'when the build carries a credential', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final env in ['local', 'production']) {
      SharedPreferences.setMockInitialValues({
        'backend_environment': env,
        'backend_local_url': 'http://192.168.1.50:18000',
      });
      final fake = _KeyBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
            backendKeyProvider.overrideWithValue(_key),
            localBackendProberProvider.overrideWithValue(_Prober()),
            phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('密碼'), findsNothing, reason: env);
      expect(find.byKey(const Key('missing-backend-key')), findsNothing);
      expect(find.text('檢查並開始'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
