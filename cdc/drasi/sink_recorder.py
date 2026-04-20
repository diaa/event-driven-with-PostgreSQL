import os
from contextlib import contextmanager
from datetime import datetime, timezone

import psycopg2
from psycopg2 import pool
from dateutil import parser as dtparser
from fastapi import FastAPI
from pydantic import BaseModel

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")
PG_SSLMODE = os.getenv("PG_SSLMODE", "disable")

app = FastAPI(title="Drasi Sink Recorder")

pg_pool = pool.SimpleConnectionPool(
    minconn=2,
    maxconn=10,
    host=PG_HOST,
    port=PG_PORT,
    user=PG_USER,
    password=PG_PASSWORD,
    dbname=PG_DB,
    sslmode=PG_SSLMODE,
)


class DrasiEvent(BaseModel):
    event_id: str
    source_commit_ts: str | None = None
    operation: str | None = None
    payload_bytes: int | None = None
    query_id: str | None = None


@contextmanager
def get_conn():
    conn = pg_pool.getconn()
    try:
        # Test if the connection is still alive; reconnect if stale
        try:
            conn.isolation_level
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        except Exception:
            pg_pool.putconn(conn, close=True)
            conn = psycopg2.connect(
                host=PG_HOST,
                port=PG_PORT,
                user=PG_USER,
                password=PG_PASSWORD,
                dbname=PG_DB,
                sslmode=PG_SSLMODE,
            )
        yield conn
    finally:
        try:
            pg_pool.putconn(conn)
        except Exception:
            try:
                conn.close()
            except Exception:
                pass


def _parse_ts(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return dtparser.isoparse(raw)
    except (ValueError, TypeError):
        try:
            return dtparser.parse(raw)
        except (ValueError, TypeError):
            return None


@app.post("/events")
def record_event(event: DrasiEvent):
    observed = datetime.now(timezone.utc)
    source_ts = _parse_ts(event.source_commit_ts)
    latency_ms = None
    if source_ts is not None:
        if source_ts.tzinfo is None:
            source_ts = source_ts.replace(tzinfo=timezone.utc)
        latency_ms = (observed - source_ts).total_seconds() * 1000.0

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO benchmark_events
                  (approach, source_event_id, source_commit_ts, observed_at, latency_ms, payload_bytes, operation, notes)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    "drasi",
                    event.event_id,
                    source_ts,
                    observed,
                    latency_ms,
                    event.payload_bytes,
                    event.operation,
                    "drasi sink webhook",
                ),
            )
        conn.commit()

    return {"status": "ok"}


@app.post("/filtered-events")
def record_filtered_event(event: DrasiEvent):
    """Receives events from Drasi filtered queries (e.g. high-value-orders).

    These are recorded separately so the benchmark dashboard can show
    that Drasi only emits matching rows — wal2json and Debezium would
    have shipped every single change.
    """
    observed = datetime.now(timezone.utc)
    source_ts = _parse_ts(event.source_commit_ts)
    latency_ms = None
    if source_ts is not None:
        if source_ts.tzinfo is None:
            source_ts = source_ts.replace(tzinfo=timezone.utc)
        latency_ms = (observed - source_ts).total_seconds() * 1000.0

    query_label = event.query_id or "filtered"

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO benchmark_events
                  (approach, source_event_id, source_commit_ts, observed_at, latency_ms, payload_bytes, operation, notes)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    "drasi",
                    event.event_id,
                    source_ts,
                    observed,
                    latency_ms,
                    event.payload_bytes,
                    event.operation,
                    f"drasi filtered [{query_label}]",
                ),
            )
        conn.commit()

    return {"status": "ok", "query_id": query_label}
