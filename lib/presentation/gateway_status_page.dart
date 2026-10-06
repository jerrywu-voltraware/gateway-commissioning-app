import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../application/app_session.dart';
import '../application/commissioning_controller.dart';
import '../application/nearby_gateways.dart';
import '../core/gateway_identity.dart'
    show
        gatewayTailText,
        isFactoryGatewayName,
        parseGatewayName,
        unconfiguredGatewayTitle;
import '../core/protocol.dart';
import '../data/contracts.dart' show GatewayPeer;
import '../data/fleet_status_api.dart';
import '../data/recent_commissions.dart';
import '../data/recent_data_api.dart' show recentDataErrorText;
import '../l10n/l10n.dart';
import 'gateway_discovery.dart' show GatewayMark, gatewayNearestColor;
import 'recent_data_page.dart';

// i18n 範本（docs/i18n.md）：其他檔與測試引用的 top-level 文字維持同名，
// 由 const 改成讀 [L10n.current] 的 getter；本頁 build 內直接用
// `context.l10n`。字串在 lib/l10n/parts/gatewayStatus_*.arb。

/// Title of the page and of its entries (the start page's button, the
/// topology menu's item).
String get gatewayStatusLabel => L10n.current.gatewayStatus_label;
String get gatewayStatusHomeCaption => L10n.current.gatewayStatus_homeCaption;
String get gatewayStatusRecentTitle => L10n.current.gatewayStatus_recentTitle;
String get gatewayStatusNearbyTitle => L10n.current.gatewayStatus_nearbyTitle;
String get gatewayStatusFleetTitle => L10n.current.gatewayStatus_fleetTitle;
String get gatewayStatusRecentEmptyText =>
    L10n.current.gatewayStatus_recentEmpty;
String get gatewayStatusNearbyEmptyText =>
    L10n.current.gatewayStatus_nearbyEmpty;
String get gatewayStatusNearbyScanningText =>
    L10n.current.gatewayStatus_nearbyScanning;
String get gatewayStatusNearbyUnnamedText =>
    L10n.current.gatewayStatus_nearbyUnnamed;
String get gatewayStatusRescanLabel => L10n.current.gatewayStatus_rescan;
String get gatewayStatusSettingsLabel =>
    L10n.current.gatewayStatus_openSettings;
String get gatewayStatusFleetEmptyText => L10n.current.gatewayStatus_fleetEmpty;
String get gatewayStatusLoadingText => L10n.current.gatewayStatus_loading;
String get gatewayStatusRefreshLabel => L10n.current.common_refresh;
String get gatewayStatusRetryLabel => L10n.current.common_retry;
String get gatewayStatusHint => L10n.current.gatewayStatus_hint;

/// 「站 56 閘道器 1」.
String gatewayStatusName(int site, int gateway) =>
    L10n.current.gatewayStatus_name(site, gateway);

/// 「-61 dBm・GIOS-S56-GW01」 (a nearby row's second line). 1.0.0+10
/// (phone: the line broke at 「GIOS-S81-」): no 「RSSI」 word, and the name
/// with non-breaking hyphens (U+2011) so it moves to the next line whole.
String gatewayStatusNearbyLine(GatewayPeer p) =>
    '${p.rssi} dBm${L10n.current.common_dotSeparator}${unbrokenName(p.name)}';

/// [name] with its hyphens non-breaking (U+2011): a line never breaks
/// inside 「GIOS-S81-GW01」.
String unbrokenName(String name) => name.replaceAll('-', '\u2011');

/// 1.0.0+10: the strongest nearby gateway's mark (as on the gateway list).
String get gatewayStatusNearestLabel => L10n.current.gatewayStatus_nearest;

/// 1.0.0+12: a nearby gateway known not to be configured's second line —
/// no station or number (an old identity may be left in its name).
String get gatewayStatusNearbyUnconfiguredText =>
    L10n.current.gatewayStatus_nearbyUnconfigured;

/// 1.0.0+12: a nearby gateway known not to be configured — its name is the
/// factory 1/1, or the back office's list ([fleet]; null: not read) has no
/// gateway with the station and number it advertises. It is listed as
/// 「未配置閘道器 …XXXX」, not its station / number.
bool nearbyKnownUnconfigured(String name, List<FleetGateway>? fleet) {
  if (isFactoryGatewayName(name)) return true;
  final id = parseGatewayName(name);
  if (id == null || fleet == null) return false;
  return !fleet.any((g) => g.site == id.site && g.gateway == id.gateway);
}

/// Words for a failed nearby scan: the link's own (「需要藍牙權限…」, 「請開啟
/// 手機藍牙後重試。」…) or a generic one.
String gatewayStatusNearbyErrorText(Object error) => error is GatewayFailure
    ? error.message
    : L10n.current.gatewayStatus_nearbyScanFailed;

