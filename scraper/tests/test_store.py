import unittest
from datetime import datetime, timezone

from price_scraper import store


class FakeSnapshot:
    def __init__(self, data):
        self.exists = data is not None
        self._data = data

    def to_dict(self):
        return dict(self._data)


class FakeDocument:
    def __init__(self, db, path):
        self.db, self.path = db, path

    def get(self):
        return FakeSnapshot(self.db.docs.get(self.path))

    def set(self, data):
        self.db.writes += 1
        self.db.docs[self.path] = data


class FakeCollection:
    def __init__(self, db, name):
        self.db, self.name = db, name

    def document(self, name):
        return FakeDocument(self.db, f'{self.name}/{name}')

    def add(self, data):
        self.db.docs[f'{self.name}/{len(self.db.docs)}'] = data


class FakeFirestore:
    def __init__(self):
        self.docs, self.writes = {}, 0

    def collection(self, name):
        return FakeCollection(self, name)


NOW = datetime(2026, 10, 27, tzinfo=timezone.utc)


class SaveTest(unittest.TestCase):
    def test_saves_new_figures_with_the_time(self):
        db = FakeFirestore()

        self.assertEqual(store.save(db, 'gold', {'pesoPerGram': 8000}, NOW), 'updated')
        self.assertEqual(
            db.docs['priceReferences/gold'], {'pesoPerGram': 8000, 'updatedAt': NOW}
        )

    def test_unchanged_figures_are_not_written_again(self):
        db = FakeFirestore()
        store.save(db, 'inflation', {'ratePercent': 3.1}, NOW)

        self.assertEqual(store.save(db, 'inflation', {'ratePercent': 3.1}, NOW), 'unchanged')
        self.assertEqual(db.writes, 1)

    def test_loads_what_was_saved(self):
        db = FakeFirestore()
        store.save(db, 'gold', {'pesoPerGram': 8000}, NOW)

        self.assertEqual(store.load(db, 'gold')['pesoPerGram'], 8000)
        self.assertIsNone(store.load(db, 'inflation'))

    def test_logs_each_run_and_the_latest_status(self):
        db = FakeFirestore()

        store.log_run(db, {'gold': 'updated'}, NOW, NOW)

        self.assertEqual(
            db.docs['priceReferences/status'],
            {'lastCheckedAt': NOW, 'results': {'gold': 'updated'}},
        )
        self.assertEqual(len([p for p in db.docs if p.startswith('scraperRuns/')]), 1)


if __name__ == '__main__':
    unittest.main()
