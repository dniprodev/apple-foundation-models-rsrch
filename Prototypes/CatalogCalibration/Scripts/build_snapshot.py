#!/usr/bin/env python3
"""PROTOTYPE: project representative Parquet into deterministic SQLite snapshots."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
import hashlib
import json
from pathlib import Path
import random
import sqlite3
import time

import duckdb


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Fixtures"
GENERATED = ROOT / "Generated"
PRODUCTS_PARQUET = FIXTURES / "products.parquet"
PRICES_PARQUET = FIXTURES / "prices.parquet"
PRICE_WINDOW_START = date(2025, 8, 4)
PRICE_WINDOW_END = date(2026, 8, 3)
BENCHMARK_SIZES = (1_000, 3_000, 10_000)


@dataclass(frozen=True)
class Product:
    code: str
    name: str
    brand: str
    quantity: str
    quantity_value: float | None
    quantity_unit: str | None
    category: str
    ingredients: str
    sugars_100g: float | None
    sodium_100g: float | None
    salt_100g: float | None
    protein_100g: float | None
    fiber_100g: float | None
    nutriscore: str | None
    nova_group: int | None
    vegetarian_status: str
    vegan_status: str
    completeness: float
    warning_count: int
    median_price: float
    price_observation_count: int
    allergens: tuple[str, ...]
    traces: tuple[str, ...]
    categories: tuple[str, ...]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def load_products() -> list[Product]:
    con = duckdb.connect()
    rows = con.execute(
        """
        WITH price_summary AS (
            SELECT
                product_code,
                median(price)::DOUBLE AS median_price,
                count(*)::INTEGER AS observation_count
            FROM read_parquet(?)
            GROUP BY product_code
        )
        SELECT
            p.code,
            coalesce(nullif(p.product_name_fr, ''), p.product_name),
            coalesce(p.brands, ''),
            coalesce(p.quantity, ''),
            p.product_quantity::DOUBLE,
            p.product_quantity_unit,
            p.prototype_bucket,
            coalesce(nullif(p.ingredients_text_fr, ''), p.ingredients_text),
            p.nutriments.sugars_100g,
            p.nutriments.sodium_100g,
            p.nutriments.salt_100g,
            p.nutriments.proteins_100g,
            p.nutriments.fiber_100g,
            p.nutriscore_grade,
            p.nova_group::INTEGER,
            CASE
                WHEN list_contains(p.ingredients_analysis_tags, 'en:vegetarian') THEN 'yes'
                WHEN list_contains(p.ingredients_analysis_tags, 'en:non-vegetarian') THEN 'no'
                ELSE 'unknown'
            END,
            CASE
                WHEN list_contains(p.ingredients_analysis_tags, 'en:vegan') THEN 'yes'
                WHEN list_contains(p.ingredients_analysis_tags, 'en:non-vegan') THEN 'no'
                ELSE 'unknown'
            END,
            coalesce(p.completeness, 0),
            coalesce(len(p.data_quality_warnings_tags), 0)::INTEGER,
            s.median_price,
            s.observation_count,
            coalesce(p.allergens_tags, []),
            coalesce(p.traces_tags, []),
            coalesce(p.categories_tags, [])
        FROM read_parquet(?) p
        JOIN price_summary s ON s.product_code = p.code
        WHERE coalesce(lower(p.obsolete), 'false') NOT IN ('true', 'on', '1')
          AND coalesce(len(p.data_quality_errors_tags), 0) = 0
          AND coalesce(nullif(p.product_name_fr, ''), nullif(p.product_name, '')) IS NOT NULL
          AND coalesce(nullif(p.ingredients_text_fr, ''), nullif(p.ingredients_text, '')) IS NOT NULL
          AND len(p.categories_tags) > 0
          AND p.nutriments.sugars_100g IS NOT NULL
          AND p.nutriments.sodium_100g IS NOT NULL
        ORDER BY p.prototype_bucket, p.code
        """,
        [str(PRICES_PARQUET), str(PRODUCTS_PARQUET)],
    ).fetchall()
    return [
        Product(
            code=row[0],
            name=row[1],
            brand=row[2],
            quantity=row[3],
            quantity_value=row[4],
            quantity_unit=row[5],
            category=row[6],
            ingredients=row[7],
            sugars_100g=row[8],
            sodium_100g=row[9],
            salt_100g=row[10],
            protein_100g=row[11],
            fiber_100g=row[12],
            nutriscore=row[13],
            nova_group=row[14],
            vegetarian_status=row[15],
            vegan_status=row[16],
            completeness=row[17],
            warning_count=row[18],
            median_price=row[19],
            price_observation_count=row[20],
            allergens=tuple(row[21]),
            traces=tuple(row[22]),
            categories=tuple(row[23]),
        )
        for row in rows
    ]


def load_prices(codes: set[str]) -> list[tuple]:
    con = duckdb.connect()
    return con.execute(
        """
        SELECT
            id, product_code, price::DOUBLE, price_without_discount::DOUBLE,
            price_is_discounted, coalesce(price_per, 'UNIT'), currency,
            date::VARCHAR, location_id, location_osm_id, location_osm_type,
            location_osm_address_city, country_code, proof_id, proof_type, source
        FROM read_parquet(?)
        WHERE product_code IN (SELECT unnest(?::VARCHAR[]))
        ORDER BY product_code, date, id
        """,
        [str(PRICES_PARQUET), sorted(codes)],
    ).fetchall()


SCHEMA = """
PRAGMA page_size = 4096;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA foreign_keys = ON;

