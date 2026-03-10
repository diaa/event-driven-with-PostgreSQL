# Debezium + Kafka Consumer

Reads Debezium-emitted records from Kafka and stores benchmark observations in `benchmark_events`.

## Run

```bash
pip install -r requirements.txt
python consumer.py
```

## Prerequisite

Register Debezium connector first:

```bash
# run from repository root
./scripts/setup-debezium.sh
```

PowerShell fallback: `./scripts/setup-debezium.ps1`

## Environment Variables

- `KAFKA_BOOTSTRAP` default `localhost:9092`
- `KAFKA_TOPIC` default `dbserver1.public.orders`
- `KAFKA_GROUP` default `benchmark-debezium-consumer`
- `PG_HOST` default `localhost`
- `PG_PORT` default `5432`
- `PG_USER` default `postgres`
- `PG_PASSWORD` default `postgres`
- `PG_DB` default `appdb`
