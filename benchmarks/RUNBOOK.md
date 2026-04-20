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

## Parallel Execution (For Pre-Recorded Demos)

When recording a demo rather than presenting live, all three approaches can run
simultaneously. This is safe because each approach uses a **separate replication
slot** (`wal2json_slot`, `debezium_slot`, `drasi_slot`) — the same WAL change is
independently delivered to each consumer.

### Single-Machine Parallel Run

```bash
# 1. Start everything
docker compose up -d --build
docker compose --profile consumers --profile drasi up -d --build
./scripts/setup-debezium.sh

# 2. Single Locust run feeds all three consumers at once
cd traffic-generator/locust
locust -f locustfile.py
# In UI (http://localhost:8089): 50 users, 10/s spawn, 5m run time

# 3. After the run, compare in dashboard (http://localhost:8501)
```

### Azure Multi-VM Parallel Run

Use `infra/terraform` with `azure_vm_instance_count = 3`. Each VM runs one
approach against a shared Azure PostgreSQL Flexible Server.

```bash
cd infra/terraform
terraform init
terraform plan -var-file=environments/azure/demo.tfvars
terraform apply -var-file=environments/azure/demo.tfvars
```

Each VM auto-bootstraps via cloud-init (Docker install → repo clone → docker
compose up). Configure each VM to start only its consumer profile.

### Time Comparison

| Mode | Baseline (5 min load) | Full Matrix (all stages) |
|---|---|---|
| Sequential (step-by-step) | ~30 min | ~2 hours |
| Parallel (single machine) | ~10 min | ~35 min |
| Parallel (3 Azure VMs) | ~10 min | ~35 min |

### Fairness Note

Parallel runs on one machine share CPU/network. For strict benchmarking, prefer
sequential or multi-VM runs. For demo recording purposes, single-machine parallel
is sufficient — the relative differences remain visible.

## Drasi Live Query Demo

The key differentiator for Drasi: add or modify continuous queries **at runtime**
while data is flowing, with zero restarts or redeployments.

### Pre-Configured Queries

| Query ID | Filter | Purpose |
|---|---|---|
| `all-orders` | None | Benchmark parity with wal2json/debezium |
| `high-value-orders` | `amount ≥ 500 AND status IN [PAID, SHIPPED]` | Declarative filtering demo |

### Live Demo Script (Run While Locust Is Active)

```bash
# One-shot script that adds two new queries at runtime:
#   - cancelled-orders  → notify finance/refund system
#   - rush-orders       → priority fulfillment for hot meals (≥$200, PAID)
./scripts/drasi-demo-live-filter.sh
```

Or add individual queries manually:

```bash
# Cancelled order detection (retail: immediate refund trigger)
./scripts/drasi-add-query.sh cancelled-orders \
    "MATCH (o:orders) WHERE o.status = 'CANCELLED' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at"

# Rush / hot meal orders (retail: start kitchen prep immediately)
./scripts/drasi-add-query.sh rush-orders \
    "MATCH (o:orders) WHERE o.amount >= 200 AND o.status = 'PAID' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at"
```

### What To Show During Recording

1. Open Drasi server logs: `docker logs -f edp-drasi-server`
2. Run `./scripts/drasi-demo-live-filter.sh` in a split terminal
3. Point out: new query events appear in logs **immediately** — no restart
4. Query the benchmark database to show filtered events arriving:

```sql
SELECT source_event_id, operation, latency_ms, notes
FROM benchmark_events
WHERE notes LIKE 'drasi filtered%'
ORDER BY observed_at DESC
LIMIT 20;
```

### Why wal2json/Debezium Cannot Do This

- **wal2json**: Consumer code must be changed and redeployed. Filter logic
  lives in Python — no way to add it at runtime without restarting.
- **Debezium**: Connector config update + Kafka Connect restart. SMT-based
  filtering requires connector reconfiguration and a rolling restart.
- **Drasi**: POST a new query via API. The replication slot stays open.
  The new query evaluates against the live WAL stream within seconds.
