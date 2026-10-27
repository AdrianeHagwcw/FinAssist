import 'dart:math' as math;

import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'app_transaction.dart';
import 'big_purchase.dart';
import 'bill.dart';
import 'debt.dart';
import 'expense_guess.dart';
import 'finance_snapshot.dart';
import 'goal.dart';
import 'financial_insights.dart';
import 'money_tips.dart';
import 'price_references.dart';
import 'report.dart';
import 'safe_to_spend.dart';
import 'savings_suggestion.dart';
import 'transaction_filter.dart';
import 'wallet.dart';
import 'chat_language.dart';
import '../utils/categories.dart';

part 'big_purchase_answers.dart';

/// The assistant's answers, worked out by rules from the user's own records.
///
/// [answerChat] is the one place replies come from, so a smarter assistant
/// can take over here later without the chat screen changing. Every number
/// comes from the same calculations as Home, Reports and Bills.

/// A savings goal the assistant suggests, filled in for the goal form.
class GoalOffer {
  const GoalOffer({
    required this.name,
    required this.target,
    required this.date,
  });

  final String name;
  final double target;
  final DateTime date;
}

ChatReply _insightsResponse(bool fil) => ChatReply(
  fil
      ? 'Oo. Matutulungan kitang unawain ang mga naitala mong gastos, '
            'ikumpara ang mga nakaraang panahon, makita kung saan napupunta '
            'ang pera, at magbigay ng praktikal na paraan para makatipid. '
            'Gagamitin ko lang ang mga rekord na nasa FinAssist, kaya mas '
            'makakatulong kung regular mong itatala ang kita at gastos.'
      : 'Yes. I can help explain your recorded spending, compare recent '
            'periods, point out your main expense categories, and suggest '
            'practical ways to save. I will use the records available in '
            'FinAssist, so keeping them up to date helps make the insights '
            'more useful.',
  filipino: fil,
);

class CategorizedChatExpense {
  const CategorizedChatExpense({
    required this.amount,
    required this.description,
    required this.category,
  });

  final double amount;
  final String description;
  final String? category;
}

List<CategorizedChatExpense>? categorizeChatExpenses(String message) {
  final matches = RegExp(
    r'(?:₱|php\s*)?(\d[\d,]*(?:\.\d{1,2})?)\s*'
    r'(?:on|for)\s+(.+?)(?=\s*,\s*(?:and\s+)?(?:₱|php\s*)?\d|'
    r'\s+and\s+(?:₱|php\s*)?\d|$)',
    caseSensitive: false,
  ).allMatches(message).toList();
  if (matches.length < 2) return null;

  final expenses = <CategorizedChatExpense>[];
  for (final match in matches) {
    final amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    final description = match
        .group(2)!
        .trim()
        .replaceFirst(RegExp(r'[,.!?]+$'), '');
    final cleanedDescription = description
        .replaceFirst(
          RegExp(
            r'[\s,.!?]+(?:categorize|classify|group)\s+(?:these|the)\s+'
            r'expenses?\.?$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (amount == null || amount <= 0 || cleanedDescription.isEmpty) {
      return null;
    }
    expenses.add(
      CategorizedChatExpense(
        amount: amount,
        description: cleanedDescription,
        category: suggestCategory(cleanedDescription, from: expenseCategories),
      ),
    );
  }
  return expenses;
}

bool isSavingsSuggestionsQuestion(String question) {
  final text = ' ${_plain(question)} ';
  return _has(text, [
    'savings suggestions',
    'saving suggestions',
    'suggestions to save',
    'ways to save',
    'saving tips',
    'savings tips',
    'tips to save',
    'suggest ways to save',
    'suggest how to save',
  ]);
}

/// What the assistant is waiting to hear in a "Can I buy it?" conversation.
enum PurchaseStep { item, brand, price }

/// Tapped when the user has no brand in mind.
const anyBrand = 'Any brand';

/// [anyBrand] in a conversation in Tagalog or Taglish.
const anyBrandFilipino = 'Kahit anong brand';

/// Tapped when the user doesn't know the price.
const notSure = "I'm not sure";

/// [notSure] in a conversation in Tagalog or Taglish.
const notSureFilipino = 'Hindi ko alam';

/// A "Can I buy it?" question, worked out over a few messages.
class PurchaseQuestion {
  const PurchaseQuestion({
    required this.deadline,
    required this.deadlineLabel,
    this.deadlineLabelFilipino = '',
    this.item = '',
    this.brand,
    this.price,
    this.waitingFor,
    this.asked = 0,
    this.details = '',
  });

  /// The day it has to be bought before.
  final DateTime deadline;

  /// How the deadline reads in an answer, such as "before payday (Oct 1)".
  final String deadlineLabel;

  /// [deadlineLabel] in Filipino, for an answer in Tagalog or Taglish. The
  /// question can carry on in either language.
  final String deadlineLabelFilipino;

  final String item;

  /// The brand or model chosen, or [anyBrand]. Null when not asked.
  final String? brand;
  final double? price;
  final PurchaseStep? waitingFor;

  /// Follow-up questions asked so far, so the assistant never keeps asking.
  final int asked;

  /// Everything the user has said about it so far, for details such as a
  /// house's size or place, or gold's weight, that aren't the item's name.
  final String details;

  /// What is being bought, as it reads in a sentence.
  String get thing {
    if (brand == null || brand == anyBrand) return item;
    if (brand!.toLowerCase().contains(item.toLowerCase())) return brand!;
    return '$brand $item';
  }

  PurchaseQuestion copyWith({
    String? item,
    String? brand,
    double? price,
    PurchaseStep? waitingFor,
    bool clearWaiting = false,
    int? asked,
    String? details,
  }) {
    return PurchaseQuestion(
      deadline: deadline,
      deadlineLabel: deadlineLabel,
      deadlineLabelFilipino: deadlineLabelFilipino,
      item: item ?? this.item,
      brand: brand ?? this.brand,
      price: price ?? this.price,
      waitingFor: clearWaiting ? null : waitingFor ?? this.waitingFor,
      asked: asked ?? this.asked,
      details: details ?? this.details,
    );
  }
}

/// One reply from the assistant.
class ChatReply {
  const ChatReply(
    this.text, {
    this.choices = const [],
    this.goal,
    this.pending,
    this.isVerifiedGoalPlan = false,
    this.useLocalAnswer = false,
    this.keepUnderAi = false,
    this.filipino = false,
    this.sources = const [],
  });

  final String text;

  /// Quick replies the user can tap instead of typing.
  final List<String> choices;

  /// A savings goal worth making, offered with a button.
  final GoalOffer? goal;

  /// A question still being worked out, carried into the next message.
  final PurchaseQuestion? pending;

  /// The numeric target in [text] was calculated locally from explicit goal
  /// details, rather than generated by Gemini.
  final bool isVerifiedGoalPlan;

  /// Exact account answers and formulas must not be replaced by generated text.
  final bool useLocalAnswer;

  /// Tips with figures from the records, shown under a generated answer
  /// rather than replaced by it, since generated text can't carry amounts.
  final bool keepUnderAi;

  /// [text] is already in Filipino, for a question asked in Tagalog or
  /// Taglish. Other replies to such a question are translated when online.
  final bool filipino;

  /// Where the public prices in [text] are from, shown as links under it.
  final List<ReferenceLink> sources;

  ChatReply protected() => ChatReply(
    text,
    choices: choices,
    goal: goal,
    pending: pending,
    isVerifiedGoalPlan: isVerifiedGoalPlan,
    useLocalAnswer: true,
    keepUnderAi: keepUnderAi,
    filipino: filipino,
    sources: sources,
  );
}

/// Questions to try, offered at the start and when a question isn't clear.
const suggestedQuestions = [
  'How much can I spend today?',
  'Where am I spending the most?',
  'May bills ba ako this week?',
  'Can I buy AirPods?',
  'Anong formula ang ginamit?',
];

/// [suggestedQuestions] for a conversation in Tagalog or Taglish.
const suggestedQuestionsFilipino = [
  'Magkano pa ang pwede kong gastusin ngayon?',
  'Saan napupunta ang pera ko?',
  'May babayaran ba ako ngayong linggo?',
  'Kaya ko bang bumili ng AirPods?',
  'Paano kinuwenta ang pwede kong gastusin?',
];

/// Answers [message] from [records], the user's own data, which is null
/// while it is still loading. [pending] is a "Can I buy it?" question still
/// being worked out. [prices] are the public prices the web scraper saved,
/// for houses, lots and gold; null when they couldn't be read.
ChatReply answerChat(
  String message, {
  required FinanceSnapshot? records,
  PurchaseQuestion? pending,
  String? contextMessage,
  ChatLanguage? language,
  PriceReferences? prices,
}) {
  final text = ' ${_plain(message)} ';
  // Tagalog and Taglish get everyday Filipino, with the money words people
  // use anyway, like bills and budget.
  final fil =
      language == ChatLanguage.tagalog || language == ChatLanguage.taglish;

  final categorizedExpenses = categorizeChatExpenses(message);
  if (categorizedExpenses != null) {
    final lines = categorizedExpenses.map((expense) {
      final category = expense.category;
      final head = '${formatPeso(expense.amount)} — ${expense.description}';
      return category != null
          ? '$head: $category'
          : fil
          ? '$head: hindi malinaw ang category; piliin ito sa FinAssist'
          : '$head: category unclear; choose the category in FinAssist';
    });
    return ChatReply(
      fil
          ? 'Ito ang category ng bawat gastos:\n${lines.join('\n')}\n\n'
                'Tama ba ang mga category? Kung oo, pindutin ang “Add all '
                'expenses”.'
          : 'Here is the categorization for each expense:\n'
                '${lines.join('\n')}\n\n'
                'Are these categories correct? If yes, tap “Add all expenses”.',
      filipino: fil,
    ).protected();
  }

  // A calculation question interrupts a purchase follow-up instead of
  // being mistaken for an item name or price.
  if (_asksForFormula(text)) return _formula(text, records, fil).protected();

  if (pending != null) {
    final followUp = _continuePurchase(
      message,
      text,
      pending,
      records,
      prices,
      fil,
    );
    if (followUp != null) return followUp;
  }

  final buy =
      _buyTrigger.firstMatch(message.toLowerCase()) ??
      _otherBuyTrigger.firstMatch(message.toLowerCase());
  if (buy != null) {
    return _startPurchase(message, buy.end, records, prices, fil);
  }

  final projection = _savingsProjection(message, records, fil);
  if (projection != null) return projection;

  final targetAnswer = _savingsTargetAnswer(
    message,
    contextMessage: contextMessage,
    records: records,
    fil: fil,
  );
  if (targetAnswer != null) return targetAnswer;

  final goalPlan = _goalSavingsPlan(message, records, fil);
  if (goalPlan != null) return goalPlan;

  final targetPlan = _targetSavingsPlan(message, records, fil);
  if (targetPlan != null) return targetPlan;

  var intent = _intentOf(text);
  // "Nagbayad na ba si Ana?" names someone the user lent to, with no debt
  // word in it, so the name alone makes it a question about that debt.
  if ((intent == null || intent == _Intent.bills) &&
      records != null &&
      _namedDebts(text, records).isNotEmpty) {
    intent = _Intent.debts;
  }

  final suggested = fil ? suggestedQuestionsFilipino : suggestedQuestions;
  if (intent == _Intent.greeting) {
    return ChatReply(
      fil
          ? 'Hi! Ako si Fin. Sumasagot ako gamit ang sarili mong records: '
                'gastos, bills, ipon, at kung kaya mo ang gusto mong bilhin. '
                'Ano ang gusto mong malaman?'
          : "Hi! I'm Fin. I answer from your own records: spending, bills, "
                'savings, and whether you can afford something. What would you '
                'like to know?',
      choices: suggested,
      filipino: fil,
    );
  }
  if (intent == _Intent.help) {
    return ChatReply(
      fil
          ? 'Masasabi ko kung magkano pa ang pwede mong gastusin ngayon, saan '
                'napunta ang pera mo, anong bills ang paparating, kumusta ang '
                'ipon at utang mo, at kung kasya sa budget mo ang gusto mong '
                'bilhin. Pera lang ang kaya kong sagutin.'
          : 'I can tell you what you can spend today, how much went where, '
                'which bills are coming up, how your savings and debts stand, '
                'and whether something you want fits your budget. '
                "I'm only for money questions.",
      choices: suggested,
      filipino: fil,
    );
  }
  if (intent == null) {
    return _looksFinancial(text)
        ? _clarification(fil)
        : ChatReply(
            fil
                ? 'Pasensya na, mga tanong lang tungkol sa pera ang kaya kong '
                      'sagutin, gaya ng budget, gastos, bills at ipon. Ano ang '
                      'gusto mong malaman tungkol sa pera mo?'
                : 'Sorry, I can only help with money questions, like '
                      'budgeting, expenses, bills and savings. What would you '
                      'like to know about your finances?',
            choices: suggested,
            filipino: fil,
          );
  }

  if (records == null) {
    return ChatReply(
      fil
          ? 'Kinukuha ko pa ang records mo. Magtanong ulit maya-maya.'
          : "I'm still loading your records. Ask me again in a moment.",
      useLocalAnswer: true,
      filipino: fil,
    );
  }

  final reply = switch (intent) {
    _Intent.safeToday => _safeToday(records, fil),
    _Intent.safeTodayComparison => _safeTodayComparison(text, records, fil),
    _Intent.insights => _insightsResponse(fil),
    _Intent.savingsPlan => _savingsPlan(records, text, fil),
    _Intent.spent => _spent(text, records, fil),
    _Intent.savingsCapacity => _savingsCapacity(text, records, fil),
    _Intent.topSpending => _topSpending(text, records, fil),
    _Intent.bills => _bills(text, records, fil),
    _Intent.balance => _balance(records, fil),
    _Intent.savings => _savings(records, fil),
    _Intent.debts => _debts(text, records, fil),
    _Intent.income => _income(text, records, fil),
    _Intent.advice => _advice(records, text, fil),
    _Intent.budgetPlan => _budgetPlan(message, text, records, fil),
    _Intent.budgetRule => _budgetRule(records, fil),
    _Intent.emergencyFund => _emergencyFund(records, fil),
    _Intent.budgetEnough => _budgetEnough(records, fil),
    _Intent.greeting || _Intent.help => throw StateError('answered above'),
  };
  // A budget plan for a given amount protects itself; the steps without one
  // are tips, like advice.
  return intent == _Intent.advice ||
          intent == _Intent.insights ||
          intent == _Intent.budgetPlan
      ? reply
      : reply.protected();
}

ChatReply _clarification(bool fil) => fil
    ? const ChatReply(
        'Hindi ko pa sigurado kung ano ang tanong mo. Gusto kong tama ang '
        'sagot ko, kaya kailangan ko ng kaunting detalye. Tungkol ba ito sa '
        'naitala mong kita, gastos, available na pera, target na ipon, o '
        'bibilhin mo sa susunod? Isama ang halaga at panahon kung gusto mong '
        'kalkulahin ko.',
        choices: [
          'Magkano ang kinita ko ngayong buwan?',
          'Magkano ang nagastos ko ngayong buwan?',
          'Magkano ang kaya kong ipon?',
          'Kaya ko bang bilhin ito?',
        ],
        filipino: true,
      )
    : const ChatReply(
        "I'm not sure what you're asking yet. I want to give you an accurate "
        'answer, but I need a little more detail. '
        'Are you asking about your recorded income, expenses, available '
        'balance, a savings target, or a future purchase? Include the amount '
        'and time period if you want me to calculate it.',
        choices: [
          'How much income did I record this month?',
          'How much did I spend this month?',
          'How much can I save?',
          'Can I afford this purchase?',
        ],
      );

ChatReply? _targetSavingsPlan(
  String message,
  FinanceSnapshot? records,
  bool fil,
) {
  final normalized = message.toLowerCase();
  final asksToSave = RegExp(
    r'\b(save|saving|savings|set aside|put aside|ipon|'
    r'mag.?ipon|makaipon|makapag.?ipon)\b',
  ).hasMatch(normalized);
  if (!asksToSave) return null;

  final duration = RegExp(
    r'(?:in|within|over|for|next|sa loob ng|within)\s*'
    r'(?:the\s+)?(?:(\d+)|a|an|isang)\s*(?:na\s+)?'
    r'(day|days|week|weeks|month|months|year|years|araw|linggo|buwan|taon)\b',
  ).firstMatch(normalized);
  if (duration == null) return null;

  final target = findAmount(message)?.value;
  final count = int.tryParse(duration[1] ?? '1');
  if (target == null || target <= 0 || count == null || count <= 0) {
    return null;
  }

  final days = count * _daysPer(duration[2]!);
  if (days <= 0) return null;

  final daily = (target / days * 100).ceil() / 100;
  final monthly = (target / (days / 30) * 100).ceil() / 100;
  final span = _span(count, duration[2]!, fil);
  final context = records == null
      ? ''
      : fil
      ? ' Ihambing ito sa naitala mong kita, gastos, bills at ipon bago mo '
            'ito simulan.'
      : ' Compare this target with your recorded income, expenses, bills, '
            'and existing savings before committing to it.';

  return ChatReply(
    fil
        ? 'Para makaipon ng ${formatPeso(target)} sa loob ng $span, '
              'magtabi ng humigit-kumulang ${formatPeso(daily)} araw-araw '
              '(${formatPeso(monthly)} kada buwan). Ito ay mathematical target '
              'batay sa halaga at panahon na ibinigay mo; hindi pa nito '
              'pinatutunayang kaya ng kasalukuyan mong budget.$context'
        : 'To save ${formatPeso(target)} in $span, set aside about '
              '${formatPeso(daily)} per day (${formatPeso(monthly)} per month). '
              'This is a mathematical target based on the amount and timeline '
              'you gave; it does not prove that your current budget can afford '
              'it.$context',
    isVerifiedGoalPlan: true,
    filipino: fil,
  ).protected();
}

/// Days in one [unit] of time, as said in English or Filipino.
int _daysPer(String unit) => switch (unit) {
  'day' || 'days' || 'araw' => 1,
  'week' || 'weeks' || 'linggo' => 7,
  'month' || 'months' || 'buwan' => 30,
  'year' || 'years' || 'taon' => 365,
  _ => 0,
};

/// "6 months" or "6 na buwan", however the unit was typed.
String _span(int count, String unit, bool fil) {
  final days = _daysPer(unit);
  if (fil) {
    final word = switch (days) {
      1 => 'araw',
      7 => 'linggo',
      30 => 'buwan',
      _ => 'taon',
    };
    return '$count $word';
  }
  final word = switch (days) {
    1 => 'day',
    7 => 'week',
    30 => 'month',
    _ => 'year',
  };
  return '$count ${count == 1 ? word : '${word}s'}';
}

ChatReply? _savingsProjection(
  String message,
  FinanceSnapshot? records,
  bool fil,
) {
  final normalized = message.toLowerCase();
  final contributionMatch = RegExp(
    r'([\d,]+(?:\.\d+)?)\s*'
    r'(?:per day|each day|a day|daily|araw araw|araw-araw|kada araw)',
  ).firstMatch(normalized);
  if (contributionMatch == null) return null;

  final contribution = double.tryParse(
    contributionMatch.group(1)!.replaceAll(',', ''),
  );
  if (contribution == null || contribution <= 0) return null;

  final targetMatch =
      RegExp(
        r'\b(?:have|save|reach|get|accumulate|makakuha|makaipon)\b'
        r'[^0-9]{0,20}([\d,]+(?:\.\d+)?)',
      ).firstMatch(normalized) ??
      RegExp(
        r'([\d,]+(?:\.\d+)?)\s+'
        r'(?:in|within|after|over|for|sa loob ng|pagkatapos ng)\s+',
      ).firstMatch(normalized);
  final durationMatch = RegExp(
    r'\b(?:in|within|after|over|for|sa loob ng|pagkatapos ng)\s+'
    r'(?:(\d+)|a|an|isang)\s+(?:na\s+)?'
    r'(day|days|week|weeks|month|months|year|years|araw|linggo|buwan|taon)\b',
  ).firstMatch(normalized);
  if (targetMatch == null || durationMatch == null) return null;

  final target = double.tryParse(targetMatch.group(1)!.replaceAll(',', ''));
  final count = int.tryParse(durationMatch.group(1) ?? '1');
  if (target == null || target <= 0 || count == null || count <= 0) {
    return null;
  }

  final days = count * _daysPer(durationMatch.group(2)!);
  if (days <= 0) return null;

  final span = _span(count, durationMatch.group(2)!, fil);
  final projected = contribution * days;
  final difference = projected - target;
  if (fil) {
    final result = difference >= 0
        ? 'oo, sobra pa ng mga ${formatPeso(difference)}'
        : 'hindi, kulang ka ng mga ${formatPeso(-difference)}';
    final recordedNote = records == null
        ? ''
        : ' Hindi pa kasama rito ang naitala mong gastos, bills at iba pang '
              'bayarin, kaya tantiya lang ito at hindi garantiyang kaya mo.';
    return ChatReply(
      'Sa ${formatPeso(contribution)} kada araw sa loob ng $span, makakaipon '
      'ka ng mga ${formatPeso(projected)}. Para sa goal na '
      '${formatPeso(target)}, ang sagot sa kuwenta ay $result.$recordedNote',
      filipino: true,
    ).protected();
  }
  final result = difference >= 0
      ? 'yes, by about ${formatPeso(difference)}'
      : 'no, you would be short by about ${formatPeso(-difference)}';
  final recordedNote = records == null
      ? ''
      : ' This is before your recorded expenses, bills, and other '
            'commitments, so it is a projection rather than an affordability '
            'guarantee.';
  return ChatReply(
    'At ${formatPeso(contribution)} per day for $span, you would '
    'save about ${formatPeso(projected)}. For a ${formatPeso(target)} goal, '
    'the mathematical answer is $result.$recordedNote',
  ).protected();
}

ChatReply? _savingsTargetAnswer(
  String message, {
  required String? contextMessage,
  required FinanceSnapshot? records,
  bool fil = false,
}) {
  final normalized = ' ${_plain(message)} ';
  final asksToSave = _has(normalized, [
    'save',
    'saving',
    'savings',
    'set aside',
    'put aside',
    'ipon',
    'mag ipon',
  ]);
  final asksDaily = _has(normalized, [
    'per day',
    'daily',
    'every day',
    'everyday',
    'a day',
    'araw araw',
    'kada araw',
  ]);
  if (!asksToSave || !asksDaily) return null;

  final context = contextMessage == null ? '' : ' $contextMessage';
  final combined = '$message$context';
  final monthlyMentioned = RegExp(
    r'\b(per month|monthly|a month|each month|kada buwan|bawat buwan)\b',
    caseSensitive: false,
  ).hasMatch(combined);
  if (!monthlyMentioned) return null;

  final amount = findAmount(message)?.value ?? findAmount(context)?.value;
  if (amount == null || amount <= 0) return null;

  final dailyTarget = (amount / 30 * 100).ceil() / 100;
  final affordability = records == null
      ? ''
      : _monthlySavingsContext(records, amount, fil);
  return ChatReply(
    fil
        ? 'Para makaipon ng ${formatPeso(amount)} kada buwan, magtabi ng mga '
              '${formatPeso(dailyTarget)} kada araw, gamit ang 30 araw sa isang '
              'buwan. Ito ang target na hiningi mo, hindi patunay na kaya mo '
              'ito. $affordability'
        : 'To save ${formatPeso(amount)} per month, set aside about '
              '${formatPeso(dailyTarget)} per day, using a 30-day month. '
              'This is the target amount you asked for, not a claim that it '
              'is affordable. $affordability',
    filipino: fil,
  );
}

String _monthlySavingsContext(
  FinanceSnapshot records,
  double target,
  bool fil,
) {
  final month = ReportPeriod.monthOf(records.now);
  final flow = inAndOut(transactionsIn(records.transactions, month));
  final spending = spendingByCategory(
    transactionsIn(records.transactions, month),
  ).fold<double>(0, (sum, entry) => sum + entry.value);
  if (flow.moneyIn <= 0) {
    return fil
        ? 'Wala pa akong naitalang kita ngayong buwan na maihahambing sa '
              'target na ito.'
        : "I don't have recorded income this month to compare with this "
              'target.';
  }
  final remaining = formatPeso(math.max(0, flow.moneyIn - spending));
  return fil
      ? 'Ngayong buwan, may ${formatPeso(flow.moneyIn)} na kita at '
            '${formatPeso(spending)} na gastos sa records, kaya mga $remaining '
            'ang natitira bago ang bills at bayaring hindi naitala. Isipin '
            'muna ang mga iyon at magtira ng reserba bago mo ito itabi.'
      : 'This month, the app records ${formatPeso(flow.moneyIn)} income and '
            '${formatPeso(spending)} in recorded expenses, leaving about '
            '$remaining before unrecorded bills '
            'and other commitments. Keep those commitments and an emergency '
            'buffer in mind before setting this aside.';
}

ChatReply? _goalSavingsPlan(
  String message,
  FinanceSnapshot? records,
  bool fil,
) {
  final normalized = message.toLowerCase();
  final asksToSave = RegExp(
    r'\b(save|saving|savings|set aside|put aside|mag ipon|mag-ipon|'
    r'makaipon|makapag ipon|makapag-ipon)\b',
  ).hasMatch(normalized);
  final mentionsPurchase = RegExp(
    r'\b(buy|purchase|house|home|property|car|vehicle|condo|land|'
    r'bahay|bumili|bibili|bilhin|makabili|get|reach|accumulate|'
    r'goal|target)\b',
  ).hasMatch(normalized);
  if (!asksToSave || !mentionsPurchase) return null;

  final amount = findAmount(message)?.value;
  final duration = RegExp(
    r'\b(?:in|within|over|for|next|sa loob ng|sa susunod na)\s+'
    r'(?:the\s+)?(?:next\s+)?(\d+)\s+(?:na\s+)?(years?|months?|taon|buwan)\b',
  ).firstMatch(normalized);
  if (amount == null || amount < 100 || duration == null) return null;

  final count = int.tryParse(duration[1]!);
  if (count == null || count < 1 || count > 600) return null;
  final unit = duration[2]!.startsWith('year') || duration[2] == 'taon'
      ? 12
      : 1;
  final months = count * unit;
  final asksDailyTarget = RegExp(
    r'\b(daily|every day|everyday|per day|a day|araw-araw|araw araw|'
    r'bawat araw|kada araw)\b',
  ).hasMatch(normalized);
  final currentDate = records?.today ?? DateTime.now();
  final today = DateTime(currentDate.year, currentDate.month, currentDate.day);
  final firstOfTargetMonth = DateTime(today.year, today.month + months, 1);
  final lastTargetMonthDay = DateTime(
    firstOfTargetMonth.year,
    firstOfTargetMonth.month + 1,
    0,
  ).day;
  final targetDate = DateTime(
    firstOfTargetMonth.year,
    firstOfTargetMonth.month,
    today.day > lastTargetMonthDay ? lastTargetMonthDay : today.day,
  );
  final days = targetDate.difference(today).inDays;

  final itemMatch = RegExp(
    r'\b(house|home|property|car|vehicle|condo|land|bahay|sasakyan)\b',
  ).firstMatch(normalized);
  final item = itemMatch?[0] ?? (fil ? 'bibilhin mo' : 'purchase');
  final matchingGoal = records?.goals.where((goal) {
    final name = goal.name.toLowerCase();
    final matchingNames = switch (item) {
      'bahay' => ['bahay', 'house', 'home', 'property'],
      'house' || 'home' => ['house', 'home', 'bahay', 'property'],
      'car' || 'vehicle' || 'sasakyan' => ['car', 'vehicle', 'sasakyan'],
      'condo' || 'land' || 'property' => [item, 'bahay', 'house', 'home'],
      _ => [item],
    };
    return goal.status == GoalStatus.active && matchingNames.any(name.contains);
  }).firstOrNull;
  final alreadySaved = matchingGoal?.shownSaved ?? 0;
  final remaining = (amount - alreadySaved).clamp(0, amount).toDouble();
  final monthlyTarget = (remaining / months * 100).ceil() / 100;
  final dailyTarget = (remaining / days * 100).ceil() / 100;
  final perTime = formatPeso(asksDailyTarget ? dailyTarget : monthlyTarget);
  final left = formatPeso(remaining);

  final plan = fil
      ? [
          'Para sa $item, magtabi ng humigit-kumulang $perTime '
              '${asksDailyTarget ? 'araw-araw' : 'kada buwan'} sa loob ng '
              '$months buwan ($left pa ang kailangang ipunin). '
              '${records == null
                  ? 'Hindi pa nakukuha ang mga goal mo, kaya ipinapalagay nitong wala ka pang naitatabi.'
                  : matchingGoal == null
                  ? 'Wala pang naitatabi para sa goal na ito.'
                  : 'Ang goal mong “${matchingGoal.name}” ay may ${formatPeso(alreadySaved)} nang nakatabi.'}',
          'Tuwid na paghahati ito batay sa presyo at panahong ibinigay mo. '
              'Hindi kasama ang interes o investment returns, fees, at '
              'posibleng pagtaas ng presyo.',
          'Ihambing ang target sa aktuwal mong kita at gastos, pagkatapos '
              'ibawas ang pangangailangan, bills, utang, at iba pang ipon. '
              'Kung hindi kasya, pag-isipang pahabain ang panahon o baguhin '
              'ang target; huwag bawasan ang mahahalagang gastusin.',
        ]
      : [
          'For the $item, aim to set aside about $perTime '
              '${asksDailyTarget ? 'per day' : 'per month'} for $months '
              'months ($left remaining). '
              '${records == null
                  ? 'Your saved goals have not loaded, so this estimate assumes no amount is already set aside.'
                  : matchingGoal == null
                  ? 'No savings are recorded for this specific goal yet.'
                  : 'Your existing “${matchingGoal.name}” goal has ${formatPeso(alreadySaved)} set aside.'}',
          'This is a straight-line target based on the price and timeline you '
              'gave; it does not assume investment returns and excludes fees '
              'or future price changes.',
          'Compare the target with your recorded income and spending after '
              'essentials, bills, debt payments, and other savings '
              'commitments. If it does not fit, consider a longer timeline or '
              'revised target rather than cutting necessary expenses.',
        ];
  return ChatReply(plan.join('\n\n'), isVerifiedGoalPlan: true, filipino: fil);
}