CREATE TABLE products (
    code TEXT PRIMARY KEY,
    source_code TEXT NOT NULL,
    is_scale_copy INTEGER NOT NULL DEFAULT 0,
    name TEXT NOT NULL,
    brand TEXT NOT NULL,
    quantity TEXT NOT NULL,
    quantity_value REAL,
    quantity_unit TEXT,
    primary_category TEXT NOT NULL,
    ingredients TEXT NOT NULL,
    sugars_100g REAL,
    sodium_100g REAL,
    salt_100g REAL,
    protein_100g REAL,
    fiber_100g REAL,
    nutriscore TEXT,
    nova_group INTEGER,
    vegetarian_status TEXT NOT NULL CHECK (vegetarian_status IN ('yes','no','unknown')),
    vegan_status TEXT NOT NULL CHECK (vegan_status IN ('yes','no','unknown')),
    completeness REAL NOT NULL,
    warning_count INTEGER NOT NULL,
    median_price REAL NOT NULL,
    price_observation_count INTEGER NOT NULL
) WITHOUT ROWID;

CREATE INDEX products_category_price ON products(primary_category, median_price, code);
CREATE INDEX products_nutrition ON products(primary_category, sugars_100g, sodium_100g, code);
CREATE INDEX products_vegetarian ON products(vegetarian_status, primary_category, code);

CREATE TABLE product_categories (
    product_code TEXT NOT NULL REFERENCES products(code),
    category_tag TEXT NOT NULL,
    PRIMARY KEY(product_code, category_tag)
) WITHOUT ROWID;
CREATE INDEX product_categories_tag ON product_categories(category_tag, product_code);

CREATE TABLE product_allergens (
    product_code TEXT NOT NULL REFERENCES products(code),
    allergen_tag TEXT NOT NULL,
    evidence_kind TEXT NOT NULL CHECK(evidence_kind IN ('contains','trace')),
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

CREATE TABLE households (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    weekly_budget REAL,
    seed INTEGER NOT NULL
) WITHOUT ROWID;

CREATE TABLE household_restrictions (
    household_id TEXT NOT NULL REFERENCES households(id),
    kind TEXT NOT NULL,
    tag TEXT NOT NULL,
    PRIMARY KEY(household_id, kind, tag)
) WITHOUT ROWID;

CREATE TABLE household_preferences (
    household_id TEXT NOT NULL REFERENCES households(id),
    preference TEXT NOT NULL,
    weight REAL NOT NULL,
    PRIMARY KEY(household_id, preference)
) WITHOUT ROWID;

CREATE TABLE purchases (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES households(id),
    purchased_on TEXT NOT NULL,
    total REAL NOT NULL
) WITHOUT ROWID;
CREATE INDEX purchases_household_date ON purchases(household_id, purchased_on DESC, id);

CREATE TABLE purchase_items (
    purchase_id TEXT NOT NULL REFERENCES purchases(id),
    line_number INTEGER NOT NULL,
    product_code TEXT NOT NULL REFERENCES products(code),
    quantity INTEGER NOT NULL,
    unit_price REAL NOT NULL,
    PRIMARY KEY(purchase_id, line_number)
) WITHOUT ROWID;
CREATE INDEX purchase_items_product ON purchase_items(product_code, purchase_id);

CREATE TABLE pantry_items (
    household_id TEXT NOT NULL REFERENCES households(id),
    product_code TEXT NOT NULL REFERENCES products(code),
    quantity REAL NOT NULL,
    opened_on TEXT,
    best_before TEXT,
    PRIMARY KEY(household_id, product_code)
) WITHOUT ROWID;

CREATE TABLE cart_items (
    household_id TEXT NOT NULL REFERENCES households(id),
    product_code TEXT NOT NULL REFERENCES products(code),
    quantity INTEGER NOT NULL,
    PRIMARY KEY(household_id, product_code)
) WITHOUT ROWID;

CREATE VIRTUAL TABLE product_fts USING fts5(
    code UNINDEXED,
    name,
    brand,
    ingredients,
    category,
    tokenize = 'unicode61 remove_diacritics 2'
);
"""


def insert_products(db: sqlite3.Connection, products: list[Product], target_rows: int | None) -> None:
    expanded: list[tuple[str, str, int, Product]] = []
    if target_rows is None:
        expanded = [(product.code, product.code, 0, product) for product in products]
    else:
        for index in range(target_rows):
            product = products[index % len(products)]
            code = f"{product.code}~{index // len(products):04d}"
            expanded.append((code, product.code, 1, product))

    for code, source_code, is_copy, product in expanded:
        db.execute(
            """
            INSERT INTO products VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                code, source_code, is_copy, product.name, product.brand, product.quantity,
                product.quantity_value, product.quantity_unit, product.category,
                product.ingredients, product.sugars_100g, product.sodium_100g,
                product.salt_100g, product.protein_100g, product.fiber_100g,
                product.nutriscore, product.nova_group, product.vegetarian_status,
                product.vegan_status, product.completeness, product.warning_count,
                product.median_price, product.price_observation_count,
            ),
        )
        db.executemany(
            "INSERT INTO product_categories VALUES (?,?)",
            [(code, tag) for tag in product.categories],
        )
        db.executemany(
            "INSERT INTO product_allergens VALUES (?,?,?)",
            [(code, tag, "contains") for tag in product.allergens]
            + [(code, tag, "trace") for tag in product.traces],
        )
        db.execute(
            "INSERT INTO product_fts(code,name,brand,ingredients,category) VALUES (?,?,?,?,?)",
            (code, product.name, product.brand, product.ingredients, product.category),
        )


