part of 'chat_answers.dart';

// Answers about big purchases: how long saving takes at the user's own
// pace, houses and lots with a home loan, and gold by its weight. The math
// is in big_purchase.dart; the public prices come from the web scraper.

enum _BigKind { home, land, gold }

/// Houses and condos, lots, or gold, from what is being bought.
_BigKind? _bigKindOf(String item) {
  final text = ' ${_plain(item)} ';
  if (_has(text, [
    'house',
    'houses',
    'home',
    'bahay',
    'condo',
    'condominium',
    'townhouse',
    'house and lot',
    'property',
  ])) {
    return _BigKind.home;
  }
  if (_has(text, ['lot', 'lote', 'lupa', 'land', 'farm lot'])) {
    return _BigKind.land;
  }
  if (_has(text, ['gold', 'ginto', 'alahas', 'jewelry', 'jewellery']) ||
      (_jewelryWord.hasMatch(item) &&
          (_karat.hasMatch(item) || _grams.hasMatch(item)))) {
    return _BigKind.gold;
  }
  return null;
}

final _jewelryWord = RegExp(
  r'\b(necklace|kwintas|ring|singsing|bracelet|pulseras|earrings?|hikaw|'
  r'pendant|chain)\b',
  caseSensitive: false,
);

/// Other ways of asking "Can I buy…?", in English, Tagalog or a mix:
///
/// * how long it takes: "How long until I can afford…", "Gaano katagal
///   bago ko mabili…", "Ilang months bago ko ma-afford…", "How long bago
///   ko mabili…";
/// * whether it can be done: "Pwede ba ako bumili ng…", "Kaya ko bang
///   magpatayo ng…".
///
/// "Get" is left out: "how long until I get paid" isn't about buying. So
/// is "all of these" ("kaya kong mabili lahat ng…"): many things at once
/// are the AI's to answer, not one price.
final _otherBuyTrigger = RegExp(
  r'\b(?:how long|how many (?:months|years)|when|gaano (?:ka ?)?katagal|'
  r'ilang (?:buwan|taon|months?|years?)|kailan)\b[^?.!]{0,30}?'
  r'\b(?:afford|buy|own|build|save (?:up )?for|mabibili|makakabili|mabili|'
  r'makabili|bilhin|bumili|magkaroon|maafford|magpatayo|makapagpatayo|'
  r'maipatayo)\b(?!\s+(?:ng\s+)?(?:lahat|all|everything|these|those)\b)|'
  r'\b(?:pwede|puwede|kaya|kakayanin)\b[^?.!]{0,15}?'
  r'\b(?:bumili|bilhin|mabili|makabili|magpatayo|magpagawa|ipatayo)'
  r'(?:\s+ng)?\b(?!\s+(?:ng\s+)?(?:lahat|all|everything|these|those)\b)',
);

final _sqm = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(?:sqm|sq\.?\s*m\b|sq\.?\s*meters?|'
  r'square\s+met(?:er|re)s?|metro\s+kwadrado|m2\b|m²)',
  caseSensitive: false,
);
final _grams = RegExp(
  r'(\d+(?:\.\d+)?)\s*(?:g|gr|grams?|gramo)\b',
  caseSensitive: false,
);
final _karat = RegExp(
  r'\b(24|22|21|18|14|10)\s*(?:k|kt|karat|carat)s?\b',
  caseSensitive: false,
);
final _downPercent = RegExp(
  r'(\d{1,2})\s*%\s*(?:down|dp)|'
  r'(?:down\s*payment|downpayment|down|dp)\D{0,12}?(\d{1,2})\s*%',
  caseSensitive: false,
);
final _loanYears = RegExp(
  r'(\d{1,2})[\s-]*(?:years?|yrs?|taon)\s*(?:loan|term|to pay|na hulugan|'
  r'hulugan|na bayaran)|(?:loan|term|hulugan|bayaran|payable)\D{0,15}?'
  r'(\d{1,2})\s*(?:years?|yrs?|taon)',
  caseSensitive: false,
);
final _inCash = RegExp(
  r'\b(?:full cash|cash basis|in cash|pay cash|spot cash|cash lang|'
  r'walang loan|no loan|without a loan|bayad nang buo|buong bayad)\b',
  caseSensitive: false,
);

double? _sqmIn(String text) {
  final match = _sqm.firstMatch(text);
  return match == null ? null : double.tryParse(match[1]!.replaceAll(',', '.'));
}

double? _gramsIn(String text) {
  final match = _grams.firstMatch(text);
  return match == null ? null : double.tryParse(match[1]!);
}

int? _karatIn(String text) {
  final match = _karat.firstMatch(text);
  return match == null ? null : int.parse(match[1]!);
}

/// A down payment percent said in the question, from 5% to 90%.
int? _downPercentIn(String text) {
  final match = _downPercent.firstMatch(text);
  final percent = int.tryParse(match?[1] ?? match?[2] ?? '');
  return percent != null && percent >= 5 && percent <= 90 ? percent : null;
}

