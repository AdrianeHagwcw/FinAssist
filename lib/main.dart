import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/app_settings_provider.dart';
import 'services/launch_screen.dart';
import 'services/reminder_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android's launch screen (the logo) stays up until the first real screen
  // is ready, instead of a blank frame or a second welcome screen.
  LaunchScreen.hold();

  final (_, settings, _) = await (
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    AppSettingsProvider.load(),
    // So the first screen's logo is there on its first frame.
    AppLogo.precache(),
  ).wait;
  // Early, so a reminder that opened the app is caught, but not waited for:
  // the home screen opens it whenever it arrives.
  unawaited(ReminderService.init());

  runApp(ChangeNotifierProvider.value(value: settings, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({this.home = const SplashScreen(), super.key});

  /// First screen shown. Tests pass one with a fake session check.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppSettingsProvider, ThemeMode>(
      (settings) => settings.themeMode,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FinAssist',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: home,
    );
  }
}
