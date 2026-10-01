import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/nearby_gateway_scan.dart';

import 'ble_lifecycle_serialization_test.dart'
    show LifecycleLink, LifecyclePlatform, a, code, until;

class PreparingLink extends LifecycleLink {
  final preparing = Completer<void>();
  bool entered = false;
  @override
  Future<void> prepare() async {
    entered = true;
    await preparing.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Duration oldSettle;
  setUp(() {
    oldSettle = BleGatewayLink.staleSettle;
    BleGatewayLink.staleSettle = Duration.zero;
    UniversalBle.clearQueue();
  });
  tearDown(() {
    BleGatewayLink.staleSettle = oldSettle;
    UniversalBle.clearQueue();
  });

  test(
    'nearby scan refuses held connection without disconnecting it',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = LifecycleLink();
      await link.connect(a);
      final previous = List.of(platform.events);
      await expectLater(
        BleNearbyScanner(link).scanNearby(),
        throwsA(code('busy')),
      );
      expect(platform.events, previous);
      expect((await link.command('ping'))['peer'], a.id);
      await link.disconnect();
    },
  );

  test(
    'nearby owns adapter during preparation; leaving cannot start a late scan',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = PreparingLink();
      final stop = Completer<void>();
      final scan = BleNearbyScanner(link).scanNearby(stop: stop.future);
      await until(() => link.entered);
      await expectLater(link.connect(a), throwsA(code('busy')));
      stop.complete();
      link.preparing.complete();
      expect(await scan, isEmpty);
      expect(platform.events, isNot(contains('startScan:adapter')));
      await link.connect(a);
      await link.disconnect();
    },
  );

  test(
    'page return waits late native stop before a connection can start',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = LifecycleLink();
      final stop = Completer<void>();
      final scan = BleNearbyScanner(link).scanNearby(stop: stop.future);
      await until(() => platform.events.contains('startScan:adapter'));
      platform.gatedStage = 'stopScan';
      platform.gate = Completer<void>();
      stop.complete();
      await until(() => platform.events.contains('stopScan:adapter'));
      await expectLater(link.connect(a), throwsA(code('busy')));
      platform.gate!.complete();
      await scan;
      platform.gatedStage = null;
      await link.connect(a);
      final stops = platform.events
          .where((e) => e == 'stopScan:adapter')
          .length;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        platform.events.where((e) => e == 'stopScan:adapter'),
        hasLength(stops),
      );
      expect((await link.command('ping'))['peer'], a.id);
      await link.disconnect();
    },
  );

  test('old nearby finally cannot stop the next page scan', () async {
    final platform = LifecyclePlatform();
    UniversalBle.setInstance(platform);
    final link = LifecycleLink();
    final first = BleNearbyScanner(link).scanNearby();
    await until(() => platform.events.contains('startScan:adapter'));
    platform.gatedStage = 'stopScan';
    platform.gate = Completer<void>();
    final secondStop = Completer<void>();
    final second = BleNearbyScanner(link).scanNearby(stop: secondStop.future);
    await until(() => platform.events.contains('stopScan:adapter'));
    expect(
      platform.events.where((e) => e == 'startScan:adapter'),
      hasLength(1),
    );
    platform.gate!.complete();
    await first;
    await until(
      () => platform.events.where((e) => e == 'startScan:adapter').length == 2,
    );
    expect(platform.events.where((e) => e == 'stopScan:adapter'), hasLength(1));
    platform.gatedStage = null;
    secondStop.complete();
    await second;
    expect(platform.events.where((e) => e == 'stopScan:adapter'), hasLength(2));
  });

  test(
    'failed native scan stop blocks connect until cleanup retry succeeds',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = LifecycleLink();
      final stop = Completer<void>();
      final failed = expectLater(
        BleNearbyScanner(link).scanNearby(stop: stop.future),
        throwsA(code('cleanup_failed')),
      );
      await until(() => platform.events.contains('startScan:adapter'));
      platform.gatedStage = 'stopScan';
      platform.gate = Completer<void>()..complete();
      platform.gateFails = true;
      stop.complete();
      await failed;
      await expectLater(link.connect(a), throwsA(code('cleanup_failed')));
      expect(platform.events, isNot(contains('connect:${a.id}')));
      platform.gatedStage = null;
      platform.gateFails = false;
      await link.disconnect();
      await link.connect(a);
      await link.disconnect();
    },
  );

  test('queued nearby scan cannot bypass failed preceding stop', () async {
    final platform = LifecyclePlatform();
    UniversalBle.setInstance(platform);
    final link = LifecycleLink();
    final first = expectLater(
      BleNearbyScanner(link).scanNearby(),
      throwsA(code('cleanup_failed')),
    );
    await until(() => platform.events.contains('startScan:adapter'));
    platform.gatedStage = 'stopScan';
    platform.gate = Completer<void>();
    platform.gateFails = true;
    final second = expectLater(
      BleNearbyScanner(link).scanNearby(),
      throwsA(code('cleanup_failed')),
    );
    await until(() => platform.events.contains('stopScan:adapter'));
    platform.gate!.complete();
    await first;
    await second;
    expect(
      platform.events.where((e) => e == 'startScan:adapter'),
      hasLength(1),
    );
    await expectLater(link.connect(a), throwsA(code('cleanup_failed')));
    platform.gatedStage = null;
    platform.gateFails = false;
    await link.disconnect();
  });

  test('scan window ends with one owned stop and no native connect', () async {
    final platform = LifecyclePlatform();
    UniversalBle.setInstance(platform);
    final link = LifecycleLink();
    final peers = await BleNearbyScanner(
      link,
    ).scanNearby(window: const Duration(milliseconds: 20));
    expect(peers, isEmpty);
    expect(platform.events, ['startScan:adapter', 'stopScan:adapter']);
  });
}
