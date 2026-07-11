"""Load raw source data into the local DuckDB warehouse.

Two independent public sources land in the `raw` schema, untransformed:

  - NYC TLC yellow taxi trip records: monthly parquet files served from the
    TLC's public CloudFront CDN (no auth). Read remotely by DuckDB via httpfs.
  - Open-Meteo historical weather archive for Central Park, NYC: free JSON
    API, no API key required.

All transformation happens downstream in dbt. This script is idempotent:
re-running it replaces the raw tables for the requested window.

Usage:
    python ingestion/load_raw_data.py --start-month 2025-01 --end-month 2025-03
"""

import argparse
import logging
import sys
from datetime import date, timedelta
from pathlib import Path

import duckdb
import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

TLC_TRIP_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{month}.parquet"
OPEN_METEO_URL = "https://archive-api.open-meteo.com/v1/archive"
# Central Park weather station coordinates
NYC_LAT, NYC_LON = 40.7826, -73.9656
WEATHER_DAILY_VARS = [
    "temperature_2m_max",
    "temperature_2m_min",
    "precipitation_sum",
    "snowfall_sum",
    "wind_speed_10m_max",
]


def parse_month(value: str) -> date:
    try:
        year, month = value.split("-")
        return date(int(year), int(month), 1)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"expected YYYY-MM, got {value!r}") from exc


def month_range(start: date, end: date) -> list[str]:
    if start > end:
        raise ValueError("--start-month must not be after --end-month")
    months = []
    current = start
    while current <= end:
        months.append(current.strftime("%Y-%m"))
        current = (current.replace(day=28) + timedelta(days=4)).replace(day=1)
    return months


def last_day_of_month(month_start: date) -> date:
    return (month_start.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)


def load_yellow_trips(con: duckdb.DuckDBPyConnection, months: list[str]) -> None:
    urls = [TLC_TRIP_URL.format(month=m) for m in months]
    logger.info("Loading %d month(s) of TLC yellow taxi data: %s", len(months), ", ".join(months))
    url_list = ", ".join(f"'{u}'" for u in urls)
    con.execute(
        f"""
        create or replace table raw.yellow_trips as
        select
            *,
            current_timestamp as _loaded_at
        from read_parquet([{url_list}], union_by_name = true, filename = true)
        """
    )
    count = con.execute("select count(*) from raw.yellow_trips").fetchone()[0]
    logger.info("raw.yellow_trips: %s rows", f"{count:,}")


def load_weather(con: duckdb.DuckDBPyConnection, start: date, end: date) -> None:
    logger.info("Loading Open-Meteo daily weather for %s to %s", start, end)
    response = requests.get(
        OPEN_METEO_URL,
        params={
            "latitude": NYC_LAT,
            "longitude": NYC_LON,
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "daily": ",".join(WEATHER_DAILY_VARS),
            "timezone": "America/New_York",
        },
        timeout=60,
    )
    response.raise_for_status()
    daily = response.json()["daily"]
    rows = list(
        zip(
            daily["time"],
            daily["temperature_2m_max"],
            daily["temperature_2m_min"],
            daily["precipitation_sum"],
            daily["snowfall_sum"],
            daily["wind_speed_10m_max"],
        )
    )
    con.execute(
        """
        create or replace table raw.weather_daily (
            observation_date date,
            temperature_max_c double,
            temperature_min_c double,
            precipitation_mm double,
            snowfall_cm double,
            wind_speed_max_kmh double,
            _loaded_at timestamp default current_timestamp
        )
        """
    )
    con.executemany(
        """
        insert into raw.weather_daily
            (observation_date, temperature_max_c, temperature_min_c,
             precipitation_mm, snowfall_cm, wind_speed_max_kmh)
        values (?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    logger.info("raw.weather_daily: %s rows", f"{len(rows):,}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-month", type=parse_month, default=parse_month("2025-01"))
    parser.add_argument("--end-month", type=parse_month, default=parse_month("2025-03"))
    parser.add_argument("--db-path", default="data/nyc_taxi.duckdb")
    args = parser.parse_args()

    months = month_range(args.start_month, args.end_month)
    Path(args.db_path).parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(args.db_path)
    try:
        con.execute("install httpfs; load httpfs;")
        con.execute("create schema if not exists raw")
        load_yellow_trips(con, months)
        load_weather(con, args.start_month, last_day_of_month(args.end_month))
    finally:
        con.close()
    logger.info("Raw load complete: %s", args.db_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
