import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/wifi_password_store.dart';

class _Call {
  const _Call(this.method, this.key, this.android, this.ios);
  final String method;
  final String key;
  final AndroidOptions? android;
  final IOSOptions? ios;
}

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  final calls = <_Call>[];
  Future<void> Function(String method, String key)? before;

  Future<void> _call(
    String method,
    String key,
    AndroidOptions? android,
    IOSOptions? ios,
  ) async {
    calls.add(_Call(method, key, android, ios));
    await before?.call(method, key);
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _call('read', key, aOptions, iOptions);
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _call('write', key, aOptions, iOptions);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _call('delete', key, aOptions, iOptions);
    values.remove(key);
  }
}

void main() {
  late _Storage storage;
  late WifiPasswordStore store;

  setUp(() {
    storage = _Storage();
    store = SecureWifiPasswordStore(storage: storage);
  });

  test(
    'missing network returns null; password contents survive unchanged',
    () async {
      expect(await store.read('Test network'), isNull);
      const password = '  fake-only 密碼 "quoted" \\ end  ';
      await store.write('Test network', password);
      expect(await store.read('Test network'), password);
      await store.write('Test network', '');
      expect(await store.read('Test network'), '');
    },
  );

  test(
    'SSID matching preserves whitespace, case, quotes and Unicode',
    () async {
      const ssids = [
        'Test',
        ' Test',
        'Test ',
        'test',
        '"Test"',
        '測試網路',
        'caf\u00e9',
        'cafe\u0301',
      ];
      for (var i = 0; i < ssids.length; i++) {
        await store.write(ssids[i], 'fake-password-$i');
      }
      for (var i = 0; i < ssids.length; i++) {
        expect(await store.read(ssids[i]), 'fake-password-$i');
      }
      expect(storage.values.length, ssids.length);
      expect(
        storage.values.keys,
        everyElement(matches(RegExp(r'^wifi-password:v1:[a-f0-9]{64}$'))),
      );
    },
  );

  test(
    'forget only removes its Wi-Fi key and never touches session data',
    () async {
      storage.values['session:https://example.invalid'] = 'fake-session';
      await store.write('Network A', 'fake-a');
      await store.write('Network B', 'fake-b');
      await store.delete('Network A');
      expect(await store.read('Network A'), isNull);
      expect(await store.read('Network B'), 'fake-b');
      expect(storage.values['session:https://example.invalid'], 'fake-session');
      await store.delete('Missing network');
      expect(storage.values.length, 2);
    },
  );

  test(
    'all operations use device-only non-sync iOS service isolation',
    () async {
      await store.write('Test', 'fake-password');
      await store.read('Test');
      await store.delete('Test');
      for (final call in storage.calls) {
        expect(call.ios!.toMap(), {
          'accountName':
              'com.voltraware.gateway_commissioning.wifi_passwords.v1',
          'accessibility': 'unlocked_this_device',
          'synchronizable': 'false',
        });
        expect(
          call.ios!.toMap()['accountName'],
          isNot(AppleOptions.defaultAccountName),
        );
      }
    },
  );

  test(
    'Android keeps existing secure-storage mode without global resets',
    () async {
      await store.write('Test', 'fake-password');
      await store.read('Test');
      await store.delete('Test');
      for (final call in storage.calls) {
        expect(call.android!.toMap(), const AndroidOptions().toMap());
        expect(call.android!.toMap()['resetOnError'], 'false');
        expect(call.android!.toMap()['sharedPreferencesName'], '');
        expect(call.android!.toMap()['preferencesKeyPrefix'], '');
      }
    },
  );

  test(
    'a pending write cannot restore a password after a later forget',
    () async {
      final started = Completer<void>();
      final finishWrite = Completer<void>();
      storage.before = (method, _) async {
        if (method == 'write') {
          started.complete();
          await finishWrite.future;
        }
      };
      final writing = store.write('Test', 'fake-password');
      await started.future;
      final otherFormStore = SecureWifiPasswordStore(storage: storage);
      final deleting = otherFormStore.delete('Test');
      final reading = otherFormStore.read('Test');
      await Future<void>.delayed(Duration.zero);
      expect(storage.calls.map((call) => call.method), ['write']);
      finishWrite.complete();
      await writing;
      await deleting;
      expect(await reading, isNull);
      expect(storage.calls.map((call) => call.method), [
        'write',
        'delete',
        'read',
      ]);
    },
  );

  test('different SSIDs are independent while one write is pending', () async {
    final started = Completer<void>();
    final finishWrite = Completer<void>();
    storage.before = (method, _) async {
      if (method == 'write' && !started.isCompleted) {
        started.complete();
        await finishWrite.future;
      }
    };
    final writing = store.write('Network A', 'fake-a');
    await started.future;
    await store.write('Network B', 'fake-b');
    expect(await store.read('Network B'), 'fake-b');
    finishWrite.complete();
    await writing;
  });

  for (final method in ['read', 'write', 'delete']) {
    test(
      '$method failure is generic and does not poison the operation queue',
      () async {
        storage.before = (_, _) async {
          throw PlatformException(
            code: 'fake-password',
            message: 'Private Test SSID',
            details: 'fake-platform-sensitive-details',
          );
        };
        final operation = switch (method) {
          'read' => store.read('Private Test SSID'),
          'write' => store.write('Private Test SSID', 'fake-password'),
          _ => store.delete('Private Test SSID'),
        };
        await expectLater(
          operation,
          throwsA(
            isA<WifiPasswordStoreException>().having(
              (error) => error.toString(),
              'safe message',
              'Wi-Fi password storage unavailable',
            ),
          ),
        );
        storage.before = null;
        await store.write('Private Test SSID', 'fake-replacement');
        expect(await store.read('Private Test SSID'), 'fake-replacement');
        await store.delete('Private Test SSID');
        expect(await store.read('Private Test SSID'), isNull);
      },
    );
  }
}
