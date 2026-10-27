import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/text_limits.dart';
import '../widgets/auth_parts.dart';
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

  /// The email is someone's account already: offer to log in instead.
  bool _emailInUse = false;

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

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
    final passwordError = password.isEmpty
        ? 'This field is required.'
        : _passwordStillNeeds(password);
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
        confirmPasswordError == null;
  }

  Future<void> _register() async {
    final name = cleanText(_nameController.text);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    _triedToRegister = true;
    setState(() {
      _formError = null;
      _emailInUse = false;
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

      // The phone can offer to save the new password.
      TextInput.finishAutofillContext();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => EmailVerificationScreen(
            email: email,
            user: user,
            sendOnOpen: true,
          ),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'An account already uses this email.';
          _emailInUse = true;
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

      // Nothing to save: no account was made with this password.
      TextInput.finishAutofillContext(shouldSave: false);
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
    MapEntry('at least 6 characters', password.length >= 6),
    MapEntry('a capital letter', RegExp(r'[A-Z]').hasMatch(password)),
    MapEntry('a small letter', RegExp(r'[a-z]').hasMatch(password)),
    MapEntry('a number', RegExp(r'[0-9]').hasMatch(password)),
    MapEntry('a symbol', RegExp(r'[^A-Za-z0-9\s]').hasMatch(password)),
  ];

  /// What the password still needs, in one line, or null when it has it all:
  /// "Still needed: a capital letter and a symbol."
  String? _passwordStillNeeds(String password) {
    final missing = [
      for (final rule in _passwordRequirementsFor(password))
        if (!rule.value) rule.key,
    ];
    if (missing.isEmpty) return null;
    final list = missing.length == 1
        ? missing.single
        : '${missing.take(missing.length - 1).join(', ')} and ${missing.last}';
    return 'Still needed: $list.';
  }

  void _onFieldChanged(String field) {
    setState(() {
      _formError = null;
      _emailInUse = false;
    });
    if (_triedToRegister) _checkFields();
  }

  /// To Log In with the email filled in, when it already has an account.
  void _logInInstead() {
    final email = _emailController.text.trim();
    if (Navigator.canPop(context)) {
      Navigator.pop(context, email);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen(initialEmail: email)),
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
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();

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

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  /// One label, inside the box, that moves up as you type.
  InputDecoration _field({
    required String label,
    required String icon,
    String? errorText,
    String? helperText,
    Widget? helper,
    Widget? suffix,
  }) {
    final colors = context.appColors;
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      errorMaxLines: 2,
      helperText: helperText,
      helperMaxLines: 2,
      helperStyle: TextStyle(fontSize: 12, color: colors.textMuted),
      helper: helper,
      prefixIcon: FieldIcon(icon),
      suffixIcon: suffix,
      border: _border(colors.inputBorder),
      enabledBorder: _border(colors.inputBorder),
      focusedBorder: _border(appPrimaryBlue, width: 2),
      errorBorder: _border(dangerColorOn(context), width: 1.5),
      focusedErrorBorder: _border(dangerColorOn(context), width: 2),
    );
  }

  Widget _eye(bool hidden, VoidCallback toggle, String what) => PasswordEye(
    hidden: hidden,
    onPressed: _isLoading ? null : toggle,
    what: what,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final passwordsMatch =
        _confirmPasswordController.text.isNotEmpty &&
        _confirmPasswordController.text == _passwordController.text;

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
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeader(),
                  const SizedBox(height: 32),
                  Text(
                    'Create your account',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "It's free and takes about a minute.",
                    style: TextStyle(fontSize: 14, color: colors.textMuted),
                  ),
                  const SizedBox(height: 20),

                  // ===========================================
                  // NAME
                  // ===========================================
                  TextField(
                    controller: _nameController,
                    enabled: !_isLoading,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    onSubmitted: (_) => _emailFocus.requestFocus(),
                    maxLength: maxPersonNameLength,
                    buildCounter: _buildCharacterCounter,
                    // Letters from any language, so Niño and Ma. Clara fit.
                    inputFormatters: [
                      personNameFormatter,
                      const SafeTextFormatter(),
                      LengthLimitingTextInputFormatter(maxPersonNameLength),
                    ],
                    onChanged: (_) => _onFieldChanged('name'),
                    decoration: _field(
                      label: 'Full name',
                      icon: AppIcons.person,
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ===========================================
                  // EMAIL
                  // ===========================================
                  TextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                    maxLength: maxEmailLength,
                    buildCounter: _buildCharacterCounter,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      LengthLimitingTextInputFormatter(maxEmailLength),
                    ],
                    onChanged: (_) => _onFieldChanged('email'),
                    decoration: _field(
                      label: 'Email',
                      icon: AppIcons.email,
                      errorText: _emailError,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ===========================================
                  // PASSWORD, with its rules ticked as they are met
                  // ===========================================
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    enabled: !_isLoading,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    // The phone can suggest a strong one and remember it.
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _confirmFocus.requestFocus(),
                    maxLength: maxPasswordLength,
                    buildCounter: _buildCharacterCounter,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(maxPasswordLength),
                    ],
                    onChanged: (_) => _onFieldChanged('password'),
                    decoration: _field(
                      label: 'Password',
                      icon: AppIcons.lock,
                      errorText: _passwordError,
                      helperText:
                          'At least 6 characters, with a capital letter, a '
                          'small letter, a number and a symbol like ! or @.',
                      suffix: _eye(
                        _obscurePassword,
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        'password',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ===========================================
                  // CONFIRM PASSWORD
                  // ===========================================
                  TextField(
                    controller: _confirmPasswordController,
                    focusNode: _confirmFocus,
                    enabled: !_isLoading,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _register(),
                    maxLength: maxPasswordLength,
                    buildCounter: _buildCharacterCounter,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(maxPasswordLength),
                    ],
                    onChanged: (_) => _onFieldChanged('confirmPassword'),
                    decoration: _field(
                      label: 'Confirm password',
                      icon: AppIcons.lock,
                      errorText: _confirmPasswordError,
                      helper: passwordsMatch && _confirmPasswordError == null
                          ? Row(
                              key: const Key('passwords-match'),
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: confirmColorOn(context),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Passwords match',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: confirmColorOn(context),
                                  ),
                                ),
                              ],
                            )
                          : null,
                      suffix: _eye(
                        _obscureConfirmPassword,
                        () => setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        ),
                        'confirmed password',
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ===========================================
                  // WHAT WENT WRONG, with the way through
                  // ===========================================
                  if (_formError != null) ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: dangerColorOn(context).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 20,
                            color: dangerColorOn(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _formError!,
                              key: const Key('register-form-error'),
                              style: TextStyle(
                                color: dangerColorOn(context),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (_emailInUse)
                            TextButton(
                              key: const Key('log-in-instead'),
                              onPressed: _isLoading ? null : _logInInstead,
                              child: const Text('Log in instead'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ===========================================
                  // CREATE ACCOUNT: green, it makes something new
                  // ===========================================
                  ElevatedButton(
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
                  const SizedBox(height: 20),

                  // ===========================================
                  // ALREADY HAVE AN ACCOUNT
                  // ===========================================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: TextStyle(color: colors.textMuted, fontSize: 14),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _backToLogin,
                        child: Text(
                          'Log In',
                          style: TextStyle(
                            color: colors.primaryText,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
