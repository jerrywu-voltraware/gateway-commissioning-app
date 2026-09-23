import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/local_backend_address.dart';
import '../data/local_backend_probe.dart';

final localBackendProberProvider = Provider<LocalBackendProber>(
  (ref) => const HttpLocalBackendProber(),
);

/// Returns the phone's Wi-Fi IPv4; injectable so tests never touch the OS.
final phoneIpv4Provider = Provider<Future<String?> Function()>(
  (ref) => phoneWifiIpv4,
);

class ScanCancel {
  final _done = Completer<void>();
  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

class FoundBackend {
  const FoundBackend(this.host, this.result);
  final String host;
  final ProbeResult result;
  bool get healthy => result.outcome == ProbeOutcome.healthy;
}

class ScanResult {
  const ScanResult(this.found, {this.cancelled = false, this.timedOut = false});
  final List<FoundBackend> found;
  final bool cancelled, timedOut;
}

/// Probes hosts with bounded concurrency and an overall deadline.
class LocalBackendFinder {
  LocalBackendFinder(
    this.prober, {
    this.concurrency = 32,
    this.probeTimeout = const Duration(milliseconds: 700),
    this.totalTimeout = const Duration(seconds: 10),
  });
  final LocalBackendProber prober;
  final int concurrency;
  final Duration probeTimeout, totalTimeout;

  Future<ScanResult> find(
    List<String> hosts, {
    int port = defaultLocalPort,
    ScanCancel? cancel,
    void Function(String host, int done, int total)? onProgress,
  }) async {
    final found = <FoundBackend>[];
    var next = 0, done = 0;
    var stopped = false, timedOut = false;
    Future<void> worker() async {
      while (!stopped && next < hosts.length) {
        final host = hosts[next++];
        onProgress?.call(host, done, hosts.length);
        ProbeResult result;
        try {
          result = await prober
              .probe(
                Uri.parse(composeLocalUrl(host, port)),
                connectTimeout: probeTimeout,
              )
              .timeout(probeTimeout * 3);
        } catch (_) {
          result = const ProbeResult(ProbeOutcome.timeout);
        }
        done++;
        if (!stopped && result.isBackend) found.add(FoundBackend(host, result));
      }
    }

    final deadline = Completer<void>();
    final timer = Timer(totalTimeout, () {
      timedOut = true;
      if (!deadline.isCompleted) deadline.complete();
    });
    try {
      await Future.any([
        Future.wait([
          for (
            var i = 0;
            i < concurrency.clamp(1, hosts.isEmpty ? 1 : hosts.length);
            i++
          )
            worker(),
        ]),
        deadline.future,
        ?cancel?.whenCancelled,
      ]);
    } finally {
      stopped = true;
      timer.cancel();
    }
    found.sort((a, b) => _order(a.host).compareTo(_order(b.host)));
    return ScanResult(
      List.unmodifiable(found),
      cancelled: cancel?.cancelled ?? false,
      timedOut: timedOut && !(cancel?.cancelled ?? false),
    );
  }

  static int _order(String host) =>
      (parseIpv4(host) ?? const [0, 0, 0, 0]).fold(0, (a, b) => a * 256 + b);
}
