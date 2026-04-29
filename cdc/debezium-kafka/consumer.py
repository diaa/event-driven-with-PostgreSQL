import json
import os
import threading
import time
from datetime import datetime, timezone
from queue import SimpleQueue

import psycopg2
from confluent_kafka import Consumer
from psycopg2.extras import execute_values

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "localhost:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "dbserver1.public.orders")
KAFKA_GROUP = os.getenv("KAFKA_GROUP", "benchmark-debezium-consumer")

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")
PG_SSLMODE = os.getenv("PG_SSLMODE", "disable")

RUN_LABEL = os.getenv("RUN_LABEL", "")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "500"))


def pg_dsn() -> str:
    return (
        f"host={PG_HOST} port={PG_PORT} dbname={PG_DB} "
        f"user={PG_USER} password={PG_PASSWORD} sslmode={PG_SSLMODE}"
    )


def parse_latency_ms(payload: dict) -> float | None:
    src = payload.get("source", {})
    ts_ms = src.get("ts_ms")
    if ts_ms is None:
        return None
    src_ts = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc)
    return (datetime.now(timezone.utc) - src_ts).total_seconds() * 1000.0


def benchmark_row(record_payload: dict, raw_value: bytes) -> tuple:
    op = record_payload.get("op")
    after = record_payload.get("after") or {}
    source = record_payload.get("source") or {}

    event_id = str(after.get("id") or record_payload.get("ts_ms") or "unknown")
    commit_ts = source.get("ts_ms")
    commit_dt = None
    if commit_ts is not None:
        commit_dt = datetime.fromtimestamp(commit_ts / 1000.0, tz=timezone.utc)

    return (
        "debezium",
        event_id,
        commit_dt,
        parse_latency_ms(record_payload),
        len(raw_value),
        op,
        f"debezium kafka consumer{' [' + RUN_LABEL + ']' if RUN_LABEL else ''}",
    )


def flush_rows(conn, rows: list[tuple]) -> None:
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


RETRY_DELAY = int(os.getenv("RETRY_DELAY", "3"))

_SENTINEL = None


def _writer_thread(write_queue: SimpleQueue, dsn_str: str) -> None:
    conn = psycopg2.connect(dsn_str)
    try:
        while True:
            batch = write_queue.get()
            if batch is _SENTINEL:
                break
            flush_rows(conn, batch)
            print(f"Flushed {len(batch)} Debezium rows")
    finally:
        conn.close()


def run_consumer() -> None:
    consumer = Consumer(
        {
            "bootstrap.servers": KAFKA_BOOTSTRAP,
            "group.id": KAFKA_GROUP,
            "auto.offset.reset": "earliest",
        }
    )
    consumer.subscribe([KAFKA_TOPIC])

    write_queue: SimpleQueue = SimpleQueue()
    writer = threading.Thread(
        target=_writer_thread, args=(write_queue, pg_dsn()), daemon=True
    )
    writer.start()

    rows: list[tuple] = []

    print(f"Consuming Debezium topic: {KAFKA_TOPIC}")
    try:
        while True:
            msg = consumer.poll(0.1)
            if msg is None:
                if rows:
                    write_queue.put(rows)
                    rows = []
                continue
            if msg.error():
                print(f"Kafka error: {msg.error()}")
                continue

            raw = msg.value()
            payload = json.loads(raw)
            if "payload" in payload:
                payload = payload["payload"]

            rows.append(benchmark_row(payload, raw))
            if len(rows) >= BATCH_SIZE:
                write_queue.put(rows)
                rows = []
    finally:
        if rows:
            write_queue.put(rows)
        write_queue.put(_SENTINEL)
        writer.join(timeout=10)
        try:
            consumer.close()
        except Exception:
            pass


def main() -> None:
    while True:
        try:
            run_consumer()
        except KeyboardInterrupt:
            print("Stopping Debezium consumer...")
            break
        except Exception as exc:
            print(f"Debezium consumer error: {exc}")
            print(f"Reconnecting in {RETRY_DELAY}s ...")
            time.sleep(RETRY_DELAY)


if __name__ == "__main__":
    main()
