import 'package:flutter/material.dart';

class GradeBadge extends StatelessWidget {
  final num grade;
  final bool showPsaLabel;

  const GradeBadge({super.key, required this.grade, this.showPsaLabel = false});

  Color get _gradeColor {
    final normalizedGrade = grade.clamp(1, 10) / 10;

    if (normalizedGrade < 0.6) {
      return Color.lerp(const Color(0xFFEF4444), const Color(0xFFF59E0B), normalizedGrade / 0.6)!;
    }

    return Color.lerp(const Color(0xFFF59E0B), const Color(0xFF22C55E), (normalizedGrade - 0.6) / 0.4)!;
  }

  @override
  Widget build(BuildContext context) {
    final gradeText = grade == grade.roundToDouble() ? grade.toInt().toString() : grade.toString();
    final badgeColor = _gradeColor;
    final foregroundColor = ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark ? Colors.white : Colors.black;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          showPsaLabel ? 'PSA $gradeText' : gradeText,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foregroundColor, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
