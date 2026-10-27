import '../utils/money_format.dart';
import 'app_transaction.dart';
import 'finance_snapshot.dart';
import 'goal.dart';
import 'report.dart';
import 'transaction_filter.dart';

/// Short money-habit tips worked out from the user's own records: at most
/// [limit], the most useful first, and never none.
///
/// Reports' Insights already give the figures (shares, changes against past
/// months), so tips say what to do rather than repeat them. This is the one
/// place tips come from: tips gathered from trusted sources, or from a
/// trained model, can take over here later without Reports changing.
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
    ?_smallBuys(records, filipino),
    if (saveFirst) ?_payday(records, filipino),
    ?_biggestShare(records, filipino),
    ?_emergencyFund(records, filipino),
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

/// Income came in today or yesterday.
String? _payday(FinanceSnapshot records, bool filipino) {
  final yesterday = records.today.subtract(const Duration(days: 1));
  final paid = records.transactions.any(
    (t) =>
        t.type == TransactionType.income &&
        !t.isDebtMovement &&
        !t.date.isBefore(yesterday) &&
        !t.date.isAfter(records.now),
  );
  if (!paid) return null;

  if (filipino) {
    return 'Tip ngayong may kita ka: itabi na ang ipon ngayong araw, bago '
        'magsimula ang gastos. Kapag inuna ang ipon, nagiging awtomatiko ito.';
  }
  return 'Income tip: set aside your savings today, before spending starts. '
      'Saving first makes it automatic.';
}

/// What to do about the category taking most of this month's day-to-day
/// spending. Nothing is said about health, school or pets: those aren't for
/// cutting back on.
String? _biggestShare(FinanceSnapshot records, bool filipino) {
  final month = ReportPeriod.monthOf(records.now);
  final spending = spendingByCategory(
    records.transactions.where((t) => _chosen(t) && month.contains(t.date)),
  );
  if (spending.isEmpty) return null;

  final total = spending.fold<double>(0, (sum, e) => sum + e.value);
  final top = spending.first;
  if (total < 1000 || top.value / total < 0.4) return null;

  if (filipino) {
    final payo = switch (top.key) {
      'Food' =>
        'Makakatulong ang pagplano ng pagkain para sa isang linggo at '
            'pagbabaon nang ilang araw para bumaba ito.',
      'Transportation' =>
        'Makakatulong ang pagsabay-sabayin ang mga lakad sa isang biyahe, o '
            'pagsakay ng jeep o tren kung kaya, para bumaba ito.',
      'Shopping' =>
        'Maghintay muna ng isang araw bago bumili ng hindi agad kailangan '
            'para maiwasan ang biglaang pagbili.',
      'Entertainment' =>
        'Isa o dalawang subscription o lakad lang kada buwan, at laktawan '
            'ang iba, para bumaba ito.',
      'Bills' =>
        'Tingnan kung may plan o subscription na hindi mo na ginagamit para '
            'bumaba ito.',
      _ => null,
    };
    if (payo == null) return null;
    return '${top.key} ang pinakamalaking bahagi ng gastos mo ngayong buwan. '
        '$payo';
  }

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
String? _emergencyFund(FinanceSnapshot records, bool filipino) {
  if (records.transactions.isEmpty) return null;
  final hasOne = records.goals.any(
    (g) => g.kind == GoalKind.emergencyFund && g.status == GoalStatus.active,
  );
  if (hasOne) return null;

  if (filipino) {
    return 'Wala ka pang emergency fund. Karaniwang gabay ang 3 hanggang 6 na '
        'buwan ng pangunahing gastos. Kahit ₱50 kada araw ay aabot ng mga '
        '₱1,500 kada buwan.';
  }
  return 'No emergency fund yet. A common guide is 3 to 6 months of basic '
      'expenses. Even ₱50 a day adds up to about ₱1,500 a month.';
}
