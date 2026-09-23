import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/local_backend_address.dart';
import '../core/protocol.dart';
import 'dashboard_api.dart';

enum ProbeOutcome {
  healthy,
  degraded,
  notBackend,
  httpError,
  unreachable,
  timeout,
}

class ProbeResult {
  const ProbeResult(this.outcome, {this.status, this.version, this.detail});
  final ProbeOutcome outcome;
  final int? status;
  final String? version, detail;

  /// Looks like our dashboard-api (even if its database is not ready).
  bool get isBackend =>
      outcome == ProbeOutcome.healthy || outcome == ProbeOutcome.degraded;
  @override
  String toString() => 'ProbeResult($outcome, $status, $version, $detail)';
}

/// Matches the dashboard-api `/healthz` contract (served through the local
/// nginx proxy on :18000 → dashboard-frontend → dashboard-api):
///   200 `{"ok": true,  "version": "1.1.0", "ingest": {...}|null}`
///   503 `{"ok": false, "version": "1.1.0", "reason": "database_unavailable"}`
/// Anything else — including the SPA's `index.html` fallback with HTTP 200 —
/// is not our backend.
ProbeResult classifyHealthz(int status, String body) {
  Object? data;
  try {
    data = jsonDecode(body);
  } catch (_) {
    data = null;
  }
  if (data is Map && data['ok'] is bool && data['version'] is String) {
    final version = data['version'] as String;
    if (status == 200 && data['ok'] == true) {
      return ProbeResult(
        ProbeOutcome.healthy,
        status: status,
        version: version,
      );
    }
    if (status == 503 && data['ok'] == false) {
      return ProbeResult(
        ProbeOutcome.degraded,
        status: status,
        version: version,
        detail: data['reason']?.toString(),
      );
    }
  }
  if (status >= 200 && status < 300) {
    return ProbeResult(ProbeOutcome.notBackend, status: status);
  }
  return ProbeResult(ProbeOutcome.httpError, status: status);
}

/// Probes `GET <base>/healthz`. Implementations must never send credentials.
abstract class LocalBackendProber {
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout});
}

class HttpLocalBackendProber implements LocalBackendProber {
  const HttpLocalBackendProber({
    this.connectTimeout = const Duration(seconds: 3),
    this.responseTimeout = const Duration(seconds: 3),
  });
  final Duration connectTimeout, responseTimeout;

  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async {
    final connect = connectTimeout ?? this.connectTimeout;
    final client = HttpClient()
      ..connectionTimeout = connect
      ..findProxy = ((_) => 'DIRECT')
      ..userAgent = 'gateway-commissioning';
    try {
      final req = await client
          .getUrl(base.resolve('/healthz'))
          .timeout(connect + const Duration(milliseconds: 300));
      req.followRedirects = false;
      req.persistentConnection = false;
      final res = await req.close().timeout(responseTimeout);
      final body = await _readLimited(res).timeout(responseTimeout);
      return classifyHealthz(res.statusCode, body);
    } on TimeoutException {
      return const ProbeResult(ProbeOutcome.timeout, detail: '逾時');
    } on SocketException catch (error) {
      if (error.message.contains('timed out')) {
        return const ProbeResult(ProbeOutcome.timeout, detail: '逾時');
      }
      return ProbeResult(
        ProbeOutcome.unreachable,
        detail: networkErrorText(error),
      );
    } on IOException catch (error) {
      return ProbeResult(
        ProbeOutcome.unreachable,
        detail: networkErrorText(error),
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _readLimited(HttpClientResponse res) async {
    final bytes = <int>[];
    await for (final chunk in res) {
      bytes.addAll(chunk);
      if (bytes.length > 4096) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// The phone's current Wi-Fi IPv4, or null when it has none.
Future<String?> phoneWifiIpv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return pickWifiIpv4([
      for (final i in interfaces)
        for (final a in i.addresses) (i.name, a.address),
    ]);
  } catch (_) {
    return null;
  }
}

const localBackendHint =
    '請確認：手機與電腦在同一個 Wi-Fi、電腦已啟動 Docker 本地後端、'
    '電腦防火牆已執行 allow_local_api_lan.ps1。';

/// User-facing result of 「測試連線」.
String connectionTestMessage(ProbeResult result, Uri base) {
  final backend = describeBackend(base);
  const endpoint = 'GET /healthz';
  return switch (result.outcome) {
    ProbeOutcome.healthy =>
      '✓ 已連上本地後端'
          '${result.version == null ? '' : '（版本 ${result.version}）'}',
    ProbeOutcome.degraded =>
      '✗ 已連到本地後端，但資料庫尚未就緒（HTTP 503）。請等 Docker 本地後端完全啟動後重試。',
    ProbeOutcome.notBackend =>
      '✗ 回應不是本地後端（HTTP ${result.status}）。這個 IP／連接埠上是其他服務，請確認電腦 IP。',
    ProbeOutcome.httpError =>
      '✗ 回應不是本地後端（HTTP ${result.status}）。請確認電腦 IP 與連接埠。',
    ProbeOutcome.timeout =>
      '✗ 逾時：${GatewayFailure.network(endpoint: endpoint, detail: '逾時', backend: backend).message}',
    ProbeOutcome.unreachable =>
      '✗ 無法連線：${GatewayFailure.network(endpoint: endpoint, detail: result.detail, backend: backend).message}',
  };
}
