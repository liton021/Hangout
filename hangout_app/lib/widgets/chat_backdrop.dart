import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The classic Telegram chat backdrop: a soft repeating "paper tear" / gear
/// glyph pattern, tinted by theme. In dark mode it's a faint lighter blue;
/// in light mode a faint blue-gray. Pure decoration — sits behind the
/// message list, never intercepts touches.
class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final color = dark
        ? const Color(0xFF6C8AA8)
        : const Color(0xFF8AA0B8);

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PatternPainter(color: color),
      ),
    );
  }
}

/// Tiles a small 6-spoke asterisk glyph at low opacity.
class _PatternPainter extends CustomPainter {
  const _PatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const spacing = 60.0;
    const r = 7.0;

    for (var y = 14.0; y < size.height; y += spacing) {
      for (var x = 14.0; x < size.width; x += spacing) {
        _drawGlyph(canvas, Offset(x, y), r, paint);
      }
    }
  }

  void _drawGlyph(Canvas canvas, Offset c, double r, Paint paint) {
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final end = c + Offset(math.cos(angle) * r, math.sin(angle) * r);
      canvas.drawLine(c - (end - c), end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) =>
      oldDelegate.color != color;
}
