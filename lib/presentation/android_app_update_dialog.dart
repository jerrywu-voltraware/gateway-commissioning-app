import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/android_app_update.dart';
import '../data/android_app_update.dart';

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
        setState(() => _message = '請允許安裝此來源的應用程式，返回後按「繼續安裝」。');
      } else if (outcome == 'opened') {
        setState(() {
          _installerOpened = true;
          _message = '請在系統畫面確認安裝。若已取消，可再按「繼續安裝」。';
        });
      } else {
        throw const AppUpdateException('install');
      }
    } catch (error) {
      if (!mounted || cancellation.cancelled) return;
      setState(() {
        _error = true;
        _message = error is AppUpdateException && error.code == 'integrity'
            ? '更新檔驗證失敗，請重新下載。'
            : '更新未完成，請確認網路或安裝權限後重試。';
        _file = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.check.release!;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cancellation?.cancel();
      },
      child: AlertDialog(
        key: const Key('android-app-update-dialog'),
        title: const Text('有新版 APP'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '目前版本：${widget.check.installed.versionName}（${widget.check.installed.versionCode}）',
                ),
                Text('最新版本：${release.versionName}（${release.versionCode}）'),
                const SizedBox(height: 16),
                Text(release.notes.isEmpty ? '改善 APP 使用體驗。' : release.notes),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _received / release.sizeBytes),
                  const SizedBox(height: 8),
                  Text(
                    _received == release.sizeBytes
                        ? '正在驗證更新檔…'
                        : '正在下載 ${(100 * _received / release.sizeBytes).floor()}%',
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
            child: Text(_busy ? '取消下載' : (_installerOpened ? '關閉' : '稍後')),
          ),
          FilledButton(
            key: const Key('android-app-update-install'),
            onPressed: _busy || !widget.isHomeSafe() ? null : _update,
            child: Text(_file != null ? '繼續安裝' : (_error ? '重新下載' : '立即更新')),
          ),
        ],
      ),
    );
  }
}
