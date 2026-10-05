// Round 24 field test fixes (APP 5312e31, FW 1.7.32):
// 1. The back office's identify in star mode came back
//    `ptu_write:"ambiguous_target"` (only the gateway blinked) and the
//    notice read 「後台剛讓這台樁閃燈…PTU 未收到（ambiguous_target）」: it now
//    says what blinked — 「後台讓閘道器閃燈（請看閘道器上的燈）」, or
//    「後台已送出 PTU #3 閃燈」 — and never shows the raw code.
// 2. A rescan refused as busy left 「已連線 0 台／周邊未連線 0 台 · 已選 0 /
//    5 台」 (read as nothing found; the diagnostics' ptus was [] too): the
//    list before it is kept and the count lines say 「閘道器忙碌，列表暫時
//    無法更新」.
// 3. The help sheet showed 「狀況代碼：HELP_ONLY」: the code in words; the
//    wire name only in its 詳細資訊 and in what goes to the back office.
// 4. A gateway restart during 「配置」 was recorded as BLE_LINK_DROP (the
//    restart is only known after the phone reconnects): that failure is
//    re-classified GW_REBOOTED with a report and a package of its own.
// 5. A help queued offline reached the backend 54.5 s after the network
//    came back (back-off at 60 s): the phone's network coming back sends
//    the outbox at once.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_reboot.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/data/network_watch.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'package:gateway_commissioning/presentation/field_help_sheet.dart';
import 'support/l10n.dart';

const _base = 'https://example.invalid';

/// Demo gateway + backend recording the rescue uploads. [busyOps] answer
/// `busy` (always); [dropAfterAssigns]: the phone link drops after that
/// many assigns, the gateway restarting for [restartReason] meanwhile.
/// [offline]: every rescue upload fails as a network error.
class R24Gateway extends DemoSystem implements SessionInfo {
  R24Gateway() {
    bootCount = 40;
  }

  final busyOps = <String>{};
  int? dropAfterAssigns;
  String? restartReason;
  bool down = false;
  bool timeoutNextNet = false;
  String? restartOnTimeout;
  bool offline = false;
  final assigns = <String>[];
  final uploads = <(String, Map<String, dynamic>)>[];

  List<Map<String, dynamic>> get reports => [
    for (final u in uploads)
      if (u.$1 == fieldSessionsPath) u.$2,
  ];
  List<Map<String, dynamic>> get diags => [
    for (final u in uploads)
      if (u.$1 == fieldDiagnosticsPath) u.$2,
  ];

  @override
  bool get hasSession => true;

  @override
  String? get origin => _base;

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    down = false;
    await super.connect(peer, onStage: onStage);
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (down) throw const GatewayFailure('not_connected');
    if (busyOps.contains(op)) throw const GatewayFailure.gateway('busy');
    if (op == 'get_net_status' && timeoutNextNet) {
      timeoutNextNet = false;
      if (restartOnTimeout != null) simulateRestart(restartOnTimeout!);
      throw const GatewayFailure('timeout');
    }
    if (op == 'assign_device_id') {
      if (dropAfterAssigns != null && assigns.length >= dropAfterAssigns!) {
        dropAfterAssigns = null;
        down = true;
        if (restartReason != null) simulateRestart(restartReason!);
        throw const GatewayFailure('not_connected');
      }
      assigns.add(params['mac'].toString());
    }
    return super.command(op, params);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!path.startsWith('/api/field/')) {
      return super.request(method, path, body);
    }
    uploads.add((path, Map<String, dynamic>.from(body ?? const {})));
    if (offline) {
      throw GatewayFailure.network(endpoint: '$method $path', detail: 'x');
    }
    return {'ok': true, 'duplicate': false};
  }
}