// ------------------------------------------------------------ understanding

bool _asksForFormula(String text) => _has(text, [
  'formula',
  'formulas',
  'calculation',
  'calculations',
  'calculate',
  'calculated',
  'compute',
  'computed',
  'computation',
  'worked out',
  'paano kinuha',
  'pano kinuha',
  'kinukuwenta',
  'kinukwenta',
  'kinuwenta',
  'kinwenta',
  'kwenta',
  'kuwenta',
  'paano nakuha',
  'pano nakuha',
  'how does safe to spend work',
]);

enum _FormulaTopic {
  safeToSpend,
  savings,
  installment,
  goal,
  bills,
  reports,
  wallet,
}

_FormulaTopic _formulaTopic(String text) {
  // A named calculation takes priority over amounts used inside it:
  // "installment balance" is about the loan, not a wallet balance.
  if (_has(text, ['safe to spend', 'daily limit', 'daily spending limit'])) {
    return _FormulaTopic.safeToSpend;
  }
  if (_has(text, [
    'suggested savings',
    'suggested contribution',
    'savings suggestion',
    'suggested to save',
  ])) {
    return _FormulaTopic.savings;
  }
  if (_has(text, [
    'installment',
    'installments',
    'loan',
    'debt',
    'utang',
    'hulog',
    'hulugan',
  ])) {
    return _FormulaTopic.installment;
  }
  if (_has(text, ['goal', 'goals', 'target'])) return _FormulaTopic.goal;
  if (_has(text, ['reports', 'report'])) return _FormulaTopic.reports;
  if (_has(text, ['savings', 'save', 'ipon', 'contribution'])) {
    return _FormulaTopic.savings;
  }
  if (_has(text, ['bill', 'bills', 'bayarin'])) return _FormulaTopic.bills;
  if (_has(text, ['income', 'expenses', 'spending total'])) {
    return _FormulaTopic.reports;
  }
  if (_has(text, ['wallet', 'wallets', 'balance'])) return _FormulaTopic.wallet;
  return _FormulaTopic.safeToSpend;
}

