import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/account_session.dart';
import '../services/saved_accounts.dart';
import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/auth_errors.dart';
import '../utils/text_limits.dart';
import '../widgets/auth_parts.dart';
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

  final _passwordFocus = FocusNode();

  /// Accounts used on this phone before, offered first so a returning user
  /// taps one instead of typing. None when adding another account, which is
  /// for one not listed.
  List<SavedAccount> _savedAccounts = const [];

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
    if (!widget.addingAccount) _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final saved = await SavedAccounts.load();
    if (!mounted || saved.isEmpty) return;
    setState(() => _savedAccounts = saved.take(3).toList());
  }

  /// Create Account comes back with an email that already has an account,
  /// to log in with instead.
  Future<void> _openCreateAccount() async {
    final email = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
    if (email == null || !mounted) return;
    setState(() {
      _emailController.text = email;
      _emailError = null;
      _passwordError = null;
    });
    _passwordFocus.requestFocus();
  }

  /// A saved account: Google signs straight into it; for a password, the
  /// email is filled in and only the password is left.
  void _continueAs(SavedAccount account) {
    if (_isLoading) return;
    if (!account.usesPassword) {
      _signInWithGoogle(email: account.email);
      return;
    }
    setState(() {
      _emailController.text = account.email;
      _emailError = null;
      _passwordError = null;
    });
    _passwordFocus.requestFocus();
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

      TextInput.finishAutofillContext();
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

  Future<void> _signInWithGoogle({String? email}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Google's picker asks every time, so any Google account can be used.
      final credential = await googleCredential(email: email);

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
    _passwordFocus.dispose();

    super.dispose();
  }

  // =========================================================
  // UI
  // =========================================================

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final returning = _savedAccounts.isNotEmpty;
    final heading = widget.addingAccount
        ? 'Add an account'
        : returning
        ? 'Welcome back'
        : 'Welcome to FinAssist';
    final subheading = widget.addingAccount
        ? 'Log in with another account'
        : returning
        ? 'Choose your account, or log in with another.'
        : 'Log in to continue.';

    // A calm white page: the logo is already a strong blue shape, so blue
    // is kept for what to tap.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
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
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeader(),
                  const SizedBox(height: 36),
                  _form(colors, heading, subheading),
                  const SizedBox(height: 28),
                  Text(
                    'New to FinAssist?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: colors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    key: const Key('create-account'),
                    onPressed: _isLoading ? null : _openCreateAccount,
                    // Green: it makes something new.
                    style: confirmButtonStyle(height: 50),
                    child: const Text(
                      'Create an account',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(AppColors colors, String heading, String subheading) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            heading,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subheading,
            style: TextStyle(fontSize: 14, color: colors.textMuted),
          ),
          const SizedBox(height: 20),

          // =============================================
          // ACCOUNTS USED ON THIS PHONE
          // =============================================
          if (_savedAccounts.isNotEmpty) ...[
            for (final account in _savedAccounts) ...[
              _savedAccountTile(colors, account),
              const SizedBox(height: 10),
            ],
            const OrDivider('or use another account'),
            const SizedBox(height: 16),
          ],

          // =============================================
          // EMAIL
          // =============================================
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            enabled: !_isLoading,
            onChanged: _onEmailChanged,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _emailError,
              prefixIcon: const FieldIcon(AppIcons.email),
              border: _border(colors.inputBorder),
              enabledBorder: _border(colors.inputBorder),
              focusedBorder: _border(appPrimaryBlue, width: 2),
            ),
            maxLength: maxEmailLength,
            buildCounter: _buildCharacterCounter,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(maxEmailLength),
            ],
          ),
          const SizedBox(height: 14),

          // =============================================
          // PASSWORD
          // =============================================
          TextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            // With the email filled in, only the password is left.
            autofocus: widget.initialEmail?.isNotEmpty ?? false,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            enabled: !_isLoading,
            onChanged: _onPasswordChanged,
            onSubmitted: (_) => _login(),
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _passwordError,
              prefixIcon: const FieldIcon(AppIcons.lock),
              suffixIcon: PasswordEye(
                hidden: _obscurePassword,
                onPressed: _isLoading
                    ? null
                    : () =>
                          setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: _border(colors.inputBorder),
              enabledBorder: _border(colors.inputBorder),
              focusedBorder: _border(appPrimaryBlue, width: 2),
            ),
            maxLength: maxPasswordLength,
            buildCounter: _buildCharacterCounter,
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxPasswordLength),
            ],
          ),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ForgotPasswordScreen(
                          initialEmail: _emailController.text,
                        ),
                      ),
                    ),
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // =============================================
          // LOG IN: blue, like the rest of the app; green is for
          // creating an account.
          // =============================================
          ElevatedButton(
            onPressed: _isLoading ? null : _login,
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 12),

          // =============================================
          // GOOGLE
          // =============================================
          GoogleButton(onPressed: _isLoading ? null : _signInWithGoogle),
        ],
      ),
    );
  }

  Widget _savedAccountTile(AppColors colors, SavedAccount account) {
    final googleOnly = !account.usesPassword;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('continue-as-${account.email}'),
        onTap: () => _continueAs(account),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.inputBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: appPrimaryBlue,
                child: Text(
                  account.initial,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (account.name.isNotEmpty)
                      Text(
                        account.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: colors.textMuted),
                      ),
                  ],
                ),
              ),
              // How it signs in, so a tap does what the person expects.
              if (googleOnly)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: GoogleLogo(),
                ),
              Icon(Icons.chevron_right, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
