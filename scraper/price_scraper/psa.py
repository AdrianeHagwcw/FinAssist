"""Inflation and the cost of building a house, from the Philippine
Statistics Authority's OpenSTAT.

OpenSTAT's robots.txt lets programs read it (it only forbids AI training).
Its web pages turn programs away, but its official data API answers them,
so the data is read through the API: the same tables people see on the
site, in a form that changes far less often than a page's layout.
"""

import re

from .http import get_json, post_json

API = 'https://openstat.psa.gov.ph/PXWeb/api/v1/en/DB'
SITE = 'https://openstat.psa.gov.ph/PXWeb/pxweb/en/DB'

# Year-on-year change of the Consumer Price Index (2018=100): inflation.
INFLATION_TABLE = '2M/PI/CPI/2018NEW/0012M4ACP23.px'
# Construction Statistics from Approved Building Permits. A new table is
# added for each set of years, so the newest one is found each run.
CONSTRUCTION_FOLDER = '2G/CONS/BGP'

MONTHS = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
]
MONTH_NAMES = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
]


def page_url(path):
    """The table's page on the PSA site, for people to check a figure."""
    folder, table = path.rsplit('/', 1)
    return f"{SITE}/DB__{folder.replace('/', '__')}/{table}"


def _variable(meta, code):
    return next(v for v in meta['variables'] if v['code'] == code)


def _value_for(variable, text):
    """The code of the value whose label is [text], ignoring case."""
    for value, label in zip(variable['values'], variable['valueTexts']):
        if label.strip().lower() == text.lower():
            return value
    raise ValueError(f"PSA table has no '{text}' in {variable['code']}")


def _latest_years(meta, count):
    """The codes of the [count] latest years, whatever order the table
    lists its years in."""
    year = _variable(meta, 'Year')
    newest_first = sorted(
        zip(year['valueTexts'], year['values']),
        key=lambda pair: int(re.sub(r'\D', '', pair[0]) or 0),
        reverse=True,
    )
    return [code for _, code in newest_first[:count]]


def _number(text):
    """A cell as a number, or None for PSA's '..' (not published yet)."""
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- inflation

def inflation_query(meta):
    """The whole Philippines, all items, every month of the last two years."""
    return {
        'query': [
            {
                'code': 'Geolocation',
                'selection': {
                    'filter': 'item',
                    'values': [
                        _value_for(_variable(meta, 'Geolocation'), 'PHILIPPINES')
                    ],
                },
            },
            {
                'code': 'Commodity Description',
                'selection': {
                    'filter': 'item',
                    'values': [
                        _value_for(
                            _variable(meta, 'Commodity Description'),
                            '0 - ALL ITEMS',
                        )
                    ],
                },
            },
            {
                'code': 'Year',
                'selection': {'filter': 'item', 'values': _latest_years(meta, 2)},
            },
        ],
        'response': {'format': 'json'},
    }


def parse_inflation(meta, data):
    year = _variable(meta, 'Year')
    period = _variable(meta, 'Period')
    year_of = dict(zip(year['values'], year['valueTexts']))
    month_of = dict(zip(period['values'], period['valueTexts']))
    columns = [c['code'] for c in data['columns']]

    months = []
    for row in data['data']:
        key = dict(zip(columns, row['key']))
        month = month_of.get(key['Period'], '')
        rate = _number(row['values'][0])
        # The yearly average isn't a month; '..' is a month not out yet.
        if month not in MONTHS or rate is None:
            continue
        months.append((int(year_of[key['Year']]), MONTHS.index(month) + 1, rate))
    if not months:
        raise ValueError('PSA returned no inflation figures')

    months.sort()
    latest_year, latest_month, latest_rate = months[-1]
    return {
        'ratePercent': latest_rate,
        'period': f'{latest_year}-{latest_month:02d}',
        'periodLabel': f'{MONTH_NAMES[latest_month - 1]} {latest_year}',
        'recent': [
            {'period': f'{y}-{m:02d}', 'ratePercent': r} for y, m, r in months[-12:]
        ],
        'scope': 'Philippines, all items (2018=100)',
        'source': {
            'name': 'Philippine Statistics Authority (OpenSTAT)',
            'url': page_url(INFLATION_TABLE),
        },
    }


def fetch_inflation(get=get_json, post=post_json):
    meta = get(f'{API}/{INFLATION_TABLE}')
    data = post(f'{API}/{INFLATION_TABLE}', inflation_query(meta))
    return parse_inflation(meta, data)


# ------------------------------------------------------ cost of building

def latest_table(listing):
    """The table covering the latest years, from a folder listing, such as
    "...: 2022-2024" over "...: 2006-2021"."""
    tables = [t for t in listing if t.get('type') == 't']

    def last_year(table):
        years = re.findall(r'(\d{4})', table['text'])
        return int(years[-1]) if years else 0

    if not tables:
        raise ValueError('PSA construction folder has no tables')
    return max(tables, key=last_year)['id']


