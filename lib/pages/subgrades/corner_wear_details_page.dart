import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/analysis/corner_wear_data.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/grade_overview.dart';
import 'package:pokemon_card_scanner/vision/card_constants.dart';

class CornerWearDetailsPage extends StatelessWidget {
  final ScannedPokemonCard card;
  final SubGrade subGrade;

  const CornerWearDetailsPage({super.key, required this.card, required this.subGrade});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = GradeOverviewPage.gradeColor(subGrade.score);

    final details = subGrade.details;
    final backPath = details?['backAnnotatedPath'] as String?;

    final backImage = backPath != null && File(backPath).existsSync() ? FileImage(File(backPath)) : card.backImage;

    final backCorners = (details?['backCorners'] as List? ?? []).map((c) => CornerInspectionData.fromJson(c as Map<String, dynamic>)).toList();

    final cardAspectRatio = CardConstants.cardAspectRatio;

    return Scaffold(
      appBar: AppBar(title: const Text('Corner wear details')),
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
                  child: Image(image: backImage, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (backCorners.isNotEmpty) ...[Text('Back corners', style: theme.textTheme.titleMedium), const SizedBox(height: 10), _CornerGrid(corners: backCorners)],
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
                  Text('Corners', style: theme.textTheme.titleMedium),
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

class _CornerGrid extends StatelessWidget {
  final List<CornerInspectionData> corners;

  const _CornerGrid({required this.corners});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        for (final corner in corners)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: Icon(corner.isDamaged ? Icons.error_outline : Icons.check_circle_outline, color: corner.isDamaged ? Colors.redAccent : Colors.green),
              title: Text(corner.name, style: theme.textTheme.titleSmall),
              subtitle: Text(corner.isDamaged ? 'Wear / whitening detected (${corner.blobArea.round()} px defect)' : 'Clean (no defect detected)'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: corner.isDamaged ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  corner.isDamaged ? 'DAMAGED' : 'CLEAN',
                  style: theme.textTheme.labelSmall?.copyWith(color: corner.isDamaged ? Colors.redAccent : Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
