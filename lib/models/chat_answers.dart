import 'dart:math' as math;

import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'app_transaction.dart';
import 'bill.dart';
import 'debt.dart';
import 'expense_guess.dart';
import 'finance_snapshot.dart';
import 'goal.dart';
import 'financial_insights.dart';
import 'report.dart';
import 'safe_to_spend.dart';
import 'savings_suggestion.dart';
import 'transaction_filter.dart';
import 'chat_language.dart';
import '../utils/categories.dart';

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

ChatReply _insightsResponse(String question) {
  final language = detectChatLanguage(question) ?? ChatLanguage.english;
  final message = switch (language) {
    ChatLanguage.english =>
      'Yes. I can help explain your recorded spending, compare recent '
          'periods, point out your main expense categories, and suggest '
          'practical ways to save. I will use the records available in '
          'FinAssist, so keeping them up to date helps make the insights more useful.',
    ChatLanguage.tagalog =>
      'Oo. Matutulungan kitang unawain ang mga naitala mong gastos, '
          'ikumpara ang mga nakaraang panahon, makita kung saan napupunta '
          'ang pera, at magbigay ng praktikal na paraan para makatipid. '
          'Gagamitin ko lang ang mga rekord na nasa FinAssist, kaya mas '
          'makakatulong kung regular mong itatala ang kita at gastos.',
    ChatLanguage.taglish =>
      'Oo. I can give you clear insights tungkol sa mga naitala mong gastos, '
          'compare recent periods, tukuyin kung saan napupunta ang pera, at '
          'mag-suggest ng practical ways para makatipid. Ibase ko ito sa '
          'records na nasa FinAssist, kaya mas useful kung updated ang mga '
          'tala mo.',
  };
  return ChatReply(message);
}

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

/// Tapped when the user doesn't know the price.
const notSure = "I'm not sure";

/// A "Can I buy it?" question, worked out over a few messages.
class PurchaseQuestion {
  const PurchaseQuestion({
    required this.deadline,
    required this.deadlineLabel,
    this.item = '',
    this.brand,
    this.price,
    this.waitingFor,
    this.asked = 0,
  });

  /// The day it has to be bought before.
  final DateTime deadline;

  /// How the deadline reads in an answer, such as "before payday (Oct 1)".
  final String deadlineLabel;

  final String item;

  /// The brand or model chosen, or [anyBrand]. Null when not asked.
  final String? brand;
  final double? price;
  final PurchaseStep? waitingFor;

