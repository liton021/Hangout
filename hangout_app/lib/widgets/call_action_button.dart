import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A circular call-control button (mute, speaker, flip, end…).
///
/// Report §6.4: white circle buttons; active controls get the teal→aqua
/// gradient, inactive ones fade out, the end call button is red.
class CallActionButton extends StatelessWidget {
  const CallActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = true,
    this.danger = false,
    this.label,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final bool danger;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color iconColor;
    if (danger) {
      background = AppColors.danger;
      iconColor = Colors.white;
    } else if (active) {
      background = AppColors.accent;
      iconColor = Colors.white;
    } else {
      background = Colors.white.withOpacity(.18);
      iconColor = Colors.white54;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: (danger || !active) ? null : AppColors.brandGradient,
            color: danger
                ? AppColors.danger
                : (active ? null : Colors.white.withOpacity(.18)),
            shape: BoxShape.circle,
            border: Border.all(
              color: danger
                  ? Colors.transparent
                  : Colors.white.withOpacity(active ? .45 : .18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: danger
                    ? AppColors.danger.withOpacity(.45)
                    : Colors.black.withOpacity(.22),
                blurRadius: danger ? 18 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 60,
                height: 60,
                child: Icon(icon, color: iconColor, size: 25),
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 7),
          Text(
            label!,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
