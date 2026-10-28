import '../utils/ph_time.dart';
import 'allocation.dart';
import 'app_transaction.dart';
import 'safe_to_spend.dart';

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

  /// The incomes logged with a plan that month. They carry the month-end
  /// decision about what is left.
  final List<AllocationCycle> cycles;

  double get totalIn => moneyIn.fold<double>(0, (sum, t) => sum + t.amount);
  double get totalOut => moneyOut.fold<double>(0, (sum, t) => sum + t.amount);

  /// What came in less what went out. Below zero when more went out.
  double get left => totalIn - totalOut;

  /// Money marked for goals when income came in: still in the wallets, but
  /// saved already, so the month-end question does not offer it again.
  double get keptForGoals =>
      cycles.fold<double>(0, (sum, cycle) => sum + cycle.toGoal);

  /// What the month-end question is about: what is left, less what goals
  /// already hold. Never below zero.
  double get leftToDecide {
    final free = left - keptForGoals;
    return free > 0.005 ? (free * 100).round() / 100 : 0;
  }

  PayPeriod get period => payPeriodFor(null, now: month);

  List<AllocationCycle> get undecided => [
    for (final cycle in cycles)
      if (!cycle.isResolved) cycle,
  ];

  /// The month is on its last day or over, by Philippine time [now].
  bool isOver(DateTime now) =>
      period.isLastDay(now) || !now.isBefore(period.end);

  /// What is left still has to be decided.
  bool awaitingDecision(DateTime now) => undecided.isNotEmpty && isOver(now);

  /// Every planned income has been decided, so the month is closed.
  bool get isDecided => cycles.isNotEmpty && undecided.isEmpty;

  /// The income the decision was recorded on, with its amounts.
  AllocationCycle? get decision {
    final decided = newestCycles(cycles.where((c) => c.isResolved));
    if (decided.isEmpty) return null;
    return decided.firstWhere(
      (cycle) => cycle.savedAmount + cycle.spentAmount > 0.005,
      orElse: () => decided.first,
    );
  }
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

List<AllocationCycle> newestCycles(Iterable<AllocationCycle> cycles) =>
    cycles.toList()..sort((a, b) {
      final date = b.receivedAt.compareTo(a.receivedAt);
      return date == 0 ? b.id.compareTo(a.id) : date;
    });
