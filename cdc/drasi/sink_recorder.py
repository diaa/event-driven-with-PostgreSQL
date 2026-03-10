import os
from contextlib import contextmanager
from datetime import datetime, timezone

import psycopg2
from psycopg2 import pool
from fastapi import FastAPI
from pydantic import BaseModel

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")

app = FastAPI(title="Drasi Sink Recorder")

pg_pool = pool.SimpleConnectionPool(
    minconn=2,
    maxconn=10,
    host=PG_HOST,
    port=PG_PORT,
    user=PG_USER,
    password=PG_PASSWORD,
    dbname=PG_DB,
)


class DrasiEvent(BaseModel):
    event_id: str
    source_commit_ts: datetime | None = None
    operation: str | None = None
    payload_bytes: int | None = None


@contextmanager
def get_conn():
    conn = pg_pool.getconn()
    try:
        yield conn
    finally:
        pg_pool.putconn(conn)


@app.post("/events")
def record_event(event: DrasiEvent):
    observed = datetime.now(timezone.utc)
    latency_ms = None
    if event.source_commit_ts is not None:
        latency_ms = (observed - event.source_commit_ts).total_seconds() * 1000.0

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
                    event.source_commit_ts,
                    observed,
                    latency_ms,
                    event.payload_bytes,
                    event.operation,
                    "drasi sink webhook",
                ),
            )
        conn.commit()

    return {"status": "ok"}
