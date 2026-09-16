import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/main.dart';
import 'package:testapp/models/onboarding_data.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/chatbot_screen.dart';
import 'package:testapp/screens/financial_setup_screen.dart';
import 'package:testapp/screens/forgot_password_screen.dart';
import 'package:testapp/screens/main_shell.dart';
import 'package:testapp/widgets/quick_add_sheet.dart';
import 'package:testapp/screens/splash_screen.dart';
import 'package:testapp/theme/app_colors.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/widgets/light_dark_toggle.dart';
import 'package:testapp/utils/categories.dart';
import 'package:testapp/utils/money_format.dart';
import 'package:testapp/widgets/money_text.dart';

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
}
