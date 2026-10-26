import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/account_session.dart';
import '../services/saved_accounts.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/auth_errors.dart';
import '../utils/text_limits.dart';
import '../widgets/check_after_save.dart';
import '../widgets/export_transactions_tile.dart';
import '../widgets/light_dark_toggle.dart';
import '../widgets/switch_account_sheet.dart';
import 'login_screen.dart';
import 'reminders_screen.dart';
import 'categories_screen.dart';
import 'forgot_password_screen.dart';
import 'help_screen.dart';
import 'history_screen.dart';
import 'splash_screen.dart';
import 'wallets_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Waiting on Google during Switch account.
  bool _switching = false;

  // =========================================================
  // GET CURRENT FIREBASE USER
  // =========================================================

  User? get currentUser => _auth.currentUser;

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  void _security() {
    final passwordAccount =
        currentUser?.providerData.any((p) => p.providerId == 'password') ??
        false;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account security'),
        content: Text(
          passwordAccount
              ? 'Use a password-reset email to change your password. You will need access to ${_getUserEmail()}.'
              : 'You sign in through Google. Manage your password and sign-in protection in your Google account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (passwordAccount)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _open(ForgotPasswordScreen(initialEmail: _getUserEmail()));
              },
              child: const Text('Reset password'),
            ),
        ],
      ),
    );
  }

  // =========================================================
  // LOGOUT
  // =========================================================

  /// Asks before signing out, since unsent changes need a connection.
  /// [isDestructive] paints the confirm button red.
  Future<bool> _confirmSignOut({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: isDestructive
                ? dangerTextStyle(context)
                : confirmTextStyle(context),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  /// Lists the accounts used on this phone and asks only what the one picked
  /// needs: its password, or Google. This account stays signed in until the
  /// other one logs in, so backing out at any step changes nothing.
  Future<void> _switchAccount() async {
    final current = SavedAccount.of(currentUser);
    if (current == null || _switching) return;

    final saved = await SavedAccounts.load();
    if (!mounted) return;
    final choice = await showSwitchAccountSheet(
      context,
      current: current,
      saved: saved,
    );
    if (choice == null || !mounted) return;

    final account = choice.account;
    if (account == null) {
      _open(const LoginScreen(addingAccount: true));
      return;
    }

    var useGoogle = !account.usesPassword;
    if (account.usesPassword) {
      final step = await showAccountPasswordDialog(
        context,
        account: account,
        logIn: (password) => _logInWithPassword(account, password),
      );
      if (step == null) return;
      useGoogle = step == PasswordStep.useGoogle;
    }
    if (useGoogle && !await _logInWithGoogle(account)) return;

    if (!mounted) return;
    // Starts again as the other account: its email check, setup or home.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  Future<String?> _logInWithPassword(
    SavedAccount account,
    String password,
  ) async {
    try {
      await saveChangesBeforeSwitching();
      await _auth.signInWithEmailAndPassword(
        email: account.email,
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (error) {
      return signInProblem(error.code);
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  /// Signs straight into [account]'s Google account, or asks Google which
  /// one if it is no longer on this phone. False when it didn't happen.
  Future<bool> _logInWithGoogle(SavedAccount account) async {
    setState(() => _switching = true);
    var problem = 'Google sign-in could not be completed.';
    try {
      final credential = await googleCredential(email: account.email);
      await saveChangesBeforeSwitching();
      await _auth.signInWithCredential(credential);
      return true;
    } on GoogleSignInCancelled {
      return false;
    } on GoogleSignInFailed catch (error) {
      problem = error.message;
    } on PlatformException catch (error) {
      problem = googleSignInMessage(
        error.code,
        '${error.message} ${error.details}',
      );
    } on FirebaseAuthException catch (error) {
      problem = signInProblem(error.code, google: true);
    } catch (_) {
      // The message above.
    } finally {
      if (mounted) setState(() => _switching = false);
    }

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
    }
    return false;
  }

  Future<void> _confirmLogOut() async {
    final confirmed = await _confirmSignOut(
      title: 'Log out?',
      message:
          'You can log back in anytime. Connect to the internet first so '
          'your latest changes are saved.',
      confirmLabel: 'Log Out',
      isDestructive: true,
    );

    if (confirmed) await _logout();
  }

  Future<void> _logout() async {
    try {
      await signOutOfApp();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,

        MaterialPageRoute(builder: (context) => const LoginScreen()),

        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to log out. Please try again.')),
      );
    }
  }

  // =========================================================
  // GET USER INITIAL
  // =========================================================

  String _getUserInitial() {
    final user = currentUser;

    if (user == null) {
      return '?';
    }

    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim().substring(0, 1).toUpperCase();
    }

    if (user.email != null && user.email!.isNotEmpty) {
      return user.email!.substring(0, 1).toUpperCase();
    }

    return '?';
  }

  // =========================================================
  // GET USER NAME
  // =========================================================

  String _getUserName() {
    final user = currentUser;

    if (user == null) {
      return 'User';
    }

    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!;
    }

    return 'FinAssist User';
  }

  // =========================================================
  // GET USER EMAIL
  // =========================================================

  String _getUserEmail() {
    return currentUser?.email ?? 'No email available';
  }

  Future<void> _editAccountInformation() async {
    final user = currentUser;
    if (user == null) return;

    final message = await showDialog<String>(
      context: context,
      builder: (_) => _EditAccountInformationDialog(
        initialName: user.displayName ?? '',
        initialEmail: user.email ?? '',
        onSave: (name, email) => _saveAccountInformation(user, name, email),
      ),
    );

    if (message == null || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String> _saveAccountInformation(
    User user,
    String name,
    String email,
  ) async {
    var nameWasUpdated = false;
    try {
      if (name != (user.displayName ?? '').trim()) {
        await user.updateDisplayName(name);
        nameWasUpdated = true;
      }

      final emailChanged =
          email.toLowerCase() != (user.email ?? '').toLowerCase();
      if (emailChanged) {
        await user.verifyBeforeUpdateEmail(email);
      }

      if (emailChanged) {
        return nameWasUpdated
            ? 'Name updated. Check your new email address to finish changing it.'
            : 'Check your new email address to finish changing it.';
      }
      return 'Account information updated.';
    } on FirebaseAuthException catch (error) {
      final detail = switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'email-already-in-use' => 'That email is already linked to an account.',
        'requires-recent-login' =>
          'For security, sign out and sign back in before changing your email.',
        'network-request-failed' =>
          'Could not connect. Check your connection and try again.',
        _ => error.message ?? 'Could not update account information.',
      };
      return nameWasUpdated
          ? 'Name updated, but the email was not changed. $detail'
          : detail;
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final user = currentUser;
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,

      // =====================================================
      // APP BAR
      // =====================================================
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),

        foregroundColor: Colors.white,

        elevation: 0,

        // BACK TO HOME. Flutter's BackButton, so screen readers announce it.
        leading: const BackButton(),

        title: const Text(
          'Profile & Settings',

          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),

      // =====================================================
      // BODY
      // =====================================================
      body: user == null
          ? Center(
              child: Text(
                'No user is currently logged in.',

                style: TextStyle(
                  fontSize: 16,
                  color: context.appColors.textMuted,
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),

              child: Column(
                children: [
                  // =================================================
                  // PROFILE HEADER
                  // =================================================
                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.all(24),

                    decoration: BoxDecoration(
                      color: colors.card,

                      borderRadius: BorderRadius.circular(16),

                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),

                          blurRadius: 10,

                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),

                    child: Column(
                      children: [
                        // PROFILE AVATAR
                        CircleAvatar(
                          radius: 45,

                          backgroundColor: const Color(0xFF1976D2),

                          child: Text(
                            _getUserInitial(),

                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // NAME
                        Text(
                          _getUserName(),

                          textAlign: TextAlign.center,

                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // EMAIL
                        Text(
                          _getUserEmail(),

                          textAlign: TextAlign.center,

                          style: TextStyle(
                            fontSize: 14,
                            color: context.appColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // =================================================
                  // ACCOUNT INFORMATION
                  // =================================================
                  _buildSectionTitle('Account Information'),

                  const SizedBox(height: 10),

                  Material(
                    color: colors.card,

                    borderRadius: BorderRadius.circular(16),

                    clipBehavior: Clip.antiAlias,

                    child: Column(
                      children: [
                        _buildInfoTile(
                          iconAsset: 'assets/icons/icons8-user-96.png',
                          title: 'Full Name',
                          value: _getUserName(),
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildInfoTile(
                          iconAsset: 'assets/icons/icons8-email-96.png',
                          title: 'Email',
                          value: _getUserEmail(),
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildInfoTile(
                          iconAsset: 'assets/icons/icons8-verified-96.png',
                          title: 'Account Status',
                          value: 'Active',
                        ),

                        const Divider(height: 1, indent: 65),

                        ListTile(
                          key: const Key('edit-account-information'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          leading: Icon(
                            Icons.edit_outlined,
                            color: colors.primaryText,
                          ),
                          title: const Text(
                            'Edit account information',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: context.appColors.textMuted,
                          ),
                          onTap: _editAccountInformation,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // APPEARANCE
                  // =================================================
                  _buildSectionTitle('Appearance'),

                  const SizedBox(height: 10),

                  Material(
                    color: colors.card,

                    borderRadius: BorderRadius.circular(16),

                    clipBehavior: Clip.antiAlias,

                    child: const LightDarkToggle(),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // SETTINGS
                  // =================================================
                  _buildSectionTitle('Your money'),

                  const SizedBox(height: 10),
                  Material(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _buildActionTile(
                          iconAsset: 'assets/icons/icons8-calendar-96.png',
                          title: 'Cash Inflows',
                          onTap: () => _open(const HistoryScreen()),
                        ),
                        const Divider(height: 1, indent: 65),
                        _buildActionTile(
                          iconAsset: 'assets/icons/icons8-cat-shopping-96.png',
                          title: 'Manage expense categories',
                          onTap: () => _open(const CategoriesScreen()),
                        ),
                        const Divider(height: 1, indent: 65),
                        _buildActionTile(
                          iconAsset: 'assets/icons/icons8-wallet-96.png',
                          title: 'Manage wallets',
                          onTap: () => _open(const WalletsScreen()),
                        ),
                        const Divider(height: 1, indent: 65),
                        const ExportTransactionsTile(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  _buildSectionTitle('Reminders & support'),

                  const SizedBox(height: 10),

                  Material(
                    color: colors.card,

                    borderRadius: BorderRadius.circular(16),

                    clipBehavior: Clip.antiAlias,

                    child: Column(
                      children: [
                        _buildActionTile(
                          iconAsset: 'assets/icons/icons8-bell-96.png',
                          title: 'Reminders',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RemindersScreen(),
                            ),
                          ),
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildActionTile(
                          iconAsset: 'assets/icons/icons8-lock-96.png',

                          title: 'Security',

                          onTap: _security,
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildActionTile(
                          iconAsset: 'assets/icons/icons8-help-96.png',

                          title: 'Help & Support',

                          onTap: () => _open(const HelpScreen()),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // LOGOUT BUTTON
                  // =================================================
                  SizedBox(
                    width: double.infinity,
                    height: 52,

                    child: ElevatedButton(
                      onPressed: _switching ? null : _switchAccount,
                      style: openButtonStyle(),
                      child: _switching
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Switch Account',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 52,

                    child: ElevatedButton.icon(
                      onPressed: _confirmLogOut,
                      icon: const Icon(Icons.logout),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: dangerButtonStyle(),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  // =========================================================
  // SECTION TITLE
  // =========================================================

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,

      child: Text(
        title,

        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: context.appColors.textPrimary,
        ),
      ),
    );
  }

  // =========================================================
  // INFORMATION TILE
  // =========================================================

  Widget _buildInfoTile({
    required String iconAsset,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),

      leading: Container(
        width: 42,
        height: 42,

        decoration: BoxDecoration(
          color: context.appColors.primaryTint,

          borderRadius: BorderRadius.circular(10),
        ),

        padding: const EdgeInsets.all(9),

        child: Image.asset(iconAsset),
      ),

      title: Text(
        title,

        style: TextStyle(fontSize: 13, color: context.appColors.textMuted),
      ),

      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),

        child: Text(
          value,

          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.appColors.textPrimary,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // ACTION TILE
  // =========================================================

  Widget _buildActionTile({
    required String iconAsset,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),

      leading: Container(
        width: 42,
        height: 42,

        decoration: BoxDecoration(
          color: context.appColors.primaryTint,

          borderRadius: BorderRadius.circular(10),
        ),

        padding: const EdgeInsets.all(9),

        child: Image.asset(iconAsset),
      ),

      title: Text(
        title,

        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),

      trailing: Icon(Icons.chevron_right, color: context.appColors.textMuted),

      onTap: onTap,
    );
  }
}

class _EditAccountInformationDialog extends StatefulWidget {
  const _EditAccountInformationDialog({
    required this.initialName,
    required this.initialEmail,
    required this.onSave,
  });

  final String initialName;
  final String initialEmail;
  final Future<String> Function(String name, String email) onSave;

  @override
  State<_EditAccountInformationDialog> createState() =>
      _EditAccountInformationDialogState();
}

class _EditAccountInformationDialogState
    extends State<_EditAccountInformationDialog>
    with CheckAfterSave {
  late final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.initialName);
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!checkForm(_formKey)) return;
    setState(() => _saving = true);

    final message = await widget.onSave(
      cleanText(_nameController.text),
      _emailController.text.trim(),
    );
    if (!mounted) return;
    Navigator.pop(context, message);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit account information'),
    content: Form(
      key: _formKey,
      autovalidateMode: checkMode,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const Key('account-name-field'),
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            // The same rules as sign-up and setup, so a name cannot be
            // changed here into one they would refuse.
            inputFormatters: [
              personNameFormatter,
              const SafeTextFormatter(),
              LengthLimitingTextInputFormatter(maxPersonNameLength),
            ],
            decoration: const InputDecoration(labelText: 'Full Name'),
            validator: (value) =>
                personNameProblem(value ?? '', empty: 'Enter your name.'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('account-email-field'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(maxEmailLength),
            ],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty ||
                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Enter a valid email address.';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Changing your email sends a verification link to the new address.',
            style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}
