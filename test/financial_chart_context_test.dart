import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/models/financial_chart.dart';
import 'package:testapp/backend/models/financial_chart_context.dart';

void main() {
  final now = DateTime(2026, 11, 16);

  test('inherits the previous period when changing income to expenses', () {
    final previous = chartContextFor(
      'Show my income for the last three months.',
      const FinancialChartData(
        type: FinancialChartType.bar,
        title: 'Monthly income',
        periodLabel: 'Last three calendar months',
        labels: ['2026-09', '2026-10', '2026-11'],
        series: {
          'Income': [100, 200, 300],
        },
        totals: {'Income': 600},
      ),
      now,
    );

    final followUp = resolveFinancialChartFollowUp(
      'How about the expenses?',
      previous,
    );

    expect(followUp?.metric, 'expenses');
    expect(followUp?.period, FinancialChartPeriod.lastThreeMonths);
    expect(followUp?.question, contains('last three months'));
  });

  test('changes only the period for a period-only follow-up', () {
    final previous = chartContextFor(
      'Show my expenses this month.',
      const FinancialChartData(
        type: FinancialChartType.bar,
        title: 'Expenses',
        periodLabel: 'Current month',
        labels: ['Expenses'],
        series: {
          'Expenses': [100],
        },
        totals: {'Expenses': 100},
      ),
      now,
    );

    final followUp = resolveFinancialChartFollowUp(
      'How about last month?',
      previous,
    );

    expect(followUp?.metric, 'expenses');
    expect(followUp?.period, FinancialChartPeriod.lastMonth);
  });

  test('resolves Tagalog metric follow-ups', () {
    final previous = FinancialChartContext(
      metric: 'income',
      period: FinancialChartPeriod.thisMonth,
      chartType: FinancialChartType.bar,
      startDate: DateTime(2026, 11),
      endDate: DateTime(2026, 12),
      category: null,
      chartGenerated: true,
    );

    final followUp = resolveFinancialChartFollowUp(
      'Paano naman ang aking mga gastos?',
      previous,
    );

    expect(followUp?.metric, 'expenses');
  });

  test('preserves income for a today-only follow-up', () {
    final previous = chartContextFor(
      'Show my income graph.',
      const FinancialChartData(
        type: FinancialChartType.bar,
        title: 'Income',
        periodLabel: 'Current month',
        labels: ['Income'],
        series: {
          'Income': [100],
        },
        totals: {'Income': 100},
      ),
      now,
    );

    final followUp = resolveFinancialChartFollowUp(
      'How about today only?',
      previous,
      knownCategories: ['today'],
    );

    expect(followUp?.metric, 'income');
    expect(followUp?.period, FinancialChartPeriod.today);
    expect(followUp?.question, 'Show my income today.');
  });

  test('resolves a complete multi-turn chart sequence', () {
    final income = chartContextFor(
      'Show me the graph of my income.',
      const FinancialChartData(
        type: FinancialChartType.bar,
        title: 'Income',
        periodLabel: 'Current month',
        labels: ['Income'],
        series: {
          'Income': [100],
        },
        totals: {'Income': 100},
      ),
      now,
    );
    final yesterday = resolveFinancialChartFollowUp(
      'How about yesterday only?',
      income,
    )!;
    expect(yesterday.metric, 'income');
    expect(yesterday.period, FinancialChartPeriod.yesterday);

    final yesterdayContext = FinancialChartContext(
      metric: yesterday.metric,
      period: yesterday.period,
      chartType: FinancialChartType.bar,
      startDate: DateTime(2026, 11, 15),
      endDate: DateTime(2026, 11, 16),
      category: null,
      chartGenerated: true,
    );
    final today = resolveFinancialChartFollowUp(
      'How about today?',
      yesterdayContext,
    )!;
    expect(today.metric, 'income');
    expect(today.period, FinancialChartPeriod.today);
  });
}
