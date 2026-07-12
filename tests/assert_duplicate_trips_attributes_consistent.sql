-- warns (does not fail) when duplicate trip records that share the dedup key
-- disagree on other attributes. int_trips__validated keeps exactly one row per
-- group deterministically, but when the discarded rows carried different
-- passenger counts, distances, or amounts, the pick is arbitrary and the
-- disagreement itself is a data-quality signal worth surfacing.
-- note: runs against staging, so it also sees duplicate groups that the
-- validation filters would remove before dedup.
{{ config(severity = 'warn') }}

with

duplicate_groups as (

    select
        vendor_id,
        pickup_at,
        dropoff_at,
        pickup_location_id,
        dropoff_location_id,
        total_amount,
        count(*) as row_count,
        count(distinct coalesce(cast(passenger_count as varchar), 'null')) as passenger_count_variants,
        count(distinct cast(trip_distance_miles as varchar)) as trip_distance_variants,
        count(distinct cast(fare_amount as varchar)) as fare_amount_variants,
        count(distinct cast(tip_amount as varchar)) as tip_amount_variants
    from {{ ref('stg_tlc__yellow_trips') }}
    group by
        vendor_id,
        pickup_at,
        dropoff_at,
        pickup_location_id,
        dropoff_location_id,
        total_amount
    having count(*) > 1

)

select *
from duplicate_groups
where passenger_count_variants > 1
    or trip_distance_variants > 1
    or fare_amount_variants > 1
    or tip_amount_variants > 1
