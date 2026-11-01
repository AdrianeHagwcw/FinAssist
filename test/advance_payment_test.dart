import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/advance_payment_sheet.dart';

/// An iPhone 15 bought on installment: ₱48,000 in 12 payments of ₱4,000, the
/// first due Jun 10, charged to GCash when it was set up.
Debt phone({int paidBefore = 0, String? walletId = 'gcash'}) => Debt(
  id: 'phone',
  direction: DebtDirection.iOwe,
  name: 'iPhone 15',
  category: DebtCategory.gadget,
  principal: 48000,
  perPayment: 4000,
  paymentCount: 12,
  firstDueDate: DateTime(2026, 6, 10),
  billId: 'bill',
  paidBefore: paidBefore,
  paidWithWalletId: walletId,
  paidWithLabel: walletId == null ? null : 'GCash',
  status: DebtStatus.active,
);

/// One of the plan's monthly occurrences: [month] counts from June 2026.
BillInstance occurrence({
  int month = 7,
  double amount = 4000,
  double paid = 0,
  BillStatus status = BillStatus.unpaid,
  String? carriedInto,
}) => BillInstance(
  id: 'bill-$month',
  billId: 'bill',
  name: 'iPhone 15',
  amount: amount,
  category: 'Bills',
  dueDate: DateTime(2026, month, 10),
  status: status,
  amountPaid: paid,
  carriedInto: carriedInto,
);

