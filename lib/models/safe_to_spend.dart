import 'app_transaction.dart';
import 'bill.dart';

/// The stretch of time one pay is meant to last.
class PayPeriod {
  const PayPeriod({required this.start, required this.end});

  /// First day of the period.
  final DateTime start;

  /// The day after the period's last day, so a period is `start <= day < end`.
  final DateTime end;

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  /// Days still to cover, counting today. Never less than one, so dividing by
  /// it is always safe.
  int daysLeft(DateTime now) {
    final today = _dateOnly(now);
    final days = end.difference(today).inDays;
    return days < 1 ? 1 : days;
  }

  /// Whether this is the last day of the period, when the leftover review is
  /// due.
  bool isLastDay(DateTime now) => daysLeft(now) <= 1;
}

/// The pay period [now] falls in, for an onboarding income frequency.
///
/// When the user has logged income through the waterfall, [lastIncomeAt]
/// anchors the period to the day money actually arrived: a monthly allowance
/// received on the 7th runs 7th to 7th, not 1st to 1st. Without it, weekly
/// periods start on Monday and monthly ones on the 1st.
///
/// Semi-monthly periods end on the 15th and the last day of each month.
/// Without a logged payday, the most recent scheduled payday is used as the
/// start; an irregular income is treated month by month.
PayPeriod payPeriodFor(
  String? frequency, {
  DateTime? lastIncomeAt,
  required DateTime now,
}) {
  final today = _dateOnly(now);

  switch (frequency) {
    case 'Semi-monthly':
      final anchor = lastIncomeAt == null
          ? today.day >= 15
                ? DateTime(today.year, today.month, 15)
                : DateTime(today.year, today.month, 0)
          : _dateOnly(lastIncomeAt);
      return _rollForward(anchor, today, _nextSemiMonthlyBoundary);

    case 'Weekly':
    case 'Bi-weekly':
      final length = frequency == 'Weekly' ? 7 : 14;
      final anchor = lastIncomeAt == null
          ? today.subtract(Duration(days: today.weekday - DateTime.monday))
          : _dateOnly(lastIncomeAt);
      return _rollForward(anchor, today, (start) {
        return DateTime(start.year, start.month, start.day + length);
      });

    case 'Monthly':
      if (lastIncomeAt != null) {
        return _monthlyFrom(_dateOnly(lastIncomeAt), today);
      }
      return _calendarMonth(today);

    default:
      return _calendarMonth(today);
  }
}

DateTime _nextSemiMonthlyBoundary(DateTime start) {
  final monthEnd = DateTime(start.year, start.month + 1, 0);
  if (start.day < 15) return DateTime(start.year, start.month, 15);
  if (start.day < monthEnd.day) return monthEnd;
  return DateTime(start.year, start.month + 1, 15);
}

/// Monthly periods counted from the day income arrived. Each boundary is
/// worked out from the original day, so the 31st becomes the 28th in
/// February and is the 31st again in March, instead of drifting earlier.
PayPeriod _monthlyFrom(DateTime anchor, DateTime today) {
  if (today.isBefore(anchor)) return PayPeriod(start: today, end: anchor);

  var months = (today.year - anchor.year) * 12 + (today.month - anchor.month);
  if (_monthsAfter(anchor, months).isAfter(today)) months--;

  return PayPeriod(
    start: _monthsAfter(anchor, months),
    end: _monthsAfter(anchor, months + 1),
  );
}

DateTime _monthsAfter(DateTime anchor, int months) {
  final lastDay = DateTime(anchor.year, anchor.month + months + 1, 0).day;
  return DateTime(
    anchor.year,
    anchor.month + months,
    anchor.day < lastDay ? anchor.day : lastDay,
  );
}

PayPeriod _calendarMonth(DateTime today) => PayPeriod(
  start: DateTime(today.year, today.month),
  end: DateTime(today.year, today.month + 1),
);

/// Steps from [anchor] one period at a time until reaching the one holding
/// [today]. If the anchor is in the future, today's period ends at it.
PayPeriod _rollForward(
  DateTime anchor,
  DateTime today,
  DateTime Function(DateTime start) next,
) {
  if (today.isBefore(anchor)) {
    return PayPeriod(start: today, end: anchor);
  }

  var start = anchor;
  var end = next(start);
  // Bounded: a pay history is years at most, not thousands of periods.
  for (var i = 0; i < 2000 && !today.isBefore(end); i++) {
    start = end;
    end = next(start);
  }
  return PayPeriod(start: start, end: end);
}

