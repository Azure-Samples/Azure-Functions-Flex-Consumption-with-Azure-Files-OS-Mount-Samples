@description('Storage account name')
param storageAccountName string

@description('Principal ID of the function app managed identity')
param functionAppPrincipalId string

@description('Principal ID of the user (deployer)')
param principalId string

@description('Enable blob storage access')
param enableBlob bool = true

@description('Enable queue storage access')
param enableQueue bool = true

@description('Enable table storage access')
param enableTable bool = true

// Storage account reference
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Built-in Azure RBAC role IDs
var roles = {
  StorageBlobDataOwner: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  StorageBlobDataContributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  StorageQueueDataContributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  StorageTableDataContributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
}

// Function app role assignments
resource functionAppBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableBlob) {
  name: guid(storage.id, functionAppPrincipalId, roles.StorageBlobDataOwner)
  scope: storage
  properties: {
    roleDefinitionId: roles.StorageBlobDataOwner
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableQueue) {
  name: guid(storage.id, functionAppPrincipalId, roles.StorageQueueDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: roles.StorageQueueDataContributor
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableTable) {
  name: guid(storage.id, functionAppPrincipalId, roles.StorageTableDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: roles.StorageTableDataContributor
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// User (deployer) role assignments
resource userBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableBlob && !empty(principalId)) {
  name: guid(storage.id, principalId, roles.StorageBlobDataOwner)
  scope: storage
  properties: {
    roleDefinitionId: roles.StorageBlobDataOwner
    principalId: principalId
    principalType: 'User'
  }
}

resource userQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableQueue && !empty(principalId)) {
  name: guid(storage.id, principalId, roles.StorageQueueDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: roles.StorageQueueDataContributor
    principalId: principalId
    principalType: 'User'
  }
}

resource userTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableTable && !empty(principalId)) {
  name: guid(storage.id, principalId, roles.StorageTableDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: roles.StorageTableDataContributor
    principalId: principalId
    principalType: 'User'
  }
}
