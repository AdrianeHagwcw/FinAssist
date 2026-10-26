import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/bill.dart';
import 'package:testapp/models/debt.dart';
import 'package:testapp/models/reminder.dart';
import 'package:testapp/models/transaction_filter.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/debt_detail_screen.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/utils/categories.dart';
import 'package:testapp/widgets/debt_form_sheet.dart';
import 'package:testapp/widgets/transaction_row.dart';

/// Interest on an installment is what the user pays to borrow: spending, in
/// its own category, never income. A ₱24,000 phone paid as 12 × ₱2,400 costs
/// ₱4,800 on top, so ₱400 of every payment is interest.
void main() {
  Debt phone({int paidBefore = 0}) => Debt(
    id: 'd',
    direction: DebtDirection.iOwe,
    name: 'Phone',
    category: DebtCategory.gadget,
    principal: 24000,
    perPayment: 2400,
    paymentCount: 12,
    firstDueDate: DateTime(2026, 1, 25),
    billId: 'b',
    status: DebtStatus.active,
    paidBefore: paidBefore,
  );

  AppTransaction payment(String id, DateTime date, {double interest = 400}) =>
      AppTransaction(
        id: id,
        type: TransactionType.expense,
        amount: 2400,
        label: 'Bills',
        date: date,
        walletId: 'bills',
        note: 'Phone',
        billInstanceId: 'b_$id',
        interest: interest,
      );

  group('the interest in each payment', () {
    test('is the same share of every payment, adding up to the extra', () {
      final debt = phone();
      expect(debt.extraCost, 4800);
      expect(debt.interestShare, closeTo(1 / 6, 1e-9));
      expect(debt.interestOf(1), 400);
      final total = [
        for (var n = 1; n <= debt.paymentCount; n++) debt.interestOf(n),
      ].fold<double>(0, (sum, part) => sum + part);
      expect(total, 4800);
    });

    test('is nothing when only what was borrowed is paid back', () {
      const loan = Debt(
        id: 'l',
        direction: DebtDirection.iOwe,
        name: 'Loan from Tita',
        category: DebtCategory.familyFriend,
        principal: 10000,
        perPayment: 3000,
        paymentCount: 4,
        lastPayment: 1000,
        status: DebtStatus.active,
      );
      expect(loan.interestShare, 0);
      expect(loan.interestOf(1), 0);
    });

    test('follows a part payment, to the centavo', () {
      final due = BillInstance(
        id: 'b_1',
        billId: 'b',
        name: 'Phone',
        amount: 2400,
        category: 'Bills',
        dueDate: DateTime(2026, 2, 25),
        status: BillStatus.unpaid,
        interestShare: phone().interestShare,
      );
      expect(due.interestIn(2400), 400);
      expect(due.interestIn(1000), 166.67);
    });

    test('is read back from the schedule, and nonsense is ignored', () {
      Map<String, dynamic> stored(Object? share) => {
        'name': 'Phone',
        'amount': 2400,
        'firstDueDate': DateTime(2026, 1, 25),
        'recurrence': 'monthly',
        'interestShare': share,
      };
      expect(Bill.fromMap('b', stored(0.25)).interestShare, 0.25);
      expect(Bill.fromMap('b', stored(null)).interestShare, 0);
      expect(Bill.fromMap('b', stored(1.5)).interestShare, 0);
      expect(Bill.fromMap('b', stored('a lot')).interestShare, 0);
    });
  });

  group('in Transactions and Reports', () {
    test('a payment is split, never counted twice', () {
      final paid = AppTransaction.fromMap('p', {
        'type': 'expense',
        'amount': 2400,
        'label': 'Bills',
        'interest': 400,
        'billInstanceId': 'b_1',
      });
      expect(paid.interest, 400);
      expect(paid.spendingParts, [
        isA<MapEntry<String, double>>()
            .having((e) => e.key, 'key', 'Bills')
            .having((e) => e.value, 'value', 2000),
        isA<MapEntry<String, double>>()
            .having((e) => e.key, 'key', interestCategory)
            .having((e) => e.value, 'value', 400),
      ]);

      final lunch = AppTransaction(
        id: 'f',
        type: TransactionType.expense,
        amount: 150,
        label: 'Food',
        date: DateTime(2026, 2, 25),
      );
      final byCategory = Map.fromEntries(spendingByCategory([paid, lunch]));
      expect(byCategory, {'Bills': 2000, 'Interest': 400, 'Food': 150});
      // Spending in all is still what left the wallet.
      expect(byCategory.values.reduce((a, b) => a + b), 2550);
    });

    test('Interest is a category of its own, with its own icon', () {
      expect(expenseCategories, contains(interestCategory));
      expect(
        categoryIconAsset(interestCategory),
        'assets/icons/icons8-cat-interest-96.png',
      );
      expect(categoryColor(interestCategory), isNot(categoryColor('Others')));
    });
  });

  group('the yearly reminder', () {
    List<PlannedReminder> plan({
      required List<AppTransaction> transactions,
      Map<ReminderKind, bool> overrides = const {},
    }) => planReminders(
      settings: ReminderSettings(
        enabled: true,
        priorities: const [],
        overrides: overrides,
      ),
      bills: const [],
      goals: const [],
      cycles: const [],
      transactions: transactions,
      now: DateTime(2026, 10, 26, 10),
    ).where((r) => r.key.startsWith('installment-interest')).toList();

    test('comes on January 1 with the year\'s interest', () {
      final reminders = plan(
        transactions: [
          payment('1', DateTime(2026, 9, 25)),
          payment('2', DateTime(2026, 10, 25)),
          // Last year's is last year's.
          payment('0', DateTime(2025, 12, 25)),
        ],
      );

      final reminder = reminders.single;
      expect(reminder.at, DateTime(2027, 1, 1, morningHour));
      expect(reminder.title, 'Interest you paid in 2026');
      expect(
        reminder.body,
        '₱800 of your Phone payments was interest. Tap to see what it has '
        'cost.',
      );
      expect(reminder.payload, 'installments');
    });

    test('does not come when nothing was interest, or when it is off', () {
      expect(
        plan(transactions: [payment('1', DateTime(2026, 9, 25), interest: 0)]),
        isEmpty,
      );
      expect(
        plan(
          transactions: [payment('1', DateTime(2026, 9, 25))],
          overrides: const {ReminderKind.interest: false},
        ),
        isEmpty,
      );
    });
  });

  test('the name picks the kind', () {
    expect(guessDebtCategory('Phone'), DebtCategory.gadget);
    expect(guessDebtCategory('Samsung A55'), DebtCategory.gadget);
    expect(guessDebtCategory('SSS loan'), DebtCategory.governmentLoan);
    expect(guessDebtCategory('Pag-IBIG'), DebtCategory.governmentLoan);
    expect(guessDebtCategory('BPI credit card'), DebtCategory.creditCard);
    expect(guessDebtCategory('SPayLater'), DebtCategory.buyNowPayLater);
    expect(guessDebtCategory('Tita Baby'), DebtCategory.familyFriend);
    expect(guessDebtCategory('GLoan'), DebtCategory.personalLoan);
    expect(guessDebtCategory('Dental braces'), isNull);
    // A word inside another word is not that word.
    expect(guessDebtCategory('Caterpillar'), isNull);
  });

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
  }

  testWidgets('the form asks only what a plan needs', (tester) async {
    DebtDraft? saved;
    await pump(
      tester,
      Scaffold(
        body: DebtFormSheet(
          today: DateTime(2026, 10, 26),
          wallets: Stream.value([
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
          onSave: (draft) => saved = draft,
        ),
      ),
    );

    // Nothing to read before anything is typed: no summary yet.
    expect(find.text('Borrowed'), findsNothing);
    expect(
      find.text(
        'This only writes down the plan. Your money does not move until '
        'you pay.',
      ),
      findsNothing,
    );
    expect(find.text('Interest (optional)'), findsNothing);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Phone');
    await tester.enterText(fields.at(1), '24000');
    await tester.enterText(fields.at(2), '2400');
    await tester.enterText(fields.at(3), '12');
    await tester.pump();

    expect(find.text('12 payments of ₱2,400, every month'), findsOneWidget);
    expect(find.text('₱400 of each payment is interest.'), findsOneWidget);

    // Payments always come from the Bills wallet: there is nothing to pick.
    await tester.tap(find.text('More options (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Usually paid from'), findsNothing);
    // Interest is there if it was told, counted a year unless changed.
    expect(find.text('Interest (optional)'), findsOneWidget);
    expect(find.text('a year'), findsOneWidget);
    // The kind was picked from the name.
    expect(find.text('Gadget or appliance'), findsOneWidget);

    await tester.enterText(fields.at(0), 'SSS loan');
    await tester.pump();
    expect(find.text('Government loan'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('installment-quoted-rate')),
      '36',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save Installment'));
    await tester.tap(find.text('Save Installment'));
    await tester.pumpAndSettle();

    expect(saved?.category, DebtCategory.governmentLoan);
    expect(saved?.quotedRate, 36);
    expect(saved?.quotedRatePer, RatePeriod.year);
  });

  testWidgets('the installment says how much interest is paid so far', (
    tester,
  ) async {
    final debt = phone(paidBefore: 3);
    await pump(
      tester,
      DebtDetailScreen(
        debt: debt,
        liveDebt: Stream.value(debt),
        payments: Stream.value(const []),
        transactions: Stream.value(const []),
        wallets: Stream.value(const []),
      ),
    );
    await tester.pump();

    expect(
      find.text('₱400 of each payment is interest. Paid so far: ₱1,200.'),
      findsOneWidget,
    );
  });

  testWidgets('History shows the interest inside a payment, or hides it', (
    tester,
  ) async {
    final settings = AppSettingsProvider();
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TransactionRow(
              transaction: payment('1', DateTime(2026, 10, 25)),
              wallets: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Bill payment · ₱400 interest'), findsOneWidget);

    // Hidden amounts stay hidden here too.
    settings.toggleAmountsMasked();
    await tester.pump();
    expect(find.textContaining('₱400'), findsNothing);
    expect(find.textContaining(' interest'), findsOneWidget);
  });

  testWidgets('Other lets the user name the kind; there are no notes', (
    tester,
  ) async {
    DebtDraft? saved;
    await pump(
      tester,
      Scaffold(
        body: DebtFormSheet(
          today: DateTime(2026, 10, 26),
          wallets: Stream.value(const <Wallet>[]),
          onSave: (draft) => saved = draft,
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Dental braces');
    await tester.enterText(fields.at(2), '2000');
    await tester.enterText(fields.at(3), '6');
    await tester.tap(find.text('More options (optional)'));
    await tester.pumpAndSettle();

    expect(find.text('Notes (optional)'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('installment-other-kind')),
      'Dental',
    );
    await tester.ensureVisible(find.text('Save Installment'));
    await tester.tap(find.text('Save Installment'));
    await tester.pumpAndSettle();

    expect(saved?.category, DebtCategory.other);
    expect(saved?.otherKind, 'Dental');
    const debt = Debt(
      id: 'x',
      direction: DebtDirection.iOwe,
      name: 'Dental braces',
      category: DebtCategory.other,
      principal: 12000,
      status: DebtStatus.active,
      otherKind: 'Dental',
    );
    expect(debt.kindLabel, 'Dental');
  });
}
