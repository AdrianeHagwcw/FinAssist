import 'package:flutter/material.dart';

import 'app_colors.dart';

/// FinAssist brand blue, used across all screens.
const Color appPrimaryBlue = Color(0xFF1976D2);

class AppTheme {
  const AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: appPrimaryBlue,
      primary: appPrimaryBlue,
    ),
    scaffoldBackgroundColor: AppColors.light.pageBackground,
    extensions: const [AppColors.light],
  );

  static ThemeData get dark {
    final colors = AppColors.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: appPrimaryBlue,
        brightness: Brightness.dark,
        surface: colors.card,
      ),
      scaffoldBackgroundColor: colors.pageBackground,
      canvasColor: colors.card,
      cardColor: colors.card,
      dividerColor: colors.border,
      extensions: const [AppColors.dark],
    );
  }
}