ChatReply _formula(String text, FinanceSnapshot? records, bool fil) {
  final topic = _formulaTopic(text);
  final choices = fil
      ? const [
          'Paano kinukuwenta ang pwede kong gastusin?',
          'Paano kinukuwenta ang iminumungkahing ipon?',
          'Paano kinukuwenta ang hulugan?',
          'Paano kinukuwenta ang target na ipon?',
        ]
      : const [
          'Safe to Spend formula',
          'Suggested savings formula',
          'Installment formula',
          'Goal formula',
        ];
  ChatReply say(String english, String filipino) =>
      ChatReply(fil ? filipino : english, choices: choices, filipino: fil);

  if (topic == _FormulaTopic.reports) {
    return say(
      'Reports add recorded income and expenses within '
          'the dates you selected. Income leaves out borrowed money and loan '
          'repayments received. Expenses include bill payments but leave out '
          'money lent. Transfers between your wallets count as neither income '
          'nor expenses.\n\n'
          'Money left = income − expenses. Saved for goals = contributions '
          'during those dates − money taken back out of goals. A category’s '
          'share = spending in that category ÷ total spending × 100. '
          'With no spending, there is no percentage to divide.',
      'Pinagsasama ng Reports ang naitalang kita at gastos sa loob ng mga '
          'petsang pinili mo. Hindi kasama sa kita ang perang hiniram at ang '
          'mga bayad sa utang na natanggap mo. Kasama sa gastos ang bayad sa '
          'bills pero hindi ang perang ipinautang. Ang paglipat ng pera sa '
          'pagitan ng mga wallet mo ay hindi kita at hindi rin gastos.\n\n'
          'Natitirang pera = kita − gastos. Naipon para sa goals = mga '
          'idinagdag sa mga petsang iyon − perang inilabas mula sa goals. Bahagi '
          'ng isang category = gastos sa category na iyon ÷ kabuuang gastos × '
          '100. Kapag walang gastos, walang porsiyentong makukuwenta.',
    );
  }
  if (topic == _FormulaTopic.wallet) {
    return say(
      'A wallet balance starts with its opening amount, '
          'adds money received and transfers in, and subtracts expenses and '
          'transfers out. Balance corrections also change it. Home’s spending '
          'balance adds active spending wallets; Savings is shown separately. '
          'A transfer changes the two wallets, but not their combined '
          'total.',
      'Nagsisimula ang balance ng wallet sa panimulang halaga nito, '
          'dinadagdagan ng perang natanggap at inilipat papasok, at binabawasan '
          'ng gastos at inilipat palabas. Nababago rin ito ng pag-aayos ng '
          'balance. Pinagsasama sa Home ang mga aktibong wallet na pang-gastos; '
          'hiwalay na ipinapakita ang Savings. Nababago ng paglipat ang '
          'dalawang wallet, pero hindi ang kabuuan nila.',
    );
  }
  if (topic == _FormulaTopic.installment) {
    return say(
      'For an installment, total to pay = regular payment × '
          '(number of payments − 1) + the last payment. If the last payment '
          'is the same, this is just payment amount × number of payments.\n\n'
          'Remaining balance = total to pay − recorded payments. Part payments '
          'reduce the balance, but only fully paid scheduled payments count '
          'as completed. Next due date is the earliest unpaid scheduled payment. '
          'Open the installment statement to see its full payment history. '
          'FinAssist uses the terms you entered; it does not invent an interest '
          'rate.',
      'Sa hulugan, kabuuang babayaran = regular na hulog × (bilang ng hulog '
          '− 1) + huling hulog. Kung pareho ang huling hulog, ito ay hulog × '
          'bilang ng hulog.\n\n'
          'Natitirang balance = kabuuang babayaran − mga naitalang bayad. '
          'Nababawasan ng partial na bayad ang balance, pero ang buong bayad '
          'lang na hulog ang itinuturing na tapos. Ang susunod na due date ay '
          'ang pinakamaagang hulog na hindi pa bayad. Buksan ang statement ng '
          'hulugan para makita ang buong kasaysayan ng bayad. Ginagamit ng '
          'FinAssist ang mga termino na inilagay mo; hindi ito nag-iimbento ng '
          'interes.',
    );
  }
  if (topic == _FormulaTopic.goal) {
    return say(
      'Goal amount still needed = target − money already saved for that goal '
          '(never below zero).\n\n'
          'Amount needed each time = amount still needed ÷ saving dates left '
          'up to your target date. The dates follow your chosen saving schedule. '
          'If no saving date remains, the full remaining amount '
          'is needed now. Without a target date, there is no deadline-based '
          'amount. This shows what the target needs, not what you can afford to '
          'save.',
      'Kulang pa sa goal = target − perang naipon na para sa goal na iyon '
          '(hindi bababa sa zero).\n\n'
          'Kailangan bawat ipon = kulang pa ÷ natitirang petsa ng pag-iipon '
          'hanggang sa target date mo. Sinusunod ng mga petsa ang schedule ng '
          'ipon na pinili mo. Kung wala nang natitirang petsa, kailangan na ngayon '
          'ang buong kulang. Kung walang target date, walang halagang batay sa '
          'deadline. Ipinapakita nito ang kailangan ng target, hindi kung '
          'magkano ang kaya mong ipunin.',
    );
  }
  if (topic == _FormulaTopic.bills) {
    return say(
      'Unpaid bill amount = bill amount − payments recorded for it, '
          'never below zero. Safe to Spend adds the unpaid bills due before '
          'the end of this calendar month, including overdue payments and '
          'scheduled installments. Bills are paid straight from your wallets, so '
          'all of it is held back. Paid bills are not subtracted again.',
      'Hindi pa bayad sa bill = halaga ng bill − mga bayad na naitala para '
          'rito, hindi bababa sa zero. Pinagsasama ng Safe to Spend ang mga '
          'hindi pa bayad na bills na due bago matapos ang buwang ito, kasama '
          'ang mga lampas na sa due at nakatakdang hulog. Diretso sa wallet mo '
          'binabayaran ang bills, kaya buo itong itinatabi. Hindi na ulit '
          'ibinabawas ang mga bill na bayad na.',
    );
  }
  if (records == null) {
    return say(
      'I need your records to show your actual figures. '
          'Safe to Spend divides available money across the days it needs to '
          'last, then subtracts what you spent today. Please try again once your '
          'records load.',
      'Kailangan ko ang records mo para maipakita ang tunay na halaga. '
          'Hinahati ng Safe to Spend ang available na pera sa mga araw na '
          'kailangan nitong tumagal, saka ibinabawas ang nagastos mo ngayon. '
          'Subukan ulit kapag nakuha na ang records mo.',
    );
  }
  if (topic == _FormulaTopic.savings) {
    final suggestion = SavingsSuggestion.from(records);
    if (!suggestion.hasHistory) {
      return say(
        'Suggested savings = 10% of money left after '
            'uncovered bills, money already saved and estimated everyday costs. '
            'The other 90% stays as a buffer. Record everyday spending on at '
            'least 7 different days in the last 30 days before I suggest an '
            'amount. This avoids assuming your everyday costs are zero.',
        'Suggested savings = 10% ng perang matitira pagkatapos ng bills, '
            'perang naipon na at tantiyang araw-araw na gastos. Ang natitirang '
            '90% ay reserba. Magtala ng araw-araw na gastos sa hindi bababa sa 7 '
            'magkakaibang araw sa nakaraang 30 araw bago ako magmungkahi ng '
            'halaga, para hindi ko ipalagay na zero ang araw-araw mong gastos.',
      );
    }
    final available = formatPeso(suggestion.available);
    final costs = formatPeso(suggestion.dailyCosts);
    final amount = formatPeso(suggestion.amount);
    return say(
      'Suggested savings = 10% × max(0, available money − '
          'estimated everyday costs).\n\n'
          'Your available money after bills and money already saved: '
          '$available.\n'
          'Estimated everyday costs for the remaining days: $costs.\n'
          'Suggested to save: $amount (rounded down '
          'to a centavo). The other 90% stays as a buffer. Everyday costs use '
          'your recent average spending per day, with today’s spending already '
          'accounted for. This depends on complete records; you choose whether '
          'and how much to save.',
      'Suggested savings = 10% × max(0, available na pera − tantiyang '
          'araw-araw na gastos).\n\n'
          'Available mong pera pagkatapos ng bills at perang naipon na: '
          '$available.\n'
          'Tantiyang araw-araw na gastos sa natitirang mga araw: $costs.\n'
          'Iminumungkahing ipunin: $amount (ibinaba sa sentimo). Ang '
          'natitirang 90% ay reserba. Ang araw-araw na gastos ay batay sa '
          'karaniwang gastos mo kada araw kamakailan, at nabilang na ang gastos '
          'ngayon. Nakadepende ito sa kumpletong records; ikaw ang magpapasya '
          'kung mag-iipon ka at magkano.',
    );
  }
  final s = records.safeToSpend;
  final billsLeft = formatPeso(math.max(0.0, s.billsDue));
  final wallets = formatPeso(s.walletBalance);
  final spentToday = formatPeso(s.spentToday);
  final goals = formatPeso(s.goalSavings);
  final start = formatPeso(s.spendableThisPeriod);
  final perDay = formatPeso(s.recommendedDailyLimit);
  final share = formatPeso(s.dailyLimit);
  final left = formatPeso(s.leftToday);
  final capped = s.periodBudget != null;
  return say(
    'Here is how Safe to Spend is worked out from your records:\n\n'
        '1. Spending wallets $wallets + today’s spending '
        '$spentToday − bills still to pay this month '
        '$billsLeft − goal money held in spending wallets '
        '$goals. Negative amounts become zero. '
        'Savings is kept separate, so saved money is not subtracted twice.\n'
        '${capped ? 'Your remaining spending plan also caps this amount. ' : ''}'
        '2. Money available at the start of today '
        '$start ÷ ${s.daysLeft} days = $perDay per day'
        '${capped ? ', also capped by your planned daily share.' : '.'}\n'
        '3. Today’s share $share − what you spent today '
        '$spentToday = $left left today. '
        'A negative result means you have gone over today’s amount.\n\n'
        'Today’s spending is added back in step 1 because your wallet balance '
        'already went down, then subtracted in step 3. Bill payments and money '
        'lent are excluded from everyday spending. '
        'The days run through the end of this calendar month. '
        'Figures depend on what you record. Which calculation would you like '
        'next?',
    'Ganito kinukuwenta ang Safe to Spend mula sa records mo:\n\n'
        '1. Mga wallet na pang-gastos $wallets + gastos ngayon $spentToday − '
        'bills na babayaran pa ngayong buwan $billsLeft − perang para sa goals '
        'na nasa mga wallet na pang-gastos $goals. Nagiging zero ang negatibo. '
        'Hiwalay ang Savings, kaya hindi nababawas nang dalawang beses ang '
        'naipon.\n'
        '${capped ? 'Nililimitahan din ito ng natitira sa plano mong gastos. ' : ''}'
        '2. Available na pera sa simula ng araw $start ÷ ${s.daysLeft} araw = '
        '$perDay kada araw'
        '${capped ? ', na nililimitahan din ng nakaplano mong bahagi kada araw.' : '.'}\n'
        '3. Bahagi ngayong araw $share − nagastos mo ngayon $spentToday = $left '
        'na natitira ngayon. Kapag negatibo, lumampas ka na sa halaga ngayong '
        'araw.\n\n'
        'Ibinabalik ang gastos ngayon sa hakbang 1 dahil bumaba na ang balance '
        'ng wallet mo, saka ibinabawas sa hakbang 3. Hindi kasama sa araw-araw '
        'na gastos ang bayad sa bills at perang ipinautang. Hanggang sa '
        'katapusan ng buwang ito ang bilang ng araw. Nakadepende ang mga halaga '
        'sa itinatala mo. Aling kuwenta ang gusto mong makita sunod?',
  );
}

enum _Extreme { smallest, biggest }

_Extreme? _extremeRequested(String text) {
  if (_has(text, [
    'smallest',
    'lowest',
    'least',
    'minimum',
    'pinakamaliit',
    'pinakamababa',
    'pinakamababang',
    'pinakamura',
  ])) {
    return _Extreme.smallest;
  }
  if (_has(text, [
    'biggest',
    'largest',
    'highest',
    'greatest',
    'maximum',
    'pinakamalaki',
    'pinakamalaking',
    'pinakamataas',
    'pinakamahal',
  ])) {
    return _Extreme.biggest;
  }
  return null;
}

T _selectExtreme<T>(
  List<T> values,
  _Extreme extreme, {
  required double Function(T) value,
}) {
  return values.reduce(
    (first, next) => extreme == _Extreme.smallest
        ? value(next) < value(first)
              ? next
              : first
        : value(next) > value(first)
        ? next
        : first,
  );
}

enum _Intent {
  greeting,
  help,
  safeToday,
  safeTodayComparison,
  insights,
  savingsPlan,
  spent,
  savingsCapacity,
  topSpending,
  bills,
  balance,
  savings,
  debts,
  income,
  advice,
  budgetPlan,
  budgetRule,
  emergencyFund,
  budgetEnough,
}

/// Lowercase words only, so phrases can be matched as whole words.
String _plain(String text) => text
    .toLowerCase()
    .replaceAll(RegExp("[’'`]"), '')
    .split(RegExp('[^a-z0-9ñ]+'))
    .where((word) => word.isNotEmpty)
    .join(' ');

/// Whether the padded plain [text] holds any of [phrases] as whole words.
bool _has(String text, List<String> phrases) =>
    phrases.any((phrase) => text.contains(' $phrase '));

/// Whether a word in [text] is built on one of these Tagalog [roots]:
/// "napautang" and "pinautang" on "utang", "naipon" on "ipon".
bool _hasRoot(String text, List<String> roots) =>
    text.trim().split(' ').any((word) => roots.any(word.contains));

