import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small green presence dot shown on avatars. The ring is punched out in the
/// colour of whatever sits behind the avatar (canvas by default).
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    this.radius = 6.5,
    this.borderWidth = 2.5,
    this.color = AppColors.success,
    this.borderColor,
  });

  final double radius;
  final double borderWidth;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ring = borderColor ?? Theme.of(context).scaffoldBackgroundColor;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: borderWidth <= 0
            ? null
            : Border.all(color: ring, width: borderWidth),
      ),
    );
  }
}
