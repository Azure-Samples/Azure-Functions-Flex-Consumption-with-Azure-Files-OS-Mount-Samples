@description('Function app name')
param functionAppName string

@description('Storage account name')
param storageAccountName string

@secure()
@description('Storage account access key for Azure Files SMB mount (retrieved from Key Vault)')
param accessKey string

@description('Array of mount configurations')
param mounts array

// Function app reference
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

// Azure Files OS mount configuration
// Deploys azureStorageAccounts site config with all mounts in one shot
resource mountConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'azurestorageaccounts'
  properties: reduce(mounts, {}, (cur, mount) => union(cur, {
    '${mount.name}': {
      type: 'AzureFiles'
      shareName: mount.shareName
      mountPath: mount.mountPath
      accountName: storageAccountName
      accessKey: accessKey
    }
  }))
}

output mountPaths array = [for mount in mounts: mount.mountPath]
