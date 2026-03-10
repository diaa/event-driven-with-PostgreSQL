# Drasi + PostgreSQL

This directory contains starter assets for a Drasi-based CDC path where continuous queries filter change events before downstream action.

## Why Drasi in this repo

- Declarative query/filter layer on top of change streams
- Reduced custom code compared with hand-written consumers
- Useful when event routing and enrichment logic evolves frequently

## Contents

- `query.sql` sample continuous query intent
- `pipeline-notes.md` wiring notes for a local or cloud deployment

## Run (Suggested)

1. Deploy Drasi components (Kubernetes or your preferred runtime).
2. Configure PostgreSQL source against logical replication publication `app_cdc_pub`.
3. Register `query.sql` as the filter for high-value order events.
4. Emit results to a sink (webhook, queue, or topic).
5. Log sink observation timestamps into `benchmark_events` with `approach='drasi'`.

## Benchmarking Parity

To compare fairly with wal2json and Debezium:

- Use same source table (`orders`)
- Use same traffic profile (Locust)
- Use same latency formula (source commit timestamp -> observed timestamp)
