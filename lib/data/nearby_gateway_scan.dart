/// 1.0.0+7 「閘道器狀態」 → 「附近閘道器（藍牙掃描）」: a short Bluetooth
/// scan for gateways (`GIOS-S{site}-GW{nn}` advertisements, the same filter
/// as the flow's step-2 search) that never connects, never pairs and never
/// touches the commissioning state — the installer taps a row to open that
/// gateway's recent data.
///
/// Permissions and the adapter state come from the link's own
/// [GatewayLink.prepare] (`permission` / `location_off` / `bluetooth_off`
/// failures, the flow's texts). The flow's live scan, if one is still
/// running under this page, is stopped first so the two never fight over
/// the one adapter scan; the flow's own state is not touched.
library;

import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'contracts.dart';

/// How long one scan listens.
const nearbyScanWindow = Duration(seconds: 8);

abstract class NearbyGatewayScanner {
  /// Gateways heard within [window] (strongest first). [stop] (optional)
  /// ends the scan early — the page completes it when it is left.
  Future<List<GatewayPeer>> scanNearby({
    Duration window = nearbyScanWindow,
    Future<void>? stop,
  });
}

/// The phone's Bluetooth through universal_ble, as the link itself scans.
class BleNearbyScanner implements NearbyGatewayScanner {
  BleNearbyScanner(this._link);
  final GatewayLink _link;

  @override
  Future<List<GatewayPeer>> scanNearby({
    Duration window = nearbyScanWindow,
    Future<void>? stop,
  }) async {
    await _link.prepare();
    if (_link is GatewayScanner) await (_link as GatewayScanner).stopScan();
    final found = <String, GatewayPeer>{};
    final sub = UniversalBle.scanStream.listen((result) {
      final name = result.name ?? '';
      if (!name.startsWith('GIOS-S')) return;
      found[result.deviceId] = GatewayPeer(
        result.deviceId,
        name,
        result.rssi ?? -127,
      );
    });
    try {
      await UniversalBle.startScan();
      await Future.any([Future<void>.delayed(window), ?stop]);
    } finally {
      await UniversalBle.stopScan();
      await sub.cancel();
    }
    return sortNearby(found.values);
  }
}

/// A link that cannot scan on its own adapter (the demo system): its
/// one-shot [GatewayLink.scan].
class LinkNearbyScanner implements NearbyGatewayScanner {
  LinkNearbyScanner(this._link);
  final GatewayLink _link;

  @override
  Future<List<GatewayPeer>> scanNearby({
    Duration window = nearbyScanWindow,
    Future<void>? stop,
  }) async => sortNearby(await _link.scan());
}

/// Strongest signal first.
List<GatewayPeer> sortNearby(Iterable<GatewayPeer> peers) =>
    peers.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
