import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/grade_overview.dart';
import 'package:pokemon_card_scanner/widgets/grading/centering_details.dart';

class CenteringDetailsPage extends StatelessWidget {
  final ScannedPokemonCard card;
  final SubGrade subGrade;

  const CenteringDetailsPage({super.key, required this.card, required this.subGrade});

  @override
  Widget build(BuildContext context) {
    final color = GradeOverviewPage.gradeColor(subGrade.score);

    return Scaffold(
      appBar: AppBar(title: const Text('Centering details')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          _ScoreSummaryCard(subGrade: subGrade, color: color),
          if (subGrade.details?['note'] != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(subGrade.details!['note'] as String, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CenteringDetails(front: card.frontCentering, back: card.backCentering),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreSummaryCard extends StatelessWidget {
  final SubGrade subGrade;
  final Color color;

  const _ScoreSummaryCard({required this.subGrade, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  subGrade.score > 0 ? subGrade.score.toStringAsFixed(1) : 'N/A',
                  style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Centering', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subGrade.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
