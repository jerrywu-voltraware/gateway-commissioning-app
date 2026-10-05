import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/contracts.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/field_support_panel.dart';
import 'support/l10n.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';

class SupportFake extends DemoSystem implements SessionInfo {
  @override
  bool hasSession = true;
  @override
  String? origin = const BackendEnvState().base;
  Map<String, dynamic> data = {
    'state': 'pending',
    'revision': 0,
    'events': <Map<String, dynamic>>[],
    'supported': true,
  };
  final calls = <(String, String, Map<String, dynamic>?)>[];
  bool offline = false;
  bool unsupported = false;
  Completer<Map<String, dynamic>>? pending;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add((method, path, body));
    if (unsupported) {
      throw GatewayFailure.http(status: 404, endpoint: path);
    }
    if (offline) throw StateError('offline');
    if (pending != null) return pending!.future;
    if (method == 'POST') {
      data = {
        ...data,
        'state': body!['action'] == 'resolved' ? 'resolved' : 'handling',
        'revision': (body['expected_revision'] as int) + 1,
      };
    }
    return data;
  }
}

Future<void> showPanel(WidgetTester tester, SupportFake fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FieldSupportPanel(
              sessionId: 'a' * 32,
              onRequestAgain: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'an older backend uses phone help until a manual retry succeeds',
    (tester) async {
      final fake = SupportFake()..unsupported = true;
      await showPanel(tester, fake);
      expect(find.text('請電話聯絡後台協助'), findsOneWidget);
      expect(find.text('正在取得協助狀態…'), findsNothing);
      expect(find.text('已解決'), findsNothing);
      expect(find.byKey(const Key('field-support-error')), findsNothing);
      await tester.pump(const Duration(seconds: 15));
      expect(fake.calls, hasLength(1));
      fake.unsupported = false;
      await tester.tap(find.text('重新整理回覆'));
      await tester.pump();
      expect(find.text('等待後台接手'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(fake.calls, hasLength(3));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an instruction for another gateway is marked old and cannot be confirmed',
    (tester) async {
      final fake = SupportFake()
        ..data = {
          'state': 'waiting_field',
          'revision': 2,
          'events': [
            {
              'action': 'instruct',
              'role': 'backend',
              'message': '原設備指引',
              'context': {
                'gateway_mac': 'AABBCCDDEEFF',
                'site_id': 50,
                'gateway_id': 1,
              },
            },
          ],
        };
      await showPanel(tester, fake);
      expect(find.textContaining('其他閘道器的協助紀錄'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '已解決'))
            .onPressed,
        isNull,
      );
      expect(fake.calls.where((call) => call.$1 == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'receives instruction, sends explicit revision confirmation, then stops polling on close',
    (tester) async {
      final fake = SupportFake();
      await showPanel(tester, fake);
      expect(find.text('等待後台接手'), findsOneWidget);
      fake.data = {
        'state': 'waiting_field',
        'revision': 2,
        'supported': true,
        'request_at': '2026-10-03T12:00:00+08:00',
        'events': [
          {
            'action': 'instruct',
            'at': '2026-10-03T12:01:00+08:00',
            'step': 6,
            'message': '請核對工單站號',
          },
        ],
      };
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('請核對工單站號'), findsOneWidget);
      await tester.tap(find.text('已解決'));
      await tester.pump();
      expect(fake.calls.last.$3, {
        'expected_revision': 2,
        'action': 'resolved',
      });
      expect(find.text('你已確認解決'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final count = fake.calls.length;
      await tester.pump(const Duration(seconds: 10));
      expect(fake.calls.length, count);
    },
  );

  testWidgets(
    'offline information cannot be confirmed; stale API origin is never called',
    (tester) async {
      final fake = SupportFake()
        ..data = {'state': 'handling', 'revision': 1, 'events': []};
      await showPanel(tester, fake);
      fake.offline = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(const Key('field-support-error')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '已解決'))
            .onPressed,
        isNull,
      );
      fake.offline = false;
      fake.origin = 'https://different.invalid';
      final count = fake.calls.length;
      await tester.tap(find.text('重新整理回覆'));
      await tester.pump();
      expect(fake.calls.length, count);
      expect(find.text('請先連線到目前選擇的後台，再查看協助回覆。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'background pauses polling and a response after disposal is ignored',
    (tester) async {
      final fake = SupportFake();
      await showPanel(tester, fake);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final count = fake.calls.length;
      await tester.pump(const Duration(seconds: 6));
      expect(fake.calls.length, count);
      fake.pending = Completer<Map<String, dynamic>>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      fake.pending!.complete({'state': 'waiting_field', 'revision': 2});
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('English (i18n B2): support state and buttons', (tester) async {
    useLanguage(AppLanguage.en);
    final fake = SupportFake();
    await showPanel(tester, fake);
    expect(find.text('Waiting for the back office'), findsOneWidget);
    expect(find.text('Refresh replies'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
