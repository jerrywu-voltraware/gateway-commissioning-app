// Round 9 phone test fixes:
// 1. Step 9 「略過此台」 — a PTU idle for verifyIdleLimit no longer forces
//    an overall `incomplete`; the rest decide pass/fail and the report
//    lists the skipped PTU.
// 2. backToSelection then 「配置」 again — _startMonitoring must not
//    re-send set_config/join_fleet when the gateway already reports every
//    chosen PTU connected and monitoring.
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';

import 'link_loss_test.dart' show DroppingLink, ready;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. step 9 skip an idle PTU', () {
    test(
      'verification passes on the rest; report lists the skipped PTU',
      () async {
        final fake = DroppingLink();
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        await c.configurePtus();
        expect(container.read(commissionProvider).step, 6);
        // PTU #2 stops reaching the backend (e.g. powered off on site).
        fake.devices
            .firstWhere((d) => d['device_number'] == 2)['connected'] = false;
        var skipRequested = false;
        container.listen(commissionProvider, (_, s) {
          if (!skipRequested && s.verifyWaiting.contains(2)) {
            skipRequested = true;
            c.skipVerifyPtu(2);
          }
        });
        await c.verify('https://example.invalid', '');
        final s = container.read(commissionProvider);
        expect(skipRequested, isTrue, reason: 'PTU #2 should have gone idle');
        expect(s.step, 7);
        expect(s.verified, isTrue);
        expect(s.verifySkipped, {2});
        expect(s.verifyCounts[1], 3);
        expect(s.verifyCounts[3], 3);
        expect(s.report, contains('未驗證（已略過）：#2'));
        expect(s.report, contains('請現場確認 PTU #2 電源與位置'));
      },
    );

    test('skipVerifyPtu is a no-op outside step 9 or before idle', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      // Not even in commissioning yet: step 0.
      c.skipVerifyPtu(2);
      expect(container.read(commissionProvider).verifySkipped, isEmpty);
      await c.configurePtus();
      // Step 9, but PTU #2 has not been idle yet.
      c.skipVerifyPtu(2);
      expect(container.read(commissionProvider).verifySkipped, isEmpty);
    });

    test('verifyProgressText shows 未驗證（已略過） for a skipped PTU', () {
      expect(
        verifyProgressText([1, 2], {1: 3, 2: 0}, {2}, {2}),
        '資料驗證 #1 3/3、#2 0/3\nPTU #2 未驗證（已略過）',
      );
    });

    test('skipping every PTU never bypasses the overall 180 s timeout', () async {
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      for (final d in fake.devices) {
        d['connected'] = false;
      }
      var skippedAll = false;
      container.listen(commissionProvider, (_, s) {
        if (!skippedAll && s.verifyWaiting.length == 3) {
          skippedAll = true;
          for (final id in [1, 2, 3]) {
            c.skipVerifyPtu(id);
          }
        }
      });
      await c.verify('https://example.invalid', '');
      final s = container.read(commissionProvider);
      expect(skippedAll, isTrue);
      expect(s.verified, isFalse);
      expect(s.error, isNotNull, reason: 'overall 180 s timeout still fires');
    });
  });

  group('2. reconfigure after backToSelection skips a redundant join', () {
    test(
      'set_config/join_fleet are not re-sent when already monitoring',
      () async {
        final fake = DroppingLink();
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        await c.configurePtus();
        expect(container.read(commissionProvider).step, 6);
        await c.backToSelection();
        expect(container.read(commissionProvider).step, 4);
        fake.commands.clear();
        await c.configurePtus();
        final s = container.read(commissionProvider);
        expect(s.step, 6, reason: 'skips straight to verification');
        expect(fake.commands, isNot(contains('set_config')));
        expect(fake.commands, isNot(contains('join_fleet')));
      },
    );

    test(
      'not actually monitoring yet still goes through the full flow',
      () async {
        final fake = DroppingLink();
        final (container, c) = await ready(fake);
        addTearDown(container.dispose);
        await c.configurePtus();
        expect(container.read(commissionProvider).step, 6);
        await c.backToSelection();
        // The gateway dropped one PTU meanwhile — not really monitoring
        // it, unlike what set_config/max_connections alone would suggest.
        fake.devices.first['connected'] = false;
        fake.commands.clear();
        await c.configurePtus();
        final s = container.read(commissionProvider);
        expect(fake.commands, contains('set_config'));
        expect(fake.commands, contains('join_fleet'));
        expect(s.step, 6);
      },
    );
  });
}
