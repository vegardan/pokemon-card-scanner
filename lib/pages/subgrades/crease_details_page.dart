import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/grade_overview.dart';
import 'package:pokemon_card_scanner/vision/card_constants.dart';
import 'package:pokemon_card_scanner/widgets/crease_overlay.dart';

class CreaseDetailsPage extends StatelessWidget {
  final ScannedPokemonCard card;
  final SubGrade subGrade;

  const CreaseDetailsPage({super.key, required this.card, required this.subGrade});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = GradeOverviewPage.gradeColor(subGrade.score);
    final creaseAnalysis = card.backCreases;
    final cardAspectRatio = CardConstants.cardAspectRatio;

    return Scaffold(
      appBar: AppBar(title: const Text('Crease details')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          _ScoreSummaryCard(subGrade: subGrade, color: color),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AspectRatio(
                aspectRatio: cardAspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: creaseAnalysis.evaluated && creaseAnalysis.width > 0 && creaseAnalysis.height > 0
                      ? CreaseOverlay(analysis: creaseAnalysis, image: card.backImage)
                      : Image(image: card.backImage, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Experimental screening for possible creases. Printed graphics and lighting can trigger markers. Dashed lines indicate possible crease positions, not measured damage lengths.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _CreaseStatusSection(analysis: creaseAnalysis),
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
                  subGrade.score.toStringAsFixed(1),
                  style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Creases', style: theme.textTheme.titleMedium),
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

class _CreaseStatusSection extends StatelessWidget {
  final CreaseAnalysis analysis;

  const _CreaseStatusSection({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (analysis.status) {
      case CreaseStatus.possibleCreases:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detected crease candidates (${analysis.candidates.length})', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            for (var i = 0; i < analysis.candidates.length; i++) _CandidateCard(index: i + 1, candidate: analysis.candidates[i]),
          ],
        );

      case CreaseStatus.noCandidates:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No creases detected', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('No possible creases were found during screening.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

      case CreaseStatus.notEvaluated:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.help_outline, color: theme.colorScheme.onSurfaceVariant, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Crease screening not evaluated', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        analysis.notEvaluatedReason ?? 'Crease analysis could not be completed for this scan.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _CandidateCard extends StatelessWidget {
  final int index;
  final PossibleCrease candidate;

  const _CandidateCard({required this.index, required this.candidate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prominencePct = (candidate.prominence * 100).round();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.red.withValues(alpha: 0.15),
              child: Text(
                '$index',
                style: theme.textTheme.labelMedium?.copyWith(color: Colors.red.shade700, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Candidate #$index', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Angle: ${candidate.angle.toStringAsFixed(1)}° • Span: (${candidate.x1.round()}, ${candidate.y1.round()}) to (${candidate.x2.round()}, ${candidate.y2.round()})',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('$prominencePct% prom.', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
