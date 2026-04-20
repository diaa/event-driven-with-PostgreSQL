# Bicep Deployment

Single-file Azure deployment: Rocky Linux 9 Docker host + PostgreSQL Flexible Server (GP tier, public access with firewall rules).

## Prerequisites

- Azure CLI with Bicep: `az bicep version`
- A resource group: `az group create --name edp-cdc-rg --location uksouth`
- Accept the Rocky Linux marketplace terms (one-time):

```bash
az vm image terms accept --publisher resf --offer rockylinux-x86_64 --plan 9-base
```

## Deploy

### From PowerShell (Windows)

```powershell
$env:ADMIN_PASSWORD = 'YourVmPass123!'
$env:PG_ADMIN_PASSWORD = 'YourPgPass123!'
$myIp = (Invoke-RestMethod -Uri 'https://ifconfig.me/ip').Trim()

cd infra/bicep
az deployment group create `
  --resource-group edp-cdc-rg `
  --template-file main.bicep `
  --parameters main.bicepparam `
  --parameters adminCidr="$myIp/32"
```

### From Bash (Linux/macOS)

```bash
export ADMIN_PASSWORD='YourVmPass123!'
export PG_ADMIN_PASSWORD='YourPgPass123!'
MY_IP=$(curl -s https://ifconfig.me)

cd infra/bicep
az deployment group create \
  --resource-group edp-cdc-rg \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters adminCidr="$MY_IP/32"
```

## Post-Deploy: Get Outputs

```bash
az deployment group show \
  --resource-group edp-cdc-rg \
  --name main \
  --query properties.outputs
```

Note the `vmPublicIps` and `postgresqlFqdn` values.

## VM Setup (Run Once After First Login)

SSH to the VM:

```bash
ssh azureuser@<vmPublicIp>
```

### 1. Install latest PostgreSQL client

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf install -y postgresql16
echo 'export PATH=/usr/pgsql-16/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
psql --version
```

### 2. Create credentials file

```bash
cat > ~/.pg_azure <<'EOF'
# App variables (Docker Compose + scripts)
export PG_HOST=<postgresqlFqdn from outputs>
export PG_PORT=5432
export PG_USER=pgadmin
export PG_PASSWORD='<your PG password>'
export PG_DB=appdb
export PG_SSLMODE=require
export DATABASE_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=${PG_SSLMODE}"

# Native psql variables (so you can just type "psql")
export PGHOST=$PG_HOST
export PGPORT=$PG_PORT
export PGUSER=$PG_USER
export PGPASSWORD=$PG_PASSWORD
export PGDATABASE=$PG_DB
export PGSSLMODE=$PG_SSLMODE
EOF
chmod 600 ~/.pg_azure
echo 'source ~/.pg_azure' >> ~/.bashrc
```

### 3. Test database connectivity

```bash
source ~/.pg_azure
psql -c "SELECT version();"
```

### 4. Clone the repo (if cloud-init didn't)

```bash
git clone https://github.com/diaa/event-driven-with-PostgreSQL.git ~/edp-cdc
```

### 5. Generate Docker Compose .env

```bash
source ~/.pg_azure
cat > ~/edp-cdc/.env <<EOF
PG_HOST=${PG_HOST}
PG_PORT=${PG_PORT}
PG_USER=${PG_USER}
PG_PASSWORD=${PG_PASSWORD}
PG_DB=${PG_DB}
PG_SSLMODE=${PG_SSLMODE}
DATABASE_URL=${DATABASE_URL}
EOF
chmod 600 ~/edp-cdc/.env
```

### 6. Build and start services

```bash
cd ~/edp-cdc
docker compose -f docker-compose.yml -f docker-compose.external-db.yml up -d --build
```

### 7. Initialize database schema

```bash
cd ~/edp-cdc
source ~/.pg_azure
bash scripts/init-demo-db.sh
```

### 8. Register Debezium connector

```bash
cd ~/edp-cdc
source ~/.pg_azure
DB_HOST=$PG_HOST DB_USER=$PG_USER DB_PASSWORD=$PG_PASSWORD DB_SSLMODE=require bash scripts/setup-debezium.sh
```

### 9. Pre-flight check

```bash
cd ~/edp-cdc
source ~/.pg_azure
bash scripts/demo-precheck.sh
```

## Returning to an Existing VM

```bash
ssh azureuser@<vmPublicIp>
# ~/.pg_azure is auto-sourced via .bashrc
cd ~/edp-cdc
docker compose -f docker-compose.yml -f docker-compose.external-db.yml ps
```

If containers are stopped:

```bash
docker compose -f docker-compose.yml -f docker-compose.external-db.yml up -d
```

## Running the Demo

```bash
cd ~/edp-cdc
source ~/.pg_azure
bash scripts/demo-scenario-wal2json.sh    # Scenario 1
bash scripts/demo-scenario-debezium.sh    # Scenario 2
bash scripts/demo-scenario-drasi.sh       # Scenario 3
bash scripts/demo-results.sh              # Comparison
```

Access dashboards from your laptop at `http://<vmPublicIp>:<port>`:

