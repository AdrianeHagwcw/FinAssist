import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../theme/app_theme.dart';

/// Asks for a wallet's type, name and starting balance.
///
/// Returns the wallet the user described, or null if they backed out. Used
/// both by onboarding, where the wallet is only held in memory, and by the
/// Wallets screen, which saves it straight away.
///
/// Pass [existing] to edit a wallet instead of adding one. The balance field
/// is then left out: money only moves through a transaction, so a balance is
/// never typed over by hand.
Future<WalletDraft?> showWalletFormSheet(
  BuildContext context, {
  Wallet? existing,
}) {
  return showModalBottomSheet<WalletDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => WalletFormSheet(existing: existing),
  );
}

class WalletFormSheet extends StatefulWidget {
  const WalletFormSheet({this.existing, super.key});

  /// The wallet being edited, or null when adding a new one.
  final Wallet? existing;

  @override
  State<WalletFormSheet> createState() => _WalletFormSheetState();
}

class _WalletFormSheetState extends State<WalletFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  final _balanceController = TextEditingController();
  late WalletType _type = widget.existing?.type ?? WalletType.cash;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    Navigator.pop(
      context,
      WalletDraft(
        type: _type,
        name: name.isEmpty ? _type.label : name,
        startingBalance: _isEditing
            ? widget.existing!.balance
            : double.parse(_balanceController.text.trim().replaceAll(',', '')),
        receivesIncome: widget.existing?.receivesIncome ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  _isEditing ? 'Edit Wallet' : 'New Wallet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Type',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in WalletType.values)
                      ChoiceChip(
                        avatar: Image.asset(
                          type.iconAsset,
                          width: 18,
                          height: 18,
                        ),
                        label: Text(type.label),
                        selected: type == _type,
                        showCheckmark: false,
                        selectedColor: appPrimaryBlue,
                        labelStyle: TextStyle(
                          color: type == _type ? Colors.white : colors.textBody,
                          fontWeight: type == _type
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Name (optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  autofocus: _isEditing,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 30,
                  decoration: InputDecoration(
                    hintText: 'e.g. ${_type.label} or "BPI Savings"',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (!_isEditing) ...[
                  const Text(
                    'Current balance',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _balanceController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixText: '₱ ',
                      helperText: 'Enter 0 if this wallet is empty.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) {
                      final amount = double.tryParse(
                        (value ?? '').trim().replaceAll(',', ''),
                      );
                      return amount == null || amount < 0
                          ? 'Enter the balance, or 0 if empty.'
                          : null;
                    },
                    onFieldSubmitted: (_) => _save(),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: confirmButtonStyle(),
                    child: Text(
                      _isEditing ? 'Save Changes' : 'Add Wallet',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