_Intent? _intentOf(String text) {
  final words = text.trim().split(' ');
  if (words.every(_greetings.contains)) return _Intent.greeting;

  if (_asksSpendingComparison(text)) return _Intent.advice;
  if (_has(text, [
    'insight',
    'insights',
    'financial analysis',
    'money analysis',
    'analyze my finances',
    'analyse my finances',
    'suriin ang aking pananalapi',
  ])) {
    return _Intent.insights;
  }

  // "Help me budget" is a budget question, not a question about Fin.
  if (_has(text, [
        'what can you do',
        'help',
        'ano kaya mo',
        'ano ang kaya mo',
        'paano ka gamitin',
      ]) &&
      !_hasRoot(text, ['budget', 'badyet'])) {
    return _Intent.help;
  }
  if (_has(text, [
    'can i spend',
    'safe to spend',
    'left to spend',
    'daily limit',
    'budget today',
    'budget for today',
    'budget ko ngayon',
    'pwede kong gastusin',
    'pwede ko pang gastusin',
    'pwede ko gastusin',
    'natitira ngayon',
    'gumastos ngayon',
    'gumastos today',
    'gastos ngayon',
    'gastos today',
  ])) {
    return _Intent.safeToday;
  }
  if (RegExp(
    r'\b(?:pwede|can i|could i|may i)\b.*\b(?:gastos|gumastos|spend)\b'
    r'.*\b(?:today|ngayon)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    return _Intent.safeTodayComparison;
  }
  if (findAmount(text) != null &&
      (_has(text, ['how about', 'what about']) || _has(text, ['paano kung']))) {
    return _Intent.safeTodayComparison;
  }
  if (_has(text, [
    '50 30 20',
    'budget rule',
    'budget rules',
    'budgeting rule',
    'budgeting rules',
  ])) {
    return _Intent.budgetRule;
  }
  if (_has(text, [
        'emergency fund',
        'emergency funds',
        'emergency savings',
        'emergency money',
      ]) ||
      (_hasRoot(text, ['emergency']) &&
          (_hasRoot(text, ['ipon', 'pondo', 'fund']) ||
              _has(text, ['savings', 'save', 'pera', 'money'])))) {
    return _Intent.emergencyFund;
  }
  if (_asksBudgetEnough(text)) return _Intent.budgetEnough;
  if (_hasRoot(text, ['budget', 'badyet', 'kasyahin']) ||
      (_hasRoot(text, ['manage', 'pamahala']) &&
          _has(text, [
            'money',
            'pera',
            'salary',
            'sahod',
            'sweldo',
            'allowance',
            'baon',
            'income',
            'finances',
          ])) ||
      (_has(text, ['paano', 'pano']) && _hasRoot(text, ['gastusin'])) ||
      _has(text, [
        'divide my',
        'split my',
        'allocate my',
        'spending plan',
        'money plan',
        'plan my spending',
        'plan my money',
        'how should i spend',
        'how to spend my',
        'use my money',
        'use my salary',
        'spend my salary',
        'spend my allowance',
        'hatiin',
        'hahatiin',
        'paghatiin',
        'plano sa pera',
        'plano sa gastos',
        'gamitin ng tama',
        'gamitin nang tama',
        'gamitin ang pera',
        'gamitin ang sahod',
        'gamitin ang sweldo',
        'gamitin ang allowance',
      ])) {
    return _Intent.budgetPlan;
  }
  if (_has(text, [
        'how can i save',
        'how to save',
        'how do i save',
        'save more',
        'savings suggestions',
        'saving suggestions',
        'suggestions to save',
        'ways to save',
        'saving tips',
        'savings tips',
        'tips to save',
        'tips',
        'tip',
        'advice',
        'paano makaipon',
        'paano mag ipon',
        'paano magipon',
        'makatipid',
        'tipid',
        'payo',
        'mungkahi',
        'suhestiyon',
      ]) ||
      _hasRoot(text, ['tipid']) ||
      (_has(text, ['paano', 'pano', 'how']) && _hasRoot(text, ['ipon']))) {
    return _Intent.advice;
  }
  if (_has(text, [
    'savings plan',
    'saving plan',
    'plan my savings',
    'plan for saving',
    'how should i save',
    'how do i plan my savings',
    'savings strategy',
    'plano sa ipon',
    'planong pag iipon',
  ])) {
    return _Intent.savingsPlan;
  }
  if (_has(text, [
    'biggest income',
    'largest income',
    'highest income',
    'smallest income',
    'lowest income',
    'pinakamalaking kita',
    'pinakamataas na kita',
    'pinakamaliit na kita',
    'pinakamababang kita',
  ])) {
    return _Intent.income;
  }
  if (_has(text, [
        'how much can i save',
        'how much could i save',
        'how much should i save',
        'how much do i need to save',
        'how much money do i need to save',
        'how much can i put aside',
        'how much can i set aside',
        'magkano ang maipon',
        'magkano ang maiipon',
        'magkano ang pwede kong ipon',
        'magkano ang pwede ko ipon',
        'magkano ang kaya kong ipon',
        'magkano ang kaya kong maipon',
      ]) ||
      (_hasRoot(text, ['maipon', 'maiipon', 'makapagipon']) &&
          _has(text, [
            'income',
            'salary',
            'sahod',
            'sweldo',
            'expense',
            'expenses',
            'gastos',
            'spending',
            'this week',
            'this month',
            'linggo',
            'buwan',
          ]))) {
    return _Intent.savingsCapacity;
  }
  if (_has(text, [
    'biggest expense',
    'largest expense',
    'highest expense',
    'smallest expense',
    'lowest expense',
    'pinakamalaking gastos',
    'pinakamaliit na gastos',
  ])) {
    return _Intent.spent;
  }
  if (_extremeRequested(text) != null &&
      _has(text, ['bill', 'bills', 'bayarin', 'babayaran'])) {
    return _Intent.bills;
  }
  if (_has(text, [
    'the most',
    'biggest',
    'pinakamalaki',
    'pinakamalaking',
    'saan napupunta',
    'saan napunta',
    'where does my money go',
    'where did my money go',
  ])) {
    return _Intent.topSpending;
  }
  if (_has(text, [
        'did i spend',
        'have i spent',
        'i spent',
        'spent',
        'expenses',
      ]) ||
      _hasRoot(text, ['gastos', 'ginastos', 'gumastos'])) {
    return _Intent.spent;
  }
  if (_has(text, ['bill', 'bills', 'bayarin', 'babayaran', 'due'])) {
    return _Intent.bills;
  }
  if (_has(text, [
        'debt',
        'debts',
        'owe',
        'owed',
        'owes',
        'lend',
        'lent',
        'borrow',
        'borrowed',
        'loan',
        'loans',
        'installment',
        'installments',
      ]) ||
      _hasRoot(text, [
        'utang',
        'hiram',
        'iniram',
        'umiram',
        'hulug',
        'hulog',
        'inulug',
      ])) {
    return _Intent.debts;
  }
  if (_has(text, ['savings', 'saved', 'goal', 'goals']) ||
      _hasRoot(text, ['ipon'])) {
    return _Intent.savings;
  }
  if (_has(text, [
        'income',
        'sahod',
        'sweldo',
        'allowance',
        'baon',
        'received',
        'earn',
        'earned',
        'earnings',
        'kita ko',
      ]) ||
      _hasRoot(text, ['kinita', 'kumita'])) {
    return _Intent.income;
  }
  if (_has(text, [
    'balance',
    'how much money',
    'how much do i have',
    'magkano pera',
    'pera ko',
    'wallet',
    'wallets',
    'natitirang pera',
  ])) {
    return _Intent.balance;
  }
  if (_has(text, ['spend', 'spending', 'expense'])) return _Intent.spent;
  return null;
}

const _greetings = {
  'hi',
  'hello',
  'hey',
  'kumusta',
  'kamusta',
  'musta',
  'good',
  'morning',
  'afternoon',
  'evening',
  'po',
  'fin',
};

bool _looksFinancial(String text) =>
    _has(text, _financeWords) ||
    _hasRoot(text, [
      'utang',
      'hiram',
      'iniram',
      'umiram',
      'gastos',
      'ipon',
      'sahod',
      'sweldo',
      'bayad',
      'bayar',
    ]);

const _financeWords = [
  'magkano',
  'how much',
  'presyo',
  'pamasahe',
  'fare',
  'money',
  'peso',
  'pesos',
  'budget',
  'save',
  'saving',
  'savings',
  'spend',
  'spending',
  'expense',
  'expenses',
  'income',
  'salary',
  'allowance',
  'bill',
  'bills',
  'pay',
  'payment',
  'debt',
  'loan',
  'goal',
  'wallet',
  'cash',
  'gcash',
  'maya',
  'bank',
  'transfer',
  'balance',
  'afford',
  'invest',
  'price',
  'cost',
  'financial',
  'finance',
  'baon',
  'gastos',
  'ipon',
  'utang',
  'sahod',
  'bayad',
  'pera',
];

// -------------------------------------------------------------- the answers

ChatReply _safeToday(FinanceSnapshot records, bool fil) {
  if (records.wallets.isEmpty) return _noWallets(fil);
  final s = records.safeToSpend;
  final monthEnd = formatMonthDay(_lastDay(records));

  if (s.isOverLimit) {
    final spent = formatPeso(s.spentToday);
    final over = formatPeso(-s.leftToday);
    final limit = formatPeso(s.dailyLimit);
    return ChatReply(
      fil
          ? 'Nakagastos ka na ng $spent ngayong araw, $over na lampas sa limit '
                'mong $limit. Gawing magaan ang gastos bukas para makahabol '
                'bago matapos ang buwan sa $monthEnd.'
          : "You've spent $spent today, which is $over over your limit of "
                '$limit. Keeping tomorrow light helps you catch up before '
                'month end on $monthEnd.',
      filipino: fil,
    );
  }
  final left = formatPeso(_down(s.leftToday));
  final limit = formatPeso(_down(s.dailyLimit));
  return ChatReply(
    fil
        ? 'Pwede ka pang gumastos ng $left ngayong araw, mula sa $limit na '
              'limit mo ngayon. Sa ganito, ligtas ang bills at ang perang '
              'nakatabi, at may ${s.daysLeft} araw pa ngayong buwan hanggang '
              '$monthEnd.'
        : "You can still spend $left today, out of today's $limit limit. "
              'That keeps bills and money set aside safe, with '
              '${_days(s.daysLeft)} left in this month through $monthEnd.',
    filipino: fil,
  );
}

ChatReply _safeTodayComparison(String text, FinanceSnapshot records, bool fil) {
  final amount = findAmount(text)?.value;
  if (amount == null) return _safeToday(records, fil);

  final asked = formatPeso(amount);
  final left = formatPeso(_down(records.safeToSpend.leftToday));
  if (amount <= _down(records.safeToSpend.leftToday)) {
    return ChatReply(
      fil
          ? 'Oo, pasok ang $asked sa $left na pwede mo pang gastusin ngayong '
                'araw. Itabi ang matitira para sa mga planadong gastos, bills '
                'at ipon.'
          : 'Yes, $asked fits within your $left left-to-spend amount for '
                'today. Keep the rest for your planned expenses, bills and '
                'savings.',
      filipino: fil,
    );
  }
  return ChatReply(
    fil
        ? 'Mas malaki ang $asked kaysa sa $left na pwede mo pang gastusin '
              'ngayong araw. Kapag ginastos mo ito, baka maapektuhan ang bills '
              'mo o ang perang nakatabi.'
        : '$asked is more than the $left you have left to spend today. '
              'Spending that much could affect your bills or money set aside.',
    filipino: fil,
  );
}

ChatReply _spent(String text, FinanceSnapshot records, bool fil) {
  final (period, label) = _periodIn(text, records.now);
  final when = _when(label, fil);
  final during = transactionsIn(records.transactions, period);
  final extreme = _extremeRequested(text);
  if (extreme != null) {
    final expenses = during
        .where(
          (transaction) =>
              transaction.type == TransactionType.expense &&
              !transaction.isBillPayment &&
              !transaction.isDebtMovement &&
              transaction.amount > 0,
        )
        .toList();
    if (expenses.isEmpty) {
      return ChatReply(
        fil
            ? 'Wala ka pang naitalang karaniwang gastos $when.'
            : "You haven't recorded any ordinary expenses $label.",
        filipino: fil,
      );
    }
    final selected = _selectExtreme(
      expenses,
      extreme,
      value: (transaction) => transaction.amount,
    );
    final smallest = extreme == _Extreme.smallest;
    final amount = formatPeso(selected.amount);
    return ChatReply(
      fil
          ? 'Ang ${smallest ? 'pinakamaliit na' : 'pinakamalaking'} karaniwang '
                'gastos mo $when ay $amount para sa ${selected.label}.'
          : 'Your ${smallest ? 'smallest' : 'biggest'} ordinary expense '
                '$label was $amount for ${selected.label}.',
      filipino: fil,
    );
  }
  final byCategory = spendingByCategory(during);
  final total = byCategory.fold<double>(0, (sum, entry) => sum + entry.value);
  final category = _categoryIn(text);

  if (category != null) {
    final spent = byCategory
        .where((entry) => entry.key == category)
        .fold<double>(0, (sum, entry) => sum + entry.value);
    if (spent <= 0) {
      return ChatReply(
        fil
            ? 'Wala ka pang gastos sa $category $when.'
            : "You haven't spent anything on $category $label.",
        filipino: fil,
      );
    }

    final count = during
        .where(
          (t) =>
              t.type == TransactionType.expense &&
              !t.isDebtMovement &&
              t.label == category,
        )
        .length;
    final share = _percent(spent, total);
    return ChatReply(
      fil
          ? 'Nakagastos ka ng ${formatPeso(spent)} sa $category $when, sa '
                '$count gastos. Iyan ay $share ng gastos mo $when.'
          : "You've spent ${formatPeso(spent)} on $category $label, across "
                '$count ${count == 1 ? 'expense' : 'expenses'}. That is '
                '$share of your spending $label.',
      filipino: fil,
    );
  }

  if (total <= 0) {
    return ChatReply(
      fil
          ? 'Wala ka pang naitalang gastos $when.'
          : "You haven't recorded any spending $label yet.",
      filipino: fil,
    );
  }
  final top = byCategory
      .take(2)
      .map((e) => '${e.key} (${formatPeso(e.value)})');
  return ChatReply(
    fil
        ? 'Nakagastos ka ng ${formatPeso(total)} $when. Karamihan ay napunta '
              'sa ${top.join(' at ')}.'
        : "You've spent ${formatPeso(total)} $label. Most of it went to "
              '${top.join(' and ')}.',
    filipino: fil,
  );
}

ChatReply _savingsPlan(FinanceSnapshot records, String question, bool fil) {
  final suggestion = SavingsSuggestion.from(records);
  final month = ReportPeriod.monthOf(records.now);
  final currentMonth = transactionsIn(records.transactions, month);
  final flow = inAndOut(currentMonth);
  final recordedExpenses = spendingByCategory(
    currentMonth,
  ).fold<double>(0, (sum, entry) => sum + entry.value);
  final noIncome = flow.moneyIn <= 0;
  final noHistory = !suggestion.hasHistory;

  if (noIncome || noHistory) {
    final missing = fil
        ? [
            if (noIncome) 'kahit isang naitalang kita para sa panahong ito',
            if (noHistory)
              'araw-araw na gastos na naitala sa hindi bababa sa 7 '
                  'magkakaibang araw sa nakaraang 30 araw',
          ]
        : [
            if (noIncome)
              'at least one recorded income entry for the planning period',
            if (noHistory)
              'ordinary spending recorded on at least 7 different days in '
                  'the last 30 days',
          ];
    return ChatReply(
      fil
          ? 'Hindi pa ako makagawa ng maaasahang plano sa pag-iipon dahil '
                'kailangan ko ng ${missing.join(' at ')}. Itala ang kita at '
                'araw-araw na gastos mo, kasama ang bills at bayad sa utang, '
                'saka magtanong ulit. Hindi ibig sabihin ng walang tala na '
                'zero ang gastos.'
          : 'I cannot make a reliable savings plan yet because I need '
                '${missing.join(' and ')}. '
                'Please record your income and everyday expenses, including '
                'bills and debt payments, then ask me again. A missing record '
                'does not mean the expense was zero.',
      filipino: fil,
    );
  }

  final billsDue = formatPeso(math.max(0.0, records.safeToSpend.billsDue));
  final goalMoney = formatPeso(records.goalSavings);
  final income = formatPeso(flow.moneyIn);
  final expenses = formatPeso(recordedExpenses);
  final monthlySuggested = suggestion.amount;
  final weekly = formatPeso((monthlySuggested / 4 * 100).floor() / 100);
  final daily = formatPeso((monthlySuggested / 30 * 100).floor() / 100);
  final asksAboutBills = _has(question, [
    'bill',
    'bills',
    'bayarin',
    'utang',
    'debt',
  ]);
  final questionNote = !asksAboutBills
      ? ''
      : fil
      ? ' Itinatabi nito ang bills na due pa ngayong buwan, at protektado ang '
            'perang nakatabi na para sa goals.'
      : ' This holds back the bills still due this month, and money already '
            'set aside for goals is protected.';

  if (monthlySuggested <= 0) {
    return ChatReply(
      fil
          ? 'Base sa naitala mong kita na $income at gastos na $expenses '
                'ngayong buwan, wala pang maaasahang halagang maimumungkahi '
                'para sa ipon pagkatapos ng mga naitalang bayarin. Ang bills na '
                'kailangan pang bayaran ay $billsDue, at may $goalMoney nang '
                'nakatabi para sa goals. Ituloy ang kumpletong pagtala ng bills '
                'at gastos, unahin ang pangangailangan, at balikan ang plano '
                'pagkatapos ng susunod mong kita.$questionNote'
          : 'Based on your recorded income of $income and '
                'expenses of $expenses this month, there is no '
                'reliable amount left to suggest for savings after your '
                'recorded commitments. Bills currently needing coverage total '
                '$billsDue, and $goalMoney is already set '
                'aside for goals. Keep recording complete bills and expenses, '
                'protect essentials, and review the plan after your next '
                'income cycle.$questionNote',
      filipino: fil,
    );
  }

  final monthly = formatPeso(monthlySuggested);
  return ChatReply(
    fil
        ? 'Ito ang plano sa pag-iipon base sa records mo: mag-ipon ng mga '
              '$monthly kada buwan, o mga $weekly kada linggo o $daily kada '
              'araw. Ginamit dito ang naitalang kita na $income, naitalang '
              'gastos na $expenses, bills na kailangan pang bayaran na '
              '$billsDue, at $goalMoney na nakatabi na para sa goals. Iniiwan '
              'ng plano ang malaking bahagi ng natitira bilang reserba. Baka '
              'kulang pa ang records, kaya tingnan muna ang pangangailangan at '
              'bagong bills bago ilipat ang halagang ito.$questionNote'
        : 'Here is a savings plan based on your recorded data: save about '
              '$monthly per month, or about $weekly per week or $daily per '
              'day. This uses recorded income of $income, recorded expenses '
              'of $expenses, bills currently needing coverage of $billsDue, '
              'and $goalMoney already set aside for goals. The plan leaves '
              'most of the calculated remainder as a buffer. Records may be '
              'incomplete, so keep checking essentials and new bills before '
              'transferring the suggested amount.$questionNote',
    filipino: fil,
  );
}

ChatReply _savingsCapacity(String text, FinanceSnapshot records, bool fil) {
  final (period, label) = _periodIn(text, records.now);
  final when = _when(label, fil);
  final during = transactionsIn(records.transactions, period);
  final flow = inAndOut(during);
  final spending = spendingByCategory(
    during,
  ).fold<double>(0, (sum, entry) => sum + entry.value);

  if (flow.moneyIn <= 0) {
    return ChatReply(
      fil
          ? 'Wala pa akong naitalang kita mo $when, kaya hindi ko pa '
                'makalkula kung magkano ang maiipon mo.'
          : "I don't have any recorded income for $label, so I can't "
                'calculate how much you could save yet.',
      filipino: fil,
    );
  }
  final available = flow.moneyIn - spending;
  if (available <= 0) {
    return ChatReply(
      fil
          ? 'Base sa naitala mong kita at araw-araw na gastos $when, wala '
                'pang natitirang pera na maiipon.'
          : 'Based on your recorded income and everyday expenses $label, '
                'there is no recorded amount left over to save yet.',
      filipino: fil,
    );
  }
  return ChatReply(
    fil
        ? 'Base sa records mo, may mga ${formatPeso(available)} kang maiipon '
              '$when: ${formatPeso(flow.moneyIn)} na natanggap bawas '
              '${formatPeso(spending)} na araw-araw na gastos. Hindi kasama '
              'rito ang bills o gastos na hindi naitala, kaya magtira ng '
              'kaunting reserba bago mo ito itabi.'
        : 'Based on your records, you could have about '
              '${formatPeso(available)} left to save $label: '
              '${formatPeso(flow.moneyIn)} received minus '
              '${formatPeso(spending)} in everyday expenses. This does not '
              'include unrecorded bills or spending, so keep a buffer before '
              'setting it aside.',
    filipino: fil,
  );
}

ChatReply _topSpending(String text, FinanceSnapshot records, bool fil) {
  final (period, label) = _periodIn(text, records.now);
  final when = _when(label, fil);
  final byCategory = spendingByCategory(
    transactionsIn(records.transactions, period),
  );
  final total = byCategory.fold<double>(0, (sum, entry) => sum + entry.value);
  if (total <= 0) {
    return ChatReply(
      fil
          ? 'Wala ka pang naitalang gastos $when.'
          : "You haven't recorded any spending $label yet.",
      filipino: fil,
    );
  }

  final lines = [
    for (final (i, entry) in byCategory.take(3).indexed)
      '${i + 1}. ${entry.key}: ${formatPeso(entry.value)} '
          '(${_percent(entry.value, total)})',
  ];
  return ChatReply(
    fil
        ? 'Pinakamalaking gastos mo $when:\n${lines.join('\n')}'
        : 'Your biggest spending $label:\n${lines.join('\n')}',
    filipino: fil,
  );
}

ChatReply _bills(String text, FinanceSnapshot records, bool fil) {
  final extreme = _extremeRequested(text);
  if (extreme != null) {
    final unpaid = records.bills.where((bill) => !bill.isSettled).toList();
    if (unpaid.isEmpty) {
      return ChatReply(
        fil
            ? 'Wala kang naitalang bills na hindi pa bayad.'
            : "You don't have any unpaid bills recorded.",
        filipino: fil,
      );
    }
    final selected = _selectExtreme(
      unpaid,
      extreme,
      value: (bill) => bill.remaining,
    );
    final smallest = extreme == _Extreme.smallest;
    final amount = formatPeso(selected.remaining);
    final due = formatMonthDay(selected.dueDate);
    return ChatReply(
      fil
          ? 'Ang ${smallest ? 'pinakamaliit na' : 'pinakamalaking'} bill mong '
                'hindi pa bayad ay ${selected.name}, $amount, na due sa $due.'
          : 'Your ${smallest ? 'smallest' : 'biggest'} unpaid bill is '
                '${selected.name} at $amount, due $due.',
      filipino: fil,
    );
  }
  final today = records.today;
  final DateTime until;
  final String label;
  if (_has(text, ['this month', 'ngayong buwan', 'month', 'buwan'])) {
    until = DateTime(today.year, today.month + 1);
    label = fil ? 'bago matapos ang buwan' : 'before the month ends';
  } else {
    until = today.add(const Duration(days: 7));
    label = fil ? 'sa susunod na 7 araw' : 'in the next 7 days';
  }

  final unpaid = records.bills.where((bill) => !bill.isSettled).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final overdue = unpaid.where((b) => b.dueDate.isBefore(today)).toList();
  final soon = unpaid
      .where((b) => !b.dueDate.isBefore(today) && b.dueDate.isBefore(until))
      .toList();

  if (overdue.isEmpty && soon.isEmpty) {
    final later = unpaid.where((b) => !b.dueDate.isBefore(until)).toList();
    if (later.isEmpty) {
      return ChatReply(
        fil
            ? 'Wala kang paparating na bills na hindi pa bayad.'
            : "You don't have any unpaid bills coming up.",
        filipino: fil,
      );
    }
    final next = later.first;
    final amount = formatPeso(next.remaining);
    final due = formatMonthDay(next.dueDate);
    return ChatReply(
      fil
          ? 'Walang bills na due $label. Ang susunod ay ${next.name}, $amount '
                'sa $due.'
          : 'No bills are due $label. The next one is ${next.name}, $amount '
                'on $due.',
      filipino: fil,
    );
  }

  String line(BillInstance bill) =>
      '• ${bill.name}: ${formatPeso(bill.remaining)}, '
      '${formatMonthDay(bill.dueDate)}';
  final total = formatPeso(
    [...overdue, ...soon].fold<double>(0, (sum, bill) => sum + bill.remaining),
  );
  return ChatReply(
    [
      if (overdue.isNotEmpty)
        '${fil ? 'Lampas na sa due' : 'Overdue'}:\n'
            '${overdue.map(line).join('\n')}',
      if (soon.isNotEmpty)
        '${fil ? 'Babayaran' : 'Due'} $label:\n${soon.map(line).join('\n')}',
      fil ? 'Lahat-lahat, $total.' : 'That is $total in all.',
    ].join('\n\n'),
    filipino: fil,
  );
}

ChatReply _balance(FinanceSnapshot records, bool fil) {
  if (records.wallets.isEmpty) return _noWallets(fil);
  // What can be spent, as on Home: the spending wallets, each less what
  // goals hold in it. The goal money is named, so nothing seems lost.
  double free(Wallet wallet) => freeInWallet(wallet, records.goals);
  final wallets =
      records.wallets
          .where((wallet) => !wallet.archived && !wallet.isSetAside)
          .toList()
        ..sort((a, b) => free(b).compareTo(free(a)));
  final available = formatPeso(
    wallets.fold<double>(0, (sum, w) => sum + free(w)),
  );
  final forGoals =
      records.walletBalance -
      wallets.fold<double>(0, (sum, w) => sum + free(w));
  final s = records.safeToSpend;
  final spendable = _down(s.spendableThisPeriod - s.spentToday);
  final list = wallets
      .take(5)
      .map((w) => '${w.name} ${formatPeso(free(w))}')
      .join(', ');
  final goalLine = forGoals <= 0.005
      ? ''
      : fil
      ? ' May ${formatPeso(forGoals)} pang nakatabi para sa goals mo.'
      : ' Another ${formatPeso(forGoals)} is set aside for your goals.';
  final toSpend = formatPeso(spendable < 0 ? 0 : spendable);
  final until = formatMonthDay(_lastDay(records));

  return ChatReply(
    fil
        ? 'May $available kang available sa ${wallets.length} wallet: '
              '$list.$goalLine\n\nPagkatapos ng bills ngayong buwan at perang '
              'nakatabi, $toSpend ang pwede mong gastusin hanggang $until.'
        : 'You have $available available across ${wallets.length} '
              '${wallets.length == 1 ? 'wallet' : 'wallets'}: $list.$goalLine'
              '\n\nAfter bills due this month and money set aside, $toSpend '
              'is free to spend until $until.',
    filipino: fil,
  );
}

ChatReply _savings(FinanceSnapshot records, bool fil) {
  final goals = records.goals
      .where((goal) => goal.status == GoalStatus.active)
      .toList();
  if (goals.isEmpty) {
    return ChatReply(
      fil
          ? 'Wala ka pang nakatabing ipon o goal. Ang paggawa ng goal, kahit '
                'maliit, ang pinakamadaling simula.'
          : "You don't have any savings set aside or goals yet. Making a goal, "
                'even a small one, is the easiest way to start.',
      filipino: fil,
    );
  }

  final lines = [
    for (final goal in goals.take(5))
      '• ${goal.name}: ${formatPeso(goal.shownSaved)} ${fil ? 'sa' : 'of'} '
          '${formatPeso(goal.targetAmount)} '
          '(${(goal.progress * 100).round()}%)',
  ];
  final saved = formatPeso(records.goalSavings);
  return ChatReply(
    fil
        ? 'Nakatabi mo na ang $saved para sa ${goals.length} goal:\n'
              '${lines.join('\n')}'
        : "You've set aside $saved for ${goals.length} "
              '${goals.length == 1 ? 'goal' : 'goals'}:\n${lines.join('\n')}',
    filipino: fil,
  );
}

ChatReply _debts(String text, FinanceSnapshot records, bool fil) {
  // A question about one person or one debt, such as "Ilan yung napautang ko
  // kay Ana?", is answered about that one.
  final named = _namedDebts(text, records);
  if (named.isNotEmpty) {
    return ChatReply(
      named.map((debt) => _aboutDebt(debt, fil)).join('\n\n'),
      filipino: fil,
    );
  }

  final active = records.debts
      .where((debt) => debt.status == DebtStatus.active)
      .toList();
  final owedToMe = active
      .where(
        (d) => d.direction == DebtDirection.owedToMe && d.stillOwedToMe > 0,
      )
      .toList();
  final iOwe = active.where((d) => d.direction == DebtDirection.iOwe).toList();

  if (owedToMe.isEmpty && iOwe.isEmpty) {
    return ChatReply(
      fil ? 'Wala kang naitalang utang.' : "You don't have any debts recorded.",
      filipino: fil,
    );
  }

  // "Who owes me?" and "What do I owe?" are each about one side.
  final asksOwedToMe =
      _has(text, [
        'owe me',
        'owes me',
        'owed to me',
        'owing me',
        'lend',
        'lent',
        'utang sa akin',
        'utang sakin',
        'singilin',
        'sisingilin',
      ]) ||
      _hasRoot(text, ['pautang']);
  final asksIOwe =
      !asksOwedToMe &&
      _has(text, [
        'i owe',
        'do i owe',
        'my debt',
        'my debts',
        'utang ko',
        'mga utang ko',
        'babayaran ko',
      ]);
  if (asksOwedToMe && owedToMe.isEmpty) {
    return ChatReply(
      fil
          ? 'Walang may utang sa iyo sa records mo.'
          : 'No one owes you money in your records.',
      filipino: fil,
    );
  }
  if (asksIOwe && iOwe.isEmpty) {
    return ChatReply(
      fil
          ? 'Wala kang utang na babayaran sa records mo.'
          : "You don't have any debts to pay in your records.",
      filipino: fil,
    );
  }

  final parts = <String>[];
  if (iOwe.isNotEmpty && !asksOwedToMe) {
    final lines = iOwe
        .map(
          (d) =>
              '• ${d.name}: ${formatPeso(d.perPayment)} '
              '${_often(d.frequency, fil)}',
        )
        .join('\n');
    parts.add(
      fil
          ? 'May ${iOwe.length} utang kang binabayaran:\n$lines'
          : "You're paying ${iOwe.length} "
                '${iOwe.length == 1 ? 'debt' : 'debts'}:\n$lines',
    );
  }
  if (owedToMe.isNotEmpty && !asksIOwe) {
    final total = formatPeso(
      owedToMe.fold<double>(0, (sum, d) => sum + d.stillOwedToMe),
    );
    final lines = owedToMe
        .map((d) => '• ${d.name}: ${formatPeso(d.stillOwedToMe)}')
        .join('\n');
    parts.add(
      fil
          ? 'May utang sa iyo na $total lahat:\n$lines'
          : 'People owe you $total:\n$lines',
    );
  }
  return ChatReply(parts.join('\n\n'), filipino: fil);
}

/// Debts whose name is in the question, such as Ana in "kay Ana".
List<Debt> _namedDebts(String text, FinanceSnapshot records) {
  final asked = text.trim().split(' ').toSet();
  return records.debts.where((debt) {
    final name = _plain(debt.name).split(' ').where((w) => w.isNotEmpty);
    return name.isNotEmpty && name.every(asked.contains);
  }).toList();
}

/// Where one debt stands.
String _aboutDebt(Debt debt, bool fil) {
  if (debt.status == DebtStatus.settled) {
    return fil
        ? 'Bayad na ang utang para sa ${debt.name}.'
        : 'Your ${debt.name} debt is paid off.';
  }
  final count = debt.paymentCount <= 0
      ? ''
      : fil
      ? ', ${debt.paymentCount} bayad lahat'
      : ', ${debt.paymentCount} payments in all';
  final last = !debt.hasDifferentLastPayment
      ? ''
      : fil
      ? ', ${formatPeso(debt.finalPayment)} ang huli'
      : ', the last one ${formatPeso(debt.finalPayment)}';
  final often = _often(debt.frequency, fil);
  return fil
      ? 'Para sa ${debt.name}, ${formatPeso(debt.perPayment)} ang bayad mo '
            '$often$count$last.'
      : 'For ${debt.name}, you pay ${formatPeso(debt.perPayment)} '
            '$often$count$last.';
}

/// How often a debt is paid, said in the reply's language.
String _often(PaymentFrequency frequency, bool fil) => !fil
    ? frequency.label.toLowerCase()
    : switch (frequency) {
        PaymentFrequency.monthly => 'buwan-buwan',
        PaymentFrequency.semiMonthly => 'dalawang beses kada buwan',
        PaymentFrequency.fortnightly => 'kada 2 linggo',
        PaymentFrequency.weekly => 'linggo-linggo',
      };

ChatReply _income(String text, FinanceSnapshot records, bool fil) {
  final (period, label) = _periodIn(text, records.now);
  final when = _when(label, fil);
  final income = transactionsIn(
    records.transactions,
    period,
  ).where((transaction) => transaction.type == TransactionType.income).toList();
  final received = income.fold<double>(
    0,
    (sum, transaction) => sum + transaction.amount,
  );
  if (received <= 0) {
    return ChatReply(
      fil
          ? 'Wala ka pang naitalang kita $when.'
          : "You haven't recorded any income $label.",
      filipino: fil,
    );
  }
  final extreme = _extremeRequested(text);
  if (extreme != null) {
    final selected = _selectExtreme(
      income,
      extreme,
      value: (transaction) => transaction.amount,
    );
    final smallest = extreme == _Extreme.smallest;
    final amount = formatPeso(selected.amount);
    return ChatReply(
      fil
          ? 'Ang ${smallest ? 'pinakamaliit na' : 'pinakamalaking'} kita mo '
                '$when ay $amount (${selected.label}).'
          : 'Your ${smallest ? 'smallest' : 'biggest'} income $label was '
                '$amount (${selected.label}).',
      filipino: fil,
    );
  }
  return ChatReply(
    fil
        ? 'Nakatanggap ka ng ${formatPeso(received)} $when.'
        : "You've received ${formatPeso(received)} $label.",
    filipino: fil,
  );
}

ChatReply _advice(FinanceSnapshot records, String question, bool fil) {
  if (_asksSpendingComparison(question)) {
    return _spendingPatternComparison(records, question, fil).protected();
  }
  if (records.transactions.isEmpty) {
    return ChatReply(
      fil
          ? 'Simulan sa pagtala ng bawat gastos sa loob ng isang linggo, kahit '
                'maliliit. Makikita mo sa Reports kung saan napupunta ang pera '
                'mo, at maituturo ko kung saan pwedeng magbawas.'
          : 'Start by recording every expense for a week, even the small ones. '
                'Then Reports shows where your money goes, and I can point out '
                'where to cut.',
      choices: _budgetChoices(fil),
      keepUnderAi: true,
      filipino: fil,
    );
  }

  // The same tips as Reports, which never suggest cutting back on what
  // isn't for cutting, like health, school or rent.
  final tips = moneyTipsFor(records, limit: 3, filipino: fil);
  return ChatReply(
    tips.length == 1
        ? tips.single
        : '${fil ? 'Mga tip mula sa records mo' : 'Tips from your records'}:\n'
              '${[for (final tip in tips) '• $tip'].join('\n')}',
    choices: _budgetChoices(fil),
    keepUnderAi: true,
    filipino: fil,
  );
}

List<String> _budgetChoices(bool fil) => fil
    ? const ['Paano ko ibubudget ang pera ko?', 'Ano ang 50/30/20?']
    : const ['How should I budget my money?', 'What is the 50/30/20 rule?'];

/// What a budget sets aside for savings before spending starts. A common
/// first step, small enough for most months.
const _saveShare = 0.10;

/// "Is my budget enough?": against the bills still to pay this month, or
/// "will my money last?" until month end.
bool _asksBudgetEnough(String text) =>
    _has(text, [
      'enough',
      'sapat',
      'kasya',
      'kakasya',
      'aabot',
      'makakaabot',
      'kulang ba',
      'kukulangin',
      'magkukulang',
      'mauubusan',
      'maubusan',
      'mauubos',
      'run out',
      'running out',
      'last until',
      'last till',
      'make it last',
      'will it last',
      'money last',
    ]) &&
    (_hasRoot(text, ['budget', 'badyet']) ||
        _has(text, [
          'money',
          'pera',
          'this month',
          'end of the month',
          'month end',
          'katapusan',
          'buwan',
          'payday',
          'sahod',
          'sweldo',
        ]));

/// "How do I budget?" With an amount ("Paano ko ibubudget ang 15000?") that
/// amount is split; without one, the steps use this month's records. Bills
/// come first and savings next, then the rest is for spending: the same
/// order Safe to Spend uses.
ChatReply _budgetPlan(
  String message,
  String text,
  FinanceSnapshot records,
  bool fil,
) {
  final found = findAmount(message);
  final amount = found != null && (found.isMoney || found.value >= 100)
      ? found.value
      : null;
  return amount == null
      ? _budgetSteps(records, fil)
      : _budgetSplit(amount, text, records, fil);
}

ChatReply _budgetSplit(
  double amount,
  String text,
  FinanceSnapshot records,
  bool fil,
) {
  final billsDue = math.max(0.0, records.safeToSpend.billsDue);
  final days =
      _has(text, [
        'kinsenas',
        'kinsena',
        '15 days',
        '2 weeks',
        'two weeks',
        'semi monthly',
      ])
      ? 15
      : _has(text, ['week', 'weekly', 'linggo', 'lingguhan'])
      ? 7
      : 30;
  final lasting = switch (days) {
    7 => fil ? 'isang linggo' : 'a week',
    15 => fil ? 'dalawang linggo' : 'two weeks',
    _ => fil ? 'isang buwan' : 'a month',
  };
  final whole = formatPeso(amount);
  final bills = formatPeso(billsDue);

  if (billsDue >= amount) {
    return ChatReply(
      fil
          ? 'Ang bills mong babayaran pa ngayong buwan ay $bills, mas malaki '
                'sa $whole. Unahin ang pinakamalapit na due, magtira para sa '
                'pagkain at pamasahe, at ipagpaliban muna ang pag-iipon at ang '
                'hindi pa kailangan.'
          : 'Your bills still to pay this month come to $bills, more than '
                '$whole. Pay the ones due soonest first, keep enough for food '
                'and transport, and leave saving and anything that can wait '
                'for later.',
      filipino: fil,
    ).protected();
  }

  final left = amount - billsDue;
  // Saving waits when bills leave too little for food and transport, since
  // needs come first.
  final save = left >= amount * 0.3 ? _down(amount * _saveShare) : 0.0;
  final spend = left - save;
  final rest = formatPeso(spend);
  final perDay = formatPeso(_down(spend / days));
  final perWeek = formatPeso(_down(spend / days * 7));
  final steps = [
    if (billsDue > 0)
      fil
          ? 'Unahin ang bills: $bills para sa bills na babayaran pa ngayong '
                'buwan.'
          : 'Bills first: $bills for the bills still to pay this month.',
    if (save > 0)
      fil
          ? 'Sunod ang ipon: ${formatPeso(save)} (10%), itabi agad pagkatanggap '
                'mo.'
          : 'Savings next: ${formatPeso(save)} (10%), set aside as soon as you '
                'get it.',
    fil
        ? 'Ang natitirang $rest ay para sa araw-araw na gastos: mga $perDay '
              'kada araw${days > 7 ? ' o $perWeek kada linggo' : ''} kung '
              'kailangan itong tumagal ng $lasting.'
        : 'The rest, $rest, is for everyday spending: about $perDay a day'
              '${days > 7 ? ' or $perWeek a week' : ''} if it has to last '
              '$lasting.',
  ];
  final last = save > 0
      ? (fil
            ? 'Sa huling bahagi kukunin ang pagkain, pamasahe at iba pang '
                  'pangangailangan, kaya planuhin muna ang mga iyon.'
            : 'Food, transport and other needs come out of the last part, so '
                  'plan those first.')
      : (fil
            ? 'Huwag munang mag-ipon ngayon: halos lahat ay napupunta sa '
                  'bills, kaya itabi ang natitira para sa pagkain at pamasahe.'
            : 'Skip saving this time: bills take most of it, so keep the rest '
                  'for food and transport.');
  return ChatReply(
    '${fil ? 'Ganito ang simpleng paraan para i-budget ang $whole' : 'Here is a simple way to budget $whole'}:\n'
    '${[for (final (i, step) in steps.indexed) '${i + 1}. $step'].join('\n')}'
    '\n\n$last',
    choices: fil
        ? const ['Ano ang 50/30/20?', 'Saan napupunta ang pera ko?']
        : const ['What is the 50/30/20 rule?', 'Where am I spending the most?'],
    filipino: fil,
  ).protected();
}

ChatReply _budgetSteps(FinanceSnapshot records, bool fil) {
  final month = ReportPeriod.monthOf(records.now);
  final received = inAndOut(
    transactionsIn(records.transactions, month),
  ).moneyIn;
  final s = records.safeToSpend;
  final billsDue = formatPeso(math.max(0.0, s.billsDue));
  // Saving first is already a step, so the tips saying it again are left out.
  final tip = moneyTipsFor(
    records,
    limit: 1,
    filipino: fil,
    saveFirst: false,
  ).firstOrNull;
  final got = formatPeso(received);
  final tenth = formatPeso(_down(received * _saveShare));
  final today = formatPeso(_down(s.leftToday));

  final steps = fil
      ? [
          s.billsDue > 0
              ? 'Unahin ang bills. May $billsDue ka pang bills na babayaran '
                    'ngayong buwan.'
              : records.bills.isEmpty
              ? 'Unahin ang bills. Ilagay ang mga ito sa Bill Planner para '
                    'mabilang bago ka gumastos.'
              : 'Unahin ang bills. Bayad na lahat ng bills mo ngayong buwan.',
          received > 0
              ? 'Mag-ipon agad pagdating ng pera, bago gumastos. Ang 10% ng '
                    '$got na natanggap mo ngayong buwan ay $tenth.'
              : 'Mag-ipon agad pagdating ng pera, bago gumastos. Kahit 10% '
                    'ay malaking tulong.',
          records.wallets.isEmpty
              ? 'Gastusin ang natitira nang paunti-unti araw-araw. Idagdag ang '
                    'mga wallet mo para makalkula ko kung magkano kada araw.'
              : s.isOverLimit
              ? 'Gastusin ang natitira nang paunti-unti araw-araw. Lampas ka na '
                    'sa limit mo ngayon, kaya magaan na gastos muna bukas.'
              : 'Gastusin ang natitira nang paunti-unti araw-araw. Ngayong '
                    'araw, pwede kang gumastos ng $today at nasa tamang landas '
                    'ka pa rin.',
          'Tingnan ang Reports linggo-linggo para makita kung saan napunta ang '
              'pera mo.',
        ]
      : [
          s.billsDue > 0
              ? 'Pay bills first. You still have $billsDue in bills to pay '
                    'this month.'
              : records.bills.isEmpty
              ? 'Pay bills first. Add them in Bill Planner so they are '
                    'counted before you spend.'
              : "Pay bills first. This month's bills are all paid.",
          received > 0
              ? 'Save as soon as money comes in, before spending. 10% of the '
                    '$got you received this month is $tenth.'
              : 'Save as soon as money comes in, before spending. Even 10% '
                    'helps.',
          records.wallets.isEmpty
              ? 'Spend the rest a little each day. Add your wallets so I can '
                    'work out how much a day.'
              : s.isOverLimit
              ? "Spend the rest a little each day. You're over today's limit, "
                    'so keep tomorrow light.'
              : 'Spend the rest a little each day. Today you can spend $today '
                    'and stay on track.',
          'Check Reports each week to see where your money went.',
        ];
  final example = received > 0 ? got : '₱10,000';
  return ChatReply(
    '${fil ? 'Simpleng paraan ng pag-budget, gamit ang records mo' : 'A simple way to budget, using your records'}:\n'
    '${[for (final (i, step) in steps.indexed) '${i + 1}. $step'].join('\n')}'
    '${tip == null ? '' : '\n\n$tip'}',
    choices: fil
        ? ['Paano ko ibubudget ang $example?', 'Ano ang 50/30/20?']
        : ['How should I budget $example?', 'What is the 50/30/20 rule?'],
    keepUnderAi: true,
    filipino: fil,
  );
}

/// The 50/30/20 rule, worked out on this month's income when there is some.
ChatReply _budgetRule(FinanceSnapshot records, bool fil) {
  final month = ReportPeriod.monthOf(records.now);
  final received = inAndOut(
    transactionsIn(records.transactions, month),
  ).moneyIn;
  final got = formatPeso(received);
  final needs = formatPeso(_down(received * 0.5));
  final wants = formatPeso(_down(received * 0.3));
  final savings = formatPeso(_down(received * 0.2));
  final text = fil
      ? 'Ang 50/30/20 rule ay simpleng gabay sa paghahati ng perang '
            'pumapasok:\n'
            '• 50% para sa pangangailangan: pagkain, upa, bills, pamasahe\n'
            '• 30% para sa gusto: kain sa labas, shopping, lakad\n'
            '• 20% para sa ipon, o pambayad ng utang'
            '${received > 0 ? '\n\nSa $got na natanggap mo ngayong buwan, mga $needs ang para sa pangangailangan, $wants sa gusto at $savings sa ipon.' : ''}'
            '\n\nGabay lang ito. Kung lampas kalahati ang napupunta sa '
            'pangangailangan, bawasan muna ang gusto at mag-ipon kahit kaunti, '
            'kahit 10%.'
      : 'The 50/30/20 rule is a simple guide for splitting what comes in:\n'
            '• 50% for needs: food, rent, bills, transport\n'
            '• 30% for wants: eating out, shopping, outings\n'
            '• 20% for savings, or paying back what you owe'
            '${received > 0 ? '\n\nFor the $got you received this month, that is about $needs for needs, $wants for wants and $savings for savings.' : ''}'
            "\n\nIt's only a guide. If needs take more than half, cut back on "
            'wants first and save what you can, even 10%.';
  return ChatReply(
    text,
    choices: fil
        ? const [
            'Paano ko ibubudget ang pera ko?',
            'Saan napupunta ang pera ko?',
          ]
        : const [
            'How should I budget my money?',
            'Where am I spending the most?',
          ],
    filipino: fil,
  );
}

/// How big an emergency fund should be: the usual 3 to 6 months, worked out
/// on the last 30 days of spending once there is enough of it.
ChatReply _emergencyFund(FinanceSnapshot records, bool fil) {
  final from = records.today.subtract(const Duration(days: 29));
  final spent = spendingByCategory(
    records.transactions.where(
      (t) => !t.date.isBefore(from) && !t.date.isAfter(records.now),
    ),
  ).fold<double>(0, (sum, entry) => sum + entry.value);
  final fund = records.goals
      .where(
        (g) =>
            g.kind == GoalKind.emergencyFund && g.status == GoalStatus.active,
      )
      .firstOrNull;
  final enough = SavingsSuggestion.from(records).hasHistory && spent > 0;
  final last30 = formatPeso(spent);
  final three = formatPeso(_up(spent * 3));
  final six = formatPeso(_up(spent * 6));

  final parts = fil
      ? [
          'Ang emergency fund ay perang nakatabi para lang sa biglaang '
              'pangangailangan, gaya ng pagkakasakit o pagkawala ng kita. '
              'Karaniwang gabay ang 3 hanggang 6 na buwan ng pangunahing gastos '
              'mo.',
          enough
              ? 'Base sa $last30 na nagastos mo sa nakaraang 30 araw, ang 3 '
                    'buwan ay mga $three at ang 6 na buwan ay mga $six. Maaaring '
                    'mas mababa kung pangangailangan lang ang bibilangin. '
                    'Magsimula sa 1 buwan; kahit ₱50 kada araw ay aabot ng mga '
                    '₱1,500 kada buwan.'
              : 'Itala ang mga gastos mo nang ilang linggo at makakalkula ko '
                    'kung magkano dapat ang sa iyo.',
          fund != null
              ? 'Ang ${fund.name} goal mo ay may ${formatPeso(fund.savedAmount)} '
                    'na.'
              : 'Pwede kang magsimula ng isa sa Goals at piliin ang Emergency '
                    'fund.',
        ]
      : [
          'An emergency fund is money kept only for surprises, like getting '
              'sick or losing income. A common guide is 3 to 6 months of your '
              'basic expenses.',
          enough
              ? 'Based on the $last30 you spent in the last 30 days, 3 months '
                    'is about $three and 6 months about $six. Needs alone may '
                    'be less. Start with 1 month; even ₱50 a day adds up to '
                    'about ₱1,500 a month.'
              : 'Record your expenses for a few weeks and I can work out how '
                    'much yours should be.',
          fund != null
              ? 'Your ${fund.name} goal has ${formatPeso(fund.savedAmount)} so '
                    'far.'
              : 'You can start one in Goals and choose Emergency fund.',
        ];
  return ChatReply(parts.join('\n\n'), filipino: fil);
}

/// "Is my budget enough?": the money free in the wallets against the bills
/// still to pay this month, then what that leaves a day.
ChatReply _budgetEnough(FinanceSnapshot records, bool fil) {
  if (records.wallets.isEmpty) return _noWallets(fil);
  final s = records.safeToSpend;
  final free = availableBalance(records.wallets, records.goals);
  final billsDue = math.max(0.0, s.billsDue);
  final have = formatPeso(free);
  final bills = formatPeso(billsDue);

  if (free < billsDue) {
    final short = formatPeso(billsDue - free);
    return ChatReply(
      fil
          ? 'Kulang ka. May $have kang available, pero $bills pa ang bills na '
                'babayaran ngayong buwan, kaya kulang ka ng $short. Unahin ang '
                'mga bill na pinakamalapit na due at ipagpaliban muna ang '
                'hindi pa kailangan.'
          : "You're short. You have $have available, but $bills in bills "
                'still to pay this month, so you are short by $short. Pay the '
                'bills due soonest first and hold off on anything that can '
                'wait.',
      filipino: fil,
    );
  }

  final daily = _down(s.dailyLimit);
  final until = formatMonthDay(_lastDay(records));
  final covered = billsDue > 0
      ? (fil
            ? 'Sapat ang pera mo. May $have kang available, sapat para sa '
                  '$bills na bills na babayaran pa ngayong buwan.'
            : "You're covered. You have $have available, enough for the "
                  '$bills in bills still to pay this month.')
      : (fil
            ? 'Sapat ang pera mo. Wala ka nang bills na babayaran ngayong '
                  'buwan, at may $have kang available.'
            : "You're covered. No bills are left to pay this month, and you "
                  'have $have available.');
  final lasting = daily >= 1
      ? (fil
            ? 'Para tumagal ang natitira hanggang $until, gumastos lang ng mga '
                  '${formatPeso(daily)} kada araw.'
            : 'To make the rest last until $until, keep to about '
                  '${formatPeso(daily)} a day.')
      : (fil
            ? 'Kinukuha ng bills ang lahat, kaya ipagpaliban muna ang hindi pa '
                  'kailangan.'
            : 'The bills take all of it, so hold off on anything that can '
                  'wait.');
  return ChatReply('$covered $lasting', filipino: fil);
}

bool _asksSpendingComparison(String text) {
  final asksToCompare = _has(text, [
    'compare',
    'compared',
    'comparison',
    'pattern',
    'patterns',
    'trend',
    'trends',
    'change',
    'changed',
    'increased',
    'decreased',
    'kumpara',
    'ikumpara',
    'paghambingin',
  ]);
  final mentionsSpending =
      _has(text, ['spending', 'spend', 'expense', 'expenses', 'gastos']) ||
      _hasRoot(text, ['gastos', 'ginastos', 'gumastos']);
  return asksToCompare && mentionsSpending;
}

ChatReply _spendingPatternComparison(
  FinanceSnapshot records,
  String question,
  bool fil,
) {
  final normalized = question.toLowerCase();
  final periods = <int>[];
  if (RegExp(r'\b(days?|daily|araw)\b').hasMatch(normalized)) periods.add(3);
  if (RegExp(r'\b(weeks?|weekly|linggo|lingguhan)\b').hasMatch(normalized)) {
    periods.add(7);
  }
  if (RegExp(r'\b(months?|monthly|buwan|buwanan)\b').hasMatch(normalized)) {
    periods.addAll([30, 90]);
  }
  final selectedPeriods = periods.isEmpty
      ? const [3, 7, 30, 90]
      : periods.toSet();

  final lines = <String>[];
  for (final days in selectedPeriods) {
    final comparison = compareSpendingPeriods(
      records.transactions,
      now: records.now,
      days: days,
    );
    final recent = comparison.recent;
    final previous = comparison.previous;
    final windowLabel = switch (days) {
      3 => fil ? 'nakaraang tatlong araw' : 'the last three days',
      7 => fil ? 'nakaraang linggo' : 'the last week',
      90 => fil ? 'nakaraang tatlong buwan' : 'the last three months',
      _ => fil ? 'nakaraang tatlumpung araw' : 'the last thirty days',
    };
    final priorLabel = switch (days) {
      3 => fil ? 'tatlong araw bago noon' : 'the three days before that',
      7 => fil ? 'linggo bago noon' : 'the week before that',
      90 => fil ? 'tatlong buwan bago noon' : 'the three months before that',
      _ => fil ? 'tatlumpung araw bago noon' : 'the thirty days before that',
    };

    if (recent.expenseCount == 0 || previous.expenseCount == 0) {
      final recordedPeriod = recent.expenseCount > 0 ? windowLabel : priorLabel;
      final recorded = formatPeso(
        (recent.expenseCount > 0 ? recent : previous).amount,
      );
      final none = recent.expenseCount == 0 && previous.expenseCount == 0;
      lines.add(
        fil
            ? none
                  ? 'Kulang ang naitalang gastos para ikumpara ang '
                        '$windowLabel sa $priorLabel. Hindi ibig sabihin ng '
                        'walang tala na walang gastos.'
                  : 'May $recorded na naitalang gastos sa $recordedPeriod, '
                        'pero walang naitalang gastos sa katapat na panahon. '
                        'Hindi ko masabi kung nagbago ang gastos mo dahil baka '
                        'kulang ang records mo.'
            : none
            ? 'I do not have enough recorded expenses to compare $windowLabel '
                  'with $priorLabel. Missing records do not mean no spending '
                  'happened.'
            : 'I found $recorded in recorded expenses '
                  'for $recordedPeriod, but no recorded expenses for the '
                  'matching period. I cannot tell whether your spending '
                  'changed because your records may be incomplete.',
      );
      continue;
    }

    final higher = recent.amount > previous.amount;
    final lower = recent.amount < previous.amount;
    final recentCategory = _topRecordedCategory(recent)?.key;
    final previousCategory = _topRecordedCategory(previous)?.key;
    final now = formatPeso(recent.amount);
    final before = formatPeso(previous.amount);
    lines.add(
      fil
          ? 'Nakapagtala ka ng $now na gastos sa $windowLabel at $before sa '
                '$priorLabel. ${higher
                    ? 'Mas mataas'
                    : lower
                    ? 'Mas mababa'
                    : 'Halos pareho'} ang naitalang gastos. '
                '${recentCategory == null ? '' : 'Kamakailan, karamihan ay sa $recentCategory.'} '
                '${previousCategory == null ? '' : 'Noong naunang panahon, karamihan ay sa $previousCategory.'}'
          : 'You recorded $now in expenses for $windowLabel '
                'and $before for $priorLabel. Recorded spending '
                'was ${higher
                    ? 'higher'
                    : lower
                    ? 'lower'
                    : 'about the same'}. '
                '${recentCategory == null ? '' : 'Most spending was $recentCategory recently.'} '
                '${previousCategory == null ? '' : 'In the earlier period, it was mostly $previousCategory.'}',
    );
  }

  lines.add(
    fil
        ? 'Ang mga paghahambing na ito ay gumagamit lang ng gastos na naitala '
              'sa FinAssist, kaya maaaring magbago ang larawan kung may kulang '
              'na tala.'
        : 'These comparisons use only expenses recorded in FinAssist, so '
              'missing entries may change the picture.',
  );
  return ChatReply(lines.join('\n\n'), filipino: fil);
}

