using 'main.bicep'

param prefix = 'edp-cdc'
param adminUsername = 'azureuser'
param adminPassword = readEnvironmentVariable('ADMIN_PASSWORD', '')
param adminSshPublicKey = ''
param adminCidr = '0.0.0.0/0'
param postgresAdminUsername = 'pgadmin'
param postgresAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD', '')
param postgresSkuName = 'Standard_D2ds_v4'
param postgresSkuTier = 'GeneralPurpose'
param postgresStorageGb = 128
param postgresVersion = '16'
param vmSize = 'Standard_D4s_v5'
param vmCount = 1
param githubRepoUrl = 'https://github.com/diaa/event-driven-with-PostgreSQL.git'
