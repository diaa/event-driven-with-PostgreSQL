# Terraform Environment Setup

This Terraform stack provisions cloud infrastructure for the talk demo.

## Targets

- `local`: no cloud resources (use Docker Compose)
- `azure`: self-contained Linux VM(s) + PostgreSQL Flexible Server (private networking)
- `aws`: RDS PostgreSQL + EKS baseline

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
- Linux VM(s) with cloud-init bootstrap:
	- Docker Engine + Docker Compose plugin
	- Git, jq, unzip, Terraform CLI
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
- `azure_vm_admin_ssh_public_key` (your real SSH public key)
- `postgres_admin_password` (strong password)

Optional but recommended:

- Restrict `azure_admin_cidr` to your public IP/CIDR
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

- This module focuses on infrastructure. Deploy app containers on the VM(s) after `terraform apply`.
- Keep tfvars with secrets out of source control.
