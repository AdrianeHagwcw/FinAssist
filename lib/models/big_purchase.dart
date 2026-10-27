import 'dart:math' as math;

import 'finance_snapshot.dart';
import 'price_references.dart';
import 'transaction_filter.dart';

/// The math behind answers about big purchases: how fast the user saves,
/// how long a price takes to reach, a home loan's monthly payment, and what
/// gold is worth. Wording lives with the other answers in chat_answers.dart.

/// What buying a house or lot usually asks for, said in every answer that
/// uses them so the user can change them in the question.
const defaultDownPercent = 20;
const defaultLoanYears = 30;

/// Taxes, transfer and paperwork when buying property, on top of the price.
const buyingCostsPercent = 5;

/// Lenders usually keep a home loan's monthly payment within this share of
/// the borrower's monthly income.
const loanIncomeShare = 0.35;

/// The Pag-IBIG rate used: the one fixed for 3 years, which most
/// borrowers pick. It is reviewed after those years.
const loanRateFixedYears = 3;

/// Gold in jewelry when the karat isn't said: 18k is the most common.
const defaultKarat = 18;

/// Fewer days of records than this can't show a saving habit.
const _fewestDays = 14;

/// How much of the user's money is left each month: their usual income less
/// their usual spending, from the last 90 days of records or fewer.
class SavingPace {
  const SavingPace({
    required this.income,
    required this.spending,
    required this.days,
    required this.categories,
  });

  /// Money in, a month.
  final double income;

  /// Money out, a month, bills included.
  final double spending;

  /// How many days of records it is worked out from.
  final int days;

  /// Day-to-day spending a month by category, largest first. Bills are left
  /// out: they can't simply be cut.
  final List<MapEntry<String, double>> categories;

  double get perMonth => income - spending;

  /// Under two months of records, a habit is only starting to show.
  bool get isRough => days < 60;
}

/// The user's [SavingPace], or null with under two weeks of records.
///
/// Spending goes on all month, so it is scaled to 30 days. Income comes in
/// lumps, so it is never scaled up: ₱20,000 recorded in a 20-day stretch is
/// counted as ₱20,000 a month, not ₱30,000.
SavingPace? savingPaceOf(FinanceSnapshot records) {
  DateTime? first;
  for (final transaction in records.transactions) {
    if (first == null || transaction.date.isBefore(first)) {
      first = transaction.date;
    }
  }
  if (first == null) return null;

  final today = records.today;
  final firstDay = DateTime(first.year, first.month, first.day);
  final ninetyDaysAgo = today.subtract(const Duration(days: 89));
  final from = firstDay.isAfter(ninetyDaysAgo) ? firstDay : ninetyDaysAgo;
  final days = today.difference(from).inDays + 1;
  if (days < _fewestDays) return null;

  final until = today.add(const Duration(days: 1));
  final recent = records.transactions
      .where((t) => !t.date.isBefore(from) && t.date.isBefore(until))
      .toList();
  final flow = inAndOut(recent);
  final dayToDay = spendingByCategory(
    recent.where((t) => !t.isBillPayment),
  ).where((entry) => entry.key != 'Bills');

  return SavingPace(
    income: flow.moneyIn / math.max(days, 30) * 30,
    spending: flow.moneyOut / days * 30,
    days: days,
    categories: [
      for (final entry in dayToDay)
        MapEntry(entry.key, entry.value / days * 30),
    ],
  );
}

/// Months until [saved] plus [perMonth] a month reaches [price], while the
/// price rises [yearlyRise] percent a year. 0 when [saved] is already
/// enough; null when it never gets there within 50 years.
int? monthsToReach({
  required double price,
  required double saved,
  required double perMonth,
  double yearlyRise = 0,
}) {
  if (saved >= price) return 0;
  if (perMonth <= 0) return null;
  for (var month = 1; month <= 600; month++) {
    final then = priceAfter(price, month, yearlyRise);
    if (saved + perMonth * month >= then) return month;
  }
  return null;
}

/// [price] after [months] of prices rising [yearlyRise] percent a year.
double priceAfter(double price, int months, double yearlyRise) =>
    price * math.pow(1 + yearlyRise / 100, months / 12);

/// A loan's monthly payment: the same amount every month pays back [loan]
/// and its interest at [yearlyRatePercent] over [years].
double monthlyLoanPayment(double loan, double yearlyRatePercent, int years) {
  final months = years * 12;
  final rate = yearlyRatePercent / 100 / 12;
  if (rate == 0) return loan / months;
  return loan * rate / (1 - math.pow(1 + rate, -months));
}

/// The biggest loan a [payment] a month can pay back: the reverse of
/// [monthlyLoanPayment].
double loanForPayment(double payment, double yearlyRatePercent, int years) {
  final months = years * 12;
  final rate = yearlyRatePercent / 100 / 12;
  if (rate == 0) return payment * months;
  return payment * (1 - math.pow(1 + rate, -months)) / rate;
}

/// What the gold in [grams] of [karat] gold is worth, at [pesoPerGram] for
/// pure gold. 24k is pure; 18k is 18 parts gold in 24.
double goldWorth(double grams, int karat, double pesoPerGram) =>
    grams * pesoPerGram * karat / 24;

/// Words and numbers only, lowercase, so place names match however typed.
String _words(String text) =>
    ' ${text.toLowerCase().replaceAll('ñ', 'n').split(RegExp('[^a-z0-9]+')).where((w) => w.isNotEmpty).join(' ')} ';