/// 「09-28 14:03 完成」.
String gatewayStatusDoneText(DateTime doneAt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return L10n.current.gatewayStatus_doneAt(
    '${two(doneAt.month)}-${two(doneAt.day)} '
    '${two(doneAt.hour)}:${two(doneAt.minute)}',
  );
}

/// 「在線・PTU 已連線・7 秒前」 (the newest data; 「離線」, 「PTU 未連線」,
/// 「心跳 N 秒前」 when the PTUs sent nothing yet, 「尚無資料」 when
/// neither). 1.0.0+10 (phone: 「最近資料 7 秒前」 wrapped): shorter.
String gatewayStatusLine(FleetGateway g, DateTime now) {
  final l10n = L10n.current;
  final parts = <String>[
    g.online ? l10n.gatewayStatus_online : l10n.gatewayStatus_offline,
    g.ptuConnected
        ? l10n.gatewayStatus_ptuConnected
        : l10n.gatewayStatus_ptuDisconnected,
  ];
  final data = g.lastData, hb = g.lastHeartbeat;
  if (data != null) {
    parts.add(l10n.gatewayStatus_dataAgo(recentAgeText(now.difference(data))));
  } else if (hb != null) {
    parts.add(
      l10n.gatewayStatus_heartbeatAgo(recentAgeText(now.difference(hb))),
    );
  } else {
    parts.add(l10n.gatewayStatus_noData);
  }
  return parts.join(l10n.common_dotSeparator);
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
  final Set<String> _expandedSites = {};

  List<Widget> _siteGroups<T>(
    String section,
    List<T> items,
    int? Function(T) siteOf,
    Widget Function(T) tileOf,
  ) {
    final groups = <int?, List<T>>{};
    for (final item in items) {
      groups.putIfAbsent(siteOf(item), () => []).add(item);
    }
    final sites = groups.keys.toList()
      ..sort(
        (a, b) =>
            a == null ? (b == null ? 0 : 1) : (b == null ? -1 : a.compareTo(b)),
      );
    final l10n = context.l10n;
    return [
      for (final site in sites)
        ExpansionTile(
          key: ValueKey('gs-$section-site-${site ?? 'unconfigured'}'),
          initiallyExpanded: _expandedSites.contains('$section:$site'),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _expandedSites.add('$section:$site');
            } else {
              _expandedSites.remove('$section:$site');
            }
          },
          leading: const Icon(Icons.location_on_outlined),
          title: Text(
            site == null
                ? l10n.gatewayStatus_unconfiguredGroup
                : l10n.gatewayStatus_siteGroup(site),
          ),
          subtitle: Text(l10n.gatewayStatus_gatewayCount(groups[site]!.length)),
          childrenPadding: const EdgeInsets.only(left: 12),
          children: [for (final item in groups[site]!) tileOf(item)],
        ),
    ];
  }

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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gatewayStatus_label, maxLines: 1, softWrap: false),
        actions: [
          IconButton(
            key: const Key('gs-refresh'),
            tooltip: l10n.common_refresh,
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
                _Header(l10n.gatewayStatus_recentTitle),
                ..._recentSection(context),
                const SizedBox(height: 8),
                _Header(l10n.gatewayStatus_nearbyTitle),
                ..._nearbySection(context),
                const SizedBox(height: 8),
                _Header(l10n.gatewayStatus_fleetTitle),
                ..._fleetSection(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    l10n.gatewayStatus_hint,
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
        _Note(
          key: const Key('gs-recent-empty'),
          text: context.l10n.gatewayStatus_recentEmpty,
        ),
      ];
    }
    // 1.0.0+10 (phone: 「GIOS-S81-GW01・09-29 / 01:15 完成」 on two lines):
    // the time alone (the title says which gateway).
    return _siteGroups<RecentCommission>(
      'recent',
      _recent,
      (r) => r.site,
      (r) => _tile(
        context,
        key: Key('gs-recent-${r.site}-${r.gateway}'),
        leading: const Icon(Icons.history),
        title: gatewayStatusName(r.site, r.gateway),
        line: gatewayStatusDoneText(r.doneAt),
        lineKey: Key('gs-recent-${r.site}-${r.gateway}-line'),
        onTap: () => _openRecent(r.site, r.gateway),
      ),
    );
  }

  /// 1.0.0+10: one row style for the three sections — the title
  /// titleMedium w700, the line under it bodySmall (phone: titles were
  /// larger than the section headers, lines wrapped).
  Widget _tile(
    BuildContext context, {
    required Key key,
    required Widget leading,
    required String title,
    required String line,
    Key? lineKey,
    Widget? mark,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final titleText = Text(
      title,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    return ListTile(
      key: key,
      leading: leading,
      titleTextStyle: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: onTap == null
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurface,
      ),
      subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: mark == null
          ? titleText
          : Row(
              children: [
                Flexible(child: titleText),
                const SizedBox(width: 8),
                mark,
              ],
            ),
      subtitle: Text(line, key: lineKey),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
  }

  Widget _rescanButton() => FilledButton.tonalIcon(
    key: const Key('gs-nearby-rescan'),
    onPressed: _scanning ? null : _scan,
    icon: const Icon(Icons.bluetooth_searching, size: 20),
    label: Text(context.l10n.gatewayStatus_rescan),
  );

  Widget _rescanRow({double top = 0}) => Padding(
    padding: EdgeInsets.fromLTRB(16, top, 16, 0),
    child: Align(alignment: Alignment.centerRight, child: _rescanButton()),
  );

  List<Widget> _nearbySection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    if (_scanning) {
      // l10n 字串不是編譯期常數：外層不能再加 const（docs/i18n.md 陷阱）。
      return [
        Padding(
          key: const Key('gs-nearby-scanning'),
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.gatewayStatus_nearbyScanning)),
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
                    child: Text(l10n.gatewayStatus_openSettings),
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
        _Note(
          key: const Key('gs-nearby-empty'),
          text: l10n.gatewayStatus_nearbyEmpty,
        ),
        _rescanRow(),
      ];
    }
    // 1.0.0+10: the strongest one (two or more heard) marked 「最近」, as
    // on the gateway list.
    final strongest = nearby.length < 2
        ? null
        : nearby.reduce((a, b) => b.rssi > a.rssi ? b : a).id;
    return [
      ..._siteGroups<GatewayPeer>(
        'nearby',
        nearby,
        (p) => nearbyKnownUnconfigured(p.name, _error == null ? _fleet : null)
            ? null
            : parseGatewayName(p.name)?.site,
        (p) => _nearbyTile(p, colors, nearest: p.id == strongest),
      ),
      _rescanRow(top: 8),
    ];
  }

  Widget _nearbyTile(
    GatewayPeer p,
    ColorScheme colors, {
    bool nearest = false,
  }) {
    final l10n = context.l10n;
    final id = parseGatewayName(p.name);
    final mark = nearest
        ? GatewayMark(
            l10n.gatewayStatus_nearest,
            key: Key('gs-nearby-nearest-${p.id}'),
            color: gatewayNearestColor,
            filled: true,
          )
        : null;
    if (id == null) {
      // A gateway without an identity yet (site / gateway 0): nothing to
      // look up in the back office.
      return _tile(
        context,
        key: Key('gs-nearby-${p.id}'),
        leading: Icon(Icons.bluetooth, color: colors.onSurfaceVariant),
        title: p.name,
        line:
            '${p.rssi} dBm${l10n.common_dotSeparator}'
            '${l10n.gatewayStatus_nearbyUnnamed}',
        lineKey: Key('gs-nearby-${p.id}-line'),
        mark: mark,
      );
    }
    // 1.0.0+12: known not to be configured — not listed by the station /
    // number it advertises (an old test identity may be left in it), and
    // nothing to look up in the back office.
    if (nearbyKnownUnconfigured(p.name, _error == null ? _fleet : null)) {
      return _tile(
        context,
        key: Key('gs-nearby-${p.id}'),
        leading: Icon(Icons.bluetooth, color: colors.onSurfaceVariant),
        title: unconfiguredGatewayTitle(gatewayTailText(bleId: p.id)),
        line:
            '${p.rssi} dBm${l10n.common_dotSeparator}'
            '${l10n.gatewayStatus_nearbyUnconfigured}',
        lineKey: Key('gs-nearby-${p.id}-line'),
        mark: mark,
      );
    }
    return _tile(
      context,
      key: Key('gs-nearby-${p.id}'),
      leading: const Icon(Icons.bluetooth, color: Color(0xFF1565C0)),
      title: gatewayStatusName(id.site, id.gateway),
      line: gatewayStatusNearbyLine(p),
      lineKey: Key('gs-nearby-${p.id}-line'),
      mark: mark,
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
                  label: Text(context.l10n.common_retry),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (fleet == null) {
      return [
        Padding(
          key: const Key('gs-loading'),
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(context.l10n.gatewayStatus_loading),
            ],
          ),
        ),
      ];
    }
    if (fleet.isEmpty) {
      return [
        _Note(
          key: const Key('gs-fleet-empty'),
          text: context.l10n.gatewayStatus_fleetEmpty,
        ),
      ];
    }
    final now = (widget.now ?? DateTime.now)();
    return _siteGroups<FleetGateway>(
      'fleet',
      fleet,
      (g) => g.site,
      (g) => _tile(
        context,
        key: Key('gs-fleet-${g.site}-${g.gateway}'),
        leading: Icon(
          g.online ? Icons.cloud_done : Icons.cloud_off,
          color: g.online ? const Color(0xFF2E7D32) : colors.error,
        ),
        title: gatewayStatusName(g.site, g.gateway),
        line: gatewayStatusLine(g, now),
        lineKey: Key('gs-fleet-${g.site}-${g.gateway}-line'),
        onTap: () => _openRecent(g.site, g.gateway),
      ),
    );
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
