import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/centering/centering_measure.dart';

//simple page showing the centering estimate for the front and back (only based on centering)
class CenteringResultPage extends StatelessWidget {
  final CenteringResult? front;
  final CenteringResult? back;

  const CenteringResultPage({super.key, required this.front, required this.back});

  String _ratios(CenteringResult? result) {
    if (result == null) return 'Could not be measured';
    final left = (result.leftMm / (result.leftMm + result.rightMm) * 100).round();
    final right = 100 - left;
    final top = (result.topMm / (result.topMm + result.bottomMm) * 100).round();
    final bottom = 100 - top;
    return 'Left/right $left/$right, top/bottom $top/$bottom';
  }

  String _verdict() {
    if (front == null || back == null) {
      return 'Centering grade not available. For a centering estimate, retake on a solid color background that is different from the card border, with even light and no shadows.';
    }
    final grade = combinedCeiling(front!.grade, back!.grade);
    if (grade == null) return 'Centering is outside the PSA limits.';
    return 'Centering alone allows up to PSA $grade.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centering estimate')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_verdict(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          for (final (side, result) in [('Front', front), ('Back', back)]) ...[
            Text(side, style: Theme.of(context).textTheme.titleSmall),
            Text(_ratios(result)),
            const SizedBox(height: 8),
            //straightened card with the measured borders (green = card edge, red = artwork edge)
            if (result != null) Image.memory(result.analysisImage),
            const SizedBox(height: 24),
          ],
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }
}