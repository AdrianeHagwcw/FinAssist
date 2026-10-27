import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testapp/backend/models/allocation.dart';
import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/cycle_history.dart';
import 'package:testapp/backend/models/expense_category_preferences.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/add_expense_screen.dart';
import 'package:testapp/frontend/screens/categories_screen.dart';
import 'package:testapp/frontend/screens/history_screen.dart';
import 'package:testapp/frontend/screens/income_waterfall_screen.dart';
import 'package:testapp/frontend/screens/leftover_review_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/backend/utils/money_format.dart';
import 'package:testapp/backend/utils/categories.dart';
import 'package:testapp/backend/utils/date_format.dart';
import 'package:testapp/frontend/widgets/category_icon.dart';

final _capture = GlobalKey();

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  AppSettingsProvider? settings,
  bool dark = false,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: settings ?? AppSettingsProvider(),
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: _capture, child: child!),
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('PHASE10_CAPTURE')) return;
  await tester.runAsync(
    () => Future.wait([
      for (final category in expenseCategories)
        precacheImage(
          AssetImage(categoryIconAsset(category)),
          _capture.currentContext!,
        ),
    ]),
  );
  await tester.pumpAndSettle();
  final boundary =
      _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/phase10/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

AllocationCycle cycle(String id, DateTime date, {LeftoverDecision? decision}) =>
    AllocationCycle(
      id: id,
      income: 18000,
      toBills: 6000,
      toGoal: 2000,
      remaining: 10000,
      goalName: 'Emergency fund',
      receivedAt: date,
      source: id,
      decision: decision,
      savedAmount: decision == LeftoverDecision.saved ? 3000 : 0,
      spentAmount: decision == LeftoverDecision.spent ? 3000 : 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use SDK fonts so screen captures show real text instead of Ahem boxes.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = packages.firstWhere((p) => p['name'] == 'flutter');
    final rootUri = flutter['rootUri'] as String;
    final root = config.uri.resolve(
      rootUri.endsWith('/') ? rootUri : '$rootUri/',
    );
    final fontRoot = root.resolve('../../bin/cache/artifacts/material_fonts/');
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File.fromUri(
            fontRoot.resolve(entry.value),
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  test('cycle snapshots survive income frequency changes', () {
    final record = AllocationCycle.fromMap('pay', {
      'income': 18000,
      'toBills': 6000,
      'toGoal': 2000,
      'remaining': 10000,
      'receivedAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      'periodStart': Timestamp.fromDate(DateTime(2026, 8, 1)),
      'periodEnd': Timestamp.fromDate(DateTime(2026, 9, 1)),
    });
    expect(record.toBills, 6000);
    expect(record.toGoal, 2000);
    expect(periodOf(record).end, DateTime(2026, 9, 1));
  });

  test('cycle statuses distinguish open, reviewable and resolved periods', () {
    final now = DateTime(2026, 9, 18);
    expect(
      cycleStatus(cycle('new', DateTime(2026, 9, 17)), now),
      CycleStatus.active,
    );
    expect(
      cycleStatus(cycle('last', DateTime(2026, 8, 19)), now),
      CycleStatus.pending,
    );
    expect(
      cycleStatus(cycle('old', DateTime(2026, 7, 1)), now),
      CycleStatus.pending,
    );
    expect(
      cycleStatus(
        cycle('saved', DateTime(2026, 7, 1), decision: LeftoverDecision.saved),
        now,
      ),
      CycleStatus.done,
    );
    expect(
      cycleStatus(
        cycle('spend', DateTime(2026, 7, 1), decision: LeftoverDecision.spent),
        now,
      ),
      CycleStatus.declined,
    );
  });

  test('hiding a category keeps Others and the original labels', () {
    final prefs = ExpenseCategoryPreferences.fromMap({
      // Added before the list was fixed; it still shows and can be hidden.
      'customCategories': ['Pets'],
      'hiddenCategories': ['Food', 'Others'],
    });
    expect(prefs.availableCategories, contains('Others'));
    expect(prefs.availableCategories, isNot(contains('Food')));
    expect(prefs.availableCategories, contains('Pets'));
    expect(prefs.allCategories, contains('Food'));
  });

  test('the eye remembers whether amounts are hidden', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettingsProvider.load(account: 'ana');
    expect(settings.amountsMasked, isFalse);

    settings.toggleAmountsMasked();
    expect(settings.amountsMasked, isTrue);
    expect(
      (await AppSettingsProvider.load(account: 'ana')).amountsMasked,
      isTrue,
    );

    settings.toggleAmountsMasked();
    expect(
      (await AppSettingsProvider.load(account: 'ana')).amountsMasked,
      isFalse,
    );
  });

  group('dark mode and the eye belong to the account', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('signed out, and for a new account, it is light', () async {
      expect((await AppSettingsProvider.load()).themeMode, ThemeMode.light);
      expect(
        (await AppSettingsProvider.load(account: 'new')).themeMode,
        ThemeMode.light,
      );
    });

    test('logging out goes back to light; logging in brings it back', () async {
      final settings = await AppSettingsProvider.load(account: 'ana');
      settings.setThemeMode(ThemeMode.dark);
      settings.toggleAmountsMasked();

      settings.useAccount(null);
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.amountsMasked, isFalse);

      // Another account on the same phone has its own.
      settings.useAccount('ben');
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.amountsMasked, isFalse);

      settings.useAccount('ana');
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.amountsMasked, isTrue);
    });

    test('no account inherits dark mode or hidden amounts', () async {
      // Saved by older builds: for the phone, and copied into an account
      // that never chose it.
      SharedPreferences.setMockInitialValues({
        'themeMode': 'dark',
        'amountsMasked': true,
        'maskByDefault': true,
        'themeMode:ana': 'dark',
        'amountsMasked:ana': true,
      });

      // Signed out, signed in, or brand new: light, with amounts shown.
      final settings = await AppSettingsProvider.load();
      expect(settings.themeMode, ThemeMode.light);
      settings.useAccount('ana');
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.amountsMasked, isFalse);
      settings.useAccount('new');
      expect(settings.themeMode, ThemeMode.light);

      // And none of it is left to be read again.
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isEmpty);
    });

    test('dark only after the account turns it on', () async {
      final settings = await AppSettingsProvider.load(account: 'ana');
      expect(settings.themeMode, ThemeMode.light);
      settings.setThemeMode(ThemeMode.dark);
      expect(
        (await AppSettingsProvider.load(account: 'ana')).themeMode,
        ThemeMode.dark,
      );
    });
  });

  test('category preferences reset when the account changes', () {
    final settings = AppSettingsProvider();
    settings.updateCategoryPreferences({
      // Added on an older build, before the list was fixed.
      'customCategories': ['Hobbies'],
    });
    expect(settings.categories.availableCategories, contains('Hobbies'));
    settings.updateCategoryPreferences(null);
    expect(settings.categories.availableCategories, isNot(contains('Hobbies')));
  });

  for (final dark in [false, true]) {
    testWidgets(
      'history sorts, filters and opens correct pending cycle ($dark)',
      (tester) async {
        AllocationCycle? reviewed;
        double? amount;
        final old = cycle('August salary', DateTime(2026, 8, 1));
        await pumpScreen(
          tester,
          HistoryScreen(
            today: DateTime(2026, 9, 18),
            profile: Stream.value({'incomeFrequency': 'Monthly'}),
            transactions: Stream.value([
              AppTransaction(
                id: 'expense',
                type: TransactionType.expense,
                amount: 1200,
                label: 'Food',
                date: DateTime(2026, 8, 3),
              ),
            ]),
            cycles: Stream.value([
              old,
              cycle('September salary', DateTime(2026, 9, 15)),
            ]),
            onReview: (c, left, _) {
              reviewed = c;
              amount = left;
            },
          ),
          dark: dark,
        );
        expect(find.text('September salary'), findsOneWidget);
        await tester.tap(find.text('Needs review (1)'));
        await tester.pumpAndSettle();
        expect(find.text('September salary'), findsNothing);
        expect(find.text('August salary'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);
        await capture(tester, dark ? 'history-dark' : 'history-light');
        await scrollTo(tester, find.text('Decide what is left'));
        await capture(
          tester,
          dark ? 'history-review-dark' : 'history-review-light',
        );
        await tester.tap(find.text('Decide what is left'));
        expect(reviewed?.id, old.id);
        expect(amount, 8800);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('resolved history uses recorded leftover and respects masking', (
    tester,
  ) async {
    final settings = AppSettingsProvider()..toggleAmountsMasked();
    await pumpScreen(
      tester,
      HistoryScreen(
        profile: Stream.value({'incomeFrequency': 'Monthly'}),
        transactions: Stream.value(const []),
        cycles: Stream.value([
          cycle('July', DateTime(2026, 7, 1), decision: LeftoverDecision.saved),
        ]),
      ),
      settings: settings,
    );
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Decide what is left'), findsNothing);
    expect(find.text(formatPeso(18000)), findsNothing);
    settings.toggleAmountsMasked();
    await tester.pumpAndSettle();
    expect(find.text(formatPeso(3000)), findsWidgets);
  });

  testWidgets('history has distinct empty and failed states', (tester) async {
    await pumpScreen(
      tester,
      HistoryScreen(
        profile: Stream.value({}),
        transactions: Stream.value(const []),
        cycles: Stream.value(const []),
      ),
    );
    expect(find.text('Your story starts with income'), findsOneWidget);
    await pumpScreen(
      tester,
      HistoryScreen(
        key: UniqueKey(),
        profile: Stream.value({}),
        transactions: Stream.value(const []),
        cycles: Stream.error(StateError('offline and uncached')),
      ),
    );
    expect(find.text('History is unavailable'), findsOneWidget);
  });

  testWidgets('hiding a category saves it and adding one is not offered', (
    tester,
  ) async {
    final data = <String, dynamic>{};
    final stream = StreamController<Map<String, dynamic>?>();
    addTearDown(stream.close);
    await tester.pumpWidget(const SizedBox());
    // A seeded async stream exercises the live update after each write.
    final updates = stream.stream;
    Future<void>.microtask(() => stream.add(data));
    await pumpScreen(
      tester,
      CategoriesScreen(
        profile: updates,
        onSave: (values) {
          data.addAll(values);
          stream.add(Map.of(data));
        },
      ),
    );
    await capture(tester, 'categories-light');
    // The list is fixed, so every category keeps its own icon and colour and
    // later auto-categorisation has a set list to predict.
    expect(find.text('Add category'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.ensureVisible(find.text('Food'));
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(data['hiddenCategories'], ['Food']);
  });

  testWidgets('expense picker offers custom categories and omits hidden ones', (
    tester,
  ) async {
    final settings = AppSettingsProvider()
      ..updateCategoryPreferences({
        'customCategories': ['Pets'],
        'hiddenCategories': ['Food'],
      });
    await pumpScreen(
      tester,
      AddExpenseScreen(wallets: Stream.value(const [])),
      settings: settings,
    );
    final dropdown = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsNothing);
    expect(find.text('Pets'), findsWidgets);
  });

  testWidgets('Add Expense reads top to bottom like Add Income', (
    tester,
  ) async {
    await pumpScreen(tester, AddExpenseScreen(wallets: Stream.value(const [])));
    double top(String label) => tester.getTopLeft(find.text(label)).dy;

    // The description comes before the category suggested from it.
    expect(top('Amount'), lessThan(top('Description')));
    expect(top('Description'), lessThan(top('Category')));
    expect(top('Category'), lessThan(top('Date')));
    expect(find.text(formatShortDate(DateTime.now())), findsOneWidget);
    expect(find.byType(CategoryIcon), findsNothing);

    await tester.enterText(
      find.ancestor(
        of: find.text('What did you spend money on?'),
        matching: find.byType(TextField),
      ),
      'date with my girlfriend',
    );
    await tester.pump();
    expect(find.text('Entertainment'), findsOneWidget);
    expect(
      tester.widget<CategoryIcon>(find.byType(CategoryIcon)).category,
      'Entertainment',
      reason: "the field shows the chosen category's own icon",
    );
  });

  testWidgets('an expense can only come out of what a wallet has', (
    tester,
  ) async {
    const cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 6528,
      startingBalance: 6528,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    await pumpScreen(tester, AddExpenseScreen(wallets: Stream.value([cash])));
    await tester.pump();

    Finder field(String hint) =>
        find.ancestor(of: find.text(hint), matching: find.byType(TextField));
    await tester.enterText(field('0.00'), '7000');
    await tester.enterText(field('What did you spend money on?'), 'Groceries');
    await tester.pump();
    // Paid from Cash on Hand: it fills in all it can, ₱6,528, and no more.
    await tester.ensureVisible(find.text('Cash on Hand'));
    await tester.tap(find.text('Cash on Hand'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pay-from-cash')), '7000');
    await tester.pumpAndSettle();
    expect(find.textContaining('Only ₱6,528 in Cash is free'), findsWidgets);

    await tester.ensureVisible(find.text('Save Expense'));
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();
    // Nothing is saved; the form stays, as typed.
    expect(find.byType(AddExpenseScreen), findsOneWidget);
    // The amount, grouped as typed, and the wallet's own box.
    expect(find.text('7,000'), findsWidgets);
  });

  testWidgets('goal money is not spent, and amounts are what is free', (
    tester,
  ) async {
    const cash = Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 10000,
      startingBalance: 10000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    );
    await pumpScreen(
      tester,
      AddExpenseScreen(
        wallets: Stream.value([cash]),
        // ₱2,000 of the cash is set aside for a goal.
        goals: Stream.value(const [
          Goal(
            id: 'grad',
            name: 'Graduation',
            targetAmount: 10000,
            savedAmount: 2000,
            priority: 0,
            status: GoalStatus.active,
            savedByWallet: {'cash': 2000},
          ),
        ]),
      ),
    );
    await tester.pump();

    Finder field(String hint) =>
        find.ancestor(of: find.text(hint), matching: find.byType(TextField));
    await tester.enterText(field('0.00'), '9000');
    await tester.enterText(field('What did you spend money on?'), 'Groceries');
    await tester.pump();

    // The wallet shows what can be spent, not all it holds.
    await tester.ensureVisible(find.text('Cash on Hand'));
    await tester.tap(find.text('Cash on Hand'));
    await tester.pumpAndSettle();
    expect(find.textContaining('₱8,000 available'), findsOneWidget);

    // Less than Cash holds, but more than it has free: refused.
    await tester.enterText(find.byKey(const Key('pay-from-cash')), '9000');
    await tester.pumpAndSettle();
    expect(
      find.text('Only ₱8,000 in Cash is free; goals hold the rest.'),
      findsWidgets,
    );
    await tester.ensureVisible(find.text('Save Expense'));
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();
    expect(find.byType(AddExpenseScreen), findsOneWidget);
  });

  testWidgets('Add Income asks for the source each time', (tester) async {
    await pumpScreen(
      tester,
      IncomeWaterfallScreen(
        wallets: Stream.value(const []),
        loadBills: () async => const [],
        goals: Stream.value(const []),
        cycles: Stream.value(const []),
      ),
    );

    expect(find.text('Salary'), findsNothing);
    // Typed fresh, so a late or partial pay is never saved as the usual one.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });

  testWidgets('leftover review requires a choice and confirmation', (
    tester,
  ) async {
    var writes = 0;
    await pumpScreen(
      tester,
      LeftoverReviewScreen(
        cycle: cycle('Salary', DateTime(2026, 8, 1)),
        leftover: 1000,
        periodEnd: DateTime(2026, 9, 1),
        // A goal to save it toward, and the cash it is in.
        wallets: Stream.value(const [
          Wallet(
            id: 'cash',
            name: 'Cash',
            type: WalletType.cash,
            balance: 5000,
            startingBalance: 5000,
            receivesIncome: true,
            archived: false,
            sortOrder: 0,
          ),
        ]),
        goals: Stream.value(const [
          Goal(
            id: 'trip',
            name: 'Trip',
            targetAmount: 10000,
            savedAmount: 0,
            priority: 0,
            status: GoalStatus.active,
          ),
        ]),
        onResolve: (decision, saved, spent) {
          writes++;
          expect(decision, LeftoverDecision.saved);
          expect(saved, 1000);
          expect(spent, 0);
        },
      ),
    );
    await tester.pump();
    expect(writes, 0);
    await tester.ensureVisible(find.text('Save it'));
    await tester.tap(find.text('Save it'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cash on Hand'));
    await tester.tap(find.text('Cash on Hand'));
    await tester.pumpAndSettle();
    // The wallet's card pushes Confirm further down the list.
    await tester.scrollUntilVisible(
      find.text('Confirm'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Confirm'));
    expect(writes, 1);
  });

  testWidgets('history handles small screens and large text in dark mode', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      HistoryScreen(
        profile: Stream.value({'incomeFrequency': 'Monthly'}),
        transactions: Stream.value(const []),
        cycles: Stream.value([
          cycle('A longer freelance income source', DateTime(2026, 7, 1)),
        ]),
      ),
      dark: true,
      width: 320,
      textScale: 1.5,
    );
    await tester.scrollUntilVisible(find.text('Decide what is left'), 250);
    expect(tester.takeException(), isNull);
  });
}
