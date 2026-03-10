# wal2json + Custom Consumer

This consumer uses PostgreSQL logical replication directly with the `wal2json` output plugin.

## Run

```bash
pip install -r requirements.txt
python consumer.py
```

## Environment Variables

- `PG_HOST` default `localhost`
- `PG_PORT` default `5432`
- `PG_USER` default `postgres`
- `PG_PASSWORD` default `postgres`
- `PG_DB` default `appdb`
- `SLOT_NAME` default `wal2json_slot`
- `PUBLICATION` default `app_cdc_pub`
- `BATCH_SIZE` default `100`

## Notes

- Consumer writes per-event metrics into `benchmark_events`.
- For demo resets, drop slot manually:

```sql
SELECT pg_drop_replication_slot('wal2json_slot');
```
