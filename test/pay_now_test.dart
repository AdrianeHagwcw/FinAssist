import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/reminder.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/debt_detail_screen.dart';
import 'package:testapp/frontend/theme/app_buttons.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/due_soon_notice.dart';
import 'package:testapp/frontend/widgets/debt_payment_flow.dart';
import 'package:testapp/frontend/widgets/safe_to_spend_card.dart';

/// A phone bought on installment: ₱48,000 in 12 payments of ₱4,000, charged
/// to Cash, the first falling due on Jun 10, 2026.
Debt installment({int paidBefore = 0, DateTime? firstDue}) => Debt(
  id: 'phone',
  direction: DebtDirection.iOwe,
  name: 'iPhone 15',
  category: DebtCategory.gadget,
  principal: 48000,
  perPayment: 4000,
  paymentCount: 12,
  firstDueDate: firstDue ?? DateTime(2026, 6, 10),
  billId: 'bill',
  paidWithWalletId: 'cash',
  paidWithLabel: 'Cash',
  paidBefore: paidBefore,
  status: DebtStatus.active,
);

/// Juan's plan: ₱20,000 back as 12 payments of ₱2,000, first due Jun 5,
/// 2026, five of them paid before it was tracked. Loans name a wallet when
/// the form is given one; older records may have none.
Debt loan({
  String? paidWithWalletId,
  int paidBefore = 5,
  PaymentFrequency frequency = PaymentFrequency.monthly,
  DateTime? firstDue,
}) => Debt(
  id: 'juan',
  direction: DebtDirection.iOwe,
  name: 'Personal loan',
  category: DebtCategory.personalLoan,
  principal: 20000,
  perPayment: 2000,
  paymentCount: 12,
  frequency: frequency,
  firstDueDate: firstDue ?? DateTime(2026, 6, 5),
  billId: 'loan-bill',
  paidBefore: paidBefore,
  paidWithWalletId: paidWithWalletId,
  paidWithLabel: paidWithWalletId == null ? null : 'Cash',
  status: DebtStatus.active,
);

BillInstance occurrence(
  DateTime due, {
  double amount = 4000,
  double paid = 0,
  BillStatus status = BillStatus.unpaid,
}) => BillInstance(
  id: 'i${due.year}-${due.month}',
  billId: 'bill',
  name: 'iPhone 15',
  amount: amount,
  category: 'Bills',
  dueDate: due,
  status: status,
  amountPaid: paid,
  debtId: 'phone',
);

const cash = Wallet(
  id: 'cash',
  name: 'Cash',
  type: WalletType.cash,
  balance: 20000,
  startingBalance: 20000,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

Widget detail({
  required Debt debt,
  List<BillInstance> payments = const [],
  required DateTime today,
  Key? key,
}) => InstallmentDetailScreen(
  key: key,
  debt: debt,
  liveDebt: Stream.value(debt),
  payments: Stream.value(payments),
  wallets: Stream.value(const [cash]),
  today: today,
);

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
  await tester.pumpAndSettle();
}

Color? fillOf(WidgetTester tester, Key key) => tester
    .widget<ElevatedButton>(find.byKey(key))
    .style
    ?.backgroundColor
    ?.resolve(const <WidgetState>{});

