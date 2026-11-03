import '../utils/ph_time.dart';
import 'allocation.dart';
import 'app_transaction.dart';

/// One month of actual money in and out, by the Philippine calendar: what
/// Cash Inflows shows. Only real records, never a plan or a share of one,
/// so every figure can be matched to a receipt or a bank statement.
class MonthFlow {
  MonthFlow({
    required this.month,
    required this.moneyIn,
    required this.moneyOut,
    required this.cycles,
  });

  /// The first day of the month.
  final DateTime month;

  /// Every income recorded that month, newest first.
  final List<AppTransaction> moneyIn;

  /// Every expense and payment recorded that month, newest first.
  final List<AppTransaction> moneyOut;

  /// The incomes logged with a plan that month, with what each put toward
  /// goals.
  final List<AllocationCycle> cycles;

  double get totalIn => moneyIn.fold<double>(0, (sum, t) => sum + t.amount);
  double get totalOut => moneyOut.fold<double>(0, (sum, t) => sum + t.amount);

  /// What came in less what went out. Below zero when more went out.
  double get left => totalIn - totalOut;

  /// Money marked for goals when income came in: still in the wallets, so
  /// part of what is left.
  double get keptForGoals =>
      cycles.fold<double>(0, (sum, cycle) => sum + cycle.toGoal);
}

/// Each month with money coming in, newest first: its actual income and
/// expense records, and its planned incomes. Transfers between the user's
/// own wallets and money borrowed or lent are neither, as on Home.
List<MonthFlow> monthFlows(
  Iterable<AllocationCycle> cycles,
  Iterable<AppTransaction> transactions,
) {
  DateTime monthOf(DateTime date) {
    final ph = philippineTime(date);
    return DateTime(ph.year, ph.month);
  }

  final moneyIn = <DateTime, List<AppTransaction>>{};
  final moneyOut = <DateTime, List<AppTransaction>>{};
  for (final t in transactions) {
    if (t.isDebtMovement) continue;
    switch (t.type) {
      case TransactionType.income:
        moneyIn.putIfAbsent(monthOf(t.date), () => []).add(t);
      case TransactionType.expense:
        moneyOut.putIfAbsent(monthOf(t.date), () => []).add(t);
      case TransactionType.transfer:
        break;
    }
  }
  final planned = <DateTime, List<AllocationCycle>>{};
  for (final cycle in cycles) {
    planned.putIfAbsent(periodOf(cycle).start, () => []).add(cycle);
  }

  // Only months something came in: this is the inflows screen.
  final months = {...moneyIn.keys, ...planned.keys}.toList()
    ..sort((a, b) => b.compareTo(a));
  List<AppTransaction> newestFirst(List<AppTransaction>? list) =>
      [...?list]..sort((a, b) => b.date.compareTo(a.date));
  return [
    for (final month in months)
      MonthFlow(
        month: month,
        moneyIn: newestFirst(moneyIn[month]),
        moneyOut: newestFirst(moneyOut[month]),
        cycles: planned[month] ?? const [],
      ),
  ];
}
