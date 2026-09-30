import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A flat inductive charging pad, without a cable or dispenser silhouette.
class WirelessChargingPadIcon extends StatelessWidget {
  const WirelessChargingPadIcon({super.key, this.color, this.size = 28});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 1.25,
    height: size,
    child: CustomPaint(
      painter: _ChargingPadPainter(
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _ChargingPadPainter extends CustomPainter {
  const _ChargingPadPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 35, size.height / 28);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Concentric induction waves rise above the horizontal charging plate.
    for (final radius in [5.0, 9.0, 13.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(17.5, 16), radius: radius),
        math.pi * 1.15,
        math.pi * 0.7,
        false,
        outline,
      );
    }

    final plate = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 18, 29, 7),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(plate, outline);
    canvas.drawLine(const Offset(7, 21.5), const Offset(28, 21.5), outline);

    // A small energy mark joins the waves to the pad, not a status badge.
    final charge = Path()
      ..moveTo(18.5, 11)
      ..lineTo(15, 15)
      ..lineTo(17, 15)
      ..lineTo(16.5, 18)
      ..lineTo(20, 13.5)
      ..lineTo(18, 13.5)
      ..close();
    canvas.drawPath(charge, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChargingPadPainter oldDelegate) =>
      color != oldDelegate.color;
}
