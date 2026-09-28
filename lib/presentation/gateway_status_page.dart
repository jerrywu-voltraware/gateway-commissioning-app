import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../application/app_session.dart';
import '../application/commissioning_controller.dart';
import '../application/nearby_gateways.dart';
import '../core/gateway_identity.dart' show parseGatewayName;
import '../core/protocol.dart';
import '../data/contracts.dart' show GatewayPeer;
import '../data/fleet_status_api.dart';
import '../data/recent_commissions.dart';
import '../data/recent_data_api.dart' show recentDataErrorText;
import 'recent_data_page.dart';

/// Title of the page and of its entries (the start page's button, the
/// topology menu's item).
const gatewayStatusLabel = '閘道器狀態';
const gatewayStatusRecentTitle = '最近配置（這支手機）';
const gatewayStatusNearbyTitle = '附近閘道器（藍牙掃描）';
const gatewayStatusFleetTitle = '後台在線閘道器';
const gatewayStatusRecentEmptyText = '這支手機尚未用此版本完成過配置';
const gatewayStatusNearbyEmptyText = '附近沒有掃到閘道器，請靠近後按〔重新掃描〕';
const gatewayStatusNearbyScanningText = '正在掃描附近閘道器（約 8 秒）…';
const gatewayStatusNearbyUnnamedText = '尚未設定站號，無法查看資料';
const gatewayStatusRescanLabel = '重新掃描';
const gatewayStatusSettingsLabel = '開啟權限設定';
const gatewayStatusFleetEmptyText = '後台目前沒有任何閘道器。';
const gatewayStatusLoadingText = '正在向後台查詢…';
const gatewayStatusRefreshLabel = '重新整理';
const gatewayStatusRetryLabel = '重試';
const gatewayStatusHint = '點一列即可查看該閘道器的最近資料。';

/// 「站 56 閘道器 1」.
String gatewayStatusName(int site, int gateway) => '站 $site 閘道器 $gateway';

/// 「RSSI -61 dBm・GIOS-S56-GW01」 (a nearby row's second line).
String gatewayStatusNearbyLine(GatewayPeer p) => 'RSSI ${p.rssi} dBm・${p.name}';

/// Words for a failed nearby scan: the link's own (「需要藍牙權限…」, 「請開啟
/// 手機藍牙後重試。」…) or a generic one.
String gatewayStatusNearbyErrorText(Object error) =>
    error is GatewayFailure ? error.message : '掃描失敗，請確認藍牙、定位與附近裝置權限後重試。';

/// 「09-28 14:03 完成」.
String gatewayStatusDoneText(DateTime doneAt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(doneAt.month)}-${two(doneAt.day)} '
      '${two(doneAt.hour)}:${two(doneAt.minute)} 完成';
}

/// 「在線・PTU 已連線・最近資料 7 秒前」 (「離線」, 「PTU 未連線」, 「最近心跳
/// N 秒前」 when the PTUs sent nothing yet, 「尚無資料」 when neither).
String gatewayStatusLine(FleetGateway g, DateTime now) {
  final parts = <String>[
    g.online ? '在線' : '離線',
    g.ptuConnected ? 'PTU 已連線' : 'PTU 未連線',
  ];
  final data = g.lastData, hb = g.lastHeartbeat;
  if (data != null) {
    parts.add('最近資料 ${recentAgeText(now.difference(data))}前');
  } else if (hb != null) {
    parts.add('最近心跳 ${recentAgeText(now.difference(hb))}前');
  } else {
    parts.add('尚無資料');
  }
  return parts.join('・');
}

/// 1.0.0+5 「閘道器狀態」: the gateways this phone finished (top, kept on
/// the phone) and the back office's fleet-status list (bottom); every row
/// opens 〔查看最近資料〕 — so the installer can check the data again after
/// the done page is gone, without a new run. Reached from the start
/// page's 〔閘道器狀態〕 and the topology menu. Never touches the flow.
///
/// 1.0.0+7 (field): the back office is read through [AppSession] — the
/// page logs the APP in itself (the flow's login no longer has to have
/// happened) — and a middle section 「附近閘道器（藍牙掃描）」 scans about 8 s
/// on entry ([NearbyGatewayScanner]; no connect, no pairing) and lists
/// every gateway heard; a row opens its recent data.
class GatewayStatusPage extends ConsumerStatefulWidget {
  const GatewayStatusPage({super.key, this.now});

