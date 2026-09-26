import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/star_allow_list.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';

/// Round 26 (P0 「星狀連錯樁」): the star-mode MAC allow list of firmware
/// 1.7.36 (`set_config star_macs`, cmd_contract.md §3B). Round 27: the
/// list goes out before step 8's first assign too
/// (round27_star_before_assign_test.dart), so every run writes it there
/// first; these tests count that write.

const _old = 'AA:BB:CC:00:00:04';

/// Demo gateway (site 80 / gateway 1, range #1..#5) with firmware
/// [fw]'s allow list: `set_config star_macs` stores it (whole list),
/// get_config reads it back, get_ble_devices reports `star_enforced` /
/// `star_listed`, get_status `star.foreign_ptus`; join_fleet connects only
/// listed PTUs while the list is enforced (star). A fourth PTU [_old] is
/// already #4 and connected (configured on an earlier visit).
///
/// Round 27: a star gateway (max_connections > 1) drops the connected PTUs
/// a new list leaves out at the next get_ble_devices read (the firmware
/// drops them within a second), and refuses an assign with `No free slot`
/// while all its connections are taken by other PTUs.
class StarListLink extends DemoSystem {
  StarListLink({String fw = '1.7.36', bool oldPtu = true}) {
    config.addAll({
      'fw_version': fw,
      'fleet_joined': true,
      'site_id': 80,
      'gateway_id': 1,
      'max_connections': 5,
    });
    if (oldPtu) {
      devices.add({
        'mac': _old,
        'rssi': -70,
        'device_number': 4,
        'connected': true,
        'notify_enabled': true,
        'zombie': false,
        'last_data_age_sec': 0,
      });
    }
  }

  /// Ops and backend requests in order (`set_config:star`,
  /// `PATCH bot-monitor true`, ...).
  final log = <String>[];

  /// Every `star_macs` sent.
  final starWrites = <List<String>>[];

  /// The gateway's list; null = never set (number-only rule).
  List<String>? starMacs;

  /// The next N star writes time out.
  int failStarWrites = 0;

  /// Round 27: star writes time out while this says so.
  bool Function()? failStarIf;

  /// Round 27: assigns of these MACs fail.
  final failAssign = <String>{};

  /// Round 27: a list was written; unlisted PTUs drop at the next read.
  bool dropPending = false;

  bool get starMode => ((config['max_connections'] as num?) ?? 1) > 1;

  /// Star writes answered `1 rejected (invalid)`.
  bool rejectStar = false;

  int foreignPtus = 0;

  /// get_ble_devices leaves these out (e.g. an own PTU off at the end).
  final hidden = <String>{};

  /// The phone link drops at the assign after this many succeeded.
  int? dropAfterAssigns;
  bool down = false;
  final assigns = <String>[];

  bool get enforced =>
      (starMacs?.isNotEmpty ?? false) &&
      ((config['max_connections'] as num?) ?? 1) > 1;

