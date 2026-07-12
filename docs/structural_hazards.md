# Structural hazard testing

This project treats **structural correctness** as a first-class testing concern, distinct from data quality testing. The approach follows Dmitriy Ryaboy's ["Testing dbt for structural hazards, or: introducing dblect"](https://medium.com/@squarecog/testing-dbt-for-structural-hazards-or-introducing-dblect-f9a4a7a0c34c) and the accompanying [dblect](https://github.com/dvryaboy/dblect) tool.

The core idea: some of the worst pipeline bugs survive a green build. The SQL is valid, every test passes, the row counts look right, but the *meaning* of a column has quietly shifted. Classic dbt tests (`unique`, `not_null`, `accepted_values`) validate data values; structural testing validates the shape of the transformations themselves: joins, grouping, window ordering, NULL flow, and grain claims.

## The hazard catalog

These are the structural anti-patterns dblect detects statically, plus two classes this project audits for manually. Severity follows dblect's taxonomy: **error** produces wrong rows (silent dropping, duplication, mis-grouping), **warn** covers determinism smells (correct rows that are not reproducible across runs), **info** marks observations worth surfacing.

| Hazard | What goes wrong |
|---|---|
| `null_group_after_outer_join` | GROUP BY on a column from the nullable side of an outer join collapses all unmatched rows into one NULL bucket, aggregating unrelated records together |
| `where_on_nullable_join_side` | A WHERE predicate on the nullable side silently converts an outer join into an inner join |
| `coalesce_on_join_key` | COALESCE masks "no match" as a real value on a key later used for joining or grouping |
| `window_without_order_by` / non-unique window order keys | Window functions whose ORDER BY can tie pick winners arbitrarily; results change between runs |
| `array_agg_without_order_by` | Aggregated lists come back in unpredictable order |
| `nondeterministic_in_join_key` | Volatile functions (current_date, random) in keys or filters make results depend on when a query runs |
| `join_fanout` | Joining a side that is not unique on the join key silently duplicates rows |
| `snapshot_without_temporal_filter` | Reading a dbt snapshot without a temporal filter returns every historical version |
| Silent row dropping (manual) | INNER JOINs to reference data that does not cover all fact rows make rows vanish with every test green |
| Semantic drift (manual) | NULLs collapsing into real categories, metric denominators that differ from what the name implies, yml grain claims the SQL does not honor |

## How this pipeline guards each hazard

- **Join fanout**: every join in the project targets a side with a *tested* uniqueness guarantee, not an assumed one. `stg_tlc__taxi_zones.location_id`, `dim_zones.location_id`, `stg_weather__daily_observations.observation_date`, and `dim_dates.date_day` all carry `unique` + `not_null` tests. A join is only fanout-safe if the uniqueness of its right side is enforced by a test that would fail before the fanout ships.
- **Null grouping after outer joins**: `daily_zone_performance` LEFT JOINs `dim_zones` and groups by `zone_name` and `borough` (nullable side), but it is safe because `pickup_location_id`, the preserved-side key, stays in the GROUP BY, so unmatched rows cannot collapse across zones. This is the idiom to copy: any rollup that groups by nullable enrichment columns must retain the preserved-side key (or an explicit is-matched flag). Both `pickup_location_id` and `dropoff_location_id` in `fct_trips` also carry `relationships` tests against `dim_zones`, so "no match" is loud, not silent.
- **Silent row dropping**: `daily_weather_trip_summary` LEFT JOINs weather so trip days without an observation keep their row (weather columns null, condition 'Unknown'). Joins to `dim_dates` stay INNER, but the spine is guarded by a `relationships` test from `fct_trips.pickup_date` to `dim_dates.date_day`: when the static spine (2024-01-01 to 2027-01-01, end exclusive) is exhausted, the build fails loudly instead of the date-joined marts silently freezing while `fct_trips` keeps growing. The spine is deliberately static for reproducibility; the test is what makes that safe.
- **Window determinism**: the dedup in `int_trips__validated` originally ordered ties by `source_file` alone. TLC publishes one parquet file per month, so true duplicates almost always tie, and the surviving row depended on scan order (empirically, it flipped with DuckDB thread count). The ORDER BY now covers every non-key attribute, so reruns keep the same row. Which duplicate wins is arbitrary but stable, and the `assert_duplicate_trips_attributes_consistent` warn test surfaces duplicate groups whose attributes disagree, because that disagreement is a data quality signal worth seeing rather than papering over.
- **Nondeterministic filters**: the validation cutoff (`pickup_at < <build date> + 1 day`) is pinned to `run_started_at` instead of `current_date`, so the intermediate views return the same rows whenever they are queried between builds instead of drifting with wall-clock time.
- **NULL collapsing into categories**: `weather_condition` only asserts 'Dry' when precipitation was actually measured at zero; missing observations map to 'Unknown'. An `accepted_values` test pins the full category set. The general rule: a NULL measurement is a distinct real-world state and never belongs in the same bucket as a measured zero.
- **Metric semantics**: TLC only records credit card tips, so `tip_amount` and `tip_percentage` are payment-channel artifacts, near zero for cash and Flex fare trips regardless of real tipping. That caveat existed at the staging layer but was being dropped downstream. It is now carried on `fct_trips` and on every `avg_tip_percentage` description. Empirically, zone-level `avg_tip_percentage` correlates 0.72 with credit card share across zones, so the blended metric partly measures payment mix. A payment-type-filtered tip metric is the recorded follow-up if tip analysis becomes a real use case.
- **Grain honesty**: yml descriptions state the grain the SQL actually guarantees. `daily_weather_trip_summary` is "one row per calendar date that has at least one trip", not "one row per calendar date"; `hourly_demand_patterns` covers "all trips whose pickup date is covered by the dim_dates spine", not "the full history of trips".

