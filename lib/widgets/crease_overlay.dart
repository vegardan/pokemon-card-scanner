import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';

/// Supply the corresponding corrected back, without extra cropping or rotation.
class CreaseOverlay extends StatelessWidget {
  final CreaseAnalysis analysis;
  final ImageProvider image;

  const CreaseOverlay({super.key, required this.analysis, required this.image});

  @override
  Widget build(BuildContext context) {
    if (!analysis.evaluated) return Image(image: image, fit: BoxFit.contain);
    return AspectRatio(
      aspectRatio: analysis.width / analysis.height,
      child: CustomPaint(
        foregroundPainter: _CreasePainter(analysis),
        child: Image(image: image, fit: BoxFit.fill),
      ),
    );
  }
}

class _CreasePainter extends CustomPainter {
  final CreaseAnalysis result;

  const _CreasePainter(this.result);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    for (final candidate in result.candidates) {
      final start = Offset(candidate.x1 / result.width * size.width, candidate.y1 / result.height * size.height);
      final end = Offset(candidate.x2 / result.width * size.width, candidate.y2 / result.height * size.height);
      final length = (end - start).distance;
      for (var offset = 0.0; offset < length; offset += 10) {
        canvas.drawLine(start + (end - start) * (offset / length), start + (end - start) * (math.min(offset + 6, length) / length), pen);
      }
    }
  }

  @override
  bool shouldRepaint(_CreasePainter oldDelegate) => oldDelegate.result != result;
}
