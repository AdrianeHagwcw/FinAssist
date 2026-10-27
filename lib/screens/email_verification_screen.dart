import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    this.email,
    this.user,
    this.sendOnOpen = false,
  });

  final String? email;
  final User? user;

  /// Sends the email straight away, right after Create Account, so it is
  /// already on its way. Not when an unverified account logs in: its email
  /// went before, and sending again could hit the sending limit.
  final bool sendOnOpen;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;
  bool _hasSentVerificationEmail = false;
  String? _sendError;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _emailController.text =
        widget.user?.email ??
        FirebaseAuth.instance.currentUser?.email ??
        widget.email ??
        '';
    if (widget.sendOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _sendVerificationEmail(),
      );
    }
  }

  String _formatCooldown() {
    final minutes = (_cooldownSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_cooldownSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _startCooldown({int seconds = 60}) {
    _cooldownSeconds = seconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_cooldownSeconds > 0) {
          _cooldownSeconds -= 1;
        } else {
          timer.cancel();
          _cooldownTimer = null;
        }
      });
    });
  }

  Future<User?> _getSignedInUser() async {
    final auth = FirebaseAuth.instance;
    return widget.user ??
        auth.currentUser ??
        await auth.authStateChanges().first;
  }

  void _returnToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LoginScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  Future<void> _sendVerificationEmail() async {
    final user = await _getSignedInUser();
    if (user == null) {
      if (mounted) _returnToLogin();
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser ?? user;

      if (refreshedUser.emailVerified) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        await _showMessage(
          'Your email is already verified. You can now log in.',
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
        return;
      }

      await refreshedUser.sendEmailVerification();
      if (mounted) {
        setState(() {
          _hasSentVerificationEmail = true;
          _sendError = null;
        });
      }
      _startCooldown();
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'user-token-expired':
          message = 'Your session expired. Please log in again.';
          break;
        case 'too-many-requests':
          if (mounted) {
            setState(() => _hasSentVerificationEmail = true);
          }
          _startCooldown();
          message =
              'Too many attempts. Please try again in ${_formatCooldown()}.';
          break;
        default:
          message = e.message ?? 'Unable to resend the verification email.';
      }
      await _showMessage(message);
      if (mounted) setState(() => _sendError = message);
    } catch (e) {
      const message =
          'Something went wrong while sending the verification email.';
      if (mounted) setState(() => _sendError = message);
      await _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkVerification() async {
    final user = await _getSignedInUser();
    if (user == null) {
      if (mounted) _returnToLogin();
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser ?? user;

      if (!mounted) return;

      if (!refreshedUser.emailVerified) {
        await _showMessage(
          'Your email is not verified yet. Open the Gmail message, then try again.',
        );
        return;
      }

      await FirebaseAuth.instance.signOut();
      await _showMessage('Email verified. You can now log in.');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      final message = switch (e.code) {
        'user-disabled' => 'This account has been disabled.',
        'user-token-expired' ||
        'requires-recent-login' => 'Please log in again to check verification.',
        _ => 'Unable to check your verification status right now.',
      };
      await _showMessage(message);
    } catch (_) {
      await _showMessage('Unable to check your verification status right now.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showMessage(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        // The same envelope as the screen behind it.
        title: Row(
          children: [
            Image.asset(AppIcons.email, width: 24, height: 24),
            const SizedBox(width: 10),
            const Text('Verification'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _backToLogin() async {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sent = _hasSentVerificationEmail;
    final email = _emailController.text;

    return Scaffold(
      backgroundColor: colors.card,
      appBar: AppBar(
        backgroundColor: colors.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back to Log In',
          icon: Icon(Icons.arrow_back, color: colors.textBody),
          onPressed: _isLoading ? null : _backToLogin,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // What this step is about, at a glance.
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: colors.primaryTint,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Image.asset(AppIcons.email),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Check your email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  sent
                      ? 'We sent a verification link to'
                      : 'Send a verification link to',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: colors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  key: const Key('verification-email-address'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  sent
                      ? 'Open the link, then come back and tap the button '
                            'below.'
                      : 'Then open the link to finish setting up your '
                            'account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: colors.textMuted),
                ),
                if (_sendError != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _sendError!,
                    key: const Key('verification-email-error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: dangerColorOn(context),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 28),

                // The next step, as the one big button: send first, then
                // confirm once it is opened.
                ElevatedButton(
                  key: const Key('verification-main-button'),
                  onPressed: _isLoading
                      ? null
                      : sent
                      ? _checkVerification
                      : _cooldownSeconds > 0
                      ? null
                      : _sendVerificationEmail,
                  style: confirmButtonStyle(),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          sent
                              ? "I've verified my email"
                              : 'Send verification email',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                if (sent)
                  TextButton(
                    key: const Key('verification-resend'),
                    onPressed: _isLoading || _cooldownSeconds > 0
                        ? null
                        : _sendVerificationEmail,
                    child: Text(
                      _cooldownSeconds > 0
                          ? 'Resend in ${_formatCooldown()}'
                          : 'Resend email',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _isLoading ? null : _checkVerification,
                    child: const Text(
                      "I've already verified it",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 20),

                // Where it usually hides.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(AppIcons.idea, width: 18, height: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "Can't find it? Check your Spam or Promotions folder.",
                        style: TextStyle(fontSize: 13, color: colors.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading ? null : _backToLogin,
                  child: Text(
                    'Back to Log In',
                    style: TextStyle(
                      color: colors.textBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
