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
