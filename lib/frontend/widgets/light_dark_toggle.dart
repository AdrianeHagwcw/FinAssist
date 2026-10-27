import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Compact sun/moon icon button for screen corners, e.g. onboarding.
class LightDarkIconButton extends StatelessWidget {
  const LightDarkIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<AppSettingsProvider, bool>(
      (settings) => settings.themeMode == ThemeMode.dark,
    );

    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        color: context.appColors.textBody,
      ),
      onPressed: () => context.read<AppSettingsProvider>().setThemeMode(
        isDark ? ThemeMode.light : ThemeMode.dark,
      ),
    );
  }
}

/// Sun/moon switch row that turns dark mode on and off for the whole app.
class LightDarkToggle extends StatelessWidget {
  const LightDarkToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<AppSettingsProvider, bool>(
      (settings) => settings.themeMode == ThemeMode.dark,
    );

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      secondary: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: context.appColors.primaryTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          color: context.appColors.primaryText,
        ),
      ),
      title: const Text(
        'Dark Mode',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(isDark ? 'On' : 'Off'),
      value: isDark,
      activeThumbColor: Colors.white,
      activeTrackColor: appPrimaryBlue,
      onChanged: (value) => context.read<AppSettingsProvider>().setThemeMode(
        value ? ThemeMode.dark : ThemeMode.light,
      ),
    );
  }
}
