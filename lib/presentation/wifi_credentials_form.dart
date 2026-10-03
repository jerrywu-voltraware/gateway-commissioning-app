import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/wifi_scan.dart';
import '../data/wifi_password_store.dart';
import 'next_action_guide.dart';

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
    this.passwordStore = const SecureWifiPasswordStore(),
    this.onStorageError,
  });

  final TextEditingController ssid;
  final TextEditingController password;
  final bool enabled;
  final bool canSave;

  /// True only when this submission's password was used and verified.
  final Future<bool> Function() onSave;
  final VoidCallback onNetworkEdited;
  final String saveLabel;
  final WifiPasswordStore passwordStore;
  final VoidCallback? onStorageError;

  @override
  State<WifiCredentialsForm> createState() => _WifiCredentialsFormState();
}

class _WifiCredentialsFormState extends State<WifiCredentialsForm>
    with WidgetsBindingObserver {
  // Forgetting in a newer form also invalidates an older submission that has
  // not reached storage yet. The store orders writes already in its queue.
  static final _forgetEpochBySsid = <String, int>{};
  bool _reading = false;
  bool _showPassword = false;
  bool _rememberPassword = true;
  bool _hasStoredPassword = false;
  bool _saving = false;
  bool _forgetting = false;
  String? _passwordMessage;
  String _selectedSsid = '';
  int _passwordRequest = 0;
  Timer? _passwordReadTimer;
  int _passwordRevision = 0;
  bool _manual = false;
  bool _showSettings = false;
  String? _message;
  int _request = 0;

  bool _accepts(int request) =>
      mounted && widget.enabled && request == _request;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedSsid = widget.ssid.text;
    widget.ssid.addListener(_ssidChanged);
    widget.password.addListener(_passwordChanged);
    unawaited(_loadPassword());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordReadTimer?.cancel();
    widget.ssid.removeListener(_ssidChanged);
    widget.password.removeListener(_passwordChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _showPassword) {
      setState(() => _showPassword = false);
    }
  }

  @override
  void didUpdateWidget(WifiCredentialsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _request++;
      _reading = false;
      _showPassword = false;
      _passwordRequest++;
      _passwordReadTimer?.cancel();
    }
    if (widget.password != oldWidget.password ||
        widget.ssid != oldWidget.ssid) {
      oldWidget.ssid.removeListener(_ssidChanged);
      oldWidget.password.removeListener(_passwordChanged);
      widget.ssid.addListener(_ssidChanged);
      widget.password.addListener(_passwordChanged);
      _selectedSsid = widget.ssid.text;
      _hasStoredPassword = false;
      _passwordMessage = null;
      _passwordRequest++;
      _showPassword = false;
      unawaited(_loadPassword());
    } else if (widget.enabled && !oldWidget.enabled && !_saving) {
      unawaited(_loadPassword());
    }
  }

  void _passwordChanged() => _passwordRevision++;

  void _ssidChanged() {
    if (widget.ssid.text == _selectedSsid) return;
    _selectedSsid = widget.ssid.text;
    widget.password.clear();
    setState(() {
      _showPassword = false;
      _hasStoredPassword = false;
      _passwordMessage = null;
    });
    unawaited(_loadPassword());
  }

  Future<void> _loadPassword() async {
    _passwordReadTimer?.cancel();
    final request = ++_passwordRequest;
    final ssid = widget.ssid.text;
    final revision = _passwordRevision;
    if (!widget.enabled || _saving || _forgetting || ssid.isEmpty) return;
    bool current() =>
        mounted &&
        widget.enabled &&
        !_saving &&
        !_forgetting &&
        request == _passwordRequest &&
        widget.ssid.text == ssid;
    final timer = Timer(const Duration(seconds: 3), () {
      if (!current()) return;
      _passwordRequest++;
      setState(() => _passwordMessage = '讀取已存密碼逾時，請手動輸入。');
    });
    _passwordReadTimer = timer;
    try {
      final saved = await widget.passwordStore.read(ssid);
      if (!current()) return;
      setState(() {
        _hasStoredPassword = saved != null;
        if (saved != null &&
            _rememberPassword &&
            widget.password.text.isEmpty &&
            revision == _passwordRevision) {
          widget.password.text = saved;
          _showPassword = false;
          _passwordMessage = '已帶入這支手機記住的密碼，可按眼睛查看或手動修改。';
        }
      });
    } catch (_) {
      if (!current()) return;
      setState(() => _passwordMessage = '暫時無法讀取已存密碼，請手動輸入。');
    } finally {
      timer.cancel();
      if (identical(_passwordReadTimer, timer)) _passwordReadTimer = null;
    }
  }

  Future<void> _forgetPassword({required bool clearInput}) async {
    if (_forgetting || _saving || !widget.enabled) return;
    final ssid = widget.ssid.text;
    _passwordRequest++;
    _passwordReadTimer?.cancel();
    _forgetEpochBySsid[ssid] = (_forgetEpochBySsid[ssid] ?? 0) + 1;
    setState(() {
      _forgetting = true;
      _showPassword = false;
      if (!clearInput) _rememberPassword = false;
    });
    try {
      if (ssid.isNotEmpty) await widget.passwordStore.delete(ssid);
      if (!mounted || widget.ssid.text != ssid) return;
      setState(() {
        _hasStoredPassword = false;
        _rememberPassword = clearInput;
        if (clearInput) widget.password.clear();
        _passwordMessage = '已忘記這個 Wi-Fi 的已存密碼。';
      });
    } catch (_) {
      if (mounted && widget.ssid.text == ssid) {
        setState(() {
          _passwordMessage = '舊密碼尚未刪除，請重試；本次不會記住新密碼。';
          _rememberPassword = false;
        });
      }
    } finally {
      if (mounted) setState(() => _forgetting = false);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _forgetting ||
        _reading ||
        !widget.enabled ||
        !widget.canSave) {
      return;
    }
    // The parent clears its controllers and can navigate away on success.
    // This submission owns its immutable snapshot until the verified result.
    final ssid = widget.ssid.text;
    final password = widget.password.text;
    final remember = _rememberPassword;
    final forgetEpoch = _forgetEpochBySsid[ssid] ?? 0;
    final store = widget.passwordStore;
    final onSave = widget.onSave;
    final onStorageError = widget.onStorageError;
    _passwordRequest++;
    _passwordReadTimer?.cancel();
    setState(() {
      _saving = true;
      _showPassword = false;
    });
    try {
      final verified = await onSave();
      if (verified &&
          remember &&
          ssid.isNotEmpty &&
          password.isNotEmpty &&
          (_forgetEpochBySsid[ssid] ?? 0) == forgetEpoch) {
        try {
          await store.write(ssid, password);
          if (mounted && widget.ssid.text == ssid) {
            setState(() => _hasStoredPassword = true);
          }
        } catch (_) {
          onStorageError?.call();
          if (mounted) {
            setState(() => _passwordMessage = 'Wi-Fi 已連線，但無法記住密碼；下次請重新輸入。');
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _passwordMessage = '連線尚未完成，未記住本次密碼。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _select(String ssid) {
    if (widget.ssid.text != ssid) {
      widget.password.clear();
      _showPassword = false;
    }
    widget.ssid.text = ssid;
    widget.onNetworkEdited();
  }

  Future<void> _usePhoneWifi() async {
    final request = ++_request;
    FocusScope.of(context).unfocus();
    setState(() {
      _reading = true;
      _showPassword = false;
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
          _message = '已帶入手機的 Wi-Fi 名稱，請確認此網路支援 2.4 GHz，並確認下方密碼。';
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.password,
      builder: (context, password, _) {
        final enabled = widget.enabled && !_reading && !_saving && !_forgetting;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('帶入手機目前的 Wi-Fi 名稱後，輸入密碼或使用已記住的密碼。'),
            const SizedBox(height: 8),
            NextActionGuide.button(
              active: !_manual && widget.ssid.text.isEmpty,
              hint: '帶入手機目前的 Wi-Fi',
              child: OutlinedButton.icon(
                key: const Key('wifi-use-phone'),
                onPressed: enabled ? _usePhoneWifi : null,
                icon: const Icon(Icons.wifi),
                label: Text(_reading ? '讀取中…' : '使用手機目前的 Wi-Fi'),
              ),
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
            Text(
              '閘道器要使用的 Wi-Fi',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (_manual)
              TextField(
                key: const Key('wifi-ssid'),
                controller: widget.ssid,
                enabled: enabled,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Wi-Fi 名稱（SSID）'),
                onChanged: (_) {
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
              ],
            ),
            const SizedBox(height: 8),
            NextActionGuide(
              active:
                  enabled &&
                  widget.ssid.text.isNotEmpty &&
                  password.text.isEmpty,
              hint: '輸入 Wi-Fi 密碼；無密碼的網路可直接儲存',
              child: TextField(
                key: const Key('wifi-password'),
                controller: widget.password,
                enabled: enabled,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Wi-Fi 密碼',
                  suffixIcon: IconButton(
                    key: const Key('wifi-password-visibility'),
                    tooltip: _showPassword ? '隱藏密碼' : '顯示密碼',
                    onPressed: enabled
                        ? () => setState(() => _showPassword = !_showPassword)
                        : null,
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              key: const Key('wifi-remember-password'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('記住密碼（僅限這支手機）'),
              value: _rememberPassword,
              onChanged: enabled
                  ? (value) {
                      if (value == true) {
                        setState(() => _rememberPassword = true);
                        unawaited(_loadPassword());
                      } else {
                        unawaited(_forgetPassword(clearInput: false));
                      }
                    }
                  : null,
            ),
            if (_passwordMessage != null)
              Text(_passwordMessage!, key: const Key('wifi-password-message')),
            if (_hasStoredPassword)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('wifi-forget-password'),
                  onPressed: enabled
                      ? () => _forgetPassword(clearInput: true)
                      : null,
                  child: const Text('忘記已存密碼'),
                ),
              ),
            const SizedBox(height: 22),
            if (enabled && _manual && widget.ssid.text.isEmpty)
              const NextActionHint('輸入 Wi-Fi 名稱'),
            NextActionGuide.button(
              active: widget.ssid.text.isNotEmpty && password.text.isNotEmpty,
              hint: '確認 Wi-Fi 名稱與密碼後，點「${widget.saveLabel}」',
              child: FilledButton(
                key: const Key('wifi-save'),
                onPressed: enabled && widget.canSave ? _save : null,
                child: Text(widget.saveLabel),
              ),
            ),
          ],
        );
      },
    );
  }
}
