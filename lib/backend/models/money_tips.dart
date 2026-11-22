import 'dart:math' as math;

import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'app_transaction.dart';
import 'debt.dart';
import 'finance_snapshot.dart';
import 'goal.dart';
import 'report.dart';
import 'savings_suggestion.dart';
import 'transaction_filter.dart';
import 'wallet.dart';

/// Short money-habit tips worked out from the user's own records: at most
/// [limit], the most urgent first, and never none.
///
/// Each tip says what to do with the user's own figures: bills against the
/// money held, how long the money lasts, what installments take from income,
/// what to save, and where spending can come down. Reports' Insights already
/// give the shares and the month's totals, so tips don't repeat them. This is
/// the one place tips come from: tips gathered from trusted sources, or from
/// a trained model, can take over here later without Reports changing.
///
/// [filipino] is for Fin, answering a question asked in Tagalog or Taglish.
/// Without [saveFirst], the tips to save before spending are left out, for
/// a reply that already says so; then there can be none.
List<String> moneyTipsFor(
  FinanceSnapshot records, {
  int limit = 2,
  bool filipino = false,
  bool saveFirst = true,
}) {
  final tips = <String>[
    ?_billsShort(records, filipino),
    ?_runsOut(records, filipino),
    ?_paymentsLoad(records, filipino),
    if (saveFirst) ?_saveFromIncome(records, filipino),
    ?_smallBuys(records, filipino),
    ?_biggestSpend(records, filipino),
    ?_safetyFund(records, filipino),
  ];
  if (tips.isEmpty && records.transactions.isEmpty) {
    tips.add(
      filipino
          ? 'Itala ang bawat gastos sa loob ng isang linggo, kahit maliliit. '
                'Sila ang pinakamadaling makalimutan.'
          : 'Track every expense for one week, even the small ones. They are '
                'the easiest to forget.',
    );
  } else if (tips.isEmpty && saveFirst) {
    tips.add(
      filipino
          ? 'Magtabi ng ipon pagdating ng kita, bago gumastos. Mas madaling '
                'sundin kapag inuna ang ipon.'
          : 'Set aside savings when income arrives, before you spend. Saving first '
                'makes it much easier to stick to.',
    );
  }
  return tips.take(limit).toList();
}

/// Day-to-day spending: expenses that aren't bill payments or money lent.
bool _chosen(AppTransaction t) =>
    t.type == TransactionType.expense && !t.isBillPayment && !t.isDebtMovement;

/// Bills still to pay this month that the wallets can't cover.
String? _billsShort(FinanceSnapshot records, bool filipino) {
  if (records.wallets.isEmpty) return null;
  final due = records.safeToSpend.billsDue;
  final held = records.walletBalance;
  if (due <= 0.005 || held + 0.005 >= due) return null;

  final owed = formatPeso(due);
  final has = formatPeso(math.max(0.0, held));
  final short = formatPeso(due - math.max(0.0, held));
  if (filipino) {
    return '$owed pa ang babayarang bills ngayong buwan pero $has lang ang '
        'nasa wallets mo, kulang ng $short. Unahin ang bills at ipagpaliban '
        'muna ang hindi kailangan.';
  }
  return 'Unpaid bills this month come to $owed, but your wallets have $has, '
      '$short short. Pay bills first and put off extras until then.';
}

/// At the usual pace, the money left after bills won't reach month end.
String? _runsOut(FinanceSnapshot records, bool filipino) {
  final usual = records.usualDailySpending;
  if (usual <= 0 || !_enoughHistory(records)) return null;
  final safe = records.safeToSpend;
  final free = safe.moneyLeftNow;
  if (free <= 0.005) return null;

  // Whole days after today the money covers, against the days left after
  // today. A day or so either way is noise, not a warning.
  final lasts = (free / usual).floor();
  if (lasts >= safe.daysLeft - 2) return null;

  final pace = formatPeso(usual.roundToDouble());
  final until = formatMonthDay(records.today.add(Duration(days: lasts)));
  final limit = formatPeso(safe.dailyLimit.floorToDouble());
  if (filipino) {
    return 'Sa karaniwang $pace kada araw, aabot lang ang pera mo (bukod sa '
        'bills) hanggang mga $until. Manatili sa Safe to Spend mo na $limit '
        'kada araw para umabot ng katapusan.';
  }
  return 'At your usual $pace a day, your money after bills lasts until about '
      '$until. Keep to your Safe to Spend of $limit a day to reach month end.';
}

