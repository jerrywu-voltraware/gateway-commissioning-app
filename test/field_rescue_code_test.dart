// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §3.1 / §3.2): every
// classification rule, the code list as the backend's FIELD_CODES, and the
// firmware review fix — Wi-Fi reason 2 (AUTH_EXPIRE) is not a wrong
// password.
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/gateway_net.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';

/// §3.2, in the document's order (the contract with field_cards.py).
const _contractCodes = [
  'PHONE_BT_OFF',
  'PHONE_PERMISSION',
  'GW_NOT_FOUND',
  'BLE_CONNECT_FAIL',
  'BLE_LINK_DROP',
  'BLE_RECONNECT_FAIL',
  'GW_REBOOTED',
  'GW_BUSY',
  'GW_LOW_MEMORY',
  'GW_AUTH_REFUSED',
  'GW_REJECTED',
  'GW_FULL',
  'CMD_TIMEOUT',
  'FW_TOO_OLD',
  'WIFI_PASSWORD',
  'WIFI_NOT_FOUND',
  'WIFI_WEAK',
  'WIFI_UNKNOWN',
  'UPLOAD_NOT_STARTED',
  'UPLOAD_TARGET',
  'IDENTITY_CONFLICT',
  'IDENTITY_REPLACE',
  'PTU_NONE_FOUND',
  'PTU_CONNECT_FAIL',
  'PTU_NO_RESPONSE',
  'PTU_WRONG_DEVICE',
  'PTU_RESIDUAL',
  'DIRECT_PICK',
  'MONITOR_UNCONFIRMED',
  'VERIFY_INCOMPLETE',
  'BACKEND_DOWN',
  'BACKEND_AUTH',
  'GW_NOT_IN_BACKEND',
  'APP_UNEXPECTED',
  'STEP_STUCK',
  'HELP_ONLY',
];

String? _code(
  GatewayFailure f, {
  bool rebooted = false,
  bool? safe = true,
  int ctlStep = 4,
  List<String> assign = const [],
}) => rescueCodeOf(
  f,
  rebooted: rebooted,
  safe: safe,
  ctlStep: ctlStep,
  assignFailTexts: assign,
)?.wire;