MapEntry<String, double>? _topRecordedCategory(SpendingPeriodTotals totals) {
  if (totals.categoryTotals.isEmpty) return null;
  final categories = totals.categoryTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return categories.first;
}

ChatReply _noWallets(bool fil) => ChatReply(
  fil
      ? 'Idagdag muna ang mga wallet mo, kasama ang perang hawak mo ngayon, '
            'para makita ko kung magkano ang pwede mong gamitin.'
      : 'Add your wallets first, with the money you have now, so I can see '
            'what you have to work with.',
  filipino: fil,
);

// ---------------------------------------------------------- "Can I buy it?"

final _buyTrigger = RegExp(
  r'\b(can i (buy|afford|get)|could i (buy|afford)|should i buy|'
  r'is it ok(ay)? (to|if i) buy|'
  r'kaya ko (bang|ba) (bilhin|bumili ng|bumili|mabili)|'
  r'kaya (bang|ba) (bilhin|bumili ng|bumili)|'
  r'mabibili ko (ba|kaya)|'
  r'pwede (ko )?(bang|ba) (bilhin|bumili ng|bumili)|'
  r'afford)\b',
);

/// Brands or models to offer for common things, names only. The price is
/// always the user's to give.
const _brandChoices = {
  'airpods': ['AirPods', 'AirPods Pro', 'AirPods Max'],
  'phone': ['Samsung', 'iPhone', 'Xiaomi', 'realme', 'OPPO', 'vivo'],
  'cellphone': ['Samsung', 'iPhone', 'Xiaomi', 'realme', 'OPPO', 'vivo'],
  'smartphone': ['Samsung', 'iPhone', 'Xiaomi', 'realme', 'OPPO', 'vivo'],
  'cp': ['Samsung', 'iPhone', 'Xiaomi', 'realme', 'OPPO', 'vivo'],
  'laptop': ['Acer', 'ASUS', 'Lenovo', 'HP', 'MacBook'],
  'tablet': ['iPad', 'Samsung', 'Xiaomi'],
  'earphones': ['JBL', 'Sony', 'Soundcore', 'Xiaomi'],
  'earbuds': ['JBL', 'Sony', 'Soundcore', 'Xiaomi'],
  'headphones': ['JBL', 'Sony', 'Soundcore'],
  'shoes': ['Nike', 'Adidas', 'New Balance'],
  'sapatos': ['Nike', 'Adidas', 'New Balance'],
  'sneakers': ['Nike', 'Adidas', 'New Balance'],
  'smartwatch': ['Apple Watch', 'Samsung', 'Huawei', 'Xiaomi'],
  'watch': ['Apple Watch', 'Samsung', 'Huawei', 'Xiaomi'],
  'console': ['PlayStation', 'Nintendo Switch', 'Xbox'],
};

