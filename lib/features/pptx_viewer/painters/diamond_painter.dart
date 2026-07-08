import 'package:flutter/material.dart';

class DiamondPainter extends CustomPainter {
  final BoxDecoration? decoration;

  DiamondPainter(this.decoration);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (decoration?.color ?? Colors.red)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}