import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/commissioning_controller.dart';
import '../data/fleet_status_api.dart';
import '../data/recent_commissions.dart';
import '../data/recent_data_api.dart' show recentDataErrorText;
import 'recent_data_page.dart';

/// Title of the page and of its entries (the start page's button, the
/// topology menu's item).
const gatewayStatusLabel = '閘道器狀態';
const gatewayStatusRecentTitle = '最近配置（這支手機）';
const gatewayStatusFleetTitle = '後台在線閘道器';
const gatewayStatusRecentEmptyText = '這支手機還沒有完成過配置。';
const gatewayStatusFleetEmptyText = '後台目前沒有任何閘道器。';
const gatewayStatusLoadingText = '正在向後台查詢…';
const gatewayStatusRefreshLabel = '重新整理';
const gatewayStatusRetryLabel = '重試';
const gatewayStatusHint = '點一列即可查看該閘道器的最近資料。';

/// 「站 56 閘道器 1」.
String gatewayStatusName(int site, int gateway) => '站 $site 閘道器 $gateway';

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

  @override
  void initState() {
    super.initState();
    _load();
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
      fleet = await fetchFleetStatus(ref.read(apiProvider));
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