  /// Clock for the 「N 秒前」 texts; tests inject one.
  final DateTime Function()? now;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const GatewayStatusPage()));

  @override
  ConsumerState<GatewayStatusPage> createState() => _GatewayStatusPageState();
}

class _GatewayStatusPageState extends ConsumerState<GatewayStatusPage> {
  List<RecentCommission> _recent = const [];
  List<FleetGateway>? _fleet;
  Object? _error;
  bool _loading = false;
  int _generation = 0;

  List<GatewayPeer>? _nearby;
  Object? _nearbyError;
  bool _scanning = false;
  int _scanGeneration = 0;
  Completer<void>? _scanStop;

  @override
  void initState() {
    super.initState();
    _load();
    _scan();
  }

  @override
  void dispose() {
    // The adapter scan is a singleton: it must not outlive the page.
    _scanGeneration++;
    _stopScan();
    super.dispose();
  }

  void _stopScan() {
    final stop = _scanStop;
    if (stop != null && !stop.isCompleted) stop.complete();
  }

  Future<void> _scan() async {
    final gen = ++_scanGeneration;
    _stopScan();
    final stop = _scanStop = Completer<void>();
    setState(() {
      _scanning = true;
      _nearbyError = null;
    });
    List<GatewayPeer>? peers;
    Object? error;
    try {
      peers = await ref
          .read(nearbyScannerProvider)
          .scanNearby(stop: stop.future);
    } catch (e) {
      error = e;
    }
    if (!mounted || gen != _scanGeneration) return;
    setState(() {
      _scanning = false;
      if (error != null) {
        _nearbyError = error;
      } else {
        _nearby = peers;
      }
    });
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final demo = ref.read(linkProvider).demo;
    final recent = await RecentCommissions.load(demo);
    if (mounted && gen == _generation) setState(() => _recent = recent);
    List<FleetGateway>? fleet;
    Object? error;
    try {
      fleet = await ref.read(appSessionProvider).run(fetchFleetStatus);
    } catch (e) {
      error = e;
    }
    if (!mounted || gen != _generation) return;
    setState(() {
      _loading = false;
      if (error != null) {
        _error = error;
      } else {
        _fleet = fleet;
      }
    });
  }

