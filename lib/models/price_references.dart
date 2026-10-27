/// Public prices the web scraper saves every day in Firestore
/// (`priceReferences`), for answers about big purchases: houses, lots and
/// gold. Every figure keeps where and when it is from, so an answer can say.
///
/// Each part is read on its own. One that is missing or in an unexpected
/// shape is left out, and the answers that need it say they can't use it,
/// instead of the whole set failing.
library;

/// A page a figure came from, shown as a link under the answer.
class ReferenceLink {
  const ReferenceLink(this.title, this.url);

  final String title;
  final String url;
}

/// How fast prices rise: the PSA's inflation rate.
class InflationFigure {
  const InflationFigure({
    required this.ratePercent,
    required this.periodLabel,
    required this.source,
    this.averageLast12Months,
  });

  /// The latest month's rate, such as 7.2 for September 2026.
  final double ratePercent;

  /// The month it is for, such as "September 2026".
  final String periodLabel;

  /// The average of the last 12 months, steadier than one month's rate.
  final double? averageLast12Months;
  final ReferenceLink source;

  /// The yearly rise to plan with: the 12-month average when there is one,
  /// since a single month can jump.
  double get yearlyRise => averageLast12Months ?? ratePercent;
}

/// What building a house costs per square meter, from the PSA.
class BuildingCost {
  const BuildingCost({
    required this.year,
    required this.pesoPerSqm,
    required this.regions,
    required this.source,
  });

  final int year;

  /// The whole country's average.
  final double pesoPerSqm;
  final List<RegionCost> regions;
  final ReferenceLink source;
}

class RegionCost {
  const RegionCost(this.name, this.pesoPerSqm);

  /// The PSA's name, such as "Region VII (Central Visayas)".
  final String name;
  final double pesoPerSqm;
}

/// Pure (24k) gold's price today.
class GoldPrice {
  const GoldPrice({
    required this.pesoPerGram,
    required this.sources,
    this.asOf,
  });

  final double pesoPerGram;
  final DateTime? asOf;
  final List<ReferenceLink> sources;
}

/// One BIR office's zonal values: the government's land values for the
/// towns it covers.
class ZonalOffice {
  const ZonalOffice({
    required this.office,
    required this.region,
    required this.province,
    required this.places,
    required this.files,
    this.revisedYear,
  });

  /// Such as "RDO No. 24-Valenzuela City".
  final String office;
  final String region;
  final String province;

  /// The towns and barangays it covers, as BIR lists them.
  final String places;
  final int? revisedYear;

  /// The files with the land value of every street.
  final List<ReferenceLink> files;
}

class ZonalValues {
  const ZonalValues({required this.offices, required this.source});

  final List<ZonalOffice> offices;
  final ReferenceLink source;
}

/// One Pag-IBIG housing loan rate.
class LoanRate {
  const LoanRate({
    required this.fixedYears,
    required this.ratePercent,
    this.loanFrom,
    this.loanUpTo,
  });

  /// How many years the rate stays the same.
  final int fixedYears;
  final double ratePercent;

  /// The loan sizes a promo rate is for, when it is only for some.
  final double? loanFrom;
  final double? loanUpTo;

  bool covers(double loan) =>
      (loanFrom == null || loan > loanFrom!) &&
      (loanUpTo == null || loan <= loanUpTo!);
}

/// Pag-IBIG's housing loan rates, kept by hand by the team.
class HomeLoanRates {
  const HomeLoanRates({
    required this.standard,
    required this.promo,
    required this.checkedOn,
    this.standardSource,
    this.promoSource,
    this.promoAsOf,
  });

  final List<LoanRate> standard;
  final List<LoanRate> promo;

  /// When the team last checked them.
  final DateTime checkedOn;
  final ReferenceLink? standardSource;
  final ReferenceLink? promoSource;

  /// When the promo was announced, such as "2026-06".
  final String? promoAsOf;

  /// The usual rate fixed for [years], or null when there is none.
  LoanRate? standardFor(int years) =>
      standard.where((rate) => rate.fixedYears == years).firstOrNull;

  /// The promo rate for a [loan] this size, or null.
  LoanRate? promoFor(double loan) =>
      promo.where((rate) => rate.covers(loan)).firstOrNull;
}