  /// Follow-up questions asked so far, so the assistant never keeps asking.
  final int asked;

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
  }) {
    return PurchaseQuestion(
      deadline: deadline,
      deadlineLabel: deadlineLabel,
      item: item ?? this.item,
      brand: brand ?? this.brand,
      price: price ?? this.price,
      waitingFor: clearWaiting ? null : waitingFor ?? this.waitingFor,
      asked: asked ?? this.asked,
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

  ChatReply protected() => ChatReply(
    text,
    choices: choices,
    goal: goal,
    pending: pending,
    isVerifiedGoalPlan: isVerifiedGoalPlan,
    useLocalAnswer: true,
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

/// Answers [message] from [records], the user's own data, which is null
/// while it is still loading. [pending] is a "Can I buy it?" question still
/// being worked out.
ChatReply answerChat(
  String message, {
  required FinanceSnapshot? records,
  PurchaseQuestion? pending,
  String? contextMessage,
}) {
  final text = ' ${_plain(message)} ';

  final categorizedExpenses = categorizeChatExpenses(message);
  if (categorizedExpenses != null) {
    final lines = categorizedExpenses.map((expense) {
      final category = expense.category;
      return category == null
          ? '${formatPeso(expense.amount)} — ${expense.description}: '
                'category unclear; choose the category in FinAssist'
          : '${formatPeso(expense.amount)} — ${expense.description}: $category';
    });
    return ChatReply(
      'Here is the categorization for each expense:\n${lines.join('\n')}\n\n'
      'Are these categories correct? If yes, tap “Add all expenses”.',
    ).protected();
  }

  // A calculation question interrupts a purchase follow-up instead of
  // being mistaken for an item name or price.
  if (_asksForFormula(text)) return _formula(text, records).protected();

  if (pending != null) {
    final followUp = _continuePurchase(message, text, pending, records);
    if (followUp != null) return followUp;
  }

  final buy = _buyTrigger.firstMatch(message.toLowerCase());
  if (buy != null) return _startPurchase(message, buy.end, records);

  final projection = _savingsProjection(message, records);
  if (projection != null) return projection;

  final targetAnswer = _savingsTargetAnswer(
    message,
    contextMessage: contextMessage,
    records: records,
  );
  if (targetAnswer != null) return targetAnswer;

  final goalPlan = _goalSavingsPlan(message, records);
  if (goalPlan != null) return goalPlan;

  final targetPlan = _targetSavingsPlan(message, records);
  if (targetPlan != null) return targetPlan;

  var intent = _intentOf(text);
  // "Nagbayad na ba si Ana?" names someone the user lent to, with no debt
  // word in it, so the name alone makes it a question about that debt.
  if ((intent == null || intent == _Intent.bills) &&
      records != null &&
      _namedDebts(text, records).isNotEmpty) {
    intent = _Intent.debts;
  }

  if (intent == _Intent.greeting) {
    return const ChatReply(
      "Hi! I'm Fin. I answer from your own records: spending, bills, "
      'savings, and whether you can afford something. What would you like '
      'to know?',
      choices: suggestedQuestions,
    );
  }
  if (intent == _Intent.help) {
    return const ChatReply(
      'I can tell you what you can spend today, how much went where, which '
      'bills are coming up, how your savings and debts stand, and whether '
      "something you want fits your budget. I'm only for money questions.",
      choices: suggestedQuestions,
    );
  }
  if (intent == null) {
    return _looksFinancial(text)
        ? _clarification()
        : const ChatReply(
            'Sorry, I can only help with money questions, like budgeting, '
            'expenses, bills and savings. What would you like to know about '
            'your finances?',
            choices: suggestedQuestions,
          );
  }

  if (records == null) {
    return const ChatReply(
      "I'm still loading your records. Ask me again in a moment.",
      useLocalAnswer: true,
    );
  }

  final reply = switch (intent) {
    _Intent.safeToday => _safeToday(records),
    _Intent.safeTodayComparison => _safeTodayComparison(text, records),
    _Intent.insights => _insightsResponse(text),
    _Intent.savingsPlan => _savingsPlan(records, text),
    _Intent.spent => _spent(text, records),
    _Intent.savingsCapacity => _savingsCapacity(text, records),
    _Intent.topSpending => _topSpending(text, records),
    _Intent.bills => _bills(text, records),
    _Intent.balance => _balance(records),
    _Intent.savings => _savings(records),
    _Intent.debts => _debts(text, records),
    _Intent.income => _income(text, records),
    _Intent.advice => _advice(records, text),
    _Intent.greeting || _Intent.help => throw StateError('answered above'),
  };
  return intent == _Intent.advice || intent == _Intent.insights
      ? reply
      : reply.protected();
}

ChatReply _clarification() => const ChatReply(
  "I'm not sure what you're asking yet. I want to give you an accurate "
  'answer, but I need a little more detail. '
  'Are you asking about your recorded income, expenses, available balance, '
  'a savings target, or a future purchase? Include the amount and time period '
  'if you want me to calculate it.',
  choices: [
    'How much income did I record this month?',
    'How much did I spend this month?',
    'How much can I save?',
    'Can I afford this purchase?',
  ],
);

ChatReply? _targetSavingsPlan(String message, FinanceSnapshot? records) {
  final normalized = message.toLowerCase();
  final asksToSave = RegExp(
    r'\b(save|saving|savings|set aside|put aside|ipon|'
    r'mag.?ipon|makaipon|makapag.?ipon)\b',
  ).hasMatch(normalized);
  if (!asksToSave) return null;

  final duration = RegExp(
    r'(?:in|within|over|for|next|sa loob ng|within)\s*'
    r'(?:the\s+)?(?:(\d+)|a|an)\s*'
    r'(day|days|week|weeks|month|months|year|years)\b',
  ).firstMatch(normalized);
  if (duration == null) return null;

  final target = findAmount(message)?.value;
  final count = int.tryParse(duration[1] ?? '1');
  if (target == null || target <= 0 || count == null || count <= 0) {
    return null;
  }

  final unit = duration[2]!;
  final days = switch (unit) {
    'day' || 'days' => count,
    'week' || 'weeks' => count * 7,
    'month' || 'months' => count * 30,
    'year' || 'years' => count * 365,
    _ => 0,
  };
  if (days <= 0) return null;

  final daily = (target / days * 100).ceil() / 100;
  final monthly = (target / (days / 30) * 100).ceil() / 100;
  final isFilipino = RegExp(
    r'\b(paano|pano|ako|makakaipon|sa loob|araw araw|araw-araw)\b',
  ).hasMatch(normalized);
  final context = records == null
      ? ''
      : ' Compare this target with your recorded income, expenses, bills, '
            'and existing savings before committing to it.';

  return ChatReply(
    isFilipino
        ? 'Para makaipon ng ${formatPeso(target)} sa loob ng $count $unit, '
              'magtabi ng humigit-kumulang ${formatPeso(daily)} araw-araw '
              '(${formatPeso(monthly)} kada buwan). Ito ay mathematical target '
              'batay sa halaga at panahon na ibinigay mo; hindi pa nito '
              'pinatutunayang kaya ng kasalukuyan mong budget.$context'
        : 'To save ${formatPeso(target)} in $count $unit, set aside about '
              '${formatPeso(daily)} per day (${formatPeso(monthly)} per month). '
              'This is a mathematical target based on the amount and timeline '
              'you gave; it does not prove that your current budget can afford '
              'it.$context',
    isVerifiedGoalPlan: true,
  ).protected();
}

ChatReply? _savingsProjection(String message, FinanceSnapshot? records) {
  final normalized = message.toLowerCase();
  final contributionMatch = RegExp(
    r'([\d,]+(?:\.\d+)?)\s*'
    r'(?:per day|each day|a day|daily|araw araw|kada araw)',
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
        r'(?:in|within|after|over|for)\s+',
      ).firstMatch(normalized);
  final durationMatch = RegExp(
    r'\b(?:in|within|after|over|for)\s+(?:(\d+)|a|an)\s+'
    r'(day|days|week|weeks|month|months|year|years)\b',
  ).firstMatch(normalized);
  if (targetMatch == null || durationMatch == null) return null;

  final target = double.tryParse(targetMatch.group(1)!.replaceAll(',', ''));
  final count = int.tryParse(durationMatch.group(1) ?? '1');
  if (target == null || target <= 0 || count == null || count <= 0) {
    return null;
  }

  final unit = durationMatch.group(2)!;
  final days = switch (unit) {
    'day' || 'days' => count,
    'week' || 'weeks' => count * 7,
    'month' || 'months' => count * 30,
    'year' || 'years' => count * 365,
    _ => 0,
  };
  if (days <= 0) return null;

  final projected = contribution * days;
  final difference = projected - target;
  final result = difference >= 0
      ? 'yes, by about ${formatPeso(difference)}'
      : 'no, you would be short by about ${formatPeso(-difference)}';
  final recordedNote = records == null
      ? ''
      : ' This is before your recorded expenses, bills, and other '
            'commitments, so it is a projection rather than an affordability '
            'guarantee.';
  return ChatReply(
    'At ${formatPeso(contribution)} per day for $count $unit, you would '
    'save about ${formatPeso(projected)}. For a ${formatPeso(target)} goal, '
    'the mathematical answer is $result.$recordedNote',
  ).protected();
}

ChatReply? _savingsTargetAnswer(
  String message, {
  required String? contextMessage,
  required FinanceSnapshot? records,
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
      : _monthlySavingsContext(records, amount);
  return ChatReply(
    'To save ${formatPeso(amount)} per month, set aside about '
    '${formatPeso(dailyTarget)} per day, using a 30-day month. '
    'This is the target amount you asked for, not a claim that it is '
    'affordable. $affordability',
  );
}

String _monthlySavingsContext(FinanceSnapshot records, double target) {
  final month = ReportPeriod.monthOf(records.now);
  final flow = inAndOut(transactionsIn(records.transactions, month));
  final spending = spendingByCategory(
    transactionsIn(records.transactions, month),
  ).fold<double>(0, (sum, entry) => sum + entry.value);
  if (flow.moneyIn <= 0) {
    return "I don't have recorded income this month to compare with this "
        'target.';
  }
  final remaining = flow.moneyIn - spending;
  return 'This month, the app records ${formatPeso(flow.moneyIn)} income and '
      '${formatPeso(spending)} in recorded expenses, leaving about '
      '${formatPeso(remaining < 0 ? 0 : remaining)} before unrecorded bills '
      'and other commitments. Keep those commitments and an emergency buffer '
      'in mind before setting this aside.';
}

ChatReply? _goalSavingsPlan(String message, FinanceSnapshot? records) {
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
    r'\b(?:in|within|over|for|next)\s+(?:the\s+)?(?:next\s+)?'
    r'(\d+)\s+(years?|months?)\b',
  ).firstMatch(normalized);
  if (amount == null || amount < 100 || duration == null) return null;

  final count = int.tryParse(duration[1]!);
  if (count == null || count < 1 || count > 600) return null;
  final unit = duration[2]!.startsWith('year') ? 12 : 1;
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
    r'\b(house|home|property|car|vehicle|condo|land)\b',
  ).firstMatch(normalized);
  final item = itemMatch?[0] ?? 'purchase';
  final matchingGoal = records?.goals.where((goal) {
    final name = goal.name.toLowerCase();
    final matchingNames = switch (item) {
      'bahay' => ['bahay', 'house', 'home', 'property'],
      'house' || 'home' => ['house', 'home', 'bahay', 'property'],
      'car' || 'vehicle' => ['car', 'vehicle'],
      'condo' || 'land' || 'property' => [item, 'bahay', 'house', 'home'],
      _ => [item],
    };
    return goal.status == GoalStatus.active && matchingNames.any(name.contains);
  }).firstOrNull;
  final alreadySaved = matchingGoal?.shownSaved ?? 0;
  final remaining = (amount - alreadySaved).clamp(0, amount).toDouble();
  final monthlyTarget = (remaining / months * 100).ceil() / 100;
  final dailyTarget = (remaining / days * 100).ceil() / 100;
  final trackedAmount = records == null
      ? 'Your saved goals have not loaded, so this estimate assumes no '
            'amount is already set aside.'
      : matchingGoal == null
      ? 'No savings are recorded for this specific goal yet.'
      : 'Your existing “${matchingGoal.name}” goal has '
            '${formatPeso(alreadySaved)} set aside.';

  final isFilipino = RegExp(
    r'\b(gusto kong|magkano|dapat kong|para makabili|araw-araw|'
    r'bahay|bumili|bibili|bilhin|makabili)\b',
  ).hasMatch(normalized);
  final plan = isFilipino
      ? [
          'Para sa $item, magtabi ng humigit-kumulang '
              '${formatPeso(asksDailyTarget ? dailyTarget : monthlyTarget)} '
              '${asksDailyTarget ? 'araw-araw' : 'kada buwan'} sa loob ng '
              '$months buwan (${formatPeso(remaining)} pa ang kailangang '
              'ipunin). $trackedAmount',
          'Tuwid na paghahati ito batay sa presyo at panahong ibinigay mo. '
              'Hindi kasama ang interes o investment returns, fees, at '
              'posibleng pagtaas ng presyo.',
          'Ihambing ang target sa aktuwal mong kita at gastos, pagkatapos '
              'ibawas ang pangangailangan, bills, utang, at iba pang ipon. '
              'Kung hindi kasya, pag-isipang pahabain ang panahon o baguhin '
              'ang target; huwag bawasan ang mahahalagang gastusin.',
        ]
      : [
          'For the $item, aim to set aside about '
              '${formatPeso(asksDailyTarget ? dailyTarget : monthlyTarget)} '
              '${asksDailyTarget ? 'per day' : 'per month'} for $months '
              'months (${formatPeso(remaining)} remaining). $trackedAmount',
          'This is a straight-line target based on the price and timeline you '
              'gave; it does not assume investment returns and excludes fees '
              'or future price changes.',
          'Compare the target with your recorded income and spending after '
              'essentials, bills, debt payments, and other savings '
              'commitments. If it does not fit, consider a longer timeline or '
              'revised target rather than cutting necessary expenses.',
        ];
  return ChatReply(plan.join('\n\n'), isVerifiedGoalPlan: true);
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

ChatReply _formula(String text, FinanceSnapshot? records) {
  final topic = _formulaTopic(text);
  const choices = [
    'Safe to Spend formula',
    'Suggested savings formula',
    'Installment formula',
    'Goal formula',
  ];
  if (topic == _FormulaTopic.reports) {
    return const ChatReply(
      'Reports add recorded income and expenses within '
      'the dates you selected. Income leaves out borrowed money and loan '
      'repayments received. Expenses include bill payments but leave out '
      'money lent. Transfers between your wallets count as neither income '
      'nor expenses.\n\n'
      'Money left = income − expenses. Saved for goals = contributions '
      'during those dates − money taken back out of goals. A category’s '
      'share = spending in that category ÷ total spending × 100. '
      'With no spending, there is no percentage to divide.',
      choices: choices,
    );
  }
  if (topic == _FormulaTopic.wallet) {
    return const ChatReply(
      'A wallet balance starts with its opening amount, '
      'adds money received and transfers in, and subtracts expenses and '
      'transfers out. Balance corrections also change it. Home’s spending '
      'balance adds active spending wallets; Bills and Savings are shown '
      'separately. A transfer changes the two wallets, but not their combined '
      'total.',
      choices: choices,
    );
  }
  if (topic == _FormulaTopic.installment) {
    return const ChatReply(
      'For an installment, total to pay = regular payment × '
      '(number of payments − 1) + the last payment. If the last payment '
      'is the same, this is just payment amount × number of payments.\n\n'
      'Remaining balance = total to pay − recorded payments. Part payments '
      'reduce the balance, but only fully paid scheduled payments count '
      'as completed. Next due date is the earliest unpaid scheduled payment. '
      'Open the installment statement to see its full payment history. '
      'FinAssist uses the terms you entered; it does not invent an interest rate.',
      choices: choices,
    );
  }
  if (topic == _FormulaTopic.goal) {
    return const ChatReply(
      'Goal amount still needed = target − money already saved for that goal '
      '(never below zero).\n\n'
      'Amount needed each time = amount still needed ÷ saving dates left '
      'up to your target date. The dates follow your chosen saving schedule. '
      'If no saving date remains, the full remaining amount '
      'is needed now. Without a target date, there is no deadline-based amount. '
      'This shows what the target needs, not what you can afford to save.',
      choices: choices,
    );
  }
  if (topic == _FormulaTopic.bills) {
    return const ChatReply(
      'Unpaid bill amount = bill amount − payments recorded for it, '
      'never below zero. Safe to Spend adds the unpaid bills due before '
      'the next expected income date, including overdue payments and scheduled '
      'installments. It subtracts only what the Bills wallet does not already '
      'cover. Paid bills are not subtracted again.',
      choices: choices,
    );
  }
  if (records == null) {
    return const ChatReply(
      'I need your records to show your actual figures. '
      'Safe to Spend divides available money across the days it needs to last, '
      'then subtracts what you spent today. Please try again once your records load.',
      choices: choices,
    );
  }
  if (topic == _FormulaTopic.savings) {
    final suggestion = SavingsSuggestion.from(records);
    if (!suggestion.hasHistory) {
      return const ChatReply(
        'Suggested savings = 10% of money left after '
        'uncovered bills, money already saved and estimated everyday costs. '
        'The other 90% stays as a buffer. Record everyday spending on at least '
        '7 different days in the last 30 days before I suggest an amount. '
        'This avoids assuming your everyday costs are zero.',
        choices: choices,
      );
    }
    return ChatReply(
      'Suggested savings = 10% × max(0, available money − '
      'estimated everyday costs).\n\n'
      'Your available money after bills and money already saved: '
      '${formatPeso(suggestion.available)}.\n'
      'Estimated everyday costs for the remaining days: '
      '${formatPeso(suggestion.dailyCosts)}.\n'
      'Suggested to save: ${formatPeso(suggestion.amount)} (rounded down '
      'to a centavo). The other 90% stays as a buffer. Everyday costs use '
      'your recent average spending per day, with today’s spending already '
      'accounted for. This depends on complete records; you choose whether '
      'and how much to save.',
      choices: choices,
    );
  }
  final s = records.safeToSpend;
  final shortfall = math.max(0.0, s.billsDue - s.billsWalletBalance);
  final irregular =
      records.incomeFrequency == null || records.incomeFrequency == 'Irregular';
  return ChatReply(
    'Here is how Safe to Spend is worked out from your records:\n\n'
    '1. Spending wallets ${formatPeso(s.walletBalance)} + today’s spending '
    '${formatPeso(s.spentToday)} − bills still needing money '
    '${formatPeso(shortfall)} − goal money held in spending wallets '
    '${formatPeso(s.goalSavings)}. Negative amounts become zero. '
    'Bills and Savings wallets are kept separate, so saved money is not '
    'subtracted twice.\n'
    '${s.periodBudget == null ? '' : 'Your remaining spending plan also caps this amount. '}'
    '2. Money available at the start of today '
    '${formatPeso(s.spendableThisPeriod)} ÷ ${s.daysLeft} days = '
    '${formatPeso(s.recommendedDailyLimit)} per day'
    '${s.periodBudget == null ? '.' : ', also capped by your planned daily share.'}\n'
    '3. Today’s share ${formatPeso(s.dailyLimit)} − what you spent today '
    '${formatPeso(s.spentToday)} = ${formatPeso(s.leftToday)} left today. '
    'A negative result means you have gone over today’s amount.\n\n'
    'Today’s spending is added back in step 1 because your wallet balance '
    'already went down, then subtracted in step 3. Bill payments and money '
    'lent are excluded from everyday spending. '
    '${irregular ? 'With no fixed income date, the days run through the end of this month.' : 'The days follow the income date and schedule in Financial preferences; recording income does not restart the countdown.'} '
    'Figures depend on what you record. Which calculation would you like next?',
    choices: choices,
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
    'pinakamataas',
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

  if (_has(text, [
    'what can you do',
    'help',
    'ano kaya mo',
    'ano ang kaya mo',
    'paano ka gamitin',
  ])) {
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
    'budget',
  ])) {
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
  ])) {
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

ChatReply _safeToday(FinanceSnapshot records) {
  if (records.wallets.isEmpty) return _noWallets;
  final s = records.safeToSpend;
  final payday = records.period.end;

  if (s.isOverLimit) {
    return ChatReply(
      "You've spent ${formatPeso(s.spentToday)} today, which is "
      '${formatPeso(-s.leftToday)} over your limit of '
      '${formatPeso(s.dailyLimit)}. Keeping tomorrow light helps you catch '
      'up before payday on ${formatMonthDay(payday)}.',
    );
  }
  return ChatReply(
    'You can still spend ${formatPeso(_down(s.leftToday))} today, out of '
    "today's ${formatPeso(_down(s.dailyLimit))} limit. That keeps bills "
    'and money set aside safe, with ${_days(s.daysLeft)} left until payday '
    'on ${formatMonthDay(payday)}.',
  );
}

ChatReply _safeTodayComparison(String text, FinanceSnapshot records) {
  final amount = findAmount(text)?.value;
  if (amount == null) return _safeToday(records);

  final available = _down(records.safeToSpend.leftToday);
  if (amount <= available) {
    return ChatReply(
      'Yes, ${formatPeso(amount)} fits within your ${formatPeso(available)} '
      'left-to-spend amount for today. Keep the rest for your planned '
      'expenses, bills and savings.',
    );
  }
  return ChatReply(
    '${formatPeso(amount)} is more than the ${formatPeso(available)} you '
    'have left to spend today. Spending that much could affect your bills '
    'or money set aside.',
  );
}

ChatReply _spent(String text, FinanceSnapshot records) {
  final (period, label) = _periodIn(text, records.now);
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
      return ChatReply("You haven't recorded any ordinary expenses $label.");
    }
    final selected = _selectExtreme(
      expenses,
      extreme,
      value: (transaction) => transaction.amount,
    );
    return ChatReply(
      'Your ${extreme == _Extreme.smallest ? 'smallest' : 'biggest'} '
      'ordinary expense $label was ${formatPeso(selected.amount)} for '
      '${selected.label}.',
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
      return ChatReply("You haven't spent anything on $category $label.");
    }

    final count = during
        .where(
          (t) =>
              t.type == TransactionType.expense &&
              !t.isDebtMovement &&
              t.label == category,
        )
        .length;
    return ChatReply(
      "You've spent ${formatPeso(spent)} on $category $label, across "
      '$count ${count == 1 ? 'expense' : 'expenses'}. That is '
      '${_percent(spent, total)} of your spending $label.',
    );
  }

  if (total <= 0) {
    return ChatReply("You haven't recorded any spending $label yet.");
  }
  final top = byCategory.take(2).toList();
  return ChatReply(
    "You've spent ${formatPeso(total)} $label. Most of it went to "
    '${top.map((e) => '${e.key} (${formatPeso(e.value)})').join(' and ')}.',
  );
}

