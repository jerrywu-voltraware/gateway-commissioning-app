import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/local_backend_finder.dart';
import '../core/local_backend_address.dart';
import '../data/local_backend_probe.dart';
import '../l10n/l10n.dart';

/// Keeps only digits and dots; a decimal comma (some keyboards) becomes a dot.
class Ipv4InputFormatter extends TextInputFormatter {
  static String _clean(String s) =>
      s.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    final text = _clean(raw);
    if (text.length > 15) return oldValue;
    if (text == raw) return newValue;
    final end = newValue.selection.end;
    final cursor = end < 0 || end > raw.length ? raw.length : end;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: _clean(raw.substring(0, cursor)).length,
      ),
    );
  }
}

/// Full backend URL input that wraps instead of truncating long URLs.
class BackendUrlField extends StatelessWidget {
  const BackendUrlField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.url,
      minLines: 1,
      maxLines: 3,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      decoration: InputDecoration(labelText: label),
    ),
  );
}

/// 本地測試站: the user types only the PC's IPv4; `http://` and the port are
/// fixed. Offers 自動尋找 (scan the phone's /24) and 測試連線 (GET /healthz).
class LocalBackendField extends ConsumerStatefulWidget {
  const LocalBackendField({
    super.key,
    required this.hostController,
    required this.port,
    required this.onPortChanged,
    required this.onHostPicked,
    this.enabled = true,
  });
  final TextEditingController hostController;
  final int port;
  final ValueChanged<int> onPortChanged;

  /// Called after 自動尋找 filled in a host, so the page can persist it.
  final VoidCallback onHostPicked;
  final bool enabled;
  @override
  ConsumerState<LocalBackendField> createState() => _LocalBackendFieldState();
}

class _LocalBackendFieldState extends ConsumerState<LocalBackendField> {
  ScanCancel? _cancel;
  bool _testing = false;
  String? _progressHost;
  int _done = 0, _total = 0;
  String? _status;
  bool _statusOk = false;

  bool get _scanning => _cancel != null;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  void _setStatus(String? text, {bool ok = false}) => setState(() {
    _status = text;
    _statusOk = ok;
  });

  void _fill(FoundBackend found) {
    widget.hostController.text = found.host;
    widget.onHostPicked();
    _setStatus(
      found.healthy
          ? L10n.current.localBackendField_foundFilled(found.host)
          : L10n.current.localBackendField_filledNotReady(found.host),
      ok: found.healthy,
    );
  }

  Future<void> _autoFind() async {
    FocusScope.of(context).unfocus();
    final cancel = ScanCancel();
    setState(() {
      _cancel = cancel;
      _status = null;
      _progressHost = null;
      _done = 0;
      _total = 0;
    });
    try {
      final ownIp = await ref.read(phoneIpv4Provider)();
      if (!mounted || cancel.cancelled) return;
      if (ownIp == null) {
        _setStatus(L10n.current.localBackendField_noPhoneIp);
        return;
      }
      final hosts = subnetHosts(ownIp);
      final subnet = '${ownIp.substring(0, ownIp.lastIndexOf('.'))}.x';
      final result =
          await LocalBackendFinder(ref.read(localBackendProberProvider)).find(
            hosts,
            port: widget.port,
            cancel: cancel,
            onProgress: (host, done, total) {
              if (mounted && !cancel.cancelled) {
                setState(() {
                  _progressHost = host;
                  _done = done;
                  _total = total;
                });
              }
            },
          );
      if (!mounted || result.cancelled) return;
      final found = result.found;
      if (found.isEmpty) {
        final l10n = L10n.current;
        final port = '${widget.port}';
        final notFound = result.timedOut
            ? l10n.localBackendField_notFoundTimedOut(subnet, port)
            : l10n.localBackendField_notFound(subnet, port);
        _setStatus('$notFound\n$localBackendHint');
      } else if (found.length == 1) {
        _fill(found.single);
      } else {
        final picked = await showDialog<FoundBackend>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(
              context.l10n.localBackendField_foundCount(found.length),
            ),
            children: [
              for (final f in found)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, f),
                  child: ListTile(
                    leading: const Icon(Icons.computer_outlined),
                    title: Text(f.host),
                    subtitle: Text(
                      f.healthy
                          ? context.l10n.localBackendField_version(
                              f.result.version ?? '—',
                            )
                          : context.l10n.localBackendField_dbNotReady,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.common_cancel),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (picked == null) {
          _setStatus(
            L10n.current.localBackendField_foundNotChosen(found.length),
          );
        } else {
          _fill(picked);
        }
      }
    } finally {
      if (mounted && identical(_cancel, cancel)) {
        setState(() => _cancel = null);
      }
    }
  }

  void _stopScan() {
    _cancel?.cancel();
    setState(() => _cancel = null);
    _setStatus(L10n.current.localBackendField_scanCancelled);
  }

  Future<void> _test() async {
    final host = widget.hostController.text.trim();
    final error = localHostError(host);
    if (error != null) {
      _setStatus(error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _status = null;
    });
    final base = Uri.parse(composeLocalUrl(host, widget.port));
    ProbeResult result;
    try {
      result = await ref.read(localBackendProberProvider).probe(base);
    } catch (error) {
      result = ProbeResult(ProbeOutcome.unreachable, detail: '$error');
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _status = connectionTestMessage(result, base);
      _statusOk = result.outcome == ProbeOutcome.healthy;
    });
  }

