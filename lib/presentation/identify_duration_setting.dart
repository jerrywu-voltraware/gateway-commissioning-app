import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/commissioning_controller.dart';
import '../application/topology_settings.dart';
import '../core/identify.dart';
import '../l10n/l10n.dart';

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
        final l10n = context.l10n;
        setState(
          () => _notice = seconds == 0
              ? l10n.identifyDurationSetting_savedOff
              : l10n.identifyDurationSetting_saved(seconds),
        );
      }
    } catch (_) {
      if (mounted) {
        final failed = context.l10n.identifyDurationSetting_saveFailed;
        setState(() => _notice = failed);
      }
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
    final l10n = context.l10n;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.identifyDurationSetting_title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('identify-seconds-input'),
            controller: _seconds,
            enabled: enabled,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.identifyDurationSetting_fieldLabel,
              suffixText: l10n.identifyDurationSetting_suffix,
            ),
            validator: (value) => parseIdentifySeconds(value ?? '') == null
                ? identifySecondsError
                : null,
          ),
          const SizedBox(height: 8),
          Text(l10n.identifyDurationSetting_help),
          TextButton(
            key: const Key('identify-seconds-save'),
            onPressed: enabled ? _save : null,
            child: Text(
              _saving
                  ? l10n.identifyDurationSetting_saving
                  : l10n.identifyDurationSetting_save,
            ),
          ),
          if (_notice != null)
            Text(_notice!, key: const Key('identify-seconds-notice')),
        ],
      ),
    );
  }
}
