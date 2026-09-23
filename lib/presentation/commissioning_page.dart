import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/connection_status.dart';
import '../core/local_backend_address.dart';
import '../core/mqtt_target.dart';
import '../data/wifi_scan.dart';
import 'connection_status_panel.dart';
import 'environment_switch.dart';
import 'local_backend_field.dart';

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
  /// Mirrors the selected backend URL (editable only for 其他網址); the
  /// source of truth is [backendEnvProvider].
  final _base = TextEditingController(text: productionApiBase);
  final _login = TextEditingController(),
      _ssid = TextEditingController(),
      _wifi = TextEditingController();
  final _site = TextEditingController(text: '1'),
      _gateway = TextEditingController(text: '1');
  bool _offline = false;

  /// Local mode: the user edits only the PC's IPv4; mirrors the provider.
  final _host = TextEditingController();

  BackendEnvController get _envController =>
      ref.read(backendEnvProvider.notifier);

  /// Keeps the text fields in step with the shared environment state.
  void _onEnvironment(BackendEnvState? previous, BackendEnvState next) {
    if (_host.text != next.localHost) _host.text = next.localHost;
    if (_base.text != next.base) _base.text = next.base;
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
    if (mounted) setState(() {});
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
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
    if (ref.read(commissionProvider).busy) {
      _snack('正在進行其他操作，完成或按「取消操作」後才能切換環境。');
      return;
    }
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
        await ref.read(commissionProvider.notifier).switchUploadTarget(target);
    }
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

  static const labels = [
    '準備',
    '找到閘道器',
    '身份與 WiFi',
    '確認上線',
    '選擇 PTU',
    '開始監控',
    '驗證資料',
    '完成',
  ];
  @override
  void initState() {
    super.initState();
    ref.listenManual(backendEnvProvider, _onEnvironment, fireImmediately: true);
    _host.addListener(() => _envController.setLocalHost(_host.text));
    _base.addListener(() {
      if (ref.read(backendEnvProvider).environment == BackendEnv.custom) {
        _envController.setCustomUrl(_base.text);
      }
    });
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
    ),
  );
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commissionProvider),
        controller = ref.read(commissionProvider.notifier);
    final demo = ref.watch(demoProvider),
        colors = Theme.of(context).colorScheme;
    final env = ref.watch(backendEnvProvider);
    return PopScope(
      canPop: !state.busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GIOS 現場開通'),
          actions: [
            EnvironmentChip(onPressed: _openEnvironmentSheet),
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
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (demo)
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: colors.secondaryContainer,
                      child: const Text('模擬模式 · 不會設定真實設備或驗證正式資料'),
                    ),
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
                  LinearProgressIndicator(value: state.step / 7),
                  const SizedBox(height: 12),
                  Text(
                    '${state.step + 1} / 8   ${labels[state.step]}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (state.peer != null)
                    Text(
                      '${state.peer!.name} · ${state.config['fw_version'] ?? ''}',
                    ),
                  if (state.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(state.message),
                    ),
                  if (state.error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: colors.errorContainer,
                      child: Text(
                        state.error!,
                        style: TextStyle(color: colors.onErrorContainer),
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
                      // Shipping: phone and gateway both go to 正式站.
                      onShipSwitch: () => _applyEnvironment(
                        BackendEnv.production,
                        fromSheet: true,
                      ),
                    ),
                  if (state.step >= 1 && state.step <= 2 && !state.loggedIn)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '尚未登入${env.label}：站號衝突檢查會先略過，第 3 步會請你輸入密碼。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: content(state, controller, demo),
                      ),
                    ),
                  ),
                  if (state.step > 0)
                    TextButton(
                      onPressed: () => controller.cancel(),
                      child: Text(state.busy ? '取消操作' : '結束並重新選擇閘道器'),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> content(
    CommissionState s,
    CommissioningController c,
    bool demo,
  ) {
    final enabled = !s.busy;
    final env = ref.read(backendEnvProvider);
    final environment = env.environment;
    switch (s.step) {
      case 0:
        return [
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
            final current = ref.read(backendEnvProvider);
            if (current.environment == BackendEnv.local) {
              final error = localHostError(current.localHost);
              if (error != null) {
                _snack(error);
                return;
              }
            }
            await c.prepare(current.base, _login.text, offline: _offline);
            _login.clear();
          }, enabled),
        ];
      case 1:
        return [
          button(s.peers.isEmpty ? '搜尋閘道器' : '重新搜尋', () => c.scan(), enabled),
          ...s.peers.map(
            (peer) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.router_outlined),
              title: Text(peer.name),
              subtitle: Text('${peer.id}\n訊號 ${peer.rssi} dBm'),
              trailing: const Icon(Icons.chevron_right),
              onTap: enabled
                  ? () async {
                      await c.connect(peer);
                      if (mounted) {
                        final next = ref.read(commissionProvider);
                        _site.text =
                            '${next.config['suggested_site_id'] ?? next.config['site_id'] ?? 1}';
                        _gateway.text =
                            '${next.config['suggested_gateway_id'] ?? next.config['gateway_id'] ?? 1}';
                        _ssid.text = next.config['wifi_ssid']?.toString() ?? '';
                        _customWifi = false;
                        // Remembered environment: sync the gateway to it.
                        if (next.error == null && next.step >= 2) {
                          await _syncGateway(explicit: false);
                        }
                      }
                    }
                  : null,
            ),
          ),
        ];
      case 2:
        if (s.config['choose_station'] == true) {
          return [
            Text(
              '目前站點：${s.config['site_id']}\n閘道器編號：${s.config['gateway_id']}',
            ),
            const SizedBox(height: 12),
            Text(
              '目前設定的 Wi-Fi：${(s.config['wifi_ssid']?.toString() ?? '').isEmpty ? '尚未設定' : s.config['wifi_ssid']}',
            ),
            const SizedBox(height: 12),
            const Text(
              '沿用會保留目前設定；設定新站點與 Wi-Fi 可一起修改站號及無線網路，儲存後重新開通。原站歷史資料不會刪除。',
            ),
            button('沿用目前站點', () => c.chooseStation(newStation: false), enabled),
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
              _site.clear();
              _gateway.text = '1';
              _wifi.clear();
            }, enabled),
          ];
        }
        return [
          if (s.config['wifi_only'] == true)
            Text(
              '保留站點 ${s.config['site_id']}／閘道器 ${s.config['gateway_id']}，只更新 Wi-Fi。',
            )
          else ...[
            field(_site, '站點 ID（1–65535）', number: true),
            field(_gateway, '閘道器編號（1–6）', number: true),
          ],
          const SizedBox(height: 16),
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
          button('儲存並連接 WiFi', () async {
            await c.configureWifi(
              int.tryParse(_site.text) ?? 0,
              int.tryParse(_gateway.text) ?? 0,
              _ssid.text,
              _wifi.text,
            );
            _wifi.clear();
          }, enabled),
        ];
      case 3:
        return [
          const Icon(Icons.cloud_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('確認閘道器不只連上 WiFi，後端也持續收到心跳。'),
          if (!s.loggedIn) ...[
            const SizedBox(height: 12),
            field(_login, '若要確認後端，請輸入${env.label}的登入密碼', secret: true),
          ],
          button(
            '確認上線',
            () => c.online(
              base: env.base,
              environment: environment.name,
              password: _login.text,
            ),
            enabled,
          ),
          TextButton(
            onPressed: enabled ? () => c.online(skip: true) : null,
            child: const Text('暫未確認，先配置 PTU'),
          ),
        ];
      case 4:
      case 5:
        return [
          const Text('勾選要由這台閘道器監控的 PTU，最多五台。'),
          button('搜尋周邊與已連線 PTU', () => c.discover(), enabled),
          Text(
            '已連線 ${s.ptus.where((p) => p['connected'] == true).length} 台／周邊未連線 ${s.ptus.where((p) => p['connected'] != true).length} 台',
          ),
          ...s.ptus.map(
            (ptu) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: s.selected.contains(ptu['mac']),
              title: Text(ptu['mac'].toString()),
              subtitle: Text(
                '${ptu['connected'] == true ? '已連線至此 Gateway' : '周邊未連線'}\n目前編號 ${ptu['device_number'] ?? 0} · 訊號 ${ptu['rssi'] ?? '—'} dBm\n${s.results[ptu['mac']] ?? ''}',
              ),
              onChanged: enabled
                  ? (value) => c.select(ptu['mac'].toString(), value ?? false)
                  : null,
            ),
          ),
          if (s.missing.isNotEmpty) Text('尚未連線：${s.missing.join('、')}'),
          button(
            '配置 ${s.selected.length} 台並開始監控',
            () => c.configurePtus(),
            enabled && s.selected.isNotEmpty,
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
              child: Text('驗證後端：${env.label}（${env.base}）'),
            ),
          if (!s.loggedIn) field(_login, '若尚未登入，請輸入登入密碼', secret: true),
          ...s.ptus.map(
            (ptu) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sensors),
              title: Text('PTU #${ptu['device_number']}'),
              subtitle: Text(ptu['mac'].toString()),
            ),
          ),
          button('開始資料驗證', () async {
            final current = ref.read(backendEnvProvider);
            await c.verify(
              current.base,
              _login.text,
              environment: current.environment.name,
            );
            _login.clear();
          }, enabled),
        ];
      default:
        return [
          Icon(
            s.online ? Icons.check_circle_outline : Icons.cloud_off,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            demo ? '模擬開通完成' : '開通完成',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          SelectableText(s.report),
          button('分享安裝報告', () async {
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
          }, enabled),
          button('複製安裝報告', () async {
            await Clipboard.setData(ClipboardData(text: s.report));
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已複製，可貼上分享')));
            }
          }, enabled),
          TextButton(
            onPressed: enabled ? () => c.refreshHealth() : null,
            child: const Text('更新健康狀態'),
          ),
          TextButton(
            onPressed: enabled ? () => c.repair() : null,
            child: const Text('重新連線並驗證'),
          ),
        ];
    }
  }
}
