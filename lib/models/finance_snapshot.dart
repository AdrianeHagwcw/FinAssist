import 'app_transaction.dart';
import 'bill.dart';
import 'debt.dart';
import 'goal.dart';
import 'safe_to_spend.dart';
import 'wallet.dart';

/// The user's own records, as the phone has them: what the assistant answers
/// from. Because it is read from the saved copy, answers work offline too.
class FinanceSnapshot {
  const FinanceSnapshot({
    required this.now,
    this.wallets = const [],
    this.transactions = const [],
    this.bills = const [],
    this.goals = const [],
    this.debts = const [],
    this.incomeFrequency,
    this.usualIncome,
    this.lastIncomeAt,
    this.savingsReserve = 0,
    this.customDailyLimit,
  });

  final DateTime now;
  final List<Wallet> wallets;
  final List<AppTransaction> transactions;

  /// Bills not yet settled, this month and next.
  final List<BillInstance> bills;
  final List<Goal> goals;
  final List<Debt> debts;

  /// From onboarding: how often income comes, and the usual amount, if given.
  final String? incomeFrequency;
  final double? usualIncome;

  /// When the user was last paid, which anchors the pay period. See
  /// [lastPayday]: a gift or a refund doesn't count.
  final DateTime? lastIncomeAt;

  final double savingsReserve;
  final double? customDailyLimit;

  DateTime get today => DateTime(now.year, now.month, now.day);

  /// The same records, looked at from [moment], such as when a question is
  /// asked long after they were read.
  FinanceSnapshot at(DateTime moment) => FinanceSnapshot(
    now: moment,
    wallets: wallets,
    transactions: transactions,
    bills: bills,
    goals: goals,
    debts: debts,
    incomeFrequency: incomeFrequency,
    usualIncome: usualIncome,
    lastIncomeAt: lastIncomeAt,
    savingsReserve: savingsReserve,
    customDailyLimit: customDailyLimit,
  );

  /// The pay period today falls in; its end is the next payday.
  PayPeriod get period =>
      payPeriodFor(incomeFrequency, lastIncomeAt: lastIncomeAt, now: now);

  double get walletBalance => totalWalletBalance(wallets);

  double get goalSavings => totalSetAside(goals);

  /// Today's Safe to Spend, worked out exactly as the Home card does.
  SafeToSpend get safeToSpend {
    final period = this.period;
    return SafeToSpend(
      walletBalance: walletBalance,
      billsDue: billsDueBefore(bills, period.end),
      savingsReserve: savingsReserve,
      goalSavings: goalSavings,
      spentToday: spentToday,
      daysLeft: period.daysLeft(now),
      customDailyLimit: customDailyLimit,
    );
  }

  /// Spent today, not counting bill payments or money lent.
  double get spentToday => discretionarySpending(
    transactions,
    from: today,
    until: today.add(const Duration(days: 1)),
  );

  /// What the user usually spends in a day, by choice: the last 30 days, or
  /// fewer for a newer account. Bill payments and money lent are left out.
  double get usualDailySpending {
    DateTime? first;
    for (final transaction in transactions) {
      if (transaction.type != TransactionType.expense) continue;
      if (first == null || transaction.date.isBefore(first)) {
        first = transaction.date;
      }
    }
    if (first == null) return 0;

    final monthAgo = today.subtract(const Duration(days: 30));
    final firstDay = DateTime(first.year, first.month, first.day);
    final from = firstDay.isAfter(monthAgo) ? firstDay : monthAgo;
    final days = today.difference(from).inDays + 1;
    final spent = discretionarySpending(
      transactions,
      from: from,
      until: today.add(const Duration(days: 1)),
    );
    return spent / (days < 1 ? 1 : days);
  }
}
