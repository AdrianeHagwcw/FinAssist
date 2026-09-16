import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/wallet.dart';
import '../services/user_profile_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

const _incomeSources = [
  'Allowance',
  'Salary',
  'Part-time Job',
  'Business',
  'Freelance',
  'Scholarship',
  'Gift',
  'Sold Something',
  'Refund',
  'Other',
];

/// Picking this asks the user to say where the money came from in their own
/// words, so "Other" never has to stand in for the real answer.
const _otherSource = 'Other';

/// Asks for an income amount, where it came from and which wallet it landed
/// in, then saves it.
///
/// Returns true when income was saved, so callers can refresh their totals.
Future<bool> showAddIncomeDialog(
  BuildContext context, {
  Stream<List<Wallet>>? wallets,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AddIncomeDialog(wallets: wallets),
  );

  return saved ?? false;
}

class AddIncomeDialog extends StatefulWidget {
  const AddIncomeDialog({this.wallets, super.key});

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  @override
  State<AddIncomeDialog> createState() => _AddIncomeDialogState();
}

class _AddIncomeDialogState extends State<AddIncomeDialog> {
  // The controller belongs to this State, so it is disposed only once the
  // dialog has finished closing. Disposing it right after the dialog is
  // popped would break the closing animation, which still paints the field.
  final _amountController = TextEditingController();
  final _otherSourceController = TextEditingController();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  String? _source;
  String? _walletId;
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _otherSourceController.dispose();
    super.dispose();
  }

  /// What the income is filed under. When the user chose "Other" and typed
  /// something, their own words are used instead.
  String? get _resolvedSource {
    if (_source != _otherSource) return _source;

    final typed = _otherSourceController.text.trim();
    return typed.isEmpty ? _otherSource : typed;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    if (amount == null || amount <= 0) {
      _showMessage('Enter a valid positive income amount.');
      return;
    }

    final source = _resolvedSource;

    if (source == null) {
      _showMessage('Select where the income came from.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final recordId = await UserProfileService.addOtherIncome(
        amount: amount,
        incomeSource: source,
      );

      // Shares the income record's id, so the one-time migration of older
      // income can't file it twice.
      WalletService.recordTransaction(
        id: recordId,
        type: TransactionType.income,
        amount: amount,
        label: source,
        walletId: _walletId,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;

      setState(() => _isSaving = false);
      _showMessage('Income could not be saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: dialogShape,
      title: const DialogTitle(
        text: 'Add Income',
        iconAsset: 'assets/icons/icons8-money-transfer-96.png',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<List<Wallet>>(
          stream: _wallets,
          builder: (context, snapshot) {
            final wallets = snapshot.data ?? const <Wallet>[];
            // Settles on a default as soon as the wallets arrive, so saving
            // without touching the picker still credits the right wallet.
            _walletId ??= defaultWalletId(wallets);

            // Scrolls rather than overflows once the keyboard takes half the
            // screen on a small phone.
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmountField(
                    controller: _amountController,
                    label: 'Amount',
                    enabled: !_isSaving,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _source,
                    isExpanded: true,
                    // Kept short so it isn't cut off on a narrow phone.
                    decoration: dialogFieldDecoration(context, 'Source'),
                    items: _incomeSources
                        .map(
                          (source) => DropdownMenuItem(
                            value: source,
                            child: Text(source),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _source = value),
                  ),
                  if (_source == _otherSource) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otherSourceController,
                      enabled: !_isSaving,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 30,
                      decoration: dialogFieldDecoration(
                        context,
                        'Where did it come from?',
                        hint: 'e.g. Sold my old phone',
                        helper: 'Optional. Blank just calls it Other.',
                      ),
                    ),
                  ],
                  if (wallets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    WalletPicker(
                      wallets: wallets,
                      selectedId: _walletId,
                      label: 'Into which wallet?',
                      onChanged: _isSaving
                          ? (_) {}
                          : (value) => setState(() => _walletId = value),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          style: cancelTextStyle(context),
          child: const Text('Cancel'),
        ),
        DialogSaveButton(onPressed: _save, isSaving: _isSaving),
      ],
    );
  }
}
