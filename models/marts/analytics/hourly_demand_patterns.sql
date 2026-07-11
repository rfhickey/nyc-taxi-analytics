with

trips as (

    select * from {{ ref('fct_trips') }}

),

dates as (

    select * from {{ ref('dim_dates') }}

),

joined as (

    select
        dates.iso_day_of_week,
        dates.day_name,
        dates.is_weekend,
        trips.pickup_hour,
        trips.total_amount,
        trips.trip_distance_miles,
        trips.trip_duration_minutes
    from trips
    inner join dates
        on trips.pickup_date = dates.date_day

),

aggregated as (

    select
        iso_day_of_week,
        day_name,
        is_weekend,
        pickup_hour,
        count(*) as trip_count,
        avg(total_amount) as avg_total_amount,
        avg(trip_distance_miles) as avg_trip_distance_miles,
        avg(trip_duration_minutes) as avg_trip_duration_minutes
    from joined
    group by
        iso_day_of_week,
        day_name,
        is_weekend,
        pickup_hour

)

select * from aggregated
