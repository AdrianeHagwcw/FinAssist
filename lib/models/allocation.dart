import '../utils/money_format.dart';
import 'bill.dart';

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
  const AllocationPlan({required this.income, this.bills = const []});

  final double income;
  final List<BillAllocation> bills;

  /// Total going to bills this cycle.
  double get toBills => bills
      .where((bill) => bill.pays)
      .fold<double>(0, (sum, bill) => sum + bill.amount);

  /// What is left of the income after bills. Negative means the bills chosen
  /// cost more than came in, and the difference comes out of money already in
  /// the wallet.
  double get remaining => income - toBills;

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

    return problems;
  }

  AllocationPlan copyWith({double? income, List<BillAllocation>? bills}) {
    return AllocationPlan(
      income: income ?? this.income,
      bills: bills ?? this.bills,
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
