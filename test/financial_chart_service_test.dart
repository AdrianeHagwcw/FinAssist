import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/finance_snapshot.dart';
import 'package:testapp/backend/models/financial_chart.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/services/financial_chart_service.dart';

void main() {
  final records = FinanceSnapshot(
    now: DateTime(2026, 11, 16),
    transactions: [
      AppTransaction(
        id: 'old-income',
        type: TransactionType.income,
        amount: 2000,
        label: 'Salary',
        date: DateTime(2026, 9, 1),
      ),
      AppTransaction(
        id: 'old-expense',
        type: TransactionType.expense,
        amount: 500,
        label: 'Food',
        date: DateTime(2026, 9, 2),
      ),
      AppTransaction(
        id: 'income',
        type: TransactionType.income,
        amount: 3000,
        label: 'Salary',
        date: DateTime(2026, 11, 1),
      ),
      AppTransaction(
        id: 'food',
        type: TransactionType.expense,
        amount: 800,
        label: 'Food',
        date: DateTime(2026, 11, 2),
      ),
      AppTransaction(
        id: 'transport',
        type: TransactionType.expense,
        amount: 200,
        label: 'Transportation',
        date: DateTime(2026, 11, 3),
      ),
    ],
    goals: [
      Goal(
        id: 'goal',
        name: 'Emergency fund',
        targetAmount: 1000,
        savedAmount: 250,
        priority: 0,
        status: GoalStatus.active,
      ),
    ],
  );

  test('recognizes English and Tagalog chart requests', () {
    expect(isFinancialChartRequest('Show my expenses by category.'), isTrue);
    expect(
      isFinancialChartRequest('Ipakita ang aking mga gastusin ngayong buwan.'),
      isTrue,
    );
    expect(isFinancialChartRequest('How much did I spend?'), isFalse);
  });

  test('recognizes savings goal progress as a chart request', () {
    expect(
      isFinancialChartRequest('How am I progressing toward my savings goal?'),
      isTrue,
    );
  });

  test('uses an income and expense chart for Tagalog comparisons', () {
    final chart = buildFinancialChart(
      'Ipakita ang paghahambing ng aking kita at gastos.',
      records,
    );

    expect(chart.title, 'Income and expenses');
    expect(chart.series['Amount'], [3000, 1000]);
  });

  test('builds category chart from verified expense records', () {
    final chart = buildFinancialChart('Show my expenses by category.', records);

    expect(chart.type, FinancialChartType.pie);
    expect(chart.labels, ['Food', 'Transportation']);
    expect(chart.series['Expenses'], [800, 200]);
    expect(chart.totals['Food'], 800);
  });

  test('builds a chart for one requested expense category', () {
    final chart = buildFinancialChart(
      'Show my expenses by category for Transportation this month.',
      records,
    );

    expect(chart.title, 'Transportation expenses');
    expect(chart.totals['Transportation'], 200);
  });

  test('builds three-month comparison without inventing values', () {
    final chart = buildFinancialChart(
      'Compare my income and expenses over the last three months.',
      records,
    );

    expect(chart.type, FinancialChartType.bar);
    expect(chart.labels, ['2026-09', '2026-10', '2026-11']);
    expect(chart.series['Income'], [2000, 0, 3000]);
    expect(chart.series['Expenses'], [500, 0, 1000]);
  });

  test('keeps a three-month expense request expense-only', () {
    final chart = buildFinancialChart(
      'Show me a chart of my expenses for the last three months.',
      records,
    );

    expect(chart.title, 'Monthly expenses');
    expect(chart.series.keys.toList(), ['Expenses']);
    expect(chart.series['Expenses'], [500, 0, 1000]);
    expect(chart.totals.keys.toList(), ['Expenses']);
  });

  test('reports unavailable chart data instead of creating samples', () {
    final chart = buildFinancialChart(
      'Show my monthly spending trends.',
      FinanceSnapshot(now: DateTime(2026, 11, 16)),
    );

    expect(chart.available, isFalse);
    expect(chart.unavailableReason, contains('no recorded'));
  });

  test('builds financial standing from recorded totals', () {
    final chart = buildFinancialChart(
      'Visualize my financial standing.',
      records,
    );

    expect(chart.type, FinancialChartType.bar);
    expect(chart.labels, ['Income', 'Expenses', 'Savings', 'Debt']);
    expect(chart.series['Amount'], [3000, 1000, 0, 0]);
  });
}