void main() {
  group('Pay Now', () {
    testWidgets('is on the page whatever the day, and says what it takes', (
      tester,
    ) async {
      // The day before it falls due: still there, naming the payment.
      await pump(
        tester,
        detail(debt: installment(), today: DateTime(2026, 6, 9)),
      );
      expect(find.byKey(const Key('pay-now')), findsOneWidget);
      expect(
        find.text(
          'Payment 1 of 12 is due tomorrow. Pay it from the wallet you want.',
        ),
        findsOneWidget,
      );

      // The day itself: this is the day's due.
      await pump(
        tester,
        detail(debt: installment(), today: DateTime(2026, 6, 10)),
      );
      expect(find.byKey(const Key('pay-now')), findsOneWidget);
      expect(
        find.text(
          'Payment 1 of 12 is due today. Pay it from the wallet you want.',
        ),
        findsOneWidget,
      );

      // And when it was missed, it is still what has to be paid first.
      await pump(
        tester,
        detail(debt: installment(), today: DateTime(2026, 6, 20)),
      );
      expect(find.byKey(const Key('pay-now')), findsOneWidget);
      expect(
        find.text(
          'Payment 1 of 12 is 10 days overdue. Pay it from the wallet you '
          'want.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('is green, and stands above paying in advance', (tester) async {
      // June's payment is made, so paying ahead is offered for what comes
      // after it — and Pay Now stays above it.
      await pump(
        tester,
        detail(
          debt: installment(),
          payments: [
            occurrence(
              DateTime(2026, 6, 10),
              paid: 4000,
              status: BillStatus.paid,
            ),
            occurrence(DateTime(2026, 7, 10)),
          ],
          today: DateTime(2026, 6, 15),
        ),
      );

      expect(find.byKey(const Key('pay-now')), findsOneWidget);
      expect(find.byKey(const Key('advance-open')), findsOneWidget);

      // Green, the way adding an installment commits, where opening
      // something is blue.
      expect(fillOf(tester, const Key('pay-now')), appConfirmGreen);
      expect(fillOf(tester, const Key('advance-open')), appPrimaryBlue);

      final payNow = tester.getTopLeft(find.byKey(const Key('pay-now'))).dy;
      final advance = tester
          .getTopLeft(find.byKey(const Key('advance-open')))
          .dy;
      expect(payNow, lessThan(advance));

      // Paying records the payment in the Bill Planner itself, so there is
      // no button taking you there to pay anymore.
      expect(find.text('Pay in Bill Planner'), findsNothing);
    });

    testWidgets('says the due is paid, and pressing it again says so', (
      tester,
    ) async {
      final screen = detail(
        debt: installment(),
        payments: [
          occurrence(
            DateTime(2026, 6, 10),
            paid: 4000,
            status: BillStatus.paid,
          ),
          occurrence(DateTime(2026, 7, 10)),
        ],
        today: DateTime(2026, 6, 15),
      );
      await pump(tester, screen);

      // The state sits under the button as well as being there to press.
      expect(
        find.text(
          'This month\'s due is paid. What comes next can be paid ahead '
          'of its date.',
        ),
        findsOneWidget,
      );

      // Pressing it anyway does not open the payment sheet: a small screen
      // comes up saying what is already done, with the way on to paying
      // ahead on it.
      await tester.tap(find.byKey(const Key('pay-now')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini-notice')), findsOneWidget);
      expect(find.text('This month\'s due is already paid'), findsOneWidget);
      expect(
        find.text(
          'To pay what comes next ahead of its date, tap Pay in advance.',
        ),
        findsOneWidget,
      );
      // The one button goes on to paying ahead; the way out is the arrow
      // at the upper left, not another button.
      expect(find.byKey(const Key('mini-notice-action')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('mini-notice')),
          matching: find.text('Pay in advance'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mini-notice-back')), findsOneWidget);
      // The screen behind still offers paying ahead on its own.
      expect(find.byKey(const Key('advance-open')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mini-notice-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini-notice')), findsNothing);
    });

    testWidgets('says so when the plan has nothing for this month', (
      tester,
    ) async {
      await pump(
        tester,
        detail(
          debt: installment(firstDue: DateTime(2026, 12, 10)),
          today: DateTime(2026, 11, 2),
        ),
      );

      expect(find.byKey(const Key('pay-now')), findsOneWidget);
      expect(find.text('Nothing falls due this month.'), findsOneWidget);
      // What waits belongs to December, so paying ahead is how it is taken.
      expect(find.byKey(const Key('advance-open')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pay-now')));
      await tester.pumpAndSettle();

      // The small screen says so, and when the payment does fall due.
      expect(find.byKey(const Key('mini-notice')), findsOneWidget);
      expect(find.text('Nothing to pay this month'), findsOneWidget);
      expect(
        find.text('Payment 1 of 12 falls due on Dec 10, 2026.'),
        findsOneWidget,
      );
      // No button here: only the arrow leaves. Its label is a tooltip,
      // not text on the screen.
      expect(find.byKey(const Key('mini-notice-action')), findsNothing);

      await tester.tap(find.byKey(const Key('mini-notice-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini-notice')), findsNothing);
      // The note under the button still stands.
      expect(find.text('Nothing falls due this month.'), findsOneWidget);
    });

    testWidgets('is gone once there is nothing left to pay', (tester) async {
      // Every payment of the plan was made before it was tracked.
      await pump(
        tester,
        detail(debt: installment(paidBefore: 12), today: DateTime(2026, 6, 10)),
      );

      expect(find.byKey(const Key('pay-now')), findsNothing);
      expect(find.byKey(const Key('advance-open')), findsNothing);
      expect(find.text('Pay in Bill Planner'), findsNothing);
    });

    testWidgets('a loan pays its own due the same way', (tester) async {
      await pump(tester, detail(debt: loan(), today: DateTime(2026, 11, 2)));

      expect(find.byKey(const Key('pay-now')), findsOneWidget);
      expect(fillOf(tester, const Key('pay-now')), appConfirmGreen);
      expect(
        find.text(
          'Payment 6 of 12 is due in 3 days. Pay it from the wallet you '
          'want.',
        ),
        findsOneWidget,
      );
      // This month's due is still owed, so paying ahead waits, and the
      // button that used to pay it off early is gone from the page.
      expect(find.byKey(const Key('advance-open')), findsNothing);
      expect(find.byKey(const Key('payoff-open')), findsNothing);
    });

    testWidgets('a loan pays ahead from its wallet like an installment', (
      tester,
    ) async {
      await pump(
        tester,
        detail(
          debt: loan(paidWithWalletId: 'cash'),
          payments: [
            for (var month = 6; month <= 11; month++)
              BillInstance(
                id: 'i2026-$month',
                billId: 'loan-bill',
                name: 'Personal loan',
                amount: 2000,
                category: 'Bills',
                dueDate: DateTime(2026, month, 5),
                status: BillStatus.paid,
                amountPaid: 2000,
                debtId: 'juan',
              ),
          ],
          today: DateTime(2026, 11, 20),
        ),
      );

      // November's due is settled; December's may be paid ahead, from the
      // wallet the loan named at setup.
      expect(find.byKey(const Key('advance-open')), findsOneWidget);
      expect(find.byKey(const Key('payoff-open')), findsNothing);
      expect(
        find.text(
          'This month\'s due is paid. What comes next can be paid ahead '
          'of its date.',
        ),
        findsOneWidget,
      );
    });
  });

  group('the due-soon notice on Home', () {
    BillInstance dueToday() => BillInstance(
      id: 'inst',
      billId: 'bill',
      name: 'iPhone 15',
      amount: 4000,
      category: 'Bills',
      dueDate: DateTime(2026, 6, 10),
      status: BillStatus.unpaid,
      debtId: 'phone',
    );

    BillInstance paid() => BillInstance(
      id: 'inst',
      billId: 'bill',
      name: 'iPhone 15',
      amount: 4000,
      category: 'Bills',
      dueDate: DateTime(2026, 6, 10),
      status: BillStatus.paid,
      amountPaid: 4000,
      debtId: 'phone',
    );

    test('drops a bill the moment its payment is recorded', () {
      final now = DateTime(2026, 6, 10, 9);

      expect(billsDueSoon([dueToday()], now: now), hasLength(1));
      // Nothing left to remind about: it is settled.
      expect(billsDueSoon([paid()], now: now), isEmpty);
    });

    testWidgets('stays while the payment has not been made, and goes once '
        'it has', (tester) async {
      final today = DateTime(2026, 6, 10, 9);
      final transactions = StreamController<List<AppTransaction>>();
      addTearDown(transactions.close);
      var outstanding = [dueToday()];

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SafeToSpendCard(
                today: today,
                showFigure: false,
                wallets: Stream.value(const [cash]),
                transactions: transactions.stream,
                goals: Stream.value(const []),
                billSchedules: Stream.value(const []),
                loadBills: () async => outstanding,
                belowCard: (context, inputs) => DueSoonNotice(
                  bills: inputs.bills,
                  now: inputs.now ?? today,
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      // The bills are read once there are transactions to read them with.
      transactions.add(const []);
      await tester.pumpAndSettle();

      // Before anything is clicked, the reminder is there.
      expect(find.text('Bills due soon'), findsOneWidget);
      expect(find.text('iPhone 15'), findsOneWidget);

      // Pay Now records the payment: the money leaves the wallet and the
      // bill is settled, which is what Home reads again.
      final payment = AppTransaction(
        id: 'p1',
        type: TransactionType.expense,
        amount: 4000,
        label: 'Bills',
        date: today,
        walletId: 'cash',
        note: 'iPhone 15',
        billInstanceId: 'inst',
        installmentPayment: true,
      );
      outstanding = [paid()];
      transactions.add([payment]);
      await tester.pumpAndSettle();

      expect(find.text('Bills due soon'), findsNothing);
      expect(find.text('iPhone 15'), findsNothing);
    });
  });

  group('paying ahead', () {
    test('a loan may pay ahead once it names a wallet, just like an '
        'installment', () {
      // Eleven of twelve paid: December's payment is what waits, and
      // November's due is already out of the way.
      final named = PayNowState.read(
        loan(paidWithWalletId: 'cash', paidBefore: 11),
        const [],
        DateTime(2026, 11, 20),
      );
      expect(named.canPayAhead, isTrue);

      // The same loan without a wallet stays on the schedule.
      final unnamed = PayNowState.read(
        loan(paidBefore: 11),
        const [],
        DateTime(2026, 11, 20),
      );
      expect(unnamed.canPayAhead, isFalse);
    });

    test('this month\'s due still comes before paying ahead', () {
      final state = PayNowState.read(
        loan(paidWithWalletId: 'cash'),
        const [],
        DateTime(2026, 11, 2),
      );
      expect(state.dueNow, isTrue);
      expect(state.canPayAhead, isFalse);
    });
  });

  group('payment periods', () {
    ({DateTime start, DateTime end}) period(
      PaymentFrequency frequency,
      DateTime today, {
      DateTime? firstDue,
      List<BillInstance> instances = const [],
    }) => paymentPeriod(
      loan(frequency: frequency, firstDue: firstDue),
      instances,
      today,
    );

    test('daily is the day itself', () {
      final p = period(PaymentFrequency.daily, DateTime(2026, 11, 8));
      expect(p.start, DateTime(2026, 11, 8));
      expect(p.end, DateTime(2026, 11, 9));
    });

    test('weekly runs Monday to Sunday', () {
      // Nov 8, 2026 is a Sunday: its week began Monday the 2nd.
      final p = period(PaymentFrequency.weekly, DateTime(2026, 11, 8));
      expect(p.start, DateTime(2026, 11, 2));
      expect(p.end, DateTime(2026, 11, 9));
    });

    test('fortnightly is a 14-day block from the first due date', () {
      final p = period(
        PaymentFrequency.fortnightly,
        DateTime(2026, 11, 8),
        firstDue: DateTime(2026, 6, 5),
      );
      expect(p.start, DateTime(2026, 11, 6));
      expect(p.end, DateTime(2026, 11, 20));
    });

    test('fortnightly falls back to the earliest payment when the plan has '
        'no start date', () {
      final plan = Debt(
        id: 'no-start',
        direction: DebtDirection.iOwe,
        name: 'Personal loan',
        category: DebtCategory.personalLoan,
        principal: 2000,
        perPayment: 1000,
        paymentCount: 2,
        frequency: PaymentFrequency.fortnightly,
        billId: 'loan-bill',
        status: DebtStatus.active,
      );
      final p = paymentPeriod(plan, [
        BillInstance(
          id: 'b',
          billId: 'loan-bill',
          name: 'Personal loan',
          amount: 1000,
          category: 'Bills',
          dueDate: DateTime(2026, 11, 20),
          status: BillStatus.unpaid,
          debtId: 'no-start',
        ),
        BillInstance(
          id: 'a',
          billId: 'loan-bill',
          name: 'Personal loan',
          amount: 1000,
          category: 'Bills',
          dueDate: DateTime(2026, 11, 1),
          status: BillStatus.unpaid,
          debtId: 'no-start',
        ),
      ], DateTime(2026, 11, 8));
      expect(p.start, DateTime(2026, 11, 1));
      expect(p.end, DateTime(2026, 11, 15));
    });

    test('semi-monthly is the half of the month', () {
      final first = period(PaymentFrequency.semiMonthly, DateTime(2026, 11, 8));
      expect(first.start, DateTime(2026, 11, 1));
      expect(first.end, DateTime(2026, 11, 16));

      final second = period(
        PaymentFrequency.semiMonthly,
        DateTime(2026, 11, 20),
      );
      expect(second.start, DateTime(2026, 11, 16));
      expect(second.end, DateTime(2026, 12, 1));
    });

    test('monthly is the calendar month, unchanged', () {
      final p = period(PaymentFrequency.monthly, DateTime(2026, 11, 8));
      expect(p.start, DateTime(2026, 11, 1));
      expect(p.end, DateTime(2026, 12, 1));
    });

    test('quarterly is the calendar quarter', () {
      final p = period(PaymentFrequency.quarterly, DateTime(2026, 11, 8));
      expect(p.start, DateTime(2026, 10, 1));
      expect(p.end, DateTime(2027, 1, 1));
    });

    test('semi-annually is the half of the year', () {
      final second = period(PaymentFrequency.semiAnnual, DateTime(2026, 11, 8));
      expect(second.start, DateTime(2026, 7, 1));
      expect(second.end, DateTime(2027, 1, 1));

      final first = period(PaymentFrequency.semiAnnual, DateTime(2026, 3, 8));
      expect(first.start, DateTime(2026, 1, 1));
      expect(first.end, DateTime(2026, 7, 1));
    });

    test('annually is the calendar year', () {
      final p = period(PaymentFrequency.annually, DateTime(2026, 11, 8));
      expect(p.start, DateTime(2026, 1, 1));
      expect(p.end, DateTime(2027, 1, 1));
    });
  });

  group('paying by the chosen frequency', () {
    PayNowState read(
      PaymentFrequency frequency,
      DateTime firstDue,
      int paidBefore,
      DateTime today,
    ) => PayNowState.read(
      loan(
        frequency: frequency,
        firstDue: firstDue,
        paidBefore: paidBefore,
        paidWithWalletId: 'cash',
      ),
      const [],
      today,
    );

    test('daily takes today\'s payment, and today\'s alone', () {
      // Payment 8 falls due on the 8th: it is the day's due.
      final due = read(
        PaymentFrequency.daily,
        DateTime(2026, 11, 1),
        7,
        DateTime(2026, 11, 8),
      );
      expect(due.next?.number, 8);
      expect(due.dueNow, isTrue);
      expect(due.canPayAhead, isFalse);
      expect(due.advance, isNull);

      // Once it is paid, the 9th is next — even though it is still the same
      // month, which the old month-based rule would have held back.
      final next = read(
        PaymentFrequency.daily,
        DateTime(2026, 11, 1),
        8,
        DateTime(2026, 11, 8),
      );
      expect(next.next?.number, 9);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
      expect(next.advance?.number, 9);
    });

    test('daily still puts an overdue payment first', () {
      final state = read(
        PaymentFrequency.daily,
        DateTime(2026, 11, 1),
        6,
        DateTime(2026, 11, 8),
      );
      expect(state.next?.number, 7);
      expect(state.dueNow, isTrue);
      expect(state.canPayAhead, isFalse);
      expect(state.advance, isNull);
    });

    test('weekly takes this week\'s payment, then offers next week', () {
      final due = read(
        PaymentFrequency.weekly,
        DateTime(2026, 11, 2),
        0,
        DateTime(2026, 11, 8),
      );
      expect(due.next?.number, 1);
      expect(due.dueNow, isTrue);
      expect(due.canPayAhead, isFalse);

      final next = read(
        PaymentFrequency.weekly,
        DateTime(2026, 11, 2),
        1,
        DateTime(2026, 11, 8),
      );
      expect(next.next?.number, 2);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
    });

    test('fortnightly takes the payment in its two-week block', () {
      final due = read(
        PaymentFrequency.fortnightly,
        DateTime(2026, 10, 26),
        0,
        DateTime(2026, 11, 8),
      );
      expect(due.next?.number, 1);
      expect(due.dueNow, isTrue);

      final next = read(
        PaymentFrequency.fortnightly,
        DateTime(2026, 10, 26),
        1,
        DateTime(2026, 11, 8),
      );
      expect(next.next?.number, 2);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
    });

    test('semi-monthly takes the payment in this half of the month', () {
      final due = read(
        PaymentFrequency.semiMonthly,
        DateTime(2026, 11, 1),
        0,
        DateTime(2026, 11, 8),
      );
      expect(due.next?.number, 1);
      expect(due.dueNow, isTrue);

      final next = read(
        PaymentFrequency.semiMonthly,
        DateTime(2026, 11, 1),
        1,
        DateTime(2026, 11, 8),
      );
      expect(next.next?.number, 2);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
    });

    test('monthly keeps the month it always had', () {
      final due = read(
        PaymentFrequency.monthly,
        DateTime(2026, 11, 10),
        0,
        DateTime(2026, 11, 2),
      );
      expect(due.next?.number, 1);
      expect(due.dueNow, isTrue);
      expect(due.byMonth, isTrue);

      final next = read(
        PaymentFrequency.monthly,
        DateTime(2026, 11, 10),
        1,
        DateTime(2026, 11, 2),
      );
      expect(next.next?.number, 2);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
    });

    test('quarterly takes the payment in this quarter', () {
      final due = read(
        PaymentFrequency.quarterly,
        DateTime(2026, 10, 1),
        0,
        DateTime(2026, 11, 8),
      );
      expect(due.next?.number, 1);
      expect(due.dueNow, isTrue);

      final next = read(
        PaymentFrequency.quarterly,
        DateTime(2026, 10, 1),
        1,
        DateTime(2026, 11, 8),
      );
      expect(next.next?.number, 2);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
    });

    test('semi-annually takes the payment in this half of the year', () {
      final due = read(
        PaymentFrequency.semiAnnual,
        DateTime(2026, 7, 1),
        0,
        DateTime(2026, 11, 8),
      );
      expect(due.next?.number, 1);
      expect(due.dueNow, isTrue);

      final next = read(
        PaymentFrequency.semiAnnual,
        DateTime(2026, 7, 1),
        1,
        DateTime(2026, 11, 8),
      );
      expect(next.next?.number, 2);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
    });

    test('annually takes the payment in this year', () {
      final due = read(
        PaymentFrequency.annually,
        DateTime(2026, 1, 1),
        0,
        DateTime(2026, 11, 8),
      );
      expect(due.next?.number, 1);
      expect(due.dueNow, isTrue);

      final next = read(
        PaymentFrequency.annually,
        DateTime(2026, 1, 1),
        1,
        DateTime(2026, 11, 8),
      );
      expect(next.next?.number, 2);
      expect(next.dueNow, isFalse);
      expect(next.canPayAhead, isTrue);
    });

    test('every frequency has a period word', () {
      expect(
        read(
          PaymentFrequency.daily,
          DateTime(2026, 11, 1),
          8,
          DateTime(2026, 11, 8),
        ).periodWord,
        'today',
      );
      expect(
        read(
          PaymentFrequency.weekly,
          DateTime(2026, 11, 2),
          1,
          DateTime(2026, 11, 8),
        ).periodWord,
        'this week',
      );
      expect(
        read(
          PaymentFrequency.fortnightly,
          DateTime(2026, 10, 26),
          1,
          DateTime(2026, 11, 8),
        ).periodWord,
        'in these two weeks',
      );
      expect(
        read(
          PaymentFrequency.semiMonthly,
          DateTime(2026, 11, 1),
          1,
          DateTime(2026, 11, 8),
        ).periodWord,
        'this half of the month',
      );
      expect(
        read(
          PaymentFrequency.monthly,
          DateTime(2026, 11, 10),
          1,
          DateTime(2026, 11, 2),
        ).periodWord,
        'this month',
      );
      expect(
        read(
          PaymentFrequency.quarterly,
          DateTime(2026, 10, 1),
          1,
          DateTime(2026, 11, 8),
        ).periodWord,
        'this quarter',
      );
      expect(
        read(
          PaymentFrequency.semiAnnual,
          DateTime(2026, 7, 1),
          1,
          DateTime(2026, 11, 8),
        ).periodWord,
        'this half of the year',
      );
      expect(
        read(
          PaymentFrequency.annually,
          DateTime(2026, 1, 1),
          1,
          DateTime(2026, 11, 8),
        ).periodWord,
        'this year',
      );
    });
  });

  group('the Pay Now note by frequency', () {
    testWidgets('a non-monthly plan says nothing is due its own period and '
        'still offers paying ahead', (tester) async {
      final cases = <(PaymentFrequency, DateTime, int, String)>[
        (
          PaymentFrequency.daily,
          DateTime(2026, 11, 1),
          8,
          'Nothing is due today. What comes next can be paid ahead of its '
              'date.',
        ),
        (
          PaymentFrequency.weekly,
          DateTime(2026, 11, 2),
          1,
          'Nothing is due this week. What comes next can be paid ahead of '
              'its date.',
        ),
        (
          PaymentFrequency.fortnightly,
          DateTime(2026, 10, 26),
          1,
          'Nothing is due in these two weeks. What comes next can be paid '
              'ahead of its date.',
        ),
        (
          PaymentFrequency.semiMonthly,
          DateTime(2026, 11, 1),
          1,
          'Nothing is due this half of the month. What comes next can be '
              'paid ahead of its date.',
        ),
        (
          PaymentFrequency.quarterly,
          DateTime(2026, 10, 1),
          1,
          'Nothing is due this quarter. What comes next can be paid ahead '
              'of its date.',
        ),
        (
          PaymentFrequency.semiAnnual,
          DateTime(2026, 7, 1),
          1,
          'Nothing is due this half of the year. What comes next can be '
              'paid ahead of its date.',
        ),
        (
          PaymentFrequency.annually,
          DateTime(2026, 1, 1),
          1,
          'Nothing is due this year. What comes next can be paid ahead of '
              'its date.',
        ),
      ];

      for (final (frequency, firstDue, paidBefore, note) in cases) {
        await pump(
          tester,
          detail(
            key: ValueKey(frequency),
            debt: loan(
              frequency: frequency,
              firstDue: firstDue,
              paidBefore: paidBefore,
              paidWithWalletId: 'cash',
            ),
            today: DateTime(2026, 11, 8),
          ),
        );
        expect(find.text(note), findsOneWidget, reason: frequency.name);
        expect(
          find.byKey(const Key('advance-open')),
          findsOneWidget,
          reason: frequency.name,
        );
      }
    });

    testWidgets('a due or overdue payment comes first whatever the frequency', (
      tester,
    ) async {
      final cases = <(PaymentFrequency, DateTime, int, String)>[
        (
          PaymentFrequency.daily,
          DateTime(2026, 11, 1),
          6,
          'Payment 7 of 12 is 1 day overdue. Pay it from the wallet you want.',
        ),
        (
          PaymentFrequency.weekly,
          DateTime(2026, 11, 2),
          0,
          'Payment 1 of 12 is 6 days overdue. Pay it from the wallet you '
              'want.',
        ),
        (
          PaymentFrequency.fortnightly,
          DateTime(2026, 10, 26),
          0,
          'Payment 1 of 12 is 13 days overdue. Pay it from the wallet you '
              'want.',
        ),
        (
          PaymentFrequency.semiMonthly,
          DateTime(2026, 11, 1),
          0,
          'Payment 1 of 12 is 7 days overdue. Pay it from the wallet you '
              'want.',
        ),
        (
          PaymentFrequency.quarterly,
          DateTime(2026, 10, 1),
          0,
          'Payment 1 of 12 is 38 days overdue. Pay it from the wallet you '
              'want.',
        ),
        (
          PaymentFrequency.semiAnnual,
          DateTime(2026, 7, 1),
          0,
          'Payment 1 of 12 is 130 days overdue. Pay it from the wallet you '
              'want.',
        ),
        (
          PaymentFrequency.annually,
          DateTime(2026, 1, 1),
          0,
          'Payment 1 of 12 is 311 days overdue. Pay it from the wallet you '
              'want.',
        ),
      ];

      for (final (frequency, firstDue, paidBefore, note) in cases) {
        await pump(
          tester,
          detail(
            key: ValueKey(frequency),
            debt: loan(
              frequency: frequency,
              firstDue: firstDue,
              paidBefore: paidBefore,
              paidWithWalletId: 'cash',
            ),
            today: DateTime(2026, 11, 8),
          ),
        );
        expect(find.byKey(const Key('pay-now')), findsOneWidget);
        expect(find.text(note), findsOneWidget, reason: frequency.name);
        expect(
          find.byKey(const Key('advance-open')),
          findsNothing,
          reason: frequency.name,
        );
      }
    });

    testWidgets('monthly keeps its own wording', (tester) async {
      await pump(
        tester,
        detail(
          debt: loan(
            firstDue: DateTime(2026, 11, 10),
            paidBefore: 1,
            paidWithWalletId: 'cash',
          ),
          today: DateTime(2026, 11, 2),
        ),
      );
      expect(
        find.text(
          'This month\'s due is paid. What comes next can be paid ahead '
          'of its date.',
        ),
        findsOneWidget,
      );
    });
  });
}
