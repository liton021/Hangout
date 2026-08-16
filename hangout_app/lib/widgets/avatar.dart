import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/app_theme.dart';
import 'presence_dot.dart';

/// Circular avatar: the user's photo, or a flat charcoal circle with their
/// initial in periwinkle (matching the Contacts / Discovery designs).
///
/// Set [ringColor] to draw the blue profile ring used on the Settings header,
/// and [showPresence] to add the green online dot.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 24,
    this.showPresence = false,
    this.ringColor,
    this.ringWidth = 2.5,
    this.presenceBorderColor,
  });

  final AppUser user;
  final double radius;
  final bool showPresence;
  final Color? ringColor;
  final double ringWidth;
  final Color? presenceBorderColor;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    final hasImage = url != null && url.isNotEmpty;
    final diameter = radius * 2;

    Widget avatar = ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: hasImage
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initials(diameter),
              )
            : _initials(diameter),
      ),
    );

    if (ringColor != null) {
      avatar = Container(
        padding: EdgeInsets.all(ringWidth + 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor!, width: ringWidth),
        ),
        child: avatar,
      );
    }

    if (!showPresence) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: ringColor != null ? radius * 0.08 : 0,
          bottom: ringColor != null ? radius * 0.08 : 0,
          child: PresenceDot(
            radius: radius > 40 ? 11 : 6.5,
            borderWidth: radius > 40 ? 3.5 : 2.5,
            borderColor: presenceBorderColor,
          ),
        ),
      ],
    );
  }

  Widget _initials(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        user.initials,
        style: TextStyle(
          color: AppColors.accentSoft,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.8,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Flat charcoal circle holding an icon — used for group chats and for
/// contacts without a photo in compact rows.
class IconAvatar extends StatelessWidget {
  const IconAvatar({
    super.key,
    required this.icon,
    this.radius = 24,
    this.background = AppColors.surfaceMuted,
    this.foreground = AppColors.textSecondary,
  });

  final IconData icon;
  final double radius;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: radius * 0.95, color: foreground),
    );
  }
}
