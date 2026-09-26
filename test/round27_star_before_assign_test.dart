import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/star_allow_list.dart';
import 'package:gateway_commissioning/gateway_app.dart';

import 'round26_star_macs_test.dart' show StarListLink, ptuMacs, starStep7;

/// Round 27: the star allow list goes out before step 8's first assign
/// (`set_config star_macs` = the chosen PTUs + the ones configured earlier
/// and left untouched). Before, it was written only after the data
/// verification: with foreign PTUs holding all five connections and no
/// list yet, every assign failed (`No free slot`) and the verification
/// that would have written the list was never reached.

const _earlier = 'AA:BB:CC:00:00:04';

/// PTUs of another site carrying this gateway's numbers #1..#5.
List<String> get _foreign => [
  for (var i = 1; i <= 5; i++) '9F:77:EF:C2:96:0$i',
];

Map<String, dynamic> _row(
  String mac,
  int id, {
  bool connected = false,
  int rssi = -60,
}) => {
  'mac': mac,
  'rssi': rssi,
  'device_number': id,
  'connected': connected,
  'notify_enabled': connected,
  'zombie': false,
  'last_data_age_sec': 0,
};

/// Own PTUs #1..#5 nearby (not connected); the gateway's five connections
/// are held by [_foreign] PTUs carrying the same numbers; no list yet.
StarListLink _takenOver(String fw) {
  final fake = StarListLink(fw: fw, oldPtu: false);
  for (final (i, d) in fake.devices.indexed) {
    d['device_number'] = i + 1;
  }
  fake.devices.addAll([
    _row('AA:BB:CC:00:00:05', 4),
    _row('AA:BB:CC:00:00:06', 5),
    for (final (i, mac) in _foreign.indexed)
      _row(mac, i + 1, connected: true, rssi: -50),
  ]);
  return fake;
}

List<String> _own(StarListLink fake) => [
  for (final d in fake.devices)
    if (!_foreign.contains(d['mac'])) d['mac'].toString(),
];

