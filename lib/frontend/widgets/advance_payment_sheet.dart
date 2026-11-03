import 'package:flutter/material.dart';

import '../../backend/models/debt.dart';
import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/bill_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'goal_funding_picker.dart' show fundingWalletKind;
import 'wallet_split_picker.dart';
import 'wallet_picker.dart';

/// Pays the installment's next payment ahead of its due date: the amount the
/// statement of account asks for, out of the wallet the installment was
/// charged to when it was set up. Returns true when it was recorded.
Future<bool> showAdvancePaymentSheet(
  BuildContext context, {
  required Debt debt,
  required DebtNextPayment next,
  Stream<List<Wallet>>? wallets,
}) async {
  final recorded = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) =>
        AdvancePaymentSheet(debt: debt, next: next, wallets: wallets),
  );
  if (recorded == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment ${next.number} of ${debt.name} recorded.'),
        backgroundColor: appConfirmGreen,
      ),
    );
  }
  return recorded == true;
}

/// Records one payment before the Bill Planner expects it. Only the amount
/// is asked: the wallet was chosen when the installment was set up, and is
/// charged here without asking again, its free balance checked first.
class AdvancePaymentSheet extends StatefulWidget {
  const AdvancePaymentSheet({
    required this.debt,
    required this.next,
    this.wallets,
    this.goals,
    this.onPay,
    super.key,
  });

  final Debt debt;
  final DebtNextPayment next;

  /// Replace the live data. Used by tests.
  final Stream<List<Wallet>>? wallets;
  final Stream<List<Goal>>? goals;

  /// Records the payment. Tests pass a fake instead of Firestore.
  final void Function(List<BillPaymentPart> parts, DateTime date)? onPay;

  @override
  State<AdvancePaymentSheet> createState() => _AdvancePaymentSheetState();
}

class _AdvancePaymentSheetState extends State<AdvancePaymentSheet>
    with CheckAfterSave, WatchesGoals {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  /// When the payment is recorded as paid: the day the plan itself says it
  /// falls due, not the day it happens to be paid. The statement of account
  /// asks for a payment on that day, so paying ahead still lands on the
  /// plan's own date, and the record lines up with the schedule.
  DateTime get _date => widget.next.due;

  /// Starts on what this payment asks for; the user follows the statement
  /// of account, which can ask for less of it.
  late final _amountController = TextEditingController(
    // With commas, as typing would give it.
    text: widget.next.amount > 0
        ? formatPeso(widget.next.amount).replaceFirst('₱', '')
        : '',
  );

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
  /// the accounts (or there was never one, which the button hides).
  Wallet? _designated(List<Wallet> wallets) {
    final id = widget.debt.paidWithWalletId;
    if (id == null) return null;
    return wallets
        .where((wallet) => wallet.id == id && !wallet.archived)
        .firstOrNull;
  }

  String? _problem(List<Wallet> wallets) {
    if (!isRecordableAmount(_amount)) return minimumAmountError;
    final wallet = _designated(wallets);
    if (wallet == null) return null;

    if (_amount > widget.next.amount + 0.005) {
      return 'That is ${formatPeso(_amount - widget.next.amount)} more than '
          'payment ${widget.next.number} needs. The rest is paid when it '
          'comes due.';
    }
    final room = splitRoom(SplitPurpose.paying, wallet, heldGoals);
    if (_amount > room + 0.005) {
      return splitRoomMessage(
        wallet,
        amount: _amount,
        room: room,
        goals: heldGoals,
      );
    }
    return null;
  }

  Future<void> _confirm(List<Wallet> wallets) async {
    markTriedToSave();
    if (_problem(wallets) != null) return;
    final wallet = _designated(wallets);
    if (wallet == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record payment ${widget.next.number} ahead of time?'),
        content: Text(
          '${formatPeso(_amount)} comes out of ${wallet.name} for payment '
          '${widget.next.number} of ${widget.debt.paymentCount}, dated '
          '${formatShortDate(_date)} — the day it falls due. The Bill '
          'Planner counts it as settled.',
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
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final parts = [BillPaymentPart(walletId: wallet.id, amount: _amount)];
    final instance = widget.next.instance;
    if (instance == null) return;
    if (widget.onPay != null) {
      widget.onPay!(parts, _date);
    } else {
      BillService.payInstance(instance: instance, parts: parts, date: _date);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final next = widget.next;
    final debt = widget.debt;

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
              final wallet = _designated(wallets);
              final error = triedToSave ? _problem(wallets) : null;
              final breakdown = _breakdown();

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
                          'Pay in advance',
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
                    'Payment ${next.number} of ${debt.paymentCount} on '
                    '${debt.name}, due ${formatShortDate(next.due)}.',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    key: const Key('advance-amount'),
                    controller: _amountController,
                    label: 'Amount you will pay',
                    hint: 'e.g. 2,000',
                    helper:
                        'What your latest statement asks for. It can be '
                        'less; what is left stays owed on this payment.',
                    alwaysShowHint: true,
                    autofocus: false,
                  ),
                  if (breakdown != null) ...[
                    const SizedBox(height: 10),
                    DialogNote(text: breakdown),
                  ],
                  const SizedBox(height: 16),
                  // Not asked for: the plan already says which day this
                  // payment is for, and paying ahead still lands on that
                  // day. So the statement reads the same as the schedule.
                  InputDecorator(
                    decoration: dialogFieldDecoration(context, 'Date paid'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatShortDate(next.due),
                            key: const Key('advance-date'),
                          ),
                        ),
                        Image.asset(
                          'assets/icons/icons8-calendar-96.png',
                          width: 22,
                          height: 22,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The day this payment falls due on your plan, so the '
                    'statement of account matches the schedule.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Paying from',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (wallet == null) ...[
                    const DialogNote(
                      text:
                          'The wallet this installment was charged to is '
                          'not in Accounts any more. Pay this payment in the '
                          'Bill Planner instead.',
                    ),
                  ] else
                    _walletCard(context, wallet),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const Key('advance-error'),
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
                      key: const Key('advance-button'),
                      onPressed: wallet == null
                          ? null
                          : () => _confirm(wallets),
                      style: confirmButtonStyle(),
                      child: const Text(
                        'Pay in advance',
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

  /// Where the money goes, in one sentence: the whole payment, or what stays
  /// owed when the statement asked for less. An installment carries no
  /// interest, so there is nothing to split apart.
  String? _breakdown() {
    final amount = _amount;
    if (amount <= 0) return null;
    final owed = widget.next.amount;
    if (amount < owed - 0.005) {
      return "That leaves ${formatPeso(owed - amount)} of this payment "
          'still owed, until the statement says the rest.';
    }
    return 'All of it goes to payment ${widget.next.number}: an installment '
        'carries no interest.';
  }

  /// The single wallet this installment was charged to, shown the way the
  /// paying-from cards always look: kind, and what is free in it now.
  Widget _walletCard(BuildContext context, Wallet wallet) {
    final colors = context.appColors;
    final room = splitRoom(SplitPurpose.paying, wallet, heldGoals);
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
                if (wallet.hasRecordedBalance)
                  Text('$kind · ${formatPeso(room)} available', style: note)
                else
                  Text(
                    '$kind · No balance recorded, so nothing can come '
                    'from it.',
                    style: note,
                  ),
                Text(
                  'Chosen when the installment was set up.',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
