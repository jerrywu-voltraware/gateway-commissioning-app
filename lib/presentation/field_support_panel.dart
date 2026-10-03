import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../application/field_report.dart' show originOf;
import '../core/protocol.dart';
import '../data/contracts.dart';

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
        _error = '請先連線到目前選擇的後台，再查看協助回覆。';
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
            _error = '暫時無法取得後台回覆；以下若有內容是上次收到的，請重新整理或電話聯絡。';
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
      if (_current) setState(() => _error = '尚未確認回覆結果，請重新整理；若指引更新，請看完後再回覆。');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _data?['state'];
    final label = switch (state) {
      'pending' => '等待後台接手',
      'handling' => '後台已接手，處理中',
      'waiting_field' => '後台已提供指引，請操作後回覆',
      'resolved' => '你已確認解決',
      _ => _unavailable ? '請電話聯絡後台協助' : '正在取得協助狀態…',
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
            if (_unavailable) const Text('目前無法在 APP 查看文字回覆，請將下方設備與步驟資訊告知後台。'),
            if (instruction != null) ...[
              const SizedBox(height: 8),
              Text(
                '後台指引 · 當時第 ${instruction['step']} 步${time == null ? '' : ' · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'}',
              ),
              if (target?['gateway_mac'] != null)
                Text(
                  '指引對象：站 ${target?['site_id'] ?? '?'} / 閘道器 ${target?['gateway_id'] ?? '?'} · MAC ${target?['gateway_mac']}',
                ),
              const SizedBox(height: 4),
              SelectableText(
                instruction['message'] as String? ?? '',
                key: const Key('field-support-instruction'),
              ),
              const Text('請先核對目前畫面與設備，再依指引操作。'),
            ],
            if (differentGateway) ...[
              const Text('這是其他閘道器的協助紀錄，請勿照做；請更新求助資訊，讓後台確認目前設備。'),
              TextButton(
                onPressed: widget.onRequestAgain,
                child: const Text('更新求助資訊'),
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
                child: Text(_sending ? '回覆中…' : '已解決'),
              ),
              TextButton(
                onPressed:
                    _sending || _reading || _error != null || differentGateway
                    ? null
                    : () => _confirm('still_help'),
                child: const Text('仍需協助'),
              ),
            ],
            if (state == 'resolved')
              TextButton(
                onPressed: widget.onRequestAgain,
                child: const Text('再次求助'),
              ),
            TextButton(
              onPressed: _sending || _reading
                  ? null
                  : () => _refresh(retryUnavailable: true),
              child: const Text('重新整理回覆'),
            ),
            if (!_unavailable)
              const Text(
                '關閉後可點頂部「請後台協助」再次查看回覆。',
                style: TextStyle(fontSize: 13),
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
