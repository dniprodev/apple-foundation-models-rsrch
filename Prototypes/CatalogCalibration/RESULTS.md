# Accepted calibration

Accepted on 2026-08-05 for the Grocery Shopping Assistant Reference App.

## Snapshot

- Use France/EUR as the first release market.
- Use a fixed 365-day price window ending at the pinned Open Prices snapshot's latest date. The prototype window is 2025-08-04 through 2026-08-03.
- Select exactly 3,000 products for the first bundled Reference Dataset: a minimum quota of 250 quality-gated, same-market products in each of the eight scenario categories, followed by 1,000 overflow products using the deterministic ranking from the ingestion contract.
- Fail the build with a coverage report rather than silently shrinking an unmet category quota.
- Keep 10,000 products as a comfortable measured ceiling, not an initial target. Increase toward it only when acceptance-scenario coverage demonstrates a need.
- A production refresh downloads the pinned bulk Parquet inputs locally before projection. The 7.7 GB product source is not treated as an interactive remote query surface.

## Measured behavior

Measurements used representative real-data row widths and the chosen SQLite schema/indexes. Scale-only rows repeat source records strictly for storage and query-load measurement; they are not Reference Dataset products.

| Indexed products | SQLite size | FTS5 p50 / p95 | Category-price index p50 / p95 |
| ---: | ---: | ---: | ---: |
| 1,000 | 2.5 MB | 0.225 / 0.274 ms | 0.036 / 0.041 ms |
| 3,000 | 7.2 MB | 0.630 / 0.742 ms | 0.034 / 0.040 ms |
| 10,000 | 23.7 MB | 2.683 / 2.989 ms | 0.034 / 0.044 ms |

The real-data fixture retained 114 quality-gated products, 1,001 price observations, and eight scenario categories. Two rebuilds produced byte-identical SQLite files and identical canonical logical checksums. The 3,000-row snapshot checksum was `966ae1413ada085fd48cb0d3db67ba78d22e029fab560b6d19cf11c96afbcd82`.

## Stable SQLite projection

The app-owned projection contains:

- `products`, with text barcode identity, display fields, quantity, category bucket, ingredient evidence, normalized scenario nutrients, vegetarian/vegan knowledge state, quality signals, and deterministic price summary;
- normalized `product_categories` and `product_allergens`, preserving `contains` versus `trace` evidence;
- raw retained `price_observations` with proof and coarse location evidence;
- FTS5 over product name, brand, ingredients, and scenario category;
- `households`, restrictions, weighted preferences, purchases/items, pantry, and cart.

Use covering indexes for category/price, category/nutrition, vegetarian/category, category-tag lookup, allergen lookup, product/date price evidence, and household/date history. Missing restriction evidence remains unknown; exclusion of a known conflict must never be presented as proof of safety.

## Query interface

The catalog/household store seam must support these model-tool and presentation queries through the same GRDB implementation:

1. full-text catalog search;
2. product detail with public evidence;
3. same-category alternatives ranked by a Demo Household's restrictions and preferences;
4. Demo Household context;
5. recent purchase history;
6. pantry state;
7. cart state.

On the real-data fixture, private-history p50/p95 was 0.025/0.030 ms and restriction-aware alternatives was 0.041/0.045 ms.

## Deterministic Demo Households

Generate state from a versioned algorithm, fixed product snapshot, fixed synthetic date interval, and these stable seeds:

- Budget Family (`41001`): 104 receipts/year, weekly target EUR 125, price-weighted selection, family quantities, no known peanut-containing purchase. Preserve unknown allergen evidence as unknown.
- Nutrition-Focused Couple (`41002`): 78 receipts/year, exclude known milk conflicts, rank the eligible pool toward lower sugar and sodium.
- Low-Waste Solo Shopper (`41003`): 60 receipts/year, require known vegetarian status for generated purchases, favor package quantities no larger than 500 g, and retain a larger pantry fixture.

All histories, pantry items, and carts reference genuine barcodes in the bundled snapshot. Reset reruns the generator; it never rebuilds or mutates the public catalog.

## What to reuse

Reuse this decision and the compact Parquet fixtures as implementation inputs. Lift the projection queries and `CatalogStore` interface where they still fit the real package structure. Rebuild production-quality error handling, migrations, configuration, and tests during implementation. Do not ship the terminal shell or scale-only duplicate rows.
