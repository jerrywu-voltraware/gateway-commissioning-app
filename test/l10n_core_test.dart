// B3 i18n（docs/i18n.md）：core／application／data 層的英文斷言、§6
// 報告維持中文、§8.2 改成列舉／雙語辨識後在 zh 與 en 下行為一致。
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/install_report.dart';
import 'package:gateway_commissioning/application/network_check.dart';
import 'package:gateway_commissioning/core/assign_progress.dart';
import 'package:gateway_commissioning/core/gateway_reboot.dart';
import 'package:gateway_commissioning/core/progress_checklist.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/core/star_allow_list.dart';
import 'package:gateway_commissioning/data/dashboard_api.dart';
import 'package:gateway_commissioning/data/recent_gateways.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';

import 'support/l10n.dart';

const _env = BackendEnvState(loaded: true);

FieldInput _input(CommissionState state) => FieldInput(state: state, env: _env);

Map<String, dynamic> _sessionReport(CommissionState state) =>
    buildSessionReport(
      sessionId: 's1',
      seq: 1,
      event: 'status',
      now: DateTime(2026, 10, 5, 12),
      input: _input(state),
      status: 'running',
    );

const _uid = 'AABBCCDDEEFF';

Map<String, dynamic> _row({bool? online = true, String mac = _uid}) => {
  'last_seen_mac': mac,
  'site_id': 81,
  'gateway_id': 1,
  'online': online,
};

