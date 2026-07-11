-- fails if total trip count in daily_zone_performance does not reconcile with fct_trips
with

fct as (

    select count(*) as trip_count from {{ ref('fct_trips') }}

),

agg as (

    select sum(trip_count) as trip_count from {{ ref('daily_zone_performance') }}

)

select
    fct.trip_count as fct_trip_count,
    agg.trip_count as agg_trip_count
from fct
cross join agg
where fct.trip_count != agg.trip_count
