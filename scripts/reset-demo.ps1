$ErrorActionPreference = "Stop"

Write-Host "Resetting benchmark table ..."
docker exec -i edp-postgres psql -U postgres -d appdb -c "TRUNCATE TABLE benchmark_events;"

Write-Host "Dropping demo slots if they exist ..."
docker exec -i edp-postgres psql -U postgres -d appdb -c "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name IN ('wal2json_slot','debezium_slot','drasi_slot');"

Write-Host "Reset complete."
