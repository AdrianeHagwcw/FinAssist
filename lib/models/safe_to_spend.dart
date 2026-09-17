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
/// Semi-monthly always splits on the 15th, as onboarding describes it, and an
/// irregular income is treated month by month.
PayPeriod payPeriodFor(
  String? frequency, {
  DateTime? lastIncomeAt,
  required DateTime now,
}) {
  final today = _dateOnly(now);

  switch (frequency) {
    case 'Semi-monthly':
      if (today.day <= 15) {
        return PayPeriod(
          start: DateTime(today.year, today.month),
          end: DateTime(today.year, today.month, 16),
        );
      }
      return PayPeriod(
        start: DateTime(today.year, today.month, 16),
        end: DateTime(today.year, today.month + 1),
      );

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
    this.customDailyLimit,
  });

  /// Everything in the user's wallets right now.
  final double walletBalance;

  /// Owed on bills before the period ends.
  final double billsDue;

  /// Money the user chose to set aside as savings.
  final double savingsReserve;

  /// Spent today, not counting bill payments.
  final double spentToday;

  final int daysLeft;

  /// A daily limit the user typed in, replacing the recommendation.
  final double? customDailyLimit;

  /// What can be spent across the rest of the period, measured from the start
  /// of today. Today's own spending is added back, because the balance has
  /// already dropped by it and it is counted separately below.
  double get spendableThisPeriod {
    final amount = walletBalance + spentToday - billsDue - savingsReserve;
    return amount > 0 ? amount : 0;
  }

  /// The period's spendable money shared evenly over the days left.
  double get recommendedDailyLimit => spendableThisPeriod / daysLeft;

  bool get usesCustomLimit => customDailyLimit != null;

  double get dailyLimit => customDailyLimit ?? recommendedDailyLimit;

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
