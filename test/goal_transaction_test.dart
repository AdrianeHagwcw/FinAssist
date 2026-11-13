import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/models/transaction_filter.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/transaction_row.dart';

const cash = Wallet(
  id: 'cash',
  name: 'Cash on Hand',
  type: WalletType.cash,
  balance: 5000,
  startingBalance: 5000,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

/// Money put into a goal: the wallet keeps every peso, only the claim is new.
AppTransaction deposit({double amount = 1500}) => AppTransaction(
  id: 'd1',
  type: TransactionType.goal,
  amount: amount,
  label: goalDepositLabel,
  date: DateTime(2026, 9, 28, 15, 4),
  walletId: 'cash',
  note: 'Vacation',
  goalId: 'g1',
);

/// Money let go of a goal, as when the goal is cancelled.
AppTransaction withdrawal({double amount = 1500}) => AppTransaction(
  id: 'w1',
  type: TransactionType.goal,
  amount: amount,
  label: goalWithdrawalLabel,
  date: DateTime(2026, 9, 28, 16, 4),
  walletId: 'cash',
  note: 'Vacation',
  goalId: 'g1',
);

Goal goal({
  GoalStatus status = GoalStatus.active,
  Map<String, double> savedByWallet = const {},
  String? walletId,
  double savedAmount = 0,
}) => Goal(
  id: 'g1',
  name: 'Vacation',
  targetAmount: 10000,
  savedAmount: savedAmount,
  priority: 0,
  status: status,
  walletId: walletId,
  savedByWallet: savedByWallet,
);

void main() {
  group('a goal transaction', () {
    test('reads as a deposit or a withdrawal', () {
      expect(deposit().title, 'Goal Deposit');
      expect(withdrawal().title, 'Goal Withdrawal');
      expect(deposit().isGoalMovement, isTrue);
      expect(withdrawal().isGoalMovement, isTrue);
    });

    test('changes no wallet balance, either way', () {
      expect(deposit().balanceDeltaFor('cash'), 0);
      expect(withdrawal().balanceDeltaFor('cash'), 0);
      // It still belongs to the wallet's history.
      expect(deposit().involvesWallet('cash'), isTrue);
      expect(withdrawal().involvesWallet('cash'), isTrue);
    });

    test('is internal, never income or spending', () {
      final rows = [deposit(), withdrawal()];
      expect(rows.every((row) => row.isInternalTransfer), isTrue);
      expect(inAndOut(rows), (moneyIn: 0.0, moneyOut: 0.0));
      expect(spendingByCategory(rows), isEmpty);
      expect(loanMovements(rows), (moneyIn: 0.0, moneyOut: 0.0));
    });

    test('can be found by its words or the goal it names', () {
      expect(
        const TransactionFilter(query: 'goal deposit').matches(deposit()),
        isTrue,
      );
      expect(
        const TransactionFilter(query: 'vacation').matches(deposit()),
        isTrue,
      );
      expect(
        const TransactionFilter(type: TransactionType.goal).matches(deposit()),
        isTrue,
      );
      expect(
        const TransactionFilter(type: TransactionType.transfer).matches(
          deposit(),
        ),
        isFalse,
      );
    });

    test('is read back from what was stored', () {
      final read = AppTransaction.fromMap('d1', {
        'type': 'goal',
        'amount': 1500,
        'label': goalDepositLabel,
        'date': DateTime(2026, 9, 28),
        'walletId': 'cash',
        'goalId': 'g1',
      });

      expect(read.type, TransactionType.goal);
      expect(read.isGoalMovement, isTrue);
      expect(read.goalId, 'g1');
      expect(read.title, 'Goal Deposit');
      expect(read.balanceDeltaFor('cash'), 0);
    });

    testWidgets('is shown by its own words, with no sign', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TransactionRow(
                transaction: deposit(),
                wallets: const [cash],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Goal Deposit'), findsOneWidget);
      // Not "Cash on Hand → Cash on Hand", and no + or -: nothing moved.
      expect(find.textContaining('→'), findsNothing);
      expect(find.text('₱1,500'), findsOneWidget);
      // The wallet and the goal it belongs to are still nameable.
      expect(find.textContaining('Cash on Hand'), findsOneWidget);
      expect(find.textContaining('Vacation'), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    });
  });

  group('what a goal holds, ready to be given back', () {
    test('is what each wallet was given', () {
      expect(
        goalHeldByWallet(
          goal(savedByWallet: {'cash': 1500, 'bank': 500}, savedAmount: 2000),
        ),
        {'cash': 1500, 'bank': 500},
      );
    });

    test('falls back to the one wallet of an older goal', () {
      expect(
        goalHeldByWallet(goal(walletId: 'cash', savedAmount: 700)),
        {'cash': 700},
      );
    });

    test('is nothing once the money was used', () {
      expect(
        goalHeldByWallet(
          goal(
            status: GoalStatus.used,
            savedByWallet: {'cash': 1500},
            savedAmount: 1500,
          ),
        ),
        isEmpty,
      );
    });

    test('leaves out a wallet with nothing left in the goal', () {
      expect(
        goalHeldByWallet(goal(savedByWallet: {'cash': 0, 'bank': 500})),
        {'bank': 500},
      );
    });
  });
}
