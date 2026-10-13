import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import 'savings_guide.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';

/// Lets the user fix a savings or bills record they set up earlier: its name,
/// and the balance they declared.
///
/// Correcting the balance is not a payment. It assumes the figure was typed
/// wrongly, so nothing is recorded as income or spending.
Future<bool?> showSetAsideRecordSheet(
  BuildContext context, {
  Wallet? wallet,
  List<Wallet> wallets = const [],
  WalletPurpose purpose = WalletPurpose.savings,
  SavingsKind? initialKind,
  double minimumBalance = 0,
  void Function(String name, double recorded)? onSave,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SetAsideRecordSheet(
      wallet: wallet,
      wallets: wallets,
      purpose: purpose,
      initialKind: initialKind,
      minimumBalance: minimumBalance,
      onSave: onSave,
    ),
  );
}

class SetAsideRecordSheet extends StatefulWidget {
  const SetAsideRecordSheet({
    this.wallet,
    this.wallets = const [],
    this.purpose = WalletPurpose.savings,
    this.initialKind,
    this.minimumBalance = 0,
    this.onSave,
    super.key,
  });

  /// The record being fixed, or null when adding a new one.
  final Wallet? wallet;

  /// Everything already saved, used to give a new record its place in the
  /// list. Only needed when adding.
  final List<Wallet> wallets;

  /// Which side of Set aside this record belongs to. An existing record
  /// keeps its own.
  final WalletPurpose purpose;

  /// The kind to open on, for a new record started from the savings guide.
  final SavingsKind? initialKind;

  /// Money in this savings record already assigned to goals.
  final double minimumBalance;

  /// Replaces the write. Used by tests.
  final void Function(String name, double recorded)? onSave;

  @override
  State<SetAsideRecordSheet> createState() => _SetAsideRecordSheetState();
}

class _SetAsideRecordSheetState extends State<SetAsideRecordSheet> {
  late final _nameController = TextEditingController(
    text: widget.wallet?.name ?? '',
  );
  late final _balanceController = TextEditingController(
    text: widget.wallet == null
        ? ''
        : formatAmountInput(widget.wallet!.balance),
  );
  late SavingsKind _kind = widget.wallet != null || widget.initialKind == null
      ? SavingsKind.fromName(widget.wallet?.savingsKind)
      : widget.initialKind!;
  late DateTime? _maturityDate = widget.wallet?.maturityDate;
  String? _error;

  bool get _isNew => widget.wallet == null;

  WalletPurpose get _purpose => widget.wallet?.purpose ?? widget.purpose;

  /// Bills money is simply money waiting, so it has no kinds and never
  /// matures. Only savings asks those questions.
  bool get _isSavings => _purpose == WalletPurpose.savings;

  String get _addLabel => _isSavings ? 'Add savings' : 'Add bills money';

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  /// The same plain-language guide that used to sit on the Goals screen,
  /// read here beside the choice it describes.
  Future<void> _explain(SavingsKind kind) async {
    await showSavingsOptionSheet(
      context,
      option: savingsOptionFor(kind),
      actionLabel: 'Use this',
      onAct: () => setState(() => _kind = kind),
    );
  }

