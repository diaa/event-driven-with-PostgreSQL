# CDC Benchmark Runbook

This runbook defines a repeatable, fair comparison across:

1. `wal2json` + custom consumer
2. Debezium + Kafka
3. Drasi + PostgreSQL

## Scenario

Primary entity: `orders`.

Event model:

- `INSERT` new order
- `UPDATE` order status (`NEW -> PAID -> SHIPPED` and occasional `CANCELLED`)

Keep one-table scope for baseline fairness. Add `customers` only as an advanced follow-up scenario.

## Fairness Rules

- Run approaches **step-by-step**, not in parallel.
- Use the **same load profile** for each approach.
- Keep infra constant (same VM size, DB SKU, config).
- Reset benchmark table and replication slots between runs.
- Use the same measurement window for each run.

## Load Matrix

Recommended progression:

| Stage | Total Events Target | Locust Users | Spawn Rate | Duration | Insert/Update Mix |
|---|---:|---:|---:|---:|---|
| Warm-up | 2,000 | 10 | 2/s | 2 min | 70/30 |
| Baseline | 10,000 | 50 | 10/s | 5 min | 70/30 |
| Stress | 50,000 | 120 | 20/s | 8 min | 70/30 |
| Max (optional) | 100,000+ | 200 | 25/s | 10 min | 70/30 |

Stop escalation if replication lag or WAL retention grows uncontrollably.

## Per-Approach Execution Steps

Run this sequence for each approach in order: `wal2json`, `debezium`, `drasi`.

1. Reset from repository root:

```bash
./scripts/reset-demo.sh
```

2. Start base services:

```bash
docker compose up -d --build
```

3. Start approach-specific components:

- wal2json:

```bash
docker compose --profile consumers up -d wal2json-consumer
```

- debezium:

```bash
./scripts/setup-debezium.sh
docker compose --profile consumers up -d debezium-consumer
```

- drasi:

```bash
docker compose --profile drasi up -d drasi-sink
# wire Drasi source/query to the sink endpoint: http://<host>:8090/events
```

4. Run Locust profile (example baseline):

```bash
cd traffic-generator/locust
locust -f locustfile.py
```

In Locust UI (`http://localhost:8089`), set:

- Users: `50`
- Spawn rate: `10`
- Run time: `5m`

5. Capture metrics during run:

- Benchmark dashboard: `http://localhost:8501`
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`

6. Record run metadata (suggested fields):

- Approach
- Stage (warm-up/baseline/stress/max)
- Start/end time
- Users/spawn rate/duration
- Total events observed
- Median/P95 latency
- Throughput
- Max slot lag / retained WAL
- Notes (errors, retries, anomalies)

Optional: store these fields in `benchmark_runs` and attach `run_id` in `benchmark_events` for post-talk analysis.

## Talk Narrative Guidance

- Start with baseline (`10,000`) for all three approaches.
- Show latency and throughput charts side-by-side.
- Call out Postgres overhead and slot behavior from Grafana.
- Move to stress (`50,000`) only if baseline is clean.
- Use max test (`100,000+`) only if time allows and system remains stable.

## Success Criteria

- All three approaches process the same workload profile.
- Metrics are captured for each run with identical conditions.
- WAL safety checks remain healthy after each run.
