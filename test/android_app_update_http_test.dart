import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/data/android_app_update.dart';
import 'package:gateway_commissioning/data/dashboard_api.dart';
import 'android_app_update_test.dart' show releaseFor;

void main() {
  test(
    'authenticated binary download stays on backend and rejects redirects',
    () async {
      final dir = await Directory.systemTemp.createTemp('update_http_test_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var redirect = false, leakedRequests = 0, authenticatedDownloads = 0;
      other.listen((r) {
        leakedRequests++;
        r.response.close();
      });
      server.listen((r) async {
        if (r.uri.path == '/api/auth/app-login') {
          r.response.write(jsonEncode({'api_key': 'synthetic-session'}));
        } else {
          if (r.headers.value('X-API-Key') == 'synthetic-session') {
            authenticatedDownloads++;
          }
          if (redirect) {
            r.response.statusCode = 302;
            r.response.headers.set(
              'Location',
              'http://127.0.0.1:${other.port}/apk',
            );
          } else {
            r.response.add([1, 2, 3]);
          }
        }
        await r.response.close();
      });
      try {
        final api = DashboardApi();
        await api.login('http://127.0.0.1:${server.port}', 'synthetic-key');
        final release = releaseFor([1, 2, 3]);
        final file = File('${dir.path}/first.apk');
        await api.downloadAndroidUpdate(
          release,
          file,
          UpdateCancellation(),
          (_) {},
        );
        expect(await file.readAsBytes(), [1, 2, 3]);
        redirect = true;
        final rejected = File('${dir.path}/rejected.apk');
        await expectLater(
          api.downloadAndroidUpdate(
            release,
            rejected,
            UpdateCancellation(),
            (_) {},
          ),
          throwsA(isA<AppUpdateException>()),
        );
        expect(authenticatedDownloads, 2);
        expect(leakedRequests, 0);
        expect(await rejected.exists(), isFalse);
      } finally {
        await server.close(force: true);
        await other.close(force: true);
        await dir.delete(recursive: true);
      }
    },
  );
}
