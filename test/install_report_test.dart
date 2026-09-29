// 09-28 (user request: 「安裝報告能直接送給後台」): the done page's install
// report goes to POST /api/field/install-reports on its own, through the
// field reporter's outbox — queued with no network / no login and sent when
// the network comes back, kept across a restart; the done page says where
// it is (「報告已送到後台 hh:mm」／「排隊中，網路恢復後自動送」／ failed
// with 〔重送〕); 〔分享安裝報告〕 stays. The JSON carries site, gateway,
// MAC, mode, PTUs and binding, verify time, backend / upload target,
// firmware / APP version and phone model — never the Wi-Fi password or a
// token.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/install_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/network_watch.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/install_report_panel.dart';

const _base = 'https://example.invalid';
const _wifiPassword = 'Wifi-Secret-4455';
const _loginPassword = 'login-pw-0001';

/// Demo gateway + backend that records the uploads. [installMode]: what
/// POST /api/field/install-reports answers (`ok`, `network`, `404`, `422`);
/// the rescue uploads always succeed.
class _Backend extends DemoSystem implements SessionInfo {
  String installMode = 'ok';
  bool loggedIn = true;
  final uploads = <(String, Map<String, dynamic>)>[];

  List<Map<String, dynamic>> get installs => [
    for (final u in uploads)
      if (u.$1 == installReportsPath) u.$2,
  ];
  List<Map<String, dynamic>> get sessions => [
    for (final u in uploads)
      if (u.$1 == fieldSessionsPath) u.$2,
  ];

  @override
  bool get hasSession => loggedIn;

  @override
  String? get origin => loggedIn ? _base : null;

  @override
  Future<void> login(String base, String password) async {
    loggedIn = true;
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!path.startsWith('/api/field/')) {
      return super.request(method, path, body);
    }
    uploads.add((path, Map<String, dynamic>.from(body ?? const {})));
    if (path == installReportsPath) {
      switch (installMode) {
        case 'network':
          throw GatewayFailure.network(endpoint: '$method $path', detail: 'x');
        case '404':
          throw GatewayFailure.http(
            status: 404,
            endpoint: '$method $path',
            detail: 'Not Found',
          );
        case '422':
          throw GatewayFailure.http(
            status: 422,
            endpoint: '$method $path',
            detail: 'Unprocessable',
          );
      }
    }
    return {'ok': true, 'duplicate': false};
  }
}

ProviderContainer _container(
  DemoSystem fake, {
  FieldReporterConfig config = const FieldReporterConfig(allowDemoLink: true),
}) {
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      fieldReporterConfigProvider.overrideWithValue(config),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'condition not reached');
}

/// Star, station 1 / gateway 1, PTUs configured and verified: the done page.
Future<CommissioningController> _toDone(ProviderContainer container) async {
  final c = container.read(commissionProvider.notifier);
  await c.prepare(_base, _loginPassword);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'Office-2G', _wifiPassword);
  await c.online();
  await c.discover();
  await c.configurePtus();
  await c.verify(_base, '');
  await _settle();
  final s = container.read(commissionProvider);
  expect(s.step, 7, reason: 'done page');
  expect(s.verified, isTrue);
  return c;
}

CommissionState _done({
  bool verified = true,
  bool deferred = false,
  Map<String, dynamic> config = const {},
  List<Map<String, dynamic>> ptus = const [],
  Set<int> skipped = const {},
  String report = '安裝報告\n站點 80 / 閘道器 1',
}) => CommissionState(
  step: 7,
  verified: verified,
  ptuDeferred: deferred,
  report: report,
  config: {
    'site_id': 80,
    'gateway_id': 1,
    'gateway_uid': 'A0B1C2D39600',
    'fw_version': '1.7.41',
    ...config,
  },
  ptus: ptus,
  verifySkipped: skipped,
);

