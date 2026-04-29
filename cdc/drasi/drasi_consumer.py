"""Drasi-equivalent CDC consumer.

Reads from the drasi_slot using pgoutput (the same protocol Drasi Server uses)
and writes benchmark events to the benchmark_events table.

Applies two query filters matching the Drasi config:
  - all-orders:         every INSERT/UPDATE (benchmark parity)
  - high-value-orders:  amount >= 500 AND status IN ('PAID', 'SHIPPED')
"""

import json
import os
import select
import struct
import threading
import time
from datetime import datetime, timezone
from queue import SimpleQueue

import psycopg2
from psycopg2.extras import LogicalReplicationConnection, execute_values

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")
PG_SSLMODE = os.getenv("PG_SSLMODE", "disable")

SLOT_NAME = os.getenv("SLOT_NAME", "drasi_slot")
PUBLICATION = os.getenv("PUBLICATION", "app_cdc_pub")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "500"))
RETRY_DELAY = int(os.getenv("RETRY_DELAY", "3"))
RUN_LABEL = os.getenv("RUN_LABEL", "")


def dsn(dbname: str) -> str:
    return (
        f"host={PG_HOST} port={PG_PORT} dbname={dbname} "
        f"user={PG_USER} password={PG_PASSWORD} sslmode={PG_SSLMODE}"
    )


def ensure_slot(cur) -> None:
    try:
        cur.create_replication_slot(SLOT_NAME, output_plugin="pgoutput")
        print(f"Created replication slot: {SLOT_NAME}")
    except psycopg2.errors.DuplicateObject:
        print(f"Replication slot already exists: {SLOT_NAME}")


# pgoutput protocol message types
PG_MSG_BEGIN = ord("B")
PG_MSG_COMMIT = ord("C")
PG_MSG_RELATION = ord("R")
PG_MSG_INSERT = ord("I")
PG_MSG_UPDATE = ord("U")
PG_MSG_DELETE = ord("D")

_relations = {}
_current_commit_ts = None
_filter_debug_remaining = [10]  # mutable so it works inside nested function


def _pg_epoch():
    """PostgreSQL epoch: 2000-01-01 00:00:00 UTC."""
    return datetime(2000, 1, 1, tzinfo=timezone.utc)


def _parse_pgoutput_timestamp(usec: int) -> datetime:
    """Convert pgoutput microseconds-since-pg-epoch to a datetime."""
    return _pg_epoch() + __import__("datetime").timedelta(microseconds=usec)


def _read_string(data: bytes, offset: int) -> tuple[str, int]:
    end = data.index(b"\x00", offset)
    return data[offset:end].decode("utf-8"), end + 1


def _read_tuple_data(data: bytes, offset: int, num_cols: int) -> tuple[dict, int]:
    """Parse a TupleData section from pgoutput."""
    values = {}
    for i in range(num_cols):
        col_type = data[offset]
        offset += 1
        if col_type == ord("n"):
            values[i] = None
        elif col_type == ord("t"):
            val_len = struct.unpack("!i", data[offset : offset + 4])[0]
            offset += 4
            values[i] = data[offset : offset + val_len].decode("utf-8")
            offset += val_len
        elif col_type == ord("u"):
            values[i] = None  # unchanged TOAST
        else:
            values[i] = None
    return values, offset


