import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/protocol.dart';
import 'contracts.dart';

class BleGatewayLink implements GatewayLink {
  @override
  bool get demo => false;
  String? _device;
  int _mtu = 23;
  String? _rx;
  StreamSubscription<List<int>>? _notify;
  StreamSubscription<bool>? _connection;
  final _frames = JsonFrames();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Future<void> _tail = Future.value();
  int _epoch = 0, _sequence = 0;
  final String _session = Random.secure().nextInt(0x7fffffff).toRadixString(16);

  @override
  Future<void> prepare() async {
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = sdk >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    final result = await permissions.request();
    if (result.values.any((p) => !p.isGranted)) {
      throw const GatewayFailure('permission');
    }
    if (await UniversalBle.getBluetoothAvailabilityState() !=
        AvailabilityState.poweredOn) {
      try {
        if (!await UniversalBle.enableBluetooth(
          timeout: const Duration(seconds: 15),
        )) {
          throw const GatewayFailure('bluetooth_off');
        }
      } catch (_) {
        throw const GatewayFailure('bluetooth_off');
      }
    }
  }

  @override
  Future<List<GatewayPeer>> scan() async {
    await disconnect();
    await prepare();
    final found = <String, GatewayPeer>{};
    final sub = UniversalBle.scanStream.listen((result) {
      final name = result.name ?? '';
      if (name.startsWith('GIOS-S')) {
        found[result.deviceId] = GatewayPeer(
          result.deviceId,
          name,
          result.rssi ?? -127,
        );
      }
    });
    try {
      await UniversalBle.startScan();
      await Future<void>.delayed(const Duration(seconds: 15));
    } finally {
      await UniversalBle.stopScan();
      await sub.cancel();
    }
    return found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  @override
  Future<void> connect(GatewayPeer peer) async {
    await disconnect();
    final epoch = _epoch;
    final device = peer.id;
    _device = device;
    for (int attempt = 0; ; attempt++) {
      if (epoch != _epoch) throw const GatewayFailure('cancelled');
      try {
        await UniversalBle.connect(
          device,
          timeout: const Duration(seconds: 15),
        );
        break;
      } catch (error) {
        if (attempt >= 2 || !error.toString().contains('133')) rethrow;
        await UniversalBle.disconnect(
          device,
          timeout: const Duration(seconds: 5),
        );
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    if (epoch != _epoch) throw const GatewayFailure('cancelled');
    final services = await UniversalBle.discoverServices(
      device,
      timeout: const Duration(seconds: 12),
    ).timeout(const Duration(seconds: 12));
    if (epoch != _epoch) throw const GatewayFailure('cancelled');
    final service = services
        .where((s) => s.uuid.toLowerCase() == nusService.toLowerCase())
        .first;
    _rx = service.characteristics
        .where((c) => c.uuid.toLowerCase() == nusRx.toLowerCase())
        .first
        .uuid;
    final tx = service.characteristics
        .where((c) => c.uuid.toLowerCase() == nusTx.toLowerCase())
        .first;
    _notify = UniversalBle.characteristicValueStream(device, tx.uuid).listen((
      bytes,
    ) {
      if (epoch != _epoch) return;
      try {
        for (final frame in _frames.add(bytes)) {
          final pending = _pending.remove(frame['req_id']);
          if (pending != null && !pending.isCompleted) pending.complete(frame);
        }
      } catch (_) {
        _frames.clear();
      }
    });
    await UniversalBle.subscribeNotifications(
      device,
      nusService,
      tx.uuid,
      timeout: const Duration(seconds: 12),
    ).timeout(const Duration(seconds: 12));
    if (epoch != _epoch) throw const GatewayFailure('cancelled');
    _connection = UniversalBle.connectionStream(device).listen((state) {
      if (!state && epoch == _epoch) {
        _rx = null;
        _frames.clear();
        for (final p in _pending.values) {
          if (!p.isCompleted) {
            p.completeError(const GatewayFailure('disconnected'));
          }
        }
        _pending.clear();
      }
    });
    try {
      _mtu = await UniversalBle.requestMtu(
        device,
        247,
        timeout: const Duration(seconds: 12),
      );
    } catch (_) {
      /* Fall back to MTU 23. */
    }
    if (epoch != _epoch || _rx == null) {
      throw const GatewayFailure('disconnected');
    }
  }

  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) {
    final result = Completer<Map<String, dynamic>>();
    final epoch = _epoch;
    _tail = _tail.then((_) async {
      try {
        // Link already down: nothing is written, so report "not sent".
        if (epoch != _epoch || _rx == null) {
          throw const GatewayFailure('not_connected');
        }
        result.complete(await _send(op, params));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<Map<String, dynamic>> _send(
    String op,
    Map<String, dynamic> params,
  ) async {
    final id = 'app-$_session-${++_sequence}';
    final envelope = {
      'req_id': id,
      'op': op,
      'params': params,
      if (sensitiveOps.contains(op)) ...{
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'ttl': 30,
      },
    };
    final bytes = utf8.encode(jsonEncode(envelope));
    if (bytes.length > 512) throw const GatewayFailure('frame_size');
    final ack = Completer<Map<String, dynamic>>();
    _pending[id] = ack;
    // Attach the error handler before writing, as disconnect may arrive during write.
    final response = ack.future.timeout(commandTimeout(op, params));
    unawaited(response.catchError((Object e) => <String, dynamic>{}));
    try {
      final size = max(1, _mtu - 3);
      for (int offset = 0; offset < bytes.length; offset += size) {
        final rx = _rx;
        if (rx == null) {
          throw offset == 0
              ? const GatewayFailure('not_connected')
              : const GatewayFailure('disconnected');
        }
        await UniversalBle.write(
          _device!,
          nusService,
          rx,
          Uint8List.fromList(
            bytes.sublist(offset, min(offset + size, bytes.length)),
          ),
          timeout: commandTimeout(op, params),
          withoutResponse: false,
        ).timeout(commandTimeout(op, params));
        if (size <= 20) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }
      final frame = await response;
      if (frame['status'] != 'ok') {
        throw GatewayFailure.gateway(frame['result']?.toString() ?? '');
      }
      dynamic payload = frame['result'];
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } on FormatException {
          return {'message': payload};
        }
      }
      return payload is Map
          ? Map<String, dynamic>.from(payload)
          : {'value': payload};
    } on TimeoutException {
      throw const GatewayFailure('timeout');
    } finally {
      _pending.remove(id);
      _frames.clear();
    }
  }

  @override
  Future<void> disconnect() async {
    _epoch++;
    _mtu = 23;
    _rx = null;
    _frames.clear();
    for (final p in _pending.values) {
      if (!p.isCompleted) p.completeError(const GatewayFailure('disconnected'));
    }
    _pending.clear();
    await _notify?.cancel();
    await _connection?.cancel();
    _notify = null;
    _connection = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await UniversalBle.disconnect(
          device,
          timeout: const Duration(seconds: 5),
        );
      } catch (_) {}
    }
  }
}
