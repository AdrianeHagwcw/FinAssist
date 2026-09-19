import 'dart:math' as math;

import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'app_transaction.dart';
import 'bill.dart';
import 'debt.dart';
import 'expense_guess.dart';
import 'finance_snapshot.dart';
import 'goal.dart';
import 'report.dart';
import 'safe_to_spend.dart';
import 'transaction_filter.dart';

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
  });

  final String text;

  /// Quick replies the user can tap instead of typing.
  final List<String> choices;

  /// A savings goal worth making, offered with a button.
  final GoalOffer? goal;

  /// A question still being worked out, carried into the next message.
  final PurchaseQuestion? pending;
}

/// Questions to try, offered at the start and when a question isn't clear.
const suggestedQuestions = [
  'How much can I spend today?',
  'Where am I spending the most?',
  'May bills ba ako this week?',
  'Can I buy AirPods?',
];

/// Answers [message] from [records], the user's own data, which is null
/// while it is still loading. [pending] is a "Can I buy it?" question still
/// being worked out.
ChatReply answerChat(
  String message, {
  required FinanceSnapshot? records,
  PurchaseQuestion? pending,
}) {
  final text = ' ${_plain(message)} ';

  if (pending != null) {
    final followUp = _continuePurchase(message, text, pending, records);
    if (followUp != null) return followUp;
  }

  final buy = _buyTrigger.firstMatch(message.toLowerCase());
  if (buy != null) return _startPurchase(message, buy.end, records);

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
        ? const ChatReply(
            "I'm not sure what you're asking. I can answer questions like "
            'these:',
            choices: suggestedQuestions,
          )
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
    );
  }

  return switch (intent) {
    _Intent.safeToday => _safeToday(records),
    _Intent.spent => _spent(text, records),
    _Intent.topSpending => _topSpending(text, records),
    _Intent.bills => _bills(text, records),
    _Intent.balance => _balance(records),
    _Intent.savings => _savings(records),
    _Intent.debts => _debts(text, records),
    _Intent.income => _income(text, records),
    _Intent.advice => _advice(records),
    _Intent.greeting || _Intent.help => throw StateError('answered above'),
  };
}

// ------------------------------------------------------------ understanding

enum _Intent {
  greeting,
  help,
  safeToday,
  spent,
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
  ])) {
    return _Intent.safeToday;
  }
  if (_has(text, [
    'how can i save',
    'how to save',
    'how do i save',
    'save more',
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
  if (s.usesCustomLimit) {
    return ChatReply(
      'You can still spend ${formatPeso(_down(s.leftToday))} today, out of '
      'your own daily limit of ${formatPeso(_down(s.dailyLimit))}. '
      '${_days(s.daysLeft)} left until payday on ${formatMonthDay(payday)}.',
    );
  }
  return ChatReply(
    'You can still spend ${formatPeso(_down(s.leftToday))} today, out of '
    "today's ${formatPeso(_down(s.dailyLimit))} limit. That keeps bills "
    'and money set aside safe, with ${_days(s.daysLeft)} left until payday '
    'on ${formatMonthDay(payday)}.',
  );
}

ChatReply _spent(String text, FinanceSnapshot records) {
  final (period, label) = _periodIn(text, records.now);
  final during = transactionsIn(records.transactions, period);
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
  final reserve = records.savingsReserve;

  if (goals.isEmpty && reserve <= 0) {
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
      if (reserve > 0) 'You also keep ${formatPeso(reserve)} as savings.',
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
  if (debt.direction == DebtDirection.owedToMe) {
    final due = debt.dueDate == null
        ? ''
        : ' It is due back on ${formatMonthDay(debt.dueDate!)}.';
    if (debt.status == DebtStatus.settled || debt.stillOwedToMe <= 0) {
      return '${debt.name} has paid back the ${formatPeso(debt.principal)} '
          'you lent in full.';
    }
    if (debt.received > 0) {
      return 'You lent ${debt.name} ${formatPeso(debt.principal)}. '
          '${formatPeso(debt.received)} is back, so '
          '${formatPeso(debt.stillOwedToMe)} is still owed to you.$due';
    }
    return 'You lent ${debt.name} ${formatPeso(debt.principal)}, and all of '
        'it is still owed to you.$due';
  }

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
  final received = inAndOut(
    transactionsIn(records.transactions, period),
  ).moneyIn;
  if (received <= 0) {
    return ChatReply("You haven't recorded any income $label.");
  }
  return ChatReply("You've received ${formatPeso(received)} $label.");
}

ChatReply _advice(FinanceSnapshot records) {
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
      records.walletBalance -
      bills -
      records.savingsReserve -
      records.goalSavings;

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
  final setAside = records.savingsReserve + records.goalSavings;
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
