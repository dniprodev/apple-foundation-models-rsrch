# Reference Dataset builder

This build-time tool projects pinned Open Food Facts product Parquet and Open Prices Parquet into the app-owned SQLite Reference Dataset. It does not call a live API, ship the upstream exports, or generate Demo Household state.

The demo snapshot is configured for France/EUR, a fixed 365-day price window, eight scenario categories, and 128 selected products. It keeps at least one product in every category, which is enough to exercise the reference app without shipping a large catalog. The builder fails with a coverage report when a category cannot be represented.

## Inputs and selective preparation

The product source is pinned to the immutable Open Food Facts revision below. Its `food.parquet` LFS object has SHA-256 `5a03f9a601a0b82129c055b356d3f504fefffdb4f0efc63a5049da4ce09dba82`, but the 7.74 GB file does not need to be downloaded in full. `prepare_product_subset.py` uses DuckDB's revision-aware `hf://` Parquet reader to materialize only product rows whose normalized barcodes have eligible evidence in the verified Open Prices input.

- Open Food Facts `product-database` revision `2a652ac61d03a601e132aa80833823cd33adea2d`.
- Open Prices revision `60c5118e3c1434717d1871a37cf2ee27c61aa530`.

Download `prices.parquet` from the pinned Open Prices revision and verify its SHA-256 is `cd76192e24953cdb192b15471e84995028dccf43004d643a9d1b0f0b0c1ec5f7`, then prepare the small product input:

```sh
uv run --project Tools/ReferenceDataset python \
  Tools/ReferenceDataset/prepare_product_subset.py \
  --prices /path/to/prices.parquet \
  --output /path/to/price-matched-products.parquet
```

Hash the prepared product input and pass that checksum to the deterministic build. The immutable revision in the `hf://` path and the prepared-input checksum together make the selective input reproducible without distributing or downloading unrelated product rows.

The sources are Open Database License data. Keep the source attribution and license links with any distributed snapshot.

## Build

```sh
uv run --project Tools/ReferenceDataset python Tools/ReferenceDataset/build_snapshot.py \
  --products /path/to/price-matched-products.parquet \
  --prices /path/to/prices.parquet \
  --output /path/to/catalog.sqlite \
  --manifest /path/to/catalog-manifest.json \
  --product-revision 2a652ac61d03a601e132aa80833823cd33adea2d \
  --price-revision 60c5118e3c1434717d1871a37cf2ee27c61aa530 \
  --product-sha256 <sha256-of-price-matched-products.parquet> \
  --price-sha256 <sha256-of-prices.parquet>
```

The SQLite file is finalized with deterministic insertion order, page settings, FTS5 optimization, and vacuuming. The manifest records input checksums, selection counts, rejection counts, artifact checksums, and verification plans for barcode and full-text lookup. The builder refuses inputs whose checksums do not match the pinned command-line values. Re-running with identical inputs and configuration produces identical manifest bytes, logical rows, and artifact bytes.

The projection keeps text barcodes, public product evidence, normalized nutrition values, same-market price observations, and one deterministic `price_basis` for the product display price. Observations with other `price_per` values remain available as evidence and are never mixed into that median.

## Tests

```sh
uv run --project Tools/ReferenceDataset python -m unittest discover \
  -s Tools/ReferenceDataset/tests -v
```
