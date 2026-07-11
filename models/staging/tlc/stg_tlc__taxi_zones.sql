with

source as (

    select * from {{ ref('taxi_zone_lookup') }}

),

renamed as (

    select
        cast("LocationID" as integer) as location_id,
        "Borough" as borough,
        "Zone" as zone_name,
        service_zone
    from source

)

select * from renamed
