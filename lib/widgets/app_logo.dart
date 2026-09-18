import 'dart:async';

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

  /// Loads both versions of the logo into memory while the launch screen is
  /// up, so the first screen shows it straight away instead of a moment
  /// later. Never fails: a logo that can't load is only drawn late.
  static Future<void> precache() {
    return Future.wait([
      for (final asset in [_lightAsset, _darkAsset]) _load(AssetImage(asset)),
    ]);
  }

  static Future<void> _load(ImageProvider image) {
    final loaded = Completer<void>();
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void done() {
      if (!loaded.isCompleted) loaded.complete();
      stream.removeListener(listener);
    }

    listener = ImageStreamListener((_, _) => done(), onError: (_, _) => done());
    stream.addListener(listener);
    return loaded.future;
  }

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
