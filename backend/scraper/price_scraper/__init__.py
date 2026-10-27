"""FinAssist's price scraper.

Every day, on GitHub Actions, it collects public price data from the web,
checks it, analyzes it, and saves it in Firestore for the app's assistant
to use:

* inflation, from the Philippine Statistics Authority (PSA)
* the cost of building a house per square meter, also from the PSA
* the price of gold in pesos per gram
* zonal values (what land is worth, by place), scraped from the Bureau of
  Internal Revenue's (BIR) zonal values page
* Pag-IBIG housing loan rates, kept by hand because their site blocks
  programs
"""
