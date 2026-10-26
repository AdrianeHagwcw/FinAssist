import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:testapp/models/bill.dart';
import 'package:testapp/models/chat_answers.dart';
import 'package:testapp/models/goal.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/bill_calendar_screen.dart';
import 'package:testapp/screens/chatbot_screen.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/widgets/wallet_split_picker.dart';

/// Money only lives where it really is: Cash on Hand or Cash in Bank. Every
/// place money comes out of or goes into wallets asks the same way, and
/// never lets a wallet give more than it has free.
void main() {
  Wallet spending(String id, WalletType type, double balance) => Wallet(
    id: id,
    name: id,
    type: type,
    balance: balance,
    startingBalance: balance,
    receivesIncome: false,
    archived: false,
    sortOrder: 0,
  );

  final cash = spending('Cash', WalletType.cash, 5000);
  final gcash = spending('GCash', WalletType.gcash, 2000);
  final savings = Wallet(
    id: 'Savings',
    name: 'Savings',
    type: WalletType.bank,
    balance: 9000,
    startingBalance: 9000,
    receivesIncome: false,
    archived: false,
    sortOrder: 2,
    purpose: WalletPurpose.savings,
  );
  final wallets = [cash, gcash, savings];

  // ₱3,000 of the cash is for a goal.
  const trip = Goal(
    id: 'trip',
    name: 'Trip',
    targetAmount: 10000,
    savedAmount: 3000,
    priority: 0,
    status: GoalStatus.active,
    savedByWallet: {'Cash': 3000},
  );

  group('paying', () {
    String? problem(
      Map<String, double> amounts, {
      Map<String, double> fees = const {},
      double target = 0,
      bool matchTarget = false,
      Map<String, double> adding = const {},
    }) => walletSplitProblem(
      purpose: SplitPurpose.paying,
      amounts: amounts,
      fees: fees,
      wallets: wallets,
      goals: const [trip],
      target: target,
      matchTarget: matchTarget,
      adding: adding,
    );

    test('a wallet pays only what it has free, goal money left alone', () {
      expect(problem({'Cash': 2000}), isNull);
      expect(
        problem({'Cash': 2500}),
        'Only ₱2,000 in Cash is free; goals hold the rest.',
      );
    });

    test('its fee comes out of the same wallet', () {
      expect(problem({'GCash': 1985}, fees: {'GCash': 15}), isNull);
      expect(
        problem({'GCash': 1990}, fees: {'GCash': 15}),
        'Only ₱2,000 in GCash is free. With the ₱15 fee, this needs '
        '₱2,005.',
      );
    });

    test('money coming in at the same time can pay', () {
      expect(problem({'GCash': 2500}), isNotNull);
      expect(problem({'GCash': 2500}, adding: {'GCash': 1000}), isNull);
    });

    test('part of a bill, or exactly an expense', () {
      // A bill can be paid in part, never past what is owed.
      expect(problem({'Cash': 1000}, target: 1500), isNull);
      expect(
        problem({'Cash': 1000, 'GCash': 1000}, target: 1500),
        'That is ₱500 more than ₱1,500.',
      );
      // An expense is all of it, split however the user paid.
      expect(
        problem({'Cash': 1000}, target: 1500, matchTarget: true),
        'Add ₱500 more to make ₱1,500.',
      );
      expect(
        problem({'Cash': 1000, 'GCash': 500}, target: 1500, matchTarget: true),
        isNull,
      );
      expect(
        problem({}, target: 1500, matchTarget: true),
        'Choose Cash on Hand, Cash in Bank or Both, then enter how much.',
      );
    });
  });

  test('money coming in has no limit per wallet, only its total', () {
    String? receiving(Map<String, double> amounts) => walletSplitProblem(
      purpose: SplitPurpose.receiving,
      amounts: amounts,
      wallets: wallets,
      goals: const [trip],
      target: 20000,
      matchTarget: true,
    );

    expect(receiving({'Cash': 15000, 'GCash': 5000}), isNull);
    expect(receiving({'Cash': 15000}), 'Add ₱5,000 more to make ₱20,000.');
  });

  test('a limit, such as what a goal holds, replaces what is free', () {
    String? takingOut(Map<String, double> amounts) => walletSplitProblem(
      purpose: SplitPurpose.giving,
      amounts: amounts,
      wallets: wallets,
      goals: const [trip],
      limits: const {'Cash': 3000},
      tooMuchMessage: (wallet, room) =>
          'Only ₱${room.toStringAsFixed(0)} of the goal is in ${wallet.name}.',
    );

    expect(takingOut({'Cash': 3000}), isNull);
    expect(takingOut({'Cash': 3500}), 'Only ₱3000 of the goal is in Cash.');
  });

  test('the Available Balance leaves out savings and goal money', () {
    // ₱5,000 + ₱2,000 in spending wallets, ₱3,000 of it for the trip.
    expect(availableBalance(wallets, const [trip]), 4000);
    // Money left in a Bills wallet from before is spending money now.
    final oldBills = Wallet(
      id: 'bills',
      name: 'Bills',
      type: WalletType.other,
      balance: 1000,
      startingBalance: 1000,
      receivesIncome: false,
      archived: false,
      sortOrder: 3,
      purpose: WalletPurpose.bills,
    );
    expect(availableBalance([...wallets, oldBills], const [trip]), 5000);
  });

  test("Fin's expense list is paid from the wallets in turn", () {
    final entries = splitExpenseBatch(
      const [
        CategorizedChatExpense(
          amount: 150,
          description: 'Lunch',
          category: 'Food',
        ),
        CategorizedChatExpense(
          amount: 100.50,
          description: 'Jeep',
          category: 'Transportation',
        ),
      ],
      {'Cash': 200, 'GCash': 50.50},
    );

    // Lunch from the cash; the jeep partly from the cash, the rest GCash.
    expect(
      [for (final e in entries) (e.note, e.walletId, e.amount)],
      [('Lunch', 'Cash', 150), ('Jeep', 'Cash', 50), ('Jeep', 'GCash', 50.5)],
    );
  });

  group('Bill Planner', () {
    final today = DateTime(2026, 3, 10);
    final rent = BillInstance(
      id: 'rent',
      billId: 'b',
      name: 'Rent',
      amount: 6000,
      category: 'Bills',
      dueDate: DateTime(2026, 3, 20),
      status: BillStatus.unpaid,
    );

    Future<void> pumpPlanner(WidgetTester tester, List<Wallet> wallets) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: BillCalendarScreen(
              today: today,
              bills: Stream.value(const []),
              instancesFor: (year, month) =>
                  Stream.value(year == 2026 && month == 3 ? [rent] : const []),
              ensureInstances: (bills, year, month) async {},
              wallets: Stream.value(wallets),
              goals: Stream.value(const [trip]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('says the month is short when the money free is less', (
      tester,
    ) async {
      // ₱4,000 free against ₱6,000 of rent.
      await pumpPlanner(tester, wallets);

      expect(find.text('Short by ₱2,000 · ₱4,000 available'), findsOneWidget);
    });

    testWidgets('says covered when there is enough', (tester) async {
      await pumpPlanner(tester, [
        ...wallets,
        spending('BPI', WalletType.bank, 5000),
      ]);

      expect(find.text('Covered · ₱9,000 available'), findsOneWidget);
    });
  });
}
