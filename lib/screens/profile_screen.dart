import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'budget_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

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

  // =========================================================
  // LOGOUT
  // =========================================================

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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

      // =====================================================
      // APP BAR
      // =====================================================
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),

        foregroundColor: Colors.white,

        elevation: 0,

        // BACK TO HOME
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),

          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: const Text(
          'Profile',

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
                      color: Colors.white,

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

                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF151515),
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

                  Container(
                    width: double.infinity,

                    decoration: BoxDecoration(
                      color: Colors.white,

                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: Column(
                      children: [
                        _buildInfoTile(
                          icon: Icons.person_outline,
                          title: 'Full Name',
                          value: _getUserName(),
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildInfoTile(
                          icon: Icons.email_outlined,
                          title: 'Email',
                          value: _getUserEmail(),
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildInfoTile(
                          icon: Icons.verified_user_outlined,
                          title: 'Account Status',
                          value: 'Active',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // SETTINGS
                  // =================================================
                  _buildSectionTitle('Settings'),

                  const SizedBox(height: 10),

                  Container(
                    width: double.infinity,

                    decoration: BoxDecoration(
                      color: Colors.white,

                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: Column(
                      children: [
                        _buildActionTile(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Category Budgets',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const BudgetScreen(),
                              ),
                            );
                          },
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildActionTile(
                          icon: Icons.notifications_outlined,

                          title: 'Notifications',

                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const NotificationsScreen(),
                              ),
                            );
                          },
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildActionTile(
                          icon: Icons.lock_outline,

                          title: 'Security',

                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Security settings coming soon.'),
                              ),
                            );
                          },
                        ),

                        const Divider(height: 1, indent: 65),

                        _buildActionTile(
                          icon: Icons.help_outline,

                          title: 'Help & Support',

                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Help & Support coming soon.'),
                              ),
                            );
                          },
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
                      onPressed: _logout,

                      icon: const Icon(Icons.logout, color: Colors.red),

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

        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Color(0xFF151515),
        ),
      ),
    );
  }

  // =========================================================
  // INFORMATION TILE
  // =========================================================

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),

      leading: Container(
        width: 42,
        height: 42,

        decoration: BoxDecoration(
          color: const Color(0xFFEAF3FB),

          borderRadius: BorderRadius.circular(10),
        ),

        child: Icon(icon, color: const Color(0xFF1976D2)),
      ),

      title: Text(
        title,

        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),

      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),

        child: Text(
          value,

          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF151515),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // ACTION TILE
  // =========================================================

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),

      leading: Container(
        width: 42,
        height: 42,

        decoration: BoxDecoration(
          color: const Color(0xFFEAF3FB),

          borderRadius: BorderRadius.circular(10),
        ),

        child: Icon(icon, color: const Color(0xFF1976D2)),
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