## The audit (2026-07-11)

Method, in order:

1. `dblect check .` against a fresh `dbt compile`: **0 findings over 11 models, 100% column resolution**.
2. A manual audit of all 11 models against the hazard catalog, run as four parallel review passes (outer-join hazards, determinism, grain and fanout, semantic drift), because static analysis cannot reason about test coverage asymmetries, DAG-level hazard setups, or documentation semantics.
3. Adversarial verification of every candidate finding: each one was independently attacked with the goal of refuting it, including read-only queries against the built DuckDB warehouse. Only findings that survived are listed below.

| # | Finding | Severity | Verdict | Resolution |
|---|---|---|---|---|
| 1 | Dedup window ordered by `source_file` alone; survivor flipped with DuckDB thread count in live tests | warn | confirmed empirically | Full deterministic tiebreaker list; warn test surfaces conflicting duplicate groups |
| 2 | Weather INNER JOIN dropped trip days without observations (2 of 92 days in current data) | error | confirmed, actively firing | LEFT JOIN weather; grain description corrected |
| 3 | NULL precipitation/snowfall collapsed into 'Dry' | error | confirmed (latent) | Measured-zero 'Dry', 'Unknown' branch, accepted_values test |
| 4 | Static date spine ends 2027-01-01; date-joined marts would silently freeze in 2027; hourly yml overclaimed "full history" | error | confirmed (latent) | relationships test on `fct_trips.pickup_date`; honest descriptions; spine kept static by design |
| 5 | `dropoff_location_id` had no not_null/relationships tests, unlike the pickup side; a future dropoff-borough rollup would hit null grouping unguarded | info | confirmed | Tests added to mirror the pickup side; safe-rollup idiom documented above |
| 6 | `current_date` in a view filter re-evaluates against wall clock on every query | warn | confirmed | Pinned to `run_started_at` |
| 7 | Credit-card-only tip capture caveat lost downstream; blended tip metrics partly measure payment mix (corr 0.72 with credit card share) | warn | confirmed, mechanism broader than first stated | Caveats restored across fct and analytics ymls; filtered-metric follow-up recorded |
| 8 | `daily_zone_performance` groups by nullable zone columns | info | refuted as a hazard | Safe because the preserved-side key stays in the GROUP BY; documented as the pattern to copy |

After the fixes: `dbt build` passes 45 tests with 1 intended warning (finding 1's signal test, currently flagging 3 conflicting duplicate groups), all 92 trip dates appear in the weather summary (previously 90), and `dblect check .` remains at 0 findings.

## The typed contract layer

Beyond the structural audit, dblect supports Pydantic-flavored declarations that
state semantics the SQL and yml cannot express to a machine. This project declares
them under `dblect/` (loaded automatically by `dblect check`):

- `dblect/types.py` defines a `Money` domain type with a `Currency` unit enum;
  the `Usd` refinement types every monetary column (fares, tips, tolls, totals,
  revenue) so amount columns carry their meaning through column-level lineage.
- `dblect/contracts/nyc_taxi.py` declares one `ModelContract` per typed model:
  primary keys (`trip_id`, `date_day`, `location_id`, `observation_date`),
  foreign keys mirroring the dbt relationships tests, grain facts for the
  aggregate marts, value constraints (non-negative precipitation, hour in 0..23),
  and the functional dependencies that actually hold: decoded labels follow their
  codes, zone attributes follow the zone id, and calendar attributes follow the
  ISO day number.

As of the audited commit this resolves 8 contracts with 9 domain-typed columns
and functional-dependency information on 5 models, all with zero findings. The
declarations are facts the analyzer grounds its reasoning in; a future model
change that contradicts one (a fanout that breaks a grain, a join that mixes
meanings) surfaces as a finding instead of a silent drift.

## Running the audit

Locally (requires [uv](https://docs.astral.sh/uv/); dblect is pre-alpha and not on PyPI, so it is pinned to the audited commit, and `pyyaml` is added because dblect does not yet declare it):

```bash
make audit
# equivalent to:
dbt compile --profiles-dir .
uvx --python 3.12 --with pyyaml \
    --from git+https://github.com/dvryaboy/dblect@3fc46a44a763667c47b02117147aa653ca9d4334 \
    dblect check .
```

CI runs the same check on every push and pull request (see `.github/workflows/ci.yml`), after `dbt build` and docs generation so `target/manifest.json` and `target/catalog.json` exist. The build fails on warn-or-worse findings.

To suppress an intentional pattern, dblect honors SQLFluff-style comments on the offending line, with or without a specific code:

```sql
group by orders.customer_id  -- noqa: DBLECT_NULL_GROUP_AFTER_OUTER_JOIN
```

No suppressions are currently needed anywhere in the project; prefer restructuring over suppressing.

## Design rules for new models

1. Never join onto a side whose uniqueness on the join key is not enforced by a test.
2. If a rollup groups by columns from the nullable side of an outer join, keep the preserved-side key (or an is-matched flag) in the GROUP BY.
3. Every INNER JOIN to reference data needs either proven full coverage (a relationships test) or a LEFT JOIN with explicit handling of the unmatched state.
4. Window ORDER BYs must not tie: cover enough columns that reruns produce identical output, and surface genuinely ambiguous ties with a warn test instead of silently resolving them.
5. No volatile functions (`current_date`, `current_timestamp`, `random`) in model logic; pin time references to `run_started_at`.
6. NULL never collapses into a real category: missing measurements get their own bucket, and CASE expressions assert a category only when its defining measurement is present.
7. yml descriptions state the grain and caveats the SQL actually guarantees, and source-layer measurement caveats (like credit-card-only tips) travel with the column all the way to the marts.
