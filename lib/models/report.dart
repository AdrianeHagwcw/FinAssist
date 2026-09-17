import 'app_transaction.dart';
import 'goal.dart';
import 'transaction_filter.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';

/// Which stretch of time a report covers.
enum ReportRange {
  week('This week'),
  month('This month'),
  custom('Custom');

  const ReportRange(this.label);

  final String label;
}

/// A stretch of days, first and last day both included.
class ReportPeriod {
  const ReportPeriod(this.start, this.end);

  /// The week holding [now], Monday to Sunday.
  factory ReportPeriod.weekOf(DateTime now) {
    final today = _day(now);
    final start = today.subtract(Duration(days: today.weekday - 1));
    return ReportPeriod(
      start,
      DateTime(start.year, start.month, start.day + 6),
    );
  }

  /// The calendar month holding [now].
  factory ReportPeriod.monthOf(DateTime now) {
    return ReportPeriod(
      DateTime(now.year, now.month),
      DateTime(now.year, now.month + 1, 0),
    );
  }

  /// First day included, at midnight.
  final DateTime start;

  /// Last day included, at midnight.
  final DateTime end;

  bool contains(DateTime date) {
    final day = _day(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// "Sep 1 – Sep 30, 2026", without repeating the year when it's shared.
  String get label {
    final sameYear = start.year == end.year;
    final first = sameYear ? formatMonthDay(start) : formatShortDate(start);
    return '$first – ${formatShortDate(end)}';
  }

  /// The period of the same kind just before this one: the week before, the
  /// month before, or the same number of days before a custom range.
  ReportPeriod previous(ReportRange range) {
    switch (range) {
      case ReportRange.week:
        return ReportPeriod.weekOf(start.subtract(const Duration(days: 7)));
      case ReportRange.month:
        return ReportPeriod.monthOf(DateTime(start.year, start.month - 1));
      case ReportRange.custom:
        final days = end.difference(start).inDays + 1;
        return ReportPeriod(
          DateTime(start.year, start.month, start.day - days),
          DateTime(start.year, start.month, start.day - 1),
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

/// The headline numbers for one period.
class ReportSummary {
  const ReportSummary({
    required this.income,
    required this.expenses,
    required this.saved,
  });

  /// Money earned. Borrowed money and repayments aren't earnings.
  final double income;

  /// Money spent, bills included. Money lent out isn't spending.
  final double expenses;

  /// Put toward goals, less anything taken back out.
  final double saved;

  /// How much more came in than went out.
  double get netChange => income - expenses;
}

List<AppTransaction> transactionsIn(
  Iterable<AppTransaction> transactions,
  ReportPeriod period,
) => transactions.where((t) => period.contains(t.date)).toList();

ReportSummary summarize(
  Iterable<AppTransaction> transactions,
  Iterable<GoalContribution> contributions,
  ReportPeriod period,
) {
  final totals = inAndOut(transactionsIn(transactions, period));
  final saved = contributions
      .where((c) => period.contains(c.date))
      .fold<double>(0, (total, c) => total + c.amount);

  return ReportSummary(
    income: totals.moneyIn,
    expenses: totals.moneyOut,
    saved: saved,
  );
}

/// Money in and money out for one step of the trend chart.
class TrendPoint {
  const TrendPoint({
    required this.period,
    required this.label,
    required this.moneyIn,
    required this.moneyOut,
  });

  final ReportPeriod period;

  /// Short axis label: "Sep" for a month, "Sep 14" for a week.
  final String label;
  final double moneyIn;
  final double moneyOut;
}

/// Money in and out for up to [count] periods ending with the one holding
/// [end], oldest first. Weeks for a weekly report; months otherwise, since a
/// custom range rarely lines up with anything shorter.
///
/// Periods before the first record are left out: nothing was tracked then,
/// which isn't the same as nothing coming in or going out. The latest period
/// is always kept.
List<TrendPoint> trend(
  Iterable<AppTransaction> transactions, {
  required ReportRange range,
  required DateTime end,
  int count = 6,
}) {
  final weekly = range == ReportRange.week;
  var period = weekly ? ReportPeriod.weekOf(end) : ReportPeriod.monthOf(end);
  final periods = <ReportPeriod>[];

  // The first day anything was recorded.
  DateTime? firstDay;
  for (final transaction in transactions) {
    final day = DateTime(
      transaction.date.year,
      transaction.date.month,
      transaction.date.day,
    );
    if (firstDay == null || day.isBefore(firstDay)) firstDay = day;
  }

  for (var i = 0; i < count; i++) {
    if (i > 0 && firstDay != null && period.end.isBefore(firstDay)) break;
    periods.add(period);
    period = period.previous(weekly ? ReportRange.week : ReportRange.month);
  }

  return [
    for (final p in periods.reversed)
      _trendPoint(transactions, p, weekly: weekly),
  ];
}

TrendPoint _trendPoint(
  Iterable<AppTransaction> transactions,
  ReportPeriod period, {
  required bool weekly,
}) {
  final totals = inAndOut(transactionsIn(transactions, period));
  return TrendPoint(
    period: period,
    label: weekly
        ? formatMonthDay(period.start)
        : formatMonthName(period.start),
    moneyIn: totals.moneyIn,
    moneyOut: totals.moneyOut,
  );
}

/// Plain-language observations about a period's spending, most useful first.
///
/// Every line is worked out from the user's own records, and a line is only
/// given when there is enough to say it honestly: no comparisons without an
/// earlier period to compare with.
List<String> insightsFor(
  Iterable<AppTransaction> transactions, {
  required ReportPeriod period,
  required ReportRange range,
  int limit = 3,
}) {
  final current = transactionsIn(transactions, period);
  final spending = spendingByCategory(current);
  final totals = inAndOut(current);
  final lines = <String>[];
  final unit = switch (range) {
    ReportRange.week => 'week',
    ReportRange.month => 'month',
    ReportRange.custom => 'stretch',
  };

  if (spending.isEmpty) {
    return totals.moneyIn > 0
        ? [
            'Nothing spent this $unit yet. Everything that came in is still yours.',
          ]
        : const [];
  }

  // Against the average of the three periods before, for the biggest
  // categories. Periods with no spending at all are left out of the average,
  // so someone who only started last month isn't told they spend three times
  // their usual.
  final earlier = <List<MapEntry<String, double>>>[];
  var before = period;
  for (var i = 0; i < 3; i++) {
    before = before.previous(range);
    final list = spendingByCategory(transactionsIn(transactions, before));
    if (list.isNotEmpty) earlier.add(list);
  }

  if (earlier.isNotEmpty) {
    for (final entry in spending.take(3)) {
      final average =
          earlier.fold<double>(0, (total, list) {
            final match = list.where((e) => e.key == entry.key);
            return total + (match.isEmpty ? 0 : match.first.value);
          }) /
          earlier.length;
      if (average <= 0) continue;

      final change = (entry.value - average) / average;
      if (change.abs() < 0.10) continue;

      final percent = (change.abs() * 100).round();
      final span = earlier.length < 3
          ? 'recent'
          : switch (range) {
              ReportRange.week => '3-week',
              ReportRange.month => '3-month',
              ReportRange.custom => 'recent',
            };
      lines.add(
        '${entry.key} spending is $percent% ${change > 0 ? 'higher' : 'lower'} '
        'than your $span average.',
      );
    }
  }

  final total = spending.fold<double>(0, (sum, e) => sum + e.value);
  final top = spending.first;
  if (spending.length > 1) {
    final share = (top.value / total * 100).round();
    lines.add('${top.key} is $share% of your spending this $unit.');
  }

  if (totals.moneyIn > 0) {
    if (totals.moneyOut > totals.moneyIn + 0.005) {
      lines.add(
        'You spent ${formatPeso(totals.moneyOut - totals.moneyIn)} more than '
        'came in this $unit.',
      );
    } else {
      final kept = ((1 - totals.moneyOut / totals.moneyIn) * 100).round();
      lines.add('You kept $kept% of what came in this $unit.');
    }
  }

  return lines.take(limit).toList();
}
