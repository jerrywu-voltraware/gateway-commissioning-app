import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/identify.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/data/demo_system.dart';
import 'package:gateway_commissioning/presentation/identify_duration_setting.dart';

ProviderContainer _container(DemoSystem fake) => ProviderContainer(
  overrides: [
    linkProvider.overrideWithValue(fake),
    apiProvider.overrideWithValue(fake),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('seconds input accepts only integers in the byte range', () {
    for (final value in ['', '-1', '1.5', '256', '65536', 'NaN', '+1']) {
      expect(parseIdentifySeconds(value), isNull, reason: value);
    }
    for (final seconds in [0, 1, 5, 6, 255]) {
      expect(parseIdentifySeconds(' $seconds '), seconds);
    }
  });

  test(
    'default 6; persisted 0, 1, 5, 255 survive reopening unchanged',
    () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      final settings = first.read(topologyProvider.notifier);
      await settings.ready;
      expect(first.read(topologyProvider).identifySeconds, 6);
      for (final seconds in [0, 1, 5, 255]) {
        await settings.setIdentifySeconds(seconds);
        final reopened = ProviderContainer();
        await reopened.read(topologyProvider.notifier).ready;
        expect(reopened.read(topologyProvider).identifySeconds, seconds);
        reopened.dispose();
      }
      for (final invalid in [-1, 256]) {
        await expectLater(
          settings.setIdentifySeconds(invalid),
          throwsRangeError,
        );
      }
      expect(first.read(topologyProvider).identifySeconds, 255);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          identifySecondsPreference,
        ),
        255,
      );
    },
  );

  test('corrupt persisted values use default, never wrap or clamp', () async {
    for (final value in [-1, 256, 1.5, '5', true]) {
      SharedPreferences.setMockInitialValues({
        identifySecondsPreference: value,
      });
      final container = ProviderContainer();
      await container.read(topologyProvider.notifier).ready;
      expect(container.read(topologyProvider).identifySeconds, 6);
      container.dispose();
    }
  });

  test('legacy gateways have explicit limits; no silent duration change', () {
    const oldPtu = {'identify_ptu_supported': true};
    expect(identifyCommandParams(oldPtu, 1), {
      'target': 'both',
      'duration_ms': 1000,
    });
    expect(identifyCommandParams(oldPtu, 30), {
      'target': 'both',
      'duration_ms': 30000,
    });
    expect(identifyCommandParams({}, 6), isEmpty);
    for (final seconds in [0, 31, 255]) {
      expect(
        () => identifyCommandParams(oldPtu, seconds),
        throwsA(isA<GatewayFailure>()),
      );
    }
    expect(() => identifyCommandParams({}, 5), throwsA(isA<GatewayFailure>()));
    expect(
      () => identifyCommandParams(oldPtu, 256),
      throwsA(isA<GatewayFailure>()),
    );
  });

  for (final seconds in [0, 1, 5, 6, 255]) {
    test(
      'both identify entrypoints send saved $seconds seconds without selecting or binding',
      () async {
        SharedPreferences.setMockInitialValues({
          identifySecondsPreference: seconds,
        });
        final fake = DemoSystem();
        final container = _container(fake);
        addTearDown(container.dispose);
        final c = container.read(commissionProvider.notifier);
        await c.prepare('https://example.invalid', '', offline: true);
        await c.scan();
        final before = container.read(commissionProvider);
        final peer = before.peers.single;
        expect(await c.identifyPeer(peer), isTrue);
        expect(container.read(commissionProvider).peer, isNull);
        expect(container.read(commissionProvider).step, before.step);
        expect(container.read(commissionProvider).selected, before.selected);
        await c.connect(peer);
        await c.identify();
        expect(container.read(commissionProvider).error, isNull);
        expect(fake.identifyRequests, [
          {'target': 'both', 'duration_ms': seconds * 1000},
          {'target': 'both', 'duration_ms': seconds * 1000},
        ]);
        expect(fake.config['direct_bind_mac'], isEmpty);
      },
    );
  }

  test(
    'legacy unsupported seconds fail before either entrypoint sends identify',
    () async {
      SharedPreferences.setMockInitialValues({identifySecondsPreference: 0});
      final fake = DemoSystem()..config.remove('identify_ptu_protocol');
      final container = _container(fake);
      addTearDown(container.dispose);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      final peer = container.read(commissionProvider).peers.single;
      expect(await c.identifyPeer(peer), isFalse);
      expect(fake.identifyRequests, isEmpty);
      await c.connect(peer);
      await c.identify();
      expect(fake.identifyRequests, isEmpty);
      expect(container.read(commissionProvider).error, contains('秒數'));
    },
  );

  test(
    'zero does not establish identification; saving duration preserves selection',
    () async {
      final fake = DemoSystem()
        ..config.addAll({'fleet_joined': true, 'site_id': 80, 'gateway_id': 3});
      final container = _container(fake);
      addTearDown(container.dispose);
      final settings = container.read(topologyProvider.notifier);
      await settings.ready;
      await settings.setTopology(GatewayTopology.direct);
      final c = container.read(commissionProvider.notifier);
      await c.prepare('https://example.invalid', '', offline: true);
      await c.scan();
      await c.connect(container.read(commissionProvider).peers.single);
      await c.chooseStation(newStation: false);
      final selection = container.read(commissionProvider).selected;
      expect(selection, isNotEmpty);
      final bound = fake.config['direct_bind_mac'];
      await settings.setIdentifySeconds(0);
      expect(container.read(commissionProvider).selected, selection);
      await c.identify();
      expect(container.read(commissionProvider).identifiedMac, isNull);
      expect(container.read(commissionProvider).identifyNote, contains('關燈'));
      expect(container.read(commissionProvider).selected, selection);
      expect(fake.config['direct_bind_mac'], bound);
    },
  );

  test('no-reply acknowledgements never report confirmation or timeout', () {
    const ack = {
      'target': 'both', 'duration_ms': 255000, 'ptu_duration_s': 255,
      'gateway_led': 'ok', 'ptu_write': 'ok', 'mac': 'AA:BB:CC:00:00:01',
      'identify_ptu_protocol': 'a2_seconds', 'ptu_reply_expected': false,
      // Stale legacy keys must not override the advertised new protocol.
      'ptu_confirmed': true, 'ptu_confirm': 'timeout',
    };
    expect(identifyConfirmOf(ack), IdentifyConfirm.sent);
    expect(identifyAckText(ack), contains('255 秒'));
    for (final text in [
      identifyLineText(ack),
      identifyAckText(ack),
      remoteIdentifyText(ack),
    ]) {
      expect(text, contains('已送出'));
      for (final misleading in ['已確認', '逾時', '未支援', '正在閃燈']) {
        expect(text, isNot(contains(misleading)));
      }
    }
    expect(identifyAckText({...ack, 'target': 'ptu'}), contains('閘道器燈號未變更'));
    expect(identifyAckText({...ack, 'duration_ms': 0}), contains('恢復正常'));
    expect(
      remoteIdentifyHeadText({
        ...ack,
        'duration_ms': 0,
        'ptu_write': 'not_connected',
      }),
      isNot(contains('已送出關燈')),
    );
  });

  testWidgets(
    'inline setting validates, persists and restores without hardware command',
    (tester) async {
      final fake = DemoSystem();
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(topologyProvider.notifier).ready;
      Widget setting() => UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: IdentifyDurationSetting()),
          ),
        ),
      );
      await tester.pumpWidget(setting());
      final input = find.byKey(const Key('identify-seconds-input'));
      final save = find.byKey(const Key('identify-seconds-save'));
      expect(tester.widget<TextFormField>(input).controller!.text, '6');
      for (final invalid in ['-1', '1.5', '256', '']) {
        await tester.enterText(input, invalid);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text(identifySecondsError), findsOneWidget);
        expect(container.read(topologyProvider).identifySeconds, 6);
      }
      await tester.enterText(input, '0');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(container.read(topologyProvider).identifySeconds, 0);
      expect(find.text(identifySecondsError), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(setting());
      expect(tester.widget<TextFormField>(input).controller!.text, '0');
      expect(fake.identifyRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
