import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/main.dart';
import 'package:testapp/models/allocation.dart';
import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/bill.dart';
import 'package:testapp/models/onboarding_data.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/bill_calendar_screen.dart';
import 'package:testapp/screens/bill_detail_screen.dart';
import 'package:testapp/screens/chatbot_screen.dart';
import 'package:testapp/screens/financial_setup_screen.dart';
import 'package:testapp/screens/forgot_password_screen.dart';
import 'package:testapp/screens/income_waterfall_screen.dart';
import 'package:testapp/screens/main_shell.dart';
import 'package:testapp/widgets/quick_add_sheet.dart';
import 'package:testapp/screens/splash_screen.dart';
import 'package:testapp/screens/wallet_detail_screen.dart';
import 'package:testapp/screens/wallets_screen.dart';
import 'package:testapp/services/legacy_migration.dart';
import 'package:testapp/theme/app_buttons.dart';
import 'package:testapp/theme/app_colors.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/widgets/bill_payment_sheet.dart';
import 'package:testapp/widgets/legacy_import_card.dart';
import 'package:testapp/widgets/light_dark_toggle.dart';
import 'package:testapp/utils/date_format.dart';
import 'package:testapp/utils/categories.dart';
import 'package:testapp/utils/money_format.dart';
import 'package:testapp/widgets/money_text.dart';
import 'package:testapp/widgets/transfer_sheet.dart';
import 'package:testapp/widgets/wallet_picker.dart';