ChatReply _savingsPlan(FinanceSnapshot records, String question) {
  final suggestion = SavingsSuggestion.from(records);
  final month = ReportPeriod.monthOf(records.now);
  final currentMonth = transactionsIn(records.transactions, month);
  final flow = inAndOut(currentMonth);
  final recordedExpenses = spendingByCategory(
    currentMonth,
  ).fold<double>(0, (sum, entry) => sum + entry.value);
  final missing = <String>[];

  if (flow.moneyIn <= 0) {
    missing.add('at least one recorded income entry for the planning period');
  }
  if (!suggestion.hasHistory) {
    missing.add(
      'ordinary spending recorded on at least 7 different days in the last '
      '30 days',
    );
  }
  if (missing.isNotEmpty) {
    return ChatReply(
      'I cannot make a reliable savings plan yet because I need ${missing.join(' and ')}. '
      'Please record your income and everyday expenses, including bills and '
      'debt payments, then ask me again. A missing record does not mean the '
      'expense was zero.',
    );
  }

  final billsDue = math.max(
    0.0,
    records.safeToSpend.billsDue - records.safeToSpend.billsWalletBalance,
  );
  final goalMoney = records.goalSavings;
  final suggested = suggestion.amount;
  final monthlySuggested = suggested;
  final weeklySuggested = (monthlySuggested / 4 * 100).floor() / 100;
  final dailySuggested = (monthlySuggested / 30 * 100).floor() / 100;
  final questionNote =
      _has(question, ['bill', 'bills', 'bayarin', 'utang', 'debt'])
      ? ' This includes the bills currently due that are not covered by the '
            'Bills wallets, while money already set aside for goals is protected.'
      : '';

  if (monthlySuggested <= 0) {
    return ChatReply(
      'Based on your recorded income of ${formatPeso(flow.moneyIn)} and '
      'expenses of ${formatPeso(recordedExpenses)} this month, there is no '
      'reliable amount left to suggest for savings after your recorded '
      'commitments. Bills currently needing coverage total '
      '${formatPeso(billsDue)}, and ${formatPeso(goalMoney)} is already set '
      'aside for goals. Keep recording complete bills and expenses, protect '
      'essentials, and review the plan after your next income cycle.'
      '$questionNote',
    );
  }

  return ChatReply(
    'Here is a savings plan based on your recorded data: save about '
    '${formatPeso(monthlySuggested)} per month, or about '
    '${formatPeso(weeklySuggested)} per week or '
    '${formatPeso(dailySuggested)} per day. This uses recorded income of '
    '${formatPeso(flow.moneyIn)}, recorded expenses of '
    '${formatPeso(recordedExpenses)}, bills currently needing coverage of '
    '${formatPeso(billsDue)}, and ${formatPeso(goalMoney)} already set aside '
    'for goals. The plan leaves most of the calculated remainder as a buffer. '
    'Records may be incomplete, so keep checking essentials and new bills '
    'before transferring the suggested amount.'
    '$questionNote',
  );
}

