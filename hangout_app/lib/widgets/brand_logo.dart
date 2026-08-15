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
    final unit = size.shortestSide;
    final paint = Paint()..color = Colors.white;
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .21,
        size.height * .22,
        size.width * .58,
        size.height * .47,
      ),
      Radius.circular(unit * .16),
    );
    canvas.drawRRect(bubble, paint);

    final tail = Path()
      ..moveTo(size.width * .31, size.height * .64)
      ..lineTo(size.width * .27, size.height * .79)
      ..lineTo(size.width * .46, size.height * .67)
      ..close();
    canvas.drawPath(tail, paint);

    final cutout = Paint()..color = AppColors.primary;
    canvas.drawCircle(
      Offset(size.width * .40, size.height * .455),
      unit * .038,
      cutout,
    );
    canvas.drawCircle(
      Offset(size.width * .51, size.height * .455),
      unit * .038,
      cutout,
    );
    canvas.drawCircle(
      Offset(size.width * .62, size.height * .455),
      unit * .038,
      cutout,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