/// How many years the loan is for, from 5 to 30.
int? _loanYearsIn(String text) {
  final match = _loanYears.firstMatch(text);
  final years = int.tryParse(match?[1] ?? match?[2] ?? '');
  return years != null && years >= 5 && years <= 30 ? years : null;
}

/// A size, weight, karat or loan detail, taken out so it isn't read as the
/// price: "120 sqm" is not ₱120, and "18k" gold is not ₱18,000.
String _withoutMeasures(String words) {
  final gold =
      _has(' ${_plain(words)} ', ['gold', 'ginto', 'alahas', 'jewelry']) ||
      _jewelryWord.hasMatch(words);
  var rest = words.replaceAll(_sqm, ' ');
  if (gold) rest = rest.replaceAll(_grams, ' ').replaceAll(_karat, ' ');
  return rest
      .replaceAll(_downPercent, ' ')
      .replaceAll(_loanYears, ' ')
      .replaceAll(_inCash, ' ');
}

/// The rest of a "how long until I can afford a house" question, without
/// the words before the thing itself.
String _withoutAskingWords(String words) => words.replaceFirst(
  RegExp(
    r'^[\s,]*(?:(?:i|can|could|will|ako|ko|afford|buy|get|own|build|'
    r'magpatayo|magpagawa|ipatayo|bilhin|bumili|'
    r'mabili|makabili|mabibili|makakabili|magkaroon|save|saving|for|to|'
    r'until|till|before|bago|have|para|mag|ipon|makaipon|kaya|enough|'
    r'money)\b[\s,]*)+',
    caseSensitive: false,
  ),
  ' ',
);

/// Whole months from [from] to [to].
int _monthsBetween(DateTime from, DateTime to) {
  final months = (to.year - from.year) * 12 + to.month - from.month;
  return math.max(0, to.day < from.day ? months - 1 : months);
}

/// The last day of the month [months] after this one ends: when saving
/// that long gets there.
DateTime _readyBy(FinanceSnapshot records, int months) {
  final monthEnd = records.period.end;
  return DateTime(monthEnd.year, monthEnd.month + months, 0);
}

const _monthsEnglish = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _monthsFilipino = [
  'Enero',
  'Pebrero',
  'Marso',
  'Abril',
  'Mayo',
  'Hunyo',
  'Hulyo',
  'Agosto',
  'Setyembre',
  'Oktubre',
  'Nobyembre',
  'Disyembre',
];

String _monthYear(DateTime date, bool fil) =>
    '${(fil ? _monthsFilipino : _monthsEnglish)[date.month - 1]} ${date.year}';

/// "about 1 year and 3 months", or "mga 1 taon at 3 buwan".
String _howLongText(int months, bool fil) {
  final years = months ~/ 12;
  final rest = months % 12;
  final parts = fil
      ? [if (years > 0) '$years taon', if (rest > 0) '$rest buwan']
      : [
          if (years > 0) '$years ${years == 1 ? 'year' : 'years'}',
          if (rest > 0) '$rest ${rest == 1 ? 'month' : 'months'}',
        ];
  if (parts.isEmpty) return fil ? 'ngayong buwan' : 'this month';
  return fil ? 'mga ${parts.join(' at ')}' : 'about ${parts.join(' and ')}';
}

String _peso(double amount) => formatPeso(amount.roundToDouble());

/// "60" or "7.5", without a needless ".0".
String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// Where the saving pace comes from. [forDeadline] when it is counted
/// toward a date the user gave.
String _paceNote(SavingPace pace, bool fil, {bool forDeadline = false}) {
  final rough = pace.isRough
      ? (fil ? ', kaya tantiya pa lang ito' : ", so it's only a rough guess")
      : '';
  if (forDeadline) {
    return fil
        ? 'Kasama rito ang pera mo ngayon at ang karaniwang natitira sa kita '
              'mo kada buwan, mula sa huling ${pace.days} araw ng records '
              'mo$rough.'
        : "This counts what you have now, then what's usually left of your "
              'income each month, from your last ${pace.days} days of '
              'records$rough.';
  }
  return fil
      ? 'Ang takbo ng ipon mo ay mula sa huling ${pace.days} araw ng records '
            'mo$rough.'
      : 'Your saving pace is from your last ${pace.days} days of '
            'records$rough.';
}

String _paceLine(SavingPace pace, bool fil) => fil
    ? 'Sa karaniwan mong takbo, mga ${_peso(pace.perMonth)} ang natitira kada '
          'buwan (${_peso(pace.income)} ang pumapasok, '
          '${_peso(pace.spending)} ang lumalabas).'
    : 'At your usual pace, about ${_peso(pace.perMonth)} is left each month '
          '(${_peso(pace.income)} in, ${_peso(pace.spending)} out).';

