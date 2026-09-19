import '../utils/category_keywords.dart';

/// What FinAssist can tell about an expense from words: what someone said or
/// typed, or the text on a receipt.
///
/// Every guess is rule-based, so it can always be explained, and the user
/// checks it on the expense form before anything is saved. This file is the
/// one place that guesses: a trained model can later take over the category
/// guess here without any screen changing.
class ExpenseGuess {
  const ExpenseGuess({this.amount, this.category, this.description, this.date});

  final double? amount;
  final String? category;
  final String? description;

  /// The date printed on a receipt, when there is a believable one.
  final DateTime? date;

  /// Whether anything worth filling in was found.
  bool get foundSomething => amount != null || category != null;
}

// ------------------------------------------------------------- categories

/// The category [text] points to, out of [from] (the categories the user
/// hasn't hidden), or null when nothing matches or two categories tie.
///
/// An occasion, like a date, decides only when nothing names what was paid
/// for.
String? suggestCategory(String text, {required Iterable<String> from}) {
  final allowed = from.toSet();
  final scores = _categoryScores(text, allowed);
  if (scores.isNotEmpty) return _best(scores);
  return _best(_categoryScores(text, allowed, keywords: occasionKeywords));
}

/// How strongly [text] points to each category: the number of words matched.
/// A longer phrase wins over a shorter one inside it, so "grab food" counts
/// for Food and not also for Transportation.
Map<String, int> _categoryScores(
  String text,
  Set<String> from, {
  Map<String, List<String>> keywords = categoryKeywords,
}) {
  final words = _words(text);
  if (words.isEmpty) return <String, int>{};

  final matches = <({int start, int end, String category})>[];
  for (final entry in keywords.entries) {
    if (!from.contains(entry.key)) continue;
    for (final keyword in entry.value) {
      final phrase = _words(keyword);
      if (phrase.isEmpty) continue;
      for (var i = 0; i + phrase.length <= words.length; i++) {
        var same = true;
        for (var j = 0; j < phrase.length && same; j++) {
          same = _sameWord(words[i + j], phrase[j]);
        }
        if (same) {
          matches.add((start: i, end: i + phrase.length, category: entry.key));
        }
      }
    }
  }

  matches.sort((a, b) => (b.end - b.start).compareTo(a.end - a.start));
  final taken = List<bool>.filled(words.length, false);
  final kept = <({int start, int end, String category})>[];
  for (final match in matches) {
    var free = true;
    for (var i = match.start; i < match.end && free; i++) {
      free = !taken[i];
    }
    if (!free) continue;
    for (var i = match.start; i < match.end; i++) {
      taken[i] = true;
    }
    kept.add(match);
  }

  // In "Grab papunta sa school", the ride is what was paid for; the school is
  // only where it went. With a ride in the text, places gone to don't count.
  bool isDestination(int start) =>
      (start > 0 && _towards.contains(words[start - 1])) ||
      (start > 1 && _towards.contains(words[start - 2]));
  final hasRide = kept.any(
    (m) => m.category == 'Transportation' && !isDestination(m.start),
  );

  final scores = <String, int>{};
  for (final match in kept) {
    if (hasRide &&
        match.category != 'Transportation' &&
        isDestination(match.start)) {
      continue;
    }
    scores[match.category] =
        (scores[match.category] ?? 0) + (match.end - match.start);
  }
  return scores;
}

/// A word matches a listed word, or its plural: "burgers" for "burger",
/// "buses" for "bus".
bool _sameWord(String word, String listed) =>
    word == listed || word == '${listed}s' || word == '${listed}es';

/// Words before a place someone went to.
const _towards = {'to', 'papunta', 'pauwi', 'punta', 'galing', 'from'};

String? _best(Map<String, int> scores) {
  if (scores.isEmpty) return null;
  final ranked = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  // A tie is a coin toss, so no suggestion rather than a wrong one.
  if (ranked.length > 1 && ranked[0].value == ranked[1].value) return null;
  return ranked.first.key;
}

/// Lowercase words, with apostrophes dropped and other punctuation as spaces.
List<String> _words(String text) => text
    .toLowerCase()
    .replaceAll(RegExp("[’'`]"), '')
    .split(RegExp('[^a-z0-9ñ]+'))
    .where((word) => word.isNotEmpty)
    .toList();

