import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/reminder.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/debt_detail_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';

/// A bank loan: ₱15,000 back as 10 monthly payments of ₱1,500 from Jan 5,
/// 2026, and the lender charges ₱180 of interest each month.
Debt bankLoan({DateTime? paidOffAt, double accrued = 540}) => Debt(
  id: 'bpi',
  direction: DebtDirection.iOwe,
  name: 'BPI loan',
  category: DebtCategory.personalLoan,
  principal: 15000,
  status: DebtStatus.active,
  perPayment: 1500,
  paymentCount: 10,
  firstDueDate: DateTime(2026, 1, 5),
  billId: 'bpi-bill',
  paidWithWalletId: 'cash',
  fixedInterestAmount: 180,
  interestChargedPer: PaymentFrequency.monthly,
  accruedInterest: accrued,
  paidOffAt: paidOffAt,
);

/// One of the loan's own payments.
BillInstance payment(
  DateTime due, {
  double paid = 0,
  BillStatus status = BillStatus.unpaid,
}) => BillInstance(
  id: billInstanceId('bpi-bill', due),
  billId: 'bpi-bill',
  name: 'BPI loan',
  amount: 1500,
  category: 'Bills',
  dueDate: due,
  status: status,
  amountPaid: paid,
  debtId: 'bpi',
  isLoan: true,
);

/// One of the lender's ₱180 interest charges, as the Bill Planner holds it.
BillInstance charge(
  DateTime due, {
  double paid = 0,
  BillStatus status = BillStatus.unpaid,
}) => BillInstance(
  id: billInstanceId(fixedInterestBillId('bpi-bill'), due),
  billId: fixedInterestBillId('bpi-bill'),
  name: 'BPI loan interest',
  amount: 180,
  category: 'Interest',
  dueDate: due,
  status: status,
  amountPaid: paid,
  debtId: 'bpi',
  isLoan: true,
  interestShare: 1,
);

FixedInterestCharge recorded(DateTime due) => FixedInterestCharge(
  periodKey: '${due.year}-${due.month}',
  amount: 180,
  chargedAt: due,
  periodDueDate: due,
  period: PaymentFrequency.monthly,
);

/// The lender's charges: Dec 2025, then Mar and Apr 2026. ₱540 in all.
final charges = {
  'bpi': [
    recorded(DateTime(2025, 12, 5)),
    recorded(DateTime(2026, 3, 5)),
    recorded(DateTime(2026, 4, 5)),
  ],
};

AppTransaction paidCharge(DateTime due, DateTime on) => AppTransaction(
  id: 'paid-${due.month}',
  type: TransactionType.expense,
  amount: 180,
  label: 'Interest',
  date: on,
  note: 'BPI loan interest',
  billInstanceId: billInstanceId(fixedInterestBillId('bpi-bill'), due),
  interest: 180,
);

