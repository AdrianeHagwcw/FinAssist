import unittest

from price_scraper import psa

import samples


class InflationTest(unittest.TestCase):
    def test_takes_the_latest_published_month(self):
        rates_2025 = [str(1.0 + i / 10) for i in range(12)]
        # September 2026 is the latest out; later months are '..'.
        rates_2026 = ['2.0', '2.1', '2.2', '2.3', '2.4', '2.5', '2.6', '2.7', '6.1', '..', '..', '..']

        data = psa.parse_inflation(
            samples.inflation_meta(), samples.inflation_data(rates_2025, rates_2026)
        )

        self.assertEqual(data['ratePercent'], 6.1)
        self.assertEqual(data['period'], '2026-09')
        self.assertEqual(data['periodLabel'], 'September 2026')
        # The last 12 months, oldest first, without the yearly averages.
        self.assertEqual(len(data['recent']), 12)
        self.assertEqual(data['recent'][0], {'period': '2025-10', 'ratePercent': 1.9})
        self.assertEqual(data['recent'][-1], {'period': '2026-09', 'ratePercent': 6.1})

    def test_asks_for_the_two_latest_years(self):
        query = psa.inflation_query(samples.inflation_meta())

        years = next(q for q in query['query'] if q['code'] == 'Year')
        self.assertEqual(sorted(years['selection']['values']), ['1', '2'])

    def test_no_figures_is_an_error(self):
        with self.assertRaises(ValueError):
            psa.parse_inflation(samples.inflation_meta(), samples.inflation_data([], []))


class ConstructionTest(unittest.TestCase):
    def test_picks_the_table_with_the_latest_years(self):
        listing = [
            {'id': 'old.px', 'type': 't', 'text': 'Construction: 2006-2021'},
            {'id': 'new.px', 'type': 't', 'text': 'Construction: 2022-2024'},
            {'id': 'folder', 'type': 'l', 'text': 'More 2030'},
        ]

        self.assertEqual(psa.latest_table(listing), 'new.px')

    def test_keeps_the_country_and_regions_only(self):
        self.assertEqual(
            psa.construction_places(samples.PLACE_LABELS),
            [
                ('0', 'Philippines'),
                ('1', 'National Capital Region (NCR)'),
                ('3', 'Region X (Northern Mindanao)'),
            ],
        )

    def test_cost_per_square_meter_is_value_over_floor_area(self):
        places = psa.construction_places(samples.PLACE_LABELS)
        # Value is in thousands of pesos. 2024 is the latest year with
        # national figures; 2022's are not out ('..').
        data = samples.construction_data({
            ('0', '0'): ('1000', '12500'),
            ('0', '1'): ('100', '1600'),
            ('0', '3'): ('200', '1600'),
            ('1', '0'): ('1000', '11800'),
            ('2', '0'): ('..', '..'),
        })

        cost = psa.parse_construction(samples.construction_meta(), data, places, 'new.px')

        self.assertEqual(cost['year'], 2024)
        self.assertEqual(cost['pesoPerSqm'], 12500)
        self.assertEqual(cost['previousYear'], {'year': 2023, 'pesoPerSqm': 11800})
        self.assertEqual(
            [(r['name'], r['pesoPerSqm']) for r in cost['regions']],
            [('National Capital Region (NCR)', 16000), ('Region X (Northern Mindanao)', 8000)],
        )

    def test_uses_the_year_before_when_the_latest_is_not_out(self):
        places = psa.construction_places(samples.PLACE_LABELS)
        data = samples.construction_data({
            ('0', '0'): ('..', '..'),
            ('1', '0'): ('1000', '11800'),
        })

        cost = psa.parse_construction(samples.construction_meta(), data, places, 'new.px')

        self.assertEqual((cost['year'], cost['pesoPerSqm']), (2023, 11800))
        self.assertIsNone(cost['previousYear'])

    def test_asks_for_the_three_latest_years(self):
        query = psa.construction_query(samples.construction_meta(), ['0'])

        years = next(q for q in query['query'] if q['code'] == 'Year')
        self.assertEqual(years['selection']['values'], ['0', '1', '2'])


if __name__ == '__main__':
    unittest.main()
