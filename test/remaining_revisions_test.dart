import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/models/allocation.dart';
import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/chat_answers.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/finance_snapshot.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/models/savings_suggestion.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/backend/services/finance_snapshot_service.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/savings_suggestion_card.dart';
import 'package:testapp/frontend/widgets/transfer_sheet.dart';

final now = DateTime(2026, 10, 14, 12);
Wallet wallet(
  String id,
  double balance, [
  WalletPurpose purpose = WalletPurpose.spending,
]) => Wallet(
  id: id,
  name: id,
  type: WalletType.cash,
  balance: balance,
  startingBalance: balance,
  receivesIncome: purpose == WalletPurpose.spending,
  archived: false,
  sortOrder: 0,
  purpose: purpose,
);
AppTransaction expense(DateTime date, {double amount = 100, String? billId}) =>
    AppTransaction(
      id: date.toIso8601String(),
      type: TransactionType.expense,
      amount: amount,
      label: 'Food',
      date: date,
      billInstanceId: billId,
    );
BillInstance bill(double amount) => BillInstance(
  id: 'rent',
  billId: 'rent',
  name: 'Rent',
  amount: amount,
  category: 'Bills',
  dueDate: DateTime(2026, 10, 15),
  status: BillStatus.unpaid,
);
FinanceSnapshot records({
  double balance = 10000,
  double billsMoney = 500,
  int spendingDays = 7,
  double due = 1500,
  String frequency = 'Monthly',
}) => FinanceSnapshot(
  now: now,
  incomeFrequency: frequency,
  lastIncomeAt: DateTime(2026, 10, 1),
  wallets: [
    wallet('Cash', balance),
    wallet('Bills', billsMoney, WalletPurpose.bills),
    wallet('Savings', 2000, WalletPurpose.savings),
  ],
  transactions: [
    for (var i = 0; i < spendingDays; i++) expense(DateTime(2026, 10, 14 - i)),
  ],
  bills: [bill(due)],
);

