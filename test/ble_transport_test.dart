import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/ble_gateway_link.dart';
import 'package:gateway_commissioning/data/contracts.dart';

class FakePlatform extends UniversalBlePlatform {
  bool connected = false, subscribed = false, failMtu = false, drop = false;
  final chunks = <int>[];
  final frames = JsonFrames();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> connect(
    String id, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    connected = true;
    updateConnection(id, true);
  }

  @override
  Future<void> disconnect(String id) async {
    connected = false;
    updateConnection(id, false);
  }

  @override
  Future<BleConnectionState> getConnectionState(String id) async => connected
      ? BleConnectionState.connected
      : BleConnectionState.disconnected;
  @override
  Future<List<BleService>> discoverServices(
    String id,
    bool descriptors,
  ) async => [
    BleService(nusService, [
      BleCharacteristic(nusRx, [CharacteristicProperty.write], []),
      BleCharacteristic(nusTx, [CharacteristicProperty.notify], []),
    ]),
  ];
  @override
  Future<void> setNotifiable(
    String id,
    String service,
    String characteristic,
    BleInputProperty property,
  ) async {
    subscribed = true;
  }

  @override
  Future<int> requestMtu(String id, int expected) async {
    if (failMtu) throw StateError('MTU unavailable');
    return 247;
  }

  @override
  Future<void> writeValue(
    String id,
    String service,
    String characteristic,
    Uint8List bytes,
    BleOutputProperty property,
  ) async {
    expect(subscribed, isTrue);
    expect(property, BleOutputProperty.withResponse);
    expect(characteristic.toLowerCase(), nusRx.toLowerCase());
    chunks.add(bytes.length);
    if (drop) {
      await disconnect(id);
      return;
    }
    for (final frame in frames.add(bytes)) {
      final ack = utf8.encode(
        jsonEncode({
          'req_id': frame['req_id'],
          'status': 'ok',
          'result': {'message': '測試成功'},
        }),
      );
      // Split UTF-8 notifications across arbitrary byte boundaries.
      for (var n = 0; n < ack.length; n += 7) {
        updateCharacteristicValue(
          id,
          nusTx,
          Uint8List.fromList(
            ack.sublist(n, n + 7 > ack.length ? ack.length : n + 7),
          ),
          null,
        );
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fallback in [false, true]) {
    test('Universal BLE ACK framing and MTU fallback=$fallback', () async {
      final platform = FakePlatform()..failMtu = fallback;
      UniversalBle.setInstance(platform);
      final link = BleGatewayLink();
      await link.connect(
        const GatewayPeer('AA:BB:CC:DD:EE:FF', 'GIOS-S1', -40),
      );
      final results = await Future.wait([
        link.command('ping'),
        link.command('get_config'),
      ]);
      expect(results.every((r) => r['message'] == '測試成功'), isTrue);
      expect(platform.chunks.every((n) => n <= (fallback ? 20 : 244)), isTrue);
      await link.disconnect();
    });
  }
  test('Universal BLE disconnect fails pending command', () async {
    final platform = FakePlatform()..drop = true;
    UniversalBle.setInstance(platform);
    final link = BleGatewayLink();
    await link.connect(const GatewayPeer('AA:BB:CC:DD:EE:FF', 'GIOS-S1', -40));
    await expectLater(link.command('ping'), throwsA(isA<GatewayFailure>()));
    await link.disconnect();
  });
}
