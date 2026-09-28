import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../core/gateway_identity.dart';
import '../core/gateway_proximity.dart';
import '../core/protocol.dart';
import '../data/contracts.dart';
import '../data/recent_gateways.dart';

/// 1.0.0+8: the tile's badge for a gateway not yet configured.
const gatewayUnconfiguredLabel = '未配置';

/// The identify button's tooltip (an icon since 1.0.0+8).
const identifyGatewayLabel = '辨識閘道器';

/// 1.0.0+9: on the row for 3 s after 〔辨識〕 blinked it.
const identifiedHint = '已閃燈';

/// 1.0.0+9: how long [identifiedHint] stays.
const identifiedHintFor = Duration(seconds: 3);

/// 1.0.0+10: the 「最近」 chip's fill and the nearest card's outline.
const gatewayNearestColor = Color(0xFF2E7D32);

/// 1.0.0+10: a small mark on a gateway row (labelMedium): outlined, or
/// [filled] (white text on [color]).
class GatewayMark extends StatelessWidget {
  const GatewayMark(
    this.text, {
    super.key,
    required this.color,
    this.filled = false,
  });
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: filled ? Colors.white : color,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : null,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, maxLines: 1, softWrap: false, style: style),
    );
  }
}

class GatewayDiscovery extends ConsumerStatefulWidget {
  const GatewayDiscovery({
    super.key,
    required this.enabled,
    required this.onConnect,
    this.onIdentify,
  });
  final bool enabled;
  final Future<void> Function(GatewayPeer) onConnect;

  /// 「辨識」 on a row: blink it and stay on the list (1.0.0+9). Answers
  /// whether the identify was really sent (1.0.0+10: 「已閃燈」 only then —
  /// not after a cancel or a failure). Null hides the button.
  final Future<bool> Function(GatewayPeer)? onIdentify;
  @override
  ConsumerState<GatewayDiscovery> createState() => _GatewayDiscoveryState();
}

