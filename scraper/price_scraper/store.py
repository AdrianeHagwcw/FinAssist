"""Saves the prices in Firestore, where the app reads them.

The scraper signs in with a Firebase service account key kept as a GitHub
Actions secret, never in the code. Only it can write these documents; the
app can only read them (see firestore.rules).
"""

import json
import os

COLLECTION = 'priceReferences'
RUNS = 'scraperRuns'


def connect():
    import firebase_admin
    from firebase_admin import credentials, firestore

    key = os.environ.get('FIREBASE_SERVICE_ACCOUNT')
    if not key:
        raise SystemExit('FIREBASE_SERVICE_ACCOUNT is not set.')
    firebase_admin.initialize_app(credentials.Certificate(json.loads(key)))
    return firestore.client()


def load(db, name):
    """What the last run saved for [name], or None."""
    saved = db.collection(COLLECTION).document(name).get()
    return saved.to_dict() if saved.exists else None


def same_data(saved, new):
    """Whether nothing changed but the time it was saved."""
    if saved is None:
        return False
    saved = {k: v for k, v in saved.items() if k != 'updatedAt'}
    return saved == new


def save(db, name, data, now):
    """Writes [data] only when it changed, so a quiet day costs nothing."""
    ref = db.collection(COLLECTION).document(name)
    saved = ref.get()
    if saved.exists and same_data(saved.to_dict(), data):
        return 'unchanged'
    ref.set({**data, 'updatedAt': now})
    return 'updated'


def log_run(db, results, started, finished):
    """Every run is kept, for checking how often it works; the latest also
    goes where the app can see when prices were last checked."""
    run = {'startedAt': started, 'finishedAt': finished, 'results': results}
    db.collection(RUNS).add(run)
    db.collection(COLLECTION).document('status').set(
        {'lastCheckedAt': finished, 'results': results}
    )
