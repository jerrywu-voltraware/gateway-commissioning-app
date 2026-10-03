import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Passwords entered in this app, indexed by the exact SSID string.
abstract interface class WifiPasswordStore {
  Future<String?> read(String ssid);
  Future<void> write(String ssid, String password);
  Future<void> delete(String ssid);
}

/// Intentionally carries no platform error, SSID, or password.
class WifiPasswordStoreException implements Exception {
  const WifiPasswordStoreException();

  @override
  String toString() => 'Wi-Fi password storage unavailable';
}

class SecureWifiPasswordStore implements WifiPasswordStore {
  const SecureWifiPasswordStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  // The plugin's Android singleton retains custom preference names/prefixes
  // across calls. Keep its existing encrypted store and isolate by key instead,
  // so DashboardApi's default session storage continues using the same file.
  // Android backup rules exclude this store and its wrapped encryption key.
  static const _androidOptions = AndroidOptions();
  static const _iosOptions = IOSOptions(
    accountName: 'com.voltraware.gateway_commissioning.wifi_passwords.v1',
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  // Shared across form/store instances: a pending write must finish before a
  // later forget operation. Failed operations must not block later requests.
  static final _pending = <String, Future<void>>{};

  String _key(String ssid) =>
      'wifi-password:v1:${sha256.convert(utf8.encode(ssid))}';

  Future<T> _ordered<T>(String ssid, Future<T> Function(String key) action) {
    final key = _key(ssid);
    final previous = _pending[key] ?? Future<void>.value();
    final result = previous.then((_) async {
      try {
        return await action(key);
      } catch (_) {
        throw const WifiPasswordStoreException();
      }
    });
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[key] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_pending[key], settled)) _pending.remove(key);
      }),
    );
    return result;
  }

  @override
  Future<String?> read(String ssid) => _ordered(
    ssid,
    (key) => storage.read(
      key: key,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    ),
  );

  @override
  Future<void> write(String ssid, String password) => _ordered(
    ssid,
    (key) => storage.write(
      key: key,
      value: password,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    ),
  );

  @override
  Future<void> delete(String ssid) => _ordered(
    ssid,
    (key) => storage.delete(
      key: key,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    ),
  );
}
