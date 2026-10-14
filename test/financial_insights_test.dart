import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/financial_insights.dart';
import 'package:testapp/models/financial_topic_validator.dart';

AppTransaction transaction(
  String id,
  TransactionType type,
  double amount,
  DateTime date, {
  String category = 'Food',
  bool debtMovement = false,
}) => AppTransaction(
  id: id,
  type: type,
  amount: amount,
  label: category,
  date: date,
  debtId: debtMovement ? 'debt' : null,
);

void main() {
  group('calculateFinancialInsights', () {
    final now = DateTime(2026, 10, 14, 12);

    test('calculates cash flow and category totals from eligible records', () {
      final result = calculateFinancialInsights([
        transaction('pay', TransactionType.income, 2000, DateTime(2026, 10)),
        transaction(
          'food',
          TransactionType.expense,
          300,
          DateTime(2026, 10, 2),
        ),
        transaction(
          'bill',
          TransactionType.expense,
          200,
          DateTime(2026, 10, 3),
          category: 'Bills',
        ),
        transaction(
          'borrowed',
          TransactionType.income,
          5000,
          DateTime(2026, 10, 4),
          debtMovement: true,
        ),
        transaction(
          'lent',
          TransactionType.expense,
          700,
          DateTime(2026, 10, 5),
          debtMovement: true,
        ),
        transaction(
          'transfer',
          TransactionType.transfer,
          1000,
          DateTime(2026, 10, 6),
        ),
      ], now: now);

      expect(result.income, 2000);
      expect(result.expenses, 500);
      expect(result.netCashFlow, 1500);
      expect(result.netCashFlowSavingsRatePercent, 75);
      expect(
        result.expenseCategories.map((entry) => (entry.category, entry.amount)),
        [('Food', 300.0), ('Bills', 200.0)],
      );
    });

    test(
      'does not divide by zero or claim budget utilization without a budget',
      () {
        final result = calculateFinancialInsights(
          [
            transaction(
              'expense',
              TransactionType.expense,
              100,
              DateTime(2026, 10, 2),
            ),
          ],
          now: now,
          spendingBudget: 0,
        );

        expect(result.netCashFlowSavingsRatePercent, isNull);
        expect(result.budgetUtilizationPercent, isNull);
        expect(result.spendingChangePercent, isNull);
        expect(result.healthScore, isNull);
        expect(result.expenses, 100);
      },
    );

    test(
      'compares equal month-to-date day counts and calculates budget use',
      () {
        final result = calculateFinancialInsights(
          [
            transaction(
              'old',
              TransactionType.expense,
              100,
              DateTime(2026, 9, 14),
            ),
            transaction(
              'outside-comparison',
              TransactionType.expense,
              900,
              DateTime(2026, 9, 15),
            ),
            transaction(
              'current',
              TransactionType.expense,
              80,
              DateTime(2026, 10, 14),
            ),
            transaction(
              'income',
              TransactionType.income,
              1000,
              DateTime(2026, 10, 1),
            ),
          ],
          now: now,
          spendingBudget: 400,
        );

        expect(result.previousMonthToDateSpending, 100);
        expect(result.currentMonthSpending, 80);
        expect(result.spendingChangePercent, -20);
        expect(result.budgetUtilizationPercent, 20);
      },
    );

    test(
      'uses a transparent score only when each scoring input is available',
      () {
        final result = calculateFinancialInsights([
          transaction('pay', TransactionType.income, 1000, DateTime(2026, 10)),
          transaction(
            'now',
            TransactionType.expense,
            400,
            DateTime(2026, 10, 3),
          ),
          transaction(
            'prior',
            TransactionType.expense,
            500,
            DateTime(2026, 9, 3),
          ),
        ], now: now);

        expect(result.healthScore, 100);
      },
    );

    test('forecast needs expense history in all three completed months', () {
      final unavailable = calculateFinancialInsights([
        transaction('jul', TransactionType.expense, 100, DateTime(2026, 7, 5)),
        transaction('sep', TransactionType.expense, 300, DateTime(2026, 9, 5)),
      ], now: now);
      expect(unavailable.forecast.isAvailable, isFalse);
      expect(unavailable.forecast.monthlyAverage, isNull);

      final available = calculateFinancialInsights([
        transaction('jul', TransactionType.expense, 100, DateTime(2026, 7, 5)),
        transaction('aug', TransactionType.expense, 200, DateTime(2026, 8, 5)),
        transaction('sep', TransactionType.expense, 300, DateTime(2026, 9, 5)),
      ], now: now);
      expect(available.forecast.monthlyHistory, [100, 200, 300]);
      expect(available.forecast.monthlyAverage, 200);
      expect(available.forecast.isHighlyVariable, isTrue);
    });
  });

  group('isFinancialTopic', () {
    test('allows supported financial topics in English and Taglish', () {
      expect(isFinancialTopic('How can I save more each month?'), isTrue);
      expect(isFinancialTopic('Anong gastos ko sa pagkain?'), isTrue);
      expect(isFinancialTopic('Explain compound interest'), isTrue);
      expect(isFinancialTopic('Explain inflation and my budget'), isTrue);
      expect(isFinancialTopic('How do I track expenses in FinAssist?'), isTrue);
      expect(
        isFinancialTopic(
          'pero gusto ko ring bumili ng cellphones, computers and etx sa '
          'tingin mo ba kaya kong mabili lahat ng bagay na to in the next 5 years',
        ),
        isTrue,
      );
    });

    test('rejects unrelated or empty questions before a model request', () {
      expect(isFinancialTopic('What is the weather tomorrow?'), isFalse);
      expect(isFinancialTopic('Write me a poem about a tree'), isFalse);
      expect(
        isFinancialTopic("What's the weather, and tell me my budget?"),
        isFalse,
      );
      expect(isFinancialTopic('   '), isFalse);
    });
  });
}
