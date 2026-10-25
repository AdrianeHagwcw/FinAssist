import 'package:flutter/material.dart';

import 'app_colors.dart';

/// FinAssist brand blue, used across all screens.
const Color appPrimaryBlue = Color(0xFF1976D2);

/// A message under a field is shown in full, never cut off with "...", so
/// the user can read what to fix.
const InputDecorationTheme _fields = InputDecorationTheme(errorMaxLines: 3);

class AppTheme {
  const AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: appPrimaryBlue,
      primary: appPrimaryBlue,
    ),
    scaffoldBackgroundColor: AppColors.light.pageBackground,
    inputDecorationTheme: _fields,
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
      inputDecorationTheme: _fields,
      extensions: const [AppColors.dark],
    );
  }
}
