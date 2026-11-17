import 'financial_chart.dart';

enum FinancialChartPeriod {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisYear,
  lastYear,
  lastThreeMonths,
}

class FinancialChartDateRange {
  const FinancialChartDateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

class FinancialChartContext {
  const FinancialChartContext({
    required this.metric,
    required this.period,
    required this.chartType,
    required this.startDate,
    required this.endDate,
    required this.category,
    required this.chartGenerated,
  });

  final String metric;
  final FinancialChartPeriod period;
  final FinancialChartType chartType;
  final DateTime startDate;
  final DateTime endDate;
  final String? category;
  final bool chartGenerated;
}

class FinancialChartFollowUp {
  const FinancialChartFollowUp({
    required this.question,
    required this.metric,
    required this.period,
    required this.category,
  });

  final String question;
  final String metric;
  final FinancialChartPeriod period;
  final String? category;
}

FinancialChartFollowUp? resolveFinancialChartFollowUp(
  String question,
  FinancialChartContext? previous, {
  Iterable<String> knownCategories = const [],
}) {
  if (previous == null || !previous.chartGenerated) return null;
  final text = question.toLowerCase().trim();
  final periodInQuestion = _periodIn(text);
  final FinancialChartPeriod period = periodInQuestion ?? previous.period;
  final category = periodInQuestion == null
      ? _categoryIn(text, knownCategories)
      : null;
  final metric =
      _metricIn(text, category) ??
      (text.contains('compare') || text.contains('both')
          ? 'income_expenses'
          : previous.metric);
  final isFollowUp = RegExp(
    r'^(?:how about|what about|and my|show the other|can you compare|'
    r'compare both|paano naman|at ang|ipakita rin)\b',
  ).hasMatch(text);
  final hasPeriodOnlyChange = _periodIn(text) != null && !_containsMetric(text);
  if (!isFollowUp && !hasPeriodOnlyChange) return null;

  final periodText = switch (period) {
    FinancialChartPeriod.today => 'today',
    FinancialChartPeriod.yesterday => 'yesterday',
    FinancialChartPeriod.thisWeek => 'this week',
    FinancialChartPeriod.lastWeek => 'last week',
    FinancialChartPeriod.thisMonth => 'this month',
    FinancialChartPeriod.lastMonth => 'last month',
    FinancialChartPeriod.thisYear => 'this year',
    FinancialChartPeriod.lastYear => 'last year',
    FinancialChartPeriod.lastThreeMonths => 'last three months',
  };
  final metricText = switch (metric) {
    'income' => 'income',
    'expenses' => 'expenses',
    'savings' => 'savings progress',
    'debt' => 'debt repayment',
    _ => 'income and expenses',
  };
  final categoryText = category == null ? '' : ' by category for $category';
  return FinancialChartFollowUp(
    question: 'Show my $metricText$categoryText $periodText.',
    metric: metric,
    period: period,
    category: category,
  );
}

FinancialChartContext chartContextFor(
  String question,
  FinancialChartData chart,
  DateTime now,
) {
  final period = _periodIn(question) ?? FinancialChartPeriod.thisMonth;
  final range = chartPeriodRange(period, now);
  final category = _categoryIn(question, chart.totals.keys);
  return FinancialChartContext(
    metric: _metricIn(question, category) ?? 'income_expenses',
    period: period,
    chartType: chart.type,
    startDate: range.start,
    endDate: range.end,
    category: category,
    chartGenerated: chart.available,
  );
}

FinancialChartPeriod? chartPeriodForQuestion(String question) =>
    _periodIn(question.toLowerCase());

FinancialChartDateRange chartPeriodRange(
  FinancialChartPeriod period,
  DateTime now,
) {
  switch (period) {
    case FinancialChartPeriod.today:
      return FinancialChartDateRange(
        DateTime(now.year, now.month, now.day),
        DateTime(now.year, now.month, now.day + 1),
      );
    case FinancialChartPeriod.yesterday:
      return FinancialChartDateRange(
        DateTime(now.year, now.month, now.day - 1),
        DateTime(now.year, now.month, now.day),
      );
    case FinancialChartPeriod.thisWeek:
      final start = DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - DateTime.monday),
      );
      return FinancialChartDateRange(
        start,
        DateTime(start.year, start.month, start.day + 7),
      );
    case FinancialChartPeriod.lastWeek:
      final thisWeek = chartPeriodRange(FinancialChartPeriod.thisWeek, now);
      return FinancialChartDateRange(
        thisWeek.start.subtract(const Duration(days: 7)),
        thisWeek.start,
      );
    case FinancialChartPeriod.thisMonth:
      return FinancialChartDateRange(
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      );
    case FinancialChartPeriod.lastMonth:
      return FinancialChartDateRange(
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month),
      );
    case FinancialChartPeriod.thisYear:
      return FinancialChartDateRange(
        DateTime(now.year),
        DateTime(now.year + 1),
      );
    case FinancialChartPeriod.lastYear:
      return FinancialChartDateRange(
        DateTime(now.year - 1),
        DateTime(now.year),
      );
    case FinancialChartPeriod.lastThreeMonths:
      return FinancialChartDateRange(
        DateTime(now.year, now.month - 2),
        DateTime(now.year, now.month + 1),
      );
  }
}

