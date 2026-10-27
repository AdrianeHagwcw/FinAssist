import 'expense_guess.dart';
import 'wallet.dart';
import '../utils/income_sources.dart';

/// The sections Voice Entry can open.
enum VoiceDestination {
  home,
  transactions,
  bills,
  wallet,
  savings,
  installments,
  debts,
  goals,
  reports,
  settings,
  scanReceipt,
  assistant,
  expenseCategories,
  payCycleHistory,
  reminders,
  help,
}

/// What a voice command does. Everything but [navigation] opens the app's
/// own form with what was said filled in; the user checks it and saves.
enum VoiceCommandType {
  expense,
  income,
  transfer,
  bill,
  goal,
  installment,
  debt,
  wallet,
  navigation,
}

class VoiceCommand {
  const VoiceCommand({
    required this.type,
    required this.expense,
    this.incomeSource,
    this.destination,
    this.name,
    this.from,
    this.to,
    this.toSavings = false,
    this.count,
    this.perPayment = false,
  });

  final VoiceCommandType type;
  final ExpenseGuess expense;
  final String? incomeSource;
  final VoiceDestination? destination;

  /// What to call the new bill, goal, installment, debt or wallet, as said.
  final String? name;

  /// The wallets a transfer is from and to, as said.
  final String? from;
  final String? to;

  /// A transfer into savings, as in "ipon 500".
  final bool toSavings;

  /// How many payments an installment or debt has, as in "12 months".
  final int? count;

  /// The amount is each payment rather than the whole price, as in "1,500 a
  /// month".
  final bool perPayment;

  double? get amount => expense.amount;
}

