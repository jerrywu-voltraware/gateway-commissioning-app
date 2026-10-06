import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// The app's task chooser. It never starts a commissioning operation.
class HomeEntryPanel extends StatelessWidget {
  const HomeEntryPanel({
    super.key,
    required this.onConfigure,
    required this.onViewData,
    this.hasSavedProgress = false,
  });

  final VoidCallback? onConfigure;
  final VoidCallback? onViewData;
  final bool hasSavedProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: const Key('home-entry-panel'),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Text(l10n.homeEntry_title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              _EntryCard(
                key: const Key('home-configure'),
                icon: Icons.build_outlined,
                title: l10n.homeEntry_configure,
                description: l10n.homeEntry_configureDescription,
                action: l10n.homeEntry_configureAction,
                note: hasSavedProgress ? l10n.homeEntry_savedProgress : null,
                onTap: onConfigure,
              ),
              const SizedBox(height: 16),
              _EntryCard(
                key: const Key('home-view-data'),
                icon: Icons.insights_outlined,
                title: l10n.homeEntry_viewData,
                description: l10n.homeEntry_viewDataDescription,
                action: l10n.homeEntry_viewDataAction,
                onTap: onViewData,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
    required this.onTap,
    this.note,
  });

  final IconData icon;
  final String title, description, action;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: colors.primary),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(description, style: theme.textTheme.bodyMedium),
              if (note != null) ...[
                const SizedBox(height: 12),
                Text(
                  note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      action,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: colors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
