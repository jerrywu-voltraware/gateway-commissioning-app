// B1（2026-10-05 i18n，docs/i18n.md）：commissioning_controller.dart 的中英字串。
//
// - 英文：插值、複數、句子組合（useLanguage(AppLanguage.en)）。
// - §6：安裝報告、field 診斷說明在英文畫面下仍是中文。
// - §8.2：取代比對畫面文字的旗標（MessageKind、pendingReadback）。
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';

import 'link_loss_test.dart' show DroppingLink, ready;
import 'round4_fixes_test.dart' show AckLink;
import 'support/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('English (screen texts follow the language)', () {
    test('interpolation', () {
      useLanguage(AppLanguage.en);
      expect(connectingAttemptText(3), 'Connecting (attempt 3)');
      expect(
        step7RetryText(2, 3, const Duration(seconds: 10)),
        'Bluetooth dropped again. Reconnecting in 10 s (retry 2/3)',
      );
      expect(
        directPickMessage(null),
        'The gateway has not reported a pick yet. Tap [Search again].',
      );
      expect(ptuFailureText('timed out'), 'PTU not responding');
    });

    test('plurals', () {
      useLanguage(AppLanguage.en);
      expect(
        absentSelectionText(1),
        '1 PTU did not appear in this scan and was unchecked',
      );
      expect(
        absentSelectionText(3),
        '3 PTUs did not appear in this scan and were unchecked',
      );
      expect(
        reconnectFailedAttemptsText(1),
        startsWith('Reconnect failed (1 attempt).'),
      );
      expect(
        reconnectFailedAttemptsText(4),
        startsWith('Reconnect failed (4 attempts).'),
      );
      expect(
        endFlowConfirmText(1),
        'The 1 PTU already done stays on the gateway.',
      );
      expect(
        endFlowConfirmText(2, restoresBind: true),
        endsWith('The 2 PTUs already done are kept.'),
      );
    });

    test('composed sentences: resume prompt and data check progress', () {
      useLanguage(AppLanguage.en);
      expect(
        resumeText(5, [2, 1], 1, inflight: [3]),
        'Stopped last time at step 8 (start monitoring): 2 done (#1, #2); '
        '#3 interrupted while assigning (the gateway decides after '
        'reconnecting), 1 not set up yet. The gateway is still running; no '
        'need to power-cycle it.',
      );
      expect(
        verifyProgressText([2, 1], {1: 2}, {2}),
        'Data check #1 2/3, #2 0/3\nPTU #2 no data yet',
      );
    });

    test('zh stays the default', () {
      expect(connectingAttemptText(3), '連線中（第 3 次）');
      expect(absentSelectionText(3), '3 台在本次掃描未出現，已取消勾選');
      expect(
        verifyProgressText([2, 1], {1: 2}, {2}),
        '資料驗證 #1 2/3、#2 0/3\nPTU #2 尚無資料',
      );
    });
  });

  group('§6 reports stay in Chinese', () {
    const bound = CommissionState(
      config: {'direct_bind_mac': 'AA:BB:CC:00:00:01'},
    );

    test('report lines in English mode', () {
      useLanguage(AppLanguage.en);
      expect(
        ptuMissingReportText('AA:BB:CC:00:96:00'),
        startsWith('本樁 PTU 不在場：閘道器綁定 '),
      );
      expect(deferredReportLine, startsWith('PTU：尚未連線'));
      // Shared with the screen: English there, Chinese for the report.
      expect(directBoundNote(bound), startsWith('Bound PTU MAC: '));
      expect(
        directBoundNote(bound, l10n: L10n.zh),
        '已綁定 PTU MAC：AA:BB:CC:00:00:01（閘道器只連這台）',
      );
      expect(deferredDetailText(-55), contains('threshold -55 dBm'));
      expect(
        deferredDetailText(-55, l10n: L10n.zh),
        '閘道器已加入運作並恢復上傳，維持一對一模式（門檻 -55 dBm），尚未綁定 PTU。',
      );
    });

    test('install report (_reportBody, skippedNote, _report) in English '
        'mode', () async {
      useLanguage(AppLanguage.en);
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      fake.devices.firstWhere((d) => d['device_number'] == 2)['connected'] =
          false;
      var skipRequested = false;
      container.listen(commissionProvider, (_, s) {
        if (!skipRequested && s.verifyWaiting.contains(2)) {
          skipRequested = true;
          c.skipVerifyPtu(2);
        }
      });
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      // The screen is English…
      expect(s.message, 'Verification passed; automatic monitoring resumed');
      expect(s.messageKind, MessageKind.verified);
      // …the report is not.
      expect(s.report, startsWith('模擬安裝報告（非實機驗證）\n站點 1 / 閘道器 1'));
      expect(s.report, contains('每台連續三次資料更新通過'));
      expect(s.report, contains('未驗證（已略過）：#2，'));
      expect(s.report, contains('請現場確認 PTU #2 電源與位置'));
      expect(s.report, contains('資料上傳目標：'));
    });
  });

  group('§8.2 flags instead of matching screen texts', () {
    test('messageKind follows the message it was set with', () {
      final s = const CommissionState().copy(
        message: 'x',
        messageKind: MessageKind.dataStreaming,
      );
      expect(s.dataStreaming, isTrue);
      expect(s.copy(busy: true).dataStreaming, isTrue);
      expect(s.copy(message: 'x').dataStreaming, isTrue);
      expect(s.copy(message: 'y').dataStreaming, isFalse);
      expect(s.copy(message: 'y').messageKind, MessageKind.none);
      expect(
        const CommissionState()
            .copy(messageKind: MessageKind.noGatewayFound)
            .noGatewayFound,
        isTrue,
      );
    });

    test('pendingReadback drops a MAC once its row text changes', () {
      const s = CommissionState(
        results: {'a': 'one', 'b': 'two'},
        pendingReadback: {'a', 'b'},
      );
      final next = s.copy(results: {'a': 'one', 'b': 'changed'});
      expect(next.pendingReadback, {'a'});
      expect(next.pendingReadbackOf('a'), isTrue);
      expect(next.pendingReadbackOf('b'), isFalse);
      expect(s.copy(busy: true).pendingReadback, {'a', 'b'});
    });

    test('step 8 sets pendingReadback with the 待回讀確認 row, in English '
        'too', () async {
      useLanguage(AppLanguage.en);
      final fake = AckLink()..ackOverride = {'verified': false};
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final seen = <String>{};
      var mismatch = false;
      container.listen(commissionProvider, (_, s) {
        for (final mac in s.results.keys) {
          final text = s.results[mac]!;
          final pendingText = text.contains('waiting for read-back');
          if (pendingText != s.pendingReadbackOf(mac)) mismatch = true;
          if (pendingText) seen.add(mac);
        }
      });
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(seen, isNotEmpty, reason: 'unverified acks show the row text');
      expect(mismatch, isFalse);
      expect(s.pendingReadback, isEmpty, reason: 'settled after read-back');
    });
  });
}
