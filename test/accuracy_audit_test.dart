import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:testapp/models/chat_answers.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/goal.dart';
import 'package:testapp/models/onboarding_data.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/home_screen.dart';
import 'package:testapp/screens/wallets_screen.dart';
import 'package:testapp/services/user_profile_service.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/widgets/transfer_sheet.dart';

/// One household's money, read on every screen that shows it: each must say
/// the same thing. The figures are the ones from the emulator: ₱19,000 in
/// six wallets, ₱12,000 of it set aside for goals, and a ₱10,000 time
/// deposit kept apart.
void main() {
  Wallet spending(String id, String name, WalletType type, double balance) =>
      Wallet(
        id: id,
        name: name,
        type: type,
        balance: balance,
        startingBalance: balance,
        receivesIncome: id == 'cash',
        archived: false,
        sortOrder: 0,
      );

  final wallets = [
    spending('cash', 'Cash', WalletType.cash, 10000),
    spending('petty', 'Petty Cash', WalletType.cash, 5000),
    spending('gcash', 'GCash', WalletType.gcash, 1000),
    spending('gotyme', 'GoTyme Bank', WalletType.bank, 1000),
    spending('metro', 'Metrobank', WalletType.bank, 1000),
    spending('maya', 'Maya', WalletType.maya, 1000),
    Wallet(
      id: 'td',
      name: 'Time Deposit',
      type: WalletType.other,
      balance: 10000,
      startingBalance: 10000,
      receivesIncome: false,
      archived: false,
      sortOrder: 7,
      purpose: WalletPurpose.savings,
      savingsKind: SavingsKind.timeDeposit.name,
      maturityDate: DateTime(2027, 4, 25),
    ),
  ];

  // ₱10,000 for Graduation across five wallets, ₱2,000 for Travel in Petty
  // Cash: ₱12,000 of the ₱19,000 is promised.
  const goals = [
    Goal(
      id: 'grad',
      name: 'Graduation',
      targetAmount: 10000,
      savedAmount: 10000,
      priority: 0,
      status: GoalStatus.active,
      savedByWallet: {
        'cash': 8000,
        'gcash': 500,
        'gotyme': 500,
        'metro': 500,
        'maya': 500,
      },
    ),
    Goal(
      id: 'travel',
      name: 'Travel',
      targetAmount: 20000,
      savedAmount: 2000,
      priority: 1,
      status: GoalStatus.active,
      savedByWallet: {'petty': 2000},
    ),
  ];

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(theme: AppTheme.light, home: home),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  test('setup saves each goal amount on its own wallet, once', () {
    OnboardingGoal goal({
      Map<String, double> byDraft = const {},
      double allocated = 0,
    }) => OnboardingGoal(
      name: 'Graduation',
      kind: GoalKind.regular,
      targetAmount: 10000,
      targetDate: null,
      frequency: ContributionFrequency.monthly,
      planAmount: null,
      note: null,
      allocated: allocated,
      fundingByWalletDraftId: byDraft,
    );
    const saved = {'draft-cash': 'cash', 'draft-gcash': 'gcash'};

    // Each draft wallet's amount goes on the wallet it became.
    expect(
      setupGoalMoneyByWallet(
        goal(byDraft: {'draft-cash': 8000, 'draft-gcash': 500}),
        walletIdsByDraftId: saved,
        fundingWalletId: 'cash',
      ),
      {'cash': 8000, 'gcash': 500},
    );
    // A draft that was not saved adds nothing, rather than the whole goal
    // landing on another wallet.
    expect(
      setupGoalMoneyByWallet(
        goal(byDraft: {'draft-cash': 8000, 'gone': 500}),
        walletIdsByDraftId: saved,
        fundingWalletId: 'cash',
      ),
      {'cash': 8000},
    );
    // A goal from before per-wallet amounts keeps its money in one place,
    // never ₱0.
    expect(
      setupGoalMoneyByWallet(
        goal(allocated: 3000),
        walletIdsByDraftId: saved,
        fundingWalletId: 'savings',
      ),
      {'savings': 3000},
    );
  });

  test('the sums agree before any screen shows them', () {
    final cash = wallets.where((w) => w.type == WalletType.cash);
    final bank = wallets.where(
      (w) => w.type != WalletType.cash && !w.isSetAside,
    );
    double free(Iterable<Wallet> group) =>
        group.fold(0, (sum, w) => sum + freeInWallet(w, goals));

    expect(
      totalWalletBalance(wallets),
      19000,
      reason: 'the time deposit is apart',
    );
    expect(free(cash), 5000);
    expect(free(bank), 2000);
    expect(free(cash) + free(bank), 7000);
    expect(totalSetAsideInSpendingWallets(goals, wallets), 12000);

    // Safe to Spend takes the same ₱12,000 off before sharing out the days.
    final snapshot = FinanceSnapshot(
      now: DateTime(2026, 10, 25),
      wallets: wallets,
      goals: goals,
    );
    expect(snapshot.walletBalance, 19000);
    expect(snapshot.goalSavingsInSpendingWallets, 12000);
    expect(snapshot.safeToSpend.spendableThisPeriod, 7000);
  });

  testWidgets('Home says ₱7,000, split ₱5,000 and ₱2,000', (tester) async {
    await pump(
      tester,
      HomeScreen(
        userName: 'Dave',
        wallets: Stream.value(wallets),
        transactions: Stream.value(const []),
        goals: Stream.value(goals),
        safeToSpend: const SizedBox(height: 10),
        today: DateTime(2026, 10, 25),
      ),
    );

    expect(find.text('₱7,000'), findsOneWidget);
    expect(find.text('₱5,000'), findsOneWidget);
    expect(find.text('₱2,000'), findsOneWidget);
    // Only what can be spent; what goals hold is shown in Goals and Wallets.
    expect(find.text('₱12,000 set aside for goals'), findsNothing);
  });

  testWidgets('Wallets says the same, as a sum', (tester) async {
    await pump(
      tester,
      WalletsScreen(
        wallets: Stream.value(wallets),
        incomeSource: Stream.value(null),
        goals: Stream.value(goals),
      ),
    );

    expect(find.text('₱19,000'), findsOneWidget);
    expect(find.text('-₱12,000'), findsOneWidget);
    expect(find.text('₱7,000'), findsNWidgets(2));
    expect(find.text('Across 6 wallets'), findsOneWidget);
  });

  test('the assistant says the same', () {
    final reply = answerChat(
      'How much money do I have?',
      records: FinanceSnapshot(
        now: DateTime(2026, 10, 25),
        wallets: wallets,
        goals: goals,
      ),
    );
    expect(reply.text, contains('₱7,000 available across 6 wallets'));
    expect(reply.text, contains('Another ₱12,000 is set aside for your goals'));
  });

  testWidgets('a transfer can only move what is free', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: TransferSheet(
          wallets: Stream.value(wallets),
          goals: Stream.value(goals),
          initialFromWalletId: 'cash',
          initialToWalletId: 'gotyme',
          onSave:
              ({
                required String fromWalletId,
                required String toWalletId,
                required double amount,
                required double serviceCharge,
              }) {},
        ),
      ),
    );

    // Cash holds ₱10,000, but ₱8,000 of it is Graduation's.
    expect(find.text('Cash has ₱2,000 free to move'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '3000',
    );
    await tester.tap(find.text('Transfer').last);
    await tester.pump();
    expect(
      find.text(
        'Cash has ₱2,000 free to move. The other ₱8,000 is set aside for '
        'goals.',
      ),
      findsOneWidget,
    );
  });
}
