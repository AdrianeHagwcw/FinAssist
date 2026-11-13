import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/transaction_filter.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/backend/utils/categories.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/category_icon.dart';
import 'package:testapp/frontend/widgets/transaction_row.dart';

const cash = Wallet(
  id: 'cash',
  name: 'Cash',
  type: WalletType.cash,
  balance: 20000,
  startingBalance: 20000,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

/// One payment of an installment, recorded the way paying the bill records
/// it: an expense out of Cash against the plan's occurrence. [loan] marks a
/// payment of borrowed money instead.
AppTransaction payment({
  bool installment = true,
  bool loan = false,
  double interest = 0,
}) => AppTransaction(
  id: 'p1',
  type: TransactionType.expense,
  amount: 4000,
  label: 'Bills',
  date: DateTime(2026, 6, 10, 9, 30),
  walletId: 'cash',
  note: 'iPhone 15',
  billInstanceId: 'i2026-6',
  interest: interest,
  installmentPayment: installment,
  loanPayment: loan,
);

void main() {
  group('a payment recorded within an installment', () {
    test('reads as one in Transactions', () {
      expect(payment().title, 'Installment Payment');
      expect(payment().isInstallmentPayment, true);
    });

    test('still comes off the wallet it was paid from', () {
      final paid = payment();
      expect(paid.type, TransactionType.expense);
      expect(paid.balanceDeltaFor('cash'), -4000);
      expect(paid.walletId, 'cash');
    });

    test('is still counted as the bill it was, in Reports', () {
      // The category it is grouped under does not change: what Reports
      // shows is where the money went, and it went to a bill.
      final parts = payment(interest: 400).spendingParts;
      expect(parts, hasLength(2));
      expect(parts.first.key, 'Bills');
      expect(parts.first.value, 3600.0);
      expect(parts.last.key, interestCategory);
      expect(parts.last.value, 400.0);

      expect(
        const TransactionFilter(category: 'Bills').matches(payment()),
        isTrue,
      );
      expect(
        const TransactionFilter(
          category: 'Installment Payment',
        ).matches(payment()),
        isFalse,
      );
    });

    test('can be found by searching what it reads as', () {
      const filter = TransactionFilter(query: 'installment');
      expect(filter.matches(payment()), isTrue);
      expect(filter.matches(payment(installment: false)), isFalse);
    });

    testWidgets('is shown that way, with a minus, on its row', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TransactionRow(
                transaction: payment(),
                wallets: const [cash],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Installment Payment'), findsOneWidget);
      // Still money out, so the minus stands and the wallet shows.
      expect(find.text('-₱4,000'), findsOneWidget);
      expect(find.textContaining('Outflow'), findsOneWidget);
      expect(find.textContaining('Cash'), findsOneWidget);
      // The bill icon goes with it, since that is still what it was paid
      // against.
      expect(
        tester.widget<CategoryIcon>(find.byType(CategoryIcon)).category,
        'Bills',
      );
    });

    testWidgets('leaves an ordinary bill payment reading as it did', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TransactionRow(
                transaction: payment(installment: false),
                wallets: const [cash],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bills'), findsOneWidget);
      expect(find.text('Installment Payment'), findsNothing);
    });
  });

  group('a payment recorded against borrowed money', () {
    test('reads as a debt payment, not an installment one', () {
      final paid = payment(loan: true);
      expect(paid.title, 'Debt Payment');
      expect(paid.title, isNot('Installment Payment'));
      // It is still a payment of a plan, so Reports keep counting it as the
      // bill it was paid against.
      expect(paid.isInstallmentPayment, isTrue);
    });

    test('keeps an installment reading as an installment', () {
      expect(payment().title, 'Installment Payment');
      expect(payment().loanPayment, isFalse);
    });

    test('leaves a plain bill payment reading as its category', () {
      final plain = payment(installment: false);
      expect(plain.title, 'Bills');
      expect(plain.loanPayment, isFalse);
    });

    test('is read back from what was stored', () {
      final read = AppTransaction.fromMap('p1', {
        'type': 'expense',
        'amount': 4000,
        'label': 'Bills',
        'date': DateTime(2026, 6, 10),
        'walletId': 'cash',
        'installmentPayment': true,
        'loanPayment': true,
      });
      expect(read.loanPayment, isTrue);
      expect(read.title, 'Debt Payment');
    });

    test('is still counted under the bill in Reports', () {
      expect(
        const TransactionFilter(category: 'Bills').matches(payment(loan: true)),
        isTrue,
      );
      expect(
        const TransactionFilter(
          category: 'Debt Payment',
        ).matches(payment(loan: true)),
        isFalse,
      );
    });

    test('can be found by searching what it reads as', () {
      expect(
        const TransactionFilter(query: 'debt').matches(payment(loan: true)),
        isTrue,
      );
      expect(
        const TransactionFilter(query: 'debt').matches(payment()),
        isFalse,
      );
      expect(
        const TransactionFilter(query: 'installment').matches(payment()),
        isTrue,
      );
      expect(
        const TransactionFilter(
          query: 'installment',
        ).matches(payment(loan: true)),
        isFalse,
      );
    });

    testWidgets('is shown that way on its row', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TransactionRow(
                transaction: payment(loan: true),
                wallets: const [cash],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Debt Payment'), findsOneWidget);
      expect(find.text('Installment Payment'), findsNothing);
      expect(find.text('-₱4,000'), findsOneWidget);
      expect(find.textContaining('Outflow'), findsOneWidget);
      expect(
        tester.widget<CategoryIcon>(find.byType(CategoryIcon)).category,
        'Bills',
      );
    });
  });
}
