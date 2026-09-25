// Round 12 fixes:
// 1. A step 7 phone-gateway drop (scan running or idle) reconnects and
//    rescans by itself; while it runs the button reads 「重新連線中…」
//    (disabled) and 「掃描中…」 never sits beside the banner.
// 2. The saved progress names the step on screen (steps 3-6 all live in
//    controller step 2), also after a fresh run supersedes a saved one.
// 3. The APP never switches the phone's Bluetooth.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';

import 'link_loss_test.dart' show DroppingLink, manualRelinkInThisTest, ready;

/// Drops the link during the next [scanDrops] scan_ble_discover.
class ScanDropLink extends DroppingLink {
  int scanDrops = 0;

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (!down && op == 'scan_ble_discover' && scanDrops > 0) {
      scanDrops--;
      down = true;
      throw const GatewayFailure('disconnected');
    }
    return super.command(op, params);
  }
}

Future<Map?> saved() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('demo_progress') ?? prefs.getString('progress');
  return raw == null ? null : jsonDecode(raw) as Map;
}

(ProviderContainer, CommissioningController) make(DroppingLink fake) {
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
    ],
  );
  return (container, container.read(commissionProvider.notifier));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration keepGap;
  setUp(() {
    keepGap = connectRetryGap;
    connectRetryGap = const Duration(milliseconds: 1);
  });
  tearDown(() => connectRetryGap = keepGap);

  group('1. step 7 link loss', () {
    test('a drop during the scan reconnects and rescans, no tap', () async {
      final fake = ScanDropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      final before = fake.connects;
      final states = <CommissionState>[];
      container.listen(commissionProvider, (_, s) => states.add(s));
      fake.scanDrops = 1;
      await c.discover();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.ptus, isNotEmpty);
      expect(s.relinking, isFalse);
      expect(fake.connects, before + 1);
      expect(states.any((x) => configureLabel(x) == relinkingLabel), isTrue);
      for (final x in states.where((x) => x.step == 4)) {
        expect(
          x.error != null && configureLabel(x) == scanningLabel,
          isFalse,
          reason: 'banner beside scanning label: ${x.message}',
        );
      }
    });

    test('auto reconnect gives up once: banner + manual retry', () async {
      final keep = connectPersistence;
      connectPersistence = Duration.zero;
      addTearDown(() => connectPersistence = keep);
      final fake = ScanDropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.scanDrops = 1;
      fake.failConnect = true;
      await c.discover();
      var s = container.read(commissionProvider);
      expect(s.error, isNotNull);
      expect(s.busy, isFalse);
      expect(s.relinking, isFalse);
      expect(configureLabel(s), rescanAfterLossLabel);
      expect(step7LinkLost(s), isTrue);
      fake.failConnect = false;
      await c.discover();
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.ptus, isNotEmpty);
    });

    test('an idle drop (keep-alive) reconnects by itself', () async {
      final fake = ScanDropLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      c.setAutoRssi(false);
      final before = fake.connects;
      fake.down = true;
      await c.keepAlive(now: DateTime.now().add(const Duration(seconds: 16)));
      expect(
        configureLabel(container.read(commissionProvider)),
        relinkingLabel,
      );
      while (container.read(commissionProvider).relinking) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.connects, before + 1);
    });
  });

  group('2. saved step = step on screen', () {
    Future<(ProviderContainer, CommissioningController)> atGateway({
      String wifi = 'got_ip',
    }) async {
      SharedPreferences.setMockInitialValues({});
      final fake = DroppingLink()..wifiState = wifi;
      final (container, c) = make(fake);
      await c.prepare('https://example.invalid', '');
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      return (container, c);
    }

    test('step 3 (network check, Wi-Fi stage)', () async {
      final (container, _) = await atGateway(wifi: 'disconnected');
      addTearDown(container.dispose);
      final data = await saved();
      expect(data!['shown'], 3);
      expect(
        resumeText(data['step'] as int, [], 0, shown: data['shown'] as int),
        startsWith('上次中斷於第 3 步（Gateway 網路體檢）'),
      );
    });

    test('step 5 (upload confirm) and step 6 (station)', () async {
      final (container, c) = await atGateway();
      addTearDown(container.dispose);
      expect((await saved())!['shown'], 5);
      await c.passNetworkCheck(skip: true);
      final data = await saved();
      expect(data!['shown'], 6);
      expect(data['step'], 2);
      expect(resumeText(2, [], 0, shown: 6), startsWith('上次中斷於第 6 步（站點選擇）'));
    });

    test('step 8 while assigning', () async {
      manualRelinkInThisTest();
      final fake = DroppingLink();
      final (container, c) = await ready(fake);
      addTearDown(container.dispose);
      fake.dropAfterAssigns = 1;
      await c.configurePtus();
      final data = await saved();
      expect(data!['shown'], 8);
      expect(data['step'], 5);
    });

    test('restart prompt uses the saved screen step', () async {
      SharedPreferences.setMockInitialValues({
        'demo_progress': jsonEncode({'step': 2, 'shown': 5, 'peer': 'x'}),
      });
      final (container, c) = make(DroppingLink());
      addTearDown(container.dispose);
      await c.restore();
      expect(
        container.read(commissionProvider).message,
        startsWith('上次中斷於第 5 步（確認資料上傳）'),
      );
    });

    test('a fresh run supersedes an older saved step', () async {
      SharedPreferences.setMockInitialValues({
        'demo_progress': jsonEncode({'step': 2, 'shown': 3, 'peer': 'x'}),
      });
      final (container, c) = make(DroppingLink());
      addTearDown(container.dispose);
      await c.restore();
      await c.prepare('https://example.invalid', '');
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.passNetworkCheck(skip: true);
      expect((await saved())!['shown'], 6);
    });
  });

  test('3. the APP never switches the phone Bluetooth', () {
    final pattern = RegExp(
      r'(enable|disable)Bluetooth\(|REQUEST_(ENABLE|DISABLE)',
    );
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      expect(pattern.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}