/// Installment and loan payments taking a large part of income. A common
/// guide keeps them under about a third of what comes in.
String? _paymentsLoad(FinanceSnapshot records, bool filipino) {
  var monthly = 0.0;
  for (final debt in records.debts) {
    if (debt.direction != DebtDirection.iOwe ||
        debt.status != DebtStatus.active ||
        debt.paidOffEarly) {
      continue;
    }
    monthly += debt.perPayment * debt.frequency.perYear / 12;
  }
  if (monthly <= 0) return null;

  final since = records.today.subtract(const Duration(days: 29));
  final earned = inAndOut(
    records.transactions.where(
      (t) => !t.date.isBefore(since) && !t.date.isAfter(records.now),
    ),
  ).moneyIn;
  if (earned <= 0 || monthly / earned < 0.3) return null;

  final pays = formatPeso(monthly.roundToDouble());
  final percent = (monthly / earned * 100).round();
  if (filipino) {
    return 'Mga $pays kada buwan ang napupunta sa installments at utang, '
        '$percent% ng kita mo sa nakaraang 30 araw. Iwasan muna ang bago '
        'hangga\'t hindi natatapos ang isa.';
  }
  return 'Installments and debts take about $pays a month, $percent% of your '
      'income in the last 30 days. Avoid new ones until one is paid off.';
}

/// What saving a tenth of this month's income still takes, when the money
/// left after bills can spare it and still last the month.
String? _saveFromIncome(FinanceSnapshot records, bool filipino) {
  final month = transactionsIn(
    records.transactions,
    ReportPeriod.monthOf(records.now),
  ).where((t) => !t.date.isAfter(records.now)).toList();
  final came = inAndOut(month).moneyIn;
  if (came <= 0) return null;

  final saved = _savedIn(month, records.wallets);
  final more = (came * 0.10 - saved).floorToDouble();
  if (more < 1) return null;
  final safe = records.safeToSpend;
  final needed = records.usualDailySpending * (safe.daysLeft - 1);
  if (safe.moneyLeftNow - more < needed) return null;

  final yesterday = records.today.subtract(const Duration(days: 1));
  final fresh = inAndOut(
    month.where((t) => !t.date.isBefore(yesterday)),
  ).moneyIn;
  final move = formatPeso(more);
  if (fresh > 0) {
    final got = formatPeso(fresh);
    return filipino
        ? 'Kapapasok lang ng $got. Ilipat na ang $move sa ipon bago '
              'gumastos, para maitabi ang 10% ng kita ngayong buwan.'
        : '$got just came in. Move $move to savings now, before you start '
              'spending, to keep 10% of this month\'s income.';
  }

  final got = formatPeso(came);
  if (saved <= 0.005) {
    return filipino
        ? '$got ang pumasok ngayong buwan pero wala pang napupunta sa ipon. '
              'Ilipat na ang $move (10%) para hindi magastos.'
        : '$got came in this month and none of it is in savings yet. Moving '
              '$move (10%) now keeps it from being spent.';
  }
  final kept = formatPeso(saved);
  return filipino
      ? '$got ang pumasok ngayong buwan at $kept ang naipon. Kulang pa ng '
            '$move para umabot sa 10%.'
      : '$got came in this month and $kept went to savings or goals. $move '
            'more makes it 10%.';
}

/// Money put into savings wallets or goals, less what came back out. Goal
/// money already in a savings wallet was counted when it moved there.
double _savedIn(Iterable<AppTransaction> transactions, List<Wallet> wallets) {
  final savings = {
    for (final wallet in wallets)
      if (wallet.isSetAside) wallet.id,
  };
  var saved = 0.0;
  for (final t in transactions) {
    if (t.type == TransactionType.transfer) {
      final into = savings.contains(t.toWalletId);
      final outOf = savings.contains(t.walletId);
      if (into && !outOf) saved += t.amount;
      if (outOf && !into) saved -= t.amount;
    } else if (t.isGoalMovement && !savings.contains(t.walletId)) {
      saved += t.isGoalWithdrawal ? -t.amount : t.amount;
    }
  }
  return saved;
}

