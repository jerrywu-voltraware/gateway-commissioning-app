import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/cert_pin.dart';

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
}
