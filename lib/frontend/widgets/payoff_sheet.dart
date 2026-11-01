import 'package:flutter/material.dart';

import '../../backend/models/debt.dart';
import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/bill_service.dart';
import '../../backend/services/debt_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'goal_funding_picker.dart' show fundingWalletKind;
import 'wallet_picker.dart';
import 'wallet_split_picker.dart';

/// Pays an installment or debt off before its schedule ends: the amount the
/// lender or store asked for, from the wallets it came out of. Returns true
/// when it was recorded.
Future<bool> showPayoffSheet(
  BuildContext context, {
  required Debt debt,
  required DebtProgress progress,
}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => PayoffSheet(debt: debt, progress: progress),
  );
  if (paid == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${debt.name} is paid off.'),
        backgroundColor: appConfirmGreen,
      ),
    );
  }
  return paid == true;
}

class PayoffSheet extends StatefulWidget {
  const PayoffSheet({
    required this.debt,
    required this.progress,
    this.today,
    this.wallets,
    this.goals,
    this.onPayOff,
    super.key,
  });

  final Debt debt;
  final DebtProgress progress;
  final DateTime? today;

  /// Replace the live data. Used by tests.
  final Stream<List<Wallet>>? wallets;
  final Stream<List<Goal>>? goals;

  /// Records the payoff. Tests pass a fake instead of Firestore.
  final void Function(List<BillPaymentPart> parts, DateTime date)? onPayOff;

  @override
  State<PayoffSheet> createState() => _PayoffSheetState();
}