/// Reads what was said, in English, Tagalog or both mixed, as one command.
///
/// Rule-based, so every result can be explained, and nothing is saved from
/// it: the matching form opens with these details for the user to check.
VoiceCommand interpretVoiceCommand(
  String words, {
  required Iterable<String> categories,
}) {
  final spoken = spokenNumbersToDigits(words);
  final count = _paymentCount.firstMatch(spoken);
  // "12 months" is how many payments, never the amount.
  final forAmount = count == null
      ? spoken
      : spoken.replaceRange(count.start, count.end, ' ');
  final expense = guessFromSpeech(forAmount, categories: categories);
  final text = _normalize(spoken);
  final amount = expense.amount;

  VoiceCommand command(
    VoiceCommandType type, {
    VoiceDestination? destination,
    String? name,
    String? incomeSource,
  }) => VoiceCommand(
    type: type,
    expense: expense,
    destination: destination,
    name: name,
    incomeSource: incomeSource,
    count: count == null ? null : int.tryParse(count[1]!),
    perPayment: _perPayment.hasMatch(text),
  );
  VoiceCommand open(VoiceDestination destination) =>
      command(VoiceCommandType.navigation, destination: destination);

  if (text.isEmpty) return command(VoiceCommandType.expense);

  if ((_has(text, _scan) && _has(text, _receipt)) ||
      _has(text, r'receipt scanner|resibo scanner')) {
    return open(VoiceDestination.scanReceipt);
  }
  if (_has(
    text,
    r'(pay cycle|pay period|paycheck|income|inflow|inflows|kita) history|'
    r'cash inflows',
  )) {
    return open(VoiceDestination.payCycleHistory);
  }

  final adding = _has(text, _addVerbs);
  final opening = _has(text, _openVerbs);
  final spending = _has(text, _spendVerbs);
  // A form is started by asking to add one, or by saying an amount for it;
  // the same words with "open" or alone go to the section.
  final wantsForm = !opening && (adding || amount != null);
  String? nameAfter() => _nameFrom(forAmount);
  // Paying one is done in the Bill Planner, so it is marked paid there.
  final paying = _has(text, _payVerbs);

  if (_has(text, _moveVerbs)) {
    final (from, to) = _walletsIn(text);
    final savings = to != null && _has(to.toLowerCase(), _savingsWords);
    return VoiceCommand(
      type: VoiceCommandType.transfer,
      expense: expense,
      from: from,
      to: savings ? null : to,
      toSavings: savings,
    );
  }

  // "Save for a laptop", "ipon para sa laptop": a new goal.
  if (!opening && _has(text, _saveFor)) {
    return command(VoiceCommandType.goal, name: nameAfter());
  }
  if (_has(text, _goalWords)) {
    // "Add 500 to my laptop goal" puts money in a goal, which is done on
    // the goal's own page.
    final intoGoal =
        amount != null &&
        !_has(text, r'new|create|bagong|bago|gumawa|gawa') &&
        _has(text, r'(to|into|sa|para sa)( \w+){0,3} (goal|goals|layunin)');
    if (wantsForm && !intoGoal) {
      return command(VoiceCommandType.goal, name: nameAfter());
    }
    return open(VoiceDestination.goals);
  }

  // "Ipon 500", "add 500 to savings": money moved into savings.
  if (_has(text, _savingsWords) && amount != null && !opening) {
    return VoiceCommand(
      type: VoiceCommandType.transfer,
      expense: expense,
      toSavings: true,
    );
  }

  if (_has(text, _installmentWords)) {
    if (paying) return open(VoiceDestination.bills);
    return wantsForm
        ? command(VoiceCommandType.installment, name: nameAfter())
        : open(VoiceDestination.installments);
  }
  if (_has(text, _debtWords)) {
    if (paying) return open(VoiceDestination.bills);
    return wantsForm
        ? command(VoiceCommandType.debt, name: nameAfter())
        : open(VoiceDestination.debts);
  }

  if (_has(text, _billWords)) {
    if (spending || paying) return open(VoiceDestination.bills);
    return wantsForm
        ? command(VoiceCommandType.bill, name: nameAfter())
        : open(VoiceDestination.bills);
  }

  if (_has(text, _walletWords) && adding && !opening) {
    return command(VoiceCommandType.wallet, name: nameAfter());
  }

  final source = _incomeSourceFor(text);
  final isIncome =
      !spending &&
      (_has(text, _incomeWords) ||
          (source != null && _has(text, _incomeVerbs)));
  if (isIncome && (!opening || amount != null)) {
    return command(
      VoiceCommandType.income,
      incomeSource: source ?? otherIncomeSource,
    );
  }

  final destination = _destinationFor(text);
  if (destination != null && (opening || amount == null)) {
    return open(destination);
  }

  return command(VoiceCommandType.expense);
}

/// The wallet among [wallets] that [spoken] names: by its name, or by what
/// it is, as "cash", "bangko" or "savings" when there is only one of those.
/// Null when none, or more than one, fits.
Wallet? matchSpokenWallet(String? spoken, Iterable<Wallet> wallets) {
  if (spoken == null) return null;
  final said = _letters(spoken);
  if (said.isEmpty) return null;
  final open = wallets.where((wallet) => !wallet.archived).toList();

  Wallet? only(bool Function(Wallet wallet) test) {
    final found = open.where(test).toList();
    return found.length == 1 ? found.single : null;
  }

  final byName = only((wallet) {
    final name = _letters(wallet.name);
    return name == said ||
        (said.length >= 3 && name.startsWith(said)) ||
        (name.length >= 3 && said.startsWith(name));
  });
  if (byName != null) return byName;

  if (RegExp(r'^(cash|cashonhand|pera|perako|cashko)$').hasMatch(said)) {
    return only(
      (wallet) => wallet.type == WalletType.cash && !wallet.isSetAside,
    );
  }
  if (RegExp(r'^(bank|bangko|cashinbank|bankko|bangkoko)$').hasMatch(said)) {
    return only(
      (wallet) => wallet.type == WalletType.bank && !wallet.isSetAside,
    );
  }
  if (RegExp(r'^(savings?|ipon|naipon)$').hasMatch(said)) {
    return savingsWalletOf(open);
  }
  return null;
}

