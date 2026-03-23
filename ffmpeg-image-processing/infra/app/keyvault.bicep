@description('Key Vault name')
param name string

@description('Location')
param location string

@description('Tags')
param tags object = {}

@description('Storage account name')
param storageAccountName string

@description('Principal ID of the function app identity (receives Key Vault Secrets User role)')
param functionAppPrincipalId string

@description('Principal ID of the deploying user (receives Key Vault Secrets Officer role)')
param deployerPrincipalId string = ''

// Storage account reference
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Key Vault with RBAC authorization
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// Store storage account key as a secret (Azure Files mounts require shared key)
resource storageKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storageAccountKey'
  properties: {
    value: storage.listKeys().keys[0].value
    contentType: 'Storage account access key for Azure Files SMB mount'
  }
}

// Built-in Key Vault RBAC role IDs
var roles = {
  KeyVaultSecretsOfficer: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  KeyVaultSecretsUser: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
}

// Grant the function app identity read access to secrets
resource functionAppSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionAppPrincipalId, roles.KeyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: roles.KeyVaultSecretsUser
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the deployer manage access to secrets
resource deployerSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, roles.KeyVaultSecretsOfficer)
  scope: keyVault
  properties: {
    roleDefinitionId: roles.KeyVaultSecretsOfficer
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
output storageKeySecretUri string = storageKeySecret.properties.secretUri
