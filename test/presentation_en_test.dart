// Phase B2（docs/i18n.md §10）：presentation 小檔的英文斷言，以及首頁與
// 「更多」選單在英文下不 overflow（360 dp、字級 1.0／1.3）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/application/android_app_update.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/ios_app_version.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/mqtt_target.dart';
import 'package:gateway_commissioning/core/progress_checklist.dart';
import 'package:gateway_commissioning/core/station_change.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'package:gateway_commissioning/presentation/connection_status_panel.dart';
import 'package:gateway_commissioning/presentation/direct_pick_activity.dart';
import 'package:gateway_commissioning/presentation/field_help_sheet.dart';
import 'package:gateway_commissioning/presentation/gateway_mode_card.dart';
import 'package:gateway_commissioning/presentation/gateway_signal.dart';
import 'package:gateway_commissioning/presentation/heartbeat_activity.dart';
import 'package:gateway_commissioning/presentation/identify_duration_setting.dart';
import 'package:gateway_commissioning/presentation/install_report_panel.dart';
import 'package:gateway_commissioning/presentation/next_action_guide.dart';
import 'package:gateway_commissioning/presentation/progress_checklist.dart';
import 'package:gateway_commissioning/presentation/station_change_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n.dart';

Widget _en(Widget child) => wrapWithL10n(
  Scaffold(body: SingleChildScrollView(child: child)),
  language: AppLanguage.en,
);

void _phone(WidgetTester tester, {double scale = 1}) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('presentation widgets in English', () {
    testWidgets('heartbeat activity', (tester) async {
      useLanguage(AppLanguage.en);
      await tester.pumpWidget(
        _en(
          HeartbeatActivity(
            busy: true,
            checklist: onlineChecklist()
                .done(onlineItemBackend)
                .start(onlineItemBeat1),
          ),
        ),
      );
      expect(find.text('Waiting for heartbeat 1'), findsOneWidget);
      expect(find.text('Heartbeat 0/2'), findsOneWidget);
      expect(find.text('Back office'), findsOneWidget);
    });

    testWidgets('station change progress', (tester) async {
      useLanguage(AppLanguage.en);
      await tester.pumpWidget(
        _en(
          const StationChangeProgress(
            progress: StationChange(
              site: 81,
              gateway: 2,
              stage: StationChangeStage.confirming,
            ),
          ),
        ),
      );
      expect(find.text('Site 81 · Gateway 2'), findsOneWidget);
      expect(
        find.text(
          'Reconnected. Checking the new site ID and Wi-Fi; '
          'it continues by itself when done.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('direct pick activity', (tester) async {
      useLanguage(AppLanguage.en);
      await tester.pumpWidget(
        _en(
          const DirectPickActivity(
            direct: DirectStatus(state: DirectState.scanning),
          ),
        ),
      );
      expect(find.text('Gateway is searching for PTUs'), findsOneWidget);
    });

    testWidgets('upload target switch dialog (connection status panel)', (
      tester,
    ) async {
      useLanguage(AppLanguage.en);
      await tester.pumpWidget(
        wrapWithL10n(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmUploadTargetSwitch(
                context,
                wanted: const MqttTarget.production(),
              ),
              child: const Text('open'),
            ),
          ),
          language: AppLanguage.en,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Switch the gateway too?'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Switch'), findsOneWidget);
    });

    testWidgets('identify duration setting', (tester) async {
      useLanguage(AppLanguage.en);
      final fake = DemoSystem();
      final container = ProviderContainer(
        overrides: [
          linkProvider.overrideWithValue(fake),
          apiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      await container.read(topologyProvider.notifier).ready;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _en(const IdentifyDurationSetting()),
        ),
      );
      expect(find.text('Identify duration'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('identify-seconds-input')),
        '6',
      );
      await tester.tap(find.byKey(const Key('identify-seconds-save')));
      await tester.pumpAndSettle();
      expect(find.text('Saved: 6 s'), findsOneWidget);
    });

    testWidgets('next action hint shows the caption it is given', (
      tester,
    ) async {
      useLanguage(AppLanguage.en);
      await tester.pumpWidget(
        _en(
          NextActionGuide.button(
            hint: 'Check and start',
            caption: nextActionStartCaption,
            child: FilledButton(
              onPressed: () {},
              child: const Text('Check and start'),
            ),
          ),
        ),
      );
      expect(find.text('Start here'), findsOneWidget);
      expect(find.text('Check and start'), findsOneWidget);
    });

    test('texts used outside build follow the language', () {
      useLanguage(AppLanguage.en);
      expect(fieldHelpLabel, 'Ask back office');
      expect(fieldHelpSentText, '✓ Help request reached the back office');
      expect(gatewayLinkLostText, startsWith('The phone lost its Bluetooth'));
      expect(installReportResendLabel, 'Resend');
      expect(gatewayModeResumeHint, startsWith('After resuming'));
      expect(
        ProgressChecklist.noteText(
          const CheckItem('x', 'x', status: CheckStatus.running),
        ),
        'In progress…',
      );
      expect(
        ProgressChecklist.noteText(
          const CheckItem('x', 'x', status: CheckStatus.running, note: '2/5'),
        ),
        'In progress… 2/5',
      );
    });
  });

  group('English layout (360 dp)', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('start page and the ⋮ menu do not overflow at $scale', (
        tester,
      ) async {
        _phone(tester, scale: scale);
        final fake = DemoSystem();
        await pumpApp(
          tester,
          prefs: {'app_locale': 'en'},
          overrides: [
            apiProvider.overrideWithValue(fake),
            linkProvider.overrideWithValue(fake),
            androidUpdateSupportedProvider.overrideWithValue(false),
            iosAppVersionSupportedProvider.overrideWithValue(false),
          ],
        );
        await tester.pumpAndSettle();
        expect(L10n.language, AppLanguage.en);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('topology-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Language'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
