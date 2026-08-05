PYTHON := uv run --with duckdb==1.5.5 python

.PHONY: prototype report refresh clean

prototype: Generated/catalog.sqlite
	swift run CatalogProbe

report: Generated/catalog.sqlite
	swift run CatalogProbe --report

refresh:
	$(PYTHON) Scripts/refresh_fixtures.py

Generated/catalog.sqlite: Fixtures/products.parquet Fixtures/prices.parquet Scripts/build_snapshot.py
	$(PYTHON) Scripts/build_snapshot.py

clean:
	rm -f Generated/catalog.sqlite Generated/manifest.json
