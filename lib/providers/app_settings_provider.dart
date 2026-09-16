import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide display preferences, stored on this device only.
class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider({
    this._themeMode = ThemeMode.light,
    this._amountsMasked = false,
    this._preferences,
  });

  static const _themeModeKey = 'themeMode';
  static const _amountsMaskedKey = 'amountsMasked';

  final SharedPreferences? _preferences;
  ThemeMode _themeMode;
  bool _amountsMasked;

  ThemeMode get themeMode => _themeMode;
  bool get amountsMasked => _amountsMasked;

  static Future<AppSettingsProvider> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedThemeMode = preferences.getString(_themeModeKey);

      return AppSettingsProvider(
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == storedThemeMode,
          orElse: () => ThemeMode.light,
        ),
        amountsMasked: preferences.getBool(_amountsMaskedKey) ?? false,
        preferences: preferences,
      );
    } catch (error) {
      debugPrint('Could not load app settings: $error');
      return AppSettingsProvider();
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;

    _themeMode = mode;
    notifyListeners();
    _preferences?.setString(_themeModeKey, mode.name);
  }

  void toggleAmountsMasked() {
    _amountsMasked = !_amountsMasked;
    notifyListeners();
    _preferences?.setBool(_amountsMaskedKey, _amountsMasked);
  }
}
