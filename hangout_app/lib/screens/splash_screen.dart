import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final dark = context.isDark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.canvasGradient),
        child: Stack(
          children: [
            // Soft accent "blobs" — flat, colorful accents (report §3).
            Positioned(
              top: -90,
              right: -70,
              child: _Blob(
                size: 240,
                color: dark
                    ? AppColors.accentSurface.withOpacity(.55)
                    : AppColors.accentSoft.withOpacity(.35),
              ),
            ),
            Positioned(
              bottom: -110,
              left: -80,
              child: _Blob(
                size: 280,
                color: dark
                    ? AppColors.surface
                    : AppColors.accentSoft.withOpacity(.25),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLogo(size: 96, showShadow: true),
                  const SizedBox(height: 28),
                  Text(
                    'Hangout',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontSize: 36,
                          letterSpacing: -1,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Closer, wherever you are.',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 44),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
