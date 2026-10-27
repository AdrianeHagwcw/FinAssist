import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../models/debt.dart';
import '../models/wallet.dart';
import '../services/bill_service.dart';
import '../services/debt_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/check_after_save.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/item_card.dart';
import '../widgets/money_text.dart';
import '../widgets/wallet_picker.dart';
import 'bill_calendar_screen.dart';

/// One installment or one amount owed to the user.
class DebtDetailScreen extends StatefulWidget {
  const DebtDetailScreen({
    required this.debt,
    this.liveDebt,
    this.payments,
    this.transactions,
    this.wallets,
    super.key,
  });

  final Debt debt;

  /// Replace the live data. Used by tests.
  final Stream<Debt?>? liveDebt;
  final Stream<List<BillInstance>>? payments;
  final Stream<List<AppTransaction>>? transactions;
  final Stream<List<Wallet>>? wallets;

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen> {
  late final Stream<Debt?> _debt =
      widget.liveDebt ?? DebtService.watchDebt(widget.debt.id);

  late final Stream<List<BillInstance>> _payments =
      widget.payments ??
      (widget.debt.billId == null
          ? Stream.value(const [])
          : BillService.watchInstancesForBill(widget.debt.billId!));

  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ?? WalletService.watchTransactions();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: dangerTextStyle(context),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _delete(Debt debt) async {
    final iOwe = debt.direction == DebtDirection.iOwe;
    final ok = await _confirm(
      title: 'Delete ${debt.name}?',
      message: iOwe
          ? 'Its unpaid payments are removed from your Bill Planner. Payments '
                'you already made stay, because that money really left your '
                'wallet.'
          : 'It stops being tracked. Any money already moved between your '
                'wallets stays recorded.',
      action: 'Delete',
    );
    if (!ok) return;

    await DebtService.deleteDebt(debt);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _recordRepayment(Debt debt) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => RepaymentSheet(debt: debt, wallets: widget.wallets),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<Debt?>(
      stream: _debt,
      builder: (context, snapshot) {
        final debt = snapshot.data ?? widget.debt;
        final iOwe = debt.direction == DebtDirection.iOwe;

        return Scaffold(
          backgroundColor: colors.pageBackground,
          appBar: AppBar(
            title: Text(
              debt.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            backgroundColor: appPrimaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Options',
                onSelected: (value) async {
                  if (value == 'delete') _delete(debt);
                  if (value == 'forgive') {
                    final ok = await _confirm(
                      title: 'Stop expecting the rest?',
                      message:
                          'The ${formatPeso(debt.stillOwedToMe)} still owed is '
                          'written off and this is marked settled. No wallet '
                          'changes.',
                      action: 'Write it off',
                    );
                    if (ok) DebtService.forgive(debt);
                  }
                },
                itemBuilder: (context) => [
                  if (!iOwe && debt.status == DebtStatus.active)
                    menuItem(
                      value: 'forgive',
                      label: 'Write off the rest',
                      icon: Icons.volunteer_activism_outlined,
                      color: dangerColorOn(context),
                    ),
                  menuItem(
                    value: 'delete',
                    label: 'Delete',
                    icon: Icons.delete_outline,
                    color: dangerColorOn(context),
                  ),
                ],
              ),
            ],
          ),
          body: iOwe
              ? _InstallmentBody(
                  debt: debt,
                  payments: _payments,
                  wallets: _wallets,
                )
              : _OwedToMeBody(
                  debt: debt,
                  transactions: _transactions,
                  wallets: _wallets,
                  onRecord: () => _recordRepayment(debt),
                  onUndo: (repayment) async {
                    final ok = await _confirm(
                      title: 'Undo this repayment?',
                      message:
                          '${formatPeso(repayment.amount)} comes back out of '
                          'the wallet and is owed again.',
                      action: 'Undo',
                    );
                    if (ok) DebtService.undoRepayment(debt, repayment);
                  },
                ),
        );
      },
    );
  }
}

