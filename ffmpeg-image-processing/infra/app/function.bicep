@description('The name of the function app')
param name string

@description('The location for the function app')
param location string

@description('Tags to apply to the function app')
param tags object = {}

@description('The service name for azd')
param serviceName string

@description('Type of managed identity (SystemAssigned or UserAssigned)')
@allowed(['SystemAssigned', 'UserAssigned'])
param identityType string = 'UserAssigned'

@description('Resource ID of the user-assigned managed identity')
param identityId string = ''

@description('Client ID of the user-assigned managed identity')
param identityClientId string = ''

@description('Resource ID of the App Service Plan')
param appServicePlanId string

@description('Runtime name')
param runtimeName string

@description('Runtime version')
param runtimeVersion string

@description('Storage account name for function app')
param storageAccountName string

@description('Deployment storage container name')
param deploymentStorageContainerName string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Instance memory in MB')
param instanceMemoryMB int = 2048

@description('Maximum instance count')
param maximumInstanceCount int = 100

@description('Additional app settings')
param appSettings object = {}

// Get storage account reference
resource stg 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Build app settings array from object
var baseAppSettings = {
  AzureWebJobsStorage__accountName: storageAccountName
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__clientId: identityType == 'UserAssigned' ? identityClientId : ''
  AzureWebJobsStorage__blobServiceUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
  AzureWebJobsStorage__queueServiceUri: 'https://${storageAccountName}.queue.${environment().suffixes.storage}'
  AzureWebJobsStorage__tableServiceUri: 'https://${storageAccountName}.table.${environment().suffixes.storage}'
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
  AzureFunctionsJobHost__logging__logLevel__default: 'Information'
}

var allAppSettings = union(baseAppSettings, appSettings)

// Convert app settings object to the name/value array format required by siteConfig
var appSettingsArray = [for key in objectKeys(allAppSettings): {
  name: key
  value: allAppSettings[key]
}]

// Deploy function app directly (AVM web/site module doesn't propagate functionAppConfig)
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  tags: union(tags, { 'azd-service-name': serviceName })
  identity: identityType == 'UserAssigned' ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${stg.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: identityType == 'SystemAssigned' ? 'SystemAssignedIdentity' : 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityType == 'UserAssigned' ? identityId : ''
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: { name: runtimeName, version: runtimeVersion }
    }
    siteConfig: {
      appSettings: appSettingsArray
    }
  }
}

output name string = functionApp.name
output uri string = 'https://${functionApp.properties.defaultHostName}'
output principalId string = identityType == 'SystemAssigned' ? (functionApp.identity.principalId ?? '') : ''
