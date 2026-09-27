import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../models/wallet.dart';
import 'bill_service.dart';
import 'firestore_write.dart';
import 'goal_service.dart';
import 'wallet_service.dart';

/// [amount] kept within zero and [ceiling], so money set aside can never be
/// more than the pay it is taken from.
double _within(double amount, double ceiling) {
  if (!amount.isFinite || amount <= 0) return 0;
  if (!ceiling.isFinite || ceiling <= 0) return 0;
  return amount < ceiling ? amount : ceiling;
}

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
    List<Wallet> wallets = const [],
    double plannedBills = 0,
    double plannedSavings = 0,
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

    // Money meant for bills and savings is moved out of the wallet the pay
    // landed in, so what stays is only what the user may spend. The bills
    // wallet is topped up to cover the bills being paid right now, in case
    // the plan set aside less than they cost.
    final billsHeld = WalletService.walletFor(wallets, WalletPurpose.bills)
        ?.balance;
    final needed = plan.toBills - (billsHeld ?? 0);
    final toBillsWallet = _within(
      needed > plannedBills ? needed : plannedBills,
      plan.income,
    );
    final toSavingsWallet = _within(
      plannedSavings,
      plan.income - toBillsWallet,
    );

    String? billsWalletId;
    if (toBillsWallet > 0 || plan.toBills > 0) {
      billsWalletId = WalletService.addPurposeWalletToBatch(
        batch,
        purpose: WalletPurpose.bills,
        wallets: wallets,
      );
    }

    if (billsWalletId != null && toBillsWallet > 0) {
      WalletService.addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: toBillsWallet,
        label: TransactionType.transfer.label,
        walletId: walletId,
        toWalletId: billsWalletId,
        note: 'Set aside for bills',
        date: receivedAt,
        collectDeltasInto: deltas,
      );
    }

    if (toSavingsWallet > 0) {
      final savingsWalletId = WalletService.addPurposeWalletToBatch(
        batch,
        purpose: WalletPurpose.savings,
        wallets: wallets,
      );

      WalletService.addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: toSavingsWallet,
        label: TransactionType.transfer.label,
        walletId: walletId,
        toWalletId: savingsWalletId,
        note: 'Set aside for savings',
        date: receivedAt,
        collectDeltasInto: deltas,
      );
    }

    // Bills are paid out of the money already set aside for them.
    final billsPaidFrom = billsWalletId ?? walletId;

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
        walletId: billsPaidFrom,
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
      'toBillsWallet': toBillsWallet,
      'toSavingsWallet': toSavingsWallet,
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
