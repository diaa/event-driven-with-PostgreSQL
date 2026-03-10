# Locust Traffic Generator

Generates insert/update load directly against PostgreSQL so all CDC approaches receive identical source traffic.

## Run

```bash
pip install -r requirements.txt
locust -f locustfile.py
```

Open `http://localhost:8089`.

## Environment Variables

- `PG_HOST` default `localhost`
- `PG_PORT` default `5432`
- `PG_DB` default `appdb`
- `PG_USER` default `postgres`
- `PG_PASSWORD` default `postgres`

## Suggested Talk Profiles

- Warm-up: 10 users, spawn 2/s, 2 minutes
- Baseline: 50 users, spawn 10/s, 5 minutes
- Stress: 200 users, spawn 25/s, 5 minutes
