# Database Assets

This folder contains PostgreSQL schema and initialization assets for the CDC demo.

## Initialization Order

Files in `db/init` are intended to run in this order:

1. `01-schema.sql` core tables, constraints, triggers, indexes
2. `02-replication.sql` publications and CDC read role grants
3. `03-views.sql` benchmark summary views
4. `04-seed.sql` minimal demo seed data

## Baseline CDC Scope

- Baseline publication: `app_cdc_pub` (table `orders` only)
- Advanced publication: `app_cdc_pub_advanced` (`orders` + `customers`)

Use `orders` only for fair baseline comparisons across all approaches.

## Bash Helpers

From repo root:

```bash
chmod +x ./scripts/init-demo-db.sh ./scripts/check-cdc-readiness.sh
```

Apply schema to any PostgreSQL endpoint:

```bash
export DATABASE_URL='postgresql://<user>:<password>@<host>:5432/appdb?sslmode=require'
./scripts/init-demo-db.sh
```

Run readiness checks:

```bash
./scripts/check-cdc-readiness.sh
```
