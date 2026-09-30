import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/auto_checklist.dart';
import '../application/connection_status.dart';
import '../application/network_check.dart';
import '../application/topology_settings.dart';
import '../core/assign_progress.dart';
import '../core/backend_key.dart';
import '../core/direct_calibration.dart';
import '../core/direct_mode.dart';
import '../core/gateway_identity.dart';
import '../core/gateway_net.dart';
import '../core/gateway_reboot.dart';
import '../core/gateway_topology.dart';
import '../core/local_backend_address.dart';
import '../core/mqtt_target.dart';
import '../core/star_allow_list.dart';
import '../data/contracts.dart';
import '../data/wifi_scan.dart';
import 'connection_status_panel.dart';
import 'direct_calibration_sheet.dart';
import 'direct_mode_panel.dart';
import 'environment_switch.dart';
import 'field_help_sheet.dart';
import 'install_report_panel.dart';
import 'local_backend_field.dart';
import 'progress_checklist.dart';
import 'ptu_selection_tile.dart';
import 'recent_data_page.dart';
import 'gateway_status_page.dart';
import 'gateway_signal.dart';
import 'gateway_discovery.dart';
import 'gateway_mode_card.dart';
import 'gateway_swap_sheet.dart';
import 'verify_live_panel.dart';
import '../core/gateway_swap.dart';

/// The AppBar title (1.0.0+8: shown whole at 360 dp, never 「GIOS …」).
const appBarTitle = 'GIOS 現場開通';

class CommissioningPage extends ConsumerStatefulWidget {
  const CommissioningPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  ConsumerState<CommissioningPage> createState() => _CommissioningPageState();
}

