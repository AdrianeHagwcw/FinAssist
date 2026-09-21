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
import 'package:testapp/models/debt.dart';
import 'package:testapp/models/goal.dart';
import 'package:testapp/models/onboarding_data.dart';
import 'package:testapp/models/safe_to_spend.dart';
import 'package:testapp/models/report.dart';
import 'package:testapp/models/reminder.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/models/transaction_filter.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/bill_calendar_screen.dart';
import 'package:testapp/screens/bill_detail_screen.dart';
import 'package:testapp/screens/chatbot_screen.dart';
import 'package:testapp/screens/debt_detail_screen.dart';
import 'package:testapp/screens/debts_screen.dart';
import 'package:testapp/screens/financial_setup_screen.dart';
import 'package:testapp/screens/forgot_password_screen.dart';
import 'package:testapp/screens/goals_screen.dart';
import 'package:testapp/screens/income_waterfall_screen.dart';
import 'package:testapp/screens/leftover_review_screen.dart';
import 'package:testapp/screens/main_shell.dart';
import 'package:testapp/screens/home_screen.dart';
import 'package:testapp/screens/reports_screen.dart';
import 'package:testapp/screens/reminders_screen.dart';
import 'package:testapp/widgets/quick_add_sheet.dart';
import 'package:testapp/screens/splash_screen.dart';
import 'package:testapp/services/launch_screen.dart';
import 'package:testapp/screens/transactions_screen.dart';
import 'package:testapp/screens/wallet_detail_screen.dart';
import 'package:testapp/screens/wallets_screen.dart';
import 'package:testapp/services/legacy_migration.dart';
import 'package:testapp/services/ledger_service.dart';
import 'package:testapp/services/budget_service.dart';
import 'package:testapp/theme/app_buttons.dart';
import 'package:testapp/theme/app_colors.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/widgets/app_logo.dart';
import 'package:testapp/widgets/back_to_home.dart';
import 'package:testapp/widgets/bill_payment_sheet.dart';
import 'package:testapp/widgets/goal_sheets.dart';
import 'package:testapp/widgets/legacy_import_card.dart';
import 'package:testapp/widgets/light_dark_toggle.dart';
import 'package:testapp/utils/date_format.dart';
import 'package:testapp/utils/categories.dart';
import 'package:testapp/utils/money_format.dart';
import 'package:testapp/widgets/money_text.dart';
import 'package:testapp/widgets/debt_form_sheet.dart';
import 'package:testapp/widgets/due_soon_notice.dart';
import 'package:testapp/widgets/savings_guide.dart';
import 'package:testapp/widgets/safe_to_spend_card.dart';
import 'package:testapp/widgets/spending_chart.dart';
import 'package:testapp/widgets/transaction_edit_sheet.dart';
import 'package:testapp/widgets/transaction_row.dart';
import 'package:testapp/widgets/transfer_sheet.dart';
import 'package:testapp/widgets/wallet_picker.dart';