class _GatewayDiscoveryState extends ConsumerState<GatewayDiscovery>
    with WidgetsBindingObserver {
  List<RecentGateway> _recent = [];
  List<GatewayPeer> _found = [];
  String _query = "";

  /// Round 30 (user rehearsal 09-27, D): the phone's signal ranks the list.
  final _ranker = GatewaySignalRanker();
  var _ranked = <String>[];
  ({String nearest, bool close})? _nearest;
  List<dynamic> _fleet = [];
  List<dynamic> _archived = [];
  String? _backendError;
  DateTime? _backendAt;
  String? _error;

  /// 1.0.0+10: the last scan failed for want of a permission (or a
  /// location service) — only then 〔開啟權限設定〕 is shown.
  bool _needsSettings = false;
  bool _scanning = false, _selecting = false;

  /// 1.0.0+9: the gateway 〔辨識〕 just blinked (「已閃燈」 on its row).
  String? _identified;
  Timer? _identifiedTimer;
  int _epoch = 0, _backendEpoch = 0;
  StreamSubscription<List<GatewayPeer>>? _scan;

  /// 1.0.0+10: a live scan is wanted (started and not stopped by the
  /// installer) — resumed when this page is on top again after another
  /// page (「閘道器狀態」's own scan) ended it.
  bool _liveWanted = false;

  /// 1.0.0+10: [_resumeScan] is waiting (the list disabled, busy or not on
  /// top); tried again when that ends.
  bool _resumePending = false;

  /// 1.0.0+10: whether this list's route was on top at the last check.
  bool? _routeCurrent;
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

  /// 1.0.0+10 (review P2-5): back on top (e.g. from 「閘道器狀態」, whose
  /// scan stopped this one) — the live scan starts again when it was
  /// wanted.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    final was = _routeCurrent;
    _routeCurrent = current;
    if (was == false && current) _resumeScan();
  }

  @override
  void didUpdateWidget(covariant GatewayDiscovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The run that disabled the list (e.g. 〔辨識〕) is over.
    if (widget.enabled && !oldWidget.enabled && _resumePending) _resumeScan();
  }

  /// Starts the live scan again when one is wanted and none runs; waits
  /// (see [_resumePending]) while the list is disabled, busy or covered.
  void _resumeScan() {
    if (!_liveWanted || _scanning) return;
    _resumePending = true;
    if (!widget.enabled ||
        _selecting ||
        _background ||
        _routeCurrent == false) {
      return;
    }
    unawaited(() async {
      await _stopping;
      if (!mounted || !_resumePending || _scanning) return;
      await _start(keep: true);
    }());
  }

  /// 〔停止搜尋〕: the installer stopped it — not resumed by itself.
  Future<void> _stopByUser() {
    _liveWanted = false;
    _resumePending = false;
    return _stop();
  }

  @override
  void dispose() {
    _identifiedTimer?.cancel();
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
        _backendError = null;
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
          _backendError = null;
          _backendAt = null;
        });
      }
      return;
    }
    final base = ref.read(backendEnvProvider).base;
    try {
      final result = await ref
          .read(apiProvider)
          .request('GET', '/api/gateways/fleet-status?include_archived=true')
          .timeout(const Duration(seconds: 8));
      if (!mounted ||
          epoch != _backendEpoch ||
          base != ref.read(backendEnvProvider).base ||
          !ref.read(commissionProvider).loggedIn) {
        return;
      }
      setState(() {
        _fleet = result['gateways'] as List? ?? [];
        _archived = result['archived_gateways'] as List? ?? [];
        _backendError = null;
        _backendAt = DateTime.now();
      });
    } catch (error) {
      if (mounted && epoch == _backendEpoch) {
        setState(() {
          _fleet = [];
          _archived = [];
          _backendError = backendQueryFailedText(error);
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

  /// [keep] (1.0.0+10, a resumed scan): the rows heard before stay until
  /// the scan's first answer — the list does not flash empty.
  Future<void> _start({bool keep = false}) async {
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
    _liveWanted = link is GatewayScanner;
    _resumePending = false;
    setState(() {
      _scanning = true;
      if (!keep) _found = [];
      _error = null;
      _needsSettings = false;
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
        final now = DateTime.now();
        for (final peer in peers) {
          _ranker.add(peer.id, peer.rssi, now);
        }
        final ids = [for (final peer in peers) peer.id];
        final ranked = _ranker.rank(ids, now);
        // 1.0.0+10 (phone: 81/1 at -41 dBm, 80/2 at -62, no 「最近」 at
        // all): the strongest gateway heard is 「最近」 whether configured
        // or not (its 「已配置」 chip says the rest) — r31 left it out, so
        // with one configured and one new gateway nothing was marked.
        final nearest = _ranker.nearest(ids, now);
        setState(() {
          _ranked = ranked;
          _nearest = nearest;
          _found = [...peers]..sort((a, b) => _rankOf(a.id) - _rankOf(b.id));
        });
      }
    }

    void failure(Object error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = error is GatewayFailure
            ? error.message
            : '搜尋失敗，請確認藍牙、定位與附近裝置權限後重試。';
        _needsSettings =
            error is! GatewayFailure ||
            error.code == 'permission' ||
            error.code == 'location_off';
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

  /// Position in the signal ranking; gateways not heard after all heard.
  int _rankOf(String id) {
    final at = _ranked.indexOf(id);
    return at < 0 ? _ranked.length : at;
  }

  /// r31: a remembered gateway the back office already knows (configured).
  bool _configured(String id) {
    if (_backendAt == null) return false;
    final uid = _recent.where((r) => r.peer.id == id).firstOrNull?.uid;
    return gatewayConfigured(uid, _fleet);
  }

  Future<void> _connect(GatewayPeer peer) async {
    if (_selecting || !widget.enabled) return;
    setState(() => _selecting = true);
    try {
      await _stop();
      if (mounted) await widget.onConnect(peer);
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  /// 1.0.0+9: 〔辨識〕 blinks [peer] ([GatewayDiscovery.onIdentify]) and the
  /// list stays; 「已閃燈」 on its row for [identifiedHintFor].
  ///
  /// 1.0.0+10: the hint only when the identify was really sent (not after
  /// 〔取消操作〕 or a failure); a live scan running before starts again
  /// afterwards.
  Future<void> _identify(GatewayPeer peer) async {
    final action = widget.onIdentify;
    if (_selecting || !widget.enabled || action == null) return;
    final resume = _scanning && _liveWanted;
    setState(() {
      _selecting = true;
      _identified = null;
    });
    try {
      await _stop();
      final blinked = mounted && await action(peer);
      if (mounted && blinked) {
        _identifiedTimer?.cancel();
        setState(() => _identified = peer.id);
        _identifiedTimer = Timer(identifiedHintFor, () {
          if (mounted) setState(() => _identified = null);
        });
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
    if (mounted && resume) _resumeScan();
  }

  Widget _tile(GatewayPeer peer, {RecentGateway? recent}) {
    final found = _found.where((p) => p.id == peer.id).firstOrNull;
    final last =
        recent ?? _recent.where((r) => r.peer.id == peer.id).firstOrNull;
    // 1.0.0+9: the back-office state as a short phrase (在線／離線／無紀錄／
    // 未知).
    final stale =
        _backendAt == null ||
        DateTime.now().difference(_backendAt!).inSeconds > 30;
    final presence = !ref.watch(commissionProvider).loggedIn || stale
        ? backendUnknownShort
        : backendPresenceShort(last?.uid, _fleet, archived: _archived);
    final configured = _configured(peer.id);
    final signal = found == null
        ? '未收到廣播'
        : found.rssi <= -127
        ? '訊號未知'
        : '${found.rssi} dBm';
    // Round 26 (field: two gateways both read 「GIOS-S80-G…」): 「站 80 ·
    // 閘道器 2」 as the title. 1.0.0+10: the advertised name (the live one:
    // a recent entry keeps the name it had) only when it does not parse —
    // the title says the same (the filter still matches it).
    final name = found?.name ?? peer.name;
    final title = gatewayTitle(name);
    // Round 28 (field round 28: this list read 「70F2」, the help panel and
    // the back office 「70F0」): the Wi-Fi MAC tail the back office shows —
    // remembered from an earlier connect, else derived from the Bluetooth
    // MAC. 1.0.0+9: 「…3A00」 (no 「MAC」 word).
    final wifi = gatewayWifiMac(uid: last?.uid, bleId: peer.id);
    final tail = wifi == null ? peer.id : '…${wifi.substring(8)}';
    final theme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final nearest = found != null && _nearest?.nearest == peer.id;
    final small = theme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final identified = _identified == peer.id;
    final detail = [if (title == name) name, tail].join(' · ');
    // 1.0.0+10 (phone 360 dp at text scale 1.1: line 1 wrapped and pushed
    // the dBm to a second line, line 3 cut 「· …」, the name repeated the
    // title): three short lines per gateway —
    // 1. 「站 81・閘道器 1」 (titleMedium w700, cut with an ellipsis if ever
    //    too long) and 「-40 dBm」 fixed at the right end;
    // 2. the marks as small chips: 「最近」 (filled green, the strongest
    //    gateway only), 「已配置」／「未配置」, the back office's short
    //    phrase (「已閃燈」 for 3 s after 〔辨識〕);
    // 3. 「…3A00」 (bodySmall).
    final (badgeKey, badgeText) = configured
        ? ('gateway-configured-', gatewayConfiguredLabel)
        : ('gateway-unconfigured-', gatewayUnconfiguredLabel);
    return Card(
      key: ValueKey('gateway-card-${peer.id}'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      shape: nearest
          ? RoundedRectangleBorder(
              side: const BorderSide(color: gatewayNearestColor, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: InkWell(
        key: ValueKey(peer.id),
        borderRadius: BorderRadius.circular(4),
        onTap: widget.enabled && !_selecting
            ? () => _connect(found ?? peer)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      key: ValueKey('gateway-head-${peer.id}'),
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            key: ValueKey('gateway-title-${peer.id}'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: theme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          signal,
                          key: ValueKey('gateway-signal-${peer.id}'),
                          maxLines: 1,
                          softWrap: false,
                          style: theme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      key: ValueKey('gateway-marks-${peer.id}'),
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (nearest)
                          GatewayMark(
                            gatewayNearestLabel,
                            key: ValueKey('gateway-nearest-${peer.id}'),
                            color: gatewayNearestColor,
                            filled: true,
                          ),
                        GatewayMark(
                          badgeText,
                          key: ValueKey('$badgeKey${peer.id}'),
                          color: configured
                              ? colors.onSurfaceVariant
                              : colors.outline,
                        ),
                        GatewayMark(
                          identified ? identifiedHint : presence,
                          key: ValueKey('gateway-presence-${peer.id}'),
                          color: identified
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      key: ValueKey('gateway-detail-${peer.id}'),
                      style: small,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.onIdentify != null)
                IconButton(
                  key: ValueKey('identify-${peer.id}'),
                  tooltip: identifyGatewayLabel,
                  icon: Icon(
                    identified ? Icons.lightbulb : Icons.lightbulb_outline,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.enabled && !_selecting
                      ? () => _identify(found ?? peer)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1.0.0+10: 「最近使用」／「附近裝置（N）」 as section titles.
  Widget _groupTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(backendEnvProvider, (_, next) {
      _backendEpoch++;
      setState(() {
        _fleet = [];
        _backendError = null;
        _backendAt = null;
      });
    });
    final recentIds = _recent.map((r) => r.peer.id).toSet();
    // Round 28: the Wi-Fi MAC the back office shows is searchable too.
    bool matches(GatewayPeer peer) =>
        '${peer.name} ${gatewayTitle(peer.name)} ${peer.id} '
                '${gatewayWifiMac(bleId: peer.id) ?? ''}'
            .toLowerCase()
            .contains(_query);
    // Round 30: both lists by the phone's signal, strongest first (a
    // recent gateway not heard keeps its place after the heard ones).
    // 1.0.0+10: configured ones no longer after the others — the strongest
    // (「最近」) is first in its group.
    final recent =
        [
          for (final (i, r) in _recent.indexed)
            if (matches(r.peer)) (i, r),
        ]..sort((a, b) {
          final c = _rankOf(a.$2.peer.id) - _rankOf(b.$2.peer.id);
          return c != 0 ? c : a.$1 - b.$1;
        });
    final nearby = _found
        .where((p) => !recentIds.contains(p.id) && matches(p))
        .toList();
    final nearest = _nearest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1.0.0+10: a section title (titleSmall w600) and room between
        // the note and the button (phone: they touched).
        Text(
          '選擇附近的閘道器',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        const Text('RSSI 為手機收到的藍牙訊號，與後端在線狀態不同。'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              onPressed: widget.enabled && !_selecting
                  ? (_scanning ? _stopByUser : _start)
                  : null,
              icon: Icon(_scanning ? Icons.stop : Icons.search),
              label: Text(_scanning ? '停止搜尋' : '重新搜尋'),
            ),
            // 1.0.0+10 (phone: always there): only when the scan failed for
            // want of a permission.
            if (_needsSettings)
              TextButton(
                key: const Key('gateway-open-settings'),
                onPressed: widget.enabled ? openAppSettings : null,
                child: const Text('開啟權限設定'),
              ),
          ],
        ),
        const SizedBox(height: 4),
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
        if (nearest != null)
          Container(
            key: const Key('gateway-nearest-hint'),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(10),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gatewayNearestHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                if (nearest.close)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '⚠ $gatewayCloseHint',
                      key: const Key('gateway-close-hint'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (recent.isNotEmpty) ...[
          _groupTitle('最近使用'),
          ...recent.map((r) => _tile(r.$2.peer, recent: r.$2)),
        ],
        if (nearby.isNotEmpty) ...[
          _groupTitle('附近裝置（${nearby.length}）'),
          ...nearby.map(_tile),
        ],
        if (!_scanning && _found.isEmpty)
          const Text('未發現附近閘道器。請確認電源、靠近裝置，並確認沒有被其他手機連線。'),
        if (_backendAt != null) const Text('後端狀態每 15 秒更新，僅代表目前選擇的後端環境。'),
        // 1.0.0+9: the rows say 「後端未知」 only; the reason is this line.
        if (_backendAt == null && _backendError != null)
          Text(
            _backendError!,
            key: const Key('gateway-backend-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