  void _openRecent(int site, int gateway) =>
      RecentDataPage.open(context, site, gateway);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(gatewayStatusLabel),
        actions: [
          IconButton(
            key: const Key('gs-refresh'),
            tooltip: gatewayStatusRefreshLabel,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                  key: Key('gs-progress'),
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const Key('gs-body'),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _Header(gatewayStatusRecentTitle),
                ..._recentSection(context),
                const SizedBox(height: 8),
                _Header(gatewayStatusNearbyTitle),
                ..._nearbySection(context),
                const SizedBox(height: 8),
                _Header(gatewayStatusFleetTitle),
                ..._fleetSection(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    gatewayStatusHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _recentSection(BuildContext context) {
    if (_recent.isEmpty) {
      return [
        const _Note(
          key: Key('gs-recent-empty'),
          text: gatewayStatusRecentEmptyText,
        ),
      ];
    }
    return [
      for (final r in _recent)
        ListTile(
          key: Key('gs-recent-${r.site}-${r.gateway}'),
          leading: const Icon(Icons.history),
          title: Text(gatewayStatusName(r.site, r.gateway)),
          subtitle: Text(
            [
              if (r.gatewayName.isNotEmpty) r.gatewayName,
              gatewayStatusDoneText(r.doneAt),
            ].join('・'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openRecent(r.site, r.gateway),
        ),
    ];
  }

  Widget _rescanButton() => FilledButton.tonalIcon(
    key: const Key('gs-nearby-rescan'),
    onPressed: _scanning ? null : _scan,
    icon: const Icon(Icons.bluetooth_searching, size: 20),
    label: const Text(gatewayStatusRescanLabel),
  );

  Widget _rescanRow({double top = 0}) => Padding(
    padding: EdgeInsets.fromLTRB(16, top, 16, 0),
    child: Align(alignment: Alignment.centerRight, child: _rescanButton()),
  );

  List<Widget> _nearbySection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_scanning) {
      return [
        const Padding(
          key: Key('gs-nearby-scanning'),
          padding: EdgeInsets.all(24),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text(gatewayStatusNearbyScanningText)),
            ],
          ),
        ),
      ];
    }
    final error = _nearbyError;
    if (error != null) {
      return [
        Padding(
          key: const Key('gs-nearby-error'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                gatewayStatusNearbyErrorText(error),
                key: const Key('gs-nearby-error-text'),
                style: TextStyle(color: colors.error),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const Key('gs-nearby-settings'),
                    onPressed: openAppSettings,
                    child: const Text(gatewayStatusSettingsLabel),
                  ),
                  _rescanButton(),
                ],
              ),
            ],
          ),
        ),
      ];
    }
    final nearby = _nearby ?? const <GatewayPeer>[];
    if (nearby.isEmpty) {
      return [
        const _Note(
          key: Key('gs-nearby-empty'),
          text: gatewayStatusNearbyEmptyText,
        ),
        _rescanRow(),
      ];
    }
    return [for (final p in nearby) _nearbyTile(p, colors), _rescanRow(top: 8)];
  }

  Widget _nearbyTile(GatewayPeer p, ColorScheme colors) {
    final id = parseGatewayName(p.name);
    if (id == null) {
      // A gateway without an identity yet (site / gateway 0): nothing to
      // look up in the back office.
      return ListTile(
        key: Key('gs-nearby-${p.id}'),
        leading: Icon(Icons.bluetooth, color: colors.onSurfaceVariant),
        title: Text(p.name),
        subtitle: Text(
          'RSSI ${p.rssi} dBm・$gatewayStatusNearbyUnnamedText',
          key: Key('gs-nearby-${p.id}-line'),
        ),
        enabled: false,
      );
    }
    return ListTile(
      key: Key('gs-nearby-${p.id}'),
      leading: const Icon(Icons.bluetooth, color: Color(0xFF1565C0)),
      title: Text(gatewayStatusName(id.site, id.gateway)),
      subtitle: Text(
        gatewayStatusNearbyLine(p),
        key: Key('gs-nearby-${p.id}-line'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openRecent(id.site, id.gateway),
    );
  }

  List<Widget> _fleetSection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final error = _error;
    final fleet = _fleet;
    if (error != null) {
      return [
        Padding(
          key: const Key('gs-error'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                recentDataErrorText(error),
                key: const Key('gs-error-text'),
                style: TextStyle(color: colors.error),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: const Key('gs-retry'),
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text(gatewayStatusRetryLabel),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (fleet == null) {
      return [
        const Padding(
          key: Key('gs-loading'),
          padding: EdgeInsets.all(24),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text(gatewayStatusLoadingText),
            ],
          ),
        ),
      ];
    }
    if (fleet.isEmpty) {
      return [
        const _Note(
          key: Key('gs-fleet-empty'),
          text: gatewayStatusFleetEmptyText,
        ),
      ];
    }
    final now = (widget.now ?? DateTime.now)();
    return [
      for (final g in fleet)
        ListTile(
          key: Key('gs-fleet-${g.site}-${g.gateway}'),
          leading: Icon(
            g.online ? Icons.cloud_done : Icons.cloud_off,
            color: g.online ? const Color(0xFF2E7D32) : colors.error,
          ),
          title: Text(gatewayStatusName(g.site, g.gateway)),
          subtitle: Text(
            gatewayStatusLine(g, now),
            key: Key('gs-fleet-${g.site}-${g.gateway}-line'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openRecent(g.site, g.gateway),
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