/// Many small buys this week, which are easy to miss.
String? _smallBuys(FinanceSnapshot records, bool filipino) {
  final week = ReportPeriod.weekOf(records.now);
  final small = records.transactions
      .where((t) => _chosen(t) && t.amount < 100 && week.contains(t.date))
      .toList();
  final total = small.fold<double>(0, (sum, t) => sum + t.amount);
  if (small.length < 8 || total < 300) return null;

  if (filipino) {
    return 'Lumalaki ang maliliit na gastos: ${small.length} na binili na '
        'mas mababa sa ₱100 ngayong linggo ay umabot ng ${formatPeso(total)}. '
        'Makakatulong ang lingguhang limit sa maliliit na gastos.';
  }
  return 'Small buys add up: ${small.length} purchases under ₱100 this week '
      'came to ${formatPeso(total)}. A weekly limit for small spends helps.';
}

/// What to do about a category that grew against the same days last month,
/// or else the one taking most of this month's day-to-day spending. Nothing
/// is said about health, school or pets: those aren't for cutting back on.
String? _biggestSpend(FinanceSnapshot records, bool filipino) {
  final now = records.today;
  final month = ReportPeriod.monthOf(now);
  final spending = spendingByCategory(
    records.transactions.where(
      (t) =>
          _chosen(t) && month.contains(t.date) && !t.date.isAfter(records.now),
    ),
  );
  if (spending.isEmpty) return null;

  // The same days of last month, so a month half gone is compared fairly.
  final lastMonthDays = DateTime(now.year, now.month, 0).day;
  final before = {
    for (final entry in spendingByCategory(
      records.transactions.where(
        (t) =>
            _chosen(t) &&
            ReportPeriod(
              DateTime(now.year, now.month - 1),
              DateTime(
                now.year,
                now.month - 1,
                math.min(now.day, lastMonthDays),
              ),
            ).contains(t.date),
      ),
    ))
      entry.key: entry.value,
  };

  for (final entry in spending) {
    final advice = _adviceFor(entry.key, filipino);
    final earlier = before[entry.key] ?? 0;
    if (advice == null || earlier <= 0) continue;
    final rise = entry.value - earlier;
    if (rise < 500 || rise / earlier < 0.25) continue;

    final so = formatPeso(entry.value);
    final up = formatPeso(rise);
    return filipino
        ? '$so na ang ${entry.key} ngayong buwan, $up na mas mataas kaysa sa '
              'ganitong araw noong nakaraang buwan. $advice'
        : '${entry.key} is $so so far this month, $up more than by this day '
              'last month. $advice';
  }

  final total = spending.fold<double>(0, (sum, e) => sum + e.value);
  final top = spending.first;
  final advice = _adviceFor(top.key, filipino);
  if (advice == null || total < 1000 || top.value / total < 0.4) return null;

  final spent = formatPeso(top.value);
  final tenth = formatPeso((top.value * 0.10).floorToDouble());
  return filipino
      ? '${top.key} ang pinakamalaki mong gastos ngayong buwan: $spent. '
            '$advice Kahit 10% lang na bawas ay $tenth na tipid.'
      : '${top.key} is your biggest spend this month: $spent. $advice Even '
            '10% less saves $tenth.';
}

String? _adviceFor(String category, bool filipino) => filipino
    ? switch (category) {
        'Food' =>
          'Makakatulong ang pagplano ng pagkain at pagbabaon nang ilang araw '
              'kada linggo.',
        'Transportation' =>
          'Makakatulong ang pagsabay-sabayin ang mga lakad sa isang biyahe, '
              'o pagsakay ng jeep o tren kung kaya.',
        'Shopping' =>
          'Maghintay muna ng isang araw bago bumili ng hindi agad kailangan.',
        'Entertainment' =>
          'Isa o dalawang subscription o lakad lang kada buwan para bumaba '
              'ito.',
        'Bills' =>
          'Tanggalin ang plan o subscription na hindi mo na ginagamit para '
              'bumaba ito.',
        _ => null,
      }
    : switch (category) {
        'Food' =>
          'Planning meals and bringing baon a few days a week can bring it '
              'down.',
        'Transportation' =>
          'Grouping errands into one trip, or taking the jeep or train when '
              'you can, can bring it down.',
        'Shopping' =>
          "Waiting a day before buying what you don't need right away helps "
              'avoid impulse buys.',
        'Entertainment' =>
          'Keeping one or two subscriptions or outings a month can bring it '
              'down.',
        'Bills' =>
          'Dropping plans or subscriptions you no longer use can bring it '
              'down.',
        _ => null,
      };

