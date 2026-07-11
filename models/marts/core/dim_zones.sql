with taxi_zones as (

    select * from {{ ref('stg_tlc__taxi_zones') }}

),

final as (

    select
        location_id,
        zone_name,
        borough,
        service_zone,
        (zone_name ilike '%airport%' or service_zone = 'Airports') as is_airport
    from taxi_zones

)

select * from final