ProviderContainer _container(
  DemoSystem fake, {
  FieldReporterConfig config = const FieldReporterConfig(allowDemoLink: true),
}) {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      fieldReporterConfigProvider.overrideWithValue(config),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _until(bool Function() done, {int ms = 1500}) async {
  for (var i = 0; i < ms ~/ 10 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'condition not reached');
}

/// Logged in, connected, Wi-Fi set, online; the PTU list read unless
/// [read] is false (step 7).
Future<CommissioningController> _toStep7(
  ProviderContainer container, {
  bool read = true,
}) async {
  final c = container.read(commissionProvider.notifier);
  await c.prepare(_base, 'login-pw-0001');
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  await c.configureWifi(1, 1, 'Office-2G', 'Wifi-Secret-4455');
  await c.online();
  if (read) await c.discover();
  await _settle();
  return c;
}

/// Step 8 tests drive 「重新連線並繼續」 themselves.
void _manualRelink() {
  final keep = autoRelinkRounds;
  autoRelinkRounds = 0;
  addTearDown(() => autoRelinkRounds = keep);
}

/// No raw code of the firmware or of the rescue contract.
final _rawCode = RegExp(r'[a-z]+_[a-z_]+|[A-Z]{2,}_[A-Z_]+');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. the back office\'s identify says what blinked', () {
    const listed = [
      {'mac': '90:5F:E8:9A:96:00', 'device_number': 1, 'connected': true},
      {'mac': '90:2C:E8:9A:96:00', 'device_number': 2, 'connected': true},
      {'mac': '90:08:1C:8E:96:00', 'device_number': 3, 'connected': true},
      {'mac': '90:3B:E8:9A:96:00', 'device_number': 0, 'connected': true},
    ];

    test('star, ptu_write ambiguous_target: the gateway, no raw code', () {
      const ack = {
        'gateway_led': 'ok',
        'ptu_write': 'ambiguous_target',
        'ptu_confirmed': false,
        'status': 'ok',
      };
      final text = remoteIdentifyText(ack, ptus: listed);
      expect(text, '後台讓閘道器閃燈（請看閘道器上的燈）');
      expect(text, isNot(contains('樁')));
      expect(text, isNot(matches(_rawCode)));
      // Any other refusal, and a gateway-only ack, read the same.
      for (final other in [
        {'ptu_write': 'not_connected'},
        {'ptu_write': 'write_failed'},
        {'gateway_led': 'ok'},
      ]) {
        expect(
          remoteIdentifyText(other, ptus: listed),
          remoteIdentifyGatewayText,
        );
      }
    });

    test(
      'a PTU written: its number, else the MAC part that tells it apart',
      () {
        const ack = {
          'gateway_led': 'ok',
          'ptu_write': 'ok',
          'ptu_confirmed': false,
          'ptu_confirm': 'timeout',
          'mac': '90081C8E9600',
          'rssi': -46,
        };
        expect(
          remoteIdentifyText(ack, ptus: listed),
          '後台已送出 PTU #3 辨識指令（請看樁上燈號） · 舊版閘道器未取得 PTU 確認 · -46 dBm',
        );
        // Confirmation as before.
        expect(
          remoteIdentifyText({
            ...ack,
            'ptu_confirmed': true,
            'ptu_confirm': 'ok',
          }, ptus: listed),
          startsWith('後台已送出 PTU #3 辨識指令（請看樁上燈號） · $identifyConfirmedText'),
        );
        // The ack's own number wins (backend identify with `mac`).
        expect(
          identifyPtuLabel({...ack, 'device_number': 4}, ptus: listed),
          '#4',
        );
        // Not numbered yet: the byte no other listed PTU has there.
        expect(
          identifyPtuLabel(const {
            'ptu_write': 'ok',
            'mac': '90:3B:E8:9A:96:00',
          }, ptus: listed),
          '…3B…',
        );
        // No list: the whole MAC.
        expect(identifyPtuLabel(ack), '90:08:1C:8E:96:00');
        // Written but not named: still 「PTU」, never 「這台樁」.
        expect(
          remoteIdentifyText(const {'ptu_write': 'ok'}),
          '後台已送出 PTU 辨識指令（請看樁上燈號） · PTU 辨識指令已送出',
        );
      },
    );

    test('the APP\'s own identify texts carry the reason in words', () {
      for (final code in [
        'ambiguous_target',
        'not_connected',
        'write_failed',
      ]) {
        final ack = {'ptu_write': code};
        expect(identifyNoteText(ack), isNot(contains(code)));
        expect(identifyPtuFailedText(code), isNot(contains(code)));
        expect(identifyResultText(ack), isNot(contains(code)));
      }
      expect(
        identifyPtuFailedText('ambiguous_target'),
        '閘道器正在閃燈（4 秒）；PTU 指令未送出（閘道器連著多台 PTU，沒有指定哪一台）。',
      );
    });

    test('star step 7: the notice names the listed PTU', () async {
      final fake = R24Gateway();
      fake.devices[2]['device_number'] = 3;
      final container = _container(fake);
      final c = await _toStep7(container);
      expect(c.directFlow, isFalse);
      final s0 = container.read(commissionProvider);
      expect(s0.ptus, hasLength(fake.devices.length));

      fake.relayForeignAck(const {
        'gateway_led': 'ok',
        'ptu_write': 'ambiguous_target',
        'ptu_confirmed': false,
        'req_id': '20260926-00040',
        'status': 'ok',
      });
      await _settle();
      var s = container.read(commissionProvider);
      expect(s.remoteIdentifyCount, 1);
      expect(s.remoteIdentifyNote, '後台讓閘道器閃燈（請看閘道器上的燈）');

      fake.relayForeignAck({
        'gateway_led': 'ok',
        'ptu_write': 'ok',
        'ptu_confirmed': false,
        'ptu_confirm': 'timeout',
        'mac': fake.devices[2]['mac'],
        'req_id': '20260926-00041',
        'status': 'ok',
      });
      await _settle();
      s = container.read(commissionProvider);
      expect(s.remoteIdentifyCount, 2);
      expect(s.remoteIdentifyNote, startsWith('後台已送出 PTU #3 辨識指令（請看樁上燈號）'));
      expect(s.remoteIdentifyNote, contains('舊版閘道器未取得 PTU 確認'));
      expect(s.step, s0.step);
      expect(s.error, s0.error);
      expect(s.selected, s0.selected);
    });
  });

  group('2. a list read refused as busy is never 「0 台」', () {
    test(
      'rescan refused: the list before it stays, the lines say busy',
      () async {
        final fake = R24Gateway();
        final container = _container(fake);
        final c = await _toStep7(container);
        final before = container.read(commissionProvider);
        expect(before.ptus, isNotEmpty);
        expect(before.selected, isNotEmpty);

        fake.busyOps.add('scan_ble_discover');
        await c.discover();
        await _settle();
        final s = container.read(commissionProvider);
        expect(s.error, const GatewayFailure('busy').message);
        expect(s.ptuListBusy, isTrue);
        expect(s.ptus, before.ptus);
        expect(s.selected, before.selected);
        final count = ptuCountText(s);
        expect(count, startsWith(ptuListBusyText));
        expect(count, contains('上一次的列表'));
        // The kept list's own counts (the demo PTUs are not connected).
        expect(count, '$ptuListBusyText（下面是上一次的列表：${ptuCountText(before)}）');
        expect(selectionCountText(s, 5), isNot(contains('已選 0')));
        // The diagnostics package lists them too (round 24: ptus []).
        await _until(
          () => fake.diags.any((d) => (d['error'] as Map)['code'] == 'GW_BUSY'),
        );
        final diag = fake.diags.lastWhere(
          (d) => (d['error'] as Map)['code'] == 'GW_BUSY',
        );
        expect(diag['ptus'] as List, hasLength(before.ptus.length));

        // The next read that works clears it.
        fake.busyOps.clear();
        await c.discover();
        final after = container.read(commissionProvider);
        expect(after.ptuListBusy, isFalse);
        expect(after.error, isNull);
        expect(ptuCountText(after), startsWith('已連線 '));
      },
    );

    test('first read refused: 「閘道器忙碌，列表暫時無法更新」, no 0 台', () async {
      final fake = R24Gateway()..busyOps.add('get_ble_devices');
      final container = _container(fake);
      await _toStep7(container);
      final s = container.read(commissionProvider);
      expect(s.ptus, isEmpty);
      expect(s.ptuListBusy, isTrue);
      expect(ptuCountText(s), ptuListBusyText);
      expect(selectionCountText(s, 5), ptuListBusyText);
    });

    test('pure texts', () {
      const idle = CommissionState(step: 4, ptuListBusy: true);
      expect(ptuCountText(idle), ptuListBusyText);
      expect(selectionCountText(idle, 5), ptuListBusyText);
      // While a new read runs it is 「讀取中…」 as before.
      const reading = CommissionState(step: 4, busy: true, ptuListBusy: true);
      expect(ptuCountText(reading), ptuCountReadingText);
      // Without the flag an empty list still counts 0 (nothing refused).
      const plain = CommissionState(step: 4);
      expect(ptuCountText(plain), '已連線 0 台／周邊未連線 0 台');
      expect(
        isGatewayBusyFailure(const GatewayFailure.gateway('busy')),
        isTrue,
      );
      expect(isGatewayBusyFailure(const GatewayFailure('not_ready')), isTrue);
      expect(isGatewayBusyFailure(const GatewayFailure('timeout')), isFalse);
    });
  });

  group('3. the help sheet says the code in words', () {
    test('every code has words and no raw code in them', () {
      for (final code in RescueCode.values) {
        expect(code.label, isNotEmpty, reason: code.wire);
        expect(code.label, isNot(matches(_rawCode)), reason: code.wire);
        expect(RescueCode.ofWire(code.wire), code);
      }
      expect(RescueCode.ofWire(null), isNull);
      expect(RescueCode.ofWire('NOT_A_CODE'), isNull);
    });

    test('lines: 狀況 / 錯誤 in words, the code only in the details', () {
      const env = BackendEnvState(loaded: true);
      const peer = GatewayPeer('id', 'GIOS-S80-GW01', -40);
      const config = {
        'site_id': 80,
        'gateway_id': 1,
        'gateway_uid': 'C8F09E4B3A00',
        'fw_version': '1.7.32',
      };
      final quiet = fieldHelpLines(
        const FieldInput(
          state: CommissionState(step: 4, peer: peer, config: config),
          env: env,
        ),
        errorCode: 'HELP_ONLY',
      );
      expect(quiet, contains('狀況：畫面沒有錯誤，現場主動求助'));
      final busy = fieldHelpLines(
        FieldInput(
          state: CommissionState(
            step: 4,
            peer: peer,
            config: config,
            error: const GatewayFailure('busy').message,
          ),
          env: env,
        ),
        errorCode: 'GW_BUSY',
      );
      expect(busy, contains('錯誤：閘道器正在準備或處理其他操作，請稍後重試。'));
      for (final line in [...quiet, ...busy]) {
        expect(line, isNot(matches(_rawCode)), reason: line);
      }
      final stuck = fieldHelpLines(
        const FieldInput(
          state: CommissionState(step: 4, peer: peer, config: config),
          env: env,
        ),
        errorCode: 'STEP_STUCK',
      );
      expect(stuck, contains('狀況：${RescueCode.stepStuck.label}'));
      expect(fieldHelpDetailLines(errorCode: 'GW_BUSY'), ['狀況代碼：GW_BUSY']);
      expect(fieldHelpDetailLines(), isEmpty);
    });

    testWidgets('queued offline: words on the sheet, 詳細資訊 has the code', (
      tester,
    ) async {
      final fake = R24Gateway()..offline = true;
      final container = _container(fake);
      await tester.runAsync(() => _toStep7(container));
      final c = container.read(commissionProvider.notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: FieldHelpSheet())),
        ),
      );
      await tester.runAsync(c.requestHelp);
      await tester.pumpAndSettle();
      expect(container.read(fieldHelpProvider).phase, FieldHelpPhase.queued);
      expect(find.text('・狀況：畫面沒有錯誤，現場主動求助'), findsOneWidget);
      expect(find.textContaining('HELP_ONLY'), findsNothing);
      expect(find.textContaining('狀況代碼'), findsNothing);
      await tester.tap(find.byKey(const Key('field-help-details')));
      await tester.pumpAndSettle();
      expect(find.text('狀況代碼：HELP_ONLY'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('4. a restart found after the drop is GW_REBOOTED', () {
    test('step 8: BLE_LINK_DROP, then on reconnect a GW_REBOOTED report '
        'and package', () async {
      _manualRelink();
      var clock = DateTime(2026, 9, 26, 22, 54);
      final fake = R24Gateway()
        ..restartReason = 'sw'
        ..dropAfterAssigns = 1;
      final container = _container(
        fake,
        config: FieldReporterConfig(allowDemoLink: true, now: () => clock),
      );
      final c = await _toStep7(container);
      await c.configurePtus();
      await _settle();
      var s = container.read(commissionProvider);
      expect(s.error, phoneLinkLostText);
      expect(s.gatewayReboot, isNull, reason: 'not known before reconnect');
      final drop = fake.reports.lastWhere((r) => r['event'] == 'error');
      expect(drop['error_code'], 'BLE_LINK_DROP');
      expect(
        fake.diags.map((d) => (d['error'] as Map)['code']),
        contains('BLE_LINK_DROP'),
      );
      final dropsBefore = fake.reports.length;

      // Past the 10 s package throttle; the reconnect finds boot 40 → 41.
      clock = clock.add(const Duration(seconds: 12));
      await c.resumeAssign();
      await _settle();
      s = container.read(commissionProvider);
      expect(s.gatewayReboot?.to, 41);

      final rebooted = [
        for (final r in fake.reports.skip(dropsBefore))
          if (r['error_code'] == 'GW_REBOOTED') r,
      ];
      expect(rebooted, hasLength(1));
      expect(rebooted.single['event'], 'error');
      expect(rebooted.single['fail_code'], 'phone_link_lost');
      expect(rebooted.single['error_message'], contains('閘道器剛重新啟動'));
      expect(rebooted.single['error_message'], contains('收到重新啟動指令或設定變更'));
      final pkg = fake.diags.lastWhere(
        (d) => (d['error'] as Map)['code'] == 'GW_REBOOTED',
      );
      final error = pkg['error'] as Map;
      expect(error['rebooted'], isTrue);
      expect(error['fail_code'], 'phone_link_lost');
      expect(error['message'], contains('閘道器剛重新啟動'));
      final reboot = (pkg['gateway'] as Map)['reboot'] as Map;
      expect((reboot['from'], reboot['to']), (40, 41));
      // The commissioning went on (nothing of the report touches it).
      expect(s.error, isNull);
    });

    // Phase C（docs/i18n.md §6）：英文畫面的重開機說明是英文，上傳的
    // error_message／診斷包 message 與 step_label 仍是中文。
    test('English: notice on screen in English, uploaded texts in Chinese', () async {
      useLanguage(AppLanguage.en);
      _manualRelink();
      var clock = DateTime(2026, 9, 26, 22, 54);
      final fake = R24Gateway()
        ..restartReason = 'sw'
        ..dropAfterAssigns = 1;
      final container = _container(
        fake,
        config: FieldReporterConfig(allowDemoLink: true, now: () => clock),
      );
      final c = await _toStep7(container);
      await c.configurePtus();
      await _settle();
      final dropsBefore = fake.reports.length;
      clock = clock.add(const Duration(seconds: 12));
      await c.resumeAssign();
      await _settle();
      final s = container.read(commissionProvider);
      expect(s.gatewayReboot?.to, 41);
      final notice = gatewayRebootText(s.gatewayReboot!);
      expect(notice, isNot(matches(RegExp('[一-鿿]'))));
      final rebooted = fake.reports
          .skip(dropsBefore)
          .lastWhere((r) => r['error_code'] == 'GW_REBOOTED');
      expect(rebooted['error_message'], contains('閘道器剛重新啟動'));
      expect(rebooted['error_message'], contains('收到重新啟動指令或設定變更'));
      expect(rebooted['step_label'], matches(RegExp('^[一-鿿]')));
      final pkg = fake.diags.lastWhere(
        (d) => (d['error'] as Map)['code'] == 'GW_REBOOTED',
      );
      expect((pkg['error'] as Map)['message'], contains('閘道器剛重新啟動'));
      expect(pkg['step_label'], matches(RegExp('^[一-鿿]')));
    });

    test(
      'a restart found while its failure is classified: one GW_REBOOTED',
      () async {
        final fake = R24Gateway();
        final container = _container(fake);
        final c = await _toStep7(container);
        final before = fake.reports.length;
        fake
          ..timeoutNextNet = true
          ..restartOnTimeout = 'task_wdt';
        await c.refreshUploadTarget();
        await _settle();
        final s = container.read(commissionProvider);
        expect(s.error, gatewayRebootRetryText);
        final rebooted = [
          for (final r in fake.reports.skip(before))
            if (r['error_code'] == 'GW_REBOOTED') r,
        ];
        expect(rebooted, hasLength(1), reason: 'rule 1, no second report');
        expect(rebooted.single['fail_code'], 'timeout');
        expect(
          fake.diags.where((d) => (d['error'] as Map)['code'] == 'GW_REBOOTED'),
          hasLength(1),
        );
      },
    );

    test(
      'reporter: amend window, other codes, the same restart once',
      () async {
        var clock = DateTime(2026, 9, 26, 12);
        final fake = R24Gateway();
        final container = _container(
          fake,
          config: FieldReporterConfig(allowDemoLink: true, now: () => clock),
        );
        await _toStep7(container);
        final reporter = container.read(fieldReporterProvider);

        // An old link drop (beyond the window): a restart report without it.
        reporter.onFailure(const GatewayFailure('phone_link_lost'), ctlStep: 4);
        clock = clock.add(rebootAmendWindow + const Duration(seconds: 1));
        final n = fake.reports.length;
        reporter.onGatewayReboot(to: 41, text: '閘道器剛重新啟動（原因：原因不明）。');
        await _settle();
        var added = fake.reports.skip(n).toList();
        expect(added.map((r) => r['error_code']), ['GW_REBOOTED']);
        expect(added.single['fail_code'], isNull);

        // The same restart again: nothing.
        reporter.onGatewayReboot(to: 41, text: 'x');
        await _settle();
        expect(fake.reports.length, n + 1);

        // A PTU failure is not something a restart explains.
        clock = clock.add(const Duration(seconds: 20));
        reporter.onFailure(const GatewayFailure('no_devices'), ctlStep: 4);
        final m = fake.reports.length;
        reporter.onGatewayReboot(to: 42, text: 'y');
        await _settle();
        added = fake.reports.skip(m).toList();
        expect(added.last['error_code'], 'GW_REBOOTED');
        expect(added.last['fail_code'], isNull);
        expect(rebootExplainedCodes, contains(RescueCode.bleLinkDrop));
        expect(rebootExplainedCodes, isNot(contains(RescueCode.ptuNoneFound)));
      },
    );
  });

  group('5. the network coming back sends the outbox at once', () {
    test(
      'queued help goes out on the network event, not the back-off',
      () async {
        final network = StreamController<String>.broadcast();
        addTearDown(network.close);
        final fake = R24Gateway();
        final container = _container(
          fake,
          config: FieldReporterConfig(
            allowDemoLink: true,
            networkEvents: () => network.stream,
          ),
        );
        final c = await _toStep7(container);
        final reporter = container.read(fieldReporterProvider);
        await _until(() => reporter.outbox.isEmpty);

        fake.offline = true;
        await c.requestHelp();
        expect(container.read(fieldHelpProvider).phase, FieldHelpPhase.queued);
        expect(reporter.outbox.where((i) => i.isHelp), isNotEmpty);

        // Back online, but inside the back-off: a flush sends nothing.
        fake.offline = false;
        final tries = fake.uploads.length;
        await reporter.flush();
        expect(fake.uploads.length, tries, reason: 'still backing off');
        expect(reporter.outbox, isNotEmpty);

        // 'lost' changes nothing; 'available' sends at once.
        network.add(networkLostEvent);
        await _settle();
        expect(fake.uploads.length, tries);
        final sw = Stopwatch()..start();
        network.add(networkAvailableEvent);
        await _until(() => reporter.outbox.isEmpty);
        expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
        expect(fake.reports.where((r) => r['event'] == 'help'), isNotEmpty);
        expect(container.read(fieldHelpProvider).phase, FieldHelpPhase.sent);
      },
    );

    test('events and the platform stream off Android', () async {
      expect(isNetworkBackEvent(networkAvailableEvent), isTrue);
      expect(isNetworkBackEvent(networkValidatedEvent), isTrue);
      expect(isNetworkBackEvent(networkLostEvent), isFalse);
      expect(isNetworkBackEvent(null), isFalse);
      // Tests run on the host: no platform channel, an empty stream.
      expect(await phoneNetworkEvents().isEmpty, isTrue);
    });

    test('the timed retry stays as the fallback', () {
      expect(
        const FieldReporterConfig().retryEvery,
        const Duration(seconds: 30),
      );
    });
  });
}
