with

source as (

    select * from {{ source('weather', 'weather_daily') }}

),

renamed as (

    select
        cast(observation_date as date) as observation_date,
        temperature_max_c,
        temperature_min_c,
        precipitation_mm,
        snowfall_cm,
        cast(wind_speed_max_kmh as double) as wind_speed_max_kmh,
        _loaded_at
    from source

)

select * from renamed
