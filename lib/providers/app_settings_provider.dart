import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense_category_preferences.dart';
import '../services/launch_screen.dart';

/// The language Voice Entry listens for. Filipino also understands English
/// words mixed in, the way most people here talk.
enum VoiceLanguage {
  english('English', 'en-PH'),
  filipino('Tagalog / Taglish', 'fil-PH');

  const VoiceLanguage(this.label, this.localeId);

  final String label;
  final String localeId;
}

/// The signed-in account's display choices, kept on this phone, and its
/// category choices.
///
/// Light, with amounts shown, until the account signed in turns dark mode
/// on or hides amounts itself. Nothing is inherited: not from the phone,
/// not from another account. Signed out, as on Log In and Sign Up, it is
/// always light.
class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider({
    this._themeMode = ThemeMode.light,
    this._amountsMasked = false,
    this._preferences,
    this._account,
  });

  /// Per account, written only by the account's own Dark Mode switch and
  /// eye, so a value here is always a choice that account made.
  static const _darkModeKey = 'darkMode';
  static const _hideAmountsKey = 'hideAmounts';
  static const _voiceLanguageKey = 'voiceLanguage';

  /// Kept by older builds: for the whole phone, then copied into accounts
  /// that never chose them, which opened new accounts in dark mode. Cleared
  /// when the app opens, and never read.
  static const _olderKeys = {'themeMode', 'amountsMasked', 'maskByDefault'};
  static const _olderPerAccountKeys = ['themeMode:', 'amountsMasked:'];

  final SharedPreferences? _preferences;
  ThemeMode _themeMode;
  bool _amountsMasked;
  VoiceLanguage _voiceLanguage = VoiceLanguage.filipino;
  ExpenseCategoryPreferences _categories = const ExpenseCategoryPreferences();

  /// The signed-in account's id, or null signed out.
  String? _account;

  ThemeMode get themeMode => _themeMode;
  bool get amountsMasked => _amountsMasked;
  VoiceLanguage get voiceLanguage => _voiceLanguage;
  ExpenseCategoryPreferences get categories => _categories;

  void updateCategoryPreferences(Map<String, dynamic>? profile) {
    _categories = ExpenseCategoryPreferences.fromMap(profile);
    notifyListeners();
  }

  /// The choices of [account], the one signed in when the app opens.
  static Future<AppSettingsProvider> load({String? account}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _clearOlderChoices(preferences);
      return AppSettingsProvider(preferences: preferences, account: account)
        .._read();
    } catch (error) {
      debugPrint('Could not load app settings: $error');
      return AppSettingsProvider();
    }
  }

  static void _clearOlderChoices(SharedPreferences preferences) {
    for (final key in preferences.getKeys().toList()) {
      if (_olderKeys.contains(key) ||
          _olderPerAccountKeys.any((prefix) => key.startsWith(prefix))) {
        preferences.remove(key);
      }
    }
  }

  /// Switches to [account]'s choices when the signed-in account changes,
  /// or back to the defaults on signing out.
  void useAccount(String? account) {
    if (account == _account) return;
    _account = account;
    _read();
    notifyListeners();
    // The next launch screen matches whoever is signed in.
    LaunchScreen.follow(dark: _themeMode == ThemeMode.dark);
  }

  String _key(String name) => '$name:$_account';

  void _read() {
    final preferences = _preferences;
    final chosen = preferences != null && _account != null;
    _themeMode = chosen && preferences.getBool(_key(_darkModeKey)) == true
        ? ThemeMode.dark
        : ThemeMode.light;
    _amountsMasked =
        chosen && (preferences.getBool(_key(_hideAmountsKey)) ?? false);
    final language = chosen
        ? preferences.getString(_key(_voiceLanguageKey))
        : null;
    _voiceLanguage = VoiceLanguage.values.firstWhere(
      (value) => value.name == language,
      orElse: () => VoiceLanguage.filipino,
    );
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;

    _themeMode = mode;
    notifyListeners();
    if (_account != null) {
      _preferences?.setBool(_key(_darkModeKey), mode == ThemeMode.dark);
    }
    LaunchScreen.follow(dark: mode == ThemeMode.dark);
  }

  /// Remembered for the next time Voice Entry opens.
  void setVoiceLanguage(VoiceLanguage language) {
    if (language == _voiceLanguage) return;
    _voiceLanguage = language;
    notifyListeners();
    if (_account != null) {
      _preferences?.setString(_key(_voiceLanguageKey), language.name);
    }
  }

  /// The eye on the Safe to Spend card. Remembered, so amounts stay hidden
  /// the next time the app opens.
  void toggleAmountsMasked() {
    _amountsMasked = !_amountsMasked;
    notifyListeners();
    if (_account != null) {
      _preferences?.setBool(_key(_hideAmountsKey), _amountsMasked);
    }
  }
}
