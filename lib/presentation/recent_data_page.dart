import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/commissioning_controller.dart';
import '../application/field_report.dart';
import '../data/recent_data_api.dart';

/// Title of the page and of the done page's button.
const recentDataLabel = '查看最近資料';
String recentDataTitle(int site, int gateway) => '站 $site 閘道器 $gateway 最近資料';

/// `count` 0: the back office has nothing from this gateway yet.
const recentDataEmptyText = '後台尚未收到這台閘道器的資料，請稍等 20 秒再重新整理';
const recentDataRefreshLabel = '重新整理';
const recentDataRetryLabel = '重試';
const recentDataLoadingText = '正在向後台查詢…';

/// 09-28 〔查看最近資料〕 (one thing, one page): the last rows the back
/// office received from this gateway, through the APP's own session (no
/// dashboard login, no key typed). No polling: 〔重新整理〕 at the top
/// right, 〔重試〕 on an error.
class RecentDataPage extends ConsumerStatefulWidget {
  const RecentDataPage({
    super.key,
    required this.site,
    required this.gateway,
    this.now,
  });

  final int site, gateway;

  /// Clock for the 「N 秒前」 summary; tests inject one.
  final DateTime Function()? now;

  /// Opens the page for [site]/[gateway].
  static Future<void> open(BuildContext context, int site, int gateway) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecentDataPage(site: site, gateway: gateway),
        ),
      );

  @override
  ConsumerState<RecentDataPage> createState() => _RecentDataPageState();
}

class _RecentDataPageState extends ConsumerState<RecentDataPage> {
  RecentData? _data;
  Object? _error;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // Field rescue: tell the back office the installer is checking the
    // data (skipped once the session ended on the done page).
    ref.read(fieldReporterProvider).noteRecentDataViewed();
    _load();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    RecentData? data;
    Object? error;
    try {
      data = await fetchRecentData(
        ref.read(apiProvider),
        site: widget.site,
        gateway: widget.gateway,
      );
    } catch (e) {
      error = e;
    }
    if (!mounted || gen != _generation) return;
    setState(() {
      _loading = false;
      if (error != null) {
        _error = error;
      } else {
        _data = data;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(recentDataTitle(widget.site, widget.gateway)),
        actions: [
          IconButton(
            key: const Key('recent-refresh'),
            tooltip: recentDataRefreshLabel,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _body(theme, colors),
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, ColorScheme colors) {
    final error = _error;
    final data = _data;
    if (_loading && data == null && error == null) {
      return const Center(
        key: Key('recent-loading'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(recentDataLoadingText),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        key: const Key('recent-error'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.cloud_off, size: 40, color: colors.error),
            const SizedBox(height: 12),
            Text(
              recentDataErrorText(error),
              key: const Key('recent-error-text'),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('recent-retry'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text(recentDataRetryLabel),
            ),
          ],
        ),
      );
    }
    if (data == null || data.isEmpty) {
      return Padding(
        key: const Key('recent-empty'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.hourglass_empty, size: 40, color: colors.outline),
            const SizedBox(height: 12),
            const Text(recentDataEmptyText, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const Key('recent-empty-refresh'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text(recentDataRefreshLabel),
            ),
          ],
        ),
      );
    }
    final now = (widget.now ?? DateTime.now)();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            recentSummaryText(data, now),
            key: const Key('recent-summary'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.separated(
            key: const Key('recent-list'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: data.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _RecentRow(item: data.items[index], index: index),
          ),
        ),
      ],
    );
  }
}

/// One row: time · PTU tail · state, then volts / mA / °C.
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item, required this.index});
  final RecentItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final mono = TextStyle(fontFeatures: const [FontFeature.tabularFigures()]);
    final ma = item.inputMa == null ? '--' : item.inputMa!.toString();
    final temp = item.tempC == null ? '--' : item.tempC!.toString();
    return Padding(
      key: Key('recent-row-$index'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                recentClockText(item.ts),
                style: theme.textTheme.titleSmall?.merge(mono),
              ),
              const SizedBox(width: 12),
              Text(
                'PTU ${item.ptuTail.isEmpty ? '----' : item.ptuTail}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.ptuState.isEmpty ? '--' : item.ptuState,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.inputVoltsText} V・$ma mA・$temp °C',
            style: theme.textTheme.bodyMedium?.merge(mono),
          ),
        ],
      ),
    );
  }
}
