import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/field_report.dart' show originOf;
import '../core/protocol.dart';
import '../data/contracts.dart';
import '../l10n/l10n.dart';

bool supportOriginMatches(GatewayApi api, String base) {
  if (api is! SessionInfo) return true;
  final session = api as SessionInfo;
  return session.hasSession && originOf(session.origin) == originOf(base);
}

/// Poll only while the help sheet is visible and the application is foreground.
class FieldSupportPanel extends ConsumerStatefulWidget {
  const FieldSupportPanel({
    super.key,
    required this.sessionId,
    required this.onRequestAgain,
    this.currentGatewayMac,
  });
  final String sessionId;
  final VoidCallback onRequestAgain;
  final String? currentGatewayMac;

  @override
  ConsumerState<FieldSupportPanel> createState() => _FieldSupportPanelState();
}

class _FieldSupportPanelState extends ConsumerState<FieldSupportPanel>
    with WidgetsBindingObserver {
  Timer? _timer;
  Map<String, dynamic>? _data;
  String? _error;
  bool _unavailable = false;
  bool _reading = false, _sending = false, _foreground = true;
  late final GatewayApi _api;
  late final String _origin;
  String get _path => '/api/field/sessions/${widget.sessionId}/support';
  bool get _current => mounted && ref.read(backendEnvProvider).base == _origin;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiProvider);
    _origin = ref.read(backendEnvProvider).base;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool retryUnavailable = false}) async {
    if (!_current || !_foreground || _reading || _sending) return;
    if (_unavailable && !retryUnavailable) return;
    if (!supportOriginMatches(_api, _origin)) {
      setState(() {
        _data = null;
        _error = L10n.current.fieldSupportPanel_notConnected;
      });
      return;
    }
    setState(() => _reading = true);
    try {
      final value = await _api
          .request('GET', _path)
          .timeout(const Duration(seconds: 10));
      if (!_current || !supportOriginMatches(_api, _origin)) return;
      if (value['state'] is! String || value['revision'] is! int) {
        throw const FormatException('Support response unavailable');
      }
      setState(() {
        _data = value;
        _error = null;
        _unavailable = false;
      });
    } catch (error) {
      if (_current) {
        setState(() {
          if (error is GatewayFailure && error.status == 404) {
            _data = null;
            _error = null;
            _unavailable = true;
          } else {
            _error = L10n.current.fieldSupportPanel_fetchFailed;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _confirm(String action) async {
    if (!_current || _sending || _reading || _data == null || _error != null) {
      return;
    }
    if (!supportOriginMatches(_api, _origin)) {
      await _refresh();
      return;
    }
    if (_differentGateway) return;
    final revision = _data!['revision'];
    setState(() => _sending = true);
    try {
      final value = await _api
          .request('POST', '$_path/confirm', {
            'expected_revision': revision,
            'action': action,
          })
          .timeout(const Duration(seconds: 10));
      if (_current && supportOriginMatches(_api, _origin)) {
        setState(() {
          _data = value;
          _error = null;
        });
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = L10n.current.fieldSupportPanel_confirmFailed);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = _data?['state'];
    final label = switch (state) {
      'pending' => l10n.fieldSupportPanel_statePending,
      'handling' => l10n.fieldSupportPanel_stateHandling,
      'waiting_field' => l10n.fieldSupportPanel_stateWaitingField,
      'resolved' => l10n.fieldSupportPanel_stateResolved,
      _ =>
        _unavailable
            ? l10n.fieldSupportPanel_stateCallSupport
            : l10n.fieldSupportPanel_stateLoading,
    };
    final events = (_data?['events'] as List? ?? const []).whereType<Map>();
    final requestedAt = _data?['request_at'] as String? ?? '';
    final instructions = events
        .where(
          (event) =>
              event['action'] == 'instruct' &&
              (event['at'] as String? ?? '').compareTo(requestedAt) >= 0,
        )
        .toList();
    final instruction = instructions.isEmpty ? null : instructions.last;
    final target = instruction?['context'] as Map?;
    final differentGateway = _differentGateway;
    final time = DateTime.tryParse(
      instruction?['at'] as String? ?? '',
    )?.toLocal();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              key: const Key('field-support-state'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_unavailable) Text(l10n.fieldSupportPanel_unavailable),
            if (instruction != null) ...[
              const SizedBox(height: 8),
              Text(
                time == null
                    ? l10n.fieldSupportPanel_instructionHeader(
                        '${instruction['step']}',
                      )
                    : l10n.fieldSupportPanel_instructionHeaderAt(
                        '${instruction['step']}',
                        '${time.hour.toString().padLeft(2, '0')}:'
                            '${time.minute.toString().padLeft(2, '0')}',
                      ),
              ),
              if (target?['gateway_mac'] != null)
                Text(
                  l10n.fieldSupportPanel_instructionTarget(
                    '${target?['site_id'] ?? '?'}',
                    '${target?['gateway_id'] ?? '?'}',
                    '${target?['gateway_mac']}',
                  ),
                ),
              const SizedBox(height: 4),
              SelectableText(
                instruction['message'] as String? ?? '',
                key: const Key('field-support-instruction'),
              ),
              Text(l10n.fieldSupportPanel_checkFirst),
            ],
            if (differentGateway) ...[
              Text(l10n.fieldSupportPanel_otherGateway),
              TextButton(
                onPressed: widget.onRequestAgain,
                child: Text(l10n.fieldSupportPanel_updateRequest),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                key: const Key('field-support-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (state == 'handling' || state == 'waiting_field') ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed:
                    _sending || _reading || _error != null || differentGateway
                    ? null
                    : () => _confirm('resolved'),
                child: Text(
                  _sending
                      ? l10n.fieldSupportPanel_replying
                      : l10n.fieldSupportPanel_resolved,
                ),
              ),
              TextButton(
                onPressed:
                    _sending || _reading || _error != null || differentGateway
                    ? null
                    : () => _confirm('still_help'),
                child: Text(l10n.fieldSupportPanel_stillHelp),
              ),
            ],
            if (state == 'resolved')
              TextButton(
                onPressed: widget.onRequestAgain,
                child: Text(l10n.fieldSupportPanel_askAgain),
              ),
            TextButton(
              onPressed: _sending || _reading
                  ? null
                  : () => _refresh(retryUnavailable: true),
              child: Text(l10n.fieldSupportPanel_refresh),
            ),
            if (!_unavailable)
              Text(
                l10n.fieldSupportPanel_reopenHint,
                style: const TextStyle(fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  bool get _differentGateway {
    final events = (_data?['events'] as List? ?? const []).whereType<Map>();
    final backend = events
        .where((e) => e['role'] == 'backend' || e['action'] == 'instruct')
        .lastOrNull;
    final context = backend?['context'] as Map?;
    final target = context?['gateway_mac'] as String?;
    if (target == null) return false;
    String normalized(String? value) =>
        (value ?? '').replaceAll(RegExp('[^a-fA-F0-9]'), '').toUpperCase();
    return normalized(target) != normalized(widget.currentGatewayMac);
  }
}
