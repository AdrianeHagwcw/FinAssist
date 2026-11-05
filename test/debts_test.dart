import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/services/bill_service.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/screens/debts_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/bill_payment_sheet.dart';
import 'package:testapp/frontend/widgets/installment_form_sheet.dart';
import 'package:testapp/frontend/widgets/loan_form_sheet.dart';
import 'package:testapp/frontend/widgets/wallet_split_picker.dart';

Debt loan({
  double principal = 5000,
  required LoanPayments payments,
  int count = 3,
  double fees = 0,
  double? quotedRate,
  RatePeriod per = RatePeriod.month,
  DebtCategory category = DebtCategory.cardCashLoan,
}) => Debt(
  id: 'loan',
  direction: DebtDirection.iOwe,
  name: 'Loan',
  category: category,
  principal: principal,
  perPayment: payments.perPayment,
  lastPayment: payments.lastPayment,
  paymentCount: count,
  status: DebtStatus.active,
  fees: fees,
  quotedRate: quotedRate,
  quotedRatePer: per,
);

LoanPayments work(
  double principal,
  double rate,
  RatePeriod per,
  int count, {
  InterestBasis basis = InterestBasis.wholeAmount,
}) => loanPayments(
  principal: principal,
  rate: rate,
  per: per,
  basis: basis,
  count: count,
  frequency: PaymentFrequency.monthly,
)!;