void main() {
  testWidgets('signed-out users see splash, then login after Get Started', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MyApp(
          home: SplashScreen(
            resolveDestination: () async => StartDestination.signedOut,
          ),
        ),
      ),
    );

    expect(find.text('Welcome to FinAssist'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Splash stays up for its minimum display time, then offers Get Started.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Facebook'), findsNothing);
  });

  testWidgets('splash shows retry when the session check fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MyApp(
          home: SplashScreen(
            resolveDestination: () async => throw Exception('offline'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
  });

  group('formatPeso', () {
    test('uses peso sign, thousands separators and 2 decimals', () {
      expect(formatPeso(12500), '₱12,500.00');
      expect(formatPeso(0.5), '₱0.50');
      expect(formatPeso(1234567.891), '₱1,234,567.89');
    });

    test('puts signs before the peso symbol', () {
      expect(formatPeso(-250), '-₱250.00');
      expect(formatPeso(500, sign: '+'), '+₱500.00');
      expect(formatPeso(500, sign: '-'), '-₱500.00');
    });

    test('masks digits', () {
      expect(formatPeso(12500, masked: true), '₱*****');
    });
  });

  testWidgets('MoneyText follows the privacy mask', (tester) async {
    final settings = AppSettingsProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: MoneyText(1500)),
      ),
    );
    expect(find.text('₱1,500.00'), findsOneWidget);

    settings.toggleAmountsMasked();
    await tester.pump();
    expect(find.text('₱*****'), findsOneWidget);
  });

  group('Forgot password', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      Future<void> Function(String) send,
    ) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ForgotPasswordScreen(
            initialEmail: 'dave@example.com',
            sendResetEmail: send,
          ),
        ),
      );
    }

    testWidgets('sends to the typed email and shows the success card', (
      tester,
    ) async {
      String? sentTo;
      await pumpScreen(tester, (email) async => sentTo = email);

      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(sentTo, 'dave@example.com');
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text("Didn't get it? Send again"), findsOneWidget);
    });

    testWidgets('shows a clear message when offline', (tester) async {
      await pumpScreen(
        tester,
        (_) async =>
            throw FirebaseAuthException(code: 'network-request-failed'),
      );

      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(
        find.text('No internet connection. Connect and try again.'),
        findsOneWidget,
      );
      expect(find.text('Check your email'), findsNothing);
    });

    testWidgets('does not send when the email is invalid', (tester) async {
      var called = false;
      await pumpScreen(tester, (_) async => called = true);

      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(find.text('Please enter a valid email.'), findsOneWidget);
    });
  });

  group('Main shell', () {
    Future<void> pumpShell(
      WidgetTester tester, {
      List<QuickAddAction>? actions,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainShell(
            pages: const [
              Text('Home page'),
              Text('Transactions page'),
              Text('Goals page'),
              Text('Wallet page'),
            ],
            quickAddActions: actions,
          ),
        ),
      );
    }

    testWidgets('has four tabs that switch in place', (tester) async {
      await pumpShell(tester, actions: const []);

      for (final label in ['Home', 'Transactions', 'Goals', 'Wallet']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Goals'));
      await tester.pump();
      expect(
        find.text('Goals page').hitTestable(),
        findsOneWidget,
        reason: 'Goals tab should be visible after tapping it',
      );
      expect(find.text('Home page').hitTestable(), findsNothing);
    });

    testWidgets('back button returns to Home before leaving', (tester) async {
      await pumpShell(tester, actions: const []);

      await tester.tap(find.text('Wallet'));
      await tester.pump();
      expect(find.text('Wallet page').hitTestable(), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Home page').hitTestable(), findsOneWidget);
    });

    testWidgets('+ opens the quick add grid and runs the chosen action', (
      tester,
    ) async {
      String? chosen;
      QuickAddAction action(String label) => QuickAddAction(
        icon: Icons.add,
        label: label,
        color: Colors.blue,
        onSelected: () => chosen = label,
      );

      await pumpShell(
        tester,
        actions: [action('Expense'), action('Income'), action('AI Chat')],
      );

      await tester.tap(find.byTooltip('Quick add'));
      await tester.pumpAndSettle();

      expect(find.text('Quick Add'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('AI Chat'), findsOneWidget);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      expect(chosen, 'Income');
      expect(find.text('Quick Add'), findsNothing);
    });
  });

  group('Onboarding', () {
    Future<void> pumpOnboarding(
      WidgetTester tester, {
      required Future<void> Function(OnboardingData) save,
      VoidCallback? onFinished,
    }) async {
      // Phone-sized screen so the layout matches a real device.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: FinancialSetupScreen(
              initialName: '',
              saveOnboarding: save,
              onFinished: onFinished ?? () {},
            ),
          ),
        ),
      );
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> chooseDropdown(
      WidgetTester tester,
      String hint,
      String option,
    ) async {
      await tapText(tester, hint);
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    testWidgets('walks through every step and saves the answers', (
      tester,
    ) async {
      OnboardingData? saved;
      var finished = false;
      await pumpOnboarding(
        tester,
        save: (data) async => saved = data,
        onFinished: () => finished = true,
      );

      // Step 1: Welcome
      expect(find.text('Step 1 of 5'), findsOneWidget);
      await tapText(tester, 'Get Started');

      // Step 2: Name is required
      expect(find.text('What should we call you?'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Please enter your name.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');

      // Step 3: Reminders
      expect(find.text('Never miss a bill'), findsOneWidget);
      await tapText(tester, 'Allow Reminders');

      // Step 4: Income
      expect(find.text('Step 4 of 5'), findsOneWidget);
      await chooseDropdown(tester, 'Select your income source', 'Allowance');
      await chooseDropdown(
        tester,
        'Select how often',
        'Twice a month (15th & 30th)',
      );
      await tester.enterText(find.byType(TextFormField).at(0), '5,000');

      // The first priority can't move up; moving it down swaps it.
      final moveUp = find.byTooltip('Move "Pay bills on time" up');
      await tester.ensureVisible(moveUp);
      final moveUpButton = find.ancestor(
        of: moveUp,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(moveUpButton).onPressed, isNull);
      await tester.tap(find.byTooltip('Move "Pay bills on time" down'));
      await tester.pump();

      await tapText(tester, 'Next');

      // Step 5: Wallets are required
      expect(find.text('Your starting wallets'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Please add at least one wallet.'), findsOneWidget);

      await tapText(tester, 'Add a Wallet');
      await tester.tap(find.text('GCash'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, '1250.50');
      await tapText(tester, 'Add Wallet');

      await tapText(tester, 'Add Another');
      await tester.enterText(find.byType(TextFormField).last, '300');
      await tapText(tester, 'Add Wallet');

      expect(find.text('₱1,250.50'), findsOneWidget);
      expect(find.text('₱300.00'), findsOneWidget);
      expect(find.text('Receives my Allowance'), findsNWidgets(2));

      // Move the income to the second (Cash) wallet.
      await tester.tap(find.text('Receives my Allowance').last);
      await tester.pump();
      await tapText(tester, 'Next');

      // Recap
      expect(find.text("You're ready, Dave!"), findsOneWidget);
      expect(find.text('2 wallets · ₱1,550.50 total'), findsOneWidget);
      expect(find.text('Not set yet'), findsOneWidget);
      // The button shows a spinner while saving, and this test's onFinished
      // doesn't navigate away, so pump a few frames instead of settling.
      await tester.ensureVisible(find.text('Go to Dashboard'));
      await tester.tap(find.text('Go to Dashboard'));
      await tester.pump();
      await tester.pump();

      expect(finished, isTrue);
      expect(saved, isNotNull);
      expect(saved!.name, 'Dave');
      expect(saved!.notificationsEnabled, isTrue);
      expect(saved!.incomeSource, 'Allowance');
      expect(saved!.incomeFrequency, 'Semi-monthly');
      expect(saved!.income, 5000);
      expect(saved!.dailyBudget, isNull);
      expect(saved!.priorities.take(2), [
        FinancialPriority.saveForGoal,
        FinancialPriority.payBills,
      ]);
      expect(saved!.wallets.map((w) => w.type), [
        WalletType.gcash,
        WalletType.cash,
      ]);
      expect(saved!.wallets.map((w) => w.receivesIncome), [false, true]);
      expect(saved!.wallets.first.name, 'GCash');
    });

    testWidgets('Back returns to the previous step', (tester) async {
      await pumpOnboarding(tester, save: (_) async {});

      await tapText(tester, 'Get Started');
      expect(find.text('Step 2 of 5'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('irregular income makes the amount an optional estimate', (
      tester,
    ) async {
      OnboardingData? saved;
      await pumpOnboarding(tester, save: (data) async => saved = data);

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');
      await tapText(tester, 'Skip for now');
      await chooseDropdown(
        tester,
        'Select how often',
        'Irregular (no fixed payday)',
      );

      expect(
        find.textContaining('No fixed payday? No problem.'),
        findsOneWidget,
      );
      expect(find.text('Rough monthly estimate (optional)'), findsOneWidget);
      expect(find.textContaining('Just a guess is fine.'), findsOneWidget);

      // The amount can stay blank for irregular income.
      await chooseDropdown(tester, 'Select your income source', 'Freelance');
      await tapText(tester, 'Next');
      expect(find.text('Your starting wallets'), findsOneWidget);

      await tapText(tester, 'Add a Wallet');
      await tester.enterText(find.byType(TextFormField).last, '500');
      await tapText(tester, 'Add Wallet');
      await tapText(tester, 'Next');

      expect(
        find.textContaining('Varies · Irregular (no fixed payday)'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Go to Dashboard'));
      await tester.tap(find.text('Go to Dashboard'));
      await tester.pump();
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!.incomeFrequency, 'Irregular');
      expect(saved!.income, isNull);
    });

    testWidgets('regular income still requires an amount', (tester) async {
      await pumpOnboarding(tester, save: (_) async {});

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');
      await tapText(tester, 'Skip for now');
      await chooseDropdown(tester, 'Select your income source', 'Salary');
      await chooseDropdown(tester, 'Select how often', 'Monthly');
      await tapText(tester, 'Next');

      expect(find.text('Enter a valid positive amount.'), findsOneWidget);
      expect(find.text('Your income'), findsOneWidget);
    });
  });

  group('AI assistant', () {
    Future<void> pumpChat(WidgetTester tester, Stream<bool> online) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ChatbotScreen(onlineStatus: online),
        ),
      );
      await tester.pump();
    }

    Future<void> ask(WidgetTester tester, String question) async {
      await tester.enterText(find.byType(TextField), question);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('shows online status and the finance-only notice', (
      tester,
    ) async {
      await pumpChat(tester, Stream.value(true));

      expect(find.text('Online'), findsOneWidget);
      expect(find.textContaining('Finance questions only'), findsOneWidget);
    });

    testWidgets('switches to offline and warns about limited answers', (
      tester,
    ) async {
      final online = StreamController<bool>();
      addTearDown(online.close);

      await pumpChat(tester, online.stream);
      online.add(false);
      // The stream delivers asynchronously, so let it arrive before checking.
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.textContaining('can only share general tips'),
        findsOneWidget,
      );

      await ask(tester, 'How is my budget doing?');
      expect(find.textContaining("You're offline right now"), findsOneWidget);
    });

    testWidgets('politely redirects questions that are not about money', (
      tester,
    ) async {
      await pumpChat(tester, Stream.value(true));

      await ask(tester, 'What is the weather tomorrow?');
      expect(
        find.textContaining('I can only help with money questions'),
        findsOneWidget,
      );

      await ask(tester, 'How do I save more?');
      expect(
        find.textContaining('setting a specific monthly savings goal'),
        findsOneWidget,
      );
    });
  });

  testWidgets('Dark Mode switch turns dark mode on and off', (tester) async {
    final settings = AppSettingsProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: LightDarkToggle()),
        ),
      ),
    );
    expect(settings.themeMode, ThemeMode.light);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.themeMode, ThemeMode.dark);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.themeMode, ThemeMode.light);
  });

  test('light mode keeps the original screen colors', () {
    expect(AppColors.light.pageBackground, const Color(0xFFF6F8FC));
    expect(AppColors.light.card, Colors.white);
    expect(AppColors.light.inputBorder, const Color(0xFFDADADA));
  });

  test('category helpers accept saved and older spellings', () {
    expect(categoryColor('Healthcare'), categoryColor('health'));
    expect(categoryColor('Others'), categoryColor('other'));
    expect(
      categoryIconAsset('Healthcare'),
      'assets/icons/icons8-cat-healthcare-96.png',
    );
    expect(categoryIconAsset('health'), categoryIconAsset('Healthcare'));
    expect(
      categoryIconAsset('Anything else'),
      'assets/icons/icons8-cat-others-96.png',
    );
  });

  group('wallets', () {
    Wallet wallet({
      required String id,
      String? name,
      double balance = 0,
      bool receivesIncome = false,
      bool archived = false,
      int sortOrder = 0,
    }) {
      return Wallet(
        id: id,
        name: name ?? id,
        type: WalletType.cash,
        balance: balance,
        startingBalance: balance,
        receivesIncome: receivesIncome,
        archived: archived,
        sortOrder: sortOrder,
      );
    }

    test('a stored wallet is read back with its saved values', () {
      final saved = Wallet.fromMap('w1', {
        'name': 'BPI Savings',
        'type': 'bank',
        'balance': 1250,
        'startingBalance': 1000,
        'receivesIncome': true,
        'archived': false,
        'sortOrder': 2,
      });

      expect(saved.name, 'BPI Savings');
      expect(saved.type, WalletType.bank);
      expect(saved.balance, 1250.0);
      expect(saved.receivesIncome, isTrue);
      expect(saved.sortOrder, 2);
      expect(saved.iconAsset, WalletType.bank.iconAsset);
    });

    test('a damaged wallet record falls back instead of crashing', () {
      final broken = Wallet.fromMap('w2', {
        'name': '   ',
        'type': 'crypto',
        'balance': 'not a number',
      });

      expect(broken.type, WalletType.other);
      expect(broken.name, WalletType.other.label, reason: 'blank name');
      expect(broken.balance, 0);
      expect(broken.archived, isFalse);
      expect(Wallet.fromMap('w3', null).name, WalletType.other.label);
    });

    test('wallets are ordered by position, then by name', () {
      final wallets = [
        wallet(id: 'c', name: 'GCash', sortOrder: 1),
        wallet(id: 'b', name: 'Bank', sortOrder: 0),
        wallet(id: 'a', name: 'Allowance', sortOrder: 0),
      ];

      sortWallets(wallets);

      expect(wallets.map((w) => w.name), ['Allowance', 'Bank', 'GCash']);
    });

    test('the total balance leaves out archived wallets', () {
      final wallets = [
        wallet(id: 'a', balance: 500),
        wallet(id: 'b', balance: 250.50),
        wallet(id: 'c', balance: 9999, archived: true),
      ];

      expect(totalWalletBalance(wallets), 750.50);
      expect(totalWalletBalance(const []), 0);
    });

    test('a new wallet is placed after the existing ones', () {
      expect(nextWalletSortOrder(const []), 0);
      expect(
        nextWalletSortOrder([
          wallet(id: 'a', sortOrder: 0),
          wallet(id: 'b', sortOrder: 3),
        ]),
        4,
      );
    });

    test('only one wallet can receive the income', () {
      final wallets = [
        wallet(id: 'a', receivesIncome: true),
        wallet(id: 'b'),
        wallet(id: 'c', receivesIncome: true),
      ];

      expect(incomeWalletUpdates(wallets, 'b'), {
        'a': false,
        'b': true,
        'c': false,
      });
      expect(incomeWallet(wallets)?.id, 'a');
    });

    test('choosing the wallet that already receives income writes nothing', () {
      final wallets = [wallet(id: 'a', receivesIncome: true), wallet(id: 'b')];

      expect(incomeWalletUpdates(wallets, 'a'), isEmpty);
    });

    test('an archived wallet is not treated as the income wallet', () {
      final wallets = [wallet(id: 'a', receivesIncome: true, archived: true)];

      expect(incomeWallet(wallets), isNull);
    });
  });

  group('transactions', () {
    AppTransaction transaction({
      required TransactionType type,
      double amount = 100,
      String? walletId = 'a',
      String? toWalletId,
      DateTime? date,
      bool isLegacy = false,
    }) {
      return AppTransaction(
        id: 't',
        type: type,
        amount: amount,
        label: type.label,
        date: date ?? DateTime(2026, 1, 1),
        walletId: walletId,
        toWalletId: toWalletId,
        isLegacy: isLegacy,
      );
    }

    test('an expense takes money out and an income puts money in', () {
      expect(
        transaction(
          type: TransactionType.expense,
          amount: 250,
        ).balanceDeltaFor('a'),
        -250,
      );
      expect(
        transaction(
          type: TransactionType.income,
          amount: 250,
        ).balanceDeltaFor('a'),
        250,
      );
    });

    test('a transfer moves the same amount between two wallets', () {
      final transfer = transaction(
        type: TransactionType.transfer,
        amount: 500,
        toWalletId: 'b',
      );

      expect(transfer.balanceDeltaFor('a'), -500);
      expect(transfer.balanceDeltaFor('b'), 500);
      expect(transfer.balanceDeltaFor('c'), 0, reason: 'untouched wallet');
      expect(
        transfer.balanceDeltaFor('a') + transfer.balanceDeltaFor('b'),
        0,
        reason: 'a transfer must not change the combined total',
      );
    });

    test('a migrated record without a wallet changes no balance', () {
      final legacy = transaction(
        type: TransactionType.expense,
        walletId: null,
        isLegacy: true,
      );

      expect(legacy.sourceDelta, 0);
      expect(legacy.balanceDeltaFor('a'), 0);
      expect(legacy.involvesWallet('a'), isFalse);
    });

    test('a wallet shows its own transactions, newest first', () {
      final transactions = [
        transaction(
          type: TransactionType.expense,
          walletId: 'a',
          date: DateTime(2026, 1, 1),
        ),
        transaction(
          type: TransactionType.expense,
          walletId: 'b',
          date: DateTime(2026, 1, 2),
        ),
        transaction(
          type: TransactionType.transfer,
          walletId: 'b',
          toWalletId: 'a',
          date: DateTime(2026, 1, 3),
        ),
      ];

      final forA = transactionsForWallet(transactions, 'a');

      expect(forA.length, 2, reason: 'its own expense plus the transfer in');
      expect(forA.first.type, TransactionType.transfer);
      expect(forA.last.date, DateTime(2026, 1, 1));
    });

    test('records copied from the old collections are still readable', () {
      final fromExpenses = AppTransaction.fromMap('old1', {
        'type': 'expense',
        'amount': 120,
        'category': 'Food',
        'date': Timestamp.fromDate(DateTime(2025, 12, 25)),
        'legacy': true,
      });

      expect(fromExpenses.label, 'Food');
      expect(fromExpenses.amount, 120);
      expect(fromExpenses.date, DateTime(2025, 12, 25));
      expect(fromExpenses.isLegacy, isTrue);
      expect(fromExpenses.walletId, isNull);

      final fromDailyIncome = AppTransaction.fromMap('old2', {
        'type': 'income',
        'amount': -50,
        'source': 'Allowance',
      });

      expect(fromDailyIncome.label, 'Allowance');
      expect(fromDailyIncome.amount, 50, reason: 'amounts are stored positive');
      expect(fromDailyIncome.sourceDelta, 0, reason: 'no wallet to credit');
    });
  });

  group('Wallets screen', () {
    Wallet wallet({
      required String id,
      required String name,
      WalletType type = WalletType.cash,
      double balance = 0,
      bool receivesIncome = false,
      int sortOrder = 0,
    }) {
      return Wallet(
        id: id,
        name: name,
        type: type,
        balance: balance,
        startingBalance: balance,
        receivesIncome: receivesIncome,
        archived: false,
        sortOrder: sortOrder,
      );
    }

    Future<void> pumpWallets(
      WidgetTester tester, {
      required List<Wallet> wallets,
      String? incomeSource,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: WalletsScreen(
              wallets: Stream.value(wallets),
              incomeSource: Stream.value(incomeSource),
            ),
          ),
        ),
      );
      // Two frames: one for the wallet list, one for the income source.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('offers to add a wallet when there are none', (tester) async {
      await pumpWallets(tester, wallets: const []);

      expect(find.text('No wallets yet'), findsOneWidget);
      expect(find.text('Add Wallet'), findsOneWidget);
      expect(find.text('Total Balance'), findsNothing);
    });

    testWidgets('lists each wallet with its balance and the total', (
      tester,
    ) async {
      await pumpWallets(
        tester,
        wallets: [
          wallet(id: 'a', name: 'Allowance', balance: 1200),
          wallet(
            id: 'b',
            name: 'My GCash',
            type: WalletType.gcash,
            balance: 300.50,
            sortOrder: 1,
          ),
        ],
      );

      expect(find.text('Allowance'), findsOneWidget);
      expect(find.text('My GCash'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget, reason: 'the type label');
      expect(find.text('₱1,200.00'), findsOneWidget);
      expect(find.text('₱300.50'), findsOneWidget);
      expect(find.text('₱1,500.50'), findsOneWidget, reason: 'the total');
      expect(find.text('Across 2 wallets'), findsOneWidget);
    });

    testWidgets('marks the income wallet using the saved income source', (
      tester,
    ) async {
      await pumpWallets(
        tester,
        incomeSource: 'Allowance',
        wallets: [
          wallet(id: 'a', name: 'Cash', receivesIncome: true),
          wallet(id: 'b', name: 'GCash', sortOrder: 1),
        ],
      );

      expect(find.text('Receives my Allowance'), findsOneWidget);
    });

    testWidgets('falls back to a plain badge with no saved income source', (
      tester,
    ) async {
      await pumpWallets(
        tester,
        wallets: [wallet(id: 'a', name: 'Cash', receivesIncome: true)],
      );

      expect(find.text('Receives my income'), findsOneWidget);
    });

    testWidgets('asks before removing a wallet and says history is kept', (
      tester,
    ) async {
      await pumpWallets(
        tester,
        wallets: [wallet(id: 'a', name: 'GCash', balance: 500)],
      );

      await tester.tap(find.byTooltip('Wallet options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove wallet'));
      await tester.pumpAndSettle();

      expect(find.text('Remove GCash?'), findsOneWidget);
      expect(find.textContaining('past transactions are kept'), findsOneWidget);

      // Backing out must leave the wallet alone.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('GCash'), findsOneWidget);
    });
  });

  group('Wallet detail', () {
    final cash = Wallet(
      id: 'a',
      name: 'Cash',
      type: WalletType.cash,
      balance: 1200,
      startingBalance: 1000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    final gcash = Wallet(
      id: 'b',
      name: 'My GCash',
      type: WalletType.gcash,
      balance: 500,
      startingBalance: 500,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
    );

    AppTransaction transfer({DateTime? date}) {
      return AppTransaction(
        id: 't1',
        type: TransactionType.transfer,
        amount: 200,
        label: 'Transfer',
        date: date ?? DateTime.now(),
        walletId: 'a',
        toWalletId: 'b',
      );
    }

    Future<void> pumpDetail(
      WidgetTester tester, {
      required Wallet wallet,
      List<AppTransaction> transactions = const [],
      String? incomeSource,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: WalletDetailScreen(
              wallet: wallet,
              wallets: Stream.value([cash, gcash]),
              transactions: Stream.value(transactions),
              incomeSource: Stream.value(incomeSource),
            ),
          ),
        ),
      );
      // Two frames: one for the wallet list, one for the transactions.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows the balance and who pays into this wallet', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: cash, incomeSource: 'Allowance');

      expect(find.text('Cash'), findsWidgets);
      expect(find.text('₱1,200.00'), findsOneWidget);
      expect(
        find.text('Your Allowance is paid into this wallet'),
        findsOneWidget,
      );
    });

    testWidgets('says there is nothing in a wallet with no transactions', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: gcash);

      expect(find.text('No transactions yet'), findsOneWidget);
    });

    testWidgets('a transfer reads as money out of the wallet it left', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: cash, transactions: [transfer()]);

      expect(find.text('To My GCash'), findsOneWidget);
      expect(find.text('-₱200.00'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('the same transfer reads as money into the wallet it reached', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: gcash, transactions: [transfer()]);

      expect(find.text('From Cash'), findsOneWidget);
      expect(find.text('+₱200.00'), findsOneWidget);
    });

    testWidgets('groups older transactions under their date', (tester) async {
      await pumpDetail(
        tester,
        wallet: cash,
        transactions: [
          transfer(date: DateTime.now().subtract(const Duration(days: 1))),
        ],
      );

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('asks before deleting and promises the money comes back', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: cash, transactions: [transfer()]);

      await tester.longPress(find.text('To My GCash'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this transaction?'), findsOneWidget);
      expect(find.textContaining('put back'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('To My GCash'), findsOneWidget);
    });
  });

  group('date labels', () {
    final now = DateTime(2026, 9, 16, 14, 30);

    test('recent days read as Today and Yesterday', () {
      expect(transactionDateLabel(DateTime(2026, 9, 16, 1), now: now), 'Today');
      expect(
        transactionDateLabel(DateTime(2026, 9, 15, 23), now: now),
        'Yesterday',
      );
    });

    test('older days read as a plain date', () {
      expect(
        transactionDateLabel(DateTime(2026, 9, 14), now: now),
        'Sep 14, 2026',
      );
      expect(formatShortDate(DateTime(2025, 12, 1)), 'Dec 1, 2025');
    });
  });

  group('choosing a wallet', () {
    Wallet wallet(
      String id, {
      bool receivesIncome = false,
      double balance = 0,
    }) {
      return Wallet(
        id: id,
        name: id,
        type: WalletType.cash,
        balance: balance,
        startingBalance: balance,
        receivesIncome: receivesIncome,
        archived: false,
        sortOrder: 0,
      );
    }

    test('a new entry starts on the wallet that receives income', () {
      expect(
        defaultWalletId([wallet('a'), wallet('b', receivesIncome: true)]),
        'b',
      );
    });

    test('with no income wallet it starts on the first one', () {
      expect(defaultWalletId([wallet('a'), wallet('b')]), 'a');
      expect(defaultWalletId(const []), isNull);
    });

    testWidgets('the picker can leave a wallet out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: WalletPicker(
              wallets: [wallet('Cash'), wallet('GCash')],
              selectedId: null,
              excludeId: 'Cash',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('GCash'), findsWidgets);
      expect(find.text('Cash'), findsNothing);
    });
  });

  group('Transfer', () {
    final cash = Wallet(
      id: 'a',
      name: 'Cash',
      type: WalletType.cash,
      balance: 500,
      startingBalance: 500,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    final gcash = Wallet(
      id: 'b',
      name: 'My GCash',
      type: WalletType.gcash,
      balance: 0,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
    );

    Future<void> pumpTransfer(
      WidgetTester tester, {
      required List<Wallet> wallets,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: TransferSheet(wallets: Stream.value(wallets))),
        ),
      );
      await tester.pump();
    }

    testWidgets('explains that a transfer needs a second wallet', (
      tester,
    ) async {
      await pumpTransfer(tester, wallets: [cash]);

      expect(find.textContaining('need a second wallet'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Transfer'),
        findsNothing,
        reason: 'nothing to transfer to',
      );
    });

    testWidgets('shows what the source wallet holds', (tester) async {
      await pumpTransfer(tester, wallets: [cash, gcash]);

      expect(find.text('Cash holds ₱500.00'), findsOneWidget);
      expect(find.textContaining('Your total stays the same'), findsOneWidget);
    });

    testWidgets('refuses to move more money than the wallet holds', (
      tester,
    ) async {
      await pumpTransfer(tester, wallets: [cash, gcash]);

      await tester.enterText(find.byType(TextFormField).first, '800');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Transfer'));
      await tester.pump();

      expect(find.text('Cash only holds ₱500.00.'), findsOneWidget);
    });

    testWidgets('asks for an amount before transferring', (tester) async {
      await pumpTransfer(tester, wallets: [cash, gcash]);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Transfer'));
      await tester.pump();

      expect(find.text('Enter an amount to transfer.'), findsOneWidget);
      expect(find.text('Choose a wallet.'), findsOneWidget);
    });
  });

  group('importing older records', () {
    test('an old expense becomes a history entry that moves no money', () {
      final entry = LegacyMigration.expenseToTransaction({
        'amount': 250,
        'category': 'Food',
        'description': 'Lunch at school',
        'date': Timestamp.fromDate(DateTime(2025, 11, 4)),
        'paymentMethod': 'Cash',
      });

      final transaction = AppTransaction.fromMap('e1', entry);

      expect(transaction.type, TransactionType.expense);
      expect(transaction.amount, 250);
      expect(transaction.label, 'Food');
      expect(transaction.note, 'Lunch at school');
      expect(transaction.date, DateTime(2025, 11, 4));
      expect(transaction.isLegacy, isTrue);
      expect(transaction.walletId, isNull);
      expect(
        transaction.sourceDelta,
        0,
        reason: 'the money is already inside the starting balances',
      );
    });

    test('an old income record becomes a history entry', () {
      final entry = LegacyMigration.incomeToTransaction({
        'amount': 500,
        'source': 'Allowance',
        'type': 'income',
        'date': Timestamp.fromDate(DateTime(2025, 11, 5)),
      });

      final transaction = AppTransaction.fromMap('i1', entry);

      expect(transaction.type, TransactionType.income);
      expect(transaction.label, 'Allowance');
      expect(transaction.amount, 500);
      expect(transaction.isLegacy, isTrue);
      expect(transaction.balanceDeltaFor('any wallet'), 0);
    });

    test('a record missing its fields still imports safely', () {
      final expense = AppTransaction.fromMap(
        'e2',
        LegacyMigration.expenseToTransaction({'amount': -75}),
      );

      expect(expense.label, 'Others');
      expect(expense.amount, 75, reason: 'amounts are stored positive');
      expect(expense.note, isNull);

      final income = AppTransaction.fromMap(
        'i2',
        LegacyMigration.incomeToTransaction(const {}),
      );

      expect(income.label, 'Income');
      expect(income.amount, 0);
    });
  });

  group('older records card', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required int pending,
      Future<int> Function()? runImport,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LegacyImportCard(
              countPending: () async => pending,
              runImport: runImport ?? () async => pending,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('stays out of the way when there is nothing to import', (
      tester,
    ) async {
      await pumpCard(tester, pending: 0);

      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('says how many records are waiting', (tester) async {
      await pumpCard(tester, pending: 12);

      expect(find.text('You have 12 older records'), findsOneWidget);
      expect(find.text('Add to my history'), findsOneWidget);
    });

    testWidgets('promises that balances do not change before importing', (
      tester,
    ) async {
      await pumpCard(tester, pending: 3);

      await tester.tap(find.text('Add to my history'));
      await tester.pumpAndSettle();

      expect(find.text('Add older records?'), findsOneWidget);
      expect(
        find.textContaining('No wallet balance will change'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing is deleted'), findsOneWidget);
    });

    testWidgets('backing out imports nothing', (tester) async {
      var ran = false;
      await pumpCard(
        tester,
        pending: 3,
        runImport: () async {
          ran = true;
          return 3;
        },
      );

      await tester.tap(find.text('Add to my history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(ran, isFalse);
      expect(find.text('Add to my history'), findsOneWidget);
    });

    testWidgets('importing reports the count and hides the card', (
      tester,
    ) async {
      await pumpCard(tester, pending: 3);

      await tester.tap(find.text('Add to my history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add them'));
      await tester.pumpAndSettle();

      expect(
        find.text('Added 3 older records to your history.'),
        findsOneWidget,
      );
      expect(find.text('Add to my history'), findsNothing);
    });
  });

  group('Add income waterfall', () {
    final today = DateTime(2026, 3, 10);

    final cash = Wallet(
      id: 'w1',
      name: 'Cash',
      type: WalletType.cash,
      balance: 500,
      startingBalance: 500,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );

    BillInstance bill(String name, double amount, {DateTime? dueDate}) {
      return BillInstance(
        id: 'b_$name',
        billId: 'b',
        name: name,
        amount: amount,
        category: 'Bills',
        dueDate: dueDate ?? DateTime(2026, 3, 15),
        status: BillStatus.unpaid,
      );
    }

    Future<void> pumpWaterfall(
      WidgetTester tester, {
      List<BillInstance> bills = const [],
      void Function(AllocationPlan plan, String walletId, String source)?
      onConfirm,
    }) async {
      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IncomeWaterfallScreen(
            today: today,
            wallets: Stream.value([cash]),
            loadBills: () async => bills,
            onConfirm:
                ({
                  required AllocationPlan plan,
                  required String walletId,
                  required String source,
                  required DateTime receivedAt,
                }) => onConfirm?.call(plan, walletId, source),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> pickSource(WidgetTester tester, String source) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(source).last);
      await tester.pumpAndSettle();
    }

    Future<void> fillIncome(WidgetTester tester, String amount) async {
      await tester.enterText(find.byType(TextField).first, amount);
      await pickSource(tester, 'Allowance');
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for the amount before moving on', (tester) async {
      await pumpWaterfall(tester);

      expect(find.text('Step 1 of 3'), findsOneWidget);
      await next(tester);

      expect(find.text('Enter how much came in.'), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('asks where the money came from only after picking Other', (
      tester,
    ) async {
      await pumpWaterfall(tester);

      expect(find.text('Where did it come from?'), findsNothing);
      await pickSource(tester, 'Other');

      expect(find.text('Where did it come from?'), findsOneWidget);
    });

    testWidgets('offers the sources a student actually has', (tester) async {
      await pumpWaterfall(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();

      for (final source in ['Allowance', 'Scholarship', 'Gift', 'Refund']) {
        expect(find.text(source), findsWidgets, reason: source);
      }
      expect(
        find.text('Borrowed Money'),
        findsNothing,
        reason: 'borrowed money is a debt, not income',
      );
    });

    testWidgets('with no bills it goes straight to what is left', (
      tester,
    ) async {
      await pumpWaterfall(tester);

      await fillIncome(tester, '2000');
      await next(tester);

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('₱2,000.00'), findsOneWidget);
      expect(find.textContaining('No unpaid bills right now'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('each bill starts on its full amount, with a running total', (
      tester,
    ) async {
      await pumpWaterfall(
        tester,
        bills: [bill('Rent', 1500), bill('Load', 300)],
      );

      await fillIncome(tester, '5000');
      await next(tester);

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('1500.00'), findsOneWidget);
      expect(find.text('300.00'), findsOneWidget);
      expect(find.text('Left after these bills'), findsOneWidget);
      expect(find.text('₱3,200.00'), findsOneWidget);
    });

    testWidgets('a bill cannot be paid more than it owes', (tester) async {
      await pumpWaterfall(tester, bills: [bill('Rent', 1500)]);

      await fillIncome(tester, '5000');
      await next(tester);

      await tester.enterText(find.widgetWithText(TextField, '1500.00'), '2000');
      await next(tester);

      expect(find.text('Rent only needs ₱1,500.00.'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsOneWidget);
    });

    testWidgets('confirming saves the income, the bills and what is left', (
      tester,
    ) async {
      AllocationPlan? saved;
      String? savedWallet;
      String? savedSource;

      await pumpWaterfall(
        tester,
        bills: [bill('Rent', 1500), bill('Load', 300)],
        onConfirm: (plan, walletId, source) {
          saved = plan;
          savedWallet = walletId;
          savedSource = source;
        },
      );

      await fillIncome(tester, '5000');
      await next(tester);

      // Leave Load for later instead of paying it.
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      await next(tester);

      expect(find.text('Left to spend'), findsOneWidget);
      expect(find.text('₱3,500.00'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(saved!.income, 5000);
      expect(saved!.toBills, 1500);
      expect(saved!.bills.map((b) => b.instance.name), ['Rent']);
      expect(savedWallet, 'w1');
      expect(savedSource, 'Allowance');
    });

    testWidgets('warns when the bills cost more than came in', (tester) async {
      await pumpWaterfall(tester, bills: [bill('Rent', 3000)]);

      await fillIncome(tester, '1000');
      await next(tester);

      expect(find.text('Short by'), findsOneWidget);
      await next(tester);

      expect(find.text('More than came in'), findsOneWidget);
      expect(
        find.textContaining('will come out of what was already in Cash'),
        findsOneWidget,
      );
    });
  });

  group('bill schedules', () {
    Bill bill({
      required DateTime firstDueDate,
      BillRecurrence recurrence = BillRecurrence.monthly,
      double amount = 1000,
    }) {
      return Bill(
        id: 'b1',
        name: 'Rent',
        amount: amount,
        category: 'Bills',
        firstDueDate: firstDueDate,
        recurrence: recurrence,
      );
    }

    test('a monthly bill falls due once a month, from its first date on', () {
      final rent = bill(firstDueDate: DateTime(2026, 3, 5));

      expect(rent.occurrencesIn(2026, 3), [DateTime(2026, 3, 5)]);
      expect(rent.occurrencesIn(2026, 4), [DateTime(2026, 4, 5)]);
      expect(rent.occurrencesIn(2027, 1), [DateTime(2027, 1, 5)]);
      expect(rent.occurrencesIn(2026, 2), isEmpty, reason: 'before it starts');
    });

    test('a bill due on the 31st still falls due in February', () {
      final due31 = bill(firstDueDate: DateTime(2026, 1, 31));

      expect(due31.occurrencesIn(2026, 2), [DateTime(2026, 2, 28)]);
      expect(due31.occurrencesIn(2028, 2), [DateTime(2028, 2, 29)]);
      expect(due31.occurrencesIn(2026, 4), [DateTime(2026, 4, 30)]);
      expect(due31.occurrencesIn(2026, 3), [DateTime(2026, 3, 31)]);
    });

    test('a weekly bill falls due several times a month', () {
      final load = bill(
        firstDueDate: DateTime(2026, 1, 5),
        recurrence: BillRecurrence.weekly,
      );

      expect(load.occurrencesIn(2026, 1), [
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 12),
        DateTime(2026, 1, 19),
        DateTime(2026, 1, 26),
      ]);
      // Keeps the weekday even months later, without walking week by week.
      expect(
        load.occurrencesIn(2026, 6).every((date) => date.weekday == 1),
        isTrue,
      );
      expect(load.occurrencesIn(2025, 12), isEmpty);
    });

    test('quarterly and yearly skip the months in between', () {
      final tuition = bill(
        firstDueDate: DateTime(2026, 1, 15),
        recurrence: BillRecurrence.quarterly,
      );
      final insurance = bill(
        firstDueDate: DateTime(2026, 1, 15),
        recurrence: BillRecurrence.yearly,
      );

      expect(tuition.occurrencesIn(2026, 4), [DateTime(2026, 4, 15)]);
      expect(tuition.occurrencesIn(2026, 5), isEmpty);
      expect(insurance.occurrencesIn(2027, 1), [DateTime(2027, 1, 15)]);
      expect(insurance.occurrencesIn(2026, 7), isEmpty);
    });

    test('a one-time bill only ever falls due once', () {
      final once = bill(
        firstDueDate: DateTime(2026, 3, 9),
        recurrence: BillRecurrence.once,
      );

      expect(once.occurrencesIn(2026, 3), [DateTime(2026, 3, 9)]);
      expect(once.occurrencesIn(2026, 4), isEmpty);
    });

    test('the same bill and date always produce the same record id', () {
      expect(
        billInstanceId('abc', DateTime(2026, 3, 5, 23, 59)),
        billInstanceId('abc', DateTime(2026, 3, 5)),
      );
      expect(billInstanceId('abc', DateTime(2026, 3, 5)), 'abc_20260305');
      expect(
        billInstanceId('abc', DateTime(2026, 3, 5)),
        isNot(billInstanceId('abc', DateTime(2026, 4, 5))),
      );
    });
  });

  group('bill occurrences', () {
    final today = DateTime(2026, 3, 10);

    BillInstance instance({
      required DateTime dueDate,
      BillStatus status = BillStatus.unpaid,
      double amount = 1000,
      double amountPaid = 0,
    }) {
      return BillInstance(
        id: 'b1_x',
        billId: 'b1',
        name: 'Rent',
        amount: amount,
        category: 'Bills',
        dueDate: dueDate,
        status: status,
        amountPaid: amountPaid,
      );
    }

    test('a bill reads as overdue, due soon or upcoming', () {
      expect(
        instance(dueDate: DateTime(2026, 3, 9)).urgency(now: today),
        BillUrgency.overdue,
      );
      expect(
        instance(dueDate: DateTime(2026, 3, 10)).urgency(now: today),
        BillUrgency.dueSoon,
        reason: 'due today',
      );
      expect(
        instance(dueDate: DateTime(2026, 3, 13)).urgency(now: today),
        BillUrgency.dueSoon,
      );
      expect(
        instance(dueDate: DateTime(2026, 3, 14)).urgency(now: today),
        BillUrgency.upcoming,
      );
    });

    test('a settled bill is never shown as overdue', () {
      final longPast = DateTime(2026, 1, 1);

      expect(
        instance(
          dueDate: longPast,
          status: BillStatus.paid,
        ).urgency(now: today),
        BillUrgency.paid,
      );
      expect(
        instance(
          dueDate: longPast,
          status: BillStatus.skipped,
        ).urgency(now: today),
        BillUrgency.skipped,
      );
    });

    test('paying part of a bill leaves the rest owing', () {
      final partly = instance(
        dueDate: DateTime(2026, 3, 5),
        amount: 1000,
        amountPaid: 400,
      );

      expect(partly.remaining, 600);
      expect(BillInstance.statusForPayment(400, 1000), BillStatus.partial);
      expect(BillInstance.statusForPayment(1000, 1000), BillStatus.paid);
      expect(BillInstance.statusForPayment(0, 1000), BillStatus.unpaid);
    });

    test('overpaying does not show as money still owed', () {
      final overpaid = instance(
        dueDate: DateTime(2026, 3, 5),
        amount: 1000,
        amountPaid: 1200,
      );

      expect(overpaid.remaining, 0);
    });

    test('what is left unpaid rolls into the next cycle', () {
      final unpaid = instance(
        dueDate: DateTime(2026, 2, 5),
        amount: 1000,
        amountPaid: 300,
      );

      expect(carryOverFrom(unpaid, now: today), 700);
      expect(carryOverFrom(null, now: today), 0);
    });

    test('a bill not due yet rolls nothing over', () {
      final notYetDue = instance(dueDate: DateTime(2026, 3, 25), amount: 1000);

      expect(carryOverFrom(notYetDue, now: today), 0);
    });

    test('skipping a bill rolls nothing over', () {
      final skipped = instance(
        dueDate: DateTime(2026, 2, 5),
        amount: 1000,
        status: BillStatus.skipped,
      );

      expect(
        carryOverFrom(skipped, now: today),
        0,
        reason: 'skipping is deciding not to pay it at all',
      );
    });

    test('a damaged bill record falls back instead of crashing', () {
      final broken = BillInstance.fromMap('x', {
        'amount': 'lots',
        'status': 'exploded',
      });

      expect(broken.name, 'Bill');
      expect(broken.amount, 0);
      expect(broken.status, BillStatus.unpaid);
      expect(broken.paymentIds, isEmpty);
      expect(Bill.fromMap('y', null).recurrence, BillRecurrence.monthly);
    });
  });

  group('Bill calendar', () {
    final today = DateTime(2026, 3, 10);

    Bill bill({String id = 'b1', String name = 'Rent'}) {
      return Bill(
        id: id,
        name: name,
        amount: 3000,
        category: 'Bills',
        firstDueDate: DateTime(2026, 3, 5),
        recurrence: BillRecurrence.monthly,
      );
    }

    BillInstance instance({
      String id = 'b1_20260305',
      String name = 'Rent',
      double amount = 3000,
      double amountPaid = 0,
      BillStatus status = BillStatus.unpaid,
      DateTime? dueDate,
    }) {
      return BillInstance(
        id: id,
        billId: 'b1',
        name: name,
        amount: amount,
        category: 'Bills',
        dueDate: dueDate ?? DateTime(2026, 3, 5),
        status: status,
        amountPaid: amountPaid,
      );
    }

    Future<void> pumpCalendar(
      WidgetTester tester, {
      List<Bill> bills = const [],
      List<BillInstance> instances = const [],
      void Function(int year, int month)? onFill,
    }) async {
      // A calendar grid plus the day's bills needs more height than the
      // default test window, which would otherwise leave the list unbuilt.
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
              bills: Stream.value(bills),
              instancesFor: (year, month) => Stream.value(
                year == 2026 && month == 3 ? instances : const [],
              ),
              ensureInstances: (bills, year, month) async {
                onFill?.call(year, month);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('invites the user to add their first bill', (tester) async {
      await pumpCalendar(tester);

      expect(find.text('No bills yet'), findsOneWidget);
      expect(find.text('Add Bill'), findsOneWidget);
    });

    testWidgets('shows the month, its total and what is still owing', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        bills: [bill()],
        instances: [
          instance(),
          instance(
            id: 'b2_20260320',
            name: 'Internet',
            amount: 1500,
            amountPaid: 1500,
            status: BillStatus.paid,
            dueDate: DateTime(2026, 3, 20),
          ),
        ],
      );

      expect(find.text('March 2026'), findsOneWidget);
      expect(find.text('₱4,500.00'), findsOneWidget, reason: 'due this month');
      expect(find.text('₱3,000.00'), findsWidgets, reason: 'still owing');
      expect(find.textContaining('1 overdue'), findsOneWidget);
    });

    testWidgets('a day shows only the bills due on it', (tester) async {
      await pumpCalendar(
        tester,
        bills: [bill()],
        instances: [
          instance(),
          instance(
            id: 'b2_20260320',
            name: 'Internet',
            dueDate: DateTime(2026, 3, 20),
          ),
        ],
      );

      // Opens on today, the 10th, where nothing is due.
      expect(find.text('Nothing due on this day.'), findsOneWidget);

      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();

      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Internet'), findsNothing);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Internet'), findsOneWidget);
    });

    testWidgets('an overdue bill is called overdue, a paid one is not', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        bills: [bill()],
        instances: [
          instance(),
          instance(
            id: 'b2_20260301',
            name: 'Water',
            amountPaid: 3000,
            status: BillStatus.paid,
            dueDate: DateTime(2026, 3, 1),
          ),
        ],
      );

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('a part-paid bill says so and shows what is left', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        bills: [bill()],
        instances: [instance(amountPaid: 1000, status: BillStatus.partial)],
      );

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.text('Partly paid'), findsOneWidget);
      expect(find.text('₱2,000.00'), findsWidgets, reason: 'still owed');
    });

    testWidgets('the list view shows every bill without picking a day', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        bills: [bill()],
        instances: [
          instance(),
          instance(
            id: 'b2_20260320',
            name: 'Internet',
            dueDate: DateTime(2026, 3, 20),
          ),
        ],
      );

      await tester.tap(find.byTooltip('Show list'));
      await tester.pumpAndSettle();

      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Internet'), findsOneWidget);
    });

    testWidgets('moving months asks for that month to be filled in', (
      tester,
    ) async {
      final filled = <String>[];

      await pumpCalendar(
        tester,
        bills: [bill()],
        instances: [instance()],
        onFill: (year, month) => filled.add('$year-$month'),
      );

      expect(filled, ['2026-3']);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();

      expect(find.text('April 2026'), findsOneWidget);
      expect(filled, ['2026-3', '2026-4']);

      // Going back to a month already done must not repeat the work.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();

      expect(filled, ['2026-3', '2026-4']);
    });
  });

  group('Bill detail', () {
    final today = DateTime(2026, 3, 10);

    final rent = Bill(
      id: 'b1',
      name: 'Rent',
      amount: 3000,
      category: 'Bills',
      firstDueDate: DateTime(2026, 3, 5),
      recurrence: BillRecurrence.monthly,
    );

    BillInstance instance({
      String id = 'b1_20260305',
      double amount = 3000,
      double amountPaid = 0,
      double carriedOver = 0,
      BillStatus status = BillStatus.unpaid,
      DateTime? dueDate,
    }) {
      return BillInstance(
        id: id,
        billId: 'b1',
        name: 'Rent',
        amount: amount,
        category: 'Bills',
        dueDate: dueDate ?? DateTime(2026, 3, 5),
        status: status,
        amountPaid: amountPaid,
        carriedOver: carriedOver,
      );
    }

    Future<void> pumpDetail(
      WidgetTester tester, {
      required BillInstance current,
      List<BillInstance> history = const [],
    }) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: BillDetailScreen(
              instance: current,
              today: today,
              liveInstance: Stream.value(current),
              history: Stream.value(history),
              bills: Stream.value([rent]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows what is owed, when, and how it repeats', (tester) async {
      await pumpDetail(tester, current: instance());

      expect(find.text('Rent'), findsWidgets);
      expect(find.text('₱3,000.00'), findsOneWidget);
      expect(find.text('Due Mar 5, 2026'), findsOneWidget);
      expect(
        find.text('Falls due on the same date each month.'),
        findsOneWidget,
      );
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Mark as Paid'), findsOneWidget);
    });

    testWidgets('a part payment shows progress and what is left', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        current: instance(amountPaid: 1200, status: BillStatus.partial),
      );

      expect(find.text('Paid ₱1200.00'), findsOneWidget);
      expect(find.text('₱1800.00 to go'), findsOneWidget);
      expect(find.text('Partly paid'), findsOneWidget);
      expect(find.text('Undo payment'), findsOneWidget);
    });

    testWidgets('a fully paid bill offers no way to pay it again', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        current: instance(amountPaid: 3000, status: BillStatus.paid),
      );

      expect(find.text('Mark as Paid'), findsNothing);
      expect(find.text('Pay part of it'), findsNothing);
      expect(find.text('Fully paid'), findsOneWidget);
      expect(find.text('Undo payment'), findsOneWidget);
    });

    testWidgets('a skipped bill can be put back', (tester) async {
      await pumpDetail(tester, current: instance(status: BillStatus.skipped));

      expect(find.text('Put this bill back'), findsOneWidget);
      expect(find.text('Mark as Paid'), findsNothing);
    });

    testWidgets('says when an amount includes an unpaid remainder', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        current: instance(amount: 4200, carriedOver: 1200),
      );

      expect(
        find.textContaining('left unpaid from the cycle before'),
        findsOneWidget,
      );
    });

    testWidgets('undoing a payment warns the money goes back', (tester) async {
      await pumpDetail(
        tester,
        current: instance(amountPaid: 3000, status: BillStatus.paid),
      );

      await tester.tap(find.text('Undo payment'));
      await tester.pumpAndSettle();

      expect(find.text('Undo this payment?'), findsOneWidget);
      expect(find.textContaining('returns to your wallet'), findsOneWidget);
    });

    testWidgets('past cycles list the other months', (tester) async {
      await pumpDetail(
        tester,
        current: instance(),
        history: [
          instance(),
          instance(
            id: 'b1_20260205',
            amountPaid: 3000,
            status: BillStatus.paid,
            dueDate: DateTime(2026, 2, 5),
          ),
        ],
      );

      expect(find.text('Feb 5, 2026'), findsOneWidget);
      expect(find.text('This is the only cycle so far.'), findsNothing);
    });

    testWidgets('a single cycle says so instead of showing an empty list', (
      tester,
    ) async {
      await pumpDetail(tester, current: instance(), history: [instance()]);

      expect(find.text('This is the only cycle so far.'), findsOneWidget);
    });
  });

  group('Bill payment', () {
    final wallet = Wallet(
      id: 'w1',
      name: 'Cash',
      type: WalletType.cash,
      balance: 5000,
      startingBalance: 5000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );

    final instance = BillInstance(
      id: 'b1_20260305',
      billId: 'b1',
      name: 'Rent',
      amount: 3000,
      category: 'Bills',
      dueDate: DateTime(2026, 3, 5),
      status: BillStatus.unpaid,
    );

    Future<double?> pumpSheet(
      WidgetTester tester, {
      bool payInFull = true,
    }) async {
      double? paid;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BillPaymentSheet(
              instance: instance,
              payInFull: payInFull,
              wallets: Stream.value([wallet]),
              onPay: ({required String walletId, required double amount}) {
                paid = amount;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      return paid;
    }

    testWidgets('starts on the full amount owing', (tester) async {
      await pumpSheet(tester);

      expect(find.text('3000.00'), findsOneWidget);
      expect(find.text('₱3,000.00 still owing'), findsOneWidget);
    });

    testWidgets('starts empty when paying only part of it', (tester) async {
      await pumpSheet(tester, payInFull: false);

      expect(find.text('3000.00'), findsNothing);
    });

    testWidgets('refuses to pay more than the bill needs', (tester) async {
      await pumpSheet(tester, payInFull: false);

      await tester.enterText(find.byType(TextFormField), '5000');
      await tester.tap(find.text('Record Payment'));
      await tester.pump();

      expect(find.text('This bill only needs ₱3,000.00.'), findsOneWidget);
    });

    testWidgets('is honest that no real payment is made', (tester) async {
      await pumpSheet(tester);

      expect(
        find.textContaining('does not pay anyone for real'),
        findsOneWidget,
      );
    });
  });

  group('Bill payments from more than one wallet', () {
    final today = DateTime(2026, 3, 10);

    final cash = Wallet(
      id: 'w1',
      name: 'Cash',
      type: WalletType.cash,
      balance: 1000,
      startingBalance: 1000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    final gcash = Wallet(
      id: 'w2',
      name: 'My GCash',
      type: WalletType.gcash,
      balance: 2000,
      startingBalance: 2000,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
    );

    final partlyPaid = BillInstance(
      id: 'b1_20260305',
      billId: 'b1',
      name: 'Rent',
      amount: 3000,
      category: 'Bills',
      dueDate: DateTime(2026, 3, 5),
      status: BillStatus.partial,
      amountPaid: 1800,
      paymentIds: const ['t1', 't2'],
    );

    AppTransaction payment({
      required String id,
      required double amount,
      required String walletId,
      required DateTime date,
    }) {
      return AppTransaction(
        id: id,
        type: TransactionType.expense,
        amount: amount,
        label: 'Bills',
        date: date,
        walletId: walletId,
        note: 'Rent',
      );
    }

    Future<void> pumpDetail(WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 1900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: BillDetailScreen(
              instance: partlyPaid,
              today: today,
              liveInstance: Stream.value(partlyPaid),
              history: Stream.value([partlyPaid]),
              bills: Stream.value(const []),
              wallets: Stream.value([cash, gcash]),
              loadPayments: (instance) async => [
                payment(
                  id: 't1',
                  amount: 1000,
                  walletId: 'w1',
                  date: DateTime(2026, 3, 5),
                ),
                payment(
                  id: 't2',
                  amount: 800,
                  walletId: 'w2',
                  date: DateTime(2026, 3, 6),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('each payment says which wallet it came out of', (
      tester,
    ) async {
      await pumpDetail(tester);

      expect(find.text('From Cash'), findsOneWidget);
      expect(find.text('From My GCash'), findsOneWidget);
      expect(find.text('₱1,000.00'), findsOneWidget);
      expect(find.text('₱800.00'), findsOneWidget);
      expect(find.text('Mar 5, 2026'), findsOneWidget);
      expect(find.text('Mar 6, 2026'), findsOneWidget);
    });

    testWidgets('the bill still shows what is left after both payments', (
      tester,
    ) async {
      await pumpDetail(tester);

      expect(find.text('Paid ₱1800.00'), findsOneWidget);
      expect(find.text('₱1200.00 to go'), findsOneWidget);
    });

    testWidgets('one payment can be undone without touching the other', (
      tester,
    ) async {
      await pumpDetail(tester);

      await tester.tap(find.byTooltip('Undo this payment').first);
      await tester.pumpAndSettle();

      expect(find.text('Undo this payment?'), findsOneWidget);
      expect(
        find.textContaining('goes back to Cash'),
        findsOneWidget,
        reason: 'names the wallet that particular payment came from',
      );
    });
  });

  group('button colour rule', () {
    Color? fillOf(ButtonStyle style) =>
        style.backgroundColor?.resolve(const <WidgetState>{});

    test('green commits, red destroys, blue only opens', () {
      expect(fillOf(confirmButtonStyle()), appConfirmGreen);
      expect(fillOf(dangerButtonStyle()), appDangerRed);
      expect(fillOf(openButtonStyle()), appPrimaryBlue);
    });

    test('the three meanings never share a colour', () {
      final colors = {appConfirmGreen, appDangerRed, appPrimaryBlue};

      expect(colors.length, 3);
    });

    Future<List<Color>> colorsUnder(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      late Color confirm;
      late Color danger;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              confirm = confirmColorOn(context);
              danger = dangerColorOn(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      return [confirm, danger];
    }

    testWidgets('cancel is red too, like the other ways of backing out', (
      tester,
    ) async {
      late Color cancel;
      late Color danger;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              cancel = cancelTextStyle(
                context,
              ).foregroundColor!.resolve(const <WidgetState>{})!;
              danger = dangerTextStyle(
                context,
              ).foregroundColor!.resolve(const <WidgetState>{})!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(cancel, danger);
    });

    testWidgets('light mode uses the solid green and red', (tester) async {
      final colors = await colorsUnder(tester, AppTheme.light);

      expect(colors, [appConfirmGreen, appDangerRed]);
    });

    testWidgets('dark mode lightens them so they stay readable', (
      tester,
    ) async {
      final colors = await colorsUnder(tester, AppTheme.dark);

      expect(colors[0], isNot(appConfirmGreen));
      expect(colors[1], isNot(appDangerRed));
    });
  });

  group('income allocation', () {
    final today = DateTime(2026, 3, 10);

    BillInstance bill({
      required String id,
      double amount = 1000,
      double amountPaid = 0,
      BillStatus status = BillStatus.unpaid,
      DateTime? dueDate,
    }) {
      return BillInstance(
        id: id,
        billId: 'b',
        name: id,
        amount: amount,
        category: 'Bills',
        dueDate: dueDate ?? DateTime(2026, 3, 15),
        status: status,
        amountPaid: amountPaid,
      );
    }

    test('each bill starts on paying what it still owes', () {
      final partly = bill(id: 'Rent', amount: 3000, amountPaid: 1000);

      expect(BillAllocation.full(partly).amount, 2000);
    });

    test('what is left is the income less the bills paid', () {
      final plan = AllocationPlan(
        income: 5000,
        bills: [
          BillAllocation.full(bill(id: 'Rent', amount: 3000)),
          BillAllocation.full(bill(id: 'Load', amount: 500)),
        ],
      );

      expect(plan.toBills, 3500);
      expect(plan.remaining, 1500);
      expect(plan.dipsIntoSavings, isFalse);
      expect(plan.problems, isEmpty);
    });

    test('skipped bills and bills left at zero cost nothing', () {
      final plan = AllocationPlan(
        income: 5000,
        bills: [
          BillAllocation.full(
            bill(id: 'Rent', amount: 3000),
          ).copyWith(skipped: true),
          BillAllocation.full(
            bill(id: 'Load', amount: 500),
          ).copyWith(amount: 0),
        ],
      );

      expect(plan.toBills, 0);
      expect(plan.remaining, 5000);
    });

    test('paying more bills than came in is allowed but flagged', () {
      final plan = AllocationPlan(
        income: 1000,
        bills: [BillAllocation.full(bill(id: 'Rent', amount: 3000))],
      );

      expect(plan.remaining, -2000);
      expect(
        plan.dipsIntoSavings,
        isTrue,
        reason: 'the rest comes from money already in the wallet',
      );
      expect(plan.problems, isEmpty);
    });

    test('a bill cannot be overpaid', () {
      final plan = AllocationPlan(
        income: 5000,
        bills: [
          BillAllocation.full(
            bill(id: 'Rent', amount: 3000),
          ).copyWith(amount: 3500),
        ],
      );

      expect(plan.problems, ['Rent only needs ₱3,000.00.']);
    });

    test('no income means nothing can be confirmed', () {
      expect(const AllocationPlan(income: 0).problems, [
        'Enter how much came in.',
      ]);
    });

    test('only open bills due within the month ahead are offered', () {
      final offered = outstandingBills([
        bill(id: 'overdue', dueDate: DateTime(2026, 2, 20)),
        bill(id: 'soon', dueDate: DateTime(2026, 3, 12)),
        bill(id: 'next month', dueDate: DateTime(2026, 4, 8)),
        bill(id: 'too far', dueDate: DateTime(2026, 5, 20)),
        bill(
          id: 'paid',
          amountPaid: 1000,
          status: BillStatus.paid,
          dueDate: DateTime(2026, 3, 11),
        ),
        bill(
          id: 'skipped',
          status: BillStatus.skipped,
          dueDate: DateTime(2026, 3, 11),
        ),
        bill(
          id: 'partly',
          amountPaid: 400,
          status: BillStatus.partial,
          dueDate: DateTime(2026, 3, 14),
        ),
      ], now: today);

      expect(offered.map((bill) => bill.id), [
        'overdue',
        'soon',
        'partly',
        'next month',
      ]);
    });
  });
}
