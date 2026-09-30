// Round 13 fixes:
// 1. A step 8 phone-gateway drop reconnects by itself, with the same
//    automatic reconnect as step 7 (one shared `_autoRelink`): the gateway
//    is reconciled and only the rest is assigned; meanwhile the button is a
//    disabled 「重新連線中…」, and 「重新連線並繼續」 is tappable only after
//    the reconnect gave up.
// 2. Step 9 retries a backend that answers 5xx, cannot be reached or times
//    out (「後端暫時無回應，自動重試中（n）」) and keeps the per-PTU progress;
//    after the retry window 「重試」 continues it.
// 3. While the automatic reconnect runs the status card and the rescan
//    button say 「正在自動重新連線…」 instead of asking for a tap.
// 4. A backend session dropped by the backend (401, e.g. after a restart)
//    is renewed once with the stored password; a failed login never empties
//    the password field.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';

import 'link_loss_test.dart' show DroppingLink, pumpApp, ready;

/// Drops the phone link at each assign count in [dropsAt] (once each); a
/// [connectGate] holds every reconnect until completed.
class Round13Link extends DroppingLink {
  final dropsAt = <int>[];

  /// Drops at every assign of this MAC (the loss recurs without progress).
  String? alwaysDropAt;
  Completer<void>? connectGate;
  Completer<void>? assignGate;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    await connectGate?.future;
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (!down && op == 'assign_device_id') {
      await assignGate?.future;
      if (dropsAt.isNotEmpty && assigns.length == dropsAt.first) {
        dropsAt.removeAt(0);
        down = true;
        throw const GatewayFailure('not_connected');
      }
      if (params['mac'] == alwaysDropAt) {
        down = true;
        throw const GatewayFailure('disconnected');
      }
    }
    return super.command(op, params);
  }

  // ---- backend ----

  /// /api/latest answers 502 from this call number on (1-based), while
  /// [recovered] is false; null = never.
  int? failLatestFrom;

  /// /api/latest answers 502 only for these call numbers.
  final failLatestAt = <int>{};
  bool recovered = false;
  int latestCalls = 0, latestOk = 0;

  /// verify-installation answers this HTTP status (a final 4xx).
  int? installStatus;

  /// The next backend request answers 401 (session dropped by a restart).
  bool expireNext = false;

  /// Logins with this password are refused (after the first one).
  String? refuse;
  final logins = <String>[];

  @override
  Future<void> login(String base, String password) async {
    if (logins.isNotEmpty && password == refuse) {
      logins.add(password);
      throw const GatewayFailure('authentication');
    }
    logins.add(password);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final status = installStatus;
    if (status != null && path.contains('verify-installation')) {
      throw GatewayFailure.http(
        status: status,
        endpoint: '$method /api/gateways/1/1/verify-installation',
      );
    }
    if (path.startsWith('/api/latest')) {
      latestCalls++;
      final from = failLatestFrom;
      if ((from != null && latestCalls >= from && !recovered) ||
          failLatestAt.contains(latestCalls)) {
        throw GatewayFailure.http(
          status: 502,
          endpoint: '$method /api/latest',
          backend: '本機後端',
        );
      }
      if (expireNext) {
        expireNext = false;
        throw const GatewayFailure('authentication');
      }
      latestOk++;
    }
    return super.request(method, path, body);
  }
}

/// Alternates real waits (the link and backend fakes) and frames.
Future<void> settle(
  WidgetTester tester,
  ProviderContainer container,
  bool Function(CommissionState) done,
) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 1));
    if (done(container.read(commissionProvider))) return;
  }
}

Future<(ProviderContainer, CommissioningController)> atStep9(
  Round13Link fake, {
  String password = 'pw1',
}) async {
  final (container, c) = await ready(fake);
  await c.configurePtus();
  expect(container.read(commissionProvider).step, 6);
  // ready() logged in with an empty password: log in with a real one.
  c.backendChanged('https://other.invalid');
  await c.login('https://example.invalid', password);
  return (container, c);
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200, version: '1.1.0');
}

