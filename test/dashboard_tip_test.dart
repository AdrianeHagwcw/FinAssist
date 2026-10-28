import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/dashboard_tip.dart';
import 'package:testapp/backend/models/wallet.dart';

const cash = Wallet(
  id: 'cash',
  name: 'Cash',
  type: WalletType.cash,
  balance: 5000,
  startingBalance: 5000,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

/// Oct 20, 2026, with something already logged today.
final now = DateTime(2026, 10, 20, 18);

AppTransaction spent(double amount, String category, DateTime date) =>
    AppTransaction(
      id: '$category-$date-$amount',
      type: TransactionType.expense,
      amount: amount,
      label: category,
      date: date,
      walletId: 'cash',
    );

DashboardTip tipFor(List<AppTransaction> transactions) => dashboardTipFor(
  wallets: const [cash],
  transactions: transactions,
  bills: const [],
  now: now,
);

void main() {
  test('says where most of the month went', () {
    final tip = tipFor([
      spent(800, 'Food', now),
      spent(200, 'Transportation', DateTime(2026, 10, 3)),
    ]);
    expect(tip.title, 'Where most of it goes');
    expect(tip.message, 'Food is 80% of your spending this month.');
  });

  test('compares with the same days of last month', () {
    // ₱600 this month, none of it mostly one thing.
    final tip = tipFor([
      spent(250, 'Food', now),
      spent(200, 'Transportation', DateTime(2026, 10, 5)),
      spent(150, 'Bills', DateTime(2026, 10, 6)),
      // By Sep 20: ₱1,000. Later in September does not count.
      spent(1000, 'Food', DateTime(2026, 9, 10)),
      spent(5000, 'Food', DateTime(2026, 9, 28)),
    ]);
    expect(tip.title, 'Compared with last month');
    expect(tip.message, "You've spent ₱400 less than by this day last month.");
  });

  test('with nothing to compare, names the biggest spending', () {
    final tip = tipFor([
      spent(300, 'Food', now),
      spent(300, 'Transportation', DateTime(2026, 10, 5)),
      spent(250, 'Bills', DateTime(2026, 10, 6)),
    ]);
    expect(tip.message, 'Food is your biggest spending this month, at ₱300.');
  });
}
