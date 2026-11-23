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

  /// Whether anything worth filling in was found. Others only says nothing
  /// was recognised, so it doesn't count.
  bool get foundSomething =>
      amount != null || (category != null && category != 'Others');
}

// ------------------------------------------------------------- categories

/// The category [text] points to, out of [from] (the categories the user
/// hasn't hidden). Others when it names something no category knows, and
/// null only when two categories tie, so the user picks between them, or
/// when there is nothing yet to go on.
///
/// An occasion, like a date, decides only when nothing names what was paid
/// for.
///
/// A name that means two things, like Bacoor's "yellow cab" multicab and
/// Yellow Cab Pizza, is decided by the words around it, then by [amount]:
/// a fare's price is the ride. Without either, the user picks.
String? suggestCategory(
  String text, {
  required Iterable<String> from,
  double? amount,
}) {
  final allowed = from.toSet();
  final scores = _categoryScores(text, allowed);
  if (scores.isNotEmpty) return _best(scores);
  final twoWay = _twoWayName(text);
  if (twoWay != null) {
    // Going somewhere is a ride, whatever it cost.
    final words = _words(text);
    final going = words.any(_towards.contains);
    final pick = going
        ? twoWay.fare
        : amount == null
        ? null
        : amount <= twoWay.over
        ? twoWay.fare
        : twoWay.meal;
    return pick != null && allowed.contains(pick) ? pick : null;
  }
  final occasions = _categoryScores(
    text,
    allowed,
    keywords: occasionKeywords,
    places: const {},
  );
  if (occasions.isNotEmpty) return _best(occasions);
  // A mall says where, not what: it decides only when nothing bought is
  // named, so "lunch at SM Megamall" is Food and "SM Megamall" alone is
  // Shopping.
  final places = _categoryScores(
    text,
    allowed,
    keywords: placeKeywords,
    places: const {},
  );
  if (places.isNotEmpty) return _best(places);

  // A word of three letters or more is something to go on; one or two are
  // only the start of typing, and an amount with "pesos" names nothing.
  final named = _words(text).any(
    (word) =>
        word.length >= 3 &&
        !_fillerWords.contains(word) &&
        !RegExp(r'^[0-9]+$').hasMatch(word),
  );
  return named && allowed.contains('Others') ? 'Others' : null;
}

/// The [twoWayNames] entry [text] says, if any.
({String fare, String meal, double over})? _twoWayName(String text) {
  final said = ' ${_words(text).join(' ')} ';
  for (final entry in twoWayNames.entries) {
    if (said.contains(' ${entry.key} ')) return entry.value;
  }
  return null;
}

/// Words said around an amount that name nothing bought.
const _fillerWords = {
  'peso',
  'pesos',
  'php',
  'piso',
  'bucks',
  'gastos',
  'gumastos',
  'spent',
  'spend',
  'paid',
  'pay',
  'bayad',
  'nagbayad',
  'binayaran',
  'bought',
  'buy',
  'bumili',
  'binili',
  'ako',
  'the',
  'for',
  'and',
  'yung',
  'worth',
  'total',
  'amount',
};

