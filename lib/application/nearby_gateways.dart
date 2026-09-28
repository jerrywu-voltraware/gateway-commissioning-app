/// 1.0.0+7: the scanner behind 「閘道器狀態」's 「附近閘道器（藍牙掃描）」
/// ([NearbyGatewayScanner]): the phone's adapter for the real link, the
/// demo link's own list in 練習模式. Tests override the provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/nearby_gateway_scan.dart';
import 'commissioning_controller.dart' show linkProvider;

final nearbyScannerProvider = Provider<NearbyGatewayScanner>((ref) {
  final link = ref.watch(linkProvider);
  return link.demo ? LinkNearbyScanner(link) : BleNearbyScanner(link);
});
