import os
from datetime import datetime, timezone

import psycopg2
from fastapi import FastAPI
from pydantic import BaseModel

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")

app = FastAPI(title="Drasi Sink Recorder")


class DrasiEvent(BaseModel):
    event_id: str
    source_commit_ts: datetime | None = None
    operation: str | None = None
    payload_bytes: int | None = None


def conn_dsn() -> str:
    return (
        f"host={PG_HOST} port={PG_PORT} dbname={PG_DB} "
        f"user={PG_USER} password={PG_PASSWORD}"
    )


@app.post("/events")
def record_event(event: DrasiEvent):
    observed = datetime.now(timezone.utc)
    latency_ms = None
    if event.source_commit_ts is not None:
        latency_ms = (observed - event.source_commit_ts).total_seconds() * 1000.0

    conn = psycopg2.connect(conn_dsn())
    try:
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
    finally:
        conn.close()

    return {"status": "ok"}
