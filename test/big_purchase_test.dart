import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/big_purchase.dart';
import 'package:testapp/models/chat_answers.dart';
import 'package:testapp/models/chat_language.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/price_references.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/screens/chatbot_screen.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/utils/money_format.dart';

/// Thursday, Oct 15, 2026.
final now = DateTime(2026, 10, 15, 10);

/// 90 days of records: ₱300 of food every day and [income] on the 1st of
/// Aug, Sep and Oct, with ₱30,000 in cash now. At ₱30,000 income, about
/// ₱21,000 is left each month (₱30,000 in, ₱9,000 out), and ₱25,200 is
/// spare by month end (₱30,000 less 16 more days of food).
FinanceSnapshot records({double income = 30000}) => FinanceSnapshot(
  now: now,
  wallets: const [
    Wallet(
      id: 'cash',
      name: 'Cash',
      type: WalletType.cash,
      balance: 30000,
      startingBalance: 30000,
      receivesIncome: true,
      archived: false,
      sortOrder: 0,
    ),
  ],
  transactions: [
    for (
      var day = DateTime(2026, 7, 18);
      !day.isAfter(DateTime(2026, 10, 15));
      day = day.add(const Duration(days: 1))
    )
      AppTransaction(
        id: 'food-$day',
        type: TransactionType.expense,
        amount: 300,
        label: 'Food',
        date: day.add(const Duration(hours: 12)),
      ),
    for (final month in [8, 9, 10])
      AppTransaction(
        id: 'pay-$month',
        type: TransactionType.income,
        amount: income,
        label: 'Salary',
        date: DateTime(2026, month, 1, 9),
      ),
  ],
);

const pagibig = ReferenceLink('Pag-IBIG rates', 'https://pagibig.example');
const buildingSource = ReferenceLink(
  'PSA building cost',
  'https://psa.example',
);
const goldSource = ReferenceLink('Gold API', 'https://gold-api.com/');

final prices = PriceReferences(
  inflation: const InflationFigure(
    ratePercent: 7.2,
    periodLabel: 'September 2026',
    averageLast12Months: 4.5,
    source: ReferenceLink('PSA inflation', 'https://psa.example/cpi'),
  ),
  buildingCost: const BuildingCost(
    year: 2024,
    pesoPerSqm: 12591,
    regions: [
      RegionCost('National Capital Region (NCR)', 16021),
      RegionCost('Region IV-A (CALABARZON)', 12713),
      RegionCost('Region VII (Central Visayas)', 10937),
    ],
    source: buildingSource,
  ),
  gold: const GoldPrice(pesoPerGram: 8000, sources: [goldSource]),
  zonalValues: const ZonalValues(
    offices: [
      ZonalOffice(
        office: 'RDO No. 24-Valenzuela City',
        region: 'Revenue Region 5 - Caloocan',
        province: '',
        places: 'Barangays Arkong Bato, Bagbaguin, Malinta',
        revisedYear: 2021,
        files: [
          ReferenceLink('View RDO No. 24 excel', 'https://bir.example/24.zip'),
        ],
      ),
      ZonalOffice(
        office: 'RDO No. 58-Batangas City',
        region: 'Revenue Region 9A - CABAMIRO',
        province: 'Batangas',
        places: 'Batangas City, Lipa City, Tanauan City, Santo Tomas',
        revisedYear: 2023,
        files: [
          ReferenceLink('View RDO No. 58 excel', 'https://bir.example/58.zip'),
        ],
      ),
    ],
    source: ReferenceLink('BIR', 'https://www.bir.gov.ph/zonal-values'),
  ),
  homeLoans: HomeLoanRates(
    standard: const [
      LoanRate(fixedYears: 1, ratePercent: 5.75),
      LoanRate(fixedYears: 3, ratePercent: 6.25),
    ],
    promo: const [LoanRate(fixedYears: 3, ratePercent: 4.5, loanUpTo: 2500000)],
    checkedOn: DateTime(2026, 10, 27),
    standardSource: pagibig,
    promoAsOf: '2026-06',
  ),
);

ChatReply ask(
  String question, {
  PurchaseQuestion? pending,
  FinanceSnapshot? from,
  PriceReferences? using,
  bool noPrices = false,
  ChatLanguage? language,
}) => answerChat(
  question,
  records: from ?? records(),
  pending: pending,
  language: language,
  prices: noPrices ? null : using ?? prices,
);

