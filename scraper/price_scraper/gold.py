"""The price of gold in pesos per gram.

The Bangko Sentral's site allows only search engines, so it isn't read.
Instead: gold's world price in US dollars from gold-api.com (free, made for
programs, commercial use allowed), turned into pesos with the day's
exchange rate from Frankfurter (free, no key, from central banks).
"""

from .http import get_json

GOLD_URL = 'https://api.gold-api.com/price/XAU'
RATE_URL = 'https://api.frankfurter.dev/v1/latest?from=USD&to=PHP'
GRAMS_PER_TROY_OUNCE = 31.1034768


def parse_gold(gold, rate):
    usd_per_ounce = float(gold['price'])
    usd_to_php = float(rate['rates']['PHP'])
    peso_per_ounce = usd_per_ounce * usd_to_php
    return {
        'pesoPerGram': round(peso_per_ounce / GRAMS_PER_TROY_OUNCE, 2),
        'pesoPerOunce': round(peso_per_ounce, 2),
        'usdPerOunce': round(usd_per_ounce, 2),
        'usdToPhp': usd_to_php,
        'purity': '24k (pure gold); jewelry is usually less pure and costs '
        'more for the work',
        'priceAsOf': gold.get('updatedAt'),
        'rateAsOf': rate.get('date'),
        'sources': [
            {'name': 'Gold API (world gold price)', 'url': 'https://gold-api.com/'},
            {
                'name': 'Frankfurter (US dollar to peso)',
                'url': 'https://frankfurter.dev/',
            },
        ],
    }


def fetch_gold(get=get_json):
    return parse_gold(get(GOLD_URL), get(RATE_URL))