void main() {
  test('wire names are exactly the §3.2 list (36, upper case)', () {
    final wires = RescueCode.values.map((c) => c.wire).toList();
    expect(wires, _contractCodes);
    expect(wires.toSet().length, 36);
    for (final w in wires) {
      expect(RegExp(r'^[A-Z0-9_]{3,32}$').hasMatch(w), isTrue, reason: w);
    }
  });

  group('§3.1 rules, first match wins', () {
    test('1 restart beats everything, even a timeout', () {
      expect(
        _code(const GatewayFailure('timeout'), rebooted: true),
        'GW_REBOOTED',
      );
      expect(
        _code(const GatewayFailure('phone_link_lost'), rebooted: true),
        'GW_REBOOTED',
      );
    });
    test('2 monitoring not confirmed', () {
      expect(
        _code(const GatewayFailure('timeout'), safe: false),
        'MONITOR_UNCONFIRMED',
      );
      expect(
        _code(const GatewayFailure('monitor_unconfirmed')),
        'MONITOR_UNCONFIRMED',
      );
    });
    test('3–7 phone and Bluetooth', () {
      expect(_code(const GatewayFailure('bluetooth_off')), 'PHONE_BT_OFF');
      expect(_code(const GatewayFailure('permission')), 'PHONE_PERMISSION');
      expect(_code(const GatewayFailure('location_off')), 'PHONE_PERMISSION');
      expect(
        _code(const GatewayFailure('ble_error', detail: '133 GATT')),
        'BLE_CONNECT_FAIL',
      );
      for (final c in ['phone_link_lost', 'disconnected', 'not_connected']) {
        expect(_code(GatewayFailure(c)), 'BLE_LINK_DROP', reason: c);
      }
      for (final c in ['reconnect_failed', 'target_reconnect']) {
        expect(_code(GatewayFailure(c)), 'BLE_RECONNECT_FAIL', reason: c);
      }
    });
    test('8–10 gateway memory, busy, refused', () {
      expect(
        _code(const GatewayFailure.gateway('low_memory')),
        'GW_LOW_MEMORY',
      );
      expect(
        _code(
          const GatewayFailure.gateway(
            'scan refused',
            detail: '{"error":"low_memory"}',
          ),
        ),
        'GW_LOW_MEMORY',
      );
      expect(_code(const GatewayFailure.gateway('busy')), 'GW_BUSY');
      expect(_code(const GatewayFailure('not_ready')), 'GW_BUSY');
      for (final c in [
        'otp_enabled',
        'otp_required',
        'otp_invalid',
        'otp_locked',
        'otp_reused',
        'time_not_synced',
        'expired',
      ]) {
        expect(_code(GatewayFailure(c)), 'GW_AUTH_REFUSED', reason: c);
      }
    });
    test('11 Wi-Fi by firmware reason', () {
      GatewayFailure wifi(int? r) => GatewayFailure(
        'wifi_failed',
        detail: r == null ? null : wifiFailedDetail(r),
      );
      expect(_code(wifi(15)), 'WIFI_PASSWORD');
      expect(_code(wifi(201)), 'WIFI_NOT_FOUND');
      expect(_code(wifi(200)), 'WIFI_WEAK');
      expect(_code(wifi(null)), 'WIFI_UNKNOWN');
      // Firmware review: AUTH_EXPIRE is weak signal / other.
      expect(_code(wifi(2)), 'WIFI_WEAK');
    });
    test('12–14 upload target and identity', () {
      expect(
        _code(
          const GatewayFailure.targetMismatch(
            gatewayTarget: '正式站',
            appTarget: '本地',
          ),
        ),
        'UPLOAD_TARGET',
      );
      expect(
        _code(const GatewayFailure.targetReadback(actual: 'a', wanted: 'b')),
        'UPLOAD_TARGET',
      );
      expect(
        _code(const GatewayFailure.uploadTarget('bad_host')),
        'UPLOAD_TARGET',
      );
      expect(
        _code(const GatewayFailure('target_unsupported')),
        'UPLOAD_TARGET',
      );
      expect(_code(const GatewayFailure('conflict')), 'IDENTITY_CONFLICT');
      expect(
        _code(const GatewayFailure('new_site_required')),
        'IDENTITY_CONFLICT',
      );
      expect(
        _code(const GatewayFailure('replace_unsupported')),
        'IDENTITY_REPLACE',
      );
      expect(
        _code(const GatewayFailure('replace_pending')),
        'IDENTITY_REPLACE',
      );
    });
    test('15–19 PTU, direct, firmware, verify', () {
      expect(_code(const GatewayFailure('no_devices')), 'PTU_NONE_FOUND');
      expect(_code(const GatewayFailure('gateway_full')), 'GW_FULL');
      for (final c in [
        'direct_no_ptu',
        'direct_pick_missing',
        'direct_switch_failed',
        'direct_threshold_not_saved',
        'identify_no_ptu',
      ]) {
        expect(_code(GatewayFailure(c)), 'DIRECT_PICK', reason: c);
      }
      expect(_code(const GatewayFailure('direct_unsupported')), 'FW_TOO_OLD');
      expect(_code(const GatewayFailure('identify_unsupported')), 'FW_TOO_OLD');
      expect(
        _code(const GatewayFailure('incomplete'), ctlStep: 6),
        'VERIFY_INCOMPLETE',
      );
    });
    test('20–22 backend', () {
      expect(_code(const GatewayFailure('authentication')), 'BACKEND_AUTH');
      expect(
        _code(
          const GatewayFailure.http(
            status: 404,
            endpoint: 'GET /api/gateways/80/1/health',
            detail: 'gateway_not_found',
          ),
        ),
        'GW_NOT_IN_BACKEND',
      );
      expect(
        _code(const GatewayFailure.network(endpoint: 'GET /api/x')),
        'BACKEND_DOWN',
      );
      expect(
        _code(const GatewayFailure.http(status: 500, endpoint: 'GET /api/x')),
        'BACKEND_DOWN',
      );
      for (final c in [
        'backend_unavailable',
        'bad_response',
        'https_required',
      ]) {
        expect(_code(GatewayFailure(c)), 'BACKEND_DOWN', reason: c);
      }
    });
    test('23–24 timeout: step 5 upload, else the command', () {
      expect(
        _code(const GatewayFailure('timeout'), ctlStep: 3),
        'UPLOAD_NOT_STARTED',
      );
      expect(_code(const GatewayFailure('timeout'), ctlStep: 4), 'CMD_TIMEOUT');
      expect(_code(const GatewayFailure('timeout'), ctlStep: 5), 'CMD_TIMEOUT');
    });
    test('25 step 8 PTU failures by their row text', () {
      expect(
        _code(
          const GatewayFailure('timeout'),
          ctlStep: 5,
          assign: ['PTU 連線失敗，請確認 PTU 電源與距離'],
        ),
        'PTU_CONNECT_FAIL',
      );
      expect(ptuAssignRescueCode('PTU 沒有回應'), RescueCode.ptuNoResponse);
      expect(ptuAssignRescueCode('指派到錯誤裝置，請重試'), RescueCode.ptuWrongDevice);
      expect(
        ptuAssignRescueCode('回讀編號為 #3，不是指派的 #2，請重試'),
        RescueCode.ptuWrongDevice,
      );
      expect(
        _code(
          const GatewayFailure.gateway('write refused'),
          ctlStep: 5,
          assign: ['PTU 沒有回應'],
        ),
        'PTU_NO_RESPONSE',
      );
    });
    test('26–28 gateway refusal, cancel, anything else', () {
      expect(_code(const GatewayFailure.gateway('bad_param')), 'GW_REJECTED');
      expect(_code(const GatewayFailure('cancelled')), isNull);
      expect(
        _code(GatewayFailure.unexpected(StateError('x'))),
        'APP_UNEXPECTED',
      );
      expect(_code(const GatewayFailure('frame_size')), 'APP_UNEXPECTED');
    });
  });

  group('Wi-Fi reason 2 (AUTH_EXPIRE) is weak signal or other', () {
    test('kind, network-check text, set_wifi text, 技術細節', () {
      expect(wifiFailKindOf(2), WifiFailKind.weakOrOther);
      expect(wifiPasswordReasons.contains(2), isFalse);
      expect(wifiRescueCode(2), RescueCode.wifiWeak);
      expect(wifiProblemText('Office', reason: 2), isNot(contains('密碼')));
      expect(wifiProblemText('Office', reason: 2), contains('訊號太弱'));
      expect(wifiSetFailedText(2), isNot(contains('密碼')));
      expect(
        wifiDiscDetail({'wifi_last_disc_reason': 2}),
        contains('訊號弱或其他（代碼 2'),
      );
      // The real password failures are unchanged.
      expect(wifiDiscDetail({'wifi_last_disc_reason': 15}), contains('密碼可能錯誤'));
    });
  });
}
