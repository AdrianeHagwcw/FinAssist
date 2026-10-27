import unittest

from price_scraper import checks, gold, pagibig

import samples


class ChecksTest(unittest.TestCase):
    def test_good_figures_pass(self):
        self.assertIsNone(checks.problem_with('inflation', samples.inflation([3.0, 4.1])))
        self.assertIsNone(checks.problem_with('constructionCost', samples.construction()))
        self.assertIsNone(checks.problem_with('gold', gold.parse_gold(*samples.gold_answers())))
        self.assertIsNone(checks.problem_with('zonalValues', samples.zonal_values()))
        self.assertIsNone(checks.problem_with('pagibigRates', pagibig.load_rates()))

    def test_refuses_an_impossible_inflation_rate(self):
        self.assertIn('inflation rate', checks.problem_with('inflation', samples.inflation([3.0, 61.0])))

    def test_refuses_a_cost_in_the_wrong_unit(self):
        # Pesos per square meter read as thousands of pesos.
        data = samples.construction(national=12)

        self.assertIn('national cost', checks.problem_with('constructionCost', data))

    def test_refuses_a_wrong_exchange_rate(self):
        data = gold.parse_gold(*samples.gold_answers(usd_to_php=0.017))

        self.assertIsNotNone(checks.problem_with('gold', data))

    def test_refuses_a_page_that_lost_its_regions(self):
        data = samples.zonal_values(region_count=3)

        self.assertIn('only 3 BIR regions', checks.problem_with('zonalValues', data))

    def test_refuses_when_most_regions_have_no_offices(self):
        data = samples.zonal_values(region_count=12)
        for region in data['regions'][:7]:
            region['offices'] = []

        self.assertIn('7 of 12', checks.problem_with('zonalValues', data))

    def test_allows_a_few_regions_missing(self):
        data = samples.zonal_values(region_count=12)
        data['regions'][0]['offices'] = []

        self.assertIsNone(checks.problem_with('zonalValues', data))

    def test_refuses_offices_without_file_links(self):
        data = samples.zonal_values()
        for region in data['regions']:
            for office in region['offices']:
                office['files'] = []

        self.assertIn('no zonal value files', checks.problem_with('zonalValues', data))

    def test_refuses_rates_without_a_checked_date(self):
        rates = pagibig.load_rates()
        del rates['checkedOn']

        self.assertIn('checkedOn', checks.problem_with('pagibigRates', rates))


if __name__ == '__main__':
    unittest.main()