/// The one savings account money can go into, or null with none or more
/// than one, so the user picks.
Wallet? savingsWalletOf(Iterable<Wallet> wallets) {
  final accounts = wallets
      .where(
        (wallet) =>
            !wallet.archived &&
            wallet.purpose == WalletPurpose.savings &&
            !wallet.isLockedSavings,
      )
      .toList();
  return accounts.length == 1 ? accounts.single : null;
}

// --------------------------------------------------------------- the words

const _addVerbs =
    r'add|new|create|make|record|log|set up|setup|start|'
    r'magdagdag|dagdag|dagdagan|idagdag|mag add|iadd|gumawa|gawa|gawan|'
    r'gagawa|bago|bagong|maglagay|lagay|ilagay|itala|magtala|mag record|'
    r'irecord|i record';

const _openVerbs =
    r'open|show|view|go|go to|goto|navigate|visit|switch|take me|see|check|'
    r'launch|display|buksan|ibukas|pabukas|pumunta|punta|puntahan|ipakita|'
    r'pakita|ipakita mo|tingnan|tignan|patingin|makita|silipin|dalhin';

const _spendVerbs =
    r'spent|spend|paid|bought|buy|gastos|gumastos|nagastos|ginastos|'
    r'bumili|binili|nagbayad|binayaran|bayad';

const _payVerbs =
    r'pay|paid|paying|bayad|magbayad|nagbayad|binayaran|bayaran|babayaran|'
    r'naghulog|maghulog|ihulog|naghuhulog|maghuhulog';

const _moveVerbs =
    r'transfer|move|moved|ilipat|lipat|maglipat|inilipat|nilipat|'
    r'mag transfer|itransfer|i transfer|nagtransfer';

const _scan = r'scan|iscan|i scan|mag scan|magscan';
const _receipt = r'receipt|receipts|resibo';

const _saveFor =
    r'save for|saving for|save up for|mag ipon para sa|ipon para sa|'
    r'iipon para sa|magiipon para sa|mag iipon para sa';

const _goalWords = r'goal|goals|layunin|pangarap';
const _savingsWords =
    r'savings|saving|ipon|naipon|iipon|mag ipon|magipon|impok|mag impok|'
    r'itabi|magtabi|set aside|ipunin';
const _installmentWords =
    r'installment|installments|instalment|instalments|hulugan|hulog|'
    r'hinuhulugan|hinulugan|inhulugan|hulugang|naghulog|maghulog|ihulog|'
    r'naghuhulog|maghuhulog';
const _debtWords =
    r'debt|debts|loan|loans|utang|utangan|nangutang|umutang|inutang|'
    r'humiram|hiniram|borrowed|borrow|mangutang|uutang';
const _billWords = r'bill|bills|bayarin|bill planner|bill calendar';
const _walletWords =
    r'wallet|wallets|pitaka|e wallet|ewallet|bank account|account';

const _incomeWords =
    r'income|salary|sweldo|suweldo|sahod|paycheck|payday|wage|wages|arawan|'
    r'allowance|baon|scholarship|freelance|sideline|raket|kinita|kumita|'
    r'inflow|got paid|received|natanggap|nakatanggap|tumanggap|earned';
const _incomeVerbs =
    r'received|receive|earned|earn|natanggap|nakatanggap|tumanggap|'
    r'binigyan|nabigyan|sold|nabenta|naibenta|nagbenta|binenta|benta|'
    r'got paid|nakakuha';

/// "12 months", "12 na buwan", "12 payments", "12 gives", "12 hulog".
final _paymentCount = RegExp(
  r'\b(\d{1,3})\s*(?:na\s+)?(?:months?|monthly payments?|payments?|gives|'
  r'buwan|hulog|hulugan|beses|times|weeks?|linggo|installments?)\b',
  caseSensitive: false,
);

