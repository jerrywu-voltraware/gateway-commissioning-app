// Explicitly select a card, connect its BLE link, then start commissioning
// from that same card. Every step uses the caller's scroll/tap/settle routine.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Finder gatewayStartButtonFor(String peerId) =>
    find.byKey(ValueKey('gateway-start-$peerId'));

bool _keyStartsWith(Widget widget, String prefix) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith(prefix);
}

/// Compatibility for callers that already selected and connected a card.
/// Resolve that card's start control, never whichever button happens to enable.
Finder get gatewayConnectButton => find.descendant(
  of: find.ancestor(
    of: find.byWidgetPredicate(
      (widget) => _keyStartsWith(widget, 'gateway-selected-'),
    ),
    matching: find.byWidgetPredicate(
      (widget) => _keyStartsWith(widget, 'gateway-card-'),
    ),
  ),
  matching: find.byWidgetPredicate(
    (widget) => _keyStartsWith(widget, 'gateway-start-'),
  ),
);

Future<void> pickGateway(
  Future<void> Function(Finder finder) tap,
  Finder card,
) async {
  final key = card.evaluate().single.widget.key;
  if (key is! ValueKey<String>) {
    throw StateError('pickGateway requires the exact peer card ValueKey.');
  }
  final peerId = key.value;
  await tap(card);
  await tap(find.byKey(const Key('gateway-link-identify')));
  await tap(gatewayStartButtonFor(peerId));
}