class _InstallmentBody extends StatelessWidget {
  const _InstallmentBody({
    required this.debt,
    required this.payments,
    required this.wallets,
  });

  final Debt debt;
  final Stream<List<BillInstance>> payments;
  final Stream<List<Wallet>> wallets;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<List<BillInstance>>(
      stream: payments,
      builder: (context, snapshot) {
        final instances = [...?snapshot.data]
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final progress = DebtProgress.of(debt, instances);
        final last = debt.lastDueDate;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.isPaidOff ? 'Paid off' : 'Still to pay',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  MoneyText(
                    progress.remaining,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 10,
                      backgroundColor: colors.track,
                      valueColor: AlwaysStoppedAnimation(
                        progress.isPaidOff
                            ? confirmColorOn(context)
                            : appPrimaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${formatPeso(progress.paid)} of '
                    '${formatPeso(progress.total)} paid · '
                    '${progress.paymentsLeft} of ${debt.paymentCount} '
                    'payments left',
                    style: TextStyle(fontSize: 13, color: colors.textBody),
                  ),
                  const Divider(height: 28),
                  _Line('Borrowed', formatPeso(debt.principal)),
                  _Line(debt.frequency.eachLabel, formatPeso(debt.perPayment)),
                  if (debt.extraCost > 0)
                    _Line(
                      'More than you borrowed',
                      '${formatPeso(debt.extraCost)} '
                          '(${roundedPercent(debt.extraCostPercent)})',
                    ),
                  if (debt.paidBefore > 0)
                    _Line(
                      'Paid before FinAssist',
                      debt.paidBefore == 1
                          ? '1 payment'
                          : '${debt.paidBefore} payments',
                    ),
                  if (last != null)
                    _Line(
                      'Last payment',
                      debt.hasDifferentLastPayment
                          ? '${formatPeso(debt.finalPayment)} on '
                                '${formatShortDate(last)}'
                          : formatShortDate(last),
                    ),
                  if (debt.note != null) _Line('Notes', debt.note!),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CostOfBorrowing(debt: debt, wallets: wallets, paid: progress.paid),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BillCalendarScreen(),
                  ),
                ),
                style: openButtonStyle(),
                icon: const Icon(Icons.calendar_month),
                label: const Text(
                  'Pay in Bill Planner',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Each payment is a bill, so you pay it, part-pay it, and choose '
              'the wallet there.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.textMuted,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Statement of account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Every payment, what you have paid on it, and what is left to '
              'pay after it.',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            // The plan's own dates are enough to list every payment; only
            // one with no start date waits for its bills.
            if (instances.isEmpty && debt.firstDueDate == null)
              Text(
                'Payments appear here once their month is opened in the Bill '
                'Planner.',
                style: TextStyle(color: context.appColors.textMuted),
              )
            else
              ..._statementRows(context, debt, instances, progress),
          ],
        );
      },
    );
  }
}

/// What borrowing costs, the way a lender has to disclose it: the extra in
/// pesos and as a share of what was borrowed, the true rate a month and a
/// year, the rate the user was told, and how it compares with what their
/// savings earn. Borrowing usually costs far more than saving earns.
class _CostOfBorrowing extends StatelessWidget {
  const _CostOfBorrowing({
    required this.debt,
    required this.wallets,
    required this.paid,
  });

  final Debt debt;
  final Stream<List<Wallet>> wallets;

  /// Everything paid on it so far, before FinAssist too.
  final double paid;

