import 'package:flutter/material.dart';

import '../../backend/services/account_deletion.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import 'dialog_kit.dart';

/// Asks before deleting the account for good, and checks it is really the
/// owner: their password, or Google for a Google account. Closes with true
/// once the account is gone.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({
    required this.usesPassword,
    required this.onDelete,
    super.key,
  });

  /// Signs in with a password, so it is asked for here. Otherwise Google
  /// asks which account, after Delete is pressed.
  final bool usesPassword;

  /// Confirms the owner and deletes; returns why it could not, or null
  /// once the account is gone.
  final Future<AccountProblem?> Function(String? password) onDelete;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _passwordController = TextEditingController();
  bool _working = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final password = _passwordController.text;
    if (widget.usesPassword && password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });

    final problem = await widget.onDelete(
      widget.usesPassword ? password : null,
    );
    if (!mounted) return;
    if (problem == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _working = false;
      _error = switch (problem) {
        AccountProblem.wrongPassword => 'That password is not right.',
        // Closing Google's picker is a change of mind, not an error.
        AccountProblem.cancelled => null,
        AccountProblem.offline =>
          'Could not connect. Connect to the internet and try again.',
        AccountProblem.failed =>
          'Your account could not be deleted. Please try again.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

    return AlertDialog(
      shape: dialogShape,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      title: const DialogTitle(
        text: 'Delete your account?',
        iconAsset: 'assets/icons/icons8-trash-96.png',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This deletes your FinAssist account and everything in it: '
              'wallets, transactions, bills, installments, debts and goals. '
              'It cannot be undone.',
              style: TextStyle(color: colors.textBody, height: 1.45),
            ),
            const SizedBox(height: 12),
            const DialogNote(
              text:
                  'Want a copy first? Export your transactions in Settings '
                  'before you delete.',
            ),
            const SizedBox(height: 16),
            if (widget.usesPassword)
              TextField(
                key: const Key('delete-account-password'),
                controller: _passwordController,
                obscureText: _hidden,
                enabled: !_working,
                decoration: dialogFieldDecoration(context, 'Your password')
                    .copyWith(
                      suffixIcon: IconButton(
                        tooltip: _hidden ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _hidden ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _hidden = !_hidden),
                      ),
                    ),
                onSubmitted: (_) => _delete(),
              )
            else
              Text(
                'Google will ask you to choose your account, to make sure it '
                'is you.',
                style: TextStyle(color: colors.textBody, height: 1.45),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const Key('delete-account-error'),
                style: TextStyle(
                  color: dangerColorOn(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                key: const Key('delete-account-confirm'),
                onPressed: _working ? null : _delete,
                style: dangerButtonStyle(),
                child: _working
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Delete My Account', style: buttonText),
              ),
              const SizedBox(height: 10),
              // Keeping the account is the safe choice: solid blue, like
              // Switch Account, not red.
              ElevatedButton(
                onPressed: _working ? null : () => Navigator.pop(context),
                style: openButtonStyle(),
                child: const Text('Keep My Account', style: buttonText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