// ----------------------------------------------------------------- amounts

/// A number in some text, and whether it was marked as money.
class _Number {
  const _Number(this.value, this.start, this.end, {required this.isMoney});

  final double value;
  final int start;
  final int end;
  final bool isMoney;
}

final _number = RegExp(
  // ₱150, P150, php 150 … or a number standing on its own: not part of a
  // word, so "PS5" and "S24" hold no amount.
  r'(?:(₱|(?<![a-z])php|(?<![a-z])p)\s?|(?<![a-z\d.,]))'
  // 150, 1,500, 150.50 …
  r'(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(?![\d%])'
  // … 1.5k
  r'(?:\s?(k)(?![a-z]))?'
  // … 150 pesos, 150 piso, 150 php
  r'(?:\s?(pesos?|piso|php)(?![a-z]))?',
  caseSensitive: false,
);

final _clockTime = RegExp(r'\b\d{1,2}:\d{2}\b');

List<_Number> _numbersIn(String text) {
  // A time of day isn't an amount; blank it out without moving anything.
  final clean = text.replaceAllMapped(
    _clockTime,
    (match) => ' ' * match[0]!.length,
  );

  return [
    for (final match in _number.allMatches(clean))
      // A unit straight after, as in "500mg" or "16GB", means it isn't money.
      if (match.end >= clean.length ||
          !RegExp('[a-z]', caseSensitive: false).hasMatch(clean[match.end]))
        if (_valueOf(match) case final value? when value > 0)
          _Number(
            value,
            match.start,
            match.end,
            isMoney: match[1] != null || match[5] != null,
          ),
  ];
}

double? _valueOf(RegExpMatch match) {
  final whole = double.tryParse(match[2]!.replaceAll(',', ''));
  if (whole == null) return null;
  final cents = match[3] == null ? 0 : double.parse('0.${match[3]}');
  final value = whole + cents;
  return match[4] == null ? value : value * 1000;
}

/// The amount in what someone said or typed: one said as money ("₱150",
/// "150 pesos") wins, otherwise the largest number.
_Number? _spokenAmount(String text) {
  final numbers = _numbersIn(text);
  if (numbers.isEmpty) return null;
  final money = numbers.where((n) => n.isMoney).toList();
  final pool = money.isNotEmpty ? money : numbers;
  return pool.reduce((a, b) => b.value > a.value ? b : a);
}

/// The amount in [text], where it sits so it can be taken out of the text,
/// and whether it was said as money. Used by the assistant to read a price
/// from a question.
({double value, int start, int end, bool isMoney})? findAmount(String text) {
  final number = _spokenAmount(text);
  return number == null
      ? null
      : (
          value: number.value,
          start: number.start,
          end: number.end,
          isMoney: number.isMoney,
        );
}

// ------------------------------------------------------------------ speech

/// What was said, such as "lunch at Jollibee 150 pesos": the amount, the
/// category, and a description without the amount ("Lunch at Jollibee").
/// The description is null when only an amount was said.
ExpenseGuess guessFromSpeech(
  String words, {
  required Iterable<String> categories,
}) {
  final amount = _spokenAmount(words);
  final rest = amount == null
      ? words
      : words.replaceRange(amount.start, amount.end, ' ');

  return ExpenseGuess(
    amount: amount?.value,
    category: suggestCategory(words, from: categories),
    description: _describe(rest),
  );
}

const _openers = [
  'i spent',
  'i paid',
  'i bought',
  'spent',
  'paid',
  'bought',
  'gumastos ako ng',
  'bumili ako ng',
  'bumili ng',
  'nagbayad ako ng',
  'nagbayad ng',
];

const _joiners = {
  'for',
  'on',
  'at',
  'of',
  'worth',
  'with',
  'and',
  'around',
  'about',
  'na',
  'ng',
  'sa',
  'para',
  'yung',
  'ang',
  'mga',
  'po',
  'lang',
};