ChatReply _startPurchase(
  String message,
  int triggerEnd,
  FinanceSnapshot? records,
  PriceReferences? prices,
  bool fil,
) {
  if (records == null) {
    return ChatReply(
      fil
          ? 'Kinukuha ko pa ang records mo. Magtanong ulit maya-maya.'
          : "I'm still loading your records. Ask me again in a moment.",
      filipino: fil,
    );
  }
  final (deadline, label, labelFilipino) = _deadlineIn(
    message.toLowerCase(),
    records,
  );
  // A house's size or gold's weight isn't its price: "120 sqm", "18k".
  final words = _withoutMeasures(
    _withoutAskingWords(message.substring(triggerEnd)),
  );
  final price = _priceIn(words);
  final question = PurchaseQuestion(
    deadline: deadline,
    deadlineLabel: label,
    deadlineLabelFilipino: labelFilipino,
    item: _itemIn(words, price),
    price: price?.value,
    details: message,
  );
  return _nextPurchaseStep(question, records, prices, fil);
}

/// Handles a reply to a follow-up question, or null when the message is a
/// new question instead.
ChatReply? _continuePurchase(
  String message,
  String text,
  PurchaseQuestion pending,
  FinanceSnapshot? records,
  PriceReferences? prices,
  bool fil,
) {
  if (records == null) return null;
  // A new "Can I buy…" or another kind of question starts over.
  if (_buyTrigger.hasMatch(message.toLowerCase()) ||
      _otherBuyTrigger.hasMatch(message.toLowerCase())) {
    return null;
  }
  pending = pending.copyWith(details: '${pending.details}\n$message');
  final amount = findAmount(message)?.value;
  final tapped = message.trim();

  switch (pending.waitingFor) {
    case PurchaseStep.item:
      final price = _priceIn(message);
      if (_intentOf(text) != null && price == null) return null;
      final item = _itemIn(message, price);
      if (item.isEmpty) return null;
      return _nextPurchaseStep(
        pending.copyWith(item: item, price: price?.value, clearWaiting: true),
        records,
        prices,
        fil,
      );

    case PurchaseStep.brand:
      // "iPhone 16" answers which one; "₱8,990" or "8990" is the price.
      final price = _priceIn(message);
      if (price != null) {
        return _nextPurchaseStep(
          pending.copyWith(
            brand: anyBrand,
            price: price.value,
            clearWaiting: true,
          ),
          records,
          prices,
          fil,
        );
      }
      if (_has(text, _noPreference) ||
          tapped == anyBrand ||
          tapped == anyBrandFilipino) {
        return _nextPurchaseStep(
          pending.copyWith(brand: anyBrand, clearWaiting: true),
          records,
          prices,
          fil,
        );
      }
      if (_intentOf(text) != null) return null;
      return _nextPurchaseStep(
        pending.copyWith(brand: tapped, clearWaiting: true),
        records,
        prices,
        fil,
      );

    case PurchaseStep.price:
      // A house's size or gold's weight, given instead of a price.
      final measured = _measuredPrice(message, pending, records, prices, fil);
      if (measured != null) return measured;
      if (amount != null) {
        return _purchaseAnswer(
          pending.copyWith(price: amount),
          records,
          prices,
          fil,
        );
      }
      if (_has(text, _unsure) ||
          tapped == notSure ||
          tapped == notSureFilipino) {
        return _purchaseAnswer(pending, records, prices, fil);
      }
      if (_intentOf(text) != null) return null;
      if (pending.asked >= 2) {
        return _purchaseAnswer(pending, records, prices, fil);
      }
      return ChatReply(
        fil
            ? 'I-type lang ang presyo, halimbawa ₱8,990, o pindutin ang '
                  '"$notSureFilipino".'
            : 'Just type the price, for example ₱8,990, or tap "$notSure".',
        choices: [fil ? notSureFilipino : notSure],
        pending: pending.copyWith(asked: pending.asked + 1),
        filipino: fil,
      );

    case null:
      return null;
  }
}