Map<String, dynamic>? _build(
  CommissionState s, {
  bool direct = false,
  Iterable<String> secrets = const [],
}) => buildInstallReport(
  reportId: 'f' * 32,
  input: FieldInput(
    state: s,
    env: const BackendEnvState(environment: BackendEnv.local),
    directMode: direct,
  ),
  now: DateTime(2026, 9, 28, 10, 15, 2),
  app: const {'version': '1.0.0', 'build': 'abc1234', 'backend_origin': _base},
  phone: const {'model': 'samsung SM-A536B', 'os': 'Android 14', 'sdk': 34},
  sessionId: 'e' * 32,
  secrets: secrets,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. the report JSON', () {
    test('only for the done page with a station and gateway number', () {
      expect(_build(const CommissionState(step: 6)), isNull);
      expect(_build(_done(verified: false)), isNull);
      expect(_build(_done(report: '')), isNull);
      expect(
        _build(_done(config: {'site_id': null, 'gateway_id': null})),
        isNull,
      );
      expect(_build(_done()), isNotNull);
    });

    test('star, verified: identity, PTUs by number with the skipped one '
        'marked, times, backend, target, versions, phone; secrets masked', () {
      final body = _build(
        _done(
          config: {'mqtt_target': 'local', 'mqtt_host': '192.168.1.50'},
          ptus: [
            {'device_number': 3, 'mac': '90:04:22:B6:96:00'},
            {'device_number': 1, 'mac': '9F:77:EF:C2:96:00'},
          ],
          skipped: {3},
          report: '安裝報告\n站點 80 / 閘道器 1\nWi-Fi $_wifiPassword',
        ),
        secrets: [_wifiPassword],
      )!;
      expect(body['schema'], 1);
      expect(body['report_id'], 'f' * 32);
      expect(body['result'], 'verified');
      expect(body['site_id'], 80);
      expect(body['gateway_id'], 1);
      expect(body['gateway_mac'], 'A0B1C2D39600');
      expect(body['mode'], 'star');
      expect(body['fw_version'], '1.7.41');
      expect(body['ptus'], [
        {'device_number': 1, 'mac': '9F:77:EF:C2:96:00', 'verified': true},
        {'device_number': 3, 'mac': '90:04:22:B6:96:00', 'verified': false},
      ]);
      expect(body['direct_bound_mac'], isNull);
      expect(body['star_list'], 'none');
      expect(
        body['verified_at'],
        matches(RegExp(r'^2026-09-28T10:15:02\.000[+-]\d\d:\d\d$')),
      );
      expect(body['backend'], {'env': 'local', 'origin': _base});
      expect(body['upload_target'], '本地 192.168.1.50:8883');
      expect(body['app'], containsPair('version', '1.0.0'));
      expect(body['phone'], containsPair('model', 'samsung SM-A536B'));
      expect(body['session_id'], 'e' * 32);
      expect(body['report_text'], '安裝報告\n站點 80 / 閘道器 1\nWi-Fi ***');
      expect(jsonEncode(body), isNot(contains(_wifiPassword)));
      expect(
        body.keys.where((k) => RegExp('pass|token|key').hasMatch(k)),
        isEmpty,
      );
    });

    test('one-to-one: the bound PTU MAC; 〔先完成配置〕 is deferred without '
        'PTUs', () {
      final bound = _build(
        _done(
          config: {'direct_bind_mac': '9F:77:EF:C2:96:00'},
          ptus: [
            {'device_number': 1, 'mac': '9F:77:EF:C2:96:00'},
          ],
        ),
        direct: true,
      )!;
      expect(bound['mode'], 'direct');
      expect(bound['direct_bound_mac'], '9F:77:EF:C2:96:00');
      expect(bound.containsKey('star_list'), isFalse);
      final deferred = _build(
        _done(verified: false, deferred: true),
        direct: true,
      )!;
      expect(deferred['result'], 'deferred');
      expect(deferred['ptus'], isEmpty);
      expect(deferred['direct_bound_mac'], isNull);
    });

    test('upload target line', () {
      expect(uploadTargetOf(const {}), '正式站（韌體固定）');
      expect(uploadTargetOf(const {'mqtt_target': 'x'}), '未確認');
      expect(uploadTargetOf(const {'mqtt_target': 'production'}), '正式站');
      expect(
        uploadTargetOf(const {
          'mqtt_target': 'local',
          'mqtt_host': '192.168.0.12',
          'mqtt_port': 8883,
        }),
        '本地 192.168.0.12:8883',
      );
    });
  });

  group('2. sent on its own from the done page', () {
    test('verified: one POST with the report on screen; the page says sent '
        'at hh:mm; the same completion is not sent twice', () async {
      final fake = _Backend();
      final container = _container(fake);
      await _toDone(container);
      await _until(
        () =>
            container.read(installReportProvider).phase ==
            InstallReportPhase.sent,
      );
      final s = container.read(commissionProvider);
      final body = fake.installs.single;
      expect(body['result'], 'verified');
      expect(body['site_id'], 1);
      expect(body['gateway_id'], 1);
      expect(body['report_text'], s.report);
      expect(body['ptus'], isNotEmpty);
      expect(body['upload_target'], isA<String>());
      expect(body['queued_ms'], isA<int>());
      final text = jsonEncode(body);
      expect(text, isNot(contains(_wifiPassword)));
      expect(text, isNot(contains(_loginPassword)));
      final status = container.read(installReportProvider);
      expect(status.reportId, body['report_id']);
      expect(
        installReportStatusText(status),
        matches(RegExp(r'^報告已送到後台 \d\d:\d\d$')),
      );
      // The session report says completed as before.
      expect(fake.sessions.last['status'], 'completed');
      final reporter = container.read(fieldReporterProvider);
      reporter.end('completed');
      await _settle();
      expect(fake.installs, hasLength(1));
      expect(reporter.outbox, isEmpty);
    });

    test('no network: queued, then sent as soon as the network is back '
        '(same report_id)', () async {
      final events = StreamController<String>.broadcast();
      addTearDown(events.close);
      final fake = _Backend()..installMode = 'network';
      final container = _container(
        fake,
        config: FieldReporterConfig(
          allowDemoLink: true,
          networkEvents: () => events.stream,
        ),
      );
      await _toDone(container);
      await _until(
        () =>
            container.read(installReportProvider).phase ==
            InstallReportPhase.queued,
      );
      final status = container.read(installReportProvider);
      expect(installReportStatusText(status), '排隊中，網路恢復後自動送（沒有網路或後台沒有回應）');
      expect(status.canResend, isTrue);
      final reporter = container.read(fieldReporterProvider);
      expect(reporter.outbox.where((i) => i.kind == 'install'), hasLength(1));
      final tries = fake.installs.length;
      expect(tries, greaterThanOrEqualTo(1));

      fake.installMode = 'ok';
      events.add(networkAvailableEvent);
      await _until(
        () =>
            container.read(installReportProvider).phase ==
            InstallReportPhase.sent,
      );
      expect(fake.installs, hasLength(tries + 1));
      expect(
        fake.installs.map((b) => b['report_id']).toSet(),
        hasLength(1),
        reason: 'a resend is the same report',
      );
      expect(reporter.outbox.where((i) => i.kind == 'install'), isEmpty);
    });

    test('not logged in: queued (尚未登入後台), sent after the login', () async {
      final fake = _Backend();
      final container = _container(fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(_base, _loginPassword);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.configureWifi(1, 1, 'Office-2G', _wifiPassword);
      await c.online();
      await c.discover();
      await c.configurePtus();
      fake.loggedIn = false;
      await c.verify(_base, '');
      await _settle();
      await _until(
        () =>
            container.read(installReportProvider).phase ==
            InstallReportPhase.queued,
      );
      expect(container.read(installReportProvider).reason, '尚未登入後台');
      expect(fake.installs, isEmpty);
      fake.loggedIn = true;
      await container.read(fieldReporterProvider).flush();
      await _until(
        () =>
            container.read(installReportProvider).phase ==
            InstallReportPhase.sent,
      );
      expect(fake.installs, hasLength(1));
    });

    test('a backend without install reports (404): failed with 〔重送〕, the '
        'rescue uploads keep going; after the update 〔重送〕 sends it', () async {
      final fake = _Backend()..installMode = '404';
      final container = _container(fake);
      await _toDone(container);
      await _until(
        () =>
            container.read(installReportProvider).phase ==
            InstallReportPhase.failed,
      );
      final status = container.read(installReportProvider);
      expect(installReportStatusText(status), '報告沒有送到後台：後台尚未支援（請更新後台）');
      expect(status.canResend, isTrue);
      final reporter = container.read(fieldReporterProvider);
      expect(reporter.outbox, isEmpty, reason: 'nothing left stuck');
      // Not disabled for the rescue uploads: a later session report goes.
      final before = fake.sessions.length;
      await reporter.requestHelp();
      expect(fake.sessions.length, greaterThan(before));

      fake.installMode = 'ok';
      await reporter.resendInstallReport();
      expect(
        container.read(installReportProvider).phase,
        InstallReportPhase.sent,
      );
      expect(fake.installs, hasLength(2));
      expect(fake.installs.last['report_id'], fake.installs.first['report_id']);
    });

    test('refused (422): failed, not kept', () async {
      final fake = _Backend()..installMode = '422';
      final container = _container(fake);
      await _toDone(container);
      await _until(
        () =>
            container.read(installReportProvider).phase ==
            InstallReportPhase.failed,
      );
      expect(container.read(installReportProvider).reason, '後台拒收（HTTP 422）');
      expect(container.read(fieldReporterProvider).outbox, isEmpty);
    });

    test('demo gateway (uploads off): 「模擬模式」, nothing sent', () async {
      final fake = _Backend();
      final container = _container(fake, config: const FieldReporterConfig());
      await _toDone(container);
      final status = container.read(installReportProvider);
      expect(status.phase, InstallReportPhase.disabled);
      expect(installReportStatusText(status), '模擬模式：報告不送後台');
      expect(status.canResend, isFalse);
      expect(fake.uploads, isEmpty);
    });

    test('kept across a restart: the next start sends it', () async {
      final fake = _Backend()..installMode = 'network';
      final first = _container(fake);
      await _toDone(first);
      await _until(
        () =>
            first.read(installReportProvider).phase ==
            InstallReportPhase.queued,
      );
      final id = fake.installs.first['report_id'];
      await _settle();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(fieldOutboxKey)!) as List;
      expect(saved.where((i) => i['kind'] == 'install'), hasLength(1));
      first.dispose();

      final next = _Backend();
      final container = _container(next);
      final reporter = container.read(fieldReporterProvider);
      await reporter.ready;
      await reporter.flush();
      await _until(() => next.installs.isNotEmpty);
      expect(next.installs.single['report_id'], id);
      expect(next.installs.single['queued_ms'], isA<int>());
    });
  });

  group('3. outbox caps', () {
    OutboxItem item(String kind, DateTime at, {int size = 10}) => OutboxItem(
      kind: kind,
      body: {
        'report_id': at.microsecondsSinceEpoch.toRadixString(16),
        if (kind == 'session') 'session_id': 'a' * 32,
        if (kind == 'session') 'event': 'status',
        'pad': 'x' * size,
      },
      createdMs: at.millisecondsSinceEpoch,
    );

    test('kept 7 days (session events 24 h), at most 10, last to go when '
        'the outbox is too big', () {
      final now = DateTime(2026, 9, 28, 12);
      final items = [
        item('session', now.subtract(const Duration(hours: 25))),
        item('install', now.subtract(const Duration(days: 3))),
        item('install', now.subtract(const Duration(days: 8))),
      ];
      pruneOutbox(items, now);
      expect(items.map((i) => i.kind), ['install']);
      expect(
        items.single.createdMs,
        now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
      );

      final many = [
        for (var i = 0; i < 12; i++)
          item('install', now.subtract(Duration(minutes: 12 - i))),
      ];
      pruneOutbox(many, now);
      expect(many, hasLength(outboxInstallLimit));
      expect(
        many.first.createdMs,
        now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );

      final big = [
        item('install', now, size: 1000),
        item('session', now, size: outboxMaxBytes),
      ];
      pruneOutbox(big, now);
      expect(big.map((i) => i.kind), ['install']);
    });

    test('an install item survives a save and load', () {
      final saved = OutboxItem(
        kind: 'install',
        body: const {'report_id': 'abc'},
        createdMs: 1,
      ).toJson();
      final back = OutboxItem.fromJson(jsonDecode(jsonEncode(saved)))!;
      expect(back.kind, 'install');
      expect(back.path, installReportsPath);
    });
  });

  group('4. on the done page', () {
    Future<ProviderContainer> pumpLine(
      WidgetTester tester,
      InstallReportStatus status,
    ) async {
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(_Backend()),
          apiProvider.overrideWithValue(_Backend()),
        ],
      );
      addTearDown(container.dispose);
      container.read(installReportProvider.notifier).set(status);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: InstallReportStatusLine()),
          ),
        ),
      );
      return container;
    }

    /// Both the real (uploads started in runAsync) and the fake (the page,
    /// the tap) zones get to run until the done page status is [phase].
    Future<void> waitPhase(
      WidgetTester tester,
      ProviderContainer container,
      InstallReportPhase phase,
    ) async {
      for (var i = 0; i < 200; i++) {
        if (container.read(installReportProvider).phase == phase) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(container.read(installReportProvider).phase, phase);
    }

    String lineText(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('install-report-status-text')))
        .data!;

    testWidgets('sent: 「報告已送到後台 hh:mm」 without 〔重送〕', (tester) async {
      await pumpLine(
        tester,
        InstallReportStatus(
          phase: InstallReportPhase.sent,
          sentAt: DateTime(2026, 9, 28, 9, 5),
        ),
      );
      expect(lineText(tester), '報告已送到後台 09:05');
      expect(find.byKey(const Key('install-report-resend')), findsNothing);
    });

    testWidgets('queued and failed show 〔重送〕; nothing before the done page', (
      tester,
    ) async {
      final container = await pumpLine(
        tester,
        const InstallReportStatus(
          phase: InstallReportPhase.queued,
          reason: '尚未登入後台',
        ),
      );
      expect(lineText(tester), '排隊中，網路恢復後自動送（尚未登入後台）');
      expect(find.byKey(const Key('install-report-resend')), findsOneWidget);
      container
          .read(installReportProvider.notifier)
          .set(
            const InstallReportStatus(
              phase: InstallReportPhase.failed,
              reason: '後台拒收（HTTP 422）',
            ),
          );
      await tester.pump();
      expect(lineText(tester), '報告沒有送到後台：後台拒收（HTTP 422）');
      expect(find.byKey(const Key('install-report-resend')), findsOneWidget);
      container
          .read(installReportProvider.notifier)
          .set(const InstallReportStatus());
      await tester.pump();
      expect(find.byKey(const Key('install-report-status')), findsNothing);
    });

    testWidgets('the done page: queued in the summary on the first screen, '
        '〔重送〕 sends it, '
        '〔分享安裝報告〕 stays in the report', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'backend_environment': 'production',
      });
      final fake = _Backend()..installMode = 'network';
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
        final c = container.read(commissionProvider.notifier);
        await c.prepare(container.read(backendEnvProvider).base, 'pw');
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.configureWifi(80, 1, 'Office-2G', _wifiPassword);
        await c.online();
        await c.discover();
        await c.configurePtus();
        await c.verify(_base, '');
      });
      await waitPhase(tester, container, InstallReportPhase.queued);
      await tester.pumpAndSettle();
      expect(container.read(commissionProvider).step, 7);
      final line = find.byKey(const Key('install-report-status'));
      // r32: the line is in the summary card, on the first screen of a
      // 360x640 phone (no scrolling), above 〔配置下一台〕／〔完成〕.
      expect(
        find.descendant(
          of: find.byKey(const Key('done-summary')),
          matching: line,
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(line).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('done-finish'))).top,
        ),
        reason: 'visible without scrolling',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('install-report-status-text')))
            .data,
        '排隊中，網路恢復後自動送（沒有網路或後台沒有回應）',
      );
      // 1.0.0+13: the summary's label card (「請在機殼上標示：…」) pushes the
      // report further down on a 360x640 phone — scrolled to it (the page
      // builds lazily); the status is still above it.
      final lineTop = tester.getRect(line).top;
      final report = find.byKey(const Key('done-report'));
      final page = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(report, 100, scrollable: page);
      expect(report, findsOneWidget);
      final position = tester.state<ScrollableState>(page).position;
      expect(
        lineTop,
        lessThan(tester.getRect(report).top + position.pixels),
        reason: 'the status is above the report',
      );
      position.jumpTo(0);
      await tester.pumpAndSettle();

      fake.installMode = 'ok';
      await tester.tap(find.byKey(const Key('install-report-resend')));
      await waitPhase(tester, container, InstallReportPhase.sent);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('install-report-status-text')))
            .data,
        matches(RegExp(r'^報告已送到後台 \d\d:\d\d$')),
      );
      expect(find.byKey(const Key('install-report-resend')), findsNothing);
      // 〔分享安裝報告〕 is still there, inside the report.
      await tester.scrollUntilVisible(report, 100, scrollable: page);
      await tester.ensureVisible(report);
      // 1.0.0+16: shorter 「閘道器」 wording moved the tile under the bottom
      // bar; scroll it clear of the bar before tapping.
      await tester.drag(page, const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(report);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-share')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}