/// What is left once the amount is taken out, tidied: no "I spent" at the
/// start, and no dangling "for" or "na" at either end. Null if nothing is left.
String? _describe(String text) {
  var words = text
      .split(RegExp(r'\s+'))
      .map((word) => word.replaceAll(RegExp(r'^[^\w₱]+|[^\w]+$'), ''))
      .where((word) => word.isNotEmpty)
      .toList();

  final start = words.join(' ').toLowerCase();
  for (final opener in _openers) {
    if (start == opener || start.startsWith('$opener ')) {
      words = words.sublist(opener.split(' ').length);
      break;
    }
  }
  while (words.isNotEmpty && _joiners.contains(words.first.toLowerCase())) {
    words.removeAt(0);
  }
  while (words.isNotEmpty && _joiners.contains(words.last.toLowerCase())) {
    words.removeLast();
  }
  return words.isEmpty ? null : _capitalize(words.join(' '));
}

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

// ----------------------------------------------------------------- receipts

/// A receipt's text: the total, the store as the description, its category,
/// and the date printed on it.
ExpenseGuess guessFromReceipt(
  String text, {
  required Iterable<String> categories,
  DateTime? now,
}) {
  final lines = _receiptLines(text);
  final store = _storeName(lines);

  // The store's name says the most about what was bought, so it counts
  // extra on top of everything else printed. Headings and greetings, such as
  // "Thank you for shopping", aren't clues at all.
  final allowed = categories.toSet();
  final scores = _categoryScores(
    lines.where((line) => !_isHeading(line)).join(' '),
    allowed,
  );
  if (store != null) {
    _categoryScores(store, allowed).forEach((category, score) {
      scores[category] = (scores[category] ?? 0) + score * 2;
    });
  }

  return ExpenseGuess(
    amount: _receiptTotal(lines),
    category: _best(scores),
    description: store,
    date: _receiptDate(text, now ?? DateTime.now()),
  );
}

/// A receipt's lines, trimmed, without blank ones.
List<String> _receiptLines(String text) => text
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

/// Whether [text] has the line with the amount paid, as the end of a
/// receipt does.
bool hasReceiptTotal(String text) => _receiptTotal(_receiptLines(text)) != null;

/// Headings printed at the top of a receipt and not at the bottom.
const _topHeadings = [
  'official receipt',
  'sales invoice',
  'cash invoice',
  'charge invoice',
  'acknowledgement receipt',
  'welcome',
];

/// Whether [text] begins like the top of a receipt, with "Official Receipt"
/// or a similar heading in its first lines.
bool startsLikeReceiptTop(String text) {
  for (final line in _receiptLines(text).take(4)) {
    final words = ' ${_words(line).join(' ')} ';
    if (_topHeadings.any((heading) => words.contains(' $heading '))) {
      return true;
    }
  }
  return false;
}

/// Labels of the amount paid, strongest first.
const _totalLabels = [
  [
    'grand total',
    'total amount due',
    'amount due',
    'total due',
    'amount payable',
  ],
  ['total amount', 'net total', 'net amount', 'total'],
];

/// Lines that say "total" but aren't the amount paid.
final _notTheTotal = RegExp(
  r'\b(sub ?total|qty|quantity|items?|vatable|vat amount|vat exempt|'
  r'zero rated|discount|change|cash|tendered|savings|points)\b',
  caseSensitive: false,
);

/// The amount paid, from the total line. Never the cash handed over or the
/// change, and nothing at all when there is no total line, rather than a
/// guess.
double? _receiptTotal(List<String> lines) {
  for (final labels in _totalLabels) {
    double? found;
    for (var i = 0; i < lines.length; i++) {
      final words = ' ${_words(lines[i]).join(' ')} ';
      if (!labels.any((label) => words.contains(' $label '))) continue;
      if (_notTheTotal.hasMatch(lines[i])) continue;

      var numbers = _numbersIn(lines[i]);
      // Read as two lines: the label, then the amount on its own.
      if (numbers.isEmpty &&
          i + 1 < lines.length &&
          !RegExp(
            '[a-z]',
            caseSensitive: false,
          ).hasMatch(lines[i + 1].replaceAll(_number, ''))) {
        numbers = _numbersIn(lines[i + 1]);
      }
      // The last total printed wins, as receipts put the final one last.
      if (numbers.isNotEmpty) found = numbers.last.value;
    }
    if (found != null) return found;
  }
  return null;
}

/// The start of a heading or greeting printed on receipts. Such a line is
/// neither the store's name nor a clue to the category: "Thank you for
/// shopping" says nothing about what was bought.
const _receiptHeadings = [
  'official receipt',
  'sales invoice',
  'receipt',
  'invoice',
  'cash invoice',
  'charge invoice',
  'acknowledgement receipt',
  'this serves as',
  'this is not',
  'welcome',
  'thank you',
  'thanks',
  'salamat',
  'please come again',
];