String _nothingLeft(SavingPace pace, bool fil) {
  if (fil) {
    return 'Sa karaniwan mong takbo, walang natitirang maiipon: mga '
        '${_peso(pace.spending)} ang lumalabas kada buwan'
        '${pace.income > 0 ? ' at ${_peso(pace.income)} lang ang pumapasok' : ' at walang naitalang kita'}.';
  }
  return 'At your usual pace, nothing is left to save: about '
      '${_peso(pace.spending)} goes out each month'
      '${pace.income > 0 ? ' and only ${_peso(pace.income)} comes in' : ' and no income is recorded'}.';
}

/// Months to save [price] from [saved], allowing for prices rising when it
/// takes over a year. Null when it never gets there.
int? _monthsToSave(
  double price,
  double saved,
  double perMonth,
  PriceReferences? prices,
) {
  final months = monthsToReach(price: price, saved: saved, perMonth: perMonth);
  final rise = prices?.inflation?.yearlyRise ?? 0;
  if (months == null || months <= 12 || rise <= 0) return months;
  return monthsToReach(
    price: price,
    saved: saved,
    perMonth: perMonth,
    yearlyRise: rise,
  );
}

/// How long saving [price] takes at the user's [pace], starting from
/// [saved] at the end of this month.
({
  List<String> lines,
  int? months,
  DateTime? ready,
  List<ReferenceLink> sources,
})
_savingPlan({
  required double price,
  required double saved,
  required SavingPace pace,
  required FinanceSnapshot records,
  required PriceReferences? prices,
  required bool fil,
}) {
  if (pace.perMonth <= 0) {
    return (
      lines: [_nothingLeft(pace, fil)],
      months: null,
      ready: null,
      sources: const <ReferenceLink>[],
    );
  }
  final months = _monthsToSave(price, saved, pace.perMonth, prices);
  if (months == null) {
    return (
      lines: [
        _paceLine(pace, fil),
        fil
            ? 'Sa ganitong takbo, aabutin ito nang mahigit 50 taon.'
            : 'At that pace, saving for it would take more than 50 years.',
      ],
      months: null,
      ready: null,
      sources: const <ReferenceLink>[],
    );
  }
  final ready = _readyBy(records, months);
  final inflation = prices?.inflation;
  final then = inflation == null || months <= 12
      ? price
      : priceAfter(price, months, inflation.yearlyRise);
  return (
    lines: [
      _paceLine(pace, fil),
      if (months == 0)
        fil
            ? 'Aabot ka na bago matapos ang buwan '
                  '(${formatMonthDay(_lastDay(records))}).'
            : "You'll have enough by the end of this month "
                  '(${formatMonthDay(_lastDay(records))}).'
      else
        fil
            ? 'Kung iipunin mo iyon, aabot ka bandang ${_monthYear(ready, fil)} '
                  '(${_howLongText(months, fil)}).'
            : "Saving that, you'd have enough by about "
                  '${_monthYear(ready, fil)} (${_howLongText(months, fil)}).',
      if (then > price)
        fil
            ? 'Isinama ko ang pagtaas ng presyo, mga '
                  '${_number(inflation!.yearlyRise)}% kada taon (PSA), kaya '
                  'maaaring mga ${_peso(then)} na ang kailangan mo pagdating '
                  'ng panahong iyon.'
            : 'That allows for prices rising about '
                  '${_number(inflation!.yearlyRise)}% a year (PSA), so you '
                  'may need about ${_peso(then)} by then.',
    ],
    months: months,
    ready: ready,
    sources: [if (then > price) inflation!.source],
  );
}

/// Concrete ways to get there sooner, or at all: spending less where most
/// day-to-day money goes, or something cheaper.
List<String> _waysToGetThere({
  required double price,
  required double saved,
  required SavingPace pace,
  required int? months,
  required FinanceSnapshot records,
  required PriceReferences? prices,
  required bool fil,
  bool offerCheaper = true,
}) {
  if (months == 0) return const [];
  final ways = <String>[];
  final top = pace.categories.take(2).toList();
  final cut = top.fold<double>(0, (sum, entry) => sum + entry.value) * 0.2;
  if (top.isNotEmpty && cut >= 100) {
    final names = top.map((entry) => entry.key).join(fil ? ' at ' : ' and ');
    final newPace = pace.perMonth + cut;
    final sooner = newPace > 0
        ? _monthsToSave(price, saved, newPace, prices)
        : null;
    final when = sooner == null
        ? null
        : _monthYear(_readyBy(records, sooner), fil);
    if (pace.perMonth > 0 &&
        sooner != null &&
        (months == null || sooner < months)) {
      ways.add(
        fil
            ? 'Kung babawasan mo nang 20% ang gastos sa $names (mga '
                  '${_peso(cut)} kada buwan), aabot ka bandang $when.'
            : 'Spending 20% less on $names (about ${_peso(cut)} a month) '
                  'would get you there by about $when instead.',
      );
    } else if (pace.perMonth <= 0 && sooner != null) {
      ways.add(
        fil
            ? 'Kung babawasan mo nang 20% ang gastos sa $names (mga '
                  '${_peso(cut)} kada buwan), may mga ${_peso(newPace)} kang '
                  'maiipon kada buwan, sapat bandang $when.'
            : 'Spending 20% less on $names (about ${_peso(cut)} a month) '
                  'would leave about ${_peso(newPace)} a month to save, '
                  'enough by about $when.',
      );
    } else if (pace.perMonth <= 0) {
      final biggest = top
          .map(
            (entry) => fil
                ? '${entry.key} (${_peso(entry.value)} kada buwan)'
                : '${entry.key} (${_peso(entry.value)} a month)',
          )
          .join(fil ? ' at ' : ' and ');
      ways.add(
        fil
            ? 'Mas malaki ang gastos mo kaysa kita, kaya unahin ang '
                  'pinakamalalaki mong araw-araw na gastos: $biggest.'
            : 'You spend more than you earn, so start with your biggest '
                  'day-to-day costs: $biggest.',
      );
    }
  }
  if (offerCheaper && pace.perMonth > 0 && (months == null || months > 12)) {
    final cheaper = price * 0.8;
    final m = _monthsToSave(cheaper, saved, pace.perMonth, prices);
    if (m != null && (months == null || m < months)) {
      ways.add(
        fil
            ? 'Kung mas mura, mga ${_peso(cheaper)}, aabutin ng '
                  '${_howLongText(m, fil)}.'
            : 'Something cheaper, at about ${_peso(cheaper)}, would take '
                  '${_howLongText(m, fil)}.',
      );
    }
  }
  return ways;
}

