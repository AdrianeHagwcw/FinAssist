import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/user_profile_service.dart';
import 'financial_setup_screen.dart';
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
      _showMessage('Please enter your name.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK EMAIL
    // ---------------------------------------------------------

    if (email.isEmpty) {
      _showMessage('Please enter your email.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK PASSWORD
    // ---------------------------------------------------------

    if (password.isEmpty) {
      _showMessage('Please enter a password.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK PASSWORD LENGTH
    // ---------------------------------------------------------

    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK CONFIRM PASSWORD
    // ---------------------------------------------------------

    if (confirmPassword.isEmpty) {
      _showMessage('Please confirm your password.');
      return;
    }

    // ---------------------------------------------------------
    // CHECK IF PASSWORDS MATCH
    // ---------------------------------------------------------

    if (password != confirmPassword) {
      _showMessage('Passwords do not match.');
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

      if (!mounted) return;

      // -------------------------------------------------------
      // SHOW SUCCESS MESSAGE
      // -------------------------------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully!')),
      );

      // -------------------------------------------------------
      // GO TO HOME SCREEN
      // -------------------------------------------------------

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const FinancialSetupScreen()),
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

        default:
          message = e.message ?? 'Registration failed. Please try again.';
      }

      _showMessage(message);
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

  // =========================================================
  // SHOW MESSAGE
  // =========================================================

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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

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
                      Container(
                        width: 75,
                        height: 75,

                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2),
                          borderRadius: BorderRadius.circular(22),
                        ),

                        child: const Icon(
                          Icons.trending_up,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),

                      const SizedBox(height: 18),

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
                const Text(
                  'Create Account',

                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF151515),
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

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
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

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
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

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
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

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),

                      borderSide: const BorderSide(color: Color(0xFFDADADA)),
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

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),

                      foregroundColor: Colors.white,

                      disabledBackgroundColor: Colors.grey.shade400,

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

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
                            onTap: _isLoading
                                ? null
                                : () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const LoginScreen(),
                                      ),
                                    );
                                  },

                            child: const Text(
                              'Log In',

                              style: TextStyle(
                                color: Color(0xFF1976D2),
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
