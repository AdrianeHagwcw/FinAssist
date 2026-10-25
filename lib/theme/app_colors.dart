import 'package:flutter/material.dart';

/// FinAssist's own surface and text colors for light and dark mode.
///
/// Every text color passes the 4.5 : 1 contrast readers need on the
/// backgrounds it is used on, in both modes. Read them with
/// `context.appColors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.pageBackground,
    required this.card,
    required this.textPrimary,
    required this.textBody,
    required this.textMuted,
    required this.primaryText,
    required this.border,
    required this.inputBorder,
    required this.primaryTint,
    required this.track,
    required this.inputFill,
    required this.successTint,
    required this.successBorder,
  });

  /// Page background behind cards.
  final Color pageBackground;

  /// Cards, input fields, app bars and sheets.
  final Color card;

  /// Headings and strong text.
  final Color textPrimary;

  /// Regular body text.
  final Color textBody;

  /// Secondary text: subtitles, hints, captions, step counters and quiet
  /// icons. Lighter than body text so headings stand out, but still easy to
  /// read: 5.3 : 1 or more in light mode, 7 : 1 in dark.
  final Color textMuted;

  /// Brand blue used for text and links on cards/page backgrounds.
  final Color primaryText;

  /// Thin borders and dividers on cards.
  final Color border;

  /// Outline of text fields and outlined buttons.
  final Color inputBorder;

  /// Light blue fill behind icons and chips.
  final Color primaryTint;

  /// Unfilled part of progress bars.
  final Color track;

  /// Filled input background (chat box).
  final Color inputFill;

  final Color successTint;
  final Color successBorder;

  static const light = AppColors(
    pageBackground: Color(0xFFF6F8FC),
    card: Colors.white,
    textPrimary: Color(0xFF151515),
    textBody: Colors.black87,
    textMuted: Color(0xFF5B6573),
    primaryText: Color(0xFF1976D2),
    // Strong enough that a white card still shows its edge on white.
    border: Color(0xFFCBD5E1),
    inputBorder: Color(0xFFDADADA),
    primaryTint: Color(0xFFEAF3FB),
    track: Color(0xFFE4EAF3),
    inputFill: Color(0xFFF2F4F7),
    successTint: Color(0xFFE8F5E9),
    successBorder: Color(0xFFA5D6A7),
  );

  static const dark = AppColors(
    pageBackground: Color(0xFF10151B),
    card: Color(0xFF1B222B),
    textPrimary: Color(0xFFE6E9ED),
    textBody: Color(0xDEFFFFFF),
    textMuted: Color(0xFFA3ACB8),
    primaryText: Color(0xFF64B5F6),
    border: Color(0xFF2C3540),
    inputBorder: Color(0xFF3A4450),
    primaryTint: Color(0xFF1E3348),
    track: Color(0xFF2C3540),
    inputFill: Color(0xFF242C36),
    successTint: Color(0xFF1E3324),
    successBorder: Color(0xFF3F6B45),
  );

  @override
  AppColors copyWith({
    Color? pageBackground,
    Color? card,
    Color? textPrimary,
    Color? textBody,
    Color? textMuted,
    Color? primaryText,
    Color? border,
    Color? inputBorder,
    Color? primaryTint,
    Color? track,
    Color? inputFill,
    Color? successTint,
    Color? successBorder,
  }) {
    return AppColors(
      pageBackground: pageBackground ?? this.pageBackground,
      card: card ?? this.card,
      textPrimary: textPrimary ?? this.textPrimary,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      primaryText: primaryText ?? this.primaryText,
      border: border ?? this.border,
      inputBorder: inputBorder ?? this.inputBorder,
      primaryTint: primaryTint ?? this.primaryTint,
      track: track ?? this.track,
      inputFill: inputFill ?? this.inputFill,
      successTint: successTint ?? this.successTint,
      successBorder: successBorder ?? this.successBorder,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;

    return AppColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      card: Color.lerp(card, other.card, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      border: Color.lerp(border, other.border, t)!,
      inputBorder: Color.lerp(inputBorder, other.inputBorder, t)!,
      primaryTint: Color.lerp(primaryTint, other.primaryTint, t)!,
      track: Color.lerp(track, other.track, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      successBorder: Color.lerp(successBorder, other.successBorder, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
