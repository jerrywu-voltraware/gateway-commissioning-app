import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/protocol.dart';
import 'contracts.dart';

class BleGatewayLink implements GatewayLink {
  @override
  bool get demo => false;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _notify;
  StreamSubscription<BluetoothConnectionState>? _connection;
  final _frames = JsonFrames();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Future<void> _tail = Future.value();
  int _epoch = 0, _sequence = 0;
  final String _session = Random.secure().nextInt(0x7fffffff).toRadixString(16);

  @override
  Future<void> prepare() async {
    if (!const bool.fromEnvironment('FBP_COMMERCIAL_LICENSED')) {
      throw const GatewayFailure('license');
    }
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = sdk >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    final result = await permissions.request();
    if (result.values.any((p) => !p.isGranted)) {
      throw const GatewayFailure('permission');
    }
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn().timeout(const Duration(seconds: 15));
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
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : result.device.platformName;
        if (name.startsWith('GIOS-S')) {
          found[result.device.remoteId.str] = GatewayPeer(
            result.device.remoteId.str,
            name,
            result.rssi,
          );
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(seconds: 15));
    } finally {
      await FlutterBluePlus.stopScan();
      await sub.cancel();
    }
    return found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  @override
  Future<void> connect(GatewayPeer peer) async {
    if (!const bool.fromEnvironment('FBP_COMMERCIAL_LICENSED')) {
      throw const GatewayFailure('license');
    }
    await disconnect();
    final epoch = _epoch;
    final device = BluetoothDevice.fromId(peer.id);
    _device = device;
    for (int attempt = 0; ; attempt++) {
      if (epoch != _epoch) throw const GatewayFailure('cancelled');
      try {
        await device.connect(
          license: License.commercial,
          timeout: const Duration(seconds: 15),
          mtu: null,
        );
        break;
      } catch (error) {
        if (attempt >= 2 || !error.toString().contains('133')) rethrow;
        await device.disconnect();
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    if (epoch != _epoch) throw const GatewayFailure('cancelled');
    final services = await device.discoverServices().timeout(
      const Duration(seconds: 12),
    );
    if (epoch != _epoch) throw const GatewayFailure('cancelled');
    final service = services.where((s) => s.uuid == Guid(nusService)).first;
    _rx = service.characteristics.where((c) => c.uuid == Guid(nusRx)).first;
    final tx = service.characteristics
        .where((c) => c.uuid == Guid(nusTx))
        .first;
    _notify = tx.onValueReceived.listen((bytes) {
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
    await tx.setNotifyValue(true).timeout(const Duration(seconds: 12));
    if (epoch != _epoch) throw const GatewayFailure('cancelled');
    try {
      await device.requestMtu(247);
    } catch (_) {
      /* Fall back to MTU 23. */
    }
    _connection = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
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
        if (epoch != _epoch || _rx == null) {
          throw const GatewayFailure('disconnected');
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
      final size = max(1, (_device?.mtuNow ?? 23) - 3);
      for (int offset = 0; offset < bytes.length; offset += size) {
        final rx = _rx;
        if (rx == null) throw const GatewayFailure('disconnected');
        await rx
            .write(
              bytes.sublist(offset, min(offset + size, bytes.length)),
              withoutResponse: false,
            )
            .timeout(commandTimeout(op, params));
        if (size <= 20) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }
      final frame = await response;
      if (frame['status'] != 'ok') {
        throw GatewayFailure(frame['result']?.toString() ?? 'failed');
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
        await device.disconnect();
      } catch (_) {}
    }
  }
}
