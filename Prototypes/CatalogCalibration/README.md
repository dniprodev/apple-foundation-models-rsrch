# PROTOTYPE — Catalog and Demo Household calibration

## Question

What catalog schema, indexes, snapshot size, and deterministic Demo Household generation rules give the Reference App realistic product discovery and private context without costly runtime preparation, excessive app size, or slow tool queries?

This is throwaway code for answering that question. It is not the production dataset builder or an app module.

The accepted answer and measurements are recorded in [`RESULTS.md`](RESULTS.md).

The prototype deliberately separates two concerns:

1. `Scripts/refresh_fixtures.py` captures a small, real-data fixture from the official Open Food Facts structured-search API and pinned Open Prices Parquet revision. Refreshing is networked, rate-limited, and optional.
2. `Scripts/build_snapshot.py` is the repeatable offline path under test. DuckDB reads the representative Parquet inputs, applies the catalog projection, and Python's SQLite adapter emits the exact database GRDB opens.

The full pinned product Parquet is 7.7 GB. Its schema was verified directly, but it is intentionally not an interactive input to this prototype. A production refresh downloads bulk inputs locally before running the same projection.

## Run

From this directory:

```sh
make prototype
```

The terminal app redraws one stable frame and exposes catalog search, product detail, alternatives, recent purchases, pantry, cart, Demo Household switching, and measurements.

For a non-interactive measurement report:

```sh
make report
```

To recapture the representative fixtures from official sources:

```sh
make refresh
```

## Pinned sources

- Open Food Facts product Parquet schema revision: `2a652ac61d03a601e132aa80833823cd33adea2d`
- Open Prices Parquet revision: `60c5118e3c1434717d1871a37cf2ee27c61aa530`
- Fixed price window: 2025-08-04 through 2026-08-03, France/EUR

The fixture data is derived from Open Food Facts and Open Prices and remains subject to the Open Database License. See `Fixtures/README.md`.
