import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/wallet.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../utils/text_limits.dart';
import 'check_after_save.dart';

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

const _philippineEWallets = [
  'GCash',
  'Maya',
  'GrabPay',
  'ShopeePay',
  'Coins.ph',
  'PalawanPay',
  'DiskarTech',
  'Other E-Wallet',
];

WalletType _editableWalletType(WalletType type) =>
    isEWalletType(type) ? WalletType.ewallet : type;

/// The entry in [options] that [name] stands for, also when a number was added
/// to tell two of the same apart ("BDO Unibank 2").
String? _listedName(String name, List<String> options) {
  if (options.contains(name)) return name;
  final stem = RegExp(r'^(.*\S) \d+$').firstMatch(name)?.group(1);
  return stem != null && options.contains(stem) ? stem : null;
}

/// The wallet a name said out loud stands for: a listed e-wallet or bank,
/// or else cash, as "GCash", "BDO" or "Alkansya".
({WalletType type, String name}) _spokenWallet(String said) {
  String key(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final heard = key(said);
  String? listed(List<String> options) {
    for (final option in options) {
      if (option.startsWith('Other')) continue;
      final name = key(option);
      final short = RegExp(r'\(([^)]+)\)').firstMatch(option)?.group(1);
      if (name == heard ||
          (short != null && key(short) == heard) ||
          (heard.length >= 3 && name.startsWith(heard))) {
        return option;
      }
    }
    return null;
  }

  if (listed(_philippineEWallets) case final name?) {
    return (type: WalletType.ewallet, name: name);
  }
  if (listed(_philippineBanks) case final name?) {
    return (type: WalletType.bank, name: name);
  }
  if (RegExp('bank|bangko').hasMatch(heard)) {
    return (type: WalletType.bank, name: said);
  }
  return (type: WalletType.cash, name: said);
}

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
/// [suggestedName] and [suggestedBalance] start a new wallet filled in, as
/// from Voice Entry.
Future<WalletDraft?> showWalletFormSheet(
  BuildContext context, {
  Wallet? existing,
  WalletDraft? initialDraft,
  String? suggestedName,
  double? suggestedBalance,
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
      suggestedName: suggestedName,
      suggestedBalance: suggestedBalance,
    ),
  );
}

class WalletFormSheet extends StatefulWidget {
  const WalletFormSheet({
    this.existing,
    this.initialDraft,
    this.suggestedName,
    this.suggestedBalance,
    super.key,
  }) : assert(existing == null || initialDraft == null);

  /// The wallet being edited, or null when adding a new one.
  final Wallet? existing;
  final WalletDraft? initialDraft;

  /// What a new wallet starts filled in with.
  final String? suggestedName;
  final double? suggestedBalance;

  @override
  State<WalletFormSheet> createState() => _WalletFormSheetState();
}

