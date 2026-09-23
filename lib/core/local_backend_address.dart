/// Pure helpers for the "本地測試站" backend address: the user types only the
/// PC's IPv4 address, the app composes `http://<ip>:<port>`.
library;

const defaultLocalPort = 18000;

/// Parses a dotted-quad IPv4 literal strictly (no leading zeros, 0–255).
List<int>? parseIpv4(String text) {
  final parts = text.split('.');
  if (parts.length != 4) return null;
  final bytes = <int>[];
  for (final part in parts) {
    if (part.isEmpty || part.length > 3 || !RegExp(r'^\d+$').hasMatch(part)) {
      return null;
    }
    if (part.length > 1 && part.startsWith('0')) return null;
    final value = int.parse(part);
    if (value > 255) return null;
    bytes.add(value);
  }
  return bytes;
}

/// RFC 1918 private ranges: 10/8, 172.16/12, 192.168/16.
bool isPrivateIpv4(String text) {
  final b = parseIpv4(text);
  if (b == null) return false;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

/// Inline validation message for the local backend IP field; null when valid.
///
/// Loopback is rejected on purpose: on the phone 127.0.0.1 is the phone
/// itself, and saved loopback URLs are migrated away on start-up anyway.
String? localHostError(String input) {
  final text = input.trim();
  if (text.isEmpty) return '請輸入電腦的 IP 位址';
  final b = parseIpv4(text);
  if (b == null) return '格式應為 4 組 0–255 的數字，例如 192.168.1.187';
  if (b[0] == 127) return '127.x 是手機本身，請輸入電腦在區域網路的 IP';
  if (!isPrivateIpv4(text)) {
    return '只接受區域網路位址（10.x、172.16–31.x、192.168.x）';
  }
  if (b[3] == 0 || b[3] == 255) return '最後一組不可為 0 或 255';
  return null;
}

String? localPortError(String input) {
  final port = int.tryParse(input.trim());
  if (port == null || port < 1 || port > 65535) return '連接埠需為 1–65535';
  return null;
}

String composeLocalUrl(String host, [int port = defaultLocalPort]) =>
    'http://${host.trim()}:$port';

class LocalEndpoint {
  const LocalEndpoint(this.host, this.port);
  final String host;
  final int port;
  String get url => composeLocalUrl(host, port);
  @override
  bool operator ==(Object other) =>
      other is LocalEndpoint && other.host == host && other.port == port;
  @override
  int get hashCode => Object.hash(host, port);
  @override
  String toString() => url;
}

/// Splits a saved local URL (`http://192.168.0.12:18000`) into host + port.
/// Returns null when the URL is not an http URL with a host; a non-IPv4 host
/// is still returned so the field can show it with a validation error.
LocalEndpoint? parseLocalUrl(String? url) {
  final uri = Uri.tryParse((url ?? '').trim());
  if (uri == null || uri.scheme != 'http' || uri.host.isEmpty) return null;
  return LocalEndpoint(uri.host, uri.hasPort ? uri.port : 80);
}

/// All hosts of [ownIp]'s /24 except network, broadcast and the phone itself.
List<String> subnetHosts(String ownIp) {
  final b = parseIpv4(ownIp);
  if (b == null) return const [];
  final prefix = '${b[0]}.${b[1]}.${b[2]}';
  return [
    for (var i = 1; i <= 254; i++)
      if (i != b[3]) '$prefix.$i',
  ];
}

final _cellular = RegExp(r'rmnet|ccmni|pdp|radio|ppp|tun|clat|dummy|usb|rndis');

/// Picks the phone's Wi-Fi IPv4 from `(interfaceName, address)` pairs:
/// private addresses on `wlan*` first, then any non-cellular private address.
String? pickWifiIpv4(List<(String, String)> candidates) {
  final private = [
    for (final c in candidates)
      if (isPrivateIpv4(c.$2)) c,
  ];
  for (final c in private) {
    if (c.$1.toLowerCase().startsWith('wlan')) return c.$2;
  }
  for (final c in private) {
    if (!_cellular.hasMatch(c.$1.toLowerCase())) return c.$2;
  }
  return null;
}
