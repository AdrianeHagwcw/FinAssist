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
import 'package:testapp/services/bill_service.dart';
import 'package:testapp/services/budget_service.dart';
import 'package:testapp/models/transaction_filter.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/bill_calendar_screen.dart';
import 'package:testapp/screens/bill_detail_screen.dart';
import 'package:testapp/screens/chatbot_screen.dart';
import 'package:testapp/screens/set_aside_screen.dart';
import 'package:testapp/screens/debt_detail_screen.dart';
import 'package:testapp/screens/debts_screen.dart';
import 'package:testapp/screens/financial_setup_screen.dart';
import 'package:testapp/screens/forgot_password_screen.dart';
import 'package:testapp/screens/goals_screen.dart';
import 'package:testapp/screens/income_waterfall_screen.dart';
import 'package:testapp/screens/leftover_review_screen.dart';
import 'package:testapp/screens/login_screen.dart';
import 'package:testapp/screens/main_shell.dart';
import 'package:testapp/screens/home_screen.dart';
import 'package:testapp/screens/reports_screen.dart';
import 'package:testapp/screens/reminders_screen.dart';
import 'package:testapp/screens/register_screen.dart';
import 'package:testapp/widgets/quick_add_sheet.dart';
import 'package:testapp/screens/splash_screen.dart';
import 'package:testapp/services/launch_screen.dart';
import 'package:testapp/screens/transactions_screen.dart';
import 'package:testapp/screens/wallet_detail_screen.dart';
import 'package:testapp/screens/wallets_screen.dart';
import 'package:testapp/services/legacy_migration.dart';
import 'package:testapp/services/transaction_export.dart';
import 'package:testapp/theme/app_buttons.dart';
import 'package:testapp/theme/app_colors.dart';
import 'package:testapp/theme/app_icons.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/widgets/app_logo.dart';
import 'package:testapp/widgets/back_to_home.dart';
import 'package:testapp/widgets/bill_payment_sheet.dart';
import 'package:testapp/widgets/export_transactions_tile.dart';
import 'package:testapp/widgets/goal_funding_picker.dart';
import 'package:testapp/widgets/goal_sheets.dart';
import 'package:testapp/widgets/matured_savings_notice.dart';
import 'package:testapp/widgets/matured_savings_sheet.dart';
import 'package:testapp/widgets/set_aside_record_sheet.dart';
import 'package:testapp/widgets/legacy_import_card.dart';
import 'package:testapp/widgets/light_dark_toggle.dart';
import 'package:testapp/utils/date_format.dart';
import 'package:testapp/utils/categories.dart';
import 'package:testapp/utils/money_format.dart';
import 'package:testapp/utils/unique_name.dart';
import 'package:testapp/widgets/goal_progress.dart';
import 'package:testapp/widgets/interest_sheet.dart';
import 'package:testapp/widgets/savings_form_parts.dart';
import 'package:testapp/utils/income_sources.dart';
import 'package:testapp/widgets/money_text.dart';
import 'package:testapp/widgets/debt_form_sheet.dart';
import 'package:testapp/widgets/due_soon_notice.dart';
import 'package:testapp/widgets/safe_to_spend_card.dart';
import 'package:testapp/widgets/spending_chart.dart';
import 'package:testapp/widgets/transaction_row.dart';
import 'package:testapp/widgets/transfer_sheet.dart';
import 'package:testapp/widgets/wallet_picker.dart';
import 'package:testapp/widgets/wallet_form_sheet.dart';

