# NYC Taxi Analytics: project notes

dbt + DuckDB portfolio project (published as rfhickey/nyc-taxi-analytics). Run dbt with `--profiles-dir .` from the repo root; the warehouse is the local file `data/nyc_taxi.duckdb` (schemas: raw, seeds, staging, intermediate, marts).

## Structural hazard rules (enforced, see docs/structural_hazards.md)

Every model change must hold these invariants, adopted from the dblect structural-hazard approach (Ryaboy):

1. Joins only target sides with a TESTED uniqueness guarantee on the join key (fanout safety is grounded in tests, not assumptions).
2. Rollups that group by nullable outer-join columns keep the preserved-side key in the GROUP BY (see daily_zone_performance; that key is what prevents NULL-bucket collapse).
3. INNER JOINs to reference data require a relationships test proving coverage (fct_trips.pickup_date -> dim_dates.date_day guards the static 2024..2027 date spine; do not remove it, and do not "fix" the spine by making it dynamic, static is deliberate for reproducibility).
4. Window ORDER BYs must be tie-free: the dedup in int_trips__validated orders by every non-key attribute on purpose; do not simplify it back to `order by source_file`. assert_duplicate_trips_attributes_consistent is warn-severity BY DESIGN (it surfaces conflicting duplicate source records, currently 3 groups, without failing CI).
5. No volatile functions in models: time cutoffs pin to `run_started_at`, not current_date.
6. NULL never collapses into a real category: weather_condition asserts 'Dry' only on a measured zero and uses 'Unknown' for missing observations; keep the accepted_values test in sync if buckets change.
7. tip_amount / tip_percentage are credit-card-only capture artifacts (cash tips unrecorded). Any new tip metric must carry that caveat or filter to payment_type_description = 'Credit card'.

## Auditing

- `make audit` = dbt compile + dblect structural audit; CI also runs it on every push/PR.
- Typed contracts live in `dblect/` (types.py = Money/Usd domain types; contracts/nyc_taxi.py = per-model keys, grains, constraints, functional dependencies). dblect check loads them automatically; only declare facts that are TRUE, a false declaration becomes a standing finding. `dblect/_stubs/` is generated (gitignored), refresh via `dblect init`. Enums must subclass dblect's UnitEnum/NominalEnum, not plain StrEnum.
- dblect is pre-alpha: installed from git pinned to commit 3fc46a4, with pyyaml added explicitly (missing from its declared deps). If bumping the pin, re-run the full audit and update docs/structural_hazards.md.
- Full audit record (2026-07-11, 8 findings, all resolved or accepted): docs/structural_hazards.md.

## Environment gotchas

- The local .venv is uv-managed (Python 3.14, no pip); dbt-core needs `mashumaro[msgpack]>=3.15` (stale upstream pin crashes dbt otherwise), already handled in requirements/CI.
- profiles.yml is committed intentionally (DuckDB local file, no secrets).