class _BluetoothOffLink extends Round13Link {
  bool bluetoothOff = true;
  @override
  Future<void> prepare() async {
    if (bluetoothOff) throw const GatewayFailure('bluetooth_off');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepGap, keepPersistence, keepRetryGap, keepRetryWindow;
  setUp(() {
    keepGap = connectRetryGap;
    keepPersistence = connectPersistence;
    keepRetryGap = backendRetryGap;
    keepRetryWindow = backendRetryWindow;
    connectRetryGap = const Duration(milliseconds: 1);
    backendRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() {
    connectRetryGap = keepGap;
    connectPersistence = keepPersistence;
    backendRetryGap = keepRetryGap;
    backendRetryWindow = keepRetryWindow;
  });

  group('1. step 8 link loss reconnects by itself', () {
    test('reconnects, reconciles and assigns only the rest, no tap', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      final connects = fake.connects;
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      fake.dropsAt.add(1);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(s.resumePending, isFalse);
      expect(s.relinking, isFalse);
      expect(fake.connects, connects + 1);
      // The first PTU was not re-sent; the gateway was read first.
      expect(fake.assigns, macs);
      expect(fake.commands, contains('get_ble_devices'));
      expect(states.where((x) => x.relinking), isNotEmpty);
      // Never a tappable 「重新連線並繼續」 while it reconnects by itself.
      for (final x in states) {
        expect(
          configureLabel(x).startsWith('重新連線並繼續'),
          isFalse,
          reason: 'busy=${x.busy} relinking=${x.relinking} ${x.message}',
        );
      }
    });

    test('a new loss after progress starts another round', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      final connects = fake.connects;
      fake.dropsAt.addAll([1, 2]);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.connects, connects + 2);
      expect(fake.assigns, macs);
    });

    test('a loss that recurs without progress is not chased', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final macs = fake.devices.map((d) => d['mac'].toString()).toList();
      final connects = fake.connects;
      fake.alwaysDropAt = macs[1];
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(fake.connects, connects + 1);
      expect(s.busy, isFalse);
      expect(s.relinking, isFalse);
      expect(s.resumePending, isTrue);
      expect(configureLabel(s), '重新連線並繼續（剩 2 台）');
    });

