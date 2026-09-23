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

class DashboardApi implements GatewayApi {
  final _storage = const FlutterSecureStorage();
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  Uri? _base;
  String? _key;
  @override
  Future<void> login(String base, String password) async {
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' &&
            !((kDebugMode || const bool.fromEnvironment('LOCAL_DEVELOPMENT')) &&
                uri.scheme == 'http' &&
                isLocalApiHost(uri.host)))) {
      throw const GatewayFailure('https_required');
    }
    _key = null;
    _base = uri;
    final result = await request('POST', '/api/auth/login', {
      'password': password,
    });
    _key = result['api_key'] as String?;
    if (_key == null || _key!.isEmpty) {
      throw const GatewayFailure('authentication');
    }
    await _storage.write(key: 'api:${uri.origin}', value: _key);
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
