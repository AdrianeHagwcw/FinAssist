import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/models/transaction_filter.dart';
import 'package:testapp/backend/models/transfer_direction.dart';
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
      // It reads as a deposit, withdrawal or transfer, so the transfer
      // choices find it too.
      expect(
        const TransactionFilter(
          type: TransactionType.transfer,
        ).matches(deposit()),
        isTrue,
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

      // Read like a transfer, with the goal as the other account; cash on
      // hand into a goal is a deposit.
      expect(find.text('Cash on Hand → Vacation'), findsOneWidget);
      expect(find.textContaining('Deposit ·'), findsOneWidget);
      // No + or -: nothing moved.
      expect(find.text('₱1,500'), findsOneWidget);
      // The wallet and the goal it belongs to are still nameable.
      expect(find.textContaining('Cash on Hand'), findsOneWidget);
      expect(find.textContaining('Vacation'), findsOneWidget);
      // The Goals icon, the same as on Home.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/icons/icons8-goal-96.png',
        ),
        findsOneWidget,
      );
    });
  });

  group('a goal reads as an account', () {
    const maya = Wallet(
      id: 'maya',
      name: 'Maya',
      type: WalletType.gcash,
      balance: 5000,
      startingBalance: 5000,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
    );
    AppTransaction from(AppTransaction t, String walletId) => AppTransaction(
      id: t.id,
      type: t.type,
      amount: t.amount,
      label: t.label,
      date: t.date,
      walletId: walletId,
      note: t.note,
      goalId: t.goalId,
    );
    const wallets = [cash, maya];

    test(
      'cash on hand deposits and withdraws; a bank or e-wallet transfers',
      () {
        expect(
          movementDirection(deposit(), wallets),
          TransferDirection.deposit,
        );
        expect(
          movementDirection(withdrawal(), wallets),
          TransferDirection.withdrawal,
        );
        expect(
          movementDirection(from(deposit(), 'maya'), wallets),
          TransferDirection.transfer,
        );
        expect(
          movementDirection(from(withdrawal(), 'maya'), wallets),
          TransferDirection.transfer,
        );
      },
    );

    testWidgets('the row says which, to or from the goal', (tester) async {
      for (final (transaction, title, word) in [
        (deposit(), 'Cash on Hand → Vacation', 'Deposit'),
        (withdrawal(), 'Vacation → Cash on Hand', 'Withdrawal'),
        (from(deposit(), 'maya'), 'Maya → Vacation', 'Transfer'),
        (from(withdrawal(), 'maya'), 'Vacation → Maya', 'Transfer'),
      ]) {
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => AppSettingsProvider(),
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: TransactionRow(
                  transaction: transaction,
                  wallets: wallets,
                ),
              ),
            ),
          ),
        );
        expect(find.text(title), findsOneWidget);
        expect(find.textContaining('$word ·'), findsOneWidget);
      }
    });

    test('the Deposit and Transfer filters find goal rows too', () {
      final depositOnly = const TransactionFilter(
        type: TransactionType.transfer,
        direction: TransferDirection.deposit,
      );
      expect(depositOnly.matches(deposit(), wallets: wallets), isTrue);
      expect(
        depositOnly.matches(from(deposit(), 'maya'), wallets: wallets),
        isFalse,
      );
      const transfers = TransactionFilter(type: TransactionType.transfer);
      expect(
        transfers.matches(from(withdrawal(), 'maya'), wallets: wallets),
        isTrue,
      );
      expect(
        const TransactionFilter(
          query: 'withdrawal',
        ).matches(withdrawal(), wallets: wallets),
        isTrue,
      );
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
      expect(goalHeldByWallet(goal(walletId: 'cash', savedAmount: 700)), {
        'cash': 700,
      });
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
      expect(goalHeldByWallet(goal(savedByWallet: {'cash': 0, 'bank': 500})), {
        'bank': 500,
      });
    });
  });
}
