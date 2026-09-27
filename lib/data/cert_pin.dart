/// Optional certificate pinning for the production backend.
///
/// `--dart-define=API_CERT_SHA256=<hex>` (colons / case ignored) makes every
/// HTTPS connection to the production API host ([productionApiBase]) accept
/// only a server certificate whose SHA-256 fingerprint equals the pin; the
/// system trust store is not consulted for that host (so a self-signed
/// certificate works and a CA-issued one with another key does not).
/// Unset: no pinning, system trust only. Other hosts (local http, custom)
/// always keep system trust.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/mqtt_target.dart';

const apiCertSha256 = String.fromEnvironment('API_CERT_SHA256');

/// Lower-case hex without separators; empty when [pin] is not 64 hex digits.
String normalizeCertPin(String pin) {
  final hex = pin.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : '';
}

/// Whether [der] (the server certificate) matches [pin]. An invalid or
/// empty pin matches nothing.
bool certMatchesPin(List<int> der, String pin) {
  final want = normalizeCertPin(pin);
  return want.isNotEmpty && sha256.convert(der).toString() == want;
}

/// Pinning decision for one base URL: the normalized pin to enforce, or
/// null when the connection keeps system trust.
String? pinFor(Uri base, {String pin = apiCertSha256, String? productionBase}) {
  if (pin.trim().isEmpty || base.scheme != 'https') return null;
  final prod = Uri.tryParse(productionBase ?? productionApiBase);
  if (prod == null || !prod.hasAuthority) return null;
  if (base.host.toLowerCase() != prod.host.toLowerCase() ||
      base.port != prod.port) {
    return null;
  }
  // A malformed pin still pins (to nothing): fail closed, never open.
  final n = normalizeCertPin(pin);
  return n.isEmpty ? '!' : n;
}

/// HTTP client for [base]: pinned (no system roots, fingerprint check) when
/// [pinFor] says so, a plain system-trust client otherwise.
HttpClient apiHttpClientFor(Uri base, {String pin = apiCertSha256}) {
  final want = pinFor(base, pin: pin);
  final client = want == null
      ? HttpClient()
      : (HttpClient(context: SecurityContext(withTrustedRoots: false))
          ..badCertificateCallback = (cert, host, port) =>
              host.toLowerCase() == base.host.toLowerCase() &&
              port == base.port &&
              certMatchesPin(cert.der, want));
  return client..connectionTimeout = const Duration(seconds: 10);
}
