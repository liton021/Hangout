import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Primary CTA button with the teal→aqua brand gradient (report §3 / §6.4).
///
/// Replaces the flat `ElevatedButton` where the design system calls for a
/// gradient accent (auth CTAs, FABs, empty-state actions).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    this.child,
    this.label,
    this.icon,
    this.loading = false,
    this.height = 56,
    this.radius = 16,
    this.gradient = AppColors.brandGradient,
  });

  final VoidCallback? onPressed;
  final Widget? child;
  final String? label;
  final IconData? icon;
  final bool loading;
  final double height;
  final double radius;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : .55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(.35),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : (child ??
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (label != null) ...[
                            Text(
                              label!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                            if (icon != null) ...[
                              const SizedBox(width: 8),
                              Icon(icon, size: 19, color: Colors.white),
                            ],
                          ] else if (icon != null)
                            Icon(icon, size: 22, color: Colors.white),
                        ],
                      )),
            ),
          ),
        ),
      ),
    );
  }
}
