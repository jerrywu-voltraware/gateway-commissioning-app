import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/wifi_scan.dart';

/// Phone Wi-Fi selection is local to this form: a result arriving after the
/// installer leaves, changes gateway, or starts saving cannot change the SSID.
class WifiCredentialsForm extends StatefulWidget {
  const WifiCredentialsForm({
    super.key,
    required this.ssid,
    required this.password,
    required this.enabled,
    required this.canSave,
    required this.onSave,
    required this.onNetworkEdited,
    required this.saveLabel,
  });

  final TextEditingController ssid;
  final TextEditingController password;
  final bool enabled;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onNetworkEdited;
  final String saveLabel;

  @override
  State<WifiCredentialsForm> createState() => _WifiCredentialsFormState();
}

class _WifiCredentialsFormState extends State<WifiCredentialsForm> {
  bool _reading = false;
  bool _scanning = false;
  bool _manual = false;
  bool _showSettings = false;
  String? _message;
  int _request = 0;

  bool get _busy => _reading || _scanning;
  bool _accepts(int request) =>
      mounted && widget.enabled && request == _request;

  @override
  void didUpdateWidget(WifiCredentialsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _request++;
      _reading = _scanning = false;
    }
  }

  void _select(String ssid) {
    if (widget.ssid.text != ssid) widget.password.clear();
    widget.ssid.text = ssid;
    widget.onNetworkEdited();
  }

  Future<void> _usePhoneWifi() async {
    final request = ++_request;
    FocusScope.of(context).unfocus();
    setState(() {
      _reading = true;
      _message = null;
      _showSettings = false;
    });
    try {
      final ssid = await readCurrentWifiSsid();
      if (!_accepts(request)) return;
      setState(() {
        if (ssid == null) {
          _message = '讀不到手機目前的 Wi-Fi。請先在手機的 Wi-Fi 設定連上現場網路，再回來重試，或手動輸入名稱。';
        } else {
          _select(ssid);
          _manual = false;
          _message = '已帶入手機的 Wi-Fi 名稱，請確認此網路支援 2.4 GHz，再輸入密碼。';
        }
      });
    } catch (error) {
      if (!_accepts(request)) return;
      final code = error is PlatformException ? error.code : '';
      setState(() {
        _showSettings = const {
          'permission',
          'permission_permanently_denied',
          'precise_location',
        }.contains(code);
        _message = switch (code) {
          'permission' ||
          'permission_permanently_denied' ||
          'precise_location' =>
            '讀取 Wi-Fi 名稱需要定位權限及精確位置。請在 App 設定允許後重試，也可手動輸入名稱。',
          'location_off' => '請開啟手機定位服務後重試，或手動輸入 Wi-Fi 名稱。',
          'wifi_off' => '請先在手機的 Wi-Fi 設定連上現場網路，再回來重試，或手動輸入名稱。',
          'unsupported' => '此平台無法讀取手機 Wi-Fi，請手動輸入名稱。',
          _ =>
            error is TimeoutException
                ? '讀取 Wi-Fi 逾時，請重試或手動輸入名稱。'
                : '暫時無法讀取 Wi-Fi 名稱，請重試或手動輸入。',
        };
      });
    } finally {
      if (_accepts(request)) setState(() => _reading = false);
    }
  }

  Future<void> _chooseWifi() async {
    final request = ++_request;
    FocusScope.of(context).unfocus();
    setState(() {
      _scanning = true;
      _message = null;
      _showSettings = false;
    });
    try {
      var networks = <WifiNetwork>[];
      String? scanMessage;
      try {
        networks = await scanWifiNetworks();
      } catch (error) {
        final code = error is PlatformException ? error.code : '';
        scanMessage = switch (code) {
          'permission' => '請允許精確位置權限後重試，或手動輸入網路名稱。',
          'wifi_off' => '請開啟手機 Wi-Fi 後重試，或手動輸入網路名稱。',
          'location_off' => '請開啟手機定位服務後重試，或手動輸入網路名稱。',
          'throttled' => '掃描太頻繁，請稍候重試，或手動輸入網路名稱。',
          _ => '掃描未完成，請重試或手動輸入網路名稱。',
        };
      }
      if (!mounted || !_accepts(request)) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('選擇 2.4 GHz Wi-Fi'),
          children: [
            if (networks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(scanMessage ?? '未找到周邊 2.4 GHz Wi-Fi，可稍後重試或手動輸入名稱。'),
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
      if (!_accepts(request) || selected == null) return;
      setState(() {
        _manual = selected.isEmpty;
        if (!_manual) _select(selected);
      });
    } finally {
      if (_accepts(request)) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('先讓手機連上現場要使用的 Wi-Fi，再帶入名稱。密碼需自行輸入。'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('wifi-use-phone'),
          onPressed: enabled ? _usePhoneWifi : null,
          icon: const Icon(Icons.wifi),
          label: Text(_reading ? '讀取中…' : '使用手機目前的 Wi-Fi'),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_message!, key: const Key('wifi-phone-message')),
          ),
        if (_showSettings)
          TextButton(
            onPressed: enabled ? openAppSettings : null,
            child: const Text('開啟 App 權限設定'),
          ),
        const SizedBox(height: 8),
        Text('閘道器要使用的 Wi-Fi', style: Theme.of(context).textTheme.labelMedium),
        if (_manual)
          TextField(
            key: const Key('wifi-ssid'),
            controller: widget.ssid,
            enabled: enabled,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Wi-Fi 名稱（SSID）'),
            onChanged: (_) {
              widget.password.clear();
              widget.onNetworkEdited();
            },
          )
        else
          Text(
            widget.ssid.text.isEmpty ? '尚未選擇 Wi-Fi' : widget.ssid.text,
            key: const Key('wifi-selected'),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: const Key('wifi-manual'),
              onPressed: enabled
                  ? () => setState(() {
                      _manual = true;
                      _message = null;
                      _showSettings = false;
                    })
                  : null,
              child: const Text('手動輸入其他網路'),
            ),
            if (canScanWifiNetworks)
              TextButton(
                key: const Key('wifi-pick'),
                onPressed: enabled ? _chooseWifi : null,
                child: Text(_scanning ? '掃描中…' : '選擇其他 Wi-Fi'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.password,
          enabled: enabled,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Wi-Fi 密碼'),
        ),
        const SizedBox(height: 22),
        FilledButton(
          key: const Key('wifi-save'),
          onPressed: enabled && widget.canSave ? widget.onSave : null,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
