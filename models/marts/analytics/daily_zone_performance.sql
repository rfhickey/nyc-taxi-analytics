with

trips as (

    select * from {{ ref('fct_trips') }}

),

zones as (

    select * from {{ ref('dim_zones') }}

),

joined as (

    select
        trips.pickup_date,
        trips.pickup_location_id,
        zones.zone_name,
        zones.borough,
        trips.total_amount,
        trips.fare_amount,
        trips.trip_distance_miles,
        trips.trip_duration_minutes,
        trips.tip_percentage
    from trips
    left join zones
        on trips.pickup_location_id = zones.location_id

),

aggregated as (

    select
        pickup_date,
        pickup_location_id,
        zone_name,
        borough,
        count(*) as trip_count,
        sum(total_amount) as total_revenue,
        avg(fare_amount) as avg_fare_amount,
        avg(trip_distance_miles) as avg_trip_distance_miles,
        avg(trip_duration_minutes) as avg_trip_duration_minutes,
        avg(tip_percentage) as avg_tip_percentage
    from joined
    group by
        pickup_date,
        pickup_location_id,
        zone_name,
        borough

)

select * from aggregated
