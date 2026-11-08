import 'package:flutter/material.dart';

import '../../backend/models/bill.dart';
import '../../backend/models/debt.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/bill_service.dart';
import '../../backend/services/debt_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/ph_time.dart';
import '../widgets/debt_payment_flow.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/due_soon_notice.dart';
import '../widgets/installment_form_sheet.dart';
import '../widgets/item_card.dart';
import '../widgets/money_text.dart';
import '../widgets/payoff_sheet.dart';

/// One installment's page: its payments, what is paid, and the statement.
class InstallmentDetailScreen extends _DebtDetailScreenBase {
  const InstallmentDetailScreen({
    required super.debt,
    super.liveDebt,
    super.payments,
    super.wallets,
    super.interestCharges,
    super.today,
    super.key,
  });
}

/// One borrowed amount's page: what it costs, its payments, and the
/// statement.
class LoanDetailScreen extends _DebtDetailScreenBase {
  const LoanDetailScreen({
    required super.debt,
    super.liveDebt,
    super.payments,
    super.wallets,
    super.interestCharges,
    super.today,
    super.key,
  });
}

/// What both pages share: the live record, its payments, the wallets, and
/// the wording that follows whether it is a loan.
class _DebtDetailScreenBase extends StatefulWidget {
  const _DebtDetailScreenBase({
    required this.debt,
    this.liveDebt,
    this.payments,
    this.wallets,
    this.interestCharges,
    this.today,
    super.key,
  });

  final Debt debt;

  /// Replace the live data. Used by tests.
  final Stream<Debt?>? liveDebt;
  final Stream<List<BillInstance>>? payments;
  final Stream<List<Wallet>>? wallets;
  final Stream<List<FixedInterestCharge>>? interestCharges;

  /// The day this page is read on, which decides whether a payment is due
  /// yet. Philippine time by default; tests set it.
  final DateTime? today;

  @override
  State<_DebtDetailScreenBase> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<_DebtDetailScreenBase> {
  /// A screen can listen to one of these streams from more than one place,
  /// and a row rebuilt as the list scrolls listens again. A Firestore watch
  /// is already broadcast, but a plain stream (or one a test supplies) is
  /// not, so share it: never open the same stream twice.
  static Stream<T> _shared<T>(Stream<T> stream) =>
      stream.isBroadcast ? stream : stream.asBroadcastStream();

  late final Stream<Debt?> _debt = _shared(
    widget.liveDebt ?? DebtService.watchDebt(widget.debt.id),
  );

  late final Stream<List<BillInstance>> _payments = _shared(
    widget.payments ??
        (widget.debt.billId == null
            ? Stream.value(const [])
            : BillService.watchInstancesForBill(widget.debt.billId!)),
  );

  late final Stream<List<Wallet>> _wallets = _shared(
    widget.wallets ?? WalletService.watchWallets(includeArchived: true),
  );

  late final Stream<List<FixedInterestCharge>> _interestCharges = _shared(
    widget.interestCharges ??
        (widget.debt.fixedInterestAmount == null
            ? Stream.value(const <FixedInterestCharge>[])
            : DebtService.watchFixedInterestCharges(widget.debt.id)),
  );

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
          'you already made stay: that money really left your wallets, and '
          'deleting does not put it back.',
      action: 'Delete',
    );
    if (!ok) return;

