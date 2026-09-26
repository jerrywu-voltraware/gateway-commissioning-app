class GatewayPeer {
  const GatewayPeer(this.id, this.name, this.rssi);
  final String id, name;
  final int rssi;
}

abstract class GatewayLink {
  bool get demo;
  Future<void> prepare();
  Future<List<GatewayPeer>> scan();

  /// [onStage] (optional) reports human-readable progress as the link is
  /// (re)established, e.g. for a reconnect banner: "清除舊連線" →
  /// "正在連線閘道器" → (on a failed attempt) "找不到閘道器，重新掃描中" →
  /// "第 n 次重試" → "正在連線閘道器" ...
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  });
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]);
  Future<void> disconnect();
}

/// Optional: the phone's Bluetooth adapter state, so a reconnect right after
/// Bluetooth was turned back on waits until the adapter is usable.
abstract class BluetoothReadiness {
  /// True when the adapter is not on, or turned on less than 3 s ago.
  Future<bool> adapterSettling();

  /// Waits (at most [max]) until the adapter is on and settled.
  Future<void> waitAdapterReady(Duration max);
}

/// Optional (round 19): acks the gateway sends over BLE that answer no
/// request of this APP — the gateway relays every ACK to a connected phone,
/// including those of commands the back office sent over MQTT (e.g. a
/// remote identify). Each is the frame's parsed `result` (a map) with
/// `req_id` / `status` added.
abstract class ForeignAcks {
  Stream<Map<String, dynamic>> get foreignAcks;
}

/// Optional connect diagnostics: the exception of the latest connect's
/// first failed attempt (round 8: the first reconnect sometimes fails).
abstract class ConnectDiagnostics {
  String? get firstConnectFailure;
}

/// Optional live scanning; callers await stopScan before connecting.
abstract class GatewayScanner {
  Stream<List<GatewayPeer>> scanLive();
  Future<void> stopScan();
}

/// Signal measured by the phone, independent of Gateway-to-PTU telemetry.
abstract class GatewaySignalSource {
  bool get signalConnected;
  Stream<bool> get signalConnections;
  Future<int> readSignal();
}

/// Optional (round 17): a backend session that survives an APP restart —
/// the token the last login returned (never the password) and when this
/// APP stops using it.
abstract class SessionStore {
  /// Uses the stored, unexpired session of [base]; true when one was
  /// loaded (requests are then authenticated without a login).
  Future<bool> restoreSession(String base);
}

/// Optional (field rescue v1): whether the API holds a login right now and
/// for which backend — the field reporter queues its uploads instead of
/// sending them without one (it never asks for the password itself).
abstract class SessionInfo {
  bool get hasSession;

  /// `scheme://host:port` of the logged-in backend, or null.
  String? get origin;
}

abstract class GatewayApi {
  Future<void> login(String base, String password);
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]);
}
