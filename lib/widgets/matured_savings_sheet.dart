import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
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
  void Function(DateTime nextDate)? onRollOver,
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
  final void Function(DateTime nextDate)? onRollOver;

  @override
  State<MaturedSavingsSheet> createState() => _MaturedSavingsSheetState();
}

class _MaturedSavingsSheetState extends State<MaturedSavingsSheet> {
  late final _amountController = TextEditingController(
    text: formatAmountInput(widget.wallet.balance),
  );
  late String? _toWalletId = _destinations.isEmpty
      ? null
      : _destinations.first.id;
  String? _error;

  /// Anywhere the money can land, including the bills and savings wallets.
  /// Only the record that matured is left out.
  List<Wallet> get _destinations => [
    for (final wallet in widget.wallets)
      if (!wallet.archived && wallet.id != widget.wallet.id) wallet,
  ];

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
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

    if (widget.onRollOver != null) {
      widget.onRollOver!(picked);
    } else {
      WalletService.rollOverMaturity(widget.wallet, picked);
    }
    if (mounted) Navigator.pop(context, true);
  }

  void _settle() {
    final amount = _typed;
    if (amount == null || !isRecordableAmount(amount)) {
      setState(() => _error = minimumAmountError);
      return;
    }
    final toWalletId = _toWalletId;
    if (toWalletId == null) {
      setState(() => _error = 'Add another wallet to move it into.');
      return;
    }

    if (widget.onSettle != null) {
      widget.onSettle!(amount, toWalletId);
    } else {
      WalletService.settleMatured(
        wallet: widget.wallet,
        received: amount,
        toWalletId: toWalletId,
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final due = widget.wallet.maturityDate;

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
                decoration: dialogFieldDecoration(
                  context,
                  'Amount you received',
                ).copyWith(prefixText: '₱ '),
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
                  onChanged: (value) => setState(() => _toWalletId = value),
                ),
              const SizedBox(height: 6),
              Text(
                'Put it in Bills or Savings and it stays out of your daily '
                'spending money.',
                style: TextStyle(fontSize: 12, color: colors.textBody),
              ),
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
