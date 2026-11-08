import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/subgrades/centering_details_page.dart';
import 'package:pokemon_card_scanner/pages/subgrades/corner_wear_details_page.dart';
import 'package:pokemon_card_scanner/pages/subgrades/crease_details_page.dart';

class GradeOverviewPage extends StatelessWidget {
  final ScannedPokemonCard card;

  const GradeOverviewPage({super.key, required this.card});

  static Color gradeColor(num grade) {
    if (grade <= 0) return const Color(0xFF9E9E9E);
    final normalized = grade.clamp(1, 10) / 10;
    if (normalized < 0.6) {
      return Color.lerp(const Color(0xFFEF4444), const Color(0xFFF59E0B), normalized / 0.6)!;
    }
    return Color.lerp(const Color(0xFFF59E0B), const Color(0xFF22C55E), (normalized - 0.6) / 0.4)!;
  }

  static String gradeDescriptor(int grade) {
    return switch (grade) {
      10 => 'Gem Mint',
      9 => 'Mint',
      8 => 'Near Mint-Mint',
      7 => 'Near Mint',
      6 => 'Excellent-Mint',
      5 => 'Excellent',
      4 => 'Very Good-Excellent',
      3 => 'Very Good',
      2 => 'Good',
      _ => 'Poor',
    };
  }

  @override
  Widget build(BuildContext context) {
    final report = card.gradeReport;
    final grade = card.estimatedGrading ?? report?.overallScore ?? 1;
    final color = gradeColor(grade);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Grade overview')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          _HeaderCard(card: card, grade: grade, color: color, descriptor: gradeDescriptor(grade)),
          if (report != null && report.subGrades.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Sub-grades', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final subGrade in report.subGrades) _SubGradeCard(card: card, subGrade: subGrade),
          ],
          if (report != null && report.notes.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Notes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final note in report.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• '),
                            Expanded(child: Text(note)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final ScannedPokemonCard card;
  final int grade;
  final Color color;
  final String descriptor;

  const _HeaderCard({required this.card, required this.grade, required this.color, required this.descriptor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strategy = card.gradeReport?.strategyName ?? 'Default';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      grade.toString(),
                      style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(descriptor, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(card.catalogCard.name, style: theme.textTheme.bodyMedium),
                      Text(card.catalogCard.setName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Strategy', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(strategy, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Scanned', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(
                  '${MaterialLocalizations.of(context).formatShortDate(card.createdAt.toLocal())} ${TimeOfDay.fromDateTime(card.createdAt.toLocal()).format(context)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubGradeCard extends StatelessWidget {
  final ScannedPokemonCard card;
  final SubGrade subGrade;

  const _SubGradeCard({required this.card, required this.subGrade});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = GradeOverviewPage.gradeColor(subGrade.score);
    final isClickable =
        (subGrade.category == 'Corners' || subGrade.category == 'Centering' || subGrade.category == 'Creases' || subGrade.category == 'Surface') && subGrade.details?['unimplemented'] != true;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: isClickable
            ? () {
                if (subGrade.category == 'Centering') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CenteringDetailsPage(card: card, subGrade: subGrade),
                    ),
                  );
                } else if (subGrade.category == 'Corners') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CornerWearDetailsPage(card: card, subGrade: subGrade),
                    ),
                  );
                } else if (subGrade.category == 'Creases' || subGrade.category == 'Surface') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreaseDetailsPage(card: card, subGrade: subGrade),
                    ),
                  );
                }
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(subGrade.category, style: theme.textTheme.titleMedium),
                      if (isClickable) ...[const SizedBox(width: 4), Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurfaceVariant)],
                    ],
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Text(
                        subGrade.score > 0 ? subGrade.score.toStringAsFixed(1) : 'N/A',
                        style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: subGrade.score > 0 ? (subGrade.score / 10).clamp(0.0, 1.0) : 0.0,
                  minHeight: 6,
                  color: color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              if (subGrade.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subGrade.details?['unimplemented'] == true) ...[Icon(Icons.info_outline, size: 15, color: theme.colorScheme.onSurfaceVariant), const SizedBox(width: 6)],
                    Expanded(
                      child: Text(subGrade.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
