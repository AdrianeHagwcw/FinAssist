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
/// 2026, five of them paid before it was tracked. Loans are never given a
/// wallet of their own.
Debt loan() => Debt(
  id: 'juan',
  direction: DebtDirection.iOwe,
  name: 'Personal loan',
  category: DebtCategory.personalLoan,
  principal: 20000,
  perPayment: 2000,
  paymentCount: 12,
  firstDueDate: DateTime(2026, 6, 5),
  billId: 'loan-bill',
  paidBefore: 5,
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
}) => InstallmentDetailScreen(
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
      // A loan keeps its own way of finishing early beside it, and has no
      // wallet named, so nothing is offered ahead of the schedule.
      expect(find.byKey(const Key('payoff-open')), findsOneWidget);
      expect(find.byKey(const Key('advance-open')), findsNothing);
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
}
