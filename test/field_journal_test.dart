// Field rescue v1 (§2.4 commands, §2.5 masking): the journal keeps 30
// commands, merges busy retries, and nothing in a diagnostics package
// carries the Wi-Fi password, the login password or a secret key.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_journal.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/data/contracts.dart';

const _wifiPassword = 'S3cret-Wifi-Pw';
const _loginPassword = 'Login-Pw-7788';

void main() {
  test('set_wifi keeps only the SSID; the whole package has no password', () {
    final journal = CommandJournal()..addSecret(_loginPassword);
    journal.ble(
      'set_wifi',
      {'ssid': 'Office-2G', 'password': _wifiPassword},
      status: 'ok',
      durMs: 412,
      result: 'wifi switching to Office-2G',
    );
    // The password echoed back anywhere is masked too.
    journal.ble(
      'get_config',
      const {},
      status: 'ok',
      result: {
        'wifi_ssid': 'Office-2G',
        'wifi_pass': _wifiPassword,
        'note': 'key=$_wifiPassword',
        'mqtt_token': 'abc123456',
      },
    );
    journal.ble(
      'set_config',
      const {'api_key': 'k-1234567', 'otp': '123456', 'max_connections': 5},
      status: 'fail',
      error: 'rejected $_wifiPassword',
    );
    final first = journal.snapshot().first;
    expect(first['params'], {'ssid': 'Office-2G', 'password': '***'});

    const state = CommissionState(
      step: 4,
      error: '等待超時，請確認裝置與網路後重試。',
      errorDetail: 'GatewayFailure(timeout) $_loginPassword',
      config: {'site_id': 80, 'gateway_id': 1, 'otp_enabled': false},
      peer: GatewayPeer('p', 'GIOS-S80-GW01', -50),
    );
    final diag = buildDiagnostics(
      sessionId: 'a' * 32,
      shortCode: '482915',
      diagSeq: 1,
      trigger: 'timeout',
      now: DateTime(2026, 9, 26, 14, 3),
      input: const FieldInput(state: state, env: BackendEnvState(loaded: true)),
      code: RescueCode.cmdTimeout,
      commands: journal.snapshot(),
      sections: diagnosticSections(state, now: DateTime(2026, 9, 26)),
      secrets: journal.secrets,
    );
    final text = jsonEncode(diag);
    expect(text, isNot(contains(_wifiPassword)));
    expect(text, isNot(contains(_loginPassword)));
    expect(text, isNot(contains('k-1234567')));
    expect(text, isNot(contains('abc123456')));
    expect(text, contains('Office-2G'));
    // The whole package goes through the same key rule as the backend's,
    // so nothing is left for its second pass (redacted = 0); a flag under a
    // secret-looking key is a state and stays readable.
    expect(
      (diag['gateway'] as Map)['config'],
      containsPair('otp_enabled', false),
    );
    expect(redactKeys(diag), diag);
    expect(isSecretValue(redactedValue), isFalse);
    expect(redactKeys({'otp': 123456, 'token': '', 'pass': null}), {
      'otp': '***',
      'token': '',
      'pass': null,
    });
  });

  test('ring of 30, oldest dropped', () {
    final journal = CommandJournal();
    for (var i = 0; i < 45; i++) {
      journal.ble('ping', {'n': i}, status: 'ok', durMs: 1);
    }
    final list = journal.snapshot();
    expect(list, hasLength(journalCapacity));
    expect((list.first['params'] as Map)['n'], 15);
    expect((list.last['params'] as Map)['n'], 44);
  });

  test('consecutive busy answers become one busy_retry ×n', () {
    final journal = CommandJournal();
    journal.ble('get_net_status', const {}, status: 'ok');
    for (var i = 0; i < 4; i++) {
      journal.ble('scan_ble_discover', const {'duration': 10}, status: 'busy');
    }
    journal.ble('scan_ble_discover', const {'duration': 10}, status: 'ok');
    final list = journal.snapshot();
    expect(list, hasLength(3));
    expect(list[1]['status'], 'busy_retry');
    expect(list[1]['result'], 'busy ×4');
    expect(list[2]['status'], 'ok');
    // The report's last_command never says busy_retry (not in its enum).
    journal.ble('ping', const {}, status: 'busy');
    expect(journal.lastCommand(DateTime.now())!['status'], 'fail');
  });

  test('HTTP entries: METHOD /path only, never the query or body', () {
    final journal = CommandJournal();
    journal.http(
      'GET',
      '/api/latest?mac=AA:BB:CC&token=zzz',
      status: 'ok',
      httpStatus: 200,
      durMs: 61,
    );
    final entry = journal.snapshot().single;
    expect(entry['op'], 'GET /api/latest');
    expect(entry['ch'], 'http');
    expect(entry['http_status'], 200);
    expect(jsonEncode(entry), isNot(contains('zzz')));
  });

  test('long results are cut to 300 characters', () {
    final journal = CommandJournal();
    journal.ble('get_ble_devices', const {}, status: 'ok', result: 'x' * 900);
    expect(
      (journal.snapshot().single['result'] as String).length,
      journalResultLimit,
    );
  });

  test('the key rule of §2.5', () {
    for (final key in [
      'password',
      'wifi_pwd',
      'client_secret',
      'token',
      'otp_code',
      'api_key',
      'API-KEY',
      'Authorization',
      'cookie',
    ]) {
      expect(secretKeyPattern.hasMatch(key), isTrue, reason: key);
    }
    for (final key in ['ssid', 'mac', 'ip', 'site_id', 'rssi']) {
      expect(secretKeyPattern.hasMatch(key), isFalse, reason: key);
    }
  });
}
