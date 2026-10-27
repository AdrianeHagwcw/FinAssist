"""Runs the scraper: collect, check, analyze, save.

    python -m price_scraper.main            collect and save to Firestore
    python -m price_scraper.main --dry-run  collect and print, save nothing

One source failing never stops the others, and never touches its last good
figures in Firestore. The run still ends in an error, so GitHub emails the
team.
"""

import argparse
import json
import sys
from datetime import datetime, timezone

from . import analysis, bir, checks, gold, pagibig, psa, store

SOURCES = {
    'inflation': psa.fetch_inflation,
    'constructionCost': psa.fetch_construction_cost,
    'gold': gold.fetch_gold,
    'zonalValues': bir.fetch_zonal_values,
    'pagibigRates': pagibig.load_rates,
}
# Sources that fill a gap in this run's data with what was saved last time.
KEEP_LAST_GOOD = {'zonalValues': bir.keep_last_good}


def _nothing_saved(name):
    return None


def _note(data):
    """What the run log should say about a source that only partly worked."""
    missing = [r['name'] for r in data.get('regions', []) if r.get('problem')]
    return f' (not on the site this time: {", ".join(missing)})' if missing else ''


def collect(sources=SOURCES, saved=_nothing_saved, today=None):
    """Each source's checked and analyzed figures, and what happened to
    each. [saved] gives what the last run kept for a source."""
    today = today or datetime.now(timezone.utc).date().isoformat()
    collected, results = {}, {}
    for name, fetch in sources.items():
        try:
            before = saved(name)
            data = fetch()
            if name in KEEP_LAST_GOOD:
                data = KEEP_LAST_GOOD[name](data, before)
            problem = checks.problem_with(name, data)
            if problem:
                raise ValueError(problem)
            collected[name] = analysis.add(name, data, before, today)
            results[name] = 'ok' + _note(data)
        except Exception as error:  # Any failure: keep the last good figures.
            results[name] = f'failed: {error}'
    return collected, results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args(argv)

    started = datetime.now(timezone.utc)
    if args.dry_run:
        collected, results = collect()
        print(json.dumps({'results': results, 'data': collected}, indent=2, default=str))
    else:
        db = store.connect()
        collected, results = collect(saved=lambda name: store.load(db, name))
        now = datetime.now(timezone.utc)
        for name, data in collected.items():
            # 'ok' becomes 'updated' or 'unchanged'; any note stays.
            results[name] = store.save(db, name, data, now) + _note(data)
        store.log_run(db, results, started, datetime.now(timezone.utc))
        print(json.dumps(results, indent=2))

    failed = [name for name, result in results.items() if result.startswith('failed')]
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
