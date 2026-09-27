// 09-28 (field: GC 刪除 56/1, then the same gateway configured again with
// the APP — 確認上線 stayed on 「收到第 1 次心跳 進行中」 forever): the back
// office skips the heartbeats of an archived station (HB_SKIP) and by
// design never restores one by itself. The APP now asks instead of waiting:
// 1. The station page: a number archived for this gateway asks 「這台閘道器
//    之前在後台被移除（封存），要重新加入嗎？」 — 〔重新加入並繼續〕 restores
//    it (PATCH restore, then reserve-identity) and carries on;
//    〔改用其他站號〕 opens the input with nothing sent.
// 2. 確認上線: 60 s without heartbeats and the back office says archived →
//    it stops on that item with the reason and 〔重新加入〕 in the bottom
//    bar (no endless wait); 〔重新加入〕 restores it and the heartbeats come.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/backend_environment.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/local_backend_finder.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/gateway_identity.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/core/progress_checklist.dart';
import 'package:gateway_commissioning/core/protocol.dart';
import 'package:gateway_commissioning/core/rescue_code.dart';
import 'package:gateway_commissioning/data/local_backend_probe.dart';
import 'package:gateway_commissioning/gateway_app.dart';
import 'package:gateway_commissioning/presentation/commissioning_page.dart';

import 'network_check_test.dart' show WifiGateway;

class _Prober implements LocalBackendProber {
  @override
  Future<ProbeResult> probe(Uri base, {Duration? connectTimeout}) async =>
      const ProbeResult(ProbeOutcome.healthy, status: 200);
}

const _path = '/api/gateways/56/1';

/// Gateway 56/1, not in service (GC's archive sent leave_fleet), on Wi-Fi;
/// the back office has 56/1 archived with this gateway's MAC. While
/// archived, fleet-status does not list it (its heartbeats are skipped).
class _ArchivedGateway extends WifiGateway {
  _ArchivedGateway() {
    config.addAll({'site_id': 56, 'gateway_id': 1});
  }

  bool archived = true;

  /// Not archived, but fleet-status has no row for it yet (no heartbeat).
  bool hideRow = false;
  final calls = <String>[];

  int api(String call) => calls.where((c) => c.startsWith(call)).length;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add('$method $path');
    if (path == '$_path/check-identity') {
      return {
        'exists': true,
        'last_seen_mac': config['gateway_uid'],
        'status': 'offline',
        'archived': archived,
      };
    }
    if (path == '$_path/restore') {
      final was = archived;
      archived = false;
      return {
        'success': true,
        'site_id': 56,
        'gateway_id': 1,
        'upload_paused': true,
        'was_archived': was,
        'join_cmd_sent': false,
      };
    }
    if (path.startsWith('$_path/reserve-identity')) {
      return {
        'ok': true,
        'replaced': false,
        'previous_mac': null,
        'archived': archived,
      };
    }
    final result = await super.request(method, path, body);
    if (path.contains('fleet-status') && (archived || hideRow)) {
      return {'mqtt_connected': true, 'gateways': <Object>[]};
    }
    return result;
  }
}

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _ArchivedGateway fake,
) async {
  SharedPreferences.setMockInitialValues({'backend_environment': 'production'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkProvider.overrideWithValue(fake),
        apiProvider.overrideWithValue(fake),
        localBackendProberProvider.overrideWithValue(_Prober()),
        fieldReporterConfigProvider.overrideWithValue(
          const FieldReporterConfig(
            allowDemoLink: true,
            helpWait: Duration(milliseconds: 300),
          ),
        ),
      ],
      child: const GatewayApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GatewayApp)),
  );
  await tester.runAsync(
    () => container.read(backendEnvProvider.notifier).ready,
  );
  await tester.runAsync(() async {
    final topo = container.read(topologyProvider.notifier);
    await topo.ready;
    await topo.setTopology(GatewayTopology.star);
  });
  await tester.runAsync(
    () => container
        .read(commissionProvider.notifier)
        .prepare(container.read(backendEnvProvider).base, 'pw'),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets the controller's run (demo waits are 1 ms) finish.
Future<void> _settleRun(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pump();
  await tester.runAsync(() async {
    for (var i = 0; i < 600; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (!container.read(commissionProvider).busy) break;
    }
  });
  await tester.pumpAndSettle();
}

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('task-title'))).data!;