void main() {
  testWidgets('signed-out users go straight to log in', (
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
    await tester.pump();

    // Android's launch screen shows the logo, so there is no welcome page.
    expect(find.text('Welcome to FinAssist'), findsNothing);
    expect(find.text('Get Started'), findsNothing);
    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Facebook'), findsNothing);
  });

  testWidgets('the launch screen stays up until the first screen is ready', (
    tester,
  ) async {
    final session = Completer<StartDestination>();
    LaunchScreen.hold();
    addTearDown(LaunchScreen.release);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MyApp(
          home: SplashScreen(resolveDestination: () => session.future),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(LaunchScreen.isHolding, isTrue);

    session.complete(StartDestination.signedOut);
    await tester.pump();
    expect(LaunchScreen.isHolding, isFalse);
    expect(find.text('Welcome Back!'), findsOneWidget);
  });

  testWidgets('a slow start shows the logo and a loading ring in the saved '
      'theme', (tester) async {
    final settings = AppSettingsProvider();
    settings.setThemeMode(ThemeMode.dark);
    final session = Completer<StartDestination>();
    LaunchScreen.hold();
    addTearDown(LaunchScreen.release);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MyApp(
          home: SplashScreen(resolveDestination: () => session.future),
        ),
      ),
    );

    // The launch screen gives way after its limit, so the wait never looks
    // frozen.
    await tester.pump(SplashScreen.launchScreenLimit);
    expect(LaunchScreen.isHolding, isFalse);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppColors.dark.card,
      reason: 'the colour of the dark launch screen, for anyone who chose dark',
    );

    session.complete(StartDestination.signedOut);
    await tester.pump();
    expect(find.text('Welcome Back!'), findsOneWidget);
  });

  testWidgets('choosing a theme sets the next launch screen straight away', (
    tester,
  ) async {
    final sent = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      LaunchScreen.channel,
      (call) async {
        sent.add('${call.method} ${call.arguments}');
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LaunchScreen.channel,
        null,
      ),
    );

    final settings = AppSettingsProvider();
    settings.setThemeMode(ThemeMode.dark);
    settings.setThemeMode(ThemeMode.dark);
    settings.setThemeMode(ThemeMode.light);
    await tester.pump();

    // Once per real change, and before the app is ever closed.
    expect(sent, ['setDark true', 'setDark false']);
  });

  testWidgets('log in has a spoken label on every tappable control', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
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
    await tester.pumpAndSettle();

    // The eye beside the password says what it does, and says the opposite
    // once pressed.
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('start shows retry when the session check fails', (tester) async {
    LaunchScreen.hold();
    addTearDown(LaunchScreen.release);

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
    await tester.pump();

    expect(LaunchScreen.isHolding, isFalse, reason: 'the problem is shown');
    expect(find.text('We could not load your profile'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
  });

  group('formatPeso', () {
    test('uses peso sign and thousands separators, centavos only if any', () {
      expect(formatPeso(12500), '₱12,500');
      expect(formatPeso(20000.001), '₱20,000');
      expect(formatPeso(0.5), '₱0.50');
      expect(formatPeso(150.05), '₱150.05');
      expect(formatPeso(1234567.891), '₱1,234,567.89');
      expect(formatPeso(0), '₱0');
      expect(formatPeso(-0.001), '₱0', reason: 'no minus on zero');
    });

    test('amounts start out in fields without needless centavos', () {
      expect(formatAmountInput(20000), '20000');
      expect(formatAmountInput(150.5), '150.50');
      expect(formatAmountInput(0.1 + 0.2), '0.30');
      expect(formatAmountInput(1583.3333), '1583.33');
    });

    test('puts signs before the peso symbol', () {
      expect(formatPeso(-250), '-₱250');
      expect(formatPeso(500, sign: '+'), '+₱500');
      expect(formatPeso(500, sign: '-'), '-₱500');
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
    expect(find.text('₱1,500'), findsOneWidget);

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

    testWidgets('each tab has a back arrow that returns to Home', (
      tester,
    ) async {
      Widget tab(String title) => Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            automaticallyImplyLeading: false,
            leading: backToHomeButton(context),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainShell(
            pages: [
              const Text('Home page'),
              tab('Transactions page'),
              tab('Goals page'),
              tab('Wallet page'),
            ],
            quickAddActions: const [],
          ),
        ),
      );

      await tester.tap(find.text('Wallet'));
      await tester.pump();
      final back = find.byTooltip('Back to Home').hitTestable();
      expect(back, findsOneWidget);

      await tester.tap(back);
      await tester.pump();
      expect(find.text('Home page').hitTestable(), findsOneWidget);
    });

    testWidgets('a tab shown on its own has no back arrow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) =>
                Scaffold(appBar: AppBar(leading: backToHomeButton(context))),
          ),
        ),
      );

      expect(find.byTooltip('Back to Home'), findsNothing);
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
      bool allowNotifications = true,
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
              requestReminderPermission: () async => allowNotifications,
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

    testWidgets('a blocked notification prompt still moves on', (tester) async {
      await pumpOnboarding(
        tester,
        save: (_) async {},
        allowNotifications: false,
      );

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');
      await tapText(tester, 'Allow Reminders');

      expect(find.text('Step 4 of 5'), findsOneWidget);
    });

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
      expect(find.text('₱300'), findsOneWidget);
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
    /// One wallet with ₱3,000 and nothing else recorded yet.
    final starter = FinanceSnapshot(
      now: DateTime(2026, 9, 19, 10),
      wallets: const [
        Wallet(
          id: 'cash',
          name: 'Cash',
          type: WalletType.cash,
          balance: 3000,
          startingBalance: 3000,
          receivesIncome: true,
          archived: false,
          sortOrder: 0,
        ),
      ],
    );

    Future<void> pumpChat(
      WidgetTester tester,
      Stream<bool> online, {
      FinanceSnapshot? records,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ChatbotScreen(
            onlineStatus: online,
            records: Stream.value(records ?? starter),
          ),
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

    testWidgets('offline, it still answers from the records on the phone', (
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
        find.textContaining('Answers use the records saved on this phone'),
        findsOneWidget,
      );

      await ask(tester, 'How much money do I have?');
      expect(find.textContaining('₱3,000 across 1 wallet'), findsOneWidget);
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
        find.textContaining('Start by recording every expense'),
        findsOneWidget,
      );
    });

    testWidgets('asks which one, offers quick replies, then answers', (
      tester,
    ) async {
      await pumpChat(tester, Stream.value(true));

      await ask(tester, 'Can I buy AirPods?');
      expect(find.textContaining('Which AirPods'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'AirPods Pro'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'Any brand'));
      await tester.pump(const Duration(milliseconds: 800));
      // Nothing is due and nothing is usually spent yet, so all ₱3,000 is
      // spare before payday (Oct 1, the calendar month's end).
      expect(
        find.textContaining(
          'the most you can spend on the AirPods is about ₱3,000',
        ),
        findsOneWidget,
      );
      // The earlier choices are gone once answered.
      expect(find.widgetWithText(ActionChip, 'AirPods Pro'), findsNothing);
    });

    testWidgets('suggests a goal when something does not fit yet', (
      tester,
    ) async {
      await pumpChat(tester, Stream.value(true));

      await ask(tester, 'Can I buy a laptop for 40000 this month?');
      expect(find.textContaining("It doesn't fit this month"), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Create Goal'),
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
      expect(find.text('₱1,200'), findsOneWidget);
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
      expect(find.text('₱1,200'), findsOneWidget);
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
      expect(find.text('-₱200'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('the same transfer reads as money into the wallet it reached', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: gcash, transactions: [transfer()]);

      expect(find.text('From Cash'), findsOneWidget);
      expect(find.text('+₱200'), findsOneWidget);
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

    test('one expense, read on four different days', () {
      // The same record, never edited. Only the day it is read on changes.
      final spent = DateTime(2026, 9, 16, 19, 42);

      expect(
        transactionDateLabel(spent, now: DateTime(2026, 9, 16, 23, 59)),
        'Today',
      );
      expect(
        transactionDateLabel(spent, now: DateTime(2026, 9, 17, 0, 1)),
        'Yesterday',
      );
      expect(
        transactionDateLabel(spent, now: DateTime(2026, 9, 18, 8)),
        'Sep 16, 2026',
      );
      expect(
        transactionDateLabel(spent, now: DateTime(2027, 1, 5)),
        'Sep 16, 2026',
        reason: 'the year keeps it from being read as this September',
      );

      // The time it was recorded at never moves, whatever day it is read on.
      expect(formatTransactionTime(spent), '7:42 PM');
    });

    test('a time is shown only when the record carries one', () {
      // Midnight is what the calendar picker leaves behind on a back-dated
      // entry, so it means no time was given rather than 12:00 AM.
      expect(formatTransactionTime(DateTime(2026, 9, 16)), isNull);
      expect(formatTransactionTime(DateTime(2026, 9, 16, 0, 0)), isNull);

      expect(formatTransactionTime(DateTime(2026, 9, 16, 0, 30)), '12:30 AM');
      expect(formatTransactionTime(DateTime(2026, 9, 16, 9, 7)), '9:07 AM');
      expect(formatTransactionTime(DateTime(2026, 9, 16, 12, 0)), '12:00 PM');
      expect(formatTransactionTime(DateTime(2026, 9, 16, 13, 5)), '1:05 PM');
      expect(formatTransactionTime(DateTime(2026, 9, 16, 23, 59)), '11:59 PM');
    });

    test('choosing a date keeps the time already on the entry', () {
      // A date picker hands back midnight. Picking today's date just to
      // check it must not turn 12:30 PM into 12:00 AM.
      final entry = DateTime(2026, 9, 16, 12, 30);

      expect(
        keepTimeOfDay(DateTime(2026, 9, 16), entry),
        DateTime(2026, 9, 16, 12, 30),
      );
      expect(
        keepTimeOfDay(DateTime(2026, 9, 11), entry),
        DateTime(2026, 9, 11, 12, 30),
        reason: 'back-dated, same time of day',
      );
      // An entry that never had a time keeps not having one.
      expect(
        keepTimeOfDay(DateTime(2026, 9, 11), DateTime(2026, 9, 16)),
        DateTime(2026, 9, 11),
      );
      expect(
        formatTransactionTime(
          keepTimeOfDay(DateTime(2026, 9, 11), DateTime(2026, 9, 16)),
        ),
        isNull,
      );
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

      expect(find.text('Cash holds ₱500'), findsOneWidget);
      expect(find.textContaining('Your total stays the same'), findsOneWidget);
    });

    testWidgets('refuses to move more money than the wallet holds', (
      tester,
    ) async {
      await pumpTransfer(tester, wallets: [cash, gcash]);

      await tester.enterText(find.byType(TextFormField).first, '800');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Transfer'));
      await tester.pump();

      expect(find.text('Cash only holds ₱500.'), findsOneWidget);
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
      List<Goal> goals = const [],
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
            goals: Stream.value(goals),
            cycles: Stream.value(const []),
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

      expect(find.text('Step 1 of 2'), findsOneWidget);
      await next(tester);

      expect(find.text('Enter how much came in.'), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);
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

      // Only two steps: nothing to pay and no goals to save for.
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.text('₱2,000'), findsOneWidget);
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
      expect(find.text('1500'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.text('Left after these bills'), findsOneWidget);
      expect(find.text('₱3,200'), findsOneWidget);
    });

    testWidgets('a bill cannot be paid more than it owes', (tester) async {
      await pumpWaterfall(tester, bills: [bill('Rent', 1500)]);

      await fillIncome(tester, '5000');
      await next(tester);

      await tester.enterText(find.widgetWithText(TextField, '1500'), '2000');
      await next(tester);

      expect(find.text('Rent only needs ₱1,500.'), findsOneWidget);
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
      expect(find.text('₱3,500'), findsOneWidget);

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
      expect(find.text('₱4,500'), findsOneWidget, reason: 'due this month');
      expect(find.text('₱3,000'), findsWidgets, reason: 'still owing');
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
      expect(find.text('₱2,000'), findsWidgets, reason: 'still owed');
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
      expect(find.text('₱3,000'), findsOneWidget);
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

      expect(find.text('Paid ₱1,200'), findsOneWidget);
      expect(find.text('₱1,800 to go'), findsOneWidget);
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

    testWidgets('a bill whose unpaid part moved on cannot be paid again', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        current: BillInstance(
          id: 'b1_20260305',
          billId: 'b1',
          name: 'Rent',
          amount: 3000,
          category: 'Bills',
          dueDate: DateTime(2026, 3, 5),
          status: BillStatus.partial,
          amountPaid: 1000,
          carriedInto: 'b1_20260405',
        ),
      );

      expect(find.text('Moved to next'), findsWidgets);
      expect(
        find.text(
          'The unpaid ₱2,000 moved to the next due date of this bill, so it '
          'is paid there.',
        ),
        findsOneWidget,
      );
      expect(find.text('Rest moved to the next bill'), findsOneWidget);
      expect(find.text('Mark as Paid'), findsNothing);
      expect(find.text('Pay part of it'), findsNothing);
      expect(find.text('Undo payment'), findsNothing);
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

      expect(find.text('3000'), findsOneWidget);
      expect(find.text('₱3,000 still owing'), findsOneWidget);
    });

    testWidgets('starts empty when paying only part of it', (tester) async {
      await pumpSheet(tester, payInFull: false);

      expect(find.text('3000'), findsNothing);
    });

    testWidgets('refuses to pay more than the bill needs', (tester) async {
      await pumpSheet(tester, payInFull: false);

      await tester.enterText(find.byType(TextFormField), '5000');
      await tester.tap(find.text('Record Payment'));
      await tester.pump();

      expect(find.text('This bill only needs ₱3,000.'), findsOneWidget);
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
      expect(find.text('₱1,000'), findsOneWidget);
      expect(find.text('₱800'), findsOneWidget);
      expect(find.text('Mar 5, 2026'), findsOneWidget);
      expect(find.text('Mar 6, 2026'), findsOneWidget);
    });

    testWidgets('the bill still shows what is left after both payments', (
      tester,
    ) async {
      await pumpDetail(tester);

      expect(find.text('Paid ₱1,800'), findsOneWidget);
      expect(find.text('₱1,200 to go'), findsOneWidget);
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

      expect(plan.problems, ['Rent only needs ₱3,000.']);
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

  group('transaction filters', () {
    AppTransaction t(
      String id, {
      TransactionType type = TransactionType.expense,
      String label = 'Food',
      String? walletId = 'cash',
      String? toWalletId,
      DateTime? date,
      double amount = 100,
    }) {
      return AppTransaction(
        id: id,
        type: type,
        amount: amount,
        label: label,
        date: date ?? DateTime(2026, 3, 10, 12),
        walletId: walletId,
        toWalletId: toWalletId,
      );
    }

    test('a wallet filter keeps transfers into and out of it', () {
      const filter = TransactionFilter(walletId: 'gcash');
      final list = [
        t('a', walletId: 'cash'),
        t('b', walletId: 'gcash'),
        t(
          'c',
          type: TransactionType.transfer,
          walletId: 'cash',
          toWalletId: 'gcash',
        ),
      ];

      expect(list.where(filter.matches).map((x) => x.id), ['b', 'c']);
    });

    test('category matching ignores capitalisation', () {
      expect(const TransactionFilter(category: 'food').matches(t('a')), isTrue);
    });

    test('a date range includes both of its end days', () {
      final filter = TransactionFilter(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
      );

      expect(filter.matches(t('a', date: DateTime(2026, 3, 10, 23))), isTrue);
      expect(filter.matches(t('b', date: DateTime(2026, 3, 1))), isTrue);
      expect(filter.matches(t('c', date: DateTime(2026, 3, 11))), isFalse);
    });

    test('money in and out leave transfers out of both', () {
      final totals = inAndOut([
        t('a', amount: 200),
        t('b', type: TransactionType.income, amount: 1000),
        t(
          'c',
          type: TransactionType.transfer,
          amount: 5000,
          toWalletId: 'gcash',
        ),
      ]);

      expect(totals.moneyIn, 1000);
      expect(totals.moneyOut, 200);
    });

    test('spending by category counts expenses only, largest first', () {
      final result = spendingByCategory([
        t('a', label: 'Food', amount: 100),
        t('b', label: 'Bills', amount: 900),
        t('c', label: 'Food', amount: 150),
        t('d', type: TransactionType.income, label: 'Allowance', amount: 9999),
        AppTransaction(
          id: 'e',
          type: TransactionType.expense,
          amount: 500,
          label: 'Lent',
          date: DateTime(2026, 3, 10, 12),
          walletId: 'cash',
          debtId: 'ana',
        ),
      ]);

      expect(result.map((e) => '${e.key}=${e.value}'), [
        'Bills=900.0',
        'Food=250.0',
      ], reason: 'money lent out is not spending');
    });
  });

  group('Transactions screen', () {
    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 1000,
      startingBalance: 1000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    final gcash = Wallet(
      id: 'gcash',
      name: 'GCash',
      type: WalletType.gcash,
      balance: 1000,
      startingBalance: 1000,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
    );

    Future<void> pumpList(
      WidgetTester tester,
      List<AppTransaction> transactions, {
      void Function(AppTransaction)? onOpen,
    }) async {
      tester.view.physicalSize = const Size(700, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: TransactionsScreen(
              transactions: Stream.value(transactions),
              wallets: Stream.value([cash, gcash]),
              showLegacyImport: false,
              onOpen: onOpen,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final now = DateTime.now();

    testWidgets('shows an empty state with nothing recorded', (tester) async {
      await pumpList(tester, const []);

      expect(find.text('No transactions yet'), findsOneWidget);
    });

    testWidgets('lists every kind, with transfers naming both wallets', (
      tester,
    ) async {
      await pumpList(tester, [
        AppTransaction(
          id: 'e',
          type: TransactionType.expense,
          amount: 120,
          label: 'Food',
          date: now,
          walletId: 'cash',
        ),
        AppTransaction(
          id: 'i',
          type: TransactionType.income,
          amount: 2000,
          label: 'Allowance',
          date: now,
          walletId: 'gcash',
        ),
        AppTransaction(
          id: 't',
          type: TransactionType.transfer,
          amount: 300,
          label: 'Transfer',
          date: now,
          walletId: 'cash',
          toWalletId: 'gcash',
        ),
      ]);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Allowance'), findsOneWidget);
      expect(find.text('Cash → GCash'), findsOneWidget);
      expect(find.text('-₱120'), findsOneWidget);
      expect(find.text('+₱2,000'), findsWidgets);
      expect(find.text('₱300'), findsOneWidget);
    });

    testWidgets('marks bill payments and records from before wallets', (
      tester,
    ) async {
      await pumpList(tester, [
        AppTransaction(
          id: 'b',
          type: TransactionType.expense,
          amount: 3000,
          label: 'Bills',
          date: now,
          walletId: 'cash',
          note: 'Rent',
          billInstanceId: 'rent_1',
        ),
        AppTransaction(
          id: 'l',
          type: TransactionType.expense,
          amount: 50,
          label: 'Food',
          date: now,
          isLegacy: true,
        ),
      ]);

      // The row now leads with the time it was recorded, which moves with
      // the clock, so the parts that carry meaning are what is checked.
      expect(
        find.textContaining('Cash · Bill payment · Rent'),
        findsOneWidget,
      );
      expect(find.textContaining('Before wallets'), findsOneWidget);
    });

    testWidgets('tapping a transaction opens it', (tester) async {
      AppTransaction? opened;
      await pumpList(tester, [
        AppTransaction(
          id: 'e',
          type: TransactionType.expense,
          amount: 120,
          label: 'Food',
          date: now,
          walletId: 'cash',
        ),
      ], onOpen: (t) => opened = t);

      await tester.tap(find.text('Food'));
      expect(opened?.id, 'e');
    });

    testWidgets('the category breakdown narrows the list', (tester) async {
      await pumpList(tester, [
        AppTransaction(
          id: 'a',
          type: TransactionType.expense,
          amount: 120,
          label: 'Food',
          date: now,
          walletId: 'cash',
        ),
        AppTransaction(
          id: 'b',
          type: TransactionType.expense,
          amount: 80,
          label: 'Transportation',
          date: now,
          walletId: 'cash',
        ),
      ]);

      await tester.tap(find.byTooltip('Spending by category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transportation').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing:'), findsOneWidget);
      expect(find.text('Food'), findsNothing);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Food'), findsOneWidget);
    });
  });

  group('Transaction edit sheet', () {
    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 1000,
      startingBalance: 1000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );

    Future<void> pumpSheet(
      WidgetTester tester,
      AppTransaction transaction, {
      void Function(double amount)? onSave,
      VoidCallback? onDelete,
    }) async {
      tester.view.physicalSize = const Size(700, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TransactionEditSheet(
              transaction: transaction,
              wallets: Stream.value([cash]),
              onSave:
                  ({
                    required double amount,
                    required String label,
                    required String? walletId,
                    required String? toWalletId,
                    required String? note,
                    required DateTime date,
                  }) => onSave?.call(amount),
              onDelete: onDelete,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('an ordinary expense can be edited', (tester) async {
      double? saved;
      await pumpSheet(
        tester,
        AppTransaction(
          id: 'e',
          type: TransactionType.expense,
          amount: 120,
          label: 'Food',
          date: DateTime(2026, 3, 10),
          walletId: 'cash',
        ),
        onSave: (amount) => saved = amount,
      );

      await tester.enterText(find.byType(TextField).first, '150');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(saved, 150);
    });

    testWidgets('a bill payment is changed from its bill, not here', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        AppTransaction(
          id: 'b',
          type: TransactionType.expense,
          amount: 3000,
          label: 'Bills',
          date: DateTime(2026, 3, 10),
          walletId: 'cash',
          billInstanceId: 'rent_1',
        ),
      );

      expect(find.textContaining('Change it from the bill'), findsOneWidget);
      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('deleting asks first and explains what happens', (
      tester,
    ) async {
      var deleted = false;
      await pumpSheet(
        tester,
        AppTransaction(
          id: 'l',
          type: TransactionType.expense,
          amount: 50,
          label: 'Food',
          date: DateTime(2026, 3, 10),
          isLegacy: true,
        ),
        onDelete: () => deleted = true,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No balance changes'), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });
  });

  group('pay periods', () {
    test('semi-monthly splits on the 15th', () {
      final early = payPeriodFor('Semi-monthly', now: DateTime(2026, 3, 10));
      final late = payPeriodFor('Semi-monthly', now: DateTime(2026, 3, 20));

      expect(early.start, DateTime(2026, 3, 1));
      expect(early.end, DateTime(2026, 3, 16));
      expect(early.daysLeft(DateTime(2026, 3, 10)), 6);
      expect(late.start, DateTime(2026, 3, 16));
      expect(late.end, DateTime(2026, 4, 1));
    });

    test('a monthly income runs from the day it arrived', () {
      final period = payPeriodFor(
        'Monthly',
        lastIncomeAt: DateTime(2026, 3, 7),
        now: DateTime(2026, 3, 20),
      );

      expect(period.start, DateTime(2026, 3, 7));
      expect(period.end, DateTime(2026, 4, 7));
    });

    test('an allowance on the 31st does not drift through February', () {
      final anchor = DateTime(2026, 1, 31);

      final feb = payPeriodFor(
        'Monthly',
        lastIncomeAt: anchor,
        now: DateTime(2026, 3, 1),
      );
      expect(feb.start, DateTime(2026, 2, 28));
      expect(feb.end, DateTime(2026, 3, 31));

      final april = payPeriodFor(
        'Monthly',
        lastIncomeAt: anchor,
        now: DateTime(2026, 4, 5),
      );
      expect(april.start, DateTime(2026, 3, 31));
      expect(april.end, DateTime(2026, 4, 30));
    });

    test('weekly periods follow the day income arrived', () {
      final period = payPeriodFor(
        'Weekly',
        lastIncomeAt: DateTime(2026, 3, 4),
        now: DateTime(2026, 3, 19),
      );

      expect(period.start, DateTime(2026, 3, 18));
      expect(period.end, DateTime(2026, 3, 25));
    });

    test('with nothing to go on, a month is a calendar month', () {
      final period = payPeriodFor('Irregular', now: DateTime(2026, 2, 14));

      expect(period.start, DateTime(2026, 2, 1));
      expect(period.end, DateTime(2026, 3, 1));
      expect(period.daysLeft(DateTime(2026, 2, 28)), 1);
      expect(period.isLastDay(DateTime(2026, 2, 28)), isTrue);
    });
  });

  group('safe to spend', () {
    test('bills and savings come off before sharing over the days left', () {
      const s = SafeToSpend(
        walletBalance: 10000,
        billsDue: 3000,
        savingsReserve: 1000,
        spentToday: 0,
        daysLeft: 10,
      );

      expect(s.spendableThisPeriod, 6000);
      expect(s.recommendedDailyLimit, 600);
      expect(s.leftToday, 600);
    });

    test("spending today doesn't shrink today's own limit", () {
      // The balance already dropped by the 200 spent, so it is added back
      // before sharing out, and taken off once, from what is left today.
      const s = SafeToSpend(
        walletBalance: 5800,
        billsDue: 0,
        savingsReserve: 0,
        spentToday: 200,
        daysLeft: 10,
      );

      expect(s.dailyLimit, 600);
      expect(s.leftToday, 400);
      expect(s.usedFraction, closeTo(1 / 3, 0.001));
    });

    test('a limit the user set is used instead of the recommendation', () {
      const s = SafeToSpend(
        walletBalance: 5000,
        billsDue: 0,
        savingsReserve: 0,
        spentToday: 350,
        daysLeft: 5,
        customDailyLimit: 300,
      );

      expect(s.dailyLimit, 300);
      expect(s.leftToday, -50);
      expect(s.isOverLimit, isTrue);
      expect(s.usedFraction, 1);
    });

    test('owing more than you have means nothing is safe to spend', () {
      const s = SafeToSpend(
        walletBalance: 1000,
        billsDue: 4000,
        savingsReserve: 0,
        spentToday: 0,
        daysLeft: 7,
      );

      expect(s.spendableThisPeriod, 0);
      expect(s.recommendedDailyLimit, 0);
    });

    test("bill payments and transfers aren't today's spending", () {
      final today = DateTime(2026, 3, 10);
      AppTransaction t(
        TransactionType type,
        double amount, {
        String? bill,
        DateTime? date,
      }) => AppTransaction(
        id: '$type$amount',
        type: type,
        amount: amount,
        label: 'x',
        date: date ?? today.add(const Duration(hours: 9)),
        walletId: 'w',
        toWalletId: type == TransactionType.transfer ? 'v' : null,
        billInstanceId: bill,
      );

      final spent = discretionarySpending(
        [
          t(TransactionType.expense, 120),
          t(TransactionType.expense, 3000, bill: 'rent'),
          t(TransactionType.transfer, 500),
          t(TransactionType.income, 999),
          t(TransactionType.expense, 80, date: DateTime(2026, 3, 9, 23)),
        ],
        from: today,
        until: today.add(const Duration(days: 1)),
      );

      expect(spent, 120);
    });

    test('only unpaid bills due before the period ends are counted', () {
      BillInstance b(double amount, DateTime due, [BillStatus? status]) =>
          BillInstance(
            id: '$amount',
            billId: 'b',
            name: 'b',
            amount: amount,
            category: 'Bills',
            dueDate: due,
            status: status ?? BillStatus.unpaid,
          );

      final total = billsDueBefore([
        b(1000, DateTime(2026, 3, 5)),
        b(500, DateTime(2026, 3, 20)),
        b(700, DateTime(2026, 4, 2)),
        b(900, DateTime(2026, 3, 12), BillStatus.skipped),
      ], DateTime(2026, 4, 1));

      expect(total, 1500);
    });

    test('an older profile limit counts as one the user chose', () {
      expect(customDailyLimitFrom({'dailyBudget': 250}), 250);
      expect(
        customDailyLimitFrom({
          'dailyBudget': 250,
          'dailyLimitMode': 'recommended',
        }),
        isNull,
      );
      expect(customDailyLimitFrom(null), isNull);
      expect(savingsReserveFrom({'savingsReserve': -5}), 0);
    });
  });

  group('leftover review', () {
    AllocationCycle cycle({
      double remaining = 2000,
      DateTime? receivedAt,
      LeftoverDecision? decision,
    }) {
      return AllocationCycle(
        id: 'c',
        income: 5000,
        remaining: remaining,
        receivedAt: receivedAt ?? DateTime(2026, 3, 1),
        source: 'Allowance',
        decision: decision,
      );
    }

    test('is due on the last day of the period, not before', () {
      final cycles = [cycle()];

      expect(
        cycleAwaitingReview(cycles, 'Semi-monthly', now: DateTime(2026, 3, 10)),
        isNull,
      );
      expect(
        cycleAwaitingReview(cycles, 'Semi-monthly', now: DateTime(2026, 3, 15)),
        isNotNull,
      );
    });

    test('a decided leftover is not asked about again, a deferred one is', () {
      final late = DateTime(2026, 3, 20);

      expect(
        cycleAwaitingReview(
          [cycle(decision: LeftoverDecision.saved)],
          'Semi-monthly',
          now: late,
        ),
        isNull,
      );
      expect(
        cycleAwaitingReview(
          [cycle(decision: LeftoverDecision.pending)],
          'Semi-monthly',
          now: late,
        ),
        isNotNull,
      );
    });

    test("the leftover is what bills left, less the period's spending", () {
      final c = cycle(remaining: 2000);
      final period = periodOf(c, 'Semi-monthly');

      final leftover = leftoverOf(c, [
        AppTransaction(
          id: 'a',
          type: TransactionType.expense,
          amount: 700,
          label: 'Food',
          date: DateTime(2026, 3, 6),
          walletId: 'w',
        ),
        AppTransaction(
          id: 'late',
          type: TransactionType.expense,
          amount: 5000,
          label: 'Food',
          date: DateTime(2026, 3, 16),
          walletId: 'w',
        ),
      ], period);

      expect(leftover, 1300);
    });

    Future<void> pumpReview(
      WidgetTester tester, {
      required void Function(LeftoverDecision, double, double) onResolve,
    }) async {
      tester.view.physicalSize = const Size(700, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: LeftoverReviewScreen(
              cycle: cycle(),
              leftover: 1000,
              periodEnd: DateTime(2026, 3, 16),
              onResolve: onResolve,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('asks for a choice before confirming', (tester) async {
      LeftoverDecision? decided;
      await pumpReview(tester, onResolve: (d, _, _) => decided = d);

      await tester.tap(find.text('Confirm'));
      await tester.pump();

      expect(find.text('Choose what to do with it first.'), findsOneWidget);
      expect(decided, isNull);
    });

    testWidgets('saving records the whole amount as saved', (tester) async {
      LeftoverDecision? decided;
      double? saved;
      await pumpReview(
        tester,
        onResolve: (d, s, _) {
          decided = d;
          saved = s;
        },
      );

      await tester.tap(find.text('Save it'));
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(decided, LeftoverDecision.saved);
      expect(saved, 1000);
    });

    testWidgets('a split must add up to the leftover', (tester) async {
      LeftoverDecision? decided;
      await pumpReview(tester, onResolve: (d, _, _) => decided = d);

      await tester.tap(find.text('Split it'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '800');
      await tester.tap(find.text('Confirm'));
      await tester.pump();

      expect(find.textContaining('must add up to ₱1,000'), findsOneWidget);
      expect(decided, isNull);

      await tester.enterText(find.byType(TextField).last, '200');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(decided, LeftoverDecision.split);
    });

    testWidgets('deciding later leaves it pending', (tester) async {
      LeftoverDecision? decided;
      await pumpReview(tester, onResolve: (d, _, _) => decided = d);

      await tester.tap(find.text('Decide later'));
      await tester.pumpAndSettle();

      expect(decided, LeftoverDecision.pending);
    });
  });

  group('Safe to Spend card', () {
    Future<void> pumpLimitSheet(
      WidgetTester tester,
      SafeToSpend safeToSpend,
      void Function(double?, double) onSave,
    ) {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: EditSafeToSpendSheet(
              safeToSpend: safeToSpend,
              onSave: onSave,
            ),
          ),
        ),
      );
    }

    testWidgets('the daily limit left empty uses the recommendation', (
      tester,
    ) async {
      double? limit = -1;
      await pumpLimitSheet(
        tester,
        const SafeToSpend(
          walletBalance: 1400,
          billsDue: 0,
          savingsReserve: 0,
          spentToday: 0,
          daysLeft: 14,
        ),
        (custom, _) => limit = custom,
      );

      expect(find.text('Use Recommendation'), findsNothing);
      expect(find.text('100'), findsOneWidget, reason: 'shown as the hint');

      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(limit, isNull);
    });

    testWidgets('a typed daily limit is saved as your own', (tester) async {
      double? limit;
      await pumpLimitSheet(
        tester,
        const SafeToSpend(
          walletBalance: 1400,
          billsDue: 0,
          savingsReserve: 0,
          spentToday: 0,
          daysLeft: 14,
        ),
        (custom, _) => limit = custom,
      );

      await tester.enterText(find.byType(TextField).first, '150.50');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(limit, 150.5);
    });

    testWidgets('clearing your own limit goes back to the recommendation', (
      tester,
    ) async {
      double? limit = -1;
      await pumpLimitSheet(
        tester,
        const SafeToSpend(
          walletBalance: 1400,
          billsDue: 0,
          savingsReserve: 0,
          spentToday: 0,
          daysLeft: 14,
          customDailyLimit: 200,
        ),
        (custom, _) => limit = custom,
      );

      final field = find.byType(TextField).first;
      expect(find.widgetWithText(TextField, '200'), findsOneWidget);

      await tester.enterText(field, '150.50');
      await tester.pump();
      expect(
        find.textContaining('Clear it to use the recommendation'),
        findsOneWidget,
      );

      await tester.enterText(field, '');
      await tester.pump();
      expect(
        find.textContaining('Empty, so the recommendation is used'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(limit, isNull);
    });

    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 5800,
      startingBalance: 5800,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );

    testWidgets('a gift raises the daily limit instead of restarting the '
        'month', (tester) async {
      final today = DateTime(2026, 3, 22, 10);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SafeToSpendCard(
                today: today,
                wallets: Stream.value([cash]),
                transactions: Stream.value(const []),
                profile: Stream.value({
                  'incomeFrequency': 'Monthly',
                  'incomeSource': 'Salary',
                }),
                // Newest first, as they are read.
                cycles: Stream.value([
                  AllocationCycle(
                    id: 'gift',
                    income: 1000,
                    remaining: 1000,
                    receivedAt: DateTime(2026, 3, 22),
                    source: 'Gift',
                  ),
                  AllocationCycle(
                    id: 'salary',
                    income: 8000,
                    remaining: 8000,
                    receivedAt: DateTime(2026, 3, 10),
                    source: 'Salary',
                  ),
                ]),
                loadBills: () async => const [],
                goals: Stream.value(const []),
                billSchedules: Stream.value(const []),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Still the salary's month, Mar 10 to Apr 10: 5800 over 19 days, not
      // over a new month from the gift.
      expect(find.text('19 days left this period'), findsOneWidget);
      expect(find.text('of ₱305.26 daily limit'), findsOneWidget);
    });

    testWidgets("shows what is left today against the day's limit", (
      tester,
    ) async {
      final today = DateTime(2026, 3, 22, 10);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SafeToSpendCard(
                today: today,
                wallets: Stream.value([cash]),
                transactions: Stream.value([
                  AppTransaction(
                    id: 'lunch',
                    type: TransactionType.expense,
                    amount: 200,
                    label: 'Food',
                    date: today,
                    walletId: 'cash',
                  ),
                ]),
                profile: Stream.value({'incomeFrequency': 'Semi-monthly'}),
                cycles: Stream.value(const []),
                loadBills: () async => const [],
                goals: Stream.value(const []),
                billSchedules: Stream.value(const []),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // 5800 + 200 spent today, over the 10 days from the 22nd to month end.
      expect(find.text('Safe to Spend Today'), findsOneWidget);
      expect(find.text('₱400'), findsOneWidget);
      expect(find.text('of ₱600 daily limit'), findsOneWidget);
      expect(find.text('Today spent: ₱200'), findsOneWidget);
      expect(find.text('10 days left this period'), findsOneWidget);
    });
  });

  group('goals', () {
    Goal goal({
      String id = 'g',
      String name = 'Laptop',
      double target = 30000,
      double saved = 0,
      int priority = 0,
      GoalStatus status = GoalStatus.active,
    }) {
      return Goal(
        id: id,
        name: name,
        targetAmount: target,
        savedAmount: saved,
        priority: priority,
        status: status,
      );
    }

    test('progress, what is left, and when it is reached', () {
      final halfway = goal(saved: 15000);

      expect(halfway.progress, 0.5);
      expect(halfway.remaining, 15000);
      expect(halfway.isReached, isFalse);
      expect(goal(saved: 30000).isReached, isTrue);
      expect(goal(saved: 45000).progress, 1, reason: 'never past full');
    });

    test('money stops being set aside once it is used', () {
      expect(goal(saved: 5000).setAside, 5000);
      expect(goal(saved: 5000, status: GoalStatus.used).setAside, 0);
      expect(
        totalSetAside([
          goal(saved: 5000),
          goal(saved: 2000, status: GoalStatus.completed),
          goal(saved: 9000, status: GoalStatus.used),
        ]),
        7000,
      );
    });

    test('goals are ordered by priority', () {
      final sorted = sortGoals([
        goal(id: 'b', name: 'Phone', priority: 1),
        goal(id: 'a', name: 'Laptop', priority: 0),
      ]);

      expect(sorted.map((g) => g.id), ['a', 'b']);
    });

    test('a finish date needs at least two contributions', () {
      final now = DateTime(2026, 3, 11);
      final g = goal(target: 3000, saved: 1000);

      expect(
        projectedCompletion(g, [
          GoalContribution(id: '1', amount: 1000, date: DateTime(2026, 3, 1)),
        ], now: now),
        isNull,
      );

      // ₱1,000 over 10 days is ₱100 a day; ₱2,000 to go is 20 more days.
      expect(
        projectedCompletion(g, [
          GoalContribution(id: '1', amount: 600, date: DateTime(2026, 3, 1)),
          GoalContribution(id: '2', amount: 400, date: DateTime(2026, 3, 6)),
        ], now: now),
        DateTime(2026, 3, 31),
      );
    });

    test('putting income toward a goal lowers what is left', () {
      final plan = AllocationPlan(
        income: 5000,
        goal: goal(target: 10000),
        goalAmount: 2000,
      );

      expect(plan.afterBills, 5000);
      expect(plan.toGoal, 2000);
      expect(plan.remaining, 3000);
      expect(plan.problems, isEmpty);
    });

    test('a goal cannot be overfilled from income', () {
      final plan = AllocationPlan(
        income: 5000,
        goal: goal(target: 10000, saved: 9000),
        goalAmount: 1500,
      );

      expect(plan.problems, ['Laptop only needs ₱1,000 more.']);
    });

    test('goal savings are not safe to spend', () {
      const s = SafeToSpend(
        walletBalance: 10000,
        billsDue: 0,
        savingsReserve: 0,
        goalSavings: 4000,
        spentToday: 0,
        daysLeft: 6,
      );

      expect(s.spendableThisPeriod, 6000);
      expect(s.recommendedDailyLimit, 1000);
    });
  });

  group('Goals screen', () {
    Goal goal(
      String id,
      int priority, {
      GoalStatus status = GoalStatus.active,
      double saved = 1000,
    }) {
      return Goal(
        id: id,
        name: id,
        targetAmount: 5000,
        savedAmount: saved,
        priority: priority,
        status: status,
      );
    }

    Future<void> pumpGoals(
      WidgetTester tester,
      List<Goal> goals, {
      void Function(List<Goal>)? onReorder,
    }) async {
      tester.view.physicalSize = const Size(700, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: GoalsScreen(
              goals: Stream.value(goals),
              profile: Stream.value(null),
              onReorder: onReorder,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    test('the tab controller opens savings or a debts list', () {
      final controller = GoalsTabController();
      addTearDown(controller.dispose);
      var tabChanges = 0;
      var listChanges = 0;
      controller.addListener(() => tabChanges++);
      controller.debtsList.addListener(() => listChanges++);

      controller.openDebts(DebtDirection.owedToMe);
      expect(controller.showDebts, isTrue);
      expect(controller.debtsList.value, DebtDirection.owedToMe);

      // Saving to the same list again still switches back to it.
      controller.openDebts(DebtDirection.owedToMe);
      expect(listChanges, 2);

      controller.openSavings();
      expect(controller.showDebts, isFalse);
      expect(tabChanges, 3);
    });

    testWidgets('Save to Goal picks a goal or offers a new one', (
      tester,
    ) async {
      Object? picked;

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<Object>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => GoalPickerSheet(
                      goals: [goal('Laptop', 0), goal('Phone', 1)],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Save to which goal?'), findsOneWidget);
      expect(find.text('₱1,000 of ₱5,000'), findsNWidgets(2));

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      expect((picked as Goal?)?.id, 'Phone');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Goal'));
      await tester.pumpAndSettle();
      expect(picked, GoalPickerSheet.newGoal);
    });

    testWidgets('invites a first goal', (tester) async {
      await pumpGoals(tester, const []);

      expect(find.text('No goals yet'), findsOneWidget);
      expect(find.text('Add New Goal'), findsOneWidget);
    });

    testWidgets('ranks active goals and shows their progress', (tester) async {
      await pumpGoals(tester, [goal('Laptop', 0), goal('Phone', 1)]);

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text(' of ₱5,000'), findsNWidgets(2));
    });

    testWidgets('moving a goal down saves the new order', (tester) async {
      List<Goal>? saved;
      await pumpGoals(tester, [
        goal('Laptop', 0),
        goal('Phone', 1),
      ], onReorder: (ordered) => saved = ordered);

      await tester.tap(find.byTooltip('Move down').first);
      await tester.pump();

      expect(saved?.map((g) => g.id), ['Phone', 'Laptop']);
    });

    testWidgets('reached goals live under Completed', (tester) async {
      await pumpGoals(tester, [
        goal('Laptop', 0),
        goal('Trip', 1, status: GoalStatus.completed, saved: 5000),
      ]);

      expect(find.text('Trip'), findsNothing);

      await tester.tap(find.text('Completed (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('Reached'), findsOneWidget);
    });
  });

  group('Goal money', () {
    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 9000,
      startingBalance: 9000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    const laptop = Goal(
      id: 'g',
      name: 'Laptop',
      targetAmount: 5000,
      savedAmount: 1200,
      priority: 0,
      status: GoalStatus.active,
    );

    Future<void> pumpSheet(
      WidgetTester tester, {
      required bool takeOut,
      required void Function(double, String) onSave,
    }) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ContributionSheet(
              goal: laptop,
              takeOut: takeOut,
              wallets: Stream.value([cash]),
              onSave: onSave,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('contributing starts on what the goal still needs', (
      tester,
    ) async {
      double? saved;
      await pumpSheet(tester, takeOut: false, onSave: (a, _) => saved = a);

      expect(find.text('3800'), findsOneWidget);
      await tester.tap(find.text('Set Aside'));
      await tester.pumpAndSettle();

      expect(saved, 3800);
    });

    testWidgets('cannot take out more than is set aside', (tester) async {
      double? saved;
      await pumpSheet(tester, takeOut: true, onSave: (a, _) => saved = a);

      await tester.enterText(find.byType(TextField).first, '2000');
      await tester.tap(find.text('Take It Out'));
      await tester.pump();

      expect(
        find.text('Only ₱1,200 is set aside for this goal.'),
        findsOneWidget,
      );
      expect(saved, isNull);

      await tester.enterText(find.byType(TextField).first, '500');
      await tester.tap(find.text('Take It Out'));
      await tester.pumpAndSettle();

      expect(saved, -500);
    });

    testWidgets('income can go toward a goal in the waterfall', (tester) async {
      AllocationPlan? confirmed;

      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IncomeWaterfallScreen(
            today: DateTime(2026, 3, 10),
            wallets: Stream.value([cash]),
            loadBills: () async => const [],
            goals: Stream.value(const [laptop]),
            cycles: Stream.value(const []),
            onConfirm:
                ({
                  required AllocationPlan plan,
                  required String walletId,
                  required String source,
                  required DateTime receivedAt,
                }) => confirmed = plan,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '10000');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allowance').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Save some toward a goal?'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      // "Use what is left" is capped at what the goal still needs.
      expect(find.text('₱3,800, all this goal needs'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(confirmed?.goal?.id, 'g');
      expect(confirmed?.toGoal, 3800);
      expect(confirmed?.remaining, 6200);
    });
  });

  group('installments', () {
    Debt phone({int count = 12, double perPayment = 2400}) => Debt(
      id: 'd',
      direction: DebtDirection.iOwe,
      name: 'Phone',
      category: DebtCategory.gadget,
      principal: 24000,
      perPayment: perPayment,
      paymentCount: count,
      firstDueDate: DateTime(2026, 1, 31),
      billId: 'b',
      status: DebtStatus.active,
    );

    test('the last payment of a monthly plan keeps its day', () {
      expect(
        lastDueDateFor(DateTime(2026, 1, 31), BillRecurrence.monthly, 12),
        DateTime(2026, 12, 31),
      );
      expect(
        lastDueDateFor(DateTime(2026, 1, 31), BillRecurrence.monthly, 2),
        DateTime(2026, 2, 28),
      );
      expect(
        lastDueDateFor(DateTime(2026, 3, 2), BillRecurrence.weekly, 4),
        DateTime(2026, 3, 23),
      );
    });

    test('a bill with an end date stops asking after its last payment', () {
      final bill = Bill(
        id: 'b',
        name: 'Phone',
        amount: 2400,
        category: 'Bills',
        firstDueDate: DateTime(2026, 1, 31),
        recurrence: BillRecurrence.monthly,
        endDate: DateTime(2026, 12, 31),
      );

      expect(bill.occurrencesIn(2026, 12), [DateTime(2026, 12, 31)]);
      expect(bill.occurrencesIn(2027, 1), isEmpty);
    });

    test('a blank payment count is worked out from the amounts', () {
      expect(paymentsToCover(24000, 2000), 12);
      expect(paymentsToCover(25000, 2000), 13);
      expect(paymentsToCover(0, 2000), 0);
    });

    test('the cost of borrowing is shown in pesos, not a rate', () {
      final debt = phone();

      expect(debt.totalPayable, 28800);
      expect(debt.extraCost, 4800);
      expect(debt.lastDueDate, DateTime(2026, 12, 31));
      expect(phone(perPayment: 2000).extraCost, 0);
    });

    test("progress comes from the installment's bill payments", () {
      BillInstance payment(int month, double paid) => BillInstance(
        id: 'b_$month',
        billId: 'b',
        name: 'Phone',
        amount: 2400,
        category: 'Bills',
        dueDate: DateTime(2026, month, 28),
        status: BillInstance.statusForPayment(paid, 2400),
        amountPaid: paid,
      );

      final progress = DebtProgress.of(phone(), [
        payment(1, 2400),
        payment(2, 2400),
        payment(3, 1000),
      ]);

      expect(progress.paid, 5800);
      expect(progress.remaining, 23000);
      expect(progress.paymentsMade, 2, reason: 'a part payment is not one');
      expect(progress.paymentsLeft, 10);
      expect(progress.isPaidOff, isFalse);
    });

    test('borrowed, lent and repaid money is not earning or spending', () {
      AppTransaction t(TransactionType type, double amount, {String? debt}) =>
          AppTransaction(
            id: '$type$amount',
            type: type,
            amount: amount,
            label: 'x',
            date: DateTime(2026, 3, 10, 9),
            walletId: 'w',
            debtId: debt,
          );

      final list = [
        t(TransactionType.income, 3000),
        t(TransactionType.income, 50000, debt: 'loan'),
        t(TransactionType.expense, 200),
        t(TransactionType.expense, 1000, debt: 'lent'),
      ];

      final totals = inAndOut(list);
      expect(totals.moneyIn, 3000);
      expect(totals.moneyOut, 200);
      expect(
        discretionarySpending(
          list,
          from: DateTime(2026, 3, 10),
          until: DateTime(2026, 3, 11),
        ),
        200,
      );

      final loan = list[1];
      expect(LedgerService.whyNotEditable(loan), contains('Debts'));
      expect(LedgerService.canDeleteHere(loan), isFalse);
      expect(LedgerService.canDeleteHere(list[0]), isTrue);
    });

    test('income is turned into a monthly figure for the suggestion', () {
      expect(
        monthlyIncomeFrom({'income': 1200, 'incomeFrequency': 'Weekly'}),
        closeTo(5200, 0.01),
      );
      expect(
        monthlyIncomeFrom({'income': 5000, 'incomeFrequency': 'Semi-monthly'}),
        10000,
      );
      expect(monthlyIncomeFrom({'incomeFrequency': 'Monthly'}), isNull);
      expect(monthlyIncomeFrom(null), isNull);
    });
  });

  group('Debts', () {
    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 5000,
      startingBalance: 5000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(700, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Widget app(Widget home) => ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(theme: AppTheme.light, home: home),
    );

    testWidgets('the form works out payments and the extra cost', (
      tester,
    ) async {
      tall(tester);
      DebtDraft? saved;

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtFormSheet(
              today: DateTime(2026, 3, 10),
              wallets: Stream.value([cash]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Phone');
      await tester.enterText(fields.at(1), '24000');
      await tester.enterText(fields.at(2), '2400');
      await tester.pump();

      expect(find.text('10'), findsOneWidget, reason: 'payments, worked out');
      expect(find.textContaining('Total you will pay: ₱24,000'), findsOne);

      await tester.enterText(fields.at(3), '12');
      await tester.pump();
      expect(
        find.textContaining('₱4,800 more than you borrowed'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();

      expect(saved?.paymentCount, 12);
      expect(saved?.perPayment, 2400);
      expect(saved?.direction, DebtDirection.iOwe);
    });

    testWidgets(
      'the installment form shows examples before anything is typed',
      (tester) async {
        tall(tester);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: DebtFormSheet(
                today: DateTime(2026, 3, 10),
                wallets: Stream.value([cash]),
                onSave: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.textContaining('Copy these from your contract'), findsOne);
        // Grey examples inside the empty fields.
        expect(find.text('e.g. Phone, SSS loan'), findsOneWidget);
        expect(find.text('e.g. 12,000'), findsOneWidget);
        expect(find.text('e.g. 1,500'), findsOneWidget);
        expect(find.text('e.g. 12'), findsOneWidget);
        expect(find.text('Every month or week'), findsOneWidget);
        expect(find.text('Blank = auto'), findsOneWidget);
        // No peso sign until an amount is typed, so no example looks filled in.
        final fields = tester
            .widgetList<TextField>(find.byType(TextField))
            .toList();
        expect(fields[1].decoration?.prefixText, isNull, reason: 'borrowed');
        expect(
          fields[2].decoration?.prefixText,
          isNull,
          reason: 'each payment',
        );
        await tester.enterText(find.byType(TextField).at(2), '1500');
        await tester.pump();
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .elementAt(2)
              .decoration
              ?.prefixText,
          '₱ ',
        );
      },
    );

    testWidgets('the contract decides the last payment', (tester) async {
      tall(tester);
      DebtDraft? saved;

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtFormSheet(
              today: DateTime(2026, 3, 10),
              wallets: Stream.value([cash]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Loan');
      await tester.enterText(fields.at(1), '10000');
      await tester.enterText(fields.at(2), '3000');
      await tester.pump();

      // No count given: pay exactly what was borrowed, the last one smaller.
      expect(find.text('4'), findsOneWidget, reason: 'payments, worked out');
      expect(find.textContaining('Total you will pay: ₱10,000'), findsOne);
      expect(find.textContaining('more than you borrowed'), findsNothing);
      expect(find.textContaining('Last payment ₱1,000 on'), findsOneWidget);

      // A count from the contract keeps every payment the same.
      await tester.enterText(fields.at(3), '4');
      await tester.pump();
      expect(find.textContaining('Total you will pay: ₱12,000'), findsOne);
      expect(find.textContaining('₱2,000 more than you borrowed'), findsOne);

      // Unless the contract's last payment is typed in.
      await tester.enterText(fields.at(4), '1000');
      await tester.pump();
      expect(find.textContaining('Total you will pay: ₱10,000'), findsOne);

      await tester.ensureVisible(find.text('Save Installment'));
      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();
      expect(saved?.paymentCount, 4);
      expect(saved?.perPayment, 3000);
      expect(saved?.lastPayment, 1000);
    });

    testWidgets('payments that cannot cover the loan are refused', (
      tester,
    ) async {
      tall(tester);
      DebtDraft? saved;

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtFormSheet(
              today: DateTime(2026, 3, 10),
              wallets: Stream.value([cash]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Loan');
      await tester.enterText(fields.at(1), '10000');
      await tester.enterText(fields.at(2), '500');
      await tester.enterText(fields.at(3), '6');
      await tester.tap(find.text('Save Installment'));
      await tester.pump();

      expect(find.textContaining('less than the ₱10,000'), findsOneWidget);
      expect(saved, isNull);
    });

    testWidgets('money owed to me needs only who and how much', (tester) async {
      tall(tester);
      DebtDraft? saved;

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtFormSheet(
              initialDirection: DebtDirection.owedToMe,
              wallets: Stream.value([cash]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Ana');
      await tester.enterText(fields.at(1), '500');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved?.direction, DebtDirection.owedToMe);
      expect(saved?.principal, 500);
      expect(
        saved?.movedWalletId,
        'cash',
        reason: 'lent money leaves a wallet unless the user says otherwise',
      );
    });

    testWidgets('money lent before using the app can skip the wallet', (
      tester,
    ) async {
      tall(tester);
      DebtDraft? saved;

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtFormSheet(
              initialDirection: DebtDirection.owedToMe,
              wallets: Stream.value([cash]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Ana');
      await tester.enterText(fields.at(1), '9000');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Cash only holds ₱5,000.'), findsOneWidget);
      expect(saved, isNull);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved?.principal, 9000);
      expect(saved?.movedWalletId, isNull);
    });

    testWidgets('switches to the list something was just saved to', (
      tester,
    ) async {
      tall(tester);
      final showing = ValueNotifier(DebtDirection.iOwe);
      addTearDown(showing.dispose);

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtsView(
              showing: showing,
              debts: Stream.value(const [
                Debt(
                  id: 'a',
                  direction: DebtDirection.owedToMe,
                  name: 'Ana',
                  category: DebtCategory.familyFriend,
                  principal: 500,
                  received: 0,
                  status: DebtStatus.active,
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Ana'), findsNothing);

      showing.value = DebtDirection.owedToMe;
      await tester.pump();
      expect(find.text('Ana'), findsOneWidget);
    });

    testWidgets('lists installments with their progress', (tester) async {
      tall(tester);

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtsView(
              debts: Stream.value([
                Debt(
                  id: 'd',
                  direction: DebtDirection.iOwe,
                  name: 'Phone',
                  category: DebtCategory.gadget,
                  principal: 24000,
                  perPayment: 2000,
                  paymentCount: 12,
                  firstDueDate: DateTime(2026, 1, 5),
                  billId: 'b',
                  status: DebtStatus.active,
                ),
              ]),
              paymentsFor: (_) => Stream.value([
                BillInstance(
                  id: 'b_1',
                  billId: 'b',
                  name: 'Phone',
                  amount: 2000,
                  category: 'Bills',
                  dueDate: DateTime(2026, 1, 5),
                  status: BillStatus.paid,
                  amountPaid: 2000,
                ),
              ]),
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Phone'), findsOneWidget);
      expect(find.text(' of ₱24,000 paid'), findsOneWidget);
      expect(find.textContaining('11 payments left'), findsOneWidget);
    });

    testWidgets('shows how much is still to come back', (tester) async {
      tall(tester);

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtsView(
              debts: Stream.value(const [
                Debt(
                  id: 'a',
                  direction: DebtDirection.owedToMe,
                  name: 'Ana',
                  category: DebtCategory.familyFriend,
                  principal: 500,
                  received: 200,
                  status: DebtStatus.active,
                ),
              ]),
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Nothing to pay off'), findsOneWidget);

      await tester.tap(find.text('Owed to me'));
      await tester.pumpAndSettle();

      expect(find.text('Still to come back to you'), findsOneWidget);
      expect(find.text('₱300'), findsOneWidget);
      expect(find.text(' of ₱500 back'), findsOneWidget);
    });

    testWidgets('a repayment cannot be more than is owed', (tester) async {
      tall(tester);
      double? saved;

      await tester.pumpWidget(
        app(
          Scaffold(
            body: RepaymentSheet(
              debt: const Debt(
                id: 'a',
                direction: DebtDirection.owedToMe,
                name: 'Ana',
                category: DebtCategory.familyFriend,
                principal: 500,
                received: 200,
                status: DebtStatus.active,
              ),
              wallets: Stream.value([cash]),
              onSave: (amount, _) => saved = amount,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('300'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '400');
      await tester.tap(find.text('Record Repayment'));
      await tester.pump();

      expect(find.text('Only ₱300 is still owed.'), findsOneWidget);
      expect(saved, isNull);
    });
  });

  group('Grow Your Money', () {
    testWidgets('suggests saving 20% of monthly income', (tester) async {
      tester.view.physicalSize = const Size(700, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? goalName;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SavingsGuide(
                monthlyIncome: 10000,
                onCreateGoal: (name, _) => goalName = name,
              ),
            ),
          ),
        ),
      );

      expect(find.text('About ₱2,000'), findsOneWidget);
      expect(find.textContaining('not financial advice'), findsOneWidget);

      await tester.tap(find.text('Emergency Fund'));
      await tester.pumpAndSettle();

      expect(find.text('Watch out for'), findsOneWidget);
      await tester.tap(find.text('Create Savings Goal'));
      await tester.pumpAndSettle();

      expect(goalName, 'Emergency Fund');
    });

    testWidgets('asks for income when there is none', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SavingsGuide(monthlyIncome: null, onCreateGoal: (_, _) {}),
            ),
          ),
        ),
      );

      expect(find.text('Add your usual income to see this'), findsOneWidget);
    });
  });

  group('goal plans', () {
    final now = DateTime(2026, 3, 10);

    test('a year away at ₱30,000 is ₱2,500 a month, not ₱2,727', () {
      expect(
        neededPerContribution(
          remaining: 30000,
          targetDate: DateTime(2027, 3, 10),
          frequency: ContributionFrequency.monthly,
          now: now,
        ),
        2500,
      );
    });

    test('the same goal weekly is about ₱577 a week', () {
      expect(
        neededPerContribution(
          remaining: 30000,
          targetDate: DateTime(2027, 3, 10),
          frequency: ContributionFrequency.weekly,
          now: now,
        ),
        closeTo(576.92, 0.01),
      );
    });

    test('no date means no suggestion; a past date means all of it now', () {
      expect(
        neededPerContribution(
          remaining: 30000,
          targetDate: null,
          frequency: ContributionFrequency.monthly,
          now: now,
        ),
        isNull,
      );
      expect(
        neededPerContribution(
          remaining: 1200,
          targetDate: DateTime(2026, 3, 1),
          frequency: ContributionFrequency.monthly,
          now: now,
        ),
        1200,
      );
    });

    test('only saving days that fit before the date are counted', () {
      // 350 days holds eleven monthly saving days, not the twelve an average
      // month would suggest; asking for twelfths would fall short.
      expect(
        neededPerContribution(
          remaining: 11000,
          targetDate: DateTime(2027, 2, 23),
          frequency: ContributionFrequency.monthly,
          now: now,
        ),
        1000,
      );
      // 50 days away: one saving day, so all of it then.
      expect(
        neededPerContribution(
          remaining: 3000,
          targetDate: DateTime(2026, 4, 29),
          frequency: ContributionFrequency.monthly,
          now: now,
        ),
        3000,
      );
      // An existing plan keeps its own saving day: the 25th.
      expect(
        neededPerContribution(
          remaining: 3000,
          targetDate: DateTime(2026, 6, 1),
          frequency: ContributionFrequency.monthly,
          now: now,
          planStartedAt: DateTime(2026, 1, 25),
        ),
        1000,
        reason: 'Mar 25, Apr 25 and May 25',
      );
    });

    test('a plan amount gives a finish date', () {
      final reached = reachedByPlan(
        remaining: 10000,
        amount: 2500,
        frequency: ContributionFrequency.monthly,
        now: now,
      );

      // Four monthly contributions.
      expect(reached, DateTime(2026, 7, 10));
      expect(
        reachedByPlan(
          remaining: 10000,
          amount: null,
          frequency: ContributionFrequency.monthly,
          now: now,
        ),
        isNull,
      );
    });

    Goal planned({required double saved, double startingSaved = 0}) => Goal(
      id: 'g',
      name: 'Laptop',
      targetAmount: 30000,
      savedAmount: saved,
      priority: 0,
      status: GoalStatus.active,
      planAmount: 1000,
      frequency: ContributionFrequency.monthly,
      planStartedAt: DateTime(2026, 1, 4),
      startingSaved: startingSaved,
    );

    test('keeping up with a plan', () {
      // 65 days in is two full months, so ₱2,000 is expected.
      expect(behindPlan(planned(saved: 1500), now: now), 500);
      expect(behindPlan(planned(saved: 2500), now: now), -500);
      expect(
        behindPlan(planned(saved: 5000, startingSaved: 3000), now: now),
        0,
        reason: 'what was already saved counts toward the plan',
      );
    });

    test('nobody is behind the day after starting a plan', () {
      final goal = Goal(
        id: 'g',
        name: 'Laptop',
        targetAmount: 30000,
        savedAmount: 0,
        priority: 0,
        status: GoalStatus.active,
        planAmount: 1000,
        planStartedAt: DateTime(2026, 3, 9),
      );

      expect(behindPlan(goal, now: now), 0);
    });
  });

  group('New Savings Goal form', () {
    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 5000,
      startingBalance: 5000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );

    testWidgets('shows what to save and records money already saved', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      GoalDraft? saved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: GoalFormSheet(
              initialName: 'Emergency Fund',
              initialKind: GoalKind.emergencyFund,
              today: DateTime(2026, 3, 10),
              wallets: Stream.value([cash]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Emergency Fund'), findsWidgets);

      // Only the essentials show at first.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Already saved'), findsNothing);

      await tester.enterText(find.byType(TextField).at(1), '12000');
      await tester.tap(find.text('More options (optional)'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      // Name, target, already saved, amount each time, notes.
      await tester.enterText(fields.at(2), '2000');
      await tester.pump();

      // No date yet and no plan amount.
      expect(
        find.text('Add a target date or an amount to see how long it takes.'),
        findsOneWidget,
      );

      await tester.enterText(fields.at(3), '2500');
      await tester.pump();
      expect(
        find.textContaining('At ₱2,500 a month you reach it around'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();

      expect(saved?.targetAmount, 12000);
      expect(saved?.alreadySaved, 2000);
      expect(saved?.planAmount, 2500);
      expect(saved?.kind, GoalKind.emergencyFund);
      expect(saved?.walletId, 'cash');
    });
  });

  group('reports', () {
    AppTransaction tx(
      String id,
      TransactionType type,
      double amount,
      DateTime date, {
      String label = 'Food',
      String? debtId,
      String? billInstanceId,
      String? toWalletId,
    }) {
      return AppTransaction(
        id: id,
        type: type,
        amount: amount,
        label: label,
        date: date,
        walletId: 'cash',
        toWalletId: toWalletId,
        debtId: debtId,
        billInstanceId: billInstanceId,
      );
    }

    test('weeks run Monday to Sunday and months to their last day', () {
      // Thursday.
      final week = ReportPeriod.weekOf(DateTime(2026, 9, 17, 15));
      expect(week.start, DateTime(2026, 9, 14));
      expect(week.end, DateTime(2026, 9, 20));
      expect(week.contains(DateTime(2026, 9, 20, 23, 59)), isTrue);
      expect(week.contains(DateTime(2026, 9, 21)), isFalse);

      final february = ReportPeriod.monthOf(DateTime(2028, 2, 10));
      expect(february.end, DateTime(2028, 2, 29));
      expect(february.label, 'Feb 1 – Feb 29, 2028');
    });

    test('the period before crosses years and keeps a custom length', () {
      expect(
        ReportPeriod.monthOf(DateTime(2026, 1, 5)).previous(ReportRange.month),
        ReportPeriod(DateTime(2025, 12, 1), DateTime(2025, 12, 31)),
      );
      expect(
        ReportPeriod.weekOf(DateTime(2026, 1, 1)).previous(ReportRange.week),
        ReportPeriod(DateTime(2025, 12, 22), DateTime(2025, 12, 28)),
      );
      expect(
        ReportPeriod(
          DateTime(2026, 9, 11),
          DateTime(2026, 9, 20),
        ).previous(ReportRange.custom),
        ReportPeriod(DateTime(2026, 9, 1), DateTime(2026, 9, 10)),
      );
    });

    test('the summary leaves out borrowing, lending and transfers', () {
      final september = ReportPeriod.monthOf(DateTime(2026, 9, 17));
      final day = DateTime(2026, 9, 10);
      final summary = summarize(
        [
          tx('a', TransactionType.income, 5000, day, label: 'Allowance'),
          tx('b', TransactionType.income, 2000, day, debtId: 'x'),
          tx('c', TransactionType.expense, 300, day),
          tx('d', TransactionType.expense, 1000, day, billInstanceId: 'i'),
          tx('e', TransactionType.expense, 500, day, debtId: 'y'),
          tx('f', TransactionType.transfer, 900, day, toWalletId: 'gcash'),
          // August.
          tx('g', TransactionType.expense, 700, DateTime(2026, 8, 31)),
        ],
        [
          GoalContribution(id: '1', amount: 800, date: day),
          GoalContribution(id: '2', amount: -200, date: day),
          GoalContribution(id: '3', amount: 999, date: DateTime(2026, 8, 1)),
        ],
        september,
      );

      expect(summary.income, 5000);
      expect(summary.expenses, 1300, reason: 'bills count, lending does not');
      expect(summary.saved, 600);
      expect(summary.netChange, 3700);
    });

    test('the trend covers six months, oldest first', () {
      final points = trend(
        [
          tx('a', TransactionType.income, 3000, DateTime(2026, 9, 2)),
          tx('b', TransactionType.expense, 450, DateTime(2026, 9, 3)),
          tx('c', TransactionType.expense, 200, DateTime(2026, 4, 30)),
          tx('d', TransactionType.expense, 999, DateTime(2026, 3, 31)),
        ],
        range: ReportRange.month,
        end: DateTime(2026, 9, 17),
      );

      expect(points.map((p) => p.label), [
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
      ]);
      expect(points.first.moneyOut, 200, reason: 'March is outside the six');
      expect(points.last.moneyIn, 3000);
      expect(points.last.moneyOut, 450);

      final weeks = trend(
        const [],
        range: ReportRange.week,
        end: DateTime(2026, 9, 17),
      );
      expect(weeks.last.label, 'Sep 14');
      expect(weeks.first.label, 'Aug 10');
    });

    test('the trend starts where the records do', () {
      final points = trend(
        [
          tx('a', TransactionType.income, 6000, DateTime(2026, 9, 2)),
          tx('b', TransactionType.expense, 2500, DateTime(2026, 8, 31, 22)),
        ],
        range: ReportRange.month,
        end: DateTime(2026, 9, 17),
      );

      expect(points.map((p) => p.label), ['Aug', 'Sep']);
      expect(points.first.moneyOut, 2500);
      expect(points.last.moneyIn, 6000);

      final onlyThisMonth = trend(
        [tx('a', TransactionType.income, 6000, DateTime(2026, 9, 2))],
        range: ReportRange.month,
        end: DateTime(2026, 9, 17),
      );
      expect(onlyThisMonth.map((p) => p.label), ['Sep']);
    });

    test('insights compare with earlier months only when there are some', () {
      final september = ReportPeriod.monthOf(DateTime(2026, 9, 17));

      final firstMonth = insightsFor(
        [
          tx('a', TransactionType.income, 4000, DateTime(2026, 9, 1)),
          tx('b', TransactionType.expense, 900, DateTime(2026, 9, 2)),
          tx(
            'c',
            TransactionType.expense,
            100,
            DateTime(2026, 9, 3),
            label: 'Transportation',
          ),
        ],
        period: september,
        range: ReportRange.month,
      );
      expect(firstMonth, [
        'Food is 90% of your spending this month.',
        'You kept 75% of what came in this month.',
      ]);

      final withHistory = insightsFor(
        [
          tx('a', TransactionType.expense, 1200, DateTime(2026, 9, 2)),
          tx('b', TransactionType.expense, 1000, DateTime(2026, 8, 2)),
          tx('c', TransactionType.expense, 1000, DateTime(2026, 7, 2)),
          tx('d', TransactionType.expense, 1000, DateTime(2026, 6, 2)),
          tx('e', TransactionType.income, 1000, DateTime(2026, 9, 1)),
        ],
        period: september,
        range: ReportRange.month,
      );
      expect(withHistory, [
        'Food spending is 20% higher than your 3-month average.',
        'You spent ₱200 more than came in this month.',
      ]);

      final shortHistory = insightsFor(
        [
          tx('a', TransactionType.expense, 500, DateTime(2026, 9, 2)),
          tx('b', TransactionType.expense, 1000, DateTime(2026, 8, 2)),
        ],
        period: september,
        range: ReportRange.month,
      );
      expect(
        shortHistory.first,
        'Food spending is 50% lower than your recent average.',
        reason: 'one earlier month is not a 3-month average',
      );

      expect(
        insightsFor(const [], period: september, range: ReportRange.month),
        isEmpty,
      );
    });

    test('spending past the top few is summed into one entry', () {
      const spending = [
        MapEntry('Food', 500.0),
        MapEntry('Bills', 300.0),
        MapEntry('Shopping', 150.0),
        MapEntry('Education', 40.0),
        MapEntry('Others', 10.0),
      ];

      final folded = foldSpending(spending, 3);
      expect(folded.map((e) => e.key), ['Food', 'Bills', 'Shopping', null]);
      expect(folded.last.value, 50);
      expect(foldSpending(spending, 5).length, 5);
      expect(foldSpending(spending, null).length, 5);
    });

    test('axis amounts are short', () {
      expect(formatPesoCompact(950), '₱950');
      expect(formatPesoCompact(1500), '₱1.5k');
      expect(formatPesoCompact(20000), '₱20k');
      expect(formatPesoCompact(999.6), '₱1k');
      expect(formatPesoCompact(999999), '₱1M');
      expect(formatPesoCompact(1250000), '₱1.25M');
    });

    test('categories keep one color, stepped for dark mode', () {
      expect(categoryColor('Food'), categoryColor('food'));
      expect(
        categoryColor('Food', brightness: Brightness.dark),
        isNot(categoryColor('Food')),
      );
      expect(categoryColor('Something new'), categoryColor('Others'));
    });
  });

  group('Reports screen', () {
    final day = DateTime(2026, 9, 10);
    final transactions = [
      AppTransaction(
        id: 'a',
        type: TransactionType.income,
        amount: 5000,
        label: 'Allowance',
        date: day,
        walletId: 'cash',
      ),
      AppTransaction(
        id: 'b',
        type: TransactionType.expense,
        amount: 1000,
        label: 'Bills',
        date: day,
        walletId: 'cash',
        billInstanceId: 'i',
      ),
      AppTransaction(
        id: 'c',
        type: TransactionType.expense,
        amount: 250.5,
        label: 'Food',
        date: DateTime(2026, 9, 16),
        walletId: 'cash',
      ),
    ];

    Future<void> pumpReports(
      WidgetTester tester, {
      List<AppTransaction>? list,
      void Function(TransactionFilter)? onOpenCategory,
    }) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: ReportsScreen(
              transactions: Stream.value(list ?? transactions),
              contributions: Stream.value([
                GoalContribution(id: '1', amount: 400, date: day),
              ]),
              records: Stream.value(
                FinanceSnapshot(
                  now: DateTime(2026, 9, 17),
                  transactions: list ?? transactions,
                ),
              ),
              today: DateTime(2026, 9, 17),
              onOpenCategory: onOpenCategory,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// Four categories rather than two, so a recount is a real sum and not a
    /// coin flip, and the shares divide cleanly enough to read.
    final fourCategories = [
      for (final (id, label, amount) in const [
        ('g', 'Groceries', 400.0),
        ('c', 'Commute', 300.0),
        ('r', 'Rent', 200.0),
        ('w', 'Clothes', 100.0),
      ])
        AppTransaction(
          id: id,
          type: TransactionType.expense,
          amount: amount,
          label: label,
          date: day,
          walletId: 'cash',
        ),
    ];

    /// The tappable row for a category, found inside the legend so a mention
    /// of the same word elsewhere on the screen cannot be hit by mistake.
    Finder legendRow(String label) => find
        .ancestor(
          of: find.descendant(
            of: find.byType(SpendingLegend),
            matching: find.text(label),
          ),
          matching: find.byType(InkWell),
        )
        .first;

    testWidgets('leaving a category out recounts the shares of the rest', (
      tester,
    ) async {
      await pumpReports(tester, list: fourCategories);

      // 400, 300, 200 and 100 of 1000.
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);

      await tester.tap(legendRow('Groceries'));
      await tester.pump();

      // 300, 200 and 100 of the 600 still counted.
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('33%'), findsOneWidget);
      expect(find.text('17%'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: 'the one left out');
      expect(find.text('40%'), findsNothing);
      expect(find.textContaining('Counting 3 of 4'), findsOneWidget);
    });

    testWidgets('a second category left out is counted out too', (
      tester,
    ) async {
      await pumpReports(tester, list: fourCategories);

      await tester.tap(legendRow('Groceries'));
      await tester.pump();
      await tester.tap(legendRow('Commute'));
      await tester.pump();

      // 200 and 100 of the 300 left.
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('33%'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.textContaining('Counting 2 of 4'), findsOneWidget);
    });

    testWidgets('tapping a category that was left out counts it again', (
      tester,
    ) async {
      await pumpReports(tester, list: fourCategories);

      await tester.tap(legendRow('Groceries'));
      await tester.pump();
      expect(find.text('—'), findsOneWidget);

      await tester.tap(legendRow('Groceries'));
      await tester.pump();

      expect(find.text('—'), findsNothing);
      expect(find.text('40%'), findsOneWidget);
      expect(find.textContaining('Counting'), findsNothing);
    });

    testWidgets('"Count all again" brings every category back', (
      tester,
    ) async {
      await pumpReports(tester, list: fourCategories);

      await tester.tap(legendRow('Groceries'));
      await tester.pump();
      await tester.tap(legendRow('Rent'));
      await tester.pump();
      expect(find.text('—'), findsNWidgets(2));

      await tester.tap(find.text('Count all again'));
      await tester.pump();

      expect(find.text('—'), findsNothing);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);
    });

    testWidgets('every category left out says so instead of drawing nothing', (
      tester,
    ) async {
      await pumpReports(tester, list: fourCategories);

      for (final label in ['Groceries', 'Commute', 'Rent', 'Clothes']) {
        await tester.tap(legendRow(label));
        await tester.pump();
      }

      expect(find.text('Every category is left out.'), findsOneWidget);
      expect(find.byType(SpendingDonut), findsNothing);
      expect(find.text('—'), findsNWidgets(4));
      expect(find.text('Count all again'), findsOneWidget);
    });

    testWidgets('the arrow still opens the category', (tester) async {
      TransactionFilter? opened;
      await pumpReports(
        tester,
        list: fourCategories,
        onOpenCategory: (filter) => opened = filter,
      );

      await tester.tap(
        find
            .descendant(
              of: find.byType(SpendingLegend),
              matching: find.byIcon(Icons.chevron_right),
            )
            .first,
      );
      await tester.pump();

      expect(opened?.category, 'Groceries');
      // Opening is not leaving out: nothing was set aside by that tap.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('the row and its arrow are both comfortable to hit', (
      tester,
    ) async {
      // The row and the arrow sit next to each other and do different
      // things, so a near miss must not leave a category out when the reader
      // meant to open it.
      final handle = tester.ensureSemantics();
      await pumpReports(tester, list: fourCategories);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('Financial tips come from the records, not a placeholder', (
      tester,
    ) async {
      await pumpReports(tester);

      expect(find.text('Financial tips'), findsOneWidget);
      expect(find.textContaining('trusted sources'), findsNothing);
      expect(
        find.byIcon(Icons.tips_and_updates_outlined),
        findsWidgets,
        reason: 'at least one tip is always shown',
      );
    });

    testWidgets('summarizes this month and breaks spending down', (
      tester,
    ) async {
      TransactionFilter? opened;
      await pumpReports(tester, onOpenCategory: (f) => opened = f);

      expect(find.text('Sep 1 – Sep 30, 2026'), findsOneWidget);
      expect(find.text('₱5,000'), findsOneWidget);
      expect(find.text('₱1,250.50'), findsWidgets);
      expect(find.text('₱400'), findsOneWidget);
      expect(find.text('+₱3,749.50'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(
        find.text('Bills is 80% of your spending this month.'),
        findsOneWidget,
      );

      // The row itself leaves a category out now, so opening one is the
      // arrow at its end.
      await tester.tap(
        find.descendant(
          of: legendRow('Food'),
          matching: find.byIcon(Icons.chevron_right),
        ),
      );
      await tester.pump();
      expect(opened?.category, 'Food');
      expect(opened?.type, TransactionType.expense);
      expect(opened?.from, DateTime(2026, 9, 1));
      expect(opened?.to, DateTime(2026, 9, 30));
    });

    testWidgets('switches to this week and steps back a week', (tester) async {
      await pumpReports(tester);

      await tester.tap(find.text('This week'));
      await tester.pump();
      expect(find.text('Sep 14 – Sep 20, 2026'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Bills'), findsNothing, reason: 'paid the week before');

      await tester.tap(find.byTooltip('Earlier'));
      await tester.pump();
      expect(find.text('Sep 7 – Sep 13, 2026'), findsOneWidget);
      expect(find.text('Bills'), findsOneWidget);
    });

    testWidgets('a new account gets a friendly empty state', (tester) async {
      await pumpReports(tester, list: const []);

      expect(find.text('Nothing to report yet'), findsOneWidget);
    });
  });

  group('Home screen', () {
    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 5000,
      startingBalance: 5000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    final gcash = Wallet(
      id: 'gcash',
      name: 'GCash',
      type: WalletType.gcash,
      balance: 10000,
      startingBalance: 10000,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
    );

    Future<void> pumpHome(
      WidgetTester tester,
      List<AppTransaction> transactions,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: HomeScreen(
              userName: 'Hayato',
              wallets: Stream.value([cash, gcash]),
              transactions: Stream.value(transactions),
              safeToSpend: const SizedBox(
                height: 80,
                child: Text('Safe to Spend placeholder'),
              ),
              today: DateTime(2026, 9, 17),
              onOpenTransactions: () {},
              onOpenWallets: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('reads the wallet ledger, with Safe to Spend first', (
      tester,
    ) async {
      await pumpHome(tester, [
        AppTransaction(
          id: 'b',
          type: TransactionType.expense,
          amount: 1000,
          label: 'Bills',
          date: DateTime(2026, 9, 17),
          walletId: 'cash',
          billInstanceId: 'i',
        ),
        AppTransaction(
          id: 'l',
          type: TransactionType.expense,
          amount: 500,
          label: 'Lent',
          date: DateTime(2026, 9, 17),
          walletId: 'gcash',
          debtId: 'ana',
        ),
      ]);

      expect(find.text('Hello, Hayato!'), findsOneWidget);
      expect(find.text('₱15,000'), findsOneWidget);
      expect(find.text('Across 2 wallets'), findsOneWidget);
      expect(find.textContaining('transactions recorded'), findsNothing);
      expect(find.text('Manage Category Budgets'), findsNothing);
      for (final shortcut in [
        'Bill Planner',
        'Savings',
        'Debts',
        'Reports',
        'Scan Receipt',
        'Voice Entry',
      ]) {
        expect(find.text(shortcut), findsOneWidget);
      }

      final safeTop = tester.getTopLeft(find.text('Safe to Spend placeholder'));
      final balanceTop = tester.getTopLeft(find.text('Total Balance'));
      expect(safeTop.dy, lessThan(balanceTop.dy));

      // The bill payment is spending; the loan to Ana isn't.
      expect(find.text('spent so far this month'), findsOneWidget);
      expect(find.byType(SpendingBar), findsOneWidget);
      final segments = find.descendant(
        of: find.byType(SpendingBar),
        matching: find.byType(ColoredBox),
      );
      expect(
        tester.getSize(segments.first).height,
        10,
        reason: 'the bar has to be drawn, not just present',
      );
      expect(find.text('100%'), findsOneWidget);

      // Both show in the recent list.
      expect(find.text('Lent'), findsOneWidget);
      expect(find.text('-₱500'), findsOneWidget);
    });

    testWidgets('a new account sees helpful empty sections', (tester) async {
      await pumpHome(tester, const []);

      expect(find.textContaining('No spending yet this month'), findsOneWidget);
      expect(find.textContaining('No transactions yet'), findsOneWidget);
    });
  });

  test('loans are totalled apart from money in and out', () {
    final day = DateTime(2026, 9, 17);
    final list = [
      AppTransaction(
        id: 'a',
        type: TransactionType.expense,
        amount: 500,
        label: 'Lent',
        date: day,
        debtId: 'ana',
      ),
      AppTransaction(
        id: 'b',
        type: TransactionType.income,
        amount: 200,
        label: 'Repayment',
        date: day,
        debtId: 'ana',
      ),
      AppTransaction(
        id: 'c',
        type: TransactionType.expense,
        amount: 100,
        label: 'Food',
        date: day,
      ),
    ];

    final loans = loanMovements(list);
    expect(loans.moneyOut, 500);
    expect(loans.moneyIn, 200);
    expect(inAndOut(list).moneyOut, 100);
  });

  testWidgets('Transactions shows the time it was recorded, when it has one', (
    tester,
  ) async {
    final today = DateTime.now();
    final logged = DateTime(today.year, today.month, today.day, 19, 42);
    final backDated = DateTime(today.year, today.month, today.day);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TransactionsScreen(
            key: UniqueKey(),
            showLegacyImport: false,
            wallets: Stream.value(const []),
            transactions: Stream.value([
              AppTransaction(
                id: 'logged',
                type: TransactionType.expense,
                amount: 100,
                label: 'Food',
                date: logged,
                isLegacy: true,
              ),
              AppTransaction(
                id: 'back',
                type: TransactionType.expense,
                amount: 200,
                label: 'Rent',
                date: backDated,
                isLegacy: true,
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('7:42 PM'), findsOneWidget);
    // Nothing is invented for the one that only ever carried a day.
    expect(find.textContaining('12:00 AM'), findsNothing);
  });

  testWidgets('Transactions heads each day once, newest first', (
    tester,
  ) async {
    // The headings are worked out per slot now rather than by walking the
    // list in order, so a day must still be announced once and only once.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    final yesterday = today.subtract(const Duration(days: 1));
    final older = today.subtract(const Duration(days: 5));

    AppTransaction spend(String id, DateTime date) => AppTransaction(
      id: id,
      type: TransactionType.expense,
      amount: 100,
      label: 'Food',
      date: date,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TransactionsScreen(
            key: UniqueKey(),
            showLegacyImport: false,
            wallets: Stream.value(const []),
            transactions: Stream.value([
              spend('a', today),
              spend('b', today),
              spend('c', yesterday),
              spend('d', older),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Today'), findsOneWidget, reason: 'two rows, one head');
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text(formatShortDate(older)), findsOneWidget);
    expect(find.byType(TransactionRow), findsNWidgets(4));
  });

  testWidgets('Transactions keeps the day heading in view while reading it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TransactionsScreen(
            key: UniqueKey(),
            showLegacyImport: false,
            wallets: Stream.value(const []),
            transactions: Stream.value([
              for (var i = 0; i < 30; i++)
                AppTransaction(
                  id: 'd$i',
                  type: TransactionType.expense,
                  amount: 100,
                  label: 'Food',
                  date: today.subtract(Duration(minutes: i)),
                ),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Today'), findsOneWidget);

    // Far enough that an unpinned heading would be long gone.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pump();

    // The block above the list has scrolled away, which is how far we are.
    expect(find.text('Money in'), findsNothing);

    expect(
      find.text('Today'),
      findsOneWidget,
      reason: 'the heading holds the top while its own rows pass under it',
    );
    expect(
      tester.getTopLeft(find.text('Today')).dy,
      lessThan(100),
      reason: 'pinned just under the bar, not somewhere down the list',
    );
  });

  testWidgets('Transactions builds only the rows on screen', (tester) async {
    // A long history must not cost a row for every transaction ever made.
    // This fails if the list is ever made to lay itself out in full, such as
    // by a Column or shrinkWrap.
    final now = DateTime.now();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TransactionsScreen(
            key: UniqueKey(),
            showLegacyImport: false,
            wallets: Stream.value(const []),
            transactions: Stream.value([
              for (var i = 0; i < 300; i++)
                AppTransaction(
                  id: 'n$i',
                  type: TransactionType.expense,
                  amount: 100,
                  label: 'Food',
                  date: now.subtract(Duration(minutes: i)),
                ),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(TransactionRow), findsAtLeastNWidgets(1));
    expect(
      find.byType(TransactionRow).evaluate().length,
      lessThan(60),
      reason: '300 transactions, only a screenful of rows',
    );
  });

  testWidgets('Transactions explains loans left out of the totals', (
    tester,
  ) async {
    Future<void> pump(List<AppTransaction> list) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: TransactionsScreen(
              key: UniqueKey(),
              showLegacyImport: false,
              wallets: Stream.value(const []),
              transactions: Stream.value(list),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final food = AppTransaction(
      id: 'f',
      type: TransactionType.expense,
      amount: 100,
      label: 'Food',
      date: DateTime(2026, 9, 17),
    );

    await pump([food]);
    expect(find.text('Loans in'), findsNothing);

    await pump([
      food,
      AppTransaction(
        id: 'l',
        type: TransactionType.expense,
        amount: 500,
        label: 'Lent',
        date: DateTime(2026, 9, 17),
        debtId: 'ana',
      ),
      AppTransaction(
        id: 'r',
        type: TransactionType.income,
        amount: 500,
        label: 'Repayment',
        date: DateTime(2026, 9, 17),
        debtId: 'ana',
      ),
    ]);
    expect(find.text('Loans in'), findsOneWidget);
    expect(find.text('Loans out'), findsOneWidget);
    expect(find.text('₱500'), findsNWidgets(2), reason: 'loans in and out');
    expect(find.text('₱100'), findsOneWidget, reason: 'money out stays ₱100');
  });

  test('loans get their own icons, not a category one', () {
    AppTransaction loan(TransactionType type) => AppTransaction(
      id: 'x',
      type: type,
      amount: 500,
      label: type == TransactionType.expense ? 'Lent' : 'Repayment',
      date: DateTime(2026, 9, 17),
      debtId: 'ana',
    );

    expect(
      loanIconAsset(loan(TransactionType.expense)),
      'assets/icons/lend-96.png',
    );
    expect(
      loanIconAsset(loan(TransactionType.income)),
      'assets/icons/loan-in-96.png',
    );
  });

  testWidgets('Transactions can open already filtered', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TransactionsScreen(
            showLegacyImport: false,
            initialFilter: const TransactionFilter(category: 'Food'),
            wallets: Stream.value(const []),
            transactions: Stream.value([
              AppTransaction(
                id: 'a',
                type: TransactionType.expense,
                amount: 120,
                label: 'Food',
                date: DateTime(2026, 9, 17),
              ),
              AppTransaction(
                id: 'b',
                type: TransactionType.expense,
                amount: 80,
                label: 'Shopping',
                date: DateTime(2026, 9, 17),
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('-₱120'), findsOneWidget);
    expect(find.text('-₱80'), findsNothing);
  });

  group('reminders', () {
    Map<String, dynamic> profile(
      List<FinancialPriority> order, {
      bool allowed = true,
      Map<String, dynamic>? reminders,
    }) => {
      'notificationsEnabled': allowed,
      'priorities': [for (final p in order) p.name],
      'reminders': ?reminders,
    };

    BillInstance bill(
      String id,
      DateTime due, {
      BillStatus status = BillStatus.unpaid,
      double amount = 1000,
    }) => BillInstance(
      id: id,
      billId: 'b-$id',
      name: id,
      amount: amount,
      category: 'Bills',
      dueDate: due,
      status: status,
    );

    List<PlannedReminder> plan(
      ReminderSettings settings, {
      List<BillInstance> bills = const [],
      List<Goal> goals = const [],
      List<AllocationCycle> cycles = const [],
      List<AppTransaction> transactions = const [],
      required DateTime now,
    }) => planReminders(
      settings: settings,
      bills: bills,
      goals: goals,
      cycles: cycles,
      incomeFrequency: 'Monthly',
      transactions: transactions,
      now: now,
    );

    test('priorities decide which reminders start on', () {
      final billsFirst = ReminderSettings.fromProfile(
        profile([
          FinancialPriority.payBills,
          FinancialPriority.saveForGoal,
          FinancialPriority.generalSavings,
          FinancialPriority.trackSpending,
        ]),
      );
      expect(billsFirst.isOn(ReminderKind.bills), isTrue);
      expect(billsFirst.isOn(ReminderKind.goals), isTrue);
      expect(billsFirst.isOn(ReminderKind.leftover), isFalse);
      expect(billsFirst.isOn(ReminderKind.dailyLog), isFalse);
      expect(billsFirst.billLeadDays, 3);

      final trackerFirst = ReminderSettings.fromProfile(
        profile([
          FinancialPriority.trackSpending,
          FinancialPriority.generalSavings,
          FinancialPriority.payBills,
          FinancialPriority.saveForGoal,
        ]),
      );
      expect(
        trackerFirst.isOn(ReminderKind.bills),
        isTrue,
        reason: 'bills are always on',
      );
      expect(
        trackerFirst.isOn(ReminderKind.payday),
        isTrue,
        reason: 'so is payday',
      );
      expect(trackerFirst.isOn(ReminderKind.dailyLog), isTrue);
      expect(trackerFirst.isOn(ReminderKind.leftover), isTrue);
      expect(trackerFirst.isOn(ReminderKind.goals), isFalse);
      expect(trackerFirst.billLeadDays, 1);
    });

    test('re-ranking moves only the reminders not set by hand', () {
      const order = [
        FinancialPriority.trackSpending,
        FinancialPriority.saveForGoal,
        FinancialPriority.payBills,
        FinancialPriority.generalSavings,
      ];
      final before = ReminderSettings.fromProfile(
        profile(order, reminders: {'goals': false}),
      );
      expect(before.isOn(ReminderKind.goals), isFalse, reason: 'by hand');
      expect(before.isOn(ReminderKind.dailyLog), isTrue);

      final reranked = ReminderSettings.fromProfile(
        profile(
          const [
            FinancialPriority.saveForGoal,
            FinancialPriority.generalSavings,
            FinancialPriority.payBills,
            FinancialPriority.trackSpending,
          ],
          reminders: {'goals': false},
        ),
      );
      expect(reranked.isOn(ReminderKind.goals), isFalse);
      expect(reranked.isOn(ReminderKind.dailyLog), isFalse);
      expect(reranked.isOn(ReminderKind.leftover), isTrue);
    });

    test('onboarding\'s answer turns reminders on or off', () {
      expect(
        ReminderSettings.fromProfile(profile(const [], allowed: false)).enabled,
        isFalse,
      );
      expect(
        ReminderSettings.fromProfile(
          profile(const [], allowed: false, reminders: {'enabled': true}),
        ).enabled,
        isTrue,
      );
      expect(
        prioritiesFrom({
          'priorities': ['trackSpending', 'nonsense'],
        }),
        [
          FinancialPriority.trackSpending,
          FinancialPriority.payBills,
          FinancialPriority.saveForGoal,
          FinancialPriority.generalSavings,
        ],
        reason: 'missing priorities go last, unknown ones are ignored',
      );
    });

    test('bills are reminded early and on the day, at 9 AM', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.payBills]),
      );
      final now = DateTime(2026, 9, 18, 10);

      final planned = plan(
        settings,
        now: now,
        bills: [
          bill('Internet', DateTime(2026, 9, 25)),
          bill('Water', DateTime(2026, 9, 19)),
          bill('Paid', DateTime(2026, 9, 26), status: BillStatus.paid),
        ],
      );

      expect(planned.map((r) => '${r.title} @ ${r.at}'), [
        'Water is due today @ 2026-09-19 09:00:00.000',
        'Internet is due in 3 days @ 2026-09-22 09:00:00.000',
        'Internet is due today @ 2026-09-25 09:00:00.000',
      ], reason: "Water's early reminder was this morning, already past");
      expect(planned.first.body, '₱1,000 to pay. Tap to pay it now.');
      expect(planned.first.payload, 'bill:Water');
    });

    test('nothing is planned while reminders are off', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [], allowed: false),
      );
      expect(
        plan(
          settings,
          now: DateTime(2026, 9, 18),
          bills: [bill('Internet', DateTime(2026, 9, 25))],
        ),
        isEmpty,
      );
    });

    test('saving plans are reminded on their own days', () {
      expect(
        planDates(
          DateTime(2026, 1, 31),
          ContributionFrequency.monthly,
          from: DateTime(2026, 1, 31),
          until: DateTime(2026, 4, 30),
        ),
        [DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30)],
      );
      expect(
        planDates(
          DateTime(2026, 9, 1),
          ContributionFrequency.weekly,
          from: DateTime(2026, 9, 10),
          until: DateTime(2026, 9, 30),
        ),
        [DateTime(2026, 9, 15), DateTime(2026, 9, 22), DateTime(2026, 9, 29)],
      );

      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );
      final planned = plan(
        settings,
        now: DateTime(2026, 9, 18, 12),
        goals: [
          Goal(
            id: 'g',
            name: 'Laptop',
            targetAmount: 20000,
            savedAmount: 1500,
            priority: 0,
            status: GoalStatus.active,
            planAmount: 1500,
            planStartedAt: DateTime(2026, 9, 17),
          ),
          Goal(
            id: 'done',
            name: 'Phone',
            targetAmount: 1000,
            savedAmount: 1000,
            priority: 1,
            status: GoalStatus.active,
            planAmount: 500,
            planStartedAt: DateTime(2026, 9, 17),
          ),
        ],
      );

      expect(planned.map((r) => r.at), [
        DateTime(2026, 10, 17, 9),
      ], reason: 'monthly from Sep 17, within six weeks; a reached goal waits');
      expect(planned.single.title, 'Time to save for Laptop');
      expect(
        planned.single.body,
        'Your plan is ₱1,500 a month. ₱18,500 to go.',
      );

      final byDate = plan(
        settings,
        now: DateTime(2026, 9, 18, 12),
        goals: [
          Goal(
            id: 'd',
            name: 'Laptop',
            targetAmount: 20000,
            savedAmount: 1000,
            priority: 0,
            status: GoalStatus.active,
            targetDate: DateTime(2027, 9, 17),
            planStartedAt: DateTime(2026, 9, 17),
          ),
          Goal(
            id: 'x',
            name: 'Someday',
            targetAmount: 5000,
            savedAmount: 0,
            priority: 1,
            status: GoalStatus.active,
            planStartedAt: DateTime(2026, 9, 17),
          ),
        ],
      );
      expect(
        byDate.single.body,
        'Save ₱1,583.33 a month to reach it by Sep 17, 2027.',
        reason: 'a goal with neither an amount nor a date gets no reminder',
      );
    });

    test('the logging nudge skips a day that already has a record', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.trackSpending]),
      );
      final now = DateTime(2026, 9, 18, 13);

      final nothingYet = plan(settings, now: now);
      expect(nothingYet.first.at, DateTime(2026, 9, 18, 20));
      expect(nothingYet.length, 7);

      final logged = plan(
        settings,
        now: now,
        transactions: [
          AppTransaction(
            id: 't',
            type: TransactionType.expense,
            amount: 50,
            label: 'Food',
            date: DateTime(2026, 9, 18, 8),
          ),
        ],
      );
      expect(logged.first.at, DateTime(2026, 9, 19, 20));
      expect(logged.length, 6);
    });

    test('the leftover question comes as the pay period ends', () {
      final settings = ReminderSettings.fromProfile(
        profile(
          const [FinancialPriority.generalSavings],
          reminders: {'payday': false},
        ),
      );
      final cycle = AllocationCycle(
        id: 'c',
        income: 5000,
        remaining: 3000,
        receivedAt: DateTime(2026, 9, 1),
        source: 'Allowance',
      );

      final ending = plan(
        settings,
        now: DateTime(2026, 9, 18),
        cycles: [cycle],
      );
      expect(ending.single.at, DateTime(2026, 9, 30, 19));
      expect(ending.single.payload, 'leftover');

      final stillWaiting = plan(
        settings,
        now: DateTime(2026, 10, 3, 12),
        cycles: [cycle],
      );
      expect(stillWaiting.single.at, DateTime(2026, 10, 4, 9));
      expect(stillWaiting.single.title, 'Your leftover is still waiting');
    });

    test('only the usual pay starts a new pay period', () {
      AllocationCycle income(String source, DateTime at) => AllocationCycle(
        id: '$source-$at',
        income: 1000,
        remaining: 1000,
        receivedAt: at,
        source: source,
      );
      final salary = income('Salary', DateTime(2026, 8, 30));
      final gift = income('Gift', DateTime(2026, 9, 19));
      final freelance = income('Freelance', DateTime(2026, 9, 10));
      final now = DateTime(2026, 9, 19, 14);

      expect(
        lastPayday([gift, freelance, salary], usualSource: 'Salary'),
        DateTime(2026, 8, 30),
      );
      expect(
        lastPayday([gift, salary], usualSource: 'Salary', onOrBefore: now),
        DateTime(2026, 8, 30),
      );
      expect(
        lastPayday([salary], onOrBefore: DateTime(2026, 8, 29)),
        isNull,
        reason: 'pay after the moment asked about is left out',
      );

      // A gift joins the salary's period; the next salary starts its own.
      final giftPeriod = periodForIncome(
        frequency: 'Monthly',
        source: 'Gift',
        receivedAt: DateTime(2026, 9, 19),
        earlier: [salary],
        usualSource: 'Salary',
      );
      expect(giftPeriod.start, DateTime(2026, 8, 30));
      expect(giftPeriod.end, DateTime(2026, 9, 30));

      final nextPay = periodForIncome(
        frequency: 'Monthly',
        source: 'Salary',
        receivedAt: DateTime(2026, 9, 30),
        earlier: [salary, gift],
        usualSource: 'Salary',
      );
      expect(nextPay.start, DateTime(2026, 9, 30));
      expect(nextPay.end, DateTime(2026, 10, 30));
    });

    group('payday', () {
      final settings = ReminderSettings.fromProfile(profile(const []));

      AllocationCycle pay(DateTime at, {String source = 'Salary'}) =>
          AllocationCycle(
            id: '$source-$at',
            income: 10000,
            remaining: 8000,
            receivedAt: at,
            source: source,
          );

      List<PlannedReminder> paydays(
        String frequency, {
        List<AllocationCycle> cycles = const [],
        String? source = 'Salary',
        required DateTime now,
      }) => planReminders(
        settings: settings,
        bills: const [],
        goals: const [],
        cycles: cycles,
        incomeFrequency: frequency,
        incomeSource: source,
        transactions: const [],
        now: now,
      ).where((r) => r.kind == ReminderKind.payday).toList();

      test('comes on payday at noon, then each day while pay is late', () {
        final planned = paydays(
          'Monthly',
          source: 'Allowance',
          cycles: [pay(DateTime(2026, 8, 7, 9), source: 'Allowance')],
          now: DateTime(2026, 9, 1, 10),
        );

        expect(planned.map((r) => r.at), [
          DateTime(2026, 9, 7, 12),
          DateTime(2026, 9, 8, 12),
          DateTime(2026, 9, 9, 12),
          DateTime(2026, 9, 10, 12),
          DateTime(2026, 10, 7, 12),
          DateTime(2026, 10, 8, 12),
          DateTime(2026, 10, 9, 12),
          DateTime(2026, 10, 10, 12),
        ], reason: 'a month after the last allowance, within six weeks');
        expect(planned.first.title, 'Payday today?');
        expect(
          planned.first.body,
          "Once your allowance is in, tap to log it. If it's late, you'll get "
          'another reminder tomorrow.',
        );
        expect(planned[1].title, 'Has your allowance come in?');
        expect(planned[1].body, "Payday was Sep 7. If it's in, tap to log it.");
        expect(planned.every((r) => r.payload == 'income'), isTrue);
      });

      test('late pay keeps asking until it is logged', () {
        final now = DateTime(2026, 9, 16, 10);
        final august = pay(DateTime(2026, 8, 30));

        final waiting = paydays('Semi-monthly', cycles: [august], now: now);
        expect(waiting.map((r) => '${r.title} @ ${r.at}').take(4), [
          'Has your salary come in? @ 2026-09-16 12:00:00.000',
          'Has your salary come in? @ 2026-09-17 12:00:00.000',
          'Has your salary come in? @ 2026-09-18 12:00:00.000',
          'Payday today? @ 2026-09-30 12:00:00.000',
        ], reason: "the 15th's own reminder has passed");

        // A gift isn't the salary.
        final gift = pay(DateTime(2026, 9, 16, 9), source: 'Gift');
        expect(
          paydays('Semi-monthly', cycles: [august, gift], now: now).first.at,
          DateTime(2026, 9, 16, 12),
        );

        final logged = paydays(
          'Semi-monthly',
          cycles: [august, pay(DateTime(2026, 9, 16, 9))],
          now: now,
        );
        expect(logged.first.at, DateTime(2026, 9, 30, 12));
        expect(logged.first.title, 'Payday today?');
      });

      test('no reminder without a set payday', () {
        final cycles = [pay(DateTime(2026, 9, 1))];
        final now = DateTime(2026, 9, 18);

        expect(paydays('Irregular', cycles: cycles, now: now), isEmpty);
        expect(
          paydays('Monthly', now: now),
          isEmpty,
          reason: 'the day is only known once pay is logged',
        );
        expect(
          paydays('Semi-monthly', now: now).first.at,
          DateTime(2026, 9, 30, 12),
          reason: 'twice a month has set days',
        );

        final off = ReminderSettings.fromProfile(
          profile(const [], reminders: {'payday': false}),
        );
        expect(
          planReminders(
            settings: off,
            bills: const [],
            goals: const [],
            cycles: cycles,
            incomeFrequency: 'Monthly',
            transactions: const [],
            now: now,
          ),
          isEmpty,
        );
      });

      test('the days pay is expected', () {
        expect(
          expectedPaydays(
            'Semi-monthly',
            lastPay: null,
            from: DateTime(2027, 2, 1),
            until: DateTime(2027, 3, 20),
          ),
          [DateTime(2027, 2, 15), DateTime(2027, 2, 28), DateTime(2027, 3, 15)],
        );
        expect(
          expectedPaydays(
            'Semi-monthly',
            lastPay: DateTime(2026, 9, 13),
            from: DateTime(2026, 9, 12),
            until: DateTime(2026, 10, 15),
          ),
          [DateTime(2026, 9, 30), DateTime(2026, 10, 15)],
          reason: 'paid two days early counts for the 15th',
        );
        expect(
          expectedPaydays(
            'Monthly',
            lastPay: DateTime(2026, 1, 31, 8),
            from: DateTime(2026, 2, 1),
            until: DateTime(2026, 4, 30),
          ),
          [DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30)],
          reason: 'the 31st stays the 31st after a short month',
        );
        expect(
          expectedPaydays(
            'Bi-weekly',
            lastPay: DateTime(2026, 9, 4),
            from: DateTime(2026, 9, 10),
            until: DateTime(2026, 10, 10),
          ),
          [DateTime(2026, 9, 18), DateTime(2026, 10, 2)],
        );
        expect(
          expectedPaydays(
            'Weekly',
            lastPay: DateTime(2026, 9, 11),
            from: DateTime(2026, 9, 8),
            until: DateTime(2026, 9, 30),
          ),
          [DateTime(2026, 9, 18), DateTime(2026, 9, 25)],
        );
      });

      test('the last payday is from the usual source', () {
        final salary = pay(DateTime(2026, 9, 1));
        final freelance = pay(DateTime(2026, 9, 10), source: 'Freelance');
        final refund = pay(DateTime(2026, 9, 12), source: 'Refund');

        expect(
          lastPayday([salary, freelance, refund], usualSource: 'salary'),
          DateTime(2026, 9, 1),
        );
        expect(
          lastPayday([salary, freelance, refund], usualSource: 'Business'),
          DateTime(2026, 9, 10),
          reason: 'no usual income on record: the newest that is not a refund',
        );
        expect(lastPayday([refund]), isNull);
      });
    });

    test('the same reminder keeps the same id', () {
      PlannedReminder reminder(String key, String title) => PlannedReminder(
        kind: ReminderKind.bills,
        key: key,
        at: DateTime(2026, 9, 25, 9),
        title: title,
        body: '',
        payload: '',
      );

      final first = reminder('bill-due:x', 'Internet is due today');
      expect(first.id, isPositive);
      expect(first.id, reminder('bill-due:x', 'renamed').id);
      expect(first.id, isNot(reminder('bill-early:x', '').id));
    });

    testWidgets('Home lists bills due soon, overdue first', (tester) async {
      BillInstance? opened;
      final now = DateTime(2026, 9, 18, 10);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: DueSoonNotice(
                now: now,
                onOpen: (b) => opened = b,
                bills: [
                  bill('Internet', DateTime(2026, 9, 19)),
                  bill('Rent', DateTime(2026, 9, 16), amount: 3000),
                  bill('Later', DateTime(2026, 9, 30)),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Bills due soon'), findsOneWidget);
      expect(find.text('2 days overdue'), findsOneWidget);
      expect(find.text('due tomorrow'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Rent')).dy,
        lessThan(tester.getTopLeft(find.text('Internet')).dy),
      );

      await tester.tap(find.text('Pay').last);
      expect(opened?.id, 'Internet');
    });

    group('settings screen', () {
      Future<void> pumpScreen(
        WidgetTester tester, {
        required Map<String, dynamic> data,
        bool permission = true,
        void Function(bool)? onEnabled,
        void Function(ReminderKind, bool?)? onKind,
        void Function(List<FinancialPriority>)? onPriorities,
      }) async {
        tester.view.physicalSize = const Size(800, 2600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: RemindersScreen(
              profile: Stream.value(data),
              requestPermission: () async => permission,
              sendTest: () async => true,
              onSetEnabled: onEnabled ?? (_) {},
              onSetKind: onKind ?? (_, _) {},
              onSetBillLeadDays: (_) {},
              onSetPriorities: onPriorities ?? (_) {},
            ),
          ),
        );
        await tester.pump();
      }

      const order = [
        FinancialPriority.payBills,
        FinancialPriority.saveForGoal,
        FinancialPriority.generalSavings,
        FinancialPriority.trackSpending,
      ];

      testWidgets('explains each reminder by the user\'s ranking', (
        tester,
      ) async {
        await pumpScreen(tester, data: profile(order));

        expect(
          find.text('Suggested: "Save toward a goal" is #2 for you.'),
          findsOneWidget,
        );
        expect(
          find.text('Off by default: "Just track my spending" is #4 for you.'),
          findsOneWidget,
        );
        expect(find.text('3 days before'), findsOneWidget);
      });

      testWidgets('moving a priority up saves the new order', (tester) async {
        List<FinancialPriority>? saved;
        await pumpScreen(
          tester,
          data: profile(order),
          onPriorities: (p) => saved = p,
        );

        await tester.tap(find.byTooltip('Move "Just track my spending" up'));
        expect(saved, [
          FinancialPriority.payBills,
          FinancialPriority.saveForGoal,
          FinancialPriority.trackSpending,
          FinancialPriority.generalSavings,
        ]);
      });

      testWidgets('a switch set back to the suggestion follows priorities', (
        tester,
      ) async {
        final calls = <String>[];
        await pumpScreen(
          tester,
          data: profile(order, reminders: {'dailyLog': true}),
          onKind: (kind, on) => calls.add('${kind.name}=$on'),
        );

        expect(find.text('Follow priorities'), findsOneWidget);

        final switches = find.byType(Switch);
        // Master, bills, payday, goals, leftover, logging.
        await tester.tap(switches.at(3));
        await tester.tap(switches.at(5));
        expect(calls, ['goals=false', 'dailyLog=null']);
      });

      testWidgets('payday is always suggested and can be turned off', (
        tester,
      ) async {
        final calls = <String>[];
        await pumpScreen(
          tester,
          data: profile(order),
          onKind: (kind, on) => calls.add('${kind.name}=$on'),
        );

        expect(find.text('Payday'), findsOneWidget);
        expect(
          find.text(
            'On payday at 12 PM, then daily for 3 days until you log it.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Always suggested: logged pay keeps Safe to Spend right.'),
          findsOneWidget,
        );

        await tester.tap(find.byType(Switch).at(2));
        expect(calls, ['payday=false']);
      });

      testWidgets('reminders stay off when Android blocks them', (
        tester,
      ) async {
        bool? enabled;
        await pumpScreen(
          tester,
          data: profile(order, allowed: false),
          permission: false,
          onEnabled: (value) => enabled = value,
        );

        await tester.tap(find.byType(Switch).first);
        await tester.pump();
        expect(enabled, isNull);
        expect(
          find.textContaining('Notifications are blocked for FinAssist'),
          findsOneWidget,
        );
      });
    });
  });
}
