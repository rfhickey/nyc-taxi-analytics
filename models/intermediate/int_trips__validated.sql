with trips as (

    select * from {{ ref('stg_tlc__yellow_trips') }}

),

filtered as (

    select * from trips

    -- these filters remove malformed tlc records: invalid pickup/dropoff ordering,
    -- out-of-range dates, unrealistic durations, non-physical distances and fares,
    -- and implausible passenger counts
    -- the upper bound is pinned to the start of the dbt invocation rather than
    -- current_date so this view returns the same rows whenever it is queried
    -- between builds instead of drifting with wall-clock time
    where pickup_at < dropoff_at
        and pickup_at >= '2020-01-01'
        and pickup_at < cast('{{ run_started_at.strftime("%Y-%m-%d") }}' as date) + interval 1 day
        and date_diff('hour', pickup_at, dropoff_at) < 24
        and trip_distance_miles > 0 and trip_distance_miles < 200
        and fare_amount >= 0 and total_amount >= 0 and tip_amount >= 0
        and (passenger_count is null or passenger_count between 1 and 8)

),

deduplicated as (

    select
        *,
        -- duplicates almost always land in the same monthly source file, so
        -- source_file alone ties; the remaining keys cover every other
        -- attribute so the surviving row is deterministic across reruns and
        -- thread counts. which duplicate wins is arbitrary but stable;
        -- conflicting groups are surfaced by the
        -- assert_duplicate_trips_attributes_consistent warn test
        row_number() over (
            partition by vendor_id, pickup_at, dropoff_at, pickup_location_id, dropoff_location_id, total_amount
            order by
                source_file,
                passenger_count nulls last,
                trip_distance_miles,
                rate_code_id nulls last,
                payment_type_id nulls last,
                is_store_and_forward,
                fare_amount,
                extra_amount,
                mta_tax_amount,
                tip_amount,
                tolls_amount,
                improvement_surcharge_amount,
                congestion_surcharge_amount,
                airport_fee_amount
        ) as row_num
    from filtered

)

select
    {{ dbt_utils.generate_surrogate_key(['vendor_id', 'pickup_at', 'dropoff_at', 'pickup_location_id', 'dropoff_location_id', 'total_amount']) }} as trip_id,
    * exclude (row_num)
from deduplicated
where row_num = 1