ChatReply _savingsCapacity(String text, FinanceSnapshot records) {
  final (period, label) = _periodIn(text, records.now);
  final during = transactionsIn(records.transactions, period);
  final flow = inAndOut(during);
  final spending = spendingByCategory(
    during,
  ).fold<double>(0, (sum, entry) => sum + entry.value);

  if (flow.moneyIn <= 0) {
    return ChatReply(
      "I don't have any recorded income for $label, so I can't calculate "
      'how much you could save yet.',
    );
  }
  final available = flow.moneyIn - spending;
  if (available <= 0) {
    return ChatReply(
      "Based on your recorded income and everyday expenses $label, there "
      'is no recorded amount left over to save yet.',
    );
  }
  return ChatReply(
    'Based on your records, you could have about ${formatPeso(available)} '
    'left to save $label: ${formatPeso(flow.moneyIn)} received minus '
    '${formatPeso(spending)} in everyday expenses. This does not include '
    'unrecorded bills or spending, so keep a buffer before setting it aside.',
  );
}

ChatReply _topSpending(String text, FinanceSnapshot records) {
  final (period, label) = _periodIn(text, records.now);
  final byCategory = spendingByCategory(
    transactionsIn(records.transactions, period),
  );
  final total = byCategory.fold<double>(0, (sum, entry) => sum + entry.value);
  if (total <= 0) {
    return ChatReply("You haven't recorded any spending $label yet.");
  }

  final lines = [
    for (final (i, entry) in byCategory.take(3).indexed)
      '${i + 1}. ${entry.key}: ${formatPeso(entry.value)} '
          '(${_percent(entry.value, total)})',
  ];
  return ChatReply('Your biggest spending $label:\n${lines.join('\n')}');
}

