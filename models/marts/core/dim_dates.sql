with date_spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2024-01-01' as date)",
        end_date="cast('2027-01-01' as date)"
    ) }}

),

final as (

    select
        cast(date_day as date) as date_day,
        extract(year from date_day) as year,
        extract(month from date_day) as month_of_year,
        monthname(date_day) as month_name,
        extract(day from date_day) as day_of_month,
        dayname(date_day) as day_name,
        isodow(date_day) as iso_day_of_week,
        isodow(date_day) in (6, 7) as is_weekend
    from date_spine

)

select * from final