class _PayoffSheetState extends State<PayoffSheet>
    with CheckAfterSave, WatchesGoals {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();
  late final DateTime _today = widget.today ?? DateTime.now();
  late DateTime _date = DateTime(_today.year, _today.month, _today.day);

  /// Starts on what is left on the plan, the usual payoff; the user changes
  /// it to what the lender actually asked for.
  late final _amountController = TextEditingController(
    // With commas, as typing would give it.
    text: widget.progress.remaining > 0
        ? formatPeso(widget.progress.remaining).replaceFirst('₱', '')
        : '',
  );
  Map<String, double> _amounts = const {};

  @override
  void initState() {
    super.initState();
    watchGoals(given: widget.goals, walletsGiven: widget.wallets != null);
    _amountController.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _amountController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  double get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '')) ?? 0;

  /// The wallet the installment was charged to, or null when it is not in
  /// the accounts, or there never was one. It takes no rising: when it is
  /// there, this sheet charges it and asks nothing else.
  Wallet? _designated(List<Wallet> wallets) {
    final id = widget.debt.paidWithWalletId;
    if (id == null) return null;
    return wallets
        .where((wallet) => wallet.id == id && !wallet.archived)
        .firstOrNull;
  }

  String? _problem(List<Wallet> wallets) {
    if (!isRecordableAmount(_amount)) return minimumAmountError;
    final designated = _designated(wallets);
    if (designated != null) {
      final room = splitRoom(SplitPurpose.paying, designated, heldGoals);
      if (_amount > room + 0.005) {
        return splitRoomMessage(
          designated,
          amount: _amount,
          room: room,
          goals: heldGoals,
        );
      }
      return null;
    }
    return walletSplitProblem(
      purpose: SplitPurpose.paying,
      amounts: _amounts,
      wallets: wallets,
      goals: heldGoals,
      target: _amount,
      matchTarget: true,
      allowBoth: false,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_today.year - 5),
      lastDate: _today,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _confirm(List<Wallet> wallets) async {
    markTriedToSave();
    if (_problem(wallets) != null) return;

    final left = widget.progress.paymentsLeft;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pay ${widget.debt.name} off early?'),
        content: Text(
          '${formatPeso(_amount)} comes out of your wallets'
          '${left > 0 ? ', and the ${left == 1 ? 'payment' : '$left payments'} left ${left == 1 ? 'is' : 'are'} taken off the Bill Planner' : ''}. '
          'You can undo this from its page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: confirmTextStyle(context),
            child: const Text('Pay it off early'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final designated = _designated(wallets);
    final parts = [
      if (designated != null)
        BillPaymentPart(walletId: designated.id, amount: _amount)
      else
        for (final entry in _amounts.entries)
          if (entry.value > 0)
            BillPaymentPart(walletId: entry.key, amount: entry.value),
    ];
    if (widget.onPayOff != null) {
      widget.onPayOff!(parts, _date);
    } else {
      DebtService.payOffEarly(debt: widget.debt, parts: parts, date: _date);
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// What the charge lands in, shown the way the paying-from cards always
  /// look: kind, and what is free in it now.
  Widget _designatedCard(BuildContext context, Wallet wallet) {
    final colors = context.appColors;
    final room = splitRoom(SplitPurpose.paying, wallet, heldGoals);
    final held = goalMoneyInWallet(heldGoals, wallet.id);
    final kind = fundingWalletKind(wallet);
    final note = TextStyle(fontSize: 12, color: colors.textBody);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Image.asset(wallet.iconAsset, width: 28, height: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (wallet.hasRecordedBalance) ...[
                  Text('$kind · ${formatPeso(room)} available', style: note),
                  if (held > 0.005)
                    Text('${formatPeso(held)} set aside for goals', style: note),
                ] else
                  Text(
                    '$kind · No balance recorded, so nothing can come '
                    'from it.',
                    style: note,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Where the money goes, in one sentence: what is still owed of the
  /// money borrowed, and interest; or a discount when it is less. An
  /// installment carries no interest, so its payments are all there is.
  String? _breakdown() {
    final amount = _amount;
    if (amount <= 0) return null;
    final debt = widget.debt;
    if (!debt.category.isLoan) {
      final left = widget.progress.remaining;
      if (amount < left - 0.005) {
        return "That's ${formatPeso(left - amount)} less than what is left "
            'on the plan: they gave you a discount.';
      }
      return 'All of it goes to the payments left: no interest.';
    }
    final left = debt.loanLeft(widget.progress.paid);
    final split = debt.payoffSplit(amount, widget.progress.paid);
    if (split.interest > 0.005) {
      return 'Of this, ${formatPeso(split.toLoan)} finishes paying what you '
          'borrowed, and ${formatPeso(split.interest)} is interest or a fee '
          'for paying early.';
    }
    if (amount < left - 0.005) {
      return "That's ${formatPeso(left - amount)} less than what you still "
          'owe on it: they gave you a discount.';
    }
    return 'All of it goes to what you borrowed: no interest.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = widget.progress;
    final breakdown = _breakdown();

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data;
              if (wallets == null) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final error = triedToSave ? _problem(wallets) : null;

              return Column(
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Paid it off early',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    '${widget.debt.name}: ${formatPeso(progress.remaining)} '
                    'left on the plan, in ${progress.paymentsLeft} '
                    '${progress.paymentsLeft == 1 ? 'payment' : 'payments'}.',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    key: const Key('payoff-amount'),
                    controller: _amountController,
                    label: 'Amount you paid to finish it',
                    hint: 'e.g. 13,500',
                    helper: widget.debt.category.isLoan
                        ? 'What the lender or store asked for. It can be less '
                              "than what's left if they took off some interest."
                        : 'What the store asked for. It can be less than what '
                              'is left if they gave a discount.',
                    alwaysShowHint: true,
                    autofocus: false,
                  ),
                  if (breakdown != null) ...[
                    const SizedBox(height: 10),
                    DialogNote(text: breakdown),
                  ],
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: dialogFieldDecoration(context, 'Date paid'),
                      child: Row(
                        children: [
                          Expanded(child: Text(formatShortDate(_date))),
                          Image.asset(
                            'assets/icons/icons8-calendar-96.png',
                            width: 22,
                            height: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_designated(wallets) != null) ...[
                    Text(
                      'Paying from',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _designatedCard(context, _designated(wallets)!),
                    const SizedBox(height: 8),
                    Text(
                      'The wallet this installment was charged to. To pay '
                      'from somewhere else, pay it in the Bill Planner.',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ] else
                    WalletSplitPicker(
                      key: const ValueKey('payoff-from'),
                      wallets: wallets,
                      goals: heldGoals,
                      purpose: SplitPurpose.paying,
                      target: _amount,
                      matchTarget: true,
                      // Like any bill: from cash on hand or the bank, not both.
                      allowBoth: false,
                      onChanged: (amounts) => setState(() => _amounts = amounts),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const Key('payoff-error'),
                      style: TextStyle(
                        color: dangerColorOn(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const Key('payoff-button'),
                      onPressed: () => _confirm(wallets),
                      style: confirmButtonStyle(),
                      child: const Text(
                        'Pay it off early',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This records the payment. It does not pay anyone for '
                    'real.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
