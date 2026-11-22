import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/finance_snapshot.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/models/money_tips.dart';
import 'package:testapp/backend/models/wallet.dart';

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

Wallet wallet(double balance, {bool savings = false}) => Wallet(
  id: savings ? 'savings' : 'cash',
  name: savings ? 'Savings' : 'Cash on Hand',
  type: WalletType.cash,
  balance: balance,
  startingBalance: balance,
  receivesIncome: !savings,
  archived: false,
  sortOrder: 0,
  purpose: savings ? WalletPurpose.savings : WalletPurpose.spending,
);

AppTransaction earn(double amount, DateTime date) => AppTransaction(
  id: 'pay-$amount-${date.toIso8601String()}',
  type: TransactionType.income,
  amount: amount,
  label: 'Salary',
  date: date,
);

List<String> tipsFor({
  List<AppTransaction> transactions = const [],
  List<Goal> goals = const [emergencyFund],
  List<Debt> debts = const [],
  List<Wallet> wallets = const [],
  List<BillInstance> bills = const [],
  bool filipino = false,
  int limit = 2,
}) => moneyTipsFor(
  FinanceSnapshot(
    now: now,
    transactions: transactions,
    goals: goals,
    debts: debts,
    wallets: wallets,
    bills: bills,
  ),
  filipino: filipino,
  limit: limit,
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

  test('payday: how much to move to savings, from what came in', () {
    final tips = tipsFor(
      transactions: [earn(8000, DateTime(2026, 9, 16))],
      wallets: [wallet(20000)],
    );
    expect(
      tips.first,
      "₱8,000 just came in. Move ₱800 to savings now, before you start "
      "spending, to keep 10% of this month's income.",
    );
  });

  test('later in the month: what is still to save to reach 10%', () {
    final records = [
      earn(20000, DateTime(2026, 9, 5)),
      AppTransaction(
        id: 'to-savings',
        type: TransactionType.transfer,
        amount: 500,
        label: 'Transfer',
        date: DateTime(2026, 9, 6),
        walletId: 'cash',
        toWalletId: 'savings',
      ),
    ];
    expect(
      tipsFor(
        transactions: records,
        wallets: [wallet(15000), wallet(500, savings: true)],
      ).first,
      '₱20,000 came in this month and ₱500 went to savings or goals. ₱1,500 '
      'more makes it 10%.',
    );
    // Saving it would leave too little for the month: not suggested.
    expect(
      tipsFor(
        transactions: [
          ...records,
          for (var day = 1; day <= 16; day++)
            spend('Food', 500, DateTime(2026, 9, day)),
        ],
        wallets: [wallet(3000), wallet(500, savings: true)],
        limit: 9,
      ).join(' '),
      isNot(contains('makes it 10%')),
    );
  });

  test('bills the wallets cannot cover come first', () {
    final tips = tipsFor(
      wallets: [wallet(5000)],
      bills: [
        BillInstance(
          id: 'rent-sep',
          billId: 'rent',
          name: 'Rent',
          amount: 8000,
          category: 'Bills',
          dueDate: DateTime(2026, 9, 25),
          status: BillStatus.unpaid,
        ),
      ],
      transactions: [spend('Food', 120, DateTime(2026, 9, 3))],
    );
    expect(
      tips.first,
      'Unpaid bills this month come to ₱8,000, but your wallets have ₱5,000, '
      '₱3,000 short. Pay bills first and put off extras until then.',
    );
  });

  test('says when the money runs out at the usual pace', () {
    final tips = tipsFor(
      goals: const [],
      wallets: [wallet(1000)],
      transactions: [
        for (final day in [3, 5, 7, 9, 11, 13, 15, 16])
          spend('Food', 300, DateTime(2026, 9, day)),
      ],
    );
    expect(
      tips.first,
      'At your usual ₱160 a day, your money after bills lasts until about '
      'Sep 23. Keep to your Safe to Spend of ₱71 a day to reach month end.',
    );
  });

  test('installments and debts taking a large part of income', () {
    final tips = tipsFor(
      transactions: [earn(10000, DateTime(2026, 9, 10))],
      debts: const [
        Debt(
          id: 'phone',
          direction: DebtDirection.iOwe,
          name: 'Phone',
          category: DebtCategory.gadget,
          principal: 24000,
          status: DebtStatus.active,
          perPayment: 4000,
          paymentCount: 6,
        ),
      ],
    );
    expect(
      tips.first,
      'Installments and debts take about ₱4,000 a month, 40% of your income '
      'in the last 30 days. Avoid new ones until one is paid off.',
    );
  });

  test('a category that grew against the same days last month', () {
    final tips = tipsFor(
      transactions: [
        spend('Food', 1000, DateTime(2026, 9, 5)),
        spend('Food', 1000, DateTime(2026, 9, 10)),
        spend('Food', 1000, DateTime(2026, 8, 5)),
        // After this day last month: not part of the comparison.
        spend('Food', 5000, DateTime(2026, 8, 25)),
      ],
    );
    expect(
      tips.first,
      'Food is ₱2,000 so far this month, ₱1,000 more than by this day last '
      'month. Planning meals and bringing baon a few days a week can bring it '
      'down.',
    );
  });

  test('savings for emergencies against the usual spending', () {
    final tips = tipsFor(
      goals: const [],
      wallets: [wallet(3000, savings: true)],
      transactions: [
        for (var day = 1; day <= 16; day += 2)
          spend('Shopping', 300, DateTime(2026, 9, day)),
        spend('Healthcare', 600, DateTime(2026, 9, 16)),
      ],
      limit: 9,
    );
    expect(
      tips,
      contains(
        'Your savings of ₱3,000 cover about 17 days of your usual spending. '
        'For emergencies, aim for 3 months, about ₱15,900. An Emergency fund '
        'goal helps you build it.',
      ),
    );
  });

  test('the same tips in Tagalog for Fin', () {
    final tips = tipsFor(
      filipino: true,
      wallets: [wallet(5000)],
      bills: [
        BillInstance(
          id: 'rent-sep',
          billId: 'rent',
          name: 'Rent',
          amount: 8000,
          category: 'Bills',
          dueDate: DateTime(2026, 9, 25),
          status: BillStatus.unpaid,
        ),
      ],
      transactions: [spend('Food', 120, DateTime(2026, 9, 3))],
    );
    expect(tips.first, startsWith('₱8,000 pa ang babayarang bills'));
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
      'Food is your biggest spend this month: ₱1,500. Planning meals and '
      'bringing baon a few days a week can bring it down. Even 10% less saves '
      '₱150.',
    );
    expect(
      tips.first,
      isNot(contains('75%')),
      reason: 'Insights has the share',
    );
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
    );
    expect(tips, hasLength(2));
    expect(tips[0], startsWith('Small buys add up'));
    expect(tips[1], startsWith('No emergency fund yet'));

    // Something recorded, but no rule applies.
    expect(tipsFor(transactions: [spend('Food', 120, DateTime(2026, 9, 3))]), [
      'Set aside savings when income arrives, before you spend. Saving first '
          'makes it much easier to stick to.',
    ]);
  });
}
