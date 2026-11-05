import 'package:flutter/material.dart';

class GradingSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const GradingSection({super.key, required this.title, required this.subtitle, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        leading: DecoratedBox(
          decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: colors.onPrimaryContainer, size: 22),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        children: [child],
      ),
    );
  }
}
