import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/vision/crease_analyzer.dart';
import 'package:pokemon_card_scanner/widgets/crease_overlay.dart';

class CreaseResultDialog extends StatelessWidget {
  final Future<CreaseResult> analysis;

  const CreaseResultDialog({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Possible creases'),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .65,
        child: FutureBuilder<CreaseResult>(
          future: analysis,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Experimental screening for possible creases. Printed graphics and lighting can trigger markers. These are not confirmed damage or a grade.'),
                  const SizedBox(height: 12),
                  _preview(context, snapshot.data!),
                ],
              ),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Continue'))],
    );
  }

  Widget _preview(BuildContext context, CreaseResult result) {
    if (!result.evaluated) {
      return Text('Back: not evaluated. ${result.notEvaluatedReason}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Back', style: Theme.of(context).textTheme.titleMedium),
        if (result.candidates.isEmpty) const Text('No possible creases were found. This does not establish that the card is crease-free.'),
        const Text('Dashed lines indicate possible crease positions, not measured damage lengths.'),
        CreaseOverlay(analysis: result, image: MemoryImage(result.preview!)),
      ],
    );
  }
}