/// [reply] with [lead] said first and [links] added to its sources.
ChatReply _withLead(ChatReply reply, String lead, List<ReferenceLink> links) =>
    ChatReply(
      '$lead\n\n${reply.text}',
      choices: reply.choices,
      goal: reply.goal,
      pending: reply.pending,
      isVerifiedGoalPlan: reply.isVerifiedGoalPlan,
      useLocalAnswer: reply.useLocalAnswer,
      keepUnderAi: reply.keepUnderAi,
      filipino: reply.filipino,
      sources: [...links, ...reply.sources],
    );

/// The follow-up for a house, lot or gold with no price yet, or null for
/// anything else.
ChatReply? _askBigPrice(
  PurchaseQuestion q,
  FinanceSnapshot records,
  PriceReferences? prices,
  bool fil,
) {
  final kind = _bigKindOf(q.item);
  if (kind == null) return null;
  final asking = q.copyWith(waitingFor: PurchaseStep.price, asked: q.asked + 1);
  final unsure = fil ? notSureFilipino : notSure;

  switch (kind) {
    case _BigKind.home:
      final cost = prices?.buildingCost;
      final sqm = _sqmIn(q.details);
      if (cost != null && sqm != null) {
        return _estimatedHome(q, sqm, cost, records, prices, fil);
      }
      final region = cost == null ? null : regionCostIn(q.details, cost);
      final perSqm = region?.pesoPerSqm ?? cost?.pesoPerSqm;
      final where = region == null
          ? ''
          : (fil ? ' sa ${region.name}' : ' in ${region.name}');
      final costLine = cost == null
          ? ''
          : fil
          ? ' Ang pagpapatayo ng bahay ay mga ${_peso(perSqm!)} kada sqm'
                '$where (PSA, ${cost.year}), hindi kasama ang lupa.'
          : ' Building one costs about ${_peso(perSqm!)} per sqm$where '
                '(PSA, ${cost.year}), not counting the land.';
      return ChatReply(
        fil
            ? 'Mga magkano ang ${q.thing}? I-type ang presyo, o ang laki nito, '
                  'halimbawa "60 sqm", at kukuwentahin ko ang gastos sa '
                  'pagpapatayo.$costLine'
            : 'About how much is the ${q.thing}? Type the price, or its size, '
                  'like "60 sqm", and I\'ll work out what building it '
                  'costs.$costLine',
        choices: [unsure],
        pending: asking,
        filipino: fil,
        sources: [?cost?.source],
      );

    case _BigKind.land:
      final offices = _zonalOffices(q, prices);
      return ChatReply(
        [
          fil
              ? 'Mga magkano ang ${q.thing}? I-type ang presyo, halimbawa '
                    '₱1,500,000.'
              : 'About how much is the ${q.thing}? Type the price, for '
                    'example ₱1,500,000.',
          ?_zonalLine(offices, fil),
        ].join('\n\n'),
        choices: [unsure],
        pending: asking,
        filipino: fil,
        sources: _zonalLinks(offices),
      );

    case _BigKind.gold:
      final gold = prices?.gold;
      if (gold == null) return null;
      final grams = _gramsIn(q.details);
      final pure =
          '${formatPeso(gold.pesoPerGram)} '
          '${fil ? 'kada gramo' : 'a gram'}'
          '${gold.asOf == null ? '' : ' (${formatMonthDay(gold.asOf!)})'}';
      if (grams == null) {
        return ChatReply(
          fil
              ? 'Ilang gramo ito, at anong karat, halimbawa "10 grams 18k"? O '
                    'i-type ang presyo sa tindahan. Ang purong ginto ay '
                    '$pure ngayon.'
              : 'How many grams is it, and what karat, like "10 grams 18k"? '
                    'Or type the price at the shop. Pure gold is $pure today.',
          choices: [unsure],
          pending: asking,
          filipino: fil,
          sources: gold.sources,
        );
      }
      final karat = _karatIn(q.details);
      final worth = goldWorth(
        grams,
        karat ?? defaultKarat,
        gold.pesoPerGram,
      ).roundToDouble();
      final assumed = karat != null
          ? ''
          : (fil
                ? ' Gumamit ako ng 18k, ang pinakakaraniwan sa alahas.'
                : ' I used 18k, the most common for jewelry.');
      return ChatReply(
        fil
            ? 'Ang ${_number(grams)} gramo ng ${karat ?? defaultKarat}k na ginto '
                  'ay mga ${_peso(worth)}: ang purong ginto ay $pure.$assumed '
                  'Mas mahal ang singil ng tindahan dahil sa disenyo at '
                  'pagkakagawa. Magkano ito sa tindahan?'
            : '${_number(grams)} grams of ${karat ?? defaultKarat}k gold is '
                  'worth about ${_peso(worth)}: pure gold is $pure.$assumed '
                  'Shops charge more than this for the design and work. '
                  "What's the price at the shop?",
        choices: [
          fil ? 'Gamitin ang ${_peso(worth)}' : 'Use ${_peso(worth)}',
          unsure,
        ],
        pending: asking,
        filipino: fil,
        sources: gold.sources,
      );
  }
}

