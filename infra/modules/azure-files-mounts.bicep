// ---------------------------------------------------------------------------
// Module: azure-files-mounts.bicep  (plural — deploys ALL mounts at once)
//
// Configures multiple OS-level Azure Files mounts on an existing function app
// in a single deployment.  This avoids the overwrite bug where sequential
// deployments of azure-files-mount.bicep (singular) replace the entire
// ``azureStorageAccounts`` dictionary, leaving only the last mount alive.
//
// Usage: pass an array of mount configurations.  Each element needs:
//   - name:         identifier for the mount (also used as the dict key)
//   - shareName:    Azure Files share to mount
//   - accountName:  storage account hosting the share
//   - accountKey:   storage account key
//   - mountPath:    local path (must start with /mounts/)
//
// IMPORTANT: Deploy *after* the function app and storage account exist.
// ---------------------------------------------------------------------------

@description('Name of the existing function app to configure.')
param functionAppName string

@description('Array of mount configurations. Each object must have: name, shareName, accountName, accountKey, mountPath.')
param mounts array

// ---------------------------------------------------------------------------
// Reference the existing function app
// ---------------------------------------------------------------------------
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

// ---------------------------------------------------------------------------
// Build a single azureStorageAccounts dictionary from the array and deploy
// it in one shot so every mount coexists.
// ---------------------------------------------------------------------------
resource mountConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'azurestorageaccounts'
  properties: reduce(mounts, {}, (cur, mount) => union(cur, {
    '${mount.name}': {
      type: 'AzureFiles'
      shareName: mount.shareName
      mountPath: mount.mountPath
      accountName: mount.accountName
      accessKey: mount.accountKey
    }
  }))
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Mount paths configured on the function app.')
output mountPaths array = [for mount in mounts: mount.mountPath]
