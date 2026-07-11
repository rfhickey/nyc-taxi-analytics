with trips as (

    select * from {{ ref('stg_tlc__yellow_trips') }}

),

filtered as (

    select * from trips

    -- these filters remove malformed tlc records: invalid pickup/dropoff ordering,
    -- out-of-range dates, unrealistic durations, non-physical distances and fares,
    -- and implausible passenger counts
    where pickup_at < dropoff_at
        and pickup_at >= '2020-01-01' and pickup_at < current_date + interval 1 day
        and date_diff('hour', pickup_at, dropoff_at) < 24
        and trip_distance_miles > 0 and trip_distance_miles < 200
        and fare_amount >= 0 and total_amount >= 0 and tip_amount >= 0
        and (passenger_count is null or passenger_count between 1 and 8)

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by vendor_id, pickup_at, dropoff_at, pickup_location_id, dropoff_location_id, total_amount
            order by source_file
        ) as row_num
    from filtered

)

select
    {{ dbt_utils.generate_surrogate_key(['vendor_id', 'pickup_at', 'dropoff_at', 'pickup_location_id', 'dropoff_location_id', 'total_amount']) }} as trip_id,
    * exclude (row_num)
from deduplicated
where row_num = 1
