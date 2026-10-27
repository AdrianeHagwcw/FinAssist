import unittest
from datetime import datetime, timezone

from price_scraper import bir

import samples


class PageTest(unittest.TestCase):
    def test_reads_regions_and_their_codes_from_the_page(self):
        page = samples.bir_page([
            samples.bir_tab('Revenue Region 1 - Calasiao, Pangasinan', '67'),
            samples.bir_tab('Revenue Region 2 - CAR', '187', 'Municipalities'),
        ])

        regions = bir.page_regions(page)

        self.assertEqual(
            [(r['name'], r['code']) for r in regions],
            [('Revenue Region 1 - Calasiao, Pangasinan', '67'), ('Revenue Region 2 - CAR', '187')],
        )
        self.assertEqual(regions[1]['fields']['content'], 'Municipalities')

    def test_a_page_without_regions_is_an_error(self):
        # Such as when BIR redesigns the page: nothing is saved.
        with self.assertRaises(ValueError):
            bir.page_regions('<html><body>Under maintenance</body></html>')


class OfficesTest(unittest.TestCase):
    fields = samples.bir_tab('Region', '1')['children'][1]['content']['listItems']['dataMapper']

    def test_reads_each_office(self):
        office = bir.parse_offices(
            samples.bir_answer([samples.bir_office(1, 'Laoag City', 2023)]), self.fields
        )[0]

        self.assertEqual(office['office'], 'RDO No. 1-Laoag City')
        self.assertEqual(office['province'], 'Laoag City')
        self.assertEqual(
            office['places'], 'Department Order No. 01-2023 Town A, Town B & Town C'
        )
        self.assertEqual((office['departmentOrder'], office['revisedYear']), ('01-2023', 2023))
        self.assertEqual(
            office['files'],
            [{
                'label': 'View RDO No. 1 excel',
                'url': 'https://bir-cdn.bir.gov.ph/local/pdf/RDO%20No.%201%20-%20Laoag%20City.zip',
            }],
        )

    def test_finds_the_order_in_the_text_when_it_has_no_field(self):
        answer = samples.bir_answer([samples.bir_office(2, 'Vigan', 2021)])
        del answer['data'][0]['content']['Department Order']

        office = bir.parse_offices(answer, self.fields)[0]

        self.assertEqual(office['revisedYear'], 2021)

    def test_skips_offices_that_are_turned_off(self):
        answer = samples.bir_answer([samples.bir_office(1, 'Laoag', 2023)])
        answer['data'][0]['is_active'] = 0

        self.assertEqual(bir.parse_offices(answer, self.fields), [])


class FetchTest(unittest.TestCase):
    def test_one_missing_region_keeps_the_rest(self):
        page = samples.bir_page([
            samples.bir_tab('Revenue Region 1', '67'),
            samples.bir_tab('Revenue Region 13', '194'),
        ])

        def get(url, headers):
            self.assertEqual(headers, {'client-website-id': '2'})
            if '/194/' in url:
                raise ValueError('HTTP Error 404: Not Found')
            return samples.bir_answer([samples.bir_office(1, 'Laoag', 2023)])

        data = bir.fetch_zonal_values(get=get, page=lambda url: page)

        first, missing = data['regions']
        self.assertEqual(len(first['offices']), 1)
        self.assertEqual(missing['offices'], [])
        self.assertIn('404', missing['problem'])

    def test_a_missing_region_keeps_its_last_saved_offices(self):
        saved_at = datetime(2026, 10, 20, tzinfo=timezone.utc)
        saved = {
            'regions': [{'name': 'Revenue Region 13', 'offices': [{'office': 'RDO No. 80'}]}],
            'updatedAt': saved_at,
        }
        data = {'regions': [{'name': 'Revenue Region 13', 'offices': [], 'problem': 'gone'}]}

        region = bir.keep_last_good(data, saved)['regions'][0]

        self.assertEqual(region['offices'], [{'office': 'RDO No. 80'}])
        self.assertEqual(region['lastReadAt'], saved_at)
        self.assertEqual(region['problem'], 'gone')

    def test_nothing_to_keep_on_the_first_run(self):
        data = {'regions': [{'name': 'Revenue Region 13', 'offices': [], 'problem': 'gone'}]}

        self.assertEqual(bir.keep_last_good(data, None), data)


if __name__ == '__main__':
    unittest.main()