HOUSEHOLDS = (
    (
        "budget-family",
        "Budget Family",
        "Two adults and two children; weekly spending target; peanut allergy.",
        125.0,
        41001,
        (("allergen", "en:peanuts"),),
        (("lower_price", 1.0), ("family_portions", 0.6)),
    ),
    (
        "nutrition-couple",
        "Nutrition-Focused Couple",
        "Two adults; lactose intolerance; lower-sugar and lower-sodium priorities.",
        None,
        41002,
        (("allergen", "en:milk"),),
        (("lower_sugar", 1.0), ("lower_sodium", 1.0)),
    ),
    (
        "low-waste-solo",
        "Low-Waste Solo Shopper",
        "One vegetarian adult; small portions; prioritizes existing pantry stock.",
        55.0,
        41003,
        (("diet", "vegetarian"),),
        (("small_portions", 1.0), ("use_pantry_first", 1.0)),
    ),
)


def household_pool(household_id: str, products: list[Product]) -> list[Product]:
    if household_id == "budget-family":
        return [p for p in products if "en:peanuts" not in p.allergens]
    if household_id == "nutrition-couple":
        safe = [p for p in products if "en:milk" not in p.allergens]
        return sorted(safe, key=lambda p: ((p.sugars_100g or 999) + (p.sodium_100g or 999) * 20, p.code))
    return [
        p for p in products
        if p.vegetarian_status == "yes" and (p.quantity_value or 10_000) <= 500
    ]


