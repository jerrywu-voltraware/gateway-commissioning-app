import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/data/recent_gateways.dart';

void main() {
  group('r31 backlog', () {
    test('1. a DIRECT_PICK help carries the direct reason as fail_code', () {
      DirectStatus? d(Map<String, dynamic> m) => DirectStatus.from(m);
      expect(directReasonFailCode(null), isNull);
      expect(
        directReasonFailCode(
          d({'state': 'no_candidate', 'select_reason': 'none'}),
        ),
        'direct_no_ptu',
      );
      expect(
        directReasonFailCode(d({'state': 'bound_missing'})),
        'direct_bound_missing',
      );
      expect(
        directReasonFailCode(
          d({'state': 'connected', 'select_reason': 'ambiguous'}),
        ),
        'direct_ambiguous',
      );
      expect(
        directReasonFailCode(d({'state': 'connected', 'select_reason': 'ok'})),
        isNull,
      );
    });

    test('3. the report name follows the current site / gateway numbers', () {
      expect(currentGatewayName('GIOS-S56-GW01', 80, 1), 'GIOS-S80-GW01');
      expect(currentGatewayName('GIOS-S56-GW01', 80, 12), 'GIOS-S80-GW12');
      expect(currentGatewayName('MyGateway', 80, 1), 'MyGateway');
      expect(currentGatewayName('GIOS-S56-GW01', null, 1), 'GIOS-S56-GW01');
      expect(currentGatewayName(null, 80, 1), isNull);
    });

    test('4. archived / configured / why the backend status is unknown', () {
      const uid = 'AABBCCDDEEFF';
      final row = {'last_seen_mac': 'AA:BB:CC:DD:EE:FF', 'online': true};
      expect(
        backendPresence(uid, const [], archived: [row]),
        gatewayArchivedLabel,
      );
      expect(backendPresence(uid, const []), contains('沒有這個 MAC'));
      expect(backendPresence(uid, [row, row]), contains('2 筆'));
      expect(
        backendPresence(uid, [
          {...row, 'conflict_flag': 1},
        ]),
        contains('身分衝突'),
      );
      expect(gatewayConfigured(uid, [row]), isTrue);
      expect(gatewayConfigured(uid, const []), isFalse);
      expect(gatewayConfigured(null, [row]), isFalse);
      expect(
        backendQueryFailedText(Exception('boom')),
        startsWith('後端狀態未知・查詢失敗'),
      );
    });

    test('5. after 15 s the pick shows its advertising RSSI as 廣播值', () {
      final picked = DirectStatus.from({
        'state': 'connected',
        'ptu_mac': '90:5F:E8:9A:96:00',
        'ptu_rssi': 0,
        'self_adv_rssi_med': -49,
      })!;
      expect(directPickRssiText(picked), directAdvRssiText(-49));
      expect(directPickRssiText(picked, stale: true), '-49 dBm（廣播值）');
      final bare = DirectStatus.from({
        'state': 'connected',
        'ptu_mac': '90:5F:E8:9A:96:00',
        'ptu_rssi': 0,
      })!;
      expect(directPickRssiText(bare), directRssiReadingText);
      expect(
        directPickRssiText(bare, stale: true, lastAdv: -52),
        '-52 dBm（廣播值）',
      );
      expect(directLinkRssiWait, const Duration(seconds: 15));
    });
  });
}
