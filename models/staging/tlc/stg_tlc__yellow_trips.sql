with

source as (

    select * from {{ source('tlc', 'yellow_trips') }}

),

renamed as (

    select
        cast(vendorid as integer) as vendor_id,
        case vendorid
            when 1 then 'Creative Mobile Technologies'
            when 2 then 'Curb Mobility'
            when 6 then 'Myle Technologies'
            when 7 then 'Helix'
            else 'Unknown'
        end as vendor_name,
        cast(tpep_pickup_datetime as timestamp) as pickup_at,
        cast(tpep_dropoff_datetime as timestamp) as dropoff_at,
        cast(passenger_count as integer) as passenger_count,
        cast(trip_distance as double) as trip_distance_miles,
        cast(ratecodeid as integer) as rate_code_id,
        case ratecodeid
            when 1 then 'Standard rate'
            when 2 then 'JFK'
            when 3 then 'Newark'
            when 4 then 'Nassau or Westchester'
            when 5 then 'Negotiated fare'
            when 6 then 'Group ride'
            else 'Unknown'
        end as rate_code_description,
        coalesce(store_and_fwd_flag = 'Y', false) as is_store_and_forward,
        cast(pulocationid as integer) as pickup_location_id,
        cast(dolocationid as integer) as dropoff_location_id,
        cast(payment_type as integer) as payment_type_id,
        case payment_type
            when 0 then 'Flex fare'
            when 1 then 'Credit card'
            when 2 then 'Cash'
            when 3 then 'No charge'
            when 4 then 'Dispute'
            when 5 then 'Unknown'
            when 6 then 'Voided trip'
            else 'Unknown'
        end as payment_type_description,
        cast(fare_amount as decimal(10, 2)) as fare_amount,
        cast(extra as decimal(10, 2)) as extra_amount,
        cast(mta_tax as decimal(10, 2)) as mta_tax_amount,
        cast(tip_amount as decimal(10, 2)) as tip_amount,
        cast(tolls_amount as decimal(10, 2)) as tolls_amount,
        cast(improvement_surcharge as decimal(10, 2)) as improvement_surcharge_amount,
        cast(congestion_surcharge as decimal(10, 2)) as congestion_surcharge_amount,
        cast(airport_fee as decimal(10, 2)) as airport_fee_amount,
        cast(total_amount as decimal(10, 2)) as total_amount,
        filename as source_file,
        _loaded_at
    from source

)

select * from renamed
