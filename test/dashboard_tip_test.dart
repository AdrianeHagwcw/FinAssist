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

DashboardTip? tipFor(List<AppTransaction> transactions) => dashboardTipFor(
  wallets: const [cash],
  transactions: transactions,
  bills: const [],
  now: now,
);

void main() {
  test('where the month went is left to Reports, not Home', () {
    // Logged today, nothing due: no nudge is needed, so no tip at all,
    // however the month's spending splits.
    expect(
      tipFor([
        spent(800, 'Food', now),
        spent(200, 'Transportation', DateTime(2026, 10, 3)),
      ]),
      isNull,
    );
    expect(
      tipFor([
        spent(250, 'Food', now),
        spent(1000, 'Food', DateTime(2026, 9, 10)),
      ]),
      isNull,
    );
  });

  test('a nudge still shows when something needs doing', () {
    // Nothing logged today.
    expect(
      tipFor([spent(300, 'Food', DateTime(2026, 10, 5))])?.title,
      'Nothing logged today',
    );
  });
}
