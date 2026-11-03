import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/debt_detail_screen.dart';
import 'package:testapp/backend/services/bill_service.dart';
import 'package:testapp/frontend/theme/app_buttons.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/payoff_sheet.dart';

/// Juan borrowed ₱20,000 to pay back as 12 payments of ₱2,000: ₱24,000 in
/// all, ₱4,000 of it interest. 5 are paid.
Debt loan({
  DateTime? paidOffAt,
  double paidOffAmount = 0,
  String? paidWithWalletId,
}) => Debt(
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
  paidWithWalletId: paidWithWalletId,
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

const gcash = Wallet(
  id: 'gcash',
  name: 'GCash',
  type: WalletType.gcash,
  balance: 5000,
  startingBalance: 5000,
  receivesIncome: false,
  archived: false,
  sortOrder: 1,
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
    expect(find.text('Pay Personal loan off early?'), findsOneWidget);
    expect(
      find.textContaining('the 7 payments left are taken off the Bill Planner'),
      findsOneWidget,
    );

    // The dialog's answer, not the sheet's own button showing behind it.
    await tester.tap(find.widgetWithText(TextButton, 'Pay it off early'));
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

  testWidgets('an installment that named its wallet pays only from it', (
    tester,
  ) async {
    List<String>? from;
    await pump(
      tester,
      Scaffold(
        body: PayoffSheet(
          debt: loan(paidWithWalletId: 'gcash'),
          progress: DebtProgress.of(loan(paidWithWalletId: 'gcash'), const []),
          today: DateTime(2026, 10, 28),
          wallets: Stream.value(const [cash, gcash]),
          goals: Stream.value(const []),
          onPayOff: (parts, _) =>
              from = [for (final part in parts) part.walletId],
        ),
      ),
    );

    // The question is not asked again: the wallet is already known, and only
    // it is shown, with what it has free.
    expect(find.text('Where are you paying from?'), findsNothing);
    expect(find.text('Paying from'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
    expect(find.textContaining('₱5,000 available'), findsOneWidget);
    // The other wallet is not offered as a choice.
    expect(find.text('Cash'), findsNothing);

    // The plan asks for the ₱14,000 left, but GCash only holds ₱5,000, so
    // it refuses until the amount fits what the wallet has.
    await tester.tap(find.byKey(const Key('payoff-button')));
    await tester.pump();
    expect(find.byKey(const Key('payoff-error')), findsOneWidget);
    expect(find.text('Pay Personal loan off early?'), findsNothing);

    await tester.enterText(find.byKey(const Key('payoff-amount')), '5000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('payoff-button')));
    await tester.pumpAndSettle();
    expect(find.text('Pay Personal loan off early?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Pay it off early'));
    await tester.pumpAndSettle();
    expect(from, ['gcash']);
  });

  testWidgets('the named wallet is checked before the payoff goes through', (
    tester,
  ) async {
    // GCash has ₱5,000; the payoff asks for the ₱14,000 left on the plan.
    await pump(
      tester,
      Scaffold(
        body: PayoffSheet(
          debt: loan(paidWithWalletId: 'gcash'),
          progress: DebtProgress.of(loan(paidWithWalletId: 'gcash'), const []),
          today: DateTime(2026, 10, 28),
          wallets: Stream.value(const [cash, gcash]),
          goals: Stream.value(const []),
          onPayOff: (_, _) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('payoff-button')));
    await tester.pump();
    expect(find.byKey(const Key('payoff-error')), findsOneWidget);
    expect(find.text('Pay Personal loan off early?'), findsNothing);
  });

  Widget detail(Debt debt, List<BillInstance> payments) => LoanDetailScreen(
    debt: debt,
    liveDebt: Stream.value(debt),
    payments: Stream.value(payments),
    wallets: Stream.value(const [cash]),
  );

  /// A phone bought on installment: ₱48,000 in 12 payments of ₱4,000, charged
  /// to Cash when it was set up.
  Debt installment({String? paidWithWalletId}) => Debt(
    id: 'phone',
    direction: DebtDirection.iOwe,
    name: 'iPhone 15',
    category: DebtCategory.gadget,
    principal: 48000,
    perPayment: 4000,
    paymentCount: 12,
    firstDueDate: DateTime(2026, 6, 10),
    billId: 'bill',
    paidWithWalletId: paidWithWalletId,
    paidWithLabel: paidWithWalletId == null ? null : 'Cash',
    status: DebtStatus.active,
  );

  testWidgets('paying in advance is offered only to an installment that '
      'named its wallet', (tester) async {
    // A loan: no wallet is ever named at setup, so it keeps the payoff
    // button and pays early in the Bill Planner.
    await pump(tester, detail(loan(), const []));
    expect(find.byKey(const Key('advance-open')), findsNothing);
    expect(find.byKey(const Key('payoff-open')), findsOneWidget);

    // An installment that never named a wallet (made before this existed).
    await pump(
      tester,
      InstallmentDetailScreen(
        key: const Key('unnamed'),
        debt: installment(),
        liveDebt: Stream.value(installment()),
        payments: Stream.value(const []),
        wallets: Stream.value(const [cash]),
        today: DateTime(2026, 6, 15),
      ),
    );
    expect(find.byKey(const Key('advance-open')), findsNothing);
    // The payoff button is not on installments at all: they are finished by
    // paying the payments ahead, not in one go.
    expect(find.byKey(const Key('payoff-open')), findsNothing);
    expect(find.text('Paid it off early'), findsNothing);

    // One that did, with June's payment made: what waits is July's, ahead
    // of its date, so paying ahead is what is on offer.
    final named = installment(paidWithWalletId: 'cash');
    await pump(
      tester,
      InstallmentDetailScreen(
        key: const Key('named'),
        debt: named,
        liveDebt: Stream.value(named),
        payments: Stream.value([
          BillInstance(
            id: 'i2026-6',
            billId: 'bill',
            name: 'iPhone 15',
            amount: 4000,
            category: 'Bills',
            dueDate: DateTime(2026, 6, 10),
            status: BillStatus.paid,
            amountPaid: 4000,
          ),
        ]),
        wallets: Stream.value(const [cash]),
        today: DateTime(2026, 6, 15),
      ),
    );
    expect(find.byKey(const Key('advance-open')), findsOneWidget);
    expect(find.byKey(const Key('payoff-open')), findsNothing);
    // It only opens the sheet, so it is blue like the other openers.
    final fill = tester
        .widget<ElevatedButton>(find.byKey(const Key('advance-open')))
        .style
        ?.backgroundColor
        ?.resolve(const <WidgetState>{});
    expect(fill, appPrimaryBlue);
  });

  testWidgets('a debt being paid offers to pay it off early', (tester) async {
    await pump(tester, detail(loan(), const []));
    expect(find.byKey(const Key('payoff-open')), findsOneWidget);
    expect(find.byKey(const Key('payoff-undo')), findsNothing);

    // It only opens something, so it is blue like the other openers.
    Color? fillOf(ButtonStyle? style) =>
        style?.backgroundColor?.resolve(const <WidgetState>{});
    final payoffFill = fillOf(
      tester.widget<ElevatedButton>(find.byKey(const Key('payoff-open'))).style,
    );
    expect(payoffFill, appPrimaryBlue);
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

  group('deleting an installment', () {
    Future<void> openDelete(WidgetTester tester, {bool dark = false}) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: detail(loan(), const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    Color? actionColor(WidgetTester tester, String label) {
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      return button.style?.foregroundColor?.resolve(const <WidgetState>{});
    }

    testWidgets('says the money does not come back', (tester) async {
      await openDelete(tester);

      expect(find.text('Delete Personal loan?'), findsOneWidget);
      // The distinction, said outright: paid payments stay because the
      // money left, and deleting is not a refund.
      expect(
        find.text(
          'Its unpaid payments are removed from your Bill Planner. Payments '
          'you already made stay: that money really left your wallets, and '
          'deleting does not put it back.',
        ),
        findsOneWidget,
      );
      // Delete is red; Cancel is red too, like every button that stops or
      // undoes something.
      expect(actionColor(tester, 'Delete'), appDangerRed);
      expect(actionColor(tester, 'Cancel'), appDangerRed);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('reads the same, in its dark colours', (tester) async {
      await openDelete(tester, dark: true);

      expect(
        find.text(
          'Its unpaid payments are removed from your Bill Planner. Payments '
          'you already made stay: that money really left your wallets, and '
          'deleting does not put it back.',
        ),
        findsOneWidget,
      );
      // Lightened red, so it stays readable on the dark background.
      expect(actionColor(tester, 'Delete'), const Color(0xFFEF5350));
      expect(actionColor(tester, 'Cancel'), const Color(0xFFEF5350));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