/// A reply to "how much is it?" that gives a house's size or gold's
/// weight instead of a price, or null for any other reply.
ChatReply? _measuredPrice(
  String message,
  PurchaseQuestion pending,
  FinanceSnapshot records,
  PriceReferences? prices,
  bool fil,
) {
  final kind = _bigKindOf(pending.item);
  if (kind == _BigKind.home) {
    final cost = prices?.buildingCost;
    final sqm = _sqmIn(message);
    if (cost != null && sqm != null) {
      return _estimatedHome(pending, sqm, cost, records, prices, fil);
    }
  }
  final gold = prices?.gold;
  if (kind != _BigKind.gold || gold == null) return null;
  final grams = _gramsIn(pending.details);
  if (grams == null) return null;
  final worth = goldWorth(
    grams,
    _karatIn(pending.details) ?? defaultKarat,
    gold.pesoPerGram,
  ).roundToDouble();
  final unsure =
      _has(' ${_plain(message)} ', _unsure) ||
      message.trim() == notSure ||
      message.trim() == notSureFilipino;
  // Not sure of the shop's price: the gold's worth is the least it costs.
  if (unsure || (_gramsIn(message) != null && pending.asked >= 2)) {
    return _purchaseAnswer(
      pending.copyWith(price: worth, clearWaiting: true),
      records,
      prices,
      fil,
    );
  }
  // A new weight: work out its worth again.
  if (_gramsIn(message) != null) {
    return _askBigPrice(pending, records, prices, fil);
  }
  return null;
}

/// The cost to build [sqm] square meters, then the house answer for it.
ChatReply _estimatedHome(
  PurchaseQuestion q,
  double sqm,
  BuildingCost cost,
  FinanceSnapshot records,
  PriceReferences? prices,
  bool fil,
) {
  final region = regionCostIn(q.details, cost);
  final perSqm = region?.pesoPerSqm ?? cost.pesoPerSqm;
  final estimate = (sqm * perSqm).roundToDouble();
  final lead = fil
      ? 'Ang pagpapatayo ng ${_number(sqm)} sqm ay mga ${_peso(estimate)}, sa '
            '${_peso(perSqm)} kada sqm, ang average ng PSA noong ${cost.year}'
            '${region == null ? ' sa buong bansa' : ' sa ${region.name}'}. '
            'Hindi kasama ang lupa.'
      : 'Building ${_number(sqm)} sqm costs about ${_peso(estimate)}, at '
            '${_peso(perSqm)} per sqm, the PSA\'s ${cost.year} average'
            '${region == null ? ' for the whole country' : ' for ${region.name}'}. '
            'The land isn\'t included.';
  return _withLead(
    _purchaseAnswer(
      q.copyWith(price: estimate, clearWaiting: true),
      records,
      prices,
      fil,
    ),
    lead,
    [cost.source],
  );
}

/// The BIR offices whose land values cover the place in the question.
List<ZonalOffice> _zonalOffices(PurchaseQuestion q, PriceReferences? prices) {
  final values = prices?.zonalValues;
  return values == null ? const [] : zonalOfficesIn(q.details, values);
}