/// Savings for emergencies against the user's own spending, until an
/// emergency fund goal is started. A common guide is 3 to 6 months.
String? _safetyFund(FinanceSnapshot records, bool filipino) {
  if (records.transactions.isEmpty) return null;
  final hasOne = records.goals.any(
    (g) => g.kind == GoalKind.emergencyFund && g.status == GoalStatus.active,
  );
  if (hasOne) return null;

  final perDay = _dailySpending(records);
  final saved = setAsideWalletBalance(records.wallets);
  if (perDay <= 0) {
    // Too new to measure: the general guide, while nothing is saved.
    if (saved > 0.005) return null;
    if (filipino) {
      return 'Wala ka pang emergency fund. Karaniwang gabay ang 3 hanggang 6 '
          'na buwan ng pangunahing gastos. Kahit ₱50 kada araw ay aabot ng '
          'mga ₱1,500 kada buwan.';
    }
    return 'No emergency fund yet. A common guide is 3 to 6 months of basic '
        'expenses. Even ₱50 a day adds up to about ₱1,500 a month.';
  }

  final days = (saved / perDay).floor();
  if (days >= 90) return null;
  final target = formatPeso(((perDay * 90) / 100).ceil() * 100.0);
  if (saved <= 0.005) {
    return filipino
        ? 'Wala ka pang ipon para sa emergency. Sikaping umabot ng 3 buwan ng '
              'karaniwang gastos mo, mga $target. Kahit ₱50 kada araw ay '
              'aabot ng ₱1,500 kada buwan.'
        : 'You have no savings for emergencies yet. Aim for 3 months of your '
              'usual spending, about $target. Even ₱50 a day adds up to '
              '₱1,500 a month.';
  }

  final has = formatPeso(saved);
  if (filipino) {
    final lasts = days < 1 ? 'kulang pa sa isang araw' : 'pang-$days araw';
    return 'Ang ipon mong $has ay $lasts lang ng karaniwang gastos mo. Para '
        'sa emergency, sikaping umabot ng 3 buwan, mga $target. Makakatulong '
        'ang Emergency fund goal.';
  }
  final lasts = days < 1
      ? 'less than a day'
      : 'about $days ${days == 1 ? 'day' : 'days'}';
  return 'Your savings of $has cover $lasts of your usual spending. For '
      'emergencies, aim for 3 months, about $target. An Emergency fund goal '
      'helps you build it.';
}

/// Everything spent in a day on average, bills included, over the last 30
/// days. Zero until spending is recorded on 7 different days, too little to
/// plan 3 months on.
double _dailySpending(FinanceSnapshot records) {
  DateTime? first;
  for (final t in records.transactions) {
    if (t.type != TransactionType.expense || t.isDebtMovement) continue;
    if (first == null || t.date.isBefore(first)) first = t.date;
  }
  if (first == null || !_enoughHistory(records)) return 0;

  final today = records.today;
  final monthAgo = today.subtract(const Duration(days: 29));
  final firstDay = DateTime(first.year, first.month, first.day);
  final from = firstDay.isAfter(monthAgo) ? firstDay : monthAgo;
  final days = today.difference(from).inDays + 1;
  final spent = inAndOut(
    records.transactions.where(
      (t) => !t.date.isBefore(from) && !t.date.isAfter(records.now),
    ),
  ).moneyOut;
  return spent / days;
}

/// Spending recorded on 7 different days in the last 30, the same rule Fin
/// uses before suggesting a savings plan.
bool _enoughHistory(FinanceSnapshot records) =>
    SavingsSuggestion.from(records).hasHistory;
