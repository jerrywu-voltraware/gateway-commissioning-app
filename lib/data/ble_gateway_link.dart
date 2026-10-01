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

/// Round 19: an ack frame no pending request took, as [ForeignAcks]
/// passes it on — its parsed `result` with `req_id` / `status` — or null
/// when it is not foreign: no string req_id, or one starting with
/// [ownPrefix] (this link's own requests, e.g. a late ack after a
/// timeout).
Map<String, dynamic>? foreignAckOf(
  Map<String, dynamic> frame,
  String ownPrefix,
) {
  final id = frame['req_id'];
  if (id is! String || id.startsWith(ownPrefix)) return null;
  var payload = frame['result'];
  if (payload is String) {
    try {
      payload = jsonDecode(payload);
    } on FormatException {
      payload = {'message': payload};
    }
  }
  return {
    if (payload is Map) ...Map<String, dynamic>.from(payload),
    'req_id': id,
    'status': frame['status'],
  };
}

class BleGatewayLink
    implements
        GatewayLink,
        GatewaySignalSource,
        GatewayScanner,
        BluetoothReadiness,
        ConnectDiagnostics,
        ForeignAcks {
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
  Future<void>? _pendingNativeScanStop;
  bool _scanNeedsStop = false;

  @override
  Future<void> stopScan() async {
    final stop = _scanStop;
    if (stop != null && !stop.isCompleted) stop.complete();
    await _scanFinished;
  }

  @override
  Stream<List<GatewayPeer>> scanLive() => _scanLive(releaseConnection: true);

  /// Status-page scanning shares the adapter owner, without releasing a
  /// legitimate held connection. The reservation is made on listen.
  Stream<List<GatewayPeer>> scanNearbyLive({
    Future<void>? stopWhen,
    void Function(Object, StackTrace)? onCleanupError,
  }) => _scanLive(
    releaseConnection: false,
    stopWhen: stopWhen,
    onCleanupError: onCleanupError,
  );

  Stream<List<GatewayPeer>> _scanLive({
    required bool releaseConnection,
    Future<void>? stopWhen,
    void Function(Object, StackTrace)? onCleanupError,
  }) {
    final output = StreamController<List<GatewayPeer>>();
    final stop = Completer<void>();
    if (stopWhen != null) {
      unawaited(
        stopWhen.then(
          (_) {
            if (!stop.isCompleted) stop.complete();
          },
          onError: (Object _, StackTrace _) {
            if (!stop.isCompleted) stop.complete();
          },
        ),
      );
    }
    Future<void>? finished;
    output.onListen = () {
      if (!releaseConnection &&
          (_device != null ||
              _lifecycle != null ||
              _disconnecting != null ||
              _cleanupFailed)) {
        output.addError(
          GatewayFailure(_cleanupFailed ? 'cleanup_failed' : 'busy'),
        );
        unawaited(output.close());
        return;
      }
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
          if (releaseConnection) {
            await disconnect();
          } else if (_cleanupFailed) {
            // The preceding scan may have failed while this owner waited.
            throw const GatewayFailure('cleanup_failed');
          }
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
          _scanNeedsStop = true;
          await UniversalBle.startScan();
          await stop.future;
        } catch (error, stack) {
          output.addError(error, stack);
        } finally {
          expiry?.cancel();
          try {
            if (started) await _stopNativeScan();
          } catch (error, stack) {
            // Subscription cancellation suppresses stream events; the owning
            // nearby request must still receive its cleanup failure.
            onCleanupError?.call(error, stack);
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

  Future<void> _stopNativeScan() async {
    try {
      final pending = _pendingNativeScanStop;
      if (pending != null) await pending.timeout(nativeCleanupTimeout);
      final native = UniversalBle.stopScan();
      _pendingNativeScanStop = native;
      void finished() {
        if (identical(_pendingNativeScanStop, native)) {
          _pendingNativeScanStop = null;
        }
      }

      unawaited(
        native.then(
          (_) => finished(),
          onError: (Object _, StackTrace _) => finished(),
        ),
      );
      await native.timeout(nativeCleanupTimeout);
      _scanNeedsStop = false;
    } catch (_) {
      // Keep stopScan's existing stream-error contract; connect remains
      // blocked until explicit disconnect retries the native scan cleanup.
      _cleanupFailed = true;
      throw const GatewayFailure('cleanup_failed');
    }
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
  final _foreign = StreamController<Map<String, dynamic>>.broadcast();

  /// Round 19: the ack of a command this APP did not send (its req_id is
  /// not one of this link's `app-<session>-n`): the back office's, relayed
  /// by the gateway. Late acks of this APP's own timed-out commands are not.
  @override
  Stream<Map<String, dynamic>> get foreignAcks => _foreign.stream;

  void _foreignAck(Map<String, dynamic> frame) {
    final ack = foreignAckOf(frame, 'app-$_session-');
    if (ack != null) _foreign.add(ack);
  }

  Future<void> _tail = Future.value();
  Future<void>? _lifecycle;
  Future<void>? _disconnecting;
  bool _cleanupFailed = false;
  Future<void>? _pendingNativeCleanup;

  void _checkEpoch(int epoch) {
    if (epoch != _epoch) throw const GatewayFailure('cancelled');
  }

  void _invalidate() {
    _epoch++;
    _rx = null;
    _signalConnections.add(false);
    _frames.clear();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const GatewayFailure('disconnected'));
      }
    }
    _pending.clear();
  }

  int _epoch = 0, _sequence = 0;
  final String _session = Random.secure().nextInt(0x7fffffff).toRadixString(16);

  @override
  Future<void> prepare() async {
    _watchAdapter();
    final androidSdk = defaultTargetPlatform == TargetPlatform.android
        ? (await DeviceInfoPlugin().androidInfo).version.sdkInt
        : null;
    final permissions = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        androidSdk! >= 31
            ? [Permission.bluetoothScan, Permission.bluetoothConnect]
            : [Permission.locationWhenInUse],
      TargetPlatform.iOS => [Permission.bluetooth],
      _ => const <Permission>[],
    };
    final result = await permissions.request();
    if (result.values.any((p) => !p.isGranted)) {
      throw const GatewayFailure('permission');
    }
    if (androidSdk != null &&
        androidSdk < 31 &&
        !await Permission.locationWhenInUse.serviceStatus.isEnabled) {
      throw const GatewayFailure('location_off');
    }
    // Round 12: never switch the phone Bluetooth (the old enable call
    // fired the system enable-request intent and could race a disable
    // request). Bluetooth off is reported; the user turns it on.
    if (await UniversalBle.getBluetoothAvailabilityState() !=
        AvailabilityState.poweredOn) {
      throw const GatewayFailure('bluetooth_off');
    }
  }

  @override
  Future<List<GatewayPeer>> scan() async {
    // The legacy snapshot API shares the live scan's adapter reservation,
    // stop signal and cleanup barrier. It cannot race a new connect.
    final found = <String, GatewayPeer>{};
    final completed = Completer<void>();
    final sub = scanLive().listen(
      (peers) {
        for (final peer in peers) {
          found[peer.id] = peer;
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      },
      onDone: () {
        if (!completed.isCompleted) completed.complete();
      },
    );
    try {
      await completed.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } finally {
      await sub.cancel();
    }
    return found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) {
    // No queued replacements: finish/cancel one lifecycle first, including
    // two successive sessions to the same address.
    if (_lifecycle != null || _disconnecting != null || _scanStop != null) {
      return Future.error(const GatewayFailure('busy'));
    }
    if (_cleanupFailed) {
      return Future.error(const GatewayFailure('cleanup_failed'));
    }
    _invalidate();
    final run = _connectExclusive(peer, _epoch, onStage);
    _lifecycle = run;
    void finished() {
      if (identical(_lifecycle, run)) _lifecycle = null;
    }

    unawaited(
      run.then(
        (_) => finished(),
        onError: (Object _, StackTrace _) {
          finished();
        },
      ),
    );
    return run;
  }

  Future<void> _connectExclusive(
    GatewayPeer peer,
    int epoch,
    void Function(String stage)? onStage,
  ) async {
    try {
      await _cleanSession();
      _checkEpoch(epoch);
      await _connectPeer(peer, epoch, onStage);
      _checkEpoch(epoch);
    } catch (error) {
      // No newer session can start before this cleanup has finished.
      await _cleanSession();
      if (epoch != _epoch) throw const GatewayFailure('cancelled');
      throw normalizeBleError(error);
    }
  }

  // ---- Retry/timeout budget ----
  // A connect-only failure path has four attempts (three normal and one
  // quick), three rediscovery windows and five stale cleanup guards,
  // including terminal cleanup: 42 + 9 + 1.5 + 8 = 60.5 seconds.
  // Native disconnect/state-query latency and GATT setup are additional.
  // A caller's timeout cancels its wait, not native work: it must await
  // disconnect() before allowing another connection.
  /// Connect retries after the first attempt (interval [retryGap]).
  static const connectRetries = 2;
  @visibleForTesting
  static Duration connectTimeout = const Duration(seconds: 12);
  @visibleForTesting
  // Android universal_ble 2.3.0 can acknowledge disconnect before its
  // 1500 ms no-callback close fallback. A bounded guard, not an Android
  // close-completion signal; the disconnected state must also be checked.
  static Duration staleSettle = const Duration(milliseconds: 1600);
  @visibleForTesting
  static Duration retryGap = const Duration(milliseconds: 1500);
  @visibleForTesting
  static Duration rescanWindow = const Duration(seconds: 3);

  /// Timeout of the immediate retry after the first failed connect.
  @visibleForTesting
  static Duration quickRetryTimeout = const Duration(seconds: 6);

  /// Shorter than the plugin timeout because universal_ble swallows its own
  /// disconnect timeout. Expiry here remains an observable cleanup failure.
  @visibleForTesting
  static Duration nativeCleanupTimeout = const Duration(seconds: 5);

  /// Retry wait budget, excluding native cleanup latency and GATT setup.
  /// Includes the initial, immediate, two normal and terminal stale guards.
  static Duration get failedConnectWaitBudget =>
      connectTimeout * (connectRetries + 1) +
      quickRetryTimeout +
      (retryGap + rescanWindow) * connectRetries +
      quickRescanWindow +
      staleSettle * (connectRetries + 3);

  /// Short scan before the immediate retry (half of [rescanWindow]).
  static Duration get quickRescanWindow => rescanWindow ~/ 2;

  String? _firstConnectFailure;

  /// `Type: message` of the latest connect's first failure (null when the
  /// first attempt succeeded).
  @override
  String? get firstConnectFailure => _firstConnectFailure;

  /// Disconnect and wait past Android's no-callback close fallback. A
  /// timeout or non-disconnected state quarantines this address for retry.
  Future<void> _dropStale(String device) async {
    try {
      final previous = _pendingNativeCleanup;
      if (previous != null) await previous.timeout(nativeCleanupTimeout);
      final native = UniversalBle.disconnect(
        device,
        timeout: nativeCleanupTimeout + const Duration(seconds: 2),
      );
      _pendingNativeCleanup = native;
      void finished() {
        if (identical(_pendingNativeCleanup, native)) {
          _pendingNativeCleanup = null;
        }
      }

      unawaited(
        native.then(
          (_) => finished(),
          onError: (Object _, StackTrace _) => finished(),
        ),
      );
      await native.timeout(nativeCleanupTimeout);
      await Future<void>.delayed(staleSettle);
      final state = await UniversalBle.getConnectionState(
        device,
      ).timeout(const Duration(seconds: 3));
      if (state != BleConnectionState.disconnected) {
        throw const GatewayFailure('cleanup_failed');
      }
    } catch (_) {
      _cleanupFailed = true;
      throw const GatewayFailure('cleanup_failed');
    }
  }

  /// Scans up to [rescanWindow] until [device] is advertised again, so the
  /// Android stack knows the address before the next connect.
  Future<void> _rediscover(String device, [Duration? window]) async {
    final seen = Completer<void>();
    StreamSubscription<BleDevice>? sub;
    try {
      sub = UniversalBle.scanStream.listen((result) {
        if (result.deviceId == device && !seen.isCompleted) seen.complete();
      }, onError: (_) {});
      _scanNeedsStop = true;
      await UniversalBle.startScan();
      await seen.future.timeout(window ?? rescanWindow, onTimeout: () {});
    } catch (_) {
      /* Scan unavailable: just try the connect again. */
    } finally {
      try {
        await _stopNativeScan();
      } finally {
        await sub?.cancel();
      }
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
    var ready = false;
    for (int attempt = 0; ; attempt++) {
      if (epoch != _epoch) throw const GatewayFailure('cancelled');
      if (attempt > 0) onStage?.call('第 $attempt 次重試');
      onStage?.call('正在連線閘道器');
      try {
        await UniversalBle.connect(device, timeout: connectTimeout);
        // Round 9: the first attempt includes the GATT setup — a 133
        // (UniversalBleException unknownError) right after an APP restart
        // often surfaces in discoverServices/subscribe, not in connect.
        if (attempt == 0) {
          await _setUp(device, epoch);
          ready = true;
        }
        break;
      } catch (error) {
        _checkEpoch(epoch);
        if (error is GatewayFailure &&
            (error.code == 'cancelled' || error.code == 'cleanup_failed')) {
          rethrow;
        }
        if (attempt == 0) {
          // Round 8: the first reconnect sometimes fails once and the next
          // try works; retry at once and keep the type. Round 9: any error
          // type (133 unknownError included), and drop the half-open GATT
          // client + a short scan first, else the retry hits the same 133.
          _firstConnectFailure = '${error.runtimeType}: $error';
          debugPrint('BLE first connect failed: $_firstConnectFailure');
          await _tearDownSetup();
          if (epoch != _epoch) throw const GatewayFailure('cancelled');
          try {
            await _dropStale(device);
            await _rediscover(device, quickRescanWindow);
            if (epoch != _epoch) throw const GatewayFailure('cancelled');
            await UniversalBle.connect(device, timeout: quickRetryTimeout);
            await _setUp(device, epoch);
            ready = true;
            break;
          } catch (retryError) {
            if (retryError is GatewayFailure &&
                retryError.code == 'cancelled') {
              rethrow;
            }
            _checkEpoch(epoch);
            if (retryError is GatewayFailure &&
                retryError.code == 'cleanup_failed') {
              rethrow;
            }
            await _tearDownSetup();
          }
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
    if (!ready) await _setUp(device, epoch);
  }

  Future<void> _tearDownSetup() async {
    final notify = _notify;
    final connection = _connection;
    _notify = null;
    _connection = null;
    _rx = null;
    await notify?.cancel();
    await connection?.cancel();
  }

  /// GATT setup after a successful connect: NUS service, notifications,
  /// connection watch and MTU.
  Future<void> _setUp(String device, int epoch) async {
    _checkEpoch(epoch);
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
          if (pending != null && !pending.isCompleted) {
            pending.complete(frame);
          } else if (pending == null) {
            _foreignAck(frame);
          }
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
  Future<void> disconnect() {
    final pending = _disconnecting;
    if (pending != null) return pending;
    _invalidate();
    final active = _lifecycle;
    final run = () async {
      // A Dart cancellation does not cancel native work. Drain it before
      // cleanup; all new connects are rejected until both finish.
      try {
        await active;
      } catch (_) {
        // Active connect cleaned up, or retained a retryable cleanup error.
      }
      await _cleanSession();
    }();
    _disconnecting = run;
    void finished() {
      if (identical(_disconnecting, run)) _disconnecting = null;
    }

    unawaited(
      run.then(
        (_) => finished(),
        onError: (Object _, StackTrace _) {
          finished();
        },
      ),
    );
    return run;
  }

  Future<void> _cleanSession() async {
    // Capture ownership before yielding. A subsequent lifecycle cannot
    // adopt these resources until this method has completed.
    final device = _device;
    _mtu = 23;
    _rx = null;
    try {
      await _tearDownSetup();
      await _tail.timeout(const Duration(seconds: 15));
      if (_scanNeedsStop) await _stopNativeScan();
      if (device != null) await _dropStale(device);
      _device = null;
      _frames.clear();
      _cleanupFailed = false;
    } catch (_) {
      // Preserve the address for explicit disconnect retry; never open a
      // new physical session after an unconfirmed cleanup.
      _cleanupFailed = true;
      throw const GatewayFailure('cleanup_failed');
    }
  }
}