String? _zonalLine(List<ZonalOffice> offices, bool fil) {
  if (offices.isEmpty) return null;
  final names = offices
      .map((office) => office.office)
      .join(fil ? ' o ' : ' or ');
  final year = offices.first.revisedYear;
  return fil
      ? 'Para sa halaga ng lupa roon, nasa listahan ng $names ang zonal values '
            'ng BIR (ang halaga ng lupa ayon sa gobyerno)'
            '${year == null ? '' : ', huling in-update noong $year'}. '
            'Naka-link ito sa ibaba; kadalasang mas mataas ang presyo ng '
            'bentahan.'
      : 'For what land there is worth, the BIR\'s zonal values (the '
            'government\'s land values) are in the list for $names'
            '${year == null ? '' : ', last updated in $year'}. It\'s linked '
            'below; selling prices are often higher.';
}

List<ReferenceLink> _zonalLinks(List<ZonalOffice> offices) => [
  for (final office in offices)
    if (office.files.isNotEmpty)
      ReferenceLink(
        'BIR land values: ${office.office}',
        office.files.first.url,
      ),
];

/// How a gold price compares with what its gold is worth today.
({String text, List<ReferenceLink> links})? _goldNote(
  PurchaseQuestion q,
  double price,
  PriceReferences? prices,
  bool fil,
) {
  final gold = prices?.gold;
  if (gold == null) return null;
  final grams = _gramsIn(q.details);
  if (grams == null) {
    return (
      text: fil
          ? 'Ang purong ginto ay ${formatPeso(gold.pesoPerGram)} kada gramo '
                'ngayon, kung gusto mong ihambing sa presyo ng tindahan.'
          : 'Pure gold is ${formatPeso(gold.pesoPerGram)} a gram today, to '
                'compare with the shop\'s price.',
      links: gold.sources,
    );
  }
  final karat = _karatIn(q.details) ?? defaultKarat;
  final worth = goldWorth(grams, karat, gold.pesoPerGram).roundToDouble();
  final weight = '${_number(grams)} g, ${karat}k';
  final String text;
  if ((price - worth).abs() < 1) {
    text = fil
        ? 'Iyan ang halaga ng ginto lang ($weight); mas mahal ang singil ng '
              'tindahan dahil sa disenyo at pagkakagawa, kaya maghanda ng '
              'mas malaki.'
        : "That's what its gold alone is worth ($weight); shops charge more "
              'for the design and work, so expect to pay more.';
  } else if (price > worth) {
    final more = ((price - worth) / worth * 100).round();
    text = fil
        ? 'Mga $more% iyan na mas mataas sa halaga ng ginto nito '
              '(${_peso(worth)} para sa $weight); ang natitira ay para sa '
              'disenyo at pagkakagawa.'
        : "That's about $more% more than its gold is worth "
              '(${_peso(worth)} for $weight); the rest is for the design and '
              'work.';
  } else {
    text = fil
        ? 'Mas mababa iyan sa halaga ng ginto nito (${_peso(worth)} para sa '
              '$weight), kaya suriin ang timbang at karat.'
        : "That's less than its gold is worth (${_peso(worth)} for "
              '$weight), so check its weight and karat.';
  }
  return (text: text, links: gold.sources);
}

/// The active goal already saving for this kind of thing, if any.
Goal? _matchingGoal(FinanceSnapshot records, _BigKind kind) {
  final words = kind == _BigKind.land
      ? const ['lot', 'lote', 'lupa', 'land']
      : const ['house', 'home', 'bahay', 'condo', 'property'];
  return records.goals.where((goal) {
    final name = ' ${_plain(goal.name)} ';
    return goal.status == GoalStatus.active && _has(name, words);
  }).firstOrNull;
}

