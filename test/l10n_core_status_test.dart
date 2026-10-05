// B3 i18n: English texts of connection_status / verify_diagnosis /
// auto_checklist / backend_environment, and the language-free upload flag.
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/auto_checklist.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/connection_status.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/application/verify_diagnosis.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/progress_checklist.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';

import 'support/l10n.dart';

const _healthy = ProbeResult(ProbeOutcome.healthy, status: 200, version: '1');
const _peer = GatewayPeer('id', 'GIOS-S1-GW01', -40);
const _local = BackendEnvState(
  environment: BackendEnv.local,
  localHost: '192.168.1.187',
  loaded: true,
);

Map<String, dynamic> _localTarget({bool? connected}) => {
  'fw_version': '1.7.3',
  'site_id': 1,
  'gateway_id': 1,
  'mqtt_target': 'local',
  'mqtt_host': '192.168.1.187',
  'mqtt_port': 8883,
  'mqtt_connected': ?connected,
};

ConnectionStatus _uploading() => connectionStatus(
  env: _local,
  state: CommissionState(
    step: 6,
    peer: _peer,
    config: _localTarget(connected: true),
    loggedIn: true,
  ),
  probe: _healthy,
);

ConnectionStatus _linkLost() => connectionStatus(
  env: _local,
  state: CommissionState(
    step: 2,
    peer: _peer,
    config: _localTarget(connected: true),
    uploadWatch: UploadWatch.linkLost,
  ),
  probe: _healthy,
);

void main() {
  group('connection_status', () {
    test('uploading is a flag, the same in both languages', () {
      final zh = _uploading();
      expect(zh.gateway.status, '✓ 資料上傳中');
      expect(zh.gateway.uploading, isTrue);
      expect(_linkLost().gateway.uploading, isFalse);
      useLanguage(AppLanguage.en);
      final en = _uploading();
      expect(en.gateway.status, '✓ Uploading data');
      expect(en.gateway.status, uploadingStatusText);
      expect(en.gateway.uploading, isTrue);
      expect(_linkLost().gateway.uploading, isFalse);
    });

    test('English rows, summary and details', () {
      useLanguage(AppLanguage.en);
      final status = connectionStatus(
        env: _local,
        state: CommissionState(
          step: 2,
          peer: _peer,
          config: _localTarget(connected: true),
        ),
        probe: _healthy,
      );
      expect(status.phone.where, 'Local test host');
      expect(status.phone.status, '✓ Connected');
      expect(status.summary, '✓ Local test: phone and gateway both connected');
      expect(status.details, contains('Firmware version: 1.7.3'));
      expect(
        status.details,
        contains('Gateway upload target: MQTT local 192.168.1.187:8883 (TLS)'),
      );
      expect(
        status.details,
        contains('Backend health check (GET /healthz): OK (version 1)'),
      );
      expect(
        subnetHint(const MqttTarget.local('192.168.1.187'), '10.0.0.5'),
        'The gateway is on the 10.0.0.x subnet and may not reach the test '
        'host 192.168.1.187. Make sure the gateway and this computer use the '
        'same Wi-Fi (tap [Use another Wi-Fi]).',
      );
      expect(_linkLost().hint, startsWith('Bluetooth to the gateway dropped'));
    });

    test('繁中 texts are unchanged', () {
      expect(placeOf(const MqttTarget.production()), '正式站');
      expect(
        subnetHint(
          const MqttTarget.local('192.168.1.187'),
          '10.0.0.5',
          wifiAction: '重設 Wi-Fi',
        ),
        '閘道器目前在 10.0.0.x 網段，可能連不到測試主機 192.168.1.187。'
        '請確認閘道器和這台電腦連同一個 Wi-Fi（可用「重設 Wi-Fi」）。',
      );
    });
  });

  group('verify_diagnosis', () {
    test('English reasons and lines', () {
      useLanguage(AppLanguage.en);
      expect(
        ptuVerifyReasons(
          latest: {'online': false, 'lag_seconds': 75, 'error_num': 0},
        ),
        ['Offline', 'Lag 75 s', 'Data time unreadable'],
      );
      expect(
        missingGatewayCause(),
        'The gateway may upload to another backend (e.g. production).',
      );
      final text = verifyDiagnosis(
        ids: const [3],
        install: const {'all_ok': true},
        rows: const [],
        fleet: const {'online': true},
        previous: const {},
        site: 81,
        gateway: 1,
        consecutive: 1,
        backend: 'backend',
      );
      expect(text, contains('Passed 1 / 3 in a row.'));
      expect(
        text,
        contains('PTU #3: PTU missing from latest data (/api/latest)'),
      );
    });

    test('繁中 reasons are unchanged', () {
      expect(
        ptuVerifyReasons(
          latest: {'online': false, 'lag_seconds': 75, 'error_num': 0},
        ),
        ['離線', '延遲 75 秒', '資料時間無法解析'],
      );
    });
  });

  group('auto_checklist', () {
    Checklist connected() =>
        connectChecklist().done(connectItemBle).done(connectItemStatus);

    test('English item notes', () {
      useLanguage(AppLanguage.en);
      final lost = CommissionState(
        step: 2,
        peer: _peer,
        config: _localTarget(connected: true),
        uploadWatch: UploadWatch.linkLost,
      );
      final lostView = connectChecklistView(
        connected(),
        lost,
        networkCheck(state: lost, env: _local),
      );
      expect(
        lostView.item(connectItemWifi)!.note,
        "Bluetooth lost; can't confirm",
      );
      final old = CommissionState(
        step: 2,
        peer: _peer,
        config: const {'fw_version': '1.6.0'},
      );
      final oldView = connectChecklistView(
        connected(),
        old,
        networkCheck(state: old, env: _local),
      );
      expect(
        oldView.item(connectItemBackend)!.note,
        "This firmware can't report; checked in the final data check",
      );
    });
  });

  group('backend_environment', () {
    test('English labels and hints', () {
      expect(envLabel(BackendEnv.custom), '其他網址');
      expect(localUnavailableLabel, '本地測試（此版本不可用）');
      useLanguage(AppLanguage.en);
      expect(envLabel(BackendEnv.production), 'Production');
      expect(envLabel(BackendEnv.local), 'Local test');
      expect(localUnavailableLabel, 'Local test (not in this build)');
      expect(localUnavailableText, startsWith("The release app can't use"));
      expect(
        environmentChangeHint(
          const BackendEnvState(),
          const BackendEnvState(loaded: true),
          buildDefault: BackendEnv.local,
        ),
        'Backend: Production (kept from last time; switch at top right)',
      );
    });
  });
}
