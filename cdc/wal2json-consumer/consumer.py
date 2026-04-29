import json
import os
import select
import threading
import time
from datetime import datetime, timezone
from queue import SimpleQueue

import psycopg2
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
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "500"))

_NOTES = f"custom logical consumer{' [' + RUN_LABEL + ']' if RUN_LABEL else ''}"


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


def _fast_parse_ts(ts_str: str) -> datetime:
    """Parse wal2json timestamp ~50x faster than dateutil.parser.parse."""
    # wal2json format: "2026-04-29 00:00:00.123456+00"
    # fromisoformat needs +HH:MM — fix short tz offset
    if ts_str[-3] in "+-":
        ts_str += ":00"
    return datetime.fromisoformat(ts_str)


def extract_event_rows(payload_obj: dict, payload_len: int, observed: datetime) -> list[tuple]:
    rows = []
    ts = payload_obj.get("timestamp")
    if not ts:
        return rows
    commit_ts = _fast_parse_ts(ts)
    latency_ms = (observed - commit_ts).total_seconds() * 1000.0

    for item in payload_obj.get("change", []):
        cols = item.get("columnnames", [])
        values = item.get("columnvalues", [])
        row_map = dict(zip(cols, values))
        rows.append((
            "wal2json",
            str(row_map.get("id", "unknown")),
            commit_ts,
            latency_ms,
            payload_len,
            item.get("kind", "unknown"),
            _NOTES,
        ))
    return rows


_INSERT_SQL = """
    INSERT INTO benchmark_events
      (approach, source_event_id, source_commit_ts, latency_ms, payload_bytes, operation, notes)
    VALUES %s
"""


def write_benchmark_rows(conn, rows: list[tuple]) -> None:
    if not rows:
        return
    with conn.cursor() as cur:
        execute_values(cur, _INSERT_SQL, rows)
    conn.commit()


RETRY_DELAY = int(os.getenv("RETRY_DELAY", "3"))

_SENTINEL = None


def _writer_thread(write_queue: SimpleQueue, dsn_str: str) -> None:
    conn = psycopg2.connect(dsn_str)
    try:
        while True:
            batch = write_queue.get()
            if batch is _SENTINEL:
                break
            write_benchmark_rows(conn, batch)
            print(f"Flushed {len(batch)} wal2json rows")
    finally:
        conn.close()


def run_stream() -> None:
    repl_conn = psycopg2.connect(
        dsn(PG_DB), connection_factory=LogicalReplicationConnection
    )
    repl_cur = repl_conn.cursor()

    ensure_slot(repl_cur)

    write_queue: SimpleQueue = SimpleQueue()
    writer = threading.Thread(
        target=_writer_thread, args=(write_queue, dsn(PG_DB)), daemon=True
    )
    writer.start()

    buffer: list[tuple] = []
    last_lsn = 0
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
                observed = datetime.now(timezone.utc)
                payload = msg.payload
                rows = extract_event_rows(json.loads(payload), len(payload), observed)
                buffer.extend(rows)
                last_lsn = msg.data_start

                if len(buffer) >= BATCH_SIZE:
                    write_queue.put(buffer)
                    repl_cur.send_feedback(flush_lsn=last_lsn)
                    buffer = []
                continue  # drain all available messages first

            # No message available — flush remaining buffer
            if buffer:
                write_queue.put(buffer)
                repl_cur.send_feedback(flush_lsn=last_lsn)
                buffer = []
            # Efficient wait for data on the replication socket
            select.select([repl_conn], [], [], 0.1)
    finally:
        if buffer:
            write_queue.put(buffer)
        write_queue.put(_SENTINEL)
        writer.join(timeout=10)
        for c in (repl_cur, repl_conn):
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
import json
import os
import threading
import time
from datetime import datetime, timezone
from queue import SimpleQueue

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

_SENTINEL = None  # signals writer thread to exit


def _writer_thread(write_queue: SimpleQueue, dsn_str: str) -> None:
    """Background thread that drains the queue and writes batches to the DB."""
    conn = psycopg2.connect(dsn_str, cursor_factory=RealDictCursor)
    try:
        while True:
            batch = write_queue.get()
            if batch is _SENTINEL:
                break
            write_benchmark_rows(conn, batch)
            print(f"Flushed {len(batch)} wal2json rows")
    finally:
        conn.close()


def run_stream() -> None:
    repl_conn = psycopg2.connect(
        dsn(PG_DB), connection_factory=LogicalReplicationConnection
    )
    repl_cur = repl_conn.cursor()

    ensure_slot(repl_cur)

    write_queue: SimpleQueue = SimpleQueue()
    writer = threading.Thread(
        target=_writer_thread, args=(write_queue, dsn(PG_DB)), daemon=True
    )
    writer.start()

    buffer: list[dict] = []
    last_flush = time.monotonic()
    last_lsn = 0
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
                last_lsn = msg.data_start

            now = time.monotonic()
            if buffer and (len(buffer) >= BATCH_SIZE or now - last_flush >= flush_interval):
                write_queue.put(buffer)
                repl_cur.send_feedback(flush_lsn=last_lsn)
                buffer = []
                last_flush = now

            if not msg:
                time.sleep(0.01)
    finally:
        if buffer:
            write_queue.put(buffer)
        write_queue.put(_SENTINEL)
        writer.join(timeout=10)
        time.sleep(0.2)
        for c in (repl_cur, repl_conn):
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
