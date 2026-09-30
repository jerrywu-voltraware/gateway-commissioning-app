import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/protocol.dart';
import 'cert_pin.dart';
import 'contracts.dart';
import 'android_app_update.dart';

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
/// phone keeps working without logging in again).
const sessionTokenTtl = Duration(hours: 12);

/// Secure-storage key of the session of [base] (its origin).
String sessionStorageKey(Uri base) => 'session:${base.origin}';

/// [base] when the APP may send a credential / key to it: https, or plain
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

class DashboardApi
    implements
        GatewayApi,
        SessionStore,
        SessionInfo,
        OperatorInfo,
        ServerClock,
        AndroidUpdateDownload {
  DashboardApi({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _storage = const FlutterSecureStorage();
  // One client per API origin: the production host may trust the build CA
  // and / or be pinned (cert_pin.dart); every other origin uses system trust.
  final _clients = <String, HttpClient>{};
  HttpClient _httpFor(Uri base) =>
      _clients.putIfAbsent(base.origin, () => apiHttpClientFor(base));
  Uri? _base;
  String? _key;

  /// Field rescue v1.1: the account name the login answered with (none
  /// today: the APP logs in with its build credential), kept with the
  /// session token.
  String? _operator;

  @override
  bool get hasSession => _base != null && _key != null;

  @override
  String? get operatorName => _operator;

  @override
  String? get origin => _base?.origin;

  /// 09-28: [credential] is the build's backend key (`APP_BACKEND_KEY`;
  /// field staff never type a password), exchanged for a session token at
  /// `POST /api/auth/app-login`. An empty one means the APK was built
  /// without `.secrets/<env>.env`: said so, nothing is sent.
  @override
  Future<void> login(String base, String credential) async {
    final uri = _apiBase(base);
    if (uri == null) throw const GatewayFailure('https_required');
    if (credential.isEmpty) throw const GatewayFailure('missing_backend_key');
    _key = null;
    _operator = null;
    _base = uri;
    final result = await request('POST', '/api/auth/app-login', {
      'app_key': credential,
    });
    _key = result['api_key'] as String?;
    if (_key == null || _key!.isEmpty) {
      throw const GatewayFailure('authentication');
    }
    _operator = operatorNameOf(result['operator_name'] ?? result['username']);
    // Round 17: the token (not the credential) with its expiry, so 「重新連線
    // 並繼續」 after the APP was killed needs no login. A storage failure
    // never fails the login itself.
    try {
      await _storage.write(
        key: sessionStorageKey(uri),
        value: jsonEncode({
          'token': _key,
          'expires': _now().add(sessionTokenTtl).millisecondsSinceEpoch,
          'operator': ?_operator,
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
      _operator = operatorNameOf(data['operator']);
      return true;
    } catch (_) {
      return false;
    }
  }

  Duration? _serverOffset;

  @override
  Duration? get serverClockOffset => _serverOffset;

  @override
  Future<void> downloadAndroidUpdate(
    AndroidAppRelease release,
    File destination,
    UpdateCancellation cancellation,
    void Function(int received) onProgress,
  ) async {
    final base = _base;
    final key = _key;
    if (base == null || key == null) {
      throw const GatewayFailure('authentication');
    }
    // Only the authenticated backend may receive this session credential.
    if (!RegExp(
      r'^/api/app/updates/android/android-v\d+\.\d+\.\d+-b\d+/apk$',
    ).hasMatch(release.path)) {
      throw const AppUpdateException('metadata');
    }
    final url = base.resolve(release.path);
    if (url.origin != base.origin || url.hasQuery || url.hasFragment) {
      throw const AppUpdateException('metadata');
    }
    HttpClientRequest? request;
    final removeCancel = cancellation.listen(() => request?.abort());
    var timedOut = false;
    final deadline = Timer(const Duration(minutes: 5), () {
      timedOut = true;
      request?.abort();
    });
    try {
      cancellation.check();
      request = await _httpFor(
        base,
      ).getUrl(url).timeout(const Duration(seconds: 10));
      cancellation.check();
      request.followRedirects = false;
      request.headers.set('X-API-Key', key);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode == 401) {
        await response.listen(null).cancel();
        _key = null;
        throw const GatewayFailure('authentication');
      }
      if (response.statusCode != 200 ||
          (response.contentLength >= 0 &&
              response.contentLength != release.sizeBytes)) {
        await response.listen(null).cancel();
        throw const AppUpdateException('download');
      }
      await writeVerifiedUpdate(
        response.timeout(const Duration(seconds: 20)),
        destination,
        release,
        cancellation,
        onProgress,
      );
      if (timedOut) {
        if (await destination.exists()) await destination.delete();
        throw const AppUpdateException('timeout');
      }
    } on IOException {
      cancellation.check();
      throw AppUpdateException(timedOut ? 'timeout' : 'download');
    } on TimeoutException {
      throw const AppUpdateException('timeout');
    } finally {
      deadline.cancel();
      removeCancel();
      request?.abort();
    }
  }

  /// 1.0.0+10: an answer's `Date` header (RFC 1123) as the back office's
  /// clock offset; a missing or unreadable one keeps the last.
  void _noteServerDate(String? value) {
    if (value == null) return;
    try {
      _serverOffset = HttpDate.parse(value).difference(_now());
    } catch (_) {}
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
      final req = await _httpFor(base)
          .openUrl(method, base.resolve(path))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      if (_key != null) req.headers.set('X-API-Key', _key!);
      if (body != null) req.write(jsonEncode(body));
      res = await req.close().timeout(const Duration(seconds: 15));
      _noteServerDate(res.headers.value(HttpHeaders.dateHeader));
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
      // credential (no key sent) leaves the stored session alone.
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