ChatReply _bills(String text, FinanceSnapshot records) {
  final extreme = _extremeRequested(text);
  if (extreme != null) {
    final unpaid = records.bills.where((bill) => !bill.isSettled).toList();
    if (unpaid.isEmpty) {
      return const ChatReply("You don't have any unpaid bills recorded.");
    }
    final selected = _selectExtreme(
      unpaid,
      extreme,
      value: (bill) => bill.remaining,
    );
    return ChatReply(
      'Your ${extreme == _Extreme.smallest ? 'smallest' : 'biggest'} '
      'unpaid bill is ${selected.name} at ${formatPeso(selected.remaining)}, '
      'due ${formatMonthDay(selected.dueDate)}.',
    );
  }
  final today = records.today;
  final DateTime until;
  final String label;
  if (_has(text, ['this month', 'ngayong buwan', 'month', 'buwan'])) {
    until = DateTime(today.year, today.month + 1);
    label = 'before the month ends';
  } else {
    until = today.add(const Duration(days: 7));
    label = 'in the next 7 days';
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
      return const ChatReply("You don't have any unpaid bills coming up.");
    }
    final next = later.first;
    return ChatReply(
      'No bills are due $label. The next one is ${next.name}, '
      '${formatPeso(next.remaining)} on ${formatMonthDay(next.dueDate)}.',
    );
  }

  String line(BillInstance bill) =>
      '• ${bill.name}: ${formatPeso(bill.remaining)}, '
      '${formatMonthDay(bill.dueDate)}';
  final total = [
    ...overdue,
    ...soon,
  ].fold<double>(0, (sum, bill) => sum + bill.remaining);
  return ChatReply(
    [
      if (overdue.isNotEmpty) 'Overdue:\n${overdue.map(line).join('\n')}',
      if (soon.isNotEmpty) 'Due $label:\n${soon.map(line).join('\n')}',
      'That is ${formatPeso(total)} in all.',
    ].join('\n\n'),
  );
}