const _noPreference = [
  'any',
  'any brand',
  'kahit ano',
  'kahit anong brand',
  'kahit anong',
  'kahit alin',
  'wala',
  'none',
  'no preference',
  'anything',
];

const _unsure = [
  'not sure',
  'no idea',
  'di ko alam',
  'hindi ko alam',
  'ewan',
  'dunno',
];

/// Asks what is still missing, at most twice, then answers.
ChatReply _nextPurchaseStep(
  PurchaseQuestion q,
  FinanceSnapshot records,
  PriceReferences? prices,
  bool fil,
) {
  if (q.item.isEmpty) {
    return ChatReply(
      fil ? 'Ano ang gusto mong bilhin?' : 'What would you like to buy?',
      pending: q.copyWith(waitingFor: PurchaseStep.item, asked: q.asked + 1),
      filipino: fil,
    );
  }
  if (q.price != null) return _purchaseAnswer(q, records, prices, fil);

  // Houses, lots and gold have their own questions: a size or a weight
  // can stand in for the price.
  final big = _askBigPrice(q, records, prices, fil);
  if (big != null) return big;

  final brands = _brandsFor(q.item);
  if (q.brand == null && brands != null) {
    final isAirPods = _plain(q.item).contains('airpods');
    return ChatReply(
      fil
          ? isAirPods
                ? 'Aling AirPods ang tinitingnan mo? Pwede mo ring i-type na '
                      'lang ang presyo.'
                : 'May brand ka bang naiisip para sa ${q.item}? Pwede mo ring '
                      'i-type na lang ang presyo.'
          : isAirPods
          ? 'Which AirPods are you looking at? You can also just type the '
                'price.'
          : 'Do you have a brand in mind for the ${q.item}? You can also '
                'just type the price.',
      choices: [...brands, fil ? anyBrandFilipino : anyBrand],
      pending: q.copyWith(waitingFor: PurchaseStep.brand, asked: q.asked + 1),
      filipino: fil,
    );
  }
  if (q.brand == anyBrand) return _purchaseAnswer(q, records, prices, fil);

  return ChatReply(
    fil
        ? 'Mga magkano ang ${q.thing}? I-type ang presyo, halimbawa ₱8,990.'
        : 'About how much is the ${q.thing}? Type the price, for example '
              '₱8,990.',
    choices: [fil ? notSureFilipino : notSure],
    pending: q.copyWith(waitingFor: PurchaseStep.price, asked: q.asked + 1),
    filipino: fil,
  );
}

/// Extracts only the product name for a live price lookup. Financial records
/// and the rest of the user's message are deliberately excluded.
String? productPriceLookupQuery(String message) {
  if (RegExp(
    r'\b(?:save|saving|savings|set aside|put aside|mag[- ]?ipon|'
    r'makaipon|dapat kong|para makabili|worth|income|salary|expense|'
    r'expenses|spend|spending|budget|wallet|bills?|utang|debt|'
    r'cash flow|financial|finances?)\b',
    caseSensitive: false,
  ).hasMatch(message)) {
    return null;
  }
  final priceRequest = RegExp(
    r'\bhow much (?:is|are)\s+(?:the\s+)?(.+?)(?=[?.!,]|$)|'
    r'\bhow much (?:does|do)\s+(.+?)\s+cost\b|'
    r'\b(?:current|latest|retail)?\s*price\s+(?:of|for)\s+(.+?)(?=[?.!,]|$)|'
    r'\bmagkano\s+(?:ang\s+)?(.+?)(?=[?.!,]|$)',
    caseSensitive: false,
  ).firstMatch(message.trim());

  String? product;
  if (priceRequest != null) {
    product = [
      priceRequest.group(1),
      priceRequest.group(2),
      priceRequest.group(3),
      priceRequest.group(4),
    ].whereType<String>().firstOrNull;
  } else {
    final purchaseRequest = _buyTrigger.firstMatch(message.toLowerCase());
    if (purchaseRequest == null) return null;
    final itemText = message.substring(purchaseRequest.end);
    if (_priceIn(itemText) != null) return null;
    if (RegExp(
      r'\b(?:afford|salary|income|budget|save|saving|savings|'
      r'ipon|kaya\s+(?:ko|kong|mong)|mabili\s+(?:lahat|ang))\b',
      caseSensitive: false,
    ).hasMatch(message)) {
      return null;
    }
    product = _itemIn(itemText, null);
    // Houses, lots and gold are worked out from the prices the app keeps.
    if (_bigKindOf(product) != null) return null;
  }

  if (product == null) return null;
  product = product
      .replaceFirst(
        RegExp(
          r'\s+(?:in the philippines|in philippines|sa philippines|near me|'
          r'for me|today)$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[^\p{L}\p{N} &+()._-]', unicode: true), '')
      .trim();
  if (RegExp(
    r'\b(?:save|saving|savings|set aside|put aside|mag[- ]?ipon|'
    r'makaipon|dapat kong|para makabili|income|salary|expense|expenses|'
    r'spend|spending|budget|wallet|bills?|utang|debt|cash flow|'
    r'financial|finances?|this week|this month|ko)\b',
    caseSensitive: false,
  ).hasMatch(product)) {
    return null;
  }
  if (product.isEmpty || product.length > 100) return null;
  return product;
}

/// Choices to offer for [item], or null for anything else, or when a brand
/// is already named in it.
List<String>? _brandsFor(String item) {
  final words = ' ${_plain(item)} ';
  for (final entry in _brandChoices.entries) {
    if (!words.contains(' ${entry.key} ')) continue;
    final named = entry.value.any(
      (brand) => entry.key != 'airpods' && words.contains(' ${_plain(brand)} '),
    );
    if (named) return null;
    // "AirPods Pro" already says which.
    if (entry.key == 'airpods' &&
        (words.contains(' pro ') || words.contains(' max '))) {
      return null;
    }
    return entry.value;
  }
  return null;
}