/// How strongly [text] points to each category: the number of words matched.
/// A longer phrase wins over a shorter one inside it, so "grab food" counts
/// for Food and not also for Transportation.
Map<String, int> _categoryScores(
  String text,
  Set<String> from, {
  Map<String, List<String>> keywords = categoryKeywords,
  // Places take their words in the same pass, so "Robinsons Magnolia" is
  // never read as the Magnolia food brand, but count for nothing here.
  Map<String, List<String>> places = placeKeywords,
}) {
  final words = _words(text);
  if (words.isEmpty) return <String, int>{};

  final matches = <({int start, int end, String category})>[];
  for (final entry in [
    ...keywords.entries,
    for (final place in places.entries) MapEntry('', place.value),
    MapEntry('', twoWayNames.keys.toList()),
  ]) {
    if (entry.key.isNotEmpty && !from.contains(entry.key)) continue;
    for (final keyword in entry.value) {
      final phrase = _words(keyword);
      if (phrase.isEmpty) continue;
      for (var i = 0; i + phrase.length <= words.length; i++) {
        var same = true;
        for (var j = 0; j < phrase.length && same; j++) {
          same = _sameWord(words[i + j], phrase[j]);
        }
        // A Tagalog verb said onto a one-word name: "nagpavet", "nagnetflix",
        // "magpagupit". Only an exact name left over counts, so words that
        // simply start the same way, like "pamasahe", never do.
        if (!same && phrase.length == 1) {
          same = _withoutVerbPrefix(
            words[i],
          ).any((rest) => _sameWord(rest, phrase.single));
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

  // In "ballpen for school", the ballpen is what was paid for; school is only
  // what it is for. With something bought named, what it is for doesn't
  // count.
  bool isPurpose(int start) =>
      (start > 0 && _forWords.contains(words[start - 1])) ||
      (start > 1 && words[start - 2] == 'para' && words[start - 1] == 'sa');
  final hasItem = kept.any((m) => !isPurpose(m.start));

  final scores = <String, int>{};
  for (final match in kept) {
    // A place only took its words; it names nothing bought.
    if (match.category.isEmpty) continue;
    if (hasRide &&
        match.category != 'Transportation' &&
        isDestination(match.start)) {
      continue;
    }
    if (hasItem && isPurpose(match.start)) continue;
    scores[match.category] =
        (scores[match.category] ?? 0) + (match.end - match.start);
  }
  return scores;
}

/// A word matches a listed word, or its plural: "burgers" for "burger",
/// "buses" for "bus".
bool _sameWord(String word, String listed) =>
    word == listed || word == '${listed}s' || word == '${listed}es';

/// [word] without a Tagalog verb prefix said onto it, longest first:
/// "nagpavet" gives "vet". Nothing shorter than three letters is left.
Iterable<String> _withoutVerbPrefix(String word) sync* {
  for (final prefix in const ['nagpa', 'magpa', 'ipina', 'nag', 'mag', 'pa']) {
    if (word.startsWith(prefix) && word.length - prefix.length >= 3) {
      yield word.substring(prefix.length);
    }
  }
}

/// Words before a place someone went to, with the "-ng" Tagalog joins:
/// "papuntang school".
const _towards = {
  'to',
  'papunta',
  'papuntang',
  'pauwi',
  'pauwing',
  'punta',
  'puntang',
  'patungo',
  'patungong',
  'galing',
  'from',
};

/// Words before what something is for.
const _forWords = {'for', 'pang', 'para'};

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
    category: suggestCategory(words, from: categories, amount: amount?.value),
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
    amount: _receiptAmount(lines),
    // A receipt nothing on it points anywhere is Others, as for typed text;
    // a tie still leaves the choice to the user.
    category: scores.isEmpty && allowed.contains('Others')
        ? 'Others'
        : _best(scores),
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
bool hasReceiptTotal(String text) => receiptTotal(text) != null;

/// The amount on [text]'s total line, or null when it has none. Only the
/// labeled total: a part of a long receipt without one has no total, even
/// though [guessFromReceipt] may still find the amount another way.
double? receiptTotal(String text) => _labeledTotal(_receiptLines(text))?.value;

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
  // "Sub-Total" and "VAT-Exempt" as some printers hyphenate them, and the
  // payment line, which is what was handed over.
  r'\b(sub[ -]?total|qty|quantity|items?|vatable|vat amount|vat[ -]exempt|'
  r'zero[ -]rated|discount|change|cash|tendered|savings|points|payments?)\b',
  caseSensitive: false,
);

/// Lines whose amounts are never what was paid for the goods: what was
/// handed over, the change, and the tax and discount parts of the total.
final _notThePrice = RegExp(
  r'\b(cash|change|tend\w*|savings|points|discount\w*|vat\w*|tax\w*|'
  r'qty|quantity|items?|payments?|balance)\b',
  caseSensitive: false,
);

/// An amount printed the way receipts print money, with two decimals:
/// found even when the reader runs it into a letter or a table's border,
/// as in "TOTAL245.00", "245.00V" or "|1,250.00|".
final _printedMoney = RegExp(
  r'(?<![\d.,])(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?!\d)',
);

/// A receipt line with the reader's usual slips in numbers put right:
/// "1, 250 .00" spaced out, the letter O for a zero inside a number, and
/// "245,00" with a comma for the decimal point.
String _cleanNumbers(String line) => line
    .replaceAllMapped(
      RegExp(r'(?<=\d)\s*([.,])\s*(?=\d)'),
      (match) => match[1]!,
    )
    .replaceAll(RegExp(r'(?<=[\d.,])[Oo]|[Oo](?=\d|[.,]\d)'), '0')
    .replaceAllMapped(
      RegExp(r'(\d),(\d{2})(?!\d)'),
      (match) => '${match[1]}.${match[2]}',
    );

/// The amount on one receipt line, and whether it was printed as money.
/// Printed money wins over a bare number, so a table border read as "1"
/// is never taken for the amount; of bare numbers the largest wins.
({double value, bool isMoney})? _lineAmount(String line) {
  final clean = _cleanNumbers(line);
  final money = _printedMoney.allMatches(clean).toList();
  if (money.isNotEmpty) {
    final last = money.last;
    return (
      value: double.parse('${last[1]!.replaceAll(',', '')}.${last[2]}'),
      isMoney: true,
    );
  }
  final numbers = _numbersIn(clean);
  if (numbers.isEmpty) return null;
  final largest = numbers.reduce((a, b) => b.value > a.value ? b : a);
  // Still written as money without decimals, as a handwritten "₱2,050":
  // with a peso sign, or with a thousands comma.
  return (
    value: largest.value,
    isMoney:
        largest.isMoney ||
        clean.substring(largest.start, largest.end).contains(','),
  );
}

/// Whether [line] holds nothing but an amount: a total's amount read as a
/// row of its own, away from its label.
bool _onlyAnAmount(String line) {
  final rest = _cleanNumbers(line)
      .replaceAll(_printedMoney, ' ')
      .replaceAll(_number, ' ')
      .replaceAll(RegExp(r'\b(php|p)\b', caseSensitive: false), ' ')
      // A VAT code printed after the amount (V, T, X, Z, E), or a table's
      // border read as a letter.
      .replaceAll(RegExp(r'\b[vtxzeli]\b', caseSensitive: false), ' ');
  return !RegExp('[a-z]', caseSensitive: false).hasMatch(rest) &&
      _lineAmount(line) != null;
}

/// A line's words as a label reads, with the reader's slips in letters put
/// right: "T0TAL" and "TOTAI" are "total", and "T O T A L", printed wide,
/// is one word.
List<String> _labelWords(String line) {
  final words = <String>[];
  var letters = <String>[];
  void flush() {
    if (letters.length >= 3) {
      words.add(letters.join());
    } else {
      words.addAll(letters);
    }
    letters = [];
  }

  // "TOTAL245.00" run together: the label first, its digits after.
  final split = [
    for (final raw in _words(line))
      if (RegExp(r'^(.*[a-z])(\d+)$').firstMatch(raw) case final m?) ...[
        m[1]!,
        m[2]!,
      ] else
        raw,
  ];
  for (final raw in split) {
    final word = RegExp('[a-z]').hasMatch(raw)
        ? raw.replaceAll('0', 'o').replaceAll('1', 'l')
        : raw;
    if (word.length == 1 && RegExp('[a-z]').hasMatch(word)) {
      letters.add(word);
      continue;
    }
    flush();
    words.add(RegExp(r'^tota[il]$').hasMatch(word) ? 'total' : word);
  }
  flush();
  return words;
}

/// The amount paid, from the total line: on the label's own row, or on the
/// row just after or before it when the reader split them. Never the cash
/// handed over or the change.
({double value, bool isMoney})? _labeledTotal(List<String> lines) {
  for (final labels in _totalLabels) {
    ({double value, bool isMoney})? found;
    for (var i = 0; i < lines.length; i++) {
      // A table's columns can share one row, as "VAT Amount  219.64  TOTAL
      // AMOUNT DUE  2,050", the cells two spaces apart. Each cell is read
      // on its own, so the VAT beside the total neither hides it nor is
      // taken for it.
      final cells = lines[i].split(RegExp(r'\s{2,}'));
      for (var c = 0; c < cells.length; c++) {
        final words = ' ${_labelWords(cells[c]).join(' ')} ';
        if (!labels.any((label) => words.contains(' $label '))) continue;
        if (_notTheTotal.hasMatch(cells[c])) continue;

        final last = c == cells.length - 1;
        // The amount cells straight after the label, together, so a table
        // border read as "1" beside the amount loses to the amount.
        final after = [
          for (final cell in cells.skip(c + 1))
            if (_onlyAnAmount(cell)) cell else '\n',
        ].join('  ').split('\n').first;
        final amount =
            _lineAmount(cells[c]) ??
            (after.trim().isEmpty ? null : _lineAmount(after)) ??
            // Read as rows of their own: the amount just after the label,
            // or just before it on a tilted photo.
            (last && i + 1 < lines.length && _onlyAnAmount(lines[i + 1])
                ? _lineAmount(lines[i + 1])
                : null) ??
            (last && i > 0 && _onlyAnAmount(lines[i - 1])
                ? _lineAmount(lines[i - 1])
                : null);
        // The last total printed wins, as receipts put the final one last.
        if (amount != null) found = amount;
      }
    }
    if (found != null) return found;
  }
  return null;
}

/// The amount to fill in from a receipt: its total line when that reads
/// cleanly. When there is none, or its amount came out garbled on a
/// receipt that prints money with decimals, the largest price on it,
/// leaving out the cash handed over, the change, tax and discounts. The
/// user checks it before saving.
double? _receiptAmount(List<String> lines) {
  final labeled = _labeledTotal(lines);
  final prices = [
    for (final line in lines)
      if (!_notThePrice.hasMatch(line))
        if (_lineAmount(line) case final amount? when amount.isMoney)
          amount.value,
  ];
  if (labeled != null && (labeled.isMoney || prices.isEmpty)) {
    return labeled.value;
  }
  if (prices.isEmpty) return null;

  // The largest price is only the total when something backs it: printed
  // twice, as a subtotal or the card or GCash line repeats it, or the
  // prices above it adding up to it. Otherwise it is just the dearest item,
  // and the amount is left for the user to type.
  int cents(double value) => (value * 100).round();
  final largest = prices.reduce((a, b) => b > a ? b : a);
  final first = prices.indexWhere((price) => cents(price) == cents(largest));
  final repeated =
      prices.where((price) => cents(price) == cents(largest)).length > 1;
  final above = prices.take(first).fold<double>(0, (sum, p) => sum + p);
  return repeated || (first > 0 && cents(above) == cents(largest))
      ? largest
      : null;
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
