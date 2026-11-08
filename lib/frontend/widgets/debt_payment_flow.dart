import 'package:flutter/material.dart';

import '../../backend/models/bill.dart';
import '../../backend/models/debt.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/bill_service.dart';
import '../../backend/services/debt_service.dart';
import '../../backend/utils/date_format.dart';
import 'advance_payment_sheet.dart';
import 'bill_payment_sheet.dart';
import 'mini_notice.dart';

/// What Pay Now has to take on the day it is read: the payment waiting in
/// the period the plan is currently in, whether the plan has a payment in
/// this period at all, and whether what comes next may be paid ahead.
///
/// The period is the one the user chose when the plan was set up — a day, a
/// week, two weeks, half a month, a month, a quarter, half a year, or a year
/// — so a plan paid every day is not asked for "this month's due", and one
/// paid every month keeps the month it always had. Read from the plan's own
/// dates and its [instances], so the note under the button and pressing the
/// button always say the same thing — and so Voice Entry opens exactly the
/// screens the plan's own page does.
class PayNowState {
  const PayNowState({
    required this.next,
    required this.dueNow,
    required this.fallsDueThisMonth,
    required this.canPayAhead,
    required this.frequency,
  });

  /// Reads the state of [debt] on [today] from its payments.
  factory PayNowState.read(
    Debt debt,
    List<BillInstance> instances,
    DateTime today,
  ) {
    final billId = debt.billId;
    // The early-payoff record is not one of the plan's payments.
    final known = billId == null
        ? instances
        : [
            for (final instance in instances)
              if (instance.id != BillService.payoffInstanceId(billId)) instance,
          ];
    final next = billId == null ? null : nextUnpaidPayment(debt, known);
    final period = paymentPeriod(debt, known, today);
    DateTime dayOf(DateTime date) => DateTime(date.year, date.month, date.day);
    final dueNow = next != null && dayOf(next.due).isBefore(period.end);
    final fallsDueThisMonth = dueNow || _fallsDueThisMonth(debt, known, today);
    return PayNowState(
      next: next,
      dueNow: dueNow,
      fallsDueThisMonth: fallsDueThisMonth,
      canPayAhead: !dueNow && next != null && debt.paidWithWalletId != null,
      frequency: debt.frequency,
    );
  }

  /// The payment waiting, or null when nothing waits.
  final DebtNextPayment? next;

  /// Whether it falls in the current period — or fell due earlier and is
  /// still owed — so Pay Now takes it.
  final bool dueNow;

  /// Whether the month has a payment of the plan at all, paid or not:
  /// what separates "already paid" from "nothing due yet". Only the monthly
  /// wording uses it.
  final bool fallsDueThisMonth;

  /// Whether the next payment may be paid ahead of its date: nothing is owed
  /// in this period, and the plan names the wallet to charge.
  final bool canPayAhead;

  /// How often the plan was set up to be paid.
  final PaymentFrequency frequency;

  /// What Pay in Advance takes, or null when there is nothing to pay ahead
  /// of — because this period's due comes first, or because every payment is
  /// already settled.
  DebtNextPayment? get advance => dueNow ? null : next;

  /// Whether the plan is paid monthly, the way installments always are.
  bool get byMonth => frequency == PaymentFrequency.monthly;

  /// How the current period reads in a sentence: "today", "this week".
  String get periodWord => switch (frequency) {
    PaymentFrequency.daily => 'today',
    PaymentFrequency.weekly => 'this week',
    PaymentFrequency.fortnightly => 'in these two weeks',
    PaymentFrequency.semiMonthly => 'this half of the month',
    PaymentFrequency.monthly => 'this month',
    PaymentFrequency.quarterly => 'this quarter',
    PaymentFrequency.semiAnnual => 'this half of the year',
    PaymentFrequency.annually => 'this year',
  };
}

