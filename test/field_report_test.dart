// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §2.2–§2.8, §5.4): when
// session reports go out, the diagnostics package of a failure, the
// offline outbox (login, 24 h expiry, caps, other backend), 404 / 409, the
// same session after a restart, demo mode, and that no upload problem
// ever reaches the commissioning. v1.1: no help code (`short_code`) is
// made or sent; `operator_name` names the logged-in account.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';

const _base = 'https://example.invalid';
const _wifiPassword = 'Wifi-Secret-4455';

/// Demo gateway + backend that records every rescue upload. [mode]:
/// `ok`, `network`, `404`, `409once`, `auth`, `throw`, `hang` (never
/// answers). [loggedIn] is what [SessionInfo] reports.
class FieldFake extends DemoSystem implements SessionInfo {
  String mode = 'ok';
  bool loggedIn = true;
  String originValue = _base;
  String? failOp;
  Completer<Map<String, dynamic>>? pendingPost;
  final uploads = <(String, Map<String, dynamic>)>[];
  final ops = <String>[];

  List<Map<String, dynamic>> get reports => [
    for (final u in uploads)
      if (u.$1 == fieldSessionsPath) u.$2,
  ];
  List<Map<String, dynamic>> get diags => [
    for (final u in uploads)
      if (u.$1 == fieldDiagnosticsPath) u.$2,
  ];

  @override
  bool get hasSession => loggedIn;

  @override
  String? get origin => loggedIn ? originValue : null;

