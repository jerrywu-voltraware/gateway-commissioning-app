import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/dashboard_api.dart';

void main() {
  test('Local HTTP accepts private IPv4 but excludes public hosts', () {
    for (final host in [
      '192.168.0.12',
      '10.0.2.2',
      '172.16.0.1',
      '172.31.255.254',
      '127.0.0.1',
      'localhost',
    ]) {
      expect(isLocalApiHost(host), isTrue);
    }
    for (final host in [
      '172.32.0.1',
      '172.15.0.1',
      '8.8.8.8',
      'example.com',
      '192.168.999.1',
    ]) {
      expect(isLocalApiHost(host), isFalse);
    }
  });
}
