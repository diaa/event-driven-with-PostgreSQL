# Terraform Environment Setup

This Terraform stack provisions Azure infrastructure for the CDC demo. After `terraform apply`, VMs are fully bootstrapped and demo-ready.

## Targets

- `local`: no cloud resources (use Docker Compose directly)
- `azure`: self-contained Linux VM(s) + Azure PostgreSQL Flexible Server (private networking)

## Usage

```bash
terraform init
terraform plan -var-file=environments/local/dev.tfvars
terraform apply -var-file=environments/local/dev.tfvars
```

## Azure Self-Contained Deployment (VM + PostgreSQL)

This is the recommended path for your session when you want a self-contained Azure environment running all demo services.

### What Terraform deploys on Azure

- Resource group
- Virtual network with two subnets:
	- App subnet for Linux VM(s)
	- Delegated DB subnet for PostgreSQL Flexible Server
- Private DNS zone and VNet link for PostgreSQL private endpoint resolution
- PostgreSQL Flexible Server configured for logical replication:
	- `wal_level=logical`
	- `max_replication_slots=10`
	- `max_wal_senders=10`
	- `max_slot_wal_keep_size=2048`
- `appdb` database
- Linux VM(s) with cloud-init bootstrap that automatically:
	- Installs Docker Engine + Docker Compose plugin + psql client
	- Clones the GitHub repo
	- Writes `.env` with Azure PG connection details
	- Runs `docker compose up -d --build`
	- Initializes DB schema on Azure Flexible Server (`init-demo-db.sh`)
	- Registers the Debezium connector (`setup-debezium.sh`)
- NSG allowing:
	- SSH `22` from `azure_admin_cidr`
	- Demo ports from `azure_admin_cidr`: `3000, 5050, 8081, 8083, 8089, 8090, 8501, 9090`
- Azure Key Vault with RBAC and purge protection enabled
- Optional VNet peering to a pre-existing remote VNet

### Resource Inventory (Professional Baseline)

- Resource Group:
	- `azurerm_resource_group`
- Networking:
	- `azurerm_virtual_network`
	- `azurerm_subnet` (app)
	- `azurerm_subnet` (db delegated for PostgreSQL Flexible Server)
	- `azurerm_private_dns_zone`
	- `azurerm_private_dns_zone_virtual_network_link`
	- `azurerm_virtual_network_peering` (optional)
- Security:
	- `azurerm_network_security_group` (app subnet)
	- `azurerm_network_security_group` (db subnet)
	- `azurerm_subnet_network_security_group_association` (app)
	- `azurerm_subnet_network_security_group_association` (db)
- Compute:
	- `azurerm_public_ip` x `azure_vm_instance_count`
	- `azurerm_network_interface` x `azure_vm_instance_count`
	- `azurerm_linux_virtual_machine` x `azure_vm_instance_count`
- Database:
	- `azurerm_postgresql_flexible_server`
	- `azurerm_postgresql_flexible_server_database` (`appdb`)
	- `azurerm_postgresql_flexible_server_configuration` for logical replication settings
- Secrets Management:
	- `azurerm_key_vault`
	- `azurerm_key_vault_secret` (`postgres-admin-username`)
	- `azurerm_key_vault_secret` (`postgres-admin-password`)
	- `azurerm_key_vault_secret` (`postgres-connection-string`)

### Required inputs

Use `environments/azure/demo.tfvars.example` as template and provide:

- `deployment_target = "azure"`
- `azure_vm_admin_password` (min 12 chars, must include upper + lower + digit + special)
- `postgres_admin_password` (strong password)

Optional but recommended:

- `azure_vm_admin_ssh_public_key` (for key-based login in addition to password)
- Restrict `azure_admin_cidr` to your public IP/CIDR
- `github_repo_url` (if you forked this repo)
- Tune VM and PostgreSQL size based on load

Default in this repo:

- `azure_vm_instance_count = 2`

### Apply sequence

```bash
cd infra/terraform
cp environments/azure/demo.tfvars.example environments/azure/demo.tfvars
# edit environments/azure/demo.tfvars

terraform init
terraform plan -var-file=environments/azure/demo.tfvars
terraform apply -var-file=environments/azure/demo.tfvars
```

### Post-apply outputs you will use

- `azure_vm_public_ips`
- `azure_vm_ssh_commands`
- `azure_postgres_fqdn`
- `azure_postgres_database`

### VM Topology Guidance

- Use `azure_vm_instance_count = 2` (default) for talk-ready isolation.
	- Suggested split:
		- VM1: Kafka + Debezium Connect + consumers + Drasi sink
		- VM2: Grafana + Prometheus + dashboard + Locust
- Use `azure_vm_instance_count = 1` only when minimizing cost is the top priority.
- Use `azure_vm_instance_count = 3` only for higher sustained load or multi-hour benchmark runs.

### Cost and sizing guidance

- VM baseline: `Standard_D4s_v5` for one-box demo reliability.
- PostgreSQL baseline: `B_Standard_B1ms`, 32 GB storage for low-cost demos.
- If lag appears under high load:
	- Increase VM size first (`Standard_D8s_v5`)
	- Then increase PostgreSQL SKU (`D2s_v3` or higher)

### Security notes

- Avoid `0.0.0.0/0` for `azure_admin_cidr` in production-like environments.
- PostgreSQL is private to the VNet in this design.
- Keep credentials in secure variable stores or CI secret managers.

## Notes

- After `terraform apply`, VMs automatically clone the repo, build containers, init the DB, and register Debezium. SSH in and check `/var/log/edp-bootstrap.done` to confirm completion.
- Keep tfvars with secrets out of source control.

### External DB Mode (Compose Override)

When Terraform provisions Azure infrastructure, the VM bootstrap uses `docker-compose.external-db.yml` to disable the embedded PostgreSQL container and connect all services to Azure Flexible Server. The `.env` written by cloud-init includes `PG_SSLMODE=require`.

Manual equivalent for local testing with an external database:

```bash
# Create .env with your external DB coordinates
cat > .env <<EOF
PG_HOST=your-server.postgres.database.azure.com
PG_PORT=5432
PG_USER=pgadmin
PG_PASSWORD=YourPassword
PG_DB=appdb
PG_SSLMODE=require
DATABASE_URL=postgresql://pgadmin:YourPassword@your-server.postgres.database.azure.com:5432/appdb?sslmode=require
EOF

# Start with external-db override
docker compose -f docker-compose.yml -f docker-compose.external-db.yml up -d --build
docker compose -f docker-compose.yml -f docker-compose.external-db.yml --profile consumers up -d
```

### Bicep Alternative

See `infra/bicep/` for a single-file Bicep deployment with Rocky Linux 9, GP-tier PostgreSQL, and `wal2json` pre-configured in `shared_preload_libraries`.