  @override
  Future<void> login(String base, String password) async {
    loggedIn = true;
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    ops.add(op);
    if (op == failOp) {
      failOp = null;
      throw const GatewayFailure('timeout');
    }
    return super.command(op, params);
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
    final pending = pendingPost;
    if (pending != null) {
      pendingPost = null;
      return pending.future;
    }
    switch (mode) {
      case 'network':
        throw GatewayFailure.network(endpoint: '$method $path', detail: 'x');
      case '404':
        throw GatewayFailure.http(
          status: 404,
          endpoint: '$method $path',
          detail: 'Not Found',
        );
      case '409once':
        mode = 'ok';
        throw const GatewayFailure('conflict');
      case 'auth':
        throw const GatewayFailure('authentication');
      case 'throw':
        throw StateError('reporter backend exploded');
      case 'hang':
        return Completer<Map<String, dynamic>>().future;
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

/// Lets microtasks, the outbox and SharedPreferences settle.
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

/// Logged in, connected, Wi-Fi set, online, PTU list read (step 7).
Future<CommissioningController> _toStep7(
  ProviderContainer container,
  FieldFake fake,
) async {
  final c = container.read(commissionProvider.notifier);
  await c.prepare(_base, 'login-pw-0001');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'Office-2G', _wifiPassword);
  await c.online();
  await c.discover();
  await _settle();
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('session reports', () {
    test(
      'first at 第 2 步, then on every step / status / error, seq +1',
      () async {
        final fake = FieldFake();
        final container = _container(fake);
        final c = container.read(commissionProvider.notifier);
        await c.prepare(_base, 'pw-00001');
        await _settle();
        // 準備 ends on 第 2 步 (the gateway list) while still busy, then idle.
        expect(fake.reports.map((r) => r['event']), ['step', 'status']);
        final first = fake.reports.first;
        expect(first['event'], 'step');
        expect(first['step'], 2);
        expect(first['step_label'], '找到閘道器');
        expect(first['seq'], 1);
        expect(first['status'], 'running');
        expect(fake.reports[1]['status'], 'idle');
        expect(fake.reports[1]['seq'], 2);
        expect(first['schema'], 1);
        expect(first['session_id'], matches(RegExp(r'^[0-9a-f]{32}$')));
        // v1.1: no help code; the account name (none on this backend).
        expect(first.containsKey('short_code'), isFalse);
        expect(first.containsKey('operator_name'), isTrue);
        expect(first['operator_name'], isNull);
        expect(first['client_ts'], matches(RegExp(r'[+-]\d\d:\d\d$')));
        expect(first['app'], containsPair('env', isA<String>()));

        await c.scan();
        await _settle();
        // Busy with its run label, then idle again.
        final events = fake.reports.map((r) => r['event']).toList();
        expect(events, ['step', 'status', 'status', 'status']);
        expect(fake.reports[2]['status'], 'running');
        expect(fake.reports[2]['busy_label'], '搜尋附近的閘道器');
        expect(fake.reports[3]['status'], 'idle');

        await c.connect(container.read(commissionProvider).peers.single);
        await _settle();
        final seqs = fake.reports.map((r) => r['seq'] as int).toList();
        for (var i = 1; i < seqs.length; i++) {
          expect(seqs[i], seqs[i - 1] + 1);
        }
        expect(fake.reports.last['step'], greaterThanOrEqualTo(3));
        expect(
          fake.reports.map((r) => r['session_id']).toSet(),
          hasLength(1),
          reason: 'one session for one gateway',
        );
        // Nothing but reports so far (no failure, no help).
        expect(fake.diags, isEmpty);
      },
    );

    test('step 7 timeout: an error report and a timeout package', () async {
      final fake = FieldFake();
      final container = _container(fake);
      final c = await _toStep7(container, fake);
      expect(container.read(commissionProvider).step, 4);
      final before = fake.reports.length;

      fake.failOp = 'scan_ble_discover';
      await c.discover();
      await _settle();
      final s = container.read(commissionProvider);
      expect(s.error, '等待超時，請確認裝置與網路後重試。');

      final error = fake.reports
          .skip(before)
          .firstWhere((r) => r['event'] == 'error');
      expect(error['step'], 7);
      expect(error['step_label'], '選擇 PTU');
      expect(error['ctl_step'], 4);
      expect(error['status'], 'failed');
      expect(error['error_code'], 'CMD_TIMEOUT');
      expect(error['fail_code'], 'timeout');
      expect(error['error_message'], s.error);
      expect(error['last_command'], containsPair('op', isA<String>()));

      final diag = fake.diags.single;
      expect(diag['trigger'], 'timeout');
      expect(diag['diag_seq'], 1);
      expect(diag['step'], 7);
      expect((diag['error'] as Map)['code'], 'CMD_TIMEOUT');
      expect((diag['error'] as Map)['message'], s.error);
      final commands = (diag['commands'] as List).cast<Map>();
      expect(
        commands.any(
          (e) => e['op'] == 'scan_ble_discover' && e['status'] == 'timeout',
        ),
        isTrue,
      );
      expect(commands.firstWhere((e) => e['op'] == 'set_wifi')['params'], {
        'ssid': 'Office-2G',
        'password': '***',
      });
      final text = jsonEncode(fake.uploads.map((u) => u.$2).toList());
      expect(text, isNot(contains(_wifiPassword)));
      expect(text, isNot(contains('login-pw-0001')));
      expect(diag['gateway'], isA<Map>());
      expect(diag['ptu_summary'], isA<Map>());
      expect(diag['context'], containsPair('logged_in', true));
      // Reports before packages, each once.
      final kinds = fake.uploads.map((u) => u.$1).toList();
      expect(kinds.last, fieldDiagnosticsPath);
    });

    test(
      'idle is not stuck; a busy operation has its own stuck clock',
      () async {
        final fake = FieldFake();
        var now = DateTime(2026, 10, 3, 12);
        var state = const CommissionState(step: 1);
        final reporter = FieldReporter(
          api: fake,
          enabled: true,
          config: FieldReporterConfig(
            now: () => now,
            appInfo: () async => {
              'version': '1.0.11',
              'build': 'Build 50 / sample',
            },
          ),
        );
        addTearDown(reporter.dispose);
        reporter.attach(
          input: () => FieldInput(
            state: state,
            env: const BackendEnvState(loaded: true),
          ),
        );
        await reporter.ready;
        reporter.onState();
        await _settle();
        now = now.add(const Duration(minutes: 20));
        reporter.checkStuck();
        expect(fake.diags, isEmpty);
        state = state.copy(busy: true);
        reporter.onState();
        await _settle();
        reporter.checkStuck();
        expect(
          fake.diags,
          isEmpty,
          reason: 'idle time must not count against busy timeout',
        );
        now = now.add(const Duration(seconds: 121));
        reporter.checkStuck();
        await _settle();
        expect(fake.diags.single['trigger'], 'stuck');
        expect(fake.reports.last['app'], containsPair('version', '1.0.11'));
        expect(
          fake.reports.last['app'],
          containsPair('build', 'Build 50 / sample'),
        );
        state = state.copy(busy: false);
        reporter.onState();
        await _settle();
        expect(fake.reports.last['error_code'], isNull);
      },
    );

    test('stuck time: 120 s, steps 8 and 9 240 s', () {
      const config = FieldReporterConfig();
      for (var step = 1; step <= 10; step++) {
        expect(
          config.stuckFor(step),
          step == 8 || step == 9
              ? const Duration(seconds: 240)
              : const Duration(seconds: 120),
          reason: '第 $step 步',
        );
      }
    });

    test('heartbeat: latest state, a new seq, never queued', () async {
      final fake = FieldFake();
      final container = _container(fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(_base, 'pw-00001');
      await _settle();
      final reporter = container.read(fieldReporterProvider);
      final seq = fake.reports.last['seq'] as int;
      reporter.heartbeat();
      await _settle();
      expect(fake.reports.last['event'], 'heartbeat');
      expect(fake.reports.last['seq'], seq + 1);
      expect(fake.reports.last['status'], 'idle');

      fake.mode = 'network';
      reporter.heartbeat();
      await _settle();
      expect(fake.reports.last['event'], 'heartbeat');
      expect(reporter.outbox, isEmpty, reason: 'a failed heartbeat is dropped');
    });

    test('completed at step 10 ends the session', () async {
      final fake = FieldFake();
      final container = _container(fake);
      final c = await _toStep7(container, fake);
      final reporter = container.read(fieldReporterProvider);
      final id = reporter.session!.id;
      // Everything below is the demo verify path.
      await c.configurePtus();
      await c.verify(_base, '');
      await _settle();
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      final end = fake.reports.last;
      expect(end['event'], 'end');
      expect(end['status'], 'completed');
      expect(end['session_id'], id);
      expect(reporter.session, isNull);
    });

    test('cancel ends the session as abandoned; the next one is new', () async {
      final fake = FieldFake();
      final container = _container(fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(_base, 'pw-00001');
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await _settle();
      final first = fake.reports.first['session_id'];
      final sent = fake.reports.length;
      await c.cancel();
      await _settle();
      final after = fake.reports.skip(sent).toList();
      final end = after.firstWhere((r) => r['event'] == 'end');
      expect(end['status'], 'abandoned');
      expect(end['session_id'], first);
      // Back on the gateway list (第 2 步): the next gateway is a new
      // session.
      final next = after.last;
      expect(next['event'], 'step');
      expect(next['step'], 2);
      expect(next['session_id'], isNot(first));
      expect(next['seq'], 1);
      expect(next.containsKey('short_code'), isFalse);
    });
  });

  group('outbox', () {
    test('not logged in: queued and saved, sent after the login', () async {
      final selectedBase = const BackendEnvState().base;
      final fake = FieldFake()
        ..loggedIn = false
        ..originValue = selectedBase;
      final container = _container(fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(selectedBase, '', offline: true);
      await c.scan();
      await _settle();
      await c.requestHelp();
      await _settle();
      expect(fake.uploads, isEmpty);
      final reporter = container.read(fieldReporterProvider);
      expect(reporter.outbox, isNotEmpty);
      expect(container.read(fieldHelpProvider).phase, FieldHelpPhase.queued);
      expect(container.read(fieldHelpProvider).reason, '尚未登入後台');
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(fieldOutboxKey)!) as List;
      expect(saved.length, reporter.outbox.length);
      expect(saved.first, containsPair('kind', 'session'));

      final queued = reporter.outbox.length;
      await c.login(selectedBase, 'pw-00001');
      await _until(() => reporter.outbox.isEmpty);
      // The queued reports first (in seq order), then the package; the
      // login's own reports may come before it (reports go first).
      final paths = fake.uploads.map((u) => u.$1).toList();
      final diagAt = paths.indexOf(fieldDiagnosticsPath);
      expect(diagAt, greaterThanOrEqualTo(queued - 1));
      expect(
        paths.take(queued - 1).every((p) => p == fieldSessionsPath),
        isTrue,
      );
      final seqs = fake.reports.map((r) => r['seq'] as int).toList();
      expect(seqs, [for (var i = 1; i <= seqs.length; i++) i]);
      expect(fake.reports.first['queued_ms'], greaterThanOrEqualTo(0));
      expect(fake.diags.single['trigger'], 'help');
      expect(container.read(fieldHelpProvider).phase, FieldHelpPhase.sent);
      expect(jsonDecode(prefs.getString(fieldOutboxKey)!) as List, isEmpty);
    });

    test('items older than 24 h are dropped, the rest sent', () async {
      final now = DateTime.now();
      Map<String, dynamic> item(Duration age, int seq) => {
        'kind': 'session',
        'created_ms': now.subtract(age).millisecondsSinceEpoch,
        'tries': 3,
        'body': {
          'schema': 1,
          'session_id': 'b' * 32,
          // Queued by v1 (before the help code was dropped).
          'short_code': '123456',
          'seq': seq,
          'event': 'step',
        },
      };
      SharedPreferences.setMockInitialValues({
        fieldOutboxKey: jsonEncode([
          item(const Duration(hours: 25), 1),
          item(const Duration(hours: 2), 2),
        ]),
      });
      final fake = FieldFake();
      final container = _container(fake);
      container.read(commissionProvider);
      final reporter = container.read(fieldReporterProvider);
      await reporter.ready;
      expect(reporter.outbox, hasLength(1));
      await reporter.flush();
      expect(fake.reports.single['seq'], 2);
      expect(fake.reports.single['queued_ms'], greaterThan(3600 * 1000));
      // v1.1: a code queued by v1 is not sent.
      expect(fake.reports.single.containsKey('short_code'), isFalse);
    });

    test('caps: 50 events per session (status first), 5 packages', () {
      final now = DateTime.now();
      OutboxItem session(String event, int seq) => OutboxItem(
        kind: 'session',
        body: {'session_id': 's' * 32, 'seq': seq, 'event': event},
        createdMs: now.millisecondsSinceEpoch,
      );
      OutboxItem diag(String trigger, int seq) => OutboxItem(
        kind: 'diag',
        body: {'session_id': 's' * 32, 'diag_seq': seq, 'trigger': trigger},
        createdMs: now.millisecondsSinceEpoch,
      );
      final items = [
        session('step', 1),
        for (var i = 2; i <= 40; i++) session('status', i),
        for (var i = 41; i <= 60; i++) session('error', i),
        diag('help', 1),
        for (var i = 2; i <= 8; i++) diag('error', i),
      ];
      pruneOutbox(items, now);
      final sessions = items.where((i) => i.kind == 'session').toList();
      expect(sessions, hasLength(outboxSessionEventLimit));
      expect(sessions.where((i) => i.event == 'error'), hasLength(20));
      expect(sessions.first.event, 'step');
      final diags = items.where((i) => i.kind == 'diag').toList();
      expect(diags, hasLength(outboxDiagLimit));
      expect(diags.first.trigger, 'help', reason: 'help is kept');
      expect(diags.last.body['diag_seq'], 8);
    });

    test('network error: kept and retried after the back-off', () async {
      final fake = FieldFake()..mode = 'network';
      final container = _container(fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(_base, 'pw-00001');
      await _settle();
      final reporter = container.read(fieldReporterProvider);
      // One try (the first report), the rest wait behind it.
      expect(fake.reports, hasLength(1));
      expect(reporter.outbox, hasLength(2));
      expect(reporter.outbox.first.tries, 1);
      // Within the back-off nothing is sent again.
      await reporter.flush();
      expect(fake.reports, hasLength(1));
      fake.mode = 'ok';
      await reporter.resendHelp(); // clears the back-off, like 〔重新傳送〕
      expect(reporter.outbox, isEmpty);
      expect(fake.reports.map((r) => r['seq']), [1, 1, 2]);
    });

    test('404: this backend is skipped for an hour, the queue kept', () async {
      var clock = DateTime(2026, 9, 26, 14);
      final fake = FieldFake()..mode = '404';
      final container = _container(
        fake,
        config: FieldReporterConfig(allowDemoLink: true, now: () => clock),
      );
      final c = container.read(commissionProvider.notifier);
      await c.prepare(_base, 'pw-00001');
      await _settle();
      expect(fake.uploads, hasLength(1));
      await c.requestHelp();
      await _settle();
      expect(fake.uploads, hasLength(1), reason: 'no request while disabled');
      expect(
        container.read(fieldHelpProvider).phase,
        FieldHelpPhase.unsupported,
      );
      final reporter = container.read(fieldReporterProvider);
      expect(reporter.outbox, isNotEmpty);

      fake.mode = 'ok';
      clock = clock.add(const Duration(minutes: 61));
      await reporter.flush();
      expect(reporter.outbox, isEmpty);
      expect(fake.diags.single['trigger'], 'help');
    });

    test('409: an ordinary failure (kept, sent again later), no code to '
        're-roll', () async {
      final fake = FieldFake()..mode = '409once';
      final container = _container(fake);
      final c = container.read(commissionProvider.notifier);
      await c.prepare(_base, 'pw-00001');
      await _settle();
      final reporter = container.read(fieldReporterProvider);
      // Not re-sent at once (v1 re-rolled the code and retried in place).
      expect(fake.reports, hasLength(1));
      expect(reporter.outbox, isNotEmpty);
      reporter.onNetworkBack();
      await _until(() => reporter.outbox.isEmpty);
      final (a, b) = (fake.reports[0], fake.reports[1]);
      expect(b['session_id'], a['session_id']);
      expect(b['seq'], a['seq'], reason: 'the same report again');
      for (final r in fake.reports) {
        expect(r.containsKey('short_code'), isFalse);
      }
    });

    test(
      'another backend: what was queued for the old one is dropped',
      () async {
        final fake = FieldFake()..loggedIn = false;
        final container = _container(fake);
        final c = container.read(commissionProvider.notifier);
        await c.prepare(_base, '', offline: true);
        await _settle();
        final reporter = container.read(fieldReporterProvider);
        expect(reporter.outbox, isNotEmpty);
        c.backendChanged('http://192.168.0.12:18000');
        expect(reporter.outbox, isEmpty);
      },
    );
  });

  group('restart and demo', () {
    test(
      'backend switch during an upload never drains new reports to the old API',
      () async {
        final fake = FieldFake();
        var state = const CommissionState(step: 1);
        final reporter = FieldReporter(api: fake, enabled: true);
        addTearDown(reporter.dispose);
        reporter.attach(
          input: () => FieldInput(
            state: state,
            env: const BackendEnvState(loaded: true),
          ),
        );
        await reporter.ready;
        final pending = Completer<Map<String, dynamic>>();
        fake.pendingPost = pending;
        reporter.onState();
        await _settle();
        expect(fake.uploads, hasLength(1));
        reporter.onBackendChanged('https://new-backend.invalid');
        state = state.copy(busy: true);
        reporter.onState();
        await _settle();
        pending.complete({'ok': true});
        await _settle();
        expect(fake.uploads, hasLength(1));
        expect(reporter.outbox, isNotEmpty);
      },
    );
    test(
      'abandoned help opens a new session and changed backend cannot send through old API',
      () async {
        final fake = FieldFake();
        final container = _container(fake);
        await _toStep7(container, fake);
        final reporter = container.read(fieldReporterProvider);
        await reporter.requestHelp();
        final previous = reporter.help.sessionId;
        reporter.end('abandoned');
        expect(reporter.help.sessionId, isNull);
        await reporter.requestHelp();
        expect(reporter.help.sessionId, isNot(previous));
        final before = fake.uploads.length;
        reporter.onBackendChanged('https://new-backend.invalid');
        await reporter.requestHelp();
        expect(reporter.help.phase, FieldHelpPhase.needsConnection);
        expect(fake.uploads.length, before);
      },
    );

    test('restore after a kill: same session id, seq continues', () async {
      final fake = FieldFake();
      final container = _container(fake);
      await _toStep7(container, fake);
      final reporter = container.read(fieldReporterProvider);
      await reporter.requestHelp();
      await _settle();
      final id = reporter.session!.id;
      final lastSeq = fake.reports.last['seq'] as int;
      container.dispose();

      final fake2 = FieldFake();
      final container2 = _container(fake2);
      final c2 = container2.read(commissionProvider.notifier);
      await c2.restore();
      final restored = container2.read(fieldReporterProvider).session!;
      expect(restored.id, id);
      expect(container2.read(fieldHelpProvider).sessionId, id);

      await c2.resumeSaved();
      await _settle();
      expect(fake2.reports, isNotEmpty);
      expect(fake2.reports.every((r) => r['session_id'] == id), isTrue);
      expect(fake2.reports.first['seq'], greaterThan(lastSeq));
    });

    test('demo gateway: no session, no request, help says demo', () async {
      final fake = FieldFake();
      final container = _container(fake, config: const FieldReporterConfig());
      await _toStep7(container, fake);
      final c = container.read(commissionProvider.notifier);
      fake.failOp = 'scan_ble_discover';
      await c.discover();
      await c.requestHelp();
      await _settle();
      expect(fake.uploads, isEmpty);
      final reporter = container.read(fieldReporterProvider);
      expect(reporter.enabled, isFalse);
      expect(reporter.session, isNull);
      expect(c.fieldHelpAvailable, isFalse);
      expect(container.read(fieldHelpProvider).phase, FieldHelpPhase.disabled);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(fieldOutboxKey), isNull);
    });
  });

  group('uploads never disturb the commissioning', () {
    for (final mode in ['network', 'throw', 'auth', 'hang']) {
      test('backend "$mode": the flow runs as without reporting', () async {
        final fake = FieldFake()..mode = mode;
        final container = _container(
          fake,
          config: const FieldReporterConfig(
            allowDemoLink: true,
            helpWait: Duration(milliseconds: 200),
          ),
        );
        final c = await _toStep7(container, fake);
        var s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.busy, isFalse);
        expect(s.step, 4);
        expect(s.ptus, isNotEmpty);
        expect(fake.uploads, isNotEmpty, reason: 'it did try');

        // A failure and a help: still only the flow's own red box.
        fake.failOp = 'scan_ble_discover';
        await c.discover();
        final commands = fake.ops.length;
        await c.requestHelp();
        await _settle();
        expect(
          container.read(fieldHelpProvider).phase,
          FieldHelpPhase.queued,
          reason: 'not sent: the sheet says to read it out',
        );
        s = container.read(commissionProvider);
        expect(s.error, '等待超時，請確認裝置與網路後重試。');
        expect(s.busy, isFalse);
        expect(fake.ops.length, commands, reason: 'no BLE command for help');
        // And the next step works.
        await c.discover();
        s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.ptus, isNotEmpty);
      });
    }

    test(
      'rule 27: a cancel red box is not failed and sends no package',
      () async {
        final fake = FieldFake();
        final container = _container(fake);
        final c = container.read(commissionProvider.notifier);
        await c.prepare(_base, 'pw-00001');
        await _settle();
        final reporter = container.read(fieldReporterProvider);
        final state = container
            .read(commissionProvider)
            .copy(error: '操作已取消，可從最近完成的步驟重試。');
        reporter.attach(
          input: () => FieldInput(
            state: state,
            env: const BackendEnvState(loaded: true),
          ),
        );
        final sent = fake.reports.length;
        reporter.onFailure(const GatewayFailure('cancelled'), ctlStep: 1);
        await _settle();
        expect(fake.diags, isEmpty);
        expect(fake.reports, hasLength(sent), reason: 'nothing changed');
        await reporter.requestHelp();
        await _settle();
        final help = fake.reports.last;
        expect(help['event'], 'help');
        expect(help['error_code'], 'HELP_ONLY');
        expect(fake.diags.single['trigger'], 'help');
      },
    );

    test('a reporter whose input throws is harmless', () async {
      final fake = FieldFake();
      final container = _container(fake);
      final c = container.read(commissionProvider.notifier);
      final reporter = container.read(fieldReporterProvider);
      reporter.attach(input: () => throw StateError('broken'));
      await c.prepare(_base, 'pw-00001');
      await c.scan();
      await c.requestHelp();
      reporter.heartbeat();
      reporter.checkStuck();
      await _settle();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.peers, isNotEmpty);
    });
  });

  group('package size', () {
    test('trimmed below 60 KiB in the §2.4 order', () {
      Map<String, dynamic> big(int pad) => {
        'schema': 1,
        'error': {'code': 'CMD_TIMEOUT', 'detail': 'd' * 2000},
        'commands': [
          for (var i = 0; i < 30; i++)
            {
              't': '14:00:00.000',
              'ch': 'ble',
              'op': 'get_ble_devices',
              'status': 'ok',
              'result': '結' * 300,
            },
        ],
        'ptus': [
          for (var i = 0; i < 12; i++) {'mac': 'AA', 'fail_text': '失' * 120},
        ],
        'pad': 'p' * pad,
      };
      int bytes(Object? v) => utf8.encode(jsonEncode(v)).length;
      List<Map> commands(Map d) => (d['commands'] as List).cast<Map>();
      String detail(Map d) => (d['error'] as Map)['detail'] as String;

      // 1. Results cut to 120 characters is enough.
      final a = fitDiagnostics(big(40000));
      expect(bytes(a), lessThanOrEqualTo(diagnosticsTrimBytes));
      expect(commands(a), hasLength(30));
      expect((commands(a).first['result'] as String).length, 120);
      expect(detail(a), hasLength(2000));
      // 2. Then only the last 15 commands.
      final b = fitDiagnostics(big(44000));
      expect(bytes(b), lessThanOrEqualTo(diagnosticsTrimBytes));
      expect(commands(b), hasLength(15));
      expect(detail(b), hasLength(2000));
      // 3. Then error.detail cut to 500.
      final c = fitDiagnostics(big(49000));
      expect(bytes(c), lessThanOrEqualTo(diagnosticsTrimBytes));
      expect(commands(c), hasLength(15));
      expect(detail(c), hasLength(500));
      // Anything larger still ends below the limit.
      expect(
        bytes(fitDiagnostics(big(58000))),
        lessThanOrEqualTo(diagnosticsTrimBytes),
      );
      // Small packages are untouched.
      final small = <String, dynamic>{'schema': 1, 'commands': const []};
      expect(identical(fitDiagnostics(small), small), isTrue);
    });

    test('session report fields stay inside the contract ranges', () {
      const state = CommissionState(
        step: 2,
        config: {'site_id': 0, 'gateway_id': 99, 'fw_version': '1.7.32'},
        peer: GatewayPeer('p', 'GIOS-S80-GW01', -50),
        busy: true,
      );
      final body = buildSessionReport(
        sessionId: 'c' * 32,
        seq: 1,
        event: 'status',
        now: DateTime(2026, 9, 26, 14),
        input: const FieldInput(
          state: state,
          env: BackendEnvState(loaded: true),
          targetCount: 9,
        ),
        status: 'running',
      );
      expect(body['site_id'], isNull);
      expect(body['gateway_id'], isNull);
      expect(body['target_ptu_count'], isNull);
      expect(body['fw_version'], '1.7.32');
      expect(body['mode'], 'star');
      expect(body.keys.toSet(), {
        'schema',
        'session_id',
        'operator_name',
        'seq',
        'event',
        'client_ts',
        'queued_ms',
        'app',
        'phone',
        'site_id',
        'gateway_id',
        'gateway_mac',
        'gateway_name',
        'fw_version',
        'mode',
        'target_ptu_count',
        'step',
        'step_label',
        'ctl_step',
        'status',
        'busy_label',
        'error_code',
        'fail_code',
        'error_message',
        'progress',
        'last_command',
      }, reason: 'additionalProperties: false');
      expect(body['operator_name'], isNull);
    });

    test('v1.1 operator_name: report top level, package context, at most '
        '64 characters; no short_code in either', () {
      const state = CommissionState(
        step: 4,
        config: {'site_id': 80, 'gateway_id': 1},
        peer: GatewayPeer('p', 'GIOS-S80-GW01', -50),
      );
      const input = FieldInput(
        state: state,
        env: BackendEnvState(loaded: true),
      );
      final long = '${'陳' * 40}  現場  ${'A' * 40}';
      final report = buildSessionReport(
        sessionId: 'd' * 32,
        seq: 1,
        event: 'help',
        now: DateTime(2026, 9, 27, 9),
        input: input,
        status: 'help',
        operatorName: '  王  小明 ',
      );
      expect(report['operator_name'], '王 小明');
      expect(report.containsKey('short_code'), isFalse);
      final cut = buildSessionReport(
        sessionId: 'd' * 32,
        seq: 2,
        event: 'status',
        now: DateTime(2026, 9, 27, 9),
        input: input,
        status: 'idle',
        operatorName: long,
      );
      expect((cut['operator_name'] as String).length, 64);
      expect(cut['operator_name'], startsWith('陳' * 40));
      final diag = buildDiagnostics(
        sessionId: 'd' * 32,
        diagSeq: 1,
        trigger: 'help',
        now: DateTime(2026, 9, 27, 9),
        input: input,
        code: RescueCode.helpOnly,
        operatorName: long,
      );
      expect(diag.containsKey('short_code'), isFalse);
      expect(diag.containsKey('operator_name'), isFalse, reason: 'context');
      final context = diag['context'] as Map;
      expect((context['operator_name'] as String).length, 64);
      expect(operatorNameOf(''), isNull);
      expect(operatorNameOf('   '), isNull);
      expect(operatorNameOf(42), isNull);
    });

    test('v1.1: a session saved by v1 (with its code) is restored without '
        'it', () {
      final session = FieldSession.fromJson({
        'id': 'e' * 32,
        'code': '482915',
        'seq': 7,
        'diag_seq': 2,
        'created_ms': 1,
      })!;
      expect(session.id, 'e' * 32);
      expect(session.seq, 7);
      expect(session.toJson().containsKey('code'), isFalse);
      expect(FieldSession.fromJson({'id': 'f' * 32})!.seq, 0);
    });
  });
}