void main() {
  test('loan payment frequencies map to matching bill dates', () {
    expect(PaymentFrequency.daily.recurrence, BillRecurrence.daily);
    expect(PaymentFrequency.quarterly.recurrence, BillRecurrence.quarterly);
    expect(PaymentFrequency.semiAnnual.recurrence, BillRecurrence.semiAnnual);
    expect(PaymentFrequency.annually.recurrence, BillRecurrence.yearly);
    expect(
      lastDueDateFor(DateTime(2026, 1, 5), BillRecurrence.daily, 3),
      DateTime(2026, 1, 7),
    );
    expect(
      lastDueDateFor(DateTime(2026, 1, 5), BillRecurrence.semiAnnual, 3),
      DateTime(2027, 1, 5),
    );
    expect(
      fixedInterestPeriodKey(DateTime(2026, 5, 2), PaymentFrequency.monthly),
      fixedInterestPeriodKey(DateTime(2026, 5, 29), PaymentFrequency.monthly),
    );
    expect(
      fixedInterestPeriodKey(DateTime(2026, 5, 2), PaymentFrequency.weekly),
      fixedInterestPeriodKey(DateTime(2026, 5, 3), PaymentFrequency.weekly),
    );
    expect(
      fixedInterestPeriodKey(DateTime(2026, 1, 10), PaymentFrequency.annually),
      fixedInterestPeriodKey(DateTime(2026, 12, 10), PaymentFrequency.annually),
    );
  });

  test('older debt records default safely without optional loan details', () {
    final debt = Debt.fromMap('older', {
      'direction': 'iOwe',
      'name': 'Old loan',
      'category': 'personalLoan',
      'principal': 5000,
      'status': 'active',
      'perPayment': 1000,
      'paymentCount': 5,
      'quotedRate': 1.5,
      'quotedRatePer': 'month',
    });

    expect(debt.principal, 5000);
    expect(debt.frequency, PaymentFrequency.monthly);
    expect(debt.originalPrincipal, isNull);
    expect(debt.interestPeriod, isNull);
    expect(debt.loanDuration, isNull);
    expect(debt.loanStartDate, isNull);
    expect(debt.balanceBasedSchedule, isFalse);
    expect(debt.fixedInterestAmount, isNull);
    expect(debt.interestChargedPer, isNull);
    expect(debt.accruedInterest, 0);
  });

  group('working out a loan from its rate', () {
    test("Metrobank's Cash2Go calculator: ₱5,000 at 1% a month for 3", () {
      final payments = work(5000, 1, RatePeriod.month, 3);
      // Metrobank shows ₱1,716.67 a month, ₱5,150 in all, ₱150 interest.
      expect(payments.perPayment, 1716.67);
      expect(payments.lastPayment, 1716.66, reason: 'rounding');
      expect(payments.interest, closeTo(150, 0.001));

      final debt = loan(payments: payments);
      expect(debt.totalPayable, closeTo(5150, 0.001));
      // Metrobank: 17.912% effective interest rate.
      expect(debt.yearlyCostPercent, closeTo(17.912, 0.01));
    });

    test('₱5,600 with 20% for the whole loan, in 12 payments', () {
      final payments = work(5600, 20, RatePeriod.wholeLoan, 12);
      expect(payments.perPayment, 560);
      expect(payments.lastPayment, 0);
      expect(payments.interest, closeTo(1120, 0.001));
      // 20% on the whole amount is about 35% a year as a true cost.
      final debt = loan(principal: 5600, payments: payments, count: 12);
      expect(debt.yearlyCostPercent, closeTo(35.07, 0.05));
    });

    test('a yearly rate on what is left to pay, like a home loan', () {
      final payments = work(
        1000000,
        6.25,
        RatePeriod.year,
        360,
        basis: InterestBasis.remainingBalance,
      );
      expect(payments.perPayment, closeTo(6157.17, 0.01));
      final debt = loan(principal: 1000000, payments: payments, count: 360);
      // Charged on what is left, the quoted rate is the true cost.
      expect(debt.yearlyCostPercent, closeTo(6.25, 0.01));
      expect(debt.totalPayable, closeTo(1000000 + payments.interest, 0.01));
    });

    test('no interest between family: the amount split evenly', () {
      final payments = work(6000, 0, RatePeriod.month, 12);
      expect(payments.perPayment, 500);
      expect(payments.interest, 0);
      final debt = loan(
        principal: 6000,
        payments: payments,
        count: 12,
        category: DebtCategory.familyFriend,
      );
      expect(debt.yearlyCostPercent, isNull);
    });

    test('fees taken out make the true cost higher', () {
      final payments = work(10000, 2, RatePeriod.month, 6);
      final plain = loan(principal: 10000, payments: payments, count: 6);
      final withFees = loan(
        principal: 10000,
        payments: payments,
        count: 6,
        fees: 300,
      );
      expect(withFees.amountReceived, 9700);
      expect(withFees.extraCost, closeTo(1500, 0.01));
      expect(
        withFees.yearlyCostPercent!,
        greaterThan(plain.yearlyCostPercent!),
      );
    });

    test('payments above the quoted rate are flagged; fees told are not', () {
      final asQuoted = loan(
        principal: 5600,
        payments: work(5600, 20, RatePeriod.wholeLoan, 12),
        count: 12,
        quotedRate: 20,
        per: RatePeriod.wholeLoan,
      );
      expect(asQuoted.costsMoreThanQuoted, isFalse);

      final more = loan(
        principal: 5600,
        payments: const LoanPayments(
          perPayment: 600,
          lastPayment: 0,
          interest: 1600,
        ),
        count: 12,
        quotedRate: 20,
        per: RatePeriod.wholeLoan,
      );
      expect(more.costsMoreThanQuoted, isTrue);
    });
  });

  group('installments and debts are kept apart', () {
    test('which kinds are loans, and whose rate must be given', () {
      expect(DebtCategory.gadget.isLoan, isFalse);
      expect(DebtCategory.creditCard.isLoan, isFalse);
      expect(DebtCategory.cardCashLoan.isLoan, isTrue);
      expect(DebtCategory.familyFriend.isLoan, isTrue);
      expect(DebtCategory.personalLoan.mustDiscloseRate, isTrue);
      expect(DebtCategory.governmentLoan.mustDiscloseRate, isTrue);
      expect(DebtCategory.familyFriend.mustDiscloseRate, isFalse);
      expect(
        DebtCategory.installmentKinds,
        isNot(contains(DebtCategory.familyFriend)),
      );
      expect(DebtCategory.loanKinds, contains(DebtCategory.cardCashLoan));
    });

    test('Cash2Go is cash from a card, not a card installment', () {
      expect(guessDebtCategory('Cash2Go'), DebtCategory.cardCashLoan);
      expect(guessDebtCategory('BPI credit card'), DebtCategory.creditCard);
    });

    Debt saved(String name, DebtCategory category) => Debt(
      id: name,
      direction: DebtDirection.iOwe,
      name: name,
      category: category,
      principal: 6000,
      perPayment: 500,
      paymentCount: 12,
      status: DebtStatus.active,
    );

    Future<void> pumpList(WidgetTester tester, {required bool loans}) async {
      final debts = Stream.value([
        saved('Phone', DebtCategory.gadget),
        saved('SSS loan', DebtCategory.governmentLoan),
      ]);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: loans
                  ? DebtsView(
                      debts: debts,
                      paymentsFor: (_) => Stream.value(const <BillInstance>[]),
                    )
                  : InstallmentsView(
                      debts: debts,
                      paymentsFor: (_) => Stream.value(const <BillInstance>[]),
                    ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Installments lists only things bought on installment', (
      tester,
    ) async {
      await pumpList(tester, loans: false);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('SSS loan'), findsNothing);
      expect(find.text('Money you borrowed is now under Debts.'), findsNothing);
      expect(find.text('Add Installment'), findsOneWidget);
    });

    testWidgets('Debts lists only borrowed money', (tester) async {
      await pumpList(tester, loans: true);
      expect(find.text('SSS loan'), findsOneWidget);
      expect(find.text('Phone'), findsNothing);
      expect(find.text('Money you borrowed is now under Debts.'), findsNothing);
      expect(find.text('Add Debt'), findsOneWidget);
    });

    testWidgets('a down payment comes off the cash price', (tester) async {
      InstallmentDraft? saved;
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: InstallmentFormSheet(
                today: DateTime(2026, 10, 28),
                onSave: (draft) => saved = draft,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('installment-description')),
        'Aircon',
      );
      await tester.enterText(
        find.byKey(const Key('installment-price')),
        '30000',
      );
      await tester.enterText(find.byKey(const Key('installment-months')), '12');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('installment-down-payment')),
        '5000',
      );
      await tester.pump();
      // ₱25,000 left after the down payment, split over 12 months. Nothing
      // is added on top: the price is the whole of what is paid.
      expect(find.textContaining('You will pay ₱25,000'), findsOneWidget);
      expect(find.textContaining('more than you borrowed'), findsNothing);
      // The each-payment field follows the down payment too.
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('installment-each-payment')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        '2,083.33',
      );

      await tester.ensureVisible(find.text('Save Installment'));
      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();
      expect(saved?.principal, 25000);
      expect(saved?.perPayment, 2083.33);
      expect(saved?.lastPayment, 2083.37);
    });

    testWidgets('the card or account a purchase was charged to is saved', (
      tester,
    ) async {
      InstallmentDraft? saved;
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InstallmentFormSheet(
              today: DateTime(2026, 10, 28),
              wallets: Stream.value([
                Wallet(
                  id: 'cash',
                  name: 'Cash on Hand',
                  type: WalletType.cash,
                  balance: 2000,
                  startingBalance: 2000,
                  receivesIncome: false,
                  archived: false,
                  sortOrder: 0,
                ),
                Wallet(
                  id: 'bank',
                  name: 'BPI Savings',
                  type: WalletType.bank,
                  balance: 50000,
                  startingBalance: 50000,
                  receivesIncome: false,
                  archived: false,
                  sortOrder: 1,
                ),
              ]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      // Always shown, even though it is optional, and asked the way paying
      // always looks: which side of the money first.
      expect(find.text('Wallet used'), findsOneWidget);
      expect(
        find.byKey(const Key('installment-paid-with-cash')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('installment-paid-with-bank')),
        findsOneWidget,
      );
      // The first wallet is already chosen, so the field is never blank.
      expect(
        find.byKey(const Key('installment-paid-with-wallet-cash')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('installment-description')),
        'iPhone 15',
      );
      await tester.enterText(
        find.byKey(const Key('installment-price')),
        '48000',
      );
      await tester.enterText(find.byKey(const Key('installment-months')), '12');

      // Cash in Bank opens the accounts under it; the cash wallets are not
      // listed there, and nothing else is offered to pick.
      await tester.tap(find.byKey(const Key('installment-paid-with-bank')));
      await tester.pumpAndSettle();
      expect(find.text('Not recorded'), findsNothing);
      expect(find.text('Another card or account'), findsNothing);
      expect(
        find.byKey(const Key('installment-paid-with-wallet-cash')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('installment-paid-with-wallet-bank')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save Installment'));
      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();

      expect(saved?.paidWithWalletId, 'bank');
      expect(saved?.paidWithLabel, 'BPI Savings');
    });

    testWidgets(
      'Cash in Bank excludes savings and transfer-only demand deposits',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Wallet savingsRecord(String id, String name, SavingsKind kind) =>
            Wallet(
              id: id,
              name: name,
              type: WalletType.other,
              balance: 5000,
              startingBalance: 5000,
              receivesIncome: false,
              archived: false,
              sortOrder: 1,
              purpose: WalletPurpose.savings,
              savingsKind: kind.name,
            );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: InstallmentFormSheet(
                today: DateTime(2026, 10, 28),
                wallets: Stream.value([
                  Wallet(
                    id: 'cash',
                    name: 'Cash',
                    type: WalletType.cash,
                    balance: 2000,
                    startingBalance: 2000,
                    receivesIncome: false,
                    archived: false,
                    sortOrder: 0,
                  ),
                  Wallet(
                    id: 'bank',
                    name: 'BPI',
                    type: WalletType.bank,
                    balance: 5000,
                    startingBalance: 5000,
                    receivesIncome: false,
                    archived: false,
                    sortOrder: 1,
                  ),
                  savingsRecord(
                    'demand',
                    'Demand Deposit',
                    SavingsKind.demandDeposit,
                  ),
                  savingsRecord(
                    'savings',
                    'Savings Deposit',
                    SavingsKind.savingsDeposit,
                  ),
                  savingsRecord(
                    'time',
                    'Time Deposit',
                    SavingsKind.timeDeposit,
                  ),
                ]),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('installment-paid-with-bank')));
        await tester.pumpAndSettle();
        expect(find.text('BPI'), findsOneWidget);
        expect(find.text('Demand Deposit'), findsNothing);
        expect(find.text('Savings Deposit'), findsNothing);
        expect(find.text('Time Deposit'), findsNothing);
      },
    );

    testWidgets('with no wallets yet, the wallet is left unrecorded', (
      tester,
    ) async {
      InstallmentDraft? saved;
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InstallmentFormSheet(
              today: DateTime(2026, 10, 28),
              wallets: Stream.value(const <Wallet>[]),
              onSave: (draft) => saved = draft,
            ),
          ),
        ),
      );
      await tester.pump();

      // Nothing to pick from, so the form says where to add one.
      expect(find.text('Wallet used'), findsOneWidget);
      expect(find.text('Add a wallet first, under Accounts.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('installment-description')),
        'Aircon',
      );
      await tester.enterText(
        find.byKey(const Key('installment-price')),
        '30000',
      );
      await tester.enterText(find.byKey(const Key('installment-months')), '12');

      await tester.ensureVisible(find.text('Save Installment'));
      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();

      // The plan still saves; only the wallet is left out.
      expect(saved?.paidWithWalletId, isNull);
      expect(saved?.paidWithLabel, isNull);
    });

    testWidgets('the installment card shows what it was charged to', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: InstallmentsView(
                debts: Stream.value([
                  Debt(
                    id: 'd',
                    direction: DebtDirection.iOwe,
                    name: 'Phone',
                    category: DebtCategory.gadget,
                    principal: 24000,
                    perPayment: 2000,
                    paymentCount: 12,
                    firstDueDate: DateTime(2026, 1, 5),
                    billId: 'b',
                    status: DebtStatus.active,
                    paidWithWalletId: 'bank',
                    paidWithLabel: 'BPI Savings',
                  ),
                ]),
                paymentsFor: (_) => Stream.value(const <BillInstance>[]),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Wallet used: BPI Savings'), findsOneWidget);
    });

    testWidgets('an installment payment is from cash or the bank, not both', (
      tester,
    ) async {
      final cash = Wallet(
        id: 'cash',
        name: 'Cash on Hand',
        type: WalletType.cash,
        balance: 5000,
        startingBalance: 5000,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
      );
      final bank = Wallet(
        id: 'bank',
        name: 'BPI Savings',
        type: WalletType.bank,
        balance: 5000,
        startingBalance: 5000,
        receivesIncome: false,
        archived: false,
        sortOrder: 1,
      );
      final payment = BillInstance(
        id: 'b_1',
        billId: 'b',
        name: 'Phone',
        amount: 2000,
        category: 'Bills',
        dueDate: DateTime(2026, 11, 28),
        status: BillStatus.unpaid,
      );
      List<BillPaymentPart>? paid;

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: BillPaymentSheet(
                instance: payment,
                wallets: Stream.value([cash, bank]),
                onPay: (parts) => paid = parts,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // One payment, one clear side: no Both.
      expect(find.text('Both'), findsNothing);
      expect(find.text('Cash on Hand'), findsOneWidget);
      expect(find.text('Cash in Bank'), findsOneWidget);

      await tester.tap(find.text('Cash in Bank'));
      await tester.pumpAndSettle();
      // The whole payment is filled in from the first bank account.
      await tester.tap(find.byKey(const Key('bill-pay-button')));
      await tester.pumpAndSettle();

      expect(paid, isNotNull);
      expect(paid!.fold<double>(0, (sum, part) => sum + part.amount), 2000);

      // Mixing the two sides is refused even if it got that far.
      expect(
        walletSplitProblem(
          purpose: SplitPurpose.paying,
          amounts: const {'cash': 1000, 'bank': 1000},
          wallets: [cash, bank],
          goals: const [],
          target: 2000,
          matchTarget: true,
          allowBoth: false,
        ),
        'Choose Cash on Hand or Cash in Bank, not both.',
      );
    });

    testWidgets('a loan typed into the installment form can move to Debts', (
      tester,
    ) async {
      String? movedName;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InstallmentFormSheet(
              today: DateTime(2026, 10, 28),
              onSave: (_) {},
              onAddAsDebt: (name) => movedName = name,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'SSS loan');
      await tester.pump();

      expect(
        find.textContaining('This sounds like borrowed money'),
        findsOneWidget,
      );
      await tester.tap(find.text('Add it as a debt'));
      expect(movedName, 'SSS loan');
    });
  });

  group('the Add Debt form', () {
    Future<void> pumpForm(
      WidgetTester tester,
      void Function(LoanDraft draft) onSave,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LoanFormSheet(today: DateTime(2026, 10, 28), onSave: onSave),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('saves required details without optional loan information', (
      tester,
    ) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await tester.enterText(find.byKey(const Key('loan-name')), 'BPI loan');
      await tester.enterText(find.byKey(const Key('loan-balance')), '15000');
      await tester.enterText(find.byKey(const Key('loan-payment')), '1000');
      await tester.pump();

      expect(find.text('Additional Debt Details (Optional)'), findsOneWidget);
      expect(find.byKey(const Key('loan-rate')), findsNothing);
      expect(find.text('Debt start date'), findsNothing);
      await tester.tap(find.byKey(const Key('loan-additional-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();

      expect(saved?.name, 'BPI loan');
      expect(saved?.principal, 15000);
      expect(saved?.perPayment, 1000);
      expect(saved?.paymentCount, 15);
      expect(saved?.frequency, PaymentFrequency.monthly);
      expect(saved?.firstDueDate, DateTime(2026, 11, 28));
      expect(saved?.fixedInterestAmount, isNull);
      expect(saved?.interestChargedPer, isNull);
      expect(saved?.balanceBasedSchedule, isTrue);
    });

    testWidgets('estimates duration from the balance and payment', (
      tester,
    ) async {
      await pumpForm(tester, (_) {});
      await tester.enterText(find.byKey(const Key('loan-balance')), '15000');
      await tester.enterText(find.byKey(const Key('loan-payment')), '1000');
      await tester.tap(find.byKey(const Key('loan-additional-details')));
      await tester.pumpAndSettle();

      final durationField = tester.widget<TextField>(
        find.byKey(const Key('loan-duration')),
      );
      expect(durationField.controller?.text, '15');
      expect(
        find.text('Estimated from your balance, payment, and frequency.'),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('loan-payment')), '500');
      await tester.pump();
      expect(durationField.controller?.text, '30');
    });

    testWidgets('keeps a duration the user edits', (tester) async {
      await pumpForm(tester, (_) {});
      await tester.enterText(find.byKey(const Key('loan-balance')), '15000');
      await tester.enterText(find.byKey(const Key('loan-payment')), '1000');
      await tester.tap(find.byKey(const Key('loan-additional-details')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('loan-duration')), '20');
      await tester.enterText(find.byKey(const Key('loan-payment')), '500');
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('loan-duration')))
            .controller
            ?.text,
        '20',
      );
    });

    testWidgets('saves optional details and a supported payment frequency', (
      tester,
    ) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await tester.enterText(find.byKey(const Key('loan-name')), 'Tita Baby');
      await tester.enterText(find.byKey(const Key('loan-balance')), '10000');
      await tester.enterText(find.byKey(const Key('loan-payment')), '1000');

      await tester.tap(find.byKey(const Key('loan-additional-details')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('loan-fixed-interest')),
        '180',
      );
      await tester.enterText(find.byKey(const Key('loan-duration')), '10');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('loan-interest-charged-per-none')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every month').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();
      expect(saved?.principal, 10000);
      expect(saved?.frequency, PaymentFrequency.monthly);
      expect(saved?.paymentCount, 10);
      expect(saved?.fixedInterestAmount, 180);
      expect(saved?.interestChargedPer, PaymentFrequency.monthly);
      expect(saved?.loanDuration, 10);
    });

    test('a recorded fixed charge is separate from principal payments', () {
      final debt = Debt(
        id: 'fixed',
        direction: DebtDirection.iOwe,
        name: 'Personal loan',
        category: DebtCategory.personalLoan,
        principal: 12000,
        perPayment: 1000,
        paymentCount: 12,
        frequency: PaymentFrequency.monthly,
        firstDueDate: DateTime(2026, 5, 1),
        status: DebtStatus.active,
        balanceBasedSchedule: true,
        fixedInterestAmount: 180,
        interestChargedPer: PaymentFrequency.monthly,
        accruedInterest: 180,
      );
      final paid = BillInstance(
        id: 'paid-month',
        billId: 'bill',
        debtId: debt.id,
        name: debt.name,
        amount: 1000,
        amountPaid: 1000,
        category: 'Bills',
        dueDate: DateTime(2026, 5, 1),
        status: BillStatus.paid,
      );

      final beforePayment = DebtProgress.of(debt, const []);
      final afterPayment = DebtProgress.of(debt, [paid]);
      expect(beforePayment.total, 12180);
      expect(beforePayment.remaining, 12180);
      expect(afterPayment.remaining, 11180);
      expect(debt.loanLeft(afterPayment.paid), 11000);
      expect(debt.interestShare, 0);
    });

    testWidgets('supports daily payment schedules', (tester) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await tester.enterText(find.byKey(const Key('loan-name')), 'Quick loan');
      await tester.enterText(find.byKey(const Key('loan-balance')), '5000');
      await tester.enterText(find.byKey(const Key('loan-payment')), '1000');
      await tester.tap(find.byKey(const ValueKey('loan-frequency-monthly')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every day').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();

      expect(saved?.frequency, PaymentFrequency.daily);
      expect(saved?.frequency.recurrence, BillRecurrence.daily);
      expect(saved?.paymentCount, 5);
    });

    testWidgets('retains the loan source choices', (tester) async {
      await pumpForm(tester, (_) {});
      await tester.tap(find.byType(DropdownButtonFormField<DebtCategory>));
      await tester.pumpAndSettle();
      for (final kind in DebtCategory.loanKinds) {
        expect(find.text(kind.label), findsWidgets, reason: kind.name);
      }
      await tester.tap(find.text(DebtCategory.otherLoan.label).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('loan-other-kind')), findsOneWidget);
    });

    testWidgets('requires a positive balance and payment amount', (
      tester,
    ) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await tester.enterText(find.byKey(const Key('loan-name')), 'BPI loan');
      await tester.tap(find.text('Save Debt'));
      await tester.pump();
      expect(
        find.text('Enter a remaining balance above zero.'),
        findsOneWidget,
      );
      expect(saved, isNull);
    });
  });
}