bool _isHeading(String line) {
  final joined = _words(line).join(' ');
  return _receiptHeadings.any(
    (heading) => joined == heading || joined.startsWith('$heading '),
  );
}

/// The store's name: the first of the top lines that reads like a name, not
/// a heading, tax number or address line.
String? _storeName(List<String> lines) {
  for (final line in lines.take(4)) {
    final words = _words(line);
    final joined = words.join(' ');
    final letters = line.replaceAll(RegExp('[^A-Za-z]'), '').length;
    final digits = line.replaceAll(RegExp(r'[^\d]'), '').length;

    if (letters < 2 || digits > letters || line.length > 40) continue;
    if (_isHeading(line)) continue;
    // A line with a price is an item, as in the lower part of a long receipt.
    if (RegExp(r'\d\.\d{2}\b').hasMatch(line)) continue;
    if (RegExp(
      r'^(tin|vat|min|sn|s n|permit|acc|ptu|tel|mobile|cashier|customer|'
      r'member|terminal|date|time)\b',
    ).hasMatch(joined)) {
      continue;
    }
    return _titleCase(line);
  }
  return null;
}

/// The store's name when [text] begins with it, after any greeting, as a
/// whole receipt or its top part does. Null for a part that begins partway
/// down.
String? storeAtTop(String text) {
  final lines = _receiptLines(text).where((line) => !_isHeading(line));
  return lines.isEmpty ? null : _storeName([lines.first]);
}

/// "JOLLIBEE" reads as "Jollibee", but short capitals such as "SM" stay.
String _titleCase(String line) {
  return line
      .split(' ')
      .map((token) {
        final letters = token.replaceAll(RegExp('[^A-Za-z]'), '');
        if (letters.length <= 3 || letters != letters.toUpperCase()) {
          return token;
        }
        return token
            .split('-')
            .map(
              (part) => part.isEmpty
                  ? part
                  : part[0].toUpperCase() + part.substring(1).toLowerCase(),
            )
            .join('-');
      })
      .join(' ');
}

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// The date printed on a receipt. Numeric dates are read month first, as
/// Philippine receipts print them, unless that lands in the future. Only a
/// date in the past year is believed.
DateTime? _receiptDate(String text, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);

  DateTime? believable(int year, int month, int day) {
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month) return null;
    if (date.isAfter(today)) return null;
    if (today.difference(date).inDays > 366) return null;
    return date;
  }

  final lower = text.toLowerCase();
  final candidates = <({int at, DateTime date})>[];

  for (final m in RegExp(
    // A space either side of a slash is how the reader sometimes sees it.
    r'\b(\d{4}) ?[/-] ?(\d{1,2}) ?[/-] ?(\d{1,2})\b',
  ).allMatches(lower)) {
    final date = believable(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
    if (date != null) candidates.add((at: m.start, date: date));
  }
  for (final m in RegExp(
    r'\b(\d{1,2}) ?[/-] ?(\d{1,2}) ?[/-] ?(\d{2,4})\b',
  ).allMatches(lower)) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!), year = int.parse(m[3]!);
    final date = believable(year, a, b) ?? believable(year, b, a);
    if (date != null) candidates.add((at: m.start, date: date));
  }
  final month = '(${_months.join('|')})[a-z]*\\.?';
  for (final m in RegExp(
    '\\b$month\\s+(\\d{1,2}),?\\s+(\\d{4})\\b',
  ).allMatches(lower)) {
    final date = believable(
      int.parse(m[3]!),
      _months.indexOf(m[1]!) + 1,
      int.parse(m[2]!),
    );
    if (date != null) candidates.add((at: m.start, date: date));
  }
  for (final m in RegExp(
    '\\b(\\d{1,2})\\s+$month,?\\s+(\\d{4})\\b',
  ).allMatches(lower)) {
    final date = believable(
      int.parse(m[3]!),
      _months.indexOf(m[2]!) + 1,
      int.parse(m[1]!),
    );
    if (date != null) candidates.add((at: m.start, date: date));
  }

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => a.at.compareTo(b.at));
  return candidates.first.date;
}
