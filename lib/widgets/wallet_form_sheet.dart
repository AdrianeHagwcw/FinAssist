import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/wallet.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';

const _philippineBanks = [
  'Asia United Bank (AUB)',
  'BDO Unibank',
  'Bank of Commerce',
  'Bank of the Philippine Islands (BPI)',
  'China Banking Corporation (China Bank)',
  'China Bank Savings',
  'Development Bank of the Philippines (DBP)',
  'EastWest Bank',
  'GoTyme Bank',
  'HSBC Philippines',
  'Land Bank of the Philippines',
  'Maybank Philippines',
  'Metrobank',
  'Maya Bank',
  'Philippine Bank of Communications (PBCOM)',
  'Philippine National Bank (PNB)',
  'Philippine Savings Bank (PSBank)',
  'Philippine Trust Company (Philtrust)',
  'Philippine Veterans Bank',
  'Rizal Commercial Banking Corporation (RCBC)',
  'Security Bank',
  'Standard Chartered Bank Philippines',
  'Sterling Bank of Asia',
  'UnionBank of the Philippines',
  'CIMB Bank Philippines',
  'Netbank',
  'Overseas Filipino Bank',
  'SeaBank Philippines',
  'Tonik Digital Bank',
  'UNO Digital Bank',
  'UnionDigital Bank',
  'OwnBank',
  'Other bank',
];

/// Asks for a wallet's type, name and starting balance.
///
/// Returns the wallet the user described, or null if they backed out. Used
/// both by onboarding, where the wallet is only held in memory, and by the
/// Wallets screen, which saves it straight away.
///
/// Pass [existing] to edit a wallet instead of adding one. The balance field
/// is then left out: money only moves through a transaction, so a balance is
/// never typed over by hand.
/// Pass [initialDraft] to edit an unsaved setup wallet, including its balance.
Future<WalletDraft?> showWalletFormSheet(
  BuildContext context, {
  Wallet? existing,
  WalletDraft? initialDraft,
  bool balanceOptional = false,
}) {
  return showModalBottomSheet<WalletDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => WalletFormSheet(
      existing: existing,
      initialDraft: initialDraft,
      balanceOptional: balanceOptional,
    ),
  );
}

class WalletFormSheet extends StatefulWidget {
  const WalletFormSheet({
    this.existing,
    this.initialDraft,
    this.balanceOptional = false,
    super.key,
  }) : assert(existing == null || initialDraft == null);

  /// The wallet being edited, or null when adding a new one.
  final Wallet? existing;
  final WalletDraft? initialDraft;
  final bool balanceOptional;

  @override
  State<WalletFormSheet> createState() => _WalletFormSheetState();
}

class _WalletFormSheetState extends State<WalletFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? widget.initialDraft?.name ?? '',
  );
  late final _balanceController = TextEditingController(
    // Shown the way money is typed, so a ₱2,500 wallet does not read
    // "2500.0" when it is opened again.
    text: widget.initialDraft == null
        ? ''
        : formatAmountInput(widget.initialDraft!.startingBalance),
  );
  late WalletType _type =
      widget.existing?.type ?? widget.initialDraft?.type ?? WalletType.cash;
  late String? _selectedBank = _type == WalletType.bank
      ? _philippineBanks.contains(_nameController.text)
            ? _nameController.text
            : 'Other bank'
      : null;

  bool get _isEditing => widget.existing != null || widget.initialDraft != null;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final walletName = _type == WalletType.bank
        ? _selectedBank == 'Other bank'
              ? name
              : _selectedBank!
        : name.isEmpty
        ? _type.label
        : name;
    Navigator.pop(
      context,
      WalletDraft(
        type: _type,
        name: walletName.isEmpty ? _type.label : walletName,
        startingBalance: widget.existing != null
            ? widget.existing!.balance
            : double.tryParse(
                    _balanceController.text.trim().replaceAll(',', ''),
                  ) ??
                  0,
        receivesIncome:
            widget.existing?.receivesIncome ??
            widget.initialDraft?.receivesIncome ??
            false,
        purpose: widget.initialDraft?.purpose ?? WalletPurpose.spending,
        savingsKind: widget.initialDraft?.savingsKind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // "Other" covers anything that is not one of the named types, so it has
    // to be named or the list is full of wallets called Other.
    final isOther = _type == WalletType.other;

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
                        onSelected: (_) {
                          if (type == WalletType.bank) {
                            FocusScope.of(context).unfocus();
                          }
                          setState(() => _type = type);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_type == WalletType.bank) ...[
                  const Text(
                    'Bank',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('wallet-bank-dropdown'),
                    initialValue: _selectedBank,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'Select a bank',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: [
                      for (final bank in _philippineBanks)
                        DropdownMenuItem(value: bank, child: Text(bank)),
                    ],
                    validator: (value) => value == null || value.isEmpty
                        ? 'Please select a bank.'
                        : null,
                    onChanged: (value) => setState(() => _selectedBank = value),
                  ),
                  if (_selectedBank == 'Other bank') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('wallet-other-bank-name'),
                      controller: _nameController,
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 30,
                      decoration: InputDecoration(
                        labelText: 'Bank name',
                        hintText: 'Enter your bank name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter the bank name.'
                          : null,
                    ),
                  ],
                ] else ...[
                  Text(
                    isOther ? 'Name' : 'Name (optional)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    autofocus: _isEditing,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 30,
                    decoration: InputDecoration(
                      hintText: isOther
                          ? 'e.g. Coins.ph, Lazada Wallet, coin bank'
                          : 'e.g. ${_type.label}',
                      helperText: isOther
                          ? 'Other is for anywhere else you keep money that '
                                'is not cash, GCash, Maya or a bank. Name it '
                                'so you can tell it apart later.'
                          : null,
                      helperMaxLines: 3,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) =>
                        isOther && (value == null || value.trim().isEmpty)
                        ? 'Name this wallet so you know what it is.'
                        : null,
                  ),
                ],
                const SizedBox(height: 8),
                if (widget.existing == null) ...[
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
                    inputFormatters: const [ThousandsSeparatorFormatter()],
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixText: '₱ ',
                      helperText: widget.balanceOptional
                          ? 'Optional. Leave blank if you do not know it yet.'
                          : 'Enter 0 if this wallet is empty.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty && widget.balanceOptional) return null;
                      final amount = double.tryParse(text.replaceAll(',', ''));
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
