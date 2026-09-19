import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // =========================================================
  // CONTROLLERS
  // =========================================================

  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // =========================================================
  // VARIABLES
  // =========================================================

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  // =========================================================
  // REGISTER WITH FIREBASE
  // =========================================================

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // ---------------------------------------------------------
    // CHECK NAME
    // ---------------------------------------------------------

    if (name.isEmpty) {
      await _showMessage('Please enter your name.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK EMAIL
    // ---------------------------------------------------------

    if (email.isEmpty) {
      await _showMessage('Please enter your email.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK PASSWORD
    // ---------------------------------------------------------

    if (password.isEmpty) {
      await _showMessage('Please enter a password.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK PASSWORD LENGTH
    // ---------------------------------------------------------

    if (password.length < 6) {
      await _showMessage('Password must be at least 6 characters.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK CONFIRM PASSWORD
    // ---------------------------------------------------------

    if (confirmPassword.isEmpty) {
      await _showMessage('Please confirm your password.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK IF PASSWORDS MATCH
    // ---------------------------------------------------------

    if (password != confirmPassword) {
      await _showMessage('Passwords do not match.');
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
      // CREATE FIREBASE ACCOUNT
      // -------------------------------------------------------

      final UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      // -------------------------------------------------------
      // UPDATE USER DISPLAY NAME
      // -------------------------------------------------------

      await userCredential.user?.updateDisplayName(name);

      // Reload Firebase user information
      await userCredential.user?.reload();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('Registration did not return an authenticated user.');
      }

      await UserProfileService.createInitialProfile(user);

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // -------------------------------------------------------
      // SHOW SUCCESS MESSAGE
      // -------------------------------------------------------

      await _showMessage(
        'Account started. Please verify your email before signing in.',
      );
      if (!mounted) return;

      // -------------------------------------------------------
      // SHOW EMAIL VERIFICATION SCREEN TO GUIDE THE USER
      // -------------------------------------------------------

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => EmailVerificationScreen(email: email),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'An account already exists with this email.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;

        case 'weak-password':
          message = 'Your password is too weak. Use at least 6 characters.';
          break;

        case 'operation-not-allowed':
          message = 'Email/password registration is not enabled in Firebase.';
          break;

        case 'network-request-failed':
          message = 'Network error. Please check your internet connection.';
          break;

        case 'too-many-requests':
          message = 'Too many registration attempts. Please try again later.';
          break;

        default:
          message = e.message ?? 'Registration failed. Please try again.';
      }

      await _showMessage(message);
    } catch (e) {
      await _showMessage('Something went wrong. Please try again.');
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
            Text('Create account'),
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

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  // =========================================================
  // UI
  // =========================================================

  /// Back to the Log In screen this was opened from, or a fresh one if
  /// there is nothing to go back to.
  void _backToLogin() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
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
          tooltip: 'Back to Log In',
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
                // =================================================
                // FINASSIST LOGO
                // =================================================
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
                        'FinAssist',

                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1976D2),
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Smart insights. Better financial future.',

                        textAlign: TextAlign.center,

                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // =================================================
                // CREATE ACCOUNT
                // =================================================
                Text(
                  'Create Account',

                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Create your account to get started with FinAssist',

                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),

                const SizedBox(height: 30),

                // =================================================
                // NAME
                // =================================================
                const Text(
                  'Full Name',

                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: _nameController,

                  enabled: !_isLoading,

                  textCapitalization: TextCapitalization.words,

                  decoration: InputDecoration(
                    hintText: 'Enter your full name',

                    prefixIcon: const Icon(
                      Icons.person_outline,
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

                const SizedBox(height: 20),

                // =================================================
                // EMAIL
                // =================================================
                const Text(
                  'Email',

                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: _emailController,

                  enabled: !_isLoading,

                  keyboardType: TextInputType.emailAddress,

                  decoration: InputDecoration(
                    hintText: 'Enter your email',

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

                const SizedBox(height: 20),

                // =================================================
                // PASSWORD
                // =================================================
                const Text(
                  'Password',

                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: _passwordController,

                  enabled: !_isLoading,

                  obscureText: _obscurePassword,

                  decoration: InputDecoration(
                    hintText: 'Create a password',

                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.grey,
                    ),

                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },

                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
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

                const SizedBox(height: 20),

                // =================================================
                // CONFIRM PASSWORD
                // =================================================
                const Text(
                  'Confirm Password',

                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: _confirmPasswordController,

                  enabled: !_isLoading,

                  obscureText: _obscureConfirmPassword,

                  decoration: InputDecoration(
                    hintText: 'Confirm your password',

                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.grey,
                    ),

                    suffixIcon: IconButton(
                      tooltip: _obscureConfirmPassword
                          ? 'Show confirmed password'
                          : 'Hide confirmed password',
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },

                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
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

                const SizedBox(height: 30),

                // =================================================
                // REGISTER BUTTON
                // =================================================
                SizedBox(
                  width: double.infinity,
                  height: 52,

                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,

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
                        : const Text(
                            'Create Account',

                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 25),

                // =================================================
                // ALREADY HAVE ACCOUNT
                // =================================================
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: 'Already have an account? ',

                      style: const TextStyle(color: Colors.grey, fontSize: 14),

                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: _isLoading ? null : _backToLogin,

                            child: Text(
                              'Log In',

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
