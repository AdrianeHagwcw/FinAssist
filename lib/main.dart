import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/app_settings_provider.dart';
import 'services/reminder_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final settings = await AppSettingsProvider.load();
  // Early, so a reminder that opened the app is caught before any screen.
  await ReminderService.init();

  runApp(ChangeNotifierProvider.value(value: settings, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({this.home = const SplashScreen(), super.key});

  /// First screen shown. Tests pass a splash with a fake session check.
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
