import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/upload_target_card.dart';

const _production = {
  'fw_version': '1.7.3',
  'mqtt_target': 'production',
  'mqtt_host': '46.250.255.172',
  'mqtt_port': 8883,
};

Future<List<MqttTarget>> _pumpCard(
  WidgetTester tester,
  Map<String, dynamic> config,
  AppUploadTarget app,
) async {
  final switched = <MqttTarget>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            UploadTargetCard(
              config: config,
              app: app,
              enabled: true,
              onSwitch: switched.add,
              onRefresh: () {},
            ),
          ],
        ),
      ),
    ),
  );
  return switched;
}

void main() {
  group('UploadTargetCard', () {
    testWidgets('mismatch shows warning and switch button', (tester) async {
      final switched = await _pumpCard(
        tester,
        _production,
        desiredUploadTarget('local', 'http://192.168.1.50:18000'),
      );
      expect(find.text('Gateway 上傳目標'), findsOneWidget);
      expect(find.text('目前：正式站'), findsOneWidget);
      expect(
        find.textContaining('但 APP 連線的是本地 192.168.1.50:8883'),
        findsOneWidget,
      );
      await tester.tap(find.text('將 Gateway 切換到本地 192.168.1.50'));
      expect(
        switched.single.sameAs(const MqttTarget.local('192.168.1.50')),
        isTrue,
      );
    });
    testWidgets('local gateway versus production APP offers 正式站', (
      tester,
    ) async {
      final switched = await _pumpCard(tester, {
        'mqtt_target': 'local',
        'mqtt_host': '192.168.1.187',
        'mqtt_port': 8883,
        'mqtt_connected': true,
      }, desiredUploadTarget('production', productionApiBase));
      expect(find.text('目前：本地 192.168.1.187:8883 · MQTT 已連線'), findsOneWidget);
      await tester.tap(find.text('將 Gateway 切換到正式站'));
      expect(switched.single.isLocal, isFalse);
    });
    testWidgets('matching target shows no button', (tester) async {
      await _pumpCard(
        tester,
        _production,
        desiredUploadTarget('production', productionApiBase),
      );
      expect(find.text('與 APP 連線環境一致（正式站）'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
    testWidgets('legacy firmware warns that step 7 cannot pass on local', (
      tester,
    ) async {
      await _pumpCard(tester, {
        'fw_version': '1.7.2',
      }, desiredUploadTarget('local', 'http://192.168.1.50:18000'));
      expect(
        find.text('此 Gateway 韌體（版本 1.7.2）不支援切換上傳目標，資料固定上傳正式站；需更新至 1.7.3 以上。'),
        findsOneWidget,
      );
      expect(find.textContaining('第 7 步資料驗證將無法通過'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('重新讀取'), findsNothing);
    });
    testWidgets('legacy firmware on production has no step 7 warning', (
      tester,
    ) async {
      await _pumpCard(tester, {
        'fw_version': '1.7.2',
      }, desiredUploadTarget('production', productionApiBase));
      expect(find.textContaining('不支援切換上傳目標'), findsOneWidget);
      expect(find.textContaining('第 7 步'), findsNothing);
    });
    testWidgets('invalid local host shows the error, no button', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _production,
        desiredUploadTarget('local', 'http://mypc.local:18000'),
      );
      expect(find.textContaining('「mypc.local」不是區網私有 IPv4 位址'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
    testWidgets('unknown custom URL is display only', (tester) async {
      await _pumpCard(
        tester,
        _production,
        desiredUploadTarget('custom', 'https://example.invalid'),
      );
      expect(find.text('目前：正式站'), findsOneWidget);
      expect(find.textContaining('僅顯示目前設定'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  testWidgets('confirmation dialog explains impact and can be declined', (
    tester,
  ) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await confirmUploadTargetSwitch(
                context,
                wanted: const MqttTarget.local('192.168.1.50'),
                current: const MqttTarget.production(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('切換 Gateway 上傳目標'), findsOneWidget);
    expect(
      find.textContaining('從「正式站」切換到「本地 192.168.1.50:8883」'),
      findsOneWidget,
    );
    expect(
      find.textContaining('正式站將收不到這台 Gateway 的資料，直到切回正式站為止'),
      findsOneWidget,
    );
    expect(find.textContaining('重新開機（約 1.5 秒）'), findsOneWidget);
    expect(find.textContaining('藍牙連線會中斷'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認切換'));
    await tester.pumpAndSettle();
    expect(answers, [false, true]);
  });

  testWidgets('connected page offers the switch and follows it through', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_environment': 'local',
      'backend_local_url': 'http://192.168.1.50:18000',
    });
    final fake = DemoSystem();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
        child: const GatewayApp(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap(find.text('檢查並開始'));
    await tap(find.text('搜尋閘道器'));
    await tap(find.text('GIOS-S1-GW01'));
    expect(find.text('2 / 8   找到閘道器'), findsNothing);
    expect(find.text('3 / 8   身份與 WiFi'), findsOneWidget);
    expect(find.text('目前：正式站'), findsOneWidget);
    expect(fake.connects, 1);

    await tap(find.text('將 Gateway 切換到本地 192.168.1.50'));
    expect(find.text('切換 Gateway 上傳目標'), findsOneWidget);
    await tap(find.text('確認切換'));

    expect(fake.targetRequests.single['host'], '192.168.1.50');
    expect(fake.connects, 2);
    expect(find.text('目前：本地 192.168.1.50:8883 · MQTT 已連線'), findsOneWidget);
    expect(find.text('與 APP 連線環境一致（本地 192.168.1.50:8883）'), findsOneWidget);
    expect(find.textContaining('已切換到本地 192.168.1.50:8883'), findsOneWidget);
    // The step itself is untouched by the switch.
    final state = ProviderScope.containerOf(
      tester.element(find.byType(GatewayApp)),
    ).read(commissionProvider);
    expect(state.step, 2);
    expect(state.message, '已連線，請設定身份與 WiFi');
    expect(state.error, isNull);
    expect(state.busy, isFalse);
    expect(tester.takeException(), isNull);
  });
}
