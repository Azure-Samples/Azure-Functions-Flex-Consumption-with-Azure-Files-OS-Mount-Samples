// ---------------------------------------------------------------------------
// Module: azure-files-mount.bicep
// Configures an OS-level Azure Files mount on an existing function app.
//
// Flex Consumption supports OS mounts via the site's
// ``azureStorageAccounts`` property.  Each entry maps a share to a local
// filesystem path like ``/mounts/<mount-name>``.
//
// IMPORTANT: This module should be deployed *after* the function app and
// storage account exist.  It uses the ``existing`` keyword to reference
// both resources and then patches the site config.
// ---------------------------------------------------------------------------

@description('Name of the existing function app to configure.')
param functionAppName string

@description('Name of the storage account that hosts the Azure Files share.')
param storageAccountName string

@description('Account key for the storage account.')
@secure()
param storageAccountKey string

@description('Name of the Azure Files share to mount.')
param shareName string

@description('Mount path inside the function app (e.g. "data" → /mounts/data).')
param mountName string

// ---------------------------------------------------------------------------
// Reference the existing function app
// ---------------------------------------------------------------------------
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

// ---------------------------------------------------------------------------
// Patch the site config with the Azure Files mount.
//
// The ``azureStorageAccounts`` property is a dictionary keyed by a
// user-chosen identifier.  The ``mountPath`` value becomes the local
// path under ``/mounts/``.
//
// NOTE: On Flex Consumption, the ``type`` MUST be ``AzureFiles`` and
// the ``mountPath`` must start with ``/mounts/``.
// ---------------------------------------------------------------------------
resource mountConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'azurestorageaccounts'
  properties: {
    '${mountName}': {
      type: 'AzureFiles'
      shareName: shareName
      mountPath: '/mounts/${mountName}'
      accountName: storageAccountName
      accessKey: storageAccountKey
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('The local filesystem path where the share is mounted.')
output mountPath string = '/mounts/${mountName}'
