class GatewayPeer {
  const GatewayPeer(this.id, this.name, this.rssi);
  final String id, name;
  final int rssi;
}

abstract class GatewayLink {
  bool get demo;
  Future<void> prepare();
  Future<List<GatewayPeer>> scan();
  Future<void> connect(GatewayPeer peer);
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

abstract class GatewayApi {
  Future<void> login(String base, String password);
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]);
}
