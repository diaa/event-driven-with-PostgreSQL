# Pipeline Notes

These notes are a checklist for wiring Drasi in the talk environment.

1. Source setup:
- PostgreSQL logical replication enabled (`wal_level=logical`)
- Publication exists (`app_cdc_pub`)
- Dedicated slot/user for Drasi source

2. Query registration:
- Register `query.sql` as continuous query
- Route matched events to a sink endpoint

3. Sink behavior:
- Sink handler writes observations to `benchmark_events`
- Required columns: `approach`, `source_event_id`, `source_commit_ts`, `observed_at`, `latency_ms`

4. Operational checks:
- Watch replication slot lag
- Verify sink throughput under load
- Capture CPU/network metrics in Grafana during benchmark window
