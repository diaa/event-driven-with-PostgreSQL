// CDC Demo — Azure deployment (Rocky Linux 9 + PostgreSQL Flexible Server)
// Single-file alternative to the Terraform stack under infra/terraform/
// PostgreSQL uses public network access with firewall rules (proven pattern).

@description('Resource name prefix')
param prefix string = 'edp-cdc'

@description('Azure region')
param location string = resourceGroup().location

@description('VM admin username')
param adminUsername string = 'azureuser'

@secure()
@description('VM admin password')
param adminPassword string

@description('SSH public key (leave empty for password-only auth)')
param adminSshPublicKey string = ''

@description('CIDR allowed to reach public VM ports (use YOUR_IP/32)')
param adminCidr string = '0.0.0.0/0'

@description('PostgreSQL admin username')
param postgresAdminUsername string = 'pgadmin'

@secure()
@description('PostgreSQL admin password')
param postgresAdminPassword string

@description('PostgreSQL Flexible Server SKU')
param postgresSkuName string = 'Standard_D2ds_v4'

@description('PostgreSQL SKU tier')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param postgresSkuTier string = 'GeneralPurpose'

@description('PostgreSQL storage in GB')
param postgresStorageGb int = 128

@description('PostgreSQL major version')
param postgresVersion string = '16'

@description('Docker host VM size')
param vmSize string = 'Standard_D4s_v5'

@minValue(1)
@description('Number of Docker host VMs')
param vmCount int = 1

@description('GitHub repo HTTPS URL to clone on VMs')
param githubRepoUrl string

// ---------- Variables ----------

var nameSafe = toLower(replace(prefix, '-', ''))
var pgServerName = '${take(nameSafe, 14)}pgfs'
var vnetCidr = '10.50.0.0/16'
var appSubnetCidr = '10.50.1.0/24'
var demoPortRanges = [
  '3000'
  '5050'
  '8081'
  '8083'
  '8089'
  '8090'
  '8501'
  '9090'
]

// ---------- Networking (VM only — PG uses public access) ----------

resource appNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-app-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: adminCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'allow-demo-ports'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: adminCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: demoPortRanges
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [vnetCidr] }
    subnets: [
      {
        name: 'app-subnet'
        properties: {
          addressPrefix: appSubnetCidr
          networkSecurityGroup: { id: appNsg.id }
        }
      }
    ]
  }
}

// ---------- PostgreSQL Flexible Server (public access + firewall) ----------

resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: pgServerName
  location: location
  sku: {
    name: postgresSkuName
    tier: postgresSkuTier
  }
  properties: {
    version: postgresVersion
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    storage: {
      storageSizeGB: postgresStorageGb
      autoGrow: 'Enabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: { mode: 'Disabled' }
    maintenanceWindow: {
      customWindow: 'Enabled'
      dayOfWeek: 6
      startHour: 2
    }
  }
}

// Firewall: allow admin CIDR
var adminIp = replace(adminCidr, '/32', '')
resource fwAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pgServer
  name: 'allow-admin-ip'
  properties: {
    startIpAddress: adminIp
    endIpAddress: adminIp
  }
}

// Firewall: allow each VM public IP
resource fwVm 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = [
  for i in range(0, vmCount): {
    parent: pgServer
    name: 'allow-vm-${i + 1}'
    properties: {
      startIpAddress: publicIp[i].properties.ipAddress
      endIpAddress: publicIp[i].properties.ipAddress
    }
    dependsOn: [fwAdmin]
  }
]

resource appDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pgServer
  name: 'appdb'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Server configurations for logical replication + wal2json
var pgConfigs = {
  wal_level: 'logical'
  max_replication_slots: '10'
  max_wal_senders: '10'
  shared_preload_libraries: 'wal2json'
}

@batchSize(1)
resource pgConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = [
  for item in items(pgConfigs): {
    parent: pgServer
    name: item.key
    properties: { value: item.value, source: 'user-override' }
  }
]

// ---------- Cloud-init for Rocky Linux 9 ----------

