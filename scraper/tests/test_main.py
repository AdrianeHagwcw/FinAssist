import unittest

from price_scraper import main

import samples


def failing():
    raise OSError('no internet')


class CollectTest(unittest.TestCase):
    def test_one_source_failing_never_stops_the_others(self):
        collected, results = main.collect(
            sources={
                'inflation': failing,
                'constructionCost': lambda: samples.construction(national=12),
                'zonalValues': samples.zonal_values,
            },
            today='2026-10-27',
        )

        self.assertEqual(results['inflation'], 'failed: no internet')
        self.assertTrue(results['constructionCost'].startswith('failed: national cost'))
        self.assertEqual(results['zonalValues'], 'ok')
        self.assertEqual(list(collected), ['zonalValues'])
        self.assertIn('analysis', collected['zonalValues'])

    def test_a_missing_region_is_kept_from_last_time_and_noted(self):
        def fetch():
            data = samples.zonal_values()
            data['regions'][0] = {'name': 'Revenue Region 1', 'offices': [], 'problem': 'gone'}
            return data

        saved = samples.zonal_values(year=2020)

        collected, results = main.collect(
            sources={'zonalValues': fetch}, saved=lambda name: saved, today='2026-10-27'
        )

        self.assertEqual(results['zonalValues'], 'ok (not on the site this time: Revenue Region 1)')
        region = collected['zonalValues']['regions'][0]
        self.assertEqual(region['offices'], saved['regions'][0]['offices'])

    def test_gold_is_compared_with_the_last_saved_price(self):
        saved = {'history': [{'date': '2026-10-20', 'pesoPerGram': 3500.0}]}

        collected, _ = main.collect(
            sources={'gold': lambda: main.gold.parse_gold(*samples.gold_answers())},
            saved=lambda name: saved,
            today='2026-10-27',
        )

        change = collected['gold']['analysis']['changeSinceLastCheck']
        self.assertEqual(change['since'], '2026-10-20')
        self.assertEqual(change['direction'], 'up')


if __name__ == '__main__':
    unittest.main()
