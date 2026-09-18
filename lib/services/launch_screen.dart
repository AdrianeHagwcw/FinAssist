import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android's launch screen: the logo on a plain background, shown while the
/// app starts.
///
/// Flutter keeps it up until the app draws its first frame. Holding that
/// frame back until the first real screen is ready means there is no blank
/// frame and no second welcome screen in between.
class LaunchScreen {
  static bool _holding = false;

  /// Talks to MainActivity, which picks the next launch screen's theme.
  @visibleForTesting
  static const channel = MethodChannel('finassist/launch_screen');

  /// Whether the launch screen is still being held.
  static bool get isHolding => _holding;

  /// Keeps the launch screen up. Called once, at the start of `main`.
  static void hold() {
    if (_holding) return;
    _holding = true;
    WidgetsBinding.instance.deferFirstFrame();
  }

  /// Lets the app draw, which takes the launch screen away. Safe to call
  /// more than once, and does nothing if it was never held.
  static void release() {
    if (!_holding) return;
    _holding = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  /// Makes the next launch screen dark or light to match the theme just
  /// chosen, straight away, so it is right however the app is closed.
  /// Android 13 and up only; elsewhere it stays light, the app's default.
  static Future<void> follow({required bool dark}) async {
    try {
      await channel.invokeMethod<void>('setDark', dark);
    } on MissingPluginException {
      // Not running on Android, as in tests: there is no launch screen.
    } on PlatformException catch (error) {
      debugPrint('Launch screen theme unchanged: $error');
    }
  }
}
