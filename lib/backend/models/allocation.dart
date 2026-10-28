import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/money_format.dart';
import '../utils/ph_time.dart';
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
    this.serviceCharge = 0,
  });

  final double income;
  final List<BillAllocation> bills;

  /// The goal some of this income is set aside for, if any.
  final Goal? goal;
  final double goalAmount;

  /// What the wallets paying these bills were charged for it, all together,
  /// as on Pay Bill. Optional, and only counted while a bill is being paid.
  final double serviceCharge;

  /// [serviceCharge], while a bill is being paid.
  double get billsServiceCharge =>
      toBills > 0 && serviceCharge > 0 ? serviceCharge : 0;

  /// Set aside for the goal this cycle.
  double get toGoal => goal == null || goalAmount <= 0 ? 0 : goalAmount;

  /// What is left once bills, and any charge for paying them, are paid,
  /// before anything goes to a goal. This is what "use what's left" puts
  /// toward the goal.
  double get afterBills => income - toBills - billsServiceCharge;

  /// Total going to bills this cycle.
  double get toBills => bills
      .where((bill) => bill.pays)
      .fold<double>(0, (total, bill) => total + bill.amount);

  /// What is left of the income after bills. Negative means the bills chosen
  /// cost more than came in, and the difference comes out of money already in
  /// the wallet.
  double get remaining => income - toBills - billsServiceCharge - toGoal;

  bool get dipsIntoSavings => remaining < -0.005;

  /// Reasons the plan can't be confirmed yet. Empty when it can.
  List<String> get problems {
    final problems = <String>[];

    if (!isRecordableAmount(income)) {
      problems.add(minimumAmountError);
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

    if (!serviceCharge.isFinite || serviceCharge < 0) {
      problems.add('Enter the service charge, or turn it off.');
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
      serviceCharge: serviceCharge,
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
    this.toBills = 0,
    this.toGoal = 0,
    this.goalName,
    this.periodStart,
    this.periodEnd,
    this.incomeTransactionIds = const [],
    this.planPaymentIds = const [],
  });

  factory AllocationCycle.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final received = map['receivedAt'];
    final incomeIds = map['incomeTransactionIds'];
    final payments = map['billPayments'];

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
      toBills: _asDouble(map['toBills']),
      toGoal: _asDouble(map['toGoal']),
      goalName: map['goalName'] is String ? map['goalName'] as String : null,
      periodStart: map['periodStart'] is Timestamp
          ? (map['periodStart'] as Timestamp).toDate()
          : null,
      periodEnd: map['periodEnd'] is Timestamp
          ? (map['periodEnd'] as Timestamp).toDate()
          : null,
      incomeTransactionIds: [
        if (incomeIds is List)
          for (final id in incomeIds)
            if (id is String)
              id
            // Older records kept only the first.
            else if (map['incomeTransactionId'] is String)
              map['incomeTransactionId'] as String,
      ],
      planPaymentIds: [
        if (payments is List)
          for (final payment in payments)
            if (payment is Map && payment['transactionId'] is String)
              payment['transactionId'] as String,
      ],
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
  final double toBills;
  final double toGoal;
  final String? goalName;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// The income records this was saved with, one per wallet it went into.
  final List<String> incomeTransactionIds;

  /// The bills paid when it was logged. Already counted in [toBills], so
  /// they are never counted again as spending out of it.
  final List<String> planPaymentIds;

  /// A decision was made. "Decide later" doesn't count: it is still open.
  bool get isResolved =>
      decision != null && decision != LeftoverDecision.pending;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;
}

/// The calendar month an income entry belongs to. Legacy saved pay-period
/// bounds and profile schedules are intentionally ignored.
///
/// By the Philippine calendar, as every other month in the app.
PayPeriod periodOf(AllocationCycle cycle) =>
    payPeriodFor(null, now: philippineTime(cycle.receivedAt));

/// What is left of a cycle's income: what was left after bills and goals,
/// less what was spent out of it. Never below zero. [others] are the user's
/// other incomes, which share the month's spending with it.
double leftoverOf(
  AllocationCycle cycle,
  Iterable<AppTransaction> transactions, {
  Iterable<AllocationCycle> others = const [],
}) {
  final left =
      cycle.remaining - spentInCycle(cycle, transactions, others: others);
  return left > 0 ? left : 0;
}

/// What was spent out of this income; see [spendingByCycle].
double spentInCycle(
  AllocationCycle cycle,
  Iterable<AppTransaction> transactions, {
  Iterable<AllocationCycle> others = const [],
}) => spendingByCycle([cycle, ...others], transactions)[cycle.id] ?? 0;

