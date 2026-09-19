import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/light_dark_toggle.dart';
import 'login_screen.dart';
import 'reminders_screen.dart';
import 'categories_screen.dart';
import 'financial_preferences_screen.dart';
import 'forgot_password_screen.dart';
import 'help_screen.dart';
import 'history_screen.dart';
import 'wallets_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
  /// [isDestructive] paints the confirm button red. Logging out ends the
  /// session; switching accounts only swaps it, so that one stays neutral.
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

  Future<void> _confirmSwitchAccount() async {
    final email = _getUserEmail();
    final confirmed = await _confirmSignOut(
      title: 'Switch account?',
      message:
          "You'll be signed out of $email and taken to the login screen, "
          'where you can sign in with another account. Connect to the '
          'internet first so your latest changes are saved.',
      confirmLabel: 'Switch',
    );

    if (confirmed) await _logout();
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
      await _auth.signOut();

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
          ? const Center(
              child: Text(
                'No user is currently logged in.',

                style: TextStyle(fontSize: 16, color: Colors.grey),
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

                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
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
                          iconAsset: 'assets/icons/icons8-banknotes-96.png',
                          title: 'Income & leftover preferences',
                          onTap: () =>
                              _open(const FinancialPreferencesScreen()),
                        ),
                        const Divider(height: 1, indent: 65),
                        _buildActionTile(
                          iconAsset: 'assets/icons/icons8-calendar-96.png',
                          title: 'Pay-cycle history',
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

                    child: OutlinedButton.icon(
                      onPressed: _confirmSwitchAccount,

                      icon: Image.asset(
                        'assets/icons/icons8-user-96.png',
                        width: 22,
                        height: 22,
                      ),

                      label: const Text(
                        'Switch Account',

                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),

                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1976D2),

                        side: const BorderSide(color: Color(0xFF1976D2)),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 52,

                    child: OutlinedButton.icon(
                      onPressed: _confirmLogOut,

                      icon: Image.asset(
                        'assets/icons/icons8-logout-96.png',
                        width: 22,
                        height: 22,
                      ),

                      label: const Text(
                        'Log Out',

                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),

                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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

        style: const TextStyle(fontSize: 13, color: Colors.grey),
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

      trailing: const Icon(Icons.chevron_right, color: Colors.grey),

      onTap: onTap,
    );
  }
}
