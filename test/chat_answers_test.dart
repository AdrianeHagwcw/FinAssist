import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/bill.dart';
import 'package:testapp/models/chat_answers.dart';
import 'package:testapp/models/chat_language.dart';
import 'package:testapp/models/debt.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/financial_ai_guardrails.dart';
import 'package:testapp/models/financial_topic_validator.dart';
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
      direction: DebtDirection.iOwe,
      name: 'Ana',
      category: DebtCategory.familyFriend,
      principal: 500,
      status: DebtStatus.active,
      perPayment: 250,
      paymentCount: 2,
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
);

ChatReply ask(
  String message, {
  PurchaseQuestion? pending,
  FinanceSnapshot? from,
  bool loading = false,
  String? contextMessage,
  ChatLanguage? language,
}) => answerChat(
  message,
  records: loading ? null : from ?? records(),
  pending: pending,
  contextMessage: contextMessage,
  language: language,
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
      expect(reply.text, contains('₱854 today'));
      expect(reply.text, contains('₱1,004 limit'));
      expect(reply.text, contains('12 days left in this month through Sep 30'));
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

    test('a Taglish request for insights has English and Tagalog', () {
      const question =
          'kaya mo ba akong bigyan ng maayos na insights sa susunod';

      // English first; the Tagalog is ready for the bubble's button.
      expect(ask(question).text, contains('help explain your recorded'));
      expect(
        ask(question, language: ChatLanguage.taglish).text,
        contains('rekord na nasa FinAssist'),
      );
    });

    test('categorizes multiple expenses using the shared category keywords', () {
      final reply = ask(
        'I spent ₱150 on lunch, ₱50 on jeepney fare, and ₱200 on mobile data.',
      );

      expect(reply.text, contains('₱150 — lunch: Food'));
      expect(reply.text, contains('₱50 — jeepney fare: Transportation'));
      expect(reply.text, contains('₱200 — mobile data: Bills'));
      expect(reply.useLocalAnswer, isTrue);
    });

    test(
      'compares recorded spending over requested day, week and month windows',
      () {
        final reply = ask(
          'Compare my spending pattern from the past few days, weeks and months',
        );

        expect(reply.text, contains('the last three days'));
        expect(reply.text, contains('the last week'));
        expect(reply.text, contains('the last thirty days'));
        expect(reply.text, contains('the last three months'));
        expect(reply.text, contains('missing entries may change the picture'));
        expect(
          reply.text,
          contains('These comparisons use only expenses recorded'),
        );
      },
    );

    test('bills this week, overdue first', () {
      final reply = ask('May bills ba ako this week?');
      expect(reply.text, contains('Overdue:\n• PLDT: ₱1,500, Sep 17'));
      expect(reply.text, contains('• Maynilad: ₱600, Sep 22'));
      expect(reply.text, isNot(contains('Rent')));
      expect(reply.text, contains('₱2,100 in all'));
    });

    test('balance, and what of it is free', () {
      final reply = ask('How much money do I have?');
      expect(reply.text, contains('₱20,000 available across 2 wallets'));
      expect(reply.text, contains('GCash ₱15,000'));
      // ₱20,000 − ₱2,100 bills − ₱6,000 for goals.
      expect(reply.text, contains('₱11,900 is free to spend until Sep 30'));
    });

    test('savings and goals', () {
      final reply = ask('Ilan na ipon ko?');
      expect(reply.text, contains('Laptop: ₱6,000 of ₱30,000 (20%)'));
      // Savings live in a savings record now, so there is no separate
      // reserve to report beside the goals.
      expect(reply.text, isNot(contains('as savings')));
    });

    test('calculates possible savings separately from saved goals', () {
      final weekly = ask(
        'Magkano ang maipon ko this week based sa expenses ko?',
      );
      expect(weekly.text, contains("don't have any recorded income"));
      expect(weekly.text, contains('this week'));
      expect(weekly.text, isNot(contains("You've spent")));

      final fromIncome = ask('How much can I save from my income?');
      expect(fromIncome.text, contains('left to save this month'));
      expect(fromIncome.text, isNot(contains("You've received")));
    });

    test('compares a proposed amount with the safe amount for today', () {
      final reply = ask('How about 400?');
      expect(reply.text, contains('fits within'));
      expect(reply.text, contains('left-to-spend amount'));

      final direct = ask('Pwede ba akong gumastos ng 300 today?');
      expect(direct.text, contains('fits within'));
    });

    test('the debts the user is paying', () {
      final reply = ask('May utang ba ako?');
      expect(reply.text, contains('Phone: ₱1,500 every month'));
      expect(reply.text, isNot(contains('owe you')));
    });

    test('Tagalog word forms, and a debt asked about by name', () {
      // "Nautangan" is "utang" with a Tagalog affix.
      expect(
        ask('ilan Yung nautangan ko kay ana?').text,
        'For Ana, you pay ₱250 every month, 2 payments in all.',
      );
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

    test('a question naming someone is about the debt owed to them', () {
      final partly = FinanceSnapshot(
        now: now,
        wallets: [wallet('cash', 'Cash', 1000)],
        debts: [
          Debt(
            id: 'ana',
            direction: DebtDirection.iOwe,
            name: 'Ana',
            category: DebtCategory.familyFriend,
            principal: 500,
            status: DebtStatus.active,
            perPayment: 250,
            paymentCount: 2,
            dueDate: DateTime(2026, 9, 30),
          ),
        ],
      );
      const answer = 'For Ana, you pay ₱250 every month, 2 payments in all.';
      expect(ask('Nagbayad na ba si Ana?', from: partly).text, answer);
      expect(ask('Has Ana been paid?', from: partly).text, answer);
      // No one by that name: not taken as a debt question.
      expect(
        ask('Nagbayad na ba si Ben?', from: partly).text,
        isNot(contains('For Ben')),
      );
    });

    test('income', () {
      expect(ask('How much income this month?').text, contains('₱20,000'));
    });

    test('income questions are not routed to spending answers', () {
      final reply = ask('What was my biggest income this month?');
      expect(reply.text, contains('Your biggest income this month'));
      expect(reply.text, contains('₱20,000'));
      expect(reply.text, isNot(contains('spending')));
    });

    test('returns the smallest recorded income', () {
      final base = records();
      final snapshot = FinanceSnapshot(
        now: base.now,
        wallets: base.wallets,
        transactions: [
          ...base.transactions,
          AppTransaction(
            id: 'small-income',
            type: TransactionType.income,
            amount: 500,
            label: 'Side job',
            date: DateTime(2026, 9, 10),
          ),
        ],
        bills: base.bills,
        goals: base.goals,
        debts: base.debts,
        incomeFrequency: base.incomeFrequency,
        usualIncome: base.usualIncome,
        lastIncomeAt: base.lastIncomeAt,
        periodBudget: base.periodBudget,
      );
      final reply = ask(
        'What is my smallest income this month?',
        from: snapshot,
      );
      expect(reply.text, contains('Your smallest income this month'));
      expect(reply.text, contains('₱500'));
      expect(reply.text, contains('Side job'));
    });

    test('returns the smallest expense and biggest unpaid bill', () {
      final base = records();
      final snapshot = FinanceSnapshot(
        now: base.now,
        wallets: base.wallets,
        transactions: [
          ...base.transactions,
          spend('Snack', 25, DateTime(2026, 9, 11)),
        ],
        bills: base.bills,
        goals: base.goals,
        debts: base.debts,
        incomeFrequency: base.incomeFrequency,
        usualIncome: base.usualIncome,
        lastIncomeAt: base.lastIncomeAt,
        periodBudget: base.periodBudget,
      );
      expect(
        ask('What is my smallest expense this month?', from: snapshot).text,
        contains('₱25'),
      );
      expect(
        ask('What is my biggest bill?', from: snapshot).text,
        contains('Rent'),
      );
    });

    test('calculates a savings target from an amount and timeline', () {
      final reply = ask(
        'Based on my current income, how much money do I need to save '
        'every day to get 50000 in 3 months?',
      );
      expect(reply.isVerifiedGoalPlan, isTrue);
      expect(reply.text, contains('per day for 3 months'));
      expect(reply.text, contains('₱50,000 remaining'));
      expect(reply.text, contains('recorded income and spending'));
    });

    test('calculates a general Tagalog savings target', () {
      final reply = ask(
        'pano ako makakaipon ng 40000 sa loob ng 3months kung araw araw '
        'ako mag ipon',
        language: ChatLanguage.tagalog,
      );
      expect(reply.isVerifiedGoalPlan, isTrue);
      expect(reply.text, contains('sa loob ng 3 buwan'));
      expect(reply.text, contains('₱40,000'));
      expect(reply.text, contains('₱444.45 araw-araw'));
      expect(reply.text, contains('₱13,333.34 kada buwan'));
    });

    test('converts a monthly savings target to a daily target', () {
      final reply = ask(
        'If I need 16666.67 per month, how much do I need to save per day?',
      );
      expect(reply.text, contains('₱16,666.67 per month'));
      expect(reply.text, contains('₱555.56 per day'));
      expect(reply.text, isNot(contains('₱13,470 left to save')));
    });

    test('uses the previous monthly target for a short daily follow-up', () {
      final reply = ask(
        'how much do I need to save per day?',
        contextMessage: 'If I need 16666.67 per month',
      );
      expect(reply.text, contains('₱16,666.67 per month'));
      expect(reply.text, contains('₱555.56 per day'));
    });

    test('calculates a daily savings projection against a target', () {
      final reply = ask('If I saved 2000 daily can I have 100000 in a year?');
      expect(reply.text, contains('₱730,000'));
      expect(reply.text, contains('yes'));
      expect(reply.text, contains('₱630,000'));
      expect(reply.text, contains('recorded expenses'));
    });

    test('answers a savings plan from reliable income and spending data', () {
      final reply = ask(
        'Can you give me a savings plan based on my current income and '
        'expenses including the bills?',
      );
      expect(reply.text, contains('Here is a savings plan based on your'));
      expect(reply.text, contains('recorded income'));
      expect(reply.text, contains('recorded expenses'));
      expect(reply.text, contains('bills currently needing coverage'));
      expect(reply.text, isNot(contains("You've spent")));
    });

    test('requests more data before making an unreliable savings plan', () {
      final sparse = FinanceSnapshot(
        now: now,
        transactions: [
          AppTransaction(
            id: 'income',
            type: TransactionType.income,
            amount: 20000,
            label: 'Salary',
            date: now,
          ),
        ],
      );
      final reply = ask(
        'Give me a savings plan based on my income and expenses.',
        from: sparse,
      );
      expect(reply.text, contains('cannot make a reliable savings plan yet'));
      expect(reply.text, contains('7 different days'));
      expect(reply.text, contains('record your income and everyday expenses'));
    });

    test('asks for clarification for an unclear financial question', () {
      final reply = ask('What should I do with my money situation?');
      expect(reply.text, contains('need a little more detail'));
      expect(reply.choices, contains('How much can I save?'));
    });

    test('advice gives the same tips as Reports', () {
      final reply = ask('How can I save more?');
      expect(reply.text, contains('Food takes the biggest share'));
      expect(reply.text, contains('baon'));
      // Shown under Gemini's answer online, not replaced by it.
      expect(reply.keepUnderAi, isTrue);
      expect(reply.useLocalAnswer, isFalse);
    });

    test('plans a purchase goal from the stated price and timeline', () {
      final reply = ask(
        'I want to buy a house worth 4999999 in the next 2 years '
        'how should i save my money?',
      );

      expect(reply.isVerifiedGoalPlan, isTrue);
      expect(
        reply.text,
        contains('₱208,333.30 per month for 24 months (₱4,999,999 remaining)'),
      );
      expect(reply.text, contains('does not assume investment returns'));
      expect(reply.text, contains('rather than cutting necessary expenses'));
    });

    test('plans a daily savings target from a Taglish house question', () {
      const question =
          'gusto kong bumili ng bahay worth 5000000 in the next 2 years '
          'magkano ang dapat kong I save everyday para makabili ng bahay?';
      // Taglish: English first.
      expect(ask(question).text, contains('₱6,839.95 per day'));

      final reply = ask(question, language: ChatLanguage.taglish);
      expect(reply.isVerifiedGoalPlan, isTrue);
      expect(reply.text, contains('₱6,839.95 araw-araw'));
      expect(reply.text, contains('₱5,000,000 pa ang kailangang ipunin'));
      expect(reply.text, contains('Ihambing ang target sa aktuwal mong kita'));
    });

    test('uses only savings recorded in a matching active goal', () {
      final snapshot = FinanceSnapshot(
        now: now,
        goals: const [
          Goal(
            id: 'home',
            name: 'House',
            targetAmount: 4999999,
            savedAmount: 999999,
            priority: 0,
            status: GoalStatus.active,
          ),
        ],
      );
      final reply = ask(
        'I want to buy a house worth 4999999 in the next 2 years '
        'how should i save my money?',
        from: snapshot,
      );

      expect(reply.text, contains('₱166,666.67 per month'));
      expect(reply.text, contains('₱999,999 set aside'));
    });

    test('does not claim goal savings when records are still loading', () {
      final reply = ask(
        'I want to buy a house worth 4999999 in the next 2 years '
        'how should i save my money?',
        loading: true,
      );

      expect(reply.text, contains('saved goals have not loaded'));
      expect(reply.text, isNot(contains('No savings are recorded')));
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
    test('extracts only a product name for current-price searches', () {
      expect(productPriceLookupQuery('How much are AirPods?'), 'AirPods');
      expect(
        productPriceLookupQuery('What is the current price of AirPods Pro?'),
        'AirPods Pro',
      );
      expect(
        productPriceLookupQuery(
          'How much does Apple AirPods Pro 3 cost in the Philippines today? '
          'Please show current sellers and source links.',
        ),
        'Apple AirPods Pro 3',
      );
      expect(
        productPriceLookupQuery('Magkano ang iPhone 17 sa Philippines?'),
        'iPhone 17',
      );
      expect(
        productPriceLookupQuery(
          'magkano ang maipon ko this week based sa expenses ko',
        ),
        isNull,
      );
      expect(productPriceLookupQuery('magkano ang ipon ko'), isNull);
      expect(
        productPriceLookupQuery('Can I buy AirPods with my ₱50,000 salary?'),
        isNull,
        reason:
            'Explicit purchase price or personal finance should not be '
            'sent to web search.',
      );
      expect(productPriceLookupQuery('Can I buy AirPods?'), 'AirPods');
    });

    test('asks which AirPods, then the price, then answers', () {
      final first = ask('Can I buy AirPods?');
      expect(first.text, contains('Which AirPods'));
      expect(first.choices, containsAll(['AirPods Pro', anyBrand]));
      expect(first.pending?.waitingFor, PurchaseStep.brand);

      final second = ask('AirPods Pro', pending: first.pending);
      expect(second.text, contains('About how much is the AirPods Pro?'));
      expect(second.pending?.waitingFor, PurchaseStep.price);

      // ₱11,900 free, less the usual ₱156 a day (food and one ride),
      // leaves ₱10,172 by month end.
      final answer = ask('₱14,990', pending: second.pending);
      expect(answer.text, contains("It doesn't fit by month end (Sep 30)"));
      expect(answer.text, contains('₱10,172 spare, ₱4,818 short of ₱14,990'));
      // The month's ₱20,000 allowance less ₱6,850 spent, over the last 31
      // days, leaves about ₱12,726 a month: one more month covers it.
      expect(
        answer.text,
        contains('At your usual pace, about ₱12,726 is left each month'),
      );
      expect(
        answer.text,
        contains("Saving that, you'd have enough by about October 2026"),
      );
      expect(answer.goal?.name, 'AirPods Pro');
      expect(answer.goal?.target, 14990);
      expect(answer.goal?.date, DateTime(2026, 10, 31));
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
      expect(reply.text, contains('about ₱6,672 spare'));
      expect(reply.pending, isNull);
    });

    test('a little short: spend less a day, from the user\'s habits', () {
      final reply = ask('Can I afford a ₱11,000 phone?');
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
          'By month end (Sep 30), the most you can spend on the laptop is '
          'about ₱10,172',
        ),
      );
    });

    test('a later deadline counts what is usually left each month', () {
      final reply = ask('Can I buy a ₱40,000 laptop by December?');
      // ₱10,172 by month end, then about ₱12,726 in each of Oct, Nov and Dec.
      expect(
        reply.text,
        contains(
          'Yes, you can buy the laptop (₱40,000) by the end of December',
        ),
      );
      expect(reply.text, contains("what's usually left of your income"));
      expect(reply.text, isNot(contains('does not include future income')));
    });

    test('something not on the brand list goes straight to the price', () {
      final first = ask('Can I buy a bike?');
      expect(first.text, contains('About how much is the bike?'));
      expect(first.choices, [notSure]);
      final answer = ask(notSure, pending: first.pending);
      expect(answer.text, startsWith("Without a price, I can't check it"));
      expect(
        answer.text,
        contains('the most you can spend on the bike is about ₱10,172'),
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
      expect(reply.text, contains('₱854 today'));
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

  group('budgeting', () {
    test('how to budget walks through the records', () {
      final reply = ask('Paano mag budget?');
      expect(reply.text, contains('A simple way to budget'));
      expect(reply.text, contains('₱2,100 in bills to pay this month'));
      expect(
        reply.text,
        contains('10% of the ₱20,000 you received this month is ₱2,000'),
      );
      expect(reply.text, contains('Today you can spend'));
      expect(reply.keepUnderAi, isTrue);
      expect(reply.choices, contains('How should I budget ₱20,000?'));
    });

    test('"help me budget" is about budgeting, not about Fin', () {
      expect(ask('Can you help me budget?').text, contains('Pay bills first'));
      expect(
        ask('How should I divide my salary?').text,
        contains('Pay bills first'),
      );
    });

    test('an amount is split: bills, then savings, then each day', () {
      final reply = ask('Paano ko ibubudget ang 15000 na sahod ko?');
      expect(reply.text, contains('Here is a simple way to budget ₱15,000'));
      expect(reply.text, contains('Bills first: ₱2,100'));
      expect(reply.text, contains('Savings next: ₱1,500 (10%)'));
      expect(reply.text, contains('The rest, ₱11,400'));
      expect(reply.text, contains('about ₱380 a day or ₱2,660 a week'));
      expect(reply.useLocalAnswer, isTrue);
    });

    test('for two weeks, it lasts two weeks', () {
      final reply = ask('How should I budget ₱8,000 for 2 weeks?');
      // ₱8,000 − ₱2,100 bills − ₱800 saved = ₱5,100 over 15 days.
      expect(reply.text, contains('about ₱340 a day'));
      expect(reply.text, contains('if it has to last two weeks'));
    });

    test('needs come before saving when bills take most of it', () {
      final tight = ask('How should I budget ₱2,500?');
      expect(tight.text, isNot(contains('Savings next')));
      expect(tight.text, contains('Skip saving this time'));

      final short = ask('How should I budget ₱1,000?');
      expect(short.text, contains('more than ₱1,000'));
    });

    test("the 50/30/20 rule, on this month's income", () {
      final reply = ask('What is the 50/30/20 rule?');
      expect(reply.text, contains('50% for needs'));
      expect(
        reply.text,
        contains(
          'about ₱10,000 for needs, ₱6,000 for wants and ₱4,000 for savings',
        ),
      );
      expect(reply.useLocalAnswer, isTrue);
    });

    test('an emergency fund, from the last 30 days of spending', () {
      final reply = ask('How much should my emergency fund be?');
      expect(reply.text, contains('3 to 6 months'));
      expect(
        reply.text,
        contains(
          'Based on the ₱6,550 you spent in the last 30 days, 3 months is '
          'about ₱19,650 and 6 months about ₱39,300',
        ),
      );
    });

    test('is the budget enough: bills against what is free', () {
      final enough = ask('Is my budget enough for this month?');
      expect(enough.text, startsWith("You're covered."));
      expect(enough.text, contains('enough for the ₱2,100 in bills'));
      expect(enough.text, contains('until Sep 30'));

      final short = ask(
        'Sapat ba ang pera ko hanggang katapusan?',
        from: FinanceSnapshot(
          now: now,
          wallets: [wallet('cash', 'Cash', 1000)],
          bills: [bill('Rent', 5000, DateTime(2026, 9, 25))],
        ),
      );
      expect(short.text, startsWith("You're short."));
      expect(short.text, contains('short by ₱4,000'));
    });

    test('tips never say to cut back on health', () {
      final reply = ask(
        'Tips para makaipon',
        from: FinanceSnapshot(
          now: now,
          wallets: [wallet('cash', 'Cash', 3000)],
          transactions: [
            spend('Health', 6000, DateTime(2026, 9, 8)),
            spend('Food', 1500, DateTime(2026, 9, 9)),
          ],
        ),
      );
      expect(reply.text, isNot(contains('Health')));
      expect(reply.text, isNot(contains('less')));
      expect(reply.text, contains('emergency fund'));
    });
  });

  test('the same question in English or Filipino gets the same answer', () {
    const pairs = [
      ('How do I budget?', 'Paano mag-budget?'),
      ('How do I manage my money?', 'Paano i-manage ang pera ko?'),
      ('How should I budget 15000?', 'Paano ko pagkakasyahin ang 15000?'),
      ('What is the 50/30/20 rule?', 'Ano ang 50/30/20 rule?'),
      (
        'How much should my emergency fund be?',
        'Gaano kalaki dapat ang ipon ko para sa emergency?',
      ),
      (
        'Will my money last until the end of the month?',
        'Kukulangin ba ang pera ko ngayong buwan?',
      ),
      ('Give me money saving tips', 'Mga paraan para magtipid'),
      ('What is my biggest expense?', 'Ano ang pinakamalaking gastos ko?'),
      ('Who owes me money?', 'Sino ang may utang sa akin?'),
      (
        'How much did I earn this month?',
        'Magkano ang kinita ko ngayong buwan?',
      ),
      ('How much can I spend today?', 'Magkano pa pwede kong gastusin ngayon?'),
      ('Where does my money go?', 'Saan napupunta ang pera ko?'),
      ('How much money do I have?', 'Magkano ang pera ko?'),
    ];
    for (final (english, filipino) in pairs) {
      expect(ask(filipino).text, ask(english).text, reason: filipino);
      expect(ask(english).text, isNot(contains("I'm not sure")));
      // Online, Gemini is asked in either language.
      expect(isFinancialTopic(filipino), isTrue, reason: filipino);
    }
  });

  group('in Filipino', () {
    ChatReply tagalog(String question) => answerChat(
      question,
      records: records(),
      language: ChatLanguage.tagalog,
    );

    test('common answers are in Filipino, with the same figures', () {
      for (final question in [
        'hello',
        'What can you do?',
        'How much can I spend today?',
        'How much did I spend this month?',
        'How much did I spend on food this month?',
        'What is my biggest expense?',
        'Where does my money go?',
        'May bills ba ako this week?',
        'How much money do I have?',
        'How much have I saved?',
        'Who do I owe?',
        'How much did I earn this month?',
        'How much can I save this month?',
        'How do I budget?',
        'How should I budget 15000?',
        'What is the 50/30/20 rule?',
        'How much should my emergency fund be?',
        'Is my budget enough for this month?',
        'Give me money saving tips',
        'What should I do with my money situation?',
        // The rarer answers.
        'Can you give me insights?',
        'Safe to Spend formula',
        'Suggested savings formula',
        'Installment formula',
        'Goal formula',
        'How are reports calculated?',
        'How is my wallet balance computed?',
        'Can I buy AirPods?',
        'Can I buy a laptop?',
        'Can I buy a laptop for 50000?',
        'Can I buy a bag for 500 this month?',
        'Can I buy a phone for 5000 this week?',
        'How should I save 40000 in 3 months?',
        'If I save 100 per day, can I have 5000 in 2 months?',
        'How much should I save daily to have 3000 per month?',
        'I want to buy a house worth 5000000 in the next 2 years, how '
            'should I save?',
        'Can you make me a savings plan?',
        'Compare my spending this week',
        '150 on lunch, 50 on jeep',
      ]) {
        final english = answerChat(question, records: records());
        final filipino = tagalog(question);
        expect(english.filipino, isFalse, reason: question);
        expect(filipino.filipino, isTrue, reason: question);
        expect(filipino.text, isNot(english.text), reason: question);
        expect(
          keepsFigures(english.text, filipino.text),
          isTrue,
          reason: '$question | ${english.text} | ${filipino.text}',
        );
      }
    });

    test('Taglish gets the same Filipino', () {
      final reply = answerChat(
        'May bills ba ako this week?',
        records: records(),
        language: ChatLanguage.taglish,
      );
      expect(reply.filipino, isTrue);
      expect(reply.text, contains('Lampas na sa due'));
    });

    test('the quick replies in Filipino are understood', () {
      for (final question in [
        ...suggestedQuestionsFilipino,
        ...tagalog('hmm ano').choices,
        ...tagalog('Paano mag-budget?').choices,
        ...tagalog('Ano ang 50/30/20 rule?').choices,
        ...tagalog('Paano ko ibubudget ang 15000?').choices,
      ]) {
        final reply = tagalog(question);
        expect(
          reply.text,
          isNot(contains('Hindi ko pa sigurado')),
          reason: question,
        );
        expect(reply.text, isNot(contains('Pasensya na')), reason: question);
      }
    });

    test('a purchase can be talked through in Tagalog', () {
      var reply = tagalog('Kaya ko bang bumili ng AirPods?');
      expect(reply.text, startsWith('Aling AirPods'));
      expect(reply.choices, contains(anyBrandFilipino));

      reply = answerChat(
        anyBrandFilipino,
        records: records(),
        pending: reply.pending,
        language: ChatLanguage.tagalog,
      );
      expect(reply.filipino, isTrue);
      // No price yet: the most that could go to it, by month end.
      expect(reply.text, contains('Wala pang presyo'));
      expect(reply.text, contains('Bago matapos ang buwan (Sep 30)'));

      reply = answerChat(
        '₱8,990',
        records: records(),
        pending: reply.pending,
        language: ChatLanguage.tagalog,
      );
      expect(reply.filipino, isTrue);
      expect(reply.text, contains('₱8,990'));
    });

    test('a translation must keep every figure', () {
      expect(
        keepsFigures(
          'You can spend ₱1,250 today, with 12 days left.',
          'Pwede kang gumastos ng ₱1,250 ngayon, may 12 araw pa.',
        ),
        isTrue,
      );
      expect(keepsFigures('₱1,250 today', '₱1,520 ngayon'), isFalse);
      expect(keepsFigures('12 days left', 'labindalawang araw pa'), isFalse);
    });
  });
}
