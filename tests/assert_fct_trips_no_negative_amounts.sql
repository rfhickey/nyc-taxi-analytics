-- fails if any fct_trips row has a negative fare, tip, or total amount
select
    trip_id,
    fare_amount,
    tip_amount,
    total_amount
from {{ ref('fct_trips') }}
where fare_amount < 0
    or total_amount < 0
    or tip_amount < 0
