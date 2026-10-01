import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';

const a = GatewayPeer('AA:BB:CC:DD:EE:01', 'GIOS-S1-GW01', -40);
const b = GatewayPeer('AA:BB:CC:DD:EE:02', 'GIOS-S1-GW02', -40);

class LifecyclePlatform extends UniversalBlePlatform {
  final events = <String>[];
  final states = <String, BleConnectionState>{};
  String? gatedStage;
  Completer<void>? gate;
  bool gateFails = false;
  bool refuseDisconnect = false;
  final frames = JsonFrames();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> enter(String stage, String id) async {
    events.add('$stage:$id');
    if (stage == gatedStage) {
      await gate!.future;
      if (gateFails) throw StateError('late $stage failure');
    }
  }

  @override
  Future<void> connect(
    String id, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    states[id] = BleConnectionState.connecting;
    await enter('connect', id);
    states[id] = BleConnectionState.connected;
    updateConnection(id, true);
  }

  @override
  Future<void> disconnect(String id) async {
    await enter('disconnect', id);
    if (refuseDisconnect) {
      states[id] = BleConnectionState.connecting;
      updateConnection(id, false);
      return;
    }
    states[id] = BleConnectionState.disconnected;
    updateConnection(id, false);
    events.add('closed:$id');
  }

  @override
  Future<BleConnectionState> getConnectionState(String id) async =>
      states[id] ?? BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(String id, bool descriptors) async {
    await enter('discover', id);
    return [
      BleService(nusService, [
        BleCharacteristic(nusRx, [CharacteristicProperty.write], []),
        BleCharacteristic(nusTx, [CharacteristicProperty.notify], []),
      ]),
    ];
  }

  @override
  Future<void> setNotifiable(
    String id,
    String service,
    String characteristic,
    BleInputProperty property,
  ) => enter('notify', id);

  @override
  Future<int> requestMtu(String id, int expected) async {
    await enter('mtu', id);
    return 247;
  }

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) => enter('startScan', 'adapter');

  @override
  Future<void> stopScan() => enter('stopScan', 'adapter');

  @override
  Future<void> writeValue(
    String id,
    String service,
    String characteristic,
    Uint8List bytes,
    BleOutputProperty property,
  ) async {
    events.add('write:$id');
    for (final frame in frames.add(bytes)) {
      updateCharacteristicValue(
        id,
        nusTx,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'req_id': frame['req_id'],
              'status': 'ok',
              'result': {'peer': id},
            }),
          ),
        ),
        null,
      );
    }
  }
}

class LifecycleLink extends BleGatewayLink {
  @override
  Future<void> prepare() async {}
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'expected native stage was reached');
}

