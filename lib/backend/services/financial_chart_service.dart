import '../models/financial_chart.dart';
import '../models/financial_chart_context.dart';
import '../models/finance_snapshot.dart';
import '../models/debt.dart';
import 'financial_analysis_service.dart';

bool isFinancialChartRequest(String question) {
  final text = question.toLowerCase();
  final asksToVisualize = RegExp(
    r'\b(show|display|visuali[sz]e|chart|graph|plot|trend|'
    r'ipakita|ipakita mo|graphical)\b',
  ).hasMatch(text);
  final asksForFinancialData = RegExp(
    r'\b(income|expenses?|spending|savings?|goals?|debt|financial|'
    r'money|category|categories|standing|kita|gastos?|gastusin|'
    r'ipon|utang|pananalapi|buwan|monthly)\b',
  ).hasMatch(text);
  final asksForSavingsProgress =
      RegExp(
        r'\b(?:progress|progressing|progression|umunlad|pag.unlad)\b',
      ).hasMatch(text) &&
      RegExp(r'\b(?:savings?|saving|goal|goals|ipon)\b').hasMatch(text);
  return (asksToVisualize || asksForSavingsProgress) && asksForFinancialData;
}

FinancialChartData buildFinancialChart(
  String question,
  FinanceSnapshot records,
) {
  final text = question.toLowerCase();
  final analysis = analyzeFinancialSnapshot(records);
  final period = chartPeriodForQuestion(text);
  final threeMonths = period == FinancialChartPeriod.lastThreeMonths;
  final monthlyTrend =
      text.contains('trend') ||
      text.contains('monthly') ||
      text.contains('buwan');
  final categories = RegExp(
    r'\b(?:categor(?:y|ies)|where.*money goes|gastusin)\b',
  ).hasMatch(text);
  final savings = RegExp(
    r'\b(savings?|saving|goals?|ipon|makaipon)\b',
  ).hasMatch(text);
  final debt = RegExp(r'\b(debt|utang|repayment|bayad)\b').hasMatch(text);
  final incomeSources = RegExp(
    r'\b(?:income|kita).*(?:source|sources|by source)\b',
  ).hasMatch(text);
  final standing = RegExp(
    r'\b(?:financial standing|financial health|pananalapi)\b',
  ).hasMatch(text);
  final asksExpenses = RegExp(
    r'\b(expenses?|spending|gastos?|gastusin)\b',
  ).hasMatch(text);
  final asksIncome = RegExp(r'\b(income|kita)\b').hasMatch(text);
  final selectedRange = period == null || threeMonths
      ? null
      : chartPeriodRange(period, records.now);
  final selectedAnalysis = selectedRange == null
      ? analysis
      : analyzeFinancialSnapshot(
          records,
          from: selectedRange.start,
          until: selectedRange.end,
        );
  final specificCategory = selectedAnalysis.expensesByCategory.keys
      .cast<String?>()
      .firstWhere(
        (category) => category != null && text.contains(category.toLowerCase()),
        orElse: () => null,
      );

  if (savings) return _savingsChart(selectedAnalysis);
  if (debt) return _debtChart(records, selectedAnalysis);
  if (incomeSources) return _incomeSourceChart(selectedAnalysis);
  if (standing) return _standingChart(selectedAnalysis);
  if (specificCategory != null) {
    return _categoryExpenseChart(selectedAnalysis, specificCategory);
  }
  if (categories) return _categoryChart(selectedAnalysis);
  if (asksExpenses && !asksIncome) {
    if (threeMonths || monthlyTrend) {
      return _monthlyChart(
        records,
        line: monthlyTrend && !threeMonths,
        expensesOnly: true,
      );
    }
    return _expenseChart(selectedAnalysis);
  }
  if (asksIncome && !asksExpenses) {
    if (threeMonths || monthlyTrend) {
      return _monthlyChart(
        records,
        line: monthlyTrend && !threeMonths,
        incomeOnly: true,
      );
    }
    return _incomeChart(selectedAnalysis);
  }

  if (threeMonths || monthlyTrend) {
    return _monthlyChart(records, line: monthlyTrend && !threeMonths);
  }
  return _incomeExpenseChart(selectedAnalysis);
}

