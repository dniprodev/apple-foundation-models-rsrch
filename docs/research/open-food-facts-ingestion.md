# Open Food Facts ingestion contract

Research date: 2026-08-04
Wayfinder ticket: [#3 — Define the Open Food Facts ingestion contract](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/3)

## Decision summary

Use the official Open Food Facts and Open Prices Parquet datasets published by the verified Open Food Facts organization on Hugging Face as build-time sources. Pin both inputs to immutable revisions, filter and join them offline, then emit a small, sorted, checksummed SQLite database plus a provenance manifest. Use Open Food Facts API v3 only for optional single-product live lookup; do not build the bundled Reference Dataset by crawling the API.

The initial snapshot should contain products with usable identity, category, ingredient/restriction, nutrition, quantity, and observed price data. It should favor a single price market and currency, retain multilingual source values, and select products deterministically with category quotas and quality gates. Household histories can then be generated from the chosen real product codes without manually curating transactions.

This contract is sufficient to implement the pipeline, but five questions remain for a small prototype: market coverage, exact Open Prices quality filtering, Parquet column compatibility at the pinned revision, final license/attribution presentation, and Open Prices refresh cadence.

## Source facts

### Licensing and attribution

- The Open Food Facts database is licensed under the Open Database License (ODbL); individual database contents use the Database Contents License. Product images use CC BY-SA, with an additional warning that packaging can contain graphical elements subject to other rights. ([Open Food Facts license guide](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/))
- Open Food Facts describes the ODbL conditions as attribution and share-alike. It warns that combining Open Food Facts with another database requires the resulting database to remain legally releasable as open data. ([Open Food Facts API reuse FAQ](https://support.openfoodfacts.org/help/en-gb/12-api-data-reuse/94-are-there-conditions-to-use-the-api))
- Open Prices gives the same practical warning: comply with ODbL, mention the source, and do not combine its data with non-free data that cannot be released. ([Open Prices data guide](https://openfoodfacts.github.io/open-prices/guides/data/))

The technical documentation does not prescribe exact app-screen wording or fully resolve whether distributing this project's transformed SQLite subset triggers a particular publication mechanism. That is a compliance question, not an ingestion-algorithm question.

### Bulk sources and cadence

- The official `openfoodfacts/product-database` dataset provides a Parquet representation derived from the daily JSONL dump. Its documented transformation removes debug, hierarchy, and `lc` fields, retains tag fields, and retains language-specific ingredient text. It currently contains millions of rows and is large enough that it must be processed as a build input rather than shipped directly. ([Official product dataset card](https://huggingface.co/datasets/openfoodfacts/product-database))
- Open Food Facts also provides CSV and JSONL bulk dumps. Its official Python SDK describes CSV as smaller but limited to the most important fields, while JSONL contains the full database. ([Official Python SDK dataset documentation](https://openfoodfacts.github.io/openfoodfacts-python/usage/))
- Open Prices officially provides an API, a Parquet dataset on Hugging Face, and separate gzipped JSONL exports for prices, proofs, and locations. ([Open Prices data guide](https://openfoodfacts.github.io/open-prices/guides/data/))
- The Open Prices Parquet representation flattens price, proof, and location data into one table, including product code, price/currency/date, proof identity/type, and OSM-derived location fields. ([Official Open Prices dataset](https://huggingface.co/datasets/openfoodfacts/open-prices))
- Product exports are documented as daily. No authoritative Open Prices export cadence or availability SLA was found, so the project must not promise a particular Open Prices refresh frequency.

### Live API rules

- API v3 is the current version and is recommended for new integrations; v2 is deprecated. Product reads are limited to 15 requests/minute/IP and searches to 10 requests/minute/IP. Mobile traffic is limited per user. Global limits can also produce HTTP 503. Open Food Facts asks bulk users fetching more than a few hundred products to use exports instead. ([API introduction and limits](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/))
- Requests should identify the app using `User-Agent: app_name/app_version (URL or contact info)`. The v3 product endpoint allows a field projection and accepts `cc`, `lc`, and `tags_lc` for country/language localization. ([v3 product endpoint](https://openfoodfacts.github.io/documentation/docs/Product-Opener/v3/products/get-api-v3-product-code/))
- Product Opener's structured search is not full-text search, and Open Food Facts explicitly warns against search-as-you-type against its rate-limited search API. The bundled SQLite FTS index should serve interactive search.
- The product schema evolves. Open Food Facts says consumers must ignore new fields, avoid undocumented fields, and account for API-versioned breaking changes; v3.6 changed the tags schema and added `tags_sources`. ([Schema change log](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/ref-api-and-product-schema-change-log/))

### Identifiers and joins

- Open Food Facts' `code` is a barcode identifier and may contain leading zeroes; therefore it is text, never an integer. Dumps and exports use normalized codes. Open Food Facts pads codes with seven or fewer significant digits to eight digits, and codes with 9–12 digits to 13 digits. Its API applies the same normalization. ([Barcode normalization reference](https://openfoodfacts.github.io/openfoodfacts-server/api/ref-barcode-normalization/))
- Open Prices price rows have their own integer `id` plus `product_code`, `location_id`, and `proof_id`. Product prices join to Open Food Facts through `product_code = code` after applying the same barcode normalization. Internal Open Prices `product_id` is not the cross-dataset key. ([Open Prices price schema](https://openfoodfacts.github.io/documentation/docs/Open-prices/prices/prices_retrieve/))
- Open Prices rows can represent `PRODUCT` or `CATEGORY`. Only `PRODUCT` rows with a nonempty `product_code` belong in the product-price join. Category rows instead use `category_tag`. ([Open Prices creation schema](https://openfoodfacts.github.io/documentation/docs/Open-prices/prices/prices_create/))
- Locations have both an Open Prices `location_id` and an OSM identity. If OSM identity is retained, use the pair `(location_osm_type, location_osm_id)`; a numeric OSM ID alone is not a safe global identity across node/way/relation types.

### Locale and geography

- `countries_tags` describes countries where a product is sold. It is not the product's language or origin. `lang` is the predominant packaging language and determines the main product name and ingredient parsing; `languages_tags` and localized fields describe other available languages. ([Product base schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_base/), [product tags schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_tags/))
- Open Prices geography comes from the joined location. Price-market filtering must therefore use `location_osm_address_country_code`, along with currency and date, rather than the product's `countries_tags`. ([Official Open Prices dataset](https://huggingface.co/datasets/openfoodfacts/open-prices))
- Taxonomy tag IDs such as category and allergen tags provide a language-independent comparison key when the value exists in an Open Food Facts taxonomy. Localized display names can be requested with `tags_lc` for live results. ([v3 product endpoint](https://openfoodfacts.github.io/documentation/docs/Product-Opener/v3/products/get-api-v3-product-code/))

### Data quality and freshness

- Open Food Facts is crowdsourced and expressly does not guarantee that records are accurate, complete, or reliable. Missing and unknown values must remain distinct from known negative values. ([API introduction](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/))
- Product records expose `data_quality_errors_tags`, `data_quality_warnings_tags`, `data_quality_bugs_tags`, `states_tags`, and checking metadata. ([Product quality schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_quality/))
- `last_modified_t` changes when primary data changes, whereas `last_updated_t` also changes when computed secondary data changes. Both are useful for provenance; `last_updated_t` is the better cache-freshness signal. ([Product metadata schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_metadata/))
- Ingredients, allergens, traces, additives, vegan/vegetarian analysis, and ingredient-analysis completeness are separate fields. An absent allergen tag or vegan analysis must not be interpreted as a safety guarantee. ([Product ingredients schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_ingredients/))
- Open Prices asks contributors for a receipt or price-tag proof to help assess quality. The API exposes proof identity and metadata as well as duplicate/draft-related fields, but the reviewed documentation does not define one canonical production-quality filter for every export. ([Product prices guide](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/product-prices/), [Open Prices price schema](https://openfoodfacts.github.io/documentation/docs/Open-prices/prices/prices_retrieve/))

## Recommended ingestion contract

Everything in this section is a project recommendation inferred from the source facts above.

### 1. Pin immutable upstream artifacts

For each source, the dataset builder takes an immutable Hugging Face commit revision rather than moving `main`. It records:

- canonical dataset and file URL;
- full upstream commit SHA;
- input file SHA-256 and byte length;
- acquisition timestamp;
- observed source schema fields and product `schema_version` range;
- builder version, configuration, and deterministic seed;
- output SQLite SHA-256 and row counts by rejection reason.

The manifest is versioned beside the generated database. Release builds fail if the downloaded input checksum differs from the manifest. Updating data is an explicit pull request that changes the pinned revisions and regenerated outputs.

### 2. Use Parquet for the first pipeline

Use the official product Parquet and Open Prices Parquet inputs because they avoid API crawling and the Open Prices table already incorporates proof/location joins. They are the smallest implementation effort, although not the smallest downloads.

Fall back to the full product JSONL only if the pinned Parquet omits a required field. Do not mix values fetched later from the live API into the versioned bundled snapshot; live values belong in the app's separate cache with their fetch time and API version.

### 3. Choose a coherent price market automatically

Make `targetCountry`, `currency`, `priceWindowEnd`, and `priceWindowDays` configuration values. Before selecting products, produce a coverage table grouped by location country code and currency after applying basic validity filters. Pick one target market for a released snapshot; do not compare prices across currencies or countries.

The likely first candidate is France/EUR because the published Open Prices examples show substantial French retail coverage, but this must be confirmed by the coverage report rather than hard-coded from examples. Set `priceWindowEnd` to a fixed date derived from the pinned dataset, not the machine's current date.

### 4. Normalize and filter price observations

Retain observations only when all of these hold:

- `type == PRODUCT`;
- normalized `product_code` is nonempty;
- `price > 0`, currency equals the configured currency, and date is inside the fixed window;
- location country code equals the configured market;
- the observation is not marked as a duplicate, and its proof is not marked draft, when those fields exist in the pinned representation.

Preserve raw observation rows needed for evidence: `id`, normalized `product_code`, `price`, `price_without_discount`, discount flags/type, `price_per`, currency, date, receipt quantity, `location_id`, OSM identity and coarse display geography, `proof_id`, proof type, source, and created/updated timestamps. Do not bundle proof image bytes.

For a deterministic display price, compute the median of the latest observations in the fixed window for each `(product_code, price_per, currency)`, retaining observation count, min/max date, and min/max price. Do not compare per-unit and per-weight/per-volume observations as though they were equivalent. Calculate package-normalized unit prices only when `price_per == UNIT` and normalized product quantity/unit are both present and compatible.

### 5. Join and quality-gate products

Normalize product `code` and join it to surviving Open Prices `product_code`. Keep a product only if it:

- is a non-obsolete food product;
- is sold in the target market according to `countries_tags`;
- has a usable name, category tag, normalized barcode, and package quantity;
- has ingredient text plus parsed restriction evidence (`allergens_tags`, `traces_tags`, or `ingredients_analysis_tags` as applicable);
- has normalized nutrition values for the scenario-relevant nutrients;
- has no `data_quality_errors_tags` and no known data-quality bug affecting a required field;
- has at least one valid price observation.

Warnings should lower selection rank rather than always reject a product. Store warning and completeness signals so the UI/tools can disclose uncertainty. A missing restriction field remains `unknown`; it never becomes “safe.”

### 6. Project to an app-owned schema

Do not expose the changing upstream record directly to model tools. Project each accepted product into stable SQLite tables containing at least:

| Group | Required source values |
| --- | --- |
| Identity/provenance | `code`, `schema_version`, `rev`, `last_modified_t`, `last_updated_t` |
| Display | localized `product_name`, `generic_name`, `brands_tags`, `quantity`, `product_quantity`, `product_quantity_unit`, `lang`, `languages_tags` |
| Discovery | `categories_tags`, `labels_tags`, `countries_tags`, popularity/scan signal when present |
| Restrictions | `ingredients_text` language variants, `ingredients_tags`, `allergens_tags`, `traces_tags`, `additives_tags`, `ingredients_analysis_tags`, `unknown_ingredients_n` |
| Nutrition | normalized per-100g/per-100ml energy, fat, saturated fat, carbohydrates, sugars, fiber, proteins, salt, sodium; serving metadata; Nutri-Score grade; NOVA group; `no_nutrition_data` |
| Quality | completeness, error/warning/bug tags, states/checking metadata |
| Price | raw valid observations plus deterministic per-product summary and evidence IDs |

Prefer normalized 100g/100ml nutrition values for comparisons. Preserve whether the basis is mass or volume and do not silently compare incompatible bases. The current v3.5 nutrition schema provides a normalized aggregated set and provenance; older dump projections expose familiar `<nutrient>_100g` fields. The adapter should map the pinned representation into the same internal columns and fail on an unknown incompatible representation. ([Current nutrition schema](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_nutrition_v3.5/), [product schema guidance](https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product/))

Store barcodes and taxonomy IDs as text. Normalize one-to-many tags and localized text into child tables or indexed JSON, and create FTS over names, brands, ingredient text, and category labels. Store upstream raw values only when they support evidence or migration debugging.

### 7. Select the compact catalog without manual curation

After quality gating, assign deterministic category buckets needed by the Reference Acceptance Suite—for example breakfast cereals/spreads, dairy and alternatives, breads/wraps, proteins, fruit/vegetable products, snacks, pantry staples, and ready-to-eat lunch components. The buckets are taxonomy rules in configuration, not hand-picked product IDs.

Within each bucket, rank candidates using:

1. number and recency of valid same-market price observations;
2. completeness of required ingredients and nutrition;
3. absence of quality warnings;
4. popularity/scan signal when available;
5. normalized barcode as the final stable tie-breaker.

Select a fixed quota per bucket plus a fixed overflow quota. Include enough candidates in each bucket to expose meaningful healthier, cheaper, allergy-safe, lactose-free, and vegetarian substitutions. A starting target of 1,000–3,000 products keeps SQLite small while giving the model tools genuine search space; the coverage prototype should determine the final count.

The three Demo Households should reference a much smaller deterministic subset of these accepted product codes. Their transaction generator must use a fixed seed, fixed synthetic dates, category-driven purchasing patterns, and the snapshot's observed price summaries. This supports the acceptance scenarios without manually authoring transaction lines.

### 8. Handle localization explicitly

Use the target market only for availability and price filtering. Separately configure the app display language:

- prefer `product_name_<displayLanguage>` and `ingredients_text_<displayLanguage>` when available;
- otherwise fall back to the product's main-language values and retain the language code;
- retain canonical taxonomy IDs for filtering and comparisons;
- never machine-translate allergy/ingredient evidence as part of ingestion.

The live lookup sends explicit `cc`, `lc`, `tags_lc`, and a minimal `fields` projection so results are not accidentally localized from IP/domain defaults.

### 9. Keep live lookup narrow and resilient

Live fallback is one v3 product GET by normalized barcode or selected product code. It uses the required identifying User-Agent, requests only the projection supported by the app-owned schema, caches success with `last_updated_t` and fetch time, handles 404/503 explicitly, and applies the same validation semantics as the bundled data.

Do not call Open Food Facts search on every keystroke. The app searches bundled/cached SQLite locally. Any future remote catalog search must be explicitly rate-limited and cannot become a prerequisite for the six reference scenarios.

### 10. Make compliance visible and separable

Ship these items with every snapshot:

- an About/Data Sources entry attributing Open Food Facts and Open Prices and linking their licenses;
- a repository data notice describing the transformation and pinned sources;
- the machine-readable provenance manifest;
- source attribution on product detail/evidence surfaces where practical;
- a separately licensed treatment of any downloaded product images.

Milestone one should omit bundled product/proof image bytes unless they are necessary for the Thin Reference Shell. This avoids download size and image-specific CC BY-SA/packaging-rights work without weakening any acceptance scenario.

## Acceptance checks for the builder

The builder is acceptable when two clean runs using the same manifest produce byte-identical logical rows and the same canonical database checksum after deterministic SQLite finalization, and when it emits automated checks proving:

- every household/cart/history product code exists in the bundled catalog;
- every selected product has at least one retained same-market price observation;
- every nutrition comparison uses compatible normalized bases;
- restriction scenarios contain both conflicting and viable alternative products while preserving unknown states;
- each configured category quota is satisfied or the build fails with a coverage report;
- the six Reference Acceptance Suite scenarios have enough catalog candidates without hard-coded answers;
- no live API request is needed to reset or demonstrate any Demo Household;
- the manifest exposes all upstream revisions, hashes, filters, counts, and rejection reasons.

## Unresolved prototype questions

1. **Market coverage:** Which country/currency pair supplies enough recent, high-quality products across every configured category? Run the coverage report before locking France/EUR or the final product count.
2. **Open Prices quality semantics:** Does the pinned Parquet already exclude duplicate prices and draft proofs? If not, which available fields reliably express those states? Verify against the actual files and Open Prices implementation before finalizing filters.
3. **Parquet compatibility:** Confirm that the pinned product Parquet contains every selected nutrition, localization, and quality column with usable types. If not, switch only the missing projection to the full JSONL input.
4. **Attribution/share-alike presentation:** Confirm exact in-app wording and the distribution obligations for the transformed SQLite subset with Open Food Facts or qualified counsel. Also confirm whether retained OSM-derived location values need separate OpenStreetMap attribution.
5. **Open Prices cadence:** Treat refresh timing as opportunistic until Open Prices documents an export schedule or SLA.
