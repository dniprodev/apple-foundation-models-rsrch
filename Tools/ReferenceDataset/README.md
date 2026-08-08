# Reference Dataset builder

This build-time tool projects pinned Open Food Facts product Parquet and Open Prices Parquet into the app-owned SQLite Reference Dataset. It does not call a live API, ship the upstream exports, or generate Demo Household state.

The first snapshot is configured for France/EUR, a fixed 365-day price window, eight scenario categories, a minimum quota of 250 products per category, and 3,000 selected products. The builder fails with a coverage report when a quota cannot be met.

## Inputs

Download the official Parquet inputs locally, then verify that the files match the immutable revisions recorded in the manifest:

- Open Food Facts `product-database` revision `2a652ac61d03a601e132aa80833823cd33adea2d`.
- Open Prices revision `60c5118e3c1434717d1871a37cf2ee27c61aa530`.

The sources are Open Database License data. Keep the source attribution and license links with any distributed snapshot.

## Build

```sh
uv run --project Tools/ReferenceDataset python Tools/ReferenceDataset/build_snapshot.py \
  --products /path/to/products.parquet \
  --prices /path/to/prices.parquet \
  --output /path/to/catalog.sqlite \
  --manifest /path/to/catalog-manifest.json \
  --product-revision 2a652ac61d03a601e132aa80833823cd33adea2d \
  --price-revision 60c5118e3c1434717d1871a37cf2ee27c61aa530 \
  --product-sha256 <sha256-of-products.parquet> \
  --price-sha256 <sha256-of-prices.parquet>
```

The SQLite file is finalized with deterministic insertion order, page settings, FTS5 optimization, and vacuuming. The manifest records input checksums, selection counts, rejection counts, artifact checksums, and verification plans for barcode and full-text lookup. The builder refuses inputs whose checksums do not match the pinned command-line values. Re-running with identical inputs and configuration produces identical manifest bytes, logical rows, and artifact bytes.

The projection keeps text barcodes, public product evidence, normalized nutrition values, same-market price observations, and one deterministic `price_basis` for the product display price. Observations with other `price_per` values remain available as evidence and are never mixed into that median.

## Tests

```sh
uv run --project Tools/ReferenceDataset python -m unittest discover \
  -s Tools/ReferenceDataset/tests -v
```