var pgFqdn = pgServer.properties.fullyQualifiedDomainName

var cloudInit = '''
#cloud-config
package_update: true
packages:
  - dnf-plugins-core
  - git
  - jq
  - postgresql
runcmd:
  - dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  - dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  - systemctl enable --now docker
  - usermod -aG docker {0}
  - git clone {1} /opt/edp-cdc
  - chown -R {0}:{0} /opt/edp-cdc
  - |
    cat > /opt/edp-cdc/.env <<EOF
    PG_HOST={2}
    PG_PORT=5432
    PG_USER={3}
    PG_PASSWORD={4}
    PG_DB=appdb
    PG_SSLMODE=require
    DATABASE_URL=postgresql://{3}:{4}@{2}:5432/appdb?sslmode=require
    EOF
  - chmod 600 /opt/edp-cdc/.env
  - cd /opt/edp-cdc && docker compose -f docker-compose.yml -f docker-compose.external-db.yml up -d --build
  - sleep 15
  - cd /opt/edp-cdc && export DATABASE_URL="postgresql://{3}:{4}@{2}:5432/appdb?sslmode=require" && bash scripts/init-demo-db.sh
  - cd /opt/edp-cdc && DB_HOST={2} DB_USER={3} DB_PASSWORD={4} DB_SSLMODE=require bash scripts/setup-debezium.sh
  - echo "Bootstrap complete" > /var/log/edp-bootstrap.done
'''

var cloudInitRendered = format(
  cloudInit,
  adminUsername,
  githubRepoUrl,
  pgFqdn,
  postgresAdminUsername,
  postgresAdminPassword
)

// ---------- VM resources ----------

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = [
  for i in range(0, vmCount): {
    name: '${prefix}-vm-pip-${i + 1}'
    location: location
    sku: { name: 'Standard' }
    properties: { publicIPAllocationMethod: 'Static' }
  }
]

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = [
  for i in range(0, vmCount): {
    name: '${prefix}-vm-nic-${i + 1}'
    location: location
    properties: {
      ipConfigurations: [
        {
          name: 'primary'
          properties: {
            subnet: { id: vnet.properties.subnets[0].id }
            privateIPAllocationMethod: 'Dynamic'
            publicIPAddress: { id: publicIp[i].id }
          }
        }
      ]
    }
  }
]

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = [
  for i in range(0, vmCount): {
    name: '${prefix}-vm-${i + 1}'
    location: location
    properties: {
      hardwareProfile: { vmSize: vmSize }
      osProfile: {
        computerName: '${prefix}-vm-${i + 1}'
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: base64(cloudInitRendered)
        linuxConfiguration: {
          disablePasswordAuthentication: adminSshPublicKey != '' ? true : false
          ssh: adminSshPublicKey != ''
            ? {
                publicKeys: [
                  {
                    path: '/home/${adminUsername}/.ssh/authorized_keys'
                    keyData: adminSshPublicKey
                  }
                ]
              }
            : null
        }
      }
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          diskSizeGB: 128
          managedDisk: { storageAccountType: 'Premium_LRS' }
        }
        imageReference: {
          publisher: 'resf'
          offer: 'rockylinux-x86_64'
          sku: '9-base'
          version: 'latest'
        }
      }
      networkProfile: {
        networkInterfaces: [{ id: nic[i].id }]
      }
    }
    plan: {
      name: '9-base'
      publisher: 'resf'
      product: 'rockylinux-x86_64'
    }
  }
]

// ---------- Outputs ----------

output postgresqlFqdn string = pgServer.properties.fullyQualifiedDomainName
output vmPublicIps string[] = [for i in range(0, vmCount): publicIp[i].properties.ipAddress]
output sshCommands string[] = [
  for i in range(0, vmCount): 'ssh ${adminUsername}@${publicIp[i].properties.ipAddress}'
]
output psqlCommand string = 'psql "host=${pgServer.properties.fullyQualifiedDomainName} user=${postgresAdminUsername} dbname=appdb sslmode=require"'
