/// Server trust for the production backend.
///
/// Two build-time settings, both optional:
///
/// * `API_CA_PEM_B64` (base64 of a PEM file, from `API_CA_FILE` in
///   `.secrets/<env>.env`, tools/build_apk.ps1): the production API host
///   ([productionApiBase]) is verified with the normal chain check — system
///   roots plus this CA, host name / IP SAN included. No
///   badCertificateCallback: a certificate that does not chain to a trusted
///   root (a self-signed one, another CA's) fails the handshake. 09-28: the
///   production nginx sends leaf + IoTGateway-CA.
/// * `API_CERT_SHA256` (64 hex digits, colons / case ignored):
///   - with the CA: an extra pin — the leaf (the server's own certificate,
///     [SecureSocket.peerCertificate]) must also have this SHA-256
///     fingerprint; both checks must pass;
///   - without a CA: the old single self-signed certificate pinning (no
///     system roots, the certificate handed to badCertificateCallback must
///     match). Only valid for a server that sends ONE self-signed
///     certificate: with a chain Dart hands over the certificate that
///     failed (the CA), so a leaf pin never matches (r33).
///
/// Neither set: system trust only. Other hosts (local http, custom) always
/// keep system trust.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/mqtt_target.dart';

const apiCertSha256 = String.fromEnvironment('API_CERT_SHA256');
const apiCaPemB64 = String.fromEnvironment('API_CA_PEM_B64');

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

/// Whether [base] is the production API origin (https, same host and port).
bool isProductionApi(Uri base, {String? productionBase}) {
  if (base.scheme != 'https') return false;
  final prod = Uri.tryParse(productionBase ?? productionApiBase);
  if (prod == null || !prod.hasAuthority) return false;
  return base.host.toLowerCase() == prod.host.toLowerCase() &&
      base.port == prod.port;
}

/// Pinning decision for one base URL: the normalized pin to enforce, or
/// null when the connection keeps system trust.
String? pinFor(Uri base, {String pin = apiCertSha256, String? productionBase}) {
  if (pin.trim().isEmpty) return null;
  if (!isProductionApi(base, productionBase: productionBase)) return null;
  // A malformed pin still pins (to nothing): fail closed, never open.
  final n = normalizeCertPin(pin);
  return n.isEmpty ? '!' : n;
}

/// The CA PEM bytes of [caPemB64]; null when none is configured. A value
/// that is not base64 of a PEM certificate gives an empty list (trusts
/// nothing extra: fail closed, the system roots still apply).
List<int>? caPemBytes(String caPemB64) {
  final b64 = caPemB64.replaceAll(RegExp(r'\s'), '');
  if (b64.isEmpty) return null;
  try {
    final bytes = base64.decode(b64);
    return utf8
            .decode(bytes, allowMalformed: true)
            .contains('-----BEGIN CERTIFICATE-----')
        ? bytes
        : const [];
  } on FormatException {
    return const [];
  }
}

/// Security context for the production host with [ca] trusted besides the
/// system roots. A CA that cannot be loaded is left out (fail closed).
SecurityContext caSecurityContext(List<int> ca) {
  final context = SecurityContext(withTrustedRoots: true);
  if (ca.isNotEmpty) {
    try {
      context.setTrustedCertificatesBytes(ca);
    } on TlsException {
      /* not a certificate: only the system roots */
    }
  }
  return context;
}

/// HTTP client for [base]:
/// * production + CA ([caPemB64]): chain verification against system roots
///   plus the CA, and — when [pin] is also set — the leaf's fingerprint;
/// * production + pin only: the single self-signed certificate pinning;
/// * anything else: a plain system-trust client.
HttpClient apiHttpClientFor(
  Uri base, {
  String pin = apiCertSha256,
  String caPemB64 = apiCaPemB64,
  String? productionBase,
}) {
  final prod = isProductionApi(base, productionBase: productionBase);
  final ca = prod ? caPemBytes(caPemB64) : null;
  final want = pinFor(base, pin: pin, productionBase: productionBase);
  final HttpClient client;
  if (ca != null) {
    final context = caSecurityContext(ca);
    client = HttpClient(context: context);
    if (want != null) {
      // The leaf is checked on the socket right after the handshake,
      // before any request byte is written.
      client.connectionFactory = (uri, proxyHost, proxyPort) async {
        final task = await SecureSocket.startConnect(
          uri.host,
          uri.port,
          context: context,
        );
        return ConnectionTask.fromSocket(
          task.socket.then((socket) {
            final leaf = socket.peerCertificate;
            if (leaf == null || !certMatchesPin(leaf.der, want)) {
              socket.destroy();
              throw const HandshakeException(
                'server certificate does not match API_CERT_SHA256',
              );
            }
            return socket;
          }),
          task.cancel,
        );
      };
    }
  } else if (want != null) {
    client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (cert, host, port) =>
          host.toLowerCase() == base.host.toLowerCase() &&
          port == base.port &&
          certMatchesPin(cert.der, want);
  } else {
    client = HttpClient();
  }
  return client..connectionTimeout = const Duration(seconds: 10);
}
