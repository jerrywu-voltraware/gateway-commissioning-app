import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/cert_pin.dart';
import 'package:gateway_commissioning/data/dashboard_api.dart';

/// Test-only TLS material (test/fixtures/tls/README.txt).
List<int> _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();

/// An HTTPS server on 127.0.0.1 sending [chain] (PEM files, leaf first).
Future<HttpServer> _serve(List<String> chain, String key) async {
  final context = SecurityContext()
    ..useCertificateChainBytes([for (final c in chain) ..._fixture(c)])
    ..usePrivateKeyBytes(_fixture(key));
  final server = await HttpServer.bindSecure('127.0.0.1', 0, context);
  server.listen((request) {
    request.response
      ..statusCode = 200
      ..write('ok');
    request.response.close();
  }, onError: (_) {});
  return server;
}

/// GET / through [apiHttpClientFor] with [server] as the production base.
Future<int> _get(HttpServer server, {String ca = '', String pin = ''}) async {
  final base = 'https://127.0.0.1:${server.port}';
  final client = apiHttpClientFor(
    Uri.parse(base),
    pin: pin,
    caPemB64: ca,
    productionBase: base,
  );
  try {
    final response = await (await client.getUrl(Uri.parse('$base/'))).close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}
void main() {
  final der = List<int>.generate(300, (i) => i % 251);
  final pin = sha256.convert(der).toString();
  final colonPin = [
    for (var i = 0; i < pin.length; i += 2) pin.substring(i, i + 2),
  ].join(':').toUpperCase();
  const prod = 'https://46.250.255.172';

  test('matching fingerprint is accepted (any case / colons)', () {
    expect(certMatchesPin(der, pin), isTrue);
    expect(certMatchesPin(der, colonPin), isTrue);
  });

  test('mismatching fingerprint is rejected', () {
    expect(certMatchesPin([...der, 0], pin), isFalse);
    expect(certMatchesPin(der, 'ab' * 32), isFalse);
    expect(certMatchesPin(der, 'not-hex'), isFalse);
    expect(certMatchesPin(der, ''), isFalse);
  });

  test('no pin configured: nothing pinned', () {
    expect(pinFor(Uri.parse(prod), pin: '', productionBase: prod), isNull);
  });

  test('pin applies to the production origin only', () {
    expect(pinFor(Uri.parse(prod), pin: colonPin, productionBase: prod), pin);
    expect(
      pinFor(Uri.parse('https://example.com'), pin: pin, productionBase: prod),
      isNull,
    );
    expect(
      pinFor(
        Uri.parse('http://192.168.1.10:18000'),
        pin: pin,
        productionBase: prod,
      ),
      isNull,
    );
    // Malformed pin fails closed on production.
    final bad = pinFor(Uri.parse(prod), pin: 'xyz', productionBase: prod);
    expect(bad, isNotNull);
    expect(certMatchesPin(der, bad!), isFalse);
  });

  test('09-28: the default production base (its IP) is the pinned one', () {
    expect(pinFor(Uri.parse(productionApiBase), pin: pin), pin);
    expect(pinFor(Uri.parse('https://46.250.255.172/api'), pin: pin), pin);
    expect(pinFor(Uri.parse('https://46.250.255.172:8443'), pin: pin), isNull);
    expect(pinFor(Uri.parse('http://46.250.255.172'), pin: pin), isNull);
  });

  group('r33: production trusts the build CA (API_CA_PEM_B64)', () {
    final caB64 = base64.encode(_fixture('ca.pem'));
    // SHA-256 of the leaf's DER (the PEM body).
    final leafPin = sha256
        .convert(
          base64.decode(
            utf8
                .decode(_fixture('leaf.pem'))
                .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
                .replaceAll(RegExp(r'\s'), ''),
          ),
        )
        .toString();

    test('leaf + CA chain verifies against the CA (IP SAN)', () async {
      final server = await _serve(['leaf.pem', 'ca.pem'], 'leaf.key');
      addTearDown(() => server.close(force: true));
      expect(await _get(server, ca: caB64), 200);
    });

    test('a leaf alone (CA not sent) still verifies against the CA', () async {
      final server = await _serve(['leaf.pem'], 'leaf.key');
      addTearDown(() => server.close(force: true));
      expect(await _get(server, ca: caB64), 200);
    });

    test('a self-signed certificate is refused', () async {
      final server = await _serve(['self.pem'], 'self.key');
      addTearDown(() => server.close(force: true));
      await expectLater(
        _get(server, ca: caB64),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('a CA-signed certificate for another IP is refused', () async {
      final server = await _serve(['otherip.pem', 'ca.pem'], 'otherip.key');
      addTearDown(() => server.close(force: true));
      await expectLater(
        _get(server, ca: caB64),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('without the CA the chain is refused (system roots only)', () async {
      final server = await _serve(['leaf.pem', 'ca.pem'], 'leaf.key');
      addTearDown(() => server.close(force: true));
      await expectLater(_get(server), throwsA(isA<HandshakeException>()));
    });

    test('CA + pin: the leaf must match too', () async {
      final server = await _serve(['leaf.pem', 'ca.pem'], 'leaf.key');
      addTearDown(() => server.close(force: true));
      expect(await _get(server, ca: caB64, pin: leafPin), 200);
      await expectLater(
        _get(server, ca: caB64, pin: 'ab' * 32),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('a CA value that is not a PEM trusts nothing extra', () async {
      expect(caPemBytes(''), isNull);
      expect(caPemBytes('not base64!'), isEmpty);
      expect(caPemBytes(base64.encode(utf8.encode('hello'))), isEmpty);
      expect(caPemBytes(caB64), isNotEmpty);
      final server = await _serve(['leaf.pem', 'ca.pem'], 'leaf.key');
      addTearDown(() => server.close(force: true));
      await expectLater(
        _get(server, ca: base64.encode(utf8.encode('hello'))),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('plain http to the production host is refused before sending', () {
      expect(
        DashboardApi().login('http://46.250.255.172', 'key'),
        throwsA(
          isA<GatewayFailure>().having((f) => f.code, 'code', 'https_required'),
        ),
      );
    });
  });
}
