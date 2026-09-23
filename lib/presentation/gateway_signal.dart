import 'dart:async';
import 'package:flutter/material.dart';
import '../data/contracts.dart';
import '../core/protocol.dart';

/// A compact, phone-measured signal row. Scan and stale samples are explicit.
class GatewaySignal extends StatefulWidget {
  const GatewaySignal({
    super.key,
    required this.link,
    required this.peer,
    required this.busy,
  });
  final GatewayLink link;
  final GatewayPeer peer;
  final bool busy;
  @override
  State<GatewaySignal> createState() => _GatewaySignalState();
}

class _GatewaySignalState extends State<GatewaySignal>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _expiry;
  StreamSubscription<bool>? _subscription;
  GatewaySignalSource? _source;
  int? _rssi;
  bool _connected = false, _live = false, _foreground = true, _inFlight = false;
  bool _measured = false;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _attach();
  }

  void _attach() {
    _version++;
    _timer?.cancel();
    _subscription?.cancel();
    _rssi = _valid(widget.peer.rssi) ? widget.peer.rssi : null;
    _expiry?.cancel();
    _live = false;
    _measured = false;
    final link = widget.link;
    _source = link is GatewaySignalSource ? link as GatewaySignalSource : null;
    _connected = _source?.signalConnected ?? false;
    if (_source == null) return;
    _subscription = _source!.signalConnections.listen((connected) {
      if (!mounted) return;
      _version++;
      setState(() {
        _connected = connected;
        _live = false;
      });
    });
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    // Wait until the first frame before publishing the first reading.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _poll();
    });
  }

  static bool _valid(int rssi) => rssi >= -127 && rssi < 0;

  Future<void> _poll() async {
    if (!mounted) return;
    if (!_foreground ||
        widget.busy ||
        !_connected ||
        _inFlight ||
        _source == null) {
      return;
    }
    _inFlight = true;
    final version = _version;
    try {
      final value = await _source!.readSignal();
      if (!mounted || version != _version || !_foreground) return;
      setState(() {
        _live = _valid(value);
        if (_live) {
          _rssi = value;
          _measured = true;
          _expiry?.cancel();
          _expiry = Timer(const Duration(seconds: 15), () {
            if (mounted) setState(() => _live = false);
          });
        }
      });
    } catch (error) {
      if (!mounted || version != _version) return;
      setState(() {
        _live = false;
        if (error is GatewayFailure &&
            ['disconnected', 'not_connected'].contains(error.code)) {
          _connected = false;
        }
      });
    } finally {
      _inFlight = false;
    }
  }

  @override
  void didUpdateWidget(GatewaySignal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.busy && widget.busy) {
      _version++;
      _live = false;
    }
    if (oldWidget.peer.id != widget.peer.id ||
        !identical(oldWidget.link, widget.link)) {
      _attach();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _version++;
    if (mounted) setState(() => _live = false);
    if (_foreground) _poll();
  }

  @override
  void dispose() {
    _version++;
    _expiry?.cancel();
    _timer?.cancel();
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _rssi == null ? '尚無讀值' : '$_rssi dBm';
    final status = _source == null
        ? (widget.link.demo ? '模擬・掃描 $value' : '掃描 $value')
        : !_connected
        ? '已斷線・${_measured ? '上次' : '掃描'} $value'
        : _live
        ? value
        : '${_measured ? '上次' : '掃描'} $value';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '手機 ↔ Gateway：$status',
        key: const Key('gateway-signal'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
