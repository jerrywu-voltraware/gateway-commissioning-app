/// Round 24 (field round 24: a help queued while the phone was offline
/// reached the backend 54.5 s after the network came back — the outbox's
/// back-off had grown to 60 s): the phone's default network, as Android's
/// ConnectivityManager reports it (MainActivity, channel
/// `voltraware/network`), so the field rescue outbox is sent the moment the
/// network is back instead of at its next timed retry.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A default network is connected (it may not reach anywhere yet).
const networkAvailableEvent = 'available';

/// Android checked that the default network reaches the internet.
const networkValidatedEvent = 'validated';

/// The default network is gone.
const networkLostEvent = 'lost';

/// Whether [event] means the phone (probably) has a network again.
bool isNetworkBackEvent(Object? event) =>
    event == networkAvailableEvent || event == networkValidatedEvent;

const _channel = EventChannel('voltraware/network');

/// The phone's network changes ([networkAvailableEvent],
/// [networkValidatedEvent], [networkLostEvent]); empty off Android (tests,
/// desktop). Errors of the platform side are swallowed: the outbox's timed
/// retry still runs without it.
Stream<String> phoneNetworkEvents() {
  if (kIsWeb || !Platform.isAndroid) return const Stream<String>.empty();
  try {
    return _channel
        .receiveBroadcastStream()
        .map((event) => event.toString())
        .handleError((Object _) {});
  } catch (_) {
    return const Stream<String>.empty();
  }
}
