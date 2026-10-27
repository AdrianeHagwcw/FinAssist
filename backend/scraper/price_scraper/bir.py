"""Zonal values: the land values the Bureau of Internal Revenue (BIR) sets
for every street and barangay, used for the taxes when a house or lot is
sold. They show what land is worth in each place.

This is the scraper's web-page part. The zonal values page
(bir.gov.ph/zonal-values) has no table to copy: its HTML carries the list
of revenue regions, and for each one the code of the list the page then
loads that region's offices from. So the scraper:

1. downloads the page and reads the regions and their codes out of it;
2. asks BIR's content service for each region's list: the same request
   the page makes when someone opens it in a browser;
3. keeps, for each Revenue District Office (RDO): its name, province, the
   towns it covers, when its values were last revised, and the links to
   its zonal value files.

Both BIR sites allow programs in their robots.txt.
"""

import html
import json
import re
import urllib.parse

from .http import get_json, get_page

PAGE = 'https://www.bir.gov.ph/zonal-values'
SERVICE = 'https://bir-cms-ws.bir.gov.ph'
# The page's own script sends this to say which BIR site is asking. It is
# public and the same for every visitor, not a password.
SITE_HEADER = {'client-website-id': '2'}

# The page's data, as Next.js puts it in the HTML: pieces of one long text,
# each in a script like  self.__next_f.push([1,"..."])
_PIECE = re.compile(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)')


def page_data(page):
    """Each JSON part of the data the page was built from. Joined, the
    pieces are lines of "<id>:<JSON>"; lines that aren't JSON are script
    and style references."""
    text = ''.join(json.loads(f'"{piece}"') for piece in _PIECE.findall(page))
    for line in text.splitlines():
        _, _, body = line.partition(':')
        try:
            yield json.loads(body)
        except ValueError:
            continue


def _walk(node):
    """Every object inside [node], at any depth."""
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)


def page_regions(page):
    """[{'name', 'code', 'fields'}]: each tab of the page that lists offices,
    the code of its list, and which field holds what in that list."""
    regions = {}
    for data in page_data(page):
        for node in _walk(data):
            if node.get('type') != 'VERTICAL TAB':
                continue
            for tab in node.get('content', {}).get('tabs', []):
                lists = [
                    found['content']['listItems']
                    for found in _walk(tab.get('children', []))
                    if found.get('type') == 'LIST CARDS'
                    and found.get('content', {}).get('listItems', {}).get('source')
                    == 'dataset'
                ]
                if lists and lists[0].get('code'):
                    regions[tab['label']] = {
                        'name': tab['label'],
                        'code': str(lists[0]['code']),
                        'fields': lists[0].get('dataMapper', {}),
                    }
    if not regions:
        raise ValueError('the BIR zonal values page lists no regions')
    return list(regions.values())


def _text(value):
    """Plain text from a field that may hold HTML."""
    text = re.sub(r'<[^>]+>', ' ', str(value or ''))
    return re.sub(r'\s+', ' ', html.unescape(text)).strip()


def _files(content, fields):
    """[{'label', 'url'}] from fields written as "url|label"."""
    links = []
    for key in ('attachments', 'attachment1', 'attachment2'):
        value = content.get(fields.get(key, ''))
        links += value if isinstance(value, list) else [value]
    files, seen = [], set()
    for link in links:
        if not isinstance(link, str) or not link.startswith('http'):
            continue
        url, _, label = link.partition('|')
        url = urllib.parse.quote(url.strip(), safe=':/?&=%#')
        if url not in seen:
            seen.add(url)
            files.append({'label': label.strip() or 'Zonal values file', 'url': url})
    return files


def _department_order(content, places):
    """The order that last revised the values, such as '047-2023', and its
    year. Some offices give it only in the text of their towns."""
    order = _text(content.get('Department Order'))
    if not order:
        found = re.search(r'Department Order No\.?\s*([\d-]+)', places, re.I)
        order = found.group(1) if found else ''
    year = re.findall(r'(?:19|20)\d{2}', order)
    return order or None, int(year[-1]) if year else None


def parse_offices(answer, fields):
    """Each office in one region's list, read with the field names the page
    itself uses (they differ a little from region to region)."""
    offices = []
    for item in answer.get('data', []):
        content = item.get('content') or {}
        name = _text(content.get(fields.get('label', 'RDO')))
        if not item.get('is_active', 1) or not name:
            continue
        places = _text(content.get(fields.get('content', '')))
        order, year = _department_order(content, places)
        province = _text(content.get(fields.get('subLabel', 'Province')))
        offices.append({
            'office': name,
            'province': re.sub(r'^Province:\s*', '', province, flags=re.I),
            'places': places,
            'departmentOrder': order,
            'revisedYear': year,
            'files': _files(content, fields),
        })
    return offices


def _region_offices(get, region):
    answer = get(
        f"{SERVICE}/api/pub/templates/{region['code']}/datasets?per_page=3000",
        headers=SITE_HEADER,
    )
    if answer.get('meta', {}).get('last_page', 1) > 1:
        raise ValueError('has more offices than one page holds')
    return parse_offices(answer, region['fields'])


def fetch_zonal_values(get=get_json, page=get_page):
    regions = []
    for region in page_regions(page(PAGE)):
        try:
            offices = _region_offices(get, region)
        except Exception as error:  # One region missing never loses the rest.
            regions.append({
                'name': region['name'],
                'offices': [],
                'problem': f"BIR's site gave no list ({error})",
            })
            continue
        regions.append({'name': region['name'], 'offices': offices})
    return {
        'regions': regions,
        'source': {'name': 'Bureau of Internal Revenue (BIR)', 'url': PAGE},
    }


def keep_last_good(data, saved):
    """A region BIR's site didn't give this time keeps the offices it had
    last time, marked with when they were read."""
    before = {r['name']: r for r in (saved or {}).get('regions', [])}
    regions = []
    for region in data['regions']:
        old = before.get(region['name'], {})
        if region.get('problem') and old.get('offices'):
            region = {
                **region,
                'offices': old['offices'],
                'lastReadAt': old.get('lastReadAt') or saved.get('updatedAt'),
            }
        regions.append(region)
    return {**data, 'regions': regions}