/// Spending the user chose today: expenses dated today, leaving out bill
/// payments, which were already set aside for when the bill came due.
double discretionarySpending(
  Iterable<AppTransaction> transactions, {
  required DateTime from,
  required DateTime until,
}) {
  var total = 0.0;

  for (final transaction in transactions) {
    if (transaction.type != TransactionType.expense) continue;
    if (transaction.isBillPayment) continue;
    // Lending money isn't spending it; it is expected back.
    if (transaction.isDebtMovement) continue;
    if (transaction.date.isBefore(from) || !transaction.date.isBefore(until)) {
      continue;
    }
    total += transaction.amount;
  }

  return total;
}

/// What is still owed on bills falling due before [periodEnd], including any
/// already overdue. That money is spoken for, so it can't be spent freely.
double billsDueBefore(Iterable<BillInstance> instances, DateTime periodEnd) {
  var total = 0.0;

  for (final instance in instances) {
    if (instance.isSettled) continue;
    if (!instance.dueDate.isBefore(periodEnd)) continue;
    total += instance.remaining;
  }

  return total;
}

/// Today's safe-to-spend figure and how it was reached.
class SafeToSpend {
  const SafeToSpend({
    required this.walletBalance,
    required this.billsDue,
    required this.savingsReserve,
    required this.spentToday,
    required this.daysLeft,
    this.goalSavings = 0,
    this.customDailyLimit,
    this.periodBudget,
    this.periodSpent = 0,
    this.periodLengthDays,
    this.plannedBills = 0,
    this.plannedSavings = 0,
  });

  /// Everything in the user's wallets right now.
  final double walletBalance;

  /// Owed on bills before the period ends.
  final double billsDue;

  /// Money the user chose to set aside as savings.
  final double savingsReserve;

  /// Planned amounts for this pay period that should be reserved before the
  /// remaining budget is split across the days left.
  final double plannedBills;
  final double plannedSavings;

  /// Money set aside for goals, which stays in the wallets but isn't
  /// spendable.
  final double goalSavings;

  /// Spent today, not counting bill payments.
  final double spentToday;

  final int daysLeft;

  /// A daily limit the user typed in. A period budget still caps it so the
  /// plan lasts until the next payday.
  final double? customDailyLimit;

  /// The user's planned spending amount for this whole pay period.
  final double? periodBudget;

  /// Discretionary spending so far this period, including today's spending.
  final double periodSpent;

  /// Full configured pay-period length. Defaults to [daysLeft] for callers
  /// without period-budget inputs.
  final int? periodLengthDays;

  /// What can be spent across the rest of the period, measured from the start
  /// of today. Today's own spending is added back, because the balance has
  /// already dropped by it and it is counted separately below.
  double get spendableThisPeriod {
    final walletAmount =
        walletBalance +
        spentToday -
        billsDue -
        savingsReserve -
        plannedBills -
        plannedSavings -
        goalSavings;
    final availableFromWallet = walletAmount > 0 ? walletAmount : 0.0;
    final budget = periodBudget;
    if (budget == null) return availableFromWallet;

    final remainingBudget = budget - periodSpent + spentToday;
    final availableFromPlan = remainingBudget > 0 ? remainingBudget : 0.0;
    return availableFromWallet < availableFromPlan
        ? availableFromWallet
        : availableFromPlan;
  }

  /// The period's spendable money shared evenly over the days left, capped at
  /// the per-day amount in the user's configured period budget.
  double get recommendedDailyLimit {
    final remainingPerDay = spendableThisPeriod / daysLeft;
    final budget = periodBudget;
    if (budget == null) return remainingPerDay;

    final plannedPerDay = budget / (periodLengthDays ?? daysLeft);
    return remainingPerDay < plannedPerDay ? remainingPerDay : plannedPerDay;
  }

  bool get usesCustomLimit => customDailyLimit != null;

  double get dailyLimit {
    final custom = customDailyLimit;
    if (custom == null) return recommendedDailyLimit;
    if (periodBudget == null || custom <= recommendedDailyLimit) return custom;
    return recommendedDailyLimit;
  }

  /// Still safe to spend today. Negative once today's limit is passed.
  double get leftToday => dailyLimit - spentToday;

  bool get isOverLimit => leftToday < -0.005;

  /// How much of today's limit is used, from 0 to 1.
  double get usedFraction {
    if (dailyLimit <= 0) return spentToday > 0 ? 1 : 0;
    final fraction = spentToday / dailyLimit;
    return fraction.clamp(0.0, 1.0).toDouble();
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
