import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/bill.dart';
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
  /// The income and the bill payments all touch the same wallet, so their
  /// balance changes are added up and written to it once.
  ///
  /// The cycle keeps the pay period it belongs to. Pay starts a new one; other
  /// income, like a gift, joins the period of the pay before it, found among
  /// [recentCycles].
  static String confirm({
    required AllocationPlan plan,
    required String walletId,
    required String source,
    required DateTime receivedAt,
    String? incomeFrequency,
    String? usualSource,
    List<AllocationCycle> recentCycles = const [],
  }) {
    final problems = plan.problems;

    if (problems.isNotEmpty) {
      throw ArgumentError(problems.join(' '));
    }

    final batch = _firestore.batch();
    final deltas = <String, double>{};
    // Made first, so the goal contribution can point back to this cycle.
    final cycle = _cycles.doc();

    final incomeId = WalletService.addTransactionToBatch(
      batch,
      type: TransactionType.income,
      amount: plan.income,
      label: source,
      walletId: walletId,
      date: receivedAt,
      collectDeltasInto: deltas,
    );

    final payments = <Map<String, dynamic>>[];
    final skipped = <String>[];

    for (final bill in plan.bills) {
      if (bill.skipped) {
        BillService.addSkipToBatch(batch, bill.instance.id);
        skipped.add(bill.instance.id);
        continue;
      }

      if (!bill.pays) continue;

      final paymentId = BillService.addPaymentToBatch(
        batch,
        instance: bill.instance,
        walletId: walletId,
        amount: bill.amount,
        date: receivedAt,
        collectDeltasInto: deltas,
      );

      payments.add({
        'instanceId': bill.instance.id,
        'billId': bill.instance.billId,
        'name': bill.instance.name,
        'amount': bill.amount,
        'transactionId': paymentId,
      });
    }

    WalletService.applyDeltasToBatch(batch, deltas);

    // Setting money aside for a goal moves nothing between wallets, so it
    // adds no balance change; it only marks part of this income as saved.
    final goal = plan.goal;
    if (goal != null && plan.toGoal > 0) {
      GoalService.addContributionToBatch(
        batch,
        goal: goal,
        amount: plan.toGoal,
        walletId: walletId,
        date: receivedAt,
        cycleId: cycle.id,
      );
    }

    final period = periodForIncome(
      frequency: incomeFrequency,
      source: source,
      receivedAt: receivedAt,
      earlier: recentCycles,
      usualSource: usualSource,
    );
    batch.set(cycle, {
      'periodStart': Timestamp.fromDate(period.start),
      'periodEnd': Timestamp.fromDate(period.end),
      'incomeTransactionId': incomeId,
      'walletId': walletId,
      'source': source,
      'income': plan.income,
      'receivedAt': Timestamp.fromDate(receivedAt),
      'billPayments': payments,
      'skippedInstanceIds': skipped,
      'toBills': plan.toBills,
      'goalId': plan.toGoal > 0 ? goal?.id : null,
      'goalName': plan.toGoal > 0 ? goal?.name : null,
      'toGoal': plan.toGoal,
      'remaining': plan.remaining,
      'createdAt': FieldValue.serverTimestamp(),
    });

    commitFirestoreWrite(batch.commit(), 'allocate income');
    return cycle.id;
  }
}