Matcher code(String value) =>
    isA<GatewayFailure>().having((error) => error.code, 'code', value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Duration oldSettle, oldCleanupTimeout;
  setUp(() {
    oldSettle = BleGatewayLink.staleSettle;
    oldCleanupTimeout = BleGatewayLink.nativeCleanupTimeout;
    BleGatewayLink.staleSettle = Duration.zero;
    UniversalBle.clearQueue();
  });
  tearDown(() {
    BleGatewayLink.staleSettle = oldSettle;
    BleGatewayLink.nativeCleanupTimeout = oldCleanupTimeout;
    UniversalBle.clearQueue();
  });

  for (final stage in ['connect', 'discover', 'notify', 'mtu']) {
    for (final lateFailure in [false, true]) {
      test('cancel drains late $stage ${lateFailure ? "error" : "success"}; '
          'A-B-A cannot overlap or replace the ready session', () async {
        final platform = LifecyclePlatform()
          ..gatedStage = stage
          ..gate = Completer<void>()
          ..gateFails = lateFailure;
        UniversalBle.setInstance(platform);
        final link = BleGatewayLink();
        final first = expectLater(link.connect(a), throwsA(code('cancelled')));
        await until(() => platform.events.contains('$stage:${a.id}'));
        await expectLater(link.connect(b), throwsA(code('busy')));
        await expectLater(link.connect(a), throwsA(code('busy')));
        var disconnected = false;
        final stopping = link.disconnect().then((_) => disconnected = true);
        expect(identical(link.disconnect(), link.disconnect()), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(disconnected, isFalse);
        await expectLater(link.connect(b), throwsA(code('busy')));
        platform.gate!.complete();
        await first;
        await stopping;
        expect(link.signalConnected, isFalse);
        final closeAt = platform.events.lastIndexOf('closed:${a.id}');
        expect(closeAt, greaterThanOrEqualTo(0));
        if (stage == 'connect') {
          expect(platform.events, isNot(contains('discover:${a.id}')));
        }
        platform.gatedStage = null;
        platform.gateFails = false;
        await link.connect(b);
        expect(
          platform.events.indexOf('connect:${b.id}'),
          greaterThan(closeAt),
        );
        expect((await link.command('ping'))['peer'], b.id);
        await link.disconnect();
        await link.connect(a);
        expect((await link.command('ping'))['peer'], a.id);
        await link.disconnect();
      });
    }
  }

  test('slow native cleanup blocks both A2 and B until completion', () async {
    final platform = LifecyclePlatform();
    UniversalBle.setInstance(platform);
    final link = BleGatewayLink();
    await link.connect(a);
    platform.gatedStage = 'disconnect';
    platform.gate = Completer<void>();
    final stopping = link.disconnect();
    await until(
      () => platform.events.where((e) => e == 'disconnect:${a.id}').length == 2,
    );
    await expectLater(link.connect(a), throwsA(code('busy')));
    await expectLater(link.connect(b), throwsA(code('busy')));
    platform.gate!.complete();
    await stopping;
    platform.gatedStage = null;
    await link.connect(a);
    expect((await link.command('ping'))['peer'], a.id);
    await link.disconnect();
  });

  test(
    'unconfirmed cleanup quarantines address until explicit disconnect retry',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await link.connect(a);
      platform.refuseDisconnect = true;
      await expectLater(link.disconnect(), throwsA(code('cleanup_failed')));
      await expectLater(link.connect(b), throwsA(code('cleanup_failed')));
      expect(platform.events, isNot(contains('connect:${b.id}')));
      platform.refuseDisconnect = false;
      await link.disconnect();
      await link.connect(b);
      expect((await link.command('ping'))['peer'], b.id);
      await link.disconnect();
    },
  );
  test(
    'disconnect timeout fails closed and drains before explicit retry',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await link.connect(a);
      BleGatewayLink.nativeCleanupTimeout = const Duration(milliseconds: 20);
      platform.gatedStage = 'disconnect';
      platform.gate = Completer<void>();
      await expectLater(link.disconnect(), throwsA(code('cleanup_failed')));
      await expectLater(link.connect(b), throwsA(code('cleanup_failed')));
      expect(platform.events, isNot(contains('connect:${b.id}')));
      platform.gate!.complete();
      await until(
        () => platform.events.where((e) => e == 'closed:${a.id}').length == 2,
      );
      platform.gatedStage = null;
      await link.disconnect();
      await link.connect(b);
      expect((await link.command('ping'))['peer'], b.id);
      await link.disconnect();
    },
  );

  test(
    'scan start reserves adapter before connect and cancellation cannot deadlock',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = LifecycleLink();
      final errors = <Object>[];
      final scan = link.scanLive().listen((_) {}, onError: errors.add);
      await expectLater(link.connect(a), throwsA(code('busy')));
      await link.stopScan().timeout(const Duration(seconds: 2));
      await scan.cancel();
      expect(errors, isEmpty);
      await link.connect(a);
      await link.disconnect();
    },
  );

  test(
    'scan requested during connect drains cancellation before starting scan',
    () async {
      final platform = LifecyclePlatform()
        ..gatedStage = 'connect'
        ..gate = Completer<void>();
      UniversalBle.setInstance(platform);
      final link = LifecycleLink();
      final connecting = expectLater(
        link.connect(a),
        throwsA(code('cancelled')),
      );
      await until(() => platform.events.contains('connect:${a.id}'));
      final errors = <Object>[];
      final scan = link.scanLive().listen((_) {}, onError: errors.add);
      await expectLater(link.connect(b), throwsA(code('busy')));
      expect(platform.events, isNot(contains('startScan:adapter')));
      platform.gate!.complete();
      await connecting;
      await until(() => platform.events.contains('startScan:adapter'));
      expect(
        platform.events.indexOf('startScan:adapter'),
        greaterThan(platform.events.lastIndexOf('closed:${a.id}')),
      );
      await link.stopScan();
      await scan.cancel();
      expect(errors, isEmpty);
    },
  );

  test('scan stop remains exclusive until native stop completes', () async {
    final platform = LifecyclePlatform();
    UniversalBle.setInstance(platform);
    final link = LifecycleLink();
    final errors = <Object>[];
    final scan = link.scanLive().listen((_) {}, onError: errors.add);
    await until(() => platform.events.contains('startScan:adapter'));
    platform.gatedStage = 'stopScan';
    platform.gate = Completer<void>();
    final stopping = link.stopScan();
    await until(() => platform.events.contains('stopScan:adapter'));
    await expectLater(link.connect(a), throwsA(code('busy')));
    platform.gate!.complete();
    await stopping;
    await scan.cancel();
    platform.gatedStage = null;
    expect(errors, isEmpty);
    await link.connect(a);
    await link.disconnect();
  });

  test(
    'legacy scan shares reservation and responds to explicit stop',
    () async {
      final platform = LifecyclePlatform();
      UniversalBle.setInstance(platform);
      final link = LifecycleLink();
      final snapshot = link.scan();
      await expectLater(link.connect(a), throwsA(code('busy')));
      await until(() => platform.events.contains('startScan:adapter'));
      await link.stopScan();
      expect(await snapshot.timeout(const Duration(seconds: 2)), isEmpty);
      await link.connect(a);
      await link.disconnect();
    },
  );
}
