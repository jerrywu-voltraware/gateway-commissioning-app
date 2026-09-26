import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../core/gateway_identity.dart';
import '../core/protocol.dart';
import '../data/contracts.dart';
import '../data/recent_gateways.dart';

class GatewayDiscovery extends ConsumerStatefulWidget {
  const GatewayDiscovery({
    super.key,
    required this.enabled,
    required this.onConnect,
    this.onIdentify,
  });
  final bool enabled;
  final Future<void> Function(GatewayPeer) onConnect;

  /// 「辨識」 on a row: connect to it (the link stays open and the flow
  /// continues) and blink it. Null hides the button.
  final Future<void> Function(GatewayPeer)? onIdentify;
  @override
  ConsumerState<GatewayDiscovery> createState() => _GatewayDiscoveryState();
}

class _GatewayDiscoveryState extends ConsumerState<GatewayDiscovery>
    with WidgetsBindingObserver {
  List<RecentGateway> _recent = [];
  List<GatewayPeer> _found = [];
  String _query = "";
  final _order = <String, int>{};
  List<dynamic> _fleet = [];
  DateTime? _backendAt;
  String? _error;
  bool _scanning = false, _selecting = false;
  int _epoch = 0, _backendEpoch = 0;
  StreamSubscription<List<GatewayPeer>>? _scan;
  GatewayLink? _activeLink;
  Timer? _refresh;
  Future<void>? _stopping;
  bool _background = false;
  int _lifecycleEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadBackend();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _epoch++;
    _backendEpoch++;
    unawaited(_scan?.cancel());
    final link = _activeLink;
    if (link is GatewayScanner) unawaited((link as GatewayScanner).stopScan());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission/adapter dialogs can be inactive without leaving the app.
    if (state == AppLifecycleState.inactive) return;
    final lifecycle = ++_lifecycleEpoch;
    if (state != AppLifecycleState.resumed) {
      _background = true;
      unawaited(_stop());
      _backendEpoch++;
      setState(() {
        _found = [];
        _fleet = [];
        _backendAt = null;
      });
      _refresh?.cancel();
    } else if (_background) {
      _background = false;
      unawaited(() async {
        await _stopping;
        if (!mounted || _background || lifecycle != _lifecycleEpoch) return;
        _refresh?.cancel();
        _refresh = Timer.periodic(
          const Duration(seconds: 15),
          (_) => _loadBackend(),
        );
        if (widget.enabled && !_selecting) await _start();
      }());
    }
  }

  Future<void> _loadBackend() async {
    final epoch = ++_backendEpoch;
    if (!ref.read(commissionProvider).loggedIn) {
      if (mounted) {
        setState(() {
          _fleet = [];
          _backendAt = null;
        });
      }
      return;
    }
    final base = ref.read(backendEnvProvider).base;
    try {
      final result = await ref
          .read(apiProvider)
          .request('GET', '/api/gateways/fleet-status')
          .timeout(const Duration(seconds: 8));
      if (!mounted ||
          epoch != _backendEpoch ||
          base != ref.read(backendEnvProvider).base ||
          !ref.read(commissionProvider).loggedIn) {
        return;
      }
      setState(() {
        _fleet = result['gateways'] as List? ?? [];
        _backendAt = DateTime.now();
      });
    } catch (_) {
      if (mounted && epoch == _backendEpoch) {
        setState(() {
          _fleet = [];
          _backendAt = null;
        });
      }
    }
  }

  Future<void> _stop() async {
    if (_stopping != null) return _stopping;
    final stopping = () async {
      _epoch++;
      final link = _activeLink;
      if (link is GatewayScanner) await (link as GatewayScanner).stopScan();
      await _scan?.cancel();
      _scan = null;
      if (mounted) setState(() => _scanning = false);
    }();
    _stopping = stopping;
    try {
      await stopping;
    } finally {
      _stopping = null;
    }
  }

  Future<void> _start() async {
    if (!widget.enabled ||
        _scanning ||
        _selecting ||
        _background ||
        _stopping != null) {
      return;
    }
    final epoch = ++_epoch;
    final link = ref.read(linkProvider);
    _activeLink = link;
    setState(() {
      _scanning = true;
      _found = [];
      _error = null;
    });
    unawaited(_loadBackend());
    final recent = await RecentGateways.load(link.demo);
    if (!mounted || epoch != _epoch) return;
    setState(() => _recent = recent);
    void update(List<GatewayPeer> peers) {
      if (mounted && epoch == _epoch) {
        // Round 26: gateways heard here are never PTUs (another gateway's
        // advertisement was listed and picked as one in the field).
        ref.read(commissionProvider.notifier).noteGatewayPeers(peers);
        for (final peer in peers) {
          _order.putIfAbsent(peer.id, () => _order.length);
        }
        setState(
          () =>
              _found = [...peers]
                ..sort((a, b) => _order[a.id]!.compareTo(_order[b.id]!)),
        );
      }
    }

    void failure(Object error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = error is GatewayFailure
            ? error.message
            : '搜尋失敗，請確認藍牙、定位與附近裝置權限後重試。';
      });
    }

    if (link is GatewayScanner) {
      _scan = (link as GatewayScanner).scanLive().listen(
        update,
        onError: failure,
        onDone: () {
          if (mounted && epoch == _epoch) setState(() => _scanning = false);
        },
      );
    } else {
      try {
        update(await link.scan());
      } catch (error) {
        failure(error);
      }
      if (mounted && epoch == _epoch) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(GatewayPeer peer, {bool identify = false}) async {
    if (_selecting || !widget.enabled) return;
    setState(() => _selecting = true);
    try {
      await _stop();
      final action = identify ? widget.onIdentify : widget.onConnect;
      if (mounted && action != null) await action(peer);
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Widget _tile(GatewayPeer peer, {RecentGateway? recent}) {
    final found = _found.where((p) => p.id == peer.id).firstOrNull;
    final last =
        recent ?? _recent.where((r) => r.peer.id == peer.id).firstOrNull;
    final status = !ref.watch(commissionProvider).loggedIn
        ? '後端狀態未知・尚未登入'
        : _backendAt == null ||
              DateTime.now().difference(_backendAt!).inSeconds > 30
        ? '後端狀態未知・尚未取得最新資料'
        : backendPresence(last?.uid, _fleet);
    final signal = found == null
        ? '未收到廣播'
        : found.rssi <= -127
        ? '訊號未知'
        : '${found.rssi} dBm';
    // Round 26 (field: two gateways both read 「GIOS-S80-G…」): 「站 80 ·
    // 閘道器 2」 as the title, the advertised name (the live one: a recent
    // entry keeps the name it had) and the MAC tail below — nothing cut,
    // long text wraps.
    final name = found?.name ?? peer.name;
    final title = gatewayTitle(name);
    final tail = macTailText(peer.id);
    final theme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        key: ValueKey(peer.id),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                key: ValueKey('gateway-title-${peer.id}'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            Text(signal, style: theme.labelMedium),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [if (title != name) Text(name), Text(tail ?? peer.id)],
            ),
            Text(status),
          ],
        ),
        trailing: widget.onIdentify == null
            ? null
            : TextButton(
                key: ValueKey('identify-${peer.id}'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                onPressed: widget.enabled && !_selecting
                    ? () => _connect(found ?? peer, identify: true)
                    : null,
                child: const Text('辨識'),
              ),
        onTap: widget.enabled && !_selecting
            ? () => _connect(found ?? peer)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(backendEnvProvider, (_, next) {
      _backendEpoch++;
      setState(() {
        _fleet = [];
        _backendAt = null;
      });
    });
    final recentIds = _recent.map((r) => r.peer.id).toSet();
    bool matches(GatewayPeer peer) =>
        '${peer.name} ${gatewayTitle(peer.name)} ${peer.id}'
            .toLowerCase()
            .contains(_query);
    final recent = _recent.where((r) => matches(r.peer)).toList();
    final nearby = _found
        .where((p) => !recentIds.contains(p.id) && matches(p))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('選擇附近的閘道器', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('RSSI 為手機收到的藍牙訊號，與後端在線狀態不同。'),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.enabled && !_selecting
                  ? (_scanning ? _stop : _start)
                  : null,
              icon: Icon(_scanning ? Icons.stop : Icons.search),
              label: Text(_scanning ? '停止搜尋' : '重新搜尋'),
            ),
            TextButton(
              onPressed: widget.enabled ? openAppSettings : null,
              child: const Text('開啟權限設定'),
            ),
          ],
        ),
        if (_scanning) const LinearProgressIndicator(),
        Text(
          _selecting
              ? '正在連線並讀取設定…'
              : _scanning
              ? '持續搜尋中・RSSI 隨廣播更新'
              : '搜尋已停止・RSSI 為最後一次結果',
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextField(
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search),
            hintText: '篩選名稱或位址',
          ),
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
        ),
        if (_query.isNotEmpty && recent.isEmpty && nearby.isEmpty)
          const Text('沒有符合的裝置'),
        if (recent.isNotEmpty) ...[
          const Text('最近使用'),
          ...recent.map((r) => _tile(r.peer, recent: r)),
        ],
        if (nearby.isNotEmpty) ...[
          Text('附近裝置（${nearby.length}）'),
          ...nearby.map(_tile),
        ],
        if (!_scanning && _found.isEmpty)
          const Text('未發現附近閘道器。請確認電源、靠近裝置，並確認沒有被其他手機連線。'),
        if (_backendAt != null) const Text('後端狀態每 15 秒更新，僅代表目前選擇的後端環境。'),
      ],
    );
  }
}