def construction_places(labels):
    """The country and its regions, leaving out provinces and cities. PSA
    marks each level down with two more leading dots."""
    places = []
    for code, label in labels.items():
        depth = (len(label) - len(label.lstrip('.'))) // 2
        if depth <= 1:
            name = label.lstrip('.').strip()
            places.append((code, 'Philippines' if depth == 0 else name))
    return places


def _selection(code, values, filter_='item'):
    return {'code': code, 'selection': {'filter': filter_, 'values': values}}


def place_label_query(meta):
    """Every place's name, asked for with as little data as possible: one
    year, one item. Only the labels are used."""
    return {
        'query': [
            _selection('Year', _latest_years(meta, 1)),
            _selection(
                'Period', [_value_for(_variable(meta, 'Period'), 'Annual')]
            ),
            _selection('Geolocation', ['*'], 'all'),
            _selection(
                'Type', [_value_for(_variable(meta, 'Type'), 'Residential')]
            ),
            _selection(
                'Item', [_value_for(_variable(meta, 'Item'), 'Floor area')]
            ),
        ],
        'response': {'format': 'json-stat2'},
    }


def construction_query(meta, place_codes):
    """Residential buildings, the yearly total, in the given places, for the
    last three years: the latest may not be complete yet, and the one
    before the latest complete year is needed to compare with."""
    item = _variable(meta, 'Item')
    return {
        'query': [
            _selection('Year', _latest_years(meta, 3)),
            _selection(
                'Period', [_value_for(_variable(meta, 'Period'), 'Annual')]
            ),
            _selection('Geolocation', place_codes),
            _selection(
                'Type', [_value_for(_variable(meta, 'Type'), 'Residential')]
            ),
            _selection(
                'Item',
                [_value_for(item, 'Floor area'), _value_for(item, 'Value')],
            ),
        ],
        'response': {'format': 'json'},
    }


def parse_construction(meta, data, places, table):
    """Peso cost per square meter: the value of the buildings divided by
    their floor area. PSA gives the value in thousands of pesos."""
    year = _variable(meta, 'Year')
    item = _variable(meta, 'Item')
    year_of = dict(zip(year['values'], year['valueTexts']))
    floor_area = _value_for(item, 'Floor area')
    value = _value_for(item, 'Value')
    columns = [c['code'] for c in data['columns']]

    # {year: {place: {'area': ..., 'value': ...}}}
    figures = {}
    for row in data['data']:
        key = dict(zip(columns, row['key']))
        number = _number(row['values'][0])
        if number is None or key['Item'] not in (floor_area, value):
            continue
        field = 'area' if key['Item'] == floor_area else 'value'
        place = figures.setdefault(int(year_of[key['Year']]), {}).setdefault(
            key['Geolocation'], {}
        )
        place[field] = number

    country_code = places[0][0]
    for latest in sorted(figures, reverse=True):
        country = figures[latest].get(country_code, {})
        if country.get('area') and country.get('value'):
            break
    else:
        raise ValueError('PSA returned no national construction figures')

    def per_sqm(code, year=latest):
        place = figures.get(year, {}).get(code, {})
        if not place.get('area') or not place.get('value'):
            return None
        return round(place['value'] * 1000 / place['area'])

    regions = []
    for code, name in places[1:]:
        cost = per_sqm(code)
        if cost is not None:
            regions.append({'code': code, 'name': name, 'pesoPerSqm': cost})

    before = per_sqm(country_code, latest - 1)
    return {
        'year': latest,
        'pesoPerSqm': per_sqm(country_code),
        'previousYear': (
            {'year': latest - 1, 'pesoPerSqm': before} if before is not None else None
        ),
        'regions': regions,
        'basis': 'Residential buildings from approved building permits, '
        'yearly average cost per square meter',
        'source': {
            'name': 'Philippine Statistics Authority (OpenSTAT)',
            'url': page_url(f'{CONSTRUCTION_FOLDER}/{table}'),
        },
    }


def fetch_construction_cost(get=get_json, post=post_json):
    table = latest_table(get(f'{API}/{CONSTRUCTION_FOLDER}'))
    url = f'{API}/{CONSTRUCTION_FOLDER}/{table}'
    meta = get(url)
    # The place names come from a json-stat2 answer, which labels every
    # place. Its numbers are not used: PSA sends those reliably only in the
    # plain json answer below.
    labelled = post(url, place_label_query(meta))
    places = construction_places(
        labelled['dimension']['Geolocation']['category']['label']
    )
    data = post(url, construction_query(meta, [code for code, _ in places]))
    return parse_construction(meta, data, places, table)