    await DebtService.deleteDebt(debt);
    if (mounted) Navigator.pop(context);
  }

  /// Whether the plan can still be corrected. Installments only, and only
  /// until a payment has been made on any part of it: from then it is the
  /// record of what was agreed, so it stays as it is.
  ///
  /// Counted the same way the statement counts it, so what this offers is
  /// exactly what the payments on the page say.
  bool _editable(Debt debt, List<BillInstance> instances) {
    if (debt.category.isLoan) return false;
    if (debt.paidOffEarly || debt.status == DebtStatus.settled) return false;
    return DebtProgress.of(debt, instances).paymentsMade == 0;
  }

  /// Corrects the plan, which the form refuses if a payment was made while
  /// it was open.
  Future<void> _edit(Debt debt) =>
      showInstallmentFormSheet(context, existing: debt);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<Debt?>(
      stream: _debt,
      builder: (context, snapshot) {
        final debt = snapshot.data ?? widget.debt;

        // Read once, here, and handed down: the menu needs the payments to
        // know whether the plan can still be edited, and the page below
        // shows them. One stream is listened to once, so it is not opened
        // a second time for the menu.
        return StreamBuilder<List<BillInstance>>(
          stream: _payments,
          builder: (context, payments) {
            final instances = [...?payments.data]
              ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
            final editable = _editable(debt, instances);

            return Scaffold(
              backgroundColor: colors.pageBackground,
              appBar: AppBar(
                title: Text(
                  debt.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: appPrimaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  PopupMenuButton<String>(
                    tooltip: 'Options',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _edit(debt);
                        case 'payoff':
                          showPayoffSheet(
                            context,
                            debt: debt,
                            progress: DebtProgress.of(debt, instances),
                          );
                        case 'delete':
                          _delete(debt);
                      }
                    },
                    itemBuilder: (context) {
                      // Finishing a loan in one go stays reachable, but the
                      // page's own button is Pay in advance now, like an
                      // installment's.
                      final canPayOffEarly =
                          debt.category.isLoan &&
                          debt.billId != null &&
                          !debt.paidOffEarly &&
                          debt.status != DebtStatus.settled &&
                          !DebtProgress.of(debt, instances).isPaidOff;
                      return [
                        // Blue, the way opening something is, because it
                        // changes what is there rather than taking it away.
                        if (editable)
                          menuItem(
                            value: 'edit',
                            label: 'Edit',
                            icon: Icons.edit_outlined,
                            color: appPrimaryBlue,
                          ),
                        if (canPayOffEarly)
                          menuItem(
                            value: 'payoff',
                            label: 'Pay it off early',
                            icon: Icons.check_circle_outline,
                            color: appPrimaryBlue,
                          ),
                        menuItem(
                          value: 'delete',
                          label: 'Delete',
                          icon: Icons.delete_outline,
                          color: dangerColorOn(context),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              body: _DetailBody(
                debt: debt,
                instances: instances,
                wallets: _wallets,
                interestCharges: _interestCharges,
                today: widget.today ?? philippineNow(),
              ),
            );
          },
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.debt,
    required this.instances,
    required this.wallets,
    required this.interestCharges,
    required this.today,
  });

  final Debt debt;

  /// The payments of the plan, oldest first, as the page reads them. Read
  /// once by the screen above, which needs them too.
  final List<BillInstance> instances;

  final Stream<List<Wallet>> wallets;
  final Stream<List<FixedInterestCharge>> interestCharges;

  /// The day the page is read on, Philippine time.
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = DebtProgress.of(debt, instances);
    final last = debt.lastDueDate;
    // What Pay Now takes, read the same way the button below acts on it, so
    // what the page says and what pressing it does can never disagree: the
    // payment waiting in the period the plan is in — the month for a plan
    // paid monthly, the day for one paid daily — from the plan's own dates,
    // there even for a period the Bill Planner has not opened yet. Null once
    // that period's due is paid: what waits then belongs to the next period,
    // which is what paying ahead of the schedule is for.
    final pay = PayNowState.read(debt, instances, today);
    final next = pay.next;
    final owing = pay.dueNow ? next : null;
    final canPayAhead = pay.canPayAhead;
    final fallsDueThisMonth = pay.fallsDueThisMonth;
    final payNowNote = owing != null
        ? 'Payment ${owing.number} of ${debt.paymentCount} is '
              '${DueSoonNotice.whenLabel(owing.due, today)}. Pay it from the '
              'wallet you want.'
        : pay.byMonth
        ? fallsDueThisMonth
              ? canPayAhead
                    ? 'This month\'s due is paid. What comes next can be paid '
                          'ahead of its date.'
                    : 'This month\'s due is paid.'
              : 'Nothing falls due this month.'
        : next == null
        ? 'Every payment of this plan is paid.'
        : canPayAhead
        ? 'Nothing is due ${pay.periodWord}. What comes next can be paid '
              'ahead of its date.'
        : 'Nothing is due ${pay.periodWord}. Payment ${next.number} of '
              '${debt.paymentCount} falls due on ${formatShortDate(next.due)}.';

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
              _Line(
                debt.balanceBasedSchedule
                    ? 'Principal at setup'
                    : debt.category.isLoan
                    ? 'Borrowed'
                    : 'Price',
                formatPeso(debt.principal),
              ),
              if (debt.balanceBasedSchedule) ...[
                _Line(
                  'Outstanding principal',
                  formatPeso(debt.loanLeft(progress.paid)),
                ),
                _Line('Accrued interest', formatPeso(debt.accruedInterest)),
                _Line('Total amount due', formatPeso(progress.remaining)),
              ],
              _Line(debt.frequency.eachLabel, formatPeso(debt.perPayment)),
              if (debt.paidWithWalletId != null || debt.paidWithLabel != null)
                StreamBuilder<List<Wallet>>(
                  stream: wallets,
                  builder: (context, snapshot) {
                    final charged = [
                      for (final wallet in snapshot.data ?? const <Wallet>[])
                        if (wallet.id == debt.paidWithWalletId) wallet,
                    ].firstOrNull;
                    return _Line(
                      'Wallet used',
                      charged?.name ??
                          debt.paidWithLabel ??
                          debt.paidWithWalletId!,
                    );
                  },
                ),
              if (debt.category.isLoan && debt.extraCost > 0)
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
        // Interest belongs to borrowed money. An installment's price is
        // the whole of what is paid, so there is no cost to disclose.
        if (debt.category.isLoan) ...[
          _CostOfBorrowing(debt: debt, wallets: wallets, paid: progress.paid),
          const SizedBox(height: 16),
        ],
        if (debt.fixedInterestAmount != null &&
            debt.interestChargedPer != null &&
            debt.status == DebtStatus.active) ...[
          SizedBox(
            width: double.infinity,
            child: debt.nextInterestDueDate == null
                ? OutlinedButton.icon(
                    key: const Key('set-interest-due-date'),
                    onPressed: () =>
                        _setInterestSchedule(context, debt: debt, today: today),
                    style: openButtonStyle(),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Set next interest charge date'),
                  )
                : _scheduledInterestChargeDate(debt) != null &&
                      _isDue(_scheduledInterestChargeDate(debt)!, today)
                ? OutlinedButton.icon(
                    key: const Key('record-fixed-interest'),
                    onPressed: () => _recordFixedInterestCharge(
                      context,
                      debt: debt,
                      date: today,
                    ),
                    style: openButtonStyle(),
                    icon: const Icon(Icons.add_card_outlined),
                    label: const Text('Record interest charge'),
                  )
                : const SizedBox.shrink(),
          ),
          if (debt.nextInterestDueDate == null ||
              (_scheduledInterestChargeDate(debt) != null &&
                  _isDue(_scheduledInterestChargeDate(debt)!, today)))
            const SizedBox(height: 12),
        ],
        if (!progress.isPaidOff) ...[
          // This month's due, always here: Pay Now takes it whenever it is
          // pressed, and so it stands above paying ahead of the schedule,
          // which is only for what comes after it. Green, the way
          // committing money is, where opening something is blue.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('pay-now'),
              onPressed: () =>
                  payDebtNow(context, debt, instances: instances, today: today),
              style: confirmButtonStyle(),
              child: const Text(
                'Pay Now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            payNowNote,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
          ),
          // Paying ahead of schedule: the next payment, in advance, from the
          // wallet the plan named when it was set up. Only once this month's
          // due is paid, so "in advance" never takes the place of the one
          // owed now. A loan that did not name a wallet is paid when it
          // falls due instead.
          if (debt.billId != null) ...[
            if (canPayAhead) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('advance-open'),
                  onPressed: () => payDebtInAdvance(
                    context,
                    debt,
                    instances: instances,
                    today: today,
                  ),
                  style: openButtonStyle(),
                  child: const Text(
                    'Pay in advance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
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
          'Payments and interest charges together, with what is left after '
          'each one.',
          style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
        ),
        const SizedBox(height: 12),
        _statementScheduleCard(context, debt: debt, today: today),
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
          StreamBuilder<List<FixedInterestCharge>>(
            stream: interestCharges,
            builder: (context, snapshot) {
              if (snapshot.hasError && debt.accruedInterest > 0) {
                return const Text(
                  'Could not load recorded interest charges for the statement.',
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  debt.accruedInterest > 0) {
                return const Text('Loading recorded interest charges…');
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: _statementRows(
                  context,
                  debt,
                  instances,
                  progress,
                  charges: snapshot.data ?? const [],
                ),
              );
            },
          ),
      ],
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

bool _isDue(DateTime due, DateTime today) => !DateTime(
  due.year,
  due.month,
  due.day,
).isAfter(DateTime(today.year, today.month, today.day));

DateTime? _scheduledInterestChargeDate(Debt debt) =>
    debt.interestPeriodsCharged == 0
    ? debt.firstInterestChargeDate ??
          debt.interestScheduleAnchor ??
          debt.nextInterestDueDate
    : debt.nextInterestDueDate;

Future<void> _setInterestSchedule(
  BuildContext context, {
  required Debt debt,
  required DateTime today,
}) async {
  final firstChargeDate = await showDatePicker(
    context: context,
    initialDate: today,
    firstDate: DateTime(today.year - 100),
    lastDate: DateTime(today.year + 50),
  );
  if (firstChargeDate == null || !context.mounted) return;

  final saved = await DebtService.setInterestSchedule(
    debt: debt,
    firstChargeDate: firstChargeDate,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        saved
            ? 'Next interest charge date saved.'
            : 'The interest schedule could not be updated.',
      ),
    ),
  );
}

/// Records a due charge if automatic reconciliation has not already done so.
Future<void> _recordFixedInterestCharge(
  BuildContext context, {
  required Debt debt,
  required DateTime date,
}) async {
  final amount = debt.fixedInterestAmount;
  final period = debt.interestChargedPer;
  final dueDate = _scheduledInterestChargeDate(debt);
  if (amount == null || period == null || dueDate == null) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Record interest charge?'),
      content: Text(
        'Add ${formatPeso(amount)} for the ${period.label.toLowerCase()} '
        'period due ${formatShortDate(dueDate)} to accrued interest? This '
        'does not move money or change your payment schedule.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Record charge'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final result = await DebtService.recordFixedInterestCharge(
    debt: debt,
    date: date,
  );
  if (!context.mounted) return;
  final message = switch (result) {
    FixedInterestChargeResult.recorded =>
      '${formatPeso(amount)} interest recorded. No money moved.',
    FixedInterestChargeResult.alreadyRecorded =>
      'Interest for this period was already recorded.',
    FixedInterestChargeResult.unavailable =>
      'This interest charge could not be recorded.',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      key: const Key('loan-cost'),
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
                debt.balanceBasedSchedule
                    ? 'Debt details'
                    : 'What borrowing costs',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (debt.balanceBasedSchedule)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance when added: ${formatPeso(debt.principal)}.',
                  style: body,
                ),
                if (debt.originalPrincipal != null)
                  Text(
                    'Original debt amount: ${formatPeso(debt.originalPrincipal!)}.',
                    style: body,
                  ),
                if (debt.loanDuration != null)
                  Text(
                    'Debt duration: ${debt.loanDuration} '
                    '${debt.loanDurationUnit == 'years' ? 'years' : 'months'}.',
                    style: body,
                  ),
                if (debt.loanStartDate != null)
                  Text(
                    'Debt start date: ${formatShortDate(debt.loanStartDate!)}.',
                    style: body,
                  ),
                Text(
                  'Fixed interest charges follow their own schedule and stay '
                  'separate from principal payments.',
                  style: body,
                ),
              ],
            )
          else if (debt.extraCost <= 0)
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
              key: const Key('loan-interest-paid'),
              style: body,
            ),
          ],
          if (quoted != null) ...[
            const SizedBox(height: 4),
            Text(
              debt.interestPeriod == null
                  ? 'Interest they told you: ${percentText(quoted)} '
                        '${debt.quotedRatePer.label}'
                        '${debt.category.isLoan ? ', ${debt.rateBasis.inSentence}' : ''}.'
                  : 'Interest rate they told you: ${percentText(quoted)} '
                        '${_interestPeriodLabel(debt.interestPeriod!)}.',
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
            ] else if (debt.extraCost > 0 && debt.interestPeriod == null) ...[
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

/// Interest schedule details shown above the statement's transactions.
Widget _statementScheduleCard(
  BuildContext context, {
  required Debt debt,
  required DateTime today,
}) {
  final colors = context.appColors;
  final hasFixedInterest =
      debt.fixedInterestAmount != null && debt.interestChargedPer != null;
  final nextInterestDate = debt.nextInterestDueDate;
  final nextInterestStatus = debt.status != DebtStatus.active
      ? 'No upcoming charge'
      : nextInterestDate == null
      ? 'Not set'
      : _isDue(nextInterestDate, today)
      ? 'Due'
      : 'Upcoming';

  return Container(
    key: const Key('statement-interest-information'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: colors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interest information',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (!hasFixedInterest)
          Text(
            debt.quotedRate != null || debt.extraCost > 0
                ? 'No fixed interest schedule.'
                : 'No Interest',
            style: TextStyle(fontSize: 13, color: colors.textBody),
          )
        else ...[
          _Line('Fixed interest amount', formatPeso(debt.fixedInterestAmount!)),
          _Line('Interest charging frequency', debt.interestChargedPer!.label),
          Container(
            key: const Key('statement-next-interest-charge-date'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primaryTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.primaryText),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next Interest Charge Date',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textBody,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        debt.status != DebtStatus.active
                            ? 'No upcoming charge'
                            : nextInterestDate == null
                            ? 'Not set'
                            : formatShortDate(nextInterestDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  nextInterestStatus,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

/// The statement's rows: payments and fixed-interest charges in date order,
/// with what is still owed after each one.
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
  DebtProgress progress, {
  List<FixedInterestCharge> charges = const [],
}) {
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

  // Counted down from the income side of the plan, so the last row reads
  // zero when the plan is finished. A plan paid off early reports its paid
  // amount as its total, so the plan's own total is used there instead:
  // the whole schedule is still listed, and the balance after each payment
  // must follow that schedule, not the smaller figure the payoff left.
  var owed = debt.paidOffEarly
      ? debt.totalPayable
      : progress.total - debt.accruedInterest;
  final orderedCharges = [...charges]
    ..sort((a, b) => a.chargedAt.compareTo(b.chargedAt));
  var chargeIndex = 0;

  void addStandaloneCharge(FixedInterestCharge charge) {
    owed += charge.amount;
    rows.add(
      Container(
        key: Key('statement-fixed-interest-${charge.periodKey}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interest charge recorded',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Charge date: ${formatShortDate(charge.chargedAt)} · '
                    'Amount: ${formatPeso(charge.amount)}',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Status: Recorded · Date recorded: '
                    '${charge.recordedAt == null ? 'Unavailable' : formatShortDate(charge.recordedAt!)}',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Period due: ${formatShortDate(charge.periodDueDate)}',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                ],
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
      ),
    );
  }

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
    final paymentCharges = <FixedInterestCharge>[];

    while (chargeIndex < orderedCharges.length &&
        orderedCharges[chargeIndex].chargedAt.isBefore(due)) {
      addStandaloneCharge(orderedCharges[chargeIndex++]);
    }
    while (chargeIndex < orderedCharges.length &&
        _sameDate(orderedCharges[chargeIndex].chargedAt, due)) {
      final charge = orderedCharges[chargeIndex++];
      paymentCharges.add(charge);
      owed += charge.amount;
    }
    final interestAmount = paymentCharges.fold<double>(
      0,
      (total, charge) => total + charge.amount,
    );
    String interestSummary() {
      if (paymentCharges.isEmpty) return '';
      final chargedDates = paymentCharges
          .map((charge) => formatShortDate(charge.chargedAt))
          .toSet()
          .join(', ');
      final recordedDates = paymentCharges
          .map((charge) => charge.recordedAt)
          .whereType<DateTime>()
          .map(formatShortDate)
          .toSet()
          .join(', ');
      return '${formatPeso(interestAmount)} interest recorded; charge date '
          '$chargedDates; date recorded: '
          '${recordedDates.isEmpty ? 'Unavailable' : recordedDates}';
    }

    // Paid before it was tracked: no bill stands for it, but it was paid.
    final paidEarlier = first != null && number <= debt.paidBefore;
    final instance = paidEarlier ? null : _instanceOn(instances, due);
    final amount = instance?.amount ?? scheduled;
    final paid = paidEarlier ? scheduled : instance?.amountPaid ?? 0;
    final stillDue = paidEarlier ? 0.0 : instance?.remaining ?? amount;

    owed = (owed - paid).clamp(0.0, double.infinity).toDouble();

    // Paid off early: the whole schedule still shows. What the payoff made
    // unnecessary is marked as such instead of hidden, so the statement
    // reads like an installment's.
    final notNeeded = debt.paidOffEarly && !paidEarlier && paid <= 0.005;
    final closedByPayoff =
        payoffId != null && instance?.carriedInto == payoffId;

    final settledHere = stillDue <= 0.005;
    final partly = paid > 0.005 && !settledHere;
    final paymentLabel = paymentCharges.isEmpty
        ? 'Payment $number of ${schedule.length}'
        : 'Payment $number + Interest charge';

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
                    '$paymentLabel · ${formatShortDate(due)}',
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
                else if (notNeeded)
                  Text(
                    'Not needed — paid off early',
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
                    [
                      notNeeded
                          ? '${formatPeso(amount)} not needed · paid off early'
                          : closedByPayoff
                          ? '${formatPeso(paid)} paid, the rest when it was paid '
                                'off'
                          : settledHere
                          ? '${formatPeso(amount)} paid in full'
                          : partly
                          ? '${formatPeso(paid)} of ${formatPeso(amount)} paid · '
                                '${formatPeso(stillDue)} still due'
                          : '${formatPeso(amount)} due',
                      if (paymentCharges.isNotEmpty) interestSummary(),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  notNeeded ? '—' : '${formatPeso(owed)} left',
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

  while (chargeIndex < orderedCharges.length) {
    addStandaloneCharge(orderedCharges[chargeIndex++]);
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

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _interestPeriodLabel(String period) => switch (period) {
  'day' => 'daily',
  'week' => 'weekly',
  'month' => 'monthly',
  'year' => 'annually',
  _ => period,
};

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