  /// The best yearly rate the user's own accounts earn, after the 20% tax
  /// banks keep, or null when no rate was entered.
  static double? _bestSavingsRate(List<Wallet> wallets) {
    double? best;
    for (final wallet in wallets) {
      final rate = wallet.annualInterestRatePercent;
      if (wallet.archived || rate == null || rate <= 0) continue;
      final kept = afterTax(rate);
      if (best == null || kept > best) best = kept;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final quoted = debt.quotedRate;
    final fromFamily = debt.category == DebtCategory.familyFriend;
    final body = TextStyle(fontSize: 13, height: 1.4, color: colors.textBody);

    return Container(
      key: const Key('installment-cost'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The app's interest icon, as on savings.
              Image.asset(
                'assets/icons/icons8-combo-chart-100.png',
                width: 22,
                height: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'What borrowing costs',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (debt.extraCost <= 0)
            Text(
              'Nothing extra: you pay back exactly what you borrowed.',
              style: body,
            )
          else ...[
            Text(
              debt.fees > 0
                  ? '${formatPeso(debt.extraCost)} more than the '
                        '${formatPeso(debt.amountReceived)} you got: '
                        '${formatPeso(debt.fees)} in fees taken out, and the '
                        'rest interest.'
                  : '${formatPeso(debt.extraCost)} more than you borrowed, '
                        '${roundedPercent(debt.extraCostPercent)} of '
                        '${formatPeso(debt.principal)}.',
              style: body,
            ),
            const SizedBox(height: 4),
            Text(costRateText(debt), style: body),
            // The interest inside each payment, which is how it shows in
            // Transactions and Reports.
            const SizedBox(height: 4),
            Text(
              '${formatPeso(debt.interestOf(1))} of each payment is interest. '
              'Paid so far: '
              '${formatPeso(interestPartOf(paid, debt.interestShare))}.',
              key: const Key('installment-interest-paid'),
              style: body,
            ),
          ],
          if (quoted != null) ...[
            const SizedBox(height: 4),
            Text(
              'Interest they told you: ${percentText(quoted)} '
              '${debt.quotedRatePer.label}'
              // How a loan's interest is charged changes what the rate means.
              '${debt.category.isLoan ? ', ${debt.rateBasis.inSentence}' : ''}.',
              style: body,
            ),
            if (debt.costsMoreThanQuoted) ...[
              const SizedBox(height: 10),
              DialogNote(
                text:
                    'These payments cost more than ${percentText(quoted)} '
                    '${debt.quotedRatePer.label}. Ask the store or lender '
                    'what else is added, such as fees.',
              ),
            ] else if (debt.extraCost > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Interest that stays the same every payment costs more than '
                'it sounds, because you keep paying it on money you have '
                'already paid back.',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ],
          if (debt.extraCost > 0)
            StreamBuilder<List<Wallet>>(
              stream: wallets,
              builder: (context, snapshot) {
                final savings = _bestSavingsRate(snapshot.data ?? const []);
                final yearly = debt.yearlyCostPercent!;
                if (savings != null && savings >= yearly) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '${savings == null ? 'Savings usually earn far less than this.' : 'Your savings earn up to ${roundedPercent(savings)} a year after tax.'} '
                    'Paying this off early usually saves you more than '
                    'keeping that money in savings, if there is no fee for '
                    'paying early. Keep some emergency money first.',
                    style: body,
                  ),
                );
              },
            ),
          const SizedBox(height: 12),
          DialogNote(
            text: fromFamily
                ? 'Between family and friends, interest is only owed if you '
                      'both agreed to it in writing.'
                : 'Lenders and stores must tell you the full cost and the '
                      'yearly rate before you sign. If they did not, ask for '
                      'it.',
          ),
        ],
      ),
    );
  }
}

