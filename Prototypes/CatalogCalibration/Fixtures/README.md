# Representative data fixtures

`products.parquet` and `prices.parquet` are compact prototype inputs derived from Open Food Facts and Open Prices. They contain real product identifiers and public product/price facts, but are not a replacement for the pinned bulk inputs used by a production snapshot build.

Source databases:

- Open Food Facts: https://world.openfoodfacts.org/ — Open Database License (ODbL)
- Open Prices: https://prices.openfoodfacts.org/ — Open Database License (ODbL)

Pinned bulk revisions used to verify schema and price data:

- `openfoodfacts/product-database@2a652ac61d03a601e132aa80833823cd33adea2d`
- `openfoodfacts/open-prices@60c5118e3c1434717d1871a37cf2ee27c61aa530`

The product fixture is captured through bounded structured-search requests because the upstream product Parquet is 7.7 GB. The price fixture is projected directly from the pinned Open Prices Parquet. Both are deterministic inputs after capture and are kept separate from code licensing.