void main() {
  test('a charge is all interest, and kept under its own schedule', () {
    final entry = BillInstance.fromMap('x', {
      'billId': fixedInterestBillId('bpi-bill'),
      'name': 'BPI loan interest',
      'amount': 180,
      'category': 'Interest',
      'dueDate': DateTime(2026, 3, 5),
      'status': 'unpaid',
      'interestShare': 1.0,
    });
    expect(entry.interestIn(180), 180);
    expect(isFixedInterestCharge(entry), isTrue);
    expect(isFixedInterestCharge(payment(DateTime(2026, 3, 5))), isFalse);
  });

  test('charges count as paid, never as one of the payments', () {
    final progress = DebtProgress.of(bankLoan(), [
      payment(DateTime(2026, 1, 5), paid: 1500, status: BillStatus.paid),
      charge(DateTime(2025, 12, 5), paid: 180, status: BillStatus.paid),
    ]);
    expect(progress.paid, 1680);
    expect(progress.chargesPaid, 180);
    expect(progress.towardLoan, 1500, reason: 'pays the amount borrowed');
    expect(progress.paymentsMade, 1);
    // ₱15,000 and the ₱540 charged, less the ₱1,680 paid.
    expect(progress.remaining, 13860);
  });

  test('the next payment is the plan\'s own, not a charge on its date', () {
    final next = nextUnpaidPayment(bankLoan(), [
      charge(DateTime(2026, 1, 5)),
      payment(DateTime(2026, 1, 5)),
    ]);
    expect(next!.number, 1);
    expect(next.instance!.billId, 'bpi-bill');
  });

  test('charges still owed, oldest first', () {
    final owed = unpaidInterestCharges([
      charge(DateTime(2026, 4, 5)),
      charge(DateTime(2026, 3, 5)),
      charge(DateTime(2025, 12, 5), paid: 180, status: BillStatus.paid),
      payment(DateTime(2026, 3, 5)),
    ]);
    expect([for (final c in owed) c.dueDate.month], [3, 4]);
  });

  group('the year\'s interest', () {
    test('paying a charge does not count it twice', () {
      // Dec's charge, paid in January: it counted in 2025, when charged.
      final cost = loanInterestForYear(
        2026,
        debts: [bankLoan()],
        transactions: [paidCharge(DateTime(2025, 12, 5), DateTime(2026, 1, 9))],
        interestCharges: charges,
      );
      expect(cost.byLoan, {'BPI loan': 360.0});
      // ₱360 still owed: this year's two charges.
      expect(cost.unpaid, 360);

      // March's paid too: only April's is left.
      expect(
        loanInterestForYear(
          2026,
          debts: [bankLoan()],
          transactions: [
            paidCharge(DateTime(2025, 12, 5), DateTime(2026, 1, 9)),
            paidCharge(DateTime(2026, 3, 5), DateTime(2026, 3, 6)),
          ],
          interestCharges: charges,
        ).unpaid,
        180,
      );
    });

    test('a payoff adds only what it paid beyond the charges owed', () {
      // ₱180 of the ₱540 was paid, so the payoff settled ₱360 of charges;
      // of its ₱500 not toward the loan, ₱140 was a fee for paying early.
      final cost = loanInterestForYear(
        2026,
        debts: [bankLoan(paidOffAt: DateTime(2026, 6, 1))],
        transactions: [
          paidCharge(DateTime(2025, 12, 5), DateTime(2026, 1, 9)),
          AppTransaction(
            id: 'off',
            type: TransactionType.expense,
            amount: 9000,
            label: 'Bills',
            date: DateTime(2026, 6, 1),
            note: 'BPI loan (paid off early)',
            billInstanceId: payoffInstanceIdFor('bpi-bill'),
            interest: 500,
          ),
        ],
        interestCharges: charges,
      );
      expect(cost.byLoan, {'BPI loan': 500.0});
      expect(cost.unpaid, 0);
    });
  });

  testWidgets('Pay Now takes the interest owed before the payment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final debt = bankLoan();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: LoanDetailScreen(
            debt: debt,
            liveDebt: Stream.value(debt),
            payments: Stream.value([
              payment(DateTime(2026, 3, 5)),
              charge(DateTime(2026, 3, 5)),
            ]),
            interestCharges: Stream.value(const []),
            wallets: Stream.value(const [
              Wallet(
                id: 'cash',
                name: 'Cash',
                type: WalletType.cash,
                balance: 20000,
                startingBalance: 20000,
                receivesIncome: false,
                archived: false,
                sortOrder: 0,
              ),
            ]),
            today: DateTime(2026, 3, 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '₱180 of interest is unpaid. Pay Now takes it first, before the next '
        'payment.',
      ),
      findsOneWidget,
    );
    // The charge is not listed as one of the payments.
    expect(find.text('BPI loan interest'), findsNothing);
  });

  testWidgets('the statement takes a paid charge off what is left', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // ₱15,000 back, ₱1,500 paid, and March's ₱180 charge paid too.
    final debt = bankLoan(accrued: 180);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: LoanDetailScreen(
            debt: debt,
            liveDebt: Stream.value(debt),
            payments: Stream.value([
              payment(
                DateTime(2026, 1, 5),
                paid: 1500,
                status: BillStatus.paid,
              ),
              charge(DateTime(2026, 3, 5), paid: 180, status: BillStatus.paid),
            ]),
            interestCharges: Stream.value([recorded(DateTime(2026, 3, 5))]),
            wallets: Stream.value(const <Wallet>[]),
            today: DateTime(2026, 3, 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('; Paid'), findsOneWidget);
    // What is left after the last payment is what is really owed.
    expect(find.text('₱13,500 left'), findsWidgets);
    expect(find.text('₱13,680 left'), findsNothing);
  });
}