/// Step 7: the installer unticks the foreign PTUs and ticks their own.
void _chooseOwn(CommissioningController c, StarListLink fake) {
  for (final mac in _foreign) {
    c.select(mac, false);
  }
  for (final mac in _own(fake)) {
    c.select(mac, true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('starTargetList', () {
    Map<String, dynamic> row(
      String mac,
      int id, {
      bool connected = true,
      bool? listed,
    }) => {
      'mac': mac,
      'device_number': id,
      'connected': connected,
      'star_listed': ?listed,
    };
    final rows = [
      row('90:08:00:00:00:01', 1, connected: false), // chosen, #1
      row('900800000002', 0, connected: false), // chosen, no number yet
      row('9f:77:ef:c2:96:01', 1), // foreign, same number as chosen #1
      row('90:08:00:00:00:04', 4), // untouched, unique number
      row('90:08:00:00:00:05', 5, listed: true), // on the list already
      row('90:08:00:00:00:07', 7), // another gateway's range
      row('90:08:00:00:00:31', 3), // #3 twice: neither is taken
      row('90:08:00:00:00:32', 3, connected: false),
    ];
    const chosen = ['90:08:00:00:00:01', '90:08:00:00:00:02'];
    List<String> macs(List<({String mac, int id})> list) => [
      for (final e in list) e.mac,
    ];

    test('chosen first (any number), untouched PTUs kept, a foreign one '
        'with a chosen number left out', () {
      final list = starTargetList(rows: rows, chosen: chosen, first: 1);
      expect(macs(list), [
        '90:08:00:00:00:01',
        '90:08:00:00:00:02',
        '90:08:00:00:00:04',
        '90:08:00:00:00:05',
      ]);
      expect([for (final e in list) e.id], [1, 0, 4, 5]);
    });

    test(
      'list already set: only listed untouched PTUs (flag or get_config)',
      () {
        expect(
          macs(
            starTargetList(rows: rows, chosen: chosen, first: 1, listSet: true),
          ),
          ['90:08:00:00:00:01', '90:08:00:00:00:02', '90:08:00:00:00:05'],
        );
        expect(
          macs(
            starTargetList(
              rows: rows,
              chosen: chosen,
              first: 1,
              listSet: true,
              listed: ['90:08:00:00:00:04'],
            ),
          ),
          [
            '90:08:00:00:00:01',
            '90:08:00:00:00:02',
            '90:08:00:00:00:04',
            '90:08:00:00:00:05',
          ],
        );
      },
    );

    test('dropped (chosen earlier, left out since) never kept; at most 5', () {
      expect(
        macs(
          starTargetList(
            rows: rows,
            chosen: chosen,
            first: 1,
            dropped: ['90:08:00:00:00:04'],
          ),
        ),
        ['90:08:00:00:00:01', '90:08:00:00:00:02', '90:08:00:00:00:05'],
      );
      final five = [for (var i = 1; i <= 6; i++) '90:08:00:00:01:0$i'];
      final full = starTargetList(rows: rows, chosen: five, first: 1);
      expect(macs(full), five.take(5).toList());
      // Gateway 2 (#6..#10): only its own range.
      expect(macs(starTargetList(rows: rows, chosen: const [], first: 6)), [
        '90:08:00:00:00:07',
      ]);
    });

    test('starAllowList: excluded PTUs never make the verified list', () {
      final list = starAllowList(
        rows: [
          row('90:08:00:00:00:01', 1),
          row('90:08:00:00:00:02', 2, listed: true),
          row('90:08:00:00:00:03', 3),
        ],
        own: {'90:08:00:00:00:01', '90:08:00:00:00:03'},
        first: 1,
        exclude: {'900800000002', '90:08:00:00:00:03'},
      );
      expect(list, [(id: 1, mac: '90:08:00:00:00:01')]);
    });
  });

  for (final fw in ['1.7.36', '1.7.37']) {
    group('firmware $fw: sent before the first assign', () {
      test('chosen PTUs + the untouched earlier one, read back, before any '
          'assign_device_id', () async {
        final fake = StarListLink(fw: fw);
        final (container, c) = await starStep7(fake);
        addTearDown(container.dispose);
        final macs = ptuMacs(fake);
        c.select(_earlier, false); // configured on an earlier visit
        await c.configurePtus();
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.step, 6);
        final write = fake.log.indexOf('set_config:star');
        final assign = fake.log.indexOf('assign_device_id');
        expect(write, isNot(-1));
        expect(write, lessThan(assign));
        expect(fake.log.sublist(write, assign), contains('get_config'));
        expect(fake.starWrites, hasLength(1));
        expect(fake.starWrites.single.toSet(), macs.toSet());
        expect(fake.starWrites.single, contains(_earlier));
        expect(s.starList, StarListStatus.written);
        expect(s.starListStage, StarListStage.beforeAssign);
        expect(s.config['star_macs'], isNotEmpty);
      });

      test('foreign PTUs holding all five connections: dropped by the list, '
          'every own PTU assigned (no 「No free slot」)', () async {
        final fake = _takenOver(fw);
        final (container, c) = await starStep7(fake);
        addTearDown(container.dispose);
        final own = _own(fake);
        _chooseOwn(c, fake);
        expect(container.read(commissionProvider).selected, own.toSet());
        await c.configurePtus();
        final s = container.read(commissionProvider);
        expect(s.error, isNull);
        expect(s.assignFailed, isEmpty);
        expect(s.step, 6);
        expect(fake.starWrites.first.toSet(), own.toSet());
        // Waited for the drop (get_ble_devices) before the first assign.
        final write = fake.log.indexOf('set_config:star');
        final assign = fake.log.indexOf('assign_device_id');
        expect(write, lessThan(assign));
        expect(fake.log.sublist(write, assign), contains('get_ble_devices'));
        for (final d in fake.devices) {
          expect(
            d['connected'],
            !_foreign.contains(d['mac']),
            reason: '${d['mac']}',
          );
        }
        // The own PTUs kept their numbers (the foreign ones do not count
        // once the list is in force).
        expect(
          [
            for (final mac in own)
              fake.devices.firstWhere((d) => d['mac'] == mac)['device_number'],
          ],
          [1, 2, 3, 4, 5],
        );

        await c.verify('https://example.invalid', 'pw');
        final done = container.read(commissionProvider);
        expect(done.step, 7);
        expect(fake.starWrites.last.toSet(), own.toSet());
        expect(done.starListIds, [1, 2, 3, 4, 5]);
      });
    });
  }

  test('firmware 1.7.35 (no list): the same site stays blocked', () async {
    final fake = _takenOver('1.7.35');
    final (container, c) = await starStep7(fake);
    addTearDown(container.dispose);
    _chooseOwn(c, fake);
    await c.configurePtus();
    final s = container.read(commissionProvider);
    expect(fake.starWrites, isEmpty);
    expect(s.step, isNot(6));
    expect(s.error, isNotNull);
  });

  group('a failed write never blocks the assignment', () {
    test('three timeouts: notice, assigns go on, verified list written '
        'later', () async {
      final fake = StarListLink(fw: '1.7.37');
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      fake.failStarWrites = 3;
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(
        fake.starWrites,
        hasLength(CommissioningController.starListAttempts),
      );
      expect(
        fake.log.indexOf('assign_device_id'),
        greaterThan(fake.log.lastIndexOf('set_config:star')),
      );
      expect(s.starList, StarListStatus.failed);
      expect(s.starListStage, StarListStage.beforeAssign);
      expect(fake.starMacs, isNull);

      await c.verify('https://example.invalid', 'pw');
      s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.starList, StarListStatus.written);
      expect(s.starListStage, StarListStage.verified);
      expect(fake.starMacs!.toSet(), ptuMacs(fake).toSet());
    });

    test('phone link lost at the write: 「重新連線並繼續」 sends it again, then '
        'assigns', () async {
      final keep = autoRelinkRounds;
      autoRelinkRounds = 0;
      addTearDown(() => autoRelinkRounds = keep);
      final fake = _DropAtStar();
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.resumePending, isTrue);
      expect(s.unassigned, s.selected);
      expect(fake.log, isNot(contains('assign_device_id')));

      await c.resumeAssign();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      // The first write never reached the gateway; sent again on resume.
      expect(fake.dropped, isTrue);
      expect(fake.starWrites, hasLength(1));
      expect(fake.starMacs!.toSet(), ptuMacs(fake).toSet());
      expect(
        fake.log.indexOf('assign_device_id'),
        greaterThan(fake.log.lastIndexOf('set_config:star')),
      );
    });
  });

  group('the verified list leaves out failed and unverified PTUs', () {
    test('a PTU left out after its assign failed', () async {
      final fake = StarListLink(fw: '1.7.37', oldPtu: false);
      // It carried #3 from before: once listed it would connect.
      final macs = ptuMacs(fake);
      fake.devices.last['device_number'] = 3;
      fake.failAssign.add(macs.last);
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.step, 4);
      expect(s.assignFailed.keys, [macs.last]);
      expect(fake.starWrites.single, contains(macs.last));

      // The installer leaves it out and configures the rest.
      c.select(macs.last, false);
      await c.configurePtus();
      s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(fake.starWrites.last, isNot(contains(macs.last)));

      await c.verify('https://example.invalid', 'pw');
      s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.starList, StarListStatus.written);
      expect(fake.starWrites.last.toSet(), macs.take(2).toSet());
      expect(s.starListIds, [1, 2]);
    });

    test('a PTU skipped at the data verification (未驗證)', () async {
      final fake = StarListLink(fw: '1.7.37', oldPtu: false);
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      final macs = ptuMacs(fake);
      await c.configurePtus();
      expect(container.read(commissionProvider).step, 6);
      final two = fake.devices.firstWhere((d) => d['device_number'] == 2);
      two['connected'] = false;
      var skipped = false;
      container.listen(commissionProvider, (_, s) {
        if (!skipped && s.verifyWaiting.contains(2)) {
          skipped = true;
          c.skipVerifyPtu(2);
        }
      });
      await c.verify('https://example.invalid', 'pw');
      final s = container.read(commissionProvider);
      expect(skipped, isTrue);
      expect(s.step, 7);
      expect(s.verifySkipped, {2});
      expect(s.starList, StarListStatus.written);
      expect(fake.starWrites.last, isNot(contains(two['mac'])));
      expect(
        fake.starWrites.last.toSet(),
        macs.where((m) => m != two['mac']).toSet(),
      );
      expect(s.starListIds, [1, 3]);
    });
  });

  testWidgets('step 7/8 page: the write failed → plain notice, the rest went '
      'on (360x640)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = StarListLink(fw: '1.7.37', oldPtu: false)..failStarWrites = 3;
    final macs = ptuMacs(fake);
    fake.failAssign.add(macs.last);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoSystemProvider.overrideWithValue(fake)],
        child: const GatewayApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GatewayApp)),
    );
    container.read(demoProvider.notifier).set(true);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
      await c.configurePtus();
    });
    await tester.pump();
    final s = container.read(commissionProvider);
    expect(s.step, 4, reason: 'one PTU failed, the others went online');
    expect(s.assignedOk, hasLength(2));
    final notice = find.byKey(const Key('star-list-before-failed'));
    await tester.ensureVisible(notice);
    await tester.pump();
    final text = tester
        .widget<Text>(find.descendant(of: notice, matching: find.byType(Text)))
        .data!;
    expect(text, starListBeforeFailedText);
    expect(text, startsWith('PTU 綁定名單未寫入，繼續配置'));
    expect(text, isNot(matches(RegExp(r'star|_|listed|enforced|slot'))));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// The phone link drops at the first star write (before any assign).
class _DropAtStar extends StarListLink {
  _DropAtStar() : super(fw: '1.7.37');

  bool dropped = false;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    if (!dropped && op == 'set_config' && params.containsKey('star_macs')) {
      dropped = true;
      down = true;
      throw const GatewayFailure('not_connected');
    }
    return super.command(op, params);
  }
}
