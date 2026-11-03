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

/// What Pay Now has to take on the day it is read: the payment waiting
/// that falls due this month, whether the month has one at all, and
/// whether what comes next may be paid ahead of its date.
///
/// Read from the plan's own dates and its [instances], so the note under
/// the button and pressing the button always say the same thing — and so
/// Voice Entry opens exactly the screens the plan's own page does.
class PayNowState {
  const PayNowState({
    required this.next,
    required this.owesThisMonth,
    required this.fallsDueThisMonth,
    required this.canPayAhead,
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
    final monthEnd = DateTime(today.year, today.month + 1, 1);
    DateTime dayOf(DateTime date) => DateTime(date.year, date.month, date.day);
    final owesThisMonth = next != null && dayOf(next.due).isBefore(monthEnd);
    final fallsDueThisMonth =
        owesThisMonth || _fallsDueThisMonth(debt, known, today);
    return PayNowState(
      next: next,
      owesThisMonth: owesThisMonth,
      fallsDueThisMonth: fallsDueThisMonth,
      canPayAhead:
          next != null && !owesThisMonth && debt.paidWithWalletId != null,
    );
  }

  /// The payment waiting, or null when nothing waits.
  final DebtNextPayment? next;

  /// Whether it falls due this month — or fell due earlier and is still
  /// owed — so Pay Now takes it.
  final bool owesThisMonth;

  /// Whether the month has a payment of the plan at all, paid or not:
  /// what separates "already paid" from "nothing due yet".
  final bool fallsDueThisMonth;

  /// Whether the next payment may be paid ahead of its date: this month's
  /// due is out of the way, and the plan names the wallet to charge.
  final bool canPayAhead;
}

/// Pays this month's due of [debt]: the payment waiting for it, whose
/// occurrence is found first so the month it falls in exists to pay against
/// even when the Bill Planner has not opened it yet.
///
/// Once this month's due is paid there is nothing left to take here, so
/// pressing it again brings up a small screen saying so rather than opening
/// the sheet: what comes next is paid ahead of its date through the way on
/// to Pay in advance it offers. Returns true when a payment was recorded.
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

  if (!state.owesThisMonth) {
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
  return showBillPaymentSheet(context, instance: instance, wallets: wallets);
}

/// Pays [debt]'s next payment ahead of its date, out of the wallet the plan
/// was charged to when it was set up. This month's due comes first: while
/// it is owed, paying ahead says so and offers Pay Now instead. Returns true
/// when a payment was recorded.
///
/// Only an installment can be paid ahead — a loan has no wallet of its own
/// to charge — and only what is not already paid. [wallets] is the list the
/// paying sheet reads; the live one is used when it is null.
Future<bool> payDebtInAdvance(
  BuildContext context,
  Debt debt, {
  required List<BillInstance> instances,
  required DateTime today,
  Stream<List<Wallet>>? wallets,
}) async {
  final state = PayNowState.read(debt, instances, today);

  if (state.owesThisMonth) {
    final choice = await showMiniNotice<String>(
      context,
      icon: Icons.calendar_month,
      good: false,
      title: 'This month\'s due is not paid yet',
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

  var next = state.next;
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
      title: 'Only an installment can be paid ahead',
      message:
          '${debt.name} has no wallet named to charge, so it is paid '
          'when it falls due.',
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