void main() {
  group('savings from remaining money', () {
    test('reserves uncovered bills and daily costs, leaving a buffer', () {
      final suggestion = SavingsSuggestion.from(records());
      expect(suggestion.available, 9000);
      // 18 days including today, less the 100 already spent today.
      expect(suggestion.dailyCosts, 1700);
      expect(suggestion.amount, 730);
    });
    test('bills still due this month are held back in full', () {
      // ₱10,000 in the wallets, ₱1,500 of bills not paid yet.
      expect(SavingsSuggestion.from(records(billsMoney: 0)).available, 8500);
    });
    test('cannot suggest saving when obligations exceed the balance', () {
      expect(SavingsSuggestion.from(records(balance: 100)).amount, 0);
    });
    test('daily costs can consume all remaining money', () {
      expect(SavingsSuggestion.from(records(balance: 2600)).amount, 0);
    });
    test('a new account does not assume daily costs are zero', () {
      final result = SavingsSuggestion.from(records(spendingDays: 0));
      expect(result.hasHistory, isFalse);
      expect(result.amount, 0);
      expect(
        SavingsSuggestion.from(records(spendingDays: 6)).hasHistory,
        isFalse,
      );
    });
    test(
      'bill payments and future expenses cannot establish spending history',
      () {
        final result = SavingsSuggestion.from(
          FinanceSnapshot(
            now: now,
            wallets: [wallet('Cash', 50000)],
            transactions: [
              for (var i = 0; i < 7; i++)
                expense(DateTime(2026, 10, 14 - i), billId: 'rent'),
              for (var i = 0; i < 7; i++) expense(DateTime(2026, 11, 1 + i)),
            ],
          ),
        );
        expect(result.hasHistory, isFalse);
        expect(result.amount, 0);
      },
    );
    test('goal money in spending wallets is protected', () {
      final base = records();
      final result = SavingsSuggestion.from(
        FinanceSnapshot(
          now: now,
          wallets: base.wallets,
          bills: base.bills,
          transactions: base.transactions,
          incomeFrequency: 'Monthly',
          lastIncomeAt: base.lastIncomeAt,
          goals: const [
            Goal(
              id: 'g',
              name: 'School',
              targetAmount: 5000,
              savedAmount: 2000,
              priority: 0,
              status: GoalStatus.active,
              savedByWallet: {'Cash': 1000, 'Savings': 1000},
            ),
          ],
        ),
      );
      expect(result.available, 8000);
      expect(result.amount, 630);
    });
    test('irregular income uses month end without inventing a payday', () {
      expect(
        SavingsSuggestion.from(records(frequency: 'Irregular')).amount,
        730,
      );
    });
    test('overspending today does not reduce future daily allowances', () {
      final base = records();
      final result = SavingsSuggestion.from(
        FinanceSnapshot(
          now: now,
          wallets: base.wallets,
          bills: base.bills,
          incomeFrequency: 'Monthly',
          lastIncomeAt: base.lastIncomeAt,
          transactions: [
            for (var i = 1; i <= 6; i++) expense(DateTime(2026, 10, 14 - i)),
            expense(DateTime(2026, 10, 14), amount: 1000),
          ],
        ),
      );
      expect(result.dailyCosts, closeTo((1600 / 7) * 17, 0.001));
    });
    test('rounds down to a centavo', () {
      expect(SavingsSuggestion.from(records(balance: 10000.09)).amount, 730);
    });
  });

  group('formula answers', () {
    test(
      'installment balance questions explain the installment, not a wallet',
      () {
        final reply = answerChat(
          'How is my remaining installment balance calculated?',
          records: records(),
        );
        expect(reply.text, contains('Remaining balance = total to pay'));
        expect(reply.text, isNot(contains('A wallet balance starts')));
      },
    );
    test(
      'Safe to Spend questions keep their topic when expenses are mentioned',
      () {
        final reply = answerChat(
          'How is Safe to Spend calculated after my expenses and bills?',
          records: records(),
        );
        expect(reply.text, contains('₱405.56'));
        expect(reply.text, isNot(startsWith('Reports add')));
      },
    );
    test('savings questions keep their topic when bills are mentioned', () {
      final reply = answerChat(
        'How are suggested savings calculated after bills and expenses?',
        records: records(),
      );
      expect(reply.text, contains('Suggested to save: ₱730'));
    });
    test('goal balance questions explain the goal target', () {
      final reply = answerChat(
        'How is my goal balance calculated?',
        records: records(),
      );
      expect(reply.text, contains('Goal amount still needed = target'));
    });
    test(
      'a Tagalog question about money taken keeps the existing debt answer',
      () {
        final reply = answerChat(
          'Magkano ang kinuha ni Ana?',
          records: FinanceSnapshot(
            now: now,
            debts: const [
              Debt(
                id: 'ana',
                name: 'Ana',
                direction: DebtDirection.iOwe,
                category: DebtCategory.familyFriend,
                principal: 500,
                perPayment: 250,
                paymentCount: 2,
                status: DebtStatus.active,
              ),
            ],
          ),
        );
        expect(reply.text, contains('For Ana, you pay'));
        expect(reply.text, isNot(contains('Safe to Spend is worked out')));
      },
    );
    test('Tagalog question explains actual Safe to Spend arithmetic', () {
      final reply = answerChat(
        'Anong formula ang ginamit?',
        records: records(),
      );
      expect(reply.text, contains('bills still to pay this month ₱1,500'));
      expect(reply.text, contains('₱505.56'));
      expect(reply.text, contains('₱405.56'));
      expect(reply.text, contains('through the end of this calendar month'));
    });
    test('specific savings formula agrees with the savings suggestion', () {
      final reply = answerChat(
        'Paano kinukwenta ang savings?',
        records: records(),
      );
      expect(reply.text, contains('₱730'));
      expect(reply.text, contains('10%'));
    });
    test('installment explanation works without loading private figures', () {
      final reply = answerChat('Anong formula ng hulog?', records: null);
      expect(reply.text, contains('the last one takes'));
      expect(reply.text, contains('Part payments'));
      expect(reply.text, isNot(contains('Safe to Spend')));
    });
    test('goal deadlines are distinguished from affordability', () {
      expect(
        answerChat('Goal formula', records: null).text,
        contains('not what you can afford'),
      );
    });
    test('report explanation distinguishes transfers and loans', () {
      final text = answerChat(
        'How are reports calculated?',
        records: null,
      ).text;
      expect(text, contains('Transfers between your wallets'));
      expect(text, contains('borrowed money'));
    });
    test('formula question interrupts a pending purchase', () {
      final reply = answerChat(
        'Safe to Spend formula',
        records: records(),
        pending: PurchaseQuestion(
          deadline: DateTime(2026, 11, 1),
          deadlineLabel: 'this month',
          waitingFor: PurchaseStep.price,
          item: 'Phone',
        ),
      );
      expect(reply.pending, isNull);
      expect(reply.text, contains('Spending wallets'));
    });
    test('irregular income explanation says month end', () {
      expect(
        answerChat(
          'Anong formula?',
          records: records(frequency: 'Irregular'),
        ).text,
        contains('through the end of this calendar month'),
      );
    });
    test('no records means no invented personal figures', () {
      final reply = answerChat('Anong formula?', records: null);
      expect(reply.text, contains('once your records load'));
      expect(reply.text, isNot(contains('₱')));
    });
  });

  testWidgets('savings suggestion is readable and requires a review tap', (
    tester,
  ) async {
    double? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SavingsSuggestionCard(
                records: records(),
                onTransfer: (a) => chosen = a,
              ),
            ),
          ),
        ),
      ),
    );
    expect(chosen, isNull);
    expect(find.text('₱730'), findsOneWidget);
    await tester.ensureVisible(find.text('Review savings transfer'));
    await tester.tap(find.text('Review savings transfer'));
    expect(chosen, 730);
    expect(tester.takeException(), isNull);
  });
  testWidgets('no savings transfer is offered with insufficient history', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SavingsSuggestionCard(
            records: records(spendingDays: 0),
            onTransfer: (_) => fail('must not transfer'),
          ),
        ),
      ),
    );
    expect(find.textContaining('7 different days'), findsOneWidget);
    expect(find.text('Review savings transfer'), findsNothing);
  });
  testWidgets('suggested transfer stays editable before confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransferSheet(
            wallets: Stream.value([
              wallet('Cash', 1000),
              Wallet(
                id: 'savings',
                name: 'BPI Savings',
                type: WalletType.bank,
                balance: 0,
                startingBalance: 0,
                receivesIncome: false,
                archived: false,
                sortOrder: 1,
                purpose: WalletPurpose.savings,
              ),
            ]),
            initialToWalletId: 'savings',
            initialAmount: 730,
          ),
        ),
      ),
    );
    await tester.pump();
    // The suggested amount is filled in on the savings account, and stays
    // editable.
    final field = find.byKey(const Key('goes-to-savings'));
    expect(find.descendant(of: field, matching: find.text('730')), findsOne);
    await tester.enterText(field, '500');
    expect(find.text('500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('complete financial records', () {
    Future<void> flush() => Future<void>.delayed(Duration.zero);
    test('waits for bills and goals before publishing any estimate', () async {
      final goals = StreamController<List<Goal>>();
      final bills = Completer<List<BillInstance>>();
      final values = <FinanceSnapshot>[];
      final subscription = watchFinanceSnapshot(
        walletStream: Stream.value([wallet('Cash', 10000)]),
        transactionStream: Stream.value(const <AppTransaction>[]),
        profileStream: Stream.value({'incomeFrequency': 'Monthly'}),
        cycleStream: Stream.value(const <AllocationCycle>[]),
        goalStream: goals.stream,
        debtStream: Stream.value(const <Debt>[]),
        billStream: Stream.value(const <Bill>[]),
        loadBills: () => bills.future,
        clock: () => now,
      ).listen(values.add);
      await flush();
      expect(values, isEmpty);
      goals.add(const []);
      await flush();
      expect(values, isEmpty);
      bills.complete([bill(1500)]);
      await flush();
      expect(values, hasLength(1));
      expect(values.single.safeToSpend.billsDue, 1500);
      await subscription.cancel();
      await goals.close();
    });
    test(
      'a failed bill read cannot publish a zero-obligations estimate',
      () async {
        final values = <FinanceSnapshot>[];
        final errors = <Object>[];
        final subscription = watchFinanceSnapshot(
          walletStream: Stream.value([wallet('Cash', 10000)]),
          transactionStream: Stream.value(const <AppTransaction>[]),
          profileStream: Stream.value({'incomeFrequency': 'Monthly'}),
          cycleStream: Stream.value(const <AllocationCycle>[]),
          goalStream: Stream.value(const <Goal>[]),
          debtStream: Stream.value(const <Debt>[]),
          billStream: Stream.value(const <Bill>[]),
          loadBills: () => Future.error(StateError('offline without cache')),
        ).listen(values.add, onError: errors.add);
        await flush();
        expect(values, isEmpty);
        expect(errors, isNotEmpty);
        await subscription.cancel();
      },
    );
  });
}