/// The answer, from the user's money, bills, savings and usual spending up
/// to the deadline.
ChatReply _purchaseAnswer(
  PurchaseQuestion q,
  FinanceSnapshot records,
  PriceReferences? prices,
  bool fil,
) {
  if (records.wallets.isEmpty) return _noWallets(fil);

  final kind = _bigKindOf(q.item);
  if (q.price != null && (kind == _BigKind.home || kind == _BigKind.land)) {
    return _homeAnswer(q, records, prices, fil);
  }

  final today = records.today;
  final monthEnd = records.period.end;
  final pace = savingPaceOf(records);
  // Past this month, what is usually left of the user's income each month
  // counts too, from their own records. Without enough records, only what
  // is on hand now is counted.
  final paced = pace != null && q.deadline.isAfter(monthEnd);
  final until = paced ? monthEnd : q.deadline;
  final days = math.max(1, until.difference(today).inDays);
  final (spare: spareThen, :bills, :daily) = _spareBy(until, records);
  final monthsAfter = paced ? _monthsBetween(monthEnd, q.deadline) : 0;
  final spare = paced
      ? _down(spareThen + pace.perMonth * monthsAfter)
      : spareThen;
  final label = fil && q.deadlineLabelFilipino.isNotEmpty
      ? q.deadlineLabelFilipino
      : q.deadlineLabel;

  final notes = fil
      ? [
          paced
              ? _paceNote(pace, fil, forDeadline: true)
              : 'Ang tantiyang ito ay base sa kasalukuyang balance at naitalang '
                    'gastos; hindi kasama ang darating na kita.',
          if (daily <= 0)
            'Wala ka pang naitalang araw-araw na gastos, kaya hindi ko pa '
                'ito naisama.',
          if (!paced &&
              q.deadline.isAfter(DateTime(today.year, today.month + 2)))
            'Hindi pa kasama ang bills na lampas isang buwan pa.',
        ]
      : [
          paced
              ? _paceNote(pace, fil, forDeadline: true)
              : 'This estimate uses current balances and recorded spending; it '
                    'does not include future income.',
          if (daily <= 0)
            "You haven't recorded day-to-day spending yet, so I couldn't "
                'allow for it.',
          if (!paced &&
              q.deadline.isAfter(DateTime(today.year, today.month + 2)))
            "Bills more than a month away aren't counted yet.",
        ];
  // What the spare money is worked out after, naming only what there is:
  // no "bills (₱0)" for someone with no bills.
  final setAside = records.goalSavingsInSpendingWallets;
  final coveredParts = [
    if (bills > 0) 'bills (${formatPeso(bills)})',
    if (setAside > 0)
      fil
          ? 'perang nakatabi (${formatPeso(setAside)})'
          : 'money set aside (${formatPeso(setAside)})',
    if (daily > 0)
      fil
          ? 'karaniwang ${formatPeso(_down(daily))} mo kada araw'
          : 'your usual ${formatPeso(_down(daily))} a day',
  ];
  final covers = coveredParts.length <= 1
      ? coveredParts.firstOrNull
      : '${coveredParts.take(coveredParts.length - 1).join(', ')} '
            '${fil ? 'at' : 'and'} ${coveredParts.last}';
  final after = covers == null ? 'You' : 'After $covers, you';
  // "Pagkatapos ng bills (₱2,100), may…" or just "May…".
  final afterFil = covers == null ? 'May' : 'Pagkatapos ng $covers, may';

  // No price: say so plainly, then give the most that could go to it, so a
  // car is never made to sound like it costs a few thousand pesos. The price
  // can still be typed next.
  final price = q.price;
  if (price == null) {
    final when = _capital(label);
    final String first;
    if (fil) {
      final what = q.thing.isEmpty ? 'ito' : q.thing;
      first = spare <= 0
          ? 'Wala pang presyo, kaya hindi ko pa ito masuri. $when, wala nang '
                'matitira${covers == null ? '' : ' pagkatapos ng $covers'}. '
                'Sabihin mo ang presyo at kukuwentahin ko kung gaano katagal '
                'mag-iipon para rito.'
          : 'Wala pang presyo, kaya hindi ko pa ito masuri. $when, ang '
                'pinakamalaking pwede mong gastusin sa $what ay mga '
                '${formatPeso(spare)}'
                '${covers == null ? '' : ', pagkatapos ng $covers'}. Sabihin '
                'mo ang presyo at sasabihin ko kung kasya, o gaano katagal '
                'mag-iipon para rito.';
    } else {
      final what = q.thing.isEmpty ? 'it' : 'the ${q.thing}';
      first = spare <= 0
          ? "Without a price, I can't check it yet. $when, there's nothing "
                'spare${covers == null ? '' : ' once $covers are covered'}. '
                "Tell me the price and I'll work out how long to save for it."
          : "Without a price, I can't check it yet. $when, the most you can "
                'spend on $what is about ${formatPeso(spare)}'
                '${covers == null ? '' : ', after $covers'}. Tell me the '
                "price and I'll tell you if it fits, or how long to save for "
                'it.';
    }
    return ChatReply(
      [first, ...notes].join('\n\n'),
      pending: q.copyWith(waitingFor: PurchaseStep.price),
      filipino: fil,
    );
  }

  // Gold: how the price compares with what its gold is worth today.
  final gold = kind == _BigKind.gold ? _goldNote(q, price, prices, fil) : null;
  ChatReply reply(
    List<String> parts, {
    GoalOffer? goal,
    List<ReferenceLink> sources = const [],
  }) {
    final answer = ChatReply(
      [parts.first, ?gold?.text, ...parts.skip(1)].join('\n\n'),
      goal: goal,
      filipino: fil,
      sources: [...?gold?.links, ...sources],
    );
    // Figures from public prices are worked out here, not by Gemini.
    return gold == null ? answer : answer.protected();
  }

  final cost = formatPeso(price);
  if (spare >= price) {
    final left = formatPeso(spare - price);
    return reply([
      fil
          ? '${q.thing.isEmpty ? 'Oo, kaya mo itong bilhin' : 'Oo, kaya mong bilhin ang ${q.thing}'} '
                '($cost) $label. $afterFil matitira ka pang mga $left.'
          : 'Yes, you can buy ${q.thing.isEmpty ? 'it' : 'the ${q.thing}'} '
                '($cost) $label. $after would still have about $left '
                'spare.',
      ...notes,
    ]);
  }

  final short = price - spare;
  final cutPerDay = _up(short / days);
  if (!paced && daily > 0 && days >= 3 && cutPerDay <= daily * 0.5) {
    final aim = formatPeso(_down(daily - cutPerDay));
    final usualDay = formatPeso(_down(daily));
    return reply([
      fil
          ? 'Oo, kung babawasan mo nang kaunti ang gastos. Kulang ka ng mga '
                '${formatPeso(short)} $label, kaya subukang gumastos lang ng '
                'mga $aim kada araw sa halip na ang karaniwang $usualDay mo.'
          : "Yes, if you spend a little less. You're about "
                '${formatPeso(short)} short $label, so aim for about $aim a '
                'day instead of your usual $usualDay.',
      ?_habit(records, fil),
      ...notes,
    ]);
  }

  // With nothing spare, "₱12,000 short of ₱10,000" would read wrong.
  final notYet = fil
      ? spare > 0
            ? 'Hindi pa ito kasya $label. $afterFil matitira kang mga '
                  '${formatPeso(spare)}, kulang pa ng ${formatPeso(short)} '
                  'para sa $cost.'
            : 'Hindi pa ito kasya $label. '
                  '${covers == null ? 'Walang' : 'Pagkatapos ng $covers, walang'} '
                  'matitira, kaya kailangan pang ipunin ang buong $cost.'
      : spare > 0
      ? "It doesn't fit $label yet. $after would have about "
            '${formatPeso(spare)} spare, ${formatPeso(short)} short of '
            '$cost.'
      : "It doesn't fit $label yet. "
            '${covers == null ? 'Nothing' : 'After $covers, nothing'} would '
            'be spare, so all $cost still needs saving.';
  final name = q.thing.isEmpty
      ? (fil ? 'Gustong bilhin' : 'Something I want')
      : _goalName(q.thing);

  // How long, at the pace the user's own records show.
  if (pace != null) {
    final saved = math.max(0.0, _spareBy(monthEnd, records).spare);
    final plan = _savingPlan(
      price: price,
      saved: saved,
      pace: pace,
      records: records,
      prices: prices,
      fil: fil,
    );
    return reply(
      [
        notYet,
        ...plan.lines,
        ..._waysToGetThere(
          price: price,
          saved: saved,
          pace: pace,
          months: plan.months,
          records: records,
          prices: prices,
          fil: fil,
        ),
        // The first note says future income isn't counted, true of the
        // month-end figure but not of the months after; the pace note says
        // what those count instead.
        ...paced ? notes : notes.skip(1),
        if (!paced) _paceNote(pace, fil),
      ],
      goal: plan.ready == null
          ? null
          : GoalOffer(name: name, target: price, date: plan.ready!),
      sources: plan.sources,
    );
  }

  // No saving habit to go on yet: a weekly amount the user's own spending
  // can support.
  final toSave = price - math.max(0, spare);
  final weeklySpending = daily * 7;
  var weeks = 52;
  for (final candidate in const [4, 8, 12, 16, 26, 52]) {
    final perWeek = _upTo50(toSave / candidate);
    if (weeklySpending <= 0 || perWeek <= weeklySpending * 0.3) {
      weeks = candidate;
      break;
    }
  }
  final perWeek = formatPeso(_upTo50(toSave / weeks));
  final ready = today.add(Duration(days: weeks * 7));
  final readyOn = formatShortDate(ready);

  return reply([
    notYet,
    fil
        ? 'Kung mag-iipon ka ng $perWeek kada linggo, aabot ka rito sa '
              '$readyOn.'
        : 'Saving $perWeek a week gets you there by $readyOn.',
    ...notes,
  ], goal: GoalOffer(name: name, target: price, date: ready));
}

/// What would be left by [until]: the wallets, less the bills due before
/// then, money set aside for goals, and the usual day-to-day spending until
/// then. Today's spending is already out of the wallets; only the rest of
/// today is still to come.
({double spare, double bills, double daily}) _spareBy(
  DateTime until,
  FinanceSnapshot records,
) {
  final days = math.max(1, until.difference(records.today).inDays);
  final bills = billsDueBefore(records.bills, until);
  final available =
      records.walletBalance - bills - records.goalSavingsInSpendingWallets;
  final daily = records.usualDailySpending;
  final restOfToday = math.max(0.0, daily - records.spentToday);
  final usual = daily * (days - 1) + restOfToday;
  return (spare: _down(available - usual), bills: bills, daily: daily);
}

/// Where most day-to-day money goes, from the last 30 days.
String? _habit(FinanceSnapshot records, bool fil) {
  final monthAgo = records.today.subtract(const Duration(days: 30));
  final recent = records.transactions.where(
    (t) => !t.isBillPayment && !t.date.isBefore(monthAgo),
  );
  final byCategory = spendingByCategory(recent);
  if (byCategory.isEmpty) return null;
  final top = byCategory.first;
  final perDay = formatPeso(_down(top.value / 30));
  return fil
      ? 'Karamihan ng araw-araw mong pera ay napupunta sa ${top.key}, mga '
            '$perDay kada araw, kaya iyon ang pinakamadaling bawasan.'
      : 'Most of your day-to-day money goes to ${top.key}, about $perDay a '
            'day, so that is the easiest place to trim.';
}

const _monthNames = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// By when it would be bought. Unless the question says, before month end.
(DateTime, String, String) _deadlineIn(String lower, FinanceSnapshot records) {
  final text = ' ${_plain(lower)} ';
  final today = records.today;

  if (_has(text, ['today']) || text.contains(' ngayon ')) {
    return (today.add(const Duration(days: 1)), 'today', 'ngayong araw');
  }
  if (_has(text, ['this week', 'ngayong linggo'])) {
    final monday = today.add(Duration(days: 8 - today.weekday));
    return (monday, 'this week', 'ngayong linggo');
  }
  if (_has(text, ['next month', 'sa susunod na buwan'])) {
    return (
      DateTime(today.year, today.month + 2),
      'by the end of next month',
      'bago matapos ang susunod na buwan',
    );
  }
  if (_has(text, ['this month', 'ngayong buwan'])) {
    return (
      DateTime(today.year, today.month + 1),
      'this month',
      'ngayong buwan',
    );
  }
  final span = RegExp(
    r'\b(?:in|within|after|sa loob ng) (?:the next )?(\d{1,2}|a|isang) '
    r'(?:na )?(months?|years?|buwan|taon)\b',
  ).firstMatch(text);
  if (span != null) {
    final count = int.tryParse(span[1]!) ?? 1;
    final years = span[2]!.startsWith('year') || span[2] == 'taon';
    if (count > 0) {
      final unit = years
          ? (count == 1 ? 'year' : 'years')
          : (count == 1 ? 'month' : 'months');
      return (
        DateTime(today.year, today.month + count * (years ? 12 : 1), today.day),
        'within $count $unit',
        'sa loob ng $count ${years ? 'taon' : 'buwan'}',
      );
    }
  }
  for (final (i, name) in _monthNames.indexed) {
    if (_has(text, [
      'by $name',
      'by ${name.substring(0, 3)}',
      'bago mag $name',
    ])) {
      var year = today.year;
      if (i + 1 < today.month) year++;
      final label = name[0].toUpperCase() + name.substring(1);
      return (
        DateTime(year, i + 2),
        'by the end of $label',
        'bago matapos ang $label',
      );
    }
  }
  final monthEnd = records.period.end;
  final lastDay = formatMonthDay(_lastDay(records));
  return (
    monthEnd,
    'by month end ($lastDay)',
    'bago matapos ang buwan ($lastDay)',
  );
}

final _timeWords = RegExp(
  r'\b(this|next) (month|week)\b|\bngayong (buwan|linggo)\b|'
  r'\bsa susunod na (buwan|linggo)\b|\b(before|bago) (my next )?'
  r'(payday|sahod|sweldo)\b|\bby (the end of )?[a-z]+\b|\btoday\b|'
  r'\bngayon\b|\b(in|within|after|sa loob ng) (the next )?(\d{1,2}|a|isang) '
  r'(na )?(months?|years?|buwan|taon)\b',
  caseSensitive: false,
);

const _itemFillers = {
  'a',
  'an',
  'the',
  'some',
  'yung',
  'ang',
  'ng',
  'na',
  'ba',
  'po',
  'ko',
  'kaya',
  'for',
  'worth',
  'at',
  'pa',
  'now',
  'it',
  'this',
  'that',
  'yan',
  'ito',
  'iyan',
};

final _millions = RegExp(
  r'(?:₱\s?)?(?<![a-z\d.,])(\d+(?:\.\d+)?)(?:m|\s?(?:mil|million|milyon))'
  r'(?![a-z\d])',
  caseSensitive: false,
);

/// The price in "Can I buy…" words. A plain number under ₱100 is more
/// likely part of a name, as in "iPhone 16", so it only counts when said as
/// money, as in "₱50" or "50 pesos".
({double value, int start, int end, bool isMoney})? _priceIn(String words) {
  // "2M" or "2.5 million" for a house. Only prices asked about here are
  // read this way: in an expense, "5m" is more likely a length.
  final millions = _millions.firstMatch(words);
  if (millions != null) {
    return (
      value: double.parse(millions[1]!) * 1000000,
      start: millions.start,
      end: millions.end,
      isMoney: true,
    );
  }
  final amount = findAmount(words);
  if (amount == null) return null;
  if (!amount.isMoney && amount.value < 100) return null;
  return amount;
}

/// What is being bought, from the words after "Can I buy…": without the
/// [price], the time, or filler words.
String _itemIn(
  String words,
  ({double value, int start, int end, bool isMoney})? price,
) {
  var rest = words;
  if (price != null) rest = rest.replaceRange(price.start, price.end, ' ');
  rest = rest.replaceAll(_timeWords, ' ');

  final parts = rest
      .split(RegExp(r'\s+'))
      .map((w) => w.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), ''))
      .where((w) => w.isNotEmpty)
      .toList();
  while (parts.isNotEmpty && _itemFillers.contains(parts.first.toLowerCase())) {
    parts.removeAt(0);
  }
  while (parts.isNotEmpty && _itemFillers.contains(parts.last.toLowerCase())) {
    parts.removeLast();
  }
  return parts.join(' ');
}

// ----------------------------------------------------------------- helpers

/// The period a question is about, and how it reads. This month unless the
/// question says otherwise.
(ReportPeriod, String) _periodIn(String text, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final month = ReportPeriod.monthOf(now);
  final week = ReportPeriod.weekOf(now);

  if (_has(text, ['last month', 'nakaraang buwan', 'noong isang buwan'])) {
    return (month.previous(ReportRange.month), 'last month');
  }
  if (_has(text, ['this month', 'ngayong buwan', 'month', 'buwan'])) {
    return (month, 'this month');
  }
  if (_has(text, ['last week', 'nakaraang linggo', 'noong isang linggo'])) {
    return (week.previous(ReportRange.week), 'last week');
  }
  if (_has(text, ['this week', 'ngayong linggo', 'week', 'linggo'])) {
    return (week, 'this week');
  }
  if (_has(text, ['yesterday', 'kahapon'])) {
    final day = today.subtract(const Duration(days: 1));
    return (ReportPeriod(day, day), 'yesterday');
  }
  if (_has(text, ['today', 'ngayon', 'ngayong araw'])) {
    return (ReportPeriod(today, today), 'today');
  }
  return (month, 'this month');
}

/// A category named in a question, by its name or an everyday word for it.
String? _categoryIn(String text) {
  const words = {
    'Food': ['food', 'foods', 'pagkain', 'kain'],
    'Transportation': [
      'transportation',
      'transport',
      'transpo',
      'pamasahe',
      'commute',
      'fare',
    ],
    'Shopping': ['shopping', 'damit', 'clothes'],
    'Bills': ['bills', 'bill', 'bayarin'],
    'Entertainment': ['entertainment', 'libangan', 'gimik'],
    'Healthcare': ['healthcare', 'health', 'medical', 'gamot', 'medicine'],
    'Education': ['education', 'school', 'tuition', 'eskwela'],
    'Pets': ['pets', 'pet', 'alaga'],
    'Others': ['others', 'other'],
  };
  for (final entry in words.entries) {
    if (_has(text, entry.value)) return entry.key;
  }
  return null;
}

String _percent(double part, double whole) =>
    whole <= 0 ? '0%' : '${(part / whole * 100).round()}%';

/// The month's last day. The period ends at the start of the next month,
/// so "through" its end date would name a day too late.
DateTime _lastDay(FinanceSnapshot records) {
  final end = records.period.end;
  return DateTime(end.year, end.month, end.day - 1);
}

/// A period from [_periodIn], said in Filipino when [fil].
String _when(String label, bool fil) => !fil
    ? label
    : switch (label) {
        'last month' => 'noong nakaraang buwan',
        'this month' => 'ngayong buwan',
        'last week' => 'noong nakaraang linggo',
        'this week' => 'ngayong linggo',
        'yesterday' => 'kahapon',
        'today' => 'ngayong araw',
        _ => label,
      };

String _days(int days) => days == 1 ? '1 day' : '$days days';

double _down(double amount) => amount.floorToDouble();

double _up(double amount) => amount.ceilToDouble();

double _upTo50(double amount) => (amount / 50).ceil() * 50.0;

/// A goal's name from what was asked about: capitalised, except a name
/// already spelled with its own capitals, such as "iPhone 16".
String _goalName(String thing) {
  final brandSpelling =
      thing.length > 1 &&
      thing[0] == thing[0].toLowerCase() &&
      thing[1] == thing[1].toUpperCase() &&
      thing[1] != thing[1].toLowerCase();
  return brandSpelling ? thing : _capital(thing);
}

String _capital(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
