import unittest
from datetime import date, timedelta

from price_scraper import analysis

import samples


class InflationTest(unittest.TestCase):
    def test_compares_with_the_month_before(self):
        rates = [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 6.1, 7.2]

        found = analysis.inflation(samples.inflation(rates))

        self.assertEqual(found['changeFromPreviousMonth'], 1.1)
        self.assertEqual(found['direction'], 'up')
        self.assertEqual(found['averageLast12Months'], 2.9)
        self.assertEqual(found['highest']['ratePercent'], 7.2)
        self.assertEqual(found['lowest'], {'period': '2026-01', 'ratePercent': 2.0})

    def test_a_single_month_has_nothing_to_compare(self):
        found = analysis.inflation(samples.inflation([3.0]))

        self.assertIsNone(found['changeFromPreviousMonth'])
        self.assertIsNone(found['direction'])


class ConstructionTest(unittest.TestCase):
    def test_compares_regions_with_the_whole_country(self):
        found = analysis.construction(samples.construction())

        self.assertEqual(
            found['priciestRegion'],
            {'name': 'NCR', 'pesoPerSqm': 16000, 'percentVsNational': 33.3},
        )
        self.assertEqual(found['cheapestRegion']['percentVsNational'], -33.3)
        self.assertEqual((found['regionsAboveNational'], found['regionsBelowNational']), (1, 1))
        self.assertEqual(
            found['changeFromPreviousYear'], {'since': 2023, 'percent': 9.1, 'direction': 'up'}
        )


class GoldTest(unittest.TestCase):
    def gold(self, price, as_of):
        return {'pesoPerGram': price, 'priceAsOf': f'{as_of}T10:00:00Z'}

    def test_the_first_run_starts_the_history(self):
        history, found = analysis.gold(self.gold(8000, '2026-10-27'), None, '2026-10-27')

        self.assertEqual(history, [{'date': '2026-10-27', 'pesoPerGram': 8000}])
        self.assertIsNone(found['changeSinceLastCheck'])

    def test_compares_with_the_last_check(self):
        saved = {'history': [{'date': '2026-10-20', 'pesoPerGram': 8000}]}

        history, found = analysis.gold(self.gold(8200, '2026-10-27'), saved, '2026-10-27')

        self.assertEqual(len(history), 2)
        self.assertEqual(
            found['changeSinceLastCheck'],
            {'since': '2026-10-20', 'pesoPerGram': 200, 'percent': 2.5, 'direction': 'up'},
        )
        self.assertEqual(found['highest']['pesoPerGram'], 8200)

    def test_a_second_run_the_same_day_replaces_that_day(self):
        saved = {'history': [{'date': '2026-10-27', 'pesoPerGram': 8000}]}

        history, _ = analysis.gold(self.gold(8100, '2026-10-27'), saved, '2026-10-27')

        self.assertEqual(history, [{'date': '2026-10-27', 'pesoPerGram': 8100}])

    def test_keeps_about_half_a_year(self):
        first = date(2026, 1, 1)
        saved = {
            'history': [
                {'date': (first + timedelta(days=i)).isoformat(), 'pesoPerGram': 7000 + i}
                for i in range(200)
            ]
        }

        history, _ = analysis.gold(self.gold(9000, '2026-10-27'), saved, '2026-10-27')

        self.assertEqual(len(history), analysis.GOLD_HISTORY_LENGTH)
        self.assertEqual(history[-1]['date'], '2026-10-27')


class ZonalValuesTest(unittest.TestCase):
    def test_counts_offices_due_for_an_update(self):
        data = samples.zonal_values(region_count=2, offices_each=2, year=2024)
        data['regions'][0]['offices'][0]['revisedYear'] = 2019
        data['regions'][1]['problem'] = 'gone'

        found = analysis.zonal_values(data, '2026-10-27')

        self.assertEqual(found['officeCount'], 4)
        self.assertEqual(found['regionsNotReadThisRun'], ['Revenue Region 2'])
        # 2026 - 3 years: values from 2023 or before are due.
        self.assertEqual(found['officesDueForUpdate'], 1)
        self.assertEqual(found['officesByUpdateYear'], {'2019': 1, '2024': 3})
        self.assertEqual((found['oldestUpdateYear'], found['newestUpdateYear']), (2019, 2024))


class AddTest(unittest.TestCase):
    def test_hand_kept_rates_have_nothing_to_analyze(self):
        rates = {'standard': {}, 'promo': {}}

        self.assertEqual(analysis.add('pagibigRates', rates), rates)


if __name__ == '__main__':
    unittest.main()
