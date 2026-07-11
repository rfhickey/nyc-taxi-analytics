with trips as (

    select * from {{ ref('int_trips__validated') }}

),

pickup_zones as (

    select * from {{ ref('stg_tlc__taxi_zones') }}

),

dropoff_zones as (

    select * from {{ ref('stg_tlc__taxi_zones') }}

),

final as (

    select
        trips.*,
        pickup_zones.borough as pickup_borough,
        pickup_zones.zone_name as pickup_zone_name,
        dropoff_zones.borough as dropoff_borough,
        dropoff_zones.zone_name as dropoff_zone_name,
        date_diff('second', trips.pickup_at, trips.dropoff_at) / 60.0 as trip_duration_minutes,
        trips.trip_distance_miles / nullif(date_diff('second', trips.pickup_at, trips.dropoff_at) / 3600.0, 0) as average_speed_mph,
        round(trips.tip_amount / nullif(trips.fare_amount, 0) * 100, 2) as tip_percentage
    from trips
    left join pickup_zones
        on trips.pickup_location_id = pickup_zones.location_id
    left join dropoff_zones
        on trips.dropoff_location_id = dropoff_zones.location_id

)

select * from final
