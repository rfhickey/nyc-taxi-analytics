with

daily_trips as (

    select
        pickup_date,
        count(*) as trip_count,
        sum(total_amount) as total_revenue,
        avg(trip_distance_miles) as avg_trip_distance_miles,
        avg(tip_percentage) as avg_tip_percentage
    from {{ ref('fct_trips') }}
    group by pickup_date

),

weather as (

    select * from {{ ref('stg_weather__daily_observations') }}

),

dates as (

    select * from {{ ref('dim_dates') }}

),

joined as (

    select
        dates.date_day,
        dates.day_name,
        dates.is_weekend,
        weather.temperature_max_c,
        weather.temperature_min_c,
        weather.precipitation_mm,
        weather.snowfall_cm,
        case
            when weather.snowfall_cm > 0 then 'Snow'
            when weather.precipitation_mm >= 5 then 'Heavy rain'
            when weather.precipitation_mm > 0 then 'Light rain'
            else 'Dry'
        end as weather_condition,
        daily_trips.trip_count,
        daily_trips.total_revenue,
        daily_trips.avg_trip_distance_miles,
        daily_trips.avg_tip_percentage
    from daily_trips
    inner join weather
        on daily_trips.pickup_date = weather.observation_date
    inner join dates
        on daily_trips.pickup_date = dates.date_day

)

select * from joined
