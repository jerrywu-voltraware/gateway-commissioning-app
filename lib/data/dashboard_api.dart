import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/protocol.dart';
import 'contracts.dart';

bool isLocalApiHost(String host) {
  if (host == 'localhost') return true;
  final address = InternetAddress.tryParse(host);
  if (address == null || address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  return bytes[0] == 127 ||
      bytes[0] == 10 ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31);
}

/// Round 17: how long a stored session token is used after its login
/// (the backend's key itself does not expire; this bounds how long a
/// phone keeps working without the password).
const sessionTokenTtl = Duration(hours: 12);

/// Secure-storage key of the session of [base] (its origin).
String sessionStorageKey(Uri base) => 'session:${base.origin}';

/// [base] when the APP may send a password / key to it: https, or plain
/// http to a local host in debug and LOCAL_DEVELOPMENT builds.
Uri? _apiBase(String base) {
  final uri = Uri.tryParse(base.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme != 'https' &&
          !((kDebugMode || const bool.fromEnvironment('LOCAL_DEVELOPMENT')) &&
              uri.scheme == 'http' &&
              isLocalApiHost(uri.host)))) {
    return null;
  }
  return uri;
}

class DashboardApi implements GatewayApi, SessionStore {
  DashboardApi({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _storage = const FlutterSecureStorage();
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  Uri? _base;
  String? _key;
  @override
  Future<void> login(String base, String password) async {
    final uri = _apiBase(base);
    if (uri == null) throw const GatewayFailure('https_required');
    _key = null;
    _base = uri;
    final result = await request('POST', '/api/auth/login', {
      'password': password,
    });
    _key = result['api_key'] as String?;
    if (_key == null || _key!.isEmpty) {
      throw const GatewayFailure('authentication');
    }
    // Round 17: the token (not the password) with its expiry, so 「重新連線
    // 並繼續」 after the APP was killed needs no login. A storage failure
    // never fails the login itself.
    try {
      await _storage.write(
        key: sessionStorageKey(uri),
        value: jsonEncode({
          'token': _key,
          'expires': _now().add(sessionTokenTtl).millisecondsSinceEpoch,
        }),
      );
      await _storage.delete(key: 'api:${uri.origin}');
    } catch (_) {}
  }

  /// Round 17: the session the last login to [base] saved, while it has
  /// not expired; an expired or unreadable one is dropped.
  @override
  Future<bool> restoreSession(String base) async {
    final uri = _apiBase(base);
    if (uri == null) return false;
    try {
      final raw = await _storage.read(key: sessionStorageKey(uri));
      if (raw == null) return false;
      final data = jsonDecode(raw);
      final token = data is Map ? data['token'] : null;
      final expires = data is Map ? data['expires'] : null;
      if (token is! String ||
          token.isEmpty ||
          expires is! int ||
          !_now().isBefore(DateTime.fromMillisecondsSinceEpoch(expires))) {
        await _storage.delete(key: sessionStorageKey(uri));
        return false;
      }
      _base = uri;
      _key = token;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final base = _base;
    if (base == null) throw const GatewayFailure('authentication');
    // Query strings may carry identifiers such as MACs; never surface them.
    final endpoint = '$method ${Uri.parse(path).path}';
    final backend = describeBackend(base);
    HttpClientResponse res;
    String text;
    try {
      final req = await _http
          .openUrl(method, base.resolve(path))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      if (_key != null) req.headers.set('X-API-Key', _key!);
      if (body != null) req.write(jsonEncode(body));
      res = await req.close().timeout(const Duration(seconds: 15));
      text = await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw GatewayFailure.network(
        endpoint: endpoint,
        detail: '逾時',
        backend: backend,
      );
    } on IOException catch (error) {
      throw GatewayFailure.network(
        endpoint: endpoint,
        detail: networkErrorText(error),
        backend: backend,
      );
    }
    if (res.statusCode == 401) {
      // Round 17: a refused (saved) token is not tried again; a refused
      // password (no key sent) leaves the stored session alone.
      if (_key != null) {
        try {
          await _storage.delete(key: sessionStorageKey(base));
        } catch (_) {}
      }
      _key = null;
      throw const GatewayFailure('authentication');
    }
    if (res.statusCode == 409) throw const GatewayFailure('conflict');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GatewayFailure.http(
        status: res.statusCode,
        endpoint: endpoint,
        detail: errorDetail(text),
        backend: backend,
      );
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (error) {
      throw GatewayFailure(
        'bad_response',
        status: res.statusCode,
        endpoint: endpoint,
        detail: error.runtimeType.toString(),
        backend: backend,
      );
    }
  }
}

/// Server `detail` from a FastAPI-style JSON error body, if any.
String? errorDetail(String body) {
  try {
    final data = jsonDecode(body);
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail == null) return null;
    final text = detail is String ? detail : jsonEncode(detail);
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  } catch (_) {
    return null;
  }
}

String networkErrorText(IOException error) {
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    final msg = error.osError?.message ?? error.message;
    return code == null ? msg : '$msg (errno $code)';
  }
  if (error is TlsException) return 'TLS: ${error.message}';
  if (error is HttpException) return error.message;
  return error.runtimeType.toString();
}

/// Short, user-facing label for a backend base URL (never includes secrets).
String describeBackend(Uri? base) {
  if (base == null) return '（尚未設定後端網址）';
  final origin = base.hasAuthority ? base.origin : base.toString();
  return isLocalApiHost(base.host) ? '區域網路／本機後端 $origin' : '後端 $origin';
}
