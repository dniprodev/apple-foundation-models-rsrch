#!/usr/bin/env python3
"""Materialize only product rows that have eligible pinned price evidence."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import duckdb

from build_snapshot import DEFAULT_PRODUCT_REVISION


DEFAULT_PRODUCT_URL = (
    "hf://datasets/openfoodfacts/product-database@"
    f"{DEFAULT_PRODUCT_REVISION}/food.parquet"
)


@dataclass(frozen=True)
class ProductSubsetConfig:
    product_path: str
    price_path: Path
    output_path: Path
    target_country: str = "FR"
    currency: str = "EUR"
    price_window_start: str = "2025-08-04"
    price_window_end: str = "2026-08-03"


def _sql_literal(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def _normalised_code_sql(expression: str) -> str:
    return f"""
        CASE
            WHEN length(trim(CAST({expression} AS VARCHAR))) <= 7
                THEN lpad(trim(CAST({expression} AS VARCHAR)), 8, '0')
            WHEN length(trim(CAST({expression} AS VARCHAR))) BETWEEN 9 AND 12
                THEN lpad(trim(CAST({expression} AS VARCHAR)), 13, '0')
            ELSE trim(CAST({expression} AS VARCHAR))
        END
    """


def prepare_product_subset(config: ProductSubsetConfig) -> int:
    """Write nested product rows whose normalized codes have eligible prices."""

    config.output_path.parent.mkdir(parents=True, exist_ok=True)
    connection = duckdb.connect()
    connection.execute("SET threads = 1")
    connection.execute("SET enable_http_metadata_cache = true")
    connection.execute("SET enable_external_file_cache = true")
    connection.execute("SET http_retries = 8")
    connection.execute("SET http_retry_wait_ms = 1000")
    connection.execute("SET http_retry_backoff = 2")
    connection.execute(
        f"""
        COPY (
            WITH eligible_codes AS (
                SELECT DISTINCT
                    {_normalised_code_sql("product_code")} AS code
                FROM read_parquet({_sql_literal(config.price_path)})
                WHERE upper(CAST(type AS VARCHAR)) = 'PRODUCT'
                  AND CAST(price AS DOUBLE) > 0
                  AND upper(CAST(currency AS VARCHAR)) = {_sql_literal(config.currency.upper())}
                  AND upper(CAST(location_osm_address_country_code AS VARCHAR)) =
                      {_sql_literal(config.target_country.upper())}
                  AND CAST(date AS DATE) BETWEEN
                      CAST({_sql_literal(config.price_window_start)} AS DATE)
                      AND CAST({_sql_literal(config.price_window_end)} AS DATE)
            )
            SELECT
                p.code,
                [struct_pack(
                    lang := 'fr',
                    "text" := coalesce(
                        list_extract(list_filter(p.product_name, item -> item.lang = 'fr'), 1).text,
                        list_extract(p.product_name, 1).text
                    )
                )] AS product_name,
                p.brands,
                p.quantity,
                p.product_quantity,
                p.product_quantity_unit,
                p.countries_tags,
                [struct_pack(
                    lang := 'fr',
                    "text" := coalesce(
                        list_extract(
                            list_filter(p.ingredients_text, item -> item.lang = 'fr'), 1
                        ).text,
                        list_extract(p.ingredients_text, 1).text
                    )
                )] AS ingredients_text,
                p.ingredients_analysis_tags,
                p.categories_tags,
                [
                    struct_pack(
                        name := 'sugars',
                        "100g" := list_extract(
                            list_filter(p.nutriments, item -> item.name = 'sugars'), 1
                        )."100g"
                    ),
                    struct_pack(
                        name := 'sodium',
                        "100g" := list_extract(
                            list_filter(p.nutriments, item -> item.name = 'sodium'), 1
                        )."100g"
                    ),
                    struct_pack(
                        name := 'salt',
                        "100g" := list_extract(
                            list_filter(p.nutriments, item -> item.name = 'salt'), 1
                        )."100g"
                    ),
                    struct_pack(
                        name := 'proteins',
                        "100g" := list_extract(
                            list_filter(p.nutriments, item -> item.name = 'proteins'), 1
                        )."100g"
                    ),
                    struct_pack(
                        name := 'fiber',
                        "100g" := list_extract(
                            list_filter(p.nutriments, item -> item.name = 'fiber'), 1
                        )."100g"
                    )
                ] AS nutriments,
                p.nutriscore_grade,
                p.nova_group,
                p.completeness,
                p.data_quality_errors_tags,
                p.data_quality_warnings_tags,
                p.scans_n,
                p.obsolete,
                p.allergens_tags,
                p.traces_tags
            FROM read_parquet({_sql_literal(config.product_path)}) p
            JOIN eligible_codes e ON e.code = {_normalised_code_sql("p.code")}
            ORDER BY p.code
        ) TO {_sql_literal(config.output_path)} (FORMAT PARQUET, COMPRESSION ZSTD)
        """
    )
    count = int(
        connection.execute(
            "SELECT count(*) FROM read_parquet(?)", [str(config.output_path)]
        ).fetchone()[0]
    )
    connection.close()
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", default=DEFAULT_PRODUCT_URL)
    parser.add_argument("--prices", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--country", default="FR")
    parser.add_argument("--currency", default="EUR")
    parser.add_argument("--price-window-start", default="2025-08-04")
    parser.add_argument("--price-window-end", default="2026-08-03")
    args = parser.parse_args()
    count = prepare_product_subset(
        ProductSubsetConfig(
            product_path=args.products,
            price_path=args.prices,
            output_path=args.output,
            target_country=args.country,
            currency=args.currency,
            price_window_start=args.price_window_start,
            price_window_end=args.price_window_end,
        )
    )
    print(f"Prepared {count} price-matched product rows at {args.output}")


if __name__ == "__main__":
    main()
