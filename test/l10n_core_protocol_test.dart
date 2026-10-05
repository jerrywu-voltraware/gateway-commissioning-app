// B3 i18n (docs/i18n.md): English texts of core/protocol, rescue codes,
// station change, identify, topology, proximity, PTU RSSI, local backend
// address/probe, backend key, BLE link stages and recent data. The default
// (繁中) texts are covered by the existing tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/backend_key.dart';
import 'package:gateway_commissioning/core/gateway_proximity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/identify.dart';
import 'package:gateway_commissioning/core/local_backend_address.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/ptu_rssi.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/core/station_change.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/data/recent_data_api.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';

import 'support/l10n.dart';

final _cjk = RegExp(r'[一-鿿]');

void main() {
  group('protocol', () {
    test('GatewayFailure messages follow the language', () {
      expect(const GatewayFailure('otp_invalid').message, '一次性密碼錯誤');
      useLanguage(AppLanguage.en);
      expect(
        const GatewayFailure('otp_invalid').message,
        'Wrong one-time password',
      );
      expect(
        const GatewayFailure('test_mode_stuck').message,
        startsWith('The gateway is still in test mode'),
      );
      expect(
        const GatewayFailure.gateway('').message,
        'The gateway reported a failure (no reason given).',
      );
      expect(
        const GatewayFailure.gateway('weird').message,
        'The gateway reported a failure: weird',
      );
      expect(
        const GatewayFailure('ble_error', detail: '133 unknown').message,
        contains('Bluetooth error 133'),
      );
      expect(phoneLinkLostText, contains('[Reconnect and continue]'));
      expect(reconnectFailedText, startsWith('Reconnect failed'));
      for (final code in [
        'cancelled',
        'phone_link_lost',
        'identity_archived',
        'reconnect_failed',
        'fleet_unconfirmed',
        'backend_unavailable',
        'missing_backend_key',
        'something_else',
      ]) {
        expect(
          GatewayFailure(code).message,
          isNot(contains(_cjk)),
          reason: code,
        );
      }
    });

    test('HTTP and network failures keep their technical tail', () {
      useLanguage(AppLanguage.en);
      const notFound = GatewayFailure.http(
        status: 404,
        endpoint: 'GET /api/gateways/81/2/status',
        detail: 'gateway_not_found',
        backend: 'backend http://x',
      );
      expect(
        notFound.message,
        allOf(
          startsWith(
            'The backend has no record of this gateway (site 81 / gateway 2).',
          ),
          contains('backend http://x'),
          contains(
            '[HTTP 404 · GET /api/gateways/81/2/status · gateway_not_found]',
          ),
        ),
      );
      expect(
        notFound.withCause('It was archived.').message,
        contains(
          '(the APP is connected to backend http://x). It was archived.',
        ),
      );
      expect(
        const GatewayFailure.http(status: 503, endpoint: 'GET /x').message,
        startsWith('Backend internal error (HTTP 503)'),
      );
      expect(
        const GatewayFailure.network(endpoint: 'GET /x').message,
        allOf(
          startsWith('Cannot reach the configured backend.'),
          endsWith('[GET /x]'),
        ),
      );
      expect(
        const GatewayFailure.targetMismatch(
          gatewayTarget: 'production',
          appTarget: 'local test host',
        ).message,
        startsWith(
          'The gateway sends its data to production, but the phone is '
          'connected to local test host',
        ),
      );
      expect(
        GatewayFailure.unexpected(StateError('boom')).message,
        startsWith('Unexpected APP error: '),
      );
    });

    test('the zh failure texts did not change', () {
      const notFound = GatewayFailure.http(
        status: 404,
        endpoint: 'GET /api/gateways/81/2/status',
        detail: 'gateway_not_found',
      );
      expect(
        notFound.message,
        '後端找不到此閘道器（站 81 / 閘道器 2）。閘道器的資料可能上傳到其他後端環境'
        '（例如正式站），而 APP 目前連的是 目前設定的後端。\n'
        '[HTTP 404 · GET /api/gateways/81/2/status · gateway_not_found]',
      );
      expect(
        const GatewayFailure('test_mode_stuck').message,
        contains('「切回正常模式」'),
      );
      expect(bleErrorText(null), '無法連上閘道器（藍牙錯誤），請靠近閘道器後重試');
    });
  });

  test('rescue code labels are screen text; wire names never change', () {
    expect(RescueCode.helpOnly.label, '畫面沒有錯誤，現場主動求助');
    useLanguage(AppLanguage.en);
    expect(RescueCode.helpOnly.label, 'No error on screen; asking for help');
    for (final code in RescueCode.values) {
      expect(code.label, isNot(contains(_cjk)), reason: code.wire);
      expect(code.label, isNot(code.wire));
      expect(RescueCode.ofWire(code.wire), code);
    }
    expect(RescueCode.gwBusy.wire, 'GW_BUSY');
  });

  test('station change title and checklist', () {
    useLanguage(AppLanguage.en);
    const change = StationChange(
      site: 81,
      gateway: 1,
      stage: StationChangeStage.restarting,
    );
    expect(change.title, 'Gateway restarting, please wait');
    expect(change.items.map((i) => i.label), [
      'Apply site settings',
      'Restart and reconnect',
      'Check the station number and Wi-Fi',
    ]);
    expect(change.items[1].note, 'Waiting for the gateway to start');
  });

  test('identify texts', () {
    useLanguage(AppLanguage.en);
    expect(identifySecondsError, contains('2–10'));
    expect(
      gatewayIdentifyText({'duration_ms': 4000}),
      'Gateway double-blinks for 4 seconds',
    );
    expect(
      gatewayIdentifyText({'duration_ms': 1000}),
      'Gateway double-blinks for 1 second',
    );
    expect(
      gatewayIdentifyText({'duration_ms': 0}),
      'Gateway stopped identifying; normal light restored',
    );
    expect(
      gatewayIdentifyText({'target': 'ptu'}),
      'PTU only; gateway light unchanged',
    );
  });

  test('topology and proximity labels', () {
    expect(GatewayTopology.direct.shortLabel, '直連模式');
    useLanguage(AppLanguage.en);
    expect(GatewayTopology.direct.shortLabel, 'One-to-one mode');
    expect(GatewayTopology.star.label, 'Star mode (1 gateway : several PTUs)');
    expect(gatewayNearestLabel, 'Nearest');
    expect(gatewayNearestHint, contains('bulb'));
    expect(gatewayCloseHint, contains('bulb'));
  });

  test('PTU RSSI words', () {
    useLanguage(AppLanguage.en);
    expect(ptuRssiText({'rssi': -65}), 'Scan -65 dBm');
    expect(ptuRssiText({'rssi': -65, 'rssi_stale': true}), 'Last -65 dBm');
    expect(ptuRssiText({'rssi': -65, 'connected': true}), 'Cached -65 dBm');
    expect(
      ptuRssiText({'rssi': -65, 'connected': true, 'rssi_age_ms': 16000}),
      'Last -65 dBm',
    );
    expect(
      ptuRssiText({'rssi': -65, 'connected': true, 'rssi_age_ms': 5000}),
      '-65 dBm',
    );
  });

  test('local backend address, probe and backend key', () {
    useLanguage(AppLanguage.en);
    expect(localHostError(''), "Enter the PC's IP address");
    expect(localHostError('8.8.8.8'), startsWith('LAN addresses only'));
    expect(localPortError('0'), 'Port must be 1–65535');
    expect(missingBackendKeyText, startsWith('This build has no back office'));
    expect(localBackendHint, contains('allow_local_api_lan.ps1'));
    final base = Uri.parse('http://192.168.1.187:18000');
    expect(
      connectionTestMessage(
        const ProbeResult(ProbeOutcome.healthy, version: '1.35.2'),
        base,
      ),
      '✓ Connected to the local backend (version 1.35.2)',
    );
    expect(
      connectionTestMessage(const ProbeResult(ProbeOutcome.timeout), base),
      allOf(startsWith('✗ Timed out: '), contains('timed out]')),
    );
    expect(
      connectionTestMessage(
        const ProbeResult(ProbeOutcome.notBackend, status: 200),
        base,
      ),
      startsWith('✗ Not the local backend (HTTP 200)'),
    );
  });

  test(
    'BLE link stage texts (demo link shares the connecting stage)',
    () async {
      useLanguage(AppLanguage.en);
      final stages = <String>[];
      final demo = DemoSystem();
      await demo.connect(
        const GatewayPeer('demo-gateway', 'GIOS-S1-GW01', -42),
        onStage: stages.add,
      );
      expect(stages, ['Connecting to the gateway']);
      expect(L10n.current.bleGatewayLink_stageRetry(2), 'Retry #2');
    },
  );

  test('recent data words', () {
    useLanguage(AppLanguage.en);
    expect(intervalWords(300000), '5 minutes');
    expect(intervalWords(60000), '1 minute');
    expect(intervalWords(1000), '1 second');
    expect(intervalWords(1500), '1.5 seconds');
    final now = DateTime(2026, 10, 5, 12);
    expect(
      recentSummaryText(
        const RecentData(siteId: 1, gatewayId: 1, count: 2, items: []),
        now,
      ),
      'Latest time unknown · 2 records',
    );
    expect(
      recentSummaryText(
        const RecentData(siteId: 1, gatewayId: 1, count: 1, items: []),
        now,
      ),
      'Latest time unknown · 1 record',
    );
    expect(L10n.current.recentDataApi_secondsAgo(7), '7 seconds ago');
    expect(
      recentDataErrorText(const GatewayFailure('authentication')),
      "Cannot reach the back office (The back office refused this APP's "
      'credential. Contact the administrator to update the APP)',
    );
  });
}
