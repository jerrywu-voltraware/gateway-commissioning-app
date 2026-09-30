import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/android_app_update.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/data/android_app_update.dart';
import 'package:gateway_commissioning/data/contracts.dart';

Map<String, dynamic> updateResponse({
  int code = 21,
  List<int> bytes = const [1, 2, 3],
}) => {
  'available': true,
  'release': {
    'schema_version': 1,
    'platform': 'android',
    'package_name': updatePackageName,
    'version_name': '1.0.0',
    'version_code': code,
    'release_tag': 'android-v1.0.0-b$code',
    'release_notes': '改善配置流程與更新體驗。',
    'apk': {
      'url': '/api/app/updates/android/android-v1.0.0-b$code/apk',
      'sha256': sha256.convert(bytes).toString(),
      'size_bytes': bytes.length,
      'signing_certificate_sha256': updateSignerSha256,
    },
  },
};
const installedBuild20 = InstalledAndroidApp(20, '1.0.0', updatePackageName);
AndroidAppRelease releaseFor(List<int> bytes) => AndroidAppRelease.parseLatest(
  updateResponse(bytes: bytes),
  installedBuild20,
)!;

void main() {
  test('only a strictly newer Android build is offered', () {
    expect(
      AndroidAppRelease.parseLatest(
        updateResponse(),
        installedBuild20,
      )!.versionCode,
      21,
    );
    for (final code in [19, 20]) {
      expect(
        AndroidAppRelease.parseLatest(
          updateResponse(code: code),
          installedBuild20,
        ),
        isNull,
      );
    }
    expect(
      AndroidAppRelease.parseLatest({'available': false}, installedBuild20),
      isNull,
    );
  });
  test(
    'malformed metadata and external or altered download paths are rejected',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['version_code'] = '21',
        (r) => r['package_name'] = 'another.app',
        (r) => r['platform'] = 'ios',
        (r) => r['schema_version'] = 2,
        (r) => r['release_tag'] = '../escape',
        (r) => r['apk']['url'] = 'https://outside.invalid/file.apk',
        (r) => r['apk']['url'] = '//outside.invalid/file.apk',
        (r) => r['apk']['url'] += '?token=x',
        (r) => r['apk']['signing_certificate_sha256'] = '0' * 64,
        (r) => r['apk']['size_bytes'] = maxUpdateBytes + 1,
        (r) => r['apk']['sha256'] = 'bad',
      ]) {
        final response = updateResponse();
        mutate(response['release'] as Map<String, dynamic>);
        expect(
          () => AndroidAppRelease.parseLatest(response, installedBuild20),
          throwsA(isA<AppUpdateException>()),
        );
      }
    },
  );
  test('updates are allowed only on idle disconnected home', () {
    expect(appUpdateHomeAllowed(const CommissionState()), isTrue);
    for (final state in [
      const CommissionState(step: 1),
      const CommissionState(step: 7),
      const CommissionState(busy: true),
      const CommissionState(resumePending: true),
      const CommissionState(peer: GatewayPeer('a', 'gateway', -50)),
    ]) {
      expect(appUpdateHomeAllowed(state), isFalse);
    }
    expect(
      appUpdateHomeAllowed(const CommissionState(), connected: true),
      isFalse,
    );
  });

  group('verified file streaming', () {
    late Directory dir;
    late File file;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('app_update_test_');
      file = File('${dir.path}/update.apk');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });
    test(
      'cancelling a stalled stream closes it immediately before retry',
      () async {
        var sourceCancelled = false;
        final source = StreamController<List<int>>(
          onCancel: () => sourceCancelled = true,
        );
        final cancel = UpdateCancellation();
        final started = Completer<void>();
        final download = writeVerifiedUpdate(
          source.stream,
          file,
          releaseFor([1, 2, 3]),
          cancel,
          (_) => started.complete(),
        );
        source.add([1]);
        await started.future;
        final assertion = expectLater(
          download,
          throwsA(isA<AppUpdateException>()),
        );
        cancel.cancel();
        await assertion.timeout(const Duration(seconds: 1));
        expect(sourceCancelled, isTrue);
        expect(await file.exists(), isFalse);
        expect(await File('${file.path}.part').exists(), isFalse);
        await writeVerifiedUpdate(
          Stream.value([1, 2, 3]),
          file,
          releaseFor([1, 2, 3]),
          UpdateCancellation(),
          (_) {},
        );
        expect(await file.readAsBytes(), [1, 2, 3]);
        await source.close();
      },
    );
    test('writes exact bytes only after complete hash validation', () async {
      final progress = <int>[];
      await writeVerifiedUpdate(
        Stream.fromIterable([
          [1],
          [2, 3],
        ]),
        file,
        releaseFor([1, 2, 3]),
        UpdateCancellation(),
        progress.add,
      );
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(progress, [1, 3]);
      expect(await File('${file.path}.part').exists(), isFalse);
    });
    test(
      'tampering, truncated and oversized streams clean partials; retry succeeds',
      () async {
        for (final bytes in [
          [1, 2, 4],
          [1],
          [1, 2, 3, 4],
        ]) {
          await expectLater(
            writeVerifiedUpdate(
              Stream.value(bytes),
              file,
              releaseFor([1, 2, 3]),
              UpdateCancellation(),
              (_) {},
            ),
            throwsA(isA<AppUpdateException>()),
          );
          expect(await file.exists(), isFalse);
          expect(await File('${file.path}.part').exists(), isFalse);
        }
        await writeVerifiedUpdate(
          Stream.value([1, 2, 3]),
          file,
          releaseFor([1, 2, 3]),
          UpdateCancellation(),
          (_) {},
        );
        expect(await file.readAsBytes(), [1, 2, 3]);
      },
    );
    test(
      'offline failure and cancellation leave no installable partial',
      () async {
        await expectLater(
          writeVerifiedUpdate(
            Stream.error(const SocketException('offline')),
            file,
            releaseFor([1, 2, 3]),
            UpdateCancellation(),
            (_) {},
          ),
          throwsA(isA<SocketException>()),
        );
        final cancel = UpdateCancellation();
        await expectLater(
          writeVerifiedUpdate(
            Stream.fromIterable([
              [1],
              [2, 3],
            ]),
            file,
            releaseFor([1, 2, 3]),
            cancel,
            (_) => cancel.cancel(),
          ),
          throwsA(isA<AppUpdateException>()),
        );
        expect(await file.exists(), isFalse);
        expect(await File('${file.path}.part').exists(), isFalse);
      },
    );
  });
}
