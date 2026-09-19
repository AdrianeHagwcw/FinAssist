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
import 'package:testapp/models/allocation.dart';
import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/cycle_history.dart';
import 'package:testapp/models/financial_preferences.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/add_expense_screen.dart';
import 'package:testapp/screens/categories_screen.dart';
import 'package:testapp/screens/financial_preferences_screen.dart';
import 'package:testapp/screens/history_screen.dart';
import 'package:testapp/screens/income_waterfall_screen.dart';
import 'package:testapp/screens/leftover_review_screen.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/utils/money_format.dart';
import 'package:testapp/utils/categories.dart';
import 'package:testapp/utils/date_format.dart';
import 'package:testapp/widgets/category_icon.dart';

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
    expect(periodOf(record, 'Weekly').end, DateTime(2026, 9, 1));
  });

  test('cycle statuses distinguish open, reviewable and resolved periods', () {
    final now = DateTime(2026, 9, 18);
    expect(
      cycleStatus(cycle('new', DateTime(2026, 9, 17)), 'Monthly', now),
      CycleStatus.active,
    );
    expect(
      cycleStatus(cycle('last', DateTime(2026, 8, 19)), 'Monthly', now),
      CycleStatus.pending,
    );
    expect(
      cycleStatus(cycle('old', DateTime(2026, 7, 1)), 'Monthly', now),
      CycleStatus.pending,
    );
    expect(
      cycleStatus(
        cycle('saved', DateTime(2026, 7, 1), decision: LeftoverDecision.saved),
        'Monthly',
        now,
      ),
      CycleStatus.done,
    );
    expect(
      cycleStatus(
        cycle('spend', DateTime(2026, 7, 1), decision: LeftoverDecision.spent),
        'Monthly',
        now,
      ),
      CycleStatus.declined,
    );
  });

  test('hiding a category keeps Others and the original labels', () {
    final prefs = FinancialPreferences.fromMap({
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
    final settings = await AppSettingsProvider.load();
    expect(settings.amountsMasked, isFalse);

    settings.toggleAmountsMasked();
    expect(settings.amountsMasked, isTrue);
    expect((await AppSettingsProvider.load()).amountsMasked, isTrue);

    settings.toggleAmountsMasked();
    expect((await AppSettingsProvider.load()).amountsMasked, isFalse);
  });

  test('an older hide-on-launch choice is still honoured', () async {
    SharedPreferences.setMockInitialValues({'maskByDefault': true});
    expect((await AppSettingsProvider.load()).amountsMasked, isTrue);
  });

  test(
    'account preferences reset without carrying categories across accounts',
    () {
      final settings = AppSettingsProvider();
      settings.updateFinancialProfile({
        // Added on an older build, before the list was fixed.
        'customCategories': ['Hobbies'],
        'defaultLeftover': 'saved',
      });
      expect(settings.financial.availableCategories, contains('Hobbies'));
      settings.updateFinancialProfile(null);
      expect(
        settings.financial.availableCategories,
        isNot(contains('Hobbies')),
      );
      expect(settings.financial.leftover, LeftoverDecision.pending);
    },
  );

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
        await scrollTo(tester, find.text('Review leftover'));
        await capture(
          tester,
          dark ? 'history-review-dark' : 'history-review-light',
        );
        await tester.tap(find.text('Review leftover'));
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
    expect(find.text('Review leftover'), findsNothing);
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

  testWidgets('income form validates and saves actual preferences', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await pumpScreen(
      tester,
      FinancialPreferencesScreen(
        profile: Stream.value({
          'incomeSource': 'Allowance',
          'incomeFrequency': 'Weekly',
          'income': 2500,
        }),
        onSave: (values) => saved = values,
      ),
    );
    await capture(tester, 'preferences-light');
    await tester.enterText(find.byKey(const Key('income-source')), 'Freelance');
    await scrollTo(tester, find.byKey(const Key('usual-income')));
    await tester.enterText(find.byKey(const Key('usual-income')), 'NaN');
    await scrollTo(tester, find.text('Save preferences'));
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await scrollTo(tester, find.byKey(const Key('usual-income')), delta: -250);
    expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('usual-income')), '4500.50');
    await scrollTo(tester, find.text('Save it'));
    await tester.tap(find.text('Save it'));
    await scrollTo(tester, find.text('Save preferences'));
    await tester.tap(find.text('Save preferences'));
    expect(saved, {
      'incomeSource': 'Freelance',
      'incomeFrequency': 'Weekly',
      'income': 4500.50,
      'defaultLeftover': 'saved',
    });
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
      ..updateFinancialProfile({
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

  testWidgets('an expense over the wallet balance is asked about first', (
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
    await tester.ensureVisible(find.text('Save Expense'));
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();

    expect(find.text("More than what's in Cash"), findsOneWidget);
    expect(
      find.text(
        'This expense is ₱7,000, but Cash has ₱6,528, so it would show '
        "-₱472. If money came in that isn't logged yet, add it as income "
        'too.',
      ),
      findsOneWidget,
    );

    // Fixing the amount goes back to the form with nothing saved.
    await tester.tap(find.text('Fix Amount'));
    await tester.pumpAndSettle();
    expect(find.text("More than what's in Cash"), findsNothing);
    expect(find.byType(AddExpenseScreen), findsOneWidget);
    expect(find.text('7000'), findsOneWidget);
  });

  testWidgets('Add Income starts with the usual source, never the amount', (
    tester,
  ) async {
    final settings = AppSettingsProvider()
      ..updateFinancialProfile({
        'incomeSource': 'Salary',
        'incomeFrequency': 'Monthly',
        'income': 18000,
      });
    await pumpScreen(
      tester,
      IncomeWaterfallScreen(
        wallets: Stream.value(const []),
        loadBills: () async => const [],
        goals: Stream.value(const []),
        cycles: Stream.value(const []),
      ),
      settings: settings,
    );

    expect(find.text('Salary'), findsOneWidget);
    // Typed fresh, so a late or partial pay is never saved as the usual one.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'leftover default only preselects and still requires confirmation',
    (tester) async {
      var writes = 0;
      await pumpScreen(
        tester,
        LeftoverReviewScreen(
          cycle: cycle('Salary', DateTime(2026, 8, 1)),
          leftover: 1000,
          periodEnd: DateTime(2026, 9, 1),
          initialDecision: LeftoverDecision.saved,
          onResolve: (decision, saved, spent) {
            writes++;
            expect(decision, LeftoverDecision.saved);
            expect(saved, 1000);
            expect(spent, 0);
          },
        ),
      );
      expect(writes, 0);
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      expect(writes, 1);
    },
  );

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
    await tester.scrollUntilVisible(find.text('Review leftover'), 250);
    expect(tester.takeException(), isNull);
  });
}
