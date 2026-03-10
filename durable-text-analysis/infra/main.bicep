targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@metadata({ azd: { type: 'location' } })
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

// Optional parameters to override the default names
param processorServiceName string = ''
param processorUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''

// Function app configuration
param instanceMemoryMB int = 2048
param maximumInstanceCount int = 100

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(processorServiceName) ? processorServiceName : '${abbrs.webSitesFunctions}processor-${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(resourceToken, 7)}'

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// User assigned managed identity for the function app
module processorIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'processorIdentity'
  scope: rg
  params: {
    name: !empty(processorUserAssignedIdentityName) ? processorUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}processor-${resourceToken}'
    location: location
    tags: tags
  }
}

// Log Analytics workspace for monitoring
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: 'logAnalytics'
  scope: rg
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
  }
}

// Application Insights for application monitoring
module applicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: 'applicationInsights'
  scope: rg
  params: {
    name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
  }
}

// Storage account for function app and Azure Files
module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: union(tags, {
      'Az.Sec.DisableLocalAuth.Storage::Skip': 'AzureFilesMountsRequireSharedKey'
    })
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [
        {
          name: deploymentStorageContainerName
          publicAccess: 'None'
        }
      ]
    }
    fileServices: {
      shares: [
        {
          name: 'data'
          accessTier: 'TransactionOptimized'
          shareQuota: 1024
        }
      ]
    }
  }
}

// App Service Plan (Flex Consumption)
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appServicePlan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
      capacity: 1
    }
    kind: 'Linux'
    reserved: true
  }
}

// Function app with Azure Files mount
module functionApp './app/function.bicep' = {
  name: 'functionApp'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    serviceName: 'processor'
    identityType: 'UserAssigned'
    identityId: processorIdentity.outputs.resourceId
    identityClientId: processorIdentity.outputs.clientId
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.11'
    storageAccountName: storage.outputs.name
    deploymentStorageContainerName: deploymentStorageContainerName
    appInsightsConnectionString: applicationInsights.outputs.connectionString
    instanceMemoryMB: instanceMemoryMB
    maximumInstanceCount: maximumInstanceCount
    appSettings: {
      MOUNT_PATH: '/mounts/data/'
    }
  }
}

// Role assignments for the function app
module functionAppRoleAssignments './app/rbac.bicep' = {
  name: 'functionAppRoleAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    functionAppPrincipalId: processorIdentity.outputs.principalId
    principalId: principalId
    enableBlob: true
    enableQueue: true
    enableTable: true
  }
}

// Azure Files mount configuration
module azureFilesMount './app/mounts.bicep' = {
  name: 'azureFilesMount'
  scope: rg
  params: {
    functionAppName: functionApp.outputs.name
    storageAccountName: storage.outputs.name
    mounts: [
      {
        name: 'data'
        shareName: 'data'
        mountPath: '/mounts/data/'
      }
    ]
  }
  dependsOn: [
    functionAppRoleAssignments
  ]
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

output AZURE_FUNCTION_APP_NAME string = functionApp.outputs.name
output AZURE_FUNCTION_APP_URL string = functionApp.outputs.uri
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_FILE_SHARE_NAME string = 'data'