def insert_households(db: sqlite3.Connection, products: list[Product]) -> None:
    start = date(2025, 8, 4)
    for household_id, name, description, budget, seed, restrictions, preferences in HOUSEHOLDS:
        db.execute("INSERT INTO households VALUES (?,?,?,?,?)", (household_id, name, description, budget, seed))
        db.executemany(
            "INSERT INTO household_restrictions VALUES (?,?,?)",
            [(household_id, kind, tag) for kind, tag in restrictions],
        )
        db.executemany(
            "INSERT INTO household_preferences VALUES (?,?,?)",
            [(household_id, preference, weight) for preference, weight in preferences],
        )
        pool = household_pool(household_id, products)
        if len(pool) < 12:
            raise RuntimeError(f"{household_id} has only {len(pool)} viable products")
        rng = random.Random(seed)
        receipt_count = {"budget-family": 104, "nutrition-couple": 78, "low-waste-solo": 60}[household_id]
        for receipt_index in range(receipt_count):
            day_offset = min(363, round(receipt_index * 364 / receipt_count) + rng.randrange(0, 3))
            purchased_on = start + timedelta(days=day_offset)
            line_count = rng.randint(5, 9) if household_id == "budget-family" else rng.randint(3, 6)
            if household_id == "nutrition-couple":
                candidates = pool[: max(20, len(pool) // 2)]
            elif household_id == "budget-family":
                candidates = sorted(pool, key=lambda p: (p.median_price, p.code))[: max(30, len(pool) * 3 // 4)]
            else:
                candidates = pool
            chosen = rng.sample(candidates, min(line_count, len(candidates)))
            receipt_id = f"{household_id}-{receipt_index:03d}"
            total = sum(product.median_price * (2 if household_id == "budget-family" and rng.random() < 0.25 else 1) for product in chosen)
            db.execute(
                "INSERT INTO purchases VALUES (?,?,?,?)",
                (receipt_id, household_id, purchased_on.isoformat(), round(total, 2)),
            )
            for line_number, product in enumerate(chosen, 1):
                quantity = 2 if household_id == "budget-family" and rng.random() < 0.25 else 1
                db.execute(
                    "INSERT INTO purchase_items VALUES (?,?,?,?,?)",
                    (receipt_id, line_number, product.code, quantity, product.median_price),
                )

        pantry_count = 12 if household_id == "low-waste-solo" else 7
        for product in rng.sample(pool, min(pantry_count, len(pool))):
            opened = PRICE_WINDOW_END - timedelta(days=rng.randrange(0, 21))
            best_before = opened + timedelta(days=rng.randrange(7, 120))
            db.execute(
                "INSERT INTO pantry_items VALUES (?,?,?,?,?)",
                (household_id, product.code, round(rng.uniform(0.2, 2.0), 1), opened.isoformat(), best_before.isoformat()),
            )
        for product in rng.sample(pool, min(4, len(pool))):
            db.execute("INSERT INTO cart_items VALUES (?,?,?)", (household_id, product.code, rng.randint(1, 2)))


def insert_prices(db: sqlite3.Connection, prices: list[tuple]) -> None:
    db.executemany(
        "INSERT INTO price_observations VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        prices,
    )


def finalize(db: sqlite3.Connection) -> None:
    db.execute("INSERT INTO product_fts(product_fts) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.execute("PRAGMA optimize")
    db.commit()


def create_database(path: Path, products: list[Product], prices: list[tuple], target_rows: int | None) -> float:
    if path.exists():
        path.unlink()
    started = time.perf_counter()
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    insert_products(db, products, target_rows)
    if target_rows is None:
        insert_prices(db, prices)
        insert_households(db, products)
    finalize(db)
    db.close()
    return time.perf_counter() - started


def logical_checksum(path: Path) -> str:
    db = sqlite3.connect(path)
    digest = hashlib.sha256()
    for table in (
        "products", "product_categories", "product_allergens", "price_observations",
        "households", "household_restrictions", "household_preferences", "purchases",
        "purchase_items", "pantry_items", "cart_items",
    ):
        columns = [row[1] for row in db.execute(f"PRAGMA table_info({table})")]
        order = ",".join(columns)
        for row in db.execute(f"SELECT * FROM {table} ORDER BY {order}"):
            digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode())
            digest.update(b"\n")
    db.close()
    return digest.hexdigest()


def counts(path: Path) -> dict[str, int]:
    db = sqlite3.connect(path)
    result = {
        table: db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        for table in ("products", "price_observations", "households", "purchases", "purchase_items", "pantry_items", "cart_items")
    }
    db.close()
    return result


def main() -> None:
    GENERATED.mkdir(parents=True, exist_ok=True)
    products = load_products()
    prices = load_prices({product.code for product in products})
    if len(products) < 80:
        raise RuntimeError(f"quality gate retained only {len(products)} products")

    snapshots: dict[str, dict] = {}
    primary = GENERATED / "catalog.sqlite"
    elapsed = create_database(primary, products, prices, None)
    snapshots[primary.name] = {
        "bytes": primary.stat().st_size,
        "build_seconds": round(elapsed, 4),
        "sha256": sha256(primary),
        "logical_sha256": logical_checksum(primary),
        "counts": counts(primary),
    }
    for size in BENCHMARK_SIZES:
        path = GENERATED / f"benchmark-{size}.sqlite"
        elapsed = create_database(path, products, [], size)
        snapshots[path.name] = {
            "bytes": path.stat().st_size,
            "build_seconds": round(elapsed, 4),
            "sha256": sha256(path),
            "logical_sha256": logical_checksum(path),
            "counts": counts(path),
        }

    category_counts: dict[str, int] = {}
    for product in products:
        category_counts[product.category] = category_counts.get(product.category, 0) + 1
    manifest = {
        "prototype": True,
        "market": {"country": "FR", "currency": "EUR"},
        "price_window": {"start": PRICE_WINDOW_START.isoformat(), "end": PRICE_WINDOW_END.isoformat()},
        "sources": {
            "product_schema_revision": "2a652ac61d03a601e132aa80833823cd33adea2d",
            "open_prices_revision": "60c5118e3c1434717d1871a37cf2ee27c61aa530",
            "products_fixture_sha256": sha256(PRODUCTS_PARQUET),
            "prices_fixture_sha256": sha256(PRICES_PARQUET),
        },
        "selection": {"retained_products": len(products), "category_counts": category_counts},
        "household_seeds": {row[0]: row[4] for row in HOUSEHOLDS},
        "snapshots": snapshots,
    }
    (GENERATED / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