class _CommissioningPageState extends ConsumerState<CommissioningPage>
    with WidgetsBindingObserver {
  final _pageScroll = ScrollController();

  /// 1.0.0+11 (phone: 〔辨識〕 emptied the list for 2–4 s): the busy row
  /// inserted above the step card shifts the page's children, so the card
  /// was built anew and the list lost its state (RSSI, 「最近」, 「已閃燈」).
  /// A global key keeps the list's state across that move.
  final _discoveryKey = GlobalKey(debugLabel: 'gateway-discovery');

  /// 1.0.0+14: the gateway selected on the list, for the fixed bottom
  /// button 〔連線到 …〕 ([GatewayConnectBar]).
  final _gatewayChoice = GatewayChoice();

  /// Mirrors the selected backend URL (editable only for 其他網址); the
  /// source of truth is [backendEnvProvider].
  final _base = TextEditingController(text: productionApiBase);
  final _ssid = TextEditingController(), _wifi = TextEditingController();
  final _site = TextEditingController(text: '1'),
      _gateway = TextEditingController(text: '1');
  bool _offline = false;
  bool _foreground = true;
  bool _connectingPeer = false;
  bool _autoCheckPaused = false;
  bool _autoOnlineStarted = false;
  bool _autoFlowScheduled = false;

  /// One-thing screens (09-28): 「改用其他站號」 opened the station input;
  /// [_wifiStage]: a new identity goes on to its Wi-Fi page (the gateway is
  /// on no Wi-Fi, or 「改用其他 Wi-Fi」 was pressed); [_stationWorking]: the
  /// 「確定是新站？」 lookup runs (one tap, one action).
  bool _otherSite = false;
  bool _wifiStage = false;
  bool _stationWorking = false;

  /// r33: 〔取代舊機〕 chosen for this (site, gateway) on the 「閘道器編號
  /// 已被使用」 question; saving it uses force_replace without asking again.
  (int, int)? _replaceSlot;

  /// 1.0.0+13 換機 (replaces 1.0.0+12's 〔修改〕 number picker): the offline
  /// gateway of the station shown that this one replaces
  /// (〔這台是來換掉壞掉的舊機〕, [_chooseSwap]) — its number is shown and
  /// sent through the replacement ([_saveWifi]); not looked up again,
  /// not asked about as a skipped number. Another station typed, another
  /// gateway or 〔取消換機〕 goes back to the automatic number.
  SwapCandidate? _swap;

  /// r33 (a fresh install defaults to star; a one-to-one gateway went
  /// through it silently as max 5): after a gateway picked from the list
  /// is connected, a mode other than the APP's is asked about — the default
  /// keeps the gateway's mode and switches the APP to it. A resumed run or
  /// a relink keeps the mode it was started with (not asked).
  Future<void> _askTopology() async {
    final next = ref.read(commissionProvider);
    if (!mounted || next.step != 2 || next.error != null) return;
    final gateway = gatewayTopologyMismatch(
      next.config,
      ref.read(topologyProvider).topology,
    );
    if (gateway == null) return;
    await _showTopologyAsk(gateway, Map<String, dynamic>.from(next.config));
  }

  Future<void> _showTopologyAsk(
    GatewayTopology gateway,
    Map<String, dynamic> config,
  ) async {
    if (!mounted) return;
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('topology-ask'),
        title: Text(topologyAskTitle(gateway)),
        content: Text(topologyAskText(gateway, config)),
        actions: [
          TextButton(
            key: const Key('topology-ask-change'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(topologyChangeLabel(gateway)),
          ),
          FilledButton(
            key: const Key('topology-ask-keep'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(topologyKeepLabel(gateway)),
          ),
        ],
      ),
    );
    if (!mounted || keep == false) return;
    await ref.read(commissionProvider.notifier).switchTopology(gateway);
    if (mounted) _snack(topologyKeptText(gateway));
  }

  /// Leaving the station / Wi-Fi pages (another step, the check again,
  /// another gateway) closes their page-only choices.
  void _resetStationPages(CommissionState? previous, CommissionState next) {
    final open = next.step == 2 && next.checkPassed;
    if (!open ||
        previous?.peer != next.peer ||
        (previous?.config['new_station'] == true &&
            next.config['choose_station'] == true)) {
      _otherSite = false;
      _wifiStage = false;
      _replaceSlot = null;
      _swap = null;
    }
  }

  /// The station the page proposes as 「本站」: the station of a gateway in
  /// service, or for a new identity the one it already carries or the one
  /// just done (〔配置下一台〕); null when there is none to propose.
  int? _stationCurrent(CommissionState s) {
    final config = s.config;
    if (config['choose_station'] == true || config['new_station'] == true) {
      return (config['site_id'] as num?)?.toInt();
    }
    if (config['suggested_site_known'] == true) {
      return (config['suggested_site_id'] as num?)?.toInt();
    }
    return null;
  }

  /// The station page shows the input (not the question).
  bool _stationInput(CommissionState s) =>
      _otherSite ||
      s.config['new_station'] == true ||
      _stationCurrent(s) == null;

  /// The typed station, when valid.
  int? get _typedSite {
    final value = int.tryParse(_site.text);
    return value != null && value >= 1 && value <= 65535 ? value : null;
  }

  /// Read-only auto-numbering shown next to the site ID field: how the last
  /// [_refreshGatewaySuggestion] answered (online / BLE-name fallback / the
  /// site's 1–[kMaxGatewayId] are all taken), and whether a lookup is in flight.
  GatewaySuggestKind _gatewayKind = GatewaySuggestKind.online;
  bool _suggestingGateway = false;
  Timer? _suggestTyping;
  static const _suggestPause = Duration(milliseconds: 500);

  /// Bumped on every call so a slower, older lookup cannot overwrite a
  /// newer one's result when the user types quickly.
  int _suggestGeneration = 0;

  /// Debounced: recomputes the auto gateway number for the typed site ID.
  void _scheduleGatewaySuggestion() {
    _suggestTyping?.cancel();
    _suggestTyping = Timer(_suggestPause, _refreshGatewaySuggestion);
  }

  Future<void> _refreshGatewaySuggestion() async {
    final site = int.tryParse(_site.text);
    if (site == null || site < 1 || site > 65535) return;
    final generation = ++_suggestGeneration;
    setState(() => _suggestingGateway = true);
    final (gw, kind) = await ref
        .read(commissionProvider.notifier)
        .suggestGateway(site);
    if (!mounted || generation != _suggestGeneration) return;
    setState(() {
      if (kind != GatewaySuggestKind.full) _gateway.text = '$gw';
      _gatewayKind = kind;
      _suggestingGateway = false;
      // 1.0.0+13: the station's automatic number (an old gateway chosen
      // for another station no longer applies).
      _clearSwap();
    });
  }

  /// Local mode: the user edits only the PC's IPv4; mirrors the provider.
  final _host = TextEditingController();

  BackendEnvController get _envController =>
      ref.read(backendEnvProvider.notifier);

  /// Typing in 其他網址 is applied after a pause, so the login and the
  /// backend check are not redone on every keystroke.
  Timer? _baseTyping;
  static const _typingPause = Duration(milliseconds: 600);

  void _onBaseEdited() {
    if (ref.read(backendEnvProvider).environment != BackendEnv.custom) return;
    if (_base.text == ref.read(backendEnvProvider).customUrl) return;
    _baseTyping?.cancel();
    _baseTyping = Timer(_typingPause, _flushBase);
  }

  /// Applies a typed 其他網址 now (before it is used, or on a switch).
  void _flushBase() {
    final pending = _baseTyping;
    _baseTyping = null;
    pending?.cancel();
    if (!mounted) return;
    if (ref.read(backendEnvProvider).environment == BackendEnv.custom) {
      _envController.setCustomUrl(_base.text);
    }
  }

  /// Keeps the text fields in step with the shared environment state.
  void _onEnvironment(BackendEnvState? previous, BackendEnvState next) {
    if (_host.text != next.localHost) _host.text = next.localHost;
    // Rewrite the URL field only when the URL itself changed, and never just
    // to trim it (that would move the cursor while typing).
    if ((previous == null ||
            previous.base != next.base ||
            previous.environment != next.environment) &&
        _base.text.trim() != next.base) {
      _baseTyping?.cancel();
      _baseTyping = null;
      _base.text = next.base;
    }
    if (previous != null && previous.base != next.base) {
      ref.read(commissionProvider.notifier).backendChanged(next.base);
    }
    final hint = environmentChangeHint(
      previous,
      next,
      buildDefault: ref.read(envSwitchPolicyProvider).defaultEnvironment,
    );
    if (hint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _snack(hint));
    }
    if (mounted) setState(() {});
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Connects to [peer] from the gateway list and fills the forms.
  Future<void> _connectPeer(CommissioningController c, GatewayPeer peer) async {
    _connectingPeer = true;
    _autoCheckPaused = false;
    try {
      await c.connect(peer);
      if (mounted && _pageScroll.hasClients) _pageScroll.jumpTo(0);
      if (mounted) {
        final next = ref.read(commissionProvider);
        _site.text = _proposedSiteText(next.config);
        _gateway.text =
            '${next.config['suggested_gateway_id'] ?? next.config['gateway_id'] ?? 1}';
        _gatewayKind = next.config['suggested_offline'] == true
            ? GatewaySuggestKind.offline
            : GatewaySuggestKind.online;
        _clearSwap();
        _ssid.text = next.config['wifi_ssid']?.toString() ?? '';
        _customWifi = false;
        // Remembered environment: sync the gateway to it.
        if (next.error == null && next.step >= 2) {
          await _syncGateway(explicit: false);
        }
        await _askTopology();
      }
    } finally {
      if (mounted) setState(() => _connectingPeer = false);
    }
  }

  /// The station field's first value: a new gateway without a station to
  /// propose ([_stationCurrent] null) starts empty, so the number is typed
  /// on site, never a guess accepted by mistake (backlog K).
  String _proposedSiteText(Map<String, dynamic> config) {
    if (config['fleet_joined'] != true &&
        config['suggested_site_known'] != true) {
      return '';
    }
    return '${config['suggested_site_id'] ?? config['site_id'] ?? 1}';
  }

  Future<void> _openEnvironmentSheet() async {
    final choice = await showEnvironmentSheet(context);
    if (choice == null || !mounted) return;
    await _applyEnvironment(choice, fromSheet: true);
  }

  /// One switch for everything: the APP backend and, when a gateway is
  /// connected, its upload target. Refused while a step is running.
  Future<void> _applyEnvironment(
    BackendEnv choice, {
    bool fromSheet = false,
  }) async {
    final current = ref.read(commissionProvider);
    if (current.busy) {
      _snack(switchBlockedText(current));
      return;
    }
    _flushBase();
    await _envController.select(choice);
    if (!mounted) return;
    // Mid-flow the old login no longer applies; on the local test host log
    // in again right away with the build's credential (other sites log in
    // when they are needed).
    final env = ref.read(backendEnvProvider);
    final state = ref.read(commissionProvider);
    if (state.step >= 1 &&
        !state.loggedIn &&
        !_offline &&
        env.environment == BackendEnv.local &&
        env.localValid &&
        ref.read(backendKeyProvider).isNotEmpty) {
      await ref.read(commissionProvider.notifier).login(env.base);
      if (!mounted) return;
    }
    await _syncGateway(explicit: true, announce: fromSheet);
  }

  /// Brings the connected gateway's upload target in line with the selected
  /// environment. [explicit]: the user asked (switch / 「同步」); otherwise it
  /// is the automatic sync after connecting, gated by the auto-sync setting.
  Future<void> _syncGateway({
    required bool explicit,
    bool announce = false,
  }) async {
    final env = ref.read(backendEnvProvider);
    final state = ref.read(commissionProvider);
    if (state.busy) return;
    // Let the installer resolve Wi-Fi before an automatic target reboot.
    if (!explicit && state.netCheckSupported && state.wifi != WifiVerdict.ok) {
      return;
    }
    final (need, target) = uploadSyncNeed(state, env.uploadTarget);
    switch (need) {
      case SyncNeed.none:
        if (announce) {
          final connected = state.peer != null && state.step >= 2;
          _snack(
            connected
                ? '已切換到${env.label}。'
                : '已切換到${env.label}。${env.autoSync ? '連上閘道器後會自動讓它一起切換。' : '連上閘道器後可在「連線狀態」按「同步」。'}',
          );
        }
      case SyncNeed.legacy:
        if (explicit || announce) {
          _snack(legacyTargetText(state.config['fw_version']));
        }
      case SyncNeed.invalid:
        if (explicit || announce) _snack(env.uploadTarget.error!);
      case SyncNeed.sync:
        if (!explicit && !env.autoSync) return;
        final policy = ref.read(envSwitchPolicyProvider);
        if (policy.confirmGatewaySwitch) {
          final ok = await confirmUploadTargetSwitch(context, wanted: target!);
          if (!ok || !mounted) return;
        } else {
          _snack('正在把閘道器切到${target!.plainLabel}，約 1 分鐘，請留在閘道器旁。');
        }
        // Without Wi-Fi the upload cannot start: do not wait for it.
        final wifi = ref.read(commissionProvider).wifi;
        await ref
            .read(commissionProvider.notifier)
            .switchUploadTarget(
              target,
              waitUpload:
                  wifi != WifiVerdict.failed &&
                  wifi != WifiVerdict.notConfigured,
            );
    }
  }

  /// 「重設 Wi-Fi」 / 「設定 Wi-Fi」 in the network check. When the upload
  /// target must change too it is switched first (one reboot, see
  /// [CommissioningController.startWifiFix]), then the Wi-Fi form opens.
  Future<void> _fixWifi() async {
    final s = ref.read(commissionProvider);
    if (s.busy) return;
    final env = ref.read(backendEnvProvider);
    MqttTarget? target;
    final (need, wanted) = uploadSyncNeed(s, env.uploadTarget);
    if (need == SyncNeed.sync) {
      final policy = ref.read(envSwitchPolicyProvider);
      final ok =
          !policy.confirmGatewaySwitch ||
          await confirmUploadTargetSwitch(context, wanted: wanted!);
      if (!mounted) return;
      if (ok) target = wanted;
    }
    await ref.read(commissionProvider.notifier).startWifiFix(target: target);
    if (!mounted) return;
    final next = ref.read(commissionProvider);
    if (next.step == 2 && next.checkPassed) {
      setState(() {
        _site.text = _proposedSiteText(next.config);
        _gateway.text =
            '${next.config['suggested_gateway_id'] ?? next.config['gateway_id'] ?? 1}';
        _gatewayKind = next.config['suggested_offline'] == true
            ? GatewaySuggestKind.offline
            : GatewaySuggestKind.online;
        _clearSwap();
        _ssid.text = next.config['wifi_ssid']?.toString() ?? '';
        _wifi.clear();
        _customWifi = false;
      });
    }
  }

  /// 「全部重新配置」：清空 assignedOk，讓所有已勾選的台重新指派一次；
  /// 二次確認以免手滑蓋掉已成功的台。
  Future<void> _reconfigureAll(CommissioningController controller) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全部重新配置？'),
        content: const Text('已成功指派的台也會重新指派一次，確定要繼續嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('全部重新配置'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final warning = controller.starFullWarning;
    if (warning != null) {
      _snack(warning);
      return;
    }
    controller.configurePtus();
  }

  /// 「儲存並連接 WiFi」 for a new station: pre-checks (site, gateway) for an
  /// existing MAC before committing, so a conflict can offer 「取代舊機」 or
  /// 「下一個編號」 instead of just failing with a generic error.
  Future<void> _saveWifi(bool wifiOnly) async {
    final c = ref.read(commissionProvider.notifier);
    // 1.0.0+15: the Wi-Fi-first form of a gateway not in service — the
    // Wi-Fi only; the station is chosen after it joined.
    if (wifiOnly && ref.read(commissionProvider).config[wifiFirstKey] == true) {
      await c.configureWifiFirst(_ssid.text, _wifi.text);
      _wifi.clear();
      return;
    }
    final site = int.tryParse(_site.text) ?? 0;
    var gw = int.tryParse(_gateway.text) ?? 0;
    // Round 30: a kept Wi-Fi ([keptWifiSsid]) is sent without a password
    // (an old one typed before is not used).
    final kept = keptWifiSsid(ref.read(commissionProvider));
    if (!wifiOnly && !_customWifi && kept != null && _ssid.text == kept) {
      _wifi.clear();
    }
    // 上次「取代舊機」在後台已成功，只差寫入裝置失敗：直接以同樣的取代設定
    // 重試，不必再跳一次確認對話框（也不必重打一次 reserve-identity）。
    if (!wifiOnly && c.pendingReplace) {
      await c.configureWifi(
        site,
        gw,
        _ssid.text,
        _wifi.text,
        replaceExisting: true,
      );
      _wifi.clear();
      return;
    }
    // r33: 〔取代舊機〕 was chosen on the 「閘道器編號已被使用」 question;
    // 1.0.0+13: or the old gateway on 〔這台是來換掉壞掉的舊機〕 ([_swap]).
    final swap = _swap;
    final swapping = swap != null && (swap.site, swap.gateway) == (site, gw);
    if (!wifiOnly && (swapping || _replaceSlot == (site, gw))) {
      // 1.0.0+13: asked once more right before it is sent — an old gateway
      // online (again) is never replaced (two gateways on one number).
      final online = await c.gatewayOnline(site, gw);
      if (!mounted) return;
      if (online == true) {
        await _replaceRefused(gw);
        return;
      }
      // 換機 takes over only a gateway known to be offline (r33's
      // 〔取代舊機〕: unknown goes on as before).
      if (swapping && online == null) {
        _snack(swapNeedsNetworkText);
        return;
      }
      _replaceSlot = null;
      await c.configureWifi(
        site,
        gw,
        _ssid.text,
        _wifi.text,
        replaceExisting: true,
      );
      _wifi.clear();
      return;
    }
    if (!wifiOnly) {
      final conflictMac = await c.conflictingMac(site, gw);
      if (conflictMac != null && mounted) {
        // r33: the back office's own conflict text, when it flags one.
        final conflict = await c.identityConflict(site, gw);
        // 1.0.0+13: an old gateway online is never replaced (unknown: as
        // before).
        final online = await c.gatewayOnline(site, gw);
        if (!mounted) return;
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('save-number-taken'),
            title: const Text('編號已被使用'),
            content: Text(
              '站點 $site / 閘道器 $gw 目前登記給另一台裝置（MAC $conflictMac）。\n'
              '${conflict == null ? '' : '$conflict\n'}'
              '${online == true ? numberTakenOnlineText(gw) : '請先確認舊機已斷電，否則後台會再次標記衝突。'}',
            ),
            actions: [
              if (online != true)
                TextButton(
                  key: const Key('save-number-taken-replace'),
                  onPressed: () => Navigator.pop(context, 'replace'),
                  child: const Text('取代舊機（沿用此編號）'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'next'),
                child: const Text('改用下一個可用編號'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        );
        if (action == null) return;
        if (action == 'next') {
          for (gw = gw + 1; gw <= kMaxGatewayId; gw++) {
            if (await c.conflictingMac(site, gw) == null) break;
          }
          if (gw > kMaxGatewayId) {
            _snack('站點 $site 的 1–$kMaxGatewayId 號閘道器都已被使用，請確認站點 ID 是否正確。');
            return;
          }
          if (mounted) setState(() => _gateway.text = '$gw');
        }
        if (!mounted) return;
        await c.configureWifi(
          site,
          gw,
          _ssid.text,
          _wifi.text,
          replaceExisting: action == 'replace',
        );
        _wifi.clear();
        return;
      }
    }
    await c.configureWifi(site, gw, _ssid.text, _wifi.text);
    _wifi.clear();
  }

  bool _scanningWifi = false;
  bool _customWifi = false;
  Future<void> _chooseWifi() async {
    FocusScope.of(context).unfocus();
    setState(() => _scanningWifi = true);
    try {
      var networks = <WifiNetwork>[];
      String? scanMessage;
      try {
        networks = await scanWifiNetworks();
      } catch (error) {
        final code = error is PlatformException ? error.code : '';
        scanMessage = switch (code) {
          'permission' => '請允許精確位置權限後重試，或選擇自訂網路。',
          'wifi_off' => '請開啟手機 Wi-Fi 後重試，或選擇自訂網路。',
          'location_off' => '請開啟手機定位服務後重試，或選擇自訂網路。',
          'throttled' => '掃描太頻繁，請稍候重試，或選擇自訂網路。',
          'unsupported' => 'iOS 不支援掃描周邊 Wi-Fi，請選擇自訂網路。',
          _ => '掃描未完成，請重試或選擇自訂網路。',
        };
      }
      if (!mounted || ref.read(commissionProvider).step != 2) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('選擇 2.4 GHz Wi-Fi'),
          children: [
            if (networks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(scanMessage ?? '未找到周邊 2.4 GHz Wi-Fi，可稍後重試或選擇自訂網路。'),
              ),
            ...networks.map(
              (network) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, network.ssid),
                child: ListTile(
                  leading: const Icon(Icons.wifi),
                  title: Text(network.ssid),
                  subtitle: Text('訊號 ${network.rssi} dBm'),
                ),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('自訂／隱藏網路'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (mounted &&
          selected != null &&
          ref.read(commissionProvider).step == 2) {
        setState(() {
          if (_ssid.text != selected) _wifi.clear();
          _ssid.text = selected;
          _customWifi = selected.isEmpty;
        });
      }
    } catch (error) {
      if (!mounted) return;
      final code = error is PlatformException ? error.code : '';
      final message = switch (code) {
        'permission' => '掃描 Wi-Fi 需要位置權限，請允許精確位置後重試。',
        'wifi_off' => '請先開啟手機 Wi-Fi。',
        'location_off' => '請先開啟手機定位服務，再重新掃描。',
        'throttled' => '系統暫時限制掃描，請稍候再試，或手動輸入名稱。',
        'unsupported' => 'iOS 不支援掃描周邊 Wi-Fi，請手動輸入名稱。',
        _ => 'Wi-Fi 掃描未完成，請重試或手動輸入名稱。',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _scanningWifi = false);
    }
  }

  /// Round 19 (field round 19: the back office flashed the pile and the
  /// installer never knew): its identify ack as a passing snack bar — over
  /// the page, never moving it, and changing nothing in the flow.
  ///
  /// Round 20 (field round 20: at direct step 7 the snack bar covered the
  /// card's yellow box for 8 s): with the direct bar's identify line on
  /// screen the notice goes there instead ([DirectPickActions]); the snack
  /// bar stays for every other page.
  void _showRemoteIdentify(CommissionState? previous, CommissionState next) {
    if (previous == null ||
        next.remoteIdentifyCount == previous.remoteIdentifyCount ||
        next.remoteIdentifyNote.isEmpty ||
        !mounted) {
      return;
    }
    if (directPickBarShown(
          next,
          directFlow: ref.read(commissionProvider.notifier).directFlow,
        ) &&
        next.config['identify_supported'] == true) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('remote-identify'),
          content: Text(next.remoteIdentifyNote),
          duration: const Duration(seconds: 8),
          showCloseIcon: true,
        ),
      );
  }

  /// Step 6 already started its automatic verification for this entry.
  bool _autoVerifyStarted = false;

  bool get _canAutoAct =>
      mounted &&
      _foreground &&
      !_connectingPeer &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  /// Queue at most one action, then re-read state after the frame. Never
  /// reuse a captured state after a back action, disconnect, or dialog.
  void _scheduleAutoFlow(CommissionState s) {
    if (s.step != 3) _autoOnlineStarted = false;
    if (s.step != 6) _autoVerifyStarted = false;
    if (_autoFlowScheduled || !_canAutoAct) return;
    final action = _automaticAction(s);
    if (action == null) return;
    final peer = s.peer;
    final base = ref.read(backendEnvProvider).base;
    _autoFlowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoFlowScheduled = false;
      if (!_canAutoAct) return;
      final current = ref.read(commissionProvider);
      if (current.peer != peer ||
          ref.read(backendEnvProvider).base != base ||
          _automaticAction(current) != action) {
        return;
      }
      final c = ref.read(commissionProvider.notifier);
      if (action == 2) {
        await c.passNetworkCheck();
      } else if (action == 3) {
        _autoOnlineStarted = true;
        final env = ref.read(backendEnvProvider);
        await c.online(base: env.base, environment: env.environment.name);
      } else {
        _autoVerifyStarted = true;
        await _startVerify();
      }
      if (mounted) setState(() {});
    });
  }

  int? _automaticAction(CommissionState s) {
    if (s.busy ||
        s.error != null ||
        s.peer == null ||
        s.relinking ||
        s.resumePending ||
        s.reconnectFailed ||
        s.savedResume ||
        s.gatewayReboot != null) {
      return null;
    }
    if (s.step == 2 &&
        !s.checkPassed &&
        !_autoCheckPaused &&
        networkCheck(state: s, env: ref.read(backendEnvProvider)).ready) {
      return 2;
    }
    if (s.step == 3 && !_autoOnlineStarted && s.loggedIn && !s.offline) {
      return 3;
    }
    if (s.step == 6 &&
        !_autoVerifyStarted &&
        s.loggedIn &&
        s.ptus.any((p) => s.selected.contains(p['mac']))) {
      return 6;
    }
    return null;
  }

  void _reviewNetworkCheck() {
    _autoCheckPaused = true;
    ref.read(commissionProvider.notifier).backToNetworkCheck();
  }

  /// Round 29 (field drill: the done page opened scrolled down, on the
  /// 連線狀態 panel and the 「切回正式站」 box): the done page starts at its
  /// summary.
  void _showDoneFromTop(CommissionState? previous, CommissionState next) {
    if (next.step != 7 || previous?.step == 7) return;
    _toTop();
  }

  /// One-thing screens (09-28): the station, Wi-Fi and check pages each
  /// start at their task sentence (a button at the end of one page must
  /// not leave the next one scrolled to its middle).
  void _showStepPageFromTop(CommissionState? previous, CommissionState next) {
    if (previous == null || next.step != 2) return;
    String page(CommissionState s) => [
      s.step,
      s.checkPassed,
      s.config['choose_station'] == true,
      s.config['wifi_only'] == true,
      s.config['new_station'] == true,
      s.config[wifiFirstKey] == true,
    ].join('/');
    if (page(previous) != page(next)) _toTop();
  }

  void _toTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageScroll.hasClients) _pageScroll.jumpTo(0);
    });
  }

  /// One-thing screens (09-28): the one sentence at the top of every page
  /// but the done page — what this page asks, or what runs by itself.
  String _taskTitle(CommissionState s, BackendEnvState env) {
    final directFlow = ref.read(commissionProvider.notifier).directFlow;
    switch (s.step) {
      case 0:
        return startTaskTitle;
      case 1:
        return s.busy ? checkingTaskTitle : pickGatewayTaskTitle;
      case 2:
        if (!s.checkPassed) {
          final check = networkCheck(state: s, env: env);
          if (s.testMode) return testModeTaskTitle;
          if (check.ready) {
            return _autoCheckPaused ? checkPassedTaskTitle : checkingTaskTitle;
          }
          if (check.wifiProblem) return wifiProblemTaskTitle;
          if (!check.targetOk) return targetTaskTitle;
          if (check.uploadPaused) return uploadPausedTaskTitle;
          if (check.upload.tone == StatusTone.bad) return uploadBadTaskTitle;
          return checkingTaskTitle;
        }
        if (wifiFormOfCheck(s) ||
            (_wifiStage && s.config['choose_station'] != true)) {
          return wifiTaskTitle;
        }
        final current = _stationCurrent(s);
        return current != null && !_stationInput(s)
            ? stationQuestionTitle(current)
            : stationInputTitle;
      case 3:
        return s.busy || (s.loggedIn && !s.offline && s.error == null)
            ? onlineRunningTaskTitle
            : onlineTaskTitle;
      case 4:
        return directFlow ? directPickTaskTitle : starPickTaskTitle;
      case 5:
      case 6:
        if (!directFlow) {
          return s.step == 5 ? starAssignTaskTitle : starVerifyTaskTitle;
        }
        return s.step == 6 && !s.loggedIn
            ? verifyLoginTaskTitle
            : finishingTaskTitle;
      default:
        return '';
    }
  }

  /// 09-28: no password field; an empty password logs in with the build's
  /// backend credential (commissioning_controller `_passwordFor`).
  Future<void> _startVerify() async {
    _flushBase();
    final current = ref.read(backendEnvProvider);
    await ref
        .read(commissionProvider.notifier)
        .verify(current.base, '', environment: current.environment.name);
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(backendEnvProvider, _onEnvironment, fireImmediately: true);
    ref.listenManual(commissionProvider, _showDoneFromTop);
    ref.listenManual(commissionProvider, _showStepPageFromTop);
    ref.listenManual(commissionProvider, _resetStationPages);
    ref.listenManual(commissionProvider, _showRemoteIdentify);
    _host.addListener(() => _envController.setLocalHost(_host.text));
    _base.addListener(_onBaseEdited);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(commissionProvider.notifier).restore(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    ref.read(commissionProvider.notifier).setForeground(_foreground);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    _gatewayChoice.dispose();
    _baseTyping?.cancel();
    _suggestTyping?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_base, _host, _ssid, _wifi, _site, _gateway]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget button(String label, VoidCallback action, bool enabled) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? action : null,
        child: Text(label),
      ),
    ),
  );
  Widget field(
    TextEditingController c,
    String label, {
    bool secret = false,
    bool number = false,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      obscureText: secret,
      autocorrect: !secret,
      enableSuggestions: !secret,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    ),
  );

  /// Read-only auto-numbering shown instead of an editable 閘道器編號 field
  /// (1.0.0+13: the number is always automatic — 1.0.0+12's 〔修改〕 number
  /// picker is gone). [swap] (the station page): 〔這台是來換掉壞掉的舊機〕
  /// below it ([_swapEntry]).
  Widget _gatewayAssignment({bool enabled = true, bool swap = false}) {
    final colors = Theme.of(context).colorScheme;
    if (_suggestingGateway) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text('正在計算閘道器編號…'),
      );
    }
    final chosen = _swap;
    final Widget line;
    if (_gatewayKind == GatewaySuggestKind.full && chosen == null) {
      line = Text(
        '本站閘道器已滿（1–$kMaxGatewayId 皆已使用），請確認站點 ID 或改用「$swapLabel」。',
        style: TextStyle(color: colors.error),
      );
    } else {
      final String hint;
      if (chosen != null) {
        hint = swapAssignmentHint(chosen.tail);
      } else {
        hint = _gatewayKind == GatewaySuggestKind.offline
            ? ref.read(commissionProvider).peers.isEmpty
                  ? '（無法取得同站閘道器清單，暫配 1 號，請上線核對）'
                  : '（離線配號，上線後會再核對）'
            : '';
      }
      line = Text(
        '將配置為 站點 ${_site.text} / 閘道器 ${_gateway.text}$hint',
        key: const Key('gateway-assignment'),
        style: TextStyle(color: colors.primary),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [line, if (swap) _swapEntry(enabled)],
      ),
    );
  }

  /// 1.0.0+13: the back office can be asked (logged in, the number was not
  /// guessed offline) — 換機 needs its list of offline gateways.
  bool get _swapAvailable =>
      ref.read(commissionProvider).loggedIn &&
      _gatewayKind != GatewaySuggestKind.offline;

  /// 1.0.0+13, under 「將配置為 …」 on the station page: 〔這台是來換掉壞掉
  /// 的舊機〕 ([_chooseSwap]), 〔取消換機〕 once an old gateway was chosen,
  /// or 「換機需要連上網路」 when the back office cannot be asked. A
  /// secondary way: the normal install never needs it.
  Widget _swapEntry(bool enabled) {
    final theme = Theme.of(context);
    if (_typedSite == null) return const SizedBox.shrink();
    if (!_swapAvailable) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          swapNeedsNetworkText,
          key: const Key('gateway-swap-offline'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final chosen = _swap != null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton.icon(
        key: Key(chosen ? 'gateway-swap-cancel' : 'gateway-swap'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: enabled && !_stationWorking
            ? (chosen ? _cancelSwap : _chooseSwap)
            : null,
        icon: Icon(chosen ? Icons.undo : Icons.swap_horiz, size: 20),
        label: Text(chosen ? swapCancelLabel : swapLabel),
      ),
    );
  }

  /// 1.0.0+13: no old gateway chosen (nor a replacement asked for).
  void _clearSwap() {
    _swap = null;
    _replaceSlot = null;
  }

  /// 1.0.0+13 〔這台是來換掉壞掉的舊機〕: the station's gateways the back
  /// office lists as offline (not this one) in a sheet; one picked and
  /// confirmed (「這台將接手 站 S · 閘道器 N。舊機（…XXXX）必須已拆除或斷電。」)
  /// becomes the number shown, sent through the existing replacement
  /// (reserve-identity force_replace first, [_saveWifi]).
  Future<void> _chooseSwap() async {
    final c = ref.read(commissionProvider.notifier);
    if (ref.read(commissionProvider).busy || _stationWorking) return;
    // A station typed a moment ago: its lookup first.
    if (_suggestTyping?.isActive ?? false) {
      _suggestTyping!.cancel();
      await _refreshGatewaySuggestion();
      if (!mounted) return;
    }
    final site = _typedSite;
    if (site == null) return;
    setState(() => _stationWorking = true);
    List<SwapCandidate>? candidates;
    try {
      candidates = await c.swapCandidates(site);
    } finally {
      if (mounted) setState(() => _stationWorking = false);
    }
    if (!mounted) return;
    if (candidates == null) {
      _snack(swapNeedsNetworkText);
      return;
    }
    final old = await showGatewaySwapSheet(
      context,
      site: site,
      candidates: candidates,
    );
    if (!mounted || old == null) return;
    if (!await _confirmSwap(site, old) || !mounted) return;
    if (_typedSite != site) return;
    setState(() {
      // A lookup still running no longer applies.
      _suggestGeneration++;
      _suggestingGateway = false;
      _clearSwap();
      _swap = old;
      _gateway.text = '${old.gateway}';
    });
  }

  /// 1.0.0+13: 「這台將接手 站 S · 閘道器 N。舊機（…XXXX）必須已拆除或斷電。」
  /// 〔確定換機〕／〔取消〕.
  Future<bool> _confirmSwap(int site, SwapCandidate old) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('swap-confirm'),
        title: const Text(swapConfirmTitle),
        content: Text(
          swapConfirmText(site, old.gateway, old.tail),
          key: const Key('swap-confirm-text'),
        ),
        actions: [
          TextButton(
            key: const Key('swap-confirm-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('swap-confirm-ok'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(swapConfirmOkLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 1.0.0+13 〔取消換機〕: the station's automatic number again.
  Future<void> _cancelSwap() async {
    setState(_clearSwap);
    await _refreshGatewaySuggestion();
  }

  /// 1.0.0+13: the old gateway to be replaced (換機, or r33's 〔取代舊機〕)
  /// is online (again) right before it would be sent — nothing is sent;
  /// 「閘道器 N 目前在線上，請先把舊機斷電。」, then the station page with its
  /// automatic number.
  Future<void> _replaceRefused(int gw) async {
    setState(() {
      _clearSwap();
      _wifiStage = false;
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('swap-online'),
        content: Text(swapOnlineText(gw)),
        actions: [
          FilledButton(
            key: const Key('swap-online-ok'),
            onPressed: () => Navigator.pop(context),
            child: const Text(swapOnlineOkLabel),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _refreshGatewaySuggestion();
  }

  /// Round 16: star mode 「每台 PTU 數」 — chosen in a dialog and confirmed
  /// with a snackbar; the topology switch never writes it.
  Future<void> _pickStarCount() async {
    final current = ref.read(topologyProvider).starCount;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        key: const Key('star-count-dialog'),
        title: const Text('星狀模式：每台 PTU 數'),
        children: [
          for (var n = minStarPtuCount; n <= maxStarPtuCount; n++)
            SimpleDialogOption(
              key: ValueKey('star-count-$n'),
              onPressed: () => Navigator.pop(context, n),
              child: Row(
                children: [
                  Icon(
                    n == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('$n 台'),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || picked == null || picked == current) return;
    await ref.read(topologyProvider.notifier).setStarCount(picked);
    if (mounted) _snack('星狀模式每台 PTU 數已改為 $picked 台');
  }

  /// Blocks 「儲存並連接 WiFi」 when the site's 1–[kMaxGatewayId] gateway slots
  /// are full (1.0.0+13: unless an old gateway is replaced, [_swap]).
  bool get _gatewaySubmitBlocked =>
      _swap == null && _gatewayKind == GatewaySuggestKind.full;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commissionProvider),
        controller = ref.read(commissionProvider.notifier);
    final demo = ref.watch(demoProvider),
        colors = Theme.of(context).colorScheme;
    final env = ref.watch(backendEnvProvider);
    _scheduleAutoFlow(state);
    final topologySettings = ref.watch(topologyProvider);
    final topology = topologySettings.topology;
    final targetPtuCount = topologySettings.targetCount;
    final shown = displayStep(state, env);
    final selectingPtus = state.step == 4 || state.step == 5;
    // Round 15: direct flow step 7 — the gateway's own pick with
    // 「辨識此樁」/「是這台，開始監控」; a link loss or a resume keeps the
    // reconnect button below.
    final directPicking = directPickBarShown(
      state,
      directFlow: controller.directFlow,
    );
    final checkNext = _checkNext(state, controller, env);
    // Round 29 (field drill: 「不知道該如何結束」): the done page — the
    // summary on top, 〔完成〕／〔配置下一台〕 fixed at the bottom.
    final done = state.step == 7;
    // One-thing screens (09-28): the gateway's identify stays on the page
    // where PTUs are chosen in a list (star, old firmware); elsewhere it is
    // in 「設備與連線資訊」 (the direct pick has its own in the bottom bar).
    final identifyAt =
        state.peer != null && state.step >= 2 && !directPicking && !done;
    final identifyOnPage =
        selectingPtus || (state.step == 6 && !controller.directFlow);
    // The connection panel stays on the page while something is wrong (with
    // its 「同步」); all fine, its one line is in 「設備與連線資訊」. The
    // station and Wi-Fi pages (the check passed or skipped) say what blocks
    // them themselves, and the check has the fixes: there it is in the
    // details too — unless it warns of a weak Wi-Fi (advice kept in sight).
    final stationPages = state.step == 2 && state.checkPassed;
    final panelAt = state.peer != null && state.step >= 2;
    final status = panelAt && !done
        ? connectionStatus(
            env: env,
            state: state,
            probe: demo
                ? null
                : ref.watch(backendProbeProvider(env.base)).value,
            demo: demo,
          )
        : null;
    final panelOk =
        status != null &&
        (status.allOk || (stationPages && status.wifiWeak == null));
    // 09-28: the automatic step as a checklist that fills in one item at a
    // time (replaces 「處理中 · 最多等待 N 秒」 there; the seconds stay, small).
    final checklist = shownChecklist(
      state,
      check: state.step == 2 && !state.checkPassed
          ? networkCheck(state: state, env: env)
          : null,
    );
    return PopScope(
      // Round 28 (field round 28: a system 返回 at step 7 left the APP at
      // once, mid-configuration): only the start page and the gateway list
      // (nothing running) leave the APP. Otherwise 返回 asks 「結束目前
      // 配置？」 first, like 「結束並重新選擇閘道器」 ([_backPressed]); 結束
      // then also puts back a temporary 「不是這台？」 binding (round 15b).
      // Round 29: on the done page 返回 is 〔完成〕 (nothing to ask).
      // 09-29: the gateway list no longer leaves the APP — 返回 there is
      // 〔結束配置〕 (back to the start page, no question asked).
      canPop: state.step == 0 && !state.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backPressed(controller);
      },
      child: Scaffold(
        appBar: AppBar(
          // 1.0.0+10 (phone 360 dp at text scale 1.1: 「GIOS 現場…」 beside
          // the help icon): the theme's AppBar title style (titleMedium
          // w600, [gatewayTheme]) on every page — no size picked by width;
          // the help icon compact and the environment chip small leave it
          // room whole up to text scale 1.3.
          title: const Text(
            appBarTitle,
            key: Key('appbar-title'),
            maxLines: 1,
            softWrap: false,
          ),
          actions: [
            // Field rescue v1: no error, but the installer does not know
            // what to do next.
            if (state.step > 0 && !demo && controller.fieldHelpAvailable)
              IconButton(
                key: const Key('field-help-appbar'),
                icon: const Icon(Icons.support_agent),
                tooltip: fieldHelpLabel,
                visualDensity: VisualDensity.compact,
                onPressed: () => openFieldHelp(context, ref),
              ),
            EnvironmentChip(onPressed: _openEnvironmentSheet),
            // ⋮: the topology items first (拓撲模式（進階）: 直連／星狀, the
            // star 「每台 PTU 數」, 直連進階設定 — greyed while busy), then
            // 「閘道器狀態…」, then the theme. One button keeps 360 dp free.
            PopupMenuButton<String>(
              key: const Key('topology-menu'),
              tooltip: '更多',
              onSelected: (value) {
                if (value.startsWith('topology:')) {
                  final t = GatewayTopology.values.firstWhere(
                    (t) => t.name == value.substring('topology:'.length),
                  );
                  // Round 22: at step 7 the old mode's list is dropped and
                  // read again (field: direct → star kept 「配置 1 台」).
                  controller.switchTopology(t);
                } else if (value == 'starcount') {
                  _pickStarCount();
                } else if (value == 'direct:settings') {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const DirectSettingsSheet(),
                  );
                } else if (value == 'status') {
                  GatewayStatusPage.open(context);
                } else if (value.startsWith('theme:')) {
                  widget.onThemeChanged(
                    ThemeMode.values.firstWhere(
                      (m) => m.name == value.substring('theme:'.length),
                    ),
                  );
                }
              },
              itemBuilder: (context) {
                final heading = Theme.of(context).textTheme.labelSmall;
                return [
                  PopupMenuItem<String>(
                    key: const Key('topology-heading'),
                    enabled: false,
                    height: 32,
                    child: Text(
                      state.busy ? '拓撲模式（操作進行中，完成後才能切換）' : '拓撲模式（進階）',
                      style: heading,
                    ),
                  ),
                  for (final t in GatewayTopology.values)
                    CheckedPopupMenuItem(
                      value: 'topology:${t.name}',
                      checked: t == topology,
                      enabled: !state.busy,
                      child: Text(t.label),
                    ),
                  // 直連進階設定：只在直連、且已連上支援直連選台的韌體時出現。
                  if (topology.isDirect &&
                      state.peer != null &&
                      directAutoConnectSupported(state.config))
                    PopupMenuItem(
                      key: const Key('direct-settings'),
                      value: 'direct:settings',
                      enabled: !state.busy,
                      child: const Text('直連進階設定…'),
                    ),
                  // Round 16: the star count opens its own dialog — one
                  // mis-tap beside the topology items no longer changes it.
                  if (topology.isStar)
                    PopupMenuItem(
                      key: const Key('star-count'),
                      value: 'starcount',
                      enabled: !state.busy,
                      child: Text('每台 PTU 數：${topologySettings.starCount}…'),
                    ),
                  const PopupMenuDivider(),
                  // 1.0.0+5: 「閘道器狀態」 from any page (the flow untouched).
                  // 1.0.0+10: greyed while a run is busy or a gateway is
                  // connected ([gatewayStatusMenuEnabled]).
                  PopupMenuItem(
                    key: const Key('gateway-status-menu'),
                    value: 'status',
                    enabled: gatewayStatusMenuEnabled(state),
                    child: Text(gatewayStatusMenuText(state)),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 32,
                    child: Text('主題', style: heading),
                  ),
                  for (final (mode, label) in const [
                    (ThemeMode.system, '跟隨系統'),
                    (ThemeMode.light, '淺色'),
                    (ThemeMode.dark, '深色'),
                  ])
                    CheckedPopupMenuItem(
                      value: 'theme:${mode.name}',
                      checked: widget.themeMode == mode,
                      child: Text(label),
                    ),
                ];
              },
            ),
          ],
        ),
        bottomNavigationBar: checkNext != null
            ? SafeArea(
                top: false,
                child: Material(
                  elevation: 8,
                  color: colors.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton(
                      key: const Key('check-next'),
                      onPressed: state.busy ? null : checkNext.$2,
                      child: Text(checkNext.$1),
                    ),
                  ),
                ),
              )
            : selectingPtus
            ? SafeArea(
                top: false,
                child: Material(
                  elevation: 8,
                  color: colors.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Round 17: 「取消操作」 is part of the bar's fixed
                        // layout (disabled while idle).
                        if (directPicking) ...[
                          DirectPickActions(onEnd: () => _endFlow(controller)),
                        ] else ...[
                          // Round 21: the automatic reconnect says what it
                          // does — reconnecting, then reading the list.
                          if (relinkStatusText(state) case final relink?)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      relink,
                                      key: const Key('relink-status'),
                                      style: TextStyle(color: colors.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            selectionCountText(state, targetPtuCount),
                            key: const Key('ptu-selection-count'),
                          ),
                          const SizedBox(height: 6),
                          if (state.assignFailed.isNotEmpty && !state.busy) ...[
                            FilledButton.tonal(
                              key: const Key('ptu-retry-failed'),
                              onPressed: controller.retryFailedAssign,
                              child: Text('重試這 ${state.assignFailed.length} 台'),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const Key('ptu-reconfigure-all'),
                                onPressed: () => _reconfigureAll(controller),
                                child: const Text('全部重新配置'),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          FilledButton(
                            key: const Key('ptu-configure'),
                            // Round 26: a gateway in test mode cannot scan;
                            // the one action is to switch it back.
                            onPressed: state.relinking
                                ? null
                                : state.testMode && !state.busy
                                ? controller.leaveTestMode
                                : step7LinkLost(state) ||
                                      (!state.busy &&
                                          configureLabel(state) == rescanLabel)
                                ? () => controller.discover()
                                : !state.busy &&
                                      configureLabel(state) != scanningLabel &&
                                      (state.resumePending ||
                                          state.selected.isNotEmpty)
                                ? () {
                                    if (!state.resumePending &&
                                        configureTargets(state).isEmpty) {
                                      // Round 9: all assigned → 開始驗證 /
                                      // 恢復監控, never a disabled dead end.
                                      controller.finishConfigured();
                                      return;
                                    }
                                    final warning = controller.starFullWarning;
                                    if (warning != null) {
                                      _snack(warning);
                                      return;
                                    }
                                    if (state.resumePending) {
                                      controller.resumeAssign();
                                    } else {
                                      controller.configurePtus(
                                        skip: state.assignedOk,
                                      );
                                    }
                                  }
                                : null,
                            child: Text(
                              state.testMode && !state.busy
                                  ? leaveTestModeLabel
                                  : configureLabel(state),
                            ),
                          ),
                          if (state.busy)
                            TextButton(
                              key: const Key('ptu-stop'),
                              // Step 8: stop but keep the progress (round 7b:
                              // a cancel here dropped back to step 2).
                              onPressed: controller.stopStep8,
                              child: const Text('取消操作'),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            : done
            ? _doneBar(state, controller)
            // 1.0.0+14: the gateway list — a card's tap selects, this
            // button connects (〔結束配置〕 stays at the end of the page).
            : state.step == 1
            ? GatewayConnectBar(choice: _gatewayChoice, enabled: !state.busy)
            : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                controller: _pageScroll,
                // 1.0.0+10: 16 (was 20) — more width for the gateway list's
                // rows at 360 dp.
                padding: EdgeInsets.all(selectingPtus ? 12 : 16),
                children: [
                  if (demo)
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: colors.secondaryContainer,
                      child: const Text('模擬模式 · 不會設定真實設備或驗證正式資料'),
                    ),
                  // Round 29: the done page starts with its summary.
                  if (done) _doneSummary(state, controller, demo, env),
                  // One-thing screens (09-28): one sentence on top — what
                  // this page asks, or what runs by itself; the step count
                  // below it, small.
                  if (!done) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _taskTitle(state, env),
                        key: const Key('task-title'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: shown / (stepLabels.length - 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${shown + 1} / ${stepLabels.length}   ${stepLabels[shown]}',
                      key: const Key('step-title'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  SizedBox(height: selectingPtus ? 4 : 12),
                  // The phone's signal row is in 「設備與連線資訊」; a lost
                  // Bluetooth link is said here, never behind the fold.
                  if (state.peer != null && !done)
                    GatewayLinkAlert(link: ref.watch(linkProvider)),
                  if (identifyAt && identifyOnPage) _identifyButton(state),
                  if (selectingPtus &&
                      !directPicking &&
                      state.identifyNote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        state.identifyNote,
                        key: const Key('identify-note'),
                        style: TextStyle(color: colors.primary),
                      ),
                    ),
                  // 09-28: on the station and Wi-Fi pages the idle message
                  // only repeated the task sentence; while something runs
                  // (or failed) it is shown as before.
                  // 1.0.0+17: on the gateway list (step 2) neither the
                  // message left from the step before (「準備完成」) nor
                  // 〔辨識〕's own (the list's progress says what runs) —
                  // others (offline, 〔配置下一台〕's) and failures stay.
                  if (state.message.isNotEmpty &&
                      !done &&
                      (state.step != 1 ||
                          state.error != null ||
                          (state.message != preparedText &&
                              state.message != identifyPeerLabel)) &&
                      (!stationPages ||
                          state.busy ||
                          state.relinking ||
                          state.error != null) &&
                      (!selectingPtus ||
                          state.busy ||
                          state.error != null ||
                          state.ptus.isEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(state.message),
                    ),
                  // The gateway restarted on its own: why, in plain words,
                  // and that it is not a PTU fault (kept until 「知道了」).
                  if (state.gatewayReboot != null)
                    Container(
                      key: const Key('gateway-reboot'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                      color: colors.tertiaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            gatewayRebootText(state.gatewayReboot!),
                            style: TextStyle(color: colors.onTertiaryContainer),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const Key('gateway-reboot-ok'),
                              onPressed: controller.dismissGatewayReboot,
                              child: const Text('知道了'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Round 26: test mode / paused upload, with the way out.
                  const GatewayModeCard(),
                  // Round 28: a PTU connected but never bound (〔先完成配置〕
                  // earlier): 〔辨識並綁定〕.
                  if (state.step == 2 &&
                      (state.bindLaterMac != null || state.bindLaterDeferred))
                    _bindLaterCard(state, controller),
                  // r34: bound, but the bound PTU is not connected:
                  // 〔更換 PTU〕 / 〔PTU 已上電，重新檢查〕.
                  if (state.step == 2 && state.ptuMissingMac != null)
                    _ptuMissingCard(state, controller),
                  // Above the red box: the item that failed, then why in
                  // full and its retry.
                  if (checklist != null)
                    ProgressChecklist(
                      key: const Key('auto-checklist'),
                      items: checklist.items,
                      animate: state.busy,
                      // 1.0.0+18: the data check says its pace instead.
                      footer: !state.busy
                          ? null
                          : state.step == 6
                          ? verifyFooterText(
                              state.seconds,
                              intervalMs: state.verifyIntervalMs,
                            )
                          : '最多等待 ${state.seconds} 秒',
                    ),
                  if (state.error != null)
                    Material(
                      key: const Key('error-banner'),
                      color: colors.errorContainer,
                      child: InkWell(
                        // Round 6: the resume action was two screens below
                        // the banner; the banner itself is the action now.
                        onTap: _resumeAction(state, controller),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                state.error!,
                                style: TextStyle(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                              // Field rescue v1.1: 「請後台協助」 (a button,
                              // so the banner's own tap action does not
                              // fire).
                              if (!demo && controller.fieldHelpAvailable)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: OutlinedButton.icon(
                                    key: const Key('field-help'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: colors.onErrorContainer,
                                      side: BorderSide(
                                        color: colors.onErrorContainer,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.support_agent,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        openFieldHelp(context, ref),
                                    label: const Text(fieldHelpLabel),
                                  ),
                                ),
                              if (_resumeAction(state, controller) != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: FilledButton.icon(
                                    key: const Key('ptu-resume'),
                                    icon: const Icon(
                                      Icons.bluetooth_searching,
                                      size: 20,
                                    ),
                                    onPressed: _resumeAction(state, controller),
                                    label: Text(
                                      state.step == 4 || state.step == 5
                                          ? '重新連線並繼續'
                                          : '重新連線',
                                    ),
                                  ),
                                ),
                              if (state.verifyBackendDown &&
                                  !state.busy &&
                                  state.step == 6)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: FilledButton.icon(
                                    key: const Key('verify-retry'),
                                    icon: const Icon(Icons.refresh, size: 20),
                                    onPressed: _startVerify,
                                    label: const Text('重試'),
                                  ),
                                ),
                              if (state.monitorUnconfirmed && !state.busy)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: OutlinedButton(
                                    key: const Key('monitor-skip'),
                                    onPressed: controller.skipMonitorConfirm,
                                    child: const Text('略過'),
                                  ),
                                ),
                              if (state.errorDetail != null)
                                Theme(
                                  data: Theme.of(
                                    context,
                                  ).copyWith(dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    key: const Key('error-detail'),
                                    tilePadding: EdgeInsets.zero,
                                    title: Text(
                                      '詳細資訊',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: colors.onErrorContainer,
                                          ),
                                    ),
                                    children: [
                                      SelectableText(
                                        state.errorDetail!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colors.onErrorContainer,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (state.busy && checklist == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('處理中 · 最多等待 ${state.seconds} 秒'),
                          ),
                        ],
                      ),
                    ),
                  // Earliest page with the gateway connected and its config
                  // read; kept on step 7 so a local target is not shipped.
                  // 09-28: all fine, it is in 「設備與連線資訊」 instead.
                  if (panelAt && !panelOk)
                    ConnectionStatusPanel(
                      state: state,
                      env: env,
                      demo: demo,
                      onSync: () => _syncGateway(explicit: true),
                      onRefresh: controller.refreshUploadTarget,
                    ),
                  if (state.step >= 1 && state.step <= 2 && !state.loggedIn)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '尚未登入${env.label}：站號衝突檢查會先略過，之後需要時會自動登入。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  // Round 29: the done page's other actions are secondary,
                  // below the summary and the 連線狀態 line (no card).
                  if (done)
                    ...content(state, controller, demo)
                  // 1.0.0+18: step 9's card turns green once the data
                  // passed.
                  else if (state.step == 6)
                    VerifyStepCard(
                      key: const Key('verify-card'),
                      passed: state.verifyPassed,
                      children: content(state, controller, demo),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(selectingPtus ? 8 : 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: content(state, controller, demo),
                        ),
                      ),
                    ),
                  // 1.0.0+16: 〔查看上傳資料〕 - its own row under the start
                  // card, level with 「設備與連線資訊」 (it was a button in the
                  // card; the field did not know what 「閘道器狀態」 was for).
                  if (!done && state.step == 0) _uploadDataRow(!state.busy),
                  if (!done)
                    _details(
                      state,
                      controller,
                      env,
                      demo,
                      shown: shown,
                      topologyLabel: topology.label,
                      identify: identifyAt && !identifyOnPage,
                      panel: panelOk,
                    ),
                  // After step 3 it asks first (field round 17: a late tap
                  // ended the flow). Round 19: at direct step 7 it is the
                  // bottom bar's last row instead ([DirectPickActions]),
                  // where the card above can no longer move it.
                  // Round 29: not on the done page (〔完成〕／〔配置下一台〕).
                  // 09-29: on the gateway list it is 〔結束配置〕 — back to
                  // the start page ([_leaveList]); 「結束並重新選擇閘道器」
                  // there only wrote 「已取消」 in place.
                  if (state.step > 0 &&
                      !done &&
                      !directPicking &&
                      !(selectingPtus && state.busy))
                    TextButton(
                      key: const Key('page-cancel'),
                      // Step 9: back to step 7 keeping the progress (round
                      // 8: a cancel here dropped back to step 2).
                      onPressed: state.step == 6 && state.busy
                          ? controller.backToSelection
                          : state.busy
                          ? () => controller.cancel()
                          : state.step == 1
                          ? () => _leaveList(controller)
                          : () => _endFlow(controller),
                      child: Text(
                        state.busy
                            ? '取消操作'
                            : state.step == 1
                            ? leaveListLabel
                            : endFlowLabel,
                      ),
                    ),
                  // 1.0.0+8: the 「使用模擬設備練習」 switch is gone from the
                  // start page; tests turn the demo on through
                  // [demoProvider]. Practice the network check: the
                  // simulated gateway's Wi-Fi after it boots.
                  if (state.step == 0 && demo)
                    DropdownButtonFormField<String>(
                      key: const Key('demo-wifi'),
                      initialValue: ref.read(demoSystemProvider).wifiState,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '模擬閘道器的 Wi-Fi',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'got_ip', child: Text('已連上')),
                        DropdownMenuItem(
                          value: 'connecting',
                          child: Text('剛開機，正在連'),
                        ),
                        DropdownMenuItem(
                          value: 'disconnected',
                          child: Text('連不上（Wi-Fi 不在附近）'),
                        ),
                      ],
                      onChanged: state.busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(
                                () => ref
                                    .read(demoSystemProvider)
                                    .simulateWifi(value),
                              );
                            },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One-thing screens (09-28): the station page — one question 「目前站號是
  /// N，這台要配置在本站嗎？」 with 〔使用此站點〕; 「改用其他站號」 (or no
  /// station to propose) shows the input with 〔使用站點 M〕. The Wi-Fi
  /// page follows only when the gateway is on no Wi-Fi or 「改用其他
  /// Wi-Fi」 is pressed ([_wifiPage]).
  List<Widget> _stationPage(
    CommissionState s,
    CommissioningController c,
    NetworkCheck check,
    bool enabled,
  ) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    // A gateway in service (its question, or a new number typed for it).
    final inService =
        s.config['choose_station'] == true || s.config['new_station'] == true;
    final current = _stationCurrent(s);
    final input = _stationInput(s);
    final typed = _typedSite;
    final kept = keptWifiSsid(s);
    // Keeping the station in service needs its upload working.
    final reason = inService && (!input || typed == current)
        ? check.reuseBlockedReason
        : null;
    final String label;
    final bool canUse;
    if (!input) {
      label = useStationLabel;
      canUse = reason == null && (inService || !_gatewaySubmitBlocked);
    } else if (typed == null) {
      label = useSiteEmptyLabel;
      canUse = false;
    } else {
      label = useSiteLabel(typed);
      canUse = inService && typed == current
          ? reason == null
          : !_suggestingGateway && !_gatewaySubmitBlocked;
    }
    return [
      // 1.0.0+15: the Wi-Fi was fixed on the check a moment ago.
      if (wifiFirstJoined(s))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _markedText(
            const CheckLine('✓', wifiFirstDoneText, StatusTone.ok),
            key: const Key('wifi-first-done'),
          ),
        ),
      if (!input)
        inService
            ? Text(
                '沿用站點 $current／閘道器 ${s.config['gateway_id']}，原站資料不變。',
                key: const Key('station-current'),
                style: muted,
              )
            : _gatewayAssignment(enabled: enabled, swap: true)
      else ...[
        field(
          _site,
          siteFieldLabel,
          number: true,
          onChanged: (_) {
            _scheduleGatewaySuggestion();
            // 1.0.0+13: an old gateway chosen belongs to the station it
            // was chosen for — another one typed is numbered again (also
            // when 〔使用站點〕 comes before the lookup).
            setState(_clearSwap);
          },
        ),
        if (typed != null && !(inService && typed == current))
          _gatewayAssignment(enabled: enabled, swap: true),
      ],
      if (kept != null)
        _markedText(
          CheckLine('✓', wifiKeptText(kept), StatusTone.ok),
          key: const Key('wifi-keep'),
        ),
      if (reason != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            // Round 26: test mode / a paused upload have their own button
            // in the card above, not a Wi-Fi reset.
            check.testMode
                ? '要使用此站點，請先按上方「$leaveTestModeLabel」（目前：$reason）。'
                : check.uploadPaused && check.wifiOk && check.targetOk
                ? '要使用此站點，請先按上方「$resumeUploadLabel」（目前：$reason）。'
                : '要使用此站點，閘道器必須先連上 Wi-Fi 並開始上傳資料（目前：$reason）。'
                      '請按「$otherWifiLabel」，或按「回到網路體檢」。',
            key: const Key('reuse-blocked'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('station-use'),
            onPressed: enabled && !_stationWorking && canUse
                ? () => _useStation(c)
                : null,
            child: Text(label),
          ),
        ),
      ),
      if (!input)
        TextButton(
          key: const Key('station-change'),
          onPressed: enabled && !_stationWorking
              ? () => setState(() {
                  _otherSite = true;
                  _site.clear();
                })
              : null,
          child: const Text(otherSiteLabel),
        )
      else if (current != null)
        TextButton(
          key: const Key('station-change-cancel'),
          onPressed: enabled && !_stationWorking
              ? () => _cancelOtherSite(c)
              : null,
          child: Text('改回站號 $current'),
        ),
      if ((inService && !input) || kept != null)
        TextButton(
          key: const Key('wifi-change'),
          onPressed: enabled && !_stationWorking && !_scanningWifi
              ? () => _otherWifi(c)
              : null,
          child: const Text(otherWifiLabel),
        ),
      if (reason != null)
        TextButton(
          key: const Key('station-review-check'),
          onPressed: enabled ? _reviewNetworkCheck : null,
          child: const Text('回到網路體檢'),
        ),
    ];
  }

  /// The Wi-Fi page: a station in service kept ([wifiOnly]: its number
  /// stays, the upload is checked again next), or a new identity whose
  /// station was chosen on the page before (sent together with it).
  ///
  /// 1.0.0+15: [wifiOnly] is also a gateway not in service fixing its
  /// Wi-Fi on the check ([wifiFirstKey]): the station comes after it.
  List<Widget> _wifiPage(
    CommissionState s,
    bool enabled, {
    required bool wifiOnly,
  }) => [
    if (s.config[wifiFirstKey] == true)
      const Text(wifiFirstPageText, key: Key('wifi-first-intro'))
    else if (wifiOnly)
      Text(
        '保留站點 ${s.config['site_id']}／閘道器 ${s.config['gateway_id']}，只更新 Wi-Fi。',
      )
    else
      _gatewayAssignment(enabled: enabled),
    const Padding(
      padding: EdgeInsets.only(top: 4, bottom: 12),
      child: Text('閘道器只能用 2.4 GHz 的 Wi-Fi，5 GHz 的網路連不上。'),
    ),
    Row(
      children: [
        const Icon(Icons.wifi),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _customWifi
                ? '自訂網路'
                : _ssid.text.isEmpty
                ? '尚未選擇 Wi-Fi'
                : _ssid.text,
            key: const Key('wifi-selected'),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('wifi-pick'),
          onPressed: enabled && !_scanningWifi ? _chooseWifi : null,
          child: Text(_scanningWifi ? '掃描中…' : '更換'),
        ),
      ],
    ),
    if (_customWifi) field(_ssid, '自訂 Wi-Fi 名稱'),
    const SizedBox(height: 8),
    field(_wifi, 'Wi-Fi 密碼', secret: true),
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('wifi-save'),
          onPressed: enabled && (wifiOnly || !_gatewaySubmitBlocked)
              ? () => _saveWifi(wifiOnly)
              : null,
          child: const Text(saveWifiLabel),
        ),
      ),
    ),
    TextButton(
      key: const Key('wifi-back'),
      onPressed: enabled
          ? wifiOnly
                ? () {
                    // Back to the station question, through the check.
                    _autoCheckPaused = false;
                    ref.read(commissionProvider.notifier).backToNetworkCheck();
                  }
                : () {
                    setState(() => _wifiStage = false);
                    _toTop();
                  }
          : null,
      child: Text(wifiOnly ? '不改 Wi-Fi，返回' : '返回修改站號'),
    ),
  ];

  /// 〔使用此站點〕／〔使用站點 M〕 (and 「改用其他 Wi-Fi」 with a new
  /// identity): a station in service kept → its PTUs are searched; a new
  /// number (「確定是新站？」 first when the back office has no gateway
  /// there) or a new gateway → saved at once when its Wi-Fi is kept, else
  /// the Wi-Fi page.
  Future<void> _useStation(
    CommissioningController c, {
    bool otherWifi = false,
  }) async {
    final s = ref.read(commissionProvider);
    if (s.busy || _stationWorking) return;
    final newStation = s.config['new_station'] == true;
    final inService = s.config['choose_station'] == true || newStation;
    final current = _stationCurrent(s);
    final input = _stationInput(s);
    final site = input ? _typedSite : current;
    if (site == null) return;
    // Its own number typed again: the station is kept.
    if (inService && site == current) {
      // r33: a conflict the back office flags on it is said first.
      final gw = (s.config['gateway_id'] as num?)?.toInt() ?? 0;
      setState(() => _stationWorking = true);
      try {
        if (!await _confirmConflict(c, site, gw)) return;
      } finally {
        if (mounted) setState(() => _stationWorking = false);
      }
      if (!mounted) return;
      if (newStation) c.cancelNewStation();
      setState(() => _otherSite = false);
      await c.chooseStation(newStation: false);
      return;
    }
    setState(() => _stationWorking = true);
    try {
      // Backlog K (second user rehearsal: 56 typed for 80, no warning).
      if (input && !await _confirmNewSite(c, site)) return;
      if (!mounted) return;
      if (inService) {
        await c.chooseStation(newStation: true);
        if (!mounted ||
            ref.read(commissionProvider).config['new_station'] != true) {
          return;
        }
      }
      if (_site.text != '$site') _site.text = '$site';
      // 1.0.0+13: an old gateway chosen for another station does not
      // apply here.
      if (_swap != null && _swap!.site != site) setState(_clearSwap);
      // A typed station: its gateway number is looked up once more
      // (1.0.0+13: not when an old gateway's number is taken over).
      if (input && _swap == null) {
        _suggestTyping?.cancel();
        await _refreshGatewaySuggestion();
        if (!mounted) return;
      }
      if (_gatewaySubmitBlocked) return;
      // r33: a number skipped by the auto-numbering (another device has
      // it) is said, with 〔取代舊機〕 to take it over (1.0.0+13: not when
      // an old gateway was chosen to be replaced).
      if (input &&
          _swap == null &&
          _gatewayKind == GatewaySuggestKind.online &&
          !await _confirmSkippedNumber(
            c,
            site,
            int.tryParse(_gateway.text) ?? 0,
          )) {
        return;
      }
      if (!mounted) return;
      // r33: this gateway's own number flagged in conflict.
      final gwNow = int.tryParse(_gateway.text) ?? 0;
      if ((s.config['site_id'] as num?)?.toInt() == site &&
          (s.config['gateway_id'] as num?)?.toInt() == gwNow &&
          !await _confirmConflict(c, site, gwNow)) {
        return;
      }
      if (!mounted) return;
      // 09-28: a number removed (archived) in the back office is asked
      // about before anything is sent.
      if (!await _confirmArchived(c, site, int.tryParse(_gateway.text) ?? 0)) {
        return;
      }
      if (!mounted) return;
      final kept = keptWifiSsid(ref.read(commissionProvider));
      if (kept != null && !otherWifi) {
        _ssid.text = kept;
        _wifi.clear();
        _customWifi = false;
        await _saveWifi(false);
      } else if (mounted) {
        setState(() {
          _wifiStage = true;
          if (_ssid.text.isEmpty) {
            _ssid.text = s.config['wifi_ssid']?.toString() ?? '';
          }
        });
        _toTop();
      }
    } finally {
      if (mounted) setState(() => _stationWorking = false);
    }
  }

  /// 「改用其他 Wi-Fi」: a station in service kept → Wi-Fi only (then the
  /// upload check and the station question again); otherwise the station
  /// shown is taken and the Wi-Fi page opens.
  Future<void> _otherWifi(CommissioningController c) async {
    final s = ref.read(commissionProvider);
    if (s.busy) return;
    final current = _stationCurrent(s);
    final newStation = s.config['new_station'] == true;
    if ((s.config['choose_station'] == true || newStation) &&
        (!_stationInput(s) || _typedSite == current)) {
      if (newStation) c.cancelNewStation();
      await c.chooseStation(newStation: false, wifiOnly: true);
      if (!mounted) return;
      setState(() {
        _otherSite = false;
        _site.text = '${s.config['site_id']}';
        _gateway.text = '${s.config['gateway_id']}';
        _clearSwap();
        _ssid.text = s.config['wifi_ssid']?.toString() ?? '';
        _wifi.clear();
        _customWifi = false;
      });
      return;
    }
    await _useStation(c, otherWifi: true);
  }

  /// 「改回站號 N」: the station proposed before 「改用其他站號」.
  void _cancelOtherSite(CommissioningController c) {
    final s = ref.read(commissionProvider);
    if (s.config['new_station'] == true) c.cancelNewStation();
    final current = _stationCurrent(s);
    setState(() {
      _otherSite = false;
      _wifiStage = false;
      _replaceSlot = null;
      _site.text = current == null ? '' : '$current';
      _gateway.text =
          '${s.config['suggested_gateway_id'] ?? s.config['gateway_id'] ?? 1}';
      _gatewayKind = s.config['suggested_offline'] == true
          ? GatewaySuggestKind.offline
          : GatewaySuggestKind.online;
      _clearSwap();
    });
  }

  /// r33 (81 typed, 81/1 held by another device: the APP went on as 81/2
  /// without a word): the number the auto-numbering skipped is said —
  /// 〔改用閘道器 N〕 (default) goes on, 〔取代舊機〕 takes the skipped
  /// number over (force_replace when saved). True: go on.
  Future<bool> _confirmSkippedNumber(
    CommissioningController c,
    int site,
    int gw,
  ) async {
    final skipped = await c.skippedGatewayNumber(site, gw);
    if (!mounted) return false;
    if (skipped == null) return true;
    final (taken, mac) = skipped;
    final action = await _askNumberTaken(c, site, taken, mac, gw);
    if (!mounted || action == null) return false;
    if (action == 'replace') {
      setState(() {
        _gateway.text = '$taken';
        _replaceSlot = (site, taken);
      });
    }
    return true;
  }

  /// r33 「閘道器編號已被使用」: gateway [taken] at [site] is held by
  /// another device ([mac]) — 〔取代舊機〕 ('replace') takes it over,
  /// 〔改用閘道器 N〕 ('next') uses [gw] instead (no such button when [gw]
  /// is null: no free number), 〔取消〕 null.
  ///
  /// 1.0.0+13: while the gateway holding [taken] is online (fleet-status
  /// `online`), 〔取代舊機〕 is not offered — 「閘道器 N 目前在線上，不能
  /// 取代；如果這台是來換掉它，請先把舊機斷電。」; when it cannot be told,
  /// as before.
  Future<String?> _askNumberTaken(
    CommissioningController c,
    int site,
    int taken,
    String mac,
    int? gw,
  ) async {
    final conflict = await c.identityConflict(site, taken);
    final online = await c.gatewayOnline(site, taken);
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('number-taken'),
        title: const Text(numberTakenTitle),
        content: Text(
          '${gw == null ? numberTakenOnlyText(site, taken) : numberTakenText(site, taken, gw)}\n'
          '（閘道器 $taken 目前登記的 MAC：$mac）\n'
          '${conflict == null ? '' : '$conflict\n'}\n'
          '${online == true ? numberTakenOnlineText(taken) : numberTakenReplaceHint(taken)}',
        ),
        actions: [
          TextButton(
            key: const Key('number-taken-cancel'),
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (online != true)
            TextButton(
              key: const Key('number-taken-replace'),
              onPressed: () => Navigator.pop(context, 'replace'),
              child: Text(numberTakenReplaceLabel(taken)),
            ),
          if (gw != null)
            FilledButton(
              key: const Key('number-taken-next'),
              onPressed: () => Navigator.pop(context, 'next'),
              child: Text(numberTakenNextLabel(gw)),
            ),
        ],
      ),
    );
  }

  /// r33 (a stale record of another MAC at 80/1: the back office flagged a
  /// conflict, the APP said nothing): this gateway's (site, gw) flagged in
  /// conflict shows the back office's text — 〔取代舊機〕 records this
  /// gateway for it (force_replace) and goes on, 〔改用其他站號〕 opens
  /// the input. True: go on (also when nothing is flagged).
  ///
  /// 1.0.0+13: while the other gateway holding the number is online
  /// (fleet-status `online`, the row held by another MAC), 〔取代舊機〕 is
  /// not offered — 「閘道器 N 目前在線上，不能取代；如果這台是來換掉它，
  /// 請先把舊機斷電。」; when it cannot be told (also: the row held by this
  /// gateway), as before — as r33's 「閘道器編號已被使用」.
  Future<bool> _confirmConflict(
    CommissioningController c,
    int site,
    int gw,
  ) async {
    final conflict = await c.identityConflict(site, gw);
    if (!mounted) return false;
    if (conflict == null) return true;
    final online = await c.gatewayOnline(site, gw);
    if (!mounted) return false;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('identity-conflict'),
        title: const Text(identityConflictTitle),
        content: Text(
          '$conflict\n\n'
          '${online == true ? numberTakenOnlineText(gw) : identityConflictHint(site, gw)}',
        ),
        actions: [
          TextButton(
            key: const Key('identity-conflict-other-site'),
            onPressed: () => Navigator.pop(context, 'other'),
            child: const Text(otherSiteLabel),
          ),
          if (online != true)
            FilledButton(
              key: const Key('identity-conflict-replace'),
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text(replaceOldLabel),
            ),
        ],
      ),
    );
    if (!mounted) return false;
    if (action == 'other') {
      setState(() {
        _otherSite = true;
        _wifiStage = false;
        _site.clear();
      });
      return false;
    }
    if (action != 'replace') return false;
    final ok = await c.replaceIdentity(site, gw);
    if (!mounted) return false;
    _snack(ok ? replacedText(site, gw) : replaceFailedText);
    return ok;
  }

  /// 09-28 (GC 刪除 56/1, then this gateway configured again: 確認上線
  /// waited for heartbeats forever — the back office skips an archived
  /// station's heartbeats and never restores it by itself): a number
  /// archived for this gateway is asked about — 〔重新加入並繼續〕 restores
  /// it, 〔改用其他站號〕 opens the input. True: go on.
  Future<bool> _confirmArchived(
    CommissioningController c,
    int site,
    int gw,
  ) async {
    if (!await c.identityArchived(site, gw)) return true;
    if (!mounted) return false;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('archived-confirm'),
        title: const Text(archivedConfirmTitle),
        content: Text(archivedConfirmText(site, gw)),
        actions: [
          TextButton(
            key: const Key('archived-other-site'),
            onPressed: () => Navigator.pop(context, 'other'),
            child: const Text(otherSiteLabel),
          ),
          FilledButton(
            key: const Key('archived-rejoin'),
            onPressed: () => Navigator.pop(context, 'rejoin'),
            child: const Text(archivedRejoinLabel),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (action == 'other') {
      setState(() {
        _otherSite = true;
        _wifiStage = false;
        _site.clear();
      });
      return false;
    }
    if (action != 'rejoin') return false;
    return c.rejoinIdentity(site, gw);
  }

  /// Backlog K: a station the back office has no gateway on is asked
  /// about once (「確定是新站？」); unknown (offline) goes on.
  Future<bool> _confirmNewSite(CommissioningController c, int site) async {
    final known = await c.siteHasGateways(site);
    if (!mounted) return false;
    if (known != false) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('new-site-confirm'),
        title: const Text(newSiteConfirmTitle),
        content: Text(newSiteConfirmText(site)),
        actions: [
          TextButton(
            key: const Key('new-site-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('重新輸入'),
          ),
          FilledButton(
            key: const Key('new-site-ok'),
            onPressed: () => Navigator.pop(context, true),
            child: Text('是新站，使用站號 $site'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// The gateway's own identify (「辨識這台」): on the page where PTUs are
  /// chosen in a list, otherwise in 「設備與連線資訊」.
  Widget _identifyButton(CommissionState state) =>
      state.config['identify_supported'] == true
      ? OutlinedButton.icon(
          onPressed: state.busy
              ? null
              : ref.read(commissionProvider.notifier).identify,
          icon: const Icon(Icons.lightbulb_outline),
          label: Text(
            identifyPtuSupported(state.config)
                ? '辨識此樁（PTU 與閘道器閃燈）'
                : '辨識這台・雙閃 6 秒',
            key: const Key('identify-label'),
          ),
        )
      : const Text('連線時藍燈呼吸；更新韌體後可使用雙閃辨識。');

  /// 1.0.0+16: the start page's 〔查看上傳資料〕 row (opens
  /// [GatewayStatusPage]); a ListTile so the touch target is >= 48 dp and
  /// the caption wraps at 360 dp / text scale 1.3.
  Widget _uploadDataRow(bool enabled) {
    return ListTile(
      key: const Key('home-gateway-status'),
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      minVerticalPadding: 12,
      leading: const Icon(Icons.cloud_done_outlined, size: 20),
      title: const Text(gatewayStatusLabel),
      subtitle: Text(
        gatewayStatusHomeCaption,
        key: const Key('home-gateway-status-caption'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled ? () => GatewayStatusPage.open(context) : null,
    );
  }

  /// One-thing screens (09-28): 「設備與連線資訊」, collapsed — the mode,
  /// the step list, the gateway's name / MAC / phone signal, its identify
  /// and, when all is fine, the connection panel. Errors, the Bluetooth
  /// alert, reconnect, 「重新開始」, 「請後台協助」 and 「結束」 are never in
  /// here.
  Widget _details(
    CommissionState s,
    CommissioningController c,
    BackendEnvState env,
    bool demo, {
    required int shown,
    required String topologyLabel,
    required bool identify,
    required bool panel,
  }) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('commission-details'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: const Icon(Icons.info_outline, size: 20),
        title: Text(detailsTitle, style: muted),
        children: [
          Text(
            '目前模式：$topologyLabel',
            key: const Key('topology-banner'),
            style: muted,
          ),
          const SizedBox(height: 6),
          StepList(current: shown),
          // Round 26: 「站 80 · 閘道器 2 · MAC 後 4 碼 70F2 · 1.7.36」
          // (field: two gateways read 「GIOS-S80-G…」).
          if (s.peer != null) ...[
            const SizedBox(height: 8),
            Text(
              gatewayHeaderText(
                name: s.peer!.name,
                id: s.peer!.id,
                config: s.config,
              ),
              key: const Key('gateway-header'),
            ),
            GatewaySignal(
              link: ref.watch(linkProvider),
              peer: s.peer!,
              busy: s.busy,
            ),
          ],
          if (identify)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _identifyButton(s),
            ),
          if (s.step == 2 && s.checkPassed && !wifiFormOfCheck(s))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('details-review-check'),
                onPressed: s.busy ? null : _reviewNetworkCheck,
                child: const Text('回到網路體檢'),
              ),
            ),
          if (panel)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConnectionStatusPanel(
                state: s,
                env: env,
                demo: demo,
                onSync: () => _syncGateway(explicit: true),
                onRefresh: c.refreshUploadTarget,
              ),
            ),
        ],
      ),
    );
  }

  /// Round 17: 「結束並重新選擇閘道器」 after step 3 asks first — 「結束目前
  /// 配置？已完成的 N 台會保留在閘道器」 [繼續配置] [結束].
  ///
  /// Round 28: [always] (the system 返回) asks on every page past the
  /// gateway list; a gateway not in service yet (upload paused until
  /// join_fleet) past the identity step adds that it will upload nothing
  /// (field round 28: pile B was left so) — at direct step 7 without this
  /// pile's PTU, that 〔先完成配置〕 is the way to finish it.
  Future<void> _endFlow(
    CommissioningController c, {
    bool always = false,
  }) async {
    final s = ref.read(commissionProvider);
    if (always || displayStep(s, ref.read(backendEnvProvider)) >= 3) {
      final held =
          s.step >= 3 && !s.ptuDeferred && uploadHeldUntilJoin(s.config);
      final end = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('end-confirm'),
          title: const Text(endFlowConfirmTitle),
          content: Text(
            [
              endFlowConfirmText(
                s.assignedOk.length,
                restoresBind: endFlowRestoresBind(s),
              ),
              if (held) endFlowHeldUploadText,
              if (held && directNoPtu(s, directFlow: c.directFlow))
                endFlowDeferHint,
            ].join('\n'),
            key: const Key('end-confirm-text'),
          ),
          actions: [
            TextButton(
              key: const Key('end-confirm-continue'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('繼續配置'),
            ),
            FilledButton(
              key: const Key('end-confirm-end'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('結束'),
            ),
          ],
        ),
      );
      if (end != true || !mounted) return;
    }
    await c.cancel();
  }

  /// 09-29: 〔結束配置〕 on the gateway list — 「結束這次配置並回首頁？」,
  /// 結束 goes to the start page ([CommissioningController.leaveList]),
  /// 留在清單 changes nothing.
  Future<void> _leaveList(CommissioningController c) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('leave-confirm'),
        title: const Text(leaveListConfirmTitle),
        actions: [
          TextButton(
            key: const Key('leave-confirm-stay'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('留在清單'),
          ),
          FilledButton(
            key: const Key('leave-confirm-end'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('結束'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    await c.leaveList();
  }

  /// Round 28: the system 返回 while a gateway is connected or a step runs
  /// ([PopScope] refused to leave): 「結束目前配置？」 — 結束 ends the run
  /// ([CommissioningController.cancel], as 「結束並重新選擇閘道器」 /
  /// 「取消操作」), 繼續配置 stays. Never leaves the APP.
  ///
  /// Round 29: on the done page 返回 is 〔完成〕 — the run is finished,
  /// nothing to ask (while an action there runs: a note to wait).
  ///
  /// 09-29: on the gateway list (nothing running) 返回 is 〔結束配置〕
  /// without the question — the start page; only the start page leaves
  /// the APP.
  bool _backAsking = false;
  Future<void> _backPressed(CommissioningController c) async {
    final s = ref.read(commissionProvider);
    // The start page (checking Bluetooth / the login) has nothing to end.
    if (_backAsking || s.step == 0) return;
    if (s.step == 1) {
      if (!s.busy) await c.leaveList();
      return;
    }
    if (s.step == 7) {
      if (s.busy) {
        _snack(doneBusyText);
      } else {
        await _finishDone(c);
      }
      return;
    }
    _backAsking = true;
    try {
      await _endFlow(c, always: true);
    } finally {
      _backAsking = false;
    }
  }

  /// Saved resume skips steps 5/6, so log in first when the rest needs the
  /// backend (star auto-reset, step 9 verify); without a login it continues
  /// manually.
  ///
  /// Round 17: the session token saved by the last login is used first;
  /// 09-28: else the build's backend credential logs in by itself (no
  /// password dialog any more; a build without one says so).
  Future<void> _resumeSaved(CommissioningController c) async {
    if (c.savedResumeNeedsLogin) {
      final env = ref.read(backendEnvProvider);
      final restored = await c.restoreSession(env.base);
      if (!mounted) return;
      if (restored) {
        await c.resumeSaved();
        return;
      }
      if (!ref.read(demoProvider) && ref.read(backendKeyProvider).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('resume-missing-key'),
            content: Text('$missingBackendKeyText。\n$resumeWithoutLoginText'),
          ),
        );
      } else {
        await c.login(env.base);
        if (!mounted) return;
        if (!ref.read(commissionProvider).loggedIn) return;
      }
    }
    await c.resumeSaved();
  }

  /// Step 8 link loss: the one action that reconnects and continues.
  /// Every link-loss banner gets one (round 8: a step 7 drop had only
  /// 「詳細資訊」).
  VoidCallback? _resumeAction(CommissionState s, CommissioningController c) {
    // Round 13: nothing to tap while the automatic reconnect runs.
    if (s.busy || s.relinking) return null;
    if (s.step == 4 || s.step == 5) {
      if (s.resumePending) return c.resumeAssign;
      if (s.scanResumePending || s.uploadWatch == UploadWatch.linkLost) {
        return c.discover;
      }
      if (s.reconnectFailed) return null; // own 「重試重新連線」 below
      return null;
    }
    if (s.peer != null &&
        s.step >= 2 &&
        (s.reconnectFailed || s.uploadWatch == UploadWatch.linkLost)) {
      return c.reconnectLink;
    }
    return null;
  }

  /// 「重新連線並繼續」 for progress saved before the APP was closed.
  /// Round 16: every saved-progress prompt (finished, resumable, or an
  /// unfinished run without a gateway to resume — round 15's 「上次中斷於
  /// 第 5 步」), in either topology, has 「重新開始」 to clear it.
  List<Widget> _savedResume(
    CommissionState s,
    CommissioningController c,
    bool enabled,
  ) => [
    // Round 29: the finished run before (〔完成〕／〔配置下一台〕, or saved
    // before a restart) — a note, never a card to resume.
    if (s.lastDone.isNotEmpty)
      Padding(
        key: const Key('last-done'),
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              size: 20,
              color: toneColor(context, StatusTone.ok),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(s.lastDone, key: const Key('last-done-text'))),
          ],
        ),
      ),
    // Round 28: which gateway the saved progress belongs to (field round
    // 28: pile B's prompt counted pile A's PTU).
    if ((s.savedResume || s.savedProgress) && s.savedGateway.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '上次配置的閘道器：${s.savedGateway}',
          key: const Key('saved-gateway'),
        ),
      ),
    // Round 29: a finished run has no 「重新開始」 (nothing to resume).
    if (s.savedResume || s.savedProgress)
      OutlinedButton.icon(
        key: const Key('restart-after-done'),
        icon: const Icon(Icons.restart_alt, size: 20),
        onPressed: enabled ? c.clearCompleted : null,
        label: const Text('重新開始'),
      ),
    if (s.savedResume || s.savedProgress) const SizedBox(height: 16),
    if (s.savedResume) ...[
      FilledButton.icon(
        key: const Key('saved-resume'),
        icon: const Icon(Icons.bluetooth_searching, size: 20),
        onPressed: enabled ? () => _resumeSaved(c) : null,
        label: const Text('重新連線並繼續'),
      ),
      const SizedBox(height: 16),
    ],
  ];

  List<Widget> content(
    CommissionState s,
    CommissioningController c,
    bool demo,
  ) {
    final enabled = !s.busy;
    final env = ref.read(backendEnvProvider);
    final environment = env.environment;
    final topology = ref.read(topologyProvider).topology;
    final localAllowed = ref.read(envSwitchPolicyProvider).localAllowed;
    switch (s.step) {
      case 0:
        final localBlocked = environment == BackendEnv.local && !localAllowed;
        return [
          ..._savedResume(s, c, enabled),
          const Text('先確認現場 WiFi 路由器與裝置電源已開啟。'),
          const SizedBox(height: 20),
          // 1.0.0+8: no 「連線環境」 dropdown here — the AppBar chip
          // (「● 正式站」) is the only switch. The local / custom address
          // fields stay for those environments; 正式站 shows its URL only.
          if (localBlocked)
            const SizedBox.shrink()
          else if (environment == BackendEnv.local)
            LocalBackendField(
              hostController: _host,
              port: env.localPort,
              enabled: enabled,
              onPortChanged: _envController.setLocalPort,
              onHostPicked: () {},
            )
          else if (environment == BackendEnv.custom)
            BackendUrlField(controller: _base, label: '後端網址', enabled: enabled)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                env.base,
                key: const Key('env-base-line'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (environment == BackendEnv.local && !localBlocked)
            const Text('手機與電腦需連同一個 Wi-Fi；電腦 IP 若變更，可在上方修改或按「自動尋找」。')
          else if (environment == BackendEnv.production)
            const Text(productionHintText),
          // 09-28: no password field; the build carries the credential.
          if (!demo && ref.read(backendKeyProvider).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                missingBackendKeyText,
                key: const Key('missing-backend-key'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _offline,
            // 1.0.0+10 (phone: larger than the notes around it — the
            // ListTile's own title style): the notes' size (bodyMedium).
            title: Text(
              '先離線配置，稍後驗證資料',
              key: const Key('offline-checkbox-title'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onChanged: enabled
                ? (v) => setState(() => _offline = v ?? false)
                : null,
          ),
          // r32: next to the button (not the banner at the top), so the
          // tap never looks like nothing happened.
          if (localBlocked)
            Padding(
              key: const Key('local-unavailable'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                localUnavailableText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          button('檢查並開始', () async {
            _flushBase();
            final current = ref.read(backendEnvProvider);
            if (current.environment == BackendEnv.local &&
                !ref.read(envSwitchPolicyProvider).localAllowed) {
              _snack(localUnavailableText);
              return;
            }
            if (current.environment == BackendEnv.local) {
              final error = localHostError(current.localHost);
              if (error != null) {
                _snack(error);
                return;
              }
            }
            await c.prepare(current.base, '', offline: _offline);
          }, enabled),
        ];
      case 1:
        return [
          ..._savedResume(s, c, enabled),
          GatewayDiscovery(
            key: _discoveryKey,
            enabled: enabled,
            // 1.0.0+9: 「辨識」 only blinks (connect → identify → disconnect)
            // and stays on this list. 1.0.0+14: the card's tap selects the
            // gateway, the fixed bottom button connects to it.
            onIdentify: c.identifyPeer,
            onConnect: (peer) => _connectPeer(c, peer),
            choice: _gatewayChoice,
          ),
        ];
      case 2:
        final check = networkCheck(state: s, env: env);
        if (!s.checkPassed) return _networkCheck(s, c, check, enabled);
        // One-thing screens (09-28): a Wi-Fi page only when it is needed
        // (the gateway is on no Wi-Fi, or 「改用其他 Wi-Fi」); otherwise the
        // station page asks one question.
        // 1.0.0+15: also the Wi-Fi-first form of a gateway not in service.
        if (wifiFormOfCheck(s)) {
          return _wifiPage(s, enabled, wifiOnly: true);
        }
        if (_wifiStage && s.config['choose_station'] != true) {
          return _wifiPage(s, enabled, wifiOnly: false);
        }
        return _stationPage(s, c, check, enabled);
      case 3:
        final check = networkCheck(state: s, env: env);
        return [
          const Icon(Icons.cloud_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('確認閘道器不只連上 WiFi，後端也持續收到心跳。'),
          const SizedBox(height: 8),
          Text('閘道器自己回報：${check.upload.line}'),
          // Round 30: its retry is in the bottom bar ([_checkNext]).
          const SizedBox(height: 8),
          Text(
            s.busy
                ? '正在確認後台收到心跳，成功後會自動尋找 PTU，請稍候。'
                : s.identityArchived
                ? rejoinHintText
                : s.error != null
                ? '檢查尚未通過。請依提示修正後，按下方按鈕重新檢查。'
                : !s.loggedIn && !demo && ref.read(backendKeyProvider).isEmpty
                ? missingBackendKeyText
                : !s.loggedIn
                ? '請按下方按鈕開始檢查。'
                : s.offline
                ? '目前為離線配置，請選擇確認上線或稍後驗證。'
                : '即將自動確認上線，請稍候。',
            key: const Key('online-next-hint'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          // 09-28: while it runs, the page only says what runs.
          if (!s.busy) ...[
            TextButton(
              onPressed: enabled ? () => c.online(skip: true) : null,
              child: const Text('暫未確認，先配置 PTU'),
            ),
            Text(
              '略過的話，最後「驗證資料」仍會確認資料有沒有上傳。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ];
      case 4:
      case 5:
        // Round 15: direct flow step 7 shows the gateway's own pick only.
        final directStep7 = c.directFlow && s.step == 4;
        // 09-28: direct step 8 runs by itself (bind, join, then the data
        // check): while it runs, only its progress.
        final directRunning = c.directFlow && s.step == 5 && s.busy;
        return [
          if (s.reconnectFailed && !s.busy)
            Padding(
              key: const Key('reconnect-failed'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const Key('reconnect-retry'),
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: s.resumePending ? c.resumeAssign : c.discover,
                    label: const Text('重試重新連線'),
                  ),
                  TextButton(
                    key: const Key('back-to-gateway'),
                    onPressed: c.cancel,
                    child: const Text('回到找閘道器'),
                  ),
                ],
              ),
            ),
          // Round 21: the assignment run in one line above the rows.
          if (!directStep7 && (s.step == 5 || s.assignStatus.isNotEmpty))
            if (assignProgressLine(s) case final progress?)
              AssignProgressHeader(
                text: progress,
                value: assignProgressValue(s.assignStatus),
                running: s.busy,
                failed: s.assignStatus.values
                    .where((a) => a.phase == AssignPhase.failed)
                    .length,
              ),
          if (!directStep7) ...[
            if (!directRunning)
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: enabled ? c.discover : null,
                label: Text(
                  s.relinking && s.relinkStage == RelinkStage.reloading
                      ? relinkReloadText
                      : relinkShown(s)
                      ? autoRelinkingText
                      : s.uploadWatch == UploadWatch.linkLost || s.resumePending
                      ? rescanAfterLossLabel
                      : '由閘道器重新掃描 PTU',
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                // Round 23: 「讀取中…」 until the list is read (field: 「已連線
                // 0 台／周邊未連線 0 台」 during a re-read read as nothing found).
                ptuCountText(s),
                key: const Key('ptu-list-count'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            // Round 23: the gateway takes the star range only at 「配置」
            // (field: one PTU connected after the switch read as a fault).
            if (starApplyNote(s, isStar: topology.isStar) case final note?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  note,
                  key: const Key('star-apply-note'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
          if (directStep7) const DirectStatusPanel(actionsInBar: true),
          // Old firmware direct list only; a failed scan has its own error
          // (round 14: 「未掃到 PTU」 beside a get_ble_devices timeout).
          if (topology.isDirect &&
              !c.directFlow &&
              s.ptus.isEmpty &&
              s.relistReason.isEmpty &&
              !s.busy &&
              s.error == null)
            Padding(
              key: const Key('direct-no-ptu-hint'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '未掃到 PTU，請確認 PTU 已上電後重新掃描',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (s.absentNotice.isNotEmpty)
            Padding(
              key: const Key('absent-notice'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.absentNotice,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (s.assignFailed.isNotEmpty)
            Padding(
              key: const Key('assign-failed-list'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.assignFailed.length} 台指派失敗：',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  for (final e in s.assignFailed.entries)
                    Text('PTU ${e.key}：${e.value}'),
                ],
              ),
            ),
          if (topology.isStar && s.starNotice.isNotEmpty)
            Padding(
              key: const Key('star-owner-notice'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.starNotice,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          // Round 26: PTUs carrying this gateway's numbers but not on its
          // allow list (ignored by the gateway), in plain words.
          if (topology.isStar)
            if (foreignPtuText(foreign: s.foreignPtus, unlisted: s.unlistedPtus)
                case final text?)
              Padding(
                key: const Key('foreign-ptu-notice'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  text,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          if (topology.isStar &&
              s.starListSwitch &&
              s.starList == StarListStatus.failed)
            Padding(
              key: const Key('star-list-switch-failed'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                starListSwitchFailedText,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          // Round 27: the list sent before the first assign did not go
          // through; the assignment went on anyway.
          if (topology.isStar &&
              s.starListStage == StarListStage.beforeAssign &&
              s.starList == StarListStatus.failed)
            Padding(
              key: const Key('star-list-before-failed'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                starListBeforeFailedText,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!directStep7)
            ...s.ptus.map((ptu) {
              final blocked = c.ptuOutOfRange(ptu);
              final resetFailed = s.resetFailed.contains(ptu['mac']);
              return PtuSelectionTile(
                blockedText: resetFailed
                    ? resetFailedText
                    : c.ptuOwnerConfirmed(ptu)
                    ? '已屬於其他閘道器'
                    : '編號不在本機範圍，所屬閘道器未確認',
                resetLabel: resetFailed ? '重試' : '重置並納入',
                key: ValueKey('ptu-${ptu['mac']}'),
                ptu: ptu,
                selected: s.selected.contains(ptu['mac']),
                result: s.results[ptu['mac']],
                status: s.assignStatus[ptu['mac']],
                statusText: switch (s.assignStatus[ptu['mac']]) {
                  final a? => assignStatusText(
                    a,
                    result: s.results[ptu['mac']],
                    failure: s.assignFailed[ptu['mac']],
                  ),
                  null => null,
                },
                blocked: blocked,
                // 直連模式：已自動勾選 RSSI 最強的一台，這裡只留「配置並開始監控」
                // 當確認鈕，不再開放改選。星狀模式：範圍外（屬於其他閘道器）的
                // PTU 不能直接勾，要先「重置並納入」。
                onChanged: enabled && !topology.isDirect && !blocked
                    ? (value) => c.select(ptu['mac'].toString(), value)
                    : null,
                onReset: enabled && blocked
                    ? () => c.resetAndInclude(ptu['mac'].toString())
                    : null,
              );
            }),
          if (s.ptus.length > 1 && !directStep7 && !directRunning)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('ptu-resort'),
                icon: const Icon(Icons.sort, size: 18),
                onPressed: enabled ? c.sortPtusBySignal : null,
                label: const Text('依訊號重新排序'),
              ),
            ),
          if (!directStep7 && !directRunning)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              // Values update in place; the order changes only on a rescan or
              // 「依訊號重新排序」, so a tap never lands on a row that moved.
              title: const Text('動態 RSSI · 每 5 秒更新（順序不變）'),
              value: s.autoRssi,
              onChanged: enabled ? c.setAutoRssi : null,
            ),
          if (s.missing.isNotEmpty) Text('尚未連線：${s.missing.join('、')}'),
          if (!directRunning)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '掃描說明與完整流程',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              children: [
                Text(
                  '由閘道器掃描附近的 PTU，再透過藍牙把清單傳回手機。'
                  '${c.directFlow
                      ? "直連模式：由閘道器自己選最近的 PTU（門檻內最強，或已綁定的那台），這裡只顯示它的選擇；請用「辨識此樁」確認是眼前這台，不是的話按「不是這台？」改選。"
                      : topology.isDirect
                      ? "直連模式：已自動選定訊號最強的一台。"
                      : "最多可選 ${ref.read(topologyProvider).starCount} 台。"}'
                  'RSSI 是閘道器與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。',
                ),
                // The step list is in 「設備與連線資訊」 (09-28).
              ],
            ),
        ];
      case 6:
        // 09-28: the direct flow's data check runs by itself — while it
        // runs, only its progress (「取消操作」 stays below the card).
        final autoRunning = c.directFlow && s.busy;
        return [
          // 1.0.0+18: the data flow on top of the card, live.
          VerifyLiveHeader(
            key: const Key('verify-live'),
            feed: s.verifyFeed,
            busy: s.busy,
            passed: s.verifyPassed,
            ptus: s.verifyCounts.length,
          ),
          const SizedBox(height: 12),
          const Text(verifyGoalText, key: Key('verify-goal')),
          const SizedBox(height: 16),
          if (autoRunning)
            const SizedBox.shrink()
          else if (environment == BackendEnv.custom)
            BackendUrlField(controller: _base, label: '後端網址', enabled: enabled)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              // The URL is in 「連線狀態」 → 技術細節.
              child: Text(
                '驗證後端：${env.label}'
                '${environment == BackendEnv.local ? '（這台電腦上的測試主機）' : ''}',
              ),
            ),
          // Round 8: listed in scan order (#1, #2, #4, #3); by number now.
          ...byDeviceNumber(s.ptus).map((ptu) {
            final id = (ptu['device_number'] as num?)?.toInt() ?? 0;
            final count = s.verifyCounts[id];
            final skip =
                count != null &&
                s.verifyWaiting.contains(id) &&
                !s.verifySkipped.contains(id);
            // 1.0.0+18: the PTU's last rows under its line.
            final rows = s.verifyFeed.where((e) => e.id == id).toList();
            // 1.0.0+10 (review: the trailing count and 〔略過此台〕 squeezed
            // the title at 360 dp): the count / state alone on the right,
            // 〔略過此台〕 under the MAC.
            final tile = ListTile(
              key: Key('verify-ptu-$id'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sensors),
              title: Text('PTU #$id'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ptu['mac'].toString()),
                  if (skip)
                    TextButton(
                      key: Key('verify-skip-$id'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => c.skipVerifyPtu(id),
                      child: const Text('略過此台'),
                    ),
                ],
              ),
              trailing: count == null
                  ? null
                  : Text(
                      s.verifySkipped.contains(id)
                          ? '未驗證（已略過）'
                          : s.verifyWaiting.contains(id)
                          ? '尚無資料'
                          : '$count/3',
                      key: Key('verify-count-$id'),
                    ),
            );
            if (rows.isEmpty) return tile;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile,
                VerifyFeedRows(key: Key('verify-feed-ptu-$id'), entries: rows),
              ],
            );
          }),
          if (!autoRunning) ...[
            TextButton(
              key: const Key('verify-back'),
              // Keeps the selection and what was assigned; no cancel.
              onPressed: c.backToSelection,
              child: const Text('返回選擇 PTU'),
            ),
            TextButton(
              onPressed: enabled ? c.rescanPtus : null,
              child: const Text('返回選擇 PTU，由閘道器重新掃描'),
            ),
            button(
              '開始資料驗證',
              _startVerify,
              enabled && s.ptus.any((p) => s.selected.contains(p['mac'])),
            ),
          ],
          // The status/error banner is at the top of the page; repeat it
          // here so a tap at the bottom never looks like nothing happened.
          if (s.busy || s.error != null)
            Padding(
              key: const Key('verify-feedback'),
              padding: const EdgeInsets.only(top: 12),
              child: s.busy
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text('${s.message}（${s.seconds} 秒）')),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          s.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        // Round 13: the backend stayed down through the
                        // automatic retries; the progress so far is kept.
                        if (s.verifyBackendDown)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: FilledButton.icon(
                              key: const Key('verify-retry-bottom'),
                              icon: const Icon(Icons.refresh, size: 20),
                              onPressed: _startVerify,
                              label: const Text('重試'),
                            ),
                          ),
                      ],
                    ),
            ),
        ];
      default:
        // Round 29 (field drill: 「不知道該如何結束」): the summary is on top
        // ([_doneSummary]) and 〔完成〕／〔配置下一台〕 at the bottom
        // ([_doneBar]); what is left here is secondary.
        final deferred = s.ptuDeferred;
        return [
          if (deferred) ..._deferredDone(s, c, enabled),
          // Round 26: a failed star allow list keeps the completion, with
          // 「重試寫入綁定名單」 (the status line is in the summary).
          if (topology.isStar &&
              s.starListStage == StarListStage.verified &&
              s.starList == StarListStatus.failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const Key('star-list-retry'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: enabled ? c.writeStarList : null,
                label: const Text(starListRetryLabel),
              ),
            ),
          // Round 18: measure the site and write the threshold back.
          if (topology.isDirect &&
              !deferred &&
              s.peer != null &&
              directAutoConnectSupported(s.config))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const Key('done-calibrate'),
                icon: const Icon(Icons.tune, size: 20),
                onPressed: enabled && c.calibrationOwnMac != null
                    ? () => openDirectCalibration(context)
                    : null,
                label: const Text(calibrationTitle),
              ),
            ),
          // After a switch of environment: log in there to check the data.
          if (!s.loggedIn && !deferred) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('done-login'),
              onPressed: enabled
                  ? () async {
                      if (!_credentialReady(demo)) return;
                      await c.login(ref.read(backendEnvProvider).base);
                      if (mounted && ref.read(commissionProvider).loggedIn) {
                        await c.refreshHealth();
                      }
                    }
                  : null,
              child: const Text('登入並確認資料'),
            ),
          ],
          // Round 29: 「出貨前切回正式站」 — a developer note of a local test
          // build only, below the summary; never the page's main action.
          if (ref.read(envSwitchPolicyProvider).localBuild &&
              parseMqttTarget(s.config)?.isLocal == true)
            _devShipNote(enabled),
          _reportTile(s, enabled),
          if (s.loggedIn && !deferred)
            TextButton(
              onPressed: enabled ? () => c.refreshHealth() : null,
              child: const Text('更新健康狀態'),
            ),
          if (!deferred)
            TextButton(
              onPressed: enabled
                  ? () async {
                      if (s.loggedIn) {
                        await c.repair();
                      } else if (_credentialReady(demo)) {
                        await c.repair(base: ref.read(backendEnvProvider).base);
                      }
                    }
                  : null,
              child: const Text('重新連線並驗證'),
            ),
        ];
    }
  }

  /// Round 29 (field drill: the done page opened on 「本地測試主機 ✓ 資料上傳
  /// 中」, a red 「出貨前請切回正式站」 and its biggest button; 「開通完成」
  /// came after): the success summary on top — done, the station and
  /// gateway, the mode, the PTU and its binding, the data upload.
  Widget _doneSummary(
    CommissionState s,
    CommissioningController c,
    bool demo,
    BackendEnvState env,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final topology = ref.read(topologyProvider).topology;
    final deferred = s.ptuDeferred;
    final probe = demo ? null : ref.watch(backendProbeProvider(env.base)).value;
    final upload = connectionStatus(
      env: env,
      state: s,
      probe: probe,
      demo: demo,
    ).gateway;
    final bound = topology.isDirect && !deferred ? directBoundNote(s) : null;
    Widget line(String text, {Key? key, Color? color, bool strong = false}) =>
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            text,
            key: key,
            style: TextStyle(
              color: color,
              fontWeight: strong ? FontWeight.w600 : null,
            ),
          ),
        );
    return Card(
      key: const Key('done-summary'),
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  deferred
                      ? Icons.task_alt
                      : s.online
                      ? Icons.check_circle
                      : Icons.cloud_off,
                  size: 40,
                  color: colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    deferred
                        ? deferredDoneTitle
                        : demo
                        ? '模擬開通完成'
                        : '開通完成',
                    key: const Key('done-title'),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _doneLabelCard(c.site, c.gateway),
            line('模式：${topology.label}', key: const Key('done-mode')),
            if (bound != null)
              line(bound, key: const Key('direct-bound-note'))
            else
              line(
                commissionSummaryText(s),
                key: const Key('commission-summary'),
              ),
            // Round 26: the star allow list written after verification.
            if (topology.isStar &&
                s.starListStage == StarListStage.verified &&
                s.starList != StarListStatus.none)
              line(
                switch (s.starList) {
                  StarListStatus.writing => '$starListWritingText…',
                  StarListStatus.written => starListWrittenText(s.starListIds),
                  _ => starListFailedText,
                },
                key: const Key('star-list-text'),
                color: s.starList == StarListStatus.failed
                    ? colors.error
                    : null,
              ),
            line(
              upload.status.isEmpty
                  ? '資料上傳：${upload.where}'
                  : '資料上傳：${upload.status}（${upload.where}）',
              key: const Key('done-upload'),
              color: toneColor(context, upload.tone),
            ),
            // 1.0.0+19: the interval is the back office's (the APP only
            // set one reading a second while commissioning); after
            // 〔先完成配置〕 too.
            line(
              uploadRateText(s.uploadIntervalMs),
              key: const Key('done-upload-rate'),
            ),
            // 09-28 / r32: the report goes to the back office on its own;
            // its status (sent / queued / failed with 〔重送〕) sits in the
            // summary so it is on the first screen (r32: below the fold).
            InstallReportStatusLine(enabled: !s.busy),
            if (!deferred && s.message.isNotEmpty)
              line(s.message, key: const Key('done-message')),
            // Until the first health check answers, say so instead of a
            // premature 資料有異常.
            if (showHealthPending(s))
              line(healthPendingText, key: const Key('health-pending')),
            // Round 28/29: after 〔先完成配置〕 — the PTU connects once
            // powered, the binding is confirmed on site later.
            if (deferred) _deferredNote(),
          ],
        ),
      ),
    );
  }

  /// 1.0.0+13: the station and gateway in large type — 「請在機殼上標示：站 S
  /// · 閘道器 N」 — so the installer writes it on the gateway's housing and
  /// the back office can find the unit it means. Nothing to press.
  Widget _doneLabelCard(int site, int gateway) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fg = colors.onPrimaryContainer;
    return Semantics(
      container: true,
      label: doneLabelText(site, gateway),
      excludeSemantics: true,
      child: Container(
        key: const Key('done-label'),
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.primary, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.edit_note, color: fg, size: 28),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doneLabelHead,
                    key: const Key('done-label-head'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    gatewayIdText(site, gateway),
                    key: const Key('done-gateway'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      doneLabelHint,
                      key: const Key('done-label-hint'),
                      style: theme.textTheme.bodySmall?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Round 28: the note of the done page after 〔先完成配置〕 (round 29: in
  /// the summary).
  Widget _deferredNote() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final warnFg = dark ? Colors.amber.shade200 : Colors.brown.shade900;
    final warnBg = dark
        ? Colors.amber.shade900.withValues(alpha: 0.35)
        : Colors.amber.shade100;
    return Container(
      key: const Key('deferred-note'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warnBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: warnFg, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              deferredDoneText,
              style: TextStyle(color: warnFg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Round 29: 〔完成〕 (main: the start page, the progress cleared) and
  /// 〔配置下一台〕 (the gateway list, the station kept), fixed at the bottom
  /// of the done page whatever the scroll or the font size.
  Widget _doneBar(CommissionState s, CommissioningController c) {
    final colors = Theme.of(context).colorScheme;
    final enabled = !s.busy;
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 09-28: 〔查看最近資料〕 — the back office's last rows from
              // this gateway on its own page, through the APP's session
              // (no dashboard login, no key). Secondary to 〔完成〕.
              TextButton.icon(
                key: const Key('done-recent'),
                onPressed: enabled
                    ? () => RecentDataPage.open(context, c.site, c.gateway)
                    : null,
                icon: const Icon(Icons.table_rows_outlined, size: 20),
                label: const Text(recentDataLabel),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('done-next'),
                      onPressed: enabled
                          ? () => _finishDone(c, next: true)
                          : null,
                      child: const Text(doneNextLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('done-finish'),
                      onPressed: enabled ? () => _finishDone(c) : null,
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text(doneFinishLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Round 29: 〔完成〕／〔配置下一台〕, and 返回 on the done page.
  Future<void> _finishDone(
    CommissioningController c, {
    bool next = false,
  }) async {
    await c.finishDone(next: next);
    if (mounted && _pageScroll.hasClients) _pageScroll.jumpTo(0);
  }

  /// Round 29: the developer note of a local test build whose gateway still
  /// uploads to the local test host — small and muted, below the summary,
  /// with a text button (field drill: a red box and the page's biggest
  /// button read as the next step).
  Widget _devShipNote(bool enabled) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: const Key('dev-ship-note'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.developer_mode,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  devShipNoteText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('dev-ship-switch'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: theme.textTheme.bodySmall,
              ),
              onPressed: enabled
                  ? () => _applyEnvironment(
                      BackendEnv.production,
                      fromSheet: true,
                    )
                  : null,
              child: const Text(devShipSwitchLabel),
            ),
          ),
        ],
      ),
    );
  }

  /// Round 29: the install report, collapsed, with 分享／複製 inside.
  Widget _reportTile(CommissionState s, bool enabled) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: const Key('done-report'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      // 1.0.0+10: a collapsed section's title (bodyMedium).
      title: Text(
        s.report.startsWith('模擬') ? '模擬安裝報告' : '安裝報告',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: const Text('全文；也可分享或複製'),
      children: [
        SelectableText(s.report),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('report-share'),
              icon: const Icon(Icons.share, size: 20),
              onPressed: enabled
                  ? () async {
                      try {
                        await const MethodChannel(
                          'voltraware/report',
                        ).invokeMethod<void>('share', {'text': s.report});
                      } on PlatformException {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('無法開啟分享，可改用複製報告。')),
                          );
                        }
                      }
                    }
                  : null,
              label: const Text('分享安裝報告'),
            ),
            TextButton.icon(
              key: const Key('report-copy'),
              icon: const Icon(Icons.copy, size: 20),
              onPressed: enabled
                  ? () async {
                      await Clipboard.setData(ClipboardData(text: s.report));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已複製，可貼上分享')),
                        );
                      }
                    }
                  : null,
              label: const Text('複製安裝報告'),
            ),
          ],
        ),
      ],
    ),
  );

  /// Round 28: the done page after 〔先完成配置〕 — the PTU is not connected
  /// yet and connects once powered; the binding is made later (on site:
  /// 〔PTU 已上電：辨識並綁定〕 right here). Round 29: its note is in the
  /// summary ([_deferredNote]); these are the details and the action.
  List<Widget> _deferredDone(
    CommissionState s,
    CommissioningController c,
    bool enabled,
  ) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          deferredDetailText(directMinRssiOf(s.config)),
          key: const Key('deferred-detail'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          deferredLaterText,
          key: const Key('deferred-later'),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          key: const Key('deferred-bind-now'),
          icon: const Icon(Icons.lightbulb_outline, size: 20),
          onPressed: enabled ? c.bindDeferredNow : null,
          label: const Text(deferredBindNowLabel),
        ),
      ),
    ];
  }

  /// Round 28: a gateway in service, one-to-one and unbound, that is
  /// connected to a PTU (or that this phone finished with 〔先完成配置〕):
  /// 〔辨識並綁定〕 goes to step 7 to identify and bind it.
  Widget _bindLaterCard(CommissionState s, CommissioningController c) {
    final theme = Theme.of(context);
    final mac = s.bindLaterMac;
    return Card(
      key: const Key('bind-later'),
      color: theme.colorScheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            macRichText(
              mac != null ? bindLaterTitle(mac) : bindLaterWaitingTitle,
              key: const Key('bind-later-title'),
              style: TextStyle(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              mac != null ? bindLaterHint : bindLaterWaitingHint,
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('bind-later-go'),
              icon: const Icon(Icons.lightbulb_outline, size: 20),
              onPressed: s.busy ? null : c.startBindLater,
              label: const Text(bindLaterLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// r34: a gateway in service, one-to-one and bound, whose bound PTU is
  /// not connected ([CommissionState.ptuMissingMac]): 〔更換 PTU〕 clears
  /// the binding and goes to step 7, 〔PTU 已上電，重新檢查〕 reads again;
  /// green 「PTU 已連線」 once the re-check found it
  /// ([CommissionState.ptuMissingBack]).
  ///
  /// 1.0.0+10: texts, tone and buttons from [ptuCardView] — neutral
  /// 「正在尋找本樁 PTU…」 with 〔重新檢查〕 only while the gateway is still
  /// looking.
  Widget _ptuMissingCard(CommissionState s, CommissioningController c) {
    final theme = Theme.of(context);
    final mac = s.ptuMissingMac!;
    final view = ptuCardView(s)!;
    final fg = switch (view.tone) {
      PtuCardTone.ok => Colors.green.shade900,
      PtuCardTone.searching => theme.colorScheme.onSurface,
      PtuCardTone.missing => theme.colorScheme.onErrorContainer,
    };
    final bg = switch (view.tone) {
      PtuCardTone.ok => Colors.green.shade100,
      PtuCardTone.searching => theme.colorScheme.surfaceContainerHighest,
      PtuCardTone.missing => theme.colorScheme.errorContainer,
    };
    return Card(
      key: const Key('ptu-missing'),
      color: bg,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            macRichText(
              view.title,
              key: const Key('ptu-missing-title'),
              style: TextStyle(color: fg, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(view.hint, style: TextStyle(color: fg)),
            if (view.replace) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('ptu-missing-replace'),
                icon: const Icon(Icons.swap_horiz, size: 20),
                onPressed: s.busy ? null : () => _replacePtu(c, mac),
                label: const Text(replacePtuLabel),
              ),
            ],
            if (view.recheck.isNotEmpty) ...[
              SizedBox(height: view.replace ? 4 : 8),
              OutlinedButton.icon(
                key: const Key('ptu-missing-recheck'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: s.busy ? null : c.recheckBoundPtu,
                label: Text(view.recheck),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// r34: 〔更換 PTU〕 asks first (it clears the gateway's binding).
  Future<void> _replacePtu(CommissioningController c, String mac) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(replacePtuConfirmTitle),
        content: Text(replacePtuConfirmText(mac)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(replacePtuLabel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await c.replaceBoundPtu();
  }

  /// Step 7 without a login: the build must carry a backend credential
  /// (09-28: there is no password field to fill in).
  bool _credentialReady(bool demo) {
    if (demo || ref.read(backendKeyProvider).isNotEmpty) return true;
    _snack(missingBackendKeyText);
    return false;
  }

  /// A check line: the mark in its tone colour, the words in the normal one.
  Widget _markedText(CheckLine line, {Key? key}) => Text.rich(
    key: key,
    TextSpan(
      children: [
        TextSpan(
          text: '${line.mark} ',
          style: TextStyle(
            color: toneColor(context, line.tone),
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(text: line.text),
      ],
    ),
  );

  /// Round 23 (field rounds 22/23: after the gateway connect the page
  /// starts at its title — [_connectPeer] jumps to the top so the new step
  /// is read from its start — and 「下一步：選擇站點」, the card's last row
  /// below the step list and the 連線狀態 panel, was a swipe away): the
  /// network check's 「下一步」 once it is ready, shown in the bottom bar so
  /// it is on screen whatever the scroll; null otherwise.
  (String, VoidCallback)? _checkNext(
    CommissionState s,
    CommissioningController c,
    BackendEnvState env,
  ) {
    // Round 30 (user rehearsal 09-27, E: 110 s at 確認資料上傳 and a help
    // request): its 「下一步」 is in the bottom bar too, always on screen.
    if (s.step == 3) {
      // 09-28: stopped on an archived station — 〔重新加入〕, then the
      // heartbeats are waited for again.
      if (s.identityArchived) {
        return (
          rejoinLabel,
          () => c.rejoinArchived(
            base: env.base,
            environment: env.environment.name,
          ),
        );
      }
      if (s.error == null && s.loggedIn && !s.offline && !_autoOnlineStarted) {
        return null;
      }
      return (
        confirmOnlineLabel,
        () => c.online(base: env.base, environment: env.environment.name),
      );
    }
    if (s.step != 2 || s.checkPassed) return null;
    if (!networkCheck(state: s, env: env).ready) return null;
    if (!_autoCheckPaused && s.error == null) return null;
    // Round 26: after a Wi-Fi reset the station is chosen again.
    // 09-28: named after its action (no 「下一步：…」).
    return (
      checkContinueLabel,
      () {
        _autoCheckPaused = false;
        c.passNetworkCheck();
      },
    );
  }

  /// 「Gateway 網路體檢」 → 「對準上傳目標」 → 「確認資料上傳」 (step 2
  /// before the station choice; again after a Wi-Fi change that keeps the
  /// station, before the data verification).
  List<Widget> _networkCheck(
    CommissionState s,
    CommissioningController c,
    NetworkCheck check,
    bool enabled,
  ) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final station = s.config['fleet_joined'] == true;
    // Wi-Fi changed with the station kept: review a fresh PTU scan next.
    final recheck = s.config['wifi_only'] == true;
    final wifiAction = check.wifiVerdict == WifiVerdict.notConfigured
        ? '設定 Wi-Fi'
        : '重設 Wi-Fi';

    Widget item(String title, CheckLine line, String key) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodySmall?.merge(muted)),
          const SizedBox(height: 2),
          _markedText(line, key: Key(key)),
        ],
      ),
    );

    final skipLabel = station
        ? '先選擇站點（沿用要等網路正常）'
        : s.offline
        ? '先離線配置新站點（稍後再確認上傳）'
        : '仍要繼續設定新站點（稍後再確認上傳）';

    return [
      // 1.0.0+10: a card title (titleSmall w700).
      Text(
        recheck ? '確認資料上傳' : '閘道器網路體檢',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        recheck
            ? 'Wi-Fi 已更新。等閘道器開始上傳資料，再確認站點（沿用或設定新站點）。'
            : '先確認閘道器能上網、資料送對地方，再選擇站點。',
        style: muted,
      ),
      item('閘道器的 Wi-Fi', check.wifi, 'check-wifi'),
      // Joined but weak: red, with what to do (advice, not a blocker).
      if (check.wifiWeak != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            check.wifiWeak!,
            key: const Key('check-wifi-weak'),
            style: TextStyle(color: toneColor(context, StatusTone.bad)),
          ),
        ),
      if (check.wifiProblem) ...[
        button(wifiAction, _fixWifi, enabled),
        if (check.need == SyncNeed.sync)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '按下後會先讓閘道器改送到${placeOf(check.syncTarget!)}'
              '（重新開機一次），再設定 Wi-Fi。',
              style: muted,
            ),
          ),
      ],
      item('資料送到哪裡', check.target, 'check-target'),
      if (!check.wifiProblem && check.need == SyncNeed.sync)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              key: const Key('check-sync'),
              onPressed: enabled ? () => _syncGateway(explicit: true) : null,
              child: Text('讓閘道器改送到${placeOf(check.syncTarget!)}（重新開機約 1 分鐘）'),
            ),
          ),
        ),
      item('資料上傳', check.upload, 'check-upload'),
      // Round 26 (field: 「✓ 資料上傳中」 with the upload paused).
      if (check.uploadPaused && !check.testMode)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              key: const Key('check-resume-upload'),
              onPressed: enabled ? c.resumeUpload : null,
              child: const Text(resumeUploadLabel),
            ),
          ),
        ),
      if (check.uploadHint != null)
        Container(
          key: const Key('check-hint'),
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          color: theme.colorScheme.secondaryContainer,
          child: Text(
            check.uploadHint!,
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
          ),
        ),
      if (check.wifiOk &&
          check.targetOk &&
          !check.uploadOk &&
          check.upload.tone == StatusTone.bad)
        TextButton(
          onPressed: enabled ? _fixWifi : null,
          child: const Text('重設 Wi-Fi'),
        ),
      // Round 23: once ready, 「下一步」 is in the bottom bar ([_checkNext]).
      if (!check.ready)
        TextButton(
          key: const Key('check-refresh'),
          onPressed: enabled ? c.refreshUploadTarget : null,
          child: const Text('重新檢查'),
        ),
      // A new gateway with no Wi-Fi fixes it from the button above (1.0.0+15:
      // the Wi-Fi first, then the station); no skip past it while online.
      if (!recheck &&
          check.canSkip &&
          (s.offline || station || !check.wifiProblem)) ...[
        TextButton(
          key: const Key('check-skip'),
          onPressed: enabled ? () => c.passNetworkCheck(skip: true) : null,
          child: Text(skipLabel),
        ),
        Text(
          station
              ? '沒有通過網路體檢時不能沿用目前站點；可以重設 Wi-Fi 或設定新站點。'
              : '⚠ 閘道器的網路還沒確認好。設定完新站點後會再確認資料上傳，'
                    '最後的「驗證資料」也會檢查。',
          style: muted,
        ),
      ],
      if (recheck && station && !check.ready)
        TextButton(
          onPressed: enabled ? c.backToStationChoice : null,
          child: const Text('回到站點選擇'),
        ),
    ];
  }
}

/// The steps in order, the current one highlighted.
class StepList extends StatelessWidget {
  const StepList({super.key, required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    return Wrap(
      key: const Key('step-list'),
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final (i, label) in stepLabels.indexed)
          Text(
            '${i + 1} $label',
            style: small?.copyWith(
              color: i == current
                  ? colors.primary
                  : i < current
                  ? colors.onSurfaceVariant
                  : colors.outline,
              fontWeight: i == current ? FontWeight.w700 : null,
            ),
          ),
      ],
    );
  }
}

/// Round 21 (field round 21: 140 s with a spinner only): the step 8 run
/// above the PTU rows — 「3/5 完成，1 台自動重試中」 with a bar, and while it
/// runs that the APP handles retries by itself.
class AssignProgressHeader extends StatelessWidget {
  const AssignProgressHeader({
    super.key,
    required this.text,
    required this.value,
    required this.running,
    required this.failed,
  });

  final String text;
  final double value;
  final bool running;

  /// PTUs out of automatic retries.
  final int failed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('assign-progress'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text,
            key: const Key('assign-progress-text'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: value),
          if (running || failed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                running ? assignAutoHint : assignFailedHint(failed),
                key: const Key('assign-progress-hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: running ? colors.onSurfaceVariant : colors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- One-thing screens (09-28): each page's one sentence and its buttons.

const startTaskTitle = '登入後台，開始配置';
const pickGatewayTaskTitle = '請選擇眼前要配置的閘道器，可按辨識確認';
const checkingTaskTitle = '正在連線並檢查網路，請稍候';
const checkPassedTaskTitle = '網路檢查通過，看完請按下方繼續';
const testModeTaskTitle = '閘道器在測試模式，請先切回正常模式';
const wifiProblemTaskTitle = '閘道器沒有連上 Wi-Fi，請設定 Wi-Fi';
const targetTaskTitle = '請讓閘道器把資料送到目前的後台';
const uploadPausedTaskTitle = '閘道器的資料上傳已暫停，請恢復上傳';
const uploadBadTaskTitle = '閘道器還沒開始上傳資料，請依下方提示處理';
const wifiTaskTitle = '設定閘道器的 Wi-Fi';

/// 1.0.0+15: the Wi-Fi-first page of a gateway not in service.
const wifiFirstPageText = '先讓閘道器連上 Wi-Fi，網路正常後再設定站號。';
String stationQuestionTitle(int site) => '目前站號是 $site，這台要配置在本站嗎？';
const stationInputTitle = '請輸入這台要配置的站號';
const onlineRunningTaskTitle = '正在確認閘道器上線，請稍候';
const onlineTaskTitle = '確認閘道器上線';
const directPickTaskTitle = '請辨識眼前的充電樁，確認後開始配置';
const starPickTaskTitle = '請選擇本閘道器負責的 PTU';
const starAssignTaskTitle = '正在配置 PTU 並開始監控';
const starVerifyTaskTitle = '正在確認資料上傳';
const verifyLoginTaskTitle = '請登入後台，確認資料上傳';
const finishingTaskTitle = '正在完成設定並確認資料上傳';

const useStationLabel = '使用此站點';
const useSiteEmptyLabel = '使用站點';
String useSiteLabel(int site) => '使用站點 $site';
const otherSiteLabel = '改用其他站號';
const otherWifiLabel = '改用其他 Wi-Fi';
const saveWifiLabel = '儲存並繼續';
const siteFieldLabel = '站號（1–65535）';
const checkContinueLabel = '繼續設定站點';
const detailsTitle = '設備與連線資訊';
const newSiteConfirmTitle = '確定是新站？';
String newSiteConfirmText(int site) =>
    '後台還沒有站號 $site 的任何閘道器。請確認站號沒有打錯；確定是新站再繼續。';

/// 09-28: the station chosen is archived in the back office (GC 刪除).
const archivedConfirmTitle = '這台閘道器之前在後台被移除（封存），要重新加入嗎？';
String archivedConfirmText(int site, int gw) =>
    '站點 $site／閘道器 $gw 在後台已被移除（封存）。封存的閘道器，後台不會記錄它的心跳，'
    '配置會停在「確認閘道器上線」。重新加入後會恢復記錄，原本的歷史資料不變。';
const archivedRejoinLabel = '重新加入並繼續';

/// r33: the auto-numbering skipped a number another device holds.
/// 1.0.0+13: the done page's label card — 「請在機殼上標示：」, the station
/// and gateway in large type, and why.
const doneLabelHead = '請在機殼上標示：';
const doneLabelHint = '後台人員靠這個標示找到這台';

/// 「請在機殼上標示：站 80 · 閘道器 2」 (the card read as one).
String doneLabelText(int site, int gateway) =>
    '$doneLabelHead${gatewayIdText(site, gateway)}';

/// 1.0.0+19: the done page's upload interval line — the back office's
/// policy ([CommissionState.uploadIntervalMs]); null (not read): no number.
const uploadRateHead = '資料上傳頻率由後台控制';
String uploadRateText(int? ms) {
  if (ms == null) return uploadRateHead;
  final seconds = ms % 1000 == 0
      ? '${ms ~/ 1000}'
      : (ms / 1000).toStringAsFixed(1);
  return '$uploadRateHead（目前每 $seconds 秒）';
}

const numberTakenTitle = '閘道器編號已被使用';
String numberTakenText(int site, int taken, int gw) =>
    '站 $site 的閘道器 $taken 已被其他設備使用，改用閘道器 $gw。';

/// 1.0.0+12: [numberTakenText] when the station has no free number left.
String numberTakenOnlyText(int site, int taken) =>
    '站 $site 的閘道器 $taken 已被其他設備使用。';

/// 1.0.0+13: instead of [numberTakenReplaceHint] (and without 〔取代舊機〕)
/// while the gateway holding [taken] is online.
String numberTakenOnlineText(int taken) =>
    '閘道器 $taken 目前在線上，不能取代；如果這台是來換掉它，請先把舊機斷電。';
String numberTakenReplaceHint(int taken) =>
    '若這台是來取代那台舊機（舊機已拆除或斷電），按〔取代舊機〕沿用閘道器 $taken。';
String numberTakenReplaceLabel(int taken) => '取代舊機（沿用閘道器 $taken）';
String numberTakenNextLabel(int gw) => '改用閘道器 $gw';

/// r33: the back office flags this gateway's own number in conflict.
const identityConflictTitle = '身分衝突';
String identityConflictHint(int site, int gw) =>
    '若舊機已拆除或換掉，按〔取代舊機〕由這台接手站 $site／閘道器 $gw；'
    '否則請先找出另一台同編號的閘道器，或改用其他站號。';
const replaceOldLabel = '取代舊機';
String replacedText(int site, int gw) => '已由這台接手站 $site／閘道器 $gw';
const replaceFailedText = '取代舊機沒有成功，請確認網路後重試';

/// r33: the connected gateway already runs in another mode than the APP's.
String topologyAskTitle(GatewayTopology gateway) =>
    gateway.isDirect ? '這台閘道器是一對一模式' : '這台閘道器是星狀模式';
String topologyAskText(GatewayTopology gateway, Map<String, dynamic> config) {
  if (gateway.isDirect) {
    final mac = gatewayBoundMac(config);
    final bound = mac == null ? '尚未綁定 PTU' : '已綁定 PTU $mac';
    return '這台閘道器目前是一對一模式（$bound），要改成星狀嗎？\n\n'
        '選〔維持一對一〕：APP 改用直連模式，閘道器的設定不變。';
  }
  final max = (config['max_connections'] as num?)?.toInt() ?? maxStarPtuCount;
  return '這台閘道器目前是星狀模式（最多 $max 台 PTU），要改成一對一嗎？\n\n'
      '選〔維持星狀〕：APP 改用星狀模式，閘道器的設定不變。';
}

String topologyKeepLabel(GatewayTopology gateway) =>
    gateway.isDirect ? '維持一對一' : '維持星狀';
String topologyChangeLabel(GatewayTopology gateway) =>
    gateway.isDirect ? '改成星狀' : '改成一對一';
String topologyKeptText(GatewayTopology gateway) =>
    'APP 已改用${gateway.label}，這台閘道器維持原模式';

/// 09-28: 確認上線 stopped on an archived station — the bottom bar's action.
const rejoinLabel = '重新加入';
const rejoinHintText = '這台閘道器在後台被移除（封存），心跳不會被記錄。按下方「重新加入」後會繼續確認上線。';
