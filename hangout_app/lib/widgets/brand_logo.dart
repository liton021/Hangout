import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The in-app version of the Hangout mark used by the launcher and splash UI.
///
/// Mirrors the launcher icon exactly: a speech bubble with the "H" monogram
/// knocked out of it, on the brand gradient. The geometry below matches
/// `design/build_logo.py`, which generates the Android mipmaps — keep the two
/// in sync if the mark is ever redrawn.
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
        borderRadius: BorderRadius.circular(size * .234),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.accent.withOpacity(.35),
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

/// Draws the bubble + tail in white, then punches the H through it so the
/// gradient behind shows within the letter.
class _LogoPainter extends CustomPainter {
  // Fractions of the tile, identical to the values in design/build_logo.py.
  static const double _bubbleCx = .500;
  static const double _bubbleCy = .459;
  static const double _bubbleR = .293;
  static const double _hW = .244;
  static const double _hH = .283;
  static const double _hStroke = .0645;

  static const List<Offset> _tail = [
    Offset(.312, .648),
    Offset(.247, .836),
    Offset(.456, .694),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * _bubbleCx;
    final cy = h * _bubbleCy;

    // saveLayer so BlendMode.clear carves the H out of the bubble only,
    // leaving the gradient container underneath untouched.
    canvas.saveLayer(Offset.zero & size, Paint());

    final white = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), w * _bubbleR, white);
    canvas.drawPath(
      Path()
        ..moveTo(w * _tail[0].dx, h * _tail[0].dy)
        ..lineTo(w * _tail[1].dx, h * _tail[1].dy)
        ..lineTo(w * _tail[2].dx, h * _tail[2].dy)
        ..close(),
      white,
    );

    final cut = Paint()..blendMode = BlendMode.clear;
    final hw = w * _hW;
    final hh = h * _hH;
    final st = w * _hStroke;
    final left = cx - hw / 2;
    final top = cy - hh / 2;

    canvas.drawRect(Rect.fromLTWH(left, top, st, hh), cut);
    canvas.drawRect(Rect.fromLTWH(left + hw - st, top, st, hh), cut);
    canvas.drawRect(Rect.fromLTWH(left, cy - st / 2, hw, st), cut);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
