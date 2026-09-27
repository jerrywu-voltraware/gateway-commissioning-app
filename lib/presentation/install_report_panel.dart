/// 09-28: the done page line of the install report sent to the back office
/// (「報告已送到後台 hh:mm」／「排隊中，網路恢復後自動送」／ failed with
/// 〔重送〕). The report itself and 〔分享安裝報告〕 stay in the report tile
/// below it (secondary).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/field_report.dart';
import '../application/install_report.dart';

/// 〔重送〕 of a queued / failed install report.
const installReportResendLabel = '重送';

class InstallReportStatusLine extends ConsumerStatefulWidget {
  const InstallReportStatusLine({super.key, this.enabled = true});

  /// The page is not busy.
  final bool enabled;

  @override
  ConsumerState<InstallReportStatusLine> createState() =>
      _InstallReportStatusLineState();
}

class _InstallReportStatusLineState
    extends ConsumerState<InstallReportStatusLine> {
  bool _resending = false;

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);
    try {
      await ref.read(fieldReporterProvider).resendInstallReport();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(installReportProvider);
    if (status.phase == InstallReportPhase.idle) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (status.phase) {
      InstallReportPhase.sent => (Icons.cloud_done, Colors.green.shade700),
      InstallReportPhase.sending => (Icons.cloud_upload, colors.primary),
      InstallReportPhase.queued => (
        Icons.schedule_send,
        Colors.orange.shade800,
      ),
      InstallReportPhase.failed => (Icons.cloud_off, colors.error),
      _ => (Icons.info_outline, colors.onSurfaceVariant),
    };
    return Padding(
      key: const Key('install-report-status'),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              installReportStatusText(status),
              key: const Key('install-report-status-text'),
              style: TextStyle(color: color),
            ),
          ),
          if (status.canResend)
            TextButton.icon(
              key: const Key('install-report-resend'),
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: widget.enabled && !_resending ? _resend : null,
              label: const Text(installReportResendLabel),
            ),
        ],
      ),
    );
  }
}
