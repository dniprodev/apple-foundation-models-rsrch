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


class ReferenceDatasetBuilderTests(unittest.TestCase):
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
                category_quota=1,
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
                        category_quota=1,
                        target_products=9,
                    )
                )

    def _write_inputs(self, products: Path, prices: Path) -> None:
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
        ]
        connection = duckdb.connect()
        connection.execute(
            """
            CREATE TABLE products AS
            SELECT * FROM (
                SELECT
                    code,
                    'Breakfast ' || CAST(index AS VARCHAR) AS product_name,
                    'Breakfast ' || CAST(index AS VARCHAR) AS product_name_fr,
                    'Brand' AS brands,
                    '500 g' AS quantity,
                    500.0::DOUBLE AS product_quantity,
                    'g' AS product_quantity_unit,
                    ['en:france'] AS countries_tags,
                    'Ingredients' AS ingredients_text,
                    'Ingredients' AS ingredients_text_fr,
                    ['en:vegetarian'] AS ingredients_analysis_tags,
                    ['en:food'] AS categories_tags,
                    struct_pack(sugars_100g := 2.0::DOUBLE, sodium_100g := 10.0::DOUBLE,
                                 salt_100g := 0.1::DOUBLE, proteins_100g := 4.0::DOUBLE,
                                 fiber_100g := 2.0::DOUBLE) AS nutriments,
                    'a' AS nutriscore_grade,
                    1::INTEGER AS nova_group,
                    0.8::DOUBLE AS completeness,
                    []::VARCHAR[] AS data_quality_errors_tags,
                    []::VARCHAR[] AS data_quality_warnings_tags,
                    []::VARCHAR[] AS allergens_tags,
                    []::VARCHAR[] AS traces_tags,
                    'false' AS obsolete,
                    10::INTEGER AS scans_n
                FROM (VALUES
                    ('1234567'), ('2000000000001'), ('2000000000002'), ('2000000000003'),
                    ('2000000000004'), ('2000000000005'), ('2000000000006'), ('2000000000007'),
                    ('2000000000008')) AS values_table(code)
                CROSS JOIN range(1) AS range_table(index)
            )
            """
        )
        for index, category in enumerate(categories):
            code = "1234567" if index == 0 else f"200000000000{index}"
            connection.execute(
                f"UPDATE products SET categories_tags = ['{category}'] WHERE code = '{code}'"
            )
        connection.execute(f"COPY products TO '{products}' (FORMAT PARQUET)")
        connection.execute(
            """
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
            FROM (VALUES
                ('01234567'), ('2000000000001'), ('2000000000002'), ('2000000000003'),
                ('2000000000004'), ('2000000000005'), ('2000000000006'), ('2000000000007'),
                ('2000000000008')) AS values_table(code)
            """
        )
        connection.execute(f"COPY prices TO '{prices}' (FORMAT PARQUET)")
        connection.close()


if __name__ == "__main__":
    unittest.main()
