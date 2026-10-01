// Gateway selection has three explicit steps: select a card, connect its BLE
// link for identification, then continue into commissioning from the bottom bar.
// Run every step through the test's tap routine (scroll, tap, settle).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gateway list's fixed bottom commissioning button.
Finder get gatewayConnectButton => find.byKey(const Key('gateway-connect'));

/// Selects [card], establishes its BLE link, then starts commissioning.
Future<void> pickGateway(
  Future<void> Function(Finder finder) tap,
  Finder card,
) async {
  await tap(card);
  await tap(find.byKey(const Key('gateway-link-identify')));
  await tap(gatewayConnectButton);
}
