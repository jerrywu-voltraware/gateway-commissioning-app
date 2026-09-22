import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/protocol.dart';
import 'contracts.dart';

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
            !(const bool.fromEnvironment('LOCAL_DEVELOPMENT') &&
                uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)))) {
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
    try {
      final req = await _http
          .openUrl(method, base.resolve(path))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      if (_key != null) req.headers.set('X-API-Key', _key!);
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) {
        _key = null;
        throw const GatewayFailure('authentication');
      }
      if (res.statusCode == 409) throw const GatewayFailure('conflict');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw const GatewayFailure('api');
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } on GatewayFailure {
      rethrow;
    } catch (_) {
      throw const GatewayFailure('api');
    }
  }
}
