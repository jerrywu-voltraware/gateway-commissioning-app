import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/protocol.dart';
import 'contracts.dart';

Object normalizeBleError(Object error) {
  if (error is UniversalBleException &&
      error.code == UniversalBleErrorCode.deviceDisconnected) {
    return const GatewayFailure('disconnected');
  }
  if (error is UniversalBleException) {
    var text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 160) text = '${text.substring(0, 160)}…';
    // Prefer the GATT status (e.g. 133) as the first number in the detail.
    final gatt = text.contains('133') ? '133 ' : '';
    return GatewayFailure('ble_error', detail: '$gatt$text');
  }
  return error;
}

class BleGatewayLink
    implements
        GatewayLink,
        GatewaySignalSource,
        GatewayScanner,
        BluetoothReadiness,
        ConnectDiagnostics {
  StreamSubscription<AvailabilityState>? _availability;

  /// Starts tracking when the adapter turns on (lazily: needs the plugin).
  void _watchAdapter() {
    if (_availability != null) return;
    try {
      _availability = UniversalBle.availabilityStream.listen((value) {
        if (value == AvailabilityState.poweredOn &&
            _adapter != null &&
            _adapter != AvailabilityState.poweredOn) {
          _poweredOnAt = DateTime.now();
        }
        _adapter = value;
      }, onError: (_) {});
    } catch (_) {
      /* No plugin (tests): only the current state is checked. */
    }
  }

  AvailabilityState? _adapter;
  DateTime? _poweredOnAt;

  /// A just-enabled Android BLE stack still refuses connections (seen as
  /// "Failed to connect" right after Bluetooth came back on).
  static const adapterSettle = Duration(seconds: 3);

  @override
  Future<bool> adapterSettling() async {
    _watchAdapter();
    final AvailabilityState now;
    try {
      now = await UniversalBle.getBluetoothAvailabilityState();
    } catch (_) {
      return false;
    }
    if (now != AvailabilityState.poweredOn) return true;
    final since = _poweredOnAt;
    return since != null && DateTime.now().difference(since) < adapterSettle;
  }

  @override
  Future<void> waitAdapterReady(Duration max) async {
    final end = DateTime.now().add(max);
    while (DateTime.now().isBefore(end) && await adapterSettling()) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Completer<void>? _scanStop;
  Future<void>? _scanFinished;

  @override
  Future<void> stopScan() async {
    final stop = _scanStop;
    if (stop != null && !stop.isCompleted) stop.complete();
    await _scanFinished;
  }

  @override
  Stream<List<GatewayPeer>> scanLive() {
    final output = StreamController<List<GatewayPeer>>();
    final stop = Completer<void>();
    Future<void>? finished;
    output.onListen = () {
      final previousStop = _scanStop;
      final previousFinished = _scanFinished;
      if (previousStop != null && !previousStop.isCompleted) {
        previousStop.complete();
      }
      _scanStop = stop;
      finished = _scanFinished = () async {
        StreamSubscription<BleDevice>? sub;
        Timer? expiry;
        var started = false;
        try {
          await previousFinished;
          if (stop.isCompleted) return;
          await disconnect();
          await prepare();
          if (stop.isCompleted) return;
          final found = <String, GatewayPeer>{};
          final lastSeen = <String, DateTime>{};
          expiry = Timer.periodic(const Duration(seconds: 1), (_) {
            final now = DateTime.now();
            final expired = lastSeen.keys
                .where(
                  (id) =>
                      now.difference(lastSeen[id]!) >=
                      const Duration(seconds: 10),
                )
                .toList();
            for (final id in expired) {
              found.remove(id);
              lastSeen.remove(id);
            }
            if (expired.isNotEmpty && !stop.isCompleted) {
              output.add(found.values.toList());
            }
          });
          sub = UniversalBle.scanStream.listen(
            (result) {
              final name = result.name ?? '';
              if (!name.startsWith('GIOS-S') || stop.isCompleted) return;
              lastSeen[result.deviceId] = DateTime.now();
              found[result.deviceId] = GatewayPeer(
                result.deviceId,
                name,
                result.rssi ?? -127,
              );
              output.add(
                found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)),
              );
            },
            onError: (Object error, StackTrace stack) {
              output.addError(error, stack);
              if (!stop.isCompleted) stop.complete();
            },
          );
          started = true;
          await UniversalBle.startScan();
          await stop.future;
        } catch (error, stack) {
          output.addError(error, stack);
        } finally {
          expiry?.cancel();
          try {
            if (started) await UniversalBle.stopScan();
          } catch (error, stack) {
            output.addError(error, stack);
          }
          await sub?.cancel();
          if (identical(_scanStop, stop)) _scanStop = null;
          unawaited(output.close());
        }
      }();
    };
    output.onCancel = () async {
      if (!stop.isCompleted) stop.complete();
      await finished;
    };
    return output.stream;
  }

  final _signalConnections = StreamController<bool>.broadcast();
  @override
  Stream<bool> get signalConnections => _signalConnections.stream;
  @override
  bool get signalConnected => _rx != null && _device != null;

  @override
  Future<int> readSignal() {
    final result = Completer<int>();
    final epoch = _epoch;
    _tail = _tail.then((_) async {
      try {
        if (epoch != _epoch || !signalConnected) {
          throw const GatewayFailure('not_connected');
        }
        final value = await UniversalBle.readRssi(
          _device!,
          timeout: const Duration(seconds: 3),
        );
        if (epoch != _epoch || !signalConnected) {
          throw const GatewayFailure('disconnected');
        }
        result.complete(value);
      } catch (error, stack) {
        result.completeError(normalizeBleError(error), stack);
      }
    });
    return result.future;
  }

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
    _watchAdapter();
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = sdk >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    final result = await permissions.request();
    if (result.values.any((p) => !p.isGranted)) {
      throw const GatewayFailure('permission');
    }
    if (sdk < 31 &&
        !await Permission.locationWhenInUse.serviceStatus.isEnabled) {
      throw const GatewayFailure('location_off');
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
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    await disconnect();
    final epoch = _epoch;
    try {
      await _connectPeer(peer, epoch, onStage);
    } catch (error) {
      if (epoch == _epoch) await disconnect();
      throw normalizeBleError(error);
    }
  }

  // ---- Retry/timeout budget ----
  // Worst case (all attempts fail): connectTimeout * (connectRetries + 1)
  // + quickRetryTimeout + (retryGap + rescanWindow) * connectRetries
  //   = 12s * 3 + 6s + 4.5s * 2 = 51s.
  // The callers budget above this with headroom for the outer machinery:
  // commissioning_controller._relink times out at 56s and the overall
  // commissioning_controller.reconnectBudget (used by _reconnect) is 66s.
  // Keep all three numbers in sync when tuning retry behaviour.
  /// Connect retries after the first attempt (interval [retryGap]).
  static const connectRetries = 2;
  @visibleForTesting
  static Duration connectTimeout = const Duration(seconds: 12);
  @visibleForTesting
  static Duration staleSettle = const Duration(milliseconds: 500);
  @visibleForTesting
  static Duration retryGap = const Duration(milliseconds: 1500);
  @visibleForTesting
  static Duration rescanWindow = const Duration(seconds: 3);

  /// Timeout of the immediate retry after the first failed connect.
  @visibleForTesting
  static Duration quickRetryTimeout = const Duration(seconds: 6);

  String? _firstConnectFailure;

  /// `Type: message` of the latest connect's first failure (null when the
  /// first attempt succeeded).
  @override
  String? get firstConnectFailure => _firstConnectFailure;

  /// Disconnects a leftover GATT client for [device] (errors ignored), then
  /// gives the stack [staleSettle] to release it.
  Future<void> _dropStale(String device) async {
    try {
      await UniversalBle.disconnect(
        device,
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {}
    await Future<void>.delayed(staleSettle);
  }

  /// Scans up to [rescanWindow] until [device] is advertised again, so the
  /// Android stack knows the address before the next connect.
  Future<void> _rediscover(String device) async {
    final seen = Completer<void>();
    StreamSubscription<BleDevice>? sub;
    try {
      sub = UniversalBle.scanStream.listen((result) {
        if (result.deviceId == device && !seen.isCompleted) seen.complete();
      }, onError: (_) {});
      await UniversalBle.startScan();
      await seen.future.timeout(rescanWindow, onTimeout: () {});
    } catch (_) {
      /* Scan unavailable: just try the connect again. */
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      await sub?.cancel();
    }
  }

  Future<void> _connectPeer(
    GatewayPeer peer,
    int epoch, [
    void Function(String stage)? onStage,
  ]) async {
    final device = peer.id;
    _device = device;
    // After the phone's Bluetooth was turned off and on, Android keeps a
    // stale GATT client for this address and forgets it from its scan
    // cache: a bare connect then fails with "Failed to connect" until the
    // APP restarts (round 6). Drop any stale client first, and before each
    // retry re-find the gateway with a short scan.
    onStage?.call('清除舊連線');
    await _dropStale(device);
    _firstConnectFailure = null;
    for (int attempt = 0; ; attempt++) {
      if (epoch != _epoch) throw const GatewayFailure('cancelled');
      if (attempt > 0) onStage?.call('第 $attempt 次重試');
      onStage?.call('正在連線閘道器');
      try {
        await UniversalBle.connect(device, timeout: connectTimeout);
        break;
      } catch (error) {
        if (attempt == 0) {
          // Round 8: the first reconnect sometimes fails once and the next
          // try works; retry at once (no gap/rescan) and keep the type.
          _firstConnectFailure = '${error.runtimeType}: $error';
          debugPrint('BLE first connect failed: $_firstConnectFailure');
          if (epoch != _epoch) throw const GatewayFailure('cancelled');
          try {
            await UniversalBle.connect(device, timeout: quickRetryTimeout);
            break;
          } catch (_) {}
        }
        if (attempt >= connectRetries) rethrow;
        onStage?.call('找不到閘道器，重新掃描中');
        await _dropStale(device);
        await Future<void>.delayed(retryGap);
        if (epoch != _epoch) throw const GatewayFailure('cancelled');
        await _rediscover(device);
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
        _signalConnections.add(false);
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
    _signalConnections.add(true);
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
        result.completeError(normalizeBleError(error), stack);
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
        throw gatewayAckFailure(frame['result']);
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
    _signalConnections.add(false);
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