ChatReply _balance(FinanceSnapshot records) {
  if (records.wallets.isEmpty) return _noWallets;
  final wallets = [...records.wallets]
    ..sort((a, b) => b.balance.compareTo(a.balance));
  final s = records.safeToSpend;
  final free = _down(s.spendableThisPeriod - s.spentToday);

  return ChatReply(
    'You have ${formatPeso(records.walletBalance)} across '
    '${wallets.length} ${wallets.length == 1 ? 'wallet' : 'wallets'}: '
    '${wallets.take(5).map((w) => '${w.name} ${formatPeso(w.balance)}').join(', ')}.'
    '\n\nAfter bills due before payday and money set aside, '
    '${formatPeso(free < 0 ? 0 : free)} is free to spend until '
    '${formatMonthDay(records.period.end)}.',
  );
}

ChatReply _savings(FinanceSnapshot records) {
  final goals = records.goals
      .where((goal) => goal.status == GoalStatus.active)
      .toList();
  if (goals.isEmpty) {
    return const ChatReply(
      "You don't have any savings set aside or goals yet. Making a goal, "
      'even a small one, is the easiest way to start.',
    );
  }

  final lines = [
    for (final goal in goals.take(5))
      '• ${goal.name}: ${formatPeso(goal.shownSaved)} of '
          '${formatPeso(goal.targetAmount)} '
          '(${(goal.progress * 100).round()}%)',
  ];
  return ChatReply(
    [
      if (goals.isNotEmpty)
        "You've set aside ${formatPeso(records.goalSavings)} for "
            '${goals.length} ${goals.length == 1 ? 'goal' : 'goals'}:\n'
            '${lines.join('\n')}',
    ].join('\n\n'),
  );
}

