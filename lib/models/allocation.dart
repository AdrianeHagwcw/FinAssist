import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/money_format.dart';
import 'app_transaction.dart';
import 'bill.dart';
import 'goal.dart';
import 'safe_to_spend.dart';

/// What the user decided for one bill while allocating new income.
class BillAllocation {
  const BillAllocation({
    required this.instance,
    required this.amount,
    this.skipped = false,
  });

  /// Starts on paying the whole amount still owed, which is what the plan
  /// asks the checklist to default to.
  factory BillAllocation.full(BillInstance instance) =>
      BillAllocation(instance: instance, amount: instance.remaining);

  final BillInstance instance;

  /// What to pay now. Less than the bill's remaining amount is a part payment;
  /// zero leaves the bill for later without skipping it.
  final double amount;

  /// The user chose not to pay this bill at all this cycle.
  final bool skipped;

  bool get pays => !skipped && amount > 0;

  BillAllocation copyWith({double? amount, bool? skipped}) {
    return BillAllocation(
      instance: instance,
      amount: amount ?? this.amount,
      skipped: skipped ?? this.skipped,
    );
  }
}

/// One incoming amount and what the user plans to do with it.
///
/// Pure arithmetic with no Firestore in it, so the numbers the summary shows
/// and the numbers that get saved come from the same place and can be tested.
class AllocationPlan {
  const AllocationPlan({
    required this.income,
    this.bills = const [],
    this.goal,
    this.goalAmount = 0,
  });

  final double income;
  final List<BillAllocation> bills;

  /// The goal some of this income is set aside for, if any.
  final Goal? goal;
  final double goalAmount;

  /// Set aside for the goal this cycle.
  double get toGoal => goal == null || goalAmount <= 0 ? 0 : goalAmount;

  /// What is left once bills are paid, before anything goes to a goal. This
  /// is what "use what's left" puts toward the goal.
  double get afterBills => income - toBills;

  /// Total going to bills this cycle.
  double get toBills => bills
      .where((bill) => bill.pays)
      .fold<double>(0, (total, bill) => total + bill.amount);

  /// What is left of the income after bills. Negative means the bills chosen
  /// cost more than came in, and the difference comes out of money already in
  /// the wallet.
  double get remaining => income - toBills - toGoal;

  bool get dipsIntoSavings => remaining < -0.005;

  /// Reasons the plan can't be confirmed yet. Empty when it can.
  List<String> get problems {
    final problems = <String>[];

    if (!income.isFinite || income <= 0) {
      problems.add('Enter how much came in.');
    }

    for (final bill in bills) {
      if (bill.skipped) continue;

      if (!bill.amount.isFinite || bill.amount < 0) {
        problems.add('${bill.instance.name} needs a valid amount.');
      } else if (bill.amount > bill.instance.remaining + 0.005) {
        problems.add(
          '${bill.instance.name} only needs '
          '${formatPeso(bill.instance.remaining)}.',
        );
      }
    }

    final goal = this.goal;
    if (goal != null) {
      if (!goalAmount.isFinite || goalAmount < 0) {
        problems.add('Enter a valid amount for ${goal.name}.');
      } else if (goalAmount > goal.remaining + 0.005) {
        problems.add(
          '${goal.name} only needs ${formatPeso(goal.remaining)} more.',
        );
      }
    }

    return problems;
  }

  AllocationPlan copyWith({double? income, List<BillAllocation>? bills}) {
    return AllocationPlan(
      income: income ?? this.income,
      bills: bills ?? this.bills,
      goal: goal,
      goalAmount: goalAmount,
    );
  }
}

/// The bills worth asking about when money comes in: anything not settled,
/// overdue or falling due within [horizonDays], soonest first.
///
/// A bill due two months out isn't offered, because paying it now would tie up
/// money the user may need before then.
List<BillInstance> outstandingBills(
  Iterable<BillInstance> instances, {
  DateTime? now,
  int horizonDays = 31,
}) {
  final today = now ?? DateTime.now();
  final horizon = DateTime(today.year, today.month, today.day + horizonDays);

  final outstanding = instances
      .where(
        (instance) =>
            !instance.isSettled &&
            instance.remaining > 0 &&
            !instance.dueDate.isAfter(horizon),
      )
      .toList();

  outstanding.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return outstanding;
}

/// What the user decided about the money left at the end of a pay period.
enum LeftoverDecision {
  saved('Saved'),
  spent('Used for spending'),
  split('Split'),
  pending('Decide later');

  const LeftoverDecision(this.label);

  final String label;

  static LeftoverDecision? fromName(String? name) {
    for (final decision in LeftoverDecision.values) {
      if (decision.name == name) return decision;
    }
    return null;
  }
}

/// One time income came in and was allocated, as saved by the waterfall.
class AllocationCycle {
  const AllocationCycle({
    required this.id,
    required this.income,
    required this.remaining,
    required this.receivedAt,
    required this.source,
    this.walletId,
    this.decision,
    this.savedAmount = 0,
    this.spentAmount = 0,
  });

  factory AllocationCycle.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final received = map['receivedAt'];

    return AllocationCycle(
      id: id,
      income: _asDouble(map['income']),
      remaining: _asDouble(map['remaining']),
      receivedAt: received is Timestamp ? received.toDate() : DateTime.now(),
      source: map['source'] is String ? map['source'] as String : 'Income',
      walletId: map['walletId'] is String ? map['walletId'] as String : null,
      decision: LeftoverDecision.fromName(
        map['leftoverDecision'] is String
            ? map['leftoverDecision'] as String
            : null,
      ),
      savedAmount: _asDouble(map['leftoverSaved']),
      spentAmount: _asDouble(map['leftoverSpent']),
    );
  }

  final String id;
  final double income;

  /// What was left after bills when the income was allocated.
  final double remaining;
  final DateTime receivedAt;
  final String source;
  final String? walletId;

  /// Null until the leftover review has been seen.
  final LeftoverDecision? decision;
  final double savedAmount;
  final double spentAmount;

  /// A decision was made. "Decide later" doesn't count: it is still open.
  bool get isResolved =>
      decision != null && decision != LeftoverDecision.pending;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;
}

/// The pay period a cycle's income was meant to cover.
PayPeriod periodOf(AllocationCycle cycle, String? frequency) {
  return payPeriodFor(
    frequency,
    lastIncomeAt: cycle.receivedAt,
    now: cycle.receivedAt,
  );
}

/// What is left of a cycle's income: what was left after bills, less what was
/// spent during its period. Never below zero.
double leftoverOf(
  AllocationCycle cycle,
  Iterable<AppTransaction> transactions,
  PayPeriod period,
) {
  final spent = discretionarySpending(
    transactions,
    from: DateTime(
      cycle.receivedAt.year,
      cycle.receivedAt.month,
      cycle.receivedAt.day,
    ),
    until: period.end,
  );
  final left = cycle.remaining - spent;
  return left > 0 ? left : 0;
}

/// The newest cycle whose period is on its last day or already over and whose
/// leftover hasn't been decided, or null when nothing is waiting.
AllocationCycle? cycleAwaitingReview(
  Iterable<AllocationCycle> cycles,
  String? frequency, {
  required DateTime now,
}) {
  final newestFirst = cycles.toList()
    ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  for (final cycle in newestFirst) {
    if (cycle.isResolved) continue;

    final period = periodOf(cycle, frequency);
    if (period.isLastDay(now) || !now.isBefore(period.end)) return cycle;
  }

  return null;
}
