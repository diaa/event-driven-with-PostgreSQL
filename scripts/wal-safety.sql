-- Monitor slot lag and retention risk.
SELECT
  slot_name,
  plugin,
  slot_type,
  active,
  restart_lsn,
  confirmed_flush_lsn,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
ORDER BY slot_name;

-- Publication membership check.
SELECT pubname, schemaname, tablename
FROM pg_publication_tables
ORDER BY 1, 2, 3;

-- Current WAL sender overview.
SELECT pid, usename, application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;
