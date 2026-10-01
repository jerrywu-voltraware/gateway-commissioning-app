import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/commissioning_controller.dart';
import '../application/topology_settings.dart';
import '../core/identify.dart';

/// Inline in the existing connection settings dialog; no second settings page.
class IdentifyDurationSetting extends ConsumerStatefulWidget {
  const IdentifyDurationSetting({super.key});
  @override
  ConsumerState<IdentifyDurationSetting> createState() =>
      _IdentifyDurationState();
}

class _IdentifyDurationState extends ConsumerState<IdentifyDurationSetting> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _seconds;
  bool _saving = false;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _seconds = TextEditingController(
      text: '${ref.read(topologyProvider).identifySeconds}',
    );
  }

  @override
  void dispose() {
    _seconds.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || ref.read(commissionProvider).busy) {
      return;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final seconds = parseIdentifySeconds(_seconds.text)!;
      await ref.read(topologyProvider.notifier).setIdentifySeconds(seconds);
      if (mounted) {
        setState(
          () => _notice = seconds == 0 ? '已儲存：0 秒（關閉辨識燈）' : '已儲存：$seconds 秒',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _notice = '無法儲存，請重試');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(topologyProvider);
    final enabled =
        settings.loaded && !ref.watch(commissionProvider).busy && !_saving;
    ref.listen(topologyProvider, (before, after) {
      if (before?.loaded == false && after.loaded) {
        _seconds.text = '${after.identifySeconds}';
      }
    });
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('辨識秒數', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('identify-seconds-input'),
            controller: _seconds,
            enabled: enabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '秒數（0–255）',
              suffixText: '秒',
            ),
            validator: (value) => parseIdentifySeconds(value ?? '') == null
                ? identifySecondsError
                : null,
          ),
          const SizedBox(height: 8),
          const Text('預設 6 秒。閘道器與 PTU 使用相同秒數。0＝關燈；閘道器會停止辨識並恢復正常狀態燈。'),
          TextButton(
            key: const Key('identify-seconds-save'),
            onPressed: enabled ? _save : null,
            child: Text(_saving ? '儲存中…' : '儲存秒數'),
          ),
          if (_notice != null)
            Text(_notice!, key: const Key('identify-seconds-notice')),
        ],
      ),
    );
  }
}
