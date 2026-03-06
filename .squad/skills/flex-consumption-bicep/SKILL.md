# Skill: Flex Consumption Bicep Pattern

## When to Use
When creating or reviewing Azure Functions Flex Consumption infrastructure in Bicep.

## Critical Requirements

A Flex Consumption function app **must** have `functionAppConfig` on the `Microsoft.Web/sites` resource. Without it, the app deploys as regular consumption.

### functionAppConfig structure
```bicep
functionAppConfig: {
  deployment: {
    storage: {
      type: 'blobContainer'
      value: '${storageBlobEndpoint}${deploymentContainerName}'
      authentication: {
        type: 'SystemAssignedIdentity'
      }
    }
  }
  scaleAndConcurrency: {
    maximumInstanceCount: 100
    instanceMemoryMB: 2048  // 512, 2048, or 4096
  }
  runtime: {
    name: 'python'      // NOT linuxFxVersion
    version: '3.11'
  }
}
```

### App Settings (managed identity, NOT connection strings)
```bicep
AzureWebJobsStorage__credential: 'managedidentity'
AzureWebJobsStorage__blobServiceUri: 'https://<name>.blob.core.windows.net'
AzureWebJobsStorage__queueServiceUri: 'https://<name>.queue.core.windows.net'
AzureWebJobsStorage__tableServiceUri: 'https://<name>.table.core.windows.net'
APPLICATIONINSIGHTS_CONNECTION_STRING: '<connection-string>'
APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'
```

### What NOT to Set
- `linuxFxVersion` — runtime is in `functionAppConfig.runtime`
- `FUNCTIONS_WORKER_RUNTIME` — runtime is in `functionAppConfig.runtime`
- `FUNCTIONS_EXTENSION_VERSION` — not applicable to Flex Consumption
- `AzureWebJobsFeatureFlags` — not needed
- `APPINSIGHTS_INSTRUMENTATIONKEY` — deprecated, use connection string
- `AzureWebJobsStorage` as a connection string — use managed identity URIs

### Storage Account Requirements
- Blob container for deployment packages (referenced by `functionAppConfig.deployment.storage`)
- Queue and table services must exist (used by AzureWebJobsStorage)
- `allowSharedKeyAccess` may need to be true if also using Azure Files mounts (which require account keys)

### Hosting Plan
```bicep
sku: { name: 'FC1', tier: 'FlexConsumption' }
kind: 'functionapp'
properties: { reserved: true }
```

### RBAC Roles Needed
The function app's system-assigned managed identity needs:
- Storage Blob Data Owner (for deployment packages + blob operations)
- Storage Queue Data Contributor (for AzureWebJobsStorage queue triggers)
- Storage Table Data Contributor (for AzureWebJobsStorage table operations)

## Reference
https://github.com/Azure-Samples/azure-functions-flex-consumption-samples
