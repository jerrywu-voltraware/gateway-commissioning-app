import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/core/local_backend_address.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/presentation/local_backend_field.dart';
import 'package:flutter/services.dart';

const healthy = ProbeResult(
  ProbeOutcome.healthy,
  status: 200,
  version: '1.1.0',
);

class FakeProber implements LocalBackendProber {
  FakeProber(this.results, {this.delay = Duration.zero});
  final Map<String, ProbeResult> results;
  final Duration delay;
  final probed = <Uri>[];
  int inFlight = 0, maxInFlight = 0;
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async {
    probed.add(base);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(delay);
    inFlight--;
    return results[base.host] ??
        const ProbeResult(ProbeOutcome.unreachable, detail: 'refused');
  }
}

void main() {
  group('local IPv4 validation', () {
    test('accepts private IPv4 literals', () {
      for (final ip in [
        '192.168.1.187',
        '192.168.0.12',
        '10.0.0.5',
        '172.16.0.1',
        '172.31.255.254',
      ]) {
        expect(localHostError(ip), isNull, reason: ip);
      }
    });
    test('rejects public IPs, hostnames, loopback and malformed input', () {
      for (final ip in [
        '',
        '8.8.8.8',
        '172.32.0.1',
        '172.15.0.1',
        '192.169.1.1',
        '127.0.0.1',
        'localhost',
        'my-pc.local',
        'http://192.168.1.187',
        '192.168.1',
        '192.168.1.1.1',
        '192.168.1.256',
        '192.168.01.5',
        '192.168..5',
        '192.168.1.0',
        '192.168.1.255',
        '192.168.1.187:18000',
      ]) {
        expect(localHostError(ip), isNotNull, reason: ip);
      }
      expect(localHostError('8.8.8.8'), contains('區域網路'));
    });
    test('port validation', () {
      expect(localPortError('18000'), isNull);
      expect(localPortError('0'), isNotNull);
      expect(localPortError('70000'), isNotNull);
      expect(localPortError('abc'), isNotNull);
    });
    test('formatter keeps digits and dots, maps decimal comma', () {
      final f = Ipv4InputFormatter();
      TextEditingValue fmt(String s) => f.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: s,
          selection: TextSelection.collapsed(offset: s.length),
        ),
      );
      expect(fmt('192,168,1,5').text, '192.168.1.5');
      expect(fmt('192.168.1.5 ').text, '192.168.1.5');
      expect(fmt('a1b2').text, '12');
      expect(fmt('a1b2').selection.baseOffset, 2);
      expect(fmt('1234567890123456').text, '');
    });
  });

  group('URL composition and migration', () {
    test('compose and parse round-trip', () {
      expect(composeLocalUrl('192.168.1.187'), 'http://192.168.1.187:18000');
      expect(composeLocalUrl(' 10.0.0.2 ', 8080), 'http://10.0.0.2:8080');
      expect(
        parseLocalUrl('http://192.168.0.12:18000'),
        const LocalEndpoint('192.168.0.12', 18000),
      );
      expect(
        parseLocalUrl('http://192.168.1.187:9000/'),
        const LocalEndpoint('192.168.1.187', 9000),
      );
      expect(
        parseLocalUrl('http://192.168.1.187')?.url,
        'http://192.168.1.187:80',
      );
      expect(parseLocalUrl('http://my-pc:18000')?.host, 'my-pc');
    });
    test('unusable saved values return null', () {
      for (final url in [null, '', 'https://x.com', 'not a url', 'http://']) {
        expect(parseLocalUrl(url), isNull, reason: '$url');
      }
    });
  });

  group('healthz signature', () {
    test('matches dashboard-api /healthz only', () {
      final ok = classifyHealthz(
        200,
        '{"ok":true,"version":"1.1.0","ingest":null}',
      );
      expect(ok.outcome, ProbeOutcome.healthy);
      expect(ok.version, '1.1.0');
      final db = classifyHealthz(
        503,
        '{"ok":false,"version":"1.1.0","reason":"database_unavailable"}',
      );
      expect(db.outcome, ProbeOutcome.degraded);
      expect(db.isBackend, isTrue);
      // SPA fallback / other web servers answering 200.
      expect(
        classifyHealthz(200, '<!doctype html><html></html>').outcome,
        ProbeOutcome.notBackend,
      );
      expect(
        classifyHealthz(200, '{"status":"ok"}').outcome,
        ProbeOutcome.notBackend,
      );
      expect(
        classifyHealthz(200, '{"ok":true}').outcome,
        ProbeOutcome.notBackend,
      );
      expect(
        classifyHealthz(200, '{"ok":false,"version":"1"}').outcome,
        ProbeOutcome.notBackend,
      );
      expect(classifyHealthz(404, 'nope').outcome, ProbeOutcome.httpError);
      expect(classifyHealthz(503, 'busy').status, 503);
    });
  });

  group('subnet enumeration', () {
    test('lists the /24 without .0, .255 and own IP', () {
      final hosts = subnetHosts('192.168.1.23');
      expect(hosts, hasLength(253));
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
      expect(hosts, isNot(contains('192.168.1.23')));
      expect(hosts, isNot(contains('192.168.1.0')));
      expect(hosts, isNot(contains('192.168.1.255')));
      expect(subnetHosts('bogus'), isEmpty);
    });
    test('prefers wlan private IPv4 over cellular', () {
      expect(
        pickWifiIpv4([('rmnet_data0', '10.12.3.4'), ('wlan0', '192.168.1.50')]),
        '192.168.1.50',
      );
      expect(pickWifiIpv4([('rmnet_data0', '10.12.3.4')]), isNull);
      expect(pickWifiIpv4([('wlan0', '100.64.1.1')]), isNull);
      expect(pickWifiIpv4([('eth0', '172.20.0.9')]), '172.20.0.9');
    });
  });

  group('auto-find', () {
    final hosts = subnetHosts('192.168.1.23');
    test('none found', () async {
      final prober = FakeProber({
        '192.168.1.9': const ProbeResult(ProbeOutcome.notBackend, status: 200),
      });
      final result = await LocalBackendFinder(prober).find(hosts);
      expect(result.found, isEmpty);
      expect(result.cancelled, isFalse);
      expect(prober.probed, hasLength(253));
      expect(prober.probed.first.port, 18000);
    });
    test('one found, with bounded concurrency', () async {
      final prober = FakeProber({
        '192.168.1.187': healthy,
      }, delay: const Duration(milliseconds: 1));
      final progress = <String>[];
      final result = await LocalBackendFinder(
        prober,
        concurrency: 32,
      ).find(hosts, port: 9000, onProgress: (h, d, t) => progress.add(h));
      expect(result.found.map((f) => f.host), ['192.168.1.187']);
      expect(prober.maxInFlight, lessThanOrEqualTo(32));
      expect(prober.maxInFlight, greaterThan(1));
      expect(prober.probed.every((u) => u.port == 9000), isTrue);
      expect(progress, hasLength(253));
    });
    test('many found are sorted numerically', () async {
      final prober = FakeProber({
        '192.168.1.187': healthy,
        '192.168.1.12': healthy,
        '192.168.1.9': const ProbeResult(
          ProbeOutcome.degraded,
          status: 503,
          version: '1.1.0',
        ),
      });
      final result = await LocalBackendFinder(prober).find(hosts);
      expect(result.found.map((f) => f.host), [
        '192.168.1.9',
        '192.168.1.12',
        '192.168.1.187',
      ]);
      expect(result.found.first.healthy, isFalse);
    });
    test('cancel returns promptly', () async {
      final prober = FakeProber({}, delay: const Duration(milliseconds: 200));
      final cancel = ScanCancel();
      final watch = Stopwatch()..start();
      final pending = LocalBackendFinder(prober).find(hosts, cancel: cancel);
      Timer(const Duration(milliseconds: 50), cancel.cancel);
      final result = await pending;
      expect(result.cancelled, isTrue);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(prober.probed.length, lessThan(253));
    });
    test('total deadline stops the scan', () async {
      final prober = FakeProber({}, delay: const Duration(milliseconds: 100));
      final result = await LocalBackendFinder(
        prober,
        concurrency: 4,
        totalTimeout: const Duration(milliseconds: 250),
      ).find(hosts);
      expect(result.timedOut, isTrue);
      expect(prober.probed.length, lessThan(253));
    });
  });

  group('HTTP prober against a loopback server', () {
    late HttpServer server;
    final seenHeaders = <HttpHeaders>[];
    void Function(HttpRequest) reply = (_) {};
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        seenHeaders.add(r.headers);
        reply(r);
      });
    });
    tearDown(() => server.close(force: true));
    Uri base() => Uri.parse('http://127.0.0.1:${server.port}');

    test('real /healthz body (captured from local nginx) is healthy', () async {
      reply = (r) => r.response
        ..headers.contentType = ContentType.json
        ..write(
          '{"ok":true,"version":"1.1.0","ingest":{"queue_depth":0,'
          '"replayed":3,"dropped":0,"updated_at":"2026-09-23T09:12:07"}}',
        )
        ..close();
      final result = await const HttpLocalBackendProber().probe(base());
      expect(result.outcome, ProbeOutcome.healthy);
      expect(seenHeaders.last.value('x-api-key'), isNull);
      expect(seenHeaders.last.value('authorization'), isNull);
    });
    test('SPA html fallback is not a backend', () async {
      reply = (r) => r.response
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><html></html>')
        ..close();
      final result = await const HttpLocalBackendProber().probe(base());
      expect(result.outcome, ProbeOutcome.notBackend);
    });
    test('closed port is unreachable', () async {
      final url = base();
      await server.close(force: true);
      final result = await const HttpLocalBackendProber().probe(url);
      expect(result.outcome, ProbeOutcome.unreachable);
      expect(result.detail, isNotEmpty);
    });
  });

  group('test connection messages', () {
    final base = Uri.parse('http://192.168.1.187:18000');
    test('each outcome has a specific reason', () {
      expect(connectionTestMessage(healthy, base), startsWith('✓ 已連上本地後端'));
      expect(
        connectionTestMessage(
          const ProbeResult(ProbeOutcome.unreachable, detail: 'refused'),
          base,
        ),
        allOf(
          startsWith('✗ 無法連線'),
          contains('192.168.1.187:18000'),
          contains('refused'),
        ),
      );
      expect(
        connectionTestMessage(const ProbeResult(ProbeOutcome.timeout), base),
        startsWith('✗ 逾時'),
      );
      expect(
        connectionTestMessage(
          const ProbeResult(ProbeOutcome.notBackend, status: 200),
          base,
        ),
        contains('回應不是本地後端'),
      );
      expect(
        connectionTestMessage(
          const ProbeResult(ProbeOutcome.httpError, status: 404),
          base,
        ),
        contains('HTTP 404'),
      );
      expect(
        connectionTestMessage(
          const ProbeResult(ProbeOutcome.degraded, status: 503),
          base,
        ),
        contains('資料庫尚未就緒'),
      );
    });
  });
}
