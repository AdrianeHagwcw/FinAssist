import unittest

from price_scraper import gold

import samples


class GoldTest(unittest.TestCase):
    def test_turns_dollars_per_ounce_into_pesos_per_gram(self):
        data = gold.parse_gold(*samples.gold_answers(usd_per_ounce=2000, usd_to_php=56))

        self.assertEqual(data['pesoPerOunce'], 112000)
        # 112,000 pesos / 31.1034768 grams in a troy ounce.
        self.assertEqual(data['pesoPerGram'], 3600.88)
        self.assertEqual(data['priceAsOf'], '2026-10-27T10:00:53Z')
        self.assertEqual(data['rateAsOf'], '2026-10-26')

    def test_asks_both_sources(self):
        asked = []

        def get(url):
            asked.append(url)
            return samples.gold_answers()[len(asked) - 1]

        gold.fetch_gold(get=get)

        self.assertEqual(asked, [gold.GOLD_URL, gold.RATE_URL])


if __name__ == '__main__':
    unittest.main()
