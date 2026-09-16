import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The FinAssist logo. In dark mode it uses a copy of the artwork whose dark
/// "Fin" lettering is recolored light so it stays readable.
class AppLogo extends StatelessWidget {
  const AppLogo({
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    super.key,
  });

  static const _lightAsset =
      'assets/icons/e621696b-4d3b-4ad5-972c-7c96ad3f6c71_removalai_preview.png';
  static const _darkAsset = 'assets/icons/finassist_logo_dark.png';

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      context.isDarkMode ? _darkAsset : _lightAsset,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}
