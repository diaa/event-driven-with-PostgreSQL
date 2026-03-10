# Event-Driven Architecture With PostgreSQL (CDC Showdown)

Repository scaffold for a talk comparing three change-data-capture (CDC) approaches:

1. `wal2json` + custom consumer
2. Debezium + Kafka
3. Drasi + PostgreSQL

The repo includes:

- A local Docker environment for PostgreSQL, Kafka, Debezium, monitoring, and demo apps
- A benchmark dashboard interface for comparing latency and overhead
- Terraform templates to provision Azure cloud infrastructure
- A Locust-based traffic generator for repeatable load testing

## Architecture Diagram

- See `docs/architecture-and-scenarios.md` for architecture and demo scenario diagrams.

## Benchmark Runbook

- See `benchmarks/RUNBOOK.md` for the exact load matrix and step-by-step comparison flow.

## 25-Minute Demo Plan

- See `docs/DEMO-25MIN.md` for the minute-by-minute live demo script.

## High-Level Structure

- `cdc/wal2json-consumer` custom logical replication consumer
- `cdc/debezium-kafka` Kafka consumer for Debezium-emitted events
- `cdc/drasi` Drasi continuous-query definitions and run scripts
- `apps/benchmark-dashboard` Streamlit dashboard for benchmark results
- `traffic-generator/locust` synthetic workload generator
- `infra/terraform` cloud provisioning templates
- `db/init` schema and publication setup scripts
- `db/README.md` database model and initialization order
- `monitoring` Prometheus and Grafana provisioning
- `benchmarks/results` output artifacts (latency, throughput, overhead)

## Quick Start (Local)

### 1) Prerequisites

- Linux shell (`bash`) environment
- Docker Engine + Docker Compose plugin
- Python 3.11+
- `psql` client (optional but useful)

### 2) Start Services

```bash
docker compose up -d --build
```
Start optional profile services when needed:

```bash
docker compose --profile consumers up -d --build
docker compose --profile drasi up -d --build
```


This starts PostgreSQL, Kafka, Debezium Connect, Grafana, Prometheus, and supporting tools.

### 3) Prepare Connectors/Publications

```bash
chmod +x ./scripts/setup-debezium.sh ./scripts/reset-demo.sh
./scripts/setup-debezium.sh
```

To initialize schema manually against any PostgreSQL endpoint:

```bash
chmod +x ./scripts/init-demo-db.sh ./scripts/check-cdc-readiness.sh
export DATABASE_URL='postgresql://<user>:<password>@<host>:5432/appdb?sslmode=require'
./scripts/init-demo-db.sh
./scripts/check-cdc-readiness.sh
```

### 4) Run Traffic Generator

```bash
cd traffic-generator/locust
pip install -r requirements.txt
locust -f locustfile.py
```

If no app API is used, run in database-direct mode with env vars (see `traffic-generator/locust/README.md`).

### 5) Run Consumers

- wal2json path:

```bash
cd cdc/wal2json-consumer
pip install -r requirements.txt
python consumer.py
```

- Debezium path:

```bash
cd cdc/debezium-kafka
pip install -r requirements.txt
python consumer.py
```

- Drasi path:

See `cdc/drasi/README.md` for deployment options and query registration.

### 6) Open Dashboards

- Benchmark UI: `http://localhost:8501`
- Grafana: `http://localhost:3000` (admin/admin)
- Prometheus: `http://localhost:9090`
- Kafka UI: `http://localhost:8081`

## What To Measure During Talk

- End-to-end event latency (insert/update -> consumer observation)
- Throughput (events/second)
- PostgreSQL CPU and network throughput
- Replication lag and WAL retention behavior
- Lines of code per approach (approximate implementation complexity)

## WAL Safety Checklist

- Use one replication slot per logical consumer path
- Monitor slot lag with `pg_replication_slots`
- Drop inactive slots after demos
- Set `max_slot_wal_keep_size` to cap WAL accumulation risk

See `scripts/wal-safety.sql` for ready-to-run checks.
See `db/README.md` for schema details and init order.

## Terraform

`infra/terraform` contains Azure-specific modules:

- `environments/local` for local variable conventions
- `modules/azure_stack` PostgreSQL Flexible Server + Linux VM(s) + Key Vault + observability base

Start with:

```bash
cd infra/terraform
terraform init
terraform plan -var-file=environments/azure/demo.tfvars
```

For full Azure VM + PostgreSQL details, see `infra/terraform/README.md`.

## Status

This scaffold is intentionally practical and demo-oriented. Individual module/image versions may need adjustment for your exact talk environment and Azure account constraints.
