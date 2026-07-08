import 'package:flutter/material.dart';

class TrianglePainter extends CustomPainter {
  final BoxDecoration? decoration;

  TrianglePainter(this.decoration);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (decoration?.color ?? Colors.blue)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}