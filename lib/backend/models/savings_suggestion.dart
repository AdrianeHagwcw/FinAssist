import 'dart:math' as math;

import 'app_transaction.dart';
import 'finance_snapshot.dart';
import 'safe_to_spend.dart';

/// A modest, optional share of money left after recorded commitments and
/// estimated day-to-day costs. This does not promise that future costs are known.
class SavingsSuggestion {
  const SavingsSuggestion({
    required this.available,
    required this.dailyCosts,
    required this.amount,
    required this.hasHistory,
  });

  final double available;
  final double dailyCosts;
  final double amount;
  final bool hasHistory;

  static SavingsSuggestion from(FinanceSnapshot records) {
    final end = records.today.add(const Duration(days: 1));
    final start = records.today.subtract(const Duration(days: 29));
    // Seven distinct days with ordinary spending avoids treating a lone
    // purchase or a newly opened account as a reliable spending pattern.
    final spendingDays = <DateTime>{};
    for (final transaction in records.transactions) {
      if (transaction.type != TransactionType.expense ||
          transaction.isBillPayment ||
          transaction.isDebtMovement ||
          transaction.amount <= 0 ||
          !transaction.amount.isFinite ||
          transaction.date.isBefore(start) ||
          !transaction.date.isBefore(end)) {
        continue;
      }
      spendingDays.add(
        DateTime(
          transaction.date.year,
          transaction.date.month,
          transaction.date.day,
        ),
      );
    }
    final hasHistory = spendingDays.length >= 7;
    final s = records.safeToSpend;
    // Current balances already include today's spending. Unlike the daily
    // limit calculation, no amount is added back here.
    final available = math.max(
      0.0,
      records.walletBalance - math.max(0.0, s.billsDue) - s.goalSavings,
    );
    if (!hasHistory) {
      return SavingsSuggestion(
        available: available,
        dailyCosts: 0,
        amount: 0,
        hasHistory: false,
      );
    }
    final first = spendingDays.reduce((a, b) => a.isBefore(b) ? a : b);
    final average =
        discretionarySpending(records.transactions, from: first, until: end) /
        (records.today.difference(first).inDays + 1);
    // Overspending today must not consume the allowance for future days.
    final dailyCosts =
        average * math.max(0, s.daysLeft - 1) +
        math.max(0.0, average - s.spentToday);
    final remaining = math.max(0.0, available - dailyCosts);
    // Leave 90% of the remainder as a buffer. Round down to a centavo so
    // the suggestion can never exceed the calculated share.
    final amount = (remaining * 0.10 * 100).floor() / 100;
    return SavingsSuggestion(
      available: available,
      dailyCosts: dailyCosts,
      amount: amount,
      hasHistory: true,
    );
  }
}
