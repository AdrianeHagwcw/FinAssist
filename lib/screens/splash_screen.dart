import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';
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

/// First screen on launch. Returning users are sent straight to their
/// dashboard; new users see a welcome with a Get Started button.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    this.resolveDestination = resolveStartDestination,
    super.key,
  });

  final Future<StartDestination> Function() resolveDestination;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Keeps the splash visible briefly so it doesn't flash on fast devices.
  static const _minimumDisplayTime = Duration(milliseconds: 800);

  bool _isChecking = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    setState(() {
      _isChecking = true;
      _hasError = false;
    });

    try {
      final results = await Future.wait([
        widget.resolveDestination(),
        Future<void>.delayed(_minimumDisplayTime),
      ]);
      final destination = results.first as StartDestination;

      if (!mounted) return;

      switch (destination) {
        case StartDestination.signedOut:
          setState(() => _isChecking = false);
        case StartDestination.setup:
          _replaceWith(const FinancialSetupScreen());
        case StartDestination.home:
          _replaceWith(const MainShell());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _hasError = true;
      });
    }
  }

  void _replaceWith(Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  Future<void> _logOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    _replaceWith(const LoginScreen());
  }

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
                'Welcome to FinAssist',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Plan your pesos, pay bills on time, and reach your savings goals.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _ReassuranceChip(
                    icon: Icons.money_off_outlined,
                    label: 'No subscriptions',
                  ),
                  _ReassuranceChip(
                    icon: Icons.cloud_off_outlined,
                    label: 'Works offline',
                  ),
                  _ReassuranceChip(
                    icon: Icons.lock_outline,
                    label: 'Only you see your data',
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: _isChecking
                    ? const Center(
                        child: CircularProgressIndicator(color: appPrimaryBlue),
                      )
                    : _hasError
                    ? _ErrorActions(onRetry: _checkSession, onLogOut: _logOut)
                    : ElevatedButton(
                        onPressed: () => _replaceWith(const LoginScreen()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appPrimaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                _hasError
                    ? 'We could not load your profile. Check your connection and try again.'
                    : 'Not connected to your bank or e-wallet. You enter everything yourself.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReassuranceChip extends StatelessWidget {
  const _ReassuranceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: context.appColors.primaryTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: context.appColors.primaryText),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appColors.primaryText,
            ),
          ),
        ],
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
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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
