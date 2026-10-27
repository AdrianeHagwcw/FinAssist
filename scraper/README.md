# Price scraper

Collects public financial data from the web once a week, checks it,
analyzes it, and saves it in Firestore (`priceReferences`) for the app.
It runs on GitHub Actions (`.github/workflows/price-scraper.yml`), free
for a public repository.

## What it collects

| Data (Firestore document) | Source | How |
| --- | --- | --- |
| `inflation`: latest rate and last 12 months | PSA OpenSTAT | PSA's official data API |
| `constructionCost`: house cost per sqm, by region | PSA OpenSTAT | PSA's official data API |
| `gold`: pesos per gram | gold-api.com + Frankfurter | Public price APIs |
| `zonalValues`: BIR offices, towns covered, last update, file links | bir.gov.ph/zonal-values | Scrapes the page's HTML, then loads each region's list the way the page does |
| `pagibigRates`: housing loan rates | Pag-IBIG (via news and guides) | Kept by hand in `data/pagibig_rates.json` |
| `status`: when it last ran and how each source did | | |

## How one run works

1. **Collect.** Each source is read separately (`psa.py`, `gold.py`,
   `bir.py`, `pagibig.py`).
2. **Check.** Every figure must fall in a sensible range (`checks.py`).
   A wrong unit, a changed page or an empty answer is refused.
3. **Analyze.** Trends and comparisons are added under `analysis`
   (`analysis.py`): inflation up or down from last month and its
   12-month average; cheapest and priciest regions to build in; gold's
   change since the last check; zonal values due for an update.
4. **Save.** Only figures that changed are written (`store.py`), and each
   run is logged in `scraperRuns`.

## Being a polite scraper (`http.py`)

- Reads each site's robots.txt first and never opens what it forbids.
- Names itself in every request (`FinAssist-price-scraper/1.0`).
- Waits a second between requests to the same site; runs once a week.
- Never gets around a captcha or a block. That is why the Bangko Sentral
  (robots.txt allows search engines only) and Pag-IBIG (captcha) are not
  scraped.

## When a site is down or changes

- One source failing never stops the others, and its last good figures
  stay in Firestore. The run is marked failed, so GitHub emails the team.
- If one BIR region's list is missing (Region 13 - Cebu City is missing
  on BIR's own site as of October 2026), that region keeps its last saved
  list and the run log names it.
- A site that changed its layout fails the checks, so nothing wrong is
  saved.

## Run it on your computer

From this folder (`scraper`), with Python 3.10 or later:

```
python -m unittest discover -s tests      # tests, no internet needed
python -m price_scraper.main --dry-run    # live, prints, saves nothing
```

## Setup (once)

1. Firebase console -> Project settings -> Service accounts -> Generate
   new private key. Never commit this file.
2. GitHub repository -> Settings -> Secrets and variables -> Actions ->
   New repository secret: name `FIREBASE_SERVICE_ACCOUNT`, value: the
   whole JSON key. Then delete the downloaded file.
3. Publish `firestore.rules` (Firebase console -> Firestore -> Rules, or
   `firebase deploy --only firestore:rules`), so the app can read
   `priceReferences`.
4. Actions tab -> Price scraper -> Run workflow, to run it the first time.

GitHub pauses scheduled runs after 60 days with no commits; re-enable it
in the Actions tab if that happens.

## Updating Pag-IBIG rates

Edit `data/pagibig_rates.json` (its `_howToUpdate` note says how), set
`checkedOn` to the day you checked, and push. The tests check the file.