Finder _bottom(String label) => find.descendant(
  of: find.byKey(const Key('check-next')),
  matching: find.text(label),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the reason on the checklist item and the rescue code', () {
    expect(
      const GatewayFailure('identity_archived').message,
      identityArchivedText,
    );
    expect(
      checklistReason(identityArchivedText),
      '這台閘道器之前在後台被移除（封存），後台不會記錄它的心跳',
    );
    expect(
      rescueCodeOf(
        const GatewayFailure('identity_archived'),
        rebooted: false,
        safe: true,
        ctlStep: 3,
      ),
      RescueCode.gwNotInBackend,
    );
  });

  group('1. the station page', () {
    testWidgets('〔使用此站點〕 on an archived station asks first; '
        '〔重新加入並繼續〕 restores it, then reserves it, and carries on', (
      tester,
    ) async {
      _phoneView(tester);
      final fake = _ArchivedGateway();
      final container = await _pump(tester, fake);
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      expect(_title(tester), '目前站號是 56，這台要配置在本站嗎？');

      await _tap(tester, find.byKey(const Key('station-use')));
      expect(find.byKey(const Key('archived-confirm')), findsOneWidget);
      expect(find.text(archivedConfirmTitle), findsOneWidget);
      expect(find.text(archivedConfirmText(56, 1)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('archived-rejoin')),
          matching: find.text('重新加入並繼續'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('archived-other-site')),
          matching: find.text('改用其他站號'),
        ),
        findsOneWidget,
      );
      // Nothing sent before the answer.
      expect(fake.api('PATCH $_path/restore'), 0);
      expect(fake.api('POST $_path/reserve-identity'), 0);

      await _tap(tester, find.byKey(const Key('archived-rejoin')));
      await _settleRun(tester, container);
      final restore = fake.calls.indexOf('PATCH $_path/restore');
      final reserve = fake.calls.indexWhere(
        (c) => c.startsWith('POST $_path/reserve-identity?mac=AABBCCDDEEFF'),
      );
      expect(restore, greaterThanOrEqualTo(0));
      expect(reserve, greaterThan(restore), reason: 'restore, then reserve');
      expect(fake.api('PATCH $_path/restore'), 1);
      expect(fake.archived, isFalse);
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.identityArchived, isFalse);
      // Carried on: saved with the kept Wi-Fi, then 確認上線 got the
      // heartbeats (the station is listed again).
      expect(s.step, 4);
      expect(s.online, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('〔改用其他站號〕 opens the input; nothing is sent', (tester) async {
      _phoneView(tester);
      final fake = _ArchivedGateway();
      final container = await _pump(tester, fake);
      await _tap(tester, find.byKey(const ValueKey('demo-gateway')));
      await _tap(tester, find.byKey(const Key('station-use')));
      await _tap(tester, find.byKey(const Key('archived-other-site')));

      expect(find.byKey(const Key('archived-confirm')), findsNothing);
      expect(_title(tester), stationInputTitle);
      expect(find.widgetWithText(TextField, siteFieldLabel), findsOneWidget);
      expect(fake.api('PATCH $_path/restore'), 0);
      expect(fake.api('POST $_path/reserve-identity'), 0);
      expect(fake.count('set_site_identity'), 0);
      expect(fake.archived, isTrue);
      expect(container.read(commissionProvider).step, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('2. 確認上線', () {
    testWidgets('no heartbeats for 60 s and the station archived: stops on '
        '收到第 1 次心跳 with the reason and 〔重新加入〕 (no endless wait); '
        '〔重新加入〕 restores it and the heartbeats come', (tester) async {
      _phoneView(tester);
      final fake = _ArchivedGateway();
      final container = await _pump(tester, fake);
      final c = container.read(commissionProvider.notifier);
      // Saved without the station page's question (e.g. an older APP).
      await tester.runAsync(() async {
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.configureWifi(56, 1, 'test', 'test-password');
      });
      expect(container.read(commissionProvider).step, 3);
      final start = fake.calls.length;
      // The page starts 確認上線 by itself.
      await _settleRun(tester, container);

      var s = container.read(commissionProvider);
      expect(s.step, 3);
      expect(s.identityArchived, isTrue);
      expect(s.error, identityArchivedText);
      final during = fake.calls.sublist(start);
      final firstCheck = during.indexOf('GET $_path/check-identity');
      expect(firstCheck, greaterThanOrEqualTo(0));
      // Asked after 60 s of waits (12 reads at 5 s), not at once and not
      // only at the 90 s timeout.
      expect(
        during
            .sublist(0, firstCheck)
            .where((c) => c.contains('fleet-status'))
            .length,
        12,
      );
      expect(during.where((c) => c.contains('fleet-status')).length, 12);
      final list = s.checklist!;
      expect(list.isDone(onlineItemBackend), isTrue);
      expect(list.item(onlineItemBeat1)!.status, CheckStatus.failed);
      expect(
        list.item(onlineItemBeat1)!.note,
        checklistReason(identityArchivedText),
      );
      expect(list.running, isFalse);
      expect(fake.api('PATCH $_path/restore'), 0, reason: 'not by itself');

      expect(find.byKey(const Key('error-banner')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(rejoinHintText),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(rejoinHintText), findsOneWidget);
      expect(_bottom(rejoinLabel), findsOneWidget);
      expect(_bottom(confirmOnlineLabel), findsNothing);

      await tester.tap(find.byKey(const Key('check-next')));
      await _settleRun(tester, container);
      s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(s.identityArchived, isFalse);
      expect(s.step, 4);
      expect(s.online, isTrue);
      expect(fake.api('PATCH $_path/restore'), 1);
      final restore = fake.calls.indexOf('PATCH $_path/restore');
      expect(
        fake.calls.indexWhere(
          (c) => c.startsWith('POST $_path/reserve-identity'),
          restore,
        ),
        greaterThan(restore),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a station that is not archived keeps waiting as before '
        '(the 90 s timeout, 〔確認閘道器上線〕 to retry)', (tester) async {
      _phoneView(tester);
      final fake = _ArchivedGateway();
      final container = await _pump(tester, fake);
      final c = container.read(commissionProvider.notifier);
      await tester.runAsync(() async {
        await c.scan();
        await c.connect(container.read(commissionProvider).peers.single);
        await c.configureWifi(56, 1, 'test', 'test-password');
      });
      // In the fleet (not archived) but no heartbeat listed.
      fake
        ..archived = false
        ..hideRow = true;
      final start = fake.calls.length;
      await _settleRun(tester, container);
      final s = container.read(commissionProvider);
      expect(s.step, 3);
      expect(s.identityArchived, isFalse);
      expect(s.error, isNot(identityArchivedText));
      final during = fake.calls.sublist(start);
      expect(during.where((c) => c.contains('fleet-status')).length, 18);
      expect(during.where((c) => c.endsWith('/check-identity')).length, 1);
      expect(_bottom(confirmOnlineLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
