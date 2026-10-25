import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

/// Asks what happened to a savings record that has reached its maturity date.
///
/// FinAssist cannot see a real account, so nothing moves until the user says
/// it did. They can take all of it, part of it, roll it over to a new date,
/// or leave it for now.
Future<bool?> showMaturedSavingsSheet(
  BuildContext context, {
  required Wallet wallet,
  required List<Wallet> wallets,
  void Function(double received, String toWalletId)? onSettle,
  void Function(DateTime nextDate, double interest)? onRollOver,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => MaturedSavingsSheet(
      wallet: wallet,
      wallets: wallets,
      onSettle: onSettle,
      onRollOver: onRollOver,
    ),
  );
}

class MaturedSavingsSheet extends StatefulWidget {
  const MaturedSavingsSheet({
    required this.wallet,
    required this.wallets,
    this.onSettle,
    this.onRollOver,
    super.key,
  });

  final Wallet wallet;

  /// Every wallet the money could go to, the matured one aside.
  final List<Wallet> wallets;

  /// Replaces the write. Used by tests.
  final void Function(double received, String toWalletId)? onSettle;

  /// Replaces the write. Gets the interest above the balance, if any.
  final void Function(DateTime nextDate, double interest)? onRollOver;

  @override
  State<MaturedSavingsSheet> createState() => _MaturedSavingsSheetState();
}

class _MaturedSavingsSheetState extends State<MaturedSavingsSheet>
    with CheckAfterSave, WatchesGoals {
  /// The interest the deposit should have paid, after tax, when its rate and
  /// dates are recorded. The amount starts on the balance plus this, so the
  /// user only changes it if the bank paid something else.
  late final double? _expectedInterest = (() {
    final gross = widget.wallet.estimatedTimeDepositInterest();
    return gross == null || gross <= 0 ? null : afterTax(gross);
  })();

  late final _amountController = TextEditingController(
    text: formatAmountInput(widget.wallet.balance + (_expectedInterest ?? 0)),
  );
  late String? _toWalletId = _destinations.isEmpty
      ? null
      : _destinations.first.id;

  /// Anywhere the money can land, including the bills and savings wallets.
  /// Only the record that matured is left out.
  List<Wallet> get _destinations => [
    for (final wallet in widget.wallets)
      // Never into another time deposit: one can't be added to.
      if (!wallet.archived &&
          wallet.id != widget.wallet.id &&
          !wallet.isLockedSavings)
        wallet,
  ];

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    // Tests answer through the callbacks and have no goals behind them.
    watchGoals(
      walletsGiven: widget.onSettle != null || widget.onRollOver != null,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? get _typed {
    final text = _amountController.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    final amount = double.tryParse(text);
    return amount == null || !amount.isFinite ? null : amount;
  }

  /// The line under the field: what this amount leaves behind, or adds.
  String get _consequence {
    final amount = _typed;
    if (amount == null || !isRecordableAmount(amount)) {
      return minimumAmountError;
    }
    final taken = (amount * 100).round() / 100;
    final balance = (widget.wallet.balance * 100).round() / 100;

    if (taken > balance) {
      return '${formatPeso(taken - balance)} above the recorded balance, '
          'counted as interest.';
    }
    if (taken == balance) return 'This record closes.';
    return '${formatPeso(balance - taken)} stays in ${widget.wallet.name}.';
  }

  Future<void> _rollOver() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(today.year + 1, today.month, today.day),
      firstDate: today,
      lastDate: DateTime(today.year + 20),
      helpText: 'When is the new end date?',
    );
    if (picked == null || !mounted) return;

    // Renewed with its interest: what is above the balance is income, kept
    // in the same deposit for the new term.
    final amount = _typed;
    final balance = (widget.wallet.balance * 100).round() / 100;
    final interest = amount == null || amount <= balance
        ? 0.0
        : ((amount - balance) * 100).round() / 100;

    if (widget.onRollOver != null) {
      widget.onRollOver!(picked, interest);
    } else {
      WalletService.rollOverMaturity(widget.wallet, picked, interest: interest);
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// What stops the money being moved out as it stands, or null.
  String? get _problem {
    final amount = _typed;
    if (amount == null || !isRecordableAmount(amount)) {
      return minimumAmountError;
    }
    if (_toWalletId == null) return 'Add another wallet to move it into.';
    return null;
  }

  void _settle() {
    markTriedToSave();
    if (_problem != null) return;
    final amount = _typed!;
    final toWalletId = _toWalletId!;

    if (widget.onSettle != null) {
      widget.onSettle!(amount, toWalletId);
    } else {
      WalletService.settleMatured(
        wallet: widget.wallet,
        received: amount,
        toWalletId: toWalletId,
        goals: heldGoals,
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final due = widget.wallet.maturityDate;
    final error = triedToSave ? _problem : null;

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
                '${widget.wallet.name} is ready to take out',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                due == null
                    ? 'Recorded balance ${formatPeso(widget.wallet.balance)}.'
                    : 'Due ${formatShortDate(due)} · recorded balance '
                          '${formatPeso(widget.wallet.balance)}.',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('matured-amount'),
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [ThousandsSeparatorFormatter()],
                decoration: dialogFieldDecoration(context, 'Amount it came to')
                    .copyWith(
                      prefixText: '₱ ',
                      helperText: _expectedInterest == null
                          ? 'With any interest your bank paid.'
                          : 'Starts on ${formatPeso(widget.wallet.balance)} '
                                'plus about ${formatPeso(_expectedInterest)} '
                                'interest after tax. Change it to what your '
                                'bank paid.',
                      helperMaxLines: 3,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _consequence,
                key: const Key('matured-consequence'),
                style: TextStyle(fontSize: 12, color: colors.primaryText),
              ),
              const SizedBox(height: 16),
              if (_destinations.isNotEmpty)
                WalletPicker(
                  wallets: _destinations,
                  selectedId: _toWalletId,
                  label: 'Where did it go?',
                  allowed: const {
                    WalletPurpose.spending,
                    WalletPurpose.bills,
                    WalletPurpose.savings,
                  },
                  goals: heldGoals,
                  onChanged: (value) => setState(() => _toWalletId = value),
                ),
              const SizedBox(height: 6),
              // Money saved here for a goal goes with it, still set aside.
              if (goalMoneyInWallet(heldGoals, widget.wallet.id) > 0.005) ...[
                Text(
                  '${formatPeso(goalMoneyInWallet(heldGoals, widget.wallet.id))} '
                  'of it is for your goals. It stays set aside for them in '
                  'the wallet you choose.',
                  key: const Key('matured-goal-money'),
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Put it in Bills or Savings and it stays out of your daily '
                'spending money.',
                style: TextStyle(fontSize: 12, color: colors.textBody),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error,
                  style: TextStyle(fontSize: 12, color: dangerColorOn(context)),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: const Key('matured-settle'),
                  style: confirmButtonStyle(),
                  onPressed: _settle,
                  child: const Text('I withdrew it'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  key: const Key('matured-rollover'),
                  onPressed: _rollOver,
                  child: const Text('It was renewed'),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Not yet',
                    style: TextStyle(color: colors.textBody),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
