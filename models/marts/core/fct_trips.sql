with trips as (

    select * from {{ ref('int_trips__enriched_with_zones') }}

),

final as (

    select
        trip_id,
        vendor_id,
        vendor_name,
        pickup_at,
        dropoff_at,
        cast(pickup_at as date) as pickup_date,
        extract(hour from pickup_at) as pickup_hour,
        pickup_location_id,
        pickup_borough,
        pickup_zone_name,
        dropoff_location_id,
        dropoff_borough,
        dropoff_zone_name,
        passenger_count,
        trip_distance_miles,
        trip_duration_minutes,
        average_speed_mph,
        rate_code_description,
        payment_type_id,
        payment_type_description,
        fare_amount,
        extra_amount,
        mta_tax_amount,
        tip_amount,
        tolls_amount,
        improvement_surcharge_amount,
        congestion_surcharge_amount,
        airport_fee_amount,
        total_amount,
        tip_percentage
    from trips

)

select * from final
