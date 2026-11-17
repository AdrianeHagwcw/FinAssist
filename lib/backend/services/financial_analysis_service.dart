import '../models/finance_snapshot.dart';
import '../models/financial_insights.dart';
import '../models/debt.dart';
import '../models/app_transaction.dart';
import '../models/wallet.dart';

/// Numeric facts prepared locally before any AI request.
class FinancialAnalysis {
  const FinancialAnalysis({
    required this.insights,
    required this.periodStart,
    required this.periodEndExclusive,
    required this.recordedIncome,
    required this.recordedExpenses,
    required this.remainingIncome,
    required this.incomeBySource,
    required this.expensesByCategory,
    required this.savingsBalances,
    required this.bankAndEWalletBalances,
    required this.savingsProgress,
    required this.activeDebtBalance,
    required this.upcomingPayments,
    required this.significantChanges,
  });

  final FinancialInsights insights;
  final DateTime periodStart;
  final DateTime periodEndExclusive;
  final double recordedIncome;
  final double recordedExpenses;
  final double remainingIncome;
  final Map<String, double> incomeBySource;
  final Map<String, double> expensesByCategory;
  final Map<String, double> savingsBalances;
  final Map<String, double> bankAndEWalletBalances;
  final List<SavingsProgress> savingsProgress;
  final double activeDebtBalance;
  final List<UpcomingPayment> upcomingPayments;
  final List<FinancialChange> significantChanges;
}

class SavingsProgress {
  const SavingsProgress({
    required this.name,
    required this.saved,
    required this.target,
    required this.progress,
  });

  final String name;
  final double saved;
  final double target;
  final double progress;
}

class UpcomingPayment {
  const UpcomingPayment({
    required this.name,
    required this.amount,
    required this.dueDate,
  });

  final String name;
  final double amount;
  final DateTime dueDate;
}

class FinancialChange {
  const FinancialChange({
    required this.action,
    required this.collection,
    required this.occurredAt,
    this.previousAmount,
    this.updatedAmount,
  });

  final String action;
  final String collection;
  final DateTime occurredAt;
  final double? previousAmount;
  final double? updatedAmount;
}

FinancialAnalysis analyzeFinancialSnapshot(
  FinanceSnapshot records, {
  DateTime? from,
  DateTime? until,
}) {
  final insights = calculateFinancialInsights(
    records.transactions,
    now: records.now,
    spendingBudget: records.periodBudget,
  );
  final periodStart = from ?? DateTime(records.now.year, records.now.month);
  final periodEndExclusive =
      until ??
      DateTime(records.now.year, records.now.month, records.now.day + 1);
  final periodTransactions = records.transactions.where(
    (transaction) =>
        !transaction.date.isBefore(periodStart) &&
        transaction.date.isBefore(periodEndExclusive),
  );
  var recordedIncome = 0.0;
  var recordedExpenses = 0.0;
  final incomeBySource = <String, double>{};
  final expensesByCategory = <String, double>{};
  for (final transaction in periodTransactions) {
    if (!transaction.amount.isFinite ||
        transaction.amount <= 0 ||
        transaction.isDebtMovement) {
      continue;
    }
    if (transaction.type == TransactionType.income) {
      recordedIncome += transaction.amount;
      incomeBySource[transaction.label] =
          (incomeBySource[transaction.label] ?? 0) + transaction.amount;
    } else if (transaction.type == TransactionType.expense) {
      for (final part in transaction.spendingParts) {
        recordedExpenses += part.value;
        expensesByCategory[part.key] =
            (expensesByCategory[part.key] ?? 0) + part.value;
      }
    }
  }
  final validWallets = records.wallets.where(
    (wallet) => !wallet.archived && wallet.balance.isFinite,
  );
  final savingsBalances = <String, double>{};
  final bankAndEWalletBalances = <String, double>{};
  var savingsNumber = 0;
  var bankNumber = 0;
  var eWalletNumber = 0;
  for (final wallet in validWallets) {
    if (wallet.purpose == WalletPurpose.savings) {
      savingsNumber++;
      savingsBalances['Savings account $savingsNumber'] = wallet.balance;
    }
    if (wallet.isBankOrEWallet) {
      final label = wallet.type == WalletType.bank
          ? 'Bank account ${++bankNumber}'
          : 'E-wallet ${++eWalletNumber}';
      bankAndEWalletBalances[label] = wallet.balance;
    }
  }
  final payments = [
    for (final bill in records.bills)
      if (!bill.isSettled &&
          (from == null || !bill.dueDate.isBefore(from)) &&
          (until == null || bill.dueDate.isBefore(until)))
        UpcomingPayment(
          name: bill.name,
          amount: bill.remaining,
          dueDate: bill.dueDate,
        ),
  ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  final changes = [
    for (final log in records.auditLogs)
      if ((from == null || !log.occurredAt.isBefore(from)) &&
          (until == null || log.occurredAt.isBefore(until)))
        FinancialChange(
          action: log.action,
          collection: log.collection,
          occurredAt: log.occurredAt,
          previousAmount: log.previousAmount,
          updatedAmount: log.updatedAmount,
        ),
  ];

  return FinancialAnalysis(
    insights: insights,
    periodStart: periodStart,
    periodEndExclusive: periodEndExclusive,
    recordedIncome: recordedIncome,
    recordedExpenses: recordedExpenses,
    remainingIncome: recordedIncome - recordedExpenses,
    incomeBySource: Map.unmodifiable(incomeBySource),
    expensesByCategory: Map.unmodifiable(expensesByCategory),
    savingsBalances: Map.unmodifiable(savingsBalances),
    bankAndEWalletBalances: Map.unmodifiable(bankAndEWalletBalances),
    savingsProgress: [
      for (final goal in records.goals)
        SavingsProgress(
          name: goal.name,
          saved: goal.shownSaved,
          target: goal.targetAmount,
          progress: goal.progress,
        ),
    ],
    activeDebtBalance: records.debts
        .where(
          (debt) =>
              debt.status == DebtStatus.active &&
              debt.direction == DebtDirection.iOwe,
        )
        .fold<double>(0, (total, debt) => total + debt.principal),
    upcomingPayments: payments,
    significantChanges: changes,
  );
}
