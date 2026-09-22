import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../application/commissioning_controller.dart';
import '../data/wifi_scan.dart';

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
  final _base = TextEditingController(
    text: const String.fromEnvironment(
      'API_BASE',
      defaultValue: 'https://dashboard.voltraware.com',
    ),
  );
  final _login = TextEditingController(),
      _ssid = TextEditingController(),
      _wifi = TextEditingController();
  final _site = TextEditingController(text: '1'),
      _gateway = TextEditingController(text: '1');
  bool _offline = false;
  String _environment = 'production';
  static const _productionUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://dashboard.voltraware.com',
  );
  static const _localUrl = String.fromEnvironment(
    'LOCAL_API_BASE',
    defaultValue: 'http://192.168.0.12:18000',
  );
  Future<void> _restoreEnvironment() async {
    final prefs = await SharedPreferences.getInstance();
    final oldLocal = Uri.tryParse(prefs.getString('backend_local_url') ?? '');
    if (oldLocal != null &&
        ['127.0.0.1', 'localhost', '10.0.2.2'].contains(oldLocal.host)) {
      await prefs.setString('backend_local_url', _localUrl);
    }
    if (!mounted) return;
    final saved = prefs.getString('backend_environment');
    setState(() {
      _environment = ['production', 'local', 'custom'].contains(saved)
          ? saved!
          : 'production';
      _base.text = _environment == 'local'
          ? (prefs.getString('backend_local_url') ?? _localUrl)
          : _environment == 'custom'
          ? (prefs.getString('backend_custom_url') ?? '')
          : _productionUrl;
    });
  }

  Future<void> _selectEnvironment(String? value) async {
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (_environment == 'local') {
      await prefs.setString('backend_local_url', _base.text.trim());
    }
    if (_environment == 'custom') {
      await prefs.setString('backend_custom_url', _base.text.trim());
    }
    if (!mounted) return;
    setState(() {
      _environment = value;
      _base.text = value == 'local'
          ? (prefs.getString('backend_local_url') ?? _localUrl)
          : value == 'custom'
          ? (prefs.getString('backend_custom_url') ?? '')
          : _productionUrl;
      _login.clear();
    });
    await prefs.setString('backend_environment', value);
  }

  bool _scanningWifi = false;
  bool _customWifi = false;
  Future<void> _chooseWifi() async {
    FocusScope.of(context).unfocus();
    setState(() => _scanningWifi = true);
    try {
      final networks = await scanWifiNetworks();
      if (!mounted || ref.read(commissionProvider).step != 2) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('選擇 2.4 GHz Wi-Fi'),
          children: [
            if (networks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('未找到周邊 2.4 GHz Wi-Fi。請靠近路由器重掃，或手動輸入名稱。'),
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
          _customWifi = false;
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
    _restoreEnvironment();
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
    for (final c in [_base, _login, _ssid, _wifi, _site, _gateway]) {
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
    return PopScope(
      canPop: !state.busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GIOS 現場開通'),
          actions: [
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
    switch (s.step) {
      case 0:
        return [
          const Text('先確認現場 WiFi 路由器與裝置電源已開啟。'),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: ValueKey(_environment),
            initialValue: _environment,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '連線環境',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'production', child: Text('VPS 正式站')),
              DropdownMenuItem(value: 'local', child: Text('本地測試站')),
              DropdownMenuItem(value: 'custom', child: Text('其他網址')),
            ],
            onChanged: enabled ? _selectEnvironment : null,
          ),
          const SizedBox(height: 12),
          if (_environment == 'custom' || _environment == 'local')
            field(_base, '後端網址')
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_base.text),
            ),
          if (_environment == 'local')
            const Text('本地測試密碼：54974211。手機與電腦需連同一個區域網路；電腦網址若變更，可在上方修改。')
          else if (_environment == 'production')
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
            if (_environment == 'local') {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('backend_local_url', _base.text.trim());
              if (!mounted) return;
            }
            if (_environment == 'custom') {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('backend_custom_url', _base.text.trim());
              if (!mounted) return;
            }
            await c.prepare(_base.text.trim(), _login.text, offline: _offline);
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
            const Text('沿用會保留目前設定；設定新站會在儲存後變更這台閘道器的站點並重新開通。原站歷史資料不會刪除。'),
            button('沿用目前站點', () => c.chooseStation(newStation: false), enabled),
            button('設定新站點', () {
              c.chooseStation(newStation: true);
              _site.clear();
              _gateway.text = '1';
              _wifi.clear();
            }, enabled),
          ];
        }
        return [
          field(_site, '站點 ID（1–65535）', number: true),
          field(_gateway, '閘道器編號（1–6）', number: true),
          DropdownButtonFormField<bool>(
            key: ValueKey('wifi-source-$_customWifi'),
            initialValue: _customWifi,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi 設定方式',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: false, child: Text('掃描選擇 Wi-Fi')),
              DropdownMenuItem(value: true, child: Text('自訂 Wi-Fi')),
            ],
            onChanged: enabled && !_scanningWifi
                ? (value) {
                    FocusScope.of(context).unfocus();
                    setState(() => _customWifi = value ?? false);
                  }
                : null,
          ),
          const SizedBox(height: 14),
          if (_customWifi)
            field(_ssid, '自訂 Wi-Fi 名稱')
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wifi),
              title: Text(_ssid.text.isEmpty ? '尚未選擇 Wi-Fi' : _ssid.text),
              subtitle: const Text('按下方掃描按鈕選擇網路'),
            ),
          if (!_customWifi)
            OutlinedButton.icon(
              onPressed: enabled && !_scanningWifi ? _chooseWifi : null,
              icon: const Icon(Icons.wifi_find),
              label: Text(_scanningWifi ? '正在掃描…' : '掃描周邊 Wi-Fi'),
            ),
          Text(
            _customWifi
                ? '請輸入完整的 Wi-Fi 名稱，包含大小寫與空白。'
                : '使用手機掃描 2.4 GHz Wi-Fi；隱藏網路請選「自訂 Wi-Fi」。',
          ),
          field(_wifi, 'WiFi 密碼（8–63 bytes）', secret: true),
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
          button('確認上線', () => c.online(), enabled),
          TextButton(
            onPressed: enabled ? () => c.online(skip: true) : null,
            child: const Text('暫未確認，先配置 PTU'),
          ),
        ];
      case 4:
      case 5:
        return [
          const Text('勾選要由這台閘道器監控的 PTU，最多五台。'),
          button('搜尋 PTU', () => c.discover(), enabled),
          ...s.ptus.map(
            (ptu) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: s.selected.contains(ptu['mac']),
              title: Text(ptu['mac'].toString()),
              subtitle: Text(
                '目前編號 ${ptu['device_number'] ?? 0} · 訊號 ${ptu['rssi'] ?? '—'} dBm\n${s.results[ptu['mac']] ?? ''}',
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
          field(_base, '後端網址'),
          field(_login, '若尚未登入，請輸入登入密碼', secret: true),
          ...s.ptus.map(
            (ptu) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sensors),
              title: Text('PTU #${ptu['device_number']}'),
              subtitle: Text(ptu['mac'].toString()),
            ),
          ),
          button('開始資料驗證', () async {
            await c.verify(_base.text, _login.text);
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
