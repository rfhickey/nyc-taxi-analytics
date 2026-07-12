.PHONY: setup ingest build docs audit clean

setup:
	python -m venv .venv
	.venv/bin/pip install -r requirements.txt
	.venv/bin/pip install --upgrade "mashumaro[msgpack]>=3.15"

ingest:
	python ingestion/load_raw_data.py --start-month 2025-01 --end-month 2025-03

build:
	dbt deps && dbt build --profiles-dir .

docs:
	dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .

# structural hazard audit (see docs/structural_hazards.md); requires uv.
# dblect is pre-alpha: pinned to the audited commit, pyyaml added because
# dblect does not yet declare it
audit:
	dbt compile --profiles-dir .
	uvx --python 3.12 --with pyyaml --from git+https://github.com/dvryaboy/dblect@3fc46a44a763667c47b02117147aa653ca9d4334 dblect check .

clean:
	dbt clean && rm -rf data
