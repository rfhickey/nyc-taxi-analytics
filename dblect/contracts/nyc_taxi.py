"""Model contracts for the NYC taxi pipeline.

Each contract states semantics the SQL and yml cannot express to a machine:
which columns carry money, which keys define a model's grain, and which
functional dependencies hold (decoded labels follow their codes, zone
attributes follow the zone id, calendar attributes follow the day number).
dblect resolves these against the manifest and propagates the types through
column-level lineage; see docs/structural_hazards.md.
"""

from dblect import Field, ForeignKey, ModelContract, PrimaryKey, contract

from ..types import Usd


class StgTlcYellowTrips(ModelContract):
    dbt_model = "stg_tlc__yellow_trips"

    fare: Usd(amount="fare_amount")
    tip: Usd(amount="tip_amount")
    tolls: Usd(amount="tolls_amount")
    total: Usd(amount="total_amount")

    @contract
    def vendor_id_determines_vendor_name(self):
        return self.vendor_id.determines(self.vendor_name)

    @contract
    def rate_code_id_determines_description(self):
        return self.rate_code_id.determines(self.rate_code_description)

    @contract
    def payment_type_id_determines_description(self):
        return self.payment_type_id.determines(self.payment_type_description)


class StgWeatherDailyObservations(ModelContract):
    dbt_model = "stg_weather__daily_observations"

    observation_date: PrimaryKey
    precipitation_mm: float = Field(non_negative=True)
    snowfall_cm: float = Field(non_negative=True)
    wind_speed_max_kmh: float = Field(non_negative=True)


class DimZones(ModelContract):
    dbt_model = "dim_zones"

    location_id: PrimaryKey

    @contract
    def location_determines_borough(self):
        return self.location_id.determines(self.borough)

    @contract
    def location_determines_zone_name(self):
        return self.location_id.determines(self.zone_name)


class DimDates(ModelContract):
    dbt_model = "dim_dates"

    date_day: PrimaryKey
    iso_day_of_week: int = Field(ge=1, le=7)

    @contract
    def day_determines_weekend_flag(self):
        return self.iso_day_of_week.determines(self.is_weekend)


class FctTrips(ModelContract):
    dbt_model = "fct_trips"

    trip_id: PrimaryKey
    pickup_location_id: ForeignKey("dim_zones.location_id")
    dropoff_location_id: ForeignKey("dim_zones.location_id")
    pickup_date: ForeignKey("dim_dates.date_day")
    pickup_hour: int = Field(ge=0, le=23)
    fare: Usd(amount="fare_amount")
    tip: Usd(amount="tip_amount")
    total: Usd(amount="total_amount")

    @contract
    def pickup_location_determines_borough(self):
        return self.pickup_location_id.determines(self.pickup_borough)

    @contract
    def dropoff_location_determines_borough(self):
        return self.dropoff_location_id.determines(self.dropoff_borough)


class DailyWeatherTripSummary(ModelContract):
    dbt_model = "daily_weather_trip_summary"

    date_day: PrimaryKey
    trip_count: int = Field(positive=True)
    revenue: Usd(amount="total_revenue")


class DailyZonePerformance(ModelContract):
    dbt_model = "daily_zone_performance"

    pickup_location_id: ForeignKey("dim_zones.location_id")
    trip_count: int = Field(positive=True)
    revenue: Usd(amount="total_revenue")

    @contract
    def grain_is_date_by_zone(self):
        return self.grain(per=(self.pickup_date, self.pickup_location_id))


class HourlyDemandPatterns(ModelContract):
    dbt_model = "hourly_demand_patterns"

    iso_day_of_week: int = Field(ge=1, le=7)
    pickup_hour: int = Field(ge=0, le=23)
    trip_count: int = Field(positive=True)

    @contract
    def grain_is_dow_by_hour(self):
        return self.grain(per=(self.iso_day_of_week, self.pickup_hour))

    @contract
    def dow_determines_day_name(self):
        return self.iso_day_of_week.determines(self.day_name)

    @contract
    def dow_determines_weekend_flag(self):
        return self.iso_day_of_week.determines(self.is_weekend)
