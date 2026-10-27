import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/models/bill.dart';
import 'package:testapp/models/debt.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/debt_detail_screen.dart';
import 'package:testapp/services/bill_service.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/widgets/payoff_sheet.dart';

/// Juan borrowed ₱20,000 to pay back as 12 payments of ₱2,000: ₱24,000 in
/// all, ₱4,000 of it interest. 5 are paid.
Debt loan({DateTime? paidOffAt, double paidOffAmount = 0}) => Debt(
  id: 'juan',
  direction: DebtDirection.iOwe,
  name: 'Personal loan',
  category: DebtCategory.personalLoan,
  principal: 20000,
  perPayment: 2000,
  paymentCount: 12,
  firstDueDate: DateTime(2026, 6, 5),
  billId: 'bill',
  paidBefore: 5,
  status: paidOffAt == null ? DebtStatus.active : DebtStatus.settled,
  paidOffAt: paidOffAt,
  paidOffAmount: paidOffAmount,
);

final payoff = BillInstance(
  id: BillService.payoffInstanceId('bill'),
  billId: 'bill',
  name: 'Personal loan (paid off early)',
  amount: 13500,
  category: 'Bills',
  dueDate: DateTime(2026, 10, 28),
  status: BillStatus.paid,
  amountPaid: 13500,
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

void main() {
  group('the math', () {
    test('what is still owed of the loan, and the interest in a payoff', () {
      // 5 × ₱2,000 paid; each payment is 5/6 loan, 1/6 interest.
      expect(loan().loanLeft(10000), closeTo(11666.67, 0.001));

      final split = loan().payoffSplit(13500, 10000);
      expect(split.toLoan, closeTo(11666.67, 0.001));
      expect(split.interest, closeTo(1833.33, 0.001));
    });

    test('paying less than is owed is a discount, with no interest', () {
      final split = loan().payoffSplit(11000, 10000);
      expect(split.toLoan, 11000);
      expect(split.interest, 0);
    });

    test('once paid off early, nothing is left and no payment is due', () {
      final progress = DebtProgress.of(
        loan(paidOffAt: DateTime(2026, 10, 28), paidOffAmount: 13500),
        [payoff],
      );
      expect(progress.paid, 23500);
      expect(progress.remaining, 0);
      expect(progress.paymentsLeft, 0);
      expect(progress.isPaidOff, isTrue);
    });
  });

  testWidgets('pays it off from a wallet, after asking', (tester) async {
    List<double>? paid;
    DateTime? on;
    await pump(
      tester,
      Scaffold(
        body: PayoffSheet(
          debt: loan(),
          progress: DebtProgress.of(loan(), const []),
          today: DateTime(2026, 10, 28),
          wallets: Stream.value(const [cash]),
          goals: Stream.value(const []),
          onPayOff: (parts, date) {
            paid = [for (final part in parts) part.amount];
            on = date;
          },
        ),
      ),
    );

    // It starts on the ₱14,000 left on the plan.
    expect(find.text('14,000'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('payoff-amount')), '13500');
    await tester.pump();
    expect(
      find.text(
        'Of this, ₱11,666.67 finishes paying what you borrowed, and '
        '₱1,833.33 is interest or a fee for paying early.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cash on Hand'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payoff-button')));
    await tester.pumpAndSettle();
    expect(find.text('Mark Personal loan as fully paid?'), findsOneWidget);
    expect(
      find.textContaining('the 7 payments left are taken off the Bill Planner'),
      findsOneWidget,
    );

    await tester.tap(find.text('Mark as paid'));
    await tester.pumpAndSettle();
    expect(paid, [13500]);
    expect(on, DateTime(2026, 10, 28));
  });

  testWidgets('a discount says so', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: PayoffSheet(
          debt: loan(),
          progress: DebtProgress.of(loan(), const []),
          today: DateTime(2026, 10, 28),
          wallets: Stream.value(const [cash]),
          goals: Stream.value(const []),
          onPayOff: (_, _) {},
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('payoff-amount')), '11000');
    await tester.pump();
    expect(
      find.textContaining('₱666.67 less than what you still owe on it'),
      findsOneWidget,
    );
  });

  Widget detail(Debt debt, List<BillInstance> payments) => DebtDetailScreen(
    debt: debt,
    liveDebt: Stream.value(debt),
    payments: Stream.value(payments),
    wallets: Stream.value(const [cash]),
  );

  testWidgets('a debt being paid offers to pay it off early', (tester) async {
    await pump(tester, detail(loan(), const []));
    expect(find.text('Pay in Bill Planner'), findsOneWidget);
    expect(find.byKey(const Key('payoff-open')), findsOneWidget);
    expect(find.byKey(const Key('payoff-undo')), findsNothing);
  });

  testWidgets('paid off early: says so, lists it, and can be undone', (
    tester,
  ) async {
    await pump(
      tester,
      detail(loan(paidOffAt: DateTime(2026, 10, 28), paidOffAmount: 13500), [
        payoff,
      ]),
    );
    // On the top card and as the last row of the statement.
    expect(find.text('Paid off early · Oct 28, 2026'), findsNWidgets(2));
    expect(
      find.text('₱23,500 paid in all, the last ₱13,500 to finish it early'),
      findsOneWidget,
    );
    expect(find.text('Pay in Bill Planner'), findsNothing);
    expect(find.byKey(const Key('payoff-open')), findsNothing);
    expect(find.byKey(const Key('payoff-undo')), findsOneWidget);
    // The 5 payments made, then the payoff; not the 7 never needed.
    expect(find.byKey(const Key('statement-payoff')), findsOneWidget);
    expect(find.textContaining('Payment 6 of 12'), findsNothing);
    expect(find.textContaining('Payment 5 of 12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('payoff-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Undo paying it off?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
