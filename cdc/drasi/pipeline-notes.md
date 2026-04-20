# Pipeline Notes

Architecture overview for the Drasi CDC path.

## Data Flow

```
PostgreSQL (orders table)
  → WAL logical replication (publication: app_cdc_pub)
  → Drasi Server (source: orders-db, slot: drasi_slot)
  → Continuous Query evaluation (Cypher)
  → HTTP Reaction → drasi-sink webhook (POST /events)
  → benchmark_events table (approach='drasi')
```

## Components

1. **Drasi Server** (`ghcr.io/drasi-project/drasi-server:latest`)
   - Configured via `drasi-server-config.yaml`
   - Connects to PostgreSQL using the `postgres` source plugin
   - Creates replication slot `drasi_slot` automatically
   - Evaluates two Cypher continuous queries in real-time

2. **Sink Recorder** (`sink_recorder.py`)
   - FastAPI app receiving HTTP POST from Drasi's HTTP reaction
   - Parses `event_id`, `source_commit_ts`, `operation` from the body template
   - Computes `latency_ms` = observed_at − source_commit_ts
   - Writes to `benchmark_events` with `approach='drasi'`

## Operational Checks

- Drasi Server health: `curl http://localhost:8080/health`
- Query results: `curl http://localhost:8080/api/v1/queries/all-orders/results`
- Watch replication slot lag in Grafana or via `scripts/wal-safety.sql`
- Drasi Server logs: `docker logs -f edp-drasi-server`