void main() {
  test('secondary text is readable on every background, in both modes', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final (mode, colors) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      for (final (name, background) in [
        ('card', colors.card),
        ('page', colors.pageBackground),
        ('tint', colors.primaryTint),
      ]) {
        // 4.5 : 1 is what people need to read ordinary text.
        expect(
          contrast(colors.textMuted, background),
          greaterThanOrEqualTo(4.5),
          reason: '$mode secondary text on $name',
        );
        expect(
          contrast(colors.textBody, background),
          greaterThanOrEqualTo(4.5),
          reason: '$mode body text on $name',
        );
      }
    }
  });

  testWidgets('login screen can prefill email from verification recovery', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(initialEmail: 'ada@example.com'),
      ),
    );

    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .first
          .controller
          ?.text,
      'ada@example.com',
    );
  });

  testWidgets('login shows inline errors for missing credentials', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    await tester.ensureVisible(find.text('Log In'));
    await tester.tap(find.text('Log In'));
    await tester.pump();

    expect(find.text('Please enter your email.'), findsOneWidget);
    expect(find.text('Please enter your password.'), findsOneWidget);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].decoration?.errorText, 'Please enter your email.');
    expect(fields[1].decoration?.errorText, 'Please enter your password.');
  });

  testWidgets('login shows inline error for an invalid email', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'not-an-email');
    await tester.enterText(fields.at(1), 'password');
    await tester.ensureVisible(find.text('Log In'));
    await tester.tap(find.text('Log In'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    final emailField = tester.widget<TextField>(fields.first);
    expect(emailField.decoration?.errorText, 'Enter a valid email address.');

    // Still wrong while it is being fixed, and gone once it is right,
    // without tapping Log In again.
    await tester.enterText(fields.first, 'ada@example');
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    await tester.enterText(fields.first, 'ada@example.com');
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsNothing);
  });

  testWidgets('login shows nothing red before Log In is tapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    await tester.enterText(find.byType(TextField).first, 'ada@');
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsNothing);
  });

  testWidgets('login limits fields and hides counters until the limit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    // Room for any real email, and for a password manager's password.
    expect(
      tester.widgetList<TextField>(fields).map((field) => field.maxLength),
      [100, 128],
    );
    expect(find.text('0/100'), findsNothing);

    await tester.enterText(fields.first, 'a' * 120);
    await tester.pump();

    expect(find.text('100/100'), findsOneWidget);
    expect(tester.widget<TextField>(fields.first).controller?.text.length, 100);

    // An email has no spaces, so none go in.
    await tester.enterText(fields.first, 'ada @mail.com');
    await tester.pump();
    expect(
      tester.widget<TextField>(fields.first).controller?.text,
      'ada@mail.com',
    );
  });

  testWidgets('create account shows inline required field errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const RegisterScreen()),
    );

    await tester.ensureVisible(find.text('Create Account').last);
    await tester.tap(find.text('Create Account').last);
    await tester.pumpAndSettle();

    expect(find.text('This field is required.'), findsNWidgets(4));
    expect(find.byType(AlertDialog), findsNothing);

    final errorFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where(
          (field) =>
              field.decoration?.errorText != null ||
              field.decoration?.error != null,
        );
    expect(errorFields, hasLength(4));

    await tester.enterText(find.byType(TextField).first, 'Ada Lovelace');
    await tester.pump();
    expect(find.text('This field is required.'), findsNWidgets(3));
  });

  testWidgets('create account limits fields and filters full name characters', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const RegisterScreen()),
    );

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(4));
    // The same name limit as setup and Profile.
    expect(
      tester.widgetList<TextField>(fields).map((field) => field.maxLength),
      [40, 100, 128, 128],
    );
    expect(find.text('0/40'), findsNothing);

    // A hyphen belongs in a name; "!" does not.
    await tester.enterText(fields.first, 'Ada-Lovelace!${'a' * 60}');
    await tester.pump();

    final nameField = tester.widget<TextField>(fields.first);
    expect(nameField.controller?.text, 'Ada-Lovelace${'a' * 28}');
    expect(find.text('40/40'), findsOneWidget);

    // Filipino names fit as they are spelled.
    await tester.enterText(fields.first, "Ma. Niño O'Neil-Peña");
    await tester.pump();
    expect(
      tester.widget<TextField>(fields.first).controller?.text,
      "Ma. Niño O'Neil-Peña",
    );
  });

  testWidgets('the password rules are one line, then only what is missing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const RegisterScreen()),
    );

    final fields = find.byType(TextField);
    expect(
      tester.widget<TextField>(fields.at(2)).decoration?.helperText,
      'At least 6 characters, with a capital letter, a small letter, a '
      'number and a symbol like ! or @.',
    );

    await tester.enterText(fields.at(0), 'Ada Lovelace');
    await tester.enterText(fields.at(1), 'ada@example.com');
    await tester.enterText(fields.at(2), 'abc');
    await tester.ensureVisible(find.text('Create Account').last);
    await tester.tap(find.text('Create Account').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Still needed: at least 6 characters, a capital letter, a number '
        'and a symbol.',
      ),
      findsOneWidget,
    );

    // It shrinks as they are added, and goes once all are there.
    await tester.enterText(fields.at(2), 'Abcdef');
    await tester.pump();
    expect(find.text('Still needed: a number and a symbol.'), findsOneWidget);
    await tester.enterText(fields.at(2), 'Abc1!x');
    // The red line fades out.
    await tester.pumpAndSettle();
    expect(find.textContaining('Still needed'), findsNothing);

    // Typed twice the same, it says so.
    await tester.enterText(fields.at(3), 'Abc1!x');
    await tester.pump();
    expect(find.byKey(const Key('passwords-match')), findsOneWidget);
  });

  testWidgets('create account is a short email form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const RegisterScreen()),
    );

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    // One label per field, inside it.
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.decoration?.labelText),
      ['Full name', 'Email', 'Password', 'Confirm password'],
    );
  });

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

    // Android's launch screen shows the logo, so there is no welcome page:
    // Log In greets a new user itself.
    expect(find.text('Get Started'), findsNothing);
    expect(find.text('Welcome to FinAssist'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
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
    expect(find.text('Welcome to FinAssist'), findsOneWidget);
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
    expect(find.text('Welcome to FinAssist'), findsOneWidget);
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
              Text('Reports page'),
              Text('Wallet page'),
            ],
            quickAddActions: actions,
          ),
        ),
      );
    }

    testWidgets('has four tabs that switch in place', (tester) async {
      await pumpShell(tester, actions: const []);

      for (final label in ['Home', 'Transactions', 'Reports', 'Wallets']) {
        expect(find.text(label), findsOneWidget);
      }
      // Savings and debts are opened from Home, not from the bar.
      expect(find.text('Goals'), findsNothing);
      expect(find.text('Set aside'), findsNothing);

      await tester.tap(find.text('Wallets'));
      await tester.pump();
      expect(
        find.text('Wallet page').hitTestable(),
        findsOneWidget,
        reason: 'Wallet tab should be visible after tapping it',
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
              tab('Reports page'),
              tab('Wallet page'),
            ],
            quickAddActions: const [],
          ),
        ),
      );

      await tester.tap(find.text('Wallets'));
      await tester.pump();
      final back = find.byTooltip('Back to Home').hitTestable();
      expect(back, findsOneWidget);

      await tester.tap(back);
      await tester.pump();
      expect(find.text('Home page').hitTestable(), findsOneWidget);
    });

    testWidgets(
      'Home has the Quick Add actions without duplicating shortcuts',
      (tester) async {
        var opened = 0;
        var goalsOpened = 0;
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
                userName: 'Dave',
                wallets: Stream.value(const []),
                transactions: Stream.value(const []),
                goals: Stream.value(const <Goal>[]),
                safeToSpend: const SizedBox(height: 40),
                today: DateTime(2026, 9, 28),
                onOpenBills: () => opened++,
                onOpenGoals: () => goalsOpened++,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        for (final label in ['Expense', 'Income', 'Transfer']) {
          expect(find.text(label), findsOneWidget);
        }
        for (final label in [
          'Scan Receipt',
          'Voice Entry',
          'Bill Planner',
          'Savings',
          'Goals',
          'Installments',
          'Debts',
          'Reports',
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(find.text('View all'), findsOneWidget);
        expect(find.text('Add Income'), findsNothing);

        await tester.tap(find.text('View all'));
        await tester.pump();

        for (final label in [
          'Scan Receipt',
          'Voice Entry',
          'Bill Planner',
          'Savings',
          'Goals',
          'Installments',
          'Debts',
          'Reports',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('Show less'), findsOneWidget);

        // Goals has its own shortcut, where goals are added.
        final goalsTile = find
            .ancestor(of: find.text('Goals'), matching: find.byType(InkWell))
            .first;
        await tester.ensureVisible(goalsTile);
        await tester.tap(goalsTile);
        await tester.pump();
        expect(goalsOpened, 1);

        final tile = find
            .ancestor(
              of: find.text('Bill Planner'),
              matching: find.byType(InkWell),
            )
            .first;
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pump();

        expect(opened, 1);
      },
    );

    testWidgets('the + sheet holds six actions, Goals among them', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MainShell(
            pages: const [
              Text('Home page'),
              Text('Transactions page'),
              Text('Reports page'),
              Text('Wallet page'),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      for (final label in [
        'Expense',
        'Income',
        'Transfer',
        'Scan Receipt',
        'Voice Entry',
        'Goals',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // Saving toward a goal is done from the goal itself, in Goals.
      expect(find.text('Save to Goal'), findsNothing);
      // Setting up an installment happens once and belongs with the debts.
      expect(find.text('Installment'), findsNothing);
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

      await tester.tap(find.text('Wallets'));
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

  group('savings that have matured', () {
    Wallet deposit({
      String id = 'mp2',
      String name = 'Pag-IBIG MP2',
      double balance = 25000,
      DateTime? matures,
      bool archived = false,
    }) => Wallet(
      id: id,
      name: name,
      type: WalletType.other,
      balance: balance,
      startingBalance: balance,
      receivesIncome: false,
      archived: archived,
      sortOrder: 0,
      purpose: WalletPurpose.savings,
      savingsKind: SavingsKind.timeDeposit.name,
      maturityDate: matures,
    );

    final today = DateTime(2027, 3, 5);

    test('locked savings are counted apart from reachable ones', () {
      final cash = Wallet(
        id: 'piggy',
        name: 'Piggy bank',
        type: WalletType.other,
        balance: 5000,
        startingBalance: 5000,
        receivesIncome: false,
        archived: false,
        sortOrder: 1,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit.name,
      );
      final sss = deposit(id: 'sss', name: 'SSS', balance: 80000);
      final wallets = [cash, sss];

      expect(lockedSavingsBalance(wallets), 80000);
      // Both are still savings, so neither counts as spendable.
      expect(walletBalanceFor(wallets, WalletPurpose.savings), 85000);
      expect(cash.isLockedSavings, isFalse);
      expect(sss.isLockedSavings, isTrue);
    });

    test('a time deposit can fund a goal, ready on its end date', () {
      final td = Wallet(
        id: 'td',
        name: 'Time Deposit',
        type: WalletType.other,
        balance: 10000,
        startingBalance: 10000,
        receivesIncome: false,
        archived: false,
        sortOrder: 2,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.timeDeposit.name,
        maturityDate: DateTime(2027, 4, 25),
      );
      expect(goalFundingWallets([td]), [td]);
      expect(td.readyOn(DateTime(2026, 10, 25)), DateTime(2027, 4, 25));
      // From its end date on, there is nothing left to wait for.
      expect(td.readyOn(DateTime(2027, 4, 25)), isNull);

      // When it is taken out, the goals' money goes with it, the top goal
      // first.
      const tuition = Goal(
        id: 't',
        name: 'Tuition',
        targetAmount: 8000,
        savedAmount: 6000,
        priority: 0,
        status: GoalStatus.active,
        savedByWallet: {'td': 6000},
      );
      const trip = Goal(
        id: 'r',
        name: 'Trip',
        targetAmount: 9000,
        savedAmount: 3500,
        priority: 1,
        status: GoalStatus.active,
        savedByWallet: {'td': 3000, 'cash': 500},
      );
      expect(goalMoneyMoving([trip, tuition], from: 'td', moved: 10000), {
        tuition: 6000,
        trip: 3000,
      });
      expect(goalMoneyMoving([trip, tuition], from: 'td', moved: 7000), {
        tuition: 6000,
        trip: 1000,
      });
    });

    test('savings saved before these kinds existed stay reachable', () {
      final old = Wallet(
        id: 'old',
        name: 'Savings',
        type: WalletType.other,
        balance: 1200,
        startingBalance: 1200,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
      );

      expect(old.isLockedSavings, isFalse);
    });

    test(
      'time-deposit estimate uses the original term and does not alter balance',
      () {
        final timeDeposit = Wallet(
          id: 'td',
          name: 'Time Deposit',
          type: WalletType.other,
          balance: 10000,
          startingBalance: 10000,
          receivesIncome: false,
          archived: false,
          sortOrder: 0,
          purpose: WalletPurpose.savings,
          savingsKind: SavingsKind.timeDeposit.name,
          annualInterestRatePercent: 5,
          depositStartDate: DateTime(2023, 1, 1),
          maturityDate: DateTime(2024, 1, 1),
        );

        expect(timeDeposit.estimatedTimeDepositInterest(), 500);
        expect(timeDeposit.estimatedMaturityValue(), 10500);
        expect(timeDeposit.balance, 10000);
      },
    );

    test('savings-deposit estimate weights recorded transaction history', () {
      final savingsDeposit = Wallet(
        id: 'savings',
        name: 'Savings Deposit',
        type: WalletType.other,
        balance: 10500,
        startingBalance: 10000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit.name,
        annualInterestRatePercent: 5,
        depositStartDate: DateTime(2024, 1, 1),
        createdAt: DateTime(2024, 1, 1),
      );
      final transactions = [
        AppTransaction(
          id: 'add',
          type: TransactionType.income,
          amount: 1000,
          label: 'Deposit',
          date: DateTime(2024, 1, 11),
          walletId: 'savings',
        ),
        AppTransaction(
          id: 'take',
          type: TransactionType.expense,
          amount: 500,
          label: 'Withdrawal',
          date: DateTime(2024, 1, 21),
          walletId: 'savings',
        ),
      ];

      expect(
        savingsDeposit.estimatedSavingsDepositInterest(
          transactions: transactions,
          asOf: DateTime(2024, 2, 1),
        ),
        closeTo(325500 * 0.05 / 365, 0.000001),
      );
    });

    test('missing and future savings-deposit dates are safe', () {
      final future = Wallet(
        id: 'future',
        name: 'Future deposit',
        type: WalletType.other,
        balance: 1000,
        startingBalance: 1000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit.name,
        annualInterestRatePercent: 5,
        depositStartDate: DateTime(2025, 1, 1),
      );
      final missing = Wallet(
        id: 'missing',
        name: 'Missing date',
        type: WalletType.other,
        balance: 1000,
        startingBalance: 1000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit.name,
        annualInterestRatePercent: 5,
      );

      expect(
        future.estimatedSavingsDepositInterest(
          transactions: const [],
          asOf: DateTime(2024, 1, 1),
        ),
        0,
      );
      expect(
        missing.estimatedSavingsDepositInterest(
          transactions: const [],
          asOf: DateTime(2024, 1, 1),
        ),
        isNull,
      );
    });

    testWidgets('a record set up at sign up can still be fixed', (
      tester,
    ) async {
      String? name;
      double? recorded;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SetAsideRecordSheet(
              wallet: deposit(name: 'Pag-IBIG MP2', balance: 50000),
              onSave: (newName, newBalance) {
                name = newName;
                recorded = newBalance;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Opens on what was entered before.
      expect(find.text('Pag-IBIG MP2'), findsWidgets);
      expect(find.text('50000'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('set-aside-balance')),
        '5000',
      );
      await tester.enterText(
        find.byKey(const Key('set-aside-name')),
        'MP2 savings',
      );
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();

      expect(name, 'MP2 savings');
      expect(recorded, 5000, reason: 'a typo at sign up can be corrected');
    });

    testWidgets('older time deposits remain editable without new metadata', (
      tester,
    ) async {
      var saves = 0;
      final oldDeposit = Wallet(
        id: 'old-time',
        name: 'Old time deposit',
        type: WalletType.other,
        balance: 5000,
        startingBalance: 5000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.timeDeposit.name,
        maturityDate: DateTime(2027, 1, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SetAsideRecordSheet(
              wallet: oldDeposit,
              onSave: (_, _) => saves++,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('new-savings-timeDeposit')), findsNothing);
      expect(find.byKey(const Key('set-aside-interest-rate')), findsNothing);
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();
      expect(saves, 1);
    });

    testWidgets('cannot correct savings below the amount assigned to goals', (
      tester,
    ) async {
      var saves = 0;
      double? recorded;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SetAsideRecordSheet(
              wallet: deposit(name: 'Savings', balance: 2500),
              minimumBalance: 2500,
              onSave: (_, amount) {
                saves++;
                recorded = amount;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byKey(const Key('set-aside-balance')), '0');
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();

      expect(saves, 0);
      expect(
        find.textContaining('₱2,500 is already assigned to goals'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('set-aside-balance')),
        '2500',
      );
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();

      expect(saves, 1);
      expect(recorded, 2500);
    });

    testWidgets('savings left empty at sign up can be started later', (
      tester,
    ) async {
      String? name;
      double? recorded;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SetAsideRecordSheet(
              onSave: (newName, newBalance) {
                name = newName;
                recorded = newBalance;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Nothing to fix here, so it reads as adding rather than editing, and
      // it opens empty.
      expect(find.text('Add Savings'), findsWidgets);
      // The same look as setup's: tiles, then two facts about the chosen
      // kind.
      expect(find.text('What kind of savings?'), findsOneWidget);
      expect(find.text('Earns interest'), findsOneWidget);
      expect(find.text("Follows your bank's rules"), findsOneWidget);
      expect(
        find.byKey(const Key('new-savings-savingsDeposit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('new-savings-demandDeposit')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('set-aside-name')), findsNothing);
      expect(find.byKey(const Key('set-aside-interest-rate')), findsOneWidget);
      expect(find.byKey(const Key('set-aside-deposit-start')), findsOneWidget);
      expect(find.byKey(const Key('new-savings-maturity')), findsNothing);
      await tester.tap(find.byKey(const Key('new-savings-timeDeposit')));
      await tester.pump();
      expect(find.byKey(const Key('new-savings-maturity')), findsOneWidget);
      expect(find.byKey(const Key('set-aside-interest-rate')), findsOneWidget);

      // A time deposit is opened with its money in it: it can't start at
      // ₱0 and be filled later.
      await tester.enterText(find.byKey(const Key('set-aside-balance')), '0');
      await tester.ensureVisible(find.byKey(const Key('set-aside-save')));
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();
      expect(
        find.text(
          'A time deposit is opened with its money in it. Enter the amount '
          'you placed.',
        ),
        findsOneWidget,
      );
      expect(recorded, isNull);
      await tester.enterText(find.byKey(const Key('set-aside-balance')), '');
      await tester.ensureVisible(
        find.byKey(const Key('new-savings-demandDeposit')),
      );

      await tester.tap(find.byKey(const Key('new-savings-demandDeposit')));
      await tester.pump();
      expect(find.byKey(const Key('set-aside-interest-rate')), findsNothing);
      expect(find.byKey(const Key('set-aside-deposit-start')), findsNothing);
      expect(find.byKey(const Key('new-savings-maturity')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('set-aside-balance')),
        '20000',
      );
      await tester.ensureVisible(find.byKey(const Key('set-aside-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();

      expect(name, 'Demand Deposit');
      expect(recorded, 20000);
    });

    testWidgets('new savings can be moved in from the wallets', (tester) async {
      tester.view.physicalSize = const Size(700, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      String? name;
      Map<String, double>? from;
      double? recorded;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SetAsideRecordSheet(
                wallets: [cash],
                // ₱1,000 of the cash is a goal's.
                goals: Stream.value(const [
                  Goal(
                    id: 'g',
                    name: 'Trip',
                    targetAmount: 5000,
                    savedAmount: 1000,
                    priority: 0,
                    status: GoalStatus.active,
                    savedByWallet: {'cash': 1000},
                  ),
                ]),
                onSave: (n, amount) => recorded = amount,
                onMoveIn: (n, amounts) {
                  name = n;
                  from = amounts;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // It starts as before: the money is already in the account.
      expect(find.text('Where is this money?'), findsOneWidget);
      expect(find.byKey(const Key('set-aside-balance')), findsOneWidget);
      expect(
        find.text('Recorded as it is. Nothing leaves your wallets.'),
        findsOneWidget,
      );

      // A demand deposit asks no rate, so only the money is left to say.
      await tester.tap(find.byKey(const Key('new-savings-demandDeposit')));
      await tester.pump();

      // Moving it in now: the same picker as goals, no balance to type.
      await tester.ensureVisible(
        find.byKey(const Key('savings-source-wallets')),
      );
      await tester.tap(find.byKey(const Key('savings-source-wallets')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('set-aside-balance')), findsNothing);
      expect(find.text('Which wallets is it coming from?'), findsOneWidget);
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();

      // Only what is free can move: ₱4,000, not the goal's ₱1,000.
      await tester.enterText(
        find.byKey(const Key('goal-funding-cash')),
        '4500',
      );
      await tester.pump();
      expect(
        find.textContaining('Only ₱4,000 in Cash is free'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('goal-funding-cash')),
        '3000',
      );
      await tester.pump();
      expect(find.text('Moving into this savings'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('set-aside-save')));
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pumpAndSettle();
      expect(name, 'Demand Deposit');
      expect(from, {'cash': 3000});
      expect(recorded, isNull, reason: 'moved in, not typed in');
    });

    testWidgets('a new record left unnamed is called after its type', (
      tester,
    ) async {
      String? name;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SetAsideRecordSheet(
              wallets: [deposit(name: 'Demand Deposit', balance: 500)],
              onSave: (newName, _) => name = newName,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('new-savings-demandDeposit')));
      await tester.pump();
      // An empty record is entered as 0.
      await tester.enterText(find.byKey(const Key('set-aside-balance')), '0');
      // A type name already exists, so the new record gets a unique suffix.
      await tester.ensureVisible(find.byKey(const Key('set-aside-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();

      expect(name, 'Demand Deposit 2');
    });

    testWidgets(
      'interest-bearing savings require a valid rate and start date',
      (tester) async {
        // Tall enough for the whole form, rate choices included.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var saves = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SetAsideRecordSheet(onSave: (_, _) => saves++),
            ),
          ),
        );
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('set-aside-balance')),
          '100',
        );
        await tester.ensureVisible(find.byKey(const Key('set-aside-save')));
        await tester.tap(find.byKey(const Key('set-aside-save')));
        await tester.pump();

        // Both problems at once, each under its own field.
        expect(find.text('Enter a rate from 0% to 100%.'), findsOneWidget);
        expect(find.text('Choose the start date.'), findsOneWidget);
        expect(saves, 0);

        await tester.enterText(
          find.byKey(const Key('set-aside-interest-rate')),
          '5',
        );
        await tester.ensureVisible(find.byKey(const Key('set-aside-save')));
        await tester.tap(find.byKey(const Key('set-aside-save')));
        // The old message fades out before it is gone.
        await tester.pumpAndSettle();
        expect(find.text('Enter a rate from 0% to 100%.'), findsNothing);
        expect(find.text('Choose the start date.'), findsOneWidget);
        expect(saves, 0);
      },
    );

    testWidgets('each kind can be read about where it is chosen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: SetAsideRecordSheet(onSave: (_, _) {})),
        ),
      );
      await tester.pump();

      // The chosen kind always has its own "Read about" link, so no kind is
      // left unexplained.
      for (final kind in const [
        SavingsKind.timeDeposit,
        SavingsKind.demandDeposit,
        SavingsKind.savingsDeposit,
      ]) {
        await tester.tap(find.byKey(Key('new-savings-${kind.name}')));
        await tester.pump();
        expect(find.byKey(Key('explain-savings-${kind.name}')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('new-savings-timeDeposit')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('explain-savings-timeDeposit')),
      );
      await tester.tap(find.byKey(const Key('explain-savings-timeDeposit')));
      await tester.pumpAndSettle();

      expect(find.text('Watch out for'), findsOneWidget);
      expect(find.textContaining('leave in a bank'), findsOneWidget);
      // Its two facts are labeled cards, and it shows the same lock as its
      // tile in the form.
      expect(find.text('Risk'), findsOneWidget);
      // The same label as under the choice in the form behind it.
      expect(find.text('Taking money out'), findsNWidgets(2));
      expect(find.text('Locked until the agreed date'), findsOneWidget);
      expect(
        find.image(const AssetImage('assets/icons/icons8-lock-96.png')),
        findsWidgets,
      );
      // Going ahead is green; closing is red.
      ButtonStyle? styleOf(String text) => tester
          .widget<ElevatedButton>(
            find.ancestor(
              of: find.text(text),
              matching: find.byType(ElevatedButton),
            ),
          )
          .style;
      expect(
        styleOf('Use this')?.backgroundColor?.resolve({}),
        appConfirmGreen,
      );
      expect(styleOf('Close')?.backgroundColor?.resolve({}), appDangerRed);

      // Reading about it is also how it gets picked.
      await tester.ensureVisible(find.text('Use this'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('new-savings-maturity')),
        findsOneWidget,
        reason: 'time deposits require a maturity date',
      );
    });

    testWidgets('an empty name or a negative balance is refused', (
      tester,
    ) async {
      var saves = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SetAsideRecordSheet(
              wallet: deposit(name: 'Savings', balance: 1000),
              onSave: (_, _) => saves++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byKey(const Key('set-aside-name')), '');
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();
      expect(find.text('Give it a name.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('set-aside-name')),
        'Savings',
      );
      // A minus sign cannot be typed into an amount at all now, so a
      // negative never reaches the check behind it.
      await tester.enterText(find.byKey(const Key('set-aside-balance')), '-5');
      expect(find.text('-5'), findsNothing);
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();
      expect(saves, 1, reason: '₱5 is a balance a record can hold');
    });

    test('a record is matured on its day, not before', () {
      expect(deposit(matures: DateTime(2027, 3, 6)).maturedBy(today), isFalse);
      expect(deposit(matures: today).maturedBy(today), isTrue);
      expect(deposit(matures: DateTime(2027, 3, 4)).maturedBy(today), isTrue);
    });

    test('nothing matures without a date, money or a live record', () {
      expect(deposit().maturedBy(today), isFalse, reason: 'no date set');
      expect(
        deposit(matures: today, balance: 0).maturedBy(today),
        isFalse,
        reason: 'nothing left in it',
      );
      expect(
        deposit(matures: today, archived: true).maturedBy(today),
        isFalse,
        reason: 'archived records are not chased',
      );
    });

    test('only savings records are picked up', () {
      final spending = Wallet(
        id: 'cash',
        name: 'Cash',
        type: WalletType.cash,
        balance: 500,
        startingBalance: 500,
        receivesIncome: true,
        archived: false,
        sortOrder: 0,
        maturityDate: today,
      );

      expect(maturedSavings([spending, deposit(matures: today)], today), [
        isA<Wallet>().having((w) => w.id, 'id', 'mp2'),
      ]);
    });

    testWidgets('a time deposit starts on its balance plus the interest', (
      tester,
    ) async {
      DateTime? renewedTo;
      double? interest;
      final timeDeposit = Wallet(
        id: 'td',
        name: 'Time Deposit',
        type: WalletType.other,
        balance: 10000,
        startingBalance: 10000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.timeDeposit.name,
        annualInterestRatePercent: 3,
        depositStartDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2027, 1, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MaturedSavingsSheet(
              wallet: timeDeposit,
              wallets: [timeDeposit],
              onRollOver: (next, earned) {
                renewedTo = next;
                interest = earned;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // ₱10,000 × 3% for 365 days = ₱300, less the 20% tax banks keep.
      expect(find.text('10240'), findsOneWidget);
      expect(
        find.text(
          'Starts on ₱10,000 plus about ₱240 interest after tax. Change it '
          'to what your bank paid.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('₱240 above the recorded balance'),
        findsOneWidget,
      );

      // Renewed with the interest: it is kept as income in the deposit.
      await tester.tap(find.byKey(const Key('matured-rollover')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(renewedTo, isNotNull);
      expect(interest, 240);
    });

    test('the end-date reminder says what interest to look for', () {
      final timeDeposit = Wallet(
        id: 'td',
        name: 'Time Deposit',
        type: WalletType.other,
        balance: 10000,
        startingBalance: 10000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.timeDeposit.name,
        annualInterestRatePercent: 3,
        depositStartDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2027, 1, 1),
      );
      final planned = planReminders(
        settings: const ReminderSettings(enabled: true, priorities: []),
        bills: const [],
        goals: const [],
        cycles: const [],
        wallets: [timeDeposit],
        transactions: const [],
        now: DateTime(2026, 12, 30),
      ).where((r) => r.key == 'savings:td:matured');
      expect(
        planned.single.body,
        '₱10,000 is recorded, plus about ₱240 interest after tax. Open '
        'FinAssist to say what you got back.',
      );
    });

    testWidgets('the sheet says what a part withdrawal leaves behind', (
      tester,
    ) async {
      double? received;
      Map<String, double>? destination;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MaturedSavingsSheet(
              wallet: deposit(matures: today),
              wallets: [
                deposit(matures: today),
                Wallet(
                  id: 'cash',
                  name: 'Cash',
                  type: WalletType.cash,
                  balance: 500,
                  startingBalance: 500,
                  receivesIncome: true,
                  archived: false,
                  sortOrder: 1,
                ),
              ],
              onSettle: (amount, to) {
                received = amount;
                destination = to;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Prefilled with the whole balance.
      expect(find.text('This record closes.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('matured-amount')), '5000');
      await tester.pump();
      expect(
        find.text('₱20,000 stays in Pag-IBIG MP2.'),
        findsOneWidget,
        reason: 'what stays behind is shown before saving',
      );

      await tester.enterText(find.byKey(const Key('matured-amount')), '27000');
      await tester.pump();
      expect(
        find.textContaining('₱2,000 above the recorded balance'),
        findsOneWidget,
        reason: 'interest is named rather than invented',
      );

      // Where it went: Cash on Hand, filled with all of it.
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('matured-settle')));
      await tester.tap(find.byKey(const Key('matured-settle')));
      await tester.pump();

      expect(received, 27000);
      expect(destination, {'cash': 27000});
    });
  });

  group('setup savings and goals', () {
    OnboardingSavingsAccount record(String name, double balance) =>
        OnboardingSavingsAccount(
          name: name,
          kind: SavingsKind.savingsDeposit,
          balance: balance,
        );

    OnboardingGoal goal(
      String name,
      double target, {
      String? fundedBy,
      double allocated = 0,
    }) => OnboardingGoal(
      name: name,
      kind: GoalKind.emergencyFund,
      targetAmount: target,
      targetDate: null,
      frequency: ContributionFrequency.monthly,
      planAmount: null,
      note: null,
      fundedBy: fundedBy,
      allocated: allocated,
    );

    test('setting money aside leaves the savings balance alone', () {
      final personal = record('Personal Savings', 15000);
      final fund = goal(
        'Emergency Fund',
        30000,
        fundedBy: 'Personal Savings',
        allocated: 5000,
      );

      expect(personal.balance, 15000, reason: 'the record is untouched');
      expect(unallocatedSavings(personal, [fund]), 10000);
      expect(fund.allocated, 5000);
      expect(fund.remaining, 25000);
      expect(fund.progress, closeTo(0.1667, 0.0001));
      expect(fund.isReached, isFalse);
    });

    test('two goals cannot promise the same money twice', () {
      final personal = record('Personal Savings', 15000);
      final first = goal(
        'Laptop',
        20000,
        fundedBy: 'Personal Savings',
        allocated: 9000,
      );
      final second = goal(
        'Tuition',
        20000,
        fundedBy: 'Personal Savings',
        allocated: 4000,
      );

      expect(unallocatedSavings(personal, [first, second]), 2000);
      // What a goal may claim leaves out what it already holds.
      expect(
        unallocatedSavings(personal, [first, second], ignoring: second),
        6000,
      );
    });

    test('a goal is reached once the whole target is set aside', () {
      final reached = goal(
        'Phone',
        5000,
        fundedBy: 'Personal Savings',
        allocated: 5000,
      );

      expect(reached.isReached, isTrue);
      expect(reached.remaining, 0);
      expect(reached.progress, 1);
    });

    test('a goal with no funding source holds nothing', () {
      final lonely = goal('Someday', 1000);

      expect(lonely.fundedBy, isNull);
      expect(lonely.allocated, 0);
      expect(lonely.remaining, 1000);
      expect(lonely.progress, 0);
    });

    test('releasing the funding clears what was set aside', () {
      final funded = goal(
        'Laptop',
        20000,
        fundedBy: 'Personal Savings',
        allocated: 9000,
      );
      final released = funded.copyWith(clearFunding: true);

      expect(released.fundedBy, isNull);
      expect(released.allocated, 0);
      expect(
        unallocatedSavings(record('Personal Savings', 15000), [released]),
        15000,
      );
    });

    test('a record never shows less than nothing free', () {
      // A balance cut below what goals already hold cannot go negative.
      final shrunk = record('Personal Savings', 1000);
      final heavy = goal(
        'Laptop',
        20000,
        fundedBy: 'Personal Savings',
        allocated: 9000,
      );

      expect(unallocatedSavings(shrunk, [heavy]), 0);
    });

    test('goal funding uses identified accounts without moving balances', () {
      Wallet wallet(
        String id,
        WalletType type,
        double balance, {
        bool archived = false,
        WalletPurpose purpose = WalletPurpose.spending,
        String? savingsKind,
      }) => Wallet(
        id: id,
        name: id,
        type: type,
        balance: balance,
        startingBalance: balance,
        receivesIncome: false,
        archived: archived,
        sortOrder: 0,
        purpose: purpose,
        savingsKind: savingsKind,
      );

      final cash = wallet('cash', WalletType.cash, 1000);
      final bank = wallet('bank', WalletType.bank, 5000);
      final ewallet = wallet('ewallet', WalletType.gcash, 2500);
      final unsupported = wallet('other', WalletType.other, 2000);
      final archived = wallet('archived', WalletType.cash, 900, archived: true);
      // A time deposit can fund a goal too: it counts now, ready on its end
      // date.
      final timeDeposit = wallet(
        'deposit',
        WalletType.other,
        8000,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.timeDeposit.name,
      );
      final eligible = goalFundingWallets([
        cash,
        bank,
        ewallet,
        unsupported,
        archived,
        timeDeposit,
      ]);

      expect(eligible.map((item) => item.id), [
        'cash',
        'bank',
        'ewallet',
        'deposit',
      ]);

      final goal = Goal(
        id: 'goal',
        name: 'Laptop',
        targetAmount: 2000,
        savedAmount: 600,
        priority: 0,
        status: GoalStatus.active,
        walletId: cash.id,
        fundingSource: GoalFundingSource.cash,
        savedByWallet: {'cash': 350, 'bank': 250},
      );
      expect(freeInWallet(cash, [goal]), 650);
      expect(freeInWallet(bank, [goal]), 4750);
      expect(totalSetAsideInSpendingWallets([goal], [cash, bank]), 600);
      expect(cash.balance, 1000);
      expect(bank.balance, 5000);
    });

    test('goal funding source parses from saved goal data', () {
      expect(
        Goal.fromMap('cash-goal', {'fundingSource': 'cash'}).fundingSource,
        GoalFundingSource.cash,
      );
      expect(
        Goal.fromMap('bank-goal', {'fundingSource': 'bank'}).fundingSource,
        GoalFundingSource.bank,
      );
      expect(
        Goal.fromMap('wallet-goal', {'fundingSource': 'ewallet'}).fundingSource,
        GoalFundingSource.ewallet,
      );
      expect(Goal.fromMap('legacy-goal', {}).fundingSource, isNull);
    });

    test('onboarding does not invent savings-deposit history before setup', () {
      final savings = OnboardingSavingsAccount(
        name: 'Savings Deposit',
        kind: SavingsKind.savingsDeposit,
        balance: 10000,
        annualInterestRatePercent: 5,
        depositStartDate: DateTime(2020, 1, 1),
      );
      final demand = OnboardingSavingsAccount(
        name: 'Demand Deposit',
        kind: SavingsKind.demandDeposit,
        balance: 10000,
      );

      expect(savings.estimatedSimpleInterest, 0);
      expect(demand.estimatedSimpleInterest, 0);
    });

    test('the kinds used before map onto the three that are offered', () {
      // Only the three deposit kinds remain.
      expect(SavingsKind.values, [
        SavingsKind.savingsDeposit,
        SavingsKind.demandDeposit,
        SavingsKind.timeDeposit,
      ]);
      expect(SavingsKind.fromName('timeDeposit'), SavingsKind.timeDeposit);
      expect(
        SavingsKind.fromName('savingsDeposit'),
        SavingsKind.savingsDeposit,
      );
      expect(SavingsKind.fromName('demandDeposit'), SavingsKind.demandDeposit);
      // Older kinds read as the closest one.
      expect(
        SavingsKind.fromName('savingsAccount'),
        SavingsKind.savingsDeposit,
      );
      expect(SavingsKind.fromName('account'), SavingsKind.savingsDeposit);
      expect(SavingsKind.fromName('emergencyFund'), SavingsKind.savingsDeposit);
      expect(SavingsKind.fromName(null), SavingsKind.savingsDeposit);
      // Government savings, like SSS or Pag-IBIG MP2, is locked like a time
      // deposit.
      expect(SavingsKind.fromName('government'), SavingsKind.timeDeposit);
      expect(SavingsKind.timeDeposit.isLockedAway, isTrue);
      expect(SavingsKind.savingsDeposit.isLockedAway, isFalse);
      expect(SavingsKind.demandDeposit.isLockedAway, isFalse);
    });

    test('only a regular goal or an emergency fund can be chosen', () {
      expect(GoalKind.choosable, [GoalKind.regular, GoalKind.emergencyFund]);
      // Older goals still read back with their own kind.
      expect(GoalKind.fromName('timeDeposit'), GoalKind.timeDeposit);
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

    // Cash Summary, then Savings and Bills, then Goals.
    Future<void> cashSummaryToGoals(WidgetTester tester) async {
      await tapText(tester, 'Next');
      expect(find.text('Build your savings'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Add bill reminders'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Set up your goals'), findsOneWidget);
    }

    // Setup wallet ids are generated, so the amount boxes are found in the
    // order they show: cash first, then each added account.
    Finder fundingField(int index) => find
        .byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'goal-funding-',
              ),
        )
        .at(index);

    testWidgets('setup name takes any language, and nothing hidden', (
      tester,
    ) async {
      await pumpOnboarding(tester, save: (_) async {});

      await tapText(tester, 'Get Started');
      final nameField = find.byType(TextFormField).first;
      String typed() =>
          tester.widget<TextFormField>(nameField).controller!.text;

      await tester.enterText(nameField, 'Ada-Lovelace!123');
      await tester.pump();
      expect(typed(), 'Ada-Lovelace123');

      // Ñ, accents, "Ma." and an apostrophe all stay.
      await tester.enterText(nameField, "Ma. Niño O'Neil-Peña");
      await tester.pump();
      expect(typed(), "Ma. Niño O'Neil-Peña");

      // Emoji, symbols and a pasted page do not get in.
      await tester.enterText(nameField, 'Dave 😀<script>${'x' * 80}');
      await tester.pump();
      expect(typed().length, 40);
      expect(typed(), startsWith('Dave script'));

      // Dots alone are not a name.
      await tester.enterText(nameField, '...');
      await tapText(tester, 'Next');
      expect(find.text('Your name needs at least one letter.'), findsOneWidget);
      expect(find.text('What should we call you?'), findsOneWidget);
    });

    testWidgets('a blocked notification prompt still moves on', (tester) async {
      OnboardingData? saved;
      await pumpOnboarding(
        tester,
        save: (data) async => saved = data,
        allowNotifications: false,
      );

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');
      await tapText(tester, 'Add a Wallet');
      expect(find.text('Current balance'), findsOneWidget);
      // An empty wallet is entered as 0; a blank is not accepted.
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '0',
      );
      await tapText(tester, 'Add Wallet');
      expect(find.text('Cash'), findsNWidgets(2));
      await tapText(tester, 'Next');
      expect(find.text('Cash Summary'), findsOneWidget);
      expect(find.text('Cash on Hand'), findsOneWidget);
      expect(find.text('₱0'), findsNWidgets(4));
      await cashSummaryToGoals(tester);
      expect(find.text('Step 7 of 10'), findsOneWidget);
      expect(find.text('Set up your goals'), findsOneWidget);
      await tapText(tester, 'Next');
      await tapText(tester, 'Allow Reminders');
      // Reminders stayed off, so the ranking is never asked.
      expect(find.text('What should we remind you about most?'), findsNothing);
      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('Step 9 of 9'), findsOneWidget);
      expect(find.text('Remind me most about'), findsNothing);
      // Back skips the ranking too.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Allow Reminders'), findsOneWidget);
      await tapText(tester, 'Allow Reminders');
      expect(find.text('Check your answers'), findsOneWidget);
      await tapText(tester, 'Continue');

      expect(find.text("You're ready, Dave!"), findsOneWidget);
      await tester.ensureVisible(find.text('Go to Dashboard'));
      await tester.tap(find.text('Go to Dashboard'));
      await tester.pump();
      await tester.pump();
      expect(saved, isNotNull);
      expect(saved!.wallets.single.startingBalance, 0);
    });

    testWidgets('wallets of the same name are numbered', (tester) async {
      OnboardingData? saved;
      await pumpOnboarding(tester, save: (data) async => saved = data);

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');

      // Every setup wallet needs a balance, even when it is 0.
      Future<void> addEmptyCash(String button, {String? name}) async {
        await tapText(tester, button);
        // Naming cash is optional, with an example to follow.
        expect(find.text('Name (optional)'), findsOneWidget);
        expect(find.text('e.g. Petty Cash'), findsOneWidget);
        if (name != null) {
          await tester.enterText(
            find.byKey(const Key('wallet-cash-name')),
            name,
          );
        }
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          '0',
        );
        await tapText(tester, 'Add Wallet');
      }

      // The first keeps its name; a repeat gets the next number.
      await addEmptyCash('Add a Wallet');
      await addEmptyCash('Add Another');

      expect(find.text('Cash 1'), findsNothing);
      expect(find.text('Cash 2'), findsOneWidget);

      // A third of the same name keeps counting.
      await addEmptyCash('Add Another');
      expect(find.text('Cash 3'), findsOneWidget);

      // Deleting asks first, and Cancel keeps the wallet.
      await tester.tap(find.byTooltip('Delete Cash 3'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Cash 3?'), findsOneWidget);
      expect(
        find.text('This wallet will be removed. You can add it again later.'),
        findsOneWidget,
      );
      await tapText(tester, 'Cancel');
      expect(find.text('Cash 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete Cash 3'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      expect(find.text('Cash 3'), findsNothing);

      // Numbers only go up from the highest one left.
      await addEmptyCash('Add Another');
      expect(find.text('Cash 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete Cash 3'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');

      await tester.tap(find.byTooltip('Delete Cash 2'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      expect(find.text('Cash 2'), findsNothing);
      expect(find.byTooltip('Delete Cash'), findsOneWidget);

      // Any name works the same way, whatever its case.
      await addEmptyCash('Add Another', name: 'Petty Cash');
      await addEmptyCash('Add Another', name: 'petty cash');
      expect(find.text('Petty Cash'), findsOneWidget);
      expect(find.text('Petty Cash 2'), findsOneWidget);

      await tapText(tester, 'Next');
      expect(find.text('Cash Summary'), findsOneWidget);
      await cashSummaryToGoals(tester);
      await tapText(tester, 'Next');
      await tapText(tester, 'Allow Reminders');
      await tapText(tester, 'Next');
      await tapText(tester, 'Continue');
      await tester.ensureVisible(find.text('Go to Dashboard'));
      await tester.tap(find.text('Go to Dashboard'));
      await tester.pump();
      await tester.pump();
      expect(saved!.wallets.map((w) => w.name), [
        'Cash',
        'Petty Cash',
        'Petty Cash 2',
      ]);
    });

    testWidgets(
      'starting wallets can be edited without changing income routing',
      (tester) async {
        OnboardingData? saved;
        await pumpOnboarding(tester, save: (data) async => saved = data);
        await tapText(tester, 'Get Started');
        await tester.enterText(find.byType(TextFormField), 'Dave');
        await tapText(tester, 'Next');
        await tapText(tester, 'Add a Wallet');
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          '100',
        );
        await tapText(tester, 'Add Wallet');
        await tapText(tester, 'Add Another');
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          '0',
        );
        await tapText(tester, 'Add Wallet');

        Future<void> editCash() async {
          await tester.ensureVisible(find.byTooltip('Edit Cash'));
          await tester.tap(find.byTooltip('Edit Cash'));
          await tester.pumpAndSettle();
        }

        await editCash();
        expect(find.text('Edit Wallet'), findsOneWidget);
        expect(find.text('100'), findsOneWidget);
        // The cash name field shows the name it has.
        expect(find.text('Name (optional)'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          '250.50',
        );
        await tapText(tester, 'Save Changes');
        // Saving without a new name keeps both names as they were.
        expect(find.byTooltip('Edit Cash'), findsOneWidget);
        expect(find.text('Cash 2'), findsOneWidget);

        // Dismissing an edit must not change the saved draft.
        await editCash();
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          '999',
        );
        Navigator.of(tester.element(find.byType(WalletFormSheet))).pop();
        await tester.pumpAndSettle();
        await editCash();
        expect(find.text('250.50'), findsOneWidget);
        await tapText(tester, 'E-Wallets');
        final ewalletDropdown = find.byKey(
          const Key('wallet-ewallet-dropdown'),
        );
        final ewalletField = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: ewalletDropdown,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        ewalletField.onChanged!('GCash');
        await tester.pump();
        await tapText(tester, 'Save Changes');

        await tapText(tester, 'Next');
        expect(find.text('Cash Summary'), findsOneWidget);
        await cashSummaryToGoals(tester);
        await tapText(tester, 'Next');
        await tapText(tester, 'Allow Reminders');
        await tapText(tester, 'Next');
        await tapText(tester, 'Continue');
        await tester.ensureVisible(find.text('Go to Dashboard'));
        await tester.tap(find.text('Go to Dashboard'));
        await tester.pump();
        await tester.pump();
        // The other keeps its number: names never change by themselves.
        expect(saved!.wallets.map((w) => w.name), ['GCash', 'Cash 2']);
        expect(saved!.wallets.map((w) => w.startingBalance), [250.5, 0]);
        expect(saved!.wallets.map((w) => w.type), [
          WalletType.ewallet,
          WalletType.cash,
        ]);
        expect(saved!.wallets.map((w) => w.receivesIncome), [true, false]);
      },
    );

    testWidgets('editing a saved wallet still hides its balance field', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: WalletFormSheet(
              existing: Wallet(
                id: 'cash',
                name: 'Pocket',
                type: WalletType.cash,
                balance: 250,
                startingBalance: 100,
                receivesIncome: true,
                archived: false,
                sortOrder: 0,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Edit Wallet'), findsOneWidget);
      expect(find.text('Current balance'), findsNothing);
      // Only the optional name can be typed, and it shows the name it has.
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Name (optional)'), findsOneWidget);
      expect(find.text('Pocket'), findsOneWidget);
      expect(
        find.byKey(const Key('wallet-annual-interest-rate')),
        findsNothing,
      );
    });

    testWidgets('every wallet needs a balance in setup, and 0 is accepted', (
      tester,
    ) async {
      WalletDraft? result;
      Future<void> open({WalletDraft? draft}) async {
        result = null;
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => result = await showWalletFormSheet(
                    context,
                    initialDraft: draft,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      Future<void> pickBank() async {
        await tester.tap(find.byKey(const Key('wallet-type-bank')));
        await tester.pumpAndSettle();
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: find.byKey(const Key('wallet-bank-dropdown')),
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .onChanged!('BDO Unibank');
        await tester.pump();
      }

      // Blank is refused for a bank: it would drop out of every total.
      await open();
      await pickBank();
      expect(
        find.text("Check your bank app or passbook. Enter 0 if it's empty."),
        findsOneWidget,
      );
      await tester.tap(find.text('Add Wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the balance, or 0 if empty.'), findsOneWidget);
      expect(result, isNull);

      // ₱0 is a real balance, so it is saved as one.
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '0',
      );
      await tester.tap(find.text('Add Wallet'));
      await tester.pumpAndSettle();
      expect(result?.type, WalletType.bank);
      expect(result?.startingBalance, 0);
      expect(result?.balanceRecorded, isTrue);

      // Cash and e-wallets need one too, each told where to look.
      await open();
      expect(
        find.text('Count what you have on hand. Enter 0 if none.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Add Wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the balance, or 0 if empty.'), findsOneWidget);
      expect(result, isNull);
      await open();
      await tester.tap(find.byKey(const Key('wallet-type-ewallet')));
      await tester.pumpAndSettle();
      expect(
        find.text("Check your e-wallet app. Enter 0 if it's empty."),
        findsOneWidget,
      );
      // The balance is no longer optional; the interest rate still is.
      expect(
        find.textContaining('Leave blank if you do not know'),
        findsNothing,
      );

      // A wallet saved without a balance counts one once it is typed in.
      await open(
        draft: const WalletDraft(
          type: WalletType.cash,
          name: 'Cash',
          startingBalance: 0,
          balanceRecorded: false,
        ),
      );
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '1500',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(result?.startingBalance, 1500);
      expect(result?.balanceRecorded, isTrue);

      // An older bank wallet saved without one needs it when edited.
      await open(
        draft: const WalletDraft(
          type: WalletType.bank,
          name: 'BDO Unibank',
          startingBalance: 0,
          balanceRecorded: false,
        ),
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the balance, or 0 if empty.'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('naming cash is optional, and it keeps the name it has', (
      tester,
    ) async {
      WalletDraft? result;
      Future<void> edit(
        WalletDraft draft, {
        WalletType? switchTo,
        String? rename,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => result = await showWalletFormSheet(
                    context,
                    initialDraft: draft,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        if (switchTo != null) {
          await tester.tap(find.byKey(Key('wallet-type-${switchTo.name}')));
          await tester.pumpAndSettle();
        }
        if (draft.type == WalletType.cash || switchTo == WalletType.cash) {
          expect(find.text('Name (optional)'), findsOneWidget);
        }
        if (rename != null) {
          await tester.enterText(
            find.byKey(const Key('wallet-cash-name')),
            rename,
          );
        }
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
      }

      // A cash wallet named before keeps that name.
      await edit(
        const WalletDraft(
          type: WalletType.cash,
          name: 'Cash 2',
          startingBalance: 500,
        ),
      );
      expect(result?.name, 'Cash 2');

      // A bank switched to cash does not carry the bank's name over.
      await edit(
        const WalletDraft(
          type: WalletType.bank,
          name: 'My Rural Bank',
          startingBalance: 500,
        ),
        switchTo: WalletType.cash,
      );
      expect(result?.type, WalletType.cash);
      expect(result?.name, 'Cash');

      // A name can be given, and a cleared one is just "Cash".
      const pocket = WalletDraft(
        type: WalletType.cash,
        name: 'Cash',
        startingBalance: 500,
      );
      await edit(pocket, rename: 'Petty Cash');
      expect(result?.name, 'Petty Cash');
      await edit(pocket, rename: '  ');
      expect(result?.name, 'Cash');

      // Only numbers would read as an amount beside the balance: refused,
      // and the sheet stays open to fix it.
      result = null;
      await edit(pocket, rename: '545636456456464');
      expect(result, isNull);
      expect(
        find.text(
          "Add a word, not just numbers, so it isn't read as an amount.",
        ),
        findsOneWidget,
      );

      // A whole card or account number never goes into a name.
      await tester.enterText(
        find.byKey(const Key('wallet-cash-name')),
        'Cash 4111111111111111',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(
        find.text(
          'Use a nickname, not an account or card number. The last 4 digits '
          'are enough.',
        ),
        findsOneWidget,
      );

      // The message follows what is typed: it goes the moment the name is
      // right, without tapping Save again, and comes back if it turns wrong.
      await tester.enterText(
        find.byKey(const Key('wallet-cash-name')),
        'Petty Cash',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Use a nickname'), findsNothing);
      expect(find.textContaining('Add a word'), findsNothing);
      expect(result, isNull);
      await tester.enterText(find.byKey(const Key('wallet-cash-name')), '2026');
      await tester.pumpAndSettle();
      expect(find.textContaining('Add a word'), findsOneWidget);
    });

    testWidgets('nothing is red until Save is tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showWalletFormSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Still being typed: no message yet.
      await tester.enterText(find.byKey(const Key('wallet-cash-name')), '123');
      await tester.pump();
      expect(find.textContaining('Add a word'), findsNothing);
      expect(find.text('Enter the balance, or 0 if empty.'), findsNothing);

      // Save shows every problem at once.
      await tester.tap(find.text('Add Wallet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add a word'), findsOneWidget);
      expect(find.text('Enter the balance, or 0 if empty.'), findsOneWidget);

      // Each goes as soon as its own field is right.
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '5000',
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter the balance, or 0 if empty.'), findsNothing);
      expect(find.textContaining('Add a word'), findsOneWidget);
    });

    test('a repeated name gets the next number, and numbers only go up', () {
      expect(uniqueName('Petty Cash', const []), 'Petty Cash');
      expect(uniqueName('Petty Cash', const ['Petty Cash']), 'Petty Cash 2');
      expect(
        uniqueName('petty cash', const ['Petty Cash', 'Petty Cash 2']),
        'Petty Cash 3',
      );
      // A gap is not filled, and a lone numbered one still counts.
      expect(uniqueName('Cash', const ['Cash', 'Cash 3']), 'Cash 4');
      expect(uniqueName('Cash', const ['Cash 2']), 'Cash 3');
      // A taken "Cash 2" typed again counts on from "Cash".
      expect(uniqueName('Cash 2', const ['Cash', 'Cash 2']), 'Cash 3');
      // A free numbered name, or a different name, stays as typed.
      expect(uniqueName('Cash 5', const ['Cash', 'Cash 2']), 'Cash 5');
      expect(uniqueName('Cashier', const ['Cash']), 'Cashier');
      expect(uniqueName('BDO Unibank', const ['BPI']), 'BDO Unibank');
    });

    testWidgets('bank interest rate is optional, retained, and range-checked', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: WalletFormSheet(
              existing: Wallet(
                id: 'bank',
                name: 'Bank of the Philippine Islands (BPI)',
                type: WalletType.bank,
                balance: 50000,
                startingBalance: 50000,
                receivesIncome: false,
                archived: false,
                sortOrder: 0,
                annualInterestRatePercent: 1.25,
              ),
            ),
          ),
        ),
      );
      final rateField = find.byKey(const Key('wallet-annual-interest-rate'));
      expect(rateField, findsOneWidget);
      expect(tester.widget<TextFormField>(rateField).controller!.text, '1.25');

      await tester.enterText(rateField, '101');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a rate from 0 to 100%.'), findsOneWidget);

      await tester.enterText(rateField, '0');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a rate from 0 to 100%.'), findsNothing);
    });

    testWidgets('new wallet form only offers supported wallet types', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: WalletFormSheet()),
        ),
      );

      expect(find.byKey(const Key('wallet-type-cash')), findsOneWidget);
      expect(find.byKey(const Key('wallet-type-ewallet')), findsOneWidget);
      expect(find.byKey(const Key('wallet-type-bank')), findsOneWidget);
      expect(find.text('GCash'), findsNothing);
      expect(find.text('Maya'), findsNothing);
      expect(find.text('Other E-Wallet'), findsNothing);
      expect(find.text('Other'), findsNothing);
      // Cash starts selected, with its optional name.
      expect(find.byKey(const Key('wallet-cash-name')), findsOneWidget);
      expect(find.byKey(const Key('wallet-current-balance')), findsOneWidget);
      final typeChipRects = ['Cash', 'E-Wallets', 'Banks'].map((type) {
        final typeKey = switch (type) {
          'E-Wallets' => 'ewallet',
          'Banks' => 'bank',
          _ => 'cash',
        };
        return tester.getRect(find.byKey(Key('wallet-type-$typeKey')));
      }).toList();
      expect(
        typeChipRects.map((rect) => rect.top).toSet(),
        hasLength(1),
        reason: 'All type options should fit on one row at mobile width.',
      );
      for (var index = 1; index < typeChipRects.length; index++) {
        final gap = typeChipRects[index].left - typeChipRects[index - 1].right;
        expect(gap, closeTo(8, 0.1));
      }
      for (final type in ['Cash', 'E-Wallets', 'Banks']) {
        final typeKey = switch (type) {
          'E-Wallets' => 'ewallet',
          'Banks' => 'bank',
          _ => 'cash',
        };
        final chip = find.byKey(Key('wallet-type-$typeKey'));
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
      }

      await tester.tap(find.byKey(const Key('wallet-type-ewallet')));
      await tester.pumpAndSettle();
      final dropdown = find.byKey(const Key('wallet-ewallet-dropdown'));
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: dropdown,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(field.items!.map((item) => item.value), [
        'GCash',
        'Maya',
        'GrabPay',
        'ShopeePay',
        'Coins.ph',
        'PalawanPay',
        'DiskarTech',
        'Other E-Wallet',
      ]);
      field.onChanged!('Other E-Wallet');
      await tester.pump();
      expect(
        find.byKey(const Key('wallet-other-ewallet-name')),
        findsOneWidget,
      );

      // A typed name has to be a name: numbers alone would read as an
      // amount, and a whole account or phone number must not be kept.
      const noWord =
          "Add a word, not just numbers, so it isn't read as an amount.";
      const accountNumber =
          'Use a nickname, not an account or card number. The last 4 digits '
          'are enough.';
      Future<void> tryName(String key, String name) async {
        await tester.enterText(find.byKey(Key(key)), name);
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          '0',
        );
        await tester.ensureVisible(find.text('Add Wallet'));
        await tester.tap(find.text('Add Wallet'));
        await tester.pumpAndSettle();
      }

      await tryName('wallet-other-ewallet-name', '1231233132-0131313123213');
      expect(find.text(noWord), findsOneWidget);
      await tryName('wallet-other-ewallet-name', 'Wallet 0917-123-4567');
      expect(find.text(accountNumber), findsOneWidget);
      expect(find.text('New Wallet'), findsOneWidget, reason: 'still open');
      expect(
        tester.getTopLeft(find.text('Current balance')).dy,
        lessThan(tester.getTopLeft(find.text('Annual Interest Rate (%)')).dy),
      );

      await tester.tap(find.byKey(const Key('wallet-type-bank')));
      await tester.pumpAndSettle();
      final bankDropdown = find.byKey(const Key('wallet-bank-dropdown'));
      final bankField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: bankDropdown,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(find.text('Select a bank'), findsOneWidget);
      expect(
        bankField.items!.map((item) => item.value),
        containsAll(['BDO Unibank', 'Bank of the Philippine Islands (BPI)']),
      );
      expect(
        bankField.items!.map((item) => item.value),
        contains('Other bank'),
      );

      bankField.onChanged!('Other bank');
      await tester.pump();
      expect(find.byKey(const Key('wallet-other-bank-name')), findsOneWidget);

      // The same for a bank typed by hand.
      await tryName('wallet-other-bank-name', '1231233132-0131313123213');
      expect(find.text(noWord), findsOneWidget);
      await tryName('wallet-other-bank-name', 'BDO 1234 5678 9012');
      expect(find.text(accountNumber), findsOneWidget);
      expect(find.text('New Wallet'), findsOneWidget, reason: 'still open');
    });

    testWidgets('cash summary totals cash, banks, and e-wallets once', (
      tester,
    ) async {
      await pumpOnboarding(tester, save: (_) async {});

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');

      var walletAdded = false;
      Future<void> addWallet({
        required String type,
        required String balance,
        String? bankName,
        String? ewalletProvider,
        String? customProvider,
        String? interestRate,
      }) async {
        await tapText(tester, walletAdded ? 'Add Another' : 'Add a Wallet');
        if (type != 'Cash') {
          final typeKey = switch (type) {
            'E-Wallets' => 'ewallet',
            'Banks' => 'bank',
            _ => 'cash',
          };
          await tester.tap(find.byKey(Key('wallet-type-$typeKey')));
          await tester.pumpAndSettle();
        }
        if (bankName != null) {
          final bankDropdown = find.byKey(const Key('wallet-bank-dropdown'));
          final bankField = tester.widget<DropdownButton<String>>(
            find.descendant(
              of: bankDropdown,
              matching: find.byType(DropdownButton<String>),
            ),
          );
          bankField.onChanged!(bankName);
          await tester.pump();
        }
        if (ewalletProvider != null) {
          final ewalletDropdown = find.byKey(
            const Key('wallet-ewallet-dropdown'),
          );
          final ewalletField = tester.widget<DropdownButton<String>>(
            find.descendant(
              of: ewalletDropdown,
              matching: find.byType(DropdownButton<String>),
            ),
          );
          ewalletField.onChanged!(ewalletProvider);
          await tester.pump();
        }
        if (customProvider != null) {
          await tester.enterText(
            find.byKey(const Key('wallet-other-ewallet-name')),
            customProvider,
          );
        }
        if (interestRate != null) {
          await tester.enterText(
            find.byKey(const Key('wallet-annual-interest-rate')),
            interestRate,
          );
        }
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          balance,
        );
        await tapText(tester, 'Add Wallet');
        walletAdded = true;
      }

      await addWallet(type: 'Cash', balance: '100');
      await addWallet(type: 'Cash', balance: '50');
      await addWallet(
        type: 'Banks',
        balance: '200',
        bankName: 'Bank of the Philippine Islands (BPI)',
        interestRate: '2.5',
      );
      await addWallet(
        type: 'Banks',
        balance: '300',
        bankName: 'BDO Unibank',
        interestRate: '1.25',
      );
      await addWallet(
        type: 'E-Wallets',
        balance: '999',
        ewalletProvider: 'GCash',
        interestRate: '0.5',
      );
      await tapText(tester, 'Next');
      expect(find.text('Step 4 of 10'), findsOneWidget);
      expect(find.text('₱150'), findsOneWidget);
      expect(find.text('₱1,499'), findsOneWidget);
      expect(find.text('₱1,649'), findsOneWidget);
      // ₱13.75 a year less the 20% tax banks keep.
      expect(find.text('₱11'), findsOneWidget);
      expect(find.text('Interest in a Year (after tax)'), findsOneWidget);
      // The same colored icons the wallets and goals use. The total is
      // cash plus bank, so it shows both of theirs.
      expect(
        find.image(AssetImage(WalletType.cash.iconAsset)),
        findsNWidgets(2),
      );
      // The notes below use the same icons: a bank for the accounts and the
      // chart for interest.
      expect(
        find.image(AssetImage(WalletType.bank.iconAsset)),
        findsNWidgets(3),
      );
      expect(
        find.image(const AssetImage('assets/icons/icons8-combo-chart-100.png')),
        findsNWidgets(2),
      );
      expect(
        find.image(const AssetImage('assets/icons/icons8-coin-96.png')),
        findsNothing,
      );

      // Every account here has a rate, so all of them are counted.
      expect(
        find.text('Interest counts all 3 of your accounts.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cash in Bank').first);
      await tester.pumpAndSettle();
      expect(find.text('Bank of the Philippine Islands (BPI)'), findsOneWidget);
      expect(find.text('BDO Unibank'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Bank Account'), findsNWidgets(2));
      expect(find.text('E-Wallet'), findsOneWidget);
      // Worded as on every other card, with no stray ".0".
      expect(find.text('Interest: 2.5% a year'), findsOneWidget);
      expect(find.text('Interest: 1.25% a year'), findsOneWidget);
      expect(find.text('Interest in a year, after tax: ₱4'), findsNWidgets(2));
      expect(find.text('Interest in a year, after tax: ₱3'), findsOneWidget);
      expect(find.text('Total · ₱1,499'), findsOneWidget);
      expect(find.text('₱200'), findsOneWidget);
      expect(find.text('₱300'), findsOneWidget);
      await tester.tap(find.byTooltip('Close bank account details'));
      await tester.pumpAndSettle();

      // Cash on Hand opens every cash wallet in it.
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      expect(find.text('Total · ₱150'), findsOneWidget);
      expect(find.text('Cash 2'), findsOneWidget);
      expect(find.text('₱100'), findsOneWidget);
      expect(find.text('₱50'), findsOneWidget);
      await tester.tap(find.byTooltip('Close cash details'));
      await tester.pumpAndSettle();

      // The total splits back into the cash and the accounts it adds up.
      await tester.tap(find.text('Total Available Money'));
      await tester.pumpAndSettle();
      expect(find.text('Total · ₱1,649'), findsOneWidget);
      expect(
        find.text('Cash on Hand plus Cash in Bank and E-Wallets.'),
        findsOneWidget,
      );
      expect(find.text('Cash in Bank and E-Wallets'), findsOneWidget);
      expect(find.text('Cash 2'), findsOneWidget);
      expect(find.text('BDO Unibank'), findsOneWidget);
      expect(find.text('₱999'), findsOneWidget);
      await tester.tap(find.byTooltip('Close total details'));
      await tester.pumpAndSettle();
    });

    testWidgets('a setup goal can be funded from cash and a bank together', (
      tester,
    ) async {
      OnboardingData? saved;
      await pumpOnboarding(tester, save: (data) async => saved = data);

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');

      await tapText(tester, 'Add a Wallet');
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '2000',
      );
      await tapText(tester, 'Add Wallet');
      await tapText(tester, 'Add Another');
      await tester.tap(find.byKey(const Key('wallet-type-bank')));
      await tester.pumpAndSettle();
      final bankField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('wallet-bank-dropdown')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      bankField.onChanged!('BDO Unibank');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('wallet-annual-interest-rate')),
        '3',
      );
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '8000',
      );
      await tapText(tester, 'Add Wallet');

      // Every Add on these steps is the same solid green as Save.
      Color? addColor(String label) => tester
          .widget<ElevatedButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(ElevatedButton),
            ),
          )
          .style
          ?.backgroundColor
          ?.resolve({});
      const green = appConfirmGreen;
      expect(addColor('Add Another'), green);

      await tapText(tester, 'Next');
      expect(find.text('Cash Summary'), findsOneWidget);
      await cashSummaryToGoals(tester);
      expect(addColor('Add Goal'), green);
      await tester.tap(find.byKey(const Key('add-onboarding-goal')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Laptop');
      await tester.enterText(find.byType(TextField).at(1), '10000');
      await tapText(tester, 'Save Goal');
      // Nothing set aside yet, and the card says where to add it.
      expect(find.textContaining('Nothing set aside yet'), findsOneWidget);
      expect(find.text('Change what is set aside'), findsNothing);

      // One Edit covers the goal and the money set aside for it.
      Future<void> openEdit() async {
        await tester.tap(find.byTooltip('Edit Laptop'));
        await tester.pumpAndSettle();
        expect(find.text('Edit Goal'), findsOneWidget);
      }

      await openEdit();
      await tapText(tester, 'Both');
      await tester.enterText(fundingField(0), '2000');
      await tester.enterText(fundingField(1), '5000');
      await tester.pump();
      expect(find.text('about ₱120'), findsOneWidget);
      await tapText(tester, 'Save Changes');

      expect(find.text('₱7,000 of ₱10,000 saved'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      // One row per account, then one line for the interest.
      expect(find.text('Set aside from'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('₱2,000'), findsOneWidget);
      expect(find.text('BDO Unibank'), findsOneWidget);
      expect(find.text('₱5,000'), findsOneWidget);
      expect(
        find.text(
          'May earn about ₱120 a year after tax from BDO Unibank. Add it as '
          'income when it is paid.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing set aside yet'), findsNothing);

      // Editing again opens with the amounts already chosen and replaces
      // them, so the same money is never counted twice.
      await openEdit();
      expect(
        tester.widget<TextField>(fundingField(0)).controller?.text,
        '2000',
      );
      await tester.enterText(fundingField(1), '6000');
      await tapText(tester, 'Save Changes');
      expect(find.text('₱8,000 of ₱10,000 saved'), findsOneWidget);

      // The Cash Summary shows what is left to spend: the ₱8,000 for the
      // goal is set aside, though nothing moved, and it says so.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Cash Summary'), findsOneWidget);
      expect(find.textContaining('less the ₱8,000 set aside'), findsOneWidget);
      // Cash ₱2,000 all for the goal; BDO ₱8,000 less ₱6,000; ₱2,000 in all.
      expect(find.text('₱0'), findsWidgets);
      expect(find.text('₱2,000'), findsNWidgets(2));
      expect(find.text('₱10,000'), findsNothing);
      await cashSummaryToGoals(tester);
      expect(find.text('₱8,000 of ₱10,000 saved'), findsOneWidget);

      // Closing the sheet changes nothing.
      await openEdit();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('₱8,000 of ₱10,000 saved'), findsOneWidget);

      // The red button in Edit releases it, with a few seconds to undo.
      // The notice stays a while, so it is not waited out here.
      await openEdit();
      final release = find.text('Release what is set aside');
      await tester.ensureVisible(release);
      await tester.tap(release);
      // The sheet closes, the notice slides in, then it takes taps.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('₱0 of ₱10,000 saved'), findsOneWidget);
      expect(find.text('Released from Laptop'), findsOneWidget);
      expect(
        find.text('₱8,000 is no longer set aside for it.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('₱8,000 of ₱10,000 saved'), findsOneWidget);
      expect(find.text('Released from Laptop'), findsNothing);

      // Deleting warns first, and Cancel keeps the goal.
      await tester.tap(find.byTooltip('Delete Laptop'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Laptop?'), findsOneWidget);
      expect(
        find.textContaining('₱8,000 set aside for it will be free again'),
        findsOneWidget,
      );
      await tapText(tester, 'Cancel');
      expect(find.text('Delete Laptop?'), findsNothing);
      expect(find.text('₱8,000 of ₱10,000 saved'), findsOneWidget);

      await tapText(tester, 'Next');
      await tapText(tester, 'Allow Reminders');
      await tapText(tester, 'Next');
      await tapText(tester, 'Continue');
      await tester.ensureVisible(find.text('Go to Dashboard'));
      await tester.tap(find.text('Go to Dashboard'));
      await tester.pump();
      await tester.pump();

      final goal = saved!.goals.single;
      final cashId = saved!.wallets.first.id;
      final bankId = saved!.wallets.last.id;
      expect(goal.fundingByWalletDraftId, {cashId: 2000, bankId: 6000});
      expect(goal.allocated, 8000);
      expect(goal.fundingSource, GoalFundingSource.both);
      expect(goal.fundingWalletDraftId, bankId);
      expect(saved!.wallets.map((wallet) => wallet.startingBalance), [
        2000,
        8000,
      ]);
    });

    testWidgets('removing a setup wallet keeps the goal\'s other amounts', (
      tester,
    ) async {
      await pumpOnboarding(tester, save: (_) async {});

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');
      await tapText(tester, 'Add a Wallet');
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '2000',
      );
      await tapText(tester, 'Add Wallet');
      await tapText(tester, 'Add Another');
      await tester.tap(find.byKey(const Key('wallet-type-bank')));
      await tester.pumpAndSettle();
      final bankField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('wallet-bank-dropdown')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      bankField.onChanged!('BDO Unibank');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '8000',
      );
      await tapText(tester, 'Add Wallet');
      await tapText(tester, 'Next');
      await cashSummaryToGoals(tester);

      await tester.tap(find.byKey(const Key('add-onboarding-goal')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Laptop');
      await tester.enterText(find.byType(TextField).at(1), '10000');
      await tapText(tester, 'Both');
      await tester.enterText(fundingField(0), '2000');
      await tester.enterText(fundingField(1), '5000');
      await tapText(tester, 'Save Goal');
      expect(find.text('₱7,000 of ₱10,000 saved'), findsOneWidget);

      // Back through Bills, Savings and the summary to the wallets.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Your starting wallets'), findsOneWidget);
      // The warning says what goes with it.
      await tester.tap(find.byTooltip('Delete Cash'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This wallet will be removed, and the ₱2,000 your goals set aside '
          'from it will be free again.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Delete');
      await tapText(tester, 'Next');
      await cashSummaryToGoals(tester);

      expect(find.text('₱5,000 of ₱10,000 saved'), findsOneWidget);
      expect(find.text('BDO Unibank'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);

      // Continuing past the warning deletes the goal.
      await tester.tap(find.byTooltip('Delete Laptop'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      expect(find.text('Laptop'), findsNothing);
      expect(find.text('No goals added yet'), findsOneWidget);
    });

    testWidgets('cash summary includes e-wallets when physical cash is empty', (
      tester,
    ) async {
      await pumpOnboarding(tester, save: (_) async {});

      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');
      await tapText(tester, 'Add a Wallet');
      await tester.tap(find.byKey(const Key('wallet-type-ewallet')));
      await tester.pumpAndSettle();
      final ewalletDropdown = find.byKey(const Key('wallet-ewallet-dropdown'));
      final ewalletField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: ewalletDropdown,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      ewalletField.onChanged!('GCash');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '1000',
      );
      await tapText(tester, 'Add Wallet');

      await tapText(tester, 'Next');
      expect(find.text('Cash Summary'), findsOneWidget);
      expect(find.text('Cash on Hand'), findsOneWidget);
      expect(find.text('₱0'), findsOneWidget);
      expect(find.text('₱1,000'), findsNWidgets(2));

      // GCash has no rate, so no interest is counted, and the list says so.
      expect(
        find.text(
          'None of your accounts has a rate yet, so no interest is counted.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cash in Bank').first);
      await tester.pumpAndSettle();
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Total · ₱1,000'), findsOneWidget);
      expect(find.text('Interest: no rate entered'), findsOneWidget);
      await tester.tap(find.byTooltip('Close bank account details'));
      await tester.pumpAndSettle();

      // With a bank that has a rate, the account left out is named.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Add Another');
      await tester.tap(find.byKey(const Key('wallet-type-bank')));
      await tester.pumpAndSettle();
      final bankField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('wallet-bank-dropdown')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      bankField.onChanged!('BDO Unibank');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '2000',
      );
      await tester.enterText(
        find.byKey(const Key('wallet-annual-interest-rate')),
        '3',
      );
      await tapText(tester, 'Add Wallet');
      await tapText(tester, 'Next');
      expect(
        find.text(
          "Interest counts 1 of your 2 accounts. GCash has no rate, so it's "
          'left out.',
        ),
        findsOneWidget,
      );
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
      expect(find.text('Step 1 of 10'), findsOneWidget);
      await tapText(tester, 'Get Started');

      // Step 2: Name is required
      expect(find.text('What should we call you?'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Please enter your name.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');

      // Name goes straight to wallets; no ranking before it.
      expect(find.text('What should we remind you about most?'), findsNothing);
      expect(find.text('Your income'), findsNothing);
      expect(find.text('Monthly income'), findsNothing);

      // Step 3: Wallets are required, and come first
      expect(find.text('Your starting wallets'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Please add at least one wallet.'), findsOneWidget);

      await tapText(tester, 'Add a Wallet');
      await tester.tap(find.byKey(const Key('wallet-type-ewallet')));
      await tester.pumpAndSettle();
      final onboardingEwalletDropdown = find.byKey(
        const Key('wallet-ewallet-dropdown'),
      );
      final onboardingEwalletField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: onboardingEwalletDropdown,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        onboardingEwalletField.items!.map((item) => item.value),
        containsAll(['GCash', 'Maya', 'GrabPay', 'ShopeePay', 'Coins.ph']),
      );
      onboardingEwalletField.onChanged!('GCash');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '1250.50',
      );
      await tapText(tester, 'Add Wallet');

      expect(find.text('Receives my income'), findsNothing);

      await tapText(tester, 'Add Another');
      await tester.tap(find.byKey(const Key('wallet-type-bank')));
      await tester.pumpAndSettle();
      final bankDropdown = find.byKey(const Key('wallet-bank-dropdown'));
      expect(bankDropdown, findsOneWidget);
      final bankField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: bankDropdown,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        bankField.items!.map((item) => item.value),
        contains('Asia United Bank (AUB)'),
      );
      bankField.onChanged!('Asia United Bank (AUB)');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '300',
      );
      await tapText(tester, 'Add Wallet');

      expect(find.text('₱1,250.50'), findsOneWidget);
      expect(find.text('₱300'), findsOneWidget);
      expect(find.text('Receives my income'), findsNothing);
      await tapText(tester, 'Next');
      // Step 4: the cash summary adds up the wallets just entered
      expect(find.text('Step 4 of 10'), findsOneWidget);
      expect(find.text('Cash Summary'), findsOneWidget);
      expect(find.text('Cash on Hand'), findsOneWidget);
      expect(find.text('₱0'), findsOneWidget);
      expect(find.text('Cash in Bank'), findsOneWidget);
      expect(find.text('₱1,550.50'), findsNWidgets(2));
      expect(find.text('Total Available Money'), findsOneWidget);

      await tester.tap(find.text('Cash in Bank').first);
      await tester.pumpAndSettle();
      expect(find.text('Asia United Bank (AUB)'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Total · ₱1,550.50'), findsOneWidget);
      await tester.tap(find.byTooltip('Close bank account details'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Your starting wallets'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Cash Summary'), findsOneWidget);

      // Step 5: savings
      await tapText(tester, 'Next');
      expect(find.text('Step 5 of 10'), findsOneWidget);
      expect(find.text('Build your savings'), findsOneWidget);
      expect(find.text('Savings amount'), findsNothing);
      await tester.tap(find.byKey(const Key('add-onboarding-savings-account')));
      await tester.pumpAndSettle();

      // Three picture tiles, and only the chosen kind is explained: what it
      // pays, and how the money comes out.
      expect(find.text('What kind of savings?'), findsOneWidget);
      expect(find.text('Interest'), findsOneWidget);
      expect(find.text('Taking money out'), findsOneWidget);
      expect(find.text('Earns interest'), findsOneWidget);
      expect(find.text("Follows your bank's rules"), findsOneWidget);
      expect(find.textContaining('Locked until the end date'), findsNothing);
      // A savings deposit asks for its rate and start date, not an end, and
      // how often it pays, for its reminders.
      expect(find.text('Interest rate per year'), findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('End date'), findsNothing);
      expect(find.text('How often does it pay interest?'), findsOneWidget);
      // Every month starts chosen: the one with the check.
      expect(
        find.descendant(
          of: find.byKey(const Key('interest-payout-monthly')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );

      // A time deposit adds the end date. Missing dates are all shown at
      // once, under the field each one belongs to.
      await tester.tap(find.byKey(const Key('savings-kind-timeDeposit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Locked until the end date'), findsOneWidget);
      expect(find.text('End date'), findsOneWidget);
      // A time deposit pays at its end date instead.
      expect(find.text('How often does it pay interest?'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('onboarding-savings-balance')),
        '5000',
      );
      await tester.enterText(
        find.byKey(const Key('onboarding-savings-rate')),
        '4',
      );
      final saveSavings = find.byKey(const Key('save-onboarding-savings'));
      await tester.ensureVisible(saveSavings);
      await tester.tap(saveSavings);
      await tester.pumpAndSettle();
      expect(find.text('Choose the start date.'), findsOneWidget);
      expect(
        find.text('Choose an end date after the start date.'),
        findsOneWidget,
      );

      // A demand deposit earns nothing, so only the balance is asked.
      await tester.ensureVisible(
        find.byKey(const Key('savings-kind-demandDeposit')),
      );
      await tester.tap(find.byKey(const Key('savings-kind-demandDeposit')));
      await tester.pumpAndSettle();
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Anytime'), findsOneWidget);
      expect(find.text('Interest rate per year'), findsNothing);
      expect(find.text('Start date'), findsNothing);
      expect(find.byKey(const Key('onboarding-savings-name')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('onboarding-savings-balance')),
        '500',
      );
      await tester.tap(find.byKey(const Key('save-onboarding-savings')));
      await tester.pumpAndSettle();
      expect(find.text('Demand Deposit'), findsOneWidget);
      // Deleting a savings record warns first; Cancel keeps it.
      await tester.tap(find.byTooltip('Delete Demand Deposit'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Demand Deposit?'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(find.text('Demand Deposit'), findsOneWidget);
      // Its card says plainly what this kind of savings does.
      expect(find.text('Take money out'), findsOneWidget);
      expect(find.text('Anytime'), findsOneWidget);

      expect(find.byKey(const Key('add-onboarding-goal')), findsNothing);
      expect(find.text('Emergency buffer'), findsNothing);

      // Step 6: bills
      await tapText(tester, 'Next');
      expect(find.text('Step 6 of 10'), findsOneWidget);
      expect(find.text('Add bill reminders'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-onboarding-bill')));
      await tester.pumpAndSettle();
      final billFields = find.byType(TextFormField);
      await tester.enterText(billFields.at(0), 'Internet');
      await tester.enterText(billFields.at(1), '1200');
      await tapText(tester, 'Add Bill');
      expect(find.text('Internet'), findsOneWidget);
      // Laid out like a goal card: the amount and how often, then the date.
      expect(find.text('₱1,200 every month'), findsOneWidget);
      expect(find.text('First due date'), findsOneWidget);

      // A bill can be edited with the same sheet, and stays in its place.
      await tester.tap(find.byTooltip('Edit Internet'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Bill'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '1500');
      await tapText(tester, 'Save Changes');
      expect(find.text('₱1,500 every month'), findsOneWidget);
      expect(find.text('₱1,200 every month'), findsNothing);
      // So does deleting a bill.
      await tester.tap(find.byTooltip('Delete Internet'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Internet?'), findsOneWidget);
      expect(
        find.text(
          'This bill and its reminders will be removed. You can add it again '
          'later.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Cancel');
      expect(find.text('Internet'), findsOneWidget);

      // Step 7: goals, and Back returns to bills.
      await tapText(tester, 'Next');
      expect(find.text('Set up your goals'), findsOneWidget);
      expect(find.text('Step 7 of 10'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Add bill reminders'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.text('Set up your goals'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-onboarding-goal')));
      await tester.pumpAndSettle();
      expect(find.text('New Savings Goal'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Emergency buffer');
      await tester.enterText(find.byType(TextField).at(1), '10000');
      expect(find.text('Where is this money now?'), findsOneWidget);
      // No cash wallet was added, so only Cash in Bank can be chosen.
      await tapText(tester, 'Cash in Bank');
      expect(find.textContaining('E-Wallet · '), findsOneWidget);
      await tester.enterText(fundingField(0), '300');
      // "Emergency" in the name makes it an emergency fund; nothing to pick.
      await tapText(tester, 'Save Goal');
      expect(find.text('Emergency buffer'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('₱300 of ₱10,000 saved'), findsOneWidget);
      // Step 8: reminders
      await tapText(tester, 'Next');
      expect(find.text('Step 8 of 10'), findsOneWidget);
      await tapText(tester, 'Allow Reminders');

      // Step 9: the ranking, only because reminders were allowed. Each
      // place shows how many reminders it gives.
      expect(find.text('Step 9 of 10'), findsOneWidget);
      expect(
        find.text('What should we remind you about most?'),
        findsOneWidget,
      );
      for (final count in [
        '4 reminders',
        '3 reminders',
        '2 reminders',
        '1 reminder',
      ]) {
        expect(find.text(count), findsOneWidget, reason: count);
      }

      // The first priority can't move up; moving it down swaps it.
      final moveUp = find.byTooltip('Move "Pay bills on time" up');
      await tester.ensureVisible(moveUp);
      final moveUpButton = find.ancestor(
        of: moveUp,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(moveUpButton).onPressed, isNull);
      final moveDown = find.byTooltip('Move "Pay bills on time" down');
      final moveDownButton = find.ancestor(
        of: moveDown,
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(moveDownButton);
      await tester.tap(moveDownButton);
      await tester.pump();

      await tapText(tester, 'Next');

      // Step 10: Review shows the ranking, as reminders are on.
      expect(find.text('Step 10 of 10'), findsOneWidget);
      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('Remind me most about'), findsOneWidget);
      expect(find.text('Save toward a goal'), findsOneWidget);
      await tapText(tester, 'Continue');
      expect(find.text('On · Save toward a goal first'), findsOneWidget);

      // Recap
      expect(find.text("You're ready, Dave!"), findsOneWidget);
      expect(find.text('Next, on your dashboard'), findsOneWidget);
      expect(
        find.text('Tap + anytime to add an expense or income'),
        findsOneWidget,
      );
      expect(find.text('See where your money goes in Reports'), findsOneWidget);
      // ₱1,550.50 listed, less the ₱300 set aside for the goal.
      expect(find.text('2 wallets · ₱1,250.50 available'), findsOneWidget);
      expect(find.text('Daily spending limit'), findsNothing);
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
      expect(saved!.bills, hasLength(1));
      expect(saved!.bills.single.name, 'Internet');
      expect(saved!.bills.single.amount, 1500);
      expect(saved!.bills.single.category, 'Bills');
      expect(saved!.bills.single.recurrence, BillRecurrence.monthly);
      expect(saved!.bills.single.firstDueDate, isA<DateTime>());
      expect(saved!.savingsAccounts, hasLength(1));
      expect(saved!.savingsAccounts.single.name, 'Demand Deposit');
      expect(saved!.savingsAccounts.single.kind, SavingsKind.demandDeposit);
      expect(saved!.savingsAccounts.single.balance, 500);
      expect(saved!.goals, hasLength(1));
      expect(saved!.goals.single.name, 'Emergency buffer');
      expect(saved!.goals.single.kind, GoalKind.emergencyFund);
      expect(saved!.goals.single.targetAmount, 10000);
      expect(saved!.goals.single.allocated, 300);
      expect(saved!.goals.single.fundingWalletDraftId, saved!.wallets.first.id);
      expect(saved!.goals.single.fundingSource, GoalFundingSource.ewallet);
      expect(saved!.priorities.take(2), [
        FinancialPriority.saveForGoal,
        FinancialPriority.payBills,
      ]);
      expect(saved!.wallets.map((w) => w.type), [
        WalletType.ewallet,
        WalletType.bank,
      ]);
      expect(saved!.wallets.map((w) => w.receivesIncome), [true, false]);
      expect(saved!.wallets.first.name, 'GCash');
      expect(saved!.wallets.last.name, 'Asia United Bank (AUB)');
    });

    testWidgets('Edit on Review fixes one answer and comes right back', (
      tester,
    ) async {
      OnboardingData? saved;
      await pumpOnboarding(tester, save: (data) async => saved = data);
      await tapText(tester, 'Get Started');
      await tester.enterText(find.byType(TextFormField), 'Dave');
      await tapText(tester, 'Next');

      // The first time through, every step says Next.
      await tapText(tester, 'Add a Wallet');
      await tester.enterText(
        find.byKey(const Key('wallet-current-balance')),
        '100',
      );
      await tapText(tester, 'Add Wallet');
      expect(find.text('Back to Review'), findsNothing);
      await tapText(tester, 'Next');
      await cashSummaryToGoals(tester);
      expect(find.text('Back to Review'), findsNothing);
      await tapText(tester, 'Next');
      await tapText(tester, 'Skip for now');
      expect(find.text('Check your answers'), findsOneWidget);
      expect(
        find.textContaining("You'll come right back here."),
        findsOneWidget,
      );
      expect(find.text('1 wallet · ₱100 available'), findsOneWidget);
      expect(find.text('Updated'), findsNothing);
      // Edit is a pencil now, not a word.
      expect(find.text('Edit'), findsNothing);

      Future<void> edit(String label) async {
        // Each answer has a pencil named for it.
        final button = find.byTooltip('Edit $label');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> cancel() async {
        await tester.tap(find.byTooltip('Cancel'));
        await tester.pumpAndSettle();
      }

      Future<void> addEmptyishWallet(String balance) async {
        await tapText(tester, 'Add Another');
        await tester.enterText(
          find.byKey(const Key('wallet-current-balance')),
          balance,
        );
        await tapText(tester, 'Add Wallet');
      }

      // Edit wallets: Save Changes keeps it and comes straight back.
      await edit('Wallets');
      expect(find.text('Your starting wallets'), findsOneWidget);
      // The header says what is happening, not a step number.
      expect(find.text('Editing'), findsOneWidget);
      expect(find.textContaining('of 9'), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Your other answers stay as they are.'), findsNothing);
      final save = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save Changes'),
      );
      expect(save.style?.backgroundColor?.resolve({}), appConfirmGreen);
      await addEmptyishWallet('50');
      await tapText(tester, 'Save Changes');
      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('2 wallets · ₱150 available'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);

      // The back arrow cancels. With nothing changed it just goes back.
      await edit('Your name');
      await cancel();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('Updated'), findsNothing);

      // With a change, it asks first; Keep Editing stays put.
      await edit('Wallets');
      await addEmptyishWallet('25');
      await cancel();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tapText(tester, 'Keep Editing');
      expect(find.text('Your starting wallets'), findsOneWidget);
      // Discard puts everything back the way it was.
      await cancel();
      await tapText(tester, 'Discard');
      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('2 wallets · ₱150 available'), findsOneWidget);

      // A step's own checks still apply before saving.
      await edit('Your name');
      await tester.enterText(find.byType(TextFormField), '');
      await tapText(tester, 'Save Changes');
      expect(find.text('Please enter your name.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Dee');
      await tapText(tester, 'Save Changes');
      expect(find.text('Dee'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);

      // A cancelled name change is put back too.
      await edit('Your name');
      await tester.enterText(find.byType(TextFormField), 'Typo');
      await cancel();
      await tapText(tester, 'Discard');
      expect(find.text('Dee'), findsOneWidget);
      expect(find.text('Typo'), findsNothing);

      // Reminders: skipping returns at once, with no ranking asked.
      await edit('Reminders');
      await tapText(tester, 'Skip for now');
      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('Remind me most about'), findsNothing);

      // Back on Review, the ordinary back arrow still walks back with Next.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Allow Reminders'), findsOneWidget);
      await tapText(tester, 'Skip for now');
      await tapText(tester, 'Continue');
      await tester.ensureVisible(find.text('Go to Dashboard'));
      await tester.tap(find.text('Go to Dashboard'));
      await tester.pump();
      await tester.pump();
      expect(saved!.name, 'Dee');
      expect(saved!.wallets, hasLength(2));
    });

    testWidgets('Back returns to the previous step', (tester) async {
      await pumpOnboarding(tester, save: (_) async {});

      await tapText(tester, 'Get Started');
      expect(find.text('Step 2 of 10'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 10'), findsOneWidget);
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
      expect(find.textContaining('Money questions only'), findsOneWidget);
      // The notice is a tip bubble with the app's bulb, like Home's tips.
      expect(
        find.descendant(
          of: find.byKey(const Key('chat-notice')),
          matching: find.image(
            const AssetImage('assets/icons/icons8-idea-96.png'),
          ),
        ),
        findsOneWidget,
      );

      // The suggestions are just the questions: no pictures to decode.
      expect(find.text('Try asking'), findsOneWidget);
      for (final asset in [
        'icons8-banknotes-96.png',
        'icons8-pie-chart-96.png',
        'icons8-receipt-96.png',
        'icons8-cat-shopping-96.png',
      ]) {
        expect(
          find.image(AssetImage('assets/icons/$asset')),
          findsNothing,
          reason: asset,
        );
      }
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
        find.textContaining('answers from the records saved on this phone'),
        findsOneWidget,
      );

      await ask(tester, 'How much money do I have?');
      expect(
        find.textContaining('₱3,000 available across 1 wallet'),
        findsOneWidget,
      );
    });

    testWidgets('politely redirects questions that are not about money', (
      tester,
    ) async {
      await pumpChat(tester, Stream.value(false));

      expect(find.text('Offline'), findsOneWidget);

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

      final anyBrand = find.widgetWithText(ActionChip, 'Any brand');
      await tester.ensureVisible(anyBrand);
      await tester.pump();
      await tester.tap(anyBrand);
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
      WalletPurpose purpose = WalletPurpose.spending,
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
        purpose: purpose,
      );
    }

    test('savings are kept out of the total; an old Bills wallet is not', () {
      final wallets = [
        wallet(id: 'cash', balance: 3000),
        wallet(id: 'bills', balance: 5000, purpose: WalletPurpose.bills),
        wallet(id: 'savings', balance: 2000, purpose: WalletPurpose.savings),
      ];

      // Bills are paid straight from the wallets now, so money still in a
      // Bills wallet from before is spending money like any other.
      expect(totalWalletBalance(wallets), 8000);
      expect(setAsideWalletBalance(wallets), 2000);
      expect(walletBalanceFor(wallets, WalletPurpose.savings), 2000);
    });

    test('an archived set-aside wallet counts nowhere', () {
      final wallets = [
        wallet(id: 'cash', balance: 1000),
        wallet(
          id: 'old',
          balance: 500,
          purpose: WalletPurpose.savings,
          archived: true,
        ),
      ];

      expect(totalWalletBalance(wallets), 1000);
      expect(setAsideWalletBalance(wallets), 0);
    });

    test('a purpose is read back, and an unknown one is spending money', () {
      final bills = Wallet.fromMap('w1', {'name': 'Bills', 'purpose': 'bills'});
      final odd = Wallet.fromMap('w2', {'name': 'Odd', 'purpose': 'mystery'});

      expect(bills.purpose, WalletPurpose.bills);
      // Spent like any other wallet now.
      expect(bills.isSetAside, isFalse);
      expect(bills.iconAsset, WalletPurpose.bills.iconAsset);
      expect(odd.purpose, WalletPurpose.spending);
      expect(odd.isSetAside, isFalse);
    });

    test(
      'an entry starts on spending money, never on the set-aside wallets',
      () {
        final wallets = [
          wallet(id: 'savings', balance: 5000, purpose: WalletPurpose.savings),
          wallet(id: 'cash', balance: 300),
          wallet(id: 'gcash', balance: 900, receivesIncome: true),
        ];

        // The first spending wallet: income no longer has one of its own.
        expect(defaultWalletId(wallets), 'cash');
        expect(defaultWalletId([wallets.first, wallets[2]]), 'gcash');
      },
    );

    test('a stored wallet is read back with its saved values', () {
      final saved = Wallet.fromMap('w1', {
        'name': 'BPI Savings',
        'type': 'bank',
        'balance': 1250,
        'balanceRecorded': true,
        'annualInterestRatePercent': 2.5,
        'startingBalance': 1000,
        'receivesIncome': true,
        'archived': false,
        'sortOrder': 2,
      });

      expect(saved.name, 'BPI Savings');
      expect(saved.type, WalletType.bank);
      expect(saved.balance, 1250.0);
      expect(saved.hasRecordedBalance, isTrue);
      expect(saved.annualInterestRatePercent, 2.5);
      expect(saved.estimatedAnnualInterestIncome, 31.25);
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
      expect(broken.hasRecordedBalance, isFalse);
      expect(broken.annualInterestRatePercent, isNull);
    });

    test('annual interest estimates validate rates and eligible balances', () {
      expect(
        calculateAnnualInterestEstimate(
          balance: 50000,
          annualInterestRatePercent: 2.5,
        ),
        1250,
      );
      expect(
        calculateAnnualInterestEstimate(
          balance: 50000,
          annualInterestRatePercent: 0,
        ),
        0,
      );
      expect(
        calculateAnnualInterestEstimate(
          balance: null,
          annualInterestRatePercent: 2.5,
        ),
        isNull,
      );
      expect(
        calculateAnnualInterestEstimate(
          balance: 100,
          annualInterestRatePercent: -1,
        ),
        isNull,
      );
      expect(
        calculateAnnualInterestEstimate(
          balance: 100,
          annualInterestRatePercent: 100.01,
        ),
        isNull,
      );

      final oldWallet = Wallet.fromMap('old', {
        'name': 'Old Maya',
        'type': 'maya',
        'balance': 1000,
      });
      expect(oldWallet.isEWallet, isTrue);
      expect(oldWallet.estimatedAnnualInterestIncome, isNull);

      final unknownBalance = Wallet.fromMap('missing', {
        'name': 'Bank',
        'type': 'bank',
        'annualInterestRatePercent': 2,
      });
      expect(unknownBalance.hasRecordedBalance, isFalse);
      expect(unknownBalance.estimatedAnnualInterestIncome, isNull);
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
    });

    test('choosing the wallet that already receives income writes nothing', () {
      final wallets = [wallet(id: 'a', receivesIncome: true), wallet(id: 'b')];

      expect(incomeWalletUpdates(wallets, 'a'), isEmpty);
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
      List<Goal> goals = const [],
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: WalletsScreen(
              wallets: Stream.value(wallets),
              goals: Stream.value(goals),
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

    testWidgets('the total reads like a sum that adds up', (tester) async {
      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpWallets(
        tester,
        wallets: [
          wallet(id: 'cash', name: 'Cash', balance: 15000),
          wallet(
            id: 'bank',
            name: 'BDO',
            type: WalletType.bank,
            balance: 4000,
            sortOrder: 1,
          ),
          Wallet(
            id: 'td',
            name: 'Time Deposit',
            type: WalletType.other,
            balance: 10000,
            startingBalance: 10000,
            receivesIncome: false,
            archived: false,
            sortOrder: 2,
            purpose: WalletPurpose.savings,
          ),
        ],
        goals: const [
          Goal(
            id: 'g',
            name: 'Graduation',
            targetAmount: 20000,
            savedAmount: 12000,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'cash': 12000},
          ),
        ],
      );

      // ₱19,000 in cash and bank, less ₱12,000 for the goal: ₱7,000, the
      // figure at the top and the end of the sum.
      expect(find.text('In these wallets'), findsOneWidget);
      expect(find.text('₱19,000'), findsOneWidget);
      expect(find.text('-₱12,000'), findsOneWidget);
      expect(find.text('Available balance'), findsOneWidget);
      expect(find.text('₱7,000'), findsNWidgets(2));
      // Nothing outside the sum sits on the card, so it always adds up.
      expect(find.text('Kept apart, not counted above'), findsNothing);
      expect(find.text('Savings wallet'), findsNothing);
      expect(find.textContaining('bills and savings'), findsNothing);
    });

    testWidgets('no wallet is marked as where income goes', (tester) async {
      // Income goes into the wallets chosen each time it is added, so even
      // a wallet marked before that has no badge, and none can be marked.
      await pumpWallets(
        tester,
        wallets: [
          wallet(id: 'a', name: 'Cash', receivesIncome: true),
          wallet(id: 'b', name: 'GCash', sortOrder: 1),
        ],
      );

      expect(find.text('Receives my income'), findsNothing);
      await tester.tap(find.byTooltip('Wallet options').last);
      await tester.pumpAndSettle();
      expect(find.text('Set as my income'), findsNothing);
      expect(find.text('Add income'), findsOneWidget);
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
            ),
          ),
        ),
      );
      // Two frames: one for the wallet list, one for the transactions.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows the balance, with no income wallet badge', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: cash);

      expect(find.text('Cash'), findsWidgets);
      expect(find.text('₱1,200'), findsOneWidget);
      expect(find.text('Your income is paid into this wallet'), findsNothing);
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

    testWidgets('long-pressing a transaction does not expose delete', (
      tester,
    ) async {
      await pumpDetail(tester, wallet: cash, transactions: [transfer()]);

      await tester.longPress(find.text('To My GCash'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this transaction?'), findsNothing);
      expect(find.text('Delete'), findsNothing);
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

    test('a new entry starts on the first wallet', () {
      // Even one marked as receiving income before that was dropped.
      expect(
        defaultWalletId([wallet('a'), wallet('b', receivesIncome: true)]),
        'a',
      );
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

    testWidgets('money only goes to wallets that exist', (tester) async {
      await pumpTransfer(tester, wallets: [cash, gcash]);

      expect(find.text('Where is it going?'), findsOneWidget);
      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();

      // No Bills or Savings wallet is made up to put money in.
      expect(find.text('Bills'), findsNothing);
      expect(find.text('Savings'), findsNothing);
      expect(find.text('My GCash'), findsWidgets);
    });

    testWidgets('with one wallet there is nowhere to move it', (tester) async {
      await pumpTransfer(tester, wallets: [cash]);

      expect(find.textContaining('need a second wallet'), findsOneWidget);
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

      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('goes-to-b')), '800');
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Transfer'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Transfer'));
      await tester.pump();

      expect(find.text('Cash only holds ₱500.'), findsOneWidget);
    });

    testWidgets('asks for an amount before transferring', (tester) async {
      await pumpTransfer(tester, wallets: [cash, gcash]);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Transfer'));
      await tester.pump();

      expect(
        find.text('Choose where it goes, then enter how much.'),
        findsOneWidget,
      );
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

    final gcash = Wallet(
      id: 'w2',
      name: 'GCash',
      type: WalletType.gcash,
      balance: 2000,
      startingBalance: 2000,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
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
      List<Wallet>? wallets,
      void Function(
        AllocationPlan plan,
        Map<String, double> income,
        Map<String, double> billsFrom,
        Map<String, double> fees,
        String source,
      )?
      onConfirm,
    }) async {
      tester.view.physicalSize = const Size(700, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IncomeWaterfallScreen(
            today: today,
            wallets: Stream.value(wallets ?? [cash]),
            loadBills: () async => bills,
            goals: Stream.value(goals),
            cycles: Stream.value(const []),
            onConfirm:
                ({
                  required AllocationPlan plan,
                  required Map<String, double> incomeByWallet,
                  required Map<String, double> billsPaidFrom,
                  required Map<String, double> billFees,
                  required Map<String, double> goalKeptIn,
                  required String source,
                  required DateTime receivedAt,
                }) => onConfirm?.call(
                  plan,
                  incomeByWallet,
                  billsPaidFrom,
                  billFees,
                  source,
                ),
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

    /// The amount, Allowance, and all of it into Cash on Hand.
    Future<void> fillIncome(WidgetTester tester, String amount) async {
      await tester.enterText(find.byType(TextField).first, amount);
      await pickSource(tester, 'Allowance');
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks where it went: cash on hand, cash in bank or both', (
      tester,
    ) async {
      await pumpWaterfall(tester, wallets: [cash, gcash]);

      expect(find.text('Where did it go?'), findsOneWidget);
      expect(find.text('Cash on Hand'), findsOneWidget);
      expect(find.text('Cash in Bank'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
    });

    testWidgets('with no wallet yet, one can be added', (tester) async {
      await pumpWaterfall(tester, wallets: const []);

      expect(find.text('Add wallet'), findsOneWidget);
    });

    testWidgets('starts blank instead of prefilling the setup estimate', (
      tester,
    ) async {
      final settings = AppSettingsProvider()
        ..updateCategoryPreferences({
          'incomeSource': 'Salary',
          'incomeFrequency': 'Semi-monthly',
          // Onboarding stores monthly income divided by two paychecks.
          'income': 30000,
        });
      addTearDown(settings.dispose);
      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            theme: AppTheme.light,
            home: IncomeWaterfallScreen(
              today: today,
              wallets: Stream.value([cash]),
              loadBills: () async => const [],
              goals: Stream.value(const []),
              cycles: Stream.value(const []),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final amountField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(amountField.controller!.text, isEmpty);
      expect(find.textContaining('Usual amount per paycheck'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '28500');
      expect(amountField.controller!.text, '28,500');
    });

    testWidgets('asks for the amount before moving on', (tester) async {
      await pumpWaterfall(tester);

      expect(find.text('Step 1 of 2'), findsOneWidget);
      await next(tester);

      expect(find.text('Enter an amount of at least ₱0.01.'), findsOneWidget);
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

    testWidgets('requires a specification when the income source is Other', (
      tester,
    ) async {
      await pumpWaterfall(tester);
      await tester.enterText(find.byType(TextField).first, '500');
      await pickSource(tester, 'Other');

      await next(tester);
      expect(find.text('Tell us where the money came from.'), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('other-income-source')),
        'Sold my old phone',
      );
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text('Step 2 of 2'), findsOneWidget);
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

    testWidgets('the income goes where the user says, exactly what came in', (
      tester,
    ) async {
      Map<String, double>? income;
      await pumpWaterfall(
        tester,
        wallets: [cash, gcash],
        onConfirm: (plan, into, billsFrom, fees, source) => income = into,
      );

      await tester.enterText(find.byType(TextField).first, '2000');
      await pickSource(tester, 'Allowance');
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      // All of it starts in the cash, ready to be split.
      await tester.enterText(find.byKey(const Key('goes-to-w1')), '1500');
      await tester.enterText(find.byKey(const Key('goes-to-w2')), '700');
      await tester.pumpAndSettle();

      // More than came in is refused.
      await next(tester);
      expect(find.text('That is ₱200 more than ₱2,000.'), findsWidgets);
      expect(find.text('Step 1 of 2'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('goes-to-w2')), '500');
      await tester.pumpAndSettle();
      await next(tester);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(income, {'w1': 1500, 'w2': 500});
    });

    testWidgets('with no bills it goes straight to what is left', (
      tester,
    ) async {
      await pumpWaterfall(tester);

      await fillIncome(tester, '2000');
      await next(tester);

      // Only two steps: nothing to pay and no goals to save for.
      expect(find.text('Step 2 of 2'), findsOneWidget);
      // The review shows the wallets after it: ₱500 cash, plus ₱2,000.
      expect(find.text('Available Balance after this'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('income-available-after')))
            .data,
        '₱2,500',
      );
      expect(find.text('Was ₱500 · +₱2,000'), findsOneWidget);
      // Nothing was taken from it, so no separate "left" line.
      expect(find.text('Left to spend from this income'), findsNothing);
      expect(find.textContaining('No unpaid bills right now'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('step 2 shows overdue and this month’s bills only', (
      tester,
    ) async {
      await pumpWaterfall(
        tester,
        bills: [
          bill('Overdue', 50, dueDate: DateTime(2026, 3, 9)),
          bill('Today', 100, dueDate: DateTime(2026, 3, 10)),
          bill('Soon', 200, dueDate: DateTime(2026, 3, 13)),
          bill('Between', 300, dueDate: DateTime(2026, 3, 14)),
          bill('Last day', 400, dueDate: DateTime(2026, 3, 20)),
          bill('End of month', 500, dueDate: DateTime(2026, 3, 31)),
          bill('Next month', 600, dueDate: DateTime(2026, 4, 1)),
          bill('Far future', 700, dueDate: DateTime(2026, 5, 20)),
        ],
      );

      await fillIncome(tester, '2000');
      await next(tester);

      expect(find.text('Did you pay any bills from it?'), findsOneWidget);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Due today'), findsOneWidget);
      expect(find.text('Soon'), findsOneWidget);
      expect(find.text('Due soon'), findsOneWidget);
      expect(find.text('Upcoming'), findsNWidgets(3));
      expect(find.text('Between'), findsOneWidget);
      expect(find.text('Last day'), findsOneWidget);
      expect(find.text('End of month'), findsOneWidget);
      expect(find.text('Next month'), findsNothing);
      expect(find.text('Far future'), findsNothing);
    });

    testWidgets('bills paid here come from the wallets, each with its fee', (
      tester,
    ) async {
      AllocationPlan? confirmed;
      Map<String, double>? paidFrom;
      Map<String, double>? fees;
      await pumpWaterfall(
        tester,
        bills: [bill('Rent', 1500), bill('Load', 300)],
        onConfirm: (plan, income, billsFrom, charged, source) {
          confirmed = plan;
          paidFrom = billsFrom;
          fees = charged;
        },
      );

      await fillIncome(tester, '5000');
      await next(tester);
      // Nothing to pay from until a bill is ticked.
      expect(find.text('Where did you pay them from?'), findsNothing);
      await tester.tap(find.text('Check all'));
      await tester.pumpAndSettle();
      expect(find.text('Where did you pay them from?'), findsOneWidget);

      // The cash, with this income in it, pays both, and charged ₱15.
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pay-from-fee-w1')), '15');
      await tester.pumpAndSettle();
      // ₱5,000 less ₱1,800 of bills and the ₱15 charge.
      expect(find.text('₱3,185'), findsOneWidget);

      await next(tester);
      expect(find.text('Service charge'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(confirmed?.billsServiceCharge, 15);
      expect(confirmed?.remaining, 3185);
      expect(paidFrom, {'w1': 1800});
      expect(fees, {'w1': 15});
    });

    test('a charge only counts while a bill is being paid', () {
      final rent = BillAllocation(
        instance: BillInstance(
          id: 'r',
          billId: 'b',
          name: 'Rent',
          amount: 1500,
          category: 'Bills',
          dueDate: DateTime(2026, 3, 15),
          status: BillStatus.unpaid,
        ),
        amount: 1500,
      );
      expect(
        AllocationPlan(
          income: 5000,
          bills: [rent],
          serviceCharge: 15,
        ).remaining,
        3485,
      );
      // Nothing paid, so there is nothing to charge for.
      expect(
        const AllocationPlan(
          income: 5000,
          serviceCharge: 15,
        ).billsServiceCharge,
        0,
      );
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
      expect(find.text('Left after these bills'), findsOneWidget);
      expect(find.text('Check all'), findsOneWidget);
      expect(find.text('₱5,000'), findsOneWidget);

      await tester.tap(find.text('Check all'));
      await tester.pumpAndSettle();
      expect(find.text('1500'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.text('₱3,200'), findsOneWidget);
    });

    testWidgets('one tap unticks every bill, and another brings them back', (
      tester,
    ) async {
      await pumpWaterfall(
        tester,
        bills: [bill('Rent', 1500), bill('Load', 300)],
      );

      await fillIncome(tester, '5000');
      await next(tester);

      expect(find.text('Check all'), findsOneWidget);
      expect(find.text('₱5,000'), findsOneWidget);

      await tester.tap(find.text('Check all'));
      await tester.pump();

      expect(find.text('₱3,200'), findsOneWidget);
      expect(find.text('Uncheck all'), findsOneWidget);

      await tester.tap(find.text('Uncheck all'));
      await tester.pump();

      expect(find.text('₱5,000'), findsWidgets);
      expect(find.text('Check all'), findsOneWidget);
    });

    testWidgets('a bill cannot be paid more than it owes', (tester) async {
      await pumpWaterfall(tester, bills: [bill('Rent', 1500)]);

      await fillIncome(tester, '5000');
      await next(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '1500'), '2000');
      await next(tester);

      expect(find.text('Rent only needs ₱1,500.'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsOneWidget);
    });

    testWidgets('confirming saves the income, the bills and what is left', (
      tester,
    ) async {
      AllocationPlan? saved;
      Map<String, double>? savedIncome;
      Map<String, double>? savedBills;
      String? savedSource;

      await pumpWaterfall(
        tester,
        bills: [bill('Rent', 1500), bill('Load', 300)],
        onConfirm: (plan, income, billsFrom, fees, source) {
          saved = plan;
          savedIncome = income;
          savedBills = billsFrom;
          savedSource = source;
        },
      );

      await fillIncome(tester, '5000');
      await next(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      await next(tester);

      // What this income leaves after the rent, and what all the wallets
      // will hold once it is confirmed.
      expect(find.text('Left to spend from this income'), findsOneWidget);
      expect(find.text('₱3,500'), findsOneWidget);
      expect(find.text('Available Balance after this'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(saved!.income, 5000);
      expect(saved!.toBills, 1500);
      expect(saved!.bills.map((b) => b.instance.name), ['Rent']);
      expect(savedIncome, {'w1': 5000});
      expect(savedBills, {'w1': 1500});
      expect(savedSource, 'Allowance');
    });

    testWidgets('bills paid only from what a wallet really has', (
      tester,
    ) async {
      await pumpWaterfall(
        tester,
        wallets: [cash, gcash],
        bills: [bill('Rent', 3000)],
      );

      await fillIncome(tester, '1000');
      await next(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Short by'), findsOneWidget);

      // The cash has its ₱500 and the ₱1,000 that just came in: no more.
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pay-from-w1')), '3000');
      await tester.pumpAndSettle();
      expect(find.textContaining('Only ₱1,500 in Cash is free'), findsWidgets);

      // The rest from GCash, from money already there.
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pay-from-w1')), '1500');
      await tester.enterText(find.byKey(const Key('pay-from-w2')), '1500');
      await tester.pumpAndSettle();
      await next(tester);

      expect(find.text('More than came in'), findsOneWidget);
      expect(
        find.textContaining('comes out of what was already in your wallets'),
        findsOneWidget,
      );
    });
  });

  group('which way the money went', () {
    Wallet pocket(String id, String name, WalletPurpose purpose) => Wallet(
      id: id,
      name: name,
      type: WalletType.other,
      balance: 1000,
      startingBalance: 1000,
      receivesIncome: false,
      archived: false,
      sortOrder: 0,
      purpose: purpose,
    );

    final wallets = [
      pocket('cash', 'Cash', WalletPurpose.spending),
      pocket('gcash', 'GCash', WalletPurpose.spending),
      pocket('save', 'Savings', WalletPurpose.savings),
    ];

    AppTransaction entry(
      TransactionType type, {
      String walletId = 'cash',
      String? toWalletId,
    }) => AppTransaction(
      id: 't',
      type: type,
      amount: 500,
      label: 'Thing',
      date: DateTime(2026, 3, 10),
      walletId: walletId,
      toWalletId: toWalletId,
    );

    test('earning and spending are inflow and outflow, and carry a sign', () {
      final inward = transactionDirection(
        entry(TransactionType.income),
        wallets,
      );
      expect(inward.label, 'Inflow');
      expect(inward.sign, '+');

      final outward = transactionDirection(
        entry(TransactionType.expense),
        wallets,
      );
      expect(outward.label, 'Outflow');
      expect(outward.sign, '-');
    });

    test('moving your own money is a deposit or a withdrawal, unsigned', () {
      // Into savings.
      final deposit = transactionDirection(
        entry(TransactionType.transfer, toWalletId: 'save'),
        wallets,
      );
      expect(deposit.label, 'Deposit');
      expect(
        deposit.sign,
        isEmpty,
        reason: 'nothing was earned or spent, so no plus or minus',
      );

      // Back out of savings.
      expect(
        transactionDirection(
          entry(TransactionType.transfer, walletId: 'save', toWalletId: 'cash'),
          wallets,
        ).label,
        'Withdraw',
      );

      // Between two spending wallets it is neither.
      expect(
        transactionDirection(
          entry(TransactionType.transfer, toWalletId: 'gcash'),
          wallets,
        ).label,
        'Moved',
      );
    });

    test('a wallet reads a transfer from its own side', () {
      final transfer = entry(TransactionType.transfer, toWalletId: 'save');

      expect(
        transactionDirection(transfer, wallets, forWalletId: 'cash').label,
        'Withdraw',
        reason: 'the money left this wallet',
      );
      expect(
        transactionDirection(transfer, wallets, forWalletId: 'save').label,
        'Deposit',
        reason: 'the same move, seen from where it landed',
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

    test('every 2 weeks falls due fortnightly, not twice a month', () {
      final plan = bill(
        firstDueDate: DateTime(2026, 3, 5),
        recurrence: BillRecurrence.fortnightly,
      );

      // 14 days apart, so a long month holds three and the next starts
      // wherever the last one left off.
      expect(plan.occurrencesIn(2026, 3), [
        DateTime(2026, 3, 5),
        DateTime(2026, 3, 19),
      ]);
      expect(plan.occurrencesIn(2026, 4), [
        DateTime(2026, 4, 2),
        DateTime(2026, 4, 16),
        DateTime(2026, 4, 30),
      ]);
      // Nothing before it starts.
      expect(plan.occurrencesIn(2026, 2), isEmpty);
    });

    test('twice a month falls due on the day and fifteen days later', () {
      final plan = bill(
        firstDueDate: DateTime(2026, 3, 15),
        recurrence: BillRecurrence.semiMonthly,
      );

      // Paid on the 15th and the 30th, the way a deduction from pay works.
      expect(plan.occurrencesIn(2026, 3), [
        DateTime(2026, 3, 15),
        DateTime(2026, 3, 30),
      ]);
      expect(plan.occurrencesIn(2026, 4), [
        DateTime(2026, 4, 15),
        DateTime(2026, 4, 30),
      ]);
      // February is short, so the second date falls on the last day.
      expect(
        bill(
          firstDueDate: DateTime(2026, 1, 20),
          recurrence: BillRecurrence.semiMonthly,
        ).occurrencesIn(2026, 2),
        [DateTime(2026, 2, 20), DateTime(2026, 2, 28)],
      );
    });

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
        BillUrgency.dueToday,
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
      expect(
        instance(dueDate: DateTime(2026, 3, 20)).urgency(now: today),
        BillUrgency.upcoming,
        reason: 'due in 10 days',
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

    testWidgets(
      'changing one bill rejects a blank amount and cancels cleanly',
      (tester) async {
        await pumpDetail(tester, current: instance());

        Future<void> openMenu() async {
          await tester.tap(find.byTooltip('Bill options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text("Change this date's amount"));
          await tester.pumpAndSettle();
        }

        await openMenu();
        expect(find.text('This date only'), findsOneWidget);

        // Backing out tears the dialog down while its text field is still on
        // screen, which is where it used to fall over.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('This date only'), findsNothing);
        expect(tester.takeException(), isNull);

        // A missing amount stays open and explains what needs correcting.
        await openMenu();
        await tester.enterText(find.byType(TextField).last, '');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Enter an amount of at least ₱0.01.'), findsOneWidget);
        expect(find.text('This date only'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('This date only'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

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
      // What is paid on the current due date stands; only a payment made
      // ahead, on next month's due date, can be taken back.
      expect(find.text('Undo payment'), findsNothing);
      expect(
        find.textContaining('The current due payment is final'),
        findsOneWidget,
      );
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
      expect(find.text('Undo payment'), findsNothing);
    });

    testWidgets('a bill paid ahead for next month can be undone', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        current: instance(
          id: 'b1_20260405',
          amountPaid: 3000,
          status: BillStatus.paid,
          dueDate: DateTime(2026, 4, 5),
        ),
      );

      expect(find.text('Undo payment'), findsOneWidget);
      expect(
        find.textContaining('The current due payment is final'),
        findsNothing,
      );
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
        find.textContaining('left unpaid from the bill before'),
        findsOneWidget,
      );
    });

    testWidgets('undoing an advance payment warns the money goes back', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        current: instance(
          id: 'b1_20260405',
          amountPaid: 3000,
          status: BillStatus.paid,
          dueDate: DateTime(2026, 4, 5),
        ),
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
      expect(
        find.text('This is the only scheduled bill so far.'),
        findsNothing,
      );
    });

    testWidgets('a single cycle says so instead of showing an empty list', (
      tester,
    ) async {
      await pumpDetail(tester, current: instance(), history: [instance()]);

      expect(
        find.text('This is the only scheduled bill so far.'),
        findsOneWidget,
      );
    });
  });

  group('Transfer service charge', () {
    testWidgets('the charge comes out of the same wallet as the transfer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final gcash = Wallet(
        id: 'gcash',
        name: 'GCash',
        type: WalletType.gcash,
        balance: 1000,
        startingBalance: 1000,
        receivesIncome: true,
        archived: false,
        sortOrder: 0,
        serviceCharge: 15,
      );
      final bpi = Wallet(
        id: 'bpi',
        name: 'BPI',
        type: WalletType.bank,
        balance: 0,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 1,
      );
      double? moved;
      double? fee;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TransferSheet(
                wallets: Stream.value([gcash, bpi]),
                initialFromWalletId: 'gcash',
                initialToWalletId: 'bpi',
                initialAmount: 1000,
                onSave:
                    ({
                      required String fromWalletId,
                      required Map<String, double> to,
                      required double serviceCharge,
                    }) {
                      moved = to['bpi'];
                      fee = serviceCharge;
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('service-charge-switch')),
      );
      await tester.tap(find.byKey(const Key('service-charge-switch')));
      await tester.pumpAndSettle();
      expect(find.text('15'), findsOneWidget, reason: "GCash's usual fee");

      // ₱1,000 plus the ₱15 fee is more than GCash holds.
      await tester.ensureVisible(find.text('Transfer').last);
      await tester.tap(find.text('Transfer').last);
      await tester.pump();
      expect(
        find.textContaining('With the ₱15 service charge, that is ₱1,015.'),
        findsOneWidget,
      );
      expect(moved, isNull);

      await tester.enterText(find.byKey(const Key('goes-to-bpi')), '985');
      await tester.pump();
      await tester.ensureVisible(find.text('Transfer').last);
      await tester.tap(find.text('Transfer').last);
      await tester.pumpAndSettle();
      expect(moved, 985);
      expect(fee, 15);
    });

    test('the charge is an expense under Service Charge', () {
      expect(expenseCategories, contains(serviceChargeCategory));
      expect(expenseCategories, contains('Supplies'));
      expect(expenseCategories.last, 'Others');
    });
  });

  group('Bill payment', () {
    final cash = Wallet(
      id: 'w1',
      name: 'Cash',
      type: WalletType.cash,
      balance: 5000,
      startingBalance: 5000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    final gcash = Wallet(
      id: 'w2',
      name: 'GCash',
      type: WalletType.gcash,
      balance: 5000,
      startingBalance: 5000,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
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

    Future<void> pumpSheet(
      WidgetTester tester, {
      bool payInFull = true,
      List<Wallet>? wallets,
      List<Goal> goals = const [],
      void Function(List<BillPaymentPart> parts)? onPay,
    }) async {
      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: BillPaymentSheet(
                instance: instance,
                payInFull: payInFull,
                wallets: Stream.value(wallets ?? [cash, gcash]),
                goals: Stream.value(goals),
                onPay: onPay ?? (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> pay(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('bill-pay-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks cash on hand, cash in bank or both, then fills it in', (
      tester,
    ) async {
      await pumpSheet(tester);

      expect(find.textContaining('₱3,000 still owing'), findsOneWidget);
      expect(find.text('Where are you paying from?'), findsOneWidget);

      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('pay-from-w1')),
          matching: find.text('3000'),
        ),
        findsOne,
      );
      expect(find.text('Pay ₱3,000'), findsOneWidget);
    });

    testWidgets('starts empty when paying only part of it', (tester) async {
      await pumpSheet(tester, payInFull: false);
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('pay-from-w1')),
          matching: find.text('3000'),
        ),
        findsNothing,
      );
    });

    testWidgets('refuses to pay more than the bill needs', (tester) async {
      List<BillPaymentPart>? paid;
      await pumpSheet(tester, payInFull: false, onPay: (parts) => paid = parts);
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('pay-from-w1')), '5000');
      await pay(tester);

      expect(find.text('That is ₱2,000 more than ₱3,000.'), findsWidgets);
      expect(paid, isNull);
    });

    testWidgets('a wallet pays only what it has free, its fee included', (
      tester,
    ) async {
      // GCash charged ₱15 last time, and holds ₱3,010.
      final charged = Wallet(
        id: 'w2',
        name: 'GCash',
        type: WalletType.gcash,
        balance: 3010,
        startingBalance: 3010,
        receivesIncome: false,
        archived: false,
        sortOrder: 1,
        serviceCharge: 15,
      );
      List<BillPaymentPart>? paid;
      await pumpSheet(
        tester,
        wallets: [cash, charged],
        onPay: (parts) => paid = parts,
      );

      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      // What it charged before is a hint, never filled in for the user.
      expect(find.text('Last time ₱15'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('pay-from-fee-w2')), '15');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Only ₱3,010 in GCash is free. With the ₱15 fee, this needs '
          '₱3,015.',
        ),
        findsWidgets,
      );
      await pay(tester);
      expect(paid, isNull);

      await tester.enterText(find.byKey(const Key('pay-from-fee-w2')), '10');
      await tester.pumpAndSettle();
      expect(find.text('Pay ₱3,010'), findsOneWidget);
      await pay(tester);

      expect(paid?.single.walletId, 'w2');
      expect(paid?.single.amount, 3000);
      expect(paid?.single.serviceCharge, 10);
    });

    testWidgets('one bill can be paid partly in cash and partly by bank', (
      tester,
    ) async {
      final little = Wallet(
        id: 'w1',
        name: 'Cash',
        type: WalletType.cash,
        balance: 1000,
        startingBalance: 1000,
        receivesIncome: true,
        archived: false,
        sortOrder: 0,
      );
      List<BillPaymentPart>? paid;
      await pumpSheet(
        tester,
        wallets: [little, gcash],
        onPay: (parts) => paid = parts,
      );

      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      // The cash gives all it has; the bank the rest.
      expect(
        find.descendant(
          of: find.byKey(const Key('pay-from-w1')),
          matching: find.text('1000'),
        ),
        findsOne,
      );
      await tester.enterText(find.byKey(const Key('pay-from-w2')), '2000');
      await tester.pumpAndSettle();
      await pay(tester);

      expect(
        {for (final part in paid!) part.walletId: part.amount},
        {'w1': 1000, 'w2': 2000},
      );
    });

    testWidgets('goal money is never used to pay a bill', (tester) async {
      await pumpSheet(
        tester,
        goals: const [
          Goal(
            id: 'g',
            name: 'Trip',
            targetAmount: 10000,
            savedAmount: 4000,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'w1': 4000},
          ),
        ],
      );

      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pay-from-w1')), '3000');
      await tester.pumpAndSettle();

      expect(
        find.text('Only ₱1,000 in Cash is free; goals hold the rest.'),
        findsWidgets,
      );
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

    // The same bill paid ahead, on next month's due date: the only payment
    // the screen lets the user take back.
    final paidAhead = BillInstance(
      id: 'b1_20260405',
      billId: 'b1',
      name: 'Rent',
      amount: 3000,
      category: 'Bills',
      dueDate: DateTime(2026, 4, 5),
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

    Future<void> pumpDetail(
      WidgetTester tester, {
      BillInstance? current,
    }) async {
      final shown = current ?? partlyPaid;
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
              instance: shown,
              today: today,
              liveInstance: Stream.value(shown),
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
      await pumpDetail(tester, current: paidAhead);

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
        'Enter an amount of at least ₱0.01.',
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

    test('search matches category, note or transaction type', () {
      const filter = TransactionFilter(query: 'rent');
      expect(
        filter.matches(t('a', label: 'Bills', date: DateTime(2026, 3, 10))),
        isFalse,
      );
      expect(
        filter.matches(
          AppTransaction(
            id: 'rent',
            type: TransactionType.expense,
            amount: 100,
            label: 'Bills',
            date: DateTime(2026, 3, 10),
            note: 'Monthly rent',
          ),
        ),
        isTrue,
      );
      expect(
        const TransactionFilter(
          query: 'inco',
        ).matches(t('income', type: TransactionType.income, label: 'Salary')),
        isTrue,
      );
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
      List<AppTransaction> transactions,
    ) async {
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
      expect(find.textContaining('Cash · Bill payment · Rent'), findsOneWidget);
      expect(find.textContaining('Before wallets'), findsOneWidget);
    });

    testWidgets('transaction history rows are not interactive', (tester) async {
      await pumpList(tester, [
        AppTransaction(
          id: 'e',
          type: TransactionType.expense,
          amount: 120,
          label: 'Food',
          date: now,
          walletId: 'cash',
        ),
      ]);

      await tester.tap(find.text('Food'));
      await tester.pump();
      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('search button opens search and transaction filters', (
      tester,
    ) async {
      await pumpList(tester, [
        AppTransaction(
          id: 'a',
          type: TransactionType.expense,
          amount: 120,
          label: 'Bills',
          date: now,
          walletId: 'cash',
          note: 'Monthly rent',
        ),
        AppTransaction(
          id: 'b',
          type: TransactionType.expense,
          amount: 80,
          label: 'Food',
          date: now,
          walletId: 'cash',
        ),
      ]);

      expect(find.byTooltip('Filter'), findsNothing);
      await tester.tap(find.byKey(const Key('transaction-search-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Search & filters'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('transaction-search-input')),
        'rent',
      );
      await tester.pump();
      // How many match shows before the sheet closes.
      await tester.tap(find.text('Show 1 result'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing:'), findsOneWidget);
      expect(find.textContaining('Monthly rent'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
    });

    testWidgets('the filters count matches and clear in place', (tester) async {
      await pumpList(tester, [
        AppTransaction(
          id: 'a',
          type: TransactionType.expense,
          amount: 120,
          label: 'Bills',
          date: now,
          walletId: 'cash',
        ),
        AppTransaction(
          id: 'b',
          type: TransactionType.income,
          amount: 500,
          label: 'Allowance',
          date: now,
          walletId: 'cash',
        ),
      ]);
      await tester.tap(find.byKey(const Key('transaction-search-filters')));
      await tester.pumpAndSettle();

      // Nothing chosen yet: everything shows, and nothing to clear.
      expect(find.text('Show 2 results'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('filter-clear')))
            .onPressed,
        isNull,
      );

      // Tiles that keep their place when chosen.
      final before = tester.getRect(
        find.byKey(const Key('filter-type-income')),
      );
      await tester.tap(find.byKey(const Key('filter-type-expense')));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const Key('filter-type-income'))),
        before,
      );
      expect(find.text('Show 1 result'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-date-thisMonth')));
      await tester.pump();
      expect(find.text('Show 1 result'), findsOneWidget);
      await tester.tap(find.byKey(const Key('filter-date-lastMonth')));
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget);

      // Clear all starts over here, without closing.
      await tester.tap(find.byKey(const Key('filter-clear')));
      await tester.pump();
      expect(find.text('Search & filters'), findsOneWidget);
      expect(find.text('Show 2 results'), findsOneWidget);
    });
  });

  group('which wallets an entry may come from', () {
    Wallet holding(String id, WalletPurpose purpose) => Wallet(
      id: id,
      name: purpose.defaultName ?? id,
      type: WalletType.other,
      balance: 1000,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
      purpose: purpose,
    );

    final cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 500,
      startingBalance: 500,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );

    Future<void> pumpPicker(
      WidgetTester tester, {
      Set<WalletPurpose>? allowed,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: WalletPicker(
                wallets: [
                  cash,
                  holding('b', WalletPurpose.bills),
                  holding('s', WalletPurpose.savings),
                ],
                selectedId: 'cash',
                onChanged: (_) {},
                allowed: allowed ?? const {WalletPurpose.spending},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
    }

    testWidgets('spending money only, by default', (tester) async {
      await pumpPicker(tester);

      expect(find.text('Cash'), findsWidgets);
      expect(find.text('Savings'), findsNothing);
      expect(find.text('Bills'), findsNothing);
    });

    testWidgets('paying a bill may come from the bills wallet, never savings', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        allowed: const {WalletPurpose.spending, WalletPurpose.bills},
      );

      expect(find.text('Bills'), findsOneWidget);
      expect(find.text('Savings'), findsNothing);
    });

    testWidgets('a transfer may move money in and out of either', (
      tester,
    ) async {
      await pumpPicker(tester, allowed: WalletPurpose.values.toSet());

      expect(find.text('Bills'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
    });
  });

  group('the Set aside tab', () {
    Wallet holding(String id, double balance, WalletPurpose purpose) {
      return Wallet(
        id: id,
        name: purpose.defaultName ?? id,
        type: WalletType.other,
        balance: balance,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: purpose,
      );
    }

    Future<void> pumpSetAside(
      WidgetTester tester, {
      List<Wallet> wallets = const [],
      List<Goal> goals = const [],
    }) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: SetAsideScreen(
              wallets: Stream.value(wallets),
              goals: Stream.value(goals),
              today: DateTime(2026, 9, 28),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('savings opens with what is free of the goals', (tester) async {
      await pumpSetAside(
        tester,
        wallets: [holding('s', 2000, WalletPurpose.savings)],
        goals: const [
          Goal(
            id: 'e',
            name: 'Emergency fund',
            targetAmount: 10000,
            savedAmount: 1500,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'s': 1500},
          ),
        ],
      );

      expect(find.text('Savings'), findsWidgets);
      expect(find.text('Total balance'), findsOneWidget);
      // The goal itself is in Goals, not listed again here.
      expect(find.text('Emergency fund'), findsNothing);
      expect(find.text('What it is for'), findsNothing);
      expect(find.text('Transfer money'), findsOneWidget);

      // The headline total is what remains available after ₱1,500 is
      // contributed to the goal. The record below still shows the wallet's
      // real ₱2,000 balance.
      // The record's card says the same: ₱1,500 for goals, ₱500 free.
      expect(find.text('₱500'), findsNWidgets(2));
      expect(find.text('Towards your goals'), findsOneWidget);
      expect(find.text('Set aside for goals'), findsOneWidget);
      expect(find.text('₱1,500'), findsNWidgets(2));
      expect(find.textContaining('₱2,000 saved'), findsOneWidget);
    });

    testWidgets('savings reads zero when the goals hold it all', (
      tester,
    ) async {
      await pumpSetAside(
        tester,
        wallets: [holding('s', 1000, WalletPurpose.savings)],
        goals: const [
          Goal(
            id: 'e',
            name: 'Emergency fund',
            targetAmount: 10000,
            savedAmount: 2500,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'s': 2500},
          ),
        ],
      );

      // The available total is zero when the goal claim exceeds the wallet,
      // and the record's card says nothing of it is free.
      expect(find.text('₱0'), findsNWidgets(2));
      // The record still reads the wallet's real ₱1,000 balance.
      expect(find.textContaining('₱1,000 saved'), findsOneWidget);
    });

    testWidgets('editing savings keeps goal-assigned money backed', (
      tester,
    ) async {
      await pumpSetAside(
        tester,
        wallets: [holding('s', 2500, WalletPurpose.savings)],
        goals: const [
          Goal(
            id: 'laptop',
            name: 'Laptop',
            targetAmount: 5000,
            savedAmount: 2500,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'s': 2500},
          ),
        ],
      );

      // The blue pencil on the record's card opens it.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('set-aside-record-s')),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('set-aside-balance')), '0');
      await tester.tap(find.byKey(const Key('set-aside-save')));
      await tester.pump();

      expect(
        find.textContaining('₱2,500 is already assigned to goals'),
        findsOneWidget,
      );
    });

    testWidgets('only savings: no bills money, no switch to it', (
      tester,
    ) async {
      await pumpSetAside(
        tester,
        wallets: [holding('s', 2000, WalletPurpose.savings)],
      );

      expect(find.text('Bills wallet'), findsNothing);
      expect(find.text('Add Bills Money'), findsNothing);
      expect(find.text('Add Savings'), findsOneWidget);
      // Goals are added from Goals on Home, so nothing here opens them.
      expect(find.text('Manage goals'), findsNothing);
    });

    testWidgets('money can be moved out of a savings deposit, not a time '
        'deposit', (tester) async {
      await pumpSetAside(
        tester,
        wallets: [
          holding('s', 2000, WalletPurpose.savings),
          Wallet(
            id: 'td',
            name: 'Time Deposit',
            type: WalletType.other,
            balance: 10000,
            startingBalance: 10000,
            receivesIncome: false,
            archived: false,
            sortOrder: 2,
            purpose: WalletPurpose.savings,
            savingsKind: SavingsKind.timeDeposit.name,
            maturityDate: DateTime(2027, 4, 25),
          ),
        ],
      );

      expect(find.byKey(const Key('move-out-s')), findsOneWidget);
      expect(find.byKey(const Key('move-out-td')), findsNothing);
    });

    testWidgets('an account with nothing set aside says so', (tester) async {
      await pumpSetAside(tester);

      expect(find.text('₱0'), findsOneWidget);
      // Goals are made in Goals, so the Savings wallet doesn't ask for one.
      expect(find.text('No savings goal yet'), findsNothing);
      expect(find.text('Add Savings'), findsOneWidget);
    });
  });

  group('pay periods', () {
    test('period lengths follow weekly, semi-monthly and calendar months', () {
      final weekly = payPeriodFor('Weekly', now: DateTime(2026, 3, 4));
      final semiMonthly = payPeriodFor(
        'Semi-monthly',
        now: DateTime(2026, 3, 3),
      );
      final march = payPeriodFor('Monthly', now: DateTime(2026, 3, 3));
      final april = payPeriodFor('Monthly', now: DateTime(2026, 4, 3));

      expect(weekly.end.difference(weekly.start).inDays, 7);
      expect(semiMonthly.end.difference(semiMonthly.start).inDays, 15);
      expect(march.end.difference(march.start).inDays, 31);
      expect(april.end.difference(april.start).inDays, 30);
    });

    test('semi-monthly starts on the 15th or 30th until pay is logged', () {
      final early = payPeriodFor('Semi-monthly', now: DateTime(2026, 3, 10));
      final late = payPeriodFor('Semi-monthly', now: DateTime(2026, 3, 20));

      // February pays on the 28th, the nearest it has to the 30th.
      expect(early.start, DateTime(2026, 2, 28));
      expect(early.end, DateTime(2026, 3, 15));
      expect(early.daysLeft(DateTime(2026, 3, 10)), 5);
      expect(late.start, DateTime(2026, 3, 15));
      expect(late.end, DateTime(2026, 3, 30));
      expect(late.end.difference(late.start).inDays, 15);
    });

    test('pay twice a month lasts fifteen days from the day it is logged', () {
      // Logged four days late: the period still runs a full fifteen days
      // rather than the few left before the next scheduled payday.
      final period = payPeriodFor(
        'Semi-monthly',
        lastIncomeAt: DateTime(2026, 3, 19),
        now: DateTime(2026, 3, 20),
      );

      expect(period.start, DateTime(2026, 3, 19));
      expect(period.end, DateTime(2026, 4, 3));
      expect(period.end.difference(period.start).inDays, semiMonthlyDays);
      expect(period.daysLeft(DateTime(2026, 3, 20)), 14);
    });

    test('semi-monthly payday anchors advance to scheduled dates', () {
      final period = payPeriodFor(
        'Semi-monthly',
        lastIncomeAt: DateTime(2026, 3, 16),
        now: DateTime(2026, 3, 27),
      );

      expect(period.start, DateTime(2026, 3, 16));
      expect(period.end, DateTime(2026, 3, 31));
      expect(period.daysLeft(DateTime(2026, 3, 27)), 4);
    });

    test('semi-monthly periods keep their length through February', () {
      final february = payPeriodFor(
        'Semi-monthly',
        lastIncomeAt: DateTime(2026, 1, 31),
        now: DateTime(2026, 2, 20),
      );

      expect(february.start, DateTime(2026, 2, 15));
      expect(february.end, DateTime(2026, 3, 2));

      final march = payPeriodFor(
        'Semi-monthly',
        lastIncomeAt: DateTime(2026, 2, 28),
        now: DateTime(2026, 3, 20),
      );
      expect(march.start, DateTime(2026, 3, 15));
      expect(march.end, DateTime(2026, 3, 30));
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
    test('bills come off before sharing over the days left', () {
      const s = SafeToSpend(
        walletBalance: 10000,
        billsDue: 3000,
        spentToday: 0,
        daysLeft: 10,
      );

      expect(s.spendableThisPeriod, 7000);
      expect(s.recommendedDailyLimit, 700);
      expect(s.leftToday, 700);
    });

    test('period budget is shared across days and reduces as spent', () {
      const s = SafeToSpend(
        walletBalance: 10000,
        billsDue: 0,
        spentToday: 0,
        daysLeft: 15,
        periodBudget: 3000,
        periodLengthDays: 15,
      );

      expect(s.spendableThisPeriod, 3000);
      expect(s.recommendedDailyLimit, 200);
      expect(s.walletBalance, 10000);

      const later = SafeToSpend(
        walletBalance: 9500,
        billsDue: 0,
        spentToday: 100,
        daysLeft: 10,
        periodBudget: 3000,
        periodSpent: 500,
        periodLengthDays: 15,
      );

      expect(later.spendableThisPeriod, 2600);
      expect(later.recommendedDailyLimit, 200);
    });

    test('bills still to pay this month are held back from spending', () {
      // ₱8,000 in the wallets, ₱5,000 of it for bills not paid yet: bills
      // are paid straight from the wallets, so all of it is held back.
      const s = SafeToSpend(
        walletBalance: 8000,
        billsDue: 5000,
        spentToday: 0,
        daysLeft: 15,
        periodBudget: 3000,
        periodLengthDays: 15,
      );

      expect(s.spendableThisPeriod, 3000);
      expect(s.recommendedDailyLimit, 200);
      expect(s.leftToday, 200);
    });

    test('a bill paid is no longer held back', () {
      // ₱1,000 still owed; the ₱4,000 already paid left the wallets.
      const s = SafeToSpend(
        walletBalance: 3000,
        billsDue: 1000,
        spentToday: 0,
        daysLeft: 10,
      );

      expect(s.spendableThisPeriod, 2000);
      expect(s.recommendedDailyLimit, 200);
    });

    test('the day\'s limit is always the worked-out one', () {
      const s = SafeToSpend(
        walletBalance: 10000,
        billsDue: 0,
        spentToday: 0,
        daysLeft: 15,
        periodBudget: 3000,
        periodLengthDays: 15,
      );

      // Nothing can be typed over it, so Safe to Spend can never promise
      // more than the money and the days allow.
      expect(s.dailyLimit, s.recommendedDailyLimit);
      expect(s.dailyLimit, 200);
    });

    test("spending today doesn't shrink today's own limit", () {
      // The balance already dropped by the 200 spent, so it is added back
      // before sharing out, and taken off once, from what is left today.
      const s = SafeToSpend(
        walletBalance: 5800,
        billsDue: 0,
        spentToday: 200,
        daysLeft: 10,
      );

      expect(s.dailyLimit, 600);
      expect(s.leftToday, 400);
      expect(s.usedFraction, closeTo(1 / 3, 0.001));
    });

    test('going past the day\'s limit reads as over', () {
      // The balance already dropped by the 1,350 spent, so it is added back
      // before sharing: 3,650 + 1,350 = 5,000 over five days is 1,000 a day.
      const s = SafeToSpend(
        walletBalance: 3650,
        billsDue: 0,
        spentToday: 1350,
        daysLeft: 5,
      );

      expect(s.dailyLimit, 1000);
      expect(s.leftToday, -350);
      expect(s.isOverLimit, isTrue);
      expect(s.usedFraction, 1);
    });

    test('owing more than you have means nothing is safe to spend', () {
      const s = SafeToSpend(
        walletBalance: 1000,
        billsDue: 4000,
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

    test('is due on the last day of the month, not before', () {
      final cycles = [cycle()];

      expect(cycleAwaitingReview(cycles, now: DateTime(2026, 3, 30)), isNull);
      expect(
        cycleAwaitingReview(cycles, now: DateTime(2026, 3, 31)),
        isNotNull,
      );
    });

    test('a decided leftover is not asked about again, a deferred one is', () {
      final late = DateTime(2026, 4, 5);

      expect(
        cycleAwaitingReview([
          cycle(decision: LeftoverDecision.saved),
        ], now: late),
        isNull,
      );
      expect(
        cycleAwaitingReview([
          cycle(decision: LeftoverDecision.pending),
        ], now: late),
        isNotNull,
      );
    });

    test("the leftover is what bills left, less the month's spending", () {
      final c = cycle(remaining: 2000);
      final period = periodOf(c);

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
          // April's, not March's.
          date: DateTime(2026, 4, 2),
          walletId: 'w',
        ),
      ], period);

      expect(leftover, 1300);
    });

    Future<void> pumpReview(
      WidgetTester tester, {
      required void Function(LeftoverDecision, double, double) onResolve,
      void Function(LeftoverSaving saving)? onSaving,
      List<Goal> goals = const [
        Goal(
          id: 'trip',
          name: 'Trip',
          targetAmount: 10000,
          savedAmount: 0,
          priority: 0,
          status: GoalStatus.active,
        ),
      ],
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
              onSaving: onSaving,
              wallets: Stream.value([
                Wallet(
                  id: 'w',
                  name: 'Cash',
                  type: WalletType.cash,
                  balance: 5000,
                  startingBalance: 5000,
                  receivesIncome: true,
                  archived: false,
                  sortOrder: 0,
                ),
              ]),
              goals: Stream.value(goals),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> fromCash(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Cash on Hand'));
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for a choice before confirming', (tester) async {
      LeftoverDecision? decided;
      await pumpReview(tester, onResolve: (d, _, _) => decided = d);

      await tester.tap(find.text('Confirm'));
      await tester.pump();

      expect(find.text('Choose what to do with it first.'), findsOneWidget);
      expect(decided, isNull);

      // Choosing is the fix, so the message goes with it.
      await tester.tap(find.text('Save it'));
      await tester.pump();
      expect(find.text('Choose what to do with it first.'), findsNothing);
      expect(decided, isNull);
    });

    testWidgets('saving records the whole amount, where it went', (
      tester,
    ) async {
      LeftoverDecision? decided;
      double? saved;
      LeftoverSaving? saving;
      await pumpReview(
        tester,
        onResolve: (d, s, _) {
          decided = d;
          saved = s;
        },
        onSaving: (value) => saving = value,
      );

      await tester.tap(find.text('Save it'));
      await tester.pumpAndSettle();
      // Toward the goal, and it stays in the cash it is in.
      expect(find.text('Goal: Trip'), findsOneWidget);
      await fromCash(tester);
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(decided, LeftoverDecision.saved);
      expect(saved, 1000);
      expect(saving?.goal?.id, 'trip');
      expect(saving?.from, {'w': 1000});
    });

    testWidgets('with no goal or savings account, saving says what to add', (
      tester,
    ) async {
      LeftoverDecision? decided;
      await pumpReview(
        tester,
        goals: const [],
        onResolve: (d, _, _) => decided = d,
      );

      await tester.tap(find.text('Save it'));
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pump();

      expect(
        find.text(
          'To save it, first add a goal in Goals or a savings account in '
          'Savings.',
        ),
        findsOneWidget,
      );
      expect(decided, isNull);
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

      // Gone as soon as they add up, before Confirm is tapped again.
      await tester.enterText(find.byType(TextField).at(1), '200');
      await tester.pump();
      expect(find.textContaining('must add up to'), findsNothing);
      await fromCash(tester);
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(decided, LeftoverDecision.split);
    });

    testWidgets('a split typed with commas is read', (tester) async {
      double? saved;
      await pumpReview(tester, onResolve: (_, s, _) => saved = s);

      await tester.tap(find.text('Split it'));
      await tester.pump();
      // Typed as 1000, shown as 1,000.
      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.enterText(find.byType(TextField).at(1), '0');
      await tester.pump();
      await fromCash(tester);
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Enter both amounts.'), findsNothing);
      expect(saved, 1000);
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

    testWidgets('uses the spendable wallet balance with four days left', (
      tester,
    ) async {
      final payday = DateTime(2026, 3, 16, 10);
      // March 28 to 31.
      final today = DateTime(2026, 3, 28, 10);

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
                  'incomeFrequency': 'Semi-monthly',
                  'incomeSource': 'Salary',
                  // The period is counted from the payday on the profile.
                  'lastPaydayAt': Timestamp.fromDate(payday),
                  'plannedAllocations': {
                    'bills': 5000,
                    'savings': 2000,
                    'others': 3000,
                  },
                }),
                cycles: Stream.value([
                  AllocationCycle(
                    id: 'pay',
                    income: 10000,
                    remaining: 10000,
                    receivedAt: payday,
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

      expect(find.text('4 days left this month'), findsOneWidget);
      expect(find.text('of ₱1,450 daily limit'), findsOneWidget);
    });

    testWidgets('a gift raises the daily limit, within the same month', (
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
                transactions: Stream.value(const []),
                profile: Stream.value({
                  'incomeFrequency': 'Monthly',
                  'incomeSource': 'Salary',
                  // Paid on the 10th, which is what the period runs from.
                  'lastPaydayAt': Timestamp.fromDate(DateTime(2026, 3, 10)),
                  'plannedAllocations': {'others': 100},
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

      // March 22 to 31: 5800 over 10 days. The gift adds to this month; it
      // does not start a new one.
      expect(find.text('10 days left this month'), findsOneWidget);
      expect(find.text('of ₱580 daily limit'), findsOneWidget);
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

      // 5800 + 200 spent today, over the 10 days left of March.
      expect(find.text('Safe to Spend Today'), findsOneWidget);
      expect(find.text('₱400'), findsOneWidget);
      expect(find.text('of ₱600 daily limit'), findsOneWidget);
      expect(find.text('Today spent: ₱200'), findsOneWidget);
      expect(find.text('10 days left this month'), findsOneWidget);
    });

    testWidgets('a brand new account is told what to do, not shown ₱0 a day', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SafeToSpendCard(
                today: DateTime(2026, 3, 22, 10),
                // Nothing set up yet: no wallets, no income, no bills.
                wallets: Stream.value(const []),
                transactions: Stream.value(const []),
                profile: Stream.value(const {}),
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

      await tester.tap(find.byKey(const Key('safe-to-spend-info')));
      await tester.pumpAndSettle();

      // "All of it is yours to spend" would be an odd thing to say about
      // nothing, and "₱0 a day" helps no one.
      expect(
        find.textContaining('Once you add income or a wallet balance'),
        findsOneWidget,
      );
      expect(find.textContaining('yours to spend'), findsNothing);
      expect(find.textContaining('a day for the'), findsNothing);
    });

    testWidgets('the card offers nothing to set, only how it was worked out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SafeToSpendCard(
                today: DateTime(2026, 3, 22, 10),
                wallets: Stream.value([cash]),
                transactions: Stream.value(const []),
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

      // Safe to Spend is worked out from the user's own records, so there
      // is nothing to type over it or hold money back with: the one thing
      // on the card explains, it does not set.
      expect(find.byTooltip('More'), findsNothing);
      expect(find.text('Set my daily limit'), findsNothing);
      expect(find.text('Money I keep for savings'), findsNothing);

      await tester.tap(find.byKey(const Key('safe-to-spend-info')));
      await tester.pumpAndSettle();
      expect(find.text('Money in your wallets'), findsOneWidget);
      // Nothing is taken off this account, so no total line repeats the
      // figure above it; it says so in words instead.
      expect(find.text('Left until your next pay'), findsNothing);
      expect(
        find.textContaining('all of it is yours to spend'),
        findsOneWidget,
      );
      expect(find.textContaining('a day for the'), findsOneWidget);
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
              onReorder: onReorder,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('each goal card shows its plan once it is set up', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpGoals(tester, [
        Goal(
          id: 'trip',
          name: 'Trip',
          targetAmount: 5000,
          savedAmount: 1000,
          priority: 0,
          status: GoalStatus.active,
          targetDate: DateTime(now.year + 1, now.month, now.day),
        ),
        goal('someday', 1),
      ]);

      // With a date: how much a month, from what is still to save.
      expect(find.textContaining('a month to reach it by'), findsOneWidget);
      // Without one: asked for, never guessed.
      expect(
        find.text('Add a finish date to see how much to save each month.'),
        findsOneWidget,
      );
    });

    testWidgets('invites a first goal', (tester) async {
      await pumpGoals(tester, const []);

      expect(find.text('No goals yet'), findsOneWidget);
      expect(find.text('Add Goal'), findsOneWidget);
    });

    testWidgets('ranks active goals and shows their progress', (tester) async {
      await pumpGoals(tester, [goal('Laptop', 0), goal('Phone', 1)]);

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text(' of ₱5,000 saved'), findsNWidgets(2));
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
      // Each list shows how many it holds, in a badge of its own.
      expect(
        find.descendant(
          of: find.byKey(const Key('goals-filter-completed')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('goals-filter-completed')));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const Key('goals-filter-completed'))),
        isSemantics(isButton: true, isSelected: true),
      );

      expect(find.text('Trip'), findsOneWidget);
      // Green and full, with a check in place of the target.
      expect(find.text('Goal reached'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('₱5,000 saved — completed!'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == goalReachedIcon,
        ),
        // On the goal's card, and on the Completed tile.
        findsNWidgets(2),
      );
    });

    test('the bar color and words follow how far along a goal is', () {
      expect(goalPercent(0.249, reached: false), 24);
      expect(goalPercent(0.999, reached: false), 99);
      // Past the target still reads 100.
      expect(goalPercent(1.0, reached: true), 100);
      expect(getProgressLabel(0), 'Getting started');
      expect(getProgressLabel(24), 'Getting started');
      expect(getProgressLabel(25), 'On the way');
      expect(getProgressLabel(74), 'On the way');
      expect(getProgressLabel(75), 'Almost there!');
      expect(getProgressLabel(99), 'Almost there!');
      expect(getProgressLabel(100), 'Goal reached');
      expect(getProgressColor(10, dark: true), const Color(0xFFF59E0B));
      expect(getProgressColor(50, dark: true), const Color(0xFF3B82F6));
      expect(getProgressColor(80, dark: true), const Color(0xFF2DD4BF));
      expect(getProgressColor(100, dark: true), const Color(0xFF22C55E));
      // Never red, in either mode.
      for (final percent in [0, 10, 24]) {
        for (final dark in [true, false]) {
          final color = getProgressColor(percent, dark: dark);
          expect(color.r > color.g && color.g < 0.2, isFalse);
        }
      }
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
    // Goal money is held in the Savings wallet, so the sheet needs one.
    final savings = Wallet(
      id: 'savings',
      name: 'Savings',
      type: WalletType.other,
      balance: 5000,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
      purpose: WalletPurpose.savings,
    );
    const laptop = Goal(
      id: 'g',
      name: 'Laptop',
      targetAmount: 5000,
      savedAmount: 1200,
      priority: 0,
      status: GoalStatus.active,
      savedByWallet: {'savings': 1200},
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
              wallets: Stream.value([cash, savings]),
              goals: Stream.value(const [laptop]),
              onSave: onSave,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('saving shows what the goal still needs, like setup', (
      tester,
    ) async {
      double? saved;
      String? into;
      await pumpSheet(
        tester,
        takeOut: false,
        onSave: (a, w) {
          saved = a;
          into = w;
        },
      );

      expect(
        find.text('₱1,200 of ₱5,000 saved · ₱3,800 to go'),
        findsOneWidget,
      );
      // The same choice as when a goal is made.
      expect(find.text('Where is this money now?'), findsOneWidget);
      await tester.tap(find.text('Set Aside'));
      await tester.pump();
      expect(
        find.text('Choose where the money is and enter an amount.'),
        findsOneWidget,
      );
      expect(saved, isNull);

      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('goal-funding-savings')),
        '3800',
      );
      await tester.pump();
      expect(find.text('Still to save'), findsOneWidget);
      await tester.tap(find.text('Set Aside'));
      await tester.pumpAndSettle();

      expect(saved, 3800);
      expect(into, 'savings');
    });

    testWidgets('contributions do not promise more than the goal needs', (
      tester,
    ) async {
      final saved = <String, double>{};
      await pumpSheet(tester, takeOut: false, onSave: (a, w) => saved[w] = a);

      // Cash and a bank together, more than the goal needs.
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('goal-funding-cash')),
        '2000',
      );
      await tester.enterText(
        find.byKey(const Key('goal-funding-savings')),
        '2000',
      );
      await tester.pump();
      await tester.tap(find.text('Set Aside'));
      await tester.pumpAndSettle();

      expect(saved, isEmpty);
      expect(
        find.text('Together that is more than the goal needs (₱3,800).'),
        findsOneWidget,
      );

      // Within what it needs, it is saved from both, one each.
      await tester.enterText(
        find.byKey(const Key('goal-funding-savings')),
        '1800',
      );
      await tester.pump();
      await tester.tap(find.text('Set Aside'));
      await tester.pumpAndSettle();
      expect(saved, {'cash': 2000, 'savings': 1800});
    });

    testWidgets('money goes into the savings record the user picks', (
      tester,
    ) async {
      String? intoWallet;

      final cashSavings = Wallet(
        id: 'cash-savings',
        name: 'Cash at home',
        type: WalletType.other,
        balance: 3000,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 2,
        purpose: WalletPurpose.savings,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ContributionSheet(
                goal: laptop,
                wallets: Stream.value([cash, savings, cashSavings]),
                goals: Stream.value(const [laptop]),
                onSave: (_, walletId) => intoWallet = walletId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Both records are offered, not just the first one.
      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add account'));
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('goal-funding-cash-savings')),
        '500',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Set Aside'));
      await tester.tap(find.text('Set Aside'));
      await tester.pumpAndSettle();

      expect(
        intoWallet,
        'cash-savings',
        reason: 'it used to always land on the first savings record',
      );
    });

    testWidgets('cannot take out more than is set aside', (tester) async {
      double? saved;
      await pumpSheet(tester, takeOut: true, onSave: (a, _) => saved = a);

      // Only where the goal's money is: its savings record.
      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      final amount = find.byKey(const Key('goal-funding-savings'));
      await tester.enterText(amount, '2000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Take It Out'));
      await tester.tap(find.text('Take It Out'));
      await tester.pump();

      // Named per record, because the goal's money may sit in several.
      expect(
        find.text('Only ₱1,200 of this goal is in Savings.'),
        findsWidgets,
      );
      expect(saved, isNull);

      await tester.enterText(amount, '500');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take It Out'));
      await tester.pumpAndSettle();

      expect(saved, -500);
    });

    testWidgets('income can go toward a goal in the waterfall', (tester) async {
      AllocationPlan? confirmed;
      Map<String, double>? keptIn;

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
                  required Map<String, double> incomeByWallet,
                  required Map<String, double> billsPaidFrom,
                  required Map<String, double> billFees,
                  required Map<String, double> goalKeptIn,
                  required String source,
                  required DateTime receivedAt,
                }) {
                  confirmed = plan;
                  keptIn = goalKeptIn;
                },
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
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Save some toward a goal?'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      // "Use what is left" is capped at what the goal still needs.
      expect(find.text('₱3,800, all this goal needs'), findsOneWidget);

      // It stays in the cash the income went into, marked for the goal.
      expect(find.text('Which wallets keep it?'), findsOneWidget);
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(confirmed?.goal?.id, 'g');
      expect(confirmed?.toGoal, 3800);
      expect(confirmed?.remaining, 6200);
      expect(keptIn, {'cash': 3800});
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

    Debt loan({
      double principal = 5600,
      double perPayment = 560,
      int count = 12,
      int paidBefore = 0,
      double? quotedRate,
      RatePeriod per = RatePeriod.month,
      DebtCategory category = DebtCategory.personalLoan,
    }) => Debt(
      id: 'l',
      direction: DebtDirection.iOwe,
      name: 'Loan',
      category: category,
      principal: principal,
      perPayment: perPayment,
      paymentCount: count,
      firstDueDate: DateTime(2026, 1, 5),
      billId: 'b',
      status: DebtStatus.active,
      paidBefore: paidBefore,
      quotedRate: quotedRate,
      quotedRatePer: per,
    );

    test('the cost is shown as a share and as a true yearly rate', () {
      // The CPA's check: ₱5,600 x 20% is ₱1,120 on top.
      final debt = loan();
      expect(debt.extraCost, closeTo(1120, 0.01));
      expect(debt.extraCostPercent, closeTo(20, 0.01));
      // Paid down monthly, 20% over a year really costs about 35% a year.
      expect(debt.yearlyCostPercent, closeTo(35.1, 0.2));
      expect(debt.monthlyCostPercent, closeTo(2.92, 0.02));
      expect(
        costRateText(debt),
        'That works out to about 2.9% a month, or 35% a year.',
      );
      // A 1% a month add-on, as card cash loans quote, is about 21% a year.
      expect(
        loan(principal: 12000, perPayment: 1120).yearlyCostPercent,
        closeTo(21.5, 0.2),
      );
      // Nothing on top, no rate to show.
      expect(loan(perPayment: 5600 / 12).yearlyCostPercent, isNull);
      expect(roundedPercent(20), '20%');
      expect(roundedPercent(2.92), '2.9%');
    });

    test('payments costing more than the rate quoted are caught', () {
      // 20% over 12 months is 1.67% a month as an add-on rate.
      expect(loan(quotedRate: 2).costsMoreThanQuoted, isFalse);
      expect(
        loan(quotedRate: 20, per: RatePeriod.year).costsMoreThanQuoted,
        isFalse,
      );
      // Told 1% a month: only ₱672 would be added, not ₱1,120.
      expect(loan(quotedRate: 1).costsMoreThanQuoted, isTrue);
      // A "0% installment" with ₱1,120 on top has fees somewhere.
      expect(loan(quotedRate: 0).costsMoreThanQuoted, isTrue);
      expect(loan().costsMoreThanQuoted, isFalse, reason: 'nothing quoted');
    });

    test('payments made before tracking count as paid', () {
      final debt = loan(perPayment: 2000, principal: 20000, paidBefore: 3);
      final progress = DebtProgress.of(debt, const []);
      expect(progress.paid, 6000);
      expect(progress.paymentsMade, 3);
      expect(progress.paymentsLeft, 9);
      expect(debt.dueDateOf(4), DateTime(2026, 4, 5));

      // Its bill starts at the fourth payment, on the same dates as before.
      final bill = Bill(
        id: 'b',
        name: 'Loan',
        amount: 2000,
        category: 'Bills',
        firstDueDate: DateTime(2026, 1, 31),
        recurrence: BillRecurrence.monthly,
        endDate: DateTime(2026, 12, 31),
        startDate: DateTime(2026, 4, 30),
      );
      expect(bill.occurrencesIn(2026, 3), isEmpty);
      expect(bill.occurrencesIn(2026, 4), [DateTime(2026, 4, 30)]);
      expect(bill.occurrencesIn(2026, 5), [DateTime(2026, 5, 31)]);
    });

    testWidgets('the details disclose the cost and compare it with savings', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> open(Debt debt) async {
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => AppSettingsProvider(),
            child: MaterialApp(
              key: UniqueKey(),
              theme: AppTheme.light,
              home: DebtDetailScreen(
                debt: debt,
                liveDebt: Stream.value(debt),
                payments: Stream.value(const []),
                wallets: Stream.value([
                  Wallet(
                    id: 'bank',
                    name: 'GoTyme Bank',
                    type: WalletType.bank,
                    balance: 5000,
                    startingBalance: 5000,
                    receivesIncome: false,
                    archived: false,
                    annualInterestRatePercent: 4,
                    sortOrder: 0,
                  ),
                ]),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      await open(loan(quotedRate: 1, paidBefore: 2));
      expect(find.text('What borrowing costs'), findsOneWidget);
      expect(
        find.text('₱1,120 more than you borrowed, 20% of ₱5,600.'),
        findsOneWidget,
      );
      expect(find.textContaining('or 35% a year'), findsOneWidget);
      // A loan says how its interest is charged.
      expect(
        find.text(
          'Interest they told you: 1% a month, the same every payment.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('cost more than 1% a month'), findsOneWidget);
      // 4% a year, less the 20% tax banks keep.
      expect(
        find.textContaining('Your savings earn up to 3.2% a year after tax.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('must tell you the full cost'),
        findsOneWidget,
      );
      // Two paid before tracking: counted, and marked on the statement.
      expect(find.text('2 payments'), findsOneWidget);
      expect(find.text('Paid before FinAssist'), findsNWidgets(3));

      // Between family and friends, the note is about agreeing in writing.
      await open(loan(category: DebtCategory.familyFriend));
      expect(find.textContaining('agreed to it in writing'), findsOneWidget);
      expect(find.textContaining('must tell you the full cost'), findsNothing);
    });

    testWidgets('the statement counts down what is left after each payment', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      BillInstance due(
        String id,
        DateTime date, {
        double paid = 0,
        BillStatus status = BillStatus.unpaid,
      }) => BillInstance(
        id: id,
        billId: 'b',
        name: 'Phone',
        amount: 2400,
        category: 'Bills',
        dueDate: date,
        status: status,
        amountPaid: paid,
      );

      final plan = phone(count: 3);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: DebtDetailScreen(
              debt: plan,
              liveDebt: Stream.value(plan),
              payments: Stream.value([
                due(
                  '1',
                  DateTime(2026, 1, 31),
                  paid: 2400,
                  status: BillStatus.paid,
                ),
                due(
                  '2',
                  DateTime(2026, 2, 28),
                  paid: 1000,
                  status: BillStatus.partial,
                ),
                due('3', DateTime(2026, 3, 31)),
              ]),
              wallets: Stream.value(const []),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Statement of account'), findsOneWidget);

      // Every payment is numbered, so a row can be matched to the contract.
      expect(find.textContaining('Payment 1 of 3'), findsOneWidget);
      expect(find.textContaining('Payment 3 of 3'), findsOneWidget);

      // A settled payment, a part-paid one, and one not yet due each read
      // differently.
      expect(find.text('₱2,400 paid in full'), findsOneWidget);
      expect(
        find.text('₱1,000 of ₱2,400 paid · ₱1,400 still due'),
        findsOneWidget,
      );
      expect(find.text('₱2,400 due'), findsOneWidget);

      // ₱7,200 payable, counted down by what was actually paid on each row:
      // 7,200 - 2,400 = 4,800, then - 1,000 = 3,800, then nothing paid.
      expect(find.text('₱4,800 left'), findsOneWidget);
      expect(find.text('₱3,800 left'), findsNWidgets(2));

      // The card at the top already carries the totals, so the statement
      // does not repeat them.
      expect(find.textContaining('of ₱7,200 paid'), findsOneWidget);
    });

    testWidgets('the statement lists the whole plan, not just the bills made', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final plan = phone(count: 12, perPayment: 2000);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: DebtDetailScreen(
              debt: plan,
              liveDebt: Stream.value(plan),
              // Only the first month has been opened in the Bill Planner,
              // which is how a freshly made plan starts out.
              payments: Stream.value([
                BillInstance(
                  id: '1',
                  billId: 'b',
                  name: 'Phone',
                  amount: 2000,
                  category: 'Bills',
                  dueDate: DateTime(2026, 1, 31),
                  status: BillStatus.unpaid,
                  amountPaid: 0,
                ),
              ]),
              wallets: Stream.value(const []),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // All twelve, not the one bill that happens to exist.
      expect(find.textContaining('Payment 1 of 12'), findsOneWidget);
      expect(find.textContaining('Payment 12 of 12'), findsOneWidget);

      // The dates come from the plan itself, keeping the 31st where the
      // month allows it. Matched on the whole row, because the card above
      // names the last payment's date too.
      expect(find.text('Payment 2 of 12 · Feb 28, 2026'), findsOneWidget);
      expect(find.text('Payment 12 of 12 · Dec 31, 2026'), findsOneWidget);

      // Payments with no bill yet are marked as still to come.
      expect(find.text('To come'), findsNWidgets(11));
    });

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
    });
  });

  group('Debts', () {
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

    testWidgets('an installment plan never moves money by itself', (
      tester,
    ) async {
      tall(tester);
      DebtDraft? saved;

      await tester.pumpWidget(
        app(
          Scaffold(
            body: DebtFormSheet(
              today: DateTime(2026, 3, 10),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      // A plan is a plan. Nothing offers to put the borrowed amount into a
      // wallet, and the form says so.
      expect(find.text('I received this money in a wallet'), findsNothing);
      expect(find.text('Received into'), findsNothing);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Phone');
      await tester.enterText(fields.at(1), '24000');
      await tester.enterText(fields.at(2), '2400');
      await tester.pump();
      expect(
        find.textContaining('Your money does not move until you pay'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();

      expect(saved?.name, 'Phone');
      expect(
        saved?.movedWalletId,
        isNull,
        reason: 'nothing arrives in a wallet from setting up a plan',
      );
    });

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

      expect(
        find.text('10 payments of ₱2,400, every month'),
        findsOneWidget,
        reason: 'payments, worked out',
      );
      expect(find.textContaining('You will pay ₱24,000'), findsOne);

      await tester.enterText(fields.at(3), '12');
      await tester.pump();
      expect(
        find.textContaining('₱4,800 more than you borrowed (20%)'),
        findsOneWidget,
      );
      // And what that really costs as a rate, as lenders must disclose.
      expect(find.textContaining('a month, or 35% a year'), findsOneWidget);

      // Only whole payments: no point, no sign, no fourth digit.
      await tester.enterText(fields.at(3), '-1.2');
      expect(tester.widget<TextField>(fields.at(3)).controller?.text, '12');
      await tester.enterText(fields.at(3), '1200');
      expect(tester.widget<TextField>(fields.at(3)).controller?.text, '120');
      await tester.enterText(fields.at(3), '12');
      await tester.pump();

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
                onSave: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        // Only what every plan has: the rest waits under More options.
        expect(find.text('Interest (optional)'), findsNothing);
        // The rare and the optional start folded away, so the first look at
        // the form is the plan itself and nothing else.
        expect(find.text('Last payment (optional)'), findsNothing);
        expect(find.text('Notes (optional)'), findsNothing);
        expect(find.text('More options (optional)'), findsOneWidget);
        // Grey examples inside the empty fields.
        // Things bought on installment: loans have their own form.
        expect(find.text('e.g. Phone, Aircon'), findsOneWidget);
        expect(find.text('e.g. 12,000'), findsOneWidget);
        expect(find.text('e.g. 1,500'), findsOneWidget);
        expect(find.text('e.g. 12'), findsOneWidget);
        expect(
          find.text('Shows how much more you pay than paying in full.'),
          findsOneWidget,
        );
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
      expect(
        find.text('4 payments of ₱3,000, every month'),
        findsOneWidget,
        reason: 'payments, worked out',
      );
      expect(find.textContaining('You will pay ₱10,000'), findsOne);
      expect(find.textContaining('more than you borrowed'), findsNothing);
      expect(find.textContaining('Last payment ₱1,000 on'), findsOneWidget);

      // A count from the contract keeps every payment the same.
      await tester.enterText(fields.at(3), '4');
      await tester.pump();
      expect(find.textContaining('You will pay ₱12,000'), findsOne);
      expect(find.textContaining('₱2,000 more than you borrowed'), findsOne);

      // Unless the contract's last payment is typed in, which is rare
      // enough to live under More options.
      await tester.tap(find.text('More options (optional)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('installment-last-payment')),
        '1000',
      );
      await tester.pump();
      expect(find.textContaining('You will pay ₱10,000'), findsOne);

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

    testWidgets('lending records made before it was dropped are not listed', (
      tester,
    ) async {
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
      expect(find.text('Owed to me'), findsNothing);
      expect(find.text('No installments yet'), findsOneWidget);
      expect(find.text('Add Installment'), findsOneWidget);
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

    test('a custom rhythm counts its own saving days', () {
      const everyTenDays = SavingInterval(10, SavingUnit.days);
      // Every 10 days from Mar 10: Mar 20 to May 29, eight before Jun 2.
      expect(
        savingDaysLeft(
          targetDate: DateTime(2026, 6, 2),
          frequency: ContributionFrequency.custom,
          now: now,
          custom: everyTenDays,
        ),
        8,
      );
      expect(
        neededPerContribution(
          remaining: 12000,
          targetDate: DateTime(2026, 6, 2),
          frequency: ContributionFrequency.custom,
          now: now,
          custom: everyTenDays,
        ),
        1500,
      );
      // Months keep the day of the month, weeks keep the weekday.
      expect(
        planDates(
          now,
          ContributionFrequency.custom,
          from: now,
          until: DateTime(2026, 9, 30),
          custom: const SavingInterval(2, SavingUnit.months),
        ),
        [DateTime(2026, 5, 10), DateTime(2026, 7, 10), DateTime(2026, 9, 10)],
      );
      expect(
        planDates(
          now,
          ContributionFrequency.custom,
          from: now,
          until: DateTime(2026, 4, 7),
          custom: const SavingInterval(2, SavingUnit.weeks),
        ),
        [DateTime(2026, 3, 24), DateTime(2026, 4, 7)],
      );
      // Custom with no rhythm saved falls back to monthly.
      expect(
        planDates(
          now,
          ContributionFrequency.custom,
          from: now,
          until: DateTime(2026, 6, 30),
        ),
        planDates(
          now,
          ContributionFrequency.monthly,
          from: now,
          until: DateTime(2026, 6, 30),
        ),
      );
    });

    test('a custom rhythm reads plainly and is saved with the goal', () {
      expect(const SavingInterval(1, SavingUnit.weeks).per, 'a week');
      expect(const SavingInterval(10, SavingUnit.days).per, 'every 10 days');
      expect(
        const SavingInterval(2, SavingUnit.months).label,
        'Every 2 months',
      );
      expect(const SavingInterval(0, SavingUnit.days).isValid, isFalse);
      expect(const SavingInterval(13, SavingUnit.months).isValid, isFalse);
      expect(const SavingInterval(365, SavingUnit.days).isValid, isTrue);

      final goal = Goal.fromMap('trip', {
        'name': 'Trip',
        'targetAmount': 12000,
        'frequency': 'custom',
        'frequencyEvery': 2,
        'frequencyUnit': 'weeks',
      });
      expect(goal.frequency, ContributionFrequency.custom);
      expect(goal.customInterval, const SavingInterval(2, SavingUnit.weeks));
      expect(goal.savingPer, 'every 2 weeks');
      // A broken rhythm is dropped rather than trusted.
      expect(SavingInterval.fromFields(0, 'weeks'), isNull);
      expect(SavingInterval.fromFields(null, 'weeks'), isNull);
    });

    test('with one saving day left it asks for it all by the date', () {
      // Six days away on a monthly plan: no saving day fits before then.
      final days = savingDaysLeft(
        targetDate: DateTime(2026, 3, 16),
        frequency: ContributionFrequency.monthly,
        now: now,
      );
      expect(days, 0);
      expect(
        neededText(
          needed: 6500,
          targetDate: DateTime(2026, 3, 16),
          savingDays: days,
          per: 'a month',
        ),
        'Save ₱6,500 by Mar 16, 2026 to reach it.',
      );
      expect(
        neededText(
          needed: 2500,
          targetDate: DateTime(2027, 3, 10),
          savingDays: 12,
          per: 'a month',
        ),
        'Save ₱2,500 a month to reach it by Mar 10, 2027.',
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

    // Goal money is kept in the Savings wallet, so money already saved has
    // to be there before a goal can claim it.
    final savings = Wallet(
      id: 'savings',
      name: 'Savings',
      type: WalletType.other,
      balance: 5000,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
      purpose: WalletPurpose.savings,
    );

    testWidgets('already saved is capped by what the record still has free', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      GoalDraft? saved;

      // ₱5,000 in the record, ₱4,000 of it already promised to another
      // goal, so only ₱1,000 is left to promise to this one.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: GoalFormSheet(
              today: DateTime(2026, 3, 10),
              wallets: Stream.value([cash, savings]),
              goals: Stream.value(const [
                Goal(
                  id: 'other',
                  name: 'Tuition',
                  targetAmount: 20000,
                  savedAmount: 4000,
                  priority: 0,
                  status: GoalStatus.active,
                  savedByWallet: {'savings': 4000},
                ),
              ]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'New phone');
      await tester.enterText(find.byType(TextField).at(1), '10000');
      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('goal-funding-savings')),
        '2500',
      );
      await tester.tap(find.text('Save Goal'));
      await tester.pump();

      // The old check read the whole ₱5,000 balance and would have let this
      // through, promising pesos another goal already holds.
      expect(saved, isNull);
      expect(find.textContaining('₱1,000 left to promise'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('goal-funding-savings')),
        '1000',
      );
      await tester.tap(find.text('Save Goal'));
      await tester.pump();

      expect(saved?.alreadySaved, 1000);
      expect(saved?.walletId, 'savings');
    });

    testWidgets('a goal is planned by its date, never asked how often', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      GoalDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: GoalFormSheet(
              today: DateTime(2026, 3, 10),
              initialDate: DateTime(2026, 6, 2),
              wallets: Stream.value(const []),
              goals: Stream.value(const []),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Trip');
      await tester.enterText(find.byType(TextField).at(1), '12000');
      await tester.pump();

      // Only the name, the amount and the date: no rhythm and no amount each
      // time to fill in, and the plan waits for the goal's card.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('How often will you save?'), findsNothing);
      expect(find.byKey(const Key('goal-frequency-custom')), findsNothing);
      expect(find.text('How much each time? (optional)'), findsNothing);
      expect(find.textContaining('to reach it by'), findsNothing);

      await tester.ensureVisible(find.text('Save Goal'));
      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();
      expect(saved?.targetDate, DateTime(2026, 6, 2));
      expect(saved?.frequency, ContributionFrequency.monthly);
      expect(saved?.customInterval, isNull);
      expect(saved?.planAmount, isNull);
    });

    test('the card plans by the calendar, from what is left to save', () {
      final now = DateTime(2026, 10, 25);
      // ₱10,000 with ₱3,500 set aside: ₱6,500 over the seven monthly saving
      // days to May 31, 2027.
      final line = goalPlanLine(
        remaining: 6500,
        targetDate: DateTime(2027, 5, 31),
        now: now,
      );
      expect(line?.text, 'Save ₱928.57 a month to reach it by May 31, 2027.');
      expect(line?.tone, GoalPlanTone.plan);

      // Less than a month away: all of it by the date.
      expect(
        goalPlanLine(
          remaining: 6500,
          targetDate: DateTime(2026, 11, 10),
          now: now,
        )?.text,
        'Save ₱6,500 by Nov 10, 2026 to reach it.',
      );
      // No date: asked for, not guessed.
      expect(
        goalPlanLine(remaining: 6500, targetDate: null, now: now)?.text,
        'Add a finish date to see how much to save each month.',
      );
      // A date gone by: a new one is needed, never a sum for the past.
      final passed = goalPlanLine(
        remaining: 6500,
        targetDate: DateTime(2026, 10, 1),
        now: now,
      );
      expect(passed?.text, 'The finish date has passed. Pick a new one.');
      expect(passed?.tone, GoalPlanTone.datePassed);
      // Reached: the progress bar says so, and nothing more is asked.
      expect(
        goalPlanLine(remaining: 0, targetDate: DateTime(2027, 5, 31), now: now),
        isNull,
      );
      // A goal saved with its own amount each time keeps it.
      expect(
        goalPlanLine(
          remaining: 6500,
          targetDate: null,
          now: now,
          planAmount: 1000,
          behind: 500,
        )?.text,
        'Plan: ₱1,000 a month · behind by ₱500',
      );
    });

    testWidgets('a bank account can fund a goal without a balance transfer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bank = Wallet(
        id: 'bpi',
        name: 'BPI',
        type: WalletType.bank,
        balance: 2500,
        startingBalance: 2500,
        receivesIncome: false,
        archived: false,
        sortOrder: 1,
        annualInterestRatePercent: 0,
      );
      GoalDraft? saved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: GoalFormSheet(
              wallets: Stream.value([cash, bank]),
              goals: Stream.value(const []),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      expect(find.text('Bank · ₱2,500 available'), findsOneWidget);
      expect(find.text('0% interest a year'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'School supplies');
      await tester.enterText(fields.at(1), '5000');
      await tester.enterText(find.byKey(const Key('goal-funding-bpi')), '400');
      await tester.ensureVisible(find.text('Save Goal'));
      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();

      expect(saved?.walletId, 'bpi');
      expect(saved?.fundingSource, GoalFundingSource.bank);
      expect(saved?.alreadySaved, 400);
      expect(saved?.savedByWallet, {'bpi': 400});
      expect(bank.balance, 2500);
    });

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
              wallets: Stream.value([cash, savings]),
              goals: Stream.value(const []),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Emergency Fund'), findsWidgets);

      // Name and amount needed; an amount box for money already saved shows
      // once a place is picked.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Where is this money now?'), findsOneWidget);
      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goal-funding-savings')), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), '12000');
      await tester.enterText(
        find.byKey(const Key('goal-funding-savings')),
        '2000',
      );
      await tester.pump();

      // The plan is shown on the goal's card once it is set up, not here.
      expect(find.textContaining('a month'), findsNothing);

      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();

      expect(saved?.targetAmount, 12000);
      expect(saved?.alreadySaved, 2000);
      expect(saved?.planAmount, isNull);
      expect(saved?.kind, GoalKind.emergencyFund);
      expect(saved?.walletId, 'savings');
      expect(saved?.fundingSource, GoalFundingSource.savings);
    });

    testWidgets('the form asks only what the plan needs, in plain words', (
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
              today: DateTime(2026, 3, 10),
              initialDate: DateTime(2026, 9, 10),
              wallets: Stream.value([cash]),
              goals: Stream.value(const []),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Goal name'), findsOneWidget);
      expect(find.text('Amount needed'), findsOneWidget);
      expect(find.text('Finish by (optional)'), findsOneWidget);
      expect(find.text('How often will you save?'), findsNothing);
      expect(find.text('Already saved some? (optional)'), findsOneWidget);
      // Gone: the preview card, the fold, the goal type and notes.
      expect(find.text('Need a month'), findsNothing);
      expect(find.text('More options (optional)'), findsNothing);
      expect(find.text('Goal type'), findsNothing);
      expect(find.text('Notes'), findsNothing);
      // No counter until the name nears its limit.
      expect(find.text('0/40'), findsNothing);
      // The amount is typed in the same size as every other field.
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).style,
        isNull,
      );

      // Neither with a finish date nor without is an amount each time asked:
      // the date plans it, on the goal's card.
      expect(find.byKey(const Key('goal-plan-amount')), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Emergency fund');
      await tester.enterText(find.byType(TextField).at(1), '6000');
      await tester.pump();
      expect(find.textContaining('a month to reach it by'), findsNothing);

      await tester.tap(find.byTooltip('Remove date'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goal-plan-amount')), findsNothing);
      expect(find.text('How much each time? (optional)'), findsNothing);

      await tester.enterText(
        find.byType(TextField).first,
        'Emergency fund for the family',
      );
      await tester.pump();
      expect(find.text('29/40'), findsNothing);
      await tester.enterText(
        find.byType(TextField).first,
        'Emergency fund for the whole family',
      );
      await tester.pump();
      expect(find.text('35/40'), findsOneWidget);

      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();
      expect(saved?.kind, GoalKind.emergencyFund);
      expect(saved?.note, isNull);
    });

    testWidgets('a new goal is planned month by month', (tester) async {
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
              today: DateTime(2026, 3, 10),
              wallets: Stream.value([cash]),
              goals: Stream.value(const []),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Pick when you usually get money.'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Phone');
      await tester.enterText(find.byType(TextField).at(1), '9000');
      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();
      expect(saved?.frequency, ContributionFrequency.monthly);
    });

    testWidgets('editing keeps a saved note and a saved plan amount', (
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
              existing: Goal(
                id: 'laptop',
                name: 'Laptop',
                targetAmount: 30000,
                savedAmount: 0,
                priority: 0,
                status: GoalStatus.active,
                targetDate: DateTime(2026, 12, 1),
                planAmount: 2000,
                note: 'for school',
              ),
              today: DateTime(2026, 3, 10),
              wallets: Stream.value([cash]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      // Saved with both a date and an amount before: the amount is kept,
      // though no longer asked.
      expect(find.byKey(const Key('goal-plan-amount')), findsNothing);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(saved?.planAmount, 2000);
      expect(saved?.frequency, ContributionFrequency.monthly);
      expect(saved?.note, 'for school');
      expect(saved?.kind, GoalKind.regular);
    });

    final bpi = Wallet(
      id: 'bpi',
      name: 'BPI',
      type: WalletType.bank,
      balance: 8000,
      startingBalance: 8000,
      receivesIncome: false,
      archived: false,
      sortOrder: 1,
      annualInterestRatePercent: 3,
    );
    final gcash = Wallet(
      id: 'gcash',
      name: 'GCash',
      type: WalletType.gcash,
      balance: 3000,
      startingBalance: 3000,
      receivesIncome: false,
      archived: false,
      sortOrder: 2,
    );

    Future<void> pumpFundingForm(
      WidgetTester tester, {
      required void Function(GoalDraft draft) onSave,
      List<Wallet>? wallets,
      List<Goal> goals = const [],
    }) async {
      tester.view.physicalSize = const Size(700, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: GoalFormSheet(
              today: DateTime(2026, 3, 10),
              wallets: Stream.value(wallets ?? [cash, bpi, gcash]),
              goals: Stream.value(goals),
              onSave: onSave,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Laptop');
      await tester.enterText(find.byType(TextField).at(1), '10000');
    }

    Future<void> choose(WidgetTester tester, String option) async {
      await tester.tap(find.text(option).first);
      await tester.pumpAndSettle();
    }

    Future<void> enterFunding(
      WidgetTester tester,
      String walletId,
      String amount,
    ) async {
      await tester.enterText(find.byKey(Key('goal-funding-$walletId')), amount);
      await tester.pump();
    }

    testWidgets('Cash on Hand shows cash; Cash in Bank adds accounts', (
      tester,
    ) async {
      await pumpFundingForm(tester, onSave: (_) {});

      Finder tileImages(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        matching: find.byType(Image),
      );
      expect(tileImages('Cash on Hand'), findsOneWidget);
      expect(tileImages('Cash in Bank'), findsOneWidget);
      expect(tileImages('Both'), findsNWidgets(2));

      expect(find.byKey(const Key('goal-funding-cash')), findsNothing);
      await choose(tester, 'Cash on Hand');
      expect(find.byKey(const Key('goal-funding-cash')), findsOneWidget);
      expect(find.byKey(const Key('goal-funding-bpi')), findsNothing);
      expect(find.text('Cash earns no interest.'), findsOneWidget);

      // The first account is ready to fill in; the rest are added.
      await choose(tester, 'Cash in Bank');
      expect(find.byKey(const Key('goal-funding-cash')), findsNothing);
      expect(find.byKey(const Key('goal-funding-bpi')), findsOneWidget);
      expect(find.byKey(const Key('goal-funding-gcash')), findsNothing);
      expect(find.text('Bank · ₱8,000 available'), findsOneWidget);
      expect(find.text('3% interest a year'), findsOneWidget);

      await choose(tester, 'Add account');
      expect(find.byKey(const Key('goal-funding-gcash')), findsOneWidget);
      expect(find.text('GCash · ₱3,000 available'), findsOneWidget);
      expect(find.text('No yearly interest rate recorded.'), findsOneWidget);
      // Every account is in, so there is nothing left to add.
      expect(find.text('Add account'), findsNothing);
    });

    testWidgets('Both splits one goal across cash and several accounts', (
      tester,
    ) async {
      GoalDraft? saved;
      await pumpFundingForm(tester, onSave: (draft) => saved = draft);

      await choose(tester, 'Both');
      // Each section is named under the choice, so both read at a glance.
      expect(find.text('Cash on Hand'), findsNWidgets(2));
      expect(find.text('Cash in Bank'), findsNWidgets(2));

      await enterFunding(tester, 'cash', '2000');
      await enterFunding(tester, 'bpi', '5000');
      await choose(tester, 'Add account');
      await enterFunding(tester, 'gcash', '3000');

      expect(find.text('Total set aside'), findsOneWidget);
      expect(find.text('₱10,000'), findsWidgets);
      expect(find.text('Still to save'), findsOneWidget);
      expect(find.text('₱0'), findsOneWidget);
      // Only BPI has a rate: ₱5,000 × 3% = ₱150. Cash earns nothing and
      // GCash has no rate, so neither adds to the guess.
      // ₱5,000 × 3% = ₱150, less the 20% tax banks keep.
      expect(find.text('about ₱120'), findsOneWidget);
      expect(find.textContaining('No rate recorded for GCash'), findsOneWidget);
      expect(
        find.text(
          '3% interest a year · ₱5,000 may earn about ₱120 a year after tax',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();

      expect(saved?.savedByWallet, {'cash': 2000, 'bpi': 5000, 'gcash': 3000});
      // The interest is never counted as money saved.
      expect(saved?.alreadySaved, 10000);
      expect(saved?.fundingSource, GoalFundingSource.both);
      // Later contributions start on the account holding the most.
      expect(saved?.walletId, 'bpi');
      expect(cash.balance, 5000);
      expect(bpi.balance, 8000);
    });

    testWidgets('switching choices keeps typed amounts but saves what shows', (
      tester,
    ) async {
      GoalDraft? saved;
      await pumpFundingForm(tester, onSave: (draft) => saved = draft);

      await choose(tester, 'Cash on Hand');
      await enterFunding(tester, 'cash', '1000');
      await choose(tester, 'Cash in Bank');
      await enterFunding(tester, 'bpi', '500');

      // The cash amount is hidden, not lost.
      await choose(tester, 'Both');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('goal-funding-cash')))
            .controller
            ?.text,
        '1,000',
      );

      await choose(tester, 'Cash in Bank');
      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();

      expect(saved?.savedByWallet, {'bpi': 500});
      expect(saved?.alreadySaved, 500);
      expect(saved?.fundingSource, GoalFundingSource.bank);
    });

    testWidgets('each account is checked against its own free money', (
      tester,
    ) async {
      GoalDraft? saved;
      // Another goal already holds ₱6,000 of BPI's ₱8,000.
      await pumpFundingForm(
        tester,
        onSave: (draft) => saved = draft,
        goals: const [
          Goal(
            id: 'tuition',
            name: 'Tuition',
            targetAmount: 20000,
            savedAmount: 6000,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'bpi': 6000},
          ),
        ],
      );

      await choose(tester, 'Both');
      expect(
        find.text('Bank · ₱8,000 balance · ₱2,000 available'),
        findsOneWidget,
      );
      await enterFunding(tester, 'cash', '1000');
      await enterFunding(tester, 'bpi', '2500');
      await tester.tap(find.text('Save Goal'));
      await tester.pump();

      expect(saved, isNull);
      expect(find.text('BPI has ₱2,000 left to promise.'), findsOneWidget);

      // Within each account, but more than the goal needs together.
      await tester.enterText(find.byType(TextField).at(1), '9000');
      await enterFunding(tester, 'cash', '5000');
      await enterFunding(tester, 'bpi', '2000');
      await choose(tester, 'Add account');
      await enterFunding(tester, 'gcash', '3000');
      await tester.tap(find.text('Save Goal'));
      await tester.pump();

      expect(saved, isNull);
      expect(
        find.text('Together that is more than the goal needs (₱9,000).'),
        findsOneWidget,
      );

      await enterFunding(tester, 'gcash', '');
      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();

      expect(saved?.savedByWallet, {'cash': 5000, 'bpi': 2000});
    });

    testWidgets('a goal can draw on several banks and e-wallets', (
      tester,
    ) async {
      final maya = Wallet(
        id: 'maya',
        name: 'Maya',
        type: WalletType.maya,
        balance: 20000,
        startingBalance: 20000,
        receivesIncome: false,
        archived: false,
        sortOrder: 3,
        annualInterestRatePercent: 3.5,
      );
      GoalDraft? saved;
      await pumpFundingForm(
        tester,
        onSave: (draft) => saved = draft,
        wallets: [cash, bpi, maya, gcash],
      );
      await tester.enterText(find.byType(TextField).at(1), '50000');

      await choose(tester, 'Cash in Bank');
      await choose(tester, 'Add account');
      await choose(tester, 'Add account');
      expect(find.text('Add account'), findsNothing);
      await enterFunding(tester, 'bpi', '8000');
      await enterFunding(tester, 'maya', '15000');
      await enterFunding(tester, 'gcash', '2000');

      expect(find.text('₱25,000'), findsNWidgets(2));
      // Each rate counts only for its own account: ₱8,000 × 3% = ₱240 and
      // ₱15,000 × 3.5% = ₱525, ₱765 less 20% tax. GCash has no rate.
      expect(find.text('about ₱612'), findsOneWidget);
      expect(
        find.text(
          '3.5% interest a year · ₱15,000 may earn about ₱420 a year after '
          'tax',
        ),
        findsOneWidget,
      );

      // An account already in another row cannot be picked again.
      final firstRow = find.byType(DropdownButtonFormField<String>).first;
      final mayaItems = tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: firstRow,
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .items!
          .where((item) => item.value == 'maya');
      expect(mayaItems, isNotEmpty);
      expect(mayaItems.every((item) => !item.enabled), isTrue);
      await tester.tap(firstRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maya').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('BPI').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goal-funding-bpi')), findsOneWidget);
      expect(find.byKey(const Key('goal-funding-maya')), findsOneWidget);

      // Taking one off updates the totals and frees it to add again.
      await tester.tap(find.byTooltip('Remove Maya'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goal-funding-maya')), findsNothing);
      expect(find.text('₱10,000'), findsOneWidget);
      expect(find.text('₱40,000'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);

      // Switching a row to another account keeps its amount.
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maya').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goal-funding-gcash')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('goal-funding-maya')))
            .controller
            ?.text,
        '2,000',
      );

      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();

      expect(saved?.savedByWallet, {'bpi': 8000, 'maya': 2000});
      expect(saved?.alreadySaved, 10000);
      expect(saved?.fundingSource, GoalFundingSource.bank);
      expect(maya.balance, 20000);
    });

    testWidgets('more than an account has free is flagged while typing', (
      tester,
    ) async {
      // Another goal already holds ₱6,000 of BPI's ₱8,000.
      await pumpFundingForm(
        tester,
        onSave: (_) {},
        goals: const [
          Goal(
            id: 'tuition',
            name: 'Tuition',
            targetAmount: 20000,
            savedAmount: 6000,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'bpi': 6000},
          ),
        ],
      );

      await choose(tester, 'Cash in Bank');
      await tester.enterText(find.byType(TextField).at(1), '2500');
      await enterFunding(tester, 'bpi', '2500');
      // No Save tap needed: the box itself says what is wrong.
      expect(
        find.text(
          'Only ₱2,000 in BPI is free to set aside; other goals hold the rest.',
        ),
        findsOneWidget,
      );
      // Nothing is totalled from an amount that is not there: the total
      // waits, and the plan does not call the goal reached.
      expect(find.text('Total set aside'), findsNothing);
      expect(find.textContaining('Fix the amount in red'), findsOneWidget);
      expect(
        find.text('Already reached with what you have saved.'),
        findsNothing,
      );

      await enterFunding(tester, 'bpi', '2000');
      expect(find.textContaining('free to set aside'), findsNothing);
      expect(find.textContaining('Fix the amount in red'), findsNothing);
      expect(find.text('Total set aside'), findsOneWidget);

      await choose(tester, 'Add account');
      await enterFunding(tester, 'gcash', '5000');
      expect(
        find.text('Only ₱3,000 in GCash is free to set aside.'),
        findsOneWidget,
      );

      // Together more than the goal needs, said in the total as well.
      await tester.enterText(find.byType(TextField).at(1), '4000');
      await enterFunding(tester, 'gcash', '3000');
      expect(
        find.text('That is ₱1,000 more than the goal needs.'),
        findsOneWidget,
      );

      // BPI is already in a row, so GCash's list shows it as added.
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('Added'), findsWidgets);
      await tester.tap(find.text('GCash').last);
      await tester.pumpAndSettle();
    });

    testWidgets('Both is off until there is cash and an account', (
      tester,
    ) async {
      GoalDraft? saved;
      await pumpFundingForm(
        tester,
        onSave: (draft) => saved = draft,
        wallets: [bpi],
      );

      await choose(tester, 'Both');
      expect(find.byKey(const Key('goal-funding-bpi')), findsNothing);
      await choose(tester, 'Cash on Hand');
      expect(find.byKey(const Key('goal-funding-bpi')), findsNothing);

      // Setting money aside stays optional.
      await tester.tap(find.text('Save Goal'));
      await tester.pumpAndSettle();
      expect(saved?.savedByWallet, isEmpty);
      expect(saved?.alreadySaved, 0);
      expect(saved?.fundingSource, isNull);
    });

    testWidgets('a goal lists each account once, then its interest', (
      tester,
    ) async {
      final archived = Wallet(
        id: 'old',
        name: 'Old BDO',
        type: WalletType.bank,
        balance: 1000,
        startingBalance: 1000,
        receivesIncome: false,
        archived: true,
        sortOrder: 4,
        annualInterestRatePercent: 6,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: GoalFundingList(
              sources: [
                (cash, 2000),
                (bpi, 5000),
                (gcash, 3000),
                (archived, 1000),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNWidgets(4));
      expect(find.text('BPI'), findsOneWidget);
      expect(find.text('₱5,000'), findsOneWidget);
      expect(find.text('Old BDO (archived)'), findsOneWidget);
      // ₱5,000 × 3% + ₱1,000 × 6%. Cash earns nothing and GCash has no
      // rate, so neither is named.
      expect(
        find.text(
          'May earn about ₱168 a year after tax from BPI and Old BDO. Add it '
          'as income when it is paid.',
        ),
        findsOneWidget,
      );
    });

    test('interest follows each account and never counts as saved', () {
      Wallet savingsRecord(SavingsKind kind, double? rate) => Wallet(
        id: kind.name,
        name: kind.label,
        type: WalletType.other,
        balance: 10000,
        startingBalance: 10000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: kind.name,
        annualInterestRatePercent: rate,
      );

      // After the 20% tax banks keep: ₱150 becomes ₱120.
      expect(yearlyInterestOnGoalMoney(bpi, 5000), closeTo(120, 0.001));
      expect(yearlyInterestOnGoalMoney(cash, 5000), 0);
      // A rate typed on a demand deposit still earns nothing.
      expect(
        yearlyInterestOnGoalMoney(
          savingsRecord(SavingsKind.demandDeposit, 2),
          5000,
        ),
        0,
      );
      expect(
        yearlyInterestOnGoalMoney(
          savingsRecord(SavingsKind.savingsDeposit, 2.5),
          4000,
        ),
        closeTo(80, 0.001),
      );
      // No rate, no made-up figure.
      expect(yearlyInterestOnGoalMoney(gcash, 5000), isNull);
    });

    test('the funding source follows the wallets used', () {
      expect(
        GoalFundingSource.fromTypes([WalletType.cash, WalletType.bank]),
        GoalFundingSource.both,
      );
      expect(
        GoalFundingSource.fromTypes([WalletType.bank, WalletType.gcash]),
        GoalFundingSource.bank,
      );
      expect(
        GoalFundingSource.fromTypes([WalletType.cash]),
        GoalFundingSource.cash,
      );
      expect(GoalFundingSource.fromTypes(const []), isNull);
      expect(
        Goal.fromMap('mixed', {'fundingSource': 'both'}).fundingSource,
        GoalFundingSource.both,
      );
      expect(mainFundingWallet({'cash': 2000, 'bpi': 5000}), 'bpi');
      expect(mainFundingWallet(const {}), isNull);
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

    test('a quarter is the three months its date falls in', () {
      expect(
        ReportPeriod.quarterOf(DateTime(2026, 2, 10)),
        ReportPeriod(DateTime(2026, 1, 1), DateTime(2026, 3, 31)),
      );
      expect(
        ReportPeriod.quarterOf(DateTime(2026, 9, 17)),
        ReportPeriod(DateTime(2026, 7, 1), DateTime(2026, 9, 30)),
      );
      // The last day of a quarter still belongs to it.
      expect(
        ReportPeriod.quarterOf(DateTime(2026, 12, 31)),
        ReportPeriod(DateTime(2026, 10, 1), DateTime(2026, 12, 31)),
      );
    });

    test('quarters and years step back across the turn of the year', () {
      expect(
        ReportPeriod.quarterOf(
          DateTime(2026, 2, 10),
        ).previous(ReportRange.quarter),
        ReportPeriod(DateTime(2025, 10, 1), DateTime(2025, 12, 31)),
      );
      expect(
        ReportPeriod.yearOf(DateTime(2026, 6, 1)).previous(ReportRange.year),
        ReportPeriod(DateTime(2025, 1, 1), DateTime(2025, 12, 31)),
      );
    });

    test('a custom stretch steps back by its own length', () {
      // The fifteen days before the fifteen being read.
      expect(
        ReportPeriod(
          DateTime(2026, 9, 15),
          DateTime(2026, 9, 29),
        ).previous(ReportRange.custom),
        ReportPeriod(DateTime(2026, 8, 31), DateTime(2026, 9, 14)),
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

    testWidgets('trend chart uses inflow and outflow terminology', (
      tester,
    ) async {
      await pumpReports(tester);
      final trendTitle = find.text('Inflow vs. outflow');
      await tester.ensureVisible(trendTitle);
      expect(trendTitle, findsOneWidget);
      expect(find.text('Inflow'), findsOneWidget);
      expect(find.text('Outflow'), findsOneWidget);
      expect(find.text('Inward'), findsNothing);
      expect(find.text('Outward'), findsNothing);
    });

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

    testWidgets('"Count all again" brings every category back', (tester) async {
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
      // Each tip shows the app's colored bulb.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == AppIcons.idea,
        ),
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

    testWidgets('money left over is called that, not a net change', (
      tester,
    ) async {
      await pumpReports(tester);

      expect(find.text('Left over'), findsOneWidget);
      expect(find.text('Net change'), findsNothing);
    });

    testWidgets('spending past what came in reads as short, not left over', (
      tester,
    ) async {
      await pumpReports(
        tester,
        list: [
          AppTransaction(
            id: 'a',
            type: TransactionType.income,
            amount: 1000,
            label: 'Allowance',
            date: day,
            walletId: 'cash',
          ),
          AppTransaction(
            id: 'b',
            type: TransactionType.expense,
            amount: 2500,
            label: 'Food',
            date: day,
            walletId: 'cash',
          ),
        ],
      );

      expect(find.text('Short by'), findsOneWidget);
      expect(find.text('Left over'), findsNothing);
    });

    testWidgets('a quarter covers three months and steps back as one', (
      tester,
    ) async {
      await pumpReports(tester);

      await tester.tap(find.text('Quarter'));
      await tester.pump();
      expect(find.text('Jul 1 – Sep 30, 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Earlier'));
      await tester.pump();
      expect(find.text('Apr 1 – Jun 30, 2026'), findsOneWidget);
    });

    testWidgets('a year covers the calendar year', (tester) async {
      await pumpReports(tester);

      await tester.tap(find.text('Year'));
      await tester.pump();
      expect(find.text('Jan 1 – Dec 31, 2026'), findsOneWidget);
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

    Wallet holding(String id, double balance, WalletPurpose purpose) => Wallet(
      id: id,
      name: purpose.defaultName ?? id,
      type: WalletType.other,
      balance: balance,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 2,
      purpose: purpose,
    );

    Future<void> pumpHome(
      WidgetTester tester,
      List<AppTransaction> transactions, {
      List<Wallet>? wallets,
      List<Goal> goals = const [],
    }) async {
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
              wallets: Stream.value(wallets ?? [cash, gcash]),
              transactions: Stream.value(transactions),
              goals: Stream.value(goals),
              // Stands in for the notices under the total balance, which
              // load live data.
              safeToSpend: const SizedBox(
                height: 80,
                child: Text('Notices placeholder'),
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

    testWidgets('Home keeps support in Settings, not its top bar', (
      tester,
    ) async {
      await pumpHome(tester, const []);
      expect(find.byTooltip('App guide'), findsNothing);
      expect(find.byTooltip('AI Assistant'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('the top card is the total, split into cash and bank', (
      tester,
    ) async {
      await pumpHome(
        tester,
        const [],
        wallets: [cash, gcash, holding('s', 8000, WalletPurpose.savings)],
      );

      expect(find.text('Available Balance'), findsOneWidget);
      // ₱5,000 cash and ₱10,000 in GCash. The ₱8,000 saved is kept apart,
      // so not in it.
      expect(find.text('₱15,000'), findsOneWidget);
      expect(find.text('Cash on Hand'), findsOneWidget);
      expect(find.text('₱5,000'), findsOneWidget);
      expect(find.text('Cash in Bank'), findsOneWidget);
      expect(find.text('₱10,000'), findsOneWidget);
      expect(find.text('₱8,000'), findsNothing);

      // Gone from Home: Safe to Spend's daily figures and the Bills and
      // Savings cards.
      expect(find.text('Safe to Spend Today'), findsNothing);
      expect(find.textContaining('daily limit'), findsNothing);
      expect(find.textContaining('left this period'), findsNothing);
      expect(find.textContaining('View your bills'), findsNothing);
      expect(find.textContaining('View your savings'), findsNothing);
      expect(find.text('Wallet Total Balance'), findsNothing);

      // No separate Wallets card: the two boxes open the wallets instead.
      expect(find.text('2 wallets'), findsNothing);
    });

    testWidgets('each box opens the wallets it adds up', (tester) async {
      final bpi = Wallet(
        id: 'bpi',
        name: 'BPI',
        type: WalletType.bank,
        balance: 3000,
        startingBalance: 3000,
        receivesIncome: false,
        archived: false,
        sortOrder: 3,
      );
      await pumpHome(
        tester,
        const [],
        wallets: [cash, gcash, bpi, holding('s', 8000, WalletPurpose.savings)],
      );

      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      expect(find.textContaining('across 1 wallet'), findsOneWidget);
      // The wallet's name and its kind both read "Cash".
      expect(find.text('Cash'), findsWidgets);
      expect(find.text('GCash'), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Banks and e-wallets together; set-aside savings stay out.
      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      expect(find.textContaining('across 2 wallets'), findsOneWidget);
      expect(find.text('GCash'), findsWidgets);
      expect(find.text('BPI'), findsOneWidget);
      expect(find.text('₱8,000'), findsNothing);
      // ₱10,000 + ₱3,000, on the box and at the top of its list.
      expect(find.text('₱13,000'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // The total opens all of them, each group with what it adds up to.
      await tester.tap(find.byKey(const Key('total-balance-open')));
      await tester.pumpAndSettle();
      expect(find.textContaining('across 3 wallets'), findsOneWidget);
      // ₱5,000 cash and ₱13,000 in the bank: on the card, and as the two
      // groups in the list.
      expect(find.text('₱5,000'), findsNWidgets(3));
      expect(find.text('₱13,000'), findsNWidgets(2));
      expect(find.text('BPI'), findsOneWidget);
      expect(find.text('₱8,000'), findsNothing);
    });

    testWidgets('the eye hides every amount; the info says what is in it', (
      tester,
    ) async {
      await pumpHome(tester, const []);

      expect(find.text('₱15,000'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      expect(find.text('₱15,000'), findsNothing);
      expect(find.byTooltip('Show amounts'), findsOneWidget);
      await tester.tap(find.byTooltip('Show amounts'));
      await tester.pumpAndSettle();
      expect(find.text('₱15,000'), findsOneWidget);

      await tester.tap(find.byKey(const Key('total-balance-info')));
      await tester.pumpAndSettle();
      // The sum with the user's own figures, like setup's Cash Summary:
      // ₱5,000 cash on hand, ₱10,000 in GCash, so ₱15,000 to spend.
      final explained = find.byKey(const Key('available-balance-explained'));
      Finder inSheet(String text) =>
          find.descendant(of: explained, matching: find.text(text));
      expect(inSheet('The money you can spend right now.'), findsOneWidget);
      expect(inSheet('Cash on Hand'), findsOneWidget);
      expect(inSheet('₱5,000'), findsOneWidget);
      expect(inSheet('Cash in Bank'), findsOneWidget);
      expect(inSheet('₱10,000'), findsOneWidget);
      expect(inSheet('Available Balance'), findsWidgets);
      expect(inSheet('₱15,000'), findsOneWidget);
      expect(
        find.byKey(const Key('available-balance-goals')),
        findsNothing,
        reason: 'no goal money to take off',
      );
      // GCash has no rate here, so no interest line.
      expect(inSheet('Interest in a Year (after tax)'), findsNothing);
      expect(
        find.textContaining('Money in Savings is not included.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets('the balance is what can be spent, after goal money', (
      tester,
    ) async {
      // ₱2,000 of the cash and ₱1,500 of GCash are set aside for a goal.
      await pumpHome(
        tester,
        const [],
        goals: const [
          Goal(
            id: 'grad',
            name: 'Graduation',
            targetAmount: 10000,
            savedAmount: 3500,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'cash': 2000, 'gcash': 1500},
          ),
        ],
      );

      // ₱15,000 in the accounts, ₱11,500 of it free to spend.
      expect(find.text('₱11,500'), findsOneWidget);
      expect(find.text('₱3,000'), findsOneWidget, reason: 'cash on hand');
      expect(find.text('₱8,500'), findsOneWidget, reason: 'cash in bank');
      // One figure to read on the card; goal money is in Goals and Wallets.
      expect(find.text('₱3,500 set aside for goals'), findsNothing);
      expect(find.textContaining('in your accounts'), findsNothing);

      // The figure opens the sum, for whoever wants to check it.
      await tester.tap(find.byKey(const Key('total-balance-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('available-balance-math')), findsOneWidget);
      expect(find.text('In your accounts'), findsOneWidget);
      expect(find.text('₱15,000'), findsOneWidget);
      expect(find.text('Available to spend'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Each wallet says what it has free, and what its goals hold.
      await tester.tap(find.byKey(const Key('total-balance-open')));
      await tester.pumpAndSettle();
      expect(find.text('₱2,000 set aside for goals'), findsOneWidget);
      expect(find.text('₱1,500 set aside for goals'), findsOneWidget);
      expect(find.textContaining('across 2 wallets'), findsOneWidget);
    });

    testWidgets('a new account sees ₱0 and a prompt to add a wallet', (
      tester,
    ) async {
      await pumpHome(tester, const [], wallets: const []);

      expect(find.text('₱0'), findsNWidgets(3));
      await tester.tap(find.text('Cash on Hand'));
      await tester.pumpAndSettle();
      expect(
        find.text('No cash wallets yet. Add one in Wallets.'),
        findsOneWidget,
      );
    });

    testWidgets('reads the wallet ledger, with the total balance first', (
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
      expect(find.textContaining('transactions recorded'), findsNothing);
      expect(find.text('Manage Category Budgets'), findsNothing);
      for (final shortcut in ['Expense', 'Income', 'Transfer']) {
        expect(find.text(shortcut), findsOneWidget);
      }
      expect(find.text('Bill Planner'), findsNothing);
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      for (final shortcut in [
        'Bill Planner',
        'Savings',
        'Installments',
        'Debts',
        'Reports',
        'Scan Receipt',
        'Voice Entry',
      ]) {
        expect(find.text(shortcut), findsOneWidget);
      }

      // The total first, then the notices under it.
      final totalTop = tester.getTopLeft(find.text('Available Balance'));
      final noticesTop = tester.getTopLeft(find.text('Notices placeholder'));
      expect(totalTop.dy, lessThan(noticesTop.dy));

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

  group('the Settings row that exports transactions', () {
    Future<void> pumpTile(
      WidgetTester tester,
      Future<ExportResult> Function() onExport,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: ExportTransactionsTile(onExport: onExport)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('says what the file is before it is tapped', (tester) async {
      await pumpTile(
        tester,
        () async => const ExportResult(ExportOutcome.cancelled),
      );

      expect(find.text('Export transactions'), findsOneWidget);
      expect(
        find.text(
          'Save all your records as a CSV file you can open in Excel or '
          'Google Sheets',
        ),
        findsOneWidget,
      );
    });

    testWidgets('names the file that was saved', (tester) async {
      var asked = 0;
      await pumpTile(tester, () async {
        asked++;
        return const ExportResult(
          ExportOutcome.saved,
          fileName: 'FinAssist-transactions-2026-09-17.csv',
        );
      });

      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(
        find.text('Saved FinAssist-transactions-2026-09-17.csv'),
        findsOneWidget,
      );
    });

    testWidgets('says so when there is nothing recorded yet', (tester) async {
      await pumpTile(
        tester,
        () async => const ExportResult(ExportOutcome.nothingToExport),
      );

      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();

      expect(find.text('No transactions to export yet.'), findsOneWidget);
    });

    testWidgets('backing out of the save dialog says nothing', (tester) async {
      await pumpTile(
        tester,
        () async => const ExportResult(ExportOutcome.cancelled),
      );

      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed save asks the user to try again', (tester) async {
      await pumpTile(tester, () async => throw Exception('no space'));

      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();

      expect(
        find.text('The file could not be saved. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('one tap opens one save dialog', (tester) async {
      var asked = 0;
      await pumpTile(tester, () async {
        asked++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return const ExportResult(ExportOutcome.cancelled);
      });

      await tester.tap(find.text('Export transactions'));
      await tester.pump();
      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();

      expect(asked, 1);
    });
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

  testWidgets('Transactions heads each day once, newest first', (tester) async {
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

    // Tall enough to hold the breakdown and every day below it, since the
    // list only builds the rows it can show.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    expect(find.text('Inflow'), findsNothing);

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
    expect(find.text('₱100'), findsOneWidget, reason: 'outward stays ₱100');
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
      List<Wallet> wallets = const [],
      required DateTime now,
      ReminderKind? only,
    }) => planReminders(
      settings: settings,
      bills: bills,
      goals: goals,
      wallets: wallets,
      cycles: cycles,
      transactions: transactions,
      now: now,
    ).where((r) => only == null || r.kind == only).toList();

    test('the ranking decides how many reminders each gets', () {
      final settings = ReminderSettings.fromProfile(
        profile([
          FinancialPriority.trackSpending,
          FinancialPriority.generalSavings,
          FinancialPriority.payBills,
          FinancialPriority.saveForGoal,
        ]),
      );
      // #1 gets 4, #2 gets 3, #3 gets 2, #4 gets 1.
      expect(settings.timesFor(ReminderKind.dailyLog), 4);
      expect(settings.timesFor(ReminderKind.leftover), 3);
      expect(settings.timesFor(ReminderKind.bills), 2);
      expect(settings.timesFor(ReminderKind.goals), 1);
      // Even #4 gets one, so every reminder starts on.
      for (final kind in ReminderKind.values) {
        expect(settings.isOn(kind), isTrue, reason: kind.name);
      }
      expect(reminderCountText(1), '4 reminders');
      expect(reminderCountText(4), '1 reminder');
    });

    test('re-ranking changes the counts, not what was switched off', () {
      final before = ReminderSettings.fromProfile(
        profile(
          const [FinancialPriority.saveForGoal, FinancialPriority.payBills],
          reminders: {'goals': false},
        ),
      );
      expect(before.isOn(ReminderKind.goals), isFalse, reason: 'by hand');
      expect(before.timesFor(ReminderKind.bills), 3);

      final reranked = ReminderSettings.fromProfile(
        profile(
          const [FinancialPriority.payBills, FinancialPriority.saveForGoal],
          reminders: {'goals': false},
        ),
      );
      expect(reranked.isOn(ReminderKind.goals), isFalse);
      expect(reranked.timesFor(ReminderKind.bills), 4);
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

    test('bills get 4, 3, 2 or 1 reminders by rank, at 9 AM', () {
      ReminderSettings billsAt(int place) {
        final order = [
          FinancialPriority.saveForGoal,
          FinancialPriority.generalSavings,
          FinancialPriority.trackSpending,
        ]..insert(place - 1, FinancialPriority.payBills);
        return ReminderSettings.fromProfile(profile(order));
      }

      final now = DateTime(2026, 9, 10, 10);
      final internet = [bill('Internet', DateTime(2026, 9, 25))];
      List<String> times(int place) => [
        for (final r in plan(
          billsAt(place),
          now: now,
          bills: internet,
          only: ReminderKind.bills,
        ))
          '${r.title} @ ${r.at.month}/${r.at.day} ${r.at.hour}h',
      ];

      expect(times(1), [
        'Internet is due in 7 days @ 9/18 9h',
        'Internet is due in 3 days @ 9/22 9h',
        'Internet is due tomorrow @ 9/24 9h',
        'Internet is due today @ 9/25 9h',
      ]);
      expect(times(2), [
        'Internet is due in 3 days @ 9/22 9h',
        'Internet is due tomorrow @ 9/24 9h',
        'Internet is due today @ 9/25 9h',
      ]);
      expect(times(3), [
        'Internet is due tomorrow @ 9/24 9h',
        'Internet is due today @ 9/25 9h',
      ]);
      expect(times(4), ['Internet is due today @ 9/25 9h']);

      final single = plan(
        billsAt(4),
        now: now,
        bills: internet,
        only: ReminderKind.bills,
      ).single;
      expect(single.body, '₱1,000 to pay. Tap to pay it now.');
      expect(single.payload, 'bill:Internet');
    });

    test('paid bills and past times are not reminded', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.payBills]),
      );
      final planned = plan(
        settings,
        now: DateTime(2026, 9, 18, 10),
        only: ReminderKind.bills,
        bills: [
          bill('Water', DateTime(2026, 9, 19)),
          bill('Paid', DateTime(2026, 9, 26), status: BillStatus.paid),
        ],
      );
      // Water's 7, 3 and 1 day reminders have already passed.
      expect(planned.map((r) => r.title), ['Water is due today']);
    });

    test('bills reminded on the same day share one notification', () {
      for (final first in [
        FinancialPriority.payBills,
        FinancialPriority.trackSpending,
      ]) {
        final settings = ReminderSettings.fromProfile(profile([first]));
        final planned = plan(
          settings,
          now: DateTime(2026, 9, 20, 10),
          only: ReminderKind.bills,
          bills: [
            bill('Rent', DateTime(2026, 9, 30), amount: 5000),
            bill('Internet', DateTime(2026, 9, 30), amount: 1200),
            bill('Water', DateTime(2026, 9, 30), amount: 400),
            bill('Phone', DateTime(2026, 9, 30), amount: 999),
            bill('Netflix', DateTime(2026, 9, 30), amount: 549),
          ],
        );
        final dueDay = planned.where((r) => r.at.day == 30).toList();
        // Whatever the rank, five bills due together are one reminder.
        expect(dueDay, hasLength(1), reason: first.name);
        expect(dueDay.single.title, '5 bills due today');
        expect(
          dueDay.single.body,
          'Internet ₱1,200, Netflix ₱549, Phone ₱999 and 2 more. Tap to '
          'see them.',
        );
        expect(dueDay.single.payload, 'bills');
        expect(planned.map((r) => r.at).toSet(), hasLength(planned.length));
      }

      // Different due dates landing on one morning are shared too, each
      // with its own day.
      final mixed = plan(
        ReminderSettings.fromProfile(
          profile(const [FinancialPriority.payBills]),
        ),
        now: DateTime(2026, 9, 20, 10),
        only: ReminderKind.bills,
        bills: [
          bill('Rent', DateTime(2026, 9, 25), amount: 5000),
          bill('Internet', DateTime(2026, 9, 28), amount: 1200),
        ],
      ).where((r) => r.at.day == 25).single;
      expect(mixed.title, '2 bills to pay soon');
      expect(
        mixed.body,
        'Rent ₱5,000 (today) and Internet ₱1,200 (in 3 days). Tap to see '
        'them.',
      );
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
        only: ReminderKind.goals,
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

      expect(
        planned.map((r) => r.at),
        [
          DateTime(2026, 10, 16, 9),
          DateTime(2026, 10, 17, 9),
          DateTime(2026, 10, 18, 9),
          DateTime(2026, 10, 20, 9),
        ],
        reason:
            'goals are #1, so 4: the day before, the saving day, a warning '
            'and a last call; a reached goal waits',
      );
      expect(planned.first.title, 'Saving day tomorrow: Laptop');
      expect(planned.first.body, 'Get ₱1,500 ready to set aside.');
      expect(planned[1].title, 'Time to save for Laptop');
      expect(planned[1].body, '₱1,500 a month. ₱18,500 to go.');
      expect(planned[2].title, 'Missed: Laptop');
      expect(planned.last.title, 'Last reminder for Laptop');
      expect(planned.last.body, startsWith('Still ₱1,500 short.'));

      final byDateGoal = Goal(
        id: 'd',
        name: 'Laptop',
        targetAmount: 20000,
        savedAmount: 1000,
        priority: 0,
        status: GoalStatus.active,
        targetDate: DateTime(2027, 9, 17),
        planStartedAt: DateTime(2026, 9, 17),
      );
      final byDate = plan(
        settings,
        now: DateTime(2026, 9, 18, 12),
        only: ReminderKind.goals,
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
        byDate[1].body,
        'Save ₱1,583.33 a month to reach it by Sep 17, 2027.',
        reason: 'a goal with neither an amount nor a date gets no reminder',
      );
      expect(byDate.length, 4, reason: 'four reminders, as goals are #1');

      // Lower ranks drop the extras in turn.
      int goalTimes(List<FinancialPriority> order) => plan(
        ReminderSettings.fromProfile(profile(order)),
        now: DateTime(2026, 9, 18, 12),
        only: ReminderKind.goals,
        goals: [byDateGoal],
      ).length;
      expect(goalTimes(const [FinancialPriority.payBills]), 3);
      expect(
        goalTimes(const [
          FinancialPriority.payBills,
          FinancialPriority.generalSavings,
        ]),
        2,
      );
      expect(
        goalTimes(const [
          FinancialPriority.payBills,
          FinancialPriority.generalSavings,
          FinancialPriority.trackSpending,
        ]),
        1,
      );
    });

    test('a goal planned by its date is not reminded past that date', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );
      Goal trip(DateTime finish) => Goal(
        id: 't',
        name: 'Trip',
        targetAmount: 6000,
        savedAmount: 0,
        priority: 0,
        status: GoalStatus.active,
        targetDate: finish,
        planStartedAt: DateTime(2026, 9, 17),
      );
      List<PlannedReminder> remind(Goal goal) => plan(
        settings,
        now: DateTime(2026, 9, 18, 12),
        only: ReminderKind.goals,
        goals: [goal],
      );

      // The date has gone by: a new one is needed, not a sum for the past.
      expect(remind(trip(DateTime(2026, 9, 1))), isEmpty);

      // Due Oct 10, before the Oct 17 saving day: all of it by the date, so
      // the date itself is the saving day reminded of, never Oct 17.
      final early = remind(trip(DateTime(2026, 10, 10)));
      expect(early, isNotEmpty);
      expect(early[1].at, DateTime(2026, 10, 10, 9));
      expect(early[1].body, 'Save ₱6,000 by Oct 10, 2026 to reach it.');
      expect(
        early.every((reminder) => reminder.at.isBefore(DateTime(2026, 10, 17))),
        isTrue,
      );
    });

    test('saving for the cycle silences the goal reminders', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );
      Goal laptop(double saved) => Goal(
        id: 'g',
        name: 'Laptop',
        targetAmount: 20000,
        savedAmount: saved,
        priority: 0,
        status: GoalStatus.active,
        planAmount: 1500,
        planStartedAt: DateTime(2026, 9, 17),
      );

      // Oct 17 was the saving day and nothing went in, so the day after
      // carries a warning and the third day the last call.
      final missed = plan(
        settings,
        now: DateTime(2026, 10, 18, 7),
        goals: [laptop(0)],
        only: ReminderKind.goals,
      );
      expect(missed.where((r) => r.at.month == 10).map((r) => r.title), [
        'Missed: Laptop',
        'Last reminder for Laptop',
      ]);

      // The same day, with the month's ₱1,500 already set aside.
      final onTrack = plan(
        settings,
        now: DateTime(2026, 10, 18, 7),
        goals: [laptop(1500)],
        only: ReminderKind.goals,
      );
      expect(
        onTrack.where((r) => r.at.month == 10),
        isEmpty,
        reason: 'nothing to chase once this cycle is saved',
      );
      expect(
        onTrack.where((r) => r.at.month == 11),
        isNotEmpty,
        reason: 'next month is still planned',
      );
    });

    Wallet interestAccount({
      InterestPayout payout = InterestPayout.monthly,
      double balance = 100000,
      double? rate = 3,
      WalletType type = WalletType.bank,
    }) => Wallet(
      id: 'bpi',
      name: 'BPI',
      type: type,
      balance: balance,
      startingBalance: balance,
      receivesIncome: false,
      archived: false,
      sortOrder: 0,
      annualInterestRatePercent: rate,
      interestPayout: payout,
    );

    test('interest is asked about on the 1st after each payment', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );
      final planned = plan(
        settings,
        now: DateTime(2027, 3, 10, 7),
        wallets: [interestAccount()],
        only: ReminderKind.interest,
      );

      expect(planned.map((r) => r.at), [
        DateTime(2027, 4, 1, 9),
        DateTime(2027, 5, 1, 9),
      ]);
      expect(planned.first.title, 'Interest from BPI may be in');
      // ₱100,000 × 3% ÷ 12 = ₱250, less the 20% tax banks keep.
      expect(
        planned.first.body,
        'About ₱200 after tax. Check your app and add what it paid.',
      );
      expect(planned.first.payload, 'interest:bpi');
      expect(planned.first.key, 'interest:bpi:2027-4');
    });

    test('interest reminders follow how often the account pays', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );
      List<DateTime> days(Wallet wallet, {DateTime? now}) => plan(
        settings,
        now: now ?? DateTime(2027, 3, 10, 7),
        wallets: [wallet],
        only: ReminderKind.interest,
      ).map((r) => r.at).toList();

      // Every 3 months: January, April, July and October.
      expect(days(interestAccount(payout: InterestPayout.quarterly)), [
        DateTime(2027, 4, 1, 9),
      ]);
      // Every year: January, planned even when it is months away.
      expect(days(interestAccount(payout: InterestPayout.yearly)), [
        DateTime(2028, 1, 1, 9),
      ]);
      // Every 6 months: January and July.
      expect(days(interestAccount(payout: InterestPayout.semiAnnual)), [
        DateTime(2027, 7, 1, 9),
      ]);
      // Paid daily, it is added once a month, as the month's total.
      final daily = plan(
        settings,
        now: DateTime(2027, 3, 10, 7),
        wallets: [interestAccount(payout: InterestPayout.daily)],
        only: ReminderKind.interest,
      );
      expect(daily.map((r) => r.at), [
        DateTime(2027, 4, 1, 9),
        DateTime(2027, 5, 1, 9),
      ]);
      expect(
        daily.first.body,
        "About ₱200 this month after tax. Check your app and add the month's "
        'total.',
      );
      expect(
        days(
          interestAccount(payout: InterestPayout.yearly),
          now: DateTime(2027, 12, 10),
        ),
        [DateTime(2028, 1, 1, 9)],
      );
      // No rate, a tiny balance, or cash: nothing honest to ask about.
      expect(days(interestAccount(rate: null)), isEmpty);
      expect(days(interestAccount(balance: 1, rate: 0.1)), isEmpty);
      expect(days(interestAccount(type: WalletType.cash)), isEmpty);
    });

    test('interest already added, or reminders turned off, asks nothing', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );
      final added = AppTransaction(
        id: 't',
        type: TransactionType.income,
        amount: 198.5,
        label: interestIncomeLabel,
        date: DateTime(2027, 3, 28),
        walletId: 'bpi',
      );
      expect(
        plan(
          settings,
          now: DateTime(2027, 3, 29, 7),
          wallets: [interestAccount()],
          transactions: [added],
          only: ReminderKind.interest,
        ).map((r) => r.at),
        [DateTime(2027, 5, 1, 9)],
        reason: 'April was added early; May is still asked',
      );

      final off = ReminderSettings(
        enabled: true,
        priorities: settings.priorities,
        overrides: const {ReminderKind.interest: false},
      );
      expect(
        plan(
          off,
          now: DateTime(2027, 3, 10, 7),
          wallets: [interestAccount()],
          only: ReminderKind.interest,
        ),
        isEmpty,
      );
    });

    test('which accounts pay interest, and what each payment brings', () {
      expect(afterTax(100), 80);
      expect(InterestPayout.quarterly.remindsOn(DateTime(2027)), isTrue);
      expect(InterestPayout.quarterly.remindsOn(DateTime(2027, 4)), isTrue);
      expect(InterestPayout.quarterly.remindsOn(DateTime(2027, 2)), isFalse);
      expect(InterestPayout.yearly.remindsOn(DateTime(2027, 7)), isFalse);
      // Any other bank's schedule, evenly spaced across years: every 5
      // months from January 2027 is June, November, then April 2028.
      const everyFive = InterestPayout.everyMonths(5);
      expect(
        [
          for (var month = 1; month <= 16; month++)
            if (everyFive.remindsOn(DateTime(2027, month))) month,
        ],
        // DateTime(2027, 16) is April 2028.
        [
          for (var month = 1; month <= 16; month++)
            if ((2027 * 12 + month - 1) % 5 == 0) month,
        ],
      );
      expect(everyFive.label, 'Every 5 months');
      expect(everyFive.isPreset, isFalse);
      expect(InterestPayout.daily.label, 'Every day');
      // Saved as a number; an older named one still reads.
      expect(
        InterestPayout.fromStored(months: 5),
        const InterestPayout.everyMonths(5),
      );
      expect(
        InterestPayout.fromStored(name: 'quarterly'),
        InterestPayout.quarterly,
      );
      expect(InterestPayout.fromStored(months: 40), InterestPayout.monthly);
      expect(interestAccount().interestPerPayoutAfterTax, closeTo(200, 1e-9));
      expect(
        interestAccount(
          payout: InterestPayout.quarterly,
        ).interestPerPayoutAfterTax,
        closeTo(600, 1e-9),
      );
      expect(interestAccount(rate: 0).paysRegularInterest, isFalse);
      expect(
        interestAccount(type: WalletType.ewallet).paysRegularInterest,
        isTrue,
      );

      Wallet savings(SavingsKind kind) => Wallet(
        id: kind.name,
        name: kind.label,
        type: WalletType.other,
        balance: 10000,
        startingBalance: 10000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: WalletPurpose.savings,
        savingsKind: kind.name,
        annualInterestRatePercent: 3,
      );
      // A savings deposit pays now and then; a time deposit pays at its end
      // and a demand deposit pays nothing.
      expect(savings(SavingsKind.savingsDeposit).paysRegularInterest, isTrue);
      expect(savings(SavingsKind.timeDeposit).paysRegularInterest, isFalse);
      expect(savings(SavingsKind.demandDeposit).paysRegularInterest, isFalse);

      // Saved accounts start on monthly, and keep what they are set to.
      expect(
        Wallet.fromMap('x', {'type': 'bank'}).interestPayout,
        InterestPayout.monthly,
      );
      expect(
        Wallet.fromMap('x', {
          'type': 'bank',
          'interestPayout': 'quarterly',
        }).interestPayout,
        InterestPayout.quarterly,
      );
      expect(incomeSources, contains('Interest'));
    });

    testWidgets('interest is added as what the app shows, not the estimate', (
      tester,
    ) async {
      double? amount;
      DateTime? date;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AddInterestSheet(
              wallet: interestAccount(),
              today: DateTime(2027, 4, 1),
              onSave: (a, d) {
                amount = a;
                date = d;
              },
            ),
          ),
        ),
      );

      expect(find.text('Interest from BPI'), findsOneWidget);
      // It starts on the estimate after tax, to be changed to the real one.
      expect(find.text('200'), findsOneWidget);
      expect(
        find.text(
          'We expected about ₱200 after tax. Change it to what your app '
          'shows.',
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.byKey(const Key('add-interest-save')));
      await tester.pump();
      expect(find.text(minimumAmountError), findsWidgets);
      expect(amount, isNull);

      await tester.enterText(find.byType(TextField).first, '198.50');
      await tester.tap(find.byKey(const Key('add-interest-save')));
      await tester.pump();
      expect(amount, 198.5);
      expect(date, DateTime(2027, 4, 1));
    });

    testWidgets('Custom sets any bank schedule, in months', (tester) async {
      var payout = InterestPayout.monthly;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => InterestPayoutPicker(
                payout: payout,
                onChanged: (next) => setState(() => payout = next),
              ),
            ),
          ),
        ),
      );

      // The usual answers are one tap, and every day is one of them.
      for (final id in [
        'daily',
        'monthly',
        'quarterly',
        'semiAnnual',
        'yearly',
        'custom',
      ]) {
        expect(find.byKey(Key('interest-payout-$id')), findsOneWidget);
      }
      expect(find.text('Pays every'), findsNothing);

      // Three to a row, in the same places whichever is picked.
      Offset where(String id) =>
          tester.getTopLeft(find.byKey(Key('interest-payout-$id')));
      final before = {
        for (final id in ['daily', 'quarterly', 'semiAnnual', 'custom'])
          id: where(id),
      };
      expect(before['daily']!.dy, before['quarterly']!.dy);
      expect(before['semiAnnual']!.dy, before['custom']!.dy);
      expect(before['semiAnnual']!.dy, greaterThan(before['daily']!.dy));
      await tester.tap(find.byKey(const Key('interest-payout-semiAnnual')));
      await tester.pump();
      for (final id in before.keys) {
        expect(where(id), before[id], reason: '$id stays where it was');
      }

      // Custom starts on every 2 months, the first not offered above.
      await tester.tap(find.byKey(const Key('interest-payout-custom')));
      await tester.pump();
      expect(find.text('Pays every'), findsOneWidget);
      expect(payout, const InterestPayout.everyMonths(2));

      // Stepping to a number that is also a choice above keeps Custom open.
      await tester.tap(find.byTooltip('One month more'));
      await tester.pump();
      expect(payout, InterestPayout.quarterly);
      expect(find.text('Pays every'), findsOneWidget);
      await tester.tap(find.byTooltip('One month more'));
      await tester.pump();
      await tester.tap(find.byTooltip('One month more'));
      await tester.pump();
      expect(payout, const InterestPayout.everyMonths(5));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('interest-payout-months')))
            .data,
        '5',
      );

      // Every day is added once a month, and the picker says so.
      await tester.tap(find.byKey(const Key('interest-payout-daily')));
      await tester.pump();
      expect(payout, InterestPayout.daily);
      expect(find.text('Pays every'), findsNothing);
      expect(
        find.textContaining("add the month's total as income"),
        findsOneWidget,
      );
    });

    testWidgets('the account card shows its interest and how often it pays', (
      tester,
    ) async {
      InterestPayout? changed;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InterestCard(
              wallet: interestAccount(),
              onPayoutChanged: (payout) => changed = payout,
              onAdd: () => opened = true,
            ),
          ),
        ),
      );

      expect(find.text('3% a year · paid every month'), findsOneWidget);
      expect(find.text('about ₱200'), findsOneWidget);
      expect(find.text('about ₱2,400'), findsOneWidget);

      await tester.tap(find.byKey(const Key('interest-payout-quarterly')));
      await tester.pump();
      expect(changed, InterestPayout.quarterly);

      await tester.tap(find.byKey(const Key('add-interest')));
      await tester.pump();
      expect(opened, isTrue);
    });

    Wallet maturedDeposit({double balance = 25000, DateTime? matures}) =>
        Wallet(
          id: 'mp2',
          name: 'Pag-IBIG MP2',
          type: WalletType.other,
          balance: balance,
          startingBalance: balance,
          receivesIncome: false,
          archived: false,
          sortOrder: 0,
          purpose: WalletPurpose.savings,
          maturityDate: matures,
        );

    test('one reminder on the day and one a week later', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );
      final planned = plan(
        settings,
        now: DateTime(2027, 3, 1, 7),
        wallets: [maturedDeposit(matures: DateTime(2027, 3, 5))],
        only: ReminderKind.goals,
      );

      expect(planned.map((r) => r.at), [
        DateTime(2027, 3, 5, 9),
        DateTime(2027, 3, 12, 9),
      ]);
      expect(planned.first.title, 'Pag-IBIG MP2 matures today');
      expect(planned.last.title, 'Pag-IBIG MP2 matured a week ago');
      // The same event always keeps the same id, so it cannot double up.
      expect(planned.first.key, 'savings:mp2:matured');
    });

    test('a settled record is no longer chased', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.saveForGoal]),
      );

      expect(
        plan(
          settings,
          now: DateTime(2027, 3, 1, 7),
          wallets: [maturedDeposit()],
          only: ReminderKind.goals,
        ),
        isEmpty,
        reason: 'clearing the date ends the reminders',
      );
      expect(
        plan(
          settings,
          now: DateTime(2027, 3, 1, 7),
          wallets: [maturedDeposit(matures: DateTime(2027, 3, 5), balance: 0)],
          only: ReminderKind.goals,
        ),
        isEmpty,
        reason: 'an emptied record has nothing to come due',
      );
    });
    test('logging comes 4, 3, 2 or 1 times a week by rank', () {
      // Friday, Sep 18, 2026.
      final now = DateTime(2026, 9, 18, 13);
      List<int> days(List<FinancialPriority> order, {bool logged = false}) => [
        for (final r in plan(
          ReminderSettings.fromProfile(profile(order)),
          now: now,
          only: ReminderKind.dailyLog,
          transactions: [
            if (logged)
              AppTransaction(
                id: 't',
                type: TransactionType.expense,
                amount: 50,
                label: 'Food',
                date: DateTime(2026, 9, 18, 8),
              ),
          ],
        ))
          r.at.day,
      ];

      // #1: Mon, Wed, Fri and Sun.
      expect(days(const [FinancialPriority.trackSpending]), [18, 20, 21, 23]);
      // Logged today, so tonight is skipped.
      expect(days(const [FinancialPriority.trackSpending], logged: true), [
        20,
        21,
        23,
      ]);
      // #4: Sundays only.
      expect(days(const []), [20]);
      final one = plan(
        ReminderSettings.fromProfile(profile(const [])),
        now: now,
        only: ReminderKind.dailyLog,
      ).single;
      expect(one.at, DateTime(2026, 9, 20, 20));
      expect(one.title, 'Time to log your spending');
    });

    test('the leftover question comes as the month ends', () {
      final settings = ReminderSettings.fromProfile(
        profile(const [FinancialPriority.generalSavings]),
      );
      final cycle = AllocationCycle(
        id: 'c',
        income: 5000,
        remaining: 3000,
        receivedAt: DateTime(2026, 9, 1),
        source: 'Allowance',
      );

      // Leftover money is #1, so 4: 3 days before the month ends, the night
      // before, the morning of the 1st, and 2 days after.
      final ending = plan(
        settings,
        now: DateTime(2026, 9, 18),
        cycles: [cycle],
        only: ReminderKind.leftover,
      );
      expect(ending.map((r) => r.at), [
        DateTime(2026, 9, 28, 19),
        DateTime(2026, 9, 30, 19),
        DateTime(2026, 10, 1, 9),
        DateTime(2026, 10, 3, 9),
      ]);
      expect(ending[1].title, 'This month ends tomorrow');
      expect(ending.every((r) => r.payload == 'leftover'), isTrue);

      final stillWaiting = plan(
        settings,
        now: DateTime(2026, 10, 2, 12),
        cycles: [cycle],
        only: ReminderKind.leftover,
      );
      expect(stillWaiting.single.at, DateTime(2026, 10, 3, 9));
      expect(stillWaiting.single.title, 'Last reminder: your leftover');

      // At #4, only the night before.
      final last = plan(
        ReminderSettings.fromProfile(
          profile(const [
            FinancialPriority.payBills,
            FinancialPriority.saveForGoal,
            FinancialPriority.trackSpending,
          ]),
        ),
        now: DateTime(2026, 9, 18),
        cycles: [cycle],
        only: ReminderKind.leftover,
      );
      expect(last.single.at, DateTime(2026, 9, 30, 19));
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

    group('last payday', () {
      AllocationCycle pay(DateTime at, {String source = 'Salary'}) =>
          AllocationCycle(
            id: '$source-$at',
            income: 10000,
            remaining: 8000,
            receivedAt: at,
            source: source,
          );

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
          find.text('"Save toward a goal" is #2 for you: 3 reminders.'),
          findsOneWidget,
        );
        expect(
          find.text('"Just track my spending" is #4 for you: 1 reminder.'),
          findsOneWidget,
        );
        // Each card says when, for the count it gets.
        expect(
          find.text(
            '7 days, 3 days and 1 day before, and on the due day, at 9 AM.',
          ),
          findsOneWidget,
        );
        expect(find.text('Sundays at 8 PM.'), findsOneWidget);
        // Each rank shows what it is worth; no separate days-before choice.
        expect(find.text('4 reminders'), findsOneWidget);
        expect(find.text('1 reminder'), findsOneWidget);
        expect(find.text('3 days before'), findsNothing);
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

      testWidgets('a reminder turned back on follows the ranking again', (
        tester,
      ) async {
        final calls = <String>[];
        await pumpScreen(
          tester,
          data: profile(order, reminders: {'dailyLog': false}),
          onKind: (kind, on) => calls.add('${kind.name}=$on'),
        );

        expect(find.text("Turned off. You won't get these."), findsOneWidget);

        final switches = find.byType(Switch);
        // Master, bills, goals, leftover, logging.
        await tester.tap(switches.at(2));
        await tester.tap(switches.at(4));
        expect(calls, ['goals=false', 'dailyLog=null']);
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