  Future<void> _editPort() async {
    final port = await showDialog<int>(
      context: context,
      builder: (context) => _PortDialog(port: widget.port),
    );
    if (port != null && port != widget.port) {
      widget.onPortChanged(port);
      _setStatus(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final idle = widget.enabled && !_scanning && !_testing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.hostController,
            builder: (context, value, _) {
              final host = value.text.trim();
              final error = host.isEmpty ? null : localHostError(host);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('local-backend-host'),
                    controller: widget.hostController,
                    enabled: widget.enabled && !_scanning,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [Ipv4InputFormatter()],
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) {
                      if (_status != null) _setStatus(null);
                    },
                    // r31: no `http://` prefix / `:port` suffix inside the
                    // field — on a narrow phone they squeezed the IP to
                    // 「http://192.168.0.:18000」; the full URL is the line
                    // below (「將連線：…」).
                    decoration: InputDecoration(
                      labelText: l10n.localBackendField_ipLabel,
                      hintText: '192.168.1.187',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ).copyWith(errorText: error, errorMaxLines: 3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    host.isEmpty || error != null
                        ? l10n.localBackendField_willConnectNone
                        : l10n.localBackendField_willConnect(
                            composeLocalUrl(host, widget.port),
                          ),
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: idle ? _autoFind : null,
                icon: const Icon(Icons.travel_explore),
                label: Text(l10n.localBackendField_autoFind),
              ),
              OutlinedButton.icon(
                onPressed: idle ? _test : null,
                icon: const Icon(Icons.network_check),
                label: Text(
                  _testing
                      ? l10n.localBackendField_testing
                      : l10n.localBackendField_testConnection,
                ),
              ),
              TextButton(
                onPressed: idle ? _editPort : null,
                child: Text(
                  l10n.localBackendField_advancedPort('${widget.port}'),
                ),
              ),
            ],
          ),
          if (_scanning) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _progressHost == null
                        ? l10n.localBackendField_gettingSubnet
                        : l10n.localBackendField_searching(
                            _progressHost!,
                            _done,
                            _total,
                          ),
                  ),
                ),
                TextButton(
                  onPressed: _stopScan,
                  child: Text(l10n.common_cancel),
                ),
              ],
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(
              _status!,
              style: TextStyle(
                color: _statusOk ? colors.primary : colors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PortDialog extends StatefulWidget {
  const _PortDialog({required this.port});
  final int port;
  @override
  State<_PortDialog> createState() => _PortDialogState();
}

class _PortDialogState extends State<_PortDialog> {
  late final _controller = TextEditingController(text: '${widget.port}');
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = localPortError(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, int.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.localBackendField_portDialogTitle),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: context.l10n.localBackendField_portLabel,
        helperText: context.l10n.localBackendField_portDefault(
          '$defaultLocalPort',
        ),
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => _controller.text = '$defaultLocalPort',
        child: Text(context.l10n.localBackendField_restoreDefault),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.common_cancel),
      ),
      FilledButton(onPressed: _submit, child: Text(context.l10n.common_ok)),
    ],
  );
}
