import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/forgot_password_screen.dart';
import '../services/saved_accounts.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/text_limits.dart';

/// What was picked in the Switch account sheet: another account used on
/// this phone, or a new one when [account] is null.
class AccountChoice {
  const AccountChoice(this.account);

  final SavedAccount? account;
}

void _forget(SavedAccount account) => SavedAccounts.forget(account);

/// Opens the Switch account sheet. Null when it is closed without a choice.
Future<AccountChoice?> showSwitchAccountSheet(
  BuildContext context, {
  required SavedAccount current,
  required List<SavedAccount> saved,
  ValueChanged<SavedAccount> onForget = _forget,
}) {
  return showModalBottomSheet<AccountChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.pageBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SwitchAccountSheet(
      current: current,
      others: [
        for (final account in saved)
          if (account.uid != current.uid) account,
      ],
      onForget: onForget,
    ),
  );
}

/// The signed-in account, the others used on this phone, and a way to add
/// one. The signed-in account stays signed in until the one picked logs in,
/// so a wrong password or a change of mind leaves everything as it was.
class SwitchAccountSheet extends StatefulWidget {
  const SwitchAccountSheet({
    required this.current,
    required this.others,
    required this.onForget,
    super.key,
  });

  final SavedAccount current;
  final List<SavedAccount> others;
  final ValueChanged<SavedAccount> onForget;

  @override
  State<SwitchAccountSheet> createState() => _SwitchAccountSheetState();
}

class _SwitchAccountSheetState extends State<SwitchAccountSheet> {
  late final _others = [...widget.others];

  void _forget(SavedAccount account) {
    setState(() => _others.remove(account));
    widget.onForget(account);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Switch account',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _AccountTile(
                    account: widget.current,
                    trailing: Icon(
                      Icons.check_circle,
                      color: colors.primaryText,
                      semanticLabel: 'Signed in',
                    ),
                  ),
                  for (final account in _others) ...[
                    const Divider(height: 1, indent: 72),
                    _AccountTile(
                      key: Key('switch-to-${account.email}'),
                      account: account,
                      onTap: () =>
                          Navigator.pop(context, AccountChoice(account)),
                      trailing: IconButton(
                        key: Key('forget-${account.email}'),
                        tooltip: 'Remove from this phone',
                        icon: Icon(Icons.close, color: colors.textMuted),
                        onPressed: () => _forget(account),
                      ),
                    ),
                  ],
                  const Divider(height: 1, indent: 72),
                  ListTile(
                    key: const Key('add-another-account'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: colors.primaryTint,
                      child: Icon(
                        Icons.person_add_alt_1,
                        color: colors.primaryText,
                      ),
                    ),
                    title: Text(
                      'Add another account',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    onTap: () =>
                        Navigator.pop(context, const AccountChoice(null)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You stay signed in as ${widget.current.label} until the other '
              'account logs in.',
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.trailing,
    this.onTap,
    super.key,
  });

  final SavedAccount account;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final details = [
      if (account.name.isNotEmpty) account.email,
      if (!account.usesPassword) 'Google',
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: appPrimaryBlue,
        child: Text(
          account.initial,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      title: Text(
        account.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// How the password step ended, when it wasn't closed.
enum PasswordStep { loggedIn, useGoogle }

/// Asks for [account]'s password and logs in with [logIn], which returns
/// what went wrong, or null once logged in. Stays open on a wrong password
/// so the user can try again. Null when closed.
Future<PasswordStep?> showAccountPasswordDialog(
  BuildContext context, {
  required SavedAccount account,
  required Future<String?> Function(String password) logIn,
}) {
  return showDialog<PasswordStep>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AccountPasswordDialog(account: account, logIn: logIn),
  );
}

class AccountPasswordDialog extends StatefulWidget {
  const AccountPasswordDialog({
    required this.account,
    required this.logIn,
    super.key,
  });

  final SavedAccount account;
  final Future<String?> Function(String password) logIn;

  @override
  State<AccountPasswordDialog> createState() => _AccountPasswordDialogState();
}

class _AccountPasswordDialogState extends State<AccountPasswordDialog> {
  final _password = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _problem = 'Please enter your password.');
      return;
    }

    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem = await widget.logIn(_password.text);
    if (!mounted) return;
    if (problem == null) {
      Navigator.pop(context, PasswordStep.loggedIn);
      return;
    }
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final colors = context.appColors;

    return AlertDialog(
      title: Text('Log in as ${account.label}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (account.name.isNotEmpty) ...[
              Text(
                account.email,
                style: TextStyle(fontSize: 13, color: colors.textMuted),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const Key('switch-password'),
              controller: _password,
              autofocus: true,
              obscureText: _hidden,
              enabled: !_busy,
              inputFormatters: [
                LengthLimitingTextInputFormatter(maxPasswordLength),
              ],
              onChanged: (_) {
                if (_problem != null) setState(() => _problem = null);
              },
              onSubmitted: (_) => _logIn(),
              decoration: InputDecoration(
                labelText: 'Password',
                errorText: _problem,
                errorMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ForgotPasswordScreen(initialEmail: account.email),
                        ),
                      ),
                child: const Text('Forgot Password?'),
              ),
            ),
            if (account.usesGoogle)
              OutlinedButton.icon(
                key: const Key('switch-use-google'),
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, PasswordStep.useGoogle),
                icon: const Icon(
                  Icons.g_mobiledata,
                  size: 28,
                  color: Colors.red,
                ),
                label: Text(
                  'Use Google instead',
                  style: TextStyle(color: colors.textBody),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: colors.inputBorder),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          style: cancelTextStyle(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('switch-log-in'),
          onPressed: _busy ? null : _logIn,
          style: confirmTextStyle(context),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Log In'),
        ),
      ],
    );
  }
}
