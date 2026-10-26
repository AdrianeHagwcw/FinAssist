import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/account_session.dart';
import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/auth_errors.dart';
import '../utils/text_limits.dart';
import '../widgets/app_logo.dart';
import 'email_verification_screen.dart';
import 'financial_setup_screen.dart';
import 'forgot_password_screen.dart';
import 'main_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialEmail, this.addingAccount = false});

  final String? initialEmail;

  /// Opened from Switch account while another account is still signed in.
  /// Back returns to it; logging in here replaces it.
  final bool addingAccount;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // =========================================================
  // CONTROLLERS
  // =========================================================

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  // =========================================================
  // VARIABLES
  // =========================================================

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;

  /// Set by the first Log In tap. From then on the fields are checked as
  /// they are typed, so a message goes as soon as its field is right.
  bool _triedToLogIn = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
  }

  // =========================================================
  // EMAIL / PASSWORD LOGIN
  // =========================================================

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // ---------------------------------------------------------
    // CHECK EMPTY FIELDS
    // ---------------------------------------------------------

    final emailError = _emailProblem(email);
    final passwordError = _passwordProblem(password);

    setState(() {
      _triedToLogIn = true;
      _emailError = null;
      _passwordError = null;
    });

    if (emailError != null || passwordError != null) {
      setState(() {
        _emailError = emailError;
        _passwordError = passwordError;
      });
      return;
    }

    // ---------------------------------------------------------
    // START LOADING
    // ---------------------------------------------------------

    setState(() {
      _isLoading = true;
    });

    try {
      // -------------------------------------------------------
      // FIREBASE LOGIN
      // -------------------------------------------------------

      await saveChangesBeforeSwitching();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // -------------------------------------------------------
      // LOGIN SUCCESSFUL
      // -------------------------------------------------------

      await _navigateAfterAuthentication();
    } on FirebaseAuthException catch (e) {
      String message = '';

      switch (e.code) {
        case 'user-not-found':
          _setFieldErrors(email: 'No account found with this email.');
          break;

        case 'wrong-password':
          _setFieldErrors(password: 'Incorrect password.');
          break;

        case 'invalid-credential':
          _setFieldErrors(
            email: _wrongEmailOrPassword,
            password: _wrongEmailOrPassword,
          );
          break;

        case 'invalid-email':
          _setFieldErrors(email: 'Please enter a valid email address.');
          break;

        case 'user-disabled':
          message = 'This account has been disabled.';
          break;

        case 'network-request-failed':
          message = 'Network error. Please check your internet connection.';
          break;

        case 'email-not-verified':
          message = 'Please verify your email before signing in.';
          break;

        default:
          message = 'Login failed. Please try again.';
      }

      if (e.code != 'user-not-found' &&
          e.code != 'wrong-password' &&
          e.code != 'invalid-credential' &&
          e.code != 'invalid-email') {
        _showMessage(message);
      }
    } catch (e) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _validEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  static const _wrongEmailOrPassword = 'Incorrect email or password.';

  String? _emailProblem(String email) => email.isEmpty
      ? 'Please enter your email.'
      : !_validEmail(email)
      ? 'Enter a valid email address.'
      : null;

  String? _passwordProblem(String password) =>
      password.isEmpty ? 'Please enter your password.' : null;

  Widget? _buildCharacterCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) {
    if (maxLength == null || currentLength < maxLength) {
      return null;
    }
    return Text('$currentLength/$maxLength');
  }

  void _setFieldErrors({String? email, String? password}) {
    if (!mounted) return;
    setState(() {
      _emailError = email;
      _passwordError = password;
    });
  }

  // A changed field is checked again as it is typed. What the server said
  // about the last try can't be checked here, so it goes once the field is
  // changed, and "Incorrect email or password" goes from both, since
  // either one may have been the wrong one.
  void _onEmailChanged(String value) {
    if (!_triedToLogIn) return;
    setState(() {
      _emailError = _emailProblem(value.trim());
      if (_passwordError == _wrongEmailOrPassword) _passwordError = null;
    });
  }

  void _onPasswordChanged(String value) {
    if (!_triedToLogIn) return;
    setState(() {
      _passwordError = _passwordProblem(value);
      if (_emailError == _wrongEmailOrPassword) _emailError = null;
    });
  }

  // =========================================================
  // GOOGLE SIGN IN
  // =========================================================

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Google's picker asks every time, so any Google account can be used.
      final credential = await googleCredential();

      await saveChangesBeforeSwitching();
      await FirebaseAuth.instance.signInWithCredential(credential);

      await _navigateAfterAuthentication();
    } on GoogleSignInCancelled {
      _showMessage('Google sign-in was cancelled.');
    } on GoogleSignInFailed catch (e) {
      _showMessage(e.message);
    } on PlatformException catch (e) {
      _showMessage(googleSignInMessage(e.code, '${e.message} ${e.details}'));
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Google sign-in failed.');
    } catch (e) {
      _showMessage('Google sign-in could not be completed.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // =========================================================
  // SHOW MESSAGE
  // =========================================================

  Future<void> _navigateAfterAuthentication() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser ?? user;
        if (!refreshedUser.emailVerified) {
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => EmailVerificationScreen(
                email: refreshedUser.email,
                user: refreshedUser,
              ),
            ),
            (route) => false,
          );
          return;
        }
      }

      final setupCompleted = await UserProfileService.isSetupCompleted();

      if (!mounted) return;

      // Clears everything below, which after Add another account is the
      // account signed in before.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) =>
              setupCompleted ? const MainShell() : const FinancialSetupScreen(),
        ),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          'We could not load your financial profile. Please try again.',
        );
      }
      await FirebaseAuth.instance.signOut();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.card,

      appBar: widget.addingAccount
          ? AppBar(
              backgroundColor: colors.card,
              foregroundColor: colors.textPrimary,
              elevation: 0,
              leading: const BackButton(),
            )
          : null,

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                // =================================================
                // FINASSIST LOGO
                // =================================================
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: const AppLogo(
                          width: 240,
                          height: 160,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Smart insights. Better financial future.',

                        textAlign: TextAlign.center,

                        style: TextStyle(
                          fontSize: 14,
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 45),

                // =================================================
                // WELCOME
                // =================================================
                Text(
                  widget.addingAccount ? 'Add an account' : 'Welcome Back!',

                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  widget.addingAccount
                      ? 'Log in with another account'
                      : 'Log in to continue to FinAssist',

                  style: TextStyle(
                    fontSize: 15,
                    color: context.appColors.textMuted,
                  ),
                ),

                const SizedBox(height: 30),

                // =================================================
                // EMAIL LABEL
                // =================================================
                const Text(
                  'Email',

                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                // =================================================
                // EMAIL FIELD
                // =================================================
                TextField(
                  controller: _emailController,

                  keyboardType: TextInputType.emailAddress,

                  enabled: !_isLoading,

                  onChanged: _onEmailChanged,

                  decoration: InputDecoration(
                    hintText: 'Enter your email',
                    errorText: _emailError,

                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: context.appColors.textMuted,
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

                  maxLength: maxEmailLength,
                  buildCounter: _buildCharacterCounter,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    LengthLimitingTextInputFormatter(maxEmailLength),
                  ],
                ),

                const SizedBox(height: 20),

                // =================================================
                // PASSWORD LABEL
                // =================================================
                const Text(
                  'Password',

                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                // =================================================
                // PASSWORD FIELD
                // =================================================
                TextField(
                  controller: _passwordController,

                  obscureText: _obscurePassword,

                  // With the email filled in, only the password is left.
                  autofocus: widget.initialEmail?.isNotEmpty ?? false,

                  enabled: !_isLoading,

                  onChanged: _onPasswordChanged,

                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    errorText: _passwordError,

                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: context.appColors.textMuted,
                    ),

                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),

                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
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

                  maxLength: maxPasswordLength,
                  buildCounter: _buildCharacterCounter,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(maxPasswordLength),
                  ],
                ),

                const SizedBox(height: 10),

                // =================================================
                // FORGOT PASSWORD
                // =================================================
                Align(
                  alignment: Alignment.centerRight,

                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ForgotPasswordScreen(
                                  initialEmail: _emailController.text,
                                ),
                              ),
                            );
                          },

                    child: Text(
                      'Forgot Password?',

                      style: TextStyle(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // =================================================
                // LOGIN BUTTON
                // =================================================
                SizedBox(
                  width: double.infinity,
                  height: 52,

                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,

                    // Blue like the rest of the app; green is kept for Sign Up,
                    // which creates something new.
                    style: openButtonStyle(),

                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,

                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Log In',

                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 25),

                // =================================================
                // OR CONTINUE WITH
                // =================================================
                Row(
                  children: [
                    Expanded(child: Divider(color: colors.inputBorder)),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),

                      child: Text(
                        'or continue with',

                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ),

                    Expanded(child: Divider(color: colors.inputBorder)),
                  ],
                ),

                const SizedBox(height: 20),

                // =================================================
                // GOOGLE
                // =================================================
                SizedBox(
                  width: double.infinity,

                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,

                    icon: const Icon(
                      Icons.g_mobiledata,
                      size: 28,
                      color: Colors.red,
                    ),

                    label: Text(
                      'Google',

                      style: TextStyle(color: colors.textBody),
                    ),

                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),

                      side: BorderSide(color: colors.inputBorder),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // =================================================
                // SIGN UP
                // =================================================
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",

                      style: TextStyle(
                        color: context.appColors.textMuted,
                        fontSize: 14,
                      ),

                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: _isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const RegisterScreen(),
                                      ),
                                    );
                                  },

                            child: Text(
                              'Sign Up',

                              style: TextStyle(
                                color: colors.primaryText,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
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
