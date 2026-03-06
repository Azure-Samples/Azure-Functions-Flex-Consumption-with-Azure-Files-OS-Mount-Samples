// ---------------------------------------------------------------------------
// Module: monitoring.bicep
// Deploys Application Insights backed by a Log Analytics workspace.
//
// Aligned with Flex Consumption best practices:
//   - Local auth disabled on App Insights (AAD-based auth via connection string).
//   - Function app should set APPLICATIONINSIGHTS_AUTHENTICATION_STRING='Authorization=AAD'.
// ---------------------------------------------------------------------------

@description('Base name used to derive resource names.')
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Disable local (non-AAD) authentication on Application Insights.')
param disableLocalAuth bool = true

@description('Tags to apply.')
param tags object = {}

// ---------------------------------------------------------------------------
// Log Analytics workspace
// ---------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${baseName}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ---------------------------------------------------------------------------
// Application Insights
// ---------------------------------------------------------------------------
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    DisableLocalAuth: disableLocalAuth
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Connection string for Application Insights.')
output connectionString string = appInsights.properties.ConnectionString

@description('Resource ID of the Application Insights instance.')
output appInsightsId string = appInsights.id

@description('Resource ID of the Log Analytics workspace.')
output logAnalyticsId string = logAnalytics.id
