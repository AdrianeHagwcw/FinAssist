import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/user_profile_service.dart';
import 'financial_setup_screen.dart';
import 'package:testapp/screens/home_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class _SocialSignInCancelled implements Exception {
  const _SocialSignInCancelled();
}

class _SocialSignInException implements Exception {
  const _SocialSignInException(this.message);

  final String message;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  // =========================================================
  // EMAIL / PASSWORD LOGIN
  // =========================================================

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // ---------------------------------------------------------
    // CHECK EMPTY FIELDS
    // ---------------------------------------------------------

    if (email.isEmpty && password.isEmpty) {
      _showMessage('Please enter your email and password.');
      return;
    }

    if (email.isEmpty) {
      _showMessage('Please enter your email.');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Please enter your password.');
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

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // -------------------------------------------------------
      // LOGIN SUCCESSFUL
      // -------------------------------------------------------

      await _navigateAfterAuthentication();
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;

        case 'wrong-password':
          message = 'Incorrect password.';
          break;

        case 'invalid-credential':
          message = 'Incorrect email or password.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;

        case 'user-disabled':
          message = 'This account has been disabled.';
          break;

        case 'too-many-requests':
          message = 'Too many login attempts. Please try again later.';
          break;

        case 'network-request-failed':
          message = 'Network error. Please check your internet connection.';
          break;

        default:
          message = 'Login failed. Please try again.';
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
  // GOOGLE SIGN IN
  // =========================================================

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      const googleWebClientId =
          '708244412702-qafbtnlba2pelc94fveoudfm7059ptkj.apps.googleusercontent.com';
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: googleWebClientId,
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      // User cancelled Google login
      if (googleUser == null) {
        throw const _SocialSignInCancelled();
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw const _SocialSignInException(
          'Google did not return an ID token. Please check the Android OAuth configuration.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      await FirebaseAuth.instance.signInWithCredential(credential);

      await _navigateAfterAuthentication();
    } on _SocialSignInCancelled {
      _showMessage('Google sign-in was cancelled.');
    } on _SocialSignInException catch (e) {
      _showMessage(e.message);
    } on PlatformException catch (e) {
      _showMessage(
        'Google sign-in failed (${e.code}). ${e.message ?? 'Check your Google OAuth configuration.'}',
      );
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
  // FACEBOOK SIGN IN
  // =========================================================

  Future<void> _signInWithFacebook() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status == LoginStatus.cancelled) {
        throw const _SocialSignInCancelled();
      }

      if (result.status != LoginStatus.success) {
        throw _SocialSignInException(
          result.message ?? 'Facebook sign-in was not completed.',
        );
      }

      final AccessToken? accessToken = result.accessToken;

      if (accessToken == null) {
        throw const _SocialSignInException(
          'Facebook access token was not received.',
        );
      }

      // Create Firebase credential
      final OAuthCredential credential = FacebookAuthProvider.credential(
        accessToken.tokenString,
      );

      // Sign in to Firebase
      await FirebaseAuth.instance.signInWithCredential(credential);

      await _navigateAfterAuthentication();
    } on _SocialSignInCancelled {
      _showMessage('Facebook sign-in was cancelled.');
    } on _SocialSignInException catch (e) {
      _showMessage(e.message);
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Facebook sign-in failed.');
    } catch (e) {
      _showMessage('Facebook sign-in could not be completed.');
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
      final setupCompleted = await UserProfileService.isSetupCompleted();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => setupCompleted
              ? const HomeScreen()
              : const FinancialSetupScreen(),
        ),
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/icons/e621696b-4d3b-4ad5-972c-7c96ad3f6c71_removalai_preview.png',
                          width: 240,
                          height: 160,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Smart insights. Better financial future.',

                        textAlign: TextAlign.center,

                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 45),

                // =================================================
                // WELCOME
                // =================================================
                const Text(
                  'Welcome Back!',

                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF151515),
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Log in to continue to FinAssist',

                  style: TextStyle(fontSize: 15, color: Colors.grey),
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

                  enabled: !_isLoading,

                  decoration: InputDecoration(
                    hintText: 'Enter your password',

                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.grey,
                    ),

                    suffixIcon: IconButton(
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
                                builder: (context) =>
                                    const ForgotPasswordScreen(),
                              ),
                            );
                          },

                    child: const Text(
                      'Forgot Password?',

                      style: TextStyle(
                        color: Color(0xFF1976D2),
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
                    const Expanded(child: Divider(color: Color(0xFFDADADA))),

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

                    const Expanded(child: Divider(color: Color(0xFFDADADA))),
                  ],
                ),

                const SizedBox(height: 20),

                // =================================================
                // GOOGLE + FACEBOOK
                // =================================================
                Row(
                  children: [
                    // GOOGLE
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,

                        icon: const Icon(
                          Icons.g_mobiledata,
                          size: 28,
                          color: Colors.red,
                        ),

                        label: const Text(
                          'Google',

                          style: TextStyle(color: Colors.black87),
                        ),

                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),

                          side: const BorderSide(color: Color(0xFFDADADA)),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // FACEBOOK
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithFacebook,

                        icon: const Icon(
                          Icons.facebook,
                          color: Color(0xFF1877F2),
                        ),

                        label: const Text(
                          'Facebook',

                          style: TextStyle(color: Colors.black87),
                        ),

                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),

                          side: const BorderSide(color: Color(0xFFDADADA)),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // =================================================
                // SIGN UP
                // =================================================
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",

                      style: const TextStyle(color: Colors.grey, fontSize: 14),

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

                            child: const Text(
                              'Sign Up',

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
