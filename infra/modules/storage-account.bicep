// ---------------------------------------------------------------------------
// Module: storage-account.bicep
// Deploys a Storage Account for Azure Functions Flex Consumption.
//
// The storage account serves multiple purposes:
//   1. AzureWebJobsStorage for the Functions runtime (via managed identity).
//   2. Deployment storage — blob container for Flex Consumption app packages.
//   3. Hosting Azure Files shares that are OS-mounted into the app.
//
// Security: Shared key access is disabled. The function app authenticates
// via system-assigned managed identity using separate blob/queue/table URIs.
// NOTE: Azure Files mounts still require account keys (set via site config),
// so we allow key access for the file service only via the allowSharedKeyAccess
// parameter which defaults to true for backward compatibility with mounts.
// ---------------------------------------------------------------------------

@description('Name of the storage account (3-24 chars, lowercase alphanumeric).')
param storageAccountName string

@description('Azure region.')
param location string = resourceGroup().location

@description('SKU for the storage account.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param skuName string = 'Standard_LRS'

@description('Name of the blob container used for Flex Consumption deployment packages.')
param deploymentContainerName string

@description('List of file share names to create under this storage account.')
param fileShareNames array = []

@description('Quota (in GB) for each file share.')
param shareQuotaGB int = 5

@description('Allow shared key access. Required for Azure Files mounts that use account keys.')
param allowSharedKeyAccess bool = true

@description('Tags to apply.')
param tags object = {}

// ---------------------------------------------------------------------------
// Storage Account
// ---------------------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: skuName
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: allowSharedKeyAccess
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ---------------------------------------------------------------------------
// Blob Service + Deployment Container
//
// Flex Consumption deploys from a blob container rather than traditional
// zip deployment. The container is created here and referenced by the
// function app module via functionAppConfig.deployment.storage.
// ---------------------------------------------------------------------------
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
}

// ---------------------------------------------------------------------------
// Queue and Table Services (required by AzureWebJobsStorage)
// ---------------------------------------------------------------------------
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

// ---------------------------------------------------------------------------
// File Service + Shares
//
// Azure Files shares are children of the "default" file service.
// We create one share per name supplied by the caller.
// ---------------------------------------------------------------------------
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource fileShares 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = [
  for shareName in fileShareNames: {
    parent: fileService
    name: shareName
    properties: {
      shareQuota: shareQuotaGB
      accessTier: 'TransactionOptimized'
    }
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Resource ID of the storage account.')
output storageAccountId string = storageAccount.id

@description('Name of the storage account.')
output storageAccountName string = storageAccount.name

@description('Primary blob endpoint (e.g. https://<name>.blob.core.windows.net/).')
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Blob service URI for managed identity auth (AzureWebJobsStorage__blobServiceUri).')
output blobServiceUri string = 'https://${storageAccount.name}.blob.${environment().suffixes.storage}'

@description('Queue service URI for managed identity auth (AzureWebJobsStorage__queueServiceUri).')
output queueServiceUri string = 'https://${storageAccount.name}.queue.${environment().suffixes.storage}'

@description('Table service URI for managed identity auth (AzureWebJobsStorage__tableServiceUri).')
output tableServiceUri string = 'https://${storageAccount.name}.table.${environment().suffixes.storage}'

@description('Primary account key. Needed for Azure Files mount configuration.')
output accountKey string = storageAccount.listKeys().keys[0].value
