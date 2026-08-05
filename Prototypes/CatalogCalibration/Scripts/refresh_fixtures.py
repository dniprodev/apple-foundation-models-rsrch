#!/usr/bin/env python3
"""PROTOTYPE: capture compact real-data Parquet fixtures from official sources."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import duckdb


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Fixtures"
CACHE = ROOT / ".cache"
PRODUCTS_JSONL = CACHE / "products.jsonl"
PRICES_BULK = CACHE / "prices-bulk.parquet"

PRODUCT_REVISION = "2a652ac61d03a601e132aa80833823cd33adea2d"
PRICE_REVISION = "60c5118e3c1434717d1871a37cf2ee27c61aa530"
PRICE_URL = (
    "https://huggingface.co/datasets/openfoodfacts/open-prices/resolve/"
    f"{PRICE_REVISION}/prices.parquet"
)
SEARCH_URL = "https://world.openfoodfacts.org/api/v2/search"
USER_AGENT = (
    "GroceryReferenceAppPrototype/0.1 "
    "(https://github.com/dniprodev/apple-foundation-models-rsrch)"
)

CATEGORIES = {
    "breakfast": "en:breakfast-cereals|en:spreads",
    "dairy_alternatives": "en:dairies|en:plant-based-milk-alternatives",
    "bread_wraps": "en:breads|en:wraps",
    "proteins": "en:meats|en:fish|en:legumes",
    "fruit_vegetables": "en:fruits|en:vegetables|en:fruit-based-foods",
    "snacks": "en:snacks",
    "pantry_staples": "en:pastas|en:rice|en:canned-foods",
    "ready_lunch": "en:prepared-meals|en:salads",
}

FIELDS = ",".join(
    [
        "code",
        "product_name",
        "product_name_fr",
        "brands",
        "categories_tags",
        "countries_tags",
        "quantity",
        "product_quantity",
        "product_quantity_unit",
        "ingredients_text",
        "ingredients_text_fr",
        "ingredients_tags",
        "allergens_tags",
        "traces_tags",
        "additives_tags",
        "ingredients_analysis_tags",
        "unknown_ingredients_n",
        "nutriments",
        "nutriscore_grade",
        "nova_group",
        "completeness",
        "data_quality_errors_tags",
        "data_quality_warnings_tags",
        "obsolete",
        "lang",
        "languages_tags",
        "last_modified_t",
        "last_updated_t",
        "scans_n",
    ]
)


def fetch_json(params: dict[str, str]) -> dict:
    request = Request(f"{SEARCH_URL}?{urlencode(params)}", headers={"User-Agent": USER_AGENT})
    for attempt in range(4):
        try:
            with urlopen(request, timeout=45) as response:
                return json.load(response)
        except Exception:
            if attempt == 3:
                raise
            time.sleep(8 * (attempt + 1))
    raise AssertionError("unreachable")


def download_prices() -> None:
    if PRICES_BULK.exists():
        return
    request = Request(PRICE_URL, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=180) as response, PRICES_BULK.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)


def capture_products() -> list[dict]:
    products: dict[str, dict] = {}
    for index, (bucket, category_query) in enumerate(CATEGORIES.items()):
        cache_path = CACHE / f"search-{bucket}.json"
        if cache_path.exists():
            payload = json.loads(cache_path.read_text(encoding="utf-8"))
        else:
            if index:
                time.sleep(7)  # Official search limit: 10 requests/minute/IP.
            payload = fetch_json(
                {
                    "categories_tags": category_query,
                    "countries_tags_en": "france",
                    "sort_by": "popularity_key",
                    "page_size": "20",
                    "fields": FIELDS,
                }
            )
            cache_path.write_text(
                json.dumps(payload, sort_keys=True, ensure_ascii=False),
                encoding="utf-8",
            )
        for product in payload.get("products", []):
            code = str(product.get("code") or "").strip()
            if not code:
                continue
            product["prototype_bucket"] = bucket
            products.setdefault(code, product)
        print(f"{bucket}: {payload.get('page_count', 0)} rows", flush=True)
    return [products[code] for code in sorted(products)]


def write_product_parquet(products: list[dict]) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    with PRODUCTS_JSONL.open("w", encoding="utf-8") as output:
        for product in products:
            output.write(json.dumps(product, sort_keys=True, ensure_ascii=False) + "\n")
    con = duckdb.connect()
    source = str(PRODUCTS_JSONL).replace("'", "''")
    destination = str(FIXTURES / "products.parquet").replace("'", "''")
    con.execute(
        f"COPY (SELECT * FROM read_json_auto('{source}', format='newline_delimited', "
        f"union_by_name=true)) TO '{destination}' (FORMAT PARQUET, COMPRESSION ZSTD)"
    )


def write_price_parquet() -> None:
    con = duckdb.connect()
    prices = str(PRICES_BULK).replace("'", "''")
    products = str(FIXTURES / "products.parquet").replace("'", "''")
    destination = str(FIXTURES / "prices.parquet").replace("'", "''")
    con.execute(
        f"""
        COPY (
            SELECT
                id, type, product_code, price, price_is_discounted,
                price_without_discount, discount_type, price_per, currency,
                date, receipt_quantity, location_id, location_osm_id,
                location_osm_type, location_osm_address_city,
                upper(location_osm_address_country_code) AS country_code,
                proof_id, proof_type, source, created, updated
            FROM read_parquet('{prices}')
            WHERE type = 'PRODUCT'
              AND product_code IN (SELECT code FROM read_parquet('{products}'))
              AND price > 0
              AND currency = 'EUR'
              AND upper(location_osm_address_country_code) = 'FR'
              AND date BETWEEN DATE '2025-08-04' AND DATE '2026-08-03'
            ORDER BY product_code, date, id
        ) TO '{destination}' (FORMAT PARQUET, COMPRESSION ZSTD)
        """
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    download_prices()
    products = capture_products()
    write_product_parquet(products)
    write_price_parquet()
    for name in ("products.parquet", "prices.parquet"):
        path = FIXTURES / name
        print(f"{name}: {path.stat().st_size} bytes sha256={sha256(path)}")


if __name__ == "__main__":
    main()
