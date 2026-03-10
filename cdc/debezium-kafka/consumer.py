import json
import os
from datetime import datetime, timezone

import psycopg2
from confluent_kafka import Consumer
from dateutil import parser as dt_parser
from psycopg2.extras import execute_values

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "localhost:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "dbserver1.public.orders")
KAFKA_GROUP = os.getenv("KAFKA_GROUP", "benchmark-debezium-consumer")

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")

BATCH_SIZE = int(os.getenv("BATCH_SIZE", "100"))


def pg_dsn() -> str:
    return (
        f"host={PG_HOST} port={PG_PORT} dbname={PG_DB} "
        f"user={PG_USER} password={PG_PASSWORD}"
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
        "debezium kafka consumer",
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


def main() -> None:
    consumer = Consumer(
        {
            "bootstrap.servers": KAFKA_BOOTSTRAP,
            "group.id": KAFKA_GROUP,
            "auto.offset.reset": "earliest",
        }
    )
    consumer.subscribe([KAFKA_TOPIC])

    pg_conn = psycopg2.connect(pg_dsn())
    rows: list[tuple] = []

    print(f"Consuming Debezium topic: {KAFKA_TOPIC}")
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
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
                flush_rows(pg_conn, rows)
                print(f"Flushed {len(rows)} Debezium rows")
                rows.clear()
    except KeyboardInterrupt:
        print("Stopping Debezium consumer...")
    finally:
        flush_rows(pg_conn, rows)
        consumer.close()
        pg_conn.close()


if __name__ == "__main__":
    main()
