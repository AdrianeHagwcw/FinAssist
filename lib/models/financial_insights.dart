import 'app_transaction.dart';

/// Verified financial metrics derived only from saved transaction records.
///
/// The savings rate is net cash flow divided by recorded income; it does not
/// claim that positive cash flow was actually transferred into savings.
FinancialInsights calculateFinancialInsights(
  Iterable<AppTransaction> source, {
  required DateTime now,
  double? spendingBudget,
}) {
  final transactions = source.toList();
  final today = DateTime(now.year, now.month, now.day);
  final currentMonthStart = DateTime(today.year, today.month);
  final currentMonthEnd = today.add(const Duration(days: 1));
  final previousMonthStart = DateTime(today.year, today.month - 1);
  final previousMonthLength = DateTime(
    previousMonthStart.year,
    previousMonthStart.month + 1,
    0,
  ).day;
  final previousMonthDayCount = today.day > previousMonthLength
      ? previousMonthLength
      : today.day;
  final previousMonthEnd = previousMonthStart.add(
    Duration(days: previousMonthDayCount),
  );

  final currentMonth = transactions.where(
    (transaction) =>
        !transaction.date.isBefore(currentMonthStart) &&
        transaction.date.isBefore(currentMonthEnd),
  );
  final currentTotals = _moneyInAndOut(currentMonth);
  final netCashFlow = currentTotals.income - currentTotals.expenses;
  final savingsRate = currentTotals.income > 0
      ? netCashFlow / currentTotals.income * 100
      : null;

  final categoryTotals = <String, double>{};
  for (final transaction in currentMonth) {
    if (!_isSpending(transaction)) continue;
    categoryTotals[transaction.label] =
        (categoryTotals[transaction.label] ?? 0) + transaction.amount;
  }
  final sortedCategories = categoryTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final previousMonth = transactions.where(
    (transaction) =>
        !transaction.date.isBefore(previousMonthStart) &&
        transaction.date.isBefore(previousMonthEnd),
  );
  final previousMonthSpending = _moneyInAndOut(previousMonth).expenses;
  final spendingChangePercent = previousMonthSpending > 0
      ? (currentTotals.expenses - previousMonthSpending) /
            previousMonthSpending *
            100
      : null;

  final normalizedBudget =
      spendingBudget != null && spendingBudget.isFinite && spendingBudget > 0
      ? spendingBudget
      : null;
  final budgetUtilizationPercent = normalizedBudget == null
      ? null
      : currentTotals.expenses / normalizedBudget * 100;

  return FinancialInsights(
    asOf: today,
    income: currentTotals.income,
    expenses: currentTotals.expenses,
    netCashFlow: netCashFlow,
    netCashFlowSavingsRatePercent: savingsRate,
    expenseCategories: [
      for (final entry in sortedCategories)
        ExpenseCategoryTotal(entry.key, entry.value),
    ],
    budgetUtilizationPercent: budgetUtilizationPercent,
    currentMonthSpending: currentTotals.expenses,
    previousMonthToDateSpending: previousMonthSpending,
    spendingChangePercent: spendingChangePercent,
    healthScore: _healthScore(
      income: currentTotals.income,
      netCashFlow: netCashFlow,
      savingsRatePercent: savingsRate,
      spendingChangePercent: spendingChangePercent,
    ),
    forecast: _forecast(transactions, today),
  );
}

class FinancialInsights {
  const FinancialInsights({
    required this.asOf,
    required this.income,
    required this.expenses,
    required this.netCashFlow,
    required this.netCashFlowSavingsRatePercent,
    required this.expenseCategories,
    required this.budgetUtilizationPercent,
    required this.currentMonthSpending,
    required this.previousMonthToDateSpending,
    required this.spendingChangePercent,
    required this.healthScore,
    required this.forecast,
  });

  final DateTime asOf;
  final double income;
  final double expenses;
  final double netCashFlow;
  final double? netCashFlowSavingsRatePercent;
  final List<ExpenseCategoryTotal> expenseCategories;

  /// Null until a real, positive spending budget exists in the user's data.
  final double? budgetUtilizationPercent;

  /// Current month through [asOf], compared with the same number of days in
  /// the preceding month.
  final double currentMonthSpending;
  final double previousMonthToDateSpending;

  /// Null when the prior comparison period has no recorded spending.
  final double? spendingChangePercent;

  /// A transparent rule-based indicator, not a credit score or prediction.
  final int? healthScore;
  final SpendingForecast forecast;
}

/// Recorded expenses within one period, grouped for a like-for-like comparison.
class SpendingPeriodTotals {
  const SpendingPeriodTotals({
    required this.amount,
    required this.expenseCount,
    required this.categoryTotals,
  });

  final double amount;
  final int expenseCount;
  final Map<String, double> categoryTotals;
}

class SpendingPeriodComparison {
  const SpendingPeriodComparison({
    required this.days,
    required this.recent,
    required this.previous,
  });

