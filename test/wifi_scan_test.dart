import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/wifi_scan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('phone Wi-Fi', () {
    const wifi = MethodChannel('voltraware/wifi');
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> calls;
    int permission = 1;
    int service = 1;
    String? ssid;
    setUp(() {
      calls = [];
      permission = service = 1;
      ssid = '  Office "2G"  ';
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(permissions, (call) async {
        calls.add(call.method);
        if (call.method == 'checkServiceStatus') return service;
        if (call.method == 'requestPermissions') return {5: permission};
        throw StateError('Unexpected permission operation');
      });
      messenger.setMockMethodCallHandler(wifi, (call) async {
        calls.add(call.method);
        if (call.method == 'requestLocation') return null;
        return ssid;
      });
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(wifi, null);
      messenger.setMockMethodCallHandler(permissions, null);
      debugDefaultTargetPlatformOverride = null;
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      test(
        '$platform reads connected SSID exactly after permission, without scanning',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          expect(await readCurrentWifiSsid(), '  Office "2G"  ');
          expect(
            calls,
            platform == TargetPlatform.iOS
                ? ['requestLocation', 'current']
                : ['checkServiceStatus', 'requestPermissions', 'current'],
          );
        },
      );
    }
    test('no connected network is not a usable SSID', () async {
      ssid = null;
      expect(await readCurrentWifiSsid(), isNull);
      ssid = '';
      expect(await readCurrentWifiSsid(), isNull);
    });
    test('location disabled does not prompt or read SSID', () async {
      service = 0;
      await expectLater(
        readCurrentWifiSsid(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'location_off',
          ),
        ),
      );
      expect(calls, ['checkServiceStatus']);
    });
    for (final status in [0, 4]) {
      test('denied permission $status never reads SSID', () async {
        permission = status;
        await expectLater(
          readCurrentWifiSsid(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              status == 4 ? 'permission_permanently_denied' : 'permission',
            ),
          ),
        );
        expect(calls, ['checkServiceStatus', 'requestPermissions']);
      });
    }
  });

  test('WiFi choices filter bands and hidden SSIDs, deduplicate and sort', () {
    final networks = selectableNetworks([
      {'ssid': 'Office', 'rssi': -80, 'frequency': 2412},
      {'ssid': 'Office', 'rssi': -40, 'frequency': 2437},
      {'ssid': 'Only5G', 'rssi': -20, 'frequency': 5180},
      {'ssid': '', 'rssi': -10, 'frequency': 2412},
      {'ssid': '中文 WiFi ', 'rssi': -50, 'frequency': 2462},
    ]);
    expect(networks.map((n) => n.ssid), ['Office', '中文 WiFi ']);
    expect(networks.first.rssi, -40);
  });

  test('iOS reports Wi-Fi scan as unsupported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await expectLater(
      scanWifiNetworks(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'unsupported',
        ),
      ),
    );
  });
}
