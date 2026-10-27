import 'package:flutter/material.dart';

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
import '../widgets/dialog_kit.dart';
import '../widgets/item_card.dart';
import '../widgets/money_text.dart';
import '../widgets/payoff_sheet.dart';
import 'bill_calendar_screen.dart';

/// One installment or one amount owed to the user.
class DebtDetailScreen extends StatefulWidget {
  const DebtDetailScreen({
    required this.debt,
    this.liveDebt,
    this.payments,
    this.wallets,
    super.key,
  });

  final Debt debt;

  /// Replace the live data. Used by tests.
  final Stream<Debt?>? liveDebt;
  final Stream<List<BillInstance>>? payments;
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
    final ok = await _confirm(
      title: 'Delete ${debt.name}?',
      message:
          'Its unpaid payments are removed from your Bill Planner. Payments '
          'you already made stay, because that money really left your '
          'wallet.',
      action: 'Delete',
    );
    if (!ok) return;

    await DebtService.deleteDebt(debt);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<Debt?>(
      stream: _debt,
      builder: (context, snapshot) {
        final debt = snapshot.data ?? widget.debt;

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
                onSelected: (value) {
                  if (value == 'delete') _delete(debt);
                },
                itemBuilder: (context) => [
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
          body: _InstallmentBody(
            debt: debt,
            payments: _payments,
            wallets: _wallets,
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
                    debt.paidOffEarly
                        ? 'Paid off early · ${formatShortDate(debt.paidOffAt!)}'
                        : progress.isPaidOff
                        ? 'Paid off'
                        : 'Still to pay',
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
                    debt.paidOffEarly
                        ? '${formatPeso(progress.paid)} paid in all, the last '
                              '${formatPeso(debt.paidOffAmount)} to finish it '
                              'early'
                        : '${formatPeso(progress.paid)} of '
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
            if (!progress.isPaidOff) ...[
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
                'Each payment is a bill, so you pay it, part-pay it, and '
                'choose the wallet there.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.textMuted,
                ),
              ),
              // Finished before its schedule: one payment closes it.
              if (debt.billId != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const Key('payoff-open'),
                    onPressed: () => showPayoffSheet(
                      context,
                      debt: debt,
                      progress: progress,
                    ),
                    style: openOutlineStyle(context, height: 52),
                    child: const Text(
                      'Paid it off early',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ] else if (debt.paidOffEarly)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('payoff-undo'),
                  onPressed: () => _undoPayoff(context, debt),
                  style: dangerOutlineStyle(context, height: 52),
                  child: const Text(
                    'Undo paying it off',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
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

/// Asks, then takes back a payoff made by mistake.
Future<void> _undoPayoff(BuildContext context, Debt debt) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Undo paying it off?'),
      content: Text(
        '${formatPeso(debt.paidOffAmount)} goes back to your wallets, and the '
        'payments that were left are owed again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: dangerTextStyle(context),
          child: const Text('Undo'),
        ),
      ],
    ),
  );
  if (ok == true) await DebtService.undoPayOff(debt);
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

  // The payoff is not one of the plan's dates: it is listed last.
  final payoffId = debt.billId == null
      ? null
      : BillService.payoffInstanceId(debt.billId!);
  final payoff = instances.where((i) => i.id == payoffId).firstOrNull;
  instances = [
    for (final instance in instances)
      if (instance.id != payoffId) instance,
  ];

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

    // Paid off early: only the payments made are listed.
    if (debt.paidOffEarly && !paidEarlier && paid <= 0.005) continue;
    final closedByPayoff =
        payoffId != null && instance?.carriedInto == payoffId;

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
                    closedByPayoff
                        ? '${formatPeso(paid)} paid, the rest when it was paid '
                              'off'
                        : settledHere
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

  if (debt.paidOffEarly) {
    final amount = payoff?.amountPaid ?? debt.paidOffAmount;
    rows.add(
      Container(
        key: const Key('statement-payoff'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: confirmColorOn(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paid off early · ${formatShortDate(debt.paidOffAt!)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatPeso(amount)} to finish it',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                ],
              ),
            ),
            Text(
              '${formatPeso(0)} left',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
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
