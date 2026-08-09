#!/usr/bin/env python3
"""Build the deterministic SQLite Reference Dataset from pinned Parquet inputs.

The builder is intentionally a build-time tool. It reads the large official
Open Food Facts and Open Prices exports with DuckDB, projects them into the
small app-owned schema, and never calls a live API.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
from statistics import median
from typing import Any, Iterable

import duckdb


BUILDER_VERSION = "2"
DEFAULT_PRODUCT_REVISION = "2a652ac61d03a601e132aa80833823cd33adea2d"
DEFAULT_PRICE_REVISION = "60c5118e3c1434717d1871a37cf2ee27c61aa530"

CATEGORY_RULES: tuple[tuple[str, frozenset[str]], ...] = (
    ("breakfast", frozenset({"en:breakfast-cereals", "en:spreads"})),
    (
        "dairy_alternatives",
        frozenset({"en:dairies", "en:plant-based-milk-alternatives"}),
    ),
    ("bread_wraps", frozenset({"en:breads", "en:wraps"})),
    ("proteins", frozenset({"en:meats", "en:fish", "en:legumes"})),
    (
        "fruit_vegetables",
        frozenset({"en:fruits", "en:vegetables", "en:fruit-based-foods"}),
    ),
    ("snacks", frozenset({"en:snacks"})),
    ("pantry_staples", frozenset({"en:pastas", "en:rice", "en:canned-foods"})),
    ("ready_lunch", frozenset({"en:prepared-meals", "en:salads"})),
)


class SnapshotError(RuntimeError):
    """Raised when inputs cannot satisfy the reproducible snapshot contract."""


@dataclass(frozen=True)
class DatasetConfig:
    product_path: Path
    price_path: Path
    output_path: Path
    manifest_path: Path
    product_revision: str = DEFAULT_PRODUCT_REVISION
    price_revision: str = DEFAULT_PRICE_REVISION
    product_sha256: str = ""
    price_sha256: str = ""
    target_country: str = "FR"
    currency: str = "EUR"
    price_window_start: str = "2025-08-04"
    price_window_end: str = "2026-08-03"
    category_target: int = 20
    target_products: int = 500

    def __post_init__(self) -> None:
        object.__setattr__(self, "product_path", Path(self.product_path))
        object.__setattr__(self, "price_path", Path(self.price_path))
        object.__setattr__(self, "output_path", Path(self.output_path))
        object.__setattr__(self, "manifest_path", Path(self.manifest_path))
        if not self.product_revision or not self.price_revision:
            raise ValueError("immutable product and price revisions are required")
        if not re.fullmatch(r"[0-9a-f]{40}", self.product_revision):
            raise ValueError("product_revision must be a 40-character immutable revision")
        if not re.fullmatch(r"[0-9a-f]{40}", self.price_revision):
            raise ValueError("price_revision must be a 40-character immutable revision")
        if not re.fullmatch(r"[0-9a-f]{64}", self.product_sha256):
            raise ValueError("product_sha256 must be a 64-character checksum")
        if not re.fullmatch(r"[0-9a-f]{64}", self.price_sha256):
            raise ValueError("price_sha256 must be a 64-character checksum")
        if self.category_target < 1:
            raise ValueError("category_target must be positive")
        if self.target_products < self.category_target * len(CATEGORY_RULES):
            raise ValueError("target_products must cover every category target")
        if date.fromisoformat(self.price_window_start) > date.fromisoformat(self.price_window_end):
            raise ValueError("price window start must not be after its end")


@dataclass(frozen=True)
class PriceObservation:
    identifier: int
    product_code: str
    price: float
    price_without_discount: float | None
    is_discounted: bool
    price_per: str
    currency: str
    observed_on: str
    location_id: int | None
    osm_id: int | None
    osm_type: str | None
    city: str | None
    country_code: str
    proof_id: int | None
    proof_type: str | None
    source: str | None


@dataclass(frozen=True)
class ProductCandidate:
    code: str
    source_code: str
    name: str
    brand: str
    quantity: str
    quantity_value: float | None
    quantity_unit: str | None
    primary_category: str
    ingredients: str
    sugars_100g: float
    sodium_100g: float
    salt_100g: float | None
    protein_100g: float | None
    fiber_100g: float | None
    nutriscore: str | None
    nova_group: int | None
    vegetarian_status: str
    vegan_status: str
    completeness: float
    warning_count: int
    scans_n: int
    allergens: tuple[str, ...]
    traces: tuple[str, ...]
    categories: tuple[str, ...]
    prices: tuple[PriceObservation, ...]

    @property
    def price_basis(self) -> str:
        grouped: dict[str, int] = {}
        for price in self.prices:
            grouped[price.price_per] = grouped.get(price.price_per, 0) + 1
        return sorted(grouped, key=lambda basis: (-grouped[basis], basis))[0]

    @property
    def median_price(self) -> float:
        return float(median(price.price for price in self.prices if price.price_per == self.price_basis))

    @property
    def latest_price_date(self) -> str:
        return max(price.observed_on for price in self.prices)

    @property
    def latest_price_ordinal(self) -> int:
        return date.fromisoformat(self.latest_price_date).toordinal()


@dataclass(frozen=True)
class SnapshotReport:
    artifact_sha256: str
    logical_sha256: str
    product_count: int
    price_count: int
    category_counts: dict[str, int]
    category_shortfalls: dict[str, int]
    rejection_counts: dict[str, int]
    verification: dict[str, Any]


def normalise_barcode(value: object) -> str | None:
    """Return an OFF-compatible textual barcode, preserving leading zeroes."""

    if value is None:
        return None
    code = str(value).strip()
    if not code or not code.isdigit():
        return None
    if len(code) <= 7:
        return code.zfill(8)
    if 9 <= len(code) <= 12:
        return code.zfill(13)
    return code


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _as_tags(value: object) -> tuple[str, ...]:
    if value is None:
        return ()
    if isinstance(value, str):
        return tuple(sorted({item.strip() for item in value.split(",") if item.strip()}))
    try:
        return tuple(sorted({str(item).strip() for item in value if str(item).strip()}))
    except TypeError:
        return ()


def _as_optional_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _as_optional_int(value: object) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _category_for(tags: Iterable[str]) -> str | None:
    tag_set = {tag.lower() for tag in tags}
    for category, rules in CATEGORY_RULES:
        if tag_set & rules:
            return category
    return None


def _country_tag_names(country_code: str) -> frozenset[str]:
    names = {
        "FR": "france",
        "DE": "germany",
        "ES": "spain",
        "IT": "italy",
        "GB": "united-kingdom",
        "US": "united-states",
    }
    code = country_code.lower()
    name = names.get(country_code.upper(), code)
    return frozenset({code, name, f"en:{code}", f"en:{name}"})


def _source_count(connection: duckdb.DuckDBPyConnection, path: Path) -> int:
    return int(connection.execute("SELECT count(*) FROM read_parquet(?)", [str(path)]).fetchone()[0])


def _load_prices(config: DatasetConfig) -> dict[str, tuple[PriceObservation, ...]]:
    connection = duckdb.connect()
    rows = connection.execute(
        """
        SELECT
            CAST(id AS BIGINT), CAST(product_code AS VARCHAR), CAST(price AS DOUBLE),
            CAST(price_without_discount AS DOUBLE), CAST(price_is_discounted AS BOOLEAN),
            coalesce(CAST(price_per AS VARCHAR), 'UNIT'), CAST(currency AS VARCHAR),
            CAST(date AS DATE), CAST(location_id AS BIGINT), CAST(location_osm_id AS BIGINT),
            CAST(location_osm_type AS VARCHAR), CAST(location_osm_address_city AS VARCHAR),
            upper(CAST(location_osm_address_country_code AS VARCHAR)),
            CAST(proof_id AS BIGINT), CAST(proof_type AS VARCHAR), CAST(source AS VARCHAR)
        FROM read_parquet(?)
        WHERE upper(CAST(type AS VARCHAR)) = 'PRODUCT'
          AND CAST(price AS DOUBLE) > 0
          AND upper(CAST(currency AS VARCHAR)) = ?
          AND upper(CAST(location_osm_address_country_code AS VARCHAR)) = ?
          AND CAST(date AS DATE) BETWEEN CAST(? AS DATE) AND CAST(? AS DATE)
        ORDER BY product_code, date, id
        """,
        [
            str(config.price_path),
            config.currency.upper(),
            config.target_country.upper(),
            config.price_window_start,
            config.price_window_end,
        ],
    ).fetchall()
    connection.close()

    grouped: dict[str, list[PriceObservation]] = {}
    for row in rows:
        code = normalise_barcode(row[1])
        if code is None:
            continue
        observation = PriceObservation(
            identifier=int(row[0]),
            product_code=code,
            price=float(row[2]),
            price_without_discount=_as_optional_float(row[3]),
            is_discounted=bool(row[4]),
            price_per=str(row[5]),
            currency=str(row[6]).upper(),
            observed_on=str(row[7]),
            location_id=_as_optional_int(row[8]),
            osm_id=_as_optional_int(row[9]),
            osm_type=str(row[10]) if row[10] is not None else None,
            city=str(row[11]) if row[11] is not None else None,
            country_code=str(row[12]).upper(),
            proof_id=_as_optional_int(row[13]),
            proof_type=str(row[14]) if row[14] is not None else None,
            source=str(row[15]) if row[15] is not None else None,
        )
        grouped.setdefault(code, []).append(observation)
    return {code: tuple(observations) for code, observations in grouped.items()}


def _load_products(
    config: DatasetConfig,
    prices_by_code: dict[str, tuple[PriceObservation, ...]],
) -> tuple[list[ProductCandidate], dict[str, int], int]:
    connection = duckdb.connect()
    source_rows = _source_count(connection, config.product_path)
    rows = connection.execute(
        """
        SELECT
            CAST(code AS VARCHAR),
            coalesce(
                nullif(list_extract(list_filter(product_name, item -> item.lang = 'fr'), 1).text, ''),
                nullif(list_extract(product_name, 1).text, '')
            ),
            coalesce(CAST(brands AS VARCHAR), ''),
            coalesce(CAST(quantity AS VARCHAR), ''),
            CAST(product_quantity AS DOUBLE), CAST(product_quantity_unit AS VARCHAR),
            countries_tags,
            list_extract(ingredients_text, 1).text,
            ingredients_analysis_tags,
            categories_tags,
            list_extract(list_filter(nutriments, item -> item.name = 'sugars'), 1)."100g",
            list_extract(list_filter(nutriments, item -> item.name = 'sodium'), 1)."100g",
            list_extract(list_filter(nutriments, item -> item.name = 'salt'), 1)."100g",
            list_extract(list_filter(nutriments, item -> item.name = 'proteins'), 1)."100g",
            list_extract(list_filter(nutriments, item -> item.name = 'fiber'), 1)."100g",
            CAST(nutriscore_grade AS VARCHAR), CAST(nova_group AS INTEGER),
            CAST(completeness AS DOUBLE), data_quality_errors_tags,
            data_quality_warnings_tags, CAST(scans_n AS INTEGER), CAST(obsolete AS VARCHAR),
            coalesce(
                nullif(list_extract(list_filter(ingredients_text, item -> item.lang = 'fr'), 1).text, ''),
                nullif(list_extract(ingredients_text, 1).text, '')
            ),
            allergens_tags, traces_tags
        FROM read_parquet(?)
        WHERE lower(CAST(obsolete AS VARCHAR)) NOT IN ('true', 'on', '1')
          AND coalesce(
              nullif(list_extract(list_filter(product_name, item -> item.lang = 'fr'), 1).text, ''),
              nullif(list_extract(product_name, 1).text, '')
          ) IS NOT NULL
          AND coalesce(
              nullif(list_extract(list_filter(ingredients_text, item -> item.lang = 'fr'), 1).text, ''),
              nullif(list_extract(ingredients_text, 1).text, '')
          ) IS NOT NULL
          AND coalesce(array_length(data_quality_errors_tags), 0) = 0
          AND list_extract(list_filter(nutriments, item -> item.name = 'sugars'), 1)."100g" IS NOT NULL
          AND list_extract(list_filter(nutriments, item -> item.name = 'sodium'), 1)."100g" IS NOT NULL
        ORDER BY code
        """,
        [str(config.product_path)],
    ).fetchall()
    connection.close()

    rejection_counts = {
        "invalid_barcode": 0,
        "not_in_target_market": 0,
        "missing_category_bucket": 0,
        "missing_package_quantity": 0,
        "missing_price": 0,
        "duplicate_normalised_barcode": 0,
    }
    products: dict[str, ProductCandidate] = {}
    for row in rows:
        code = normalise_barcode(row[0])
        if code is None:
            rejection_counts["invalid_barcode"] += 1
            continue
        country_tags = _as_tags(row[6])
        if not any(tag.lower() in _country_tag_names(config.target_country) for tag in country_tags):
            rejection_counts["not_in_target_market"] += 1
            continue
        categories = _as_tags(row[9])
        primary_category = _category_for(categories)
        if primary_category is None:
            rejection_counts["missing_category_bucket"] += 1
            continue
        quantity_value = _as_optional_float(row[4])
        quantity_unit = str(row[5]).lower() if row[5] is not None else None
        if quantity_value is None or not quantity_unit:
            rejection_counts["missing_package_quantity"] += 1
            continue
        prices = prices_by_code.get(code, ())
        if not prices:
            rejection_counts["missing_price"] += 1
            continue
        analysis_tags = _as_tags(row[8])
        if "en:vegetarian" in analysis_tags:
            vegetarian_status = "yes"
        elif "en:non-vegetarian" in analysis_tags:
            vegetarian_status = "no"
        else:
            vegetarian_status = "unknown"
        if "en:vegan" in analysis_tags:
            vegan_status = "yes"
        elif "en:non-vegan" in analysis_tags:
            vegan_status = "no"
        else:
            vegan_status = "unknown"
        candidate = ProductCandidate(
            code=code,
            source_code=str(row[0]).strip(),
            name=str(row[1]).strip(),
            brand=str(row[2]).strip(),
            quantity=str(row[3]).strip(),
            quantity_value=quantity_value,
            quantity_unit=quantity_unit,
            primary_category=primary_category,
            ingredients=str(row[22] or row[7]).strip(),
            sugars_100g=float(row[10]),
            sodium_100g=float(row[11]),
            salt_100g=_as_optional_float(row[12]),
            protein_100g=_as_optional_float(row[13]),
            fiber_100g=_as_optional_float(row[14]),
            nutriscore=str(row[15]) if row[15] else None,
            nova_group=_as_optional_int(row[16]),
            vegetarian_status=vegetarian_status,
            vegan_status=vegan_status,
            completeness=float(row[17] or 0),
            warning_count=len(_as_tags(row[19])),
            scans_n=int(row[20] or 0),
            allergens=_as_tags(row[23]),
            traces=_as_tags(row[24]),
            categories=categories,
            prices=prices,
        )
        if code in products:
            rejection_counts["duplicate_normalised_barcode"] += 1
            continue
        products[code] = candidate
    return list(products.values()), rejection_counts, source_rows


def _rank(product: ProductCandidate) -> tuple[object, ...]:
    return (
        -len(product.prices),
        -product.latest_price_ordinal,
        -product.completeness,
        product.warning_count,
        -product.scans_n,
        product.code,
    )


def _select_products(
    products: list[ProductCandidate],
    config: DatasetConfig,
) -> tuple[list[ProductCandidate], dict[str, int]]:
    by_category = {category: [] for category, _ in CATEGORY_RULES}
    for product in products:
        by_category[product.primary_category].append(product)
    ranked_by_category = {
        category: sorted(candidates, key=_rank)
        for category, candidates in by_category.items()
    }
    selected: dict[str, ProductCandidate] = {}
    shortfalls: dict[str, int] = {}
    for category, _ in CATEGORY_RULES:
        candidates = ranked_by_category[category]
        if len(candidates) < config.category_target:
            shortfalls[category] = config.category_target - len(candidates)
        for product in candidates[: config.category_target]:
            selected[product.code] = product
    if len(products) < config.target_products:
        raise SnapshotError(
            f"target requires {config.target_products} products but only {len(products)} passed quality gates"
        )
    remaining_by_category = {
        category: iter(
            product
            for product in ranked_by_category[category]
            if product.code not in selected
        )
        for category, _ in CATEGORY_RULES
    }
    while len(selected) < config.target_products:
        added_product = False
        for category, _ in CATEGORY_RULES:
            product = next(remaining_by_category[category], None)
            if product is None:
                continue
            selected[product.code] = product
            added_product = True
            if len(selected) == config.target_products:
                break
        if not added_product:
            break
    return sorted(selected.values(), key=lambda product: product.code), shortfalls


SCHEMA = """
PRAGMA page_size = 4096;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA foreign_keys = ON;
CREATE TABLE products (
    code TEXT PRIMARY KEY,
    source_code TEXT NOT NULL,
    name TEXT NOT NULL,
    brand TEXT NOT NULL,
    quantity TEXT NOT NULL,
    quantity_value REAL NOT NULL,
    quantity_unit TEXT NOT NULL,
    primary_category TEXT NOT NULL,
    ingredients TEXT NOT NULL,
    sugars_100g REAL NOT NULL,
    sodium_100g REAL NOT NULL,
    salt_100g REAL,
    protein_100g REAL,
    fiber_100g REAL,
    nutriscore TEXT,
    nova_group INTEGER,
    vegetarian_status TEXT NOT NULL CHECK (vegetarian_status IN ('yes', 'no', 'unknown')),
    vegan_status TEXT NOT NULL CHECK (vegan_status IN ('yes', 'no', 'unknown')),
    completeness REAL NOT NULL,
    warning_count INTEGER NOT NULL,
    scans_n INTEGER NOT NULL,
    median_price REAL NOT NULL,
    price_observation_count INTEGER NOT NULL,
    price_basis TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX products_category_price ON products(primary_category, median_price, code);
CREATE INDEX products_category_nutrition ON products(primary_category, sugars_100g, sodium_100g, code);
CREATE TABLE product_categories (
    product_code TEXT NOT NULL REFERENCES products(code),
    category_tag TEXT NOT NULL,
    PRIMARY KEY(product_code, category_tag)
) WITHOUT ROWID;
CREATE INDEX product_categories_tag ON product_categories(category_tag, product_code);
CREATE TABLE product_allergens (
    product_code TEXT NOT NULL REFERENCES products(code),
    allergen_tag TEXT NOT NULL,
    evidence_kind TEXT NOT NULL CHECK(evidence_kind IN ('contains', 'trace')),
    PRIMARY KEY(product_code, allergen_tag, evidence_kind)
) WITHOUT ROWID;
CREATE INDEX product_allergens_tag ON product_allergens(allergen_tag, product_code);
CREATE TABLE price_observations (
    id INTEGER PRIMARY KEY,
    product_code TEXT NOT NULL REFERENCES products(code),
    price REAL NOT NULL,
    price_without_discount REAL,
    is_discounted INTEGER NOT NULL,
    price_per TEXT NOT NULL,
    currency TEXT NOT NULL,
    observed_on TEXT NOT NULL,
    location_id INTEGER,
    osm_id INTEGER,
    osm_type TEXT,
    city TEXT,
    country_code TEXT NOT NULL,
    proof_id INTEGER,
    proof_type TEXT,
    source TEXT
);
CREATE INDEX price_product_date ON price_observations(product_code, observed_on DESC, id);
CREATE VIRTUAL TABLE product_fts USING fts5(
    code UNINDEXED, name, brand, ingredients, category,
    tokenize = 'unicode61 remove_diacritics 2'
);
"""


def _write_database(path: Path, products: list[ProductCandidate]) -> None:
    if path.exists():
        path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(path) as database:
        database.executescript(SCHEMA)
        for product in products:
            database.execute(
                """
                INSERT INTO products (
                    code, source_code, name, brand, quantity, quantity_value, quantity_unit,
                    primary_category, ingredients, sugars_100g, sodium_100g, salt_100g,
                    protein_100g, fiber_100g, nutriscore, nova_group, vegetarian_status,
                    vegan_status, completeness, warning_count, scans_n, median_price,
                    price_observation_count, price_basis
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    product.code, product.source_code, product.name, product.brand, product.quantity,
                    product.quantity_value, product.quantity_unit, product.primary_category,
                    product.ingredients, product.sugars_100g, product.sodium_100g, product.salt_100g,
                    product.protein_100g, product.fiber_100g, product.nutriscore, product.nova_group,
                    product.vegetarian_status, product.vegan_status, product.completeness,
                    product.warning_count, product.scans_n, product.median_price, len(product.prices),
                    product.price_basis,
                ),
            )
            database.executemany(
                "INSERT INTO product_categories VALUES (?, ?)",
                [(product.code, tag) for tag in product.categories],
            )
            database.executemany(
                "INSERT INTO product_allergens VALUES (?, ?, ?)",
                [(product.code, tag, "contains") for tag in product.allergens]
                + [(product.code, tag, "trace") for tag in product.traces],
            )
            database.execute(
                "INSERT INTO product_fts(code, name, brand, ingredients, category) VALUES (?, ?, ?, ?, ?)",
                (product.code, product.name, product.brand, product.ingredients, product.primary_category),
            )
            database.executemany(
                "INSERT INTO price_observations VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    (
                        price.identifier, price.product_code, price.price, price.price_without_discount,
                        int(price.is_discounted), price.price_per, price.currency, price.observed_on,
                        price.location_id, price.osm_id, price.osm_type, price.city, price.country_code,
                        price.proof_id, price.proof_type, price.source,
                    )
                    for price in product.prices
                ],
            )
        database.execute("INSERT INTO product_fts(product_fts) VALUES ('optimize')")
        database.commit()
        database.execute("VACUUM")
        database.execute("PRAGMA optimize")
        database.commit()


