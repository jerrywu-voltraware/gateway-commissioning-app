import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/local_backend_address.dart';
import '../core/protocol.dart';
import '../l10n/l10n.dart';
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
      // A code, not words (the message is built by [connectionTestMessage]).
      return const ProbeResult(
        ProbeOutcome.timeout,
        detail: networkTimeoutDetail,
      );
    } on SocketException catch (error) {
      if (error.message.contains('timed out')) {
        return const ProbeResult(
          ProbeOutcome.timeout,
          detail: networkTimeoutDetail,
        );
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

String get localBackendHint => L10n.current.localBackendProbe_hint;

/// User-facing result of 「測試連線」.
String connectionTestMessage(ProbeResult result, Uri base) {
  final backend = describeBackend(base);
  const endpoint = 'GET /healthz';
  final l10n = L10n.current;
  final version = result.version;
  return switch (result.outcome) {
    ProbeOutcome.healthy =>
      version == null
          ? l10n.localBackendProbe_healthy
          : l10n.localBackendProbe_healthyVersion(version),
    ProbeOutcome.degraded => l10n.localBackendProbe_degraded,
    ProbeOutcome.notBackend => l10n.localBackendProbe_notBackend(
      '${result.status}',
    ),
    ProbeOutcome.httpError => l10n.localBackendProbe_httpError(
      '${result.status}',
    ),
    ProbeOutcome.timeout => l10n.localBackendProbe_timeout(
      GatewayFailure.network(
        endpoint: endpoint,
        detail: networkTimeoutDetail,
        backend: backend,
      ).message,
    ),
    ProbeOutcome.unreachable => l10n.localBackendProbe_unreachable(
      GatewayFailure.network(
        endpoint: endpoint,
        detail: result.detail,
        backend: backend,
      ).message,
    ),
  };
}
