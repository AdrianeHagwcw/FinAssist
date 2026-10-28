import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/allocation.dart';
import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/cycle_history.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/history_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';

AllocationCycle planned(
  String id,
  DateTime at, {
  double amount = 1000,
  double toGoal = 0,
  LeftoverDecision? decision,
  double saved = 0,
}) => AllocationCycle(
  id: id,
  income: amount,
  toGoal: toGoal,
  remaining: amount - toGoal,
  receivedAt: at,
  source: id,
  decision: decision,
  savedAmount: saved,
);

AppTransaction record(
  String id,
  TransactionType type,
  double amount,
  DateTime at, {
  String label = 'Food',
  String? debtId,
}) => AppTransaction(
  id: id,
  type: type,
  amount: amount,
  label: label,
  date: at,
  walletId: 'cash',
  debtId: debtId,
);

void main() {
  group('a month of actual records', () {
    test('money in, money out, and what is left', () {
      final months = monthFlows(
        [planned('Salary', DateTime(2026, 10, 27))],
        [
          record(
            'salary',
            TransactionType.income,
            1000,
            DateTime(2026, 10, 27),
            label: 'Salary',
          ),
          record(
            'sold',
            TransactionType.income,
            500,
            DateTime(2026, 10, 28),
            label: 'Sold Something',
          ),
          record('food', TransactionType.expense, 120, DateTime(2026, 10, 28)),
          record('jeep', TransactionType.expense, 30, DateTime(2026, 10, 27)),
        ],
      );

      final october = months.single;
      expect(october.totalIn, 1500);
      expect(october.totalOut, 150);
      expect(october.left, 1350);
      expect(october.moneyIn.map((t) => t.id), ['sold', 'salary']);
    });

    test('transfers and borrowed or lent money are neither', () {
      final october = monthFlows(const [], [
        record('in', TransactionType.income, 1000, DateTime(2026, 10, 1)),
        record('move', TransactionType.transfer, 400, DateTime(2026, 10, 2)),
        record(
          'lent',
          TransactionType.expense,
          300,
          DateTime(2026, 10, 3),
          debtId: 'ana',
        ),
      ]).single;
      expect(october.totalIn, 1000);
      expect(october.totalOut, 0);
    });

    test('months follow Philippine time', () {
      // 4:30 PM on Oct 31 in London is 12:30 AM on Nov 1 in Manila.
      final months = monthFlows(const [], [
        record(
          'late',
          TransactionType.income,
          100,
          DateTime.utc(2026, 10, 31, 16, 30),
        ),
      ]);
      expect(months.single.month, DateTime(2026, 11));
    });

    test('goal money already saved is not offered again at month end', () {
      final october = monthFlows(
        [planned('Salary', DateTime(2026, 10, 1), toGoal: 300)],
        [record('in', TransactionType.income, 1000, DateTime(2026, 10, 1))],
      ).single;
      expect(october.left, 1000);
      expect(october.leftToDecide, 700);
    });

    test('the decision waits for the month to end', () {
      final october = monthFlows(
        [planned('Salary', DateTime(2026, 10, 1))],
        [record('in', TransactionType.income, 1000, DateTime(2026, 10, 1))],
      ).single;
      expect(october.awaitingDecision(DateTime(2026, 10, 20)), isFalse);
      expect(october.awaitingDecision(DateTime(2026, 10, 31)), isTrue);
    });
  });

  group('the Cash Inflows screen', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<AllocationCycle> cycles,
      required List<AppTransaction> transactions,
      DateTime? today,
      void Function(AllocationCycle, double, DateTime)? onReview,
    }) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: HistoryScreen(
              today: today ?? DateTime(2026, 10, 28),
              cycles: Stream.value(cycles),
              transactions: Stream.value(transactions),
              onReview: onReview,
              wallets: Stream.value(const [
                Wallet(
                  id: 'cash',
                  name: 'Cash',
                  type: WalletType.cash,
                  balance: 0,
                  startingBalance: 0,
                  receivesIncome: false,
                  archived: false,
                  sortOrder: 0,
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final october = [
      record(
        'salary',
        TransactionType.income,
        1000,
        DateTime(2026, 10, 27),
        label: 'Salary',
      ),
      record(
        'interest',
        TransactionType.income,
        12,
        DateTime(2026, 10, 15),
        label: 'Interest',
      ),
      record('food', TransactionType.expense, 120, DateTime(2026, 10, 28)),
    ];

    testWidgets('shows the totals, then every income and every expense', (
      tester,
    ) async {
      await pump(
        tester,
        cycles: [planned('Salary', DateTime(2026, 10, 27))],
        transactions: october,
      );

      expect(find.text('Oct 2026'), findsOneWidget);
      expect(find.text('+₱1,012'), findsOneWidget);
      expect(find.text('-₱120'), findsNWidgets(2));
      expect(find.text('₱892'), findsOneWidget);
      expect(find.text('Money in (2)'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Interest'), findsOneWidget);
      expect(find.text('Money out (1)'), findsOneWidget);
      // Actual records only: no status for a month still under way.
      expect(find.text('In progress'), findsNothing);
      expect(find.textContaining('Decide what to do'), findsNothing);
    });

    testWidgets('at month end, one decision for the month', (tester) async {
      AllocationCycle? decidedOn;
      double? left;
      await pump(
        tester,
        cycles: [planned('Salary', DateTime(2026, 10, 27))],
        transactions: october,
        today: DateTime(2026, 10, 31),
        onReview: (cycle, amount, _) {
          decidedOn = cycle;
          left = amount;
        },
      );

      await tester.tap(find.byKey(const Key('decide-2026-10')));
      expect(decidedOn?.id, 'Salary');
      expect(left, 892);
    });

    testWidgets('a decided month says what was done', (tester) async {
      await pump(
        tester,
        cycles: [
          planned(
            'Salary',
            DateTime(2026, 9, 2),
            decision: LeftoverDecision.saved,
            saved: 500,
          ),
        ],
        transactions: [
          record(
            'in',
            TransactionType.income,
            1000,
            DateTime(2026, 9, 2),
            label: 'Salary',
          ),
        ],
      );

      expect(find.text('You saved ₱500 of what was left.'), findsOneWidget);
    });

    testWidgets('a long month shows its first expenses, then all', (
      tester,
    ) async {
      await pump(
        tester,
        cycles: const [],
        transactions: [
          record('in', TransactionType.income, 5000, DateTime(2026, 10, 1)),
          for (var day = 2; day <= 9; day++)
            record(
              'out$day',
              TransactionType.expense,
              10,
              DateTime(2026, 10, day),
            ),
        ],
      );

      expect(find.text('Money out (8)'), findsOneWidget);
      expect(find.text('-₱10'), findsNWidgets(5));
      await tester.tap(find.byKey(const Key('show-all-2026-10')));
      await tester.pumpAndSettle();
      expect(find.text('-₱10'), findsNWidgets(8));
    });
  });
}
