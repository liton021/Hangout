import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/app_theme.dart';
import 'presence_dot.dart';

/// Circular avatar: teal→aqua gradient with a white initial, or the user's
/// photo when available. Optionally shows a teal/green presence dot (report
/// §6.4: "Circle, teal→aqua gradient with white initial; presence dot").
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 22,
    this.showPresence = false,
  });

  final AppUser user;
  final double radius;
  final bool showPresence;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    final hasImage = url != null && url.isNotEmpty;
    final diameter = radius * 2;

    final Widget avatar = ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: hasImage
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _gradientInitials(diameter),
              )
            : _gradientInitials(diameter),
      ),
    );

    if (!showPresence) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(right: 0, bottom: 0, child: PresenceDot()),
      ],
    );
  }

  Widget _gradientInitials(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        user.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.78,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