def parse_pgoutput_message(data: bytes, observed: datetime | None = None) -> list[dict]:
    """Parse a single pgoutput message and return benchmark rows."""
    global _current_commit_ts
    rows = []

    if not data:
        return rows

    msg_type = data[0]

    if msg_type == PG_MSG_BEGIN:
        if len(data) >= 21:
            ts_usec = struct.unpack("!q", data[9:17])[0]
            _current_commit_ts = _parse_pgoutput_timestamp(ts_usec)

    elif msg_type == PG_MSG_RELATION:
        offset = 1
        rel_id = struct.unpack("!i", data[offset : offset + 4])[0]
        offset += 4
        ns, offset = _read_string(data, offset)
        name, offset = _read_string(data, offset)
        offset += 1  # replica identity
        num_cols = struct.unpack("!h", data[offset : offset + 2])[0]
        offset += 2
        col_names = []
        for _ in range(num_cols):
            _flags = data[offset]
            offset += 1
            col_name, offset = _read_string(data, offset)
            col_names.append(col_name)
            _type_id = struct.unpack("!i", data[offset : offset + 4])[0]
            offset += 4
            _type_mod = struct.unpack("!i", data[offset : offset + 4])[0]
            offset += 4
        _relations[rel_id] = {"schema": ns, "table": name, "columns": col_names}

    elif msg_type in (PG_MSG_INSERT, PG_MSG_UPDATE):
        offset = 1
        rel_id = struct.unpack("!i", data[offset : offset + 4])[0]
        offset += 4

        rel = _relations.get(rel_id)
        if not rel or rel["table"] != "orders":
            return rows

        # Skip old tuple for updates
        if msg_type == PG_MSG_UPDATE and data[offset] == ord("O"):
            offset += 1
            num_cols_old = struct.unpack("!h", data[offset : offset + 2])[0]
            offset += 2
            _, offset = _read_tuple_data(data, offset, num_cols_old)

        # New tuple marker
        if data[offset] == ord("N"):
            offset += 1

        # Read column count from the tuple header
        num_cols = struct.unpack("!h", data[offset : offset + 2])[0]
        offset += 2

        values_raw, _ = _read_tuple_data(data, offset, num_cols)
        col_map = {
            rel["columns"][i]: values_raw.get(i) for i in range(len(rel["columns"]))
        }

        observed_ts = observed or datetime.now(timezone.utc)
        commit_ts = _current_commit_ts
        latency_ms = None
        if commit_ts:
            latency_ms = (observed_ts - commit_ts).total_seconds() * 1000.0

        event_id = col_map.get("id", "unknown")
        op = "INSERT" if msg_type == PG_MSG_INSERT else "UPDATE"

        # all-orders query (unfiltered — benchmark parity)
        rows.append(
            (
                "drasi",
                str(event_id),
                commit_ts,
                latency_ms,
                len(data),
                op,
                f"drasi sink webhook{' [' + RUN_LABEL + ']' if RUN_LABEL else ''}",
            )
        )

        # high-value-orders query (filtered)
        try:
            amount = float(col_map.get("amount", 0))
        except (TypeError, ValueError):
            amount = 0
        status = col_map.get("status", "")
        if _filter_debug_remaining[0] > 0:
            _filter_debug_remaining[0] -= 1
            print(f"[FILTER-DBG] amount={amount} status={status!r} col_map keys={list(col_map.keys())}")
        if amount >= 500 and status in ("PAID", "SHIPPED"):
            rows.append(
                (
                    "drasi",
                    str(event_id),
                    commit_ts,
                    latency_ms,
                    len(data),
                    op,
                    f"drasi filtered [high-value-orders]{' [' + RUN_LABEL + ']' if RUN_LABEL else ''}",
                )
            )

    return rows


def write_rows(conn, rows: list[tuple]) -> None:
    if not rows:
        return
    sql = """
        INSERT INTO benchmark_events
          (approach, source_event_id, source_commit_ts, latency_ms, payload_bytes, operation, notes)
        VALUES %s
    """
    with conn.cursor() as cur:
        execute_values(cur, sql, rows)
    conn.commit()


_SENTINEL = None  # signals writer thread to exit


def _writer_thread(write_queue: SimpleQueue, dsn_str: str) -> None:
    """Background thread that drains the queue and writes batches to the DB."""
    conn = psycopg2.connect(dsn_str)
    try:
        while True:
            batch = write_queue.get()
            if batch is _SENTINEL:
                break
            write_rows(conn, batch)
            print(f"Flushed {len(batch)} Drasi rows")
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
    print("Starting Drasi pgoutput stream...")

    repl_cur.start_replication(
        slot_name=SLOT_NAME,
        decode=False,
        options={"proto_version": "1", "publication_names": PUBLICATION},
    )

    try:
        while True:
            msg = repl_cur.read_message()
            if msg:
                observed = datetime.now(timezone.utc)
                rows = parse_pgoutput_message(
                    msg.payload if isinstance(msg.payload, bytes)
                    else msg.payload.encode("latin-1"),
                    observed,
                )
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
            print("Stopping Drasi consumer...")
            break
        except Exception as exc:
            print(f"Drasi stream error: {exc}")
            print(f"Reconnecting in {RETRY_DELAY}s ...")
            time.sleep(RETRY_DELAY)


if __name__ == "__main__":
    main()
