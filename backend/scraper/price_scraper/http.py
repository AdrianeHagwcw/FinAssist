"""Polite web requests. The scraper:

- says who it is, and where its code is, in every request;
- reads each site's robots.txt first, and never opens an address it
  forbids;
- waits a second between requests to the same site;
- gives a slow server time to answer, and tries a failed request twice
  more before giving up, but not when the site itself said no.
"""

import json
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser

USER_AGENT = (
    'FinAssist-price-scraper/1.0 '
    '(+https://github.com/AdrianeHagwcw/FinAssist)'
)
PAUSE_SECONDS = 1


class Forbidden(Exception):
    """A site's robots.txt asks programs not to open this address."""


_robots = {}  # site -> its robots.txt, read once per run
_last_request = {}  # site -> when it was last asked


def get_json(url, *, headers=None, timeout=30, tries=3):
    return json.loads(_request(url, None, headers, 'application/json', timeout, tries))


def post_json(url, body, *, timeout=60, tries=3):
    data = json.dumps(body).encode('utf-8')
    return json.loads(_request(url, data, None, 'application/json', timeout, tries))


def get_page(url, *, timeout=30, tries=3):
    """A web page's HTML."""
    return _request(url, None, None, 'text/html', timeout, tries)


def robots_allows(robots_txt, url):
    """Whether [robots_txt] lets this scraper open [url]."""
    parser = urllib.robotparser.RobotFileParser()
    parser.parse(robots_txt.splitlines())
    return parser.can_fetch(USER_AGENT, url)


def _site(url):
    parts = urllib.parse.urlsplit(url)
    return f'{parts.scheme}://{parts.netloc}'


def _robots_txt(site):
    try:
        text, kind = _open(f'{site}/robots.txt', None, None, 'text/plain', 30)
    except urllib.error.HTTPError as error:
        if error.code < 500:
            return ''  # No robots.txt: the site sets no rules.
        raise  # The site is down; it is tried again next run.
    # Some sites answer every address with their home page.
    return text if kind == 'text/plain' else ''


def _request(url, data, headers, accept, timeout, tries):
    site = _site(url)
    if site not in _robots:
        _robots[site] = _robots_txt(site)
    if not robots_allows(_robots[site], url):
        raise Forbidden(f'{site}/robots.txt asks programs not to open {url}')

    for attempt in range(tries):
        try:
            return _open(url, data, headers, accept, timeout)[0]
        except urllib.error.HTTPError as error:
            # "Not found" or "not allowed" won't change by asking again;
            # only a busy or broken server (429, 5xx) is worth a retry.
            if (error.code < 500 and error.code != 429) or attempt == tries - 1:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == tries - 1:
                raise
        # Wait a little longer each time, so a busy server can recover.
        time.sleep(5 * (attempt + 1))


def _open(url, data, headers, accept, timeout):
    """The answer's text and its type, such as 'text/html'."""
    site = _site(url)
    wait = _last_request.get(site, 0) + PAUSE_SECONDS - time.monotonic()
    if wait > 0:
        time.sleep(wait)
    sent = {'User-Agent': USER_AGENT, 'Accept': accept, **(headers or {})}
    if data is not None:
        sent['Content-Type'] = 'application/json'
    try:
        request = urllib.request.Request(url, data=data, headers=sent)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            charset = response.headers.get_content_charset() or 'utf-8'
            text = response.read().decode(charset, 'replace').lstrip('﻿')
            return text, response.headers.get_content_type()
    finally:
        _last_request[site] = time.monotonic()