ChatReply _debts(String text, FinanceSnapshot records) {
  // A question about one person or one debt, such as "Ilan yung napautang ko
  // kay Ana?", is answered about that one.
  final named = _namedDebts(text, records);
  if (named.isNotEmpty) {
    return ChatReply(named.map(_aboutDebt).join('\n\n'));
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
    return const ChatReply("You don't have any debts recorded.");
  }

  final parts = <String>[];
  if (iOwe.isNotEmpty) {
    parts.add(
      "You're paying ${iOwe.length} "
      '${iOwe.length == 1 ? 'debt' : 'debts'}:\n'
      '${iOwe.map((d) => '• ${d.name}: ${formatPeso(d.perPayment)} ${d.frequency.label.toLowerCase()}').join('\n')}',
    );
  }
  if (owedToMe.isNotEmpty) {
    final total = owedToMe.fold<double>(0, (sum, d) => sum + d.stillOwedToMe);
    parts.add(
      'People owe you ${formatPeso(total)}:\n'
      '${owedToMe.map((d) => '• ${d.name}: ${formatPeso(d.stillOwedToMe)}').join('\n')}',
    );
  }
  return ChatReply(parts.join('\n\n'));
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
String _aboutDebt(Debt debt) {
  if (debt.status == DebtStatus.settled) {
    return 'Your ${debt.name} debt is paid off.';
  }
  final count = debt.paymentCount > 0
      ? ', ${debt.paymentCount} payments in all'
      : '';
  final last = debt.hasDifferentLastPayment
      ? ', the last one ${formatPeso(debt.finalPayment)}'
      : '';
  return 'For ${debt.name}, you pay ${formatPeso(debt.perPayment)} '
      '${debt.frequency.label.toLowerCase()}$count$last.';
}

ChatReply _income(String text, FinanceSnapshot records) {
  final (period, label) = _periodIn(text, records.now);
  final income = transactionsIn(
    records.transactions,
    period,
  ).where((transaction) => transaction.type == TransactionType.income).toList();
  final received = income.fold<double>(
    0,
    (sum, transaction) => sum + transaction.amount,
  );
  if (received <= 0) {
    return ChatReply("You haven't recorded any income $label.");
  }
  final extreme = _extremeRequested(text);
  if (extreme != null) {
    final selected = _selectExtreme(
      income,
      extreme,
      value: (transaction) => transaction.amount,
    );
    return ChatReply(
      'Your ${extreme == _Extreme.smallest ? 'smallest' : 'biggest'} '
      'income $label was ${formatPeso(selected.amount)} '
      '(${selected.label}).',
    );
  }
  return ChatReply("You've received ${formatPeso(received)} $label.");
}

ChatReply _advice(FinanceSnapshot records, String question) {
  if (_asksSpendingComparison(question)) {
    return _spendingPatternComparison(records, question).protected();
  }
  final month = ReportPeriod.monthOf(records.now);
  final byCategory = spendingByCategory(
    transactionsIn(records.transactions, month),
  );
  if (byCategory.isEmpty) {
    return const ChatReply(
      'Start by recording every expense for a week, even the small ones. '
      'Then Reports shows where your money goes, and I can point out where '
      'to cut.',
    );
  }

  final total = byCategory.fold<double>(0, (sum, entry) => sum + entry.value);
  final top = byCategory.first;
  final insights = insightsFor(
    records.transactions,
    period: month,
    range: ReportRange.month,
    limit: 1,
  );
  return ChatReply(
    [
      'Your biggest spending this month is ${top.key} at '
          '${formatPeso(top.value)}, ${_percent(top.value, total)} of the '
          'total. Spending 10% less there saves about '
          '${formatPeso(_up(top.value * 0.1))} a month.',
      ...insights,
      'Setting aside savings on payday, before you spend, makes it much '
          'easier to stick to.',
    ].join('\n\n'),
  );
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

ChatReply _spendingPatternComparison(FinanceSnapshot records, String question) {
  final normalized = question.toLowerCase();
  final periods = <int>[];
  if (RegExp(r'\b(days?|daily)\b').hasMatch(normalized)) periods.add(3);
  if (RegExp(r'\b(weeks?|weekly)\b').hasMatch(normalized)) periods.add(7);
  if (RegExp(r'\b(months?|monthly)\b').hasMatch(normalized)) {
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
    final windowLabel = days == 3
        ? 'the last three days'
        : days == 7
        ? 'the last week'
        : days == 90
        ? 'the last three months'
        : 'the last thirty days';
    final priorLabel = days == 3
        ? 'the three days before that'
        : days == 7
        ? 'the week before that'
        : days == 90
        ? 'the three months before that'
        : 'the thirty days before that';

    if (recent.expenseCount == 0 || previous.expenseCount == 0) {
      final recordedPeriod = recent.expenseCount > 0 ? windowLabel : priorLabel;
      final recorded = recent.expenseCount > 0 ? recent : previous;
      lines.add(
        recent.expenseCount == 0 && previous.expenseCount == 0
            ? 'I do not have enough recorded expenses to compare $windowLabel '
                  'with $priorLabel. Missing records do not mean no spending '
                  'happened.'
            : 'I found ${formatPeso(recorded.amount)} in recorded expenses '
                  'for $recordedPeriod, but no recorded expenses for the '
                  'matching period. I cannot tell whether your spending '
                  'changed because your records may be incomplete.',
      );
      continue;
    }

    final direction = recent.amount > previous.amount
        ? 'higher'
        : recent.amount < previous.amount
        ? 'lower'
        : 'about the same';
    final recentCategory = _topRecordedCategory(recent);
    final previousCategory = _topRecordedCategory(previous);
    lines.add(
      'You recorded ${formatPeso(recent.amount)} in expenses for $windowLabel '
      'and ${formatPeso(previous.amount)} for $priorLabel. Recorded spending '
      'was $direction. '
      '${recentCategory == null ? '' : 'Most spending was ${recentCategory.key} recently.'} '
      '${previousCategory == null ? '' : 'In the earlier period, it was mostly ${previousCategory.key}.'}',
    );
  }

  lines.add(
    'These comparisons use only expenses recorded in FinAssist, so missing '
    'entries may change the picture.',
  );
  return ChatReply(lines.join('\n\n'));
}

MapEntry<String, double>? _topRecordedCategory(SpendingPeriodTotals totals) {
  if (totals.categoryTotals.isEmpty) return null;
  final categories = totals.categoryTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return categories.first;
}

const _noWallets = ChatReply(
  'Add your wallets first, with the money you have now, so I can see what '
  'you have to work with.',
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
) {
  if (records == null) {
    return const ChatReply(
      "I'm still loading your records. Ask me again in a moment.",
    );
  }
  final (deadline, label) = _deadlineIn(message.toLowerCase(), records);
  final words = message.substring(triggerEnd);
  final price = _priceIn(words);
  final question = PurchaseQuestion(
    deadline: deadline,
    deadlineLabel: label,
    item: _itemIn(words, price),
    price: price?.value,
  );
  return _nextPurchaseStep(question, records);
}

/// Handles a reply to a follow-up question, or null when the message is a
/// new question instead.
ChatReply? _continuePurchase(
  String message,
  String text,
  PurchaseQuestion pending,
  FinanceSnapshot? records,
) {
  if (records == null) return null;
  // A new "Can I buy…" or another kind of question starts over.
  if (_buyTrigger.hasMatch(message.toLowerCase())) return null;
  final amount = findAmount(message)?.value;

  switch (pending.waitingFor) {
    case PurchaseStep.item:
      final price = _priceIn(message);
      if (_intentOf(text) != null && price == null) return null;
      final item = _itemIn(message, price);
      if (item.isEmpty) return null;
      return _nextPurchaseStep(
        pending.copyWith(item: item, price: price?.value, clearWaiting: true),
        records,
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
        );
      }
      if (_has(text, _noPreference) || message.trim() == anyBrand) {
        return _nextPurchaseStep(
          pending.copyWith(brand: anyBrand, clearWaiting: true),
          records,
        );
      }
      if (_intentOf(text) != null) return null;
      return _nextPurchaseStep(
        pending.copyWith(brand: message.trim(), clearWaiting: true),
        records,
      );

    case PurchaseStep.price:
      if (amount != null) {
        return _purchaseAnswer(pending.copyWith(price: amount), records);
      }
      if (_has(text, _unsure) || message.trim() == notSure) {
        return _purchaseAnswer(pending, records);
      }
      if (_intentOf(text) != null) return null;
      if (pending.asked >= 2) return _purchaseAnswer(pending, records);
      return ChatReply(
        'Just type the price, for example ₱8,990, or tap "$notSure".',
        choices: const [notSure],
        pending: pending.copyWith(asked: pending.asked + 1),
      );

    case null:
      return null;
  }
}

const _noPreference = [
  'any',
  'any brand',
  'kahit ano',
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
ChatReply _nextPurchaseStep(PurchaseQuestion q, FinanceSnapshot records) {
  if (q.item.isEmpty) {
    return ChatReply(
      'What would you like to buy?',
      pending: q.copyWith(waitingFor: PurchaseStep.item, asked: q.asked + 1),
    );
  }
  if (q.price != null) return _purchaseAnswer(q, records);

  final brands = _brandsFor(q.item);
  if (q.brand == null && brands != null) {
    final isAirPods = _plain(q.item).contains('airpods');
    return ChatReply(
      isAirPods
          ? 'Which AirPods are you looking at? You can also just type the '
                'price.'
          : 'Do you have a brand in mind for the ${q.item}? You can also '
                'just type the price.',
      choices: [...brands, anyBrand],
      pending: q.copyWith(waitingFor: PurchaseStep.brand, asked: q.asked + 1),
    );
  }
  if (q.brand == anyBrand) return _purchaseAnswer(q, records);

  return ChatReply(
    'About how much is the ${q.thing}? Type the price, for example ₱8,990.',
    choices: const [notSure],
    pending: q.copyWith(waitingFor: PurchaseStep.price, asked: q.asked + 1),
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
ChatReply _purchaseAnswer(PurchaseQuestion q, FinanceSnapshot records) {
  if (records.wallets.isEmpty) return _noWallets;

  final today = records.today;
  final days = math.max(1, q.deadline.difference(today).inDays);
  final bills = billsDueBefore(records.bills, q.deadline);
  final available =
      records.walletBalance - bills - records.goalSavingsInSpendingWallets;

  final daily = records.usualDailySpending;
  // Today's spending is already out of the wallets; only the rest of today
  // is still to come.
  final restOfToday = math.max(0.0, daily - records.spentToday);
  final usual = daily * (days - 1) + restOfToday;

  final paydays = _paydaysBefore(records, q.deadline);
  final income = (records.usualIncome ?? 0) * paydays;
  final spare = _down(available + income - usual);

  final notes = [
    if (income > 0)
      'That counts ${formatPeso(income)} of income you usually get before '
          'then.',
    if (daily <= 0)
      "You haven't recorded day-to-day spending yet, so I couldn't allow for "
          'it.',
    if (q.deadline.isAfter(DateTime(today.year, today.month + 2)))
      "Bills more than a month away aren't counted yet.",
  ];
  // What the spare money is worked out after, naming only what there is:
  // no "bills (₱0)" for someone with no bills.
  final setAside = records.goalSavingsInSpendingWallets;
  final coveredParts = [
    if (bills > 0) 'bills (${formatPeso(bills)})',
    if (setAside > 0) 'money set aside (${formatPeso(setAside)})',
    if (daily > 0) 'your usual ${formatPeso(_down(daily))} a day',
  ];
  final covers = coveredParts.length <= 1
      ? coveredParts.firstOrNull
      : '${coveredParts.take(coveredParts.length - 1).join(', ')} and '
            '${coveredParts.last}';
  final after = covers == null ? 'You' : 'After $covers, you';

  // No price: say so plainly, then give the most that could go to it, so a
  // car is never made to sound like it costs a few thousand pesos. The price
  // can still be typed next.
  final price = q.price;
  if (price == null) {
    final what = q.thing.isEmpty ? 'it' : 'the ${q.thing}';
    final when = _capital(q.deadlineLabel);
    return ChatReply(
      [
        if (spare <= 0)
          "Without a price, I can't check it yet. $when, there's nothing "
              'spare${covers == null ? '' : ' once $covers are covered'}. '
              "Tell me the price and I'll work out how long to save for it."
        else
          "Without a price, I can't check it yet. $when, the most you can "
              'spend on $what is about ${formatPeso(spare)}'
              '${covers == null ? '' : ', after $covers'}. Tell me the '
              "price and I'll tell you if it fits, or how long to save for "
              'it.',
        ...notes,
      ].join('\n\n'),
      pending: q.copyWith(waitingFor: PurchaseStep.price),
    );
  }

  final thing = q.thing.isEmpty ? 'it' : 'the ${q.thing}';
  if (spare >= price) {
    return ChatReply(
      [
        'Yes, you can buy $thing (${formatPeso(price)}) ${q.deadlineLabel}. '
            '$after would still have about ${formatPeso(spare - price)} '
            'spare.',
        ...notes,
      ].join('\n\n'),
    );
  }

  final short = price - spare;
  final cutPerDay = _up(short / days);
  if (daily > 0 && days >= 3 && cutPerDay <= daily * 0.5) {
    return ChatReply(
      [
        "Yes, if you spend a little less. You're about ${formatPeso(short)} "
            'short ${q.deadlineLabel}, so aim for about '
            '${formatPeso(_down(daily - cutPerDay))} a day instead of your '
            'usual ${formatPeso(_down(daily))}.',
        ?_habit(records),
        ...notes,
      ].join('\n\n'),
    );
  }

  // Not in time: a weekly amount the user's own spending can support.
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
  final perWeek = _upTo50(toSave / weeks);
  final ready = today.add(Duration(days: weeks * 7));
  final name = q.thing.isEmpty ? 'Something I want' : _goalName(q.thing);

  return ChatReply(
    [
      // With nothing spare, "₱12,000 short of ₱10,000" would read wrong.
      if (spare > 0)
        "It doesn't fit ${q.deadlineLabel} yet. $after would have about "
            '${formatPeso(spare)} spare, ${formatPeso(short)} short of '
            '${formatPeso(price)}.'
      else
        "It doesn't fit ${q.deadlineLabel} yet. "
            '${covers == null ? 'Nothing' : 'After $covers, nothing'} would '
            'be spare, so all ${formatPeso(price)} still needs saving.',
      'Saving ${formatPeso(perWeek)} a week gets you there by '
          '${formatShortDate(ready)}.',
      ...notes,
    ].join('\n\n'),
    goal: GoalOffer(name: name, target: price, date: ready),
  );
}

/// Where most day-to-day money goes, from the last 30 days.
String? _habit(FinanceSnapshot records) {
  final monthAgo = records.today.subtract(const Duration(days: 30));
  final recent = records.transactions.where(
    (t) => !t.isBillPayment && !t.date.isBefore(monthAgo),
  );
  final byCategory = spendingByCategory(recent);
  if (byCategory.isEmpty) return null;
  final top = byCategory.first;
  return 'Most of your day-to-day money goes to ${top.key}, about '
      '${formatPeso(_down(top.value / 30))} a day, so that is the easiest '
      'place to trim.';
}

/// How many paydays fall before [deadline], after the current one.
int _paydaysBefore(FinanceSnapshot records, DateTime deadline) {
  var count = 0;
  var period = records.period;
  for (var i = 0; i < 60 && period.end.isBefore(deadline); i++) {
    count++;
    period = payPeriodFor(
      records.incomeFrequency,
      lastIncomeAt: records.lastIncomeAt,
      now: period.end,
    );
  }
  return count;
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

/// By when it would be bought. Unless the question says, before payday.
(DateTime, String) _deadlineIn(String lower, FinanceSnapshot records) {
  final text = ' ${_plain(lower)} ';
  final today = records.today;

  if (_has(text, ['today']) || text.contains(' ngayon ')) {
    return (today.add(const Duration(days: 1)), 'today');
  }
  if (_has(text, ['this week', 'ngayong linggo'])) {
    final monday = today.add(Duration(days: 8 - today.weekday));
    return (monday, 'this week');
  }
  if (_has(text, ['next month', 'sa susunod na buwan'])) {
    return (DateTime(today.year, today.month + 2), 'by the end of next month');
  }
  if (_has(text, ['this month', 'ngayong buwan'])) {
    return (DateTime(today.year, today.month + 1), 'this month');
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
      return (DateTime(year, i + 2), 'by the end of $label');
    }
  }
  final payday = records.period.end;
  return (payday, 'before payday (${formatMonthDay(payday)})');
}

final _timeWords = RegExp(
  r'\b(this|next) (month|week)\b|\bngayong (buwan|linggo)\b|'
  r'\bsa susunod na (buwan|linggo)\b|\b(before|bago) (my next )?'
  r'(payday|sahod|sweldo)\b|\bby (the end of )?[a-z]+\b|\btoday\b|'
  r'\bngayon\b',
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

/// The price in "Can I buy…" words. A plain number under ₱100 is more
/// likely part of a name, as in "iPhone 16", so it only counts when said as
/// money, as in "₱50" or "50 pesos".
({double value, int start, int end, bool isMoney})? _priceIn(String words) {
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
