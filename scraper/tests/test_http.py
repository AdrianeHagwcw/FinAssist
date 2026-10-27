import unittest
import urllib.error
from unittest import mock

from price_scraper import http

PSA_STYLE = """
User-agent: *
Content-Signal: search=yes,ai-train=no,use=reference
Allow: /
User-agent: GPTBot
Disallow: /
"""


def answer(body, kind='application/json'):
    response = mock.MagicMock()
    response.__enter__.return_value = response
    response.read.return_value = body.encode('utf-8')
    response.headers.get_content_charset.return_value = 'utf-8'
    response.headers.get_content_type.return_value = kind
    return response


def refused(code):
    return urllib.error.HTTPError('https://example.com/data', code, 'no', {}, None)


class RobotsTest(unittest.TestCase):
    def test_follows_the_rules_for_every_program(self):
        self.assertTrue(http.robots_allows(PSA_STYLE, 'https://openstat.psa.gov.ph/PXWeb/api'))
        self.assertFalse(
            http.robots_allows('User-agent: *\nDisallow: /', 'https://www.bsp.gov.ph/a')
        )

    def test_follows_rules_written_for_this_scraper(self):
        rules = 'User-agent: FinAssist-price-scraper\nDisallow: /private'

        self.assertFalse(http.robots_allows(rules, 'https://example.com/private/x'))
        self.assertTrue(http.robots_allows(rules, 'https://example.com/public'))

    def test_no_robots_txt_sets_no_rules(self):
        self.assertTrue(http.robots_allows('', 'https://example.com/anything'))


class RequestTest(unittest.TestCase):
    def setUp(self):
        http._robots.clear()
        http._last_request.clear()
        self.addCleanup(http._robots.clear)
        self.addCleanup(http._last_request.clear)
        sleep = mock.patch.object(http.time, 'sleep')
        self.sleep = sleep.start()
        self.addCleanup(sleep.stop)

    def test_never_opens_an_address_robots_txt_forbids(self):
        with mock.patch.object(http.urllib.request, 'urlopen') as urlopen:
            urlopen.return_value = answer('User-agent: *\nDisallow: /', 'text/plain')

            with self.assertRaises(http.Forbidden):
                http.get_json('https://example.com/data')

        # Only robots.txt was read.
        self.assertEqual(urlopen.call_count, 1)

    def test_says_who_it_is(self):
        with mock.patch.object(http.urllib.request, 'urlopen') as urlopen:
            urlopen.side_effect = [refused(404), answer('{"price": 1}')]

            self.assertEqual(http.get_json('https://example.com/data'), {'price': 1})

        request = urlopen.call_args.args[0]
        self.assertTrue(request.get_header('User-agent').startswith('FinAssist-price-scraper'))

    def test_does_not_ask_again_when_the_site_says_no(self):
        http._robots['https://example.com'] = ''
        with mock.patch.object(http.urllib.request, 'urlopen') as urlopen:
            urlopen.side_effect = refused(403)

            with self.assertRaises(urllib.error.HTTPError):
                http.get_json('https://example.com/data')

        self.assertEqual(urlopen.call_count, 1)

    def test_tries_again_when_the_server_is_busy(self):
        http._robots['https://example.com'] = ''
        with mock.patch.object(http.urllib.request, 'urlopen') as urlopen:
            urlopen.side_effect = [refused(503), answer('{"ok": true}')]

            self.assertEqual(http.get_json('https://example.com/data'), {'ok': True})

        self.assertEqual(urlopen.call_count, 2)

    def test_reads_a_page_with_a_byte_order_mark(self):
        http._robots['https://example.com'] = ''
        with mock.patch.object(http.urllib.request, 'urlopen') as urlopen:
            urlopen.return_value = answer('﻿{"a": 1}')

            self.assertEqual(http.get_json('https://example.com/data'), {'a': 1})


if __name__ == '__main__':
    unittest.main()
