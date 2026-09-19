import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/bill.dart';
import 'package:testapp/models/chat_answers.dart';
import 'package:testapp/models/debt.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/goal.dart';
import 'package:testapp/models/wallet.dart';

/// Saturday, Sep 19, 2026. A monthly allowance came on Sep 1, so payday is
/// Oct 1, twelve days away.
final now = DateTime(2026, 9, 19, 10);

Wallet wallet(String id, String name, double balance) => Wallet(
  id: id,
  name: name,
  type: WalletType.cash,
  balance: balance,
  startingBalance: balance,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

AppTransaction spend(
  String label,
  double amount,
  DateTime date, {
  String? bill,
  String? debt,
}) => AppTransaction(
  id: '$label-${date.toIso8601String()}',
  type: TransactionType.expense,
  amount: amount,
  label: label,
  date: date,
  billInstanceId: bill,
  debtId: debt,
);

BillInstance bill(String name, double amount, DateTime due) => BillInstance(
  id: name,
  billId: name,
  name: name,
  amount: amount,
  category: 'Bills',
  dueDate: due,
  status: BillStatus.unpaid,
);

/// ₱20,000 in two wallets; ₱150 of food every day for the last month; one
/// Grab ride; a Meralco bill paid; ₱500 lent to Ana; PLDT overdue, Maynilad
/// due Tuesday, rent in October; ₱6,000 toward a laptop; ₱1,000 kept aside.
FinanceSnapshot records() => FinanceSnapshot(
  now: now,
  wallets: [wallet('cash', 'Cash', 5000), wallet('gcash', 'GCash', 15000)],
  transactions: [
    for (
      var day = DateTime(2026, 8, 20);
      !day.isAfter(DateTime(2026, 9, 19));
      day = day.add(const Duration(days: 1))
    )
      spend('Food', 150, day.add(const Duration(hours: 12))),
    spend('Transportation', 200, DateTime(2026, 9, 10)),
    spend('Bills', 2000, DateTime(2026, 9, 5), bill: 'meralco-sep'),
    spend('Lent', 500, DateTime(2026, 9, 12), debt: 'ana'),
    AppTransaction(
      id: 'salary',
      type: TransactionType.income,
      amount: 20000,
      label: 'Allowance',
      date: DateTime(2026, 9, 1),
    ),
  ],
  bills: [
    bill('PLDT', 1500, DateTime(2026, 9, 17)),
    bill('Maynilad', 600, DateTime(2026, 9, 22)),
    bill('Rent', 5000, DateTime(2026, 10, 5)),
  ],
  goals: const [
    Goal(
      id: 'laptop',
      name: 'Laptop',
      targetAmount: 30000,
      savedAmount: 6000,
      priority: 0,
      status: GoalStatus.active,
    ),
  ],
  debts: const [
    Debt(
      id: 'ana',
      direction: DebtDirection.owedToMe,
      name: 'Ana',
      category: DebtCategory.familyFriend,
      principal: 500,
      status: DebtStatus.active,
    ),
    Debt(
      id: 'phone',
      direction: DebtDirection.iOwe,
      name: 'Phone',
      category: DebtCategory.gadget,
      principal: 12000,
      status: DebtStatus.active,
      perPayment: 1500,
      paymentCount: 8,
    ),
  ],
  incomeFrequency: 'Monthly',
  usualIncome: 20000,
  lastIncomeAt: DateTime(2026, 9, 1),
  savingsReserve: 1000,
);

ChatReply ask(
  String message, {
  PurchaseQuestion? pending,
  FinanceSnapshot? from,
  bool loading = false,
}) => answerChat(
  message,
  records: loading ? null : from ?? records(),
  pending: pending,
);

void main() {
  test('with nothing spare, the whole price is what is still needed', () {
    final tight = FinanceSnapshot(
      now: now,
      wallets: [wallet('cash', 'Cash', 1000)],
      transactions: [
        for (
          var day = DateTime(2026, 8, 20);
          !day.isAfter(DateTime(2026, 9, 19));
          day = day.add(const Duration(days: 1))
        )
          spend('Food', 150, day.add(const Duration(hours: 12))),
      ],
      incomeFrequency: 'Monthly',
      lastIncomeAt: DateTime(2026, 9, 1),
    );
    final reply = ask('Can I buy a bike for 5000 this month?', from: tight);
    expect(
      reply.text,
      contains(
        "It doesn't fit this month yet. After your usual ₱150 a day, nothing "
        'would be spare, so all ₱5,000 still needs saving.',
      ),
    );
    expect(reply.text, isNot(contains('short of')));
  });

  group('answers from the user\'s records', () {
    test('what is safe to spend today, as Home works it out', () {
      // (₱20,000 + ₱150 spent today − ₱2,100 bills − ₱1,000 − ₱6,000) over
      // 12 days is ₱920.83 a day; ₱150 of it is spent.
      final reply = ask('How much can I spend today?');
      expect(reply.text, contains('₱770 today'));
      expect(reply.text, contains('₱920 limit'));
      expect(reply.text, contains('12 days left until payday on Oct 1'));
    });

    test('spending in a category, in Taglish', () {
      final reply = ask('Magkano nagastos ko sa food this month?');
      // 19 days of ₱150; all September spending is ₱5,050.
      expect(reply.text, contains('₱2,850 on Food this month'));
      expect(reply.text, contains('19 expenses'));
      expect(reply.text, contains('56%'));
    });

    test('spending in all, and today is not mistaken for the allowance', () {
      expect(
        ask('How much did I spend this month?').text,
        contains(
          '₱5,050 this month. Most of it went to Food (₱2,850) and '
          'Bills (₱2,000)',
        ),
      );
      expect(ask('How much did I spend today?').text, contains('₱150 today'));
    });

    test('money lent out is not spending', () {
      expect(
        ask('How much did I spend this month?').text,
        isNot(contains('Lent')),
      );
    });

    test('where the money goes', () {
      final reply = ask('Where am I spending the most?');
      expect(reply.text, contains('1. Food: ₱2,850 (56%)'));
      expect(reply.text, contains('2. Bills: ₱2,000 (40%)'));
    });

    test('bills this week, overdue first', () {
      final reply = ask('May bills ba ako this week?');
      expect(reply.text, contains('Overdue:\n• PLDT: ₱1,500, Sep 17'));
      expect(reply.text, contains('• Maynilad: ₱600, Sep 22'));
      expect(reply.text, isNot(contains('Rent')));
      expect(reply.text, contains('₱2,100 in all'));
    });

    test('balance, and what of it is free', () {
      final reply = ask('How much money do I have?');
      expect(reply.text, contains('₱20,000 across 2 wallets'));
      expect(reply.text, contains('GCash ₱15,000'));
      // ₱20,000 − ₱2,100 bills − ₱1,000 kept aside − ₱6,000 for goals.
      expect(reply.text, contains('₱10,900 is free to spend until Oct 1'));
    });

    test('savings and goals', () {
      final reply = ask('Ilan na ipon ko?');
      expect(reply.text, contains('Laptop: ₱6,000 of ₱30,000 (20%)'));
      expect(reply.text, contains('₱1,000 as savings'));
    });

    test('debts both ways', () {
      final reply = ask('May utang ba ako?');
      expect(reply.text, contains('Phone: ₱1,500 every month'));
      expect(reply.text, contains('People owe you ₱500'));
    });

    test('Tagalog word forms, and a debt asked about by name', () {
      // "Napautang" is "utang" with a Tagalog affix.
      expect(
        ask('ilan Yung napautang ko kay ana?').text,
        'You lent Ana ₱500, and all of it is still owed to you.',
      );
      expect(ask('Magkano pinautang ko?').text, contains('People owe you'));
      expect(ask('may hiniram ba ako?').text, contains('Phone'));
      expect(
        ask('Magkano ang hulog ko sa phone?').text,
        'For Phone, you pay ₱1,500 every month, 8 payments in all.',
      );
      expect(ask('ilan na naipon ko?').text, contains('Laptop'));
      expect(
        ask('Gumastos ako ng magkano sa food this month?').text,
        contains('₱2,850 on Food this month'),
      );
    });

    test('a question naming someone is about their debt, repaid part too', () {
      final partly = FinanceSnapshot(
        now: now,
        wallets: [wallet('cash', 'Cash', 1000)],
        debts: [
          Debt(
            id: 'ana',
            direction: DebtDirection.owedToMe,
            name: 'Ana',
            category: DebtCategory.familyFriend,
            principal: 500,
            status: DebtStatus.active,
            received: 200,
            dueDate: DateTime(2026, 9, 30),
          ),
        ],
      );
      const answer =
          'You lent Ana ₱500. ₱200 is back, so ₱300 is still owed to you. It '
          'is due back on Sep 30.';
      expect(ask('Nagbayad na ba si Ana?', from: partly).text, answer);
      expect(ask('Has Ana paid me back?', from: partly).text, answer);
      // No one by that name: not taken as a debt question.
      expect(
        ask('Nagbayad na ba si Ben?', from: partly).text,
        isNot(contains('lent')),
      );
    });

    test('income', () {
      expect(ask('How much income this month?').text, contains('₱20,000'));
    });

    test('advice points at the biggest category', () {
      final reply = ask('How can I save more?');
      expect(reply.text, contains('Food at ₱2,850'));
      expect(reply.text, contains('about ₱285 a month'));
    });

    test('greets, redirects what is not about money, and waits for data', () {
      expect(ask('Hi').text, contains("I'm Fin"));
      expect(ask('Hi').choices, suggestedQuestions);
      expect(
        ask('What is the weather tomorrow?').text,
        contains('I can only help with money questions'),
      );
      expect(
        ask('How much can I spend today?', loading: true).text,
        contains('still loading'),
      );
    });
  });

  group('can I buy it?', () {
    test('asks which AirPods, then the price, then answers', () {
      final first = ask('Can I buy AirPods?');
      expect(first.text, contains('Which AirPods'));
      expect(first.choices, containsAll(['AirPods Pro', anyBrand]));
      expect(first.pending?.waitingFor, PurchaseStep.brand);

      final second = ask('AirPods Pro', pending: first.pending);
      expect(second.text, contains('About how much is the AirPods Pro?'));
      expect(second.pending?.waitingFor, PurchaseStep.price);

      // ₱10,900 free, less the usual ₱156 a day (food and one ride), leaves ₱9,172 by payday.
      final answer = ask('₱14,990', pending: second.pending);
      expect(answer.text, contains("It doesn't fit before payday (Oct 1)"));
      expect(answer.text, contains('₱9,172 spare, ₱5,818 short of ₱14,990'));
      // ₱250 a week is within 30% of the ₱1,095 usually spent in a week.
      expect(answer.text, contains('Saving ₱250 a week'));
      expect(answer.goal?.name, 'AirPods Pro');
      expect(answer.goal?.target, 14990);
      expect(answer.goal?.date, DateTime(2027, 3, 20));
      expect(answer.pending, isNull);
    });

    test('a price in the question skips the follow-ups', () {
      final reply = ask('Kaya ko bang bilhin yung sapatos na 3500 this month?');
      expect(
        reply.text,
        contains(
          'Yes, you can buy the sapatos (₱3,500) '
          'this month',
        ),
      );
      expect(reply.text, contains('about ₱5,672 spare'));
      expect(reply.pending, isNull);
    });

    test('a little short: spend less a day, from the user\'s habits', () {
      final reply = ask('Can I afford a ₱10,000 phone?');
      expect(reply.text, contains('Yes, if you spend a little less'));
      expect(reply.text, contains('₱828 short'));
      expect(
        reply.text,
        contains('about ₱87 a day instead of your usual ₱156'),
      );
      expect(reply.text, contains('Food, about ₱155 a day'));
    });

    test('no brand in mind: the most that can safely go to it', () {
      final first = ask('Can I buy a laptop?');
      expect(first.text, contains('brand in mind for the laptop'));
      final answer = ask(anyBrand, pending: first.pending);
      expect(
        answer.text,
        contains(
          'Before payday (Oct 1), the most you can spend on the laptop is '
          'about ₱9,172',
        ),
      );
    });

    test('a later deadline counts the income coming before it', () {
      final reply = ask('Can I buy a ₱40,000 laptop by December?');
      // Three more allowances; rent is also due before then.
      expect(
        reply.text,
        contains(
          'Yes, you can buy the laptop (₱40,000) by '
          'the end of December',
        ),
      );
      expect(reply.text, contains('₱60,000 of income'));
      expect(
        reply.text,
        contains("Bills more than a month away aren't counted"),
      );
    });

    test('something not on the brand list goes straight to the price', () {
      final first = ask('Can I buy a bike?');
      expect(first.text, contains('About how much is the bike?'));
      expect(first.choices, [notSure]);
      final answer = ask(notSure, pending: first.pending);
      expect(answer.text, startsWith("Without a price, I can't check it"));
      expect(
        answer.text,
        contains('the most you can spend on the bike is about ₱9,172'),
      );
      // The price can still be typed after.
      expect(answer.pending?.waitingFor, PurchaseStep.price);
      expect(
        ask('9000', pending: answer.pending).text,
        contains('Yes, you can buy the bike (₱9,000)'),
      );
    });

    test('a named brand is not asked about again', () {
      final reply = ask('Can I buy a Samsung phone?');
      expect(reply.text, contains('About how much is the Samsung phone?'));
    });

    test('asks what, when the question does not say', () {
      final first = ask('Can I afford it?');
      expect(first.text, 'What would you like to buy?');
      final second = ask('Headphones', pending: first.pending);
      expect(second.text, contains('brand in mind for the Headphones'));
    });

    test('another question in the middle starts over', () {
      final first = ask('Can I buy AirPods?');
      final reply = ask('How much can I spend today?', pending: first.pending);
      expect(reply.text, contains('₱770 today'));
      expect(reply.pending, isNull);
    });

    test('a model number is not a price', () {
      final ps5 = ask('Can I buy a PS5?');
      expect(
        ps5.text,
        'About how much is the PS5? Type the price, for example '
        '₱8,990.',
      );
      final iphone = ask('Can I buy an iPhone 16?');
      expect(iphone.text, contains('About how much is the iPhone 16?'));
      // A plain number big enough to be a price still counts, and the
      // goal keeps the brand's own spelling.
      final iphone45 = ask('Pwede ko bang bilhin yung iPhone 16 na 45000?');
      expect(iphone45.text, contains('short of ₱45,000'));
      expect(iphone45.goal?.name, 'iPhone 16');
      // A small price said as money counts too.
      expect(
        ask('Can I buy a snack for 50 pesos?').text,
        contains('Yes, you can buy the snack (₱50)'),
      );
    });

    test('a money question it cannot answer is not called off-topic', () {
      expect(
        ask('Magkano ang pamasahe papuntang Makati?').text,
        contains("I'm not sure what you're asking"),
      );
    });

    test('never keeps asking for the price', () {
      var reply = ask('Can I buy a bike?');
      reply = ask('hmm', pending: reply.pending);
      expect(reply.text, contains('Just type the price'));
      reply = ask('hmm', pending: reply.pending);
      expect(reply.text, contains('the most you can spend'));
    });
  });
}
