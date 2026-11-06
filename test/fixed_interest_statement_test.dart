import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/debt_detail_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';

void main() {
  testWidgets('combines same-date interest with the numbered payment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final date = DateTime(2026, 12, 1);
    final debt = Debt(
      id: 'annual-loan',
      direction: DebtDirection.iOwe,
      name: 'Personal loan',
      category: DebtCategory.personalLoan,
      principal: 2000,
      perPayment: 1000,
      paymentCount: 2,
      frequency: PaymentFrequency.monthly,
      firstDueDate: date,
      billId: 'annual-loan-bill',
      status: DebtStatus.active,
      fixedInterestAmount: 180,
      interestChargedPer: PaymentFrequency.annually,
      interestScheduleAnchor: date,
      nextInterestDueDate: DateTime(2027, 12, 1),
      interestPeriodsCharged: 1,
      accruedInterest: 180,
    );
    final payment = BillInstance(
      id: 'december-payment',
      billId: 'annual-loan-bill',
      debtId: debt.id,
      name: debt.name,
      amount: 1000,
      amountPaid: 1000,
      category: 'Bills',
      dueDate: date,
      status: BillStatus.paid,
    );
    final charge = FixedInterestCharge(
      periodKey: 'annually-2026',
      amount: 180,
      chargedAt: date,
      periodDueDate: date,
      period: PaymentFrequency.annually,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: LoanDetailScreen(
            debt: debt,
            liveDebt: Stream.value(debt),
            payments: Stream.value([payment]),
            wallets: Stream.value(const <Wallet>[]),
            interestCharges: Stream.value([charge]),
            today: date,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Statement of account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Payment 1 + Interest charge'), findsOneWidget);
    expect(
      find.textContaining('interest recorded; charge date'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('statement-fixed-interest-annually-2026')),
      findsNothing,
    );
  });

  testWidgets('keeps an interest charge separate when dates differ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final paymentDate = DateTime(2026, 12, 1);
    final chargeDate = DateTime(2026, 11, 15);
    final debt = Debt(
      id: 'separate-date-loan',
      direction: DebtDirection.iOwe,
      name: 'Personal loan',
      category: DebtCategory.personalLoan,
      principal: 2000,
      perPayment: 1000,
      paymentCount: 2,
      frequency: PaymentFrequency.monthly,
      firstDueDate: paymentDate,
      billId: 'separate-date-bill',
      status: DebtStatus.active,
      fixedInterestAmount: 180,
      interestChargedPer: PaymentFrequency.monthly,
      interestScheduleAnchor: chargeDate,
      nextInterestDueDate: DateTime(2026, 12, 15),
      interestPeriodsCharged: 1,
      accruedInterest: 180,
    );
    final charge = FixedInterestCharge(
      periodKey: 'monthly-2026-11',
      amount: 180,
      chargedAt: chargeDate,
      periodDueDate: chargeDate,
      period: PaymentFrequency.monthly,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: LoanDetailScreen(
            debt: debt,
            liveDebt: Stream.value(debt),
            payments: Stream.value(const <BillInstance>[]),
            wallets: Stream.value(const <Wallet>[]),
            interestCharges: Stream.value([charge]),
            today: paymentDate,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Statement of account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Payment 1 of 2 ·'), findsOneWidget);
    expect(
      find.byKey(const Key('statement-fixed-interest-monthly-2026-11')),
      findsOneWidget,
    );
  });
}