  final int days;
  final SpendingPeriodTotals recent;
  final SpendingPeriodTotals previous;
}

/// Compares the latest [days] calendar days with the same-length period just
/// before them. Only saved, positive expense records are counted.
SpendingPeriodComparison compareSpendingPeriods(
  Iterable<AppTransaction> source, {
  required DateTime now,
  required int days,
}) {
  if (days < 1) {
    throw ArgumentError.value(days, 'days', 'Must be greater than zero.');
  }

  final today = DateTime(now.year, now.month, now.day);
  final recentStart = today.subtract(Duration(days: days - 1));
  final previousStart = recentStart.subtract(Duration(days: days));
  final tomorrow = today.add(const Duration(days: 1));
  final transactions = source.where(_isSpending).toList();

  SpendingPeriodTotals totalFor(DateTime start, DateTime end) {
    final totals = <String, double>{};
    var amount = 0.0;
    var expenseCount = 0;
    for (final transaction in transactions) {
      if (transaction.date.isBefore(start) || !transaction.date.isBefore(end)) {
        continue;
      }
      amount += transaction.amount;
      expenseCount++;
      totals[transaction.label] =
          (totals[transaction.label] ?? 0) + transaction.amount;
    }
    return SpendingPeriodTotals(
      amount: amount,
      expenseCount: expenseCount,
      categoryTotals: Map.unmodifiable(totals),
    );
  }

  return SpendingPeriodComparison(
    days: days,
    recent: totalFor(recentStart, tomorrow),
    previous: totalFor(previousStart, recentStart),
  );
}

class ExpenseCategoryTotal {
  const ExpenseCategoryTotal(this.category, this.amount);

  final String category;
  final double amount;
}

class SpendingForecast {
  const SpendingForecast({
    required this.monthlyAverage,
    required this.monthlyHistory,
    required this.isHighlyVariable,
  });

  /// Average of the three complete months before [FinancialInsights.asOf].
  /// Null unless each month contains at least one valid expense.
  final double? monthlyAverage;
  final List<double> monthlyHistory;
  final bool isHighlyVariable;

  bool get isAvailable => monthlyAverage != null;
}

({double income, double expenses}) _moneyInAndOut(
  Iterable<AppTransaction> transactions,
) {
  var income = 0.0;
  var expenses = 0.0;

  for (final transaction in transactions) {
    if (transaction.isDebtMovement ||
        !transaction.amount.isFinite ||
        transaction.amount < 0) {
      continue;
    }

    switch (transaction.type) {
      case TransactionType.income:
        income += transaction.amount;
      case TransactionType.expense:
        expenses += transaction.amount;
      case TransactionType.transfer:
        break;
    }
  }

  return (income: income, expenses: expenses);
}

bool _isSpending(AppTransaction transaction) =>
    transaction.type == TransactionType.expense &&
    !transaction.isDebtMovement &&
    transaction.amount.isFinite &&
    transaction.amount > 0;

int? _healthScore({
  required double income,
  required double netCashFlow,
  required double? savingsRatePercent,
  required double? spendingChangePercent,
}) {
  if (income <= 0 ||
      savingsRatePercent == null ||
      spendingChangePercent == null) {
    return null;
  }

  // 40 points for non-negative cash flow, up to 40 scaled linearly from a
  // 0% to 20% net cash-flow savings rate, and 20 when comparable spending
  // is flat or lower. The score is shown only when all three inputs exist.
  final cashFlowPoints = netCashFlow >= 0 ? 40 : 0;
  final savingsPoints = (savingsRatePercent.clamp(0, 20) * 2).round();
  final spendingTrendPoints = spendingChangePercent <= 0 ? 20 : 0;
  return cashFlowPoints + savingsPoints + spendingTrendPoints;
}

SpendingForecast _forecast(List<AppTransaction> transactions, DateTime today) {
  final months = <double>[];
  var month = DateTime(today.year, today.month);

  for (var offset = 1; offset <= 3; offset++) {
    month = DateTime(month.year, month.month - 1);
    final nextMonth = DateTime(month.year, month.month + 1);
    var spent = 0.0;
    var hasExpense = false;

    for (final transaction in transactions) {
      if (!_isSpending(transaction) ||
          transaction.date.isBefore(month) ||
          !transaction.date.isBefore(nextMonth)) {
        continue;
      }
      hasExpense = true;
      spent += transaction.amount;
    }

    if (!hasExpense) {
      return const SpendingForecast(
        monthlyAverage: null,
        monthlyHistory: [],
        isHighlyVariable: false,
      );
    }
    months.add(spent);
  }

  final average = months.fold<double>(0, (sum, value) => sum + value) / 3;
  final range =
      months.reduce((a, b) => a > b ? a : b) -
      months.reduce((a, b) => a < b ? a : b);

  return SpendingForecast(
    monthlyAverage: average,
    monthlyHistory: months.reversed.toList(),
    isHighlyVariable: average > 0 && range / average > 0.5,
  );
}
