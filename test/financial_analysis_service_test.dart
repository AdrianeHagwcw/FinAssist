import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/models/account_audit_log.dart';
import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/finance_snapshot.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/models/financial_ai_guardrails.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/backend/services/financial_analysis_service.dart';
import 'package:testapp/backend/services/financial_ai_service.dart';

void main() {
  test(
    'combines current metrics with audit changes without replacing records',
    () {
      final snapshot = FinanceSnapshot(
        now: DateTime(2026, 11, 16),
        transactions: [
          AppTransaction(
            id: 'income',
            type: TransactionType.income,
            amount: 2000,
            label: 'Salary',
            date: DateTime(2026, 11, 1),
          ),
          AppTransaction(
            id: 'food',
            type: TransactionType.expense,
            amount: 500,
            label: 'Food',
            date: DateTime(2026, 11, 2),
          ),
        ],
        goals: [
          Goal(
            id: 'emergency',
            name: 'Emergency fund',
            targetAmount: 1000,
            savedAmount: 250,
            priority: 0,
            status: GoalStatus.active,
          ),
        ],
        auditLogs: [
          AccountAuditLog(
            id: 'change',
            action: 'updated',
            collection: 'transactions',
            documentId: 'food',
            occurredAt: DateTime(2026, 11, 3),
            previousAmount: 300,
            updatedAmount: 500,
          ),
        ],
      );

      final analysis = analyzeFinancialSnapshot(snapshot);

      expect(analysis.insights.income, 2000);
      expect(analysis.insights.expenses, 500);
      expect(analysis.savingsProgress.single.progress, 0.25);
      expect(analysis.significantChanges.single.previousAmount, 300);
    },
  );

  test(
    'financial summary exposes actual period, balances, sources, and debt',
    () {
      final snapshot = FinanceSnapshot(
        now: DateTime(2026, 11, 16),
        wallets: [
          Wallet(
            id: 'bank',
            name: 'Bank',
            type: WalletType.bank,
            balance: 5000,
            startingBalance: 5000,
            receivesIncome: true,
            archived: false,
            sortOrder: 0,
          ),
          Wallet(
            id: 'savings',
            name: 'Savings',
            type: WalletType.bank,
            balance: 3000,
            startingBalance: 3000,
            receivesIncome: false,
            archived: false,
            sortOrder: 1,
            purpose: WalletPurpose.savings,
          ),
        ],
        transactions: [
          AppTransaction(
            id: 'salary',
            type: TransactionType.income,
            amount: 10000,
            label: 'Salary',
            date: DateTime(2026, 11, 1),
          ),
          AppTransaction(
            id: 'food',
            type: TransactionType.expense,
            amount: 1500,
            label: 'Food',
            date: DateTime(2026, 11, 2),
          ),
        ],
      );

      final summary = FirebaseFinancialAssistant.financialSummary(snapshot);

      expect(summary['recordedIncome'], 10000);
      expect(summary['recordedExpenses'], 1500);
      expect(summary['remainingIncomeAfterExpenses'], 8500);
      expect(summary['incomeBySource'], {'Salary': 10000});
      expect(summary['expenseCategoryTotals'], {'Food': 1500});
      expect(summary['currentSavingsTotal'], 3000);
      expect(summary['bankAndEWalletBalances'], {
        'Bank account 1': 5000,
        'Bank account 2': 3000,
      });
      expect(
        (summary['monthlyIncomeExpenseComparisons'] as List).last,
        containsPair('income', 10000),
      );
    },
  );

  test('numeric claims remain subject to the existing guardrail', () {
    expect(
      isUsableFinancialExplanation(
        'Your recorded income is ₱1,000 this month.',
        allowNumbers: true,
      ),
      isTrue,
    );
    expect(
      isUsableFinancialExplanation(
        'Your recorded income is 999999 this month.',
        allowNumbers: true,
      ),
      isTrue,
    );
    expect(isUsableFinancialExplanation('Your income is 999999.'), isFalse);
  });

  test(
    'generic savings advice may use examples but account questions stay strict',
    () {
      expect(
        allowsGeneralNumericAdvice('Can you give me savings suggestions?'),
        isTrue,
      );
      expect(
        allowsGeneralNumericAdvice('What is my total income this month?'),
        isFalse,
      );
    },
  );
}