| Port | Service |
|------|---------|
| 3000 | Grafana (admin/admin) |
| 5050 | pgAdmin |
| 8081 | Kafka UI |
| 8083 | Kafka Connect API |
| 8089 | Locust load generator |
| 8501 | Streamlit benchmark dashboard |
| 9090 | Prometheus |

## Update NSG Rules (IP Changed)

### PowerShell

```powershell
$myIp = (Invoke-RestMethod -Uri 'https://ifconfig.me/ip').Trim()

az network nsg rule create `
  --resource-group edp-cdc-rg --nsg-name edp-cdc-app-nsg `
  --name allow-ssh --priority 100 --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes "$myIp/32" --destination-port-ranges 22

az network nsg rule create `
  --resource-group edp-cdc-rg --nsg-name edp-cdc-app-nsg `
  --name allow-demo-ports --priority 110 --direction Inbound --access Allow --protocol Tcp `
  --source-address-prefixes "$myIp/32" --destination-port-ranges 3000 5050 8081 8083 8089 8090 8501 9090

az postgres flexible-server firewall-rule create `
  --resource-group edp-cdc-rg --name edpcdcpgfs `
  --rule-name allow-my-ip --start-ip-address $myIp --end-ip-address $myIp
```

### Bash

```bash
MY_IP=$(curl -s https://ifconfig.me)

az network nsg rule create \
  --resource-group edp-cdc-rg --nsg-name edp-cdc-app-nsg \
  --name allow-ssh --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$MY_IP/32" --destination-port-ranges 22

az network nsg rule create \
  --resource-group edp-cdc-rg --nsg-name edp-cdc-app-nsg \
  --name allow-demo-ports --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$MY_IP/32" --destination-port-ranges 3000 5050 8081 8083 8089 8090 8501 9090

az postgres flexible-server firewall-rule create \
  --resource-group edp-cdc-rg --name edpcdcpgfs \
  --rule-name allow-my-ip --start-ip-address "$MY_IP" --end-ip-address "$MY_IP"
```

## What Gets Deployed

| Resource | Details |
|----------|---------|
| VNet | `10.50.0.0/16` with app subnet |
| NSG | SSH + demo ports from `adminCidr` |
| PostgreSQL Flexible Server | Standard_D2ds_v4 GP, PG 16, public access, logical replication, wal2json |
| PG Firewall | Admin IP + VM public IPs |
| VM(s) | Rocky Linux 9, Standard_D4s_v5, 128 GB Premium SSD |

## Teardown

```bash
az group delete --name edp-cdc-rg --yes --no-wait
```

## Differences from Terraform Stack

| | Terraform | Bicep |
|---|---|---|
| VM OS | Ubuntu 22.04 | Rocky Linux 9 |
| PG SKU | B_Standard_B1ms | Standard_D2ds_v4 (GP) |
| PG Network | Private DNS + VNet delegation | Public access + firewall rules |
| wal2json | Not preconfigured | `shared_preload_libraries=wal2json` |
| Key Vault | Included | Not included (use `--query` on outputs) |
| Structure | Multi-file modules | Single file |
