import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    this.email,
    this.user,
  });

  final String? email;
  final User? user;

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
    return widget.user ?? auth.currentUser ?? await auth.authStateChanges().first;
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

      if (!mounted) return;

      await _showMessage('Verification email sent. Please check your inbox.');
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
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFF1976D2)),
            SizedBox(width: 10),
            Text('Verification'),
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

    return Scaffold(
      backgroundColor: colors.card,
      appBar: AppBar(
        backgroundColor: colors.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textBody),
          onPressed: _isLoading ? null : _backToLogin,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: const AppLogo(
                          width: 180,
                          height: 120,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Verify your email',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1976D2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Please confirm your email address before continuing.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Email',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  readOnly: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Colors.grey,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF1976D2),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                if (_sendError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _sendError!,
                    key: const Key('verification-email-error'),
                    style: TextStyle(
                      color: dangerColorOn(context),
                      fontSize: 13,
                    ),
                  ),
                ] else if (_hasSentVerificationEmail) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Verification email sent. Open the link in your inbox to continue.',
                    key: Key('verification-email-sent'),
                    style: TextStyle(color: Color(0xFF2E7D32), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _cooldownSeconds > 0)
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
                            _cooldownSeconds > 0
                                ? 'Resend in ${_formatCooldown()}'
                                : _hasSentVerificationEmail
                                ? 'Resend verification email'
                                : 'Send verification email',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _checkVerification,
                    child: Text(
                      'I have verified my email',
                      style: TextStyle(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _backToLogin,
                    child: Text(
                      'Back to login',
                      style: TextStyle(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
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
