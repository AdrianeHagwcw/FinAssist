import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/debt.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/goal.dart';
import 'package:testapp/models/money_tips.dart';

/// Thursday, Sep 17, 2026: this week began Monday the 14th.
final now = DateTime(2026, 9, 17, 18);

AppTransaction spend(
  String label,
  double amount,
  DateTime date, {
  String? bill,
}) => AppTransaction(
  id: '$label-$amount-${date.toIso8601String()}',
  type: TransactionType.expense,
  amount: amount,
  label: label,
  date: date,
  billInstanceId: bill,
);

/// An emergency fund already exists, so only the rule under test speaks.
const emergencyFund = Goal(
  id: 'ef',
  name: 'Emergency fund',
  targetAmount: 30000,
  savedAmount: 2000,
  priority: 0,
  status: GoalStatus.active,
  kind: GoalKind.emergencyFund,
);

Debt owed(String name, double lent, {double back = 0}) => Debt(
  id: name,
  direction: DebtDirection.owedToMe,
  name: name,
  category: DebtCategory.familyFriend,
  principal: lent,
  status: DebtStatus.active,
  received: back,
);

List<String> tipsFor({
  List<AppTransaction> transactions = const [],
  List<Goal> goals = const [emergencyFund],
  List<Debt> debts = const [],
  double? limit,
}) => moneyTipsFor(
  FinanceSnapshot(
    now: now,
    transactions: transactions,
    goals: goals,
    debts: debts,
    customDailyLimit: limit,
  ),
);

void main() {
  test('nothing recorded yet: start by tracking', () {
    expect(tipsFor(), [
      'Track every expense for one week, even the small ones. They are the '
          'easiest to forget.',
    ]);
  });

  test('many small buys this week', () {
    final tips = tipsFor(
      transactions: [
        for (var i = 0; i < 9; i++)
          spend('Food', 50, DateTime(2026, 9, 14 + i % 4, 10 + i)),
        // Last week's and a bill payment don't count.
        spend('Food', 50, DateTime(2026, 9, 10)),
        spend('Bills', 80, DateTime(2026, 9, 15), bill: 'load'),
      ],
    );
    expect(
      tips.first,
      'Small buys add up: 9 purchases under ₱100 this week came to ₱450. A '
      'weekly limit for small spends helps.',
    );
  });

  test('over a daily limit the user set, on several days', () {
    final spending = [
      spend('Food', 400, DateTime(2026, 9, 14, 12)),
      spend('Food', 350, DateTime(2026, 9, 15, 12)),
      spend('Food', 310, DateTime(2026, 9, 16, 12)),
    ];
    expect(
      tipsFor(transactions: spending, limit: 300).first,
      'You went over your ₱300 daily limit on 3 days this week. Spending by '
      'category above shows what pushed it up.',
    );
    // Without a limit of their own, nothing is said about it.
    expect(
      tipsFor(transactions: spending).first,
      isNot(contains('daily limit')),
    );
  });

  test('payday', () {
    final tips = tipsFor(
      transactions: [
        AppTransaction(
          id: 'pay',
          type: TransactionType.income,
          amount: 8000,
          label: 'Allowance',
          date: DateTime(2026, 9, 16),
        ),
      ],
    );
    expect(tips.first, startsWith('Payday tip: set aside your savings today'));
  });

  test('money still owed to the user', () {
    expect(
      tipsFor(debts: [owed('Ana', 500, back: 200)]).first,
      'Ana still owes you ₱300. A friendly reminder now is easier than later.',
    );
    expect(
      tipsFor(debts: [owed('Ana', 500), owed('Ben', 250)]).first,
      startsWith('₱750 is still owed to you.'),
    );
    expect(
      tipsFor(debts: [owed('Ana', 500, back: 500)]),
      isNot(contains(contains('owes you'))),
    );
  });

  test('what to do about the biggest share, without repeating Insights', () {
    final tips = tipsFor(
      transactions: [
        spend('Food', 1500, DateTime(2026, 9, 3)),
        spend('Shopping', 500, DateTime(2026, 9, 5)),
      ],
    );
    expect(
      tips.first,
      'Food takes the biggest share of your spending this month. Planning '
      'meals for the week and bringing baon a few days can bring it down.',
    );
    expect(tips.first, isNot(contains('%')), reason: 'Insights has the share');
  });

  test('never tells the user to cut back on health', () {
    final tips = tipsFor(
      transactions: [
        spend('Healthcare', 1800, DateTime(2026, 9, 3)),
        spend('Food', 200, DateTime(2026, 9, 5)),
      ],
    );
    expect(tips.join(' '), isNot(contains('Healthcare')));
  });

  test('suggests an emergency fund until there is one', () {
    final records = [spend('Food', 120, DateTime(2026, 9, 3))];
    expect(
      tipsFor(transactions: records, goals: const []).first,
      startsWith('No emergency fund yet. A common guide is 3 to 6 months'),
    );
    expect(
      tipsFor(transactions: records).join(' '),
      isNot(contains('emergency')),
    );
  });

  test('at most two, most useful first, and always one', () {
    final tips = tipsFor(
      transactions: [
        for (var i = 0; i < 9; i++)
          spend('Food', 60, DateTime(2026, 9, 14 + i % 4, 8 + i)),
      ],
      goals: const [],
      debts: [owed('Ana', 500)],
    );
    expect(tips, hasLength(2));
    expect(tips[0], startsWith('Small buys add up'));
    expect(tips[1], startsWith('Ana still owes you'));

    // Something recorded, but no rule applies.
    expect(tipsFor(transactions: [spend('Food', 120, DateTime(2026, 9, 3))]), [
      'Set aside savings on payday, before you spend. Saving first makes it '
          'much easier to stick to.',
    ]);
  });
}
