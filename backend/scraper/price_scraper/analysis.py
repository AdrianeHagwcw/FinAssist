"""Turns the collected figures into findings the app can say in one
sentence: which way a price is going, and how places compare. Each data
set gets them under 'analysis'.

- Inflation: up or down from the month before, the 12-month average, and
  the highest and lowest month.
- Cost of building: the cheapest and priciest regions against the whole
  country, and the change from the year before.
- Gold: a price history kept from run to run, the change since the last
  check, and the highest and lowest price kept.
- Zonal values: how many offices were found, and how many are due for
  their next update (the Tax Code asks for one every three years).
"""

from collections import Counter

GOLD_HISTORY_LENGTH = 180  # About half a year of daily checks.
ZONAL_UPDATE_EVERY_YEARS = 3


def _direction(change):
    if change is None:
        return None
    return 'up' if change > 0 else 'down' if change < 0 else 'same'


def _percent(new, old):
    return round((new - old) / old * 100, 1)


def inflation(data):
    recent = data['recent']
    rates = [month['ratePercent'] for month in recent]
    change = round(rates[-1] - rates[-2], 1) if len(rates) > 1 else None
    return {
        'changeFromPreviousMonth': change,
        'direction': _direction(change),
        'averageLast12Months': round(sum(rates) / len(rates), 1),
        'highest': max(recent, key=lambda month: month['ratePercent']),
        'lowest': min(recent, key=lambda month: month['ratePercent']),
        'monthsCompared': len(rates),
    }


def construction(data):
    national = data['pesoPerSqm']
    regions = sorted(data['regions'], key=lambda region: region['pesoPerSqm'])

    def against_national(region):
        return {
            'name': region['name'],
            'pesoPerSqm': region['pesoPerSqm'],
            'percentVsNational': _percent(region['pesoPerSqm'], national),
        }

    before = data.get('previousYear')
    return {
        'cheapestRegion': against_national(regions[0]) if regions else None,
        'priciestRegion': against_national(regions[-1]) if regions else None,
        'regionsAboveNational': sum(r['pesoPerSqm'] > national for r in regions),
        'regionsBelowNational': sum(r['pesoPerSqm'] < national for r in regions),
        'changeFromPreviousYear': (
            {
                'since': before['year'],
                'percent': _percent(national, before['pesoPerSqm']),
                'direction': _direction(national - before['pesoPerSqm']),
            }
            if before
            else None
        ),
    }


def gold(data, saved, today):
    """Gold's price history, with today's price added. A second run on the
    same day replaces that day's price instead of adding another."""
    day = str(data.get('priceAsOf') or today)[:10]
    kept = [
        entry
        for entry in (saved or {}).get('history', [])
        if entry.get('date') != day
    ]
    history = sorted(
        kept + [{'date': day, 'pesoPerGram': data['pesoPerGram']}],
        key=lambda entry: entry['date'],
    )[-GOLD_HISTORY_LENGTH:]

    change = None
    if len(history) > 1:
        before, now = history[-2], history[-1]
        change = {
            'since': before['date'],
            'pesoPerGram': round(now['pesoPerGram'] - before['pesoPerGram'], 2),
            'percent': _percent(now['pesoPerGram'], before['pesoPerGram']),
            'direction': _direction(now['pesoPerGram'] - before['pesoPerGram']),
        }
    return history, {
        'changeSinceLastCheck': change,
        'highest': max(history, key=lambda entry: entry['pesoPerGram']),
        'lowest': min(history, key=lambda entry: entry['pesoPerGram']),
        'checksKept': len(history),
    }


def zonal_values(data, today):
    regions = data['regions']
    offices = [office for region in regions for office in region['offices']]
    years = [o['revisedYear'] for o in offices if o.get('revisedYear')]
    due_by = int(today[:4]) - ZONAL_UPDATE_EVERY_YEARS
    by_year = Counter(str(o.get('revisedYear') or 'unknown') for o in offices)
    return {
        'officeCount': len(offices),
        'regionCount': len(regions),
        'regionsNotReadThisRun': [r['name'] for r in regions if r.get('problem')],
        'newestUpdateYear': max(years) if years else None,
        'oldestUpdateYear': min(years) if years else None,
        'officesByUpdateYear': dict(sorted(by_year.items())),
        'officesDueForUpdate': sum(year <= due_by for year in years),
        'updateEveryYears': ZONAL_UPDATE_EVERY_YEARS,
    }


def add(name, data, saved=None, today=None):
    """[data] with its findings added. [saved] is what the last run kept,
    for the findings that compare with it; [today] is 'YYYY-MM-DD'."""
    if name == 'inflation':
        return {**data, 'analysis': inflation(data)}
    if name == 'constructionCost':
        return {**data, 'analysis': construction(data)}
    if name == 'gold':
        history, findings = gold(data, saved, today)
        return {**data, 'history': history, 'analysis': findings}
    if name == 'zonalValues':
        return {**data, 'analysis': zonal_values(data, today)}
    return data