/// The amount is each payment: "1,500 a month", "kada buwan", "monthly".
final _perPayment = RegExp(
  r'\b(a|per|each|every|kada|bawat|tuwing|isang) (month|buwan|week|linggo|'
  r'payday|sahod|kinsenas|katapusan)\b|\b(monthly|buwanan|buwan buwan|'
  r'weekly|lingguhan|kada kinsenas)\b',
);

bool _has(String text, String words) =>
    RegExp('\\b(?:$words)\\b').hasMatch(text);

/// Lowercase words with single spaces: no punctuation, and "mag-ipon" as
/// "mag ipon".
String _normalize(String words) => words
    .toLowerCase()
    .replaceAll(RegExp(r"[’'`]"), '')
    .replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _letters(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'\b(wallet|account|ko)\b'), '')
    .replaceAll(RegExp('[^a-z0-9]'), '');

String? _incomeSourceFor(String words) {
  // Pay by the day or the hour is a wage; checked first, so "daily wage"
  // is never read as a salary.
  if (_has(words, r'wage|wages|arawan|daily pay|daily rate')) return 'Wage';
  if (_has(words, r'salary|paycheck|payday|sweldo|suweldo|sahod')) {
    return 'Salary';
  }
  if (_has(words, r'allowance|allowances|baon')) return 'Allowance';
  if (_has(words, r'part time job|part time|parttime')) {
    return 'Part-time Job';
  }
  if (_has(words, r'business|negosyo|tindahan|paninda')) return 'Business';
  if (_has(words, r'freelance|freelancing|sideline|raket|commission')) {
    return 'Freelance';
  }
  if (_has(words, r'scholarship|iskolarship')) return 'Scholarship';
  if (_has(words, r'gift|regalo|pamasko|aguinaldo|bigay')) return 'Gift';
  if (_has(words, r'refund|ibinalik|binalik|sukli')) return 'Refund';
  if (_has(
    words,
    r'sold something|sold|sale|nabenta|naibenta|nagbenta|binenta|benta',
  )) {
    return 'Sold Something';
  }
  if (_has(words, r'interest|tubo')) return 'Interest';
  return null;
}

VoiceDestination? _destinationFor(String words) {
  const destinations = <VoiceDestination, String>{
    VoiceDestination.home: r'home|dashboard|bahay|simula',
    VoiceDestination.transactions:
        r'transactions|transaction|transaction history|history|expenses|'
        r'mga gastos|gastos ko|talaan|kasaysayan',
    VoiceDestination.bills: _billWords,
    VoiceDestination.wallet: r'wallets|wallet|pitaka|accounts|account',
    VoiceDestination.savings: _savingsWords,
    VoiceDestination.installments: _installmentWords,
    VoiceDestination.debts: _debtWords,
    VoiceDestination.goals: _goalWords,
    VoiceDestination.reports: r'reports|report|ulat|summary|buod|chart|charts',
    VoiceDestination.settings: r'settings|setting|profile|setup|ayos|ayusin',
    VoiceDestination.scanReceipt:
        r'scan receipt|scan a receipt|receipt scanner|receipt scan|'
        r'scan resibo|iscan ang resibo',
    VoiceDestination.assistant:
        r'assistant|ai assistant|ai|chatbot|chat bot|fin|katulong',
    VoiceDestination.expenseCategories:
        r'expense categories|manage categories|categories|category|'
        r'mga kategorya|kategorya',
    VoiceDestination.payCycleHistory:
        r'pay cycle history|paycheck history|pay period history|cash inflows|'
        r'inflows|income|kita|sweldo|sahod',
    VoiceDestination.reminders: r'reminders|reminder|notifications|paalala',
    VoiceDestination.help: r'help|support|tulong',
  };
  for (final entry in destinations.entries) {
    if (_has(words, entry.value)) return entry.key;
  }
  return null;
}

// ------------------------------------------------------------- the details

