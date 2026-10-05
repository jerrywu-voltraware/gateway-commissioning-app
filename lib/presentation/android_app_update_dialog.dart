import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/android_app_update.dart';
import '../data/android_app_update.dart';
import '../l10n/l10n.dart';

class AndroidAppUpdateDialog extends ConsumerStatefulWidget {
  const AndroidAppUpdateDialog({
    super.key,
    required this.check,
    required this.isHomeSafe,
  });
  final AndroidUpdateCheck check;
  final bool Function() isHomeSafe;

  @override
  ConsumerState<AndroidAppUpdateDialog> createState() =>
      _AndroidAppUpdateDialogState();
}

class _AndroidAppUpdateDialogState extends ConsumerState<AndroidAppUpdateDialog>
    with WidgetsBindingObserver {
  UpdateCancellation? _cancellation;
  File? _file;
  bool _busy = false, _installerOpened = false;
  int _received = 0;
  String? _message;
  bool _error = false;
  late final AndroidUpdatePlatform _platform;

  @override
  void initState() {
    super.initState();
    _platform = ref.read(androidUpdateServiceProvider).platform;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _platform.cancelInstall();
    WidgetsBinding.instance.removeObserver(this);
    // The package installer may still be reading the verified file.
    super.dispose();
  }

  Future<void> _update() async {
    if (_busy || !widget.isHomeSafe()) return;
    final release = widget.check.release!;
    final service = ref.read(androidUpdateServiceProvider);
    final cancellation = UpdateCancellation();
    _cancellation = cancellation;
    setState(() {
      _busy = true;
      _message = null;
      _error = false;
    });
    try {
      _file ??= await service.download(release, cancellation, (received) {
        if (!mounted || !widget.isHomeSafe()) {
          cancellation.cancel();
          return;
        }
        setState(() => _received = received);
      });
      if (!mounted || !widget.isHomeSafe()) return;
      cancellation.check();
      final outcome = await service.platform.install(release, _file!);
      if (!mounted) return;
      if (outcome == 'permission_required') {
        setState(
          () =>
              _message = L10n.current.androidAppUpdateDialog_permissionRequired,
        );
      } else if (outcome == 'opened') {
        setState(() {
          _installerOpened = true;
          _message = L10n.current.androidAppUpdateDialog_installerOpened;
        });
      } else {
        throw const AppUpdateException('install');
      }
    } catch (error) {
      if (!mounted || cancellation.cancelled) return;
      setState(() {
        _error = true;
        if (error is PlatformException) {
          final l10n = L10n.current;
          _message = switch (error.code) {
            'update_verification_failed' =>
              l10n.androidAppUpdateDialog_verificationFailed,
            'update_install_failed' =>
              l10n.androidAppUpdateDialog_installFailed,
            'update_prepare_failed' =>
              l10n.androidAppUpdateDialog_prepareFailed,
            _ => l10n.androidAppUpdateDialog_startFailed,
          };
        } else {
          _message = error is AppUpdateException && error.code == 'integrity'
              ? L10n.current.androidAppUpdateDialog_integrityFailed
              : L10n.current.androidAppUpdateDialog_downloadFailed;
        }
        _file = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.check.release!;
    final l10n = context.l10n;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cancellation?.cancel();
      },
      child: AlertDialog(
        key: const Key('android-app-update-dialog'),
        title: Text(l10n.androidAppUpdateDialog_title),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.androidAppUpdateDialog_currentVersion(
                    widget.check.installed.versionName,
                    '${widget.check.installed.versionCode}',
                  ),
                ),
                Text(
                  l10n.androidAppUpdateDialog_latestVersion(
                    release.versionName,
                    '${release.versionCode}',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  release.notes.isEmpty
                      ? l10n.androidAppUpdateDialog_defaultNotes
                      : release.notes,
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _received / release.sizeBytes),
                  const SizedBox(height: 8),
                  Text(
                    _received == release.sizeBytes
                        ? l10n.androidAppUpdateDialog_verifying
                        : l10n.androidAppUpdateDialog_downloading(
                            (100 * _received / release.sizeBytes).floor(),
                          ),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _error
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _cancellation?.cancel();
              Navigator.pop(context);
            },
            child: Text(
              _busy
                  ? l10n.androidAppUpdateDialog_cancelDownload
                  : (_installerOpened
                        ? l10n.common_close
                        : l10n.common_later),
            ),
          ),
          FilledButton(
            key: const Key('android-app-update-install'),
            onPressed: _busy || !widget.isHomeSafe() ? null : _update,
            child: Text(
              _file != null
                  ? l10n.androidAppUpdateDialog_continueInstall
                  : (_error
                        ? l10n.androidAppUpdateDialog_redownload
                        : l10n.androidAppUpdateDialog_updateNow),
            ),
          ),
        ],
      ),
    );
  }
}
