import json
import os
import time
from datetime import datetime, timezone

import psycopg2
from dateutil import parser as dt_parser
from psycopg2.extras import RealDictCursor
from psycopg2.extras import execute_values
from psycopg2.extras import LogicalReplicationConnection

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")
PG_SSLMODE = os.getenv("PG_SSLMODE", "disable")

SLOT_NAME = os.getenv("SLOT_NAME", "wal2json_slot")
PUBLICATION = os.getenv("PUBLICATION", "app_cdc_pub")
RUN_LABEL = os.getenv("RUN_LABEL", "")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "100"))


def dsn(dbname: str) -> str:
    return (
        f"host={PG_HOST} port={PG_PORT} dbname={dbname} "
        f"user={PG_USER} password={PG_PASSWORD} sslmode={PG_SSLMODE}"
    )


def ensure_slot(cur) -> None:
    try:
        cur.create_replication_slot(SLOT_NAME, output_plugin="wal2json")
        print(f"Created replication slot: {SLOT_NAME}")
    except psycopg2.errors.DuplicateObject:
        print(f"Replication slot already exists: {SLOT_NAME}")


def parse_source_ts(payload_obj: dict) -> datetime | None:
    ts = payload_obj.get("timestamp")
    if not ts:
        return None
    try:
        return dt_parser.parse(ts)
    except Exception:
        return None


def extract_event_rows(payload_obj: dict) -> list[dict]:
    rows = []
    commit_ts = parse_source_ts(payload_obj)
    for item in payload_obj.get("change", []):
        cols = item.get("columnnames", [])
        values = item.get("columnvalues", [])
        row_map = dict(zip(cols, values))
        event_id = str(row_map.get("id", "unknown"))
        op = item.get("kind", "unknown")

        latency_ms = None
        if commit_ts is not None:
            latency_ms = (datetime.now(timezone.utc) - commit_ts).total_seconds() * 1000.0

        rows.append(
            {
                "approach": "wal2json",
                "source_event_id": event_id,
                "source_commit_ts": commit_ts,
                "latency_ms": latency_ms,
                "payload_bytes": len(json.dumps(item)),
                "operation": op,
                "notes": f"custom logical consumer{' [' + RUN_LABEL + ']' if RUN_LABEL else ''}",
            }
        )
    return rows


def write_benchmark_rows(conn, rows: list[dict]) -> None:
    if not rows:
        return

    sql = """
        INSERT INTO benchmark_events
          (approach, source_event_id, source_commit_ts, latency_ms, payload_bytes, operation, notes)
        VALUES %s
    """
    tuples = [
        (
            r["approach"],
            r["source_event_id"],
            r["source_commit_ts"],
            r["latency_ms"],
            r["payload_bytes"],
            r["operation"],
            r["notes"],
        )
        for r in rows
    ]
    with conn.cursor() as cur:
        execute_values(cur, sql, tuples)
    conn.commit()


RETRY_DELAY = int(os.getenv("RETRY_DELAY", "3"))


def run_stream() -> None:
    metrics_conn = psycopg2.connect(dsn(PG_DB), cursor_factory=RealDictCursor)
    repl_conn = psycopg2.connect(
        dsn(PG_DB), connection_factory=LogicalReplicationConnection
    )
    repl_cur = repl_conn.cursor()

    ensure_slot(repl_cur)

    buffer: list[dict] = []
    last_flush = time.monotonic()
    flush_interval = 0.5  # flush at least every 500ms
    print("Starting wal2json stream...")

    repl_cur.start_replication(
        slot_name=SLOT_NAME,
        options={
            "pretty-print": 0,
            "add-tables": "public.orders",
            "include-lsn": 1,
            "include-timestamp": 1,
        },
    )

    try:
        while True:
            msg = repl_cur.read_message()
            if msg:
                payload_obj = json.loads(msg.payload)
                rows = extract_event_rows(payload_obj)
                buffer.extend(rows)
                repl_cur.send_feedback(flush_lsn=msg.data_start)

            now = time.monotonic()
            if buffer and (len(buffer) >= BATCH_SIZE or now - last_flush >= flush_interval):
                write_benchmark_rows(metrics_conn, buffer)
                print(f"Flushed {len(buffer)} wal2json rows")
                buffer = []
                last_flush = now

            if not msg:
                time.sleep(0.01)
    finally:
        if buffer:
            write_benchmark_rows(metrics_conn, buffer)
            print(f"Final flush: {len(buffer)} wal2json rows")
        time.sleep(0.2)
        for c in (repl_cur, repl_conn, metrics_conn):
            try:
                c.close()
            except Exception:
                pass


def main() -> None:
    while True:
        try:
            run_stream()
        except KeyboardInterrupt:
            print("Stopping wal2json consumer...")
            break
        except Exception as exc:
            print(f"wal2json stream error: {exc}")
            print(f"Reconnecting in {RETRY_DELAY}s ...")
            time.sleep(RETRY_DELAY)


if __name__ == "__main__":
    main()