FinancialChartPeriod? _periodIn(String text) {
  if (RegExp(r'\b(?:today|ngayong araw)\b').hasMatch(text)) {
    return FinancialChartPeriod.today;
  }
  if (RegExp(r'\b(?:yesterday|kahapon)\b').hasMatch(text)) {
    return FinancialChartPeriod.yesterday;
  }
  if (RegExp(r'\b(?:this|current)\s+week|linggong ito\b').hasMatch(text)) {
    return FinancialChartPeriod.thisWeek;
  }
  if (RegExp(r'\b(?:last|previous)\s+week|nakaraang linggo\b').hasMatch(text)) {
    return FinancialChartPeriod.lastWeek;
  }
  if (RegExp(
    r'\b(?:last|past|previous|nakaraang)\s*(?:three|3|tatlong)\s*months?\b',
  ).hasMatch(text)) {
    return FinancialChartPeriod.lastThreeMonths;
  }
  if (RegExp(r'\b(?:last|previous|nakaraang)\s+month\b').hasMatch(text)) {
    return FinancialChartPeriod.lastMonth;
  }
  if (RegExp(r'\b(?:this|current)\s+month\b').hasMatch(text)) {
    return FinancialChartPeriod.thisMonth;
  }
  if (RegExp(r'\b(?:this|current)\s+year|taong ito\b').hasMatch(text)) {
    return FinancialChartPeriod.thisYear;
  }
  if (RegExp(r'\b(?:last|previous)\s+year|nakaraang taon\b').hasMatch(text)) {
    return FinancialChartPeriod.lastYear;
  }
  return null;
}

String? _metricIn(String text, String? category) {
  final hasIncome = RegExp(r'\b(?:income|kita)\b').hasMatch(text);
  final hasExpenses = RegExp(
    r'\b(?:expenses?|spending|gastos?|gastusin)\b',
  ).hasMatch(text);
  if (text.contains('compare') ||
      text.contains('both') ||
      (hasIncome && hasExpenses)) {
    return 'income_expenses';
  }
  if (RegExp(r'\b(?:savings?|saving|goal|goals|ipon)\b').hasMatch(text)) {
    return 'savings';
  }
  if (RegExp(r'\b(?:debt|utang|repayment)\b').hasMatch(text)) return 'debt';
  if (category != null ||
      RegExp(r'\b(?:expenses?|spending|gastos?|gastusin)\b').hasMatch(text)) {
    return 'expenses';
  }
  if (hasIncome) return 'income';
  return null;
}

String? _categoryIn(String text, Iterable<String> knownCategories) {
  const reserved = {
    'income',
    'expenses',
    'expense',
    'savings',
    'saving',
    'debt',
    'remaining',
    'amount',
    'paid',
  };
  for (final category in knownCategories) {
    final normalized = category.toLowerCase().trim();
    if (normalized.isNotEmpty &&
        !reserved.contains(normalized) &&
        text.contains(normalized)) {
      return category;
    }
  }
  return null;
}

bool _containsMetric(String text) =>
    _metricIn(text, null) != null ||
    RegExp(r'\b(?:category|categories|category|kategorya)\b').hasMatch(text);