/// Places people name, by a word in the PSA's region names. The longest
/// match wins, so "quezon city" beats "quezon".
const _regionPlaces = <String, List<String>>{
  'NCR': [
    'ncr',
    'metro manila',
    'manila',
    'quezon city',
    'qc',
    'makati',
    'taguig',
    'pasig',
    'caloocan',
    'pasay',
    'paranaque',
    'las pinas',
    'muntinlupa',
    'marikina',
    'mandaluyong',
    'valenzuela',
    'malabon',
    'navotas',
    'san juan',
    'pateros',
  ],
  '(CAR)': [
    'cordillera',
    'baguio',
    'benguet',
    'ifugao',
    'abra',
    'kalinga',
    'apayao',
    'mountain province',
  ],
  'Ilocos': ['ilocos', 'pangasinan', 'la union', 'laoag', 'vigan', 'dagupan'],
  'Cagayan Valley': [
    'cagayan valley',
    'isabela',
    'tuguegarao',
    'nueva vizcaya',
    'quirino',
    'batanes',
    'cagayan',
  ],
  'Central Luzon': [
    'central luzon',
    'pampanga',
    'bulacan',
    'tarlac',
    'nueva ecija',
    'bataan',
    'zambales',
    'aurora',
    'angeles',
    'olongapo',
    'malolos',
    'cabanatuan',
    'clark',
  ],
  'CALABARZON': [
    'calabarzon',
    'cavite',
    'laguna',
    'batangas',
    'rizal',
    'quezon',
    'lucena',
    'antipolo',
    'calamba',
    'santa rosa',
    'dasmarinas',
    'bacoor',
    'imus',
    'lipa',
    'tanauan',
    'san pablo',
    'binan',
    'cainta',
    'taytay',
  ],
  'MIMAROPA': [
    'mimaropa',
    'mindoro',
    'palawan',
    'puerto princesa',
    'romblon',
    'marinduque',
    'calapan',
  ],
  'Bicol': [
    'bicol',
    'albay',
    'legazpi',
    'legaspi',
    'naga',
    'camarines',
    'sorsogon',
    'catanduanes',
    'masbate',
  ],
  'Western Visayas': [
    'western visayas',
    'iloilo',
    'bacolod',
    'negros occidental',
    'capiz',
    'aklan',
    'antique',
    'guimaras',
    'boracay',
  ],
  'Central Visayas': [
    'central visayas',
    'cebu',
    'bohol',
    'tagbilaran',
    'negros oriental',
    'dumaguete',
    'siquijor',
    'lapu lapu',
    'mandaue',
  ],
  'Eastern Visayas': [
    'eastern visayas',
    'leyte',
    'samar',
    'tacloban',
    'biliran',
    'ormoc',
  ],
  'Zamboanga': ['zamboanga', 'pagadian', 'dipolog'],
  'Northern Mindanao': [
    'northern mindanao',
    'cagayan de oro',
    'cdo',
    'bukidnon',
    'misamis',
    'iligan',
    'camiguin',
    'lanao del norte',
  ],
  'Davao': ['davao', 'tagum', 'digos', 'panabo'],
  'SOCCSKSARGEN': [
    'soccsksargen',
    'general santos',
    'gensan',
    'south cotabato',
    'sultan kudarat',
    'sarangani',
    'koronadal',
  ],
  'Caraga': ['caraga', 'butuan', 'agusan', 'surigao', 'dinagat'],
  'BARMM': [
    'barmm',
    'bangsamoro',
    'maguindanao',
    'lanao del sur',
    'marawi',
    'sulu',
    'basilan',
    'tawi tawi',
    'cotabato city',
  ],
};

/// The region's building cost for a place named in [text], or null when no
/// place is named or the PSA has no figure for it.
RegionCost? regionCostIn(String text, BuildingCost cost) {
  final words = _words(text);
  String? best;
  var bestLength = 0;
  for (final MapEntry(key: region, value: places) in _regionPlaces.entries) {
    for (final place in places) {
      if (place.length > bestLength && words.contains(' $place ')) {
        best = region;
        bestLength = place.length;
      }
    }
  }
  if (best == null) return null;
  return cost.regions
      .where((region) => region.name.contains(best!))
      .firstOrNull;
}

/// Words that say where, not which place: "in the city", "near me".
const _notPlaces = {
  'the',
  'my',
  'our',
  'a',
  'philippines',
  'pilipinas',
  'city',
  'province',
  'area',
  'lugar',
  'amin',
  'namin',
  'near',
  'me',
  'probinsya',
};

/// The BIR offices whose land values cover a place named after "in", "at"
/// or "sa" in [text], best match first, at most two.
List<ZonalOffice> zonalOfficesIn(String text, ZonalValues values) {
  final named = RegExp(
    r'\b(?:in|at|sa|near|malapit sa)\s+([^?.!]+)',
    caseSensitive: false,
  ).allMatches(text).map((match) => match[1]!).toList();
  if (named.isEmpty) return const [];

  // "in Tanauan, Batangas for ₱1,500,000": the place ends where the price
  // or the rest of the question starts.
  final place = named.last
      .split(
        RegExp(
          r'\b(?:for|worth|with|by|within|para|na|priced|around|costing|that|'
          r'which|in)\b|[₱\d]',
          caseSensitive: false,
        ),
      )
      .first;

  // "Tanauan, Batangas": the town first, then the province.
  final parts = [
    for (final part in place.split(RegExp(r',|\band\b|\bat\b')))
      _words(
        part,
      ).trim().split(' ').where((word) => !_notPlaces.contains(word)).join(' '),
  ].where((part) => part.length >= 3);

  for (final part in parts) {
    final found = values.offices.where((office) {
      final where = _words(
        '${office.office} ${office.province} ${office.places}',
      );
      return where.contains(' $part ');
    }).toList();
    if (found.isNotEmpty) return found.take(2).toList();
  }
  return const [];
}
