import '../utils/money_format.dart';
import 'app_transaction.dart';
import 'debt.dart';
import 'finance_snapshot.dart';
import 'goal.dart';
import 'report.dart';
import 'safe_to_spend.dart';
import 'transaction_filter.dart';

/// Short money-habit tips worked out from the user's own records: at most
/// [limit], the most useful first, and never none.
///
/// Reports' Insights already give the figures (shares, changes against past
/// months), so tips say what to do rather than repeat them. This is the one
/// place tips come from: tips gathered from trusted sources, or from a
/// trained model, can take over here later without Reports changing.
List<String> moneyTipsFor(FinanceSnapshot records, {int limit = 2}) {
  final tips = <String>[
    ?_smallBuys(records),
    ?_overLimit(records),
    ?_payday(records),
    ?_owedToYou(records),
    ?_biggestShare(records),
    ?_emergencyFund(records),
  ];
  if (tips.isEmpty) {
    tips.add(
      records.transactions.isEmpty
          ? 'Track every expense for one week, even the small ones. They are '
                'the easiest to forget.'
          : 'Set aside savings on payday, before you spend. Saving first '
                'makes it much easier to stick to.',
    );
  }
  return tips.take(limit).toList();
}

/// Day-to-day spending: expenses that aren't bill payments or money lent.
bool _chosen(AppTransaction t) =>
    t.type == TransactionType.expense && !t.isBillPayment && !t.isDebtMovement;

/// Many small buys this week, which are easy to miss.
String? _smallBuys(FinanceSnapshot records) {
  final week = ReportPeriod.weekOf(records.now);
  final small = records.transactions
      .where((t) => _chosen(t) && t.amount < 100 && week.contains(t.date))
      .toList();
  final total = small.fold<double>(0, (sum, t) => sum + t.amount);
  if (small.length < 8 || total < 300) return null;

  return 'Small buys add up: ${small.length} purchases under ₱100 this week '
      'came to ${formatPeso(total)}. A weekly limit for small spends helps.';
}

/// Going over a daily limit the user set, on several days this week.
String? _overLimit(FinanceSnapshot records) {
  final limit = records.customDailyLimit;
  if (limit == null) return null;

  final week = ReportPeriod.weekOf(records.now);
  var days = 0;
  for (
    var day = week.start;
    day.isBefore(records.today);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final spent = discretionarySpending(
      records.transactions,
      from: day,
      until: DateTime(day.year, day.month, day.day + 1),
    );
    if (spent > limit + 0.005) days++;
  }
  if (days < 3) return null;

  return 'You went over your ${formatPeso(limit)} daily limit on $days days '
      'this week. Spending by category above shows what pushed it up.';
}

/// Income came in today or yesterday.
String? _payday(FinanceSnapshot records) {
  final yesterday = records.today.subtract(const Duration(days: 1));
  final paid = records.transactions.any(
    (t) =>
        t.type == TransactionType.income &&
        !t.isDebtMovement &&
        !t.date.isBefore(yesterday) &&
        !t.date.isAfter(records.now),
  );
  if (!paid) return null;

  return 'Payday tip: set aside your savings today, before spending starts. '
      'Saving first makes it automatic.';
}

/// Money lent out and not yet back.
String? _owedToYou(FinanceSnapshot records) {
  final owed = records.debts
      .where(
        (d) =>
            d.status == DebtStatus.active &&
            d.direction == DebtDirection.owedToMe &&
            d.stillOwedToMe > 0,
      )
      .toList();
  if (owed.isEmpty) return null;

  final who = owed.length == 1
      ? '${owed.first.name} still owes you ${formatPeso(owed.first.stillOwedToMe)}'
      : '${formatPeso(owed.fold<double>(0, (sum, d) => sum + d.stillOwedToMe))} '
            'is still owed to you';
  return '$who. A friendly reminder now is easier than later.';
}

/// What to do about the category taking most of this month's day-to-day
/// spending. Nothing is said about health, school or pets: those aren't for
/// cutting back on.
String? _biggestShare(FinanceSnapshot records) {
  final month = ReportPeriod.monthOf(records.now);
  final spending = spendingByCategory(
    records.transactions.where((t) => _chosen(t) && month.contains(t.date)),
  );
  if (spending.isEmpty) return null;

  final total = spending.fold<double>(0, (sum, e) => sum + e.value);
  final top = spending.first;
  if (total < 1000 || top.value / total < 0.4) return null;

  final advice = switch (top.key) {
    'Food' =>
      'Planning meals for the week and bringing baon a few days can bring '
          'it down.',
    'Transportation' =>
      'Grouping errands into one trip, or taking the jeep or train when you '
          'can, can bring it down.',
    'Shopping' =>
      "Waiting a day before buying something you don't need right away "
          'helps avoid impulse buys.',
    'Entertainment' =>
      'Keeping one or two subscriptions or outings a month and skipping the '
          'rest can bring it down.',
    'Bills' =>
      'Checking for plans or subscriptions you no longer use can bring it '
          'down.',
    _ => null,
  };
  if (advice == null) return null;

  return '${top.key} takes the biggest share of your spending this month. '
      '$advice';
}

/// No emergency fund goal yet, once there is something recorded.
String? _emergencyFund(FinanceSnapshot records) {
  if (records.transactions.isEmpty) return null;
  final hasOne = records.goals.any(
    (g) => g.kind == GoalKind.emergencyFund && g.status == GoalStatus.active,
  );
  if (hasOne) return null;

  return 'No emergency fund yet. A common guide is 3 to 6 months of basic '
      'expenses. Even ₱50 a day adds up to about ₱1,500 a month.';
}
