"""Small copies of what each source sends, in the same shape as the real
answers, so the tests run without the internet."""

import json


# ------------------------------------------------------------------- PSA

def inflation_meta():
    return {
        'variables': [
            {
                'code': 'Geolocation',
                'values': ['0', '1'],
                'valueTexts': ['PHILIPPINES', '..National Capital Region (NCR)'],
            },
            {
                'code': 'Commodity Description',
                'values': ['0', '1'],
                'valueTexts': ['0 - ALL ITEMS', '01 - FOOD'],
            },
            {'code': 'Year', 'values': ['0', '1', '2'], 'valueTexts': ['2024', '2025', '2026']},
            {
                'code': 'Period',
                'values': [str(i) for i in range(13)],
                'valueTexts': [
                    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', 'Ave',
                ],
            },
        ],
    }


def inflation_data(rates_2025, rates_2026):
    """PSA's plain json answer: one row per month, '..' for a month not out
    yet, and the yearly average as period 12."""
    rows = []
    for year, rates in (('1', rates_2025), ('2', rates_2026)):
        for month, rate in enumerate(rates):
            rows.append({'key': ['0', '0', year, str(month)], 'values': [rate]})
        rows.append({'key': ['0', '0', year, '12'], 'values': ['3.0']})
    return {
        'columns': [
            {'code': 'Geolocation'},
            {'code': 'Commodity Description'},
            {'code': 'Year'},
            {'code': 'Period'},
            {'code': 'CPI', 'type': 'c'},
        ],
        'data': rows,
    }


def construction_meta():
    return {
        'variables': [
            # Newest first, as the PSA lists this table's years.
            {'code': 'Year', 'values': ['0', '1', '2'], 'valueTexts': ['2024', '2023', '2022']},
            {'code': 'Period', 'values': ['0', '1'], 'valueTexts': ['Annual', 'Q1']},
            {'code': 'Geolocation', 'values': ['0', '1', '2', '3'], 'valueTexts': []},
            {'code': 'Type', 'values': ['0', '1'], 'valueTexts': ['Residential', 'Non-residential']},
            {
                'code': 'Item',
                'values': ['0', '1', '2'],
                'valueTexts': ['Number', 'Floor area', 'Value'],
            },
        ],
    }


PLACE_LABELS = {
    '0': 'PHILIPPINES',
    '1': '..National Capital Region (NCR)',
    '2': '....City of Manila',
    '3': '..Region X (Northern Mindanao)',
}


def construction_data(figures):
    """[figures]: {(year code, place code): (floor area, value)}."""
    rows = []
    for (year, place), (area, value) in figures.items():
        rows.append({'key': [year, '0', place, '0', '1'], 'values': [area]})
        rows.append({'key': [year, '0', place, '0', '2'], 'values': [value]})
    return {
        'columns': [
            {'code': 'Year'},
            {'code': 'Period'},
            {'code': 'Geolocation'},
            {'code': 'Type'},
            {'code': 'Item'},
            {'code': 'Construction', 'type': 'c'},
        ],
        'data': rows,
    }


# ------------------------------------------------------------------- BIR

def bir_tab(label, code, content_field='Municities'):
    return {
        'label': label,
        'children': [
            {'type': 'CONTENT TITLE', 'content': {'label': label}},
            {
                'type': 'LIST CARDS',
                'content': {
                    'listItems': {
                        'source': 'dataset',
                        'data': [{'label': 'List Item 1'}],
                        'code': code,
                        'dataMapper': {
                            'label': 'RDO',
                            'subLabel': 'Province',
                            'content': content_field,
                            'attachment1': 'File',
                            'attachments': 'Files Collection',
                        },
                    }
                },
            },
        ],
    }


def bir_page(tabs):
    """The zonal values page as Next.js sends it: the page's data cut into
    pieces, each a JavaScript string inside a script tag."""
    sections = {
        'sections': [
            {'type': 'CONTENT TITLE', 'content': {'label': 'Zonal Values'}},
            {'type': 'VERTICAL TAB', 'content': {'tabs': tabs}},
        ]
    }
    text = (
        '0:I["123",["static/chunks/page.js"],"default"]\n'
        f'4:["$","$Le",null,{{"children":["$","$L13",null,{json.dumps(sections)}]}}]\n'
    )
    middle = len(text) // 2
    scripts = ''.join(
        f'<script>self.__next_f.push([1,{json.dumps(piece)}])</script>'
        for piece in (text[:middle], text[middle:])
    )
    return f'<!DOCTYPE html><html><body><main>Loading</main>{scripts}</body></html>'


def bir_office(number, place, year, files=True):
    link = (
        f'https://bir-cdn.bir.gov.ph/local/pdf/RDO No. {number} - {place}.zip'
        f'|View RDO No. {number} excel'
    )
    content = {
        'RDO': f'RDO No. {number}-{place}',
        'Province': f'Province: {place}',
        'Municities': (
            f'<p><strong>Department Order No. 0{number}-{year}</strong></p>'
            '<p>Town A, Town B &amp; Town C</p>'
        ),
        'Department Order': f'0{number}-{year}',
    }
    if files:
        content['File'] = link
        content['Files Collection'] = [link]
    return {'id': number, 'content': content, 'is_active': 1}


def bir_answer(offices):
    return {'data': offices, 'meta': {'current_page': 1, 'last_page': 1}}


def zonal_values(region_count=12, offices_each=2, year=2023):
    return {
        'regions': [
            {
                'name': f'Revenue Region {r}',
                'offices': [
                    {
                        'office': f'RDO No. {r}{o}',
                        'province': 'Somewhere',
                        'places': 'Town A',
                        'departmentOrder': f'001-{year}',
                        'revisedYear': year,
                        'files': [{'label': 'File', 'url': 'https://bir-cdn.bir.gov.ph/a.zip'}],
                    }
                    for o in range(offices_each)
                ],
            }
            for r in range(1, region_count + 1)
        ],
        'source': {'name': 'BIR', 'url': 'https://www.bir.gov.ph/zonal-values'},
    }


# ------------------------------------------------------------ the others

def gold_answers(usd_per_ounce=2000.0, usd_to_php=56.0):
    return (
        {'name': 'Gold', 'price': usd_per_ounce, 'symbol': 'XAU',
         'updatedAt': '2026-10-27T10:00:53Z'},
        {'amount': 1.0, 'base': 'USD', 'date': '2026-10-26', 'rates': {'PHP': usd_to_php}},
    )


def inflation(rates):
    return {
        'ratePercent': rates[-1],
        'period': '2026-09',
        'periodLabel': 'September 2026',
        'recent': [
            {'period': f'2026-{i + 1:02d}', 'ratePercent': rate}
            for i, rate in enumerate(rates)
        ],
    }


def construction(national=12000, regions=(('NCR', 16000), ('Region X', 8000))):
    return {
        'year': 2024,
        'pesoPerSqm': national,
        'previousYear': {'year': 2023, 'pesoPerSqm': 11000},
        'regions': [
            {'code': str(i), 'name': name, 'pesoPerSqm': cost}
            for i, (name, cost) in enumerate(regions)
        ],
    }