/// The statement's rows: one per payment in the plan, in the order they fall
/// due, with what is still owed after each one.
///
/// Built from the plan's own schedule rather than from the bills that happen
/// to exist. A payment only becomes a bill when its month is opened, so a
/// fresh twelve-month plan has one bill and eleven payments still to come;
/// a statement that showed only the first would be no statement at all.
/// Where a bill does exist, what was really paid on it is laid over the top.
List<Widget> _statementRows(
  BuildContext context,
  Debt debt,
  List<BillInstance> instances,
  DebtProgress progress,
) {
  final colors = context.appColors;
  final rows = <Widget>[];

  // Counted down from the whole amount payable, so the last row reads zero
  // when the plan is finished.
  var owed = progress.total;

  // Without a start date there is no schedule to lay out, so the bills that
  // exist are all there is to show.
  final first = debt.firstDueDate;
  final schedule = <({int number, DateTime due, double amount})>[];

  if (first == null) {
    final known = [...instances]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    for (var i = 0; i < known.length; i++) {
      schedule.add((
        number: i + 1,
        due: known[i].dueDate,
        amount: known[i].amount,
      ));
    }
  } else {
    for (var number = 1; number <= debt.paymentCount; number++) {
      schedule.add((
        number: number,
        due: lastDueDateFor(first, debt.frequency.recurrence, number),
        amount: number == debt.paymentCount && debt.hasDifferentLastPayment
            ? debt.finalPayment
            : debt.perPayment,
      ));
    }
  }

  for (final payment in schedule) {
    final number = payment.number;
    final due = payment.due;
    final scheduled = payment.amount;

    // Paid before it was tracked: no bill stands for it, but it was paid.
    final paidEarlier = first != null && number <= debt.paidBefore;
    final instance = paidEarlier ? null : _instanceOn(instances, due);
    final amount = instance?.amount ?? scheduled;
    final paid = paidEarlier ? scheduled : instance?.amountPaid ?? 0;
    final stillDue = paidEarlier ? 0.0 : instance?.remaining ?? amount;

    owed = (owed - paid).clamp(0.0, double.infinity).toDouble();

    final settledHere = stillDue <= 0.005;
    final partly = paid > 0.005 && !settledHere;

    rows.add(
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Payment $number of ${schedule.length} · '
                    '${formatShortDate(due)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (paidEarlier)
                  Text(
                    'Paid before FinAssist',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  )
                else if (instance != null)
                  BillStatusBadge(instance: instance)
                else
                  Text(
                    'To come',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    settledHere
                        ? '${formatPeso(amount)} paid in full'
                        : partly
                        ? '${formatPeso(paid)} of ${formatPeso(amount)} paid · '
                              '${formatPeso(stillDue)} still due'
                        : '${formatPeso(amount)} due',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${formatPeso(owed)} left',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // No totals box: the card at the top of the screen already states what
  // has been paid, what is left and how many payments remain, and saying it
  // twice only invites the two to disagree.
  return rows;
}

/// The bill standing for the payment due on [day], or null when that month
/// has not been opened yet.
BillInstance? _instanceOn(List<BillInstance> instances, DateTime day) {
  for (final instance in instances) {
    if (instance.dueDate.year == day.year &&
        instance.dueDate.month == day.month &&
        instance.dueDate.day == day.day) {
      return instance;
    }
  }
  return null;
}

class _OwedToMeBody extends StatelessWidget {
  const _OwedToMeBody({
    required this.debt,
    required this.transactions,
    required this.wallets,
    required this.onRecord,
    required this.onUndo,
  });

  final Debt debt;
  final Stream<List<AppTransaction>> transactions;
  final Stream<List<Wallet>> wallets;
  final VoidCallback onRecord;
  final void Function(AppTransaction repayment) onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settled = debt.status == DebtStatus.settled;
    final fraction = debt.principal <= 0
        ? 0.0
        : (debt.received / debt.principal).clamp(0.0, 1.0).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settled ? 'Settled' : 'Still owed to you',
                style: TextStyle(
                  fontSize: 13,
                  color: context.appColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              MoneyText(
                debt.stillOwedToMe,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 10,
                  backgroundColor: colors.track,
                  valueColor: AlwaysStoppedAnimation(confirmColorOn(context)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${formatPeso(debt.received > 0 ? debt.received : 0)} of '
                '${formatPeso(debt.principal)} paid back',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              ),
              if (debt.dueDate != null || debt.note != null)
                const Divider(height: 28),
              if (debt.dueDate != null)
                _Line('Promised by', formatShortDate(debt.dueDate!)),
              if (debt.note != null) _Line('Notes', debt.note!),
            ],
          ),
        ),
        if (!settled) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRecord,
              style: confirmButtonStyle(),
              icon: const Icon(Icons.check),
              label: const Text(
                'Record a Repayment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text(
          'Repayments',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<Wallet>>(
          stream: wallets,
          builder: (context, walletSnapshot) {
            final walletList = walletSnapshot.data ?? const <Wallet>[];

            return StreamBuilder<List<AppTransaction>>(
              stream: transactions,
              builder: (context, snapshot) {
                final repayments = (snapshot.data ?? const <AppTransaction>[])
                    .where(
                      (t) =>
                          t.debtId == debt.id &&
                          t.type == TransactionType.income,
                    )
                    .toList();

                if (repayments.isEmpty) {
                  return Text(
                    'Nothing paid back yet.',
                    style: TextStyle(color: context.appColors.textMuted),
                  );
                }

                return Column(
                  children: [
                    for (final repayment in repayments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: confirmColorOn(context),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${formatShortDate(repayment.date)} · into '
                                '${_walletName(walletList, repayment.walletId)}',
                                style: TextStyle(color: colors.textPrimary),
                              ),
                            ),
                            MoneyText(
                              repayment.amount,
                              sign: '+',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: confirmColorOn(context),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Undo this repayment',
                              color: dangerColorOn(context),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => onUndo(repayment),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  static String _walletName(List<Wallet> wallets, String? id) {
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.name;
    }
    return 'a wallet';
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: context.appColors.textMuted,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.appColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Records money paid back to the user.
class RepaymentSheet extends StatefulWidget {
  const RepaymentSheet({
    required this.debt,
    this.wallets,
    this.onSave,
    super.key,
  });

  final Debt debt;

  /// Its own feed of wallets unless given one. A live Firestore feed only
  /// hands its data to the first listener, so a sheet can't borrow the one
  /// the screen underneath is already showing.
  final Stream<List<Wallet>>? wallets;

  /// Replaces saving. Used by tests.
  final void Function(double amount, String walletId)? onSave;

  @override
  State<RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends State<RepaymentSheet>
    with CheckAfterSave, WatchesGoals {
  late final _amountController = TextEditingController(
    text: formatAmountInput(widget.debt.stillOwedToMe),
  );
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();
  String? _walletId;

  @override
  void initState() {
    super.initState();
    recheckWhenChanged(_amountController);
    watchGoals(walletsGiven: widget.wallets != null);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', ''));

  /// What stops the repayment being saved as it stands, or null.
  String? _problem(List<Wallet> wallets) {
    final amount = _amount;
    final owed = widget.debt.stillOwedToMe;
    return amount == null || !isRecordableAmount(amount)
        ? minimumAmountError
        : amount > owed + 0.005
        ? 'Only ${formatPeso(owed)} is still owed.'
        : (_walletId ?? defaultWalletId(wallets)) == null
        ? 'Add a wallet first.'
        : null;
  }

  void _save(List<Wallet> wallets) {
    markTriedToSave();
    if (_problem(wallets) != null) return;
    final amount = _amount;
    final walletId = _walletId ?? defaultWalletId(wallets);

    if (widget.onSave != null) {
      widget.onSave!(amount!, walletId!);
    } else {
      DebtService.recordRepayment(
        widget.debt,
        amount: amount!,
        walletId: walletId!,
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <Wallet>[];
              final error = triedToSave ? _problem(wallets) : null;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.debt.name} paid you back',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AmountField(controller: _amountController, label: 'Amount'),
                  const SizedBox(height: 16),
                  if (wallets.isNotEmpty)
                    WalletPicker(
                      wallets: wallets,
                      selectedId: _walletId ?? defaultWalletId(wallets),
                      label: 'Into which wallet?',
                      goals: heldGoals,
                      onChanged: (value) => setState(() => _walletId = value),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      style: TextStyle(
                        color: dangerColorOn(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _save(wallets),
                      style: confirmButtonStyle(),
                      child: const Text(
                        'Record Repayment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
