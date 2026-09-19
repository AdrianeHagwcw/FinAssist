import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/launch_screen.dart';
import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'financial_setup_screen.dart';
import 'login_screen.dart';
import 'main_shell.dart';

/// Where the app should go after checking for a saved session.
enum StartDestination { signedOut, setup, home }

/// Checks for a signed-in user and whether they finished financial setup.
Future<StartDestination> resolveStartDestination() async {
  final user = await FirebaseAuth.instance.authStateChanges().first;

  if (user == null) return StartDestination.signedOut;

  final setupCompleted = await UserProfileService.isSetupCompleted();
  return setupCompleted ? StartDestination.home : StartDestination.setup;
}

/// The app's first screen. Behind Android's launch screen it checks for a
/// saved session, then shows Log In, financial setup or the dashboard. If the
/// check fails it offers Try Again and Log Out.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    this.resolveDestination = resolveStartDestination,
    super.key,
  });

  /// How long the launch screen waits for the session check. After that the
  /// app shows the same logo with a loading ring, so a slow connection never
  /// looks frozen.
  static const launchScreenLimit = Duration(seconds: 2);

  final Future<StartDestination> Function() resolveDestination;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _limit;
  StartDestination? _destination;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _limit = Timer(SplashScreen.launchScreenLimit, LaunchScreen.release);
    _checkSession();
  }

  @override
  void dispose() {
    _limit?.cancel();
    LaunchScreen.release();
    super.dispose();
  }

  Future<void> _checkSession() async {
    setState(() {
      _destination = null;
      _hasError = false;
    });

    try {
      final destination = await widget.resolveDestination();
      if (!mounted) return;
      setState(() => _destination = destination);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }

    // The first real screen is built, so it takes over from the launch screen.
    _limit?.cancel();
    LaunchScreen.release();
  }

  Future<void> _logOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _destination = StartDestination.signedOut;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _StartError(onRetry: _checkSession, onLogOut: _logOut);
    }

    return switch (_destination) {
      null => const _Loading(),
      StartDestination.signedOut => const LoginScreen(),
      StartDestination.setup => const FinancialSetupScreen(),
      StartDestination.home => const MainShell(),
    };
  }
}

/// The launch screen redrawn by the app, with a loading ring under the logo.
/// Seen only when starting takes longer than usual, or after Try Again.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.card,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // As tall as the ring and its gap below, so the logo stays in the
            // middle of the screen, where the launch screen had it.
            SizedBox(height: 60),
            _LaunchLogo(),
            SizedBox(height: 28),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: appPrimaryBlue,
                semanticsLabel: 'Loading',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The logo as the launch screen shows it: the artwork 160 wide, in the
/// exact middle.
class _LaunchLogo extends StatelessWidget {
  const _LaunchLogo();

  @override
  Widget build(BuildContext context) {
    // The logo files are 600 x 548 with the artwork from (96, 129) to
    // (496, 344). At 240 wide the artwork is 160 wide, and its centre sits
    // 1.6 left of and 15 above the image's centre, so the image moves by that.
    return Transform.translate(
      offset: const Offset(1.6, 15),
      child: const AppLogo(width: 240, height: 219.2),
    );
  }
}

/// Shown when the saved session could not be checked.
class _StartError extends StatelessWidget {
  const _StartError({required this.onRetry, required this.onLogOut});

  final VoidCallback onRetry;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.card,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
          child: Column(
            children: [
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: const AppLogo(
                  width: 240,
                  height: 160,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'We could not load your profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.4),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: _ErrorActions(onRetry: onRetry, onLogOut: onLogOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorActions extends StatelessWidget {
  const _ErrorActions({required this.onRetry, required this.onLogOut});

  final VoidCallback onRetry;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onLogOut,
            style: dangerOutlineStyle(context, height: 52),
            child: const Text('Log Out'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 52),
              backgroundColor: appPrimaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Try Again'),
          ),
        ),
      ],
    );
  }
}