void main() {
  group('the math', () {
    test('a loan pays back the same amount every month', () {
      // ₱2.4M at 6.25% a year over 30 years.
      expect(monthlyLoanPayment(2400000, 6.25, 30).round(), 14777);
      expect(monthlyLoanPayment(120000, 0, 10), 1000);
      final payment = monthlyLoanPayment(1000000, 6.25, 30);
      expect(loanForPayment(payment, 6.25, 30), closeTo(1000000, 0.01));
    });

    test('months to save, with and without prices rising', () {
      expect(monthsToReach(price: 1000, saved: 100, perMonth: 300), 3);
      expect(monthsToReach(price: 1000, saved: 1000, perMonth: 0), 0);
      expect(monthsToReach(price: 1000, saved: 0, perMonth: 0), isNull);
      expect(monthsToReach(price: 12000, saved: 0, perMonth: 500), 24);
      expect(
        monthsToReach(price: 12000, saved: 0, perMonth: 500, yearlyRise: 10),
        greaterThan(24),
      );
      // Prices rising faster than saving can catch up: never.
      expect(
        monthsToReach(price: 1e9, saved: 0, perMonth: 1, yearlyRise: 10),
        isNull,
      );
    });

    test('gold is worth its weight times its share of pure gold', () {
      expect(goldWorth(10, 18, 8000), 60000);
      expect(goldWorth(5, 24, 8000), 40000);
    });

    test('the saving pace is income less spending, a month', () {
      final pace = savingPaceOf(records())!;
      expect(pace.days, 90);
      expect(pace.income, closeTo(30000, 0.01));
      expect(pace.spending, closeTo(9000, 0.01));
      expect(pace.perMonth, closeTo(21000, 0.01));
      expect(pace.categories.single.key, 'Food');
      expect(pace.isRough, isFalse);
    });

    test('income in a short stretch is never scaled up', () {
      // 20 days of records with one ₱20,000 pay: ₱20,000 a month, not
      // ₱30,000. Spending, which goes on every day, is scaled to a month.
      final short = FinanceSnapshot(
        now: now,
        transactions: [
          for (var day = 26; day <= 45; day++)
            AppTransaction(
              id: 'food-$day',
              type: TransactionType.expense,
              amount: 300,
              label: 'Food',
              date: DateTime(2026, 9, day, 12),
            ),
          AppTransaction(
            id: 'pay',
            type: TransactionType.income,
            amount: 20000,
            label: 'Salary',
            date: DateTime(2026, 10, 1),
          ),
        ],
      );
      final pace = savingPaceOf(short)!;
      expect(pace.days, 20);
      expect(pace.income, closeTo(20000, 0.01));
      expect(pace.spending, closeTo(9000, 0.01));
      expect(pace.isRough, isTrue);
    });

    test('under two weeks of records shows no pace yet', () {
      final week = FinanceSnapshot(
        now: now,
        transactions: [
          AppTransaction(
            id: 'food',
            type: TransactionType.expense,
            amount: 300,
            label: 'Food',
            date: DateTime(2026, 10, 9),
          ),
        ],
      );
      expect(savingPaceOf(week), isNull);
    });

    test('a place names its region, the most specific match first', () {
      final cost = prices.buildingCost!;
      expect(regionCostIn('house in Cebu', cost)?.pesoPerSqm, 10937);
      expect(regionCostIn('condo in Quezon City', cost)?.pesoPerSqm, 16021);
      expect(regionCostIn('bahay sa Lucena, Quezon', cost)?.pesoPerSqm, 12713);
      expect(regionCostIn('a house', cost), isNull);
    });

    test('a town finds the BIR office with its land values', () {
      final values = prices.zonalValues!;
      expect(
        zonalOfficesIn(
          'a lot in Valenzuela for ₱1,500,000',
          values,
        ).single.office,
        'RDO No. 24-Valenzuela City',
      );
      expect(
        zonalOfficesIn('lote sa Tanauan, Batangas', values).single.office,
        'RDO No. 58-Batangas City',
      );
      expect(zonalOfficesIn('a lot', values), isEmpty);
    });
  });

  group('reading the saved prices', () {
    Map<String, Map<String, dynamic>> documents() => {
      'inflation': {
        'ratePercent': 7.2,
        'periodLabel': 'September 2026',
        'analysis': {'averageLast12Months': 4.5},
        'source': {'name': 'PSA', 'url': 'https://psa.example'},
      },
      'constructionCost': {
        'year': 2024,
        'pesoPerSqm': 12591,
        'regions': [
          {
            'code': '1',
            'name': 'National Capital Region (NCR)',
            'pesoPerSqm': 16021,
          },
        ],
        'source': {'name': 'PSA', 'url': 'https://psa.example'},
      },
      'gold': {
        'pesoPerGram': 8231.2,
        'priceAsOf': '2026-10-27T10:00:53Z',
        'sources': [
          {'name': 'Gold API', 'url': 'https://gold-api.com/'},
        ],
      },
      'zonalValues': {
        'regions': [
          {
            'name': 'Revenue Region 5 - Caloocan',
            'offices': [
              {
                'office': 'RDO No. 24-Valenzuela City',
                'province': '',
                'places': 'Malinta',
                'revisedYear': 2021,
                'files': [
                  {'label': 'File', 'url': 'https://bir.example/24.zip'},
                ],
              },
            ],
          },
        ],
        'source': {'name': 'BIR', 'url': 'https://www.bir.gov.ph'},
      },
      'pagibigRates': {
        'checkedOn': '2026-10-27',
        'standard': {
          'rates': [
            {'fixedYears': 3, 'ratePercent': 6.25},
          ],
          'source': {'name': 'Moneymax', 'url': 'https://moneymax.example'},
        },
        'promo': {
          'asOf': '2026-06',
          'rates': [
            {'loanUpTo': 2500000, 'fixedYears': 3, 'ratePercent': 4.5},
          ],
        },
      },
    };

    test('reads every part the scraper saves', () {
      final read = PriceReferences.fromDocuments(documents());
      expect(read.inflation?.yearlyRise, 4.5);
      expect(read.buildingCost?.regions.single.pesoPerSqm, 16021);
      expect(read.gold?.pesoPerGram, 8231.2);
      expect(read.gold?.asOf?.toUtc(), DateTime.utc(2026, 10, 27, 10, 0, 53));
      expect(read.zonalValues?.offices.single.files.single.url, contains('24'));
      expect(read.homeLoans?.standardFor(3)?.ratePercent, 6.25);
      expect(read.homeLoans?.promoFor(2400000)?.ratePercent, 4.5);
      expect(read.homeLoans?.promoFor(3000000), isNull);
    });

    test('a part in an unexpected shape is left out, not the rest', () {
      final broken = documents();
      broken['gold'] = {'pesoPerGram': 'a lot'};

      final read = PriceReferences.fromDocuments(broken);

      expect(read.gold, isNull);
      expect(read.inflation, isNotNull);
      expect(read.homeLoans, isNotNull);
    });
  });

  group('how long until I can afford it', () {
    test('saving what is usually left each month', () {
      // ₱25,200 spare by month end, then ₱21,000 a month: 4 months.
      final reply = ask('How long until I can afford a ₱100,000 laptop?');
      expect(
        reply.text,
        contains(
          'At your usual pace, about ₱21,000 is left each month '
          '(₱30,000 in, ₱9,000 out).',
        ),
      );
      expect(
        reply.text,
        contains(
          "Saving that, you'd have enough by about February 2027 "
          '(about 4 months).',
        ),
      );
      expect(reply.text, isNot(contains('does not include future income')));
      expect(reply.goal?.date, DateTime(2027, 2, 28));
    });

    test('in Tagalog', () {
      final reply = ask(
        'Gaano katagal bago ko mabili ang laptop na ₱100,000?',
        language: ChatLanguage.tagalog,
      );
      expect(reply.filipino, isTrue);
      expect(reply.text, contains('aabot ka bandang Pebrero 2027'));
    });

    test('spending more than earning: why, and where to start', () {
      final reply = ask(
        'Can I buy a ₱100,000 laptop?',
        from: records(income: 5000),
      );
      expect(
        reply.text,
        contains(
          'nothing is left to save: about ₱9,000 goes out each month '
          'and only ₱5,000 comes in',
        ),
      );
      expect(
        reply.text,
        contains(
          'You spend more than you earn, so start with your biggest '
          'day-to-day costs: Food (₱9,000 a month).',
        ),
      );
      expect(reply.goal, isNull);
    });

    test('a date further away counts what is usually left each month', () {
      // ₱25,200 by month end, then ₱21,000 in each of Nov and Dec.
      final reply = ask('Can I buy a ₱60,000 phone by December?');
      expect(reply.text, contains('Yes, you can buy the phone (₱60,000)'));
      expect(reply.text, contains("what's usually left of your income"));
    });
  });

  group('a house or lot', () {
    test('what to save first, the monthly payment, and if it fits', () {
      final reply = ask('Can I buy a house worth ₱3,000,000?');
      expect(
        reply.text,
        contains(
          "you'd first save about ₱750,000: a 20% down payment "
          '(₱600,000) plus about 5% (₱150,000)',
        ),
      );
      expect(reply.text, contains('about ₱14,777 a month for 30 years'));
      // ₱14,777 is more than 35% of ₱30,000.
      final biggest = loanForPayment(30000 * 0.35, 6.25, 30) / 0.8;
      expect(
        reply.text,
        contains(
          'A house up to about ${formatPeso(biggest.roundToDouble())} '
          'keeps the payment within it.',
        ),
      );
      expect(
        reply.text,
        contains(
          'lower 4.5% rate for loans this size in '
          'June 2026',
        ),
      );
      expect(reply.goal?.name, 'Down payment for house');
      expect(reply.goal?.target, 750000);
      expect(reply.useLocalAnswer, isTrue);
      expect(reply.sources.first, pagibig);
    });

    test('"2M", a smaller down payment and a shorter loan', () {
      final reply = ask('Can I buy a house for 2M, 10% down, 20 years loan?');
      expect(reply.text, contains('the house (₱2,000,000)'));
      expect(reply.text, contains('a 10% down payment (₱200,000)'));
      expect(reply.text, contains('for 20 years'));
    });

    test('the cost to build, from a size and a place', () {
      final reply = ask('Can I afford to build a 60 sqm house in Cebu?');
      expect(
        reply.text,
        startsWith(
          'Building 60 sqm costs about ₱656,220, at ₱10,937 per sqm, '
          "the PSA's 2024 average for Region VII (Central Visayas).",
        ),
      );
      expect(reply.sources, contains(buildingSource));
    });

    test('no price yet: a size will do', () {
      final first = ask('Can I buy a house?');
      expect(first.text, contains('like "60 sqm"'));
      expect(first.text, contains('₱12,591 per sqm (PSA, 2024)'));
      expect(first.pending?.waitingFor, PurchaseStep.price);

      final answer = ask('80 sqm', pending: first.pending);
      expect(answer.text, startsWith('Building 80 sqm costs about ₱1,007,280'));
      expect(answer.text, contains('for the whole country'));
    });

    test('a lot points to the BIR land values for its town', () {
      final reply = ask('Can I buy a lot in Valenzuela for ₱1,500,000?');
      expect(
        reply.text,
        contains(
          'RDO No. 24-Valenzuela City, last updated in '
          '2021',
        ),
      );
      expect(
        reply.sources.map((source) => source.url),
        contains('https://bir.example/24.zip'),
      );
    });

    test('in Tagalog', () {
      final reply = ask(
        'Gaano katagal bago ko mabili ang bahay na ₱3,000,000?',
        language: ChatLanguage.tagalog,
      );
      expect(
        reply.text,
        contains(
          'kailangan mo munang mag-ipon ng mga '
          '₱750,000',
        ),
      );
      expect(reply.goal?.name, 'Down payment sa bahay');
    });

    test('without the saved prices, it still says what to save', () {
      final reply = ask('Can I buy a house worth ₱3,000,000?', noPrices: true);
      expect(reply.text, contains('about ₱750,000'));
      expect(reply.text, contains("I couldn't load home loan rates"));
    });

    test('is never sent to a web search', () {
      expect(productPriceLookupQuery('Can I buy a house?'), isNull);
      expect(productPriceLookupQuery('Can I buy a gold necklace?'), isNull);
      expect(
        productPriceLookupQuery('How much is a house in Cebu?'),
        isNotNull,
      );
    });
  });

  group('gold', () {
    test("its weight gives what its gold is worth, then the shop's price", () {
      final first = ask('Can I buy a 10 grams 18k gold necklace?');
      expect(
        first.text,
        startsWith(
          '10 grams of 18k gold is worth about ₱60,000: pure gold is '
          '₱8,000 a gram.',
        ),
      );
      expect(first.choices, ['Use ₱60,000', notSure]);

      final atWorth = ask('Use ₱60,000', pending: first.pending);
      expect(atWorth.text, contains("That's what its gold alone is worth"));
      expect(atWorth.useLocalAnswer, isTrue);

      final atShop = ask('₱75,000', pending: first.pending);
      expect(
        atShop.text,
        contains(
          "That's about 25% more than its gold is "
          'worth (₱60,000 for 10 g, 18k)',
        ),
      );

      // Not sure of the shop's price: the gold's worth is the least it costs.
      final unsure = ask(notSure, pending: first.pending);
      expect(unsure.text, contains('short of ₱60,000'));
      expect(unsure.text, contains("That's what its gold alone is worth"));
    });

    test('no weight yet: asks for it, or the price', () {
      final first = ask('Can I buy gold earrings?');
      expect(first.text, contains('How many grams is it'));
      final answer = ask('5 grams 22k', pending: first.pending);
      expect(
        answer.text,
        startsWith(
          '5 grams of 22k gold is worth about '
          '₱36,667',
        ),
      );
    });

    test('18k is not read as ₱18,000', () {
      final reply = ask('Can I buy a 18k gold ring?');
      expect(reply.pending?.price, isNull);
    });
  });

  testWidgets('the sources show under the answer as links', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChatbotScreen(
          onlineStatus: Stream.value(false),
          records: Stream.value(records()),
          loadPrices: () async => prices,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      'Can I buy a lot in Valenzuela for ₱1,500,000?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(find.text('Sources'), findsOneWidget);
    expect(
      find.text('BIR land values: RDO No. 24-Valenzuela City'),
      findsOneWidget,
    );
    expect(find.text('Pag-IBIG rates'), findsOneWidget);
  });

  group('Taglish and Tagalog ways of asking', () {
    test('"Ilang months bago ko mabili…"', () {
      final reply = ask(
        'Ilang months bago ko mabili yung laptop na 50k?',
        language: ChatLanguage.tagalog,
      );
      expect(reply.text, contains('Kung iipunin mo iyon, aabot ka bandang'));
      expect(reply.goal?.name, 'Laptop');
    });

    test('"How long bago ko mabili…", in English with Tagalog ready', () {
      const question = 'How long bago ko mabili yung condo na 4M, 10% down?';
      final english = ask(question, language: ChatLanguage.english);
      final tagalog = ask(question, language: ChatLanguage.tagalog);
      expect(english.text, contains('the condo (₱4,000,000)'));
      expect(english.text, contains('a 10% down payment (₱400,000)'));
      expect(tagalog.filipino, isTrue);
      expect(tagalog.text, contains('mag-ipon ng mga ₱600,000'));
    });

    test('"Pwede ba ako bumili ng…" gold', () {
      final reply = ask(
        'Pwede ba ako bumili ng 10 grams na 18k gold necklace?',
        language: ChatLanguage.tagalog,
      );
      expect(
        reply.text,
        startsWith(
          'Ang 10 gramo ng 18k na ginto ay mga '
          '₱60,000',
        ),
      );
      expect(reply.pending?.waitingFor, PurchaseStep.price);
    });

    test('"Kaya ko bang magpatayo ng…" a house', () {
      final reply = ask(
        'Kaya ko bang magpatayo ng 60 sqm na bahay sa Cebu?',
        language: ChatLanguage.tagalog,
      );
      expect(
        reply.text,
        startsWith(
          'Ang pagpapatayo ng 60 sqm ay mga '
          '₱656,220',
        ),
      );
    });

    test('"how long until I get paid" is not about buying', () {
      final reply = ask('How long until I get paid?');
      expect(reply.pending, isNull);
      expect(reply.goal, isNull);
      expect(reply.text, isNot(contains('What would you like to buy')));
    });
  });

  testWidgets('a Taglish answer switches to Tagalog, figures and all', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChatbotScreen(
          onlineStatus: Stream.value(false),
          records: Stream.value(records()),
          loadPrices: () async => prices,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      'How long bago ko mabili yung condo na 4M?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(
      find.textContaining('To get the condo (₱4,000,000) with a home loan'),
      findsOneWidget,
    );
    final translate = find.text('Translate into Tagalog');
    await tester.ensureVisible(translate);
    await tester.pumpAndSettle();
    await tester.tap(translate);
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Para makuha ang condo (₱4,000,000) gamit ang '
        'housing loan',
      ),
      findsOneWidget,
    );
  });
}