def _logical_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with sqlite3.connect(path) as database:
        for table in (
            "products", "product_categories", "product_allergens", "price_observations",
        ):
            columns = [row[1] for row in database.execute(f"PRAGMA table_info({table})")]
            order = ",".join(columns)
            for row in database.execute(f"SELECT * FROM {table} ORDER BY {order}"):
                digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode())
                digest.update(b"\n")
    return digest.hexdigest()


def _verify_database(path: Path, products: list[ProductCandidate]) -> dict[str, Any]:
    with sqlite3.connect(path) as database:
        barcode = products[0].code
        barcode_lookup_plan = " ".join(row[3] for row in database.execute(
            "EXPLAIN QUERY PLAN SELECT code FROM products WHERE code = ?", (barcode,)
        ))
        lookup_row = database.execute(
            "SELECT code FROM products WHERE code = ?", (barcode,)
        ).fetchone()
        indexed_barcode_lookup = "SEARCH products" in barcode_lookup_plan and lookup_row == (barcode,)
        fts_plan = " ".join(row[3] for row in database.execute(
            "EXPLAIN QUERY PLAN SELECT code FROM product_fts WHERE product_fts MATCH 'breakfast'"
        ))
        full_text_search = "VIRTUAL TABLE" in fts_plan and database.execute(
            "SELECT count(*) FROM product_fts WHERE product_fts MATCH 'breakfast'"
        ).fetchone()[0] > 0
        foreign_keys_clean = not database.execute("PRAGMA foreign_key_check").fetchone()
        price_references_clean = database.execute(
            """
            SELECT count(*) FROM price_observations p
            LEFT JOIN products product ON product.code = p.product_code
            WHERE product.code IS NULL
            """
        ).fetchone()[0] == 0
    result = {
        "indexed_barcode_lookup": indexed_barcode_lookup,
        "full_text_search": full_text_search,
        "foreign_keys_clean": foreign_keys_clean,
        "price_references_clean": price_references_clean,
        "barcode_lookup_plan": barcode_lookup_plan,
        "full_text_search_plan": fts_plan,
    }
    if not all(result[key] for key in (
        "indexed_barcode_lookup", "full_text_search", "foreign_keys_clean", "price_references_clean"
    )):
        raise SnapshotError(f"snapshot verification failed: {json.dumps(result, sort_keys=True)}")
    return result


