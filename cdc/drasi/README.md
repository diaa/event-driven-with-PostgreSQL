# Drasi + PostgreSQL

This directory contains assets for the Drasi-based CDC path, using [Drasi Server](https://drasi.io/drasi-server/) to run continuous queries over PostgreSQL logical replication and forward matching changes to the benchmark sink via HTTP webhook.

## How It Works

1. **Drasi Server** connects to PostgreSQL using logical replication (publication `app_cdc_pub`)
2. **Continuous queries** (Cypher) evaluate every change in real-time
3. An **HTTP reaction** forwards matched events to the `drasi-sink` webhook
4. The **sink recorder** writes latency observations to `benchmark_events`

## Contents

- `drasi-server-config.yaml` — Full Drasi Server configuration (source, queries, reactions)
- `sink_recorder.py` — FastAPI webhook that records benchmark events
- `query.sql` — Reference copy of the Cypher continuous queries
- `Dockerfile` — Container for the sink recorder
- `pipeline-notes.md` — Architecture notes

## Queries

Two continuous queries are defined in `drasi-server-config.yaml`:

| Query ID | Purpose | Filter |
|---|---|---|
| `all-orders` | Benchmark parity with wal2json/debezium | None (captures all changes) |
| `high-value-orders` | Demonstrates Drasi filtering | `amount >= 500 AND status IN ['PAID', 'SHIPPED']` |

## Run (Docker Compose)

```bash
docker compose --profile drasi up -d --build
```

This starts:
- `edp-drasi-server` — Drasi Server container (`ghcr.io/drasi-project/drasi-server:latest`)
- `edp-drasi-sink` — Benchmark sink webhook

Verify Drasi Server is running:

```bash
curl http://localhost:8080/health
```

View current query results:

```bash
curl http://localhost:8080/api/v1/queries/all-orders/results
curl http://localhost:8080/api/v1/queries/high-value-orders/results
```

View Drasi Server logs (shows filtered events via log reaction):

```bash
docker logs -f edp-drasi-server
```

## Benchmarking Parity

To compare fairly with wal2json and Debezium:

- The `all-orders` query captures the same source table (`orders`) with no filter
- Same traffic profile (Locust)
- Same latency formula (source commit timestamp → observed timestamp)
