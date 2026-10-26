import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../utils/money_format.dart';
import 'bill_service.dart';
import 'firestore_write.dart';
import 'goal_service.dart';
import 'wallet_service.dart';

/// Saves what the user decided to do with new income: the income itself, the
/// bills paid from it, the bills skipped, and a record of the whole cycle.
class AllocationService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _cycles {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('allocationCycles');
  }

  /// The bills to offer when money comes in: last month's that are still
  /// open, and this month's and next month's.
  ///
  /// This and next month are filled in first, because a bill's occurrences
  /// only exist once someone has opened that month on the calendar.
  static Future<List<BillInstance>> loadOutstandingBills({
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final bills = await BillService.loadBills();

    final months = [
      DateTime(today.year, today.month - 1),
      DateTime(today.year, today.month),
      DateTime(today.year, today.month + 1),
    ];

    for (final month in months.skip(1)) {
      await BillService.ensureInstances(
        bills: bills,
        year: month.year,
        month: month.month,
        now: today,
      );
    }

    final instances = <BillInstance>[];
    for (final month in months) {
      instances.addAll(
        await BillService.loadInstances(month.year, month.month),
      );
    }

    return outstandingBills(instances, now: today);
  }

  /// Saves the whole allocation in one batch and returns the cycle's id.
  ///
  /// The income, every bill payment, every skip and the cycle record land
  /// together or not at all. Paying three bills can't leave the wallet
  /// credited but only two bills marked paid.
  ///
  /// Money only lives where it really is. The income goes into the wallets
  /// in [incomeByWallet]; bills are paid straight out of the wallets in
  /// [billsPaidFrom], each with its own fee in [billFees]; money for the
  /// goal stays in the wallets in [goalKeptIn], marked for it. Each wallet's
  /// balance changes once.
  static String confirm({
    required AllocationPlan plan,
    required Map<String, double> incomeByWallet,
    Map<String, double> billsPaidFrom = const {},
    Map<String, double> billFees = const {},
    Map<String, double> goalKeptIn = const {},
    required String source,
    required DateTime receivedAt,
    List<AllocationCycle> recentCycles = const [],
  }) {
    final problems = plan.problems;
    if (problems.isNotEmpty) {
      throw ArgumentError(problems.join(' '));
    }
    _checkAddsUp(incomeByWallet, plan.income, 'The income');
    _checkAddsUp(billsPaidFrom, plan.toBills, 'The bill payments');
    _checkAddsUp(goalKeptIn, plan.toGoal, 'The goal money');

    final batch = _firestore.batch();
    final deltas = <String, double>{};
    // Made first, so the goal contribution can point back to this cycle.
    final cycle = _cycles.doc();

    final incomeIds = <String>[
      for (final entry in incomeByWallet.entries)
        if (entry.value > 0)
          WalletService.addTransactionToBatch(
            batch,
            type: TransactionType.income,
            amount: entry.value,
            label: source,
            walletId: entry.key,
            date: receivedAt,
            collectDeltasInto: deltas,
          ),
    ];

    final payments = <Map<String, dynamic>>[];
    final skipped = <String>[];

    // Each bill is paid from the chosen wallets in turn, in centavos, so
    // every peso is recorded against the wallet it really left.
    final sources = [
      for (final entry in billsPaidFrom.entries)
        if (entry.value > 0) (walletId: entry.key, cents: _cents(entry.value)),
    ];
    var sourceIndex = 0;
    var sourceLeft = sources.isEmpty ? 0 : sources.first.cents;

    for (final bill in plan.bills) {
      if (bill.skipped) {
        BillService.addSkipToBatch(batch, bill.instance.id);
        skipped.add(bill.instance.id);
        continue;
      }
      if (!bill.pays) continue;

      var owed = _cents(bill.amount);
      var paidSoFar = bill.instance.amountPaid;
      while (owed > 0) {
        if (sourceIndex >= sources.length) {
          throw StateError('The bills cost more than was paid from wallets.');
        }
        final walletId = sources[sourceIndex].walletId;
        final part = owed < sourceLeft ? owed : sourceLeft;
        final amount = part / 100;

        final paymentId = BillService.addPaymentToBatch(
          batch,
          instance: bill.instance,
          walletId: walletId,
          amount: amount,
          date: receivedAt,
          collectDeltasInto: deltas,
          paidBefore: paidSoFar,
        );
        payments.add({
          'instanceId': bill.instance.id,
          'billId': bill.instance.billId,
          'name': bill.instance.name,
          'amount': amount,
          'walletId': walletId,
          'transactionId': paymentId,
        });

        paidSoFar += amount;
        owed -= part;
        sourceLeft -= part;
        if (sourceLeft <= 0) {
          sourceIndex++;
          sourceLeft = sourceIndex < sources.length
              ? sources[sourceIndex].cents
              : 0;
        }
      }
    }

    // What each wallet was charged for paying them: an expense of its own,
    // as on Pay Bill, and the amount filled in for it next time.
    if (plan.toBills > 0) {
      for (final entry in billFees.entries) {
        if (entry.value <= 0) continue;
        WalletService.addServiceChargeToBatch(
          batch,
          walletId: entry.key,
          amount: entry.value,
          note: 'For paying bills',
          date: receivedAt,
          collectDeltasInto: deltas,
        );
        WalletService.rememberServiceChargeInBatch(
          batch,
          entry.key,
          entry.value,
        );
      }
    }

    WalletService.applyDeltasToBatch(batch, deltas);

    // Goal money stays in its wallets, marked for the goal; nothing moves.
    final goal = plan.goal;
    if (goal != null && plan.toGoal > 0) {
      GoalService.addContributionsToBatch(
        batch,
        goal: goal,
        amounts: goalKeptIn,
        date: receivedAt,
        cycleId: cycle.id,
      );
    }

    final period = periodForIncome(
      frequency: null,
      source: source,
      receivedAt: receivedAt,
      earlier: recentCycles,
    );
    // The wallet most of it went into, where a leftover is taken from.
    final mainWallet = incomeByWallet.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    batch.set(cycle, {
      'periodStart': Timestamp.fromDate(period.start),
      'periodEnd': Timestamp.fromDate(period.end),
      'incomeTransactionId': incomeIds.first,
      'incomeTransactionIds': incomeIds,
      'walletId': mainWallet,
      'incomeByWallet': incomeByWallet,
      'source': source,
      'income': plan.income,
      'receivedAt': Timestamp.fromDate(receivedAt),
      'billPayments': payments,
      'skippedInstanceIds': skipped,
      'toBills': plan.toBills,
      'billsPaidFrom': billsPaidFrom,
      'goalId': plan.toGoal > 0 ? goal?.id : null,
      'goalName': plan.toGoal > 0 ? goal?.name : null,
      'toGoal': plan.toGoal,
      'goalKeptIn': plan.toGoal > 0 ? goalKeptIn : const <String, double>{},
      'remaining': plan.remaining,
      'createdAt': FieldValue.serverTimestamp(),
    });

    commitFirestoreWrite(batch.commit(), 'allocate income');
    return cycle.id;
  }

  /// Whole centavos, so splitting money never leaves a stray fraction.
  static int _cents(double amount) => (amount * 100).round();

  /// Refuses [byWallet] unless it adds up to [total], to the centavo.
  static void _checkAddsUp(
    Map<String, double> byWallet,
    double total,
    String what,
  ) {
    final sum = byWallet.values.fold<int>(
      0,
      (all, value) => all + _cents(value),
    );
    if (sum != _cents(total)) {
      throw ArgumentError('$what must add up to ${formatPeso(total)}.');
    }
  }
}