FinancialChartData _categoryExpenseChart(
  FinancialAnalysis analysis,
  String category,
) {
  final amount = analysis.expensesByCategory[category] ?? 0;
  if (amount == 0) {
    return FinancialChartData.unavailable(
      title: '$category expenses',
      periodLabel: _periodLabel(analysis),
      reason: 'There are no recorded expenses for $category in this period.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.bar,
    title: '$category expenses',
    periodLabel: _periodLabel(analysis),
    labels: [category],
    series: {
      'Expenses': [amount],
    },
    totals: {category: amount},
  );
}

FinancialChartData _expenseChart(FinancialAnalysis analysis) {
  if (analysis.recordedExpenses == 0) {
    return const FinancialChartData.unavailable(
      title: 'Expenses',
      periodLabel: 'Current month to date',
      reason: 'There are no recorded expenses for this period.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.bar,
    title: 'Expenses',
    periodLabel: _periodLabel(analysis),
    labels: const ['Expenses'],
    series: {
      'Expenses': [analysis.recordedExpenses],
    },
    totals: {'Expenses': analysis.recordedExpenses},
  );
}

FinancialChartData _incomeChart(FinancialAnalysis analysis) {
  if (analysis.recordedIncome == 0) {
    return const FinancialChartData.unavailable(
      title: 'Income',
      periodLabel: 'Current month to date',
      reason: 'There are no recorded income values for this period.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.bar,
    title: 'Income',
    periodLabel: _periodLabel(analysis),
    labels: const ['Income'],
    series: {
      'Income': [analysis.recordedIncome],
    },
    totals: {'Income': analysis.recordedIncome},
  );
}

FinancialChartData _incomeSourceChart(FinancialAnalysis analysis) {
  final entries =
      analysis.incomeBySource.entries.where((entry) => entry.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  if (entries.isEmpty) {
    return const FinancialChartData.unavailable(
      title: 'Income by source',
      periodLabel: 'Current month to date',
      reason: 'There are no recorded income sources for this period.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.pie,
    title: 'Income by source',
    periodLabel: _periodLabel(analysis),
    labels: [for (final entry in entries) entry.key],
    series: {
      'Income': [for (final entry in entries) entry.value],
    },
    totals: {for (final entry in entries) entry.key: entry.value},
  );
}

FinancialChartData _standingChart(FinancialAnalysis analysis) {
  final savings = analysis.savingsBalances.values.fold<double>(
    0,
    (sum, amount) => sum + amount,
  );
  final values = [
    analysis.recordedIncome,
    analysis.recordedExpenses,
    savings,
    analysis.activeDebtBalance,
  ];
  if (values.every((value) => value == 0)) {
    return const FinancialChartData.unavailable(
      title: 'Financial standing',
      periodLabel: 'Current recorded data',
      reason: 'There are no recorded financial values to display.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.bar,
    title: 'Financial standing',
    periodLabel: _periodLabel(analysis),
    labels: const ['Income', 'Expenses', 'Savings', 'Debt'],
    series: {'Amount': values},
    totals: {
      'Income': analysis.recordedIncome,
      'Expenses': analysis.recordedExpenses,
      'Savings': savings,
      'Debt': analysis.activeDebtBalance,
    },
  );
}

FinancialChartData _incomeExpenseChart(FinancialAnalysis analysis) {
  if (analysis.recordedIncome == 0 && analysis.recordedExpenses == 0) {
    return const FinancialChartData.unavailable(
      title: 'Income and expenses',
      periodLabel: 'Current month to date',
      reason: 'There are no recorded income or expense values for this period.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.bar,
    title: 'Income and expenses',
    periodLabel: _periodLabel(analysis),
    labels: const ['Income', 'Expenses'],
    series: {
      'Amount': [analysis.recordedIncome, analysis.recordedExpenses],
    },
    totals: {
      'Income': analysis.recordedIncome,
      'Expenses': analysis.recordedExpenses,
      'Remaining': analysis.remainingIncome,
    },
  );
}

FinancialChartData _categoryChart(FinancialAnalysis analysis) {
  final entries = analysis.expensesByCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (entries.isEmpty) {
    return const FinancialChartData.unavailable(
      title: 'Expenses by category',
      periodLabel: 'Current month to date',
      reason: 'There are no recorded expenses for this period.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.pie,
    title: 'Expenses by category',
    periodLabel: _periodLabel(analysis),
    labels: [for (final entry in entries) entry.key],
    series: {
      'Expenses': [for (final entry in entries) entry.value],
    },
    totals: {for (final entry in entries) entry.key: entry.value},
  );
}

FinancialChartData _monthlyChart(
  FinanceSnapshot records, {
  required bool line,
  bool incomeOnly = false,
  bool expensesOnly = false,
}) {
  final labels = <String>[];
  final income = <double>[];
  final expenses = <double>[];
  for (var offset = 2; offset >= 0; offset--) {
    final month = DateTime(records.now.year, records.now.month - offset);
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final analysis = analyzeFinancialSnapshot(records, from: start, until: end);
    labels.add('${month.year}-${month.month.toString().padLeft(2, '0')}');
    income.add(analysis.recordedIncome);
    expenses.add(analysis.recordedExpenses);
  }
  final selected = incomeOnly
      ? income
      : expensesOnly
      ? expenses
      : income;
  if (selected.every((value) => value == 0) &&
      (incomeOnly || expensesOnly || expenses.every((value) => value == 0))) {
    return FinancialChartData.unavailable(
      title: incomeOnly
          ? 'Monthly income'
          : expensesOnly
          ? 'Monthly expenses'
          : 'Monthly income and expenses',
      periodLabel: 'Last three calendar months',
      reason: 'There are no recorded values for these months.',
    );
  }
  final series = <String, List<double>>{
    if (!expensesOnly) 'Income': income,
    if (!incomeOnly) 'Expenses': expenses,
  };
  return FinancialChartData(
    type: line ? FinancialChartType.line : FinancialChartType.bar,
    title: incomeOnly
        ? 'Monthly income'
        : expensesOnly
        ? 'Monthly expenses'
        : 'Monthly income and expenses',
    periodLabel: 'Last three calendar months',
    labels: labels,
    series: series,
    totals: {
      if (!expensesOnly) 'Income': income.fold(0, (a, b) => a + b),
      if (!incomeOnly) 'Expenses': expenses.fold(0, (a, b) => a + b),
    },
  );
}

FinancialChartData _savingsChart(FinancialAnalysis analysis) {
  final goals = analysis.savingsProgress;
  if (goals.isEmpty) {
    return const FinancialChartData.unavailable(
      title: 'Savings goal progress',
      periodLabel: 'Current recorded goals',
      reason: 'There are no recorded savings goals to display.',
    );
  }
  return FinancialChartData(
    type: FinancialChartType.progress,
    title: 'Savings goal progress',
    periodLabel: 'Current recorded goals',
    labels: [for (final goal in goals) goal.name],
    series: {
      'Progress': [for (final goal in goals) goal.progress * 100],
    },
    totals: {for (final goal in goals) '${goal.name} saved': goal.saved},
  );
}

FinancialChartData _debtChart(
  FinanceSnapshot records,
  FinancialAnalysis analysis,
) {
  final debts = records.debts
      .where((debt) => debt.status == DebtStatus.active)
      .toList();
  if (debts.isEmpty) {
    return const FinancialChartData.unavailable(
      title: 'Debt repayment progress',
      periodLabel: 'Current active debts',
      reason: 'There are no recorded active debts to display.',
    );
  }
  final progress = [
    for (final debt in debts) DebtProgress.of(debt, records.bills),
  ];
  return FinancialChartData(
    type: FinancialChartType.progress,
    title: 'Debt repayment progress',
    periodLabel: 'Current active debts',
    labels: [for (final debt in debts) debt.name],
    series: {
      'Paid': [for (final item in progress) item.fraction * 100],
    },
    totals: {
      'Outstanding debt': analysis.activeDebtBalance,
      for (var i = 0; i < debts.length; i++)
        '${debts[i].name} remaining': progress[i].remaining,
    },
  );
}

String _periodLabel(FinancialAnalysis analysis) =>
    '${analysis.periodStart.year}-${analysis.periodStart.month.toString().padLeft(2, '0')} '
    'to ${analysis.periodEndExclusive.subtract(const Duration(days: 1)).day}';
