"""Checks every figure before it is saved, so a changed page or a bad
answer can never put a wrong price in the app. A figure outside a sensible
range is refused, and the last good one stays."""

import re


def _between(value, low, high, what):
    if not isinstance(value, (int, float)) or not low <= value <= high:
        return f'{what} {value!r} is outside {low} to {high}'
    return None


def _first(*problems):
    return next((p for p in problems if p), None)


def inflation_problem(data):
    if not re.fullmatch(r'\d{4}-\d{2}', str(data.get('period'))):
        return f"inflation period {data.get('period')!r} isn't a month"
    return _first(
        _between(data.get('ratePercent'), -10, 30, 'inflation rate'),
        *[
            _between(month.get('ratePercent'), -10, 30, 'inflation rate')
            for month in data.get('recent', [])
        ],
    )


def construction_problem(data):
    # Houses cost thousands of pesos per square meter, not tens or millions:
    # a figure far off means a unit changed at the source.
    before = data.get('previousYear')
    return _first(
        _between(data.get('year'), 2015, 2100, 'construction year'),
        _between(data.get('pesoPerSqm'), 3000, 60000, 'national cost per sqm'),
        before
        and _between(before.get('pesoPerSqm'), 3000, 60000, 'last year cost'),
        *[
            _between(
                region.get('pesoPerSqm'), 3000, 80000, f"{region.get('name')} cost"
            )
            for region in data.get('regions', [])
        ],
    )


def gold_problem(data):
    return _first(
        _between(data.get('usdPerOunce'), 500, 20000, 'gold price (USD/oz)'),
        _between(data.get('usdToPhp'), 30, 150, 'dollar to peso rate'),
        _between(data.get('pesoPerGram'), 500, 50000, 'gold price (PHP/g)'),
    )


def pagibig_problem(data):
    rates = [
        rate
        for part in ('standard', 'promo')
        for rate in data.get(part, {}).get('rates', [])
    ]
    if not rates:
        return 'no Pag-IBIG rates'
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', str(data.get('checkedOn'))):
        return 'Pag-IBIG rates have no checkedOn date'
    return _first(
        *[_between(r.get('ratePercent'), 0.5, 20, 'Pag-IBIG rate') for r in rates]
    )


def zonal_problem(data):
    # A changed page layout shows up as too few regions, regions with no
    # offices, or offices with no file links: then nothing is saved.
    regions = data.get('regions', [])
    if len(regions) < 10:
        return f'only {len(regions)} BIR regions found'
    empty = [r for r in regions if not r.get('offices')]
    if len(empty) > len(regions) // 2:
        return f'{len(empty)} of {len(regions)} BIR regions have no offices'
    offices = [office for region in regions for office in region['offices']]
    if any(not office.get('office') for office in offices):
        return 'a BIR office has no name'
    if sum(bool(office.get('files')) for office in offices) < len(offices) / 2:
        return 'most BIR offices have no zonal value files'
    return _first(
        *[
            _between(office['revisedYear'], 1990, 2100, 'zonal values year')
            for office in offices
            if office.get('revisedYear') is not None
        ]
    )


PROBLEMS = {
    'inflation': inflation_problem,
    'constructionCost': construction_problem,
    'gold': gold_problem,
    'pagibigRates': pagibig_problem,
    'zonalValues': zonal_problem,
}


def problem_with(name, data):
    """What is wrong with [data], or None when it can be saved."""
    return PROBLEMS[name](data)
