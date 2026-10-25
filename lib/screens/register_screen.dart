import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/text_limits.dart';
import '../widgets/app_logo.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _formError;
  bool _showPasswordRequirements = false;

  /// Set by the first Create Account tap. From then on every field is
  /// checked as it is typed, so a message goes as soon as its field is right.
  bool _triedToRegister = false;

  // =========================================================
  // REGISTER WITH FIREBASE
  // =========================================================

  /// Shows what is wrong with each field, or nothing where it is right.
  /// Returns whether all of them are right.
  bool _checkFields() {
    final name = cleanText(_nameController.text);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final nameError = personNameProblem(name, empty: 'This field is required.');
    final emailError = email.isEmpty
        ? 'This field is required.'
        : !_validEmail(email)
        ? 'Enter a valid email address.'
        : null;
    final passwordError = password.isEmpty ? 'This field is required.' : null;
    final passwordMeetsPolicy = _passwordRequirementsFor(
      password,
    ).every((requirement) => requirement.value);
    final confirmPasswordError = confirmPassword.isEmpty
        ? 'This field is required.'
        : password != confirmPassword
        ? 'Passwords do not match.'
        : null;

    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmPasswordError = confirmPasswordError;
    });

    return nameError == null &&
        emailError == null &&
        passwordError == null &&
        passwordMeetsPolicy &&
        confirmPasswordError == null;
  }

  Future<void> _register() async {
    final name = cleanText(_nameController.text);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    _triedToRegister = true;
    setState(() {
      _formError = null;
      _showPasswordRequirements = password.isNotEmpty;
    });
    if (!_checkFields()) return;

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
      // SHOW EMAIL VERIFICATION SCREEN TO GUIDE THE USER
      // -------------------------------------------------------

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) =>
              EmailVerificationScreen(email: email, user: user),
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

      if (mounted) setState(() => _formError = message);
    } catch (e) {
      if (mounted) {
        setState(() => _formError = 'Something went wrong. Please try again.');
      }
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

  List<MapEntry<String, bool>> _passwordRequirementsFor(String password) => [
    MapEntry('At least 6 characters', password.length >= 6),
    MapEntry(
      'Require uppercase character',
      RegExp(r'[A-Z]').hasMatch(password),
    ),
    MapEntry(
      'Require lowercase character',
      RegExp(r'[a-z]').hasMatch(password),
    ),
    MapEntry(
      'Require special character',
      RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
    ),
    MapEntry('Require numeric character', RegExp(r'[0-9]').hasMatch(password)),
  ];

  void _onFieldChanged(String field) {
    setState(() {
      _formError = null;
      if (field == 'password') _showPasswordRequirements = true;
    });
    if (_triedToRegister) _checkFields();
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

                Text(
                  'Create your account to get started with FinAssist',

                  style: TextStyle(
                    fontSize: 15,
                    color: context.appColors.textMuted,
                  ),
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

                  maxLength: maxPersonNameLength,
                  buildCounter: _buildCharacterCounter,
                  // Letters from any language, so Niño and Ma. Clara fit.
                  inputFormatters: [
                    personNameFormatter,
                    const SafeTextFormatter(),
                    LengthLimitingTextInputFormatter(maxPersonNameLength),
                  ],

                  onChanged: (_) => _onFieldChanged('name'),

                  decoration: InputDecoration(
                    hintText: 'Enter your full name',
                    errorText: _nameError,

                    prefixIcon: Icon(
                      Icons.person_outline,
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
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
                        width: 1.5,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
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

                  maxLength: maxEmailLength,
                  buildCounter: _buildCharacterCounter,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    LengthLimitingTextInputFormatter(maxEmailLength),
                  ],

                  onChanged: (_) => _onFieldChanged('email'),

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
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
                        width: 1.5,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
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

                const SizedBox(height: 6),
                Text(
                  'Your password is used to sign in. It is not saved in your '
                  'financial records or shown to other users.',
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: _passwordController,

                  enabled: !_isLoading,

                  obscureText: _obscurePassword,

                  maxLength: maxPasswordLength,
                  buildCounter: _buildCharacterCounter,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(maxPasswordLength),
                  ],

                  onChanged: (_) => _onFieldChanged('password'),

                  decoration: InputDecoration(
                    hintText: 'Create a password',
                    error: _passwordError != null
                        ? Text(
                            _passwordError!,
                            style: TextStyle(color: dangerColorOn(context)),
                          )
                        : _showPasswordRequirements &&
                              _passwordRequirementsFor(
                                _passwordController.text,
                              ).any((requirement) => !requirement.value)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:
                                _passwordRequirementsFor(
                                      _passwordController.text,
                                    )
                                    .where((requirement) => !requirement.value)
                                    .map((requirement) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          requirement.key,
                                          style: TextStyle(
                                            color: dangerColorOn(context),
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                          )
                        : null,

                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: context.appColors.textMuted,
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
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
                        width: 1.5,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
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

                  maxLength: maxPasswordLength,
                  buildCounter: _buildCharacterCounter,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(maxPasswordLength),
                  ],

                  onChanged: (_) => _onFieldChanged('confirmPassword'),

                  decoration: InputDecoration(
                    hintText: 'Confirm your password',
                    errorText: _confirmPasswordError,

                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: context.appColors.textMuted,
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
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
                        width: 1.5,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: dangerColorOn(context),
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

                if (_formError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _formError!,
                    key: const Key('register-form-error'),
                    style: TextStyle(
                      color: dangerColorOn(context),
                      fontSize: 13,
                    ),
                  ),
                ],

                const SizedBox(height: 25),

                // =================================================
                // ALREADY HAVE ACCOUNT
                // =================================================
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: 'Already have an account? ',

                      style: TextStyle(
                        color: context.appColors.textMuted,
                        fontSize: 14,
                      ),

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
