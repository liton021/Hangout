import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The in-app version of the Hangout mark used by the launcher and splash UI.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 48, this.showShadow = false});

  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(size * .3),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(.28),
                  blurRadius: size * .45,
                  offset: Offset(0, size * .16),
                ),
              ]
            : null,
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(size * .21, size * .22, size * .58, size * .47),
      Radius.circular(size * .16),
    );
    canvas.drawRRect(bubble, paint);

    final tail = Path()
      ..moveTo(size * .31, size * .64)
      ..lineTo(size * .27, size * .79)
      ..lineTo(size * .46, size * .67)
      ..close();
    canvas.drawPath(tail, paint);

    final cutout = Paint()..color = AppColors.primary;
    canvas.drawCircle(Offset(size * .40, size * .455), size * .038, cutout);
    canvas.drawCircle(Offset(size * .51, size * .455), size * .038, cutout);
    canvas.drawCircle(Offset(size * .62, size * .455), size * .038, cutout);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
