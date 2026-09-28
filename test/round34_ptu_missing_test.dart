// r34: after commissioning, this pile's PTU is broken or taken away.
// Reconnecting the gateway (in service, one-to-one, bound) at step 2 shows
// the PTU-missing card when the bound PTU is not connected: 〔更換 PTU〕
// clears the binding and goes to step 7 on the current station,
// 〔PTU 已上電，重新檢查〕 turns the card green once it is connected. A
// bound PTU that is connected, or no binding at all, shows no such card.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/commissioning_controller.dart';
import 'package:gateway_commissioning/application/field_report.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';
import 'package:gateway_commissioning/core/direct_mode.dart';
import 'package:gateway_commissioning/core/gateway_topology.dart';
import 'package:gateway_commissioning/data/contracts.dart';

import 'round15_direct_flow_test.dart' show PickGateway;

/// The demo's first PTU: this pile's, bound to the gateway.
const _ownPtu = 'AA:BB:CC:00:00:01';

/// A gateway in service, one-to-one, bound to [_ownPtu]; [present] false
/// removes that PTU (broken / taken away) so `get_status.direct.state` is
/// `bound_missing`. Field reports are recorded in [reports].
class _BoundGateway extends PickGateway implements SessionInfo {
  _BoundGateway({bool present = true, String? bound = _ownPtu}) {
    config['max_connections'] = 1;
    config['direct_bind_mac'] = bound ?? '';
    if (!present) devices.removeWhere((d) => d['mac'] == _ownPtu);
  }

  final reports = <Map<String, dynamic>>[];

  @override
  bool get hasSession => true;

  @override
  String? get origin => 'https://example.invalid';

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == fieldSessionsPath) {
      reports.add(Map<String, dynamic>.from(body ?? const {}));
      return {'ok': true};
    }
    return super.request(method, path, body);
  }

  /// The PTU is powered again (heard and connected next window).
  void powerOwnPtu() => devices.insert(0, <String, dynamic>{
    'mac': _ownPtu,
    'rssi': -40,
    'device_number': directPtuId,
    'connected': false,
    'notify_enabled': false,
    'zombie': false,
    'last_data_age_sec': 0,
  });
}

Future<(ProviderContainer, CommissioningController)> _connected(
  _BoundGateway fake,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      linkProvider.overrideWithValue(fake),
      apiProvider.overrideWithValue(fake),
      fieldReporterConfigProvider.overrideWithValue(
        const FieldReporterConfig(allowDemoLink: true),
      ),
    ],
  );
  final topo = container.read(topologyProvider.notifier);
  await topo.ready;
  await topo.setTopology(GatewayTopology.direct);
  final c = container.read(commissionProvider.notifier);
  await c.prepare('https://example.invalid', '', offline: true);
  await c.scan();
  await c.connect(container.read(commissionProvider).peers.single);
  return (container, c);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('r34 PTU-missing card', () {
    test('bound and the PTU not connected: the card shows and is reported',
        () async {
      final fake = _BoundGateway(present: false);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.ptuMissingMac, _ownPtu);
      expect(s.ptuMissingBack, isFalse);
      expect(s.bindLaterMac, isNull);
      expect(ptuMissingTitle(_ownPtu), contains('0001'));
      await _settle();
      final report = fake.reports.firstWhere(
        (r) => r['error_message'] == ptuMissingReportText(_ownPtu),
        orElse: () => const {},
      );
      expect(report['event'], 'status');
      // Re-check without the PTU: the card stays red.
      await c.recheckBoundPtu();
      expect(container.read(commissionProvider).ptuMissingBack, isFalse);
      // The PTU powered: the re-check turns the card green.
      fake.powerOwnPtu();
      await c.recheckBoundPtu();
      final after = container.read(commissionProvider);
      expect(after.ptuMissingMac, _ownPtu);
      expect(after.ptuMissingBack, isTrue);
      expect(after.error, isNull);
    });

    test('bound and the PTU connected: no card', () async {
      final fake = _BoundGateway();
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.ptuMissingMac, isNull);
      expect(s.bindLaterMac, isNull);
      expect(
        fake.reports.any(
          (r) => r['error_message'] == ptuMissingReportText(_ownPtu),
        ),
        isFalse,
      );
    });

    test('unbound: the bind-later path as before, no PTU-missing card',
        () async {
      final fake = _BoundGateway(bound: null);
      final (container, _) = await _connected(fake);
      addTearDown(container.dispose);
      final s = container.read(commissionProvider);
      expect(s.step, 2);
      expect(s.ptuMissingMac, isNull);
      // The gateway's own pick (the strongest PTU in the demo).
      expect(s.bindLaterMac, isNotNull);
    });

    test('〔更換 PTU〕 clears the binding and goes to step 7 on the station',
        () async {
      final fake = _BoundGateway(present: false);
      final (container, c) = await _connected(fake);
      addTearDown(container.dispose);
      await c.passNetworkCheck(skip: true);
      await c.replaceBoundPtu();
      final s = container.read(commissionProvider);
      expect(s.error, isNull);
      expect(fake.config['direct_bind_mac'], '');
      expect(fake.sent('set_config').last, {'direct_bind_mac': ''});
      expect(fake.sent('set_site_identity'), isEmpty);
      expect(s.ptuMissingMac, isNull);
      expect(s.step, 4);
      expect(s.config['choose_station'], false);
      expect(s.config['new_station'], false);
    });
  });

  test('the card texts name the bound MAC', () {
    expect(macTail4('90:5F:E8:9A:96:00'), '9600');
    expect(ptuBackTitle(_ownPtu), contains(_ownPtu));
    expect(replacePtuConfirmText(_ownPtu), contains(_ownPtu));
    expect(ptuMissingHint, contains(replacePtuLabel));
  });
}