  bool listed(Object? mac) => starMacs?.contains(starMac(mac)) ?? false;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    down = false;
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    if (path.contains('bot-monitor')) {
      log.add('$method bot-monitor ${body?['enabled']}');
    }
    return super.request(method, path, body);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (down) throw const GatewayFailure('not_connected');
    final star = op == 'set_config' && params.containsKey('star_macs');
    log.add(star ? 'set_config:star' : op);
    if (star) {
      starWrites.add([for (final m in params['star_macs'] as List) '$m']);
      if (failStarWrites > 0 || (failStarIf?.call() ?? false)) {
        if (failStarWrites > 0) failStarWrites--;
        throw const GatewayFailure('timeout');
      }
      if (rejectStar) {
        return {
          'message': 'config updated: 0 params changed, 1 rejected (invalid)',
        };
      }
      starMacs = [for (final m in params['star_macs'] as List) starMac(m)!];
      dropPending = starMode;
      return {'message': 'config updated: 1 params changed'};
    }
    if (op == 'assign_device_id' && dropAfterAssigns != null) {
      if (assigns.length >= dropAfterAssigns!) {
        down = true;
        dropAfterAssigns = null;
        throw const GatewayFailure('not_connected');
      }
      assigns.add(params['mac'].toString());
    }
    if (op == 'assign_device_id') {
      final mac = params['mac'];
      final linked = devices.where((d) => d['connected'] == true);
      final full =
          starMode &&
          linked.length >= (config['max_connections'] as num) &&
          !linked.any((d) => d['mac'] == mac);
      if (failAssign.contains(mac) || full) {
        return {'success': false, 'error': 'No free slot'};
      }
    }
    if (op == 'get_ble_devices' && dropPending) {
      dropPending = false;
      if (enforced) {
        for (final d in devices) {
          if (!listed(d['mac'])) d['connected'] = false;
        }
      }
    }
    final result = await super.command(op, params);
    switch (op) {
      case 'get_config':
        return {
          ...result,
          'star_macs': ?starMacs,
          'star_mac_lock': true,
          'star_macs_set': starMacs != null,
        };
      case 'get_ble_devices':
        return {
          ...result,
          'star_enforced': enforced,
          'devices': [
            for (final d in result['devices'] as List)
              if (!hidden.contains(d['mac']))
                {...d, 'star_listed': listed(d['mac'])},
          ],
        };
      case 'get_status':
        return {
          ...result,
          'star': {
            'active': ((config['max_connections'] as num?) ?? 1) > 1,
            'enforced': enforced,
            'foreign_ptus': foreignPtus,
          },
        };
      case 'join_fleet':
        if (enforced) {
          for (final d in devices) {
            if (!listed(d['mac'])) d['connected'] = false;
          }
        }
    }
    return result;
  }
}

