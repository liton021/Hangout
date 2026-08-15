import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small teal/green presence dot shown on avatars (report §6.4).
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    this.radius = 6.5,
    this.borderWidth = 2.5,
    this.color = AppColors.success,
  });

  final double radius;
  final double borderWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // The dot sits on top of a card/app-bar surface, so the ring matches the
    // current surface colour for a clean "cut-out" look.
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: surface, width: borderWidth),
      ),
    );
  }
}