/// What was spent out of each income, by its id.
///
/// The earliest money is used first: every payment after money came in is
/// taken from the oldest income of that month that still has some left,
/// and only from income that had already arrived. So each payment counts
/// once, and the incomes add up to what really went out. More than they
/// had is put on the newest, so it can say by how much. Spending before a
/// month's first income was paid from older money, so none of it counts.
///
/// What went out is everything Outflow counts: expenses, and bills,
/// installments and debts paid later. Not the bills paid when an income
/// was logged, which are in its [AllocationCycle.toBills] already, and not
/// transfers or money borrowed or lent.
Map<String, double> spendingByCycle(
  Iterable<AllocationCycle> cycles,
  Iterable<AppTransaction> transactions,
) {
  final unique = {for (final cycle in cycles) cycle.id: cycle}.values.toList();
  final planned = {for (final cycle in unique) ...cycle.planPaymentIds};
  final spent = {for (final cycle in unique) cycle.id: 0.0};

  final outflows =
      transactions
          .where(
            (t) =>
                t.type == TransactionType.expense &&
                !t.isDebtMovement &&
                !planned.contains(t.id),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  // Month by month: one month's money is never spent in another.
  final byMonth = <DateTime, List<AllocationCycle>>{};
  for (final cycle in unique) {
    byMonth.putIfAbsent(periodOf(cycle).start, () => []).add(cycle);
  }

  for (final month in byMonth.values) {
    month.sort((a, b) {
      final byDate = a.receivedAt.compareTo(b.receivedAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    final first = month.first.receivedAt;
    final end = philippineDayStart(periodOf(month.first).end);

    for (final outflow in outflows) {
      if (outflow.date.isBefore(first) || !outflow.date.isBefore(end)) {
        continue;
      }
      final arrived = [
        for (final cycle in month)
          if (!cycle.receivedAt.isAfter(outflow.date)) cycle,
      ];
      var amount = outflow.amount;
      for (final cycle in arrived) {
        if (amount <= 0.005) break;
        final room = cycle.remaining - spent[cycle.id]!;
        if (room <= 0.005) continue;
        final taken = amount < room ? amount : room;
        spent[cycle.id] = spent[cycle.id]! + taken;
        amount -= taken;
      }
      if (amount > 0.005) {
        spent[arrived.last.id] = spent[arrived.last.id]! + amount;
      }
    }
  }

  return {
    for (final entry in spent.entries)
      entry.key: (entry.value * 100).round() / 100,
  };
}

/// The newest cycle whose period is on its last day or already over and whose
/// leftover hasn't been decided, or null when nothing is waiting.
AllocationCycle? cycleAwaitingReview(
  Iterable<AllocationCycle> cycles, {
  required DateTime now,
}) {
  final newestFirst = cycles.toList()
    ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  for (final cycle in newestFirst) {
    if (cycle.isResolved) continue;

    final period = periodOf(cycle);
    if (period.isLastDay(now) || !now.isBefore(period.end)) return cycle;
  }

  return null;
}

/// Income that says nothing about when pay comes.
const _oneOffSources = {'Gift', 'Sold Something', 'Refund'};

/// When the user was last paid: the newest income from their usual source,
/// or, when none is on record, the newest that isn't a one-off like a gift.
///
/// Only pay starts a new pay period. A gift, a refund or a side income adds
/// money to the period already under way, so it raises Safe to Spend instead
/// of spreading everything over a fresh month. With [onOrBefore], income
/// received after it is left out.
DateTime? lastPayday(
  Iterable<AllocationCycle> cycles, {
  String? usualSource,
  DateTime? onOrBefore,
}) {
  final newestFirst =
      cycles
          .where(
            (cycle) =>
                onOrBefore == null || !cycle.receivedAt.isAfter(onOrBefore),
          )
          .toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  final usual = usualSource?.trim().toLowerCase() ?? '';

  if (usual.isNotEmpty) {
    for (final cycle in newestFirst) {
      if (cycle.source.trim().toLowerCase() == usual) return cycle.receivedAt;
    }
  }
  for (final cycle in newestFirst) {
    if (!_oneOffSources.contains(cycle.source)) return cycle.receivedAt;
  }
  return null;
}

/// The pay period income received at [receivedAt] belongs to: a new one when
/// it is the user's pay, otherwise the period of the pay before it, found
/// among the [earlier] income.
PayPeriod periodForIncome({
  required String? frequency,
  required String source,
  required DateTime receivedAt,
  Iterable<AllocationCycle> earlier = const [],
  String? usualSource,
}) {
  final lastPay = lastPayday(
    [
      ...earlier,
      AllocationCycle(
        id: '',
        income: 0,
        remaining: 0,
        receivedAt: receivedAt,
        source: source,
      ),
    ],
    usualSource: usualSource,
    onOrBefore: receivedAt,
  );
  return payPeriodFor(frequency, lastIncomeAt: lastPay, now: receivedAt);
}