/// Pays what [debt] owes in the period it is in: the payment waiting for it,
/// whose occurrence is found first so the period it falls in exists to pay
/// against even when the Bill Planner has not opened it yet.
///
/// Once that payment is made there is nothing left to take here, so pressing
/// it again brings up a small screen saying so rather than opening the
/// sheet: what comes next is paid ahead of its date through the way on to
/// Pay in advance it offers. Returns true when a payment was recorded.
///
/// [wallets] is the wallet list the paying sheet reads; the live one is
/// used when it is null. Tests hand one in instead of Firestore.
Future<bool> payDebtNow(
  BuildContext context,
  Debt debt, {
  required List<BillInstance> instances,
  required DateTime today,
  Stream<List<Wallet>>? wallets,
}) async {
  final state = PayNowState.read(debt, instances, today);

  if (!state.dueNow) {
    if (state.byMonth) {
      // Nothing at all for this month: says so, and when the plan's next
      // payment falls due.
      if (!state.fallsDueThisMonth) {
        final next = state.next;
        final number = next?.number;
        final due = next?.due;
        await showMiniNotice(
          context,
          icon: Icons.calendar_month,
          good: false,
          title: 'Nothing to pay this month',
          message: number == null || due == null
              ? 'This plan has nothing waiting to be paid.'
              : 'Payment $number of ${debt.paymentCount} falls due on '
                    '${formatShortDate(due)}.',
        );
        return false;
      }

      // Already paid: the indication asked for, with the way on to paying
      // ahead of the schedule when this plan can.
      final canPayAhead = state.canPayAhead;
      final choice = await showMiniNotice<String>(
        context,
        title: 'This month\'s due is already paid',
        message: canPayAhead
            ? 'To pay what comes next ahead of its date, tap Pay in advance.'
            : 'There is nothing else to pay right now.',
        actionLabel: canPayAhead ? 'Pay in advance' : null,
        actionValue: 'advance',
      );
      if (choice == 'advance' && context.mounted) {
        return payDebtInAdvance(
          context,
          debt,
          instances: instances,
          today: today,
          wallets: wallets,
        );
      }
      return false;
    }

    // Every other frequency: this period's payment is out of the way. Say
    // what comes next, and offer to pay it ahead when the plan named the
    // wallet to charge.
    final next = state.next;
    if (next == null) {
      await showMiniNotice(
        context,
        icon: Icons.check_circle_outline,
        title: 'Every payment of this plan is paid',
        message: 'There is nothing left to pay.',
      );
      return false;
    }
    final canPayAhead = state.canPayAhead;
    final choice = await showMiniNotice<String>(
      context,
      icon: Icons.calendar_month,
      good: false,
      title: 'Nothing is due ${state.periodWord}',
      message:
          'Payment ${next.number} of ${debt.paymentCount} falls due on '
          '${formatShortDate(next.due)}.',
      actionLabel: canPayAhead ? 'Pay in advance' : null,
      actionValue: 'advance',
    );
    if (choice == 'advance' && context.mounted) {
      return payDebtInAdvance(
        context,
        debt,
        instances: instances,
        today: today,
        wallets: wallets,
      );
    }
    return false;
  }

  var next = state.next;
  if (next?.instance == null) {
    // The Bill Planner has not opened that month, so no record stands for
    // the payment; finding it there makes the month exist to pay against.
    next = await DebtService.loadNextUnpaidPayment(debt);
  }
  if (!context.mounted) return false;
  final instance = next?.instance;
  if (instance == null) {
    await showMiniNotice(
      context,
      icon: Icons.info_outline,
      good: false,
      title: 'Nothing is waiting to be paid',
      message: 'This plan has no payment to record right now.',
    );
    return false;
  }
  return showBillPaymentSheet(
    context,
    instance: instance,
    wallets: wallets,
    initialWalletId: debt.paidWithWalletId,
  );
}

/// Pays [debt]'s next payment ahead of its date, out of the wallet the plan
/// was charged to when it was set up. The payment this period is owed comes
/// first: while it is owed, paying ahead says so and offers Pay Now instead.
/// Returns true when a payment was recorded.
///
/// A plan can be paid ahead only when it names the wallet to charge, so a
/// loan without one is paid when it falls due instead. [wallets] is the
/// list the paying sheet reads; the live one is used when it is null.
Future<bool> payDebtInAdvance(
  BuildContext context,
  Debt debt, {
  required List<BillInstance> instances,
  required DateTime today,
  Stream<List<Wallet>>? wallets,
}) async {
  final state = PayNowState.read(debt, instances, today);

  if (state.dueNow) {
    final owing = state.next;
    final choice = await showMiniNotice<String>(
      context,
      icon: Icons.calendar_month,
      good: false,
      title: state.byMonth
          ? 'This month\'s due is not paid yet'
          : owing == null
          ? 'This payment is not paid yet'
          : 'Payment ${owing.number} is not paid yet',
      message:
          'Pay it first with Pay Now. Paying ahead takes what comes after it.',
      actionLabel: 'Pay Now',
      actionValue: 'now',
    );
    if (choice == 'now' && context.mounted) {
      return payDebtNow(
        context,
        debt,
        instances: instances,
        today: today,
        wallets: wallets,
      );
    }
    return false;
  }

  var next = state.advance;
  if (next == null) {
    await showMiniNotice(
      context,
      title: 'Nothing to pay in advance',
      message: 'Every payment of this plan is already paid.',
    );
    return false;
  }
  if (debt.paidWithWalletId == null) {
    await showMiniNotice(
      context,
      icon: Icons.info_outline,
      good: false,
      title: 'This plan has no wallet to charge',
      message:
          '${debt.name} has no wallet named to charge, so it is paid when '
          'it falls due.',
    );
    return false;
  }
  if (next.instance == null) {
    // The month has not been opened in the Bill Planner yet: finding the
    // payment there makes it exist to pay against.
    next = await DebtService.loadNextUnpaidPayment(debt);
  }
  if (!context.mounted) return false;
  final waiting = next;
  if (waiting == null || waiting.instance == null) {
    await showMiniNotice(
      context,
      icon: Icons.info_outline,
      good: false,
      title: 'Nothing is waiting to be paid',
      message: 'This plan has no payment to record right now.',
    );
    return false;
  }
  return showAdvancePaymentSheet(
    context,
    debt: debt,
    next: waiting,
    wallets: wallets,
  );
}

/// Whether the plan has a payment falling due in [today]'s month at all:
/// from the occurrences already made, or from its own dates when the Bill
/// Planner has not opened that month yet.
bool _fallsDueThisMonth(
  Debt debt,
  List<BillInstance> instances,
  DateTime today,
) {
  final monthStart = DateTime(today.year, today.month, 1);
  final monthEnd = DateTime(today.year, today.month + 1, 1);
  bool inMonth(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(monthStart) && day.isBefore(monthEnd);
  }

  for (final instance in instances) {
    if (inMonth(instance.dueDate)) return true;
  }
  for (var number = 1; number <= debt.paymentCount; number++) {
    final due = debt.dueDateOf(number);
    if (due != null && inMonth(due)) return true;
  }
  return false;
}