void main() {
  group('screen texts follow the language', () {
    test('assign_progress', () {
      const waiting = AssignStatus(AssignPhase.waiting);
      expect(assignStatusText(waiting), '等待中');
      expect(assignProgressText({'m': waiting}), '0/1 完成');
      useLanguage(AppLanguage.en);
      expect(assignStatusText(waiting), 'Waiting');
      expect(
        assignProgressText({
          'a': const AssignStatus(AssignPhase.done),
          'b': const AssignStatus(AssignPhase.retry, retry: 1, retries: 2),
        }),
        '1/2 done, 1 retrying automatically',
      );
      expect(assignFailedHint(1), contains('[Retry this one]'));
      expect(assignAutoHint, startsWith('Handled automatically'));
    });

    test('progress_checklist items and notes', () {
      useLanguage(AppLanguage.en);
      expect(connectChecklist().items.first.label, 'Bluetooth connection');
      expect(
        finishChecklist(direct: false, total: 3).item(finishItemAssign)!.label,
        'Assign PTUs (3 in total)',
      );
      expect(dataCountNote(1, 3, ptus: 1), '1/3 rows received');
      expect(uploadTargetNote(null), 'To the current back office');
    });

    test('install_report status line (screen only)', () {
      const queued = InstallReportStatus(phase: InstallReportPhase.queued);
      expect(installReportStatusText(queued), '排隊中，網路恢復後自動送');
      useLanguage(AppLanguage.en);
      expect(
        installReportStatusText(queued),
        'Queued; sent automatically when the network is back',
      );
    });

    test('field_report help lines', () {
      useLanguage(AppLanguage.en);
      final lines = fieldHelpLines(_input(const CommissionState(step: 1)));
      expect(lines.first, 'Not connected to a gateway yet');
      expect(lines[1], 'Now at step 2: Find gateway');
      expect(fieldHelpDetailLines(errorCode: 'GW_NOT_FOUND'), [
        'Situation code: GW_NOT_FOUND',
      ]);
    });

    test('star_allow_list screen texts', () {
      useLanguage(AppLanguage.en);
      expect(
        starListWrittenText([1, 2]),
        startsWith('PTU binding list written: #1, #2'),
      );
      expect(
        foreignPtuText(foreign: 1, unlisted: 0),
        startsWith('1 other PTU nearby has the same number'),
      );
    });
  });

  group('§6: uploaded texts stay Chinese in English', () {
    test('network_check stepLabels: screen English, step_label Chinese', () {
      useLanguage(AppLanguage.en);
      expect(stepLabels[1], 'Find gateway');
      expect(stepLabelsIn(L10n.zh)[1], '找到閘道器');
      final body = _sessionReport(const CommissionState(step: 1));
      expect(body['step_label'], '找到閘道器');
    });

    test('gateway_reboot: screen English, upload (l10n: zh) Chinese', () {
      const reboot = GatewayReboot(from: 3, to: 4, reason: 'brownout');
      expect(gatewayRebootText(reboot), startsWith('閘道器剛重新啟動（原因：供電電壓不足'));
      useLanguage(AppLanguage.en);
      expect(
        gatewayRebootText(reboot),
        startsWith('The gateway just restarted'),
      );
      expect(resetReasonText('ext'), 'Someone pressed the reset button');
      expect(
        gatewayRebootText(reboot, l10n: L10n.zh),
        startsWith('閘道器剛重新啟動（原因：供電電壓不足'),
      );
      expect(resetReasonText('ext', l10n: L10n.zh), '有人按了重置鍵');
      expect(
        gatewayRebootRetryText,
        startsWith('The last action was interrupted'),
      );
    });

    test('dashboard_api describeBackend: screen English, report Chinese', () {
      final base = Uri.parse('https://46.250.255.172');
      useLanguage(AppLanguage.en);
      expect(describeBackend(base), 'Backend https://46.250.255.172');
      expect(describeBackend(null), '(no backend URL set)');
      expect(describeBackend(base, l10n: L10n.zh), '後端 https://46.250.255.172');
    });

    test('star_allow_list starListReportText', () {
      useLanguage(AppLanguage.en);
      expect(
        starListReportText(StarListStatus.written, [1, 2]),
        'PTU 綁定名單：已寫入 #1、#2',
      );
      expect(
        starListReportText(StarListStatus.failed, const []),
        'PTU 綁定名單：未寫入（請在完成頁重試）',
      );
    });

    test('install_report uploadTargetOf', () {
      useLanguage(AppLanguage.en);
      expect(uploadTargetOf(const {}), '正式站（韌體固定）');
      expect(
        uploadTargetOf(const {
          'mqtt_target': 'local',
          'mqtt_host': '192.168.0.12',
          'mqtt_port': 8883,
        }),
        '本地 192.168.0.12:8883',
      );
    });

    test('field_report recentDataReportText', () {
      useLanguage(AppLanguage.en);
      expect(recentDataReportText, '查看最近資料');
    });
  });

  group('§8.2: logic no longer depends on the language', () {
    for (final language in AppLanguage.values) {
      test('field_report: gateway not found (${language.name})', () {
        useLanguage(language);
        final prefix = L10n.current.fieldReport_gatewayNotFoundPrefix;
        final state = CommissionState(
          step: 1,
          message: '$prefix. Move closer and rescan.',
        );
        expect(sessionRescueCode(_input(state)), RescueCode.gwNotFound);
        // Both languages are recognised whatever the current one is.
        expect(isGatewayNotFoundMessage('未找到閘道器，請靠近並確認電源後重掃。'), isTrue);
        expect(isGatewayNotFoundMessage('No gateway found. Rescan.'), isTrue);
        expect(isGatewayNotFoundMessage('請選擇要開通的閘道器'), isFalse);
        expect(
          sessionRescueCode(
            _input(const CommissionState(step: 1, message: '準備完成')),
          ),
          isNull,
        );
      });

      test('field_report: pending read-back (${language.name})', () {
        useLanguage(language);
        expect(isPendingReadbackResult(pendingReadbackText(3)), isTrue);
        expect(isPendingReadbackResult('已指派 #3，等待連線'), isFalse);
        expect(isPendingReadbackResult(null), isFalse);
        final state = CommissionState(
          step: 5,
          ptus: const [
            {'mac': 'AA', 'device_number': 3},
          ],
          results: {'AA': pendingReadbackText(3)},
        );
        final ptus = diagnosticSections(state, now: DateTime(2026))['ptus'];
        expect((ptus as List).single['assign'], 'pending_readback');
      });

      test('progress_checklist: checklistReason (${language.name})', () {
        useLanguage(language);
        // Chinese errors (the existing behaviour).
        expect(checklistReason('找不到閘道器，請靠近後重掃。'), '找不到閘道器');
        expect(checklistReason('連線失敗。請重試\n細節'), '連線失敗');
        expect(checklistReason('藍牙斷線：'), '藍牙斷線');
        // English errors.
        expect(
          checklistReason('Gateway not found. Move closer and rescan.'),
          'Gateway not found',
        );
        expect(
          checklistReason('Cannot reach the backend, please check Wi-Fi'),
          'Cannot reach the backend',
        );
        expect(
          checklistReason('Firmware 1.7.36 is too old.'),
          'Firmware 1.7.36 is too old',
        );
        expect(checklistReason('Bluetooth lost:'), 'Bluetooth lost');
        expect(
          checklistReason(null),
          language == AppLanguage.en ? 'Not completed' : '沒有完成',
        );
      });

      test('recent_gateways: BackendPresence (${language.name})', () {
        useLanguage(language);
        final l10n = L10n.current;
        expect(backendPresenceKind(_uid, [_row()]), BackendPresence.online);
        expect(
          backendPresenceKind(_uid, [_row(online: false)]),
          BackendPresence.offline,
        );
        expect(backendPresenceKind(_uid, const []), BackendPresence.noRecord);
        expect(
          backendPresenceKind(_uid, const [], archived: [_row()]),
          BackendPresence.archived,
        );
        expect(
          backendPresenceKind(_uid, [_row(), _row()]),
          BackendPresence.unknown,
        );
        expect(
          backendPresenceKind(null, [_row()], advertisedName: 'GIOS-S81-GW01'),
          BackendPresence.online,
        );
        expect(
          backendPresenceShort(_uid, [_row()]),
          l10n.recentGateways_shortOnline,
        );
        expect(
          backendPresenceShort(_uid, const []),
          l10n.recentGateways_shortNoRecord,
        );
        // Short texts of every language map back to their kind.
        for (final kind in BackendPresence.values) {
          expect(BackendPresence.ofShortText(kind.shortTextIn(L10n.zh)), kind);
          expect(
            BackendPresence.ofShortText(
              kind.shortTextIn(lookupAppLocalizations(appEnLocale)),
            ),
            kind,
          );
        }
        expect(BackendPresence.ofShortText('已配置'), isNull);
      });
    }

    test('recent_gateways: English texts', () {
      useLanguage(AppLanguage.en);
      expect(backendPresenceShort(_uid, [_row()]), 'Backend online');
      expect(backendPresence(_uid, [_row()]), 'Back office reports online');
      expect(backendUnknownShort, 'Backend unknown');
      expect(gatewayArchivedLabel, 'Archived (removed in back office)');
    });
  });
}