  Future<void> _pickMaturity() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _maturityDate ?? DateTime(today.year, today.month + 6, today.day),
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 20),
      helpText: 'When can you take it out?',
    );
    if (picked != null) setState(() => _maturityDate = picked);
  }

  /// What the record ends up called. A blank name falls back to the type,
  /// and a name already taken gets a number so two records never read the
  /// same.
  String _finalName() {
    final typed = _nameController.text.trim();
    if (!_isNew) return typed;

    final fallback = _isSavings ? _kind.label : 'Bills wallet';
    final base = typed.isEmpty ? fallback : typed;
    final taken = {
      for (final wallet in widget.wallets)
        if (!wallet.archived) wallet.name.trim().toLowerCase(),
    };
    if (!taken.contains(base.toLowerCase())) return base;

    var next = 2;
    while (taken.contains('$base $next'.toLowerCase())) {
      next++;
    }
    return '$base $next';
  }

  void _save() {
    final name = _finalName();
    // Only an existing record has to keep a name; a new one can be left to
    // the type.
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name.');
      return;
    }

    final text = _balanceController.text.trim().replaceAll(',', '');
    final recorded = text.isEmpty ? 0.0 : double.tryParse(text);
    if (recorded == null || !recorded.isFinite || recorded < 0) {
      setState(() => _error = 'Enter an amount of zero or more.');
      return;
    }

    if (_isSavings && recorded + 0.005 < widget.minimumBalance) {
      setState(
        () => _error =
            'At least ${formatPeso(widget.minimumBalance)} is already '
            'assigned to goals. Reduce the goal contributions first.',
      );
      return;
    }

    if (widget.onSave != null) {
      widget.onSave!(name, recorded);
      Navigator.pop(context, true);
      return;
    }

    if (_isNew) {
      WalletService.addWallet(
        type: WalletType.other,
        name: name,
        startingBalance: recorded,
        currentWallets: widget.wallets,
        purpose: _purpose,
        savingsKind: _isSavings ? _kind.name : null,
        maturityDate: _isSavings && _kind.isLockedAway ? _maturityDate : null,
      );
    } else {
      final wallet = widget.wallet!;
      if (name != wallet.name) {
        WalletService.updateWallet(walletId: wallet.id, name: name);
      }
      WalletService.correctDeclaredBalance(wallet: wallet, recorded: recorded);
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.track,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isNew ? _addLabel : 'Edit ${widget.wallet!.name}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                !_isNew
                    ? 'Fix what you entered when you set this up.'
                    : _isSavings
                    ? 'Money you have already put aside. FinAssist records '
                          'the balance you enter; it is never read from a '
                          'bank.'
                    : 'Where you keep the money waiting for your bills. '
                          'FinAssist records the balance you enter; it is '
                          'never read from a bank.',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              ),
              const SizedBox(height: 18),
              if (_isNew && _isSavings) ...[
                Text(
                  'What kind of savings? Tap the i to read about one.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                // The sheet paints its own background, so the tiles need a
                // Material of their own for their ink to show.
                Material(
                  color: Colors.transparent,
                  child: RadioGroup<SavingsKind>(
                    groupValue: _kind,
                    onChanged: (value) => setState(() => _kind = value!),
                    child: Column(
                      children: [
                        for (final kind in SavingsKind.values)
                          RadioListTile<SavingsKind>(
                            key: Key('new-savings-${kind.name}'),
                            value: kind,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(kind.label),
                            subtitle: Text(
                              kind.hint,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textBody,
                              ),
                            ),
                            secondary: IconButton(
                              key: Key('explain-savings-${kind.name}'),
                              onPressed: () => _explain(kind),
                              tooltip: 'What is this?',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.info_outline,
                                size: 20,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                key: const Key('set-aside-name'),
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: dialogFieldDecoration(
                  context,
                  _isNew ? 'Name (optional)' : 'Name',
                  hint: !_isNew
                      ? null
                      : _isSavings
                      ? 'e.g. ${_kind.label}'
                      : 'e.g. Bills wallet',
                ).copyWith(counterText: ''),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('set-aside-balance'),
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [ThousandsSeparatorFormatter()],
                decoration: dialogFieldDecoration(
                  context,
                  'Recorded balance',
                ).copyWith(prefixText: '₱ '),
              ),
              const SizedBox(height: 6),
              Text(
                _isNew
                    ? 'What you have in it today. Enter 0 if it is empty.'
                    : _isSavings && widget.minimumBalance > 0
                    ? 'At least ${formatPeso(widget.minimumBalance)} is assigned '
                          'to goals. Reduce those goal contributions before '
                          'lowering this balance below that amount.'
                    : 'Changing this only fixes a figure you typed. It is '
                          'not money coming in or going out, so your reports '
                          'stay the same.',
                style: TextStyle(fontSize: 12, color: colors.textBody),
              ),
              if (_isNew && _isSavings && _kind.isLockedAway) ...[
                const SizedBox(height: 14),
                InkWell(
                  key: const Key('new-savings-maturity'),
                  onTap: _pickMaturity,
                  child: InputDecorator(
                    decoration: dialogFieldDecoration(
                      context,
                      'Date you can take it out (optional)',
                    ),
                    child: Text(
                      _maturityDate == null
                          ? 'Select the date'
                          : formatShortDate(_maturityDate!),
                      style: TextStyle(
                        color: _maturityDate == null
                            ? colors.textBody
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'On this date FinAssist asks what you did with it. Until '
                  'then it never counts as money you can spend.',
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: dangerColorOn(context)),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: const Key('set-aside-save'),
                  style: confirmButtonStyle(),
                  onPressed: _save,
                  child: Text(_isNew ? _addLabel : 'Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
