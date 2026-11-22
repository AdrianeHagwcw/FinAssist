import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/safe_to_spend.dart';

/// Safe to Spend with nothing owed and nothing spent yet: [balance] shared
/// over [daysLeft] days.
SafeToSpend figure({
  double balance = 10000,
  double billsDue = 0,
  double goalSavings = 0,
  double spentToday = 0,
  int daysLeft = 10,
}) => SafeToSpend(
  walletBalance: balance,
  billsDue: billsDue,
  goalSavings: goalSavings,
  spentToday: spentToday,
  daysLeft: daysLeft,
);

void main() {
  test('nothing is said while the expense fits today', () {
    // ₱10,000 over 10 days is ₱1,000 a day; ₱500 fits.
    expect(
      expenseHeadsUp(figure(), fromSpendingWallets: 500, addedToToday: 500),
      isNull,
    );
  });

  test('going over today says by how much, and that tomorrow drops', () {
    // ₱1,500 against ₱1,000 for today. Tomorrow shares the ₱8,500 left over
    // 9 days: ₱944.44, below today's ₱1,000.
    final headsUp = expenseHeadsUp(
      figure(),
      fromSpendingWallets: 1500,
      addedToToday: 1500,
    );
    expect(
      headsUp?.text,
      "This puts you ₱500 over today's safe amount. "
      "Tomorrow's will be lower.",
    );
    expect(headsUp?.usesBillMoney, isFalse);
  });

  test('money needed for bills is named first, with only that part', () {
    // ₱10,000 less ₱8,000 of bills and ₱1,000 for goals leaves ₱1,000 free;
    // ₱1,500 takes ₱500 of the bill money.
    final headsUp = expenseHeadsUp(
      figure(billsDue: 8000, goalSavings: 1000),
      fromSpendingWallets: 1500,
      addedToToday: 1500,
    );
    expect(headsUp?.text, 'This uses ₱500 you need for bills this month.');
    expect(headsUp?.usesBillMoney, isTrue);
  });

  test('once bills are already short, all of it is bill money', () {
    final headsUp = expenseHeadsUp(
      figure(balance: 5000, billsDue: 8000),
      fromSpendingWallets: 200,
      addedToToday: 200,
    );
    expect(headsUp?.text, 'This uses ₱200 you need for bills this month.');
  });

  test('an earlier date still lowers what today can take', () {
    // Today: (₱10,000 + ₱900 spent) / 10 = ₱1,090, ₱190 left. ₱3,000 dated
    // yesterday leaves ₱7,900 / 10 = ₱790 for today, ₱110 under what is
    // already spent.
    final headsUp = expenseHeadsUp(
      figure(spentToday: 900),
      fromSpendingWallets: 3000,
      addedToToday: 0,
    );
    expect(
      headsUp?.text,
      "This puts you ₱110 over today's safe amount. "
      "Tomorrow's will be lower.",
    );
  });

  test('a day already over is warned again as it grows', () {
    final headsUp = expenseHeadsUp(
      figure(spentToday: 1200),
      fromSpendingWallets: 100,
      addedToToday: 100,
    );
    // (₱9,900 + ₱1,300) / 10 = ₱1,120 for today, against ₱1,300 spent.
    expect(headsUp?.text, startsWith("This puts you ₱180 over today's"));
  });

  test('the last day of the month says nothing of tomorrow', () {
    // One day left and nothing to spare after bills: the bill warning is
    // the one that applies, never a promise about a new month.
    final headsUp = expenseHeadsUp(
      figure(balance: 3000, billsDue: 2500, daysLeft: 1),
      fromSpendingWallets: 1000,
      addedToToday: 1000,
    );
    expect(headsUp?.text, 'This uses ₱500 you need for bills this month.');
    expect(headsUp?.text, isNot(contains('Tomorrow')));
  });
}
