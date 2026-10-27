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

  /// Just the artwork, without the empty space around it in the image, so
  /// it centres and sizes by what is drawn. [width] is the artwork's.
  const AppLogo.trimmed({required double this.width, super.key})
    : height = null,
      fit = BoxFit.contain,
      alignment = Alignment.center;

  static const _lightAsset =
      'assets/icons/e621696b-4d3b-4ad5-972c-7c96ad3f6c71_removalai_preview.png';
  static const _darkAsset = 'assets/icons/finassist_logo_dark.png';

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  /// Where the artwork sits in both images (600 × 548).
  static const _imageSize = Size(600, 548);
  static const _artwork = Rect.fromLTRB(96, 129, 496, 344);

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
    final asset = context.isDarkMode ? _darkAsset : _lightAsset;
    if (height != null || fit != BoxFit.contain || width == null) {
      return Image.asset(
        asset,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
      );
    }

    // Trimmed: the image drawn large enough for the artwork to be [width]
    // wide, with only the artwork's part of it shown.
    final widthFactor = _artwork.width / _imageSize.width;
    final heightFactor = _artwork.height / _imageSize.height;
    return ClipRect(
      child: Align(
        alignment: Alignment(
          2 * _artwork.left / (_imageSize.width - _artwork.width) - 1,
          2 * _artwork.top / (_imageSize.height - _artwork.height) - 1,
        ),
        widthFactor: widthFactor,
        heightFactor: heightFactor,
        child: Image.asset(asset, width: width! / widthFactor),
      ),
    );
  }
}