def build_snapshot(config: DatasetConfig) -> SnapshotReport:
    if not config.product_path.exists() or not config.price_path.exists():
        raise SnapshotError("both Parquet inputs must exist")
    actual_product_sha256 = sha256(config.product_path)
    actual_price_sha256 = sha256(config.price_path)
    if actual_product_sha256 != config.product_sha256:
        raise SnapshotError(
            f"product input checksum mismatch: expected {config.product_sha256}, got {actual_product_sha256}"
        )
    if actual_price_sha256 != config.price_sha256:
        raise SnapshotError(
            f"price input checksum mismatch: expected {config.price_sha256}, got {actual_price_sha256}"
        )
    prices_by_code = _load_prices(config)
    products, rejection_counts, source_rows = _load_products(config, prices_by_code)
    selected, category_shortfalls = _select_products(products, config)
    rejection_counts["not_selected_after_quality_gate"] = len(products) - len(selected)
    _write_database(config.output_path, selected)
    verification = _verify_database(config.output_path, selected)
    category_counts = {
        category: sum(product.primary_category == category for product in selected)
        for category, _ in CATEGORY_RULES
    }
    report = SnapshotReport(
        artifact_sha256=sha256(config.output_path),
        logical_sha256=_logical_sha256(config.output_path),
        product_count=len(selected),
        price_count=sum(len(product.prices) for product in selected),
        category_counts=category_counts,
        category_shortfalls=category_shortfalls,
        rejection_counts=rejection_counts,
        verification=verification,
    )
    config.manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "builder_version": BUILDER_VERSION,
        "market": {"country": config.target_country.upper(), "currency": config.currency.upper()},
        "price_window": {"start": config.price_window_start, "end": config.price_window_end},
        "sources": {
            "product_revision": config.product_revision,
            "product_sha256": actual_product_sha256,
            "price_revision": config.price_revision,
            "price_sha256": actual_price_sha256,
            "product_source_rows": source_rows,
        },
        "selection": {
            "target_products": config.target_products,
            "category_target": config.category_target,
            "category_counts": category_counts,
            "category_shortfalls": category_shortfalls,
            "retained_products": len(selected),
            "rejection_counts": rejection_counts,
        },
        "artifact": {
            "sha256": report.artifact_sha256,
            "logical_sha256": report.logical_sha256,
            "product_count": report.product_count,
            "price_observation_count": report.price_count,
        },
        "verification": verification,
    }
    config.manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def _arguments() -> DatasetConfig:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--prices", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--product-revision", default=DEFAULT_PRODUCT_REVISION)
    parser.add_argument("--price-revision", default=DEFAULT_PRICE_REVISION)
    parser.add_argument("--product-sha256", required=True)
    parser.add_argument("--price-sha256", required=True)
    parser.add_argument("--country", default="FR")
    parser.add_argument("--currency", default="EUR")
    parser.add_argument("--price-window-start", default="2025-08-04")
    parser.add_argument("--price-window-end", default="2026-08-03")
    parser.add_argument("--category-target", type=int, default=20)
    parser.add_argument("--target-products", type=int, default=500)
    args = parser.parse_args()
    return DatasetConfig(
        product_path=args.products,
        price_path=args.prices,
        output_path=args.output,
        manifest_path=args.manifest,
        product_revision=args.product_revision,
        price_revision=args.price_revision,
        product_sha256=args.product_sha256,
        price_sha256=args.price_sha256,
        target_country=args.country,
        currency=args.currency,
        price_window_start=args.price_window_start,
        price_window_end=args.price_window_end,
        category_target=args.category_target,
        target_products=args.target_products,
    )


if __name__ == "__main__":
    result = build_snapshot(_arguments())
    print(json.dumps(result.__dict__, indent=2, sort_keys=True))