/// Everything the scraper saved. Any part can be null.
class PriceReferences {
  const PriceReferences({
    this.inflation,
    this.buildingCost,
    this.gold,
    this.zonalValues,
    this.homeLoans,
  });

  final InflationFigure? inflation;
  final BuildingCost? buildingCost;
  final GoldPrice? gold;
  final ZonalValues? zonalValues;
  final HomeLoanRates? homeLoans;

  /// From the Firestore documents, by their ids: inflation,
  /// constructionCost, gold, zonalValues and pagibigRates.
  factory PriceReferences.fromDocuments(
    Map<String, Map<String, dynamic>> documents,
  ) {
    T? read<T>(String id, T Function(Map<String, dynamic>) parse) {
      final data = documents[id];
      if (data == null) return null;
      try {
        return parse(data);
      } on Object {
        return null; // Unexpected shape: leave this part out.
      }
    }

    return PriceReferences(
      inflation: read('inflation', _inflation),
      buildingCost: read('constructionCost', _buildingCost),
      gold: read('gold', _gold),
      zonalValues: read('zonalValues', _zonalValues),
      homeLoans: read('pagibigRates', _homeLoans),
    );
  }
}

double _number(Object? value) => (value as num).toDouble();

double? _numberOrNull(Object? value) => value is num ? value.toDouble() : null;

ReferenceLink _link(Object? value) {
  final source = value as Map<String, dynamic>;
  return ReferenceLink(source['name'] as String, source['url'] as String);
}

List<Map<String, dynamic>> _maps(Object? value) => [
  for (final item in value as List) item as Map<String, dynamic>,
];

InflationFigure _inflation(Map<String, dynamic> data) {
  final analysis = data['analysis'] as Map<String, dynamic>?;
  return InflationFigure(
    ratePercent: _number(data['ratePercent']),
    periodLabel: data['periodLabel'] as String,
    averageLast12Months: _numberOrNull(analysis?['averageLast12Months']),
    source: _link(data['source']),
  );
}

BuildingCost _buildingCost(Map<String, dynamic> data) => BuildingCost(
  year: (data['year'] as num).toInt(),
  pesoPerSqm: _number(data['pesoPerSqm']),
  regions: [
    for (final region in _maps(data['regions']))
      RegionCost(region['name'] as String, _number(region['pesoPerSqm'])),
  ],
  source: _link(data['source']),
);

GoldPrice _gold(Map<String, dynamic> data) => GoldPrice(
  pesoPerGram: _number(data['pesoPerGram']),
  asOf: DateTime.tryParse(data['priceAsOf'] as String? ?? '')?.toLocal(),
  sources: [for (final source in _maps(data['sources'])) _link(source)],
);

ZonalValues _zonalValues(Map<String, dynamic> data) => ZonalValues(
  offices: [
    for (final region in _maps(data['regions']))
      for (final office in _maps(region['offices']))
        ZonalOffice(
          office: office['office'] as String,
          region: region['name'] as String,
          province: office['province'] as String? ?? '',
          places: office['places'] as String? ?? '',
          revisedYear: (office['revisedYear'] as num?)?.toInt(),
          files: [
            for (final file in _maps(office['files'] ?? const []))
              ReferenceLink(file['label'] as String, file['url'] as String),
          ],
        ),
  ],
  source: _link(data['source']),
);

List<LoanRate> _rates(Object? part) => [
  for (final rate in _maps((part as Map<String, dynamic>)['rates']))
    LoanRate(
      fixedYears: (rate['fixedYears'] as num).toInt(),
      ratePercent: _number(rate['ratePercent']),
      loanFrom: _numberOrNull(rate['loanFrom']),
      loanUpTo: _numberOrNull(rate['loanUpTo']),
    ),
];

HomeLoanRates _homeLoans(Map<String, dynamic> data) {
  final standard = data['standard'] as Map<String, dynamic>;
  final promo = data['promo'] as Map<String, dynamic>?;
  return HomeLoanRates(
    standard: _rates(standard),
    promo: promo == null ? const [] : _rates(promo),
    checkedOn: DateTime.parse(data['checkedOn'] as String),
    standardSource: standard['source'] == null
        ? null
        : _link(standard['source']),
    promoSource: promo?['source'] == null ? null : _link(promo!['source']),
    promoAsOf: promo?['asOf'] as String?,
  );
}
