// ---------------------------------------------------------------------------
// Module: function-app.bicep
// Deploys an Azure Functions Flex Consumption plan and function app.
//
// Flex Consumption is the serverless plan that supports OS-level mounts.
// The function app is configured for Python and uses the v2 programming
// model.  The OS mount configuration is handled by the companion
// azure-files-mount.bicep module after deployment.
// ---------------------------------------------------------------------------

@description('Name of the function app resource.')
param functionAppName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Resource ID of the Application Insights instance.')
param appInsightsInstrumentationKey string = ''

@description('Resource ID of the Application Insights connection string.')
param appInsightsConnectionString string = ''

@description('Connection string of the storage account used by the Functions runtime (AzureWebJobsStorage).')
param storageConnectionString string

@description('Additional app settings to merge into the function app configuration.')
param additionalAppSettings object = {}

@description('Tags to apply to all resources.')
param tags object = {}

// ---------------------------------------------------------------------------
// Flex Consumption hosting plan (SKU: FC1)
// ---------------------------------------------------------------------------
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    // FC1 is the Flex Consumption SKU.
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Required for Linux
  }
}

// ---------------------------------------------------------------------------
// Function app
// ---------------------------------------------------------------------------

// Build the base app settings, then merge any extras the caller provides.
var baseAppSettings = {
  AzureWebJobsStorage: storageConnectionString
  FUNCTIONS_WORKER_RUNTIME: 'python'
  FUNCTIONS_EXTENSION_VERSION: '~4'
  APPINSIGHTS_INSTRUMENTATIONKEY: appInsightsInstrumentationKey
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
  // Python v2 programming model — single function_app.py entry point.
  AzureWebJobsFeatureFlags: 'EnableWorkerIndexing'
}

// Union of base + caller-supplied settings.
var mergedAppSettings = union(baseAppSettings, additionalAppSettings)

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [for item in items(mergedAppSettings): {
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