    test('gives up after the reconnect window: then 重新連線並繼續', () async {
      connectPersistence = const Duration(milliseconds: 80);
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      fake.dropsAt.add(1);
      fake.failConnect = true;
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.relinking, isFalse);
      expect(s.reconnectFailed, isTrue);
      expect(s.resumePending, isTrue);
      expect(s.error, startsWith('重新連線失敗（已嘗試 '));
      expect(configureLabel(s), '重新連線並繼續（剩 2 台）');
      expect(states.where((x) => x.relinking), isNotEmpty);
      // The manual label shows only once the automatic reconnect gave up.
      final manual = states.firstWhere(
        (x) => configureLabel(x).startsWith('重新連線並繼續'),
      );
      expect(manual.reconnectFailed, isTrue);
      expect(manual.relinking, isFalse);

      fake.failConnect = false;
      await c.resumeAssign();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
    });

    test('「取消操作」 during step 8 does not start it', () async {
      final fake = Round13Link();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final connects = fake.connects;
      fake.assignGate = Completer<void>();
      final run = c.configurePtus();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(commissionProvider).busy, isTrue);
      final stop = c.stopStep8();
      fake.assignGate!.complete();
      await stop;
      await run;
      final s = container.read(commissionProvider);
      expect(s.relinking, isFalse);
      expect(s.resumePending, isTrue);
      expect(fake.connects, connects);
      expect(configureLabel(s), startsWith('重新連線並繼續'));
    });

    test('the step 7 and step 8 labels share 重新連線中…', () {
      const lost = CommissionState(step: 5, resumePending: true);
      expect(configureLabel(lost.copy(relinking: true)), relinkingLabel);
      expect(configureLabel(lost.copy(busy: true)), relinkingLabel);
      expect(configureLabel(lost), '重新連線並繼續');
      expect(
        configureLabel(
          const CommissionState(step: 4, scanResumePending: true, busy: true),
        ),
        relinkingLabel,
      );
    });

    testWidgets('page: disabled 重新連線中…, no resume button, card says so', (
      tester,
    ) async {
      final fake = Round13Link();
      final container = await pumpApp(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await tester.runAsync(
        () => c.configureWifi(1, 1, 'Office-2G', 'pw123456'),
      );
      // Provisioning logs in; this fixture intentionally continues offline.
      c.backendChanged('https://offline-fixture.invalid');
      await c.online(skip: true);
      await c.discover();
      fake.dropsAt.add(1);
      fake.connectGate = Completer<void>();
      late Future<void> run;
      await tester.runAsync(() async {
        run = c.configurePtus();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      var s = container.read(commissionProvider);
      expect(s.step, 5);
      expect(s.relinking, isTrue);
      final configure = find.byKey(const Key('ptu-configure'));
      expect(tester.widget<FilledButton>(configure).onPressed, isNull);
      expect(
        find.descendant(of: configure, matching: find.text(relinkingLabel)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ptu-resume')), findsNothing);
      expect(
        find.text('手機和閘道器的藍牙已中斷，$autoRelinkingText'),
        findsOneWidget,
      );
      expect(find.text(autoRelinkingText), findsOneWidget);
      expect(find.textContaining('請按「重新連線'), findsNothing);

      fake.connectGate!.complete();
      await tester.runAsync(() => run);
      await tester.pumpAndSettle();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(s.relinking, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('2. step 9 retries an unavailable backend', () {
    test('transient: 5xx, unreachable, timeout; not 4xx or 401', () {
      expect(
        isTransientBackendFailure(
          const GatewayFailure.http(status: 502, endpoint: 'GET /x'),
        ),
        isTrue,
      );
      expect(
        isTransientBackendFailure(
          const GatewayFailure.network(endpoint: 'GET /x', detail: '逾時'),
        ),
        isTrue,
      );
      expect(isTransientBackendFailure(TimeoutException('x')), isTrue);
      expect(
        isTransientBackendFailure(
          const GatewayFailure.http(status: 404, endpoint: 'GET /x'),
        ),
        isFalse,
      );
      expect(
        isTransientBackendFailure(const GatewayFailure('authentication')),
        isFalse,
      );
      expect(backendRetryText(3), '後端暫時無回應，自動重試中（3）');
    });

    test('a 502 streak is retried and the progress is kept', () async {
      final fake = Round13Link()..failLatestAt.addAll({2, 3, 4});
      final (container, c) = await atStep9(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      final messages = states.map((x) => x.message).toList();
      // Round 15: the retry line is on top, the per-PTU progress below it.
      for (var n = 1; n <= 3; n++) {
        expect(
          messages.any((m) => m.startsWith('${backendRetryText(n)}\n資料驗證 #')),
          isTrue,
          reason: 'retry $n with progress',
        );
      }
      // Counts never fell back while the backend was retried.
      final seen = <int, int>{};
      for (final x in states) {
        for (final e in x.verifyCounts.entries) {
          expect(e.value, greaterThanOrEqualTo(seen[e.key] ?? 0));
          seen[e.key] = e.value;
        }
      }
      expect(seen.values, everyElement(3));
    });

    test('after the window: 重試 continues from the kept counts', () async {
      backendRetryWindow = const Duration(milliseconds: 40);
      final fake = Round13Link()..failLatestFrom = 2;
      final (container, c) = await atStep9(fake);
      addTearDown(container.dispose);
      await c.verify('https://example.invalid', '');
      var s = container.read(commissionProvider);
      expect(s.busy, isFalse);
      expect(s.step, 6);
      expect(s.verifyBackendDown, isTrue);
      expect(s.error, backendUnavailableText);
      expect(s.errorDetail, contains('HTTP 502'));
      expect(s.verifyCounts.values, everyElement(1));

      fake.recovered = true;
      fake.latestOk = 0;
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.verify('https://example.invalid', '');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.verified, isTrue);
      expect(s.verifyBackendDown, isFalse);
      // 1/3 kept: two more rounds of data were enough.
      expect(fake.latestOk, 2);
      for (final x in states) {
        expect(x.verifyCounts.values.where((n) => n == 0), isEmpty);
      }
    });

    test('a 4xx is final: no retry', () async {
      final fake = Round13Link()..installStatus = 422;
      final (container, c) = await atStep9(fake);
      addTearDown(container.dispose);
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.error, contains('HTTP 422'));
      expect(s.verifyBackendDown, isFalse);
      expect(
        states.map((x) => x.message),
        isNot(contains(backendRetryText(1))),
      );
    });

    testWidgets('page: 重試 after the backend stayed down', (tester) async {
      backendRetryWindow = const Duration(milliseconds: 100);
      final fake = Round13Link()..failLatestFrom = 2;
      final container = await pumpApp(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await tester.runAsync(
        () => c.configureWifi(1, 1, 'Office-2G', 'pw123456'),
      );
      // Provisioning logs in; this fixture intentionally continues offline.
      c.backendChanged('https://offline-fixture.invalid');
      await c.online(skip: true);
      await c.discover();
      await tester.runAsync(c.configurePtus);
      expect(container.read(commissionProvider).step, 6);
      await tester.runAsync(() => c.verify(productionApiBase, 'pw'));
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).verifyBackendDown, isTrue);
      expect(find.byKey(const Key('verify-retry')), findsOneWidget);
      final retry = find.byKey(const Key('verify-retry-bottom'));
      expect(retry, findsOneWidget);
      expect(find.text('1/3'), findsNWidgets(3));

      fake.recovered = true;
      fake.latestOk = 0;
      await tester.ensureVisible(retry);
      await tester.runAsync(() async {
        await tester.tap(retry);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester, container, (s) => s.step == 7);
      final s = container.read(commissionProvider);
      expect(s.verified, isTrue);
      expect(fake.latestOk, 2);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('3. status card while reconnecting by itself', () {
    test('hint says 正在自動重新連線…, then names the real button', () {
      const lost = CommissionState(
        step: 4,
        uploadWatch: UploadWatch.linkLost,
        scanResumePending: true,
      );
      expect(
        linkLostHint(lost.copy(relinking: true)),
        '手機和閘道器的藍牙已中斷，$autoRelinkingText',
      );
      expect(linkLostHint(lost), contains('請按「重新連線並繼續」'));
      expect(
        linkLostHint(const CommissionState(step: 5, resumePending: true)),
        contains('請按「重新連線並繼續」'),
      );
      expect(
        linkLostHint(const CommissionState(step: 3)),
        contains('請重新連線閘道器後再確認'),
      );
    });
  });

  group('4. backend session', () {
    test('a 401 after a backend restart logs in again by itself', () async {
      final fake = Round13Link();
      final (container, c) = await atStep9(fake);
      addTearDown(container.dispose);
      final logins = fake.logins.length;
      fake.expireNext = true;
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.verified, isTrue);
      expect(s.loggedIn, isTrue);
      expect(fake.logins.skip(logins), ['pw1']);
    });

    test('a refused re-login asks for the password again', () async {
      final fake = Round13Link();
      final (container, c) = await atStep9(fake);
      addTearDown(container.dispose);
      fake.refuse = 'pw1';
      fake.expireNext = true;
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.loggedIn, isFalse);
      expect(s.error, const GatewayFailure('authentication').message);
    });

    testWidgets('Bluetooth off at 檢查並開始: no password field; the build '
        'credential logs in once Bluetooth is on (09-28)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'local',
        'backend_local_url': 'http://192.168.1.50:18000',
      });
      final fake = _BluetoothOffLink();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkProvider.overrideWithValue(fake),
            apiProvider.overrideWithValue(fake),
            localBackendProberProvider.overrideWithValue(_Prober()),
            phoneIpv4Provider.overrideWithValue(() async => '192.168.1.23'),
            backendKeyProvider.overrideWithValue('build-key-13'),
          ],
          child: const GatewayApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GatewayApp)),
      );
      expect(find.widgetWithText(TextField, '後端登入密碼'), findsNothing);
      expect(find.textContaining('本地測試密碼'), findsNothing);
      expect(find.byKey(const Key('missing-backend-key')), findsNothing);

      final start = find.text('檢查並開始');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).error, '請開啟手機藍牙後重試。');
      expect(fake.logins, isEmpty);

      fake.bluetoothOff = false;
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 1);
      expect(s.loggedIn, isTrue);
      expect(fake.logins, ['build-key-13']);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
