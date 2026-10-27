"""Pag-IBIG housing loan rates.

Their site makes programs prove they are human, and getting around that
would not be right, so the rates are kept by hand in
data/pagibig_rates.json, each with where it came from and when it was
checked. The scraper saves them with the rest, so the app finds every price
in one place.
"""

import json
from pathlib import Path

RATES_FILE = Path(__file__).resolve().parent.parent / 'data' / 'pagibig_rates.json'


def load_rates(path=RATES_FILE):
    rates = json.loads(Path(path).read_text(encoding='utf-8'))
    # Notes for whoever updates the file aren't data for the app.
    return {key: value for key, value in rates.items() if not key.startswith('_')}