const gcash = Wallet(
  id: 'gcash',
  name: 'GCash',
  type: WalletType.gcash,
  balance: 5000,
  startingBalance: 5000,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

/// GCash holding less than the ₱4,000 the plan asks for.
const poorGcash = Wallet(
  id: 'gcash',
  name: 'GCash',
  type: WalletType.gcash,
  balance: 3000,
  startingBalance: 3000,
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
  group('the payment still waiting on a plan', () {
    test('is the first one nothing has settled', () {
      final next = nextUnpaidPayment(phone(), const []);
      expect(next, isNotNull);
      expect(next!.number, 1);
      expect(next.due, DateTime(2026, 6, 10));
      expect(next.scheduledAmount, 4000);
      // The month was never opened in the Bill Planner, so there is no
      // occurrence standing for it yet.
      expect(next.instance, isNull);
      expect(next.amount, 4000);
    });

    test('skips the payments made before the plan was tracked', () {
      final next = nextUnpaidPayment(phone(paidBefore: 5), const []);
      expect(next!.number, 6);
      expect(next.due, DateTime(2026, 11, 10));
      expect(next.amount, 4000);
    });

    test('passes over an occurrence already paid', () {
      final next = nextUnpaidPayment(phone(), [
        occurrence(month: 6, paid: 4000, status: BillStatus.paid),
      ]);
      expect(next!.number, 2);
      expect(next.due, DateTime(2026, 7, 10));
      // July was never opened in the Bill Planner, so nothing stands for
      // this payment yet.
      expect(next.instance, isNull);
    });

    test('passes over one whose unpaid part moved to the next month', () {
      final next = nextUnpaidPayment(phone(), [
        occurrence(month: 6, carriedInto: 'bill-7'),
      ]);
      expect(next!.number, 2);
      expect(next.due, DateTime(2026, 7, 10));
    });

    test('a part-paid payment waits, at what is left of it', () {
      final next = nextUnpaidPayment(phone(), [
        occurrence(month: 6, paid: 1500, status: BillStatus.partial),
      ]);
      expect(next!.number, 1);
      expect(next.instance!.id, 'bill-6');
      // The statement asked for less; the rest is still owed on it.
      expect(next.amount, 2500);
    });

    test('nothing waits once every payment is settled', () {
      final settled = [
        for (var month = 6; month <= 17; month++)
          occurrence(month: month, paid: 4000, status: BillStatus.paid),
      ];
      expect(nextUnpaidPayment(phone(), settled), isNull);
    });

    test('with no start date, the earliest owed occurrence is next', () {
      final tracked = phone();
      final withoutDates = Debt(
        id: tracked.id,
        direction: tracked.direction,
        name: tracked.name,
        category: tracked.category,
        principal: tracked.principal,
        perPayment: tracked.perPayment,
        paymentCount: tracked.paymentCount,
        billId: tracked.billId,
        paidWithWalletId: tracked.paidWithWalletId,
        status: tracked.status,
      );
      final next = nextUnpaidPayment(withoutDates, [
        occurrence(month: 5, paid: 4000, status: BillStatus.paid),
        occurrence(month: 6, paid: 4000, status: BillStatus.paid),
        occurrence(month: 7),
      ]);
      expect(next!.number, 3);
      expect(next.due, DateTime(2026, 7, 10));
      expect(next.amount, 4000);
    });
  });

  testWidgets('starts on what the payment asks, from the named wallet only', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        body: AdvancePaymentSheet(
          debt: phone(),
          next: DebtNextPayment(
            number: 2,
            due: DateTime(2026, 7, 10),
            scheduledAmount: 4000,
            instance: occurrence(month: 7),
          ),
          wallets: Stream.value(const [gcash]),
          goals: Stream.value(const []),
          onPay: (_, _) {},
        ),
      ),
    );

    expect(
      find.text('Payment 2 of 12 on iPhone 15, due Jul 10, 2026.'),
      findsOneWidget,
    );
    // Prefilled with the whole payment, ready to follow the statement.
    expect(find.text('4,000'), findsOneWidget);
    // The wallet is charged without asking again: no group tiles, no list.
    expect(find.text('Where are you paying from?'), findsNothing);
    expect(find.text('Paying from'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
    // What GCash has free now, not the ₱4,000 being paid.
    expect(find.textContaining('₱5,000 available'), findsOneWidget);
    expect(
      find.text('Chosen when the installment was set up.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('advance-button')), findsOneWidget);
  });

  testWidgets('the payment is dated the day the plan says it falls due', (
    tester,
  ) async {
    DateTime? paidOn;
    await pump(
      tester,
      Scaffold(
        body: AdvancePaymentSheet(
          debt: phone(),
          // Payment 3 of 12, due 30 December 2026.
          next: DebtNextPayment(
            number: 3,
            due: DateTime(2026, 12, 30),
            scheduledAmount: 4000,
            instance: occurrence(month: 12),
          ),
          wallets: Stream.value(const [gcash]),
          goals: Stream.value(const []),
          onPay: (_, date) => paidOn = date,
        ),
      ),
    );

    // Said on the sheet, so the day it will be recorded on is plain.
    expect(find.text('Dec 30, 2026'), findsOneWidget);
    expect(
      find.text(
        'The day this payment falls due on your plan, so the statement of '
        'account matches the schedule.',
      ),
      findsOneWidget,
    );
    // And not asked for: the plan already has the day, so there is nothing
    // to pick — the date is shown, not chosen.

    await tester.tap(find.byKey(const Key('advance-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Record payment'));
    await tester.pumpAndSettle();

    // Recorded on 30 December 2026, the plan's own date for payment 3 — not
    // on the day the button was tapped.
    expect(paidOn, DateTime(2026, 12, 30));
  });

  testWidgets('the statement asking for less records a part payment', (
    tester,
  ) async {
    double? paid;
    String? from;
    await pump(
      tester,
      Scaffold(
        body: AdvancePaymentSheet(
          debt: phone(),
          next: DebtNextPayment(
            number: 2,
            due: DateTime(2026, 7, 10),
            scheduledAmount: 4000,
            instance: occurrence(month: 7),
          ),
          wallets: Stream.value(const [gcash]),
          goals: Stream.value(const []),
          onPay: (parts, _) {
            paid = parts.single.amount;
            from = parts.single.walletId;
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('advance-amount')), '2000');
    await tester.pump();
    expect(
      find.textContaining(
        'That leaves ₱2,000 of this payment still owed, until the statement '
        'says the rest.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('advance-button')));
    await tester.pumpAndSettle();
    expect(find.text('Record payment 2 ahead of time?'), findsOneWidget);
    expect(
      find.text(
        '₱2,000 comes out of GCash for payment 2 of 12, dated Jul 10, 2026 '
        '— the day it falls due. The Bill Planner counts it as settled.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Record payment'));
    await tester.pumpAndSettle();
    expect(paid, 2000);
    expect(from, 'gcash');
  });

  testWidgets('refuses to pay more than the payment needs', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: AdvancePaymentSheet(
          debt: phone(),
          next: DebtNextPayment(
            number: 2,
            due: DateTime(2026, 7, 10),
            scheduledAmount: 4000,
            instance: occurrence(month: 7),
          ),
          wallets: Stream.value(const [gcash]),
          goals: Stream.value(const []),
          onPay: (_, _) {},
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('advance-amount')), '5000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('advance-button')));
    await tester.pump();
    expect(
      find.textContaining('₱1,000 more than payment 2 needs'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('advance-error')), findsOneWidget);
    expect(find.text('Record payment 2 ahead of time?'), findsNothing);
  });

  testWidgets('refuses more than the wallet has free', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: AdvancePaymentSheet(
          debt: phone(),
          next: DebtNextPayment(
            number: 2,
            due: DateTime(2026, 7, 10),
            scheduledAmount: 4000,
            instance: occurrence(month: 7),
          ),
          wallets: Stream.value(const [poorGcash]),
          goals: Stream.value(const []),
          onPay: (_, _) {},
        ),
      ),
    );

    // GCash holds ₱3,000; the payment asks for ₱4,000.
    await tester.tap(find.byKey(const Key('advance-button')));
    await tester.pump();
    expect(find.text('Only ₱3,000 in GCash is free.'), findsOneWidget);
    expect(find.text('Record payment 2 ahead of time?'), findsNothing);
  });

  testWidgets('a wallet that is gone cannot be paid from', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: AdvancePaymentSheet(
          debt: phone(walletId: 'deleted'),
          next: DebtNextPayment(
            number: 2,
            due: DateTime(2026, 7, 10),
            scheduledAmount: 4000,
            instance: occurrence(month: 7),
          ),
          wallets: Stream.value(const [gcash]),
          goals: Stream.value(const []),
          onPay: (_, _) {},
        ),
      ),
    );

    expect(
      find.textContaining(
        'The wallet this installment was charged to is not '
        'in Accounts any more.',
      ),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('advance-button')),
    );
    expect(button.onPressed, isNull);
  });
}
