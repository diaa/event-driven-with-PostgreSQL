# Bicep Deployment

Single-file Azure deployment: Rocky Linux 9 Docker host + PostgreSQL Flexible Server (GP tier) with `wal2json` pre-configured.

## Prerequisites

- Azure CLI with Bicep: `az bicep version`
- A resource group: `az group create --name edp-cdc-rg --location eastus`
- Accept the Rocky Linux marketplace terms (one-time):

```bash
az vm image terms accept --publisher resf --offer rockylinux-x86_64 --plan 9-base
```

## Deploy

```bash
# Set passwords as environment variables (read by .bicepparam)
export ADMIN_PASSWORD='YourVmPassword123!'
export PG_ADMIN_PASSWORD='YourPgPassword123!'

cd infra/bicep
az deployment group create \
  --resource-group edp-cdc-rg \
  --template-file main.bicep \
  --parameters main.bicepparam
```

Or override parameters inline:

```bash
az deployment group create \
  --resource-group edp-cdc-rg \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters adminCidr='YOUR.PUBLIC.IP/32' vmCount=1
```

## Post-Deploy

1. Get outputs:
   ```bash
   az deployment group show \
     --resource-group edp-cdc-rg \
     --name main \
     --query properties.outputs
   ```

2. SSH to the VM:
   ```bash
   ssh azureuser@<vmPublicIp>
   ```

3. Verify bootstrap completed:
   ```bash
   cat /var/log/edp-bootstrap.done
   docker compose -f /opt/edp-cdc/docker-compose.yml \
     -f /opt/edp-cdc/docker-compose.external-db.yml ps
   ```

4. Run demo scenarios:
   ```bash
   cd /opt/edp-cdc
   ./scripts/demo-precheck.sh
   ./scripts/demo-scenario-wal2json.sh
   ./scripts/demo-scenario-debezium.sh
   ./scripts/demo-scenario-drasi.sh
   ./scripts/demo-results.sh
   ```

## What Gets Deployed

| Resource | Details |
|----------|---------|
| VNet | `10.50.0.0/16` with app + db subnets |
| NSGs | SSH + demo ports from `adminCidr`; PG from app-subnet only |
| Private DNS | `{prefix}.postgres.database.azure.com` |
| PostgreSQL Flexible Server | GP_Standard_D4ds_v5, PG 16, logical replication, wal2json |
| VM(s) | Rocky Linux 9, Standard_D4s_v5, 128 GB Premium SSD |

## Teardown

```bash
az group delete --name edp-cdc-rg --yes --no-wait
```

## Differences from Terraform Stack

| | Terraform | Bicep |
|---|---|---|
| VM OS | Ubuntu 22.04 | Rocky Linux 9 |
| PG SKU | B_Standard_B1ms | GP_Standard_D4ds_v5 |
| wal2json | Not preconfigured | `shared_preload_libraries=wal2json` |
| Key Vault | Included | Not included (use `--query` on outputs) |
| Structure | Multi-file modules | Single file |
