import 'package:flutter/material.dart';

class LevelPainter extends CustomPainter {
  final Offset _offset;
  final Color _color;

  const LevelPainter(this._offset, this._color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()..color = Colors.black54;
    canvas.drawCircle(center, 48, paint);
    paint
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 12, paint);
    canvas.drawLine(center - const Offset(20, 0), center + const Offset(20, 0), paint);
    canvas.drawLine(center - const Offset(0, 20), center + const Offset(0, 20), paint);

    var displacement = _offset * 12;
    if (displacement.distance > 36) {
      displacement = displacement / displacement.distance * 36;
    }
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(center + displacement, 6, paint);
  }

  @override
  bool shouldRepaint(LevelPainter oldDelegate) => oldDelegate._offset != _offset || oldDelegate._color != _color;
}
