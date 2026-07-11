.PHONY: setup ingest build docs clean

setup:
	python -m venv .venv
	.venv/bin/pip install -r requirements.txt

ingest:
	python ingestion/load_raw_data.py --start-month 2025-01 --end-month 2025-03

build:
	dbt deps && dbt build --profiles-dir .

docs:
	dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .

clean:
	dbt clean && rm -rf data