/// A house or lot: what to save first, the loan's monthly payment, how
/// long saving takes, and whether the payment fits the user's income.
ChatReply _homeAnswer(
  PurchaseQuestion q,
  FinanceSnapshot records,
  PriceReferences? prices,
  bool fil,
) {
  final price = q.price!;
  final kind = _bigKindOf(q.item)!;
  final thing = q.thing;
  final cash = _inCash.hasMatch(q.details);
  final down = _downPercentIn(q.details) ?? defaultDownPercent;
  final years = _loanYearsIn(q.details) ?? defaultLoanYears;

  final costs = price * buyingCostsPercent / 100;
  final downPayment = price * down / 100;
  final upfront = cash ? price + costs : downPayment + costs;
  final loan = cash ? 0.0 : price - downPayment;
  final loans = prices?.homeLoans;
  final rate = loans?.standardFor(loanRateFixedYears)?.ratePercent;
  final payment = cash || rate == null
      ? null
      : monthlyLoanPayment(loan, rate, years);
  final sources = <ReferenceLink>[];

  final parts = <String>[
    if (cash)
      fil
          ? 'Para makuha ang $thing (${_peso(price)}) nang cash, kailangan mo '
                'ng mga ${_peso(upfront)}: ang presyo at mga '
                '$buyingCostsPercent% (${_peso(costs)}) para sa buwis, '
                'paglilipat ng titulo at papeles.'
          : "To get the $thing (${_peso(price)}) in cash, you'd need about "
                '${_peso(upfront)}: the price plus about $buyingCostsPercent% '
                '(${_peso(costs)}) for taxes, transfer and paperwork.'
    else
      [
        fil
            ? 'Para makuha ang $thing (${_peso(price)}) gamit ang housing '
                  'loan, kailangan mo munang mag-ipon ng mga ${_peso(upfront)}: '
                  '$down% na down payment (${_peso(downPayment)}) at mga '
                  '$buyingCostsPercent% (${_peso(costs)}) para sa buwis, '
                  'paglilipat ng titulo at papeles.'
            : "To get the $thing (${_peso(price)}) with a home loan, you'd "
                  'first save about ${_peso(upfront)}: a $down% down payment '
                  '(${_peso(downPayment)}) plus about $buyingCostsPercent% '
                  '(${_peso(costs)}) for taxes, transfer and paperwork.',
        payment == null
            ? (fil
                  ? 'Hindi ko ma-load ang mga rate ng housing loan, kaya hindi '
                        'ko pa makuwenta ang buwanang hulog.'
                  : "I couldn't load home loan rates, so I can't work out the "
                        'monthly payment yet.')
            : (fil
                  ? 'Ang loan na ${_peso(loan)} ay mga ${_peso(payment)} kada '
                        'buwan sa loob ng $years taon, sa ${_number(rate!)}% na '
                        'rate ng Pag-IBIG.'
                  : 'The loan of ${_peso(loan)} would be about '
                        '${_peso(payment)} a month for $years years, at '
                        "Pag-IBIG's ${_number(rate!)}% rate."),
      ].join(' '),
  ];

  // How long saving the first part takes.
  final pace = savingPaceOf(records);
  final goal = _matchingGoal(records, kind);
  final inGoal = goal?.shownSaved ?? 0;
  final start =
      math.max(0.0, _spareBy(records.period.end, records).spare) + inGoal;
  int? months;
  DateTime? ready;
  if (pace == null) {
    parts.add(
      fil
          ? 'Para masabi kung gaano katagal ang pag-iipon para rito, kailangan '
                'ko ng kahit dalawang linggo ng records ng kita at gastos mo.'
          : 'To tell how long saving for it takes, I need at least two weeks '
                'of your income and spending records.',
    );
  } else if (start >= upfront) {
    months = 0;
    parts.add(
      fil
          ? 'Sapat na ang pera mo para rito: mga ${_peso(start)} pagdating ng '
                'katapusan ng buwan.'
          : 'You already have enough for this: about ${_peso(start)} by the '
                'end of the month.',
    );
  } else {
    final plan = _savingPlan(
      price: upfront,
      saved: start,
      pace: pace,
      records: records,
      prices: prices,
      fil: fil,
    );
    months = plan.months;
    ready = plan.ready;
    parts.addAll(plan.lines);
    sources.addAll(plan.sources);

    // A target the user gave, such as "within 5 years".
    final monthEnd = records.period.end;
    if (months != null && q.deadline.isAfter(monthEnd)) {
      final target = math.max(1, _monthsBetween(monthEnd, q.deadline));
      final label = fil ? q.deadlineLabelFilipino : q.deadlineLabel;
      if (months <= target) {
        parts.add(
          fil
              ? 'Pasok iyan sa target mo ($label).'
              : "That's within your target ($label).",
        );
      } else {
        final needed = (upfront - start) / target;
        parts.add(
          fil
              ? 'Lampas iyan sa target mo ($label): kailangan mong mag-ipon ng '
                    'mga ${_peso(needed)} kada buwan para umabot.'
              : "That's past your target ($label): you'd need to save about "
                    '${_peso(needed)} a month to make it.',
        );
      }
    }
  }
  if (inGoal > 0 && pace != null) {
    parts.add(
      fil
          ? 'Kasama na rito ang ${_peso(inGoal)} sa goal mong “${goal!.name}”.'
          : 'That counts the ${_peso(inGoal)} already in your “${goal!.name}” '
                'goal.',
    );
  }

  // Whether the monthly payment fits the user's income.
  if (payment != null && pace != null) {
    final limit = pace.income * loanIncomeShare;
    final share = (loanIncomeShare * 100).round();
    if (pace.income <= 0) {
      parts.add(
        fil
            ? 'Walang naitalang kita, kaya hindi ko masuri ang buwanang hulog '
                  'laban dito.'
            : "No income is recorded, so I can't check the monthly payment "
                  'against it.',
      );
    } else if (payment <= limit) {
      final short = payment - math.max(0.0, pace.perMonth);
      parts.add(
        [
          fil
              ? 'Pasok ang ${_peso(payment)} na buwanang hulog sa $share% ng '
                    'karaniwan mong kita (${_peso(pace.income)} kada buwan), na '
                    'karaniwang pinapayagan ng mga nagpapautang.'
              : 'The ${_peso(payment)} monthly payment is within $share% of '
                    'your usual income (${_peso(pace.income)} a month), which '
                    'lenders usually allow.',
          if (short > 0)
            fil
                ? 'Pero mas malaki ito sa natitira sa iyo kada buwan ngayon, '
                      'kaya kailangan mong bawasan ang gastos nang mga '
                      '${_peso(short)} kada buwan, o mas kaunti kung papalitan '
                      'nito ang upa mo.'
                : "It's more than what's left each month now, though, so "
                      "you'd need to spend about ${_peso(short)} less a "
                      'month, or less if it replaces your rent.',
        ].join(' '),
      );
    } else {
      final biggest = loanForPayment(limit, rate!, years) / (1 - down / 100);
      parts.add(
        fil
            ? 'Lampas ang ${_peso(payment)} na buwanang hulog sa $share% ng '
                  'karaniwan mong kita (${_peso(pace.income)} kada buwan), ang '
                  'karaniwang pinakamataas na pinapayagan, kaya maaaring hindi '
                  'maaprubahan ang ganito kalaking loan. Kung hanggang mga '
                  '${_peso(biggest)} lang ang $thing, pasok ang hulog.'
            : 'The ${_peso(payment)} monthly payment is more than $share% of '
                  'your usual income (${_peso(pace.income)} a month), the most '
                  'lenders usually allow, so a loan this big may not be '
                  'approved. A $thing up to about ${_peso(biggest)} keeps the '
                  'payment within it.',
      );
    }
  }

  // Ways to get there sooner.
  if (pace != null) {
    parts.addAll(
      _waysToGetThere(
        price: upfront,
        saved: start,
        pace: pace,
        months: months,
        records: records,
        prices: prices,
        fil: fil,
        offerCheaper: false,
      ),
    );
    if (cash && (months == null || months > 24)) {
      final withLoan = price * (defaultDownPercent + buyingCostsPercent) / 100;
      parts.add(
        fil
            ? 'Kung gagamit ng housing loan, mga ${_peso(withLoan)} lang ang '
                  'kailangan mong ipunin muna ($defaultDownPercent% na down '
                  'payment at $buyingCostsPercent% para sa buwis at bayarin).'
            : "With a home loan, you'd only need to save about "
                  '${_peso(withLoan)} first ($defaultDownPercent% down plus '
                  '$buyingCostsPercent% for taxes and fees).',
      );
    }
  }

  // What the answer assumes, and where its figures are from.
  if (payment != null) {
    parts.add(
      fil
          ? 'Gumamit ako ng $down% na down payment, $years taong loan at '
                '${_number(rate!)}% na rate ng Pag-IBIG, na hindi nagbabago sa '
                'unang $loanRateFixedYears taon at saka nire-review. Itanong '
                'ulit na may "10% down" o "20 years" para baguhin.'
          : 'This uses a $down% down payment, a $years-year loan and '
                "Pag-IBIG's ${_number(rate!)}% rate, which stays the same for "
                '$loanRateFixedYears years and is then reviewed. Ask with '
                '"10% down" or "20 years" to change them.',
    );
    final promo = loans!.promoFor(loan);
    final promoAsOf = DateTime.tryParse('${loans.promoAsOf}-01');
    if (promo != null && promo.ratePercent < rate && promoAsOf != null) {
      parts.add(
        fil
            ? 'Nag-anunsyo ang Pag-IBIG ng mas mababang '
                  '${_number(promo.ratePercent)}% na rate para sa ganitong laki '
                  'ng loan noong ${_monthYear(promoAsOf, fil)}; itanong sa '
                  'kanila kung may bisa pa ito.'
            : 'Pag-IBIG announced a lower ${_number(promo.ratePercent)}% rate '
                  'for loans this size in ${_monthYear(promoAsOf, fil)}; ask '
                  'them if it still applies.',
      );
      sources.addAll([?loans.promoSource]);
    }
    parts.add(
      fil
          ? 'Huling sinuri ang mga rate noong '
                '${formatShortDate(loans.checkedOn)}.'
          : 'Loan rates last checked ${formatShortDate(loans.checkedOn)}.',
    );
    sources.insertAll(0, [?loans.standardSource]);
  }

  final offices = _zonalOffices(q, prices);
  final zonal = _zonalLine(offices, fil);
  if (zonal != null) {
    parts.add(zonal);
    sources.addAll(_zonalLinks(offices));
  } else if (kind == _BigKind.land && prices?.zonalValues != null) {
    parts.add(
      fil
          ? 'Sabihin ang bayan, halimbawa "lot sa Tanauan, Batangas", at '
                'hahanapin ko ang halaga ng lupa roon ayon sa gobyerno.'
          : 'Name the town, like "lot in Tanauan, Batangas", and I\'ll find '
                "the government's land values for it.",
    );
  }
  if (pace != null) parts.add(_paceNote(pace, fil));

  return ChatReply(
    parts.join('\n\n'),
    goal: ready == null
        ? null
        : GoalOffer(
            name: cash
                ? _goalName(thing)
                : (fil ? 'Down payment sa $thing' : 'Down payment for $thing'),
            target: upfront.roundToDouble(),
            date: ready,
          ),
    filipino: fil,
    sources: sources,
  ).protected();
}
