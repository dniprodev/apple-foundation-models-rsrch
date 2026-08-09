Research complete: [Open Food Facts ingestion contract](https://github.com/dniprodev/apple-foundation-models-rsrch/blob/main/docs/research/open-food-facts-ingestion.md).

## Resolution

- Pin immutable official Open Food Facts and Open Prices Parquet revisions as build-time inputs.
- Normalize text barcodes, filter and join offline, then emit a sorted checksummed SQLite snapshot plus a provenance manifest.
- Select products deterministically through category quotas, same-market price coverage, nutrition/ingredient completeness, quality signals, and stable barcode tie-breaking.
- Use API v3 only for narrow live single-product lookup; local SQLite FTS serves interactive search.
- Preserve unknown safety/nutrition states rather than treating missing data as negative evidence.
- Generate the three Demo Households from a fixed seed and selected real product codes.
- Resolve market coverage, exact price-quality filtering, pinned Parquet compatibility, attribution presentation, and refresh cadence through the existing data-calibration prototype.
