import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/allocation.dart';
import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/history_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';

AllocationCycle income(
  String id,
  DateTime at, {
  double amount = 10000,
  double toBills = 0,
  List<String> paid = const [],
}) => AllocationCycle(
  id: id,
  income: amount,
  toBills: toBills,
  remaining: amount - toBills,
  receivedAt: at,
  source: id,
  incomeTransactionIds: ['$id-in'],
  planPaymentIds: paid,
);

AppTransaction out(
  double amount,
  DateTime at, {
  String id = '',
  String? billInstanceId,
  String? debtId,
  TransactionType type = TransactionType.expense,
}) => AppTransaction(
  id: id.isEmpty ? 'out-$amount-$at' : id,
  type: type,
  amount: amount,
  label: 'Food',
  date: at,
  walletId: 'cash',
  billInstanceId: billInstanceId,
  debtId: debtId,
);

void main() {
  group('what was spent out of each income', () {
    test('the earliest money is used first, and nothing is counted twice', () {
      // A ₱10,000 salary on the 1st, a ₱500 refund on the 3rd; ₱2,000
      // spent on the 10th comes out of the salary, not the refund.
      final spent = spendingByCycle(
        [
          income('salary', DateTime(2026, 10, 1, 9)),
          income('refund', DateTime(2026, 10, 3, 9), amount: 500),
        ],
        [out(2000, DateTime(2026, 10, 10))],
      );
      expect(spent, {'salary': 2000, 'refund': 0});
    });

    test('once one income is used up, the next one pays', () {
      final spent = spendingByCycle(
        [
          income('allowance', DateTime(2026, 10, 1), amount: 1000),
          income('salary', DateTime(2026, 10, 5)),
        ],
        [out(1500, DateTime(2026, 10, 6))],
      );
      expect(spent, {'allowance': 1000, 'salary': 500});
    });

    test('only money that had already come in pays', () {
      final spent = spendingByCycle(
        [
          income('allowance', DateTime(2026, 10, 1), amount: 1000),
          income('salary', DateTime(2026, 10, 15)),
        ],
        [
          // Before the salary arrived: the allowance, then more than it had.
          out(1500, DateTime(2026, 10, 5)),
          // Before any income this month: paid from older money.
          out(300, DateTime(2026, 9, 30)),
        ],
      );
      expect(spent, {'allowance': 1500, 'salary': 0});
    });

    test('spending earlier on the day it came in does not count', () {
      final spent = spendingByCycle(
        [income('salary', DateTime(2026, 10, 27, 16, 46))],
        [
          out(30, DateTime(2026, 10, 27, 11)),
          out(120, DateTime(2026, 10, 27, 16, 58)),
        ],
      );
      expect(spent, {'salary': 120});
    });

    test('bills paid when it was logged are not counted again; later ones '
        'are', () {
      final spent = spendingByCycle(
        [
          income(
            'salary',
            DateTime(2026, 10, 1),
            toBills: 2000,
            paid: ['plan-bill'],
          ),
        ],
        [
          out(
            2000,
            DateTime(2026, 10, 1),
            id: 'plan-bill',
            billInstanceId: 'b',
          ),
          out(1500, DateTime(2026, 10, 12), billInstanceId: 'c'),
        ],
      );
      expect(spent, {'salary': 1500});
    });

    test('transfers and borrowed or lent money are not spending', () {
      final spent = spendingByCycle(
        [income('salary', DateTime(2026, 10, 1))],
        [
          out(500, DateTime(2026, 10, 2), type: TransactionType.transfer),
          out(700, DateTime(2026, 10, 3), debtId: 'ana'),
        ],
      );
      expect(spent, {'salary': 0});
    });

    test('a new month starts fresh', () {
      final spent = spendingByCycle(
        [
          income('september', DateTime(2026, 9, 1)),
          income('october', DateTime(2026, 10, 1)),
        ],
        [out(400, DateTime(2026, 10, 2))],
      );
      expect(spent, {'september': 0, 'october': 400});
    });
  });

  group('the Cash Inflows screen', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<AllocationCycle> cycles,
      required List<AppTransaction> transactions,
    }) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: HistoryScreen(
              today: DateTime(2026, 10, 28),
              cycles: Stream.value(cycles),
              transactions: Stream.value(transactions),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists interest too, so the month adds up to Inflow', (
      tester,
    ) async {
      await pump(
        tester,
        cycles: [income('Salary', DateTime(2026, 10, 27), amount: 1000)],
        transactions: [
          AppTransaction(
            id: 'Salary-in',
            type: TransactionType.income,
            amount: 1000,
            label: 'Salary',
            date: DateTime(2026, 10, 27),
            walletId: 'cash',
          ),
          AppTransaction(
            id: 'interest',
            type: TransactionType.income,
            amount: 12,
            label: 'Interest',
            date: DateTime(2026, 10, 15),
            walletId: 'bank',
            note: 'Interest from BDO',
          ),
          out(150, DateTime(2026, 10, 27, 12)),
        ],
      );

      expect(find.text('Oct 2026'), findsOneWidget);
      expect(find.text('2 inflows'), findsOneWidget);
      expect(find.text('+₱1,012'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('+₱1,000'), findsOneWidget);
      expect(find.text('Interest'), findsOneWidget);
      expect(find.text('+₱12'), findsOneWidget);
      // ₱150 spent out of the salary, ₱850 left of it.
      expect(find.text('₱150'), findsOneWidget);
      expect(find.text('₱850'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
    });

    testWidgets('says when more went out than an income had', (tester) async {
      await pump(
        tester,
        cycles: [income('Allowance', DateTime(2026, 10, 1), amount: 1000)],
        transactions: [out(1300, DateTime(2026, 10, 2))],
      );

      expect(
        find.text('₱300 more went out than this income had'),
        findsOneWidget,
      );
    });
  });
}