/// The wallets a transfer is from and to, as said: "from GCash to BDO",
/// "mula sa GCash papunta sa BDO", "ilipat ang 500 sa BDO".
(String?, String?) _walletsIn(String text) {
  final clean = text
      .replaceAll(RegExp(r'\b\d+(?:\s?k)?\b'), ' ')
      .replaceAll(RegExp(r'\b(pesos?|piso|php)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const fromWords = r'from|mula sa|mula|galing sa|galing';
  const toWords = r'to|into|papunta sa|papuntang|papunta|patungo sa|patungong';
  final from = RegExp(
    '\\b(?:$fromWords) (.+?)(?= (?:$toWords|sa)\\b|\$)',
  ).firstMatch(clean)?.group(1);
  var to = RegExp(
    '\\b(?:$toWords) (.+?)(?= (?:$fromWords)\\b|\$)',
  ).firstMatch(clean)?.group(1);
  // Tagalog names where it goes with a plain "sa": "ilipat sa BDO".
  to ??= RegExp(
    '(?<!mula |galing )\\bsa (.+?)(?= (?:$fromWords)\\b|\$)',
  ).firstMatch(clean)?.group(1);
  return (_walletName(from), _walletName(to));
}

String? _walletName(String? said) {
  if (said == null) return null;
  final name = said
      .replaceAll(
        RegExp(r'\b(my|the|ang|aking|ko|po|na|wallet|account|please)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return name.isEmpty ? null : _tidyName(name);
}

/// Words that start a command or join one, never part of what something is
/// called.
const _notName = {
  // English
  'add', 'new', 'create', 'make', 'record', 'log', 'set', 'up', 'setup',
  'start', 'a', 'an', 'the', 'my', 'for', 'to', 'of', 'in', 'on', 'at',
  'from', 'with', 'and', 'please', 'i', 'me', 'want', 'would', 'like',
  'need', 'called', 'named', 'is', 'it', 'that', 'this', 'save', 'saving',
  'savings', 'every', 'each', 'per', 'month', 'months', 'monthly', 'week',
  'weeks', 'weekly', 'year', 'yearly', 'payment', 'payments', 'pesos',
  'peso', 'php', 'piso', 'worth', 'amount', 'target', 'bill', 'bills',
  'goal', 'goals', 'installment', 'installments', 'instalment',
  'instalments', 'debt', 'debts', 'loan', 'loans', 'borrowed', 'borrow',
  'wallet', 'wallets', 'account', 'owe', 'gives', 'times', 'due', 'about',
  // Tagalog
  'magdagdag', 'dagdag', 'idagdag', 'dagdagan', 'mag', 'gumawa', 'gawa',
  'gawan', 'gagawa', 'bago', 'bagong', 'lagay', 'maglagay', 'ilagay',
  'itala', 'magtala', 'ng', 'na', 'sa', 'kay', 'ni', 'para', 'ang', 'mga',
  'ko', 'ako', 'akong', 'aking', 'ka', 'mo', 'po', 'lang', 'yung', 'iyong',
  'nang', 'may', 'meron', 'mayroon', 'utang', 'nangutang', 'umutang',
  'inutang', 'humiram', 'hiniram', 'mangutang', 'hulugan', 'hulog',
  'hulugang', 'bayarin', 'bayad', 'layunin', 'pangarap', 'pitaka', 'ipon',
  'iipon', 'magipon', 'kada', 'tuwing', 'bawat', 'buwan', 'buwanan',
  'linggo', 'lingguhan', 'taon', 'beses', 'gusto', 'kong', 'pa', 'din',
  'rin', 'naman', 'tapos', 'isang', 'halaga', 'nagkakahalaga',
  'iadd', 'irecord',
};

/// What the bill, goal, installment, debt or wallet is called: what was
/// said, less the command words and the amount. Null when nothing is left.
String? _nameFrom(String spoken) {
  final words = spoken
      .replaceAll(RegExp(r'₱\s?[\d,.]+|\b[\d,.]+\s?k?\b'), ' ')
      // "Mag-ipon" is two words to drop; "Pag-IBIG" is put back together.
      .split(RegExp(r'[\s,.!?-]+'))
      .map((word) => word.replaceAll(RegExp(r"^[^\wñÑ]+|[^\wñÑ]+$"), ''))
      .where((word) => word.isNotEmpty)
      .where((word) => !_notName.contains(word.toLowerCase()))
      .toList();
  if (words.isEmpty) return null;
  return _tidyName(words.join(' '));
}

/// Capitalized, with the names people say in lowercase written properly.
String _tidyName(String name) {
  const proper = {
    'sss': 'SSS',
    'gsis': 'GSIS',
    'bdo': 'BDO',
    'bpi': 'BPI',
    'pnb': 'PNB',
    'rcbc': 'RCBC',
    'gcash': 'GCash',
    'g cash': 'GCash',
    'pag ibig': 'Pag-IBIG',
    'pag-ibig': 'Pag-IBIG',
    'pagibig': 'Pag-IBIG',
    'meralco': 'Meralco',
    'pldt': 'PLDT',
    'maya': 'Maya',
  };
  var tidy = name;
  proper.forEach((said, written) {
    tidy = tidy.replaceAll(
      RegExp('\\b${RegExp.escape(said)}\\b', caseSensitive: false),
      written,
    );
  });
  return tidy[0].toUpperCase() + tidy.substring(1);
}

// ----------------------------------------------------------------- numbers

/// Amounts said as words, written as digits: "limandaan" as 500, "isang
/// libo't dalawang daan" as 1200, "two hundred fifty" as 250.
///
/// A small number on its own, as in "isang kape", stays a word: only one
/// with hundreds or thousands in it, one of twenty or more, or one followed
/// by "pesos" is taken as an amount.
String spokenNumbersToDigits(String text) {
  final tokens = RegExp(r"[A-Za-zÑñ'’]+|\d+").allMatches(text).toList();
  final out = StringBuffer();
  var copied = 0;
  var i = 0;
  while (i < tokens.length) {
    final run = _numberRun(text, tokens, i);
    if (run == null) {
      i++;
      continue;
    }
    out
      ..write(text.substring(copied, tokens[i].start))
      ..write(run.value);
    copied = tokens[run.end - 1].end;
    i = run.end;
  }
  out.write(text.substring(copied));
  return out.toString();
}

const _units = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
  'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
  'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
  'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60,
  'seventy': 70, 'eighty': 80, 'ninety': 90,
  'isa': 1, 'isang': 1, 'dalawa': 2, 'dalawang': 2, 'tatlo': 3,
  'tatlong': 3, 'apat': 4, 'lima': 5, 'limang': 5, 'anim': 6, 'pito': 7,
  'pitong': 7, 'walo': 8, 'walong': 8, 'siyam': 9, 'sampu': 10,
  'sampung': 10, 'labing': 10, 'labin': 10,
  'dalawampu': 20, 'tatlumpu': 30, 'apatnapu': 40, 'limampu': 50,
  'animnapu': 60, 'pitumpu': 70, 'walumpu': 80, 'siyamnapu': 90,
  // Said the Spanish way, as prices often are.
  'singko': 5, 'diyes': 10, 'dyes': 10, 'onse': 11, 'dose': 12,
  'trese': 13, 'katorse': 14, 'kinse': 15, 'bente': 20, 'beinte': 20,
  'trenta': 30, 'treinta': 30, 'kwarenta': 40, 'kuwarenta': 40,
  'singkwenta': 50, 'sinkwenta': 50, 'sisenta': 60, 'setenta': 70,
  'otsenta': 80, 'nobenta': 90,
};

const _hundreds = {'hundred', 'daan', 'raan', 'siyento', 'syento'};
const _thousands = {'thousand': 1000, 'libo': 1000, 'mil': 1000};
const _millions = {'million', 'milyon'};
const _joins = {'and', 'at', 'y', 'na', 'ng'};
const _currency = {'pesos', 'peso', 'piso', 'php'};

/// What one spoken word is worth, as a number or a multiplier.
({int value, int times})? _wordValue(String word) {
  if (_units[word] case final unit?) return (value: unit, times: 1);
  if (_hundreds.contains(word)) return (value: 0, times: 100);
  if (_thousands[word] case final thousand?) return (value: 0, times: thousand);
  if (_millions.contains(word)) return (value: 0, times: 1000000);
  // "dalawampung", "limampu't", "libo't".
  for (final ending in const ['ng', 't', 'g']) {
    if (word.length > ending.length + 2 && word.endsWith(ending)) {
      final stem = word.substring(0, word.length - ending.length);
      if (_units[stem] case final unit? when unit >= 10) {
        return (value: unit, times: 1);
      }
      if (_thousands.containsKey(stem)) return (value: 0, times: 1000);
    }
  }
  // "labindalawa", "labingisa": ten and one more word.
  for (final start in const ['labing', 'labin']) {
    if (word.startsWith(start) && word.length > start.length) {
      final rest = _units[word.substring(start.length)];
      if (rest != null && rest < 10) return (value: 10 + rest, times: 1);
    }
  }
  // "limandaan", "apatnaraan", "sanlibo": a number and its hundreds or
  // thousands said as one word.
  for (final (ending, times) in const [
    ('daan', 100),
    ('raan', 100),
    ('libo', 1000),
  ]) {
    if (!word.endsWith(ending) || word.length == ending.length) continue;
    var stem = word.substring(0, word.length - ending.length);
    if (stem == 'san' || stem == 'sang') return (value: times, times: 1);
    for (final link in const ['na', 'ng', 'n']) {
      if (_units[stem] != null) break;
      if (stem.endsWith(link)) {
        stem = stem.substring(0, stem.length - link.length);
      }
    }
    if (_units[stem] case final unit? when unit < 10) {
      return (value: unit * times, times: 1);
    }
  }
  return null;
}

/// The number said from token [start] on, and the token after it, or null
/// when no amount starts there.
({int value, int end})? _numberRun(
  String text,
  List<RegExpMatch> tokens,
  int start,
) {
  var total = 0;
  var group = 0;
  var bigWord = false;
  var lastNumber = -1;
  for (var i = start; i < tokens.length; i++) {
    if (i > start) {
      final gap = text.substring(tokens[i - 1].end, tokens[i].start);
      if (!RegExp(r'^[\s-]*$').hasMatch(gap)) break;
    }
    final word = tokens[i][0]!.toLowerCase().replaceAll(RegExp("['’]"), '');
    final digits = int.tryParse(word);
    if (digits != null) {
      // Only as in "2 libo", a digit said with its thousands.
      final next = i + 1 < tokens.length
          ? _wordValue(tokens[i + 1][0]!.toLowerCase())
          : null;
      if (next == null || next.times == 1 || lastNumber >= 0) break;
      group += digits;
      lastNumber = i;
      continue;
    }
    if (_joins.contains(word)) {
      if (lastNumber < 0) break;
      continue;
    }
    final value = _wordValue(word);
    if (value == null) break;
    if (value.times == 1) {
      group += value.value;
    } else if (value.times == 100) {
      group = (group == 0 ? 1 : group) * 100;
      bigWord = true;
    } else {
      total += (group == 0 ? 1 : group) * value.times;
      group = 0;
      bigWord = true;
    }
    lastNumber = i;
  }
  if (lastNumber < 0) return null;
  final value = total + group;
  final end = lastNumber + 1;
  final nextWord = end < tokens.length ? tokens[end][0]!.toLowerCase() : '';
  if (value <= 0 || !(bigWord || value >= 20 || _currency.contains(nextWord))) {
    return null;
  }
  return (value: value, end: end);
}
