import 'package:flutter/material.dart';

class CenteringMeasurements extends StatelessWidget {
  final double leftMm, rightMm, topMm, bottomMm;

  const CenteringMeasurements({super.key, required this.leftMm, required this.rightMm, required this.topMm, required this.bottomMm});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _AxisMeasurement(firstLabel: 'Left', secondLabel: 'Right', firstMm: leftMm, secondMm: rightMm),
      const SizedBox(height: 20),
      _AxisMeasurement(firstLabel: 'Top', secondLabel: 'Bottom', firstMm: topMm, secondMm: bottomMm),
    ],
  );
}

class _AxisMeasurement extends StatelessWidget {
  final String firstLabel, secondLabel;
  final double firstMm, secondMm;

  const _AxisMeasurement({required this.firstLabel, required this.secondLabel, required this.firstMm, required this.secondMm});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = firstMm + secondMm;
    final share = total > 0 && total.isFinite ? (firstMm / total).clamp(0.0, 1.0) : 0.5;
    final percent = (share * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text('$firstLabel / $secondLabel', style: theme.textTheme.labelLarge)),
            const SizedBox(width: 12),
            Text('$percent : ${100 - percent}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '$firstLabel $percent percent, $secondLabel ${100 - percent} percent',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: colors.secondaryContainer)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: share,
                      heightFactor: 1,
                      child: ColoredBox(color: colors.primary),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(width: 2, height: 6, child: ColoredBox(color: colors.surface)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text('$firstLabel ${firstMm.toStringAsFixed(2)} mm', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$secondLabel ${secondMm.toStringAsFixed(2)} mm',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
