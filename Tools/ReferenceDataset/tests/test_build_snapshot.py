from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build_snapshot import DatasetConfig, SnapshotError, build_snapshot, normalise_barcode
from prepare_product_subset import ProductSubsetConfig, prepare_product_subset


class ReferenceDatasetBuilderTests(unittest.TestCase):
    def test_remaining_slots_are_balanced_across_categories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = root / "products.parquet"
            prices = root / "prices.parquet"
            self._write_inputs(
                products,
                prices,
                extra_categories=["en:breakfast-cereals"] * 7 + ["en:dairies"] * 7,
            )

            report = build_snapshot(
                DatasetConfig(
                    product_path=products,
                    price_path=prices,
                    output_path=root / "catalog.sqlite",
                    manifest_path=root / "manifest.json",
                    product_revision="a" * 40,
                    price_revision="b" * 40,
                    product_sha256=hashlib.sha256(products.read_bytes()).hexdigest(),
                    price_sha256=hashlib.sha256(prices.read_bytes()).hexdigest(),
                    price_window_start="2025-01-01",
                    price_window_end="2025-12-31",
                    category_target=1,
                    target_products=16,
                )
            )

            self.assertEqual(report.category_counts["breakfast"], 5)
            self.assertEqual(report.category_counts["dairy_alternatives"], 5)

    def test_category_targets_record_source_constrained_shortfalls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = root / "products.parquet"
            prices = root / "prices.parquet"
            self._write_inputs(
                products,
                prices,
                extra_categories=["en:breakfast-cereals"] * 7,
            )
            manifest_path = root / "manifest.json"

            report = build_snapshot(
                DatasetConfig(
                    product_path=products,
                    price_path=prices,
                    output_path=root / "catalog.sqlite",
                    manifest_path=manifest_path,
                    product_revision="a" * 40,
                    price_revision="b" * 40,
                    product_sha256=hashlib.sha256(products.read_bytes()).hexdigest(),
                    price_sha256=hashlib.sha256(prices.read_bytes()).hexdigest(),
                    price_window_start="2025-01-01",
                    price_window_end="2025-12-31",
                    category_target=2,
                    target_products=16,
                )
            )

            self.assertEqual(report.product_count, 16)
            self.assertEqual(report.category_shortfalls["ready_lunch"], 1)
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["selection"]["category_target"], 2)
            self.assertEqual(manifest["selection"]["category_shortfalls"]["ready_lunch"], 1)

    def test_preparation_keeps_only_products_with_eligible_prices(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = root / "products.parquet"
            prices = root / "prices.parquet"
            output = root / "matched-products.parquet"
            self._write_inputs(products, prices)

            count = prepare_product_subset(
                ProductSubsetConfig(
                    product_path=str(products),
                    price_path=prices,
                    output_path=output,
                    price_window_start="2025-01-01",
                    price_window_end="2025-12-31",
                )
            )

            self.assertEqual(count, 9)
            with duckdb.connect() as database:
                product_name_type = database.execute(
                    "SELECT typeof(product_name) FROM read_parquet(?) LIMIT 1",
                    [str(output)],
                ).fetchone()[0]
                self.assertIn("STRUCT(lang VARCHAR", product_name_type)

    def test_normalise_barcode_preserves_text_and_pads_short_codes(self) -> None:
        self.assertEqual(normalise_barcode(" 1234567 "), "01234567")
        self.assertEqual(normalise_barcode("0001234567890"), "0001234567890")
        self.assertEqual(normalise_barcode(""), None)

    def test_build_is_deterministic_and_verifies_indexed_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = root / "products.parquet"
            prices = root / "prices.parquet"
            self._write_inputs(products, prices)

            first = root / "first.sqlite"
            second = root / "second.sqlite"
            first_manifest = root / "first.json"
            second_manifest = root / "second.json"
            common = dict(
                product_path=products,
                price_path=prices,
                product_revision="a" * 40,
                price_revision="b" * 40,
                product_sha256=hashlib.sha256(products.read_bytes()).hexdigest(),
                price_sha256=hashlib.sha256(prices.read_bytes()).hexdigest(),
                target_country="FR",
                currency="EUR",
                price_window_start="2025-01-01",
                price_window_end="2025-12-31",
                category_target=1,
                target_products=9,
            )

            first_report = build_snapshot(
                DatasetConfig(output_path=first, manifest_path=first_manifest, **common)
            )
            second_report = build_snapshot(
                DatasetConfig(output_path=second, manifest_path=second_manifest, **common)
            )

            self.assertEqual(first_report.logical_sha256, second_report.logical_sha256)
            self.assertEqual(
                hashlib.sha256(first.read_bytes()).hexdigest(),
                hashlib.sha256(second.read_bytes()).hexdigest(),
            )
            self.assertEqual(first_manifest.read_bytes(), second_manifest.read_bytes())
            self.assertEqual(first_report.product_count, 9)
            self.assertEqual(first_report.category_counts["breakfast"], 2)
            self.assertEqual(first_report.category_counts["ready_lunch"], 1)
            self.assertEqual(first_report.verification["indexed_barcode_lookup"], True)

            manifest = json.loads(first_manifest.read_text(encoding="utf-8"))
            self.assertEqual(manifest["sources"]["product_revision"], "a" * 40)
            self.assertEqual(manifest["artifact"]["sha256"], first_report.artifact_sha256)
            self.assertEqual(manifest["selection"]["target_products"], 9)

            with sqlite3.connect(first) as database:
                row = database.execute(
                    "SELECT code, name FROM products WHERE code = ?", ("01234567",)
                ).fetchone()
                self.assertEqual(row, ("01234567", "Breakfast 0"))
                fts_row = database.execute(
                    "SELECT code FROM product_fts WHERE product_fts MATCH 'Breakfast'"
                ).fetchone()
                self.assertEqual(fts_row, ("01234567",))

    def test_build_rejects_an_input_checksum_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = root / "products.parquet"
            prices = root / "prices.parquet"
            self._write_inputs(products, prices)
            with self.assertRaises(SnapshotError):
                build_snapshot(
                    DatasetConfig(
                        product_path=products,
                        price_path=prices,
                        output_path=root / "catalog.sqlite",
                        manifest_path=root / "manifest.json",
                        product_revision="a" * 40,
                        price_revision="b" * 40,
                        product_sha256="0" * 64,
                        price_sha256=hashlib.sha256(prices.read_bytes()).hexdigest(),
                        category_target=1,
                        target_products=9,
                    )
                )

    def _write_inputs(
        self,
        products: Path,
        prices: Path,
        extra_categories: list[str] | None = None,
    ) -> None:
        extra_categories = extra_categories or []
        categories = [
            "en:breakfast-cereals",
            "en:dairies",
            "en:breads",
            "en:legumes",
            "en:fruits",
            "en:snacks",
            "en:pastas",
            "en:prepared-meals",
            "en:breakfast-cereals",
        ] + extra_categories
        codes = ["1234567"] + [f"200000000000{index}" for index in range(1, 9)]
        codes += [f"30000000000{index:02d}" for index in range(len(extra_categories))]
        product_values = ", ".join(f"('{code}')" for code in codes)
        price_codes = ["01234567", *codes[1:]]
        price_values = ", ".join(f"('{code}')" for code in price_codes)
        connection = duckdb.connect()
        connection.execute(
            f"""
            CREATE TABLE products AS
            SELECT * FROM (
                SELECT
                    code,
                    [struct_pack(
                        lang := 'fr',
                        "text" := 'Breakfast ' || CAST(index AS VARCHAR)
                    )] AS product_name,
                    'Brand' AS brands,
                    '500 g' AS quantity,
                    '500' AS product_quantity,
                    'g' AS product_quantity_unit,
                    ['en:france'] AS countries_tags,
                    [struct_pack(lang := 'fr', "text" := 'Ingredients')] AS ingredients_text,
                    ['en:vegetarian'] AS ingredients_analysis_tags,
                    ['en:food'] AS categories_tags,
                    [
                        struct_pack(name := 'sugars', "100g" := 2.0::DOUBLE),
                        struct_pack(name := 'sodium', "100g" := 10.0::DOUBLE),
                        struct_pack(name := 'salt', "100g" := 0.1::DOUBLE),
                        struct_pack(name := 'proteins', "100g" := 4.0::DOUBLE),
                        struct_pack(name := 'fiber', "100g" := 2.0::DOUBLE)
                    ] AS nutriments,
                    'a' AS nutriscore_grade,
                    1::INTEGER AS nova_group,
                    0.8::DOUBLE AS completeness,
                    []::VARCHAR[] AS data_quality_errors_tags,
                    []::VARCHAR[] AS data_quality_warnings_tags,
                    []::VARCHAR[] AS allergens_tags,
                    []::VARCHAR[] AS traces_tags,
                    'false' AS obsolete,
                    10::INTEGER AS scans_n
                FROM (VALUES {product_values}) AS values_table(code)
                CROSS JOIN range(1) AS range_table(index)
            )
            """
        )
        for index, category in enumerate(categories):
            code = codes[index]
            connection.execute(
                f"UPDATE products SET categories_tags = ['{category}'] WHERE code = '{code}'"
            )
        connection.execute(f"COPY products TO '{products}' (FORMAT PARQUET)")
        connection.execute(
            f"""
            CREATE TABLE prices AS
            SELECT
                row_number() OVER ()::BIGINT AS id,
                'PRODUCT' AS type,
                code AS product_code,
                2.50::DOUBLE AS price,
                false AS price_is_discounted,
                2.50::DOUBLE AS price_without_discount,
                'UNIT' AS price_per,
                'EUR' AS currency,
                DATE '2025-06-01' AS date,
                1::BIGINT AS location_id,
                1::BIGINT AS location_osm_id,
                'node' AS location_osm_type,
                'Paris' AS location_osm_address_city,
                'FR' AS location_osm_address_country_code,
                1::BIGINT AS proof_id,
                'receipt' AS proof_type,
                'fixture' AS source
            FROM (VALUES {price_values}) AS values_table(code)
            """
        )
        connection.execute(f"COPY prices TO '{prices}' (FORMAT PARQUET)")
        connection.close()


if __name__ == "__main__":
    unittest.main()