class _WalletFormSheetState extends State<WalletFormSheet> with CheckAfterSave {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: _originalName);

  /// Cash has its own name field, so a bank's name never carries over to it.
  late final _cashNameController = TextEditingController(
    text: _originalType == WalletType.cash ? _originalName : '',
  );
  late final _balanceController = TextEditingController(
    text: widget.initialDraft != null && widget.initialDraft!.balanceRecorded
        ? formatAmountInput(widget.initialDraft!.startingBalance)
        : widget.suggestedBalance != null
        ? formatAmountInput(widget.suggestedBalance!)
        : '',
  );
  late final _interestRateController = TextEditingController(
    text: _interestRateText(
      widget.existing?.annualInterestRatePercent ??
          widget.initialDraft?.annualInterestRatePercent,
    ),
  );
  late WalletType _type = _editableWalletType(_originalType ?? WalletType.cash);
  late String? _selectedBank = _initialBankSelection();
  late String? _selectedEWallet = _initialEWalletSelection();

  bool get _isEditing => widget.existing != null || widget.initialDraft != null;

  late final _suggested = widget.suggestedName == null
      ? null
      : _spokenWallet(widget.suggestedName!);

  String get _originalName =>
      widget.existing?.name ??
      widget.initialDraft?.name ??
      _suggested?.name ??
      '';

  WalletType? get _originalType =>
      widget.existing?.type ?? widget.initialDraft?.type ?? _suggested?.type;

  // Both lists start on the wallet as it was opened, never on a name typed
  // under another type since: these are first read when a list is shown,
  // which can be after an e-wallet name was typed and Banks picked.
  String? _initialBankSelection() {
    if (_originalType != WalletType.bank) return null;
    final name = _originalName.trim();
    if (name.isEmpty) return null;
    return _listedName(name, _philippineBanks) ?? 'Other bank';
  }

  String? _initialEWalletSelection() {
    final sourceType = _originalType;
    if (sourceType == WalletType.gcash) return 'GCash';
    if (sourceType == WalletType.maya) return 'Maya';
    if (sourceType != WalletType.ewallet) return null;

    final name = _originalName.trim();
    if (name.isEmpty) return null;
    return _listedName(name, _philippineEWallets) ?? 'Other E-Wallet';
  }

  List<WalletType> get _availableTypes {
    const supportedTypes = [
      WalletType.cash,
      WalletType.ewallet,
      WalletType.bank,
    ];
    if (supportedTypes.contains(_type)) return supportedTypes;
    return [...supportedTypes, _type];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cashNameController.dispose();
    _balanceController.dispose();
    _interestRateController.dispose();
    super.dispose();
  }

  String _interestRateText(double? rate) =>
      rate == null ? '' : formatAmountInput(rate);

  void _save() {
    if (!checkForm(_formKey)) return;

    final name = cleanText(_nameController.text);
    final cashName = cleanText(_cashNameController.text);
    // A numbered name ("BDO Unibank 2") stays as it is while the same entry
    // is still picked.
    String picked(String choice, List<String> options) =>
        _editableWalletType(_originalType ?? _type) == _type &&
            _listedName(_originalName, options) == choice
        ? _originalName
        : choice;
    final walletName = switch (_type) {
      WalletType.bank =>
        _selectedBank == 'Other bank'
            ? name
            : picked(_selectedBank!, _philippineBanks),
      WalletType.ewallet =>
        _selectedEWallet == 'Other E-Wallet'
            ? name
            : picked(_selectedEWallet!, _philippineEWallets),
      // Naming cash is optional; left blank it is just "Cash".
      WalletType.cash => cashName.isEmpty ? 'Cash' : cashName,
      _ => name.isEmpty ? _type.label : name,
    };
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
        // What the field holds now, so a balance typed into a setup wallet
        // saved without one counts from then on.
        balanceRecorded:
            widget.existing?.hasRecordedBalance ??
            _balanceController.text.trim().isNotEmpty,
        annualInterestRatePercent:
            _supportsInterestRate(_type) &&
                _interestRateController.text.trim().isNotEmpty
            ? double.tryParse(_interestRateController.text.trim())
            : null,
        purpose: widget.initialDraft?.purpose ?? WalletPurpose.spending,
        savingsKind: widget.initialDraft?.savingsKind,
      ),
    );
  }

  bool _supportsInterestRate(WalletType type) => isBankOrEWalletType(type);

  Widget _buildTypeChip(WalletType type, AppColors colors) {
    final selected = type == _type;
    final label = switch (type) {
      WalletType.ewallet => 'E-Wallets',
      WalletType.bank => 'Banks',
      _ => type.label,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('wallet-type-${type.name}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (type == WalletType.bank) {
              FocusScope.of(context).unfocus();
            }
            setState(() => _type = type);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? appPrimaryBlue : colors.card,
                border: Border.all(
                  color: selected ? appPrimaryBlue : colors.border,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(type.iconAsset, width: 16, height: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected ? Colors.white : colors.textBody,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isOther = _type == WalletType.other;
    final requiresCustomName =
        isOther ||
        (_type == WalletType.ewallet && _selectedEWallet == 'Other E-Wallet');

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _formKey,
            autovalidateMode: checkMode,
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
                Row(
                  children: [
                    for (
                      var index = 0;
                      index < _availableTypes.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _buildTypeChip(_availableTypes[index], colors),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                if (_type == WalletType.bank ||
                    _type == WalletType.ewallet) ...[
                  Text(
                    _type == WalletType.bank ? 'Banks' : 'E-Wallets',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: Key(
                      _type == WalletType.bank
                          ? 'wallet-bank-dropdown'
                          : 'wallet-ewallet-dropdown',
                    ),
                    initialValue: _type == WalletType.bank
                        ? _selectedBank
                        : _selectedEWallet,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: _type == WalletType.bank
                          ? 'Select a bank'
                          : 'Select an e-wallet',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: [
                      for (final provider
                          in _type == WalletType.bank
                              ? _philippineBanks
                              : _philippineEWallets)
                        DropdownMenuItem(
                          value: provider,
                          child: Text(provider),
                        ),
                    ],
                    validator: (value) {
                      if (value != null && value.isNotEmpty) return null;
                      return _type == WalletType.bank
                          ? 'Please select a bank.'
                          : 'Please select an e-wallet.';
                    },
                    onChanged: (value) => setState(() {
                      if (_type == WalletType.bank) {
                        _selectedBank = value;
                      } else {
                        _selectedEWallet = value;
                      }
                    }),
                  ),
                  if (_type == WalletType.bank &&
                      _selectedBank == 'Other bank') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('wallet-other-bank-name'),
                      controller: _nameController,
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                      maxLength: maxWalletNameLength,
                      inputFormatters: const [SafeTextFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Bank name',
                        hintText: 'Enter your bank name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (value) => itemNameProblem(
                        value ?? '',
                        maxLength: maxWalletNameLength,
                        empty: 'Enter the bank name.',
                      ),
                    ),
                  ],
                  if (_type == WalletType.ewallet &&
                      _selectedEWallet == 'Other E-Wallet') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('wallet-other-ewallet-name'),
                      controller: _nameController,
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                      maxLength: maxWalletNameLength,
                      inputFormatters: const [SafeTextFormatter()],
                      decoration: InputDecoration(
                        labelText: 'E-Wallet name',
                        hintText: 'Enter the e-wallet name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (value) => itemNameProblem(
                        value ?? '',
                        maxLength: maxWalletNameLength,
                        empty: 'Enter the e-wallet name.',
                      ),
                    ),
                  ],
                ] else if (_type == WalletType.cash) ...[
                  const Text(
                    'Name (optional)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('wallet-cash-name'),
                    controller: _cashNameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: maxWalletNameLength,
                    inputFormatters: const [SafeTextFormatter()],
                    // Optional, but a name given has to be readable.
                    validator: (value) => cleanText(value ?? '').isEmpty
                        ? null
                        : itemNameProblem(
                            value!,
                            maxLength: maxWalletNameLength,
                          ),
                    decoration: InputDecoration(
                      hintText: 'e.g. Petty Cash',
                      helperText: 'Leave blank to call it Cash.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    requiresCustomName ? 'Name' : 'Name (optional)',
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
                    maxLength: maxWalletNameLength,
                    inputFormatters: const [SafeTextFormatter()],
                    decoration: InputDecoration(
                      hintText: isOther
                          ? 'e.g. coin bank'
                          : 'e.g. ${_type.label}',
                      helperText: isOther
                          ? 'Other is for somewhere else you keep money that '
                                'is not cash, an e-wallet or a bank.'
                          : null,
                      helperMaxLines: 3,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) =>
                        !requiresCustomName && cleanText(value ?? '').isEmpty
                        ? null
                        : itemNameProblem(
                            value ?? '',
                            maxLength: maxWalletNameLength,
                            empty: 'Name this wallet so you know what it is.',
                          ),
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
                    key: const Key('wallet-current-balance'),
                    controller: _balanceController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [ThousandsSeparatorFormatter()],
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixText: '₱ ',
                      // Where to find the number, for each kind of wallet.
                      helperText: switch (_type) {
                        WalletType.bank =>
                          "Check your bank app or passbook. Enter 0 if it's "
                              'empty.',
                        WalletType.cash =>
                          'Count what you have on hand. Enter 0 if none.',
                        WalletType.ewallet ||
                        WalletType.gcash ||
                        WalletType.maya =>
                          "Check your e-wallet app. Enter 0 if it's empty.",
                        WalletType.other => 'Enter 0 if this wallet is empty.',
                      },
                      helperMaxLines: 2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) {
                      // Every wallet has a balance the user can check, even
                      // if it is zero, so it is never skipped: a blank would
                      // quietly drop it from every total.
                      final text = (value ?? '').trim();
                      final amount = double.tryParse(text.replaceAll(',', ''));
                      return amount == null || amount < 0
                          ? 'Enter the balance, or 0 if empty.'
                          : null;
                    },
                    onFieldSubmitted: (_) => _save(),
                  ),
                ],
                if (_supportsInterestRate(_type)) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('wallet-annual-interest-rate'),
                    controller: _interestRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [RateInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Annual Interest Rate (%)',
                      hintText: 'Optional',
                      helperText:
                          'Enter the rate for this specific account. Leave '
                          'blank if unknown or not applicable.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return null;
                      final rate = double.tryParse(text);
                      if (!isValidAnnualInterestRatePercent(rate)) {
                        return 'Enter a rate from 0 to '
                            '${maximumAnnualInterestRatePercent.toInt()}%.';
                      }
                      return null;
                    },
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
