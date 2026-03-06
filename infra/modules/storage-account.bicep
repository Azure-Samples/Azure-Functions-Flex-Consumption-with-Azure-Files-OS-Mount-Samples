// ---------------------------------------------------------------------------
// Module: storage-account.bicep
// Deploys a Storage Account with one or more Azure Files shares.
//
// The storage account serves double duty:
//   1. AzureWebJobsStorage for the Functions runtime.
//   2. Hosting the Azure Files shares that are OS-mounted into the app.
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

@description('List of file share names to create under this storage account.')
param fileShareNames array = []

@description('Quota (in GB) for each file share.')
param shareQuotaGB int = 5

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
  }
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

@description('Primary connection string (includes account key).')
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Primary account key.')
output accountKey string = storageAccount.listKeys().keys[0].value