Future<(ProviderContainer, CommissioningController)> starStep7(
  StarListLink fake, {
  GatewayTopology topology = GatewayTopology.star,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(topology);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.chooseStation(newStation: false);
  return (container, c);
}

List<String> ptuMacs(DemoSystem fake) => [
  for (final d in fake.devices) d['mac'].toString(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('firmware version and list rules', () {
    test('firmwareAtLeast / starAllowListSupported', () {
      expect(firmwareAtLeast('1.7.36', 1, 7, 36), isTrue);
      expect(firmwareAtLeast('1.7.37-dev', 1, 7, 36), isTrue);
      expect(firmwareAtLeast('v1.8.0', 1, 7, 36), isTrue);
      expect(firmwareAtLeast('1.7.35', 1, 7, 36), isFalse);
      expect(firmwareAtLeast('1.7', 1, 7, 36), isFalse);
      expect(firmwareAtLeast('', 1, 7, 36), isFalse);
      expect(firmwareAtLeast(null, 1, 7, 36), isFalse);
      expect(starAllowListSupported({'fw_version': '1.7.36'}), isTrue);
      expect(starAllowListSupported({'fw_version': '1.7.3'}), isFalse);
      expect(starAllowListSupported({}), isFalse);
    });

    test('starAllowList: own first, one MAC per number, range only', () {
      Map<String, dynamic> row(String mac, int id, {bool? listed}) => {
        'mac': mac,
        'device_number': id,
        'connected': true,
        'star_listed': ?listed,
      };
      final rows = [
        row('9f:77:ef:c2:96:00', 3), // foreign, same number as own #3
        row('90:08:00:00:00:03', 3),
        row('90:08:00:00:00:01', 1),
        row('90:08:00:00:00:07', 7), // out of range (#1..#5)
        row('90:08:00:00:00:05', 5, listed: true), // configured before
        row('90:08:00:00:00:04', 4), // unique number, taken earlier
      ];
      final own = {'90:08:00:00:00:01', '90:08:00:00:00:03', '900800000002'};
      final known = [
        {'mac': '90:08:00:00:00:02', 'device_number': 2}, // skipped, off now
      ];
      final list = starAllowList(rows: rows, own: own, first: 1, known: known);
      expect([for (final e in list) e.id], [1, 2, 3, 4, 5]);
      expect(
        [for (final e in list) e.mac],
        [
          '90:08:00:00:00:01',
          '90:08:00:00:00:02',
          '90:08:00:00:00:03',
          '90:08:00:00:00:04',
          '90:08:00:00:00:05',
        ],
      );
      // Enforced: a connected unlisted PTU outside [own] is a foreign one.
      final enforced = starAllowList(
        rows: rows,
        own: own,
        first: 1,
        enforced: true,
        known: known,
      );
      expect([for (final e in enforced) e.id], [1, 2, 3, 5]);
      // Gateway 2 (#6..#10): nothing of gateway 1's range.
      expect(starAllowList(rows: rows, own: own, first: 6), [
        (id: 7, mac: '90:08:00:00:00:07'),
      ]);
    });

    test('ack / count helpers and texts (no firmware codes)', () {
      expect(
        setConfigRejected({
          'message': 'config updated: 0 params changed, 1 rejected (invalid)',
        }),
        isTrue,
      );
      expect(
        setConfigRejected({'message': 'config updated: 1 params changed'}),
        isFalse,
      );
      expect(
        unlistedStarPtus({
          'star_enforced': true,
          'devices': [
            {'connected': true, 'star_listed': false},
            {'connected': true, 'star_listed': true},
          ],
        }),
        1,
      );
      expect(
        unlistedStarPtus({
          'star_enforced': false,
          'devices': [
            {'connected': true, 'star_listed': false},
          ],
        }),
        0,
      );
      expect(foreignPtuText(foreign: 0, unlisted: 0), isNull);
      for (final text in [
        foreignPtuText(foreign: 2, unlisted: 0)!,
        foreignPtuText(foreign: 0, unlisted: 1)!,
        starListFailedText,
        starListSwitchFailedText,
        starListWrittenText([1, 2]),
      ]) {
        expect(text, isNot(matches(RegExp(r'foreign|star|_|listed|enforced'))));
      }
      expect(
        foreignPtuText(foreign: 2, unlisted: 0),
        startsWith('附近有 2 台編號相同的其他 PTU，已被閘道器忽略'),
      );
      expect(starListFailedText, startsWith('PTU 綁定名單未寫入，請重試'));
    });
  });

  group('1. the verified list is written once the star verification '
      'passed', () {
    test('after verification (again, after the list sent before the '
        'assigns), own + earlier-configured PTUs, read back', () async {
      final fake = StarListLink();
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      final macs = ptuMacs(fake);
      var s = container.read(commissionProvider);
      expect(s.step, 4);
      // The PTU configured on an earlier visit is left untouched.
      c.select(_old, false);
      await c.configurePtus();
      s = container.read(commissionProvider);
      expect(s.step, 6);
      // Round 27: the target list went out before the assigns.
      expect(fake.starWrites, hasLength(1));
      expect(s.starListStage, StarListStage.beforeAssign);

      await c.verify('https://example.invalid', 'pw');
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      expect(fake.starWrites, hasLength(2));
      expect(fake.starWrites.last.toSet(), macs.toSet());
      expect(fake.starMacs!.toSet(), macs.toSet());
      // Written after the backend confirmed the data, then read back.
      final write = fake.log.lastIndexOf('set_config:star');
      expect(
        write,
        greaterThan(fake.log.lastIndexOf('PATCH bot-monitor true')),
      );
      expect(fake.log.sublist(write), contains('get_config'));
      expect(s.starList, StarListStatus.written);
      expect(s.starListSwitch, isFalse);
      expect(s.starListStage, StarListStage.verified);
      expect(s.starListIds, [1, 2, 3, 4]);
      expect(s.report, contains('PTU 綁定名單：已寫入 #1、#2、#3、#4'));
      expect(s.busy, isFalse);
    });

    test('resume after a link loss: PTUs of the interrupted part are listed '
        'too', () async {
      final keep = autoRelinkRounds;
      autoRelinkRounds = 0;
      addTearDown(() => autoRelinkRounds = keep);
      final fake = StarListLink();
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      final macs = ptuMacs(fake);
      c.select(_old, false);
      fake.dropAfterAssigns = 1;
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.resumePending, isTrue);
      expect(s.assignedOk, {macs[0]});
      expect(fake.starWrites, hasLength(1), reason: 'before the assigns');

      await c.resumeAssign();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      // Round 27: sent again before the resumed assigns.
      expect(fake.starWrites, hasLength(2));
      await c.verify('https://example.invalid', 'pw');
      s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(fake.starWrites, hasLength(3));
      for (final write in fake.starWrites) {
        expect(write.toSet(), macs.toSet());
      }
      expect(s.starList, StarListStatus.written);
    });

    test('an own PTU gone at the end (skipped / off) keeps its place on the '
        'list; a stranger never takes its number', () async {
      final fake = StarListLink(oldPtu: false);
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      final macs = ptuMacs(fake);
      await c.configurePtus();
      await c.verify('https://example.invalid', 'pw');
      expect(
        container.read(commissionProvider).starList,
        isNot(StarListStatus.failed),
      );
      // Next visit: #2 is off and a stranger carrying #2 is connected.
      final two = fake.devices.firstWhere((d) => d['mac'] == macs[1]);
      fake.hidden.add(macs[1]);
      fake.devices.add({...two, 'mac': '9F:77:EF:C2:96:00', 'connected': true});
      fake.starMacs = null;
      await c.writeStarList();
      final s = container.read(commissionProvider);
      expect(s.starList, StarListStatus.written);
      expect(fake.starWrites.last.toSet(), macs.toSet());
      expect(fake.starWrites.last, isNot(contains('9F:77:EF:C2:96:00')));
    });

    test('firmware before 1.7.36: never sent, nothing shown', () async {
      final fake = StarListLink(fw: '1.7.35');
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      await c.verify('https://example.invalid', 'pw');
      final s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      expect(fake.starWrites, isEmpty);
      expect(fake.log, isNot(contains('set_config:star')));
      expect(s.starList, StarListStatus.none);
      expect(s.report, isNot(contains('綁定名單')));
      // No star status read at step 7 either.
      expect(s.foreignPtus, 0);
    });

    test('direct mode: never sent', () async {
      final fake = StarListLink(oldPtu: false);
      final (container, _) = await starStep7(
        fake,
        topology: GatewayTopology.direct,
      );
      addTearDown(container.dispose);
      expect(fake.log, isNot(contains('set_config:star')));
    });
  });

  group('failures: retried, shown, never block the completion', () {
    test('three timeouts: completion kept, notice + retry writes it', () async {
      final fake = StarListLink();
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      expect(fake.starWrites, hasLength(1), reason: 'before the assigns');
      fake.failStarWrites = 3;
      await c.verify('https://example.invalid', 'pw');
      var s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(s.verified, isTrue);
      expect(s.error, isNull, reason: 'no red banner');
      expect(
        fake.starWrites,
        hasLength(1 + CommissioningController.starListAttempts),
      );
      expect(s.starList, StarListStatus.failed);
      expect(s.report, contains('PTU 綁定名單：未寫入'));

      await c.writeStarList();
      s = container.read(commissionProvider);
      expect(fake.starWrites, hasLength(5));
      expect(s.starList, StarListStatus.written);
      expect(s.report, contains('PTU 綁定名單：已寫入'));
      expect(s.step, 7);
    });

    test('a rejected list (read back differs) counts as not written', () async {
      final fake = StarListLink();
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      fake.rejectStar = true;
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.step, 6, reason: 'a refused list never blocks the assigns');
      expect(fake.starWrites, hasLength(3));
      expect(fake.starMacs, isNull);
      expect(s.starList, StarListStatus.failed);
      expect(s.starListStage, StarListStage.beforeAssign);
      await c.verify('https://example.invalid', 'pw');
      s = container.read(commissionProvider);
      expect(s.step, 7);
      expect(fake.starWrites, hasLength(6));
      expect(fake.starMacs, isNull);
      expect(s.starList, StarListStatus.failed);
      expect(s.starListStage, StarListStage.verified);
    });

    test('one timeout, then written on the automatic retry', () async {
      final fake = StarListLink();
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      fake.failStarWrites = 1;
      await c.verify('https://example.invalid', 'pw');
      expect(fake.starWrites, hasLength(3));
      expect(
        container.read(commissionProvider).starList,
        StarListStatus.written,
      );
    });
  });

  group('2. direct → star sends the list again with the switch', () {
    test('a stale list from before direct mode would refuse the chosen PTUs: '
        'sent before the assigns and again right after max_connections, '
        'before join_fleet', () async {
      final fake = StarListLink(oldPtu: false);
      fake.config['max_connections'] = 1; // direct mode until step 8
      fake.starMacs = ['11:22:33:44:55:66']; // before direct mode
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      final macs = ptuMacs(fake);
      await c.configurePtus();
      var s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6, reason: 'the chosen PTUs connected');
      final max = fake.log.indexOf('set_config');
      final before = fake.log.indexOf('set_config:star');
      final star = fake.log.lastIndexOf('set_config:star');
      expect(before, lessThan(fake.log.indexOf('assign_device_id')));
      expect(star, greaterThan(max));
      expect(star, lessThan(fake.log.indexOf('join_fleet')));
      expect(fake.starWrites, hasLength(2));
      for (final write in fake.starWrites) {
        expect(write.toSet(), macs.toSet());
      }
      expect(s.starList, StarListStatus.written);
      expect(s.starListSwitch, isTrue);

      await c.verify('https://example.invalid', 'pw');
      s = container.read(commissionProvider);
      expect(fake.starWrites, hasLength(3));
      expect(s.starList, StarListStatus.written);
      expect(s.starListSwitch, isFalse);
    });

    test('through the topology menu (direct flow → star at step 7)', () async {
      final keep = directPollInterval;
      directPollInterval = const Duration(milliseconds: 1);
      addTearDown(() => directPollInterval = keep);
      final fake = StarListLink(oldPtu: false);
      fake.starMacs = ['11:22:33:44:55:66'];
      final (container, c) = await starStep7(
        fake,
        topology: GatewayTopology.direct,
      );
      addTearDown(container.dispose);
      expect(fake.config['max_connections'], 1);
      await c.switchTopology(GatewayTopology.star);
      expect(container.read(commissionProvider).selected, hasLength(3));
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.step, 6);
      expect(fake.starWrites, hasLength(2), reason: 'before assign + switch');
      for (final write in fake.starWrites) {
        expect(write.toSet(), ptuMacs(fake).toSet());
      }
    });

    test('star → star (no switch): only the list before the assigns', () async {
      final fake = StarListLink(oldPtu: false);
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(fake.starWrites, hasLength(1));
      expect(s.starListSwitch, isFalse);
      expect(s.starListStage, StarListStage.beforeAssign);
    });

    test('switch write fails: step 8 goes on and says so; old firmware never '
        'sends it', () async {
      final fake = StarListLink(oldPtu: false);
      fake.config['max_connections'] = 1;
      // Only the write after the switch fails (the one before the assigns
      // goes to the still direct gateway).
      fake.failStarIf = () => fake.starMode;
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      await c.configurePtus();
      final s = container.read(commissionProvider);
      expect(s.step, 6);
      expect(s.starList, StarListStatus.failed);
      expect(s.starListSwitch, isTrue);
      expect(fake.starWrites, hasLength(1 + 3));
      expect(fake.log, contains('join_fleet'));

      final legacy = StarListLink(fw: '1.7.35', oldPtu: false);
      legacy.config['max_connections'] = 1;
      final (container2, c2) = await starStep7(legacy);
      addTearDown(container2.dispose);
      await c2.configurePtus();
      expect(container2.read(commissionProvider).step, 6);
      expect(legacy.starWrites, isEmpty);
    });
  });

  group('3. foreign PTUs at the star list', () {
    test('foreign_ptus from get_status, unlisted connected ones from '
        'get_ble_devices', () async {
      final fake = StarListLink(oldPtu: false);
      fake.foreignPtus = 2;
      final (container, c) = await starStep7(fake);
      addTearDown(container.dispose);
      var s = container.read(commissionProvider);
      expect(s.foreignPtus, 2);
      expect(s.unlistedPtus, 0, reason: 'list not set: nothing enforced');

      // Enforced list without the connected #4 of an earlier visit.
      fake.foreignPtus = 0;
      fake.starMacs = [ptuMacs(fake).first];
      fake.devices.add({
        'mac': _old,
        'rssi': -70,
        'device_number': 4,
        'connected': true,
        'notify_enabled': true,
        'zombie': false,
        'last_data_age_sec': 0,
      });
      await c.discover();
      s = container.read(commissionProvider);
      expect(s.foreignPtus, 0);
      expect(s.unlistedPtus, 1);
      expect(
        foreignPtuText(foreign: s.foreignPtus, unlisted: s.unlistedPtus),
        contains('不在這台閘道器的綁定名單'),
      );
    });

    test('old firmware: no star status read, no notice', () async {
      final fake = StarListLink(fw: '1.7.35', oldPtu: false);
      fake.foreignPtus = 2;
      final (container, _) = await starStep7(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.foreignPtus, 0);
      expect(fake.log, isNot(contains('get_status')));
    });
  });

  group('widgets', () {
    Future<(ProviderContainer, StarListLink)> pump(
      WidgetTester tester,
      StarListLink fake,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      });
      await tester.pump();
      return (container, fake);
    }

    testWidgets('star list shows the foreign notice in plain words', (
      tester,
    ) async {
      final fake = StarListLink(oldPtu: false)..foreignPtus = 1;
      await pump(tester, fake);
      final notice = find.byKey(const Key('foreign-ptu-notice'));
      await tester.ensureVisible(notice);
      final text = tester
          .widget<Text>(
            find.descendant(of: notice, matching: find.byType(Text)),
          )
          .data!;
      expect(text, startsWith('附近有 1 台編號相同的其他 PTU，已被閘道器忽略'));
      expect(text, isNot(matches(RegExp(r'foreign|star|_'))));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('completion page: not written → notice and 重試寫入綁定名單', (
      tester,
    ) async {
      final fake = StarListLink(oldPtu: false);
      final (container, _) = await pump(tester, fake);
      await tester.runAsync(() async {
        final c = container.read(commissionProvider.notifier);
        await c.configurePtus();
        fake.failStarWrites = 3;
        await c.verify('https://example.invalid', 'pw');
      });
      await tester.pump();
      expect(container.read(commissionProvider).step, 7);
      final retry = find.byKey(const Key('star-list-retry'));
      await tester.ensureVisible(retry);
      expect(find.text(starListFailedText), findsOneWidget);
      expect(find.text(starListRetryLabel), findsOneWidget);

      await tester.tap(retry);
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (container.read(commissionProvider).starList ==
              StarListStatus.written) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(fake.starWrites, hasLength(5));
      expect(find.byKey(const Key('star-list-retry')), findsNothing);
      expect(find.text(starListWrittenText([1, 2, 3])), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
