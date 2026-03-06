// ---------------------------------------------------------------------------
// Module: function-app.bicep
// Deploys an Azure Functions Flex Consumption plan and function app.
//
// Flex Consumption is the serverless plan that supports OS-level mounts.
// This module configures the app using the ``functionAppConfig`` property
// which is REQUIRED for Flex Consumption:
//   - deployment.storage: blob container with managed identity auth
//   - scaleAndConcurrency: instance count and memory
//   - runtime: language name and version (replaces linuxFxVersion)
//
// Authentication uses system-assigned managed identity for both the
// deployment storage and AzureWebJobsStorage (blob/queue/table URIs).
//
// The OS mount configuration is handled by the companion
// azure-files-mount(s).bicep module after deployment.
// ---------------------------------------------------------------------------

@description('Name of the function app resource.')
param functionAppName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Application Insights connection string.')
param appInsightsConnectionString string = ''

@description('Primary blob endpoint of the storage account (e.g. https://<name>.blob.core.windows.net/).')
param storageBlobEndpoint string

@description('Name of the blob container for Flex Consumption deployment packages.')
param deploymentContainerName string

@description('Blob service URI for AzureWebJobsStorage managed identity auth.')
param storageBlobServiceUri string

@description('Queue service URI for AzureWebJobsStorage managed identity auth.')
param storageQueueServiceUri string

@description('Table service URI for AzureWebJobsStorage managed identity auth.')
param storageTableServiceUri string

@description('Functions runtime name.')
@allowed(['dotnet-isolated', 'python', 'java', 'node', 'powerShell'])
param functionAppRuntime string = 'python'

@description('Functions runtime version.')
param functionAppRuntimeVersion string = '3.11'

@description('Maximum instance count for scale out.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 100

@description('Memory allocated per instance in MB.')
@allowed([512, 2048, 4096])
param instanceMemoryMB int = 2048

@description('Additional app settings to merge into the function app configuration.')
param additionalAppSettings object = {}

@description('Tags to apply to all resources.')
param tags object = {}

// ---------------------------------------------------------------------------
// Flex Consumption hosting plan (SKU: FC1)
// ---------------------------------------------------------------------------
resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

// ---------------------------------------------------------------------------
// Function app — Flex Consumption with managed identity
// ---------------------------------------------------------------------------

// Base app settings using managed identity (no connection strings / keys).
var baseAppSettings = union({
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__blobServiceUri: storageBlobServiceUri
  AzureWebJobsStorage__queueServiceUri: storageQueueServiceUri
  AzureWebJobsStorage__tableServiceUri: storageTableServiceUri
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
  APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'
}, additionalAppSettings)

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
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
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: functionAppRuntime
        version: functionAppRuntimeVersion
      }
    }
    siteConfig: {
      appSettings: [for item in items(baseAppSettings): {
        name: item.key
        value: item.value
      }]
    }
    httpsOnly: true
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Resource ID of the function app.')
output functionAppId string = functionApp.id

@description('Name of the function app.')
output functionAppName string = functionApp.name

@description('Default hostname of the function app.')
output defaultHostName string = functionApp.properties.defaultHostName

@description('Resource ID of the hosting plan.')
output hostingPlanId string = hostingPlan.id

@description('Principal ID of the function app system-assigned managed identity.')
output principalId string = functionApp.identity.principalId
