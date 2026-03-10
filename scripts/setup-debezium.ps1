$ErrorActionPreference = "Stop"

$connectorConfig = @{
  name = "orders-connector"
  config = @{
    "connector.class" = "io.debezium.connector.postgresql.PostgresConnector"
    "database.hostname" = "postgres"
    "database.port" = "5432"
    "database.user" = "postgres"
    "database.password" = "postgres"
    "database.dbname" = "appdb"
    "database.server.name" = "dbserver1"
    "plugin.name" = "pgoutput"
    "slot.name" = "debezium_slot"
    "publication.name" = "app_cdc_pub"
    "table.include.list" = "public.orders"
    "tombstones.on.delete" = "false"
    "snapshot.mode" = "never"
    "topic.prefix" = "dbserver1"
  }
}

$body = $connectorConfig | ConvertTo-Json -Depth 5

Write-Host "Upserting Debezium connector on localhost:8083 ..."
Invoke-RestMethod -Method Put -Uri "http://localhost:8083/connectors/orders-connector/config" -ContentType "application/json" -Body ($connectorConfig.config | ConvertTo-Json -Depth 5) | Out-Null
Write-Host "Connector upserted."
