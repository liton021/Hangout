import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Text painted with a [Gradient] fill instead of a flat color.
///
/// Used for the "Hangout 2.0" gradient titles and highlights. The text is
/// rendered in white underneath and the gradient is applied as a mask, so
/// [style.color] is ignored.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = AppColors.vividGradient,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;

  /// Defaults to the brand blue→violet [AppColors.vividGradient].
  final Gradient gradient;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        // The mask colors the glyphs; the base color just needs to be
        // opaque. White keeps semantics simple in both themes.
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}
