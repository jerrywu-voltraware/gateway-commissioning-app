import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';

class ScanPlatform extends UniversalBlePlatform {
  int starts = 0, stops = 0;
  Completer<void>? stopping;
  bool fail = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    starts++;
    if (fail) throw StateError('scanner failed');
  }

  @override
  Future<void> stopScan() async {
    stops++;
    await stopping?.future;
  }
}

class ScanLink extends BleGatewayLink {
  @override
  Future<void> prepare() async {}
}

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 20));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'scan remains active beyond 15 seconds and expires stale peers',
    () async {
      final platform = ScanPlatform();
      UniversalBle.setInstance(platform);
      final link = ScanLink();
      final seen = <List<GatewayPeer>>[];
      final sub = link.scanLive().listen(seen.add);
      await flush();
      platform.updateScanResult(
        BleDevice(deviceId: 'a', name: 'GIOS-S1-GW01', rssi: -80),
      );
      await flush();
      expect(seen.last.single.rssi, -80);
      await Future<void>.delayed(const Duration(seconds: 16));
      expect(platform.stops, 0);
      expect(seen.last, isEmpty);
      platform.updateScanResult(
        BleDevice(deviceId: 'a', name: 'GIOS-S1-GW01', rssi: -42),
      );
      await flush();
      expect(seen.last.single.rssi, -42);
      await link.stopScan();
      await sub.cancel();
      expect(platform.stops, 1);
    },
  );
  test('live results deduplicate and sort before scan completion', () async {
    final platform = ScanPlatform();
    UniversalBle.setInstance(platform);
    final link = ScanLink();
    final seen = <List<GatewayPeer>>[];
    final sub = link.scanLive().listen(seen.add);
    await flush();
    platform.updateScanResult(
      BleDevice(deviceId: 'a', name: 'GIOS-S1-GW01', rssi: -80),
    );
    platform.updateScanResult(
      BleDevice(deviceId: 'b', name: 'GIOS-S1-GW02', rssi: -40),
    );
    platform.updateScanResult(
      BleDevice(deviceId: 'a', name: 'GIOS-S1-GW01', rssi: -50),
    );
    platform.updateScanResult(
      BleDevice(deviceId: 'x', name: 'headphones', rssi: -20),
    );
    await flush();
    expect(seen.last.map((p) => p.id), ['b', 'a']);
    expect(seen.last.last.rssi, -50);
    await link.stopScan();
    await sub.cancel();
    expect(platform.stops, 1);
  });
  test(
    'next scan waits for previous cleanup; old cancellation cannot stop new scan',
    () async {
      final platform = ScanPlatform();
      UniversalBle.setInstance(platform);
      final link = ScanLink();
      final first = link.scanLive().listen((_) {});
      await flush();
      platform.stopping = Completer<void>();
      final stopped = link.stopScan();
      await flush();
      final second = link.scanLive().listen((_) {});
      await flush();
      expect(platform.starts, 1);
      platform.stopping!.complete();
      await stopped;
      await flush();
      expect(platform.starts, 2);
      await first.cancel();
      expect(platform.stops, 1);
      await link.stopScan();
      await second.cancel();
      expect(platform.stops, 2);
    },
  );
  test('failed start closes stream after cleanup and permits retry', () async {
    final platform = ScanPlatform()..fail = true;
    UniversalBle.setInstance(platform);
    final link = ScanLink();
    final errors = <Object>[];
    final done = Completer<void>();
    link.scanLive().listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 2));
    expect(errors, hasLength(1));
    expect(platform.stops, 1);
    platform.fail = false;
    final sub = link.scanLive().listen((_) {});
    await flush();
    expect(platform.starts, 2);
    await link.stopScan();
    await sub.cancel();
  });
}
