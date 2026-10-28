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
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Aircon');
      await tester.enterText(fields.at(1), '30000');
      await tester.enterText(fields.at(2), '12');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('installment-down-payment')),
        '5000',
      );
      await tester.pump();
      // ₱25,000 left after the down payment, split over 12 months. Nothing
      // is added on top: the price is the whole of what is paid.
      expect(
        find.text('12 payments of ₱2,083.33, every month'),
        findsOneWidget,
      );
      expect(find.textContaining('more than you borrowed'), findsNothing);

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

      // Always shown, even though it is optional.
      expect(find.text('Card or account used'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('installment-description')),
        'iPhone 15',
      );
      await tester.enterText(
        find.byKey(const Key('installment-price')),
        '48000',
      );
      await tester.enterText(find.byKey(const Key('installment-months')), '12');
      await tester.tap(find.byKey(const Key('installment-paid-with')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BPI Savings').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save Installment'));
      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();

      expect(saved?.paidWithWalletId, 'bank');
      expect(saved?.paidWithLabel, 'BPI Savings');
    });

    testWidgets('a card that is not a wallet can be typed instead', (
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

      await tester.enterText(
        find.byKey(const Key('installment-description')),
        'Aircon',
      );
      await tester.enterText(
        find.byKey(const Key('installment-price')),
        '30000',
      );
      await tester.enterText(find.byKey(const Key('installment-months')), '12');
      await tester.tap(find.byKey(const Key('installment-paid-with')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Another card or account').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('installment-paid-with-label')),
        'BPI credit card',
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Save Installment'));
      await tester.tap(find.text('Save Installment'));
      await tester.pumpAndSettle();

      // Written down only: no wallet id, because it is not one of theirs.
      expect(saved?.paidWithWalletId, isNull);
      expect(saved?.paidWithLabel, 'BPI credit card');
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

      expect(find.text('Card or account: BPI Savings'), findsOneWidget);
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

    Future<void> fill(
      WidgetTester tester, {
      required String name,
      required String amount,
      String? rate,
      required String count,
    }) async {
      await tester.enterText(find.byKey(const Key('loan-name')), name);
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount borrowed'),
        amount,
      );
      if (rate != null) {
        await tester.enterText(find.byKey(const Key('loan-rate')), rate);
      }
      await tester.enterText(find.byKey(const Key('loan-count')), count);
      await tester.pump();
    }

    String shown(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data!;

    testWidgets('works out Cash2Go the way Metrobank does', (tester) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await fill(
        tester,
        name: 'Cash2Go',
        amount: '5000',
        rate: '1',
        count: '3',
      );

      // The kind came from the name, and the rate is per month for it.
      expect(
        tester.getSemantics(find.byKey(const Key('loan-kind-cardCashLoan'))),
        isSemantics(isSelected: true),
      );
      expect(shown(tester, 'loan-payment'), '₱1,716.67');
      expect(shown(tester, 'loan-total'), '₱5,150');
      expect(shown(tester, 'loan-interest'), '₱150');
      expect(shown(tester, 'loan-true-cost'), '17.9%');
      expect(
        find.text('The last one is ₱1,716.66, from rounding.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();
      expect(saved?.category, DebtCategory.cardCashLoan);
      expect(saved?.perPayment, 1716.67);
      expect(saved?.lastPayment, 1716.66);
      expect(saved?.quotedRate, 1);
      expect(saved?.quotedRatePer, RatePeriod.month);
    });

    testWidgets('20% for the whole loan on ₱5,600 over 12', (tester) async {
      await pumpForm(tester, (_) {});
      await fill(
        tester,
        name: 'Personal loan',
        amount: '5600',
        rate: '20',
        count: '12',
      );
      await tester.tap(
        find.byKey(const ValueKey('loan-rate-per-RatePeriod.month')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Once (whole loan)').last);
      await tester.pumpAndSettle();

      expect(shown(tester, 'loan-payment'), '₱560');
      expect(shown(tester, 'loan-interest'), '₱1,120');
      expect(shown(tester, 'loan-true-cost'), '35.1%');
    });

    testWidgets('a bank or lender must give its interest', (tester) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await fill(tester, name: 'BPI loan', amount: '10000', count: '12');
      expect(find.byKey(const Key('loan-result')), findsNothing);

      await tester.tap(find.text('Save Debt'));
      await tester.pump();
      expect(
        find.textContaining('Enter the interest from your loan papers'),
        findsOneWidget,
      );
      expect(saved, isNull);
    });

    testWidgets('family can lend without interest', (tester) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await fill(tester, name: 'Tita Baby', amount: '6000', count: '12');

      expect(find.text('Interest (optional)'), findsOneWidget);
      expect(shown(tester, 'loan-payment'), '₱500');
      expect(find.byKey(const Key('loan-true-cost')), findsNothing);

      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();
      expect(saved?.category, DebtCategory.familyFriend);
      expect(saved?.quotedRate, isNull);
    });

    testWidgets('choosing who lent it never moves the choices', (tester) async {
      await pumpForm(tester, (_) {});
      Rect place(String kind) =>
          tester.getRect(find.byKey(Key('loan-kind-$kind')));
      final before = {
        for (final kind in DebtCategory.loanKinds) kind.name: place(kind.name),
      };

      await tester.tap(find.byKey(const Key('loan-kind-familyFriend')));
      await tester.pump();

      for (final kind in DebtCategory.loanKinds) {
        expect(place(kind.name), before[kind.name], reason: kind.name);
      }
    });

    testWidgets('Other loan asks what kind it is', (tester) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      expect(find.byKey(const Key('loan-other-kind')), findsNothing);

      await tester.tap(find.byKey(const Key('loan-kind-otherLoan')));
      await tester.pump();
      expect(find.text('What kind of loan?'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('loan-other-kind')),
        'Pawnshop',
      );
      await fill(tester, name: 'Sangla', amount: '3000', count: '3');

      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();
      expect(saved?.category, DebtCategory.otherLoan);
      expect(saved?.otherKind, 'Pawnshop');
    });

    testWidgets('SSS and Pag-IBIG charge on what is left to pay', (
      tester,
    ) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await fill(
        tester,
        name: 'SSS salary loan',
        amount: '20000',
        rate: '10',
        count: '24',
      );

      // A year's rate, on what is left: the lender's own way.
      expect(find.text('How does the interest work?'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const Key('loan-basis-remainingBalance')),
        ),
        isSemantics(isSelected: true),
      );
      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();
      expect(saved?.category, DebtCategory.governmentLoan);
      expect(saved?.quotedRatePer, RatePeriod.year);
      expect(saved?.rateBasis, InterestBasis.remainingBalance);
      // ₱20,000 at 10% a year on what is left, over 24 months.
      expect(saved?.perPayment, closeTo(922.90, 0.01));
    });

    testWidgets("no interest on hand: the payment on the papers will do", (
      tester,
    ) async {
      LoanDraft? saved;
      await pumpForm(tester, (draft) => saved = draft);
      await fill(tester, name: 'BPI loan', amount: '5000', count: '3');

      await tester.tap(
        find.text("Don't know the interest? Enter the payment instead"),
      );
      await tester.pump();
      expect(find.byKey(const Key('loan-rate')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('loan-payment-papers')),
        '1716.67',
      );
      await tester.pump();

      // What it costs comes from the payments alone.
      expect(shown(tester, 'loan-payment'), '₱1,716.67');
      expect(shown(tester, 'loan-true-cost'), '17.9%');

      await tester.tap(find.text('Save Debt'));
      await tester.pumpAndSettle();
      expect(saved?.perPayment, 1716.67);
      expect(saved?.quotedRate, isNull);
    });

    testWidgets('a very costly loan gets a gentle warning', (tester) async {
      await pumpForm(tester, (_) {});
      await fill(
        tester,
        name: 'Lending app',
        amount: '10000',
        rate: '10',
        count: '6',
      );
      expect(find.byKey(const Key('loan-high-cost')), findsOneWidget);
      expect(
        find.textContaining('registered with the government'),
        findsOneWidget,
      );
    });
  });
}
