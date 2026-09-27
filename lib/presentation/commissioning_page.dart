import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/connection_status.dart';
import '../application/network_check.dart';
import '../application/topology_settings.dart';
import '../core/assign_progress.dart';
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
import 'local_backend_field.dart';
import 'ptu_selection_tile.dart';
import 'gateway_signal.dart';
import 'gateway_discovery.dart';
import 'gateway_mode_card.dart';

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

  /// Mirrors the selected backend URL (editable only for 其他網址); the
  /// source of truth is [backendEnvProvider].
  final _base = TextEditingController(text: productionApiBase);
  final _login = TextEditingController(),
      _ssid = TextEditingController(),
      _wifi = TextEditingController();
  final _site = TextEditingController(text: '1'),
      _gateway = TextEditingController(text: '1');
  bool _offline = false;

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
    if (previous == null ||
        previous.environment != next.environment ||
        previous.loaded != next.loaded) {
      _login.text = next.environment == BackendEnv.local
          ? localTestPassword
          : '';
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
    await c.connect(peer);
    if (mounted && _pageScroll.hasClients) _pageScroll.jumpTo(0);
    if (mounted) {
      final next = ref.read(commissionProvider);
      _site.text =
          '${next.config['suggested_site_id'] ?? next.config['site_id'] ?? 1}';
      _gateway.text =
          '${next.config['suggested_gateway_id'] ?? next.config['gateway_id'] ?? 1}';
      _gatewayKind = next.config['suggested_offline'] == true
          ? GatewaySuggestKind.offline
          : GatewaySuggestKind.online;
      _ssid.text = next.config['wifi_ssid']?.toString() ?? '';
      _customWifi = false;
      // Remembered environment: sync the gateway to it.
      if (next.error == null && next.step >= 2) {
        await _syncGateway(explicit: false);
      }
    }
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
    // Mid-flow the old login no longer applies; the local test host has a
    // known password, so log in again right away (other sites ask later).
    final env = ref.read(backendEnvProvider);
    final state = ref.read(commissionProvider);
    if (state.step >= 1 &&
        !state.loggedIn &&
        !_offline &&
        env.environment == BackendEnv.local &&
        env.localValid) {
      await ref
          .read(commissionProvider.notifier)
          .login(env.base, localTestPassword);
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
                : '已切換到${env.label}。${env.autoSync ? '連上 Gateway 後會自動讓它一起切換。' : '連上 Gateway 後可在「連線狀態」按「同步」。'}',
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
          _snack('正在把 Gateway 切到${target!.plainLabel}，約 1 分鐘，請留在 Gateway 旁。');
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
        _site.text =
            '${next.config['suggested_site_id'] ?? next.config['site_id'] ?? 1}';
        _gateway.text =
            '${next.config['suggested_gateway_id'] ?? next.config['gateway_id'] ?? 1}';
        _gatewayKind = next.config['suggested_offline'] == true
            ? GatewaySuggestKind.offline
            : GatewaySuggestKind.online;
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
    if (!wifiOnly) {
      final conflictMac = await c.conflictingMac(site, gw);
      if (conflictMac != null && mounted) {
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('編號已被使用'),
            content: Text(
              '站點 $site / 閘道器 $gw 目前登記給另一台裝置（MAC $conflictMac）。\n'
              '請先確認舊機已斷電，否則後台會再次標記衝突。',
            ),
            actions: [
              TextButton(
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

  /// Round 29 (field drill: the done page opened scrolled down, on the
  /// 連線狀態 panel and the 「切回正式站」 box): the done page starts at its
  /// summary.
  void _showDoneFromTop(CommissionState? previous, CommissionState next) {
    if (next.step != 7 || previous?.step == 7) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageScroll.hasClients) _pageScroll.jumpTo(0);
    });
  }

  /// Entering step 6 (驗證資料) starts one verification by itself when logged
  /// in; the manual button stays for re-runs.
  void _maybeAutoVerify(CommissionState? previous, CommissionState next) {
    if (next.step != 6) {
      _autoVerifyStarted = false;
      return;
    }
    if (_autoVerifyStarted ||
        next.busy ||
        !next.loggedIn ||
        next.error != null ||
        !next.ptus.any((p) => next.selected.contains(p['mac']))) {
      return;
    }
    _autoVerifyStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startVerify());
    });
  }

  Future<void> _startVerify() async {
    _flushBase();
    final current = ref.read(backendEnvProvider);
    await ref
        .read(commissionProvider.notifier)
        .verify(
          current.base,
          _login.text,
          environment: current.environment.name,
        );
    _afterLogin();
  }

  /// Round 13: a failed login (Bluetooth off, backend restarted, wrong
  /// password) never empties the password field, and the local test host
  /// keeps its known password; other backends clear it once logged in (the
  /// controller keeps it in memory to renew an expired session).
  void _afterLogin() {
    if (!mounted || !ref.read(commissionProvider).loggedIn) return;
    if (ref.read(backendEnvProvider).environment == BackendEnv.local) return;
    _login.clear();
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(backendEnvProvider, _onEnvironment, fireImmediately: true);
    ref.listenManual(commissionProvider, _maybeAutoVerify);
    ref.listenManual(commissionProvider, _showDoneFromTop);
    ref.listenManual(commissionProvider, _showRemoteIdentify);
    _host.addListener(() => _envController.setLocalHost(_host.text));
    _base.addListener(_onBaseEdited);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(commissionProvider.notifier).restore(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => ref
      .read(commissionProvider.notifier)
      .setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _pageScroll.dispose();
    _baseTyping?.cancel();
    _suggestTyping?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_base, _host, _login, _ssid, _wifi, _site, _gateway]) {
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

  /// Read-only auto-numbering shown instead of an editable 閘道器編號 field.
  Widget _gatewayAssignment() {
    final colors = Theme.of(context).colorScheme;
    if (_suggestingGateway) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text('正在計算閘道器編號…'),
      );
    }
    if (_gatewayKind == GatewaySuggestKind.full) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          '本站閘道器已滿（1–$kMaxGatewayId 皆已使用），請確認站點 ID 或改用「取代舊機」。',
          style: TextStyle(color: colors.error),
        ),
      );
    }
    final offlineHint = _gatewayKind == GatewaySuggestKind.offline
        ? ref.read(commissionProvider).peers.isEmpty
              ? '（無法取得同站閘道器清單，暫配 1 號，請上線核對）'
              : '（離線配號，上線後會再核對）'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        '將配置為 站點 ${_site.text} / 閘道器 ${_gateway.text}$offlineHint',
        style: TextStyle(color: colors.primary),
      ),
    );
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
  /// are full.
  bool get _gatewaySubmitBlocked => _gatewayKind == GatewaySuggestKind.full;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commissionProvider),
        controller = ref.read(commissionProvider.notifier);
    final demo = ref.watch(demoProvider),
        colors = Theme.of(context).colorScheme;
    final env = ref.watch(backendEnvProvider);
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
    return PopScope(
      // Round 28 (field round 28: a system 返回 at step 7 left the APP at
      // once, mid-configuration): only the start page and the gateway list
      // (nothing running) leave the APP. Otherwise 返回 asks 「結束目前
      // 配置？」 first, like 「結束並重新選擇閘道器」 ([_backPressed]); 結束
      // then also puts back a temporary 「不是這台？」 binding (round 15b).
      // Round 29: on the done page 返回 is 〔完成〕 (nothing to ask).
      canPop: state.step <= 1 && !state.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backPressed(controller);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GIOS 現場開通'),
          actions: [
            // Field rescue v1: no error, but the installer does not know
            // what to do next.
            if (state.step > 0 && !demo && controller.fieldHelpAvailable)
              IconButton(
                key: const Key('field-help-appbar'),
                icon: const Icon(Icons.support_agent),
                tooltip: fieldHelpLabel,
                onPressed: () => openFieldHelp(context, ref),
              ),
            EnvironmentChip(onPressed: _openEnvironmentSheet),
            // 拓撲模式（進階）：直連／星狀切換與星狀「每台 PTU 數」收在同一個選單，
            // 避免 360dp 窄螢幕被多個 AppBar action 擠壓（narrow 360dp widget test）。
            PopupMenuButton<String>(
              key: const Key('topology-menu'),
              tooltip: state.busy ? '操作進行中，完成後才能切換拓撲' : '拓撲模式（進階）',
              enabled: !state.busy,
              icon: const Icon(Icons.hub_outlined),
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
                }
              },
              itemBuilder: (_) => [
                for (final t in GatewayTopology.values)
                  CheckedPopupMenuItem(
                    value: 'topology:${t.name}',
                    checked: t == topology,
                    child: Text(t.label),
                  ),
                // 直連進階設定：只在直連、且已連上支援直連選台的韌體時出現。
                if (topology.isDirect &&
                    state.peer != null &&
                    directAutoConnectSupported(state.config)) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    key: Key('direct-settings'),
                    value: 'direct:settings',
                    child: Text('直連進階設定…'),
                  ),
                ],
                // Round 16: the star count opens its own dialog — one mis-tap
                // beside the topology items no longer changes it (round 15:
                // it was 4 after a direct run, R14 had ended at 5).
                if (topology.isStar) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    key: const Key('star-count'),
                    value: 'starcount',
                    child: Text('每台 PTU 數：${topologySettings.starCount}…'),
                  ),
                ],
              ],
            ),
            PopupMenuButton<ThemeMode>(
              tooltip: '主題',
              initialValue: widget.themeMode,
              onSelected: widget.onThemeChanged,
              itemBuilder: (_) => const [
                PopupMenuItem(value: ThemeMode.system, child: Text('跟隨系統')),
                PopupMenuItem(value: ThemeMode.light, child: Text('淺色')),
                PopupMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
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
            : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                controller: _pageScroll,
                padding: EdgeInsets.all(selectingPtus ? 12 : 20),
                children: [
                  if (demo)
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: colors.secondaryContainer,
                      child: const Text('模擬模式 · 不會設定真實設備或驗證正式資料'),
                    ),
                  // Round 29: the done page starts with its summary.
                  if (done) _doneSummary(state, controller, demo, env),
                  if (!done)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '目前模式：${topology.label}',
                        key: const Key('topology-banner'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (!selectingPtus && !done) ...[
                    const SizedBox(height: 20),
                    Text(
                      '讓每一台裝置，都確實上線。',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '依照步驟完成網路、裝置配置與資料驗證。',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (!done) ...[
                    LinearProgressIndicator(
                      value: shown / (stepLabels.length - 1),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${shown + 1} / ${stepLabels.length}   ${stepLabels[shown]}',
                      key: const Key('step-title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (!selectingPtus && !done) StepList(current: shown),
                  SizedBox(height: selectingPtus ? 4 : 16),
                  // Round 26: 「站 80 · 閘道器 2 · MAC 後 4 碼 70F2 · 1.7.36」
                  // (field: two gateways read 「GIOS-S80-G…」).
                  if (state.peer != null && !done)
                    Text(
                      gatewayHeaderText(
                        name: state.peer!.name,
                        id: state.peer!.id,
                        config: state.config,
                      ),
                      key: const Key('gateway-header'),
                    ),
                  if (state.peer != null && !done)
                    GatewaySignal(
                      link: ref.watch(linkProvider),
                      peer: state.peer!,
                      busy: state.busy,
                    ),
                  if (state.peer != null &&
                      state.step >= 2 &&
                      !directPicking &&
                      !done)
                    state.config['identify_supported'] == true
                        ? OutlinedButton.icon(
                            onPressed: state.busy
                                ? null
                                : ref
                                      .read(commissionProvider.notifier)
                                      .identify,
                            icon: const Icon(Icons.lightbulb_outline),
                            label: Text(
                              identifyPtuSupported(state.config)
                                  ? '辨識此樁（PTU 與閘道器閃燈）'
                                  : '辨識這台・雙閃 6 秒',
                              key: const Key('identify-label'),
                            ),
                          )
                        : const Text('連線時藍燈呼吸；更新韌體後可使用雙閃辨識。'),
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
                  if (state.message.isNotEmpty &&
                      !done &&
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
                                      style: TextStyle(
                                        color: colors.onErrorContainer,
                                      ),
                                    ),
                                    children: [
                                      SelectableText(
                                        state.errorDetail!,
                                        style: TextStyle(
                                          color: colors.onErrorContainer,
                                          fontSize: 12,
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
                  if (state.busy)
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
                  if (state.peer != null && state.step >= 2)
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
                        '尚未登入${env.label}：站號衝突檢查會先略過，之後需要時會請你輸入密碼。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  // Round 29: the done page's other actions are secondary,
                  // below the summary and the 連線狀態 line (no card).
                  if (done)
                    ...content(state, controller, demo)
                  else
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(selectingPtus ? 8 : 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: content(state, controller, demo),
                        ),
                      ),
                    ),
                  // After step 3 it asks first (field round 17: a late tap
                  // ended the flow). Round 19: at direct step 7 it is the
                  // bottom bar's last row instead ([DirectPickActions]),
                  // where the card above can no longer move it.
                  // Round 29: not on the done page (〔完成〕／〔配置下一台〕).
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
                          : () => _endFlow(controller),
                      child: Text(state.busy ? '取消操作' : endFlowLabel),
                    ),
                  if (state.step == 0)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('使用模擬設備練習'),
                      subtitle: const Text('不需要連接閘道器'),
                      value: demo,
                      onChanged: state.busy
                          ? null
                          : (value) =>
                                ref.read(demoProvider.notifier).set(value),
                    ),
                  // Practice the network check: the simulated gateway's
                  // Wi-Fi after it boots.
                  if (state.step == 0 && demo)
                    DropdownButtonFormField<String>(
                      key: const Key('demo-wifi'),
                      initialValue: ref.read(demoSystemProvider).wifiState,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '模擬 Gateway 的 Wi-Fi',
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

  /// Round 28: the system 返回 while a gateway is connected or a step runs
  /// ([PopScope] refused to leave): 「結束目前配置？」 — 結束 ends the run
  /// ([CommissioningController.cancel], as 「結束並重新選擇閘道器」 /
  /// 「取消操作」), 繼續配置 stays. Never leaves the APP.
  ///
  /// Round 29: on the done page 返回 is 〔完成〕 — the run is finished,
  /// nothing to ask (while an action there runs: a note to wait).
  bool _backAsking = false;
  Future<void> _backPressed(CommissioningController c) async {
    final s = ref.read(commissionProvider);
    // The start page (checking Bluetooth / the login) has nothing to end.
    if (_backAsking || s.step == 0 || (s.step <= 1 && !s.busy)) return;
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
  /// backend (star auto-reset, step 9 verify); cancel continues manually.
  ///
  /// Round 17: the session token saved by the last login is used first;
  /// the password is asked only without one (the local test host keeps
  /// its known password prefilled, and renews a refused token with it).
  Future<void> _resumeSaved(CommissioningController c) async {
    if (c.savedResumeNeedsLogin) {
      final env = ref.read(backendEnvProvider);
      final restored = await c.restoreSession(
        env.base,
        fallbackPassword: env.environment == BackendEnv.local
            ? _login.text
            : null,
      );
      if (!mounted) return;
      if (restored) {
        await c.resumeSaved();
        return;
      }
      final password = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('resume-login'),
          title: const Text('登入後端'),
          content: field(_login, '${env.label}的登入密碼', secret: true),
          actions: [
            TextButton(
              key: const Key('resume-login-cancel'),
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('resume-login-ok'),
              onPressed: () => Navigator.pop(context, _login.text),
              child: const Text('登入'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (password == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(resumeWithoutLoginText)));
      } else {
        await c.login(env.base, password);
        if (!mounted) return;
        if (!ref.read(commissionProvider).loggedIn) return;
        _afterLogin();
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
    switch (s.step) {
      case 0:
        return [
          ..._savedResume(s, c, enabled),
          const Text('先確認現場 WiFi 路由器與裝置電源已開啟。'),
          const SizedBox(height: 20),
          DropdownButtonFormField<BackendEnv>(
            key: ValueKey(environment),
            initialValue: environment,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '連線環境',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final value in [
                BackendEnv.production,
                BackendEnv.local,
                BackendEnv.custom,
              ])
                DropdownMenuItem(value: value, child: Text(envLabel(value))),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) _applyEnvironment(value);
                  }
                : null,
          ),
          const SizedBox(height: 12),
          if (environment == BackendEnv.local)
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
              child: Text(env.base),
            ),
          if (environment == BackendEnv.local)
            const Text(
              '本地測試密碼：$localTestPassword。手機與電腦需連同一個 Wi-Fi；電腦 IP 若變更，可在上方修改或按「自動尋找」。',
            )
          else if (environment == BackendEnv.production)
            const Text('請輸入 VPS 網頁的登入密碼。正式網址目前仍待部署確認。'),
          field(_login, '後端登入密碼', secret: true),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _offline,
            title: const Text('先離線配置，稍後驗證資料'),
            onChanged: enabled
                ? (v) => setState(() => _offline = v ?? false)
                : null,
          ),
          button('檢查並開始', () async {
            _flushBase();
            final current = ref.read(backendEnvProvider);
            if (current.environment == BackendEnv.local) {
              final error = localHostError(current.localHost);
              if (error != null) {
                _snack(error);
                return;
              }
            }
            await c.prepare(current.base, _login.text, offline: _offline);
            _afterLogin();
          }, enabled),
        ];
      case 1:
        return [
          ..._savedResume(s, c, enabled),
          GatewayDiscovery(
            enabled: enabled,
            // 「辨識」：連上這台（保持連線進入流程）後立即送 identify。
            onIdentify: (peer) async {
              await _connectPeer(c, peer);
              final next = ref.read(commissionProvider);
              if (mounted &&
                  next.error == null &&
                  next.peer != null &&
                  next.step >= 2) {
                await c.identify();
              }
            },
            onConnect: (peer) => _connectPeer(c, peer),
          ),
        ];
      case 2:
        final check = networkCheck(state: s, env: env);
        if (!s.checkPassed) return _networkCheck(s, c, check, enabled);
        if (s.config['choose_station'] == true) {
          final reason = check.reuseBlockedReason;
          return [
            Text(
              '目前站點：${s.config['site_id']}\n閘道器編號：${s.config['gateway_id']}',
            ),
            const SizedBox(height: 12),
            Text(
              '目前設定的 Wi-Fi：${(s.config['wifi_ssid']?.toString() ?? '').isEmpty ? '尚未設定' : s.config['wifi_ssid']}',
            ),
            const SizedBox(height: 12),
            _markedText(
              reason == null
                  ? const CheckLine(
                      '✓',
                      '網路體檢通過：Gateway 能上網，資料上傳中。',
                      StatusTone.ok,
                    )
                  : CheckLine('⚠', '網路體檢未通過：$reason。', StatusTone.warn),
              key: const Key('station-check'),
            ),
            const SizedBox(height: 12),
            const Text(
              '沿用會保留站點與 Wi-Fi，再由 Gateway 搜尋 PTU 供你確認；設定新站點與 Wi-Fi 可一起修改站號及無線網路。原站歷史資料不會刪除。',
            ),
            button(
              '沿用目前站點',
              () => c.chooseStation(newStation: false),
              enabled && reason == null,
            ),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  // Round 26: test mode / a paused upload have their own
                  // button in the card above, not a Wi-Fi reset.
                  check.testMode
                      ? '要沿用目前站點，請先按上方「$leaveTestModeLabel」（目前：$reason）。'
                      : check.uploadPaused && check.wifiOk && check.targetOk
                      ? '要沿用目前站點，請先按上方「$resumeUploadLabel」（目前：$reason）。'
                      : '要沿用目前站點，Gateway 必須先連上 Wi-Fi 並開始上傳資料（目前：$reason）。'
                            '請用「保留站點，重設 Wi-Fi」，或按「回到網路體檢」。',
                  key: const Key('reuse-blocked'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            button('保留站點，重設 Wi-Fi', () {
              c.chooseStation(newStation: false, wifiOnly: true);
              _site.text = '${s.config['site_id']}';
              _gateway.text = '${s.config['gateway_id']}';
              _ssid.text = s.config['wifi_ssid']?.toString() ?? '';
              _wifi.clear();
              _customWifi = false;
            }, enabled),
            button('設定新站點與 Wi-Fi', () {
              c.chooseStation(newStation: true);
              _gateway.text = '1';
              // Round 29: after 〔配置下一台〕 the station just done is
              // proposed (its next free gateway number).
              final kept = c.keptSite;
              if (kept != null) {
                _site.text = '$kept';
                _scheduleGatewaySuggestion();
              } else {
                _site.clear();
              }
              _wifi.clear();
            }, enabled),
            TextButton(
              onPressed: enabled ? c.backToNetworkCheck : null,
              child: const Text('回到網路體檢'),
            ),
          ];
        }
        // Round 30 (user rehearsal 09-27, C): the Wi-Fi the gateway is
        // already on (MQTT up) is kept — no password, no set_wifi.
        final keptSsid = keptWifiSsid(s);
        final keepingWifi =
            keptSsid != null && !_customWifi && _ssid.text == keptSsid;
        return [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Gateway 只能用 2.4 GHz 的 Wi-Fi，5 GHz 的網路連不上。'),
          ),
          if (s.config['wifi_only'] == true)
            Text(
              '保留站點 ${s.config['site_id']}／閘道器 ${s.config['gateway_id']}，只更新 Wi-Fi。',
            )
          else ...[
            field(
              _site,
              '站點 ID（1–65535）',
              number: true,
              onChanged: (_) => _scheduleGatewaySuggestion(),
            ),
            _gatewayAssignment(),
          ],
          const SizedBox(height: 16),
          if (keepingWifi) ...[
            _markedText(
              CheckLine('✓', wifiKeptText(keptSsid), StatusTone.ok),
              key: const Key('wifi-keep'),
            ),
            const SizedBox(height: 4),
            Text(
              '不必輸入 Wi-Fi 密碼，閘道器不會斷線重連。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('wifi-change'),
                icon: const Icon(Icons.wifi_find, size: 20),
                onPressed: enabled && !_scanningWifi ? _chooseWifi : null,
                label: Text(_scanningWifi ? '掃描中…' : '改用其他 Wi-Fi'),
              ),
            ),
            button(
              '儲存站點，沿用此 Wi-Fi',
              () => _saveWifi(false),
              enabled && !_gatewaySubmitBlocked,
            ),
            TextButton(
              onPressed: enabled ? c.backToNetworkCheck : null,
              child: const Text('返回網路體檢'),
            ),
          ] else ...[
            Text(
              '目前 Wi-Fi：${(s.config['wifi_ssid']?.toString() ?? '').isEmpty ? '尚未設定' : s.config['wifi_ssid']}',
            ),
            const SizedBox(height: 16),
            const Text('要連接的 Wi-Fi'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.wifi),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _customWifi
                        ? '自訂網路'
                        : _ssid.text.isEmpty
                        ? '尚未選擇'
                        : _ssid.text,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: enabled && !_scanningWifi ? _chooseWifi : null,
                  child: Text(_scanningWifi ? '掃描中…' : '更換'),
                ),
              ],
            ),
            if (_customWifi) field(_ssid, '自訂 Wi-Fi 名稱'),
            const SizedBox(height: 16),
            field(_wifi, 'Wi-Fi 密碼', secret: true),
            button(
              '儲存並連接 WiFi',
              () => _saveWifi(s.config['wifi_only'] == true),
              enabled &&
                  (s.config['wifi_only'] == true || !_gatewaySubmitBlocked),
            ),
            TextButton(
              onPressed: enabled ? c.backToNetworkCheck : null,
              child: const Text('返回網路體檢'),
            ),
          ],
        ];
      case 3:
        final check = networkCheck(state: s, env: env);
        return [
          const Icon(Icons.cloud_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('確認閘道器不只連上 WiFi，後端也持續收到心跳。'),
          const SizedBox(height: 8),
          Text('Gateway 自己回報：${check.upload.line}'),
          if (!s.loggedIn) ...[
            const SizedBox(height: 12),
            field(_login, '若要確認後端，請輸入${env.label}的登入密碼', secret: true),
          ],
          // Round 30: 「下一步：確認上線」 is in the bottom bar ([_checkNext]).
          const SizedBox(height: 8),
          Text(
            '請按下方「$confirmOnlineLabel」。',
            key: const Key('online-next-hint'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
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
        ];
      case 4:
      case 5:
        // Round 15: direct flow step 7 shows the gateway's own pick only.
        final directStep7 = c.directFlow && s.step == 4;
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
                    : '由 Gateway 重新掃描 PTU',
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
          if (s.ptus.length > 1 && !directStep7)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('ptu-resort'),
                icon: const Icon(Icons.sort, size: 18),
                onPressed: enabled ? c.sortPtusBySignal : null,
                label: const Text('依訊號重新排序'),
              ),
            ),
          if (!directStep7)
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
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '掃描說明與完整流程',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            children: [
              Text(
                '由 Gateway 掃描附近的 PTU，再透過藍牙把清單傳回手機。'
                '${c.directFlow
                    ? "直連模式：由閘道器自己選最近的 PTU（門檻內最強，或已綁定的那台），這裡只顯示它的選擇；請用「辨識此樁」確認是眼前這台，不是的話按「不是這台？」改選。"
                    : topology.isDirect
                    ? "直連模式：已自動選定訊號最強的一台。"
                    : "最多可選 ${ref.read(topologyProvider).starCount} 台。"}'
                'RSSI 是 Gateway 與 PTU 之間的訊號；未連線裝置顯示掃描值。「上次」表示暫停或過期，「快取」表示韌體未提供讀值時間。韌體 1.7.5 起可在配置期間量測；RSSI — 表示尚無有效讀值。',
              ),
              StepList(current: displayStep(s, env)),
            ],
          ),
        ];
      case 6:
        return [
          const Text('逐台檢查資料時間、落後秒數與錯誤碼。連續三次通過後才判定完成。'),
          const SizedBox(height: 16),
          if (environment == BackendEnv.custom)
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
          if (!s.loggedIn) field(_login, '若尚未登入，請輸入登入密碼', secret: true),
          // Round 8: listed in scan order (#1, #2, #4, #3); by number now.
          ...byDeviceNumber(s.ptus).map((ptu) {
            final id = (ptu['device_number'] as num?)?.toInt() ?? 0;
            final count = s.verifyCounts[id];
            return ListTile(
              key: Key('verify-ptu-$id'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sensors),
              title: Text('PTU #$id'),
              subtitle: Text(ptu['mac'].toString()),
              trailing: count == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.verifySkipped.contains(id)
                              ? '未驗證（已略過）'
                              : s.verifyWaiting.contains(id)
                              ? '尚無資料'
                              : '$count/3',
                          key: Key('verify-count-$id'),
                        ),
                        if (s.verifyWaiting.contains(id) &&
                            !s.verifySkipped.contains(id))
                          TextButton(
                            key: Key('verify-skip-$id'),
                            onPressed: () => c.skipVerifyPtu(id),
                            child: const Text('略過此台'),
                          ),
                      ],
                    ),
            );
          }),
          TextButton(
            key: const Key('verify-back'),
            // Keeps the selection and what was assigned; no cancel.
            onPressed: c.backToSelection,
            child: const Text('返回選擇 PTU'),
          ),
          TextButton(
            onPressed: enabled ? c.rescanPtus : null,
            child: const Text('返回選擇 PTU，由 Gateway 重新掃描'),
          ),
          button(
            '開始資料驗證',
            _startVerify,
            enabled && s.ptus.any((p) => s.selected.contains(p['mac'])),
          ),
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
            field(_login, '${env.label}的登入密碼', secret: true),
            OutlinedButton(
              key: const Key('done-login'),
              onPressed: enabled
                  ? () async {
                      if (!_passwordReady(demo)) return;
                      await c.login(
                        ref.read(backendEnvProvider).base,
                        _login.text,
                      );
                      if (mounted && ref.read(commissionProvider).loggedIn) {
                        _afterLogin();
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
                      } else if (_passwordReady(demo)) {
                        await c.repair(
                          base: ref.read(backendEnvProvider).base,
                          password: _login.text,
                        );
                        if (mounted && ref.read(commissionProvider).loggedIn) {
                          _afterLogin();
                        }
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
            line(
              gatewayIdText(c.site, c.gateway),
              key: const Key('done-gateway'),
              strong: true,
            ),
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
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('done-next'),
                  onPressed: enabled ? () => _finishDone(c, next: true) : null,
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
      title: Text(s.report.startsWith('模擬') ? '模擬安裝報告' : '安裝報告'),
      subtitle: const Text('可分享或複製給後台'),
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

  /// Step 7 without a login: the password field must be filled in first.
  bool _passwordReady(bool demo) {
    if (demo || _login.text.isNotEmpty) return true;
    _snack('請先輸入${ref.read(backendEnvProvider).label}的登入密碼。');
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
      return (
        confirmOnlineLabel,
        () => c.online(
          base: env.base,
          environment: env.environment.name,
          password: _login.text,
        ),
      );
    }
    if (s.step != 2 || s.checkPassed) return null;
    if (!networkCheck(state: s, env: env).ready) return null;
    // Round 26: after a Wi-Fi reset the station is chosen again.
    final label = s.config['wifi_only'] == true
        ? '下一步：確認站點'
        : s.config['fleet_joined'] == true
        ? '下一步：選擇站點'
        : '下一步：設定身份與 Wi-Fi';
    return (label, () => c.passNetworkCheck());
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
      Text(
        recheck ? '確認資料上傳' : 'Gateway 網路體檢',
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        recheck
            ? 'Wi-Fi 已更新。等 Gateway 開始上傳資料，再確認站點（沿用或設定新站點）。'
            : '先確認 Gateway 能上網、資料送對地方，再選擇站點。',
        style: muted,
      ),
      item('Gateway 的 Wi-Fi', check.wifi, 'check-wifi'),
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
              '按下後會先讓 Gateway 改送到${placeOf(check.syncTarget!)}'
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
              child: Text(
                '讓 Gateway 改送到${placeOf(check.syncTarget!)}（重新開機約 1 分鐘）',
              ),
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
      // A new gateway with no Wi-Fi gets the identity/Wi-Fi form from the
      // button above; skipping would lead to the same form.
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
              : '⚠ Gateway 的網路還沒確認好。設定完新站點後會再確認資料上傳，'
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
