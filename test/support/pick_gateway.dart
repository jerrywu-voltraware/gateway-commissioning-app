// 1.0.0+14: on the gateway list a card's tap only selects the gateway; the
// fixed bottom button 〔連線到 …〕 (`GatewayConnectBar`) connects to it.
// Tests that tapped the card to connect now tap the card, then the button —
// each through the test's own tap routine (scroll into view, tap, settle).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gateway list's fixed bottom button.
Finder get gatewayConnectButton => find.byKey(const Key('gateway-connect'));

/// Selects the gateway [card] (its row, e.g. `ValueKey('demo-gateway')`) and
/// connects to it from the bottom button, both taps through [tap].
Future<void> pickGateway(
  Future<void> Function(Finder finder) tap,
  Finder card,
) async {
  await tap(card);
  await tap(gatewayConnectButton);
}
