import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/financial_preferences.dart';
import '../services/launch_screen.dart';

/// Device display preferences and the signed-in account's live financial profile.
class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider({
    this._themeMode = ThemeMode.light,
    this._amountsMasked = false,
    this._preferences,
  });

  static const _themeModeKey = 'themeMode';
  static const _amountsMaskedKey = 'amountsMasked';

  /// Written by an older build's "hide on launch" setting; still read so
  /// anyone who set it keeps their choice.
  static const _maskByDefaultKey = 'maskByDefault';

  final SharedPreferences? _preferences;
  ThemeMode _themeMode;
  bool _amountsMasked;
  FinancialPreferences _financial = const FinancialPreferences();

  ThemeMode get themeMode => _themeMode;
  bool get amountsMasked => _amountsMasked;
  FinancialPreferences get financial => _financial;

  void updateFinancialProfile(Map<String, dynamic>? profile) {
    _financial = FinancialPreferences.fromMap(profile);
    notifyListeners();
  }

  static Future<AppSettingsProvider> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedThemeMode = preferences.getString(_themeModeKey);

      return AppSettingsProvider(
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == storedThemeMode,
          orElse: () => ThemeMode.light,
        ),
        amountsMasked:
            preferences.getBool(_amountsMaskedKey) ??
            preferences.getBool(_maskByDefaultKey) ??
            false,
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
    LaunchScreen.follow(dark: mode == ThemeMode.dark);
  }

  /// The eye on the Safe to Spend card. Remembered, so amounts stay hidden
  /// the next time the app opens.
  void toggleAmountsMasked() {
    _amountsMasked = !_amountsMasked;
    notifyListeners();
    _preferences?.setBool(_amountsMaskedKey, _amountsMasked);
  }
}
