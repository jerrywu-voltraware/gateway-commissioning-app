// B3 i18n: core/direct_mode.dart, direct_calibration.dart, gateway_identity.dart,
// gateway_net.dart — 繁中 default unchanged, English via useLanguage.
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/direct_calibration.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_net.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';

import 'support/l10n.dart';

void main() {
  group('direct_mode', () {
    test('繁中 stays as before', () {
      expect(directConfirmLabel, '是這台，開始配置');
      expect(directIdentifyFirstText, '請先按「辨識此樁」確認是眼前這台，再按「是這台，開始配置」。');
      expect(DirectState.noCandidate.label, '找不到夠近的 PTU');
      expect(directReasonText('none'), '找不到夠近的 PTU');
      expect(
        identifyPtuFailedText('not_connected', seconds: 6),
        '閘道器正在閃燈（6 秒）；PTU 指令未送出（閘道器尚未連上 PTU）。',
      );
      expect(remoteIdentifyHeads, hasLength(8));
      for (final head in remoteIdentifyHeads) {
        expect(head.length, lessThanOrEqualTo(remoteIdentifyHeadMax));
      }
    });

    test('English', () {
      useLanguage(AppLanguage.en);
      expect(directConfirmLabel, 'This one, start setup');
      expect(directIdentifyFirstText, contains('[This one, start setup]'));
      expect(DirectState.connected.label, 'PTU connected');
      expect(directReasonText('ok'), 'Clearly the strongest signal');
      expect(identifyPendingText, 'Sent, waiting for the gateway…');
      expect(identifyPendingGatewayText, identifyPendingText);
      expect(
        identifyPtuFailedText('not_connected', seconds: 6),
        'Gateway is blinking (6 s); PTU command not sent '
        '(Gateway is not connected to a PTU yet).',
      );
      expect(
        const DirectCandidate('90:5F:E8:9A:96:00', -48, null).rssiText,
        'Peak -48 dBm',
      );
      expect(
        remoteIdentifyHeadText(const {'ptu_write': 'not_connected'}),
        remoteIdentifyHeads[4],
      );
      expect(remoteIdentifyHeads, contains('Back office sent lights-off'));
      expect(
        directUnbindFailedText('905FE89A9601', '905FE89A9600'),
        contains('90:5F:E8:9A:96:01'),
      );
    });
  });

  group('direct_calibration', () {
    test('繁中 stays as before', () {
      expect(calibrationTitle, '校正門檻');
      expect(calibrationGapText(2, 'X'), '鄰近樁 X 只比本樁弱 2 dB，餘裕不足（至少要弱 3 dB）');
      expect(
        calibrationFewSamplesText(2),
        '有 2 台鄰近 PTU 讀數較少（不足 3 筆），已計入下限但可能不穩定，'
        '請按「重新掃描鄰近」再取樣一次。',
      );
      expect(calibrationNeighborLabel(['A', 'B'], total: 3), 'A、B 等 3 台');
      expect(
        CalibrationBasis.staleOwnAdvertising.referenceText,
        '參考值（本樁廣播值超過 15 分鐘，上限只用連線訊號）',
      );
    });

    test('English', () {
      useLanguage(AppLanguage.en);
      expect(calibrationTitle, 'Calibrate threshold');
      expect(
        calibrationGapText(-3, 'X'),
        'Neighbour X is 3 dB stronger than this charger',
      );
      expect(calibrationFewSamplesText(1), startsWith('1 neighbour PTU has'));
      expect(calibrationFewSamplesText(2), startsWith('2 neighbour PTUs have'));
      expect(calibrationFewSamplesText(2), contains('[Rescan neighbours]'));
      expect(calibrationNeighborLabel(['A', 'B']), 'A, B');
      expect(calibrationSelfAdvAgeText(130), contains('2 min ago'));
      expect(
        CalibrationBasis.legacy.referenceText,
        'Reference only (older gateway firmware)',
      );
    });
  });

  group('gateway_identity', () {
    test('繁中 stays as before', () {
      expect(gatewayIdText(80, 2), '站 80 · 閘道器 2');
      expect(uploadPausedText, '閘道器已連上後台，但資料上傳已暫停：PTU 資料不會送出。請按「恢復上傳」。');
      expect(testModeStatusHint, '閘道器在測試模式（只產生測試資料），請按「切回正常模式」。');
      expect(
        gatewayMacText(uid: '240AC41270F0', bleId: '24:0A:C4:12:70:F2'),
        'MAC 後 4 碼 70F0（藍牙 70F2）',
      );
    });

    test('English', () {
      useLanguage(AppLanguage.en);
      expect(gatewayIdText(80, 2), 'Site 80 · Gateway 2');
      expect(unconfiguredGatewayTitle('…3A00'), 'Unconfigured gateway …3A00');
      expect(uploadPausedStatusHint, endsWith('Tap [Resume upload].'));
      expect(macTailText('24:0A:C4:12:70:F2'), 'MAC last 4: 70F2');
    });

    test('the gateway-pick notice is recognised in every language', () {
      final zh = directGatewayPickText('24:0A:C4:12:70:F2');
      expect(isDirectGatewayPickText(zh), isTrue);
      useLanguage(AppLanguage.en);
      final en = directGatewayPickText('24:0A:C4:12:70:F2');
      expect(en, startsWith('The gateway connected to another gateway'));
      expect(isDirectGatewayPickText(en), isTrue);
      // Written in 繁中 before the switch: still recognised.
      expect(isDirectGatewayPickText(zh), isTrue);
      expect(
        isDirectGatewayPickText(directSwitchedText('905FE89A9600')),
        isFalse,
      );
      expect(isDirectGatewayPickText(''), isFalse);
    });
  });

  group('gateway_net', () {
    test('繁中 stays as before', () {
      expect(wifiOkText('Office'), '閘道器已連上 Wi-Fi「Office」');
      expect(
        wifiDiscDetail({
          'wifi_last_disc_reason': 15,
          'wifi_last_disc_age_s': 12,
        }),
        'Wi-Fi 最後斷線原因：密碼可能錯誤（代碼 15，12 秒前）',
      );
      expect(wifiStateText('idle'), '未知（idle）');
    });

    test('English', () {
      useLanguage(AppLanguage.en);
      expect(wifiOkText('Office'), 'Gateway joined Wi-Fi "Office"');
      expect(wifiOkText(null), 'Gateway joined Wi-Fi');
      expect(wifiConnectingText, 'Gateway is joining Wi-Fi…');
      expect(
        wifiDiscDetail({'wifi_last_disc_reason': 15}),
        'Last Wi-Fi drop: Password may be wrong (code 15)',
      );
      expect(wifiStateText('got_ip'), 'Connected (got_ip)');
      expect(
        weakWifiText(-80),
        startsWith('⚠ Weak Wi-Fi (-80 dBm, below -75 dBm)'),
      );
      expect(
        wifiSetFailedText(null),
        'New Wi-Fi not joined. Check the password and signal, then retry.',
      );
      expect(wifiProblemText('', reason: null), contains('no Wi-Fi set up'));
    });
  });
}
